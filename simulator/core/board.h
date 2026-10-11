// The simulated board: the firmware's device on LinkKit, and what a front
// end needs of it. The Mac's loops (main.cpp, live.cpp) and the browser's
// (web.cpp) all drive this, so they show the same board.
#pragma once
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "app/device.h"
#include "linkkit/kit.h"
#include "linkkit/line_reader.h"
#include "sim_hal.h"

namespace sim {

class Board {
 public:
  // A frame as the panel takes it: RGB565, row by row.
  struct Frame {
    const uint16_t* pixels = nullptr;
    uint16_t width = 0, height = 0;
  };

  // `usb` is where the board's USB lines go. A live board's clock runs,
  // and `bootId` differs each power-on; a frozen one's starts at 0 and
  // moves only by dbg.* lines, with a boot ID of 0, so every run is the same.
  Board(linkkit::Out& usb, bool frozenClock, uint32_t bootId = 0);

  SimHal& hal() { return hal_; }
  app::Device& device() { return *device_; }

  // The card that goes in the slot at `card in`, and now unless `out`.
  void setCard(Card* card, bool out = false);

  // Bytes a host sent on USB. Returns how many lines they finished.
  int usb(const char* bytes, size_t n);
  // One pass of the board's loop. True when it drew a frame.
  bool tick();
  // The frame it last drew.
  Frame frame();

  // One of the front end's inputs: `touch X Y` (canvas pixels), `release`,
  // `boot 0|1`, `card in|out`.
  void input(const char* line);
  // The parts a front end draws, as JSON:
  // {"led":16711680,"backlight":255,"amp":true,"card":"ok"}
  std::string parts() const;

 private:
  SimHal hal_;
  Card* card_ = nullptr;
  std::vector<uint8_t> canvas_;
  std::vector<uint16_t> rgb_;
  std::unique_ptr<app::Device> device_;
  std::unique_ptr<linkkit::Kit> kit_;
  linkkit::LineReader line_;
};

}  // namespace sim
