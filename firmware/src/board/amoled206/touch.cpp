// The FT3168 touch controller on the Waveshare ESP32-S3-Touch-AMOLED-2.06,
// on the shared I2C bus. Its reading is already in
// panel pixels; BoardHal maps it to the canvas (app/touch_cal.h). It's read
// only while its interrupt line says there's a touch: idle, it naps and
// fails to answer, and each failure logs an error onto the USB link.
#include "board/touch.h"

#include <Arduino.h>
#include <Wire.h>

#include "board/amoled206/i2c.h"
#include "board/config.h"

namespace board {

namespace {
constexpr uint8_t kAddr = 0x38;
constexpr uint8_t kRegPoints = 0x02;  // then XH, XL, YH, YL of the first point
// The line falls when the chip has a report and stays low or pulses while
// a finger is down; a last read after it goes quiet sees the release.
constexpr uint32_t kQuietMs = 60;
volatile uint32_t lastEdgeMs = 0;
bool ok = false;
bool down = false;  // the last read saw a finger
// The chip reported a finger lifted after one was down; how many times.
bool lifted = false;
uint32_t lifts = 0;

void IRAM_ATTR edge() { lastEdgeMs = millis(); }
}  // namespace

void touchBegin() {
  pinMode(pins::kTouchIrq, INPUT_PULLUP);
  pinMode(pins::kTouchReset, OUTPUT);
  digitalWrite(pins::kTouchReset, LOW);
  delay(10);
  digitalWrite(pins::kTouchReset, HIGH);
  delay(150);
  Wire.beginTransmission(kAddr);
  ok = Wire.endTransmission() == 0;
  attachInterrupt(pins::kTouchIrq, edge, FALLING);
}

void touchRaw(int& x, int& y, int& z, bool& irq) {
  x = y = z = 0;
  irq = false;
  if (!ok) return;
  bool active = digitalRead(pins::kTouchIrq) == LOW || millis() - lastEdgeMs < kQuietMs;
  if (!active && !down) return;
  const bool was = down;
  down = false;
  uint8_t d[5];
  if (!i2cRead(kAddr, kRegPoints, d, 5)) return;
  // The number of points, and the first's event (XH's top two bits): 0
  // put down, 1 lifted, 2 in contact.
  const int n = d[0] & 0x0F, event = d[1] >> 6;
  if (n == 0 || event == 1) {
    if (was) lifted = true, ++lifts;
    return;
  }
  if (n > 2) return;
  irq = down = true;
  x = (d[1] & 0x0F) << 8 | d[2];
  y = (d[3] & 0x0F) << 8 | d[4];
  z = 1;
}

bool touchLifted() {
  const bool l = lifted;
  lifted = false;
  return l;
}
uint32_t touchLifts() { return lifts; }

}  // namespace board
