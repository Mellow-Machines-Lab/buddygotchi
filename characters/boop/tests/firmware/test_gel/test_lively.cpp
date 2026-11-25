// The motion layer, motion V2 (render/gel/lively.h): its numbers, each rule
// alone and off, and every spring coming to rest on what the clips ask.
#include <unity.h>

#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>

#include "render/gel/face.h"
#include "render/gel/lively.h"
#include "rig_tables.h"  // the staged pack's (characters/charactergen.py)

using namespace render;
using namespace render::gel;
using rig::Channel;

namespace {

double num(F f) { return double(f.raw) / F::scale; }

// A spring as the layer integrates one, in doubles: 1/240 s substeps.
struct Ref {
  double x = 0, v = 0;
  void step(double dt, double target, LivelySpring k) {
    for (double left = dt; left > 1e-12;) {
      const double h = std::min(left, 1.0 / 240);
      v += (double(k.frequency) * k.frequency * (target - x) - k.damping * v) * h;
      x += v * h;
      left -= h;
    }
  }
};

// A hop as a clip asks it: up 20 px over 140 ms, down over 140, still after.
int hopLift(int ms) {
  if (ms < 200) return 0;
  if (ms < 340) return (ms - 200) * 20 / 140;
  if (ms < 480) return 20 - (ms - 340) * 20 / 140;
  return 0;
}
// A slide 40 px to the left over 300 ms, from 200.
int slideX(int ms) { return ms < 200 ? 0 : ms < 500 ? -(ms - 200) * 40 / 300 : -40; }
// A hand out to (60, 50) at size 1000 from 200 ms, back in from 900.
int handSize(int ms) { return ms < 200 ? 0 : ms < 900 ? std::min(1000, (ms - 200) * 5) : std::max(0, 1000 - (ms - 900) * 5); }

rig::Channels at(int ms) {
  rig::Channels c = rig::kRest;
  c[Channel::kLift] = int16_t(hopLift(ms));
  c[Channel::kX] = int16_t(slideX(ms));
  c[Channel::kSquash] = int16_t(ms >= 480 && ms < 560 ? 120 : 0);
  c[Channel::kGlass] = int16_t(ms >= 300 && ms < 700 ? 1000 : 0);
  for (int side = 0; side < 2; ++side) {
    const int size = handSize(ms);
    c[rig::hand(side, rig::HandPart::kSize)] = int16_t(size);
    c[rig::hand(side, rig::HandPart::kX)] = int16_t(size ? (side ? 60 : -60) : 0);
    c[rig::hand(side, rig::HandPart::kY)] = int16_t(size ? 50 : 0);
  }
  return c;
}

// The layer through the hop, the slide and the hands, 16 ms a step, with
// `each` called after every step.
template <class Each>
void play(Lively& l, int until, Each each, bool desk = false) {
  for (int ms = 0; ms <= until; ms += 16) {
    l.advance(16, at(ms), 0, 0, desk);
    each(ms, l.apply(at(ms)));
  }
}

}  // namespace

// Pins motion V2's numbers: the five rules on by default, by name; settle's
// springs (frequency and damping) squash 44 and 31, lean 30 and 21, lift 40
// and 36, x 34 and 31, reach and melt 30 and 30, the glass 36 and 36, in
// 1/240 s substeps, the lift never below the floor; stretch 0.7 thousandths
// taller for each px a second up or down, at most 220, and a landing kicking
// the flat spring (38 and 23) 30 for each px a second, held within 300; the
// crown's lean 2.5 for each px a second across, the other way, at most 320,
// on its spring (19 and 11); the face's springs 22 and 22, drawn all the
// way it's behind, at most 8 px; each hand's place 24 and 24, its size 34
// and 38; the desk's paw at 12 px either side, 4 up, size 765, home within
// 3; a step of 1 s or more setting each where it's going.
void test_the_motion_v2_numbers() {
  static_assert(kRuleCount == 5, "five rules");
  const char* names[] = {"stretch", "settle", "drag", "face", "hands"};
  for (int i = 0; i < kRuleCount; ++i) {
    TEST_ASSERT_EQUAL_STRING(names[i], kRules[i].name);
    TEST_ASSERT_TRUE(kRules[i].on);
  }
  constexpr LivelySpring settle[] = {{44, 31}, {30, 21}, {40, 36}, {34, 31}, {30, 30}, {30, 30}, {36, 36}, {26, 24}};
  for (int i = 0; i < Lively::kSettledCount; ++i) {
    TEST_ASSERT_EQUAL_INT(settle[i].frequency, Lively::kSettle[i].frequency);
    TEST_ASSERT_EQUAL_INT(settle[i].damping, Lively::kSettle[i].damping);
  }
  static_assert(Lively::kTallPerSpeed == 700 && Lively::kTallMost == 220 && Lively::kLand == 30 &&
                    Lively::kFlatMost == 300 && Lively::kFlat.frequency == 38 && Lively::kFlat.damping == 23,
                "stretch");
  static_assert(Lively::kDragPerSpeed == 2500 && Lively::kDragMost == 320 && Lively::kCrown.frequency == 19 &&
                    Lively::kCrown.damping == 11,
                "drag");
  static_assert(Lively::kFaceSpring.frequency == 22 && Lively::kFaceSpring.damping == 22 &&
                    Lively::kFaceGain == 1000 && Lively::kFaceMost == 8,
                "face");
  static_assert(Lively::kHandPlace.frequency == 24 && Lively::kHandPlace.damping == 24 &&
                    Lively::kHandSize.frequency == 34 && Lively::kHandSize.damping == 38 && Lively::kDeskX == 12 &&
                    Lively::kDeskY == 4 && Lively::kDeskSize == 765 && Lively::kHome == 3 &&
                    Lively::kSettledMs == 1000,
                "hands");
  // Each settled channel against its spring, in doubles, through the moves.
  Lively l;
  Ref ref[Lively::kSettledCount];
  play(l, 1200, [&](int ms, const rig::Channels&) {
    if (!ms) {
      for (int i = 0; i < Lively::kSettledCount; ++i) ref[i] = {double(at(0)[Lively::kSettled[i]]), 0};
      return;
    }
    for (int i = 0; i < Lively::kSettledCount; ++i) {
      Ref& r = ref[i];
      r.step(.016, at(ms)[Lively::kSettled[i]], Lively::kSettle[i]);
      if (Lively::kSettled[i] == Channel::kLift && r.x < 0) r = {0, 0};
      if (std::abs(r.x - at(ms)[Lively::kSettled[i]]) < .25 && std::abs(r.v) < 1) r = {double(at(ms)[Lively::kSettled[i]]), 0};
      TEST_ASSERT_TRUE(std::abs(num(l.settled[i].x) - r.x) < 2e-3 + 1e-5 * std::abs(r.x));
    }
  });
  // Stretch: tall as it rises, by its speed; the drag and the face behind
  // the slide; the face never more than 8 px off.
  Lively s;
  s.set("settle", false);
  bool tall = false, landed = false, dragged = false, lagged = false;
  play(s, 1200, [&](int ms, const rig::Channels& c) {
    if (ms == 256) {  // rising: as fast as the lift went up this step
      const int want = int(std::lround((hopLift(256) - hopLift(240)) / .016 * .7));
      TEST_ASSERT_INT_WITHIN(1, -want, c[Channel::kSquash]);
      tall = true;
    }
    if (ms >= 480 && ms < 560 && c[Channel::kSquash] > 120) landed = true;  // flat past the clip's own
    if (ms > 200 && ms < 500 && c[Channel::kLean] > 0) dragged = true;      // sliding left: the crown behind, right
    if (ms > 200 && ms < 520 && s.faceX16() > 0) lagged = true;            // and the face behind it
    TEST_ASSERT_TRUE(std::abs(s.faceX16()) <= 8 * 16 && std::abs(s.faceY16()) <= 8 * 16);
  });
  TEST_ASSERT_TRUE(tall && landed && dragged && lagged);
}

// Each rule off gives back the motion before it, exactly, the others on:
// settle off, the body's channels are the clips' (but the squash and the
// lean, which stretch and drag add to); stretch off, the squash is
// settle's alone; drag off, the lean is; face off, the face is where the
// body puts it; hands off, the hands are the clips'. All off, every channel
// is the clips'.
void test_each_motion_rule_off_gives_back_the_motion_before() {
  {
    Lively l;
    l.set("settle", false);
    play(l, 1600, [&](int ms, const rig::Channels& c) {
      for (Channel ch : {Channel::kLift, Channel::kX, Channel::kReach, Channel::kMelt, Channel::kGlass})
        TEST_ASSERT_EQUAL_INT(at(ms)[ch], c[ch]);
    });
  }
  {
    Lively l;
    l.set("stretch", false);
    play(l, 1600, [&](int, const rig::Channels& c) {
      TEST_ASSERT_EQUAL_INT(int(std::lround(num(l.settled[0].x))), c[Channel::kSquash]);
      TEST_ASSERT_TRUE(l.flat.x == F(0) && l.flat.v == F(0));
    });
  }
  {
    Lively l;
    l.set("drag", false);
    play(l, 1600, [&](int, const rig::Channels& c) {
      TEST_ASSERT_EQUAL_INT(int(std::lround(num(l.settled[1].x))), c[Channel::kLean]);
    });
  }
  {
    Lively l;
    l.set("face", false);
    play(l, 1600, [&](int, const rig::Channels&) { TEST_ASSERT_TRUE(!l.faceX16() && !l.faceY16()); });
  }
  {
    Lively l;
    l.set("hands", false);
    play(l, 1600, [&](int ms, const rig::Channels& c) {
      for (int side = 0; side < 2; ++side)
        for (auto p : {rig::HandPart::kX, rig::HandPart::kY, rig::HandPart::kSize})
          TEST_ASSERT_EQUAL_INT(at(ms)[rig::hand(side, p)], c[rig::hand(side, p)]);
    }, true);
  }
  {
    Lively l;
    TEST_ASSERT_TRUE(l.set("all", false));
    play(l, 1600, [&](int ms, const rig::Channels& c) {
      const rig::Channels want = at(ms);
      TEST_ASSERT_EQUAL_MEMORY(&want, &c, sizeof c);
      TEST_ASSERT_TRUE(!l.faceX16() && !l.faceY16());
    });
  }
  // By name, as dbg.motion sets them; a reset puts them back.
  Lively l;
  TEST_ASSERT_FALSE(l.set("wobble", false));
  TEST_ASSERT_TRUE(l.set("face", false) && !l.rule(Rule::kFace));
  l.reset();
  for (int i = 0; i < kRuleCount; ++i) TEST_ASSERT_TRUE(l.on[i]);
  GelFace face;
  TEST_ASSERT_TRUE(face.motionRule("drag", false) && !face.lively().rule(Rule::kDrag));
  TEST_ASSERT_FALSE(face.motionRule("nope", true));
}

// The springs settle: once the clips stop, no rule leaves a channel ringing
// or drifting. Within 1.5 s every channel is the clips' exactly, the face is
// where the body is, and so it stays.
void test_the_motion_layer_comes_to_rest() {
  for (bool desk : {false, true}) {
    Lively l;
    play(l, 2600, [&](int ms, const rig::Channels& c) {
      if (ms < 2500) return;
      const rig::Channels want = at(ms);
      TEST_ASSERT_EQUAL_MEMORY(&want, &c, sizeof c);
      TEST_ASSERT_TRUE(!l.faceX16() && !l.faceY16());
    }, desk);
    for (int i = 0; i < 400; ++i) {
      l.advance(16, at(5000), 0, 0, desk);
      const rig::Channels c = l.apply(at(5000)), want = at(5000);
      TEST_ASSERT_EQUAL_MEMORY(&want, &c, sizeof c);
    }
  }
}

// Hands follow: a hand arrives late and leaves late; one off the desk's keys
// starts there, at the paw's size, and one going back goes to them before
// the desk has it again (its size then none, so the desk draws it).
void test_hands_follow_and_change_owner_without_a_jump() {
  Lively l;
  bool late = false, leftLate = false, startedAtDesk = false;
  int lastX = 0, lastY = 0, lastSize = 0, most = 0;
  play(l, 2000, [&](int ms, const rig::Channels& c) {
    const int x = c[rig::hand(1, rig::HandPart::kX)], y = c[rig::hand(1, rig::HandPart::kY)],
              size = c[rig::hand(1, rig::HandPart::kSize)];
    if (size && !lastSize) startedAtDesk = std::abs(x - Lively::kDeskX) <= 8 && size > 600;  // its first frame out
    if (ms == 240 && x < 55) late = true;  // the clip has it at 60 by then
    if (ms == 1008 && size > handSize(1008)) leftLate = true;
    if (ms > 200 && size && lastSize) most = std::max({most, std::abs(x - lastX), std::abs(y - lastY)});
    lastX = x, lastY = y, lastSize = size;
  }, true);
  TEST_ASSERT_TRUE(startedAtDesk && late && leftLate);
  TEST_ASSERT_TRUE(most <= 16);  // px a frame at most: no jump
  TEST_ASSERT_EQUAL_INT(0, l.apply(at(2000))[rig::hand(1, rig::HandPart::kSize)]);  // the desk's again
}

// The mood gestures folded in: one idle move for each lasting mood, a rig
// clip idle-<mood> that ends where it starts, and each face plays its
// lasting mood's (the faces that settle into happy, happy's hop; the cross
// ones, the stomp). Idle, the face plays it as its acting deals it, about a
// second in.
// The turn settles like any body channel, and goes round the short way: a
// spin that ends a whole turn round (the high five's) carries on to rest
// where it began and never unwinds back through its back; with settle off
// it's the clip's own.
void test_a_spin_never_unwinds() {
  Lively l;
  rig::Channels target = rig::kRest;
  bool round = false;
  for (int ms = 16; ms <= 3000; ms += 16) {
    target[Channel::kTurn] = int16_t(ms <= 800 ? ms * 1000 / 800 : ms <= 1600 ? 1000 : 0);
    l.advance(16, target, 0, 0, false);
    const int turn = l.apply(target)[Channel::kTurn];
    if (ms > 800 && turn > 950) round = true;
    // Past 950 it never comes back below 900 (the far side, its back).
    if (round && ms > 1000) TEST_ASSERT_TRUE(turn < 100 || turn > 900);
  }
  TEST_ASSERT_TRUE(round);
  TEST_ASSERT_EQUAL_INT(0, l.apply(target)[Channel::kTurn]);  // at rest where it began
  l.set("settle", false);
  target[Channel::kTurn] = 420;
  l.advance(16, target, 0, 0, false);
  TEST_ASSERT_EQUAL_INT(420, l.apply(target)[Channel::kTurn]);
}

// Exactly half a turn off (a stroke as the back pose turns, which sends it
// from its back to its front) is as near either way: it turns, and ends there.
void test_half_a_turn_off_still_turns() {
  Lively l;
  rig::Channels target = rig::kRest;
  l.advance(16, target, 0, 0, false);
  target[Channel::kTurn] = Lively::kWholeTurn / 2;
  for (int ms = 16; ms <= 3000; ms += 16) l.advance(16, target, 0, 0, false);
  TEST_ASSERT_EQUAL_INT(Lively::kWholeTurn / 2, l.apply(target)[Channel::kTurn]);
}
// Come round the short way past the turn's limits (+1950 to -1900 is -2050,
// two turns and a little round), the spring starts from the limit, which is
// what draws, and never sits past it; it comes to rest at its target.
void test_the_turn_comes_round_within_its_limits() {
  Lively l;
  rig::Channels target = rig::kRest;
  target[Channel::kTurn] = 1950;
  l.advance(16, target, 0, 0, false);
  target[Channel::kTurn] = -1900;
  for (int ms = 16; ms <= 3000; ms += 16) {
    l.advance(16, target, 0, 0, false);
    const F x = l.settled[Lively::kSettledCount - 1].x;
    TEST_ASSERT_TRUE_MESSAGE(x >= F(-2000) && x <= F(2000), std::to_string(ms).c_str());
  }
  TEST_ASSERT_EQUAL_INT(-1900, l.apply(target)[Channel::kTurn]);
}
void test_the_seven_idle_moves() {
  const char* moods[] = {"calm", "happy", "focused", "proud", "cross", "sad", "lonely"};
  for (const char* m : moods) {
    char id[24];
    std::snprintf(id, sizeof id, "idle-%s", m);
    const rig::Clip* clip = rig::kRig.clip(id);
    TEST_ASSERT_NOT_NULL_MESSAGE(clip, id);
    TEST_ASSERT_TRUE_MESSAGE(clip->additive && !clip->loop && clip->ms >= 1000 && clip->ms <= 4000, id);
    for (const rig::Track& t : clip->tracks) TEST_ASSERT_EQUAL_INT_MESSAGE(0, clip->value(t, clip->ms), id);
  }
  const struct {
    int profile;
    const char* move;
  } faces[] = {{slime::kCalm, "idle-calm"},       {slime::kExcited, "idle-happy"},  {slime::kAffectionate, "idle-happy"},
               {slime::kCurious, "idle-focused"}, {slime::kProud, "idle-proud"},    {slime::kGrumpy, "idle-cross"},
               {slime::kAngry, "idle-cross"},     {slime::kWounded, "idle-sad"},    {slime::kLonely, "idle-lonely"}};
  for (const auto& f : faces) TEST_ASSERT_EQUAL_STRING(f.move, slime::kIdleMoves[f.profile]);
  linkkit::Rng rng;
  GelFace face;
  face.reset(0, rng);
  FaceSource s;
  FaceContext c;
  c.mood = s.mood = Mood::kProud;
  bool played = false;
  for (uint32_t t = 0; t <= 2000 && !played; t += 16) {
    face.sync(s, c, t);
    face.step(t, rng);
    played = face.cueing() && !std::strcmp(face.cueing()->id, "idle-proud");
  }
  TEST_ASSERT_TRUE(played);
}
