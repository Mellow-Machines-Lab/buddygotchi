// The simulated board as a process on the Mac, in real time: the board's
// own loop, with USB on a serial port of its own (port.h), which is all
// there is to it from outside. Tests and tools drive it as they drive a
// board.
#pragma once
#include "port.h"

namespace sim {

// Runs until a SIGTERM or SIGINT.
int live(Port& port);

}  // namespace sim
