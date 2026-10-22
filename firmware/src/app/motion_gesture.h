// What a board with a motion sensor felt, from its accelerometer: picked
// up and put down, shaken, a thump on the desk, laid face down and turned
// back up. Pure C++, fed readings in milli-g (z out of the screen, so a
// board lying face up reads about +1000) about every 20 ms. First guesses,
// to tune on the board (`dbg.imu` feeds it in tests and the simulator).
#pragma once
#include <cstdint>

namespace app {

class MotionGesture {
 public:
  enum Event : uint8_t { kNone, kPickup, kPutdown, kShake, kThump, kFaceDown, kFaceUp };
  // Still: within kStillMg of 1 g for kSettleMs.
  static constexpr int kStillMg = 60;
  static constexpr uint32_t kSettleMs = 1000;
  // Picked up: off 1 g by kLiftMg for kLiftMs while it was still.
  static constexpr int kLiftMg = 150;
  static constexpr uint32_t kLiftMs = 150;
  // Shaken: kShakeSwings swings past kShakeMg either way within kShakeMs.
  static constexpr int kShakeMg = 500, kShakeSwings = 3;
  static constexpr uint32_t kShakeMs = 600;
  // A thump: a jolt past kThumpMg, over within kThumpMs, the board still.
  static constexpr int kThumpMg = 350;
  static constexpr uint32_t kThumpMs = 80;
  // Face down: z under -kFlatMg for kFaceMs; face up again over kFlatMg.
  static constexpr int kFlatMg = 800;
  static constexpr uint32_t kFaceMs = 1000;
  // After a shake or a thump, this long before the next.
  static constexpr uint32_t kQuietMs = 1500;

  // One reading; returns what it completes, if anything.
  Event update(int ax, int ay, int az, uint32_t t);
  bool faceDown() const { return faceDown_; }
  bool held() const { return held_; }

 private:
  bool started_ = false, still_ = false, held_ = false, faceDown_ = false;
  // Since when it's been calm (within kStillMg of 1 g), when it began to
  // lift, when it lay flat face down, and the quiet after an event.
  uint32_t calmSince_ = 0, liftSince_ = 0, flatSince_ = 0, quietUntil_ = 0;
  uint32_t jolt_ = 0;  // when a jolt past kThumpMg began, for a thump; 0 for none
  bool lifting_ = false;
  int swings_ = 0, lastSign_ = 0;
  uint32_t swingsFrom_ = 0;
};

}  // namespace app
