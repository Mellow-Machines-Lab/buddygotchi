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

// What a board says on USB, kept until a page takes it.
class Said : public linkkit::Out {
 public:
  void write(const char* s, size_t n) override { text_.append(s, n); }
  // What it said since the last take, or null for nothing. The text
  // stays until the next take.
  const char* take();
  void clear() { text_.clear(); }

 private:
  std::string text_, taken_;
};

class Board {
 public:
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

  // A frame as a page's canvas takes it: RGBA, 8 bits each, row by row.
  struct Picture {
    const uint8_t* rgba = nullptr;
    int width = 0, height = 0;
  };
  // One pass of the loop (tick) for a page that shows the board: when it
  // drew, its frame is picture(), on the page's panel as soon as it's
  // taken (dbg.latency), and its time to draw is dbg.ping's fps and
  // draw_us. True when it drew. The picture stays until the next frame.
  bool tickRgba();
  const Picture& picture() const { return picture_; }

 private:
  app::Hal& hal_;
  std::vector<uint8_t> canvas_, rgba_;
  std::unique_ptr<app::Device> device_;
  std::unique_ptr<linkkit::Kit> kit_;
  linkkit::LineReader line_;
  Picture picture_;
  // The bytes after a batch's dbg.* line, held for after the next tick;
  // `ticked_` is false from that line until then.
  std::string held_;
  bool ticked_ = true;

  int lines();  // the next batch from held_
};

}  // namespace hosted
