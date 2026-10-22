// Register reads and writes on the AMOLED board's shared I2C bus (board_hal
// starts it), for the touch controller, the codec and the motion sensor.
#pragma once
#include <Wire.h>

#include <cstdint>

namespace board {

// Writes v to the chip's register reg; whether the chip took it.
inline bool i2cWrite(uint8_t addr, uint8_t reg, uint8_t v) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(v);
  return Wire.endTransmission() == 0;
}

// Reads n bytes from register reg on into out; whether all n came.
inline bool i2cRead(uint8_t addr, uint8_t reg, uint8_t* out, uint8_t n) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0 || Wire.requestFrom(addr, n) != n) return false;
  for (uint8_t i = 0; i < n; ++i) out[i] = uint8_t(Wire.read());
  return true;
}

}  // namespace board
