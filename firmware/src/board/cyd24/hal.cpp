// The CYD's own part of BoardHal: its pins, the
// RGB LED, and the touch map from the XPT2046's raw range.
#include <Arduino.h>

#include "board/board_hal.h"
#include "board/card.h"
#include "board/config.h"
#include "board/touch.h"

namespace board {

namespace {
constexpr uint32_t kLedHz = 5000;
constexpr uint8_t kLedBits = 8;

void ledChannel(int pin, uint8_t level) { ledcWrite(pin, 255 - level); }  // common anode
}  // namespace

void BoardHal::beginBoard() {
  pinMode(pins::kAmpEnable, OUTPUT);
  digitalWrite(pins::kAmpEnable, HIGH);  // amp off by default (active low)
  pinMode(pins::kMainButton, INPUT_PULLUP);
  touchBegin();
  cardBegin();  // the voice file; dbg.ping's `card` says whether it's there
  for (int pin : {pins::kLedRed, pins::kLedGreen, pins::kLedBlue}) {
    ledcAttach(pin, kLedHz, kLedBits);
    ledChannel(pin, 0);
  }
  defaultCal_ = app::defaultTouchCal(kRotation);
}

bool BoardHal::motion(int&, int&, int&) { return false; }  // no motion sensor on this board

void BoardHal::setLed(uint32_t rgb) {
  ledChannel(pins::kLedRed, (rgb >> 16) & 0xFF);
  ledChannel(pins::kLedGreen, (rgb >> 8) & 0xFF);
  ledChannel(pins::kLedBlue, rgb & 0xFF);
}

}  // namespace board
