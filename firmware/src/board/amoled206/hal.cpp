// The AMOLED board's own part of BoardHal: the shared
// I2C bus, touch and card, the touch map from panel pixels, and no LED.
#include <Arduino.h>
#include <Wire.h>

#include "board/board_hal.h"
#include "board/card.h"
#include "board/config.h"
#include "board/touch.h"

namespace board {

namespace {

// The FT3168 reads in panel pixels; this undoes the picture's scaling and
// turning (board/config.h) to give canvas pixels.
app::TouchCal panelToCanvas() {
  constexpr int32_t k = 65536 * 2 / 3;
  app::TouchCal c;
  if (kTopOnPanelLeft) {
    c.bx = -k, c.cx = (kPicY + kPicH - 1) * k;  // x = (picY + picH - 1 - ry) · 2/3
    c.ay = k, c.cy = -kPicX * k;                // y = (rx - picX) · 2/3
  } else {
    c.bx = k, c.cx = -kPicY * k;
    c.ay = -k, c.cy = (kPicX + kPicW - 1) * k;
  }
  c.valid = true;
  return c;
}

}  // namespace

void BoardHal::beginBoard() {
  pinMode(pins::kMainButton, INPUT_PULLUP);
  Wire.begin(pins::kI2cSda, pins::kI2cScl, 400000);  // touch now, the codec in audioBegin
  touchBegin();
  cardBegin();  // the voice file; dbg.ping's `card` says whether it's there
  defaultCal_ = panelToCanvas();
}

void BoardHal::setLed(uint32_t) {}  // no LED on this board

}  // namespace board
