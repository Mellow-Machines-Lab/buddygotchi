// The simulated board: the firmware's hosted board (board/hosted/board.h,
// which the Mac's mirror of the board runs too), with the simulator's
// stand-in for the hardware, and what a front end needs of it. The Mac's
// loops (main.cpp, live.cpp) and the browser's (web.cpp) all drive this,
// so they show the same board.
#pragma once
#include <cstdint>
#include <string>

#include "board/hosted/board.h"
#include "sim_hal.h"

namespace sim {

class Board {
 public:
  // `usb` is where the board's USB lines go. A live board's clock runs,
  // and `bootId` differs each power-on; a frozen one's starts at 0 and
  // moves only by dbg.* lines, with a boot ID of 0, so every run is the same.
  // A native face is the AMOLED board's, so the board is that one.
  Board(linkkit::Out& usb, bool frozenClock, uint32_t bootId = 0) : hal_(bootId), board_(hal_, usb, frozenClock) {
    if (board_.device().surface()) hal_.amoled();
  }

  SimHal& hal() { return hal_; }
  // The board itself: what a host sends on its USB, its loop and its frames.
  hosted::Board& hosted() { return board_; }

  // The card that goes in the slot at `card in`, and now unless `out`.
  void setCard(Card* card, bool out = false);

  // One of the front end's inputs: `touch X Y` (canvas pixels), `release`,
  // `boot 0|1`, `card in|out`.
  void input(const char* line);
  // The parts a front end draws, as JSON, with no `led` on a board that has none:
  // {"led":16711680,"backlight":255,"amp":true,"card":"ok"}
  std::string parts() const;

 private:
  SimHal hal_;
  Card* card_ = nullptr;
  hosted::Board board_;
};

}  // namespace sim
