#include "board/touch.h"

#include <Arduino.h>

#include <algorithm>
#include <cstring>

#include "board/config.h"

namespace board {

namespace {

// One full-duplex byte, SPI mode 0, most significant bit first. digitalWrite
// and digitalRead keep the clock well under the chip's 2.5 MHz.
uint8_t transfer(uint8_t out) {
  uint8_t in = 0;
  for (int bit = 7; bit >= 0; --bit) {
    digitalWrite(pins::kTouchMosi, (out >> bit) & 1);
    digitalWrite(pins::kTouchSclk, HIGH);
    in = uint8_t(in << 1 | (digitalRead(pins::kTouchMiso) & 1));
    digitalWrite(pins::kTouchSclk, LOW);
  }
  return in;
}

}  // namespace

void touchBegin() {
  pinMode(pins::kTouchCs, OUTPUT);
  digitalWrite(pins::kTouchCs, HIGH);
  pinMode(pins::kTouchSclk, OUTPUT);
  digitalWrite(pins::kTouchSclk, LOW);
  pinMode(pins::kTouchMosi, OUTPUT);
  pinMode(pins::kTouchMiso, INPUT);
  pinMode(pins::kTouchIrq, INPUT);
}

// Seven rounds of Y, Z1, X and Z2, the median of each kept, as LovyanGFX's
// Touch_XPT2046 reads it (the readings the calibration was made with).
void touchRaw(int& x, int& y, int& z, bool& irq) {
  irq = digitalRead(pins::kTouchIrq) == LOW;
  x = y = z = 0;
  if (!irq) return;
  uint8_t d[57] = {0x91, 0, 0xB1, 0, 0xD1, 0, 0xC1, 0};
  for (int j = 1; j < 7; ++j) std::memcpy(&d[j * 8], d, 8);
  d[56] = 0x80;  // and power down
  digitalWrite(pins::kTouchCs, LOW);
  for (uint8_t& b : d) b = transfer(b);
  digitalWrite(pins::kTouchCs, HIGH);
  int xt[7], yt[7], zt[7], ix = 0, iy = 0, iz = 0;
  for (int j = 0; j < 7; ++j) {
    const uint8_t* p = &d[j * 8];
    int rx = (p[5] << 8 | p[6]) >> 3;
    int ry = (p[1] << 8 | p[2]) >> 3;
    int rz = 0x3200 + ry - rx + (((p[3] << 8 | p[4]) - (p[7] << 8 | p[8])) >> 1);
    if (rx > 128 && rx <= 3968) xt[ix++] = rx;
    if (ry > 128 && ry <= 3968) yt[iy++] = ry;
    if (rz > 0) zt[iz++] = rz;
  }
  if (ix < 3 || iy < 3 || iz < 3) return;
  std::sort(xt, xt + ix);
  std::sort(yt, yt + iy);
  std::sort(zt, zt + iz);
  x = xt[ix >> 1], y = yt[iy >> 1], z = zt[iz >> 1] >> 8;
}

bool touchLifted() { return false; }  // the resistive panel can't tell
uint32_t touchLifts() { return 0; }

}  // namespace board
