// Boop's BOOT button: a tap, and a hold for push-to-talk; a touch's path:
// a tap, a swipe, a stroke, a ruffle, a tickle, a boop on the nose, a hold,
// and the finger's speed as it lets go; and the motion
// sensor's readings: picked up, put down, shaken, a thump, face down and up.
#include <unity.h>

#include "app/gesture.h"
#include "app/motion_gesture.h"
#include "app/touch_gesture.h"

#include <algorithm>
#include <initializer_list>
#include <utility>
#include <vector>

using app::ButtonGesture;
using app::MotionGesture;
using app::TouchGesture;

void setUp() {}
void tearDown() {}

static void test_short_press_is_a_tap() {
  ButtonGesture g;
  TEST_ASSERT_EQUAL(ButtonGesture::kDown, g.update(true, 1000));
  TEST_ASSERT_EQUAL(ButtonGesture::kNone, g.update(true, 1399));
  TEST_ASSERT_EQUAL(ButtonGesture::kTap, g.update(false, 1399));
}

// Held 400 ms or more, a press is push-to-talk from then
// until the release, and the release is no tap.
static void test_hold_is_push_to_talk() {
  TEST_ASSERT_EQUAL_UINT32(400, ButtonGesture::kHoldMs);
  ButtonGesture g;
  g.update(true, 0);
  TEST_ASSERT_EQUAL(ButtonGesture::kNone, g.update(true, 399));
  TEST_ASSERT_EQUAL(ButtonGesture::kHoldStart, g.update(true, 400));
  TEST_ASSERT_TRUE(g.holding());
  TEST_ASSERT_EQUAL(ButtonGesture::kNone, g.update(true, 5000));
  TEST_ASSERT_EQUAL(ButtonGesture::kHoldEnd, g.update(false, 5000));
  TEST_ASSERT_FALSE(g.down());
  TEST_ASSERT_FALSE(g.holding());
  // The next press starts afresh: a tap.
  TEST_ASSERT_EQUAL(ButtonGesture::kDown, g.update(true, 6000));
  TEST_ASSERT_EQUAL(ButtonGesture::kTap, g.update(false, 6100));
}

// Talking stops by itself 30 s after it started, however long
// BOOT stays down, and the release after that sends nothing.
static void test_talk_is_capped_at_30_s() {
  TEST_ASSERT_EQUAL_UINT32(30000, ButtonGesture::kTalkCapMs);
  ButtonGesture g;
  g.update(true, 1000);
  TEST_ASSERT_EQUAL(ButtonGesture::kHoldStart, g.update(true, 1400));
  TEST_ASSERT_EQUAL(ButtonGesture::kNone, g.update(true, 1400 + 29999));
  TEST_ASSERT_EQUAL(ButtonGesture::kHoldEnd, g.update(true, 1400 + 30000));
  TEST_ASSERT_TRUE(g.down());
  TEST_ASSERT_FALSE(g.holding());
  TEST_ASSERT_EQUAL(ButtonGesture::kNone, g.update(true, 90000));
  TEST_ASSERT_EQUAL(ButtonGesture::kNone, g.update(false, 90000));
  TEST_ASSERT_EQUAL(ButtonGesture::kDown, g.update(true, 91000));
  TEST_ASSERT_EQUAL(ButtonGesture::kTap, g.update(false, 91100));
}

static void test_bounces_are_ignored() {
  ButtonGesture g;
  g.update(true, 0);
  TEST_ASSERT_EQUAL(ButtonGesture::kNone, g.update(false, 5));  // bounce
  TEST_ASSERT_TRUE(g.down());
  TEST_ASSERT_EQUAL(ButtonGesture::kTap, g.update(false, 60));
}

// Pins TouchGesture's distances: 40 px of travel is a stroke, upward
// more than sideways a ruffle; 90 px of wiggling inside a 36 px spot a
// tickle; a tap within 14 px of the nose, under the eyes, a boop on it.
// What a touch along `points` was, a reading every `stepMs`: its gesture,
// kTouchSwipe for a swipe, or kTouchTap for a tap.
constexpr int kTouchTap = -1, kTouchSwipe = -2;
static int path(std::initializer_list<std::pair<int, int>> points, uint32_t stepMs = 200) {
  TouchGesture g;
  auto p = points.begin();
  uint32_t t = 1000;
  g.down(p->first, p->second, t);
  for (++p; p != points.end(); ++p) g.move(p->first, p->second, t += stepMs);
  render::Gesture what;
  switch (g.up(what)) {
    case TouchGesture::kGesture: return int(what);
    case TouchGesture::kSwipe: return kTouchSwipe;
    default: return kTouchTap;
  }
}
static void test_a_touchs_path() {
  using render::Gesture;
  TEST_ASSERT_EQUAL(kTouchTap, path({{40, 40}}));
  TEST_ASSERT_EQUAL(kTouchTap, path({{40, 40}, {60, 40}}));                 // short of a stroke
  TEST_ASSERT_EQUAL(int(Gesture::kStroke), path({{60, 120}, {100, 120}}));  // 40 px across
  TEST_ASSERT_EQUAL(int(Gesture::kStroke), path({{160, 60}, {160, 150}}));  // down
  TEST_ASSERT_EQUAL(int(Gesture::kRuffle), path({{160, 150}, {150, 90}}));  // up
  TEST_ASSERT_EQUAL(int(Gesture::kTickle),
                    path({{100, 100}, {120, 100}, {100, 100}, {120, 100}, {100, 100}, {120, 100}}));
  TEST_ASSERT_EQUAL(int(Gesture::kTickle),  // however quick the wiggle
                    path({{100, 100}, {120, 100}, {100, 100}, {120, 100}, {100, 100}, {120, 100}}, 20));
  TEST_ASSERT_EQUAL(int(Gesture::kNose), path({{160, 134}}));
  TEST_ASSERT_EQUAL(int(Gesture::kNose), path({{174, 148}}));
  TEST_ASSERT_EQUAL(kTouchTap, path({{175, 134}}));
  TEST_ASSERT_EQUAL(kTouchTap, path({{160, 100}}));  // the face, but not its nose
}

// Pins the swipe: a touch that travels a stroke's 40 px and lets go faster
// than 600 px a second (its velocity, which the face carries on) is a swipe,
// whichever way it goes, and names the stroke (or the ruffle) it would be;
// as slow or slower it's that stroke, the board's deliberate one.
static void test_a_quick_stroke_is_a_swipe() {
  using render::Gesture;
  TEST_ASSERT_EQUAL_INT(600, TouchGesture::kSwipePxPerS);
  TEST_ASSERT_EQUAL(kTouchSwipe, path({{160, 60}, {160, 110}, {160, 160}, {160, 200}}, 40));  // down, 140 px in 120 ms
  TEST_ASSERT_EQUAL(kTouchSwipe, path({{160, 200}, {160, 60}}, 160));                         // up
  TEST_ASSERT_EQUAL(kTouchSwipe, path({{60, 120}, {250, 120}}, 160));                         // across
  TEST_ASSERT_EQUAL(kTouchSwipe, path({{60, 120}, {100, 120}}, 66));                          // 40 px in 66 ms
  TEST_ASSERT_EQUAL(int(Gesture::kStroke), path({{60, 120}, {100, 120}}, 67));                // and in 67
  TEST_ASSERT_EQUAL(int(Gesture::kStroke), path({{60, 120}, {120, 120}}, 100));               // 600 px a second
  TEST_ASSERT_EQUAL(kTouchSwipe, path({{60, 120}, {100, 80}}, 80));  // 500 px a second across and up: 707 in all
  TEST_ASSERT_EQUAL(int(Gesture::kRuffle), path({{160, 200}, {160, 60}}, 900));
  TEST_ASSERT_EQUAL(kTouchTap, path({{60, 120}, {90, 120}}, 10));  // quick, but short of a stroke
  // What counts is how fast it lets go: a finger that waits, then flicks,
  // swipes; one that swipes, then stops before it lets go, strokes.
  TEST_ASSERT_EQUAL(kTouchSwipe, path({{60, 120}, {60, 120}, {60, 120}, {200, 120}}, 100));
  TEST_ASSERT_EQUAL(int(Gesture::kStroke), path({{60, 120}, {200, 120}, {200, 120}}, 80));
  // A swipe names the stroke it would be: up, the ruffle.
  TouchGesture g;
  g.down(160, 200, 0);
  g.move(160, 60, 100);
  render::Gesture what = Gesture::kHandoff;
  TEST_ASSERT_EQUAL(TouchGesture::kSwipe, g.up(what));
  TEST_ASSERT_EQUAL(int(Gesture::kRuffle), int(what));
  g.down(60, 120, 0);
  g.move(200, 120, 100);
  TEST_ASSERT_EQUAL(TouchGesture::kSwipe, g.up(what));
  TEST_ASSERT_EQUAL(int(Gesture::kStroke), int(what));
}

// Pins the finger's speed as it lets go: over its last 80 ms of readings
// (at least the last two), so a finger that stopped before it let go has
// none, and a reading again on a frozen clock takes the last one's place.
static void test_how_fast_a_finger_lets_go() {
  TEST_ASSERT_EQUAL_UINT32(80, TouchGesture::kFlingMs);
  TouchGesture g;
  int vx, vy;
  g.down(100, 100, 0);
  g.velocity(vx, vy);
  TEST_ASSERT_EQUAL_INT(0, vx);
  TEST_ASSERT_EQUAL_INT(0, vy);
  for (int t = 20; t <= 200; t += 20) g.move(100 + t, 100 - t / 2, uint32_t(t));  // 1000 px/s right, 500 up
  g.velocity(vx, vy);
  TEST_ASSERT_EQUAL_INT(1000, vx);
  TEST_ASSERT_EQUAL_INT(-500, vy);
  for (uint32_t t = 220; t <= 300; t += 20) g.move(300, 0, t);  // still, its last 80 ms
  g.velocity(vx, vy);
  TEST_ASSERT_EQUAL_INT(0, vx);
  TEST_ASSERT_EQUAL_INT(0, vy);
  // Readings 40 ms apart, as on the board's slower frames.
  g.down(100, 100, 1000);
  g.move(140, 100, 1040);
  g.move(180, 100, 1080);
  g.move(180, 100, 1080);  // the loop again on the same clock
  g.velocity(vx, vy);
  TEST_ASSERT_EQUAL_INT(1000, vx);
  const TouchGesture::Path p = g.path();
  TEST_ASSERT_EQUAL_INT(100, p.x0);
  TEST_ASSERT_EQUAL_INT(180, p.x);
  TEST_ASSERT_EQUAL_UINT32(80, p.ms);
}

// Pins the hold that dismisses a request: a finger kept down 1 s inside a
// spot 24 px wide each way. Wandering past it (a stroke on its way, a
// tickle's wiggle) is no hold, however long the finger stays down.
static void test_a_hold() {
  TEST_ASSERT_EQUAL_UINT32(1000, TouchGesture::kHoldMs);
  TEST_ASSERT_EQUAL_INT(24, TouchGesture::kHoldSpotPx);
  TouchGesture g;
  g.down(100, 100, 5000);
  g.move(112, 112, 5100);
  g.move(88, 88, 5200);  // 24 px each way: still the spot
  TEST_ASSERT_FALSE(g.held(5999));
  TEST_ASSERT_TRUE(g.held(6000));
  TEST_ASSERT_TRUE(g.held(9000));
  g.down(100, 100, 5000);
  g.move(125, 100, 5100);  // 25 px across
  TEST_ASSERT_FALSE(g.held(9000));
  g.down(100, 100, 5000);
  g.move(100, 75, 5100);  // 25 px down
  TEST_ASSERT_FALSE(g.held(9000));
  // A stroke that has come back to where it began was still a stroke.
  g.down(60, 120, 0);
  g.move(120, 120, 500);
  g.move(60, 120, 1000);
  TEST_ASSERT_FALSE(g.held(2000));
  // The clock wraps.
  g.down(10, 10, 0xFFFFFF00u);
  TEST_ASSERT_TRUE(g.held(0xFFFFFF00u + 1000));
}

// Feeds `MotionGesture` a reading every 20 ms from `from` to `to`, and
// returns the events it made.
static std::vector<MotionGesture::Event> feed(MotionGesture& m, uint32_t from, uint32_t to, int ax, int ay, int az) {
  std::vector<MotionGesture::Event> out;
  for (uint32_t t = from; t < to; t += 20)
    if (MotionGesture::Event e = m.update(ax, ay, az, t)) out.push_back(e);
  return out;
}
static void still(MotionGesture& m, uint32_t& t, uint32_t ms) {
  feed(m, t, t + ms, 0, 0, 1000);
  t += ms;
}

// Pins MotionGesture's first guesses: a pick-up is 150 mg off 1 g for
// 150 ms from still, and a put-down 1 s still after it; a shake three
// swings past 500 mg within 600 ms; a thump a jolt past 350 mg over within
// 80 ms; face down 1 s with z under -800 mg, face up again over 800.
// Typing on the desk (a few tens of mg) is none of them.
static void test_what_the_motion_sensor_feels() {
  TEST_ASSERT_EQUAL_INT(150, MotionGesture::kLiftMg);
  TEST_ASSERT_EQUAL_INT(500, MotionGesture::kShakeMg);
  MotionGesture m;
  uint32_t t = 0;
  still(m, t, 2000);
  // Typing: a jitter well inside the still band.
  for (int i = 0; i < 100; ++i, t += 20) TEST_ASSERT_EQUAL(MotionGesture::kNone, m.update(i % 2 ? 30 : -30, 0, 1000, t));
  // A thump: one 40 ms jolt.
  TEST_ASSERT_TRUE(feed(m, t, t + 40, 0, 0, 1500).empty());
  t += 40;
  auto e = feed(m, t, t + 40, 0, 0, 1000);
  t += 40;
  TEST_ASSERT_EQUAL(1, int(e.size()));
  TEST_ASSERT_EQUAL(MotionGesture::kThump, e[0]);
  still(m, t, 2000);
  // Picked up: 300 ms lifting at 1.3 g, then held, then set down.
  e = feed(m, t, t + 300, 0, 0, 1300);
  t += 300;
  TEST_ASSERT_EQUAL(1, int(e.size()));
  TEST_ASSERT_EQUAL(MotionGesture::kPickup, e[0]);
  TEST_ASSERT_TRUE(m.held());
  e = feed(m, t, t + 600, 200, 0, 900);  // carried about
  t += 600;
  TEST_ASSERT_TRUE(e.empty());
  e = feed(m, t, t + 1200, 0, 0, 1000);
  t += 1200;
  TEST_ASSERT_EQUAL(1, int(e.size()));
  TEST_ASSERT_EQUAL(MotionGesture::kPutdown, e[0]);
  // Shaken: swings of ±700 mg every 60 ms.
  std::vector<MotionGesture::Event> shook;
  for (int i = 0; i < 12; ++i, t += 60) {
    if (auto x = m.update(0, 0, i % 2 ? 300 : 1700, t)) shook.push_back(x);
  }
  TEST_ASSERT_TRUE(!shook.empty());
  TEST_ASSERT_EQUAL(MotionGesture::kShake, shook.back());
  still(m, t, 3000);
  // Face down, and back up.
  e = feed(m, t, t + 1500, 0, 0, -1000);
  t += 1500;
  TEST_ASSERT_EQUAL(1, int(std::count(e.begin(), e.end(), MotionGesture::kFaceDown)));
  TEST_ASSERT_TRUE(m.faceDown());
  e = feed(m, t, t + 200, 0, 0, 1000);
  t += 200;
  TEST_ASSERT_EQUAL(1, int(std::count(e.begin(), e.end(), MotionGesture::kFaceUp)));
  TEST_ASSERT_FALSE(m.faceDown());
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_short_press_is_a_tap);
  RUN_TEST(test_hold_is_push_to_talk);
  RUN_TEST(test_talk_is_capped_at_30_s);
  RUN_TEST(test_bounces_are_ignored);
  RUN_TEST(test_a_touchs_path);
  RUN_TEST(test_a_quick_stroke_is_a_swipe);
  RUN_TEST(test_how_fast_a_finger_lets_go);
  RUN_TEST(test_a_hold);
  RUN_TEST(test_what_the_motion_sensor_feels);
  return UNITY_END();
}
