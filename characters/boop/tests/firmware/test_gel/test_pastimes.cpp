// The gel's pastimes (render/gel/pastimes.h): the catalog and each one's
// clip, what each draws, how the face deals them by tier after a rest, and
// the kit the tiers put out.
#include <unity.h>

#include <cstring>
#include <memory>
#include <vector>

#include "app/behaviour.h"
#include "render/canvas.h"
#include "render/gel/face.h"
#include "render/gel/pastimes.h"
#include "render/tags.h"
#include "rig_tables.h"  // the staged pack's (characters/charactergen.py)

using namespace render;
using namespace render::gel;

namespace {

// A board with the gel, in a look with these tags, the Mac's state again
// every 10 s as it sends it.
struct Board {
  linkkit::Rng rng;
  app::Behaviour b{std::make_unique<GelFace>()};
  app::Model m;
  uint32_t t = 0;
  Board(SceneState look, uint32_t when) {
    b.reset(0, rng);
    m.mood = Mood::kHappy;
    m.base = look == SceneState::kNeedsYou ? SceneState::kWorking : look;
    m.act = SceneState::kTerminal;
    m.attn = look == SceneState::kNeedsYou;
    if (m.attn) std::strcpy(m.agent, "claude"), std::strcpy(m.project, "api"), m.attnId = 3;
    m.when = reached(when);
    b.onState(m, 0);
  }
  GelFace& face() { return static_cast<GelFace&>(b.face()); }
  void tags(uint32_t when) {
    m.when = reached(when);
    b.onState(m, t);
  }
  // On to `until`, calling `each` at every step.
  template <typename Each>
  void to(uint32_t until, Each each) {
    for (; t + 16 <= until;) {
      t += 16;
      if (t % 10000 < 16) b.onState(m, t);
      b.advance(t, rng);
      each();
    }
  }
  void to(uint32_t until) {
    to(until, [] {});
  }
};

uint32_t tiers(int n) { return n ? reached(tierBit(n)) : 0; }

}  // namespace

// Pins the catalog: each pastime's clip is in the pack's rig and plays
// once, a few seconds; working's and idle's each need a tier and have at
// least three for every one of the five, and needs you's and asleep's
// wait: a wave from 30 s, a tap on the glass from 2 minutes, the watch
// from 5 and nodding off from 10; asleep rolls over from a minute, dreams
// of sheep from 2 and blows a snore bubble from 4.
void test_every_pastime_has_its_clip_and_its_turn() {
  int count[2][6] = {};
  for (int i = 0; i < kPastimeCount; ++i) {
    const PastimeInfo& p = kPastimes[i];
    TEST_ASSERT_EQUAL_INT(i + 1, int(p.id));
    TEST_ASSERT_EQUAL_PTR(&p, &info(p.id));
    const rig::Clip* clip = rig::kRig.clip(p.clip);
    TEST_ASSERT_NOT_NULL_MESSAGE(clip, p.clip);
    TEST_ASSERT_FALSE(clip->loop);
    TEST_ASSERT_TRUE(clip->additive);
    TEST_ASSERT_TRUE_MESSAGE(clip->ms >= 2000 && clip->ms <= 6500, p.clip);
    if (p.look == SceneState::kWorking || p.look == SceneState::kIdle) {
      TEST_ASSERT_TRUE(p.tier >= 1 && p.tier <= 5);
      TEST_ASSERT_EQUAL_INT(0, p.afterS);
      ++count[p.look == SceneState::kIdle][p.tier];
    } else {
      TEST_ASSERT_TRUE(p.look == SceneState::kNeedsYou || p.look == SceneState::kAsleep);
      TEST_ASSERT_EQUAL_INT(0, p.tier);
    }
  }
  for (int n = 1; n <= 5; ++n) TEST_ASSERT_TRUE(count[0][n] >= 3 && count[1][n] >= 3);
  TEST_ASSERT_EQUAL_INT(30, info(Pastime::kWave).afterS);
  TEST_ASSERT_EQUAL_INT(120, info(Pastime::kTap).afterS);
  TEST_ASSERT_EQUAL_INT(300, info(Pastime::kWatch).afterS);
  TEST_ASSERT_EQUAL_INT(600, info(Pastime::kDrowsy).afterS);
  TEST_ASSERT_EQUAL_INT(60, info(Pastime::kRollOver).afterS);
  TEST_ASSERT_EQUAL_INT(120, info(Pastime::kSheep).afterS);
  TEST_ASSERT_EQUAL_INT(240, info(Pastime::kSnoreBubble).afterS);
  // The tiers: the Mac sends the last reached, and the board takes the
  // ones below it as on.
  for (int n = 1; n <= 5; ++n) {
    char name[8] = "tier0";
    name[4] = char('0' + n);
    TEST_ASSERT_EQUAL_UINT32(tagBit(name), tierBit(n));
    TEST_ASSERT_EQUAL_INT(n, tierOf(reached(tierBit(n))));
  }
  TEST_ASSERT_EQUAL_UINT32(tierBit(1) | tierBit(2) | tierBit(3), reached(tierBit(3)));
  TEST_ASSERT_EQUAL_UINT32(tagBit("day"), reached(tagBit("day")));
  TEST_ASSERT_EQUAL_INT(0, tierOf(tagBit("night")));
}

// Each pastime moves the body and draws in time with it, above the lane,
// and is over at its clip's end: nothing of it shows after.
void test_each_pastime_draws_and_ends() {
  std::vector<uint16_t> before(502 * 410), during(before.size()), after(before.size());
  std::vector<uint8_t> canvas(size_t(kWidth) * kHeight);
  Canvas c{canvas.data()};
  for (const PastimeInfo& p : kPastimes) {
    const bool tiered = p.look == SceneState::kWorking || p.look == SceneState::kIdle;
    Board board(p.look, tagBit("day") | (tiered ? tierBit(5) : 0));
    GelFace& face = board.face();
    auto draw = [&](std::vector<uint16_t>& px) {
      Surface s{502, 410, px.data()};
      std::fill(px.begin(), px.end(), 0);
      face.draw(c, &s, face.show(board.t, false, 0), board.t, nullptr, SignShow{}, Strip{}, false);
    };
    board.to(3008);
    draw(before);
    face.playPastime(p.id, board.t);
    const uint32_t start = board.t, ms = rig::kRig.clip(p.clip)->ms;
    board.to(start + ms / 2);
    TEST_ASSERT_EQUAL_INT_MESSAGE(int(p.id), int(face.pastimes(board.t).playing), p.clip);
    TEST_ASSERT_EQUAL_INT_MESSAGE(255, face.pastimes(board.t).fade, p.clip);
    draw(during);
    int changed = 0;
    for (size_t i = 0; i < before.size(); ++i) changed += before[i] != during[i];
    TEST_ASSERT_TRUE_MESSAGE(changed > 500, p.clip);
    // The lane, the bottom fifth, is the host's.
    for (size_t i = size_t(502) * (410 * 4 / 5); i < before.size(); ++i)
      TEST_ASSERT_EQUAL_HEX16_MESSAGE(before[i], during[i], p.clip);
    board.to(start + ms + 16);
    TEST_ASSERT_EQUAL_INT_MESSAGE(int(Pastime::kNone), int(face.pastimes(board.t).playing), p.clip);
  }
}

// Pins kRestMinMs, kRestMaxMs and kNewestPct: at work with tier2 on for
// a quarter of an hour, the face deals only working pastimes of tier1 and tier2,
// one at a time, never the same twice running, each after a rest of 4 to
// 10 s (the look's first too), the newest tier's about 60% of the time.
// With no tier, none.
void test_pastimes_are_dealt_by_tier_after_a_rest() {
  Board board(SceneState::kWorking, tagBit("day") | tierBit(2));
  GelFace& face = board.face();
  Pastime playing = Pastime::kNone, last = Pastime::kNone;
  uint32_t ended = 0;
  int dealt = 0, newest = 0;
  board.to(15 * 60 * 1000, [&] {
    const Pastime now = face.pastimes(board.t).playing;
    if (now == playing) return;
    if (now != Pastime::kNone) {
      const PastimeInfo& p = info(now);
      TEST_ASSERT_TRUE(p.look == SceneState::kWorking && p.tier <= 2);
      TEST_ASSERT_TRUE(now != last);
      const uint32_t rest = board.t - ended;
      TEST_ASSERT_TRUE(rest >= kRestMinMs && rest <= kRestMaxMs + 32);
      ++dealt, newest += p.tier == 2, last = now;
    } else {
      ended = board.t;
    }
    playing = now;
  });
  TEST_ASSERT_TRUE(dealt > 50);
  TEST_ASSERT_INT_WITHIN(15, kNewestPct, newest * 100 / dealt);
  // No tier, no pastime: at work or idle.
  for (SceneState look : {SceneState::kWorking, SceneState::kIdle}) {
    Board none(look, tagBit("day"));
    none.to(120000, [&] { TEST_ASSERT_EQUAL_INT(int(Pastime::kNone), int(none.face().pastimes(none.t).playing)); });
  }
  // In the morning, no sip or refill: its coffee is in its hand.
  Board morning(SceneState::kWorking, tagBit("morning") | tierBit(4));
  morning.to(5 * 60 * 1000, [&] {
    const Pastime now = morning.face().pastimes(morning.t).playing;
    TEST_ASSERT_TRUE(now != Pastime::kSip && now != Pastime::kRefill);
  });
  // While something needs you, only the wave before 2 minutes.
  Board asking(SceneState::kNeedsYou, tagBit("day"));
  asking.to(110000, [&] {
    const Pastime now = asking.face().pastimes(asking.t).playing;
    TEST_ASSERT_TRUE(now == Pastime::kNone || (now == Pastime::kWave && asking.t >= 30000));
  });
}

// Pins kTuneEveryMs, kTuneGapMs and kTuneNoteMs: with the headphones on, a
// note floats up from the left cup, then kTuneGapMs later from the right,
// each up for kTuneNoteMs, a pair every kTuneEveryMs, and a rest between
// pairs when none is; and none while bopping, whose notes are its own.
void test_the_headphones_play_a_tune() {
  TEST_ASSERT_EQUAL_INT(0, tuneNoteAge(0, 0));
  TEST_ASSERT_EQUAL_INT(-1, tuneNoteAge(0, 1));
  TEST_ASSERT_EQUAL_INT(0, tuneNoteAge(kTuneGapMs, 1));
  TEST_ASSERT_EQUAL_INT(int(kTuneNoteMs - 1), tuneNoteAge(kTuneNoteMs - 1, 0));
  TEST_ASSERT_EQUAL_INT(-1, tuneNoteAge(kTuneNoteMs, 0));
  TEST_ASSERT_EQUAL_INT(-1, tuneNoteAge(kTuneGapMs + kTuneNoteMs, 1));
  TEST_ASSERT_EQUAL_INT(100, tuneNoteAge(5 * kTuneEveryMs + 100, 0));
  TEST_ASSERT_TRUE(kTuneGapMs + kTuneNoteMs < kTuneEveryMs);  // a rest between pairs

  rig::Anchors at;
  at.crown = {251 * 16, 100 * 16}, at.brimL = {160 * 16, 140 * 16}, at.brimR = {342 * 16, 140 * 16};
  at.eyeL = {178 * 16, 237 * 16}, at.eyeR = {324 * 16, 237 * 16};
  auto above = [&](uint32_t t, Pastime playing) {
    std::vector<uint16_t> px(502 * 410, 0);
    Surface s{502, 410, px.data()};
    PastimeShow show;
    show.t = t, show.headphones = 255, show.playing = playing;
    paintWorn(s, show, at);
    // Only the notes go out past the band's ends, above the cups.
    int lit = 0;
    for (int y = 60; y < 150; ++y)
      for (int x = 0; x < 502; ++x) lit += (x < 90 || x > 412) && px[size_t(y) * 502 + size_t(x)];
    return lit;
  };
  const uint32_t rest = kTuneGapMs + kTuneNoteMs + 100, both = kTuneGapMs + 500;
  TEST_ASSERT_EQUAL_INT(0, above(rest, Pastime::kNone));
  TEST_ASSERT_TRUE(above(both, Pastime::kNone) > 20);
  TEST_ASSERT_EQUAL_INT(0, above(both, Pastime::kBop));
}

// Pins the kit: at work a mug from tier1, headphones from tier3 and a
// sweatband from tier4 (none while it wears a hat), and from tier5 the
// camp, with a mug more on the stack every kMugEveryMs up to kMostMugs;
// idle, a plant from tier3 that grows to tier5. No mug in the morning,
// when its coffee is in its hand; none while something needs you.
void test_the_kit_follows_the_tiers() {
  Board board(SceneState::kWorking, tagBit("day"));
  GelFace& face = board.face();
  auto kit = [&](int tier, uint32_t more = 0) {
    board.tags(tagBit("day") | more | tiers(tier));
    board.to(board.t + rig::kFadeMs + 32);
    return face.pastimes(board.t);
  };
  PastimeShow s = kit(0);
  TEST_ASSERT_TRUE(!s.mug && !s.headphones && !s.sweatband && !s.camp && !s.plant);
  s = kit(1);
  TEST_ASSERT_TRUE(s.mug == 255 && !s.headphones && !s.sweatband && !s.camp);
  s = kit(3);
  TEST_ASSERT_TRUE(s.mug && s.headphones && !s.sweatband);
  s = kit(4);
  TEST_ASSERT_TRUE(s.headphones && s.sweatband && !s.camp);
  s = kit(5);
  TEST_ASSERT_TRUE(s.camp && s.mug);
  TEST_ASSERT_EQUAL_INT(1, s.mugs);
  TEST_ASSERT_EQUAL_INT(2, face.pastimes(board.t + kMugEveryMs).mugs);
  TEST_ASSERT_EQUAL_INT(kMostMugs, face.pastimes(board.t + 10 * kMugEveryMs).mugs);
  s = kit(5, tagBit("night"));  // the nightcap wins the head
  TEST_ASSERT_TRUE(s.camp && !s.headphones && !s.sweatband);
  s = kit(3, tagBit("morning"));  // the morning's coffee is in its hand
  TEST_ASSERT_TRUE(!s.mug && s.headphones);
  board.m.attn = true, board.m.attnId = 4;
  s = kit(5);
  TEST_ASSERT_TRUE(!s.mug && !s.headphones && !s.camp);
  board.m.attn = false, board.m.base = SceneState::kIdle;
  for (int tier : {2, 3, 4, 5}) {
    s = kit(tier);
    TEST_ASSERT_TRUE(!s.mug && !s.camp);
    TEST_ASSERT_EQUAL_INT(tier >= 3 ? 255 : 0, s.plant);
    if (tier >= 3) TEST_ASSERT_EQUAL_INT(tier - 2, s.grown);
  }
}
