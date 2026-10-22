// What a touch on the screen was, from its path: a tap, a stroke (one the
// wrong way, upward, ruffles), a tickle (a finger wiggling in one spot) or
// a boop on the nose (a tap on the face's middle). Pure C++, fed the
// touch's canvas positions as they come; the canvas is 320 × 240 on both
// boards (the AMOLED's panel is mapped onto it).
#pragma once
#include <cstdint>

#include "render/types.h"

namespace app {

class TouchGesture {
 public:
  // A stroke travels this far from where it began; one that goes up more
  // than sideways is a ruffle.
  static constexpr int kStrokePx = 40;
  // A tickle wiggles this far in all, inside a spot this wide.
  static constexpr int kTicklePathPx = 90, kTickleSpotPx = 36;
  // The face's nose, where a tap is a boop: a small spot under the eyes,
  // so a poke anywhere else stays a poke.
  static constexpr int kNoseX = 160, kNoseY = 134, kNoseHalf = 14;

  void down(int x, int y);
  void move(int x, int y);
  // What it was, on release: false for a tap, else true with the board's
  // own reaction to it in g.
  bool up(render::Gesture& g) const;

 private:
  int x0_ = 0, y0_ = 0, x_ = 0, y_ = 0, minX_ = 0, maxX_ = 0, minY_ = 0, maxY_ = 0;
  int path_ = 0;
};

}  // namespace app
