// A finger on the gel, its own life under your hand: the eyes after it, at
// every size; a finger at rest leaning in and dozing; and what that leaves
// alone: the needs-you screen's dismiss, the drawer, a finish's touches, an
// ask's lane, a stroke, a tickle and push-to-talk. Nothing here ever approves
// or blocks: the most a lean does is tell the Mac `gesture lean`.
#include <unity.h>

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "app/device.h"
#include "linkkit/kit.h"
#include "render/gel/face.h"
#include "render/gel/painter.h"
#include "render/tags.h"

using namespace render;
using namespace render::gel;

extern long allocCount;
extern bool allocCounting;

namespace {

struct Hal : app::Hal {
  int effects = 0, gain = 0, vol = 0;
  uint32_t realMs() override { return 0; }
  const char* fwVersion() override { return "t"; }
  const char* gitSha() override { return "t"; }
  void effect(const voice::Effect& e) override { ++effects, gain = e.gain, vol = e.vol; }
};

struct Capture : linkkit::Out {
  std::string text;
  void write(const char* s, size_t n) override { text.append(s, n); }
};

constexpr const char* kLean = "{\"t\":\"ev\",\"kind\":\"gesture\",\"did\":\"lean\"}\n";
constexpr const char* kAnyTap = "\"kind\":\"tap\"";
constexpr const char* kAttn = "{\"t\":\"state\",\"base\":\"working\",\"vol\":0,"
                              "\"attn\":{\"agent\":\"claude\",\"project\":\"landing\",\"id\":3}}";

// A gel board on USB, its clock frozen.
struct Board {
  Hal hal;
  Capture usb;
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(kWidth) * kHeight);
  std::unique_ptr<app::Device> dev;
  std::unique_ptr<linkkit::Kit> kit;
  uint32_t t = 0;
  explicit Board(const char* state = "{\"t\":\"state\",\"base\":\"idle\",\"idle\":1,\"vol\":0}") {
    dev = std::make_unique<app::Device>(hal, px.data());
    kit = std::make_unique<linkkit::Kit>(hal, *dev, true);
    kit->setOut(linkkit::Link::kUsb, &usb);
    line("{\"t\":\"dbg.clock\",\"freeze\":0}");
    line(state);
  }
  void line(const char* s) {
    kit->handleLine(s, std::strlen(s), linkkit::Link::kUsb);
    kit->tick();
    if (dev->takeFrame()) dev->frames()->present();
  }
  void run(uint32_t ms) {
    for (uint32_t done = 0; done < ms; done += 20) {
      char step[64];
      std::snprintf(step, sizeof(step), "{\"t\":\"dbg.clock\",\"freeze\":%lu}", (unsigned long)(t += 20));
      line(step);
    }
  }
  void touch(int x, int y, int ms) {
    char s[96];
    std::snprintf(s, sizeof(s), "{\"t\":\"dbg.touch\",\"x\":%d,\"y\":%d,\"ms\":%d}", x, y, ms);
    line(s);
  }
  void stroke(int x, int y, int toX, int toY, int ms) {
    char s[128];
    std::snprintf(s, sizeof(s), "{\"t\":\"dbg.touch\",\"x\":%d,\"y\":%d,\"to_x\":%d,\"to_y\":%d,\"ms\":%d}", x, y, toX,
                  toY, ms);
    line(s);
  }
  // dbg.state's touch.lean: 0 none, 1 leaning, 2 dozing.
  int lean() {
    const size_t from = usb.text.size();
    line("{\"t\":\"dbg.state\"}");
    const size_t i = usb.text.find("\"lean\":", from);
    const int at = i == std::string::npos ? -1 : std::atoi(usb.text.c_str() + i + 7);
    usb.text.resize(from);
    return at;
  }
  int count(const char* needle) const {
    int n = 0;
    for (size_t at = usb.text.find(needle); at != std::string::npos; at = usb.text.find(needle, at + 1)) ++n;
    return n;
  }
};

// A gel face, settled in the look.
void settle(GelFace& f, uint32_t& t) {
  linkkit::Rng rng;
  f.reset(0, rng);
  FaceContext c;
  c.base = SceneState::kIdle;
  c.when = tagBit("day");
  FaceSource s;
  s.look = SceneState::kIdle;
  f.sync(s, c, 0);
  for (t = 0; t < 400; t += 16) f.step(t, rng);
}

void runFace(GelFace& f, uint32_t& t, uint32_t ms) {
  linkkit::Rng rng;
  for (const uint32_t end = t + ms; t < end; t += 16) f.step(t, rng);
}

}  // namespace

// The eyes go toward a finger at each of the screen's corners, the way it is
// from the eyes, no further than kGazeReach, and drift back when it goes.
void test_the_eyes_follow_a_finger() {
  const struct {
    int x, y, across, up;
  } corners[] = {{10, 10, -1, 1}, {310, 10, 1, 1}, {10, 200, -1, -1}, {310, 200, 1, -1}};
  for (const auto& c : corners) {
    GelFace f;
    uint32_t t = 0;
    settle(f, t);
    f.finger(true, c.x, c.y);
    runFace(f, t, 800);
    const Motion& m = f.engine().motion;
    TEST_ASSERT_EQUAL_INT(c.across, m.gaze > F(0) ? 1 : -1);
    TEST_ASSERT_EQUAL_INT(c.up, m.gazeUp > F(0) ? 1 : -1);
    TEST_ASSERT_TRUE(abs(m.gaze) > q(.04));
    TEST_ASSERT_TRUE(abs(m.gaze) < q(.16));
    TEST_ASSERT_TRUE(abs(m.gazeUp) < q(.12));
    f.finger(false, 0, 0);
    runFace(f, t, 2000);
    TEST_ASSERT_TRUE(abs(f.engine().motion.gazeUp) < q(.005));
    TEST_ASSERT_TRUE(abs(f.engine().motion.gaze) < q(.02));  // its own wander's
  }
  // Over the eyes, it looks straight on: the target's measured from them.
  GelFace f;
  uint32_t t = 0;
  settle(f, t);
  f.finger(true, 160, kDeskRow - kEyesOverDesk);
  runFace(f, t, 800);
  TEST_ASSERT_TRUE(abs(f.engine().motion.gazeUp) < q(.012));
}

// A finger takes the dome where it stands: where on it the finger went down
// is in its own half-width and half-height.
void test_a_drag_starts_where_the_finger_is_on_the_dome() {
  GelFace f;
  uint32_t t = 0;
  settle(f, t);
  // Half way out on its half-width, on its middle's row.
  f.finger(true, 160 + kPxPerUnit * 11 / 10 / 2, 129);
  TEST_ASSERT_TRUE(abs(f.engine().point[0] - q(.5)) < q(.03));
  TEST_ASSERT_TRUE(abs(f.engine().point[1]) < q(.03));
  f.finger(false, 0, 0);
}

// The eyes' wander draws its dice with or without a finger, so a touch changes
// nothing else the engine goes on to do.
void test_a_finger_leaves_the_dice_alone() {
  Motion left, right;
  Random ra(9), rb(9);
  right.following = true;
  for (int i = 0; i < 2000; ++i) {
    left.advance(T::ratio(16, 1000), left.time + T::ratio(16, 1000), ra);
    right.advance(T::ratio(16, 1000), right.time + T::ratio(16, 1000), rb);
  }
  TEST_ASSERT_TRUE(ra.next() == rb.next());
  TEST_ASSERT_TRUE(left.nextLook == right.nextLook);
}

// The lean is toward where the finger is, in the body's own half-widths: a
// finger on its edge, 93 px from its middle, pulls it the whole reach.
void test_a_lean_goes_where_the_finger_is() {
  for (int side : {-1, 1}) {
    GelFace f;
    uint32_t t = 0;
    settle(f, t);
    f.finger(true, 160 + side * 93, 130);
    f.lean(Face::Lean::kIn, t);
    runFace(f, t, 1500);
    const F reach = f.engine().pull[0].x * side;
    TEST_ASSERT_TRUE(reach > Engine::kLeanReach * q(.85));
    TEST_ASSERT_TRUE(reach < Engine::kLeanReach * q(1.15));
    TEST_ASSERT_TRUE(f.engine().pull[2].x > q(.25));  // and forward, into it
  }
  // A finger past it pulls no further than its edge.
  GelFace f;
  uint32_t t = 0;
  settle(f, t);
  f.finger(true, 318, 130);
  f.lean(Face::Lean::kIn, t);
  runFace(f, t, 1500);
  TEST_ASSERT_TRUE(f.engine().pull[0].x < Engine::kLeanReach * q(1.15));
}

// Pins the board's rule: past a second at rest it leans in, past five it dozes
// (the sleeping face), and lifting wakes it, telling the Mac one `lean`, which
// is care: no tap, so it opens nothing, and a poke doesn't play.
void test_a_finger_at_rest_leans_then_dozes_and_lifting_wakes() {
  Board b;
  b.touch(100, 90, 7000);
  b.run(960);
  TEST_ASSERT_EQUAL_INT(0, b.lean());
  b.run(80);
  TEST_ASSERT_EQUAL_INT(1, b.lean());
  b.run(3900);
  TEST_ASSERT_EQUAL_INT(1, b.lean());
  b.run(120);
  TEST_ASSERT_EQUAL_INT(2, b.lean());
  TEST_ASSERT_EQUAL_INT(0, b.count(kLean));
  b.run(2100);
  TEST_ASSERT_EQUAL_INT(0, b.lean());
  TEST_ASSERT_EQUAL_INT(1, b.count(kLean));
  TEST_ASSERT_EQUAL_INT(0, b.count(kAnyTap));
  // On the nose it's the same.
  b.usb.text.clear();
  b.touch(160, 134, 1300);
  b.run(1500);
  TEST_ASSERT_EQUAL_INT(1, b.count(kLean));
  TEST_ASSERT_EQUAL_INT(0, b.count("\"did\":\"nose\""));
}

// How hard the body starts as the finger lifts, from a touch of `ms`.
static F startOnLifting(int ms) {
  Board b;
  b.touch(100, 90, ms);
  b.run(ms - 200);
  const Engine& e = static_cast<GelFace&>(b.dev->face()).engine();
  F most = 0;
  for (int i = 0; i < 40; ++i) {
    b.run(20);
    most = max(most, abs(e.pull[1].v));
  }
  return most;
}

// Lifting your finger from a doze wakes it with a little start, up; from a
// lean it only lets go. The start is a kick of the body's spring on the
// frame the finger goes, before the springs have taken any of it.
void test_lifting_a_doze_wakes_it_with_a_start() {
  const F dozing = startOnLifting(7000), leaning = startOnLifting(3000);
  TEST_ASSERT_TRUE(dozing > leaning + q(1));
  TEST_ASSERT_TRUE(leaning < q(.5));
}

// Under a second, a touch stays what it was: a tap, a boop on the nose.
void test_a_short_hold_stays_a_tap() {
  Board b;
  b.touch(100, 90, 900);
  b.run(1100);
  TEST_ASSERT_EQUAL_INT(0, b.count(kLean));
  TEST_ASSERT_EQUAL_INT(1, b.count(kAnyTap));
  b.run(3000);
  b.usb.text.clear();
  b.touch(160, 134, 500);
  b.run(700);
  TEST_ASSERT_EQUAL_INT(0, b.count(kLean));
  TEST_ASSERT_EQUAL_INT(1, b.count("\"did\":\"nose\""));
}

void test_a_stroke_and_a_tickle_stay_theirs() {
  Board b;
  b.stroke(60, 120, 260, 120, 3000);  // slow, and long past a second
  b.run(800);
  TEST_ASSERT_EQUAL_INT(0, b.lean());
  b.run(2400);
  TEST_ASSERT_EQUAL_INT(0, b.count(kLean));
  TEST_ASSERT_EQUAL_INT(1, b.count("\"did\":\"stroke\""));
  // A swipe is still a swipe.
  b.run(3000);
  b.usb.text.clear();
  b.stroke(60, 120, 260, 120, 150);
  b.run(300);
  TEST_ASSERT_EQUAL_INT(1, b.count("\"did\":\"swipe\""));
  // A tickle wiggles past a second without ever coming to rest.
  b.run(3000);
  b.usb.text.clear();
  for (int i = 0; i < 16; ++i) {
    b.stroke(i % 2 ? 110 : 100 + 20, 100, i % 2 ? 130 : 100, 100, 100);
    b.run(100);
    TEST_ASSERT_EQUAL_INT(0, b.lean());
  }
  TEST_ASSERT_EQUAL_INT(0, b.count(kLean));
}

// On the needs-you screen a held finger dismisses, as it always did, and that
// is all: no lean, so no care, and no tap.
void test_a_hold_on_the_needs_you_screen_only_dismisses() {
  Board b(kAttn);
  b.touch(60, 60, 7000);
  b.run(1040);
  TEST_ASSERT_EQUAL_INT(1, b.count("\"did\":\"dismiss\""));
  TEST_ASSERT_EQUAL_INT(0, b.lean());
  b.run(6200);
  TEST_ASSERT_EQUAL_INT(0, b.lean());
  TEST_ASSERT_EQUAL_INT(1, b.count("\"did\":\"dismiss\""));
  TEST_ASSERT_EQUAL_INT(0, b.count(kLean));
  TEST_ASSERT_EQUAL_INT(0, b.count(kAnyTap));
}

// A request that comes up under a leaning finger ends the lean at once. It
// isn't dismissed, and it isn't opened: the lift says `lean`, not a tap.
void test_a_needs_you_under_a_lean_ends_it() {
  Board b;
  b.touch(60, 60, 3000);
  b.run(1500);
  TEST_ASSERT_EQUAL_INT(1, b.lean());
  b.line(kAttn);
  b.run(40);
  TEST_ASSERT_EQUAL_INT(0, b.lean());
  b.run(1700);
  TEST_ASSERT_EQUAL_INT(0, b.count("\"did\":\"dismiss\""));
  TEST_ASSERT_EQUAL_INT(0, b.count(kAnyTap));
  TEST_ASSERT_EQUAL_INT(1, b.count(kLean));
  // One that came before the second was up: it never leant, and it's the tap
  // it always was (the Mac's rule, which opens the thread).
  Board early;
  early.touch(60, 60, 1500);
  early.run(500);
  early.line(kAttn);
  early.run(1200);
  TEST_ASSERT_EQUAL_INT(0, early.count(kLean));
  TEST_ASSERT_EQUAL_INT(0, early.count("\"did\":\"dismiss\""));
  TEST_ASSERT_EQUAL_INT(1, early.count(kAnyTap));
}

// While a finish names whose turn it was, a touch is about that: no lean,
// however long, and it taps as it did. A lean a finish comes up under gives way
// and opens nothing.
void test_a_finish_keeps_its_touches() {
  const char* finish = "{\"t\":\"do\",\"id\":42,\"name\":\"reply_ready\",\"play\":\"now\",\"args\":{"
                       "\"who\":{\"agent\":\"claude\",\"thread\":\"fix-nav\"}}}";
  Board b;
  b.line(finish);
  b.run(200);
  b.touch(100, 90, 1400);
  b.run(1200);
  TEST_ASSERT_EQUAL_INT(0, b.lean());
  b.run(400);
  TEST_ASSERT_EQUAL_INT(0, b.count(kLean));
  TEST_ASSERT_EQUAL_INT(1, b.count("\"on\":42"));
  Board under;
  under.touch(100, 90, 2500);
  under.run(1500);
  TEST_ASSERT_EQUAL_INT(1, under.lean());
  under.line(finish);
  under.run(40);
  TEST_ASSERT_EQUAL_INT(0, under.lean());
  under.run(1200);
  TEST_ASSERT_EQUAL_INT(0, under.count("\"on\":42"));
  TEST_ASSERT_EQUAL_INT(1, under.count(kLean));
}

// Push-to-talk takes the face from a lean, and BOOT's press goes on working.
void test_listening_takes_the_face_from_a_lean() {
  Board b;
  b.touch(100, 90, 4000);
  b.run(1500);
  TEST_ASSERT_EQUAL_INT(1, b.lean());
  b.line("{\"t\":\"dbg.press\",\"ms\":1500}");
  b.run(1000);
  TEST_ASSERT_EQUAL_INT(1, b.count("\"talk_on\""));
  TEST_ASSERT_EQUAL_INT(0, b.lean());
}

// The strip's touches are the drawer's: a finger held there leans nothing and
// sends nothing.
void test_a_hold_on_the_strip_is_the_drawers() {
  Board b;
  b.touch(160, 225, 2000);
  b.run(1500);
  TEST_ASSERT_EQUAL_INT(0, b.lean());
  b.run(800);
  TEST_ASSERT_EQUAL_INT(0, b.count(kLean));
}

// A held tap in an ask's lane is its answer, not a lean.
void test_an_asks_lane_keeps_its_held_tap() {
  Board b;
  b.line("{\"t\":\"do\",\"id\":7,\"name\":\"react\",\"play\":\"now\",\"args\":{\"sign\":\"fav snack?\","
         "\"ask\":{\"q\":\"snack\",\"a\":\"cookie\",\"b\":\"pizza\"}}}");
  b.run(200);
  b.usb.text.clear();
  b.touch(60, kLaneTop + 5, 1400);
  b.run(1200);
  TEST_ASSERT_EQUAL_INT(0, b.lean());
  b.run(400);
  TEST_ASSERT_EQUAL_INT(0, b.count(kLean));
  TEST_ASSERT_EQUAL_INT(1, b.count("\"kind\":\"ask\",\"did\":\"a\""));
}

// A Moment takes the body: the lean gives way, and comes back when it's over.
void test_a_moment_cuts_a_lean() {
  Board b;
  b.touch(100, 90, 12000);
  b.run(1500);
  TEST_ASSERT_EQUAL_INT(1, b.lean());
  b.line("{\"t\":\"do\",\"id\":9,\"name\":\"react\",\"play\":\"now\",\"args\":{\"mood\":\"surprised\",\"sign\":\"oh\"}}");
  b.run(100);
  TEST_ASSERT_EQUAL_INT(0, b.lean());
  TEST_ASSERT_EQUAL_INT(0, b.count(kAnyTap));
  b.run(8000);
  TEST_ASSERT_NOT_EQUAL(0, b.lean());
  // So does a Moment's animation.
  Board played;
  played.touch(100, 90, 12000);
  played.run(1500);
  TEST_ASSERT_EQUAL_INT(1, played.lean());
  played.line("{\"t\":\"do\",\"id\":9,\"name\":\"notice\",\"play\":\"now\"}");
  played.run(100);
  TEST_ASSERT_EQUAL_INT(0, played.lean());
}

// The soft breath goes through the sound engine at the state's volume, at a
// fraction of a take's gain; with the volume at 0, or face down, none.
void test_a_leans_breath_minds_the_volume() {
  Board b("{\"t\":\"state\",\"base\":\"idle\",\"idle\":1,\"vol\":5}");
  b.touch(100, 90, 8000);
  b.run(900);
  const int before = b.hal.effects;
  b.run(3000);
  TEST_ASSERT_GREATER_THAN_INT(before, b.hal.effects);
  TEST_ASSERT_EQUAL_INT(5, b.hal.vol);
  TEST_ASSERT_LESS_THAN_INT(100, b.hal.gain);
  Board mute;  // vol 0
  mute.touch(100, 90, 8000);
  mute.run(5000);
  TEST_ASSERT_EQUAL_INT(0, mute.hal.effects);
}

// Following, leaning and dozing take nothing from the heap, frame after frame.
// dbg.state's caption now, "" for none.
static std::string captionOf(Board& b) {
  const size_t from = b.usb.text.size();
  b.line("{\"t\":\"dbg.state\"}");
  const size_t i = b.usb.text.find("\"reason\":", from);
  std::string out;
  if (i != std::string::npos && b.usb.text[i + 9] == '"') {
    const size_t end = b.usb.text.find('"', i + 10);
    out = b.usb.text.substr(i + 10, end - i - 10);
  }
  b.usb.text.resize(from);
  return out;
}
static void doReact(Board& b, int id, const char* args) {
  char s[256];
  std::snprintf(s, sizeof(s), "{\"t\":\"do\",\"id\":%d,\"name\":\"react\",\"play\":\"now\",\"args\":%s}", id, args);
  b.line(s);
}

// A touch says why itself, as it plays: before the Mac has heard. Its run counts.
void test_a_touch_says_why_itself() {
  Board b;
  b.run(500);
  TEST_ASSERT_EQUAL_STRING("", captionOf(b).c_str());
  b.touch(160, 70, 40);
  b.run(120);
  TEST_ASSERT_EQUAL_STRING("you poked Boop", captionOf(b).c_str());
  b.touch(160, 70, 40);
  b.run(120);
  TEST_ASSERT_EQUAL_STRING("you poked Boop x2", captionOf(b).c_str());
  b.run(app::Behaviour::kSignMinMs + 3000);
  TEST_ASSERT_EQUAL_STRING("", captionOf(b).c_str());
  b.stroke(120, 80, 220, 80, 700);
  b.run(900);
  TEST_ASSERT_EQUAL_STRING("you stroked Boop", captionOf(b).c_str());
  // A lean, as it lets go.
  Board held;
  held.touch(100, 90, 1400);
  held.run(1700);
  TEST_ASSERT_EQUAL_STRING("you held Boop", captionOf(held).c_str());
  // With no Mac, with the name you gave it, and a name past the caption's width.
  Board named("{\"t\":\"state\",\"base\":\"idle\",\"idle\":1,\"vol\":0,\"buddy\":\"Luna\"}");
  named.touch(160, 70, 40);
  named.run(120);
  TEST_ASSERT_EQUAL_STRING("you poked Luna", captionOf(named).c_str());
  Board longName("{\"t\":\"state\",\"base\":\"idle\",\"idle\":1,\"vol\":0,\"buddy\":\"Bartholomew\"}");
  longName.touch(160, 70, 40);
  longName.run(120);
  TEST_ASSERT_EQUAL_STRING("you poked it", captionOf(longName).c_str());
  // Asleep, it says who woke it.
  Board asleep("{\"t\":\"state\",\"base\":\"asleep\",\"vol\":0}");
  asleep.touch(160, 70, 40);
  asleep.run(120);
  TEST_ASSERT_EQUAL_STRING("you woke Boop", captionOf(asleep).c_str());
}

// The Mac's reason for the same touch a moment later: no second caption. Still
// up, it carries on past when it would have gone; gone, it isn't shown again;
// in other words, it takes over. Past kOwnReasonMs it's a new reason.
void test_the_macs_reason_doesnt_double_a_touchs() {
  TEST_ASSERT_EQUAL_UINT32(10000, app::Behaviour::kOwnReasonMs);
  constexpr const char* kSame = "{\"mood\":\"happy\",\"loops\":3,\"reason\":\"you poked Boop\"}";
  {
    Board b;
    b.touch(160, 70, 40);
    b.run(500);
    doReact(b, 1, kSame);
    b.run(app::Behaviour::kSignMinMs + 200);  // past what the poke alone would have shown
    TEST_ASSERT_EQUAL_STRING("you poked Boop", captionOf(b).c_str());
  }
  {
    Board b;
    b.touch(160, 70, 40);
    b.run(4000);
    TEST_ASSERT_EQUAL_STRING("", captionOf(b).c_str());
    doReact(b, 1, kSame);
    b.run(60);
    TEST_ASSERT_EQUAL_STRING("", captionOf(b).c_str());
  }
  {
    Board b;
    b.touch(160, 70, 40);
    b.run(500);
    doReact(b, 1, "{\"mood\":\"happy\",\"reason\":\"day 41\"}");
    b.run(60);
    TEST_ASSERT_EQUAL_STRING("day 41", captionOf(b).c_str());
  }
  {
    Board b;
    b.touch(160, 70, 40);
    b.run(app::Behaviour::kOwnReasonMs + 1000);
    doReact(b, 1, kSame);
    b.run(60);
    TEST_ASSERT_EQUAL_STRING("you poked Boop", captionOf(b).c_str());
  }
}

// A `do` that's only a reason plays nothing, ends at once, and takes down
// nothing: a sign or a reason up stays. Needs you refuses it.
void test_a_reason_alone() {
  Board b;
  b.run(500);
  doReact(b, 1, "{\"reason\":\"quiet for 1 h\"}");
  b.run(60);
  TEST_ASSERT_EQUAL_STRING("quiet for 1 h", captionOf(b).c_str());
  TEST_ASSERT_GREATER_THAN_INT(0, b.count("\"kind\":\"ended\""));
  doReact(b, 2, "{\"reason\":\"no agents open\"}");
  b.run(60);
  TEST_ASSERT_EQUAL_STRING("quiet for 1 h", captionOf(b).c_str());
  b.line(kAttn);
  b.run(60);
  doReact(b, 3, "{\"reason\":\"no agents open\"}");
  b.run(60);
  TEST_ASSERT_EQUAL_STRING("", captionOf(b).c_str());
}

// The body's lean from a steady tilt, read off the face.
static F tiltOf(Board& b) { return static_cast<GelFace&>(b.dev->face()).engine().tilted(); }
static void imu(Board& b, int ax, int az) {
  char s[64];
  std::snprintf(s, sizeof(s), "{\"t\":\"dbg.imu\",\"ax\":%d,\"ay\":0,\"az\":%d}", ax, az);
  b.line(s);
}

// Tilted, it sloshes the way it's tipped, past where it'll stay and back; the
// eyes stay level, as a tilt adds only lean; set down at that angle, it goes
// back to none. Pins kTiltMost and that the springs overshoot.
void test_a_tilt_sloshes_and_settles() {
  TEST_ASSERT_TRUE(Engine::kTiltMost == q(.6));
  Board b;
  imu(b, 0, 1000);
  b.run(1000);
  TEST_ASSERT_TRUE(tiltOf(b) == F(0));
  imu(b, -300, 954);
  F most = 0, last = 0;
  for (int i = 0; i < 100; ++i) {
    b.run(20);
    most = max(most, tiltOf(b));
    last = tiltOf(b);
  }
  TEST_ASSERT_TRUE(most > q(.2));
  TEST_ASSERT_TRUE(most > last);
  b.run(25000);
  TEST_ASSERT_TRUE(abs(tiltOf(b)) < q(.02));
}

// Only while nothing else moves the body: a finger, a poke's Moment, listening
// or a needs-you each take the lean back to none, and it comes back after.
void test_a_tilt_gives_way() {
  auto tipped = [] {
    auto b = std::make_unique<Board>();
    imu(*b, 0, 1000);
    b->run(1000);
    imu(*b, -300, 954);
    b->run(800);
    TEST_ASSERT_TRUE(tiltOf(*b) > q(.1));
    return b;
  };
  {
    auto b = tipped();
    b->touch(100, 90, 1500);
    b->run(1200);
    TEST_ASSERT_TRUE(abs(tiltOf(*b)) < q(.05));
    b->run(1200);
    TEST_ASSERT_TRUE(tiltOf(*b) > q(.05));
  }
  {
    auto b = tipped();
    b->line("{\"t\":\"dbg.press\",\"ms\":2500}");
    b->run(1500);
    TEST_ASSERT_TRUE(abs(tiltOf(*b)) < q(.05));
  }
  {
    auto b = tipped();
    b->line(kAttn);
    b->run(1500);
    TEST_ASSERT_TRUE(abs(tiltOf(*b)) < q(.05));
  }
  {
    auto b = tipped();
    imu(*b, 0, -1000);  // turned over: face down, and the lean goes
    b->run(1500);
    TEST_ASSERT_TRUE(abs(tiltOf(*b)) < q(.05));
  }
}

void test_a_tilt_allocates_nothing() {
  Board b;
  imu(b, 0, 1000);
  b.run(3000);
  imu(b, -300, 954);
  b.usb.text.reserve(1 << 20);
  allocCount = 0;
  allocCounting = true;
  b.run(1500);
  allocCounting = false;
  TEST_ASSERT_EQUAL_INT(0, int(allocCount));
}

// Listening, it nods, in bursts with rests between, and nowhere else.
void test_listening_nods() {
  Board b;
  const Engine& e = static_cast<GelFace&>(b.dev->face()).engine();
  for (int i = 0; i < 50; ++i) {
    b.run(40);
    TEST_ASSERT_TRUE(e.nod() == F(0));
  }
  b.line("{\"t\":\"dbg.press\",\"ms\":9000}");
  b.run(600);
  F most = 0, least = 1;
  int rests = 0;
  for (int i = 0; i < 300; ++i) {
    b.run(20);
    most = max(most, e.nod()), least = min(least, e.nod());
    rests += e.nod() < q(.01);
  }
  TEST_ASSERT_TRUE(most > q(.8));
  TEST_ASSERT_TRUE(least < q(.01));
  TEST_ASSERT_GREATER_THAN_INT(30, rests);
  // Pins the nod's size: small enough that the face stays on its desk.
  TEST_ASSERT_TRUE(Engine::kNodForward == q(.42) && Engine::kNodSquash == q(.09));
}

void test_a_lean_allocates_nothing() {
  Board b;
  b.run(3000);  // into the look's loop, as test_steady_frames_allocate_nothing
  b.touch(100, 90, 9000);
  b.usb.text.reserve(1 << 20);  // the test's own capture, growing, isn't the board's
  const auto steady = [&](uint32_t ms) {
    allocCount = 0;
    allocCounting = true;
    b.run(ms);
    allocCounting = false;
    TEST_ASSERT_EQUAL_INT(0, int(allocCount));
  };
  steady(900);  // following
  b.run(400);   // the lean's face coming, as any Moment's does
  steady(3000);
  b.run(1000);  // dozing off
  steady(2000);
}
