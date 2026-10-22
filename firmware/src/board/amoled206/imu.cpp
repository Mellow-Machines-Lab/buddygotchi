// The AMOLED board's motion sensor, a QMI8658 on the shared I2C bus: its
// accelerometer at +/-4 g, read when the app asks (every 20 ms), in milli-g.
// What it feels is the app's (app/motion_gesture.h). Its axes on this
// board, held sideways with USB-C on the left, are first guesses: z is out
// of the screen when kFlipZ says so, to check on the board (`boopctl imu`).
#include <Arduino.h>
#include <Wire.h>

#include "board/board_hal.h"

namespace board {

namespace {
constexpr uint8_t kAddrs[] = {0x6B, 0x6A};  // SA0 high, then low
constexpr uint8_t kWhoAmI = 0x00, kWho = 0x05;
constexpr uint8_t kCtrl1 = 0x02, kCtrl2 = 0x03, kCtrl7 = 0x08, kAxL = 0x35;
constexpr int kLsbPerG = 8192;  // at +/-4 g
constexpr bool kFlipZ = false;
uint8_t addr = 0;
bool tried = false;

bool writeReg(uint8_t reg, uint8_t v) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(v);
  return Wire.endTransmission() == 0;
}

bool readRegs(uint8_t reg, uint8_t* out, int n) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(int(addr), n) != n) return false;
  for (int i = 0; i < n; ++i) out[i] = uint8_t(Wire.read());
  return true;
}

// Finds the sensor once: its address, then auto-increment, +/-4 g at about
// 125 Hz, and the accelerometer on.
bool start() {
  tried = true;
  for (uint8_t a : kAddrs) {
    addr = a;
    uint8_t who = 0;
    if (readRegs(kWhoAmI, &who, 1) && who == kWho) {
      return writeReg(kCtrl1, 0x40) && writeReg(kCtrl2, 0x16) && writeReg(kCtrl7, 0x01);
    }
  }
  addr = 0;
  return false;
}
}  // namespace

bool BoardHal::motion(int& ax, int& ay, int& az) {
  if (!tried) start();
  if (!addr) return false;
  uint8_t b[6];
  if (!readRegs(kAxL, b, 6)) return false;
  auto mg = [&](int i) { return int(int16_t(uint16_t(b[i]) | uint16_t(b[i + 1]) << 8)) * 1000 / kLsbPerG; };
  ax = mg(0), ay = mg(2), az = kFlipZ ? -mg(4) : mg(4);
  return true;
}

}  // namespace board
