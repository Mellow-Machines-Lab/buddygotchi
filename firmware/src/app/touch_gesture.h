// What a touch on the screen was, from its path: a tap, a swipe (a quick
// one that travels), a stroke (a slow one; one the wrong way, upward,
// ruffles), a tickle (a finger wiggling in one spot), a boop on the nose (a
// tap on the face's middle), or a hold (a finger kept still). Pure C++, fed
// the touch's canvas positions as they come; the canvas is 320 × 240 on
// both boards (the AMOLED's panel is mapped onto it).
#pragma once
#include <cstdint>

#include "render/types.h"

namespace app {

class TouchGesture {
 public:
  // A stroke or a swipe travels this far from where it began; a stroke
  // that goes up more than sideways is a ruffle.
  static constexpr int kStrokePx = 40;
  // A touch that travels faster than this on average, from going down to
  // its last reading, is a swipe: the face only feels it go by. A slower one
  // is a deliberate stroke, which the board reacts to.
  static constexpr int kSwipePxPerS = 600;
  // A tickle wiggles this far in all, inside a spot this wide.
  static constexpr int kTicklePathPx = 90, kTickleSpotPx = 36;
  // The face's nose, where a tap is a boop: a small spot under the eyes,
  // so a poke anywhere else stays a poke.
  static constexpr int kNoseX = 160, kNoseY = 134, kNoseHalf = 14;
  // A hold is a finger kept down kHoldMs inside a spot kHoldSpotPx wide
  // each way: steadier than a tickle's spot, and short of a stroke.
  static constexpr uint32_t kHoldMs = 1000;
  static constexpr int kHoldSpotPx = 24;
  // The finger's velocity as it lets go is over its last readings this
  // long (at least the last two).
  static constexpr uint32_t kFlingMs = 80;

  // What a touch was, on release.
  enum Kind : uint8_t { kTap, kSwipe, kGesture };

  // Where it went down and where it was last, and how long that took.
  struct Path {
    int x0 = 0, y0 = 0, x = 0, y = 0;
    uint32_t ms = 0;
  };

  void down(int x, int y, uint32_t t);
  void move(int x, int y, uint32_t t);
  // Whether the touch, still down at t, is a hold: kHoldMs since it went
  // down and never outside its spot.
  bool held(uint32_t t) const;
  // What it was, on release: a gesture names the board's own reaction to it
  // in g.
  Kind up(render::Gesture& g) const;
  // How fast the finger moved over its last kFlingMs, in px a second; none
  // for a finger that was still.
  void velocity(int& vx, int& vy) const;
  Path path() const { return {x0_, y0_, x_, y_, t_ - t0_}; }

 private:
  static constexpr int kSamples = 8;  // the latest readings, for the velocity
  struct Sample {
    int x, y;
    uint32_t t;
  };
  int x0_ = 0, y0_ = 0, x_ = 0, y_ = 0, minX_ = 0, maxX_ = 0, minY_ = 0, maxY_ = 0;
  int path_ = 0;
  uint32_t t0_ = 0, t_ = 0;
  Sample samples_[kSamples] = {};
  int count_ = 0;  // readings so far; the newest is at (count_ - 1) % kSamples
  void sample(int x, int y, uint32_t t);
};

}  // namespace app
