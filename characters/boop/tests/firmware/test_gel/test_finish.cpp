// The gel's finishes (render/gel/finish.h): how big a successful finish is,
// which one plays, that it plays once and cheers once, and that each moves
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

constexpr Finish kBig[] = {Finish::kConfetti, Finish::kGoldRush, Finish::kFireworks,
                           Finish::kMegaBoop, Finish::kParade,   Finish::kSpotlight};

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
  done.anim = SceneState::kTaskComplete, done.outcome = Outcome::kSuccess, done.hasId = true, done.id = "done";
  done.hold = true, done.variant = variant;
  TEST_ASSERT_TRUE(e->oneShot(done));
  return e;
}

}  // namespace

// A finish's size pins the rule in render/gel/finish.h: by the tier its
// turn reached, whatever it's held (small short of a minute, medium to 5
// minutes, big to 10, biggest from there); by its hold only with no turn;
// a sad mood's small whatever else.
void test_a_finish_is_sized_by_its_turn_or_else_its_hold() {
  const int happy = slime::kHappy;
  TEST_ASSERT_EQUAL_INT(2, kLongTier);
  TEST_ASSERT_EQUAL_INT(4, kBigTier);
  TEST_ASSERT_EQUAL_INT(5, kBiggestTier);
  // With a turn, the work sizes it, however long it's held.
  for (int loops : {1, 2, 3, 4}) {
    TEST_ASSERT_TRUE(finishSize(loops, 0, happy) == FinishSize::kSmall);
    TEST_ASSERT_TRUE(finishSize(loops, 1, happy) == FinishSize::kSmall);
    TEST_ASSERT_TRUE(finishSize(loops, 2, happy) == FinishSize::kMedium);
    TEST_ASSERT_TRUE(finishSize(loops, 3, happy) == FinishSize::kMedium);
    TEST_ASSERT_TRUE(finishSize(loops, 4, happy) == FinishSize::kBig);
    TEST_ASSERT_TRUE(finishSize(loops, 5, happy) == FinishSize::kBiggest);
  }
  // With none, the hold does.
  TEST_ASSERT_TRUE(finishSize(1, kNoTurn, happy) == FinishSize::kSmall);
  TEST_ASSERT_TRUE(finishSize(2, kNoTurn, happy) == FinishSize::kMedium);
  TEST_ASSERT_TRUE(finishSize(3, kNoTurn, happy) == FinishSize::kBig);
  TEST_ASSERT_TRUE(finishSize(4, kNoTurn, happy) == FinishSize::kBiggest);
  TEST_ASSERT_TRUE(finishSize(6, kNoTurn, happy) == FinishSize::kBiggest);
  // A sad success is small, a camp's or held four times.
  for (int sad : {slime::kDisappointed, slime::kSad, slime::kCrying, slime::kWhiny, slime::kWounded}) {
    TEST_ASSERT_TRUE(finishSize(4, 5, sad) == FinishSize::kSmall);
    TEST_ASSERT_TRUE(finishSize(2, kNoTurn, sad) == FinishSize::kSmall);
  }
}

// Each mood takes turns between its two big finishes, never the one that
// played last first; the Mac's choice (from 1) wins; a proud board takes the
// spotlight whatever the reaction's mood.
void test_each_mood_takes_turns_between_its_big_finishes() {
  struct Case {
    int mood;
    Finish first, second;
  };
  const Case cases[] = {
      {slime::kExcited, Finish::kFireworks, Finish::kGoldRush}, {slime::kHappy, Finish::kGoldRush, Finish::kParade},
      {slime::kPleased, Finish::kGoldRush, Finish::kParade},    {slime::kAmused, Finish::kParade, Finish::kFireworks},
      {slime::kProud, Finish::kSpotlight, Finish::kGoldRush},   {slime::kCalm, Finish::kGoldRush, Finish::kFireworks},
      {slime::kRelieved, Finish::kGoldRush, Finish::kFireworks}};
  for (const Case& c : cases) {
    TEST_ASSERT_TRUE(bigFinish(c.mood, slime::kCalm, 0, Finish::kLittle) == c.first);
    TEST_ASSERT_TRUE(bigFinish(c.mood, slime::kCalm, 0, c.first) == c.second);
    TEST_ASSERT_TRUE(bigFinish(c.mood, slime::kCalm, 0, c.second) == c.first);
    TEST_ASSERT_TRUE(bigFinish(c.mood, slime::kCalm, 1, c.first) == c.first);
    TEST_ASSERT_TRUE(bigFinish(c.mood, slime::kCalm, 2, Finish::kLittle) == c.second);
    TEST_ASSERT_TRUE(bigFinish(c.mood, slime::kProud, 0, Finish::kLittle) == Finish::kSpotlight);
  }
  // The Mac's choice past the two is no choice.
  TEST_ASSERT_TRUE(bigFinish(slime::kHappy, slime::kCalm, 3, Finish::kLittle) == Finish::kGoldRush);
}

// The face picks a successful finish by its size, as a pure pick; the one it
// played counts as last only once it starts; a finish a size above small
// plays once whatever its loops, and Little Win plays its loops; a failure
// keeps its card's takes.
void test_the_face_picks_a_finish_and_plays_it_once() {
  linkkit::Rng rng;
  GelFace f;
  f.reset(0, rng);
  const SceneState done = SceneState::kTaskComplete;
  const uint32_t before = f.engine().random.state;
  TEST_ASSERT_EQUAL_UINT8(finishVariant(Finish::kConfetti),
                          f.pick(done, Mood::kHappy, 0, Outcome::kSuccess, StartCtx::kNone, rng, 2, 3));
  TEST_ASSERT_EQUAL_UINT8(finishVariant(Finish::kMegaBoop),
                          f.pick(done, Mood::kHappy, 0, Outcome::kSuccess, StartCtx::kNone, rng, 1, 5));
  const uint8_t big = f.pick(done, Mood::kExcited, 0, Outcome::kSuccess, StartCtx::kNone, rng, 1, 4);
  TEST_ASSERT_EQUAL_UINT8(finishVariant(Finish::kFireworks), big);
  TEST_ASSERT_EQUAL_UINT8(big, f.pick(done, Mood::kExcited, 0, Outcome::kSuccess, StartCtx::kNone, rng, 1, 4));
  TEST_ASSERT_EQUAL_UINT32(before, f.engine().random.state);
  f.started(done, Mood::kExcited, big, Outcome::kSuccess, StartCtx::kNone);
  TEST_ASSERT_EQUAL_UINT32(before, f.engine().random.state);  // no bag deals a finish
  TEST_ASSERT_EQUAL_UINT8(finishVariant(Finish::kGoldRush),
                          f.pick(done, Mood::kExcited, 0, Outcome::kSuccess, StartCtx::kNone, rng, 1, 4));
  // Small deals Little Win's takes from the bag.
  TEST_ASSERT_TRUE(f.pick(done, Mood::kHappy, 0, Outcome::kSuccess, StartCtx::kNone, rng, 4, 1) < kFinishBase);
  TEST_ASSERT_TRUE(f.pick(done, Mood::kSad, 0, Outcome::kSuccess, StartCtx::kNone, rng, 4, 5) < kFinishBase);
  TEST_ASSERT_TRUE(f.pick(done, Mood::kHappy, 0, Outcome::kFailure, StartCtx::kNone, rng, 4, 5) < 3);
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
    TEST_ASSERT_TRUE(e->scenes.visible(Scenes::kResultProp, e->timeMs()) == F(0));
  }
}

// Every finish moves smoothly, under 16 px and a tenth of its size a frame
// (but the parade's split and merge, where its little ones take its place
// and give it back), and is back at rest by its end.
void test_every_finish_moves_smoothly_and_settles() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  for (Finish fin : {Finish::kLittle, Finish::kConfetti, Finish::kGoldRush, Finish::kFireworks, Finish::kMegaBoop,
                     Finish::kParade, Finish::kSpotlight}) {
    const int end = fin == Finish::kLittle ? 3200 : lengthMs(fin),
              reveal = fin == Finish::kLittle ? 680 : revealMs(fin);
    FinishPose last = finishPose(s, fin, 0, reveal);
    for (int t = 16; t <= end; t += 16) {
      const FinishPose p = finishPose(s, fin, t, reveal);
      if (!p.minis && !last.minis) {
        char why[96];
        std::snprintf(why, sizeof why, "finish %d at %d ms: dy %d -> %d, scale %d -> %d", int(fin), t, last.dy16,
                      p.dy16, last.scale, p.scale);
        TEST_ASSERT_TRUE_MESSAGE(std::abs(p.dy16 - last.dy16) <= 16 * 16 && std::abs(p.dx16 - last.dx16) <= 16 * 16,
                                 why);
        TEST_ASSERT_TRUE_MESSAGE(std::abs(p.scale - last.scale) <= 410, why);
      }
      last = p;
    }
    const FinishPose rest = finishPose(s, fin, end, reveal);
    char why[96];
    std::snprintf(why, sizeof why, "finish %d at rest: dy %d scale %d squash %d lean %d", int(fin), rest.dy16,
                  rest.scale, rest.squash, rest.lean);
    TEST_ASSERT_TRUE_MESSAGE(!rest.minis && !rest.starEyes, why);
    TEST_ASSERT_TRUE_MESSAGE(std::abs(rest.dy16) < 16 && std::abs(rest.dx16) < 16, why);
    TEST_ASSERT_TRUE_MESSAGE(std::abs(rest.scale - 4096) < 41 && std::abs(rest.squash) < 82 && std::abs(rest.lean) < 82,
                             why);
  }
  // The parade's little ones stand side by side, inside the screen.
  FinishPose minis[kParadeMinis];
  TEST_ASSERT_EQUAL_INT(kParadeMinis, finishMinis(s, 2000, minis));
  for (int i = 1; i < kParadeMinis; ++i) TEST_ASSERT_TRUE(minis[i].dx16 > minis[i - 1].dx16);
  TEST_ASSERT_TRUE(minis[0].dx16 > -200 * 16 && minis[kParadeMinis - 1].dx16 < 200 * 16);
  TEST_ASSERT_EQUAL_INT(0, finishMinis(s, 400, minis));
}

// Only Gold Rush and the spotlight draw behind the body, so only they erase
// the frame whole before it; Gold Rush's flood, once it reaches every
// corner above the lane, covers those rows, and they aren't erased first.
void test_only_what_draws_behind_erases_first() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  for (Finish fin : kBig) TEST_ASSERT_EQUAL(fin == Finish::kGoldRush || fin == Finish::kSpotlight, drawsBehind(fin));
  TEST_ASSERT_FALSE(drawsBehind(Finish::kLittle));
  TEST_ASSERT_EQUAL_INT(0, finishCovers(s, Finish::kGoldRush, 400));
  TEST_ASSERT_EQUAL_INT(410 * 4 / 5, finishCovers(s, Finish::kGoldRush, 2000));
  TEST_ASSERT_EQUAL_INT(0, finishCovers(s, Finish::kGoldRush, 4300));
  TEST_ASSERT_EQUAL_INT(0, finishCovers(s, Finish::kSpotlight, 2000));
}
// Gold Rush floods the screen above the lane with gold, and drains it
// again; Little Win draws its trophy in gold over its head.
void test_gold_rush_floods_and_little_win_shows_its_trophy() {
  constexpr int kW = 502, kH = 410;
  std::vector<uint16_t> px(kW * kH);
  Surface s{kW, kH, px.data()};
  const uint16_t gold = rgb565(255, 201, 60), deep = rgb565(255, 176, 32);
  auto golden = [&](int y0, int y1) {
    int n = 0;
    for (int y = y0; y < y1; ++y)
      for (int x = 0; x < kW; ++x) n += px[size_t(y) * kW + x] == gold || px[size_t(y) * kW + x] == deep;
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
