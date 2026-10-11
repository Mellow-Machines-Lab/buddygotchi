// The simulated board as a process on the Mac: the board's own loop in
// real time, with USB on a serial port and a front end on a socket.
#pragma once
#include "port.h"

namespace sim {

// USB is `port`, a serial port of its own (port.h). `panel` is the
// descriptor to the front end, or -1 for a board with nobody looking at
// it, which tests and tools drive over USB alone. Runs until the front end
// closes its end, or a SIGTERM or SIGINT.
//
// To the front end, each message is a 4-letter tag, its length (32 bits,
// low byte first) and that many bytes:
//   FRM1  a frame: its width and height (16 bits each, low byte first),
//         then its RGB565 pixels, low byte first, row by row
//   AUD1  the next sound: 8-bit unsigned samples at voice::kOutRate
//   STA1  the board's parts, as JSON, whenever one changes (Board::parts)
// From the front end, lines: Board::input's, and `card in`.
int live(Port& port, int panel);

}  // namespace sim
