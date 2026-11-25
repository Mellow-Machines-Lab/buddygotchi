// The board being built for: its pins (namespace pins) and screen settings
// (namespace board). Its code is in its own folder, and its env in
// firmware/platformio.ini builds only that folder.
#pragma once

#if defined(BOOP_BOARD_AMOLED206)
#include "board/amoled206/config.h"
#else
#error "no board: build with env amoled206 (firmware/platformio.ini)"
#endif
