// The CYD's screen: the ST7789 through LovyanGFX on
// SPI, turned by the panel to the canvas's shape (board/config.h).
#include "board/display.h"

#include <Arduino.h>

#define LGFX_USE_V1
#include <LovyanGFX.hpp>
#include <esp_heap_caps.h>

#include "board/config.h"
#include "render/palette.h"

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
      cfg.spi_3wire = false;
      cfg.use_lock = true;
      cfg.dma_channel = SPI_DMA_CH_AUTO;
      cfg.pin_sclk = pins::kLcdSclk;
      cfg.pin_mosi = pins::kLcdMosi;
      cfg.pin_miso = -1;
      cfg.pin_dc = pins::kLcdDc;
      bus_.config(cfg);
      panel_.setBus(&bus_);
    }
    {
      auto cfg = panel_.config();
      cfg.pin_cs = pins::kLcdCs;
      cfg.pin_rst = -1;  // shared with EN; the ST7789 gets a software reset
      cfg.pin_busy = -1;
      // The physical panel. setRotation turns it into the 320×240 canvas.
      cfg.memory_width = kPanelWidth;
      cfg.memory_height = kPanelHeight;
      cfg.panel_width = kPanelWidth;
      cfg.panel_height = kPanelHeight;
      cfg.offset_x = 0;
      cfg.offset_y = 0;
      cfg.offset_rotation = 0;
      cfg.readable = false;
      cfg.invert = kInvert;
      cfg.rgb_order = kBgr;
      cfg.dlen_16bit = false;
      cfg.bus_shared = false;
      panel_.config(cfg);
    }
    {
      auto cfg = light_.config();
      cfg.pin_bl = pins::kBacklight;
      cfg.invert = false;
      cfg.freq = 12000;  // at least 5 kHz, or it flickers
      cfg.pwm_channel = 7;
      light_.config(cfg);
      panel_.setLight(&light_);
    }
    setPanel(&panel_);
  }

 private:
  lgfx::Bus_SPI bus_;
  lgfx::Panel_ST7789 panel_;
  lgfx::Light_PWM light_;
};

// One band's changed columns per DMA batch (render::Changes):
// at most 320 × 6 px, 3.84 KB.
Panel lcd;
uint16_t* band[2] = {nullptr, nullptr};
uint16_t swapped[256];  // palette in the panel's byte order
render::Changes changes;

}  // namespace

bool displayBegin() {
  for (int i = 0; i < 2; ++i) {
    band[i] = static_cast<uint16_t*>(heap_caps_malloc(render::kWidth * render::kBand * 2, MALLOC_CAP_DMA));
    if (!band[i]) return false;
  }
  for (int i = 0; i < 256; ++i) {
    uint16_t c = render::paletteAt(i);
    swapped[i] = uint16_t((c << 8) | (c >> 8));
  }
  if (!lcd.init()) return false;
  lcd.setRotation(kRotation);
  lcd.setBrightness(255);
  return true;
}

void displayPush(const render::Canvas& canvas) {
  int cur = 0;
  lcd.startWrite();
  for (int b = 0; b < render::kHeight / render::kBand; ++b) {
    render::Span s = changes.band(canvas, b);
    if (s.empty()) continue;
    int y0 = b * render::kBand, w = s.x1 - s.x0;
    uint16_t* dst = band[cur];
    for (int y = y0; y < y0 + render::kBand; ++y) {
      const uint8_t* src = canvas.pixels() + y * render::kWidth + s.x0;
      for (int x = 0; x < w; ++x) *dst++ = swapped[src[x]];
    }
    lcd.setAddrWindow(s.x0, y0, w, render::kBand);
    lcd.writePixelsDMA(band[cur], w * render::kBand, false);  // already in panel order
    cur ^= 1;
  }
  lcd.endWrite();
}

void displayBacklight(uint8_t level) { lcd.setBrightness(level); }

void displayFailed() {
  pinMode(pins::kBacklight, OUTPUT);
  digitalWrite(pins::kBacklight, HIGH);
}

// The CYD has no native face: it pushes only the canvas.
bool displayPush(render::SurfacePair&) { return false; }
uint32_t displayPushUs() { return 0; }
bool displayShown(uint32_t&) { return false; }

}  // namespace board
