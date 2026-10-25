// The screen on the Waveshare ESP32-S3-Touch-AMOLED-2.06:
// the CO5300 through LovyanGFX on quad SPI. The gel draws native pixels,
// turned a quarter as they're sent by a task of its own on core 0 while the
// loop draws the next frame.
#include "board/display.h"

#define LGFX_USE_V1
#include <Arduino.h>
#include <LovyanGFX.hpp>
#include <esp_heap_caps.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/task.h>

#include <algorithm>
#include <atomic>

#include "board/config.h"

namespace board {
namespace {

class Panel : public lgfx::LGFX_Device {
 public:
  Panel() {
    {
      auto cfg = bus_.config();
      cfg.spi_host = SPI2_HOST;
      cfg.spi_mode = 0;
      cfg.freq_write = kSpiWriteHz;
      cfg.freq_read = 16000000;
      cfg.spi_3wire = true;
      cfg.use_lock = true;
      cfg.dma_channel = SPI_DMA_CH_AUTO;
      cfg.pin_sclk = pins::kLcdSclk;
      cfg.pin_mosi = -1;
      cfg.pin_miso = -1;
      cfg.pin_dc = -1;
      cfg.pin_io0 = pins::kLcdIo0;
      cfg.pin_io1 = pins::kLcdIo1;
      cfg.pin_io2 = pins::kLcdIo2;
      cfg.pin_io3 = pins::kLcdIo3;
      bus_.config(cfg);
      panel_.setBus(&bus_);
    }
    {
      auto cfg = panel_.config();
      cfg.pin_cs = pins::kLcdCs;
      cfg.pin_rst = -1;  // reset in displayBegin, held longer than LovyanGFX holds it
      cfg.pin_busy = -1;
      cfg.memory_width = kPanelWidth;
      cfg.memory_height = kPanelHeight;
      cfg.panel_width = kPanelWidth;
      cfg.panel_height = kPanelHeight;
      cfg.offset_x = kPanelOffsetX;
      cfg.offset_y = 0;
      cfg.offset_rotation = 0;
      cfg.readable = false;
      cfg.invert = false;
      cfg.rgb_order = false;
      cfg.dlen_16bit = false;
      cfg.bus_shared = false;
      panel_.config(cfg);
    }
    setPanel(&panel_);
  }

 private:
  lgfx::Bus_SPI bus_;
  lgfx::Panel_CO5300 panel_;
};

// A DMA buffer holds one band of a native frame: 16 rows of the surface,
// turned into 16 panel columns 502 long, 16 KB.
constexpr int kBufPixels = render::PushPlan::kRows * kNativeWidth;

Panel lcd;
uint16_t* buf[2] = {nullptr, nullptr};

// The native frames' sender: a task on core 0 below the
// voice task and Bluetooth's host, so it takes only time they leave. It
// sends `job` while the loop, on core 1, draws the next frame. `idle` is
// there to take while no frame is being sent: the loop takes it to hand
// over the next one, or to use the panel itself.
constexpr UBaseType_t kPushPriority = 1;
constexpr uint32_t kPushStack = 4096;
struct Job {
  const render::Surface* surface = nullptr;
  render::PushPlan plan;
};
Job job;
TaskHandle_t pusher = nullptr;
SemaphoreHandle_t idle = nullptr;
std::atomic<uint32_t> pushUs{0};
// Frames sent, and when the last two finished (millis, by frame number),
// for displayShown. The loop hands a frame over only once the one before
// has gone, so at most two are sent between two of its passes.
std::atomic<uint32_t> sentFrames{0};
std::atomic<uint32_t> sentAt[2];
uint32_t shownFrames = 0;  // the loop's: frames displayShown has reported

// The plan's bands, each turned into a DMA buffer while the other one sends.
void send(const Job& j) {
  int cur = 0;
  lcd.startWrite();
  for (int b = 0; b < j.plan.bands; ++b) {
    if (j.plan.spans[b].empty()) continue;
    const render::PanelWindow w = render::packBand(*j.surface, b, j.plan.spans[b], kTopOnPanelLeft, buf[cur]);
    lcd.setAddrWindow(w.x, w.y, w.w, w.h);
    lcd.writePixelsDMA(buf[cur], w.w * w.h, false);  // already in panel order
    cur ^= 1;
  }
  lcd.endWrite();  // waits for the last batch
}

void pushTask(void*) {
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    const uint32_t start = micros();
    send(job);
    pushUs.store(micros() - start);
    const uint32_t frame = sentFrames.load();
    sentAt[frame % 2].store(millis());
    sentFrames.store(frame + 1);
    xSemaphoreGive(idle);
  }
}

// The panel to itself, once no frame is being sent: the brightness waits
// for the native frame in flight, at most one push.
struct PanelHeld {
  PanelHeld() {
    if (idle) xSemaphoreTake(idle, portMAX_DELAY);
  }
  ~PanelHeld() {
    if (idle) xSemaphoreGive(idle);
  }
};

// The CO5300's hardware reset, timed as Waveshare's own driver times it
// (Arduino_GFX's CO5300, 200 ms each way). LovyanGFX's 8 ms low and 64 ms
// after were enough from power-up but, after a restart over USB with the
// panel still powered, left it stuck on a white screen until the board
// was unplugged.
constexpr uint32_t kResetMs = 200;

void resetPanel() {
  pinMode(pins::kLcdReset, OUTPUT);
  digitalWrite(pins::kLcdReset, HIGH);
  delay(10);
  digitalWrite(pins::kLcdReset, LOW);
  delay(kResetMs);
  digitalWrite(pins::kLcdReset, HIGH);
  delay(kResetMs);
}

}  // namespace

bool displayBegin() {
  for (int i = 0; i < 2; ++i) {
    buf[i] = static_cast<uint16_t*>(heap_caps_malloc(kBufPixels * 2, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL));
    if (!buf[i]) return false;
  }
  resetPanel();
  if (!lcd.init()) return false;
  lcd.setRotation(0);
  lcd.fillScreen(0);
  lcd.setBrightness(255);
  idle = xSemaphoreCreateBinary();
  if (!idle) return false;
  xSemaphoreGive(idle);
  return xTaskCreatePinnedToCore(pushTask, "push", kPushStack, nullptr, kPushPriority, &pusher, 0) == pdPASS;
}

// The gel, the only face this board draws, draws natively: frames go by
// the other push, the test pattern included (render::blit).
void displayPush(const render::Canvas&) {}

bool displayPush(render::SurfacePair& frames) {
  if (!frames.ready() || frames.front().width != kNativeWidth || frames.front().height != kNativeHeight) return false;
  xSemaphoreTake(idle, portMAX_DELAY);  // the frame before has gone: its surface is the next back()
  job.plan = frames.present();
  job.surface = &frames.front();
  xTaskNotifyGive(pusher);
  return true;
}

uint32_t displayPushUs() { return pushUs.load(); }

bool displayShown(uint32_t& atMs) {
  if (sentFrames.load() == shownFrames) return false;
  atMs = sentAt[shownFrames++ % 2].load();
  return true;
}

void displayBacklight(uint8_t level) {
  PanelHeld held;
  lcd.setBrightness(level);
}

void displayFailed() {}  // an AMOLED has no backlight to leave on

}  // namespace board
