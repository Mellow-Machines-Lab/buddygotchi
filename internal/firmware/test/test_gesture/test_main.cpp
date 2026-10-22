// Boop's BOOT button: a tap, and a hold for push-to-talk; a touch's path:
// a tap, a stroke, a ruffle, a tickle, a boop on the nose; and the motion
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
static TouchGesture::Kind path(std::initializer_list<std::pair<int, int>> points) {
  TouchGesture g;
  auto p = points.begin();
  g.down(p->first, p->second);
  for (++p; p != points.end(); ++p) g.move(p->first, p->second);
  return g.up();
}
static void test_a_touchs_path() {
  TEST_ASSERT_EQUAL(TouchGesture::kTap, path({{40, 40}}));
  TEST_ASSERT_EQUAL(TouchGesture::kTap, path({{40, 40}, {60, 40}}));        // short of a stroke
  TEST_ASSERT_EQUAL(TouchGesture::kStroke, path({{60, 120}, {100, 120}}));  // 40 px across
  TEST_ASSERT_EQUAL(TouchGesture::kStroke, path({{160, 60}, {160, 150}}));  // down
  TEST_ASSERT_EQUAL(TouchGesture::kRuffle, path({{160, 150}, {150, 90}}));  // up
  TEST_ASSERT_EQUAL(TouchGesture::kTickle, path({{100, 100}, {120, 100}, {100, 100}, {120, 100}, {100, 100}, {120, 100}}));
  TEST_ASSERT_EQUAL(TouchGesture::kNose, path({{160, 134}}));
  TEST_ASSERT_EQUAL(TouchGesture::kNose, path({{174, 148}}));
  TEST_ASSERT_EQUAL(TouchGesture::kTap, path({{175, 134}}));
  TEST_ASSERT_EQUAL(TouchGesture::kTap, path({{160, 100}}));  // the face, but not its nose
  render::Gesture g;
  TEST_ASSERT_TRUE(app::gestureOf(TouchGesture::kNose, g) && g == render::Gesture::kNose);
  TEST_ASSERT_FALSE(app::gestureOf(TouchGesture::kTap, g));
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
  RUN_TEST(test_what_the_motion_sensor_feels);
  return UNITY_END();
}
