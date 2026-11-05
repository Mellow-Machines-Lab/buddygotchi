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
  // Still: within kStillMg of 1 g for kSettleMs, its tilt steady: no axis,
  // smoothed over a few readings so a desk's typing doesn't count, moving
  // over kSteadyMg (about 2°). A hand held still turns the board a little
  // more than that, so carrying it is no put-down; it needn't lie flat, as
  // it may stand on a desk.
  static constexpr int kStillMg = 60, kSteadyMg = 40;
  static constexpr uint32_t kSettleMs = 1500;
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
  // A finger on the screen or BOOT jolts the board too: no thump while one
  // is down (hands), or for kHandsMs after.
  static constexpr uint32_t kHandsMs = 150;

  // One reading; returns what it completes, if anything.
  Event update(int ax, int ay, int az, uint32_t t);
  // A finger is on the screen, or BOOT is down, at t.
  void hands(uint32_t t) { handled_ = true, handsAt_ = t; }
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
  bool handled_ = false;
  uint32_t handsAt_ = 0;
  // The tilt, smoothed, and where it was as the board last became calm.
  int fx_ = 0, fy_ = 0, fz_ = 0, calmX_ = 0, calmY_ = 0, calmZ_ = 0;
  void calmFrom(uint32_t t) { calmSince_ = t, calmX_ = fx_, calmY_ = fy_, calmZ_ = fz_; }
};

// How far the board is tilted now against how it's been resting, across the
// screen, for a face to slosh by. Pure C++, fed the same readings; it only
// reads them, so it can't touch what MotionGesture makes of them. Where it
// rests follows the reading over kRestMs, so a board set down at an angle
// settles back to none in about 3 kRestMs, and it counts only gravity: moving
// (off 1 g by over kCalmMg, a shake, a jolt) or face down it says none, and
// face down it rests where it lies. Under kDeadMg (about 2 degrees) is none:
// a desk's typing, a hand's tremble.
class Tilt {
 public:
  static constexpr int kCalmMg = 150, kDeadMg = 35, kMostMg = 500, kFaceDownMg = -MotionGesture::kFlatMg;
  static constexpr uint32_t kRestMs = 6000;
  // Which way the sensor's x runs across the screen: with the board's right
  // side down, gravity's share of a sensor x pointing right reads negative.
  // x's direction on the AMOLED is a first guess (board/amoled206/imu.cpp).
  static constexpr int kAcross = -1;

  void update(int ax, int ay, int az, uint32_t t);
  // Milli-g across the screen, right side down positive, at most kMostMg.
  int mg() const { return mg_; }

 private:
  bool started_ = false;
  uint32_t at_ = 0;
  int x_ = 0;      // the reading, smoothed, in 1/256 mg
  int rest_ = 0;   // where it rests, in 1/256 mg
  int mg_ = 0;
};

}  // namespace app
