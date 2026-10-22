#include "app/motion_gesture.h"

#include <cmath>
#include <cstdlib>

#include "render/maths.h"

namespace app {

using render::after;

MotionGesture::Event MotionGesture::update(int ax, int ay, int az, uint32_t t) {
  // In float: the ESP32-S3's FPU has no double.
  const float x = float(ax), y = float(ay), z = float(az);
  const int off = int(std::lroundf(std::sqrt(x * x + y * y + z * z))) - 1000;
  const bool calm = std::abs(off) <= kStillMg;
  if (!started_) started_ = true, calmSince_ = flatSince_ = t;

  // Face down for a while, and back up.
  if (calm && az < -kFlatMg) {
    if (!faceDown_ && !after(flatSince_ + kFaceMs, t)) return faceDown_ = true, kFaceDown;
  } else {
    flatSince_ = t;
    if (faceDown_ && calm && az > kFlatMg) return faceDown_ = false, kFaceUp;
  }

  // Shaken: swings past kShakeMg one way, then the other, close together.
  if (std::abs(off) >= kShakeMg) {
    const int sign = off > 0 ? 1 : -1;
    if (sign != lastSign_) {
      if (!swings_ || after(t, swingsFrom_ + kShakeMs)) swings_ = 0, swingsFrom_ = t;
      ++swings_, lastSign_ = sign;
    }
    if (swings_ >= kShakeSwings && !after(quietUntil_, t)) {
      swings_ = lastSign_ = 0, jolt_ = 0, quietUntil_ = t + kQuietMs;
      return kShake;
    }
  } else if (swings_ && after(t, swingsFrom_ + kShakeMs)) {
    swings_ = lastSign_ = 0;
  }

  if (calm) {
    // A jolt over within kThumpMs, the board still and not held: a thump.
    const bool thump = jolt_ && after(jolt_ + kThumpMs + 1, t) && still_ && !held_ && !after(quietUntil_, t);
    jolt_ = 0, lifting_ = false;
    if (thump) return quietUntil_ = t + kQuietMs, kThump;
    if (!still_ && !after(calmSince_ + kSettleMs, t)) {
      still_ = true;
      if (held_) return held_ = false, kPutdown;
    }
    return kNone;
  }
  calmSince_ = t;
  if (!jolt_ && std::abs(off) >= kThumpMg) jolt_ = t;
  // Off 1 g for longer than a jolt: it's moving.
  const bool moving = !jolt_ || !after(jolt_ + kThumpMs + 1, t);
  // Picked up: off 1 g by kLiftMg for kLiftMs from still, and not a shake.
  if (std::abs(off) >= kLiftMg && still_ && !held_ && !faceDown_ && !swings_) {
    if (!lifting_) lifting_ = true, liftSince_ = t;
    if (!after(liftSince_ + kLiftMs, t)) return held_ = true, still_ = false, jolt_ = 0, kPickup;
  }
  if (moving && !lifting_) still_ = false;
  return kNone;
}

}  // namespace app
