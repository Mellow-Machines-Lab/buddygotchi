// The touch controller: the CYD's XPT2046 on
// bit-banged SPI (cyd24/touch.cpp), or the AMOLED board's FT3168 on I2C
// (amoled206/touch.cpp).
#pragma once
#include <cstdint>

namespace board {

void touchBegin();
// The controller's raw reading (no mapping) and whether it reports a touch;
// z is 0 with no press. BoardHal maps it to screen pixels (app/touch_cal.h).
void touchRaw(int& x, int& y, int& z, bool& irq);
// True once after the controller itself reported the finger lifted (the
// AMOLED's FT3168: no point, or the point's lift-up event), so the touch
// can end at once instead of waiting out the readings it might have
// missed; never on the CYD, whose panel says nothing of a lift. How many
// such lifts it has reported, for dbg.state.
bool touchLifted();
uint32_t touchLifts();

}  // namespace board
