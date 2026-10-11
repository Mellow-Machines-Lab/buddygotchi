// The simulated board, live: the firmware's device on LinkKit with a real
// clock, and what a front end needs of it. The native loop (live.cpp) and
// the browser's (web.cpp) both drive this, so they show the same board.
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

  // `usb` is where the board's USB lines go; `bootId` differs each power-on.
  Board(linkkit::Out& usb, uint32_t bootId);

  SimHal& hal() { return hal_; }
  app::Device& device() { return *device_; }

  // Bytes a host sent on USB.
  void usb(const char* bytes, size_t n);
  // One pass of the board's loop. True when it drew a frame, which
  // frame() then is until the next pass; `convert` false skips making the
  // canvas's pixels when nobody will look.
  bool tick(bool convert = true);
  Frame frame() const { return frame_; }
  // The frame reached its screen, after this long drawing and sending it.
  void shown(uint32_t drawUs, uint32_t pushUs);

  // One of the front end's inputs: `touch X Y` (canvas pixels), `release`,
  // `boot 0|1`, `card out`. False for a line it doesn't know (`card in`
  // is the front end's own: it has the card).
  bool input(const char* line);
  // The parts a front end draws, as JSON:
  // {"led":16711680,"backlight":255,"amp":true,"card":"ok"}
  std::string parts() const;

 private:
  SimHal hal_;
  std::vector<uint8_t> canvas_;
  std::vector<uint16_t> rgb_;
  std::unique_ptr<app::Device> device_;
  std::unique_ptr<linkkit::Kit> kit_;
  linkkit::LineReader line_;
  Frame frame_;
};

}  // namespace sim
