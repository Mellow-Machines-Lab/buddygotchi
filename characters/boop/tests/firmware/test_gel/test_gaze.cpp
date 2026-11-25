// Where the gel looks by itself (render/gel/gaze.h) and typing along with
// you (render/gel/face.h): the rules, their times, and how each gives way.
#include <unity.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <memory>

#include "app/behaviour.h"
#include "render/gel/face.h"
#include "render/gel/gaze.h"
#include "render/gel/pastimes.h"
#include "render/tags.h"

using namespace render;
using namespace render::gel;

namespace {

struct Board {
  linkkit::Rng rng;
  app::Behaviour b{std::make_unique<GelFace>()};
  app::Model m;
  uint32_t t = 0;
  Board(SceneState look, uint32_t when) {
    b.reset(0, rng);
    m.mood = Mood::kCalm;
    m.base = look;
    m.act = SceneState::kToolUse;  // typing: no activity's pose has the body
    m.when = reached(when);
    b.onState(m, 0);
  }
  GelFace& face() { return static_cast<GelFace&>(b.face()); }
  void state() { b.onState(m, t); }
  void tags(uint32_t when) {
    m.when = reached(when);
    state();
  }
  template <typename Each>
  void to(uint32_t until, Each each) {
    for (; t + 16 <= until;) {
      t += 16;
      if (t % 10000 < 16) state();
      b.advance(t, rng);
      each();
    }
  }
  void to(uint32_t until) {
    to(until, [] {});
  }
};

}  // namespace

// Pins the rules and their order: nothing while something else has the
// eyes; needs you is up at you for kNoticeMs, then the Mac's side, and
// rest with no side told; typing along is down at the keys; at work in an
// activity's own pose (looking, running, waiting) the pose's clip has the
// eyes; else rest.
void test_the_eyes_rest_unless_theres_a_reason() {
  static_assert(Gaze::kNoticeMs == 1200, "the look at you this test pins");
  Gaze g;
  GazeFacts f;
  TEST_ASSERT_FALSE(g.look(f, 0).on);  // not free
  f.free = true;
  TEST_ASSERT_FALSE(g.look(f, 16).on);  // free, and nothing to look at
  f.needsYou = true, f.lookMs = 0, f.mac = 1;
  GazePoint p = g.look(f, 32);
  TEST_ASSERT_TRUE(p.on && p.x == Gaze::kMidX && p.y < 0);  // up at you
  f.lookMs = Gaze::kNoticeMs - 1;
  TEST_ASSERT_TRUE(g.look(f, 48).y < 0);
  f.lookMs = Gaze::kNoticeMs;
  p = g.look(f, 64);
  TEST_ASSERT_TRUE(p.on && p.x > 502 && p.y == Gaze::kEyesY);  // then the Mac, on its right
  f.lookMs = 10 * 60 * 1000;
  TEST_ASSERT_TRUE(g.look(f, 80).x > 502);  // and held while it waits
  f.mac = -1;
  TEST_ASSERT_TRUE(g.look(f, 96).x < 0);
  f.mac = 0;
  TEST_ASSERT_FALSE(g.look(f, 112).on);  // no side told: rest
  f.free = false, f.mac = 1;
  TEST_ASSERT_FALSE(g.look(f, 128).on);  // a Moment over it has the eyes
  f = GazeFacts{};
  f.free = f.along = true;
  p = g.look(f, 144);
  TEST_ASSERT_TRUE(p.on && p.x == Gaze::kMidX && p.y > Gaze::kEyesY);  // down at the keys
  f.needsYou = true;
  TEST_ASSERT_TRUE(g.look(f, 160).y < 0);  // needs you first
  // A pose's clip has the eyes, but needs you comes before it.
  Gaze posed;
  f = GazeFacts{};
  f.free = f.posed = true;
  TEST_ASSERT_FALSE(posed.look(f, 1016).on);
  f.posed = f.needsYou = true, f.mac = 1, f.lookMs = Gaze::kNoticeMs;
  TEST_ASSERT_TRUE(posed.look(f, 2064).x > 502);  // needs you comes before a pose
}

// The eyes turn to what it looks at more slowly than they follow a finger
// (Motion::kAttendRate against kFollowRate), a finger has them first, and
// let go they come back forward.
void test_a_look_is_a_turn_not_a_dart() {
  static_assert(Motion::kAttendRate == 5 && Motion::kFollowRate == 12, "the rates this test pins");
  auto after = [](bool finger, int ms) {
    auto e = std::make_unique<Engine>();
    for (int t = 0; t <= 960; t += 16) e->step(t);
    for (int t = 976; t <= 960 + ms; t += 16) {
      if (finger) e->lookAt(q(.08), 0);
      else e->attend(q(.08), 0);
      e->step(t);
    }
    return e->motion.gaze;
  };
  const F look = after(false, 160), follow = after(true, 160);
  TEST_ASSERT_TRUE(look > F(0) && look < follow);
  TEST_ASSERT_TRUE(after(false, 160) < q(.08) * q(.6));   // not there in 160 ms
  TEST_ASSERT_TRUE(after(false, 1000) > q(.08) * q(.95));  // there within a second
  auto e = std::make_unique<Engine>();
  for (int t = 0; t <= 960; t += 16) e->step(t);
  e->attend(q(.08), q(.05));
  e->lookAt(q(-.08), 0);  // a finger, the other way
  for (int t = 976; t <= 2000; t += 16) e->step(t);
  TEST_ASSERT_TRUE(e->motion.gaze < F(0));
  e->lookAway();
  e->unattend();
  for (int t = 2016; t <= 5000; t += 16) e->step(t);
  TEST_ASSERT_TRUE(abs(e->motion.gaze) < q(.02) && abs(e->motion.gazeUp) < q(.005));
}

// Pins typing along, kAlongLingerMs and the brisk paws: idle with your
// hands busy, its keyboard comes out over the rig's fade and its paws tap;
// you stop, they rest and the keyboard stays 4 s, then goes; no pastime is
// dealt while it's out. Something needs you: gone. At work its paws type
// briskly with you at its desk, in its typing pose alone: looking, running
// or waiting, its paws are off the keys and stay off. Asleep, nothing. It
// waits for a pastime playing to end, and never cuts one.
void test_it_types_along_with_you() {
  static_assert(GelFace::kAlongLingerMs == 4000, "the linger this test pins");
  const uint32_t day = tagBit("day"), typing = tagBit("typing");
  Board board(SceneState::kIdle, day | tierBit(2));
  GelFace& face = board.face();
  board.to(1000);
  TEST_ASSERT_EQUAL_INT(0, face.pastimes(board.t).keys);
  board.tags(day | tierBit(2) | typing);
  board.to(board.t + rig::kFadeMs + 48);
  PastimeShow s = face.pastimes(board.t);
  TEST_ASSERT_TRUE(s.keys == 255 && s.tapping);
  // Its body keeps time too, a little (the rig's `type-along`): it moves, and
  // never bounces.
  int low = 1 << 30, high = 0, lifted = 0;
  board.to(board.t + 1300, [&] {
    const auto c = face.mixer().channels();
    low = std::min(low, int(c[rig::Channel::kSquash])), high = std::max(high, int(c[rig::Channel::kSquash]));
    lifted = std::max(lifted, int(c[rig::Channel::kLift]));
  });
  TEST_ASSERT_TRUE(high - low > 20 && high - low < 100);  // a slight dip, a beat every 600 ms
  TEST_ASSERT_EQUAL_INT(0, lifted);                        // and no hop
  TEST_ASSERT_EQUAL_STRING("along", face.passing(board.t));
  TEST_ASSERT_TRUE(face.engine().motion.attending);  // its eyes on the keys
  // Two minutes of your typing: never a pastime over the keys.
  board.to(board.t + 120000, [&] { TEST_ASSERT_EQUAL_INT(int(Pastime::kNone), int(face.pastimes(board.t).playing)); });
  // You stop.
  board.tags(day | tierBit(2));
  const uint32_t stopped = board.t;
  board.to(stopped + 64);
  s = face.pastimes(board.t);
  TEST_ASSERT_TRUE(s.keys == 255 && !s.tapping);
  board.to(board.t + 600);
  TEST_ASSERT_TRUE(std::abs(face.mixer().channels()[rig::Channel::kSquash]) < 10);  // and it sits up again
  // Two minutes of typing along stopped: it looks up at you a moment
  // (thinking with you), then rests.
  TEST_ASSERT_TRUE(face.engine().motion.attending && face.engine().motion.attendUp > F(0));
  board.to(stopped + Gaze::kThinkMs + 32);
  TEST_ASSERT_FALSE(face.engine().motion.attending);  // and its eyes come back
  board.to(stopped + GelFace::kAlongLingerMs - 64);
  TEST_ASSERT_EQUAL_INT(255, face.pastimes(board.t).keys);
  board.to(stopped + GelFace::kAlongLingerMs + rig::kFadeMs + 64);
  TEST_ASSERT_EQUAL_INT(0, face.pastimes(board.t).keys);
  // A pause shorter than that keeps it out.
  board.tags(day | tierBit(2) | typing);
  board.to(board.t + 1000);
  board.tags(day | tierBit(2));
  board.to(board.t + 2000);
  board.tags(day | tierBit(2) | typing);
  board.to(board.t + 64);
  TEST_ASSERT_TRUE(face.pastimes(board.t).keys == 255 && face.pastimes(board.t).tapping);
  // Something needs you: the keys go with the look.
  board.m.attn = true, board.m.attnId = 4;
  std::strcpy(board.m.agent, "claude");
  board.state();
  board.to(board.t + rig::kFadeMs + 64);
  TEST_ASSERT_TRUE(face.pastimes(board.t).keys == 0 && !face.pastimes(board.t).tapping);
  board.m.attn = false;
  // At work its desk is out already: no keyboard of its own, and its paws
  // type with you, briskly, its eyes on the keys; you stop, and they don't.
  board.m.base = SceneState::kWorking;
  board.tags(day | typing);
  board.to(board.t + 1000);
  s = face.pastimes(board.t);
  TEST_ASSERT_TRUE(s.keys == 0 && s.tapping);
  TEST_ASSERT_EQUAL_STRING("along", face.passing(board.t));
  TEST_ASSERT_TRUE(face.engine().motion.attending);
  board.tags(day);
  board.to(board.t + 64);
  TEST_ASSERT_TRUE(!face.pastimes(board.t).tapping && !face.engine().motion.attending);
  // In another activity's pose it goes with you at the light size: the
  // pose sways at your speed (`type-along` on the mixer), but its paws stay
  // the pose's and the gaze leaves the eyes to the pose's clip; back at
  // typing, its paws type again.
  for (SceneState act : {SceneState::kAnalyzing, SceneState::kTerminal, SceneState::kWaiting}) {
    board.m.act = act;
    board.tags(day | typing);
    board.to(board.t + 2000, [&] {
      TEST_ASSERT_TRUE(!face.pastimes(board.t).tapping && !face.engine().motion.attending);
    });
    TEST_ASSERT_EQUAL_STRING("along", face.passing(board.t));
  }
  board.m.act = SceneState::kToolUse;
  board.state();
  board.to(board.t + 64);
  TEST_ASSERT_TRUE(face.pastimes(board.t).tapping);
  board.tags(day);
  // Asleep: nothing, your typing or not.
  board.m.base = SceneState::kAsleep;
  board.tags(day | typing);
  board.to(board.t + 3000, [&] { TEST_ASSERT_TRUE(face.pastimes(board.t).keys == 0 && !face.pastimes(board.t).tapping); });
  // Brisk is twice as often and higher than the agents' soft typing.
  // No quicker than the soft typing, higher, and no bounce.
  static_assert(kBriskMs >= 300 && kBriskLift > 2 * kTypeLift && kBriskLift <= 3 * kTypeLift,
                "typing with you is clearer than the agents', not a bounce");
  TEST_ASSERT_EQUAL_INT(kBriskLift, typeLift(2 * kBriskMs - kBriskTapMs / 2, -1, true));
  TEST_ASSERT_EQUAL_INT(kBriskLift, typeLift(kBriskMs - kBriskTapMs / 2, 1, true));
  TEST_ASSERT_EQUAL_INT(kBriskLift, briskLift(kBeat - kTapBeat / 2, 1));
  // A pastime playing as you start: it plays out first.
  Board playing(SceneState::kIdle, day | tierBit(2));
  playing.to(1000);
  playing.face().playPastime(Pastime::kHop, playing.t);
  playing.tags(day | tierBit(2) | typing);
  bool hopped = false, alongDuring = false, alongAfter = false;
  playing.to(playing.t + 9000, [&] {
    const PastimeShow now = playing.face().pastimes(playing.t);
    hopped = hopped || now.playing == Pastime::kHop;
    if (now.playing == Pastime::kHop && now.fade == 255) alongDuring = alongDuring || now.tapping;
    alongAfter = alongAfter || (now.playing == Pastime::kNone && now.tapping);
  });
  TEST_ASSERT_TRUE(hopped && !alongDuring && alongAfter);
}
