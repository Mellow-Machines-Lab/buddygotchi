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
#include "render/gel/painter.h"
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
// once, a few seconds (a move up to 11); working's and idle's each need a
// tier, idle's at least three for every one of the five and working's at
// least two for each of the first four and the stretch break at the
// fifth, the three moves only at work, and needs you's and asleep's
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
    TEST_ASSERT_TRUE_MESSAGE(clip->ms >= 2000 && clip->ms <= (p.move ? 11000 : 6500), p.clip);
    TEST_ASSERT_TRUE(!p.move || p.look == SceneState::kWorking);
    if (p.look == SceneState::kWorking || p.look == SceneState::kIdle) {
      TEST_ASSERT_TRUE(p.tier >= 1 && p.tier <= 5);
      TEST_ASSERT_EQUAL_INT(0, p.afterS);
      ++count[p.look == SceneState::kIdle][p.tier];
    } else {
      TEST_ASSERT_TRUE(p.look == SceneState::kNeedsYou || p.look == SceneState::kAsleep);
      TEST_ASSERT_EQUAL_INT(0, p.tier);
    }
  }
  for (int n = 1; n <= 5; ++n) TEST_ASSERT_TRUE((n == 5 || count[0][n] >= 2) && count[1][n] >= 3);
  TEST_ASSERT_TRUE(info(Pastime::kReach).move && info(Pastime::kMelt).move && info(Pastime::kStretch).move);
  TEST_ASSERT_EQUAL_INT(5, info(Pastime::kStretch).tier);
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
      face.draw(c, &s, face.show(board.t, false, 0), board.t, nullptr, SignShow{}, DoneShow{}, Strip{}, false);
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

// Pins the kit: at work a mug from tier1, headphones from tier3 once it
// has put them on (none while it wears a hat), and from tier5 a mug more on the stack every
// kMugEveryMs up to kMostMugs, counted from when the work reached tier5,
// and the zone's motes;
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
  TEST_ASSERT_TRUE(!s.mug && !s.headphones && !s.plant);
  s = kit(1);
  TEST_ASSERT_TRUE(s.mug == 255 && !s.headphones);
  s = kit(3);
  TEST_ASSERT_TRUE(s.mug && !s.headphones);  // until it puts them on
  board.to(board.t + 20000);
  TEST_ASSERT_EQUAL_INT(255, face.pastimes(board.t).headphones);
  s = kit(4);
  TEST_ASSERT_TRUE(s.mug && s.headphones && !s.zone);
  TEST_ASSERT_EQUAL_INT(1, s.mugs);
  TEST_ASSERT_EQUAL_INT(1, face.pastimes(board.t + kMugEveryMs).mugs);  // not before tier5
  s = kit(5);
  TEST_ASSERT_TRUE(s.mug && s.headphones && s.zone == 255);
  TEST_ASSERT_EQUAL_INT(1, s.mugs);
  TEST_ASSERT_EQUAL_INT(2, face.pastimes(board.t + kMugEveryMs).mugs);
  TEST_ASSERT_EQUAL_INT(kMostMugs, face.pastimes(board.t + 10 * kMugEveryMs).mugs);
  s = kit(5, tagBit("night"));  // the nightcap wins the head
  TEST_ASSERT_TRUE(s.mug && !s.headphones);
  s = kit(3, tagBit("morning"));  // the morning's coffee is in its hand
  board.to(board.t + 20000);  // and on go the headphones again
  s = face.pastimes(board.t);
  TEST_ASSERT_TRUE(!s.mug && s.headphones);
  board.m.attn = true, board.m.attnId = 4;
  s = kit(5);
  TEST_ASSERT_TRUE(!s.mug && !s.headphones && !s.zone);
  board.m.attn = false, board.m.base = SceneState::kIdle;
  for (int tier : {2, 3, 4, 5}) {
    s = kit(tier);
    TEST_ASSERT_TRUE(!s.mug && !s.headphones);
    TEST_ASSERT_EQUAL_INT(tier >= 3 ? 255 : 0, s.plant);
    if (tier >= 3) TEST_ASSERT_EQUAL_INT(tier - 2, s.grown);
  }
}

// Pins working's base by tier (the rig's looks.json tiers): the last tier
// reached names it, none with no tier; the gel loops it while the look
// shows, its lids lower the further in (tier1's open, tier5's at 620 of
// 1000), and fades it out under a reaction and while something needs you.
void test_work_settles_by_tier() {
  const rig::Look* working = rig::kRig.look(SceneState::kWorking);
  TEST_ASSERT_NULL(working->tiered(tagBit("day")));
  TEST_ASSERT_EQUAL_PTR(rig::kRig.clip("work-easy"), working->tiered(reached(tierBit(1))));
  TEST_ASSERT_EQUAL_PTR(rig::kRig.clip("work-focused"), working->tiered(reached(tierBit(3))));
  TEST_ASSERT_EQUAL_PTR(rig::kRig.clip("work-zone"), working->tiered(reached(tierBit(5)) | tagBit("night")));
  TEST_ASSERT_NULL(rig::kRig.look(SceneState::kIdle)->tiered(reached(tierBit(5))));
  // Two seconds in, before any pastime's rest is over.
  auto at2s = [](SceneState look, uint32_t when) {
    Board board(look, when);
    board.to(2000);
    return board.face().mixer().channels();
  };
  const rig::Channels none = at2s(SceneState::kWorking, tagBit("day"));
  TEST_ASSERT_EQUAL_MEMORY(&rig::kRest, &none, sizeof none);
  TEST_ASSERT_EQUAL_INT(1000, at2s(SceneState::kWorking, tagBit("day") | tiers(1))[rig::Channel::kEyeOpenL]);
  TEST_ASSERT_INT_WITHIN(30, 620, at2s(SceneState::kWorking, tagBit("day") | tiers(5))[rig::Channel::kEyeOpenL]);
  TEST_ASSERT_TRUE(at2s(SceneState::kWorking, tagBit("day") | tiers(3))[rig::Channel::kEyeOpenL] < 800);
  TEST_ASSERT_EQUAL_INT(1000, at2s(SceneState::kNeedsYou, tagBit("day") | tiers(5))[rig::Channel::kEyeOpenL]);
  // A poke's reaction: the base fades out under it, and back after.
  Board board(SceneState::kWorking, tagBit("day") | tiers(5));
  board.to(2000);
  app::ReactionIn in;
  in.anim = SceneState::kPoked;
  in.id = 9;
  in.variant = board.b.pick(in.anim, board.m.mood, 255, in.outcome, StartCtx::kNone, board.rng);
  board.b.play(in, board.t);
  board.to(board.t + 600);
  TEST_ASSERT_TRUE(board.face().mixer().channels()[rig::Channel::kEyeOpenL] > 950);
}

// Pins kTapMs, kTapLift, kTypeMs and kTypeLift: a paw lifts before each
// of its own key contacts and lands on it, its highest halfway; the other
// paw stays down. Between them the paws tap softly by turns, each every
// other kTypeMs, lower.
void test_the_paws_type_on_the_keys() {
  Scenes s;
  s.recipe.count = 2;
  s.recipe.contacts[0] = {T::literal(1000), uint8_t(kKey), int8_t(1), F(1)};
  s.recipe.contacts[1] = {T::literal(1400), uint8_t(kKnock), int8_t(-1), F(1)};
  auto at = [&](int ms, int side) {
    s.ageMs = T::literal(ms);
    return tapLift(s, side);
  };
  TEST_ASSERT_EQUAL_INT(0, at(1000 - kTapMs - 1, 1));
  TEST_ASSERT_EQUAL_INT(kTapLift, at(1000 - kTapMs / 2, 1));
  TEST_ASSERT_TRUE(at(1000 - kTapMs / 4, 1) > 0 && at(1000 - kTapMs / 4, 1) < kTapLift);
  TEST_ASSERT_EQUAL_INT(0, at(1000, 1));
  TEST_ASSERT_EQUAL_INT(0, at(1000 - kTapMs / 2, -1));
  TEST_ASSERT_EQUAL_INT(0, at(1400 - kTapMs / 2, -1));  // a knock isn't a key
  TEST_ASSERT_EQUAL_INT(0, typeLift(0, -1));
  TEST_ASSERT_EQUAL_INT(kTypeLift, typeLift(2 * kTypeMs - kTapMs / 2, -1));
  TEST_ASSERT_EQUAL_INT(0, typeLift(2 * kTypeMs - kTapMs / 2, 1));
  TEST_ASSERT_EQUAL_INT(kTypeLift, typeLift(kTypeMs - kTapMs / 2, 1));
  TEST_ASSERT_EQUAL_INT(0, typeLift(kTypeMs, 1));
  TEST_ASSERT_TRUE(kTypeLift < kTapLift);
}

// Pins kPhonesDropPx and kPhonesOnMs: once it wants its headphones
// (working, tier3, its head free) the first pastime it plays is putting
// them on: they come down from kPhonesDropPx above its ears, its paws up
// at its head holding them, on by kPhonesOnMs, and stay on; it isn't dealt
// again while they're on, and it is once they've been off.
void test_the_headphones_go_on_where_you_see_them() {
  Board board(SceneState::kWorking, tagBit("day") | tiers(3));
  GelFace& face = board.face();
  int puts = 0, others = 0;
  uint32_t start = 0;
  board.to(60000, [&] {
    const PastimeShow s = face.pastimes(board.t);
    if (s.playing == Pastime::kPhonesOn) {
      if (!start) start = board.t, ++puts, TEST_ASSERT_EQUAL_INT(0, others);
      const uint32_t age = board.t - start;
      if (age == 16) TEST_ASSERT_TRUE(s.drop > kPhonesDropPx * 9 / 10 && s.headphones > 0);
      if (age >= kPhonesOnMs) TEST_ASSERT_EQUAL_INT(0, s.drop);
      if (age == 800) TEST_ASSERT_TRUE(pawsFor(s).alpha[0] == 0 && pawsFor(s).alpha[1] == 0);
    } else {
      if (s.playing != Pastime::kNone && start) ++others;
      if (!start) TEST_ASSERT_EQUAL_INT(0, s.headphones);
      if (start && board.t > start + 2400 + 300) TEST_ASSERT_EQUAL_INT(255, s.headphones);
    }
  });
  TEST_ASSERT_EQUAL_INT(1, puts);
  TEST_ASSERT_TRUE(others > 2);
  // Something needs you, and back to work: on again.
  board.m.attn = true, board.m.attnId = 5;
  board.b.onState(board.m, board.t);
  board.to(board.t + 5000);
  board.m.attn = false;
  board.b.onState(board.m, board.t);
  start = 0;
  board.to(board.t + 30000, [&] {
    if (face.pastimes(board.t).playing == Pastime::kPhonesOn && !start) start = board.t;
  });
  TEST_ASSERT_TRUE(start > 0);
}

// Pins kMoveGapMs: at work for half an hour at tier5, the moves (the
// coffee reach, the melt, the stretch break) each start at least
// kMoveGapMs after the last, the stretch break among them, and calm
// pastimes play between. While one plays, the desk's paws are its: the
// right one has the mug, they spread with the melt, and they're away with
// it on its stretch break.
void test_moves_are_rare() {
  Board board(SceneState::kWorking, tagBit("day") | tiers(5));
  GelFace& face = board.face();
  Pastime playing = Pastime::kNone;
  uint32_t lastMove = 0;
  int moves = 0, calm = 0, stretches = 0;
  board.to(30 * 60 * 1000, [&] {
    const PastimeShow s = face.pastimes(board.t);
    if (s.playing != playing && s.playing != Pastime::kNone) {
      if (info(s.playing).move) {
        if (moves) TEST_ASSERT_TRUE(board.t - lastMove >= kMoveGapMs);
        lastMove = board.t, ++moves, stretches += s.playing == Pastime::kStretch;
      } else {
        ++calm;
      }
    }
    playing = s.playing;
    if (s.fade < 255) return;
    const Paws paws = pawsFor(s);
    if (s.playing == Pastime::kReach && s.age >= 1000 && s.age < 4100) TEST_ASSERT_EQUAL_INT(0, paws.alpha[1]);
    if (s.playing == Pastime::kMelt && s.age >= 2300 && s.age < 4200) TEST_ASSERT_EQUAL_INT(70, paws.dx[1]);
    if (s.playing == Pastime::kStretch && s.age >= 3000 && s.age < 7000) TEST_ASSERT_EQUAL_INT(0, paws.alpha[0]);
  });
  TEST_ASSERT_TRUE(moves >= 8 && moves <= 30 * 60 / 90 + 1);
  TEST_ASSERT_TRUE(stretches > 0);
  TEST_ASSERT_TRUE(calm > moves * 5);
}
