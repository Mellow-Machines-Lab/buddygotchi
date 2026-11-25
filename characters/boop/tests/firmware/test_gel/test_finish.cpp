// The gel's finishes (render/gel/finish.h): how big a successful finish is,
// which one plays for its size, that it plays once and cheers once, and that each moves
// smoothly and settles by its end.
#include <unity.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "render/gel/engine.h"
#include "render/gel/face.h"
#include "render/gel/painter.h"

using namespace render;
using namespace render::gel;

namespace {

constexpr Finish kBig[] = {Finish::kConfetti, Finish::kGoldRush};

int lengthMs(Finish f) { return F(finishRecipe(f).duration).integer(); }
int revealMs(Finish f) {
  const auto& r = finishRecipe(f);
  for (int i = 0; i < r.count; ++i)
    if (r.contacts[i].kind == kSuccess) return F(r.contacts[i].at).integer();
  return -1;
}

// An engine playing finish `variant` of a success over the working look,
// held as the board holds it.
std::unique_ptr<Engine> finishing(int variant, int mood = slime::kHappy) {
  auto e = std::make_unique<Engine>();
  e->setMood(mood);
  Facts working;
  working.base = SceneState::kWorking;
  e->setFacts(working);
  e->step(0);
  for (int t = 16; t <= 2000; t += 16) e->step(uint32_t(t));
  Request done;
  done.anim = SceneState::kTaskComplete, done.outcome = Outcome::kSuccess;
  done.variant = variant;
  TEST_ASSERT_TRUE(e->play(done));
  return e;
}

}  // namespace

// A finish's size pins the rule in render/gel/finish.h: by the tier its
// turn reached, whatever it's held (small short of a minute, medium to 5
// minutes, big from there); by its hold only with no turn; a sad mood's
// small whatever else.
void test_a_finish_is_sized_by_its_turn_or_else_its_hold() {
  const int happy = slime::kHappy;
  TEST_ASSERT_EQUAL_INT(1, kLongTier);
  TEST_ASSERT_EQUAL_INT(2, kBigTier);
  // With a turn, the work sizes it, however long it's held.
  for (int loops : {1, 2, 3}) {
    TEST_ASSERT_TRUE(finishSize(loops, 0, happy) == FinishSize::kSmall);
    TEST_ASSERT_TRUE(finishSize(loops, 1, happy) == FinishSize::kMedium);
    TEST_ASSERT_TRUE(finishSize(loops, 2, happy) == FinishSize::kBig);
    TEST_ASSERT_TRUE(finishSize(loops, 3, happy) == FinishSize::kBig);
  }
  // With none, the hold does.
  TEST_ASSERT_TRUE(finishSize(1, kNoTurn, happy) == FinishSize::kSmall);
  TEST_ASSERT_TRUE(finishSize(2, kNoTurn, happy) == FinishSize::kMedium);
  TEST_ASSERT_TRUE(finishSize(3, kNoTurn, happy) == FinishSize::kBig);
  TEST_ASSERT_TRUE(finishSize(6, kNoTurn, happy) == FinishSize::kBig);
  // A sad success is small, a long turn's or held three times.
  for (int sad : {slime::kSad, slime::kWounded}) {
    TEST_ASSERT_TRUE(finishSize(3, 3, sad) == FinishSize::kSmall);
    TEST_ASSERT_TRUE(finishSize(2, kNoTurn, sad) == FinishSize::kSmall);
  }
}

// The face picks a successful finish by its size, as a pure pick: Confetti
// for a medium one, Gold Rush for a big one, whatever the mood; a finish a
// size above small plays once whatever its loops, and Little Win plays its
// loops; a failure keeps its card's takes.
void test_the_face_picks_a_finish_and_plays_it_once() {
  linkkit::Rng rng;
  GelFace f;
  f.reset(0, rng);
  const SceneState done = SceneState::kTaskComplete;
  const uint32_t before = f.engine().random.state;
  TEST_ASSERT_EQUAL_UINT8(finishVariant(Finish::kConfetti),
                          f.pick(done, Mood::kHappy, 0, Outcome::kSuccess, rng, 2, 1));
  for (Mood mood : {Mood::kHappy, Mood::kExcited, Mood::kProud, Mood::kCalm})
    for (int turn : {2, 3})
      TEST_ASSERT_EQUAL_UINT8(finishVariant(Finish::kGoldRush), f.pick(done, mood, 0, Outcome::kSuccess, rng, 1, turn));
  const uint8_t big = finishVariant(Finish::kGoldRush);
  TEST_ASSERT_EQUAL_UINT32(before, f.engine().random.state);
  f.started(done, Mood::kExcited, big, Outcome::kSuccess);
  TEST_ASSERT_EQUAL_UINT32(before, f.engine().random.state);  // no bag deals a finish
  // Small deals Little Win's takes from the bag.
  TEST_ASSERT_TRUE(f.pick(done, Mood::kHappy, 0, Outcome::kSuccess, rng, 3, 0) < kFinishBase);
  TEST_ASSERT_TRUE(f.pick(done, Mood::kSad, 0, Outcome::kSuccess, rng, 3, 3) < kFinishBase);
  TEST_ASSERT_TRUE(f.pick(done, Mood::kHappy, 0, Outcome::kFailure, rng, 3, 3) < 3);
  for (Finish fin : kBig) {
    TEST_ASSERT_EQUAL_INT(1, f.plays(done, uint8_t(finishVariant(fin)), 4));
    TEST_ASSERT_EQUAL_UINT32(uint32_t(lengthMs(fin)), f.loopMs(Mood::kHappy, done, finishVariant(fin)));
    // A `say` starts at its reveal, as a card's does.
    TEST_ASSERT_EQUAL_UINT32(uint32_t(revealMs(fin) + 70), f.voiceMs(Mood::kHappy, done, finishVariant(fin)));
  }
  TEST_ASSERT_EQUAL_INT(3, f.plays(done, 0, 3));
}

// A finish a size above small lasts 3.6 to 5 s, cheers once at its reveal
// (never the small one's fanfare) and bounces as it lands; Little Win's
// reveal plays the fanfare.
void test_a_big_finish_cheers_once_and_bounces() {
  for (Finish fin : kBig) {
    TEST_ASSERT_TRUE(lengthMs(fin) >= 3600 && lengthMs(fin) <= 5000);
    TEST_ASSERT_TRUE(revealMs(fin) > 0);
    auto e = finishing(finishVariant(fin));
    int cheers = 0, bounces = 0, fanfares = 0;
    for (int t = 2016; t <= 2000 + lengthMs(fin) + 1000; t += 16) {
      e->step(uint32_t(t));
      for (const auto& cue : e->cues) {
        cheers += !std::strcmp(cue.recipe, "cheer");
        bounces += !std::strcmp(cue.recipe, "bounce");
        fanfares += !std::strcmp(cue.recipe, "complete");
      }
    }
    TEST_ASSERT_EQUAL_INT(1, cheers);
    TEST_ASSERT_TRUE(bounces >= 1);
    TEST_ASSERT_EQUAL_INT(0, fanfares);
  }
  auto e = finishing(0);
  int fanfares = 0, cheers = 0;
  for (int t = 2016; t <= 6000; t += 16) {
    e->step(uint32_t(t));
    for (const auto& cue : e->cues)
      fanfares += !std::strcmp(cue.recipe, "complete"), cheers += !std::strcmp(cue.recipe, "cheer");
  }
  TEST_ASSERT_EQUAL_INT(1, fanfares);
  TEST_ASSERT_EQUAL_INT(0, cheers);
}

// A finish that takes over the screen puts the desk away while it plays;
// Little Win and the confetti keep it; a success never shows a card.
void test_a_takeover_puts_the_desk_away() {
  for (Finish fin : kBig) {
    auto e = finishing(finishVariant(fin));
    TEST_ASSERT_TRUE(e->scenes.desk.x > q(.9));
    for (int t = 2016; t <= 3200; t += 16) e->step(uint32_t(t));
    TEST_ASSERT_TRUE(e->scenes.finishShow().on && e->scenes.finishShow().finish == fin);
    TEST_ASSERT_TRUE(takesOver(fin) ? e->scenes.desk.x < q(.05) : e->scenes.desk.x > q(.9));
  }
}

// Every finish moves smoothly, under 16 px and a tenth of its size a
// frame, and is back at rest by its end.
void test_every_finish_moves_smoothly_and_settles() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  for (Finish fin : {Finish::kLittle, Finish::kConfetti, Finish::kGoldRush}) {
    const int end = fin == Finish::kLittle ? 3200 : lengthMs(fin),
              reveal = fin == Finish::kLittle ? 680 : revealMs(fin);
    FinishPose last = finishPose(s, fin, 0, reveal);
    for (int t = 16; t <= end; t += 16) {
      const FinishPose p = finishPose(s, fin, t, reveal);
      char why[96];
      std::snprintf(why, sizeof why, "finish %d at %d ms: dy %d -> %d, scale %d -> %d", int(fin), t, last.dy16, p.dy16,
                    last.scale, p.scale);
      TEST_ASSERT_TRUE_MESSAGE(std::abs(p.dy16 - last.dy16) <= 16 * 16 && std::abs(p.dx16 - last.dx16) <= 16 * 16, why);
      TEST_ASSERT_TRUE_MESSAGE(std::abs(p.scale - last.scale) <= 410, why);
      last = p;
    }
    const FinishPose rest = finishPose(s, fin, end, reveal);
    char why[96];
    std::snprintf(why, sizeof why, "finish %d at rest: dy %d scale %d squash %d lean %d", int(fin), rest.dy16,
                  rest.scale, rest.squash, rest.lean);
    TEST_ASSERT_TRUE_MESSAGE(std::abs(rest.dy16) < 16 && std::abs(rest.dx16) < 16, why);
    TEST_ASSERT_TRUE_MESSAGE(std::abs(rest.scale - 4096) < 41 && std::abs(rest.squash) < 82 && std::abs(rest.lean) < 82,
                             why);
  }
}

// Only Gold Rush draws behind the body, so only it erases the frame whole
// before it; Gold Rush's flood, once it reaches every
// corner above the lane, covers those rows, and they aren't erased first.
void test_only_what_draws_behind_erases_first() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  for (Finish fin : kBig) TEST_ASSERT_EQUAL(fin == Finish::kGoldRush, drawsBehind(fin));
  TEST_ASSERT_FALSE(drawsBehind(Finish::kLittle));
  TEST_ASSERT_EQUAL_INT(0, finishCovers(s, Finish::kGoldRush, 400));
  TEST_ASSERT_EQUAL_INT(410 * 4 / 5, finishCovers(s, Finish::kGoldRush, 2000));
  TEST_ASSERT_EQUAL_INT(0, finishCovers(s, Finish::kGoldRush, 4300));
  TEST_ASSERT_EQUAL_INT(0, finishCovers(s, Finish::kConfetti, 2000));
}
// Gold Rush floods the screen above the lane with gold, and drains it
// again; Little Win draws its trophy in gold over its head.
void test_gold_rush_floods_and_little_win_shows_its_trophy() {
  constexpr int kW = 502, kH = 410;
  std::vector<uint16_t> px(kW * kH);
  Surface s{kW, kH, px.data()};
  // The trophy's golds, and the flood's at 70% of them (at night, half that).
  const uint16_t golds[] = {rgb565(255, 201, 60), rgb565(255, 176, 32), rgb565(178, 140, 42), rgb565(178, 123, 22)};
  auto golden = [&](int y0, int y1) {
    int n = 0;
    for (int y = y0; y < y1; ++y)
      for (int x = 0; x < kW; ++x)
        for (uint16_t g : golds) n += px[size_t(y) * kW + x] == g;
    return n;
  };
  auto e = finishing(finishVariant(Finish::kGoldRush));
  for (int t = 2016; t <= 3500; t += 16) e->step(uint32_t(t));
  s.invalidate(), s.clear();
  paint(s, *e);
  TEST_ASSERT_TRUE(golden(0, kH * 4 / 5) > kW * kH / 3);
  TEST_ASSERT_EQUAL_INT(0, golden(kH * 4 / 5, kH));  // the lane is left alone
  for (int t = 3516; t <= 2000 + lengthMs(Finish::kGoldRush); t += 16) e->step(uint32_t(t));
  s.invalidate(), s.clear();
  paint(s, *e);
  TEST_ASSERT_TRUE(golden(0, kH) < 2000);
  auto little = finishing(0);
  for (int t = 2016; t <= 2000 + 680 + 900; t += 16) little->step(uint32_t(t));
  s.invalidate(), s.clear();
  rig::Anchors at;
  paint(s, *little, false, 0, 0, &at);
  TEST_ASSERT_TRUE(golden(0, at.crown.y / 16) > 300);
}
