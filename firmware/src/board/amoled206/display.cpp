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

// A DMA buffer holds one band of a native frame: 16 columns of the
// surface, turned into 16 panel rows 410 long, 13 KB.
constexpr int kBufPixels = render::PushPlan::kColumns * kNativeHeight;

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

// The panel's refresh: TE (pins::kLcdTe) rises as each scan of its rows
// begins, 60 times a second. A frame sent in the scan's order, its bands
// along the scan lines, starting as a scan begins, stays behind that scan
// (it's faster than the writer) and ahead of the next (the writer takes
// under two scans for a whole frame), so no refresh shows two frames: no
// tear. Which way the panel scans its rows is the mode, `down` from its
// first row (the surface's last column with the top on the left), or `up`;
// `off` sends whenever a frame is ready, as before. A tear is counted when
// the scan, as timed from TE, passes through a band while it's sent.
std::atomic<int> scanMode{kScanDown};
SemaphoreHandle_t refresh = nullptr;
volatile uint32_t refreshAt = 0, refreshUs = 16667;  // the last TE, and its period
std::atomic<uint32_t> scanPushes{0}, scanTears{0};

void IRAM_ATTR refreshEdge() {
  const uint32_t now = micros();
  const uint32_t period = now - refreshAt;
  if (period > 10000 && period < 30000) refreshUs = period;
  refreshAt = now;
  BaseType_t woken = pdFALSE;
  xSemaphoreGiveFromISR(refresh, &woken);
  if (woken) portYIELD_FROM_ISR();
}

// Where the scan is at `us`, in panel rows from the start of the scan that
// began at `from`, counting on past the panel into the next scans.
uint32_t scanRow(uint32_t from, uint32_t us) { return uint32_t(uint64_t(us - from) * kPanelHeight / refreshUs); }

// The plan's bands, each turned into a DMA buffer while the other one sends,
// in the scan's order once a scan begins.
void send(const Job& j) {
  const int mode = scanMode.load();
  uint32_t from = refreshAt;  // off: tears still counted, from the scan under way
  if (mode != kScanOff && refresh) {
    xSemaphoreTake(refresh, 0);  // an edge from before this frame
    xSemaphoreTake(refresh, pdMS_TO_TICKS(25));
    from = refreshAt;
  }
  // With the top on the panel's left its first row is the last band's.
  const bool lastFirst = (mode == kScanUp) != kTopOnPanelLeft;
  int cur = 0;
  bool torn = false;
  lcd.startWrite();
  for (int k = 0; k < j.plan.bands; ++k) {
    const int b = lastFirst ? j.plan.bands - 1 - k : k;
    for (int r = 0; r < j.plan.runCount[b]; ++r) {
      const render::PanelWindow w = render::packBand(*j.surface, b, j.plan.runs[b][r], kTopOnPanelLeft, buf[cur]);
      const uint32_t start = micros();
      lcd.setAddrWindow(w.x, w.y, w.w, w.h);
      lcd.writePixelsDMA(buf[cur], w.w * w.h, false);  // already in panel order
      if (from) {
        // The scan's rows from this band's start to about when it's sent, at
        // the panel's rate of 40 MHz on four lines; its rows, as the scan
        // meets them in its own direction.
        const uint32_t end = start + uint32_t(w.w * w.h) / 10;
        const int r0 = mode == kScanUp ? kPanelHeight - (w.y + w.h) : w.y;
        const uint32_t a = scanRow(from, start), z = scanRow(from, end);
        for (uint32_t base = a / kPanelHeight * kPanelHeight; base <= z && !torn; base += kPanelHeight)
          torn = a < base + r0 + w.h && z >= base + r0;
      }
      cur ^= 1;
    }
  }
  lcd.endWrite();  // waits for the last batch
  if (from) {
    scanPushes.fetch_add(1);
    if (torn) scanTears.fetch_add(1);
  }
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
  refresh = xSemaphoreCreateBinary();  // LovyanGFX's init turns the panel's TE on
  if (refresh) {
    pinMode(pins::kLcdTe, INPUT);
    attachInterrupt(pins::kLcdTe, refreshEdge, RISING);
  }
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

void displayScanMode(int mode) {
  scanMode.store(mode);
  scanPushes.store(0), scanTears.store(0);
}

int displayScanMode() { return scanMode.load(); }

void displayScanStats(uint32_t& hz, uint32_t& pushes, uint32_t& tears) {
  hz = refreshAt && micros() - refreshAt < 100000 ? 1000000 / refreshUs : 0;
  pushes = scanPushes.load(), tears = scanTears.load();
}

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
