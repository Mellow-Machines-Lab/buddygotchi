// A second core to draw on. A face may hand part of a frame to it: start
// runs `job(arg)` there and returns at once, and join waits for it to
// finish. It must draw pixels no one else touches meanwhile. Boards with
// one core to draw on (the CYD, the simulator, the Mac's mirror) leave it
// unset, and the face draws it all itself, the same pixels.
#pragma once
#include <cstdint>

namespace render {

struct Helper {
  void (*start)(void (*job)(void*), void* arg) = nullptr;
  void (*join)() = nullptr;
  uint32_t (*micros)() = nullptr;  // a clock, to share the work out evenly
  explicit operator bool() const { return start && join && micros; }
};
inline Helper helper;

}  // namespace render
