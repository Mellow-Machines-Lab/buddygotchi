#include "render/gel/gaze.h"

namespace render::gel {

GazePoint Gaze::look(const GazeFacts& f, uint32_t) {
  if (!f.free) return {};
  if (f.needsYou) {
    if (f.lookMs < kNoticeMs) return {true, kMidX, kYouY};
    if (f.mac) return {true, kMidX + f.mac * kMacReach, kEyesY};
    if (f.up) return {true, kMidX, kScreenUpY};
    return {};
  }
  if (f.along) return {true, kMidX, kKeysY};
  if (f.thinking && f.thinkMs < kThinkMs) return {true, kMidX, kYouY};
  if (f.posed || f.with == WithYou::kCall) return {};
  if (f.pointer) {
    if (f.pointerNear) {
      // Right at it, to the Mac's side: where the pointer points from.
      const int side = f.pointerX > 0 ? 1 : f.pointerX < 0 ? -1 : f.mac;
      if (side) return {true, kMidX + side * kMacReach, kEyesY};
      if (f.up) return {true, kMidX, kScreenUpY};
    }
    return {true, kMidX + f.pointerX * kPointerX, kEyesY + f.pointerY * kPointerY};
  }
  if (f.with == WithYou::kReading) return {true, kMidX + f.mac * kPageReach, f.up ? kPageUpY : kPageY};
  if (f.with == WithYou::kVideo) return {true, kMidX + f.mac * kPageReach, f.up ? kYouY : kEyesY};
  return {};
}

}  // namespace render::gel
