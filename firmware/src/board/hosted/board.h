// A board hosted in a program on a computer, with no hardware of its own:
// the firmware's device on LinkKit, fed what a host sends on its USB,
// ticked as the firmware's loop ticks it, and its frames read. The
// simulator (simulator/core/) and the Mac's mirror of the board
// (board/mirror/) run it, each behind a Hal of its own, so both run the
// same loop as each other, and the device's code as the boards do.
#pragma once
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "app/device.h"
#include "linkkit/kit.h"
#include "linkkit/line_reader.h"

namespace hosted {

class Board {
 public:
  // A frame as the panel takes it: RGB565, row by row.
  struct Frame {
    const uint16_t* pixels = nullptr;
    uint16_t width = 0, height = 0;
  };

  // `hal` must outlive the board; `usb` is where what it says on USB goes.
  // A live board's clock runs, and its randomness starts from the Hal's
  // boot ID; a frozen one's clock starts at 0 and moves only by dbg.*
  // messages, so every run is the same.
  Board(app::Hal& hal, linkkit::Out& usb, bool frozenClock);

  app::Device& device() { return *device_; }

  // Bytes a host sent on USB. The board handles the lines waiting in
  // order, as the firmware's loop does, and a dbg.* line ends the batch:
  // the lines after it wait for the next tick, since tools order their
  // input and clock steps against ticks. Returns how many lines it handled.
  int usb(const char* bytes, size_t n);
  // One pass of the board's loop, then the next batch of lines waiting.
  // True when it drew a frame.
  bool tick();
  // The frame it last drew.
  Frame frame();

  // A frame's pixels as RGBA, 8 bits each, for a page's canvas.
  static void rgba(const Frame& f, std::vector<uint8_t>& out);

 private:
  std::vector<uint8_t> canvas_;
  std::vector<uint16_t> rgb_;
  std::unique_ptr<app::Device> device_;
  std::unique_ptr<linkkit::Kit> kit_;
  linkkit::LineReader line_;
  // The bytes after a batch's dbg.* line, held for after the next tick;
  // `ticked_` is false from that line until then.
  std::string held_;
  bool ticked_ = true;

  int lines();  // the next batch from held_
};

}  // namespace hosted
