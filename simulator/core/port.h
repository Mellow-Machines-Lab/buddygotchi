// The simulated board's USB: a pseudo serial port, which bridges and tools
// open as they open a board's /dev/cu.usbserial-*. The board is the far
// end of the cable, and nothing about the lines differs.
#pragma once
#include <cstddef>
#include <cstdint>
#include <string>

#include "linkkit/kit.h"

namespace sim {

class Port : public linkkit::Out {
 public:
  // With nobody reading, what the board said this long ago is thrown away,
  // as a cable with nothing on its other end holds nothing: a tool that
  // opens the port later hears only what's said from then on.
  static constexpr uint32_t kStaleMs = 500;
  // A reader that takes nothing for this long while the board has more to
  // say has stopped listening, and the rest is dropped.
  static constexpr int kDeafMs = 250;

  ~Port() override;
  // Makes the port; `link`, if not empty, is a path that will lead to it
  // (a symbolic link, replaced if it's there). False with why in error().
  bool open(const std::string& link);
  const std::string& path() const { return path_; }  // /dev/ttysNNN
  const std::string& error() const { return error_; }
  int fd() const { return master_; }  // readable when a host has sent something

  // What a host sent, up to `n` bytes; 0 when there's nothing.
  size_t read(char* buf, size_t n);
  // The board's lines to whoever is reading.
  void write(const char* s, size_t n) override;
  // Once a pass of the loop, at real time `ms`.
  void tick(uint32_t ms);

 private:
  int waiting() const;  // bytes the board has said that nobody has read yet
  void forget();        // throws them away

  int master_ = -1;
  int slave_ = -1;  // held open, so the port outlives each tool that opens it
  std::string path_, link_, error_;
  bool listening_ = false;
  int lastWaiting_ = 0;
  uint32_t changedAt_ = 0;
};

}  // namespace sim
