// The gel's pastimes (render/gel/pastimes.h): the catalog and each one's
// clip, that each moves the body and ends, and how the face deals them by
// tier after a rest.
#include <algorithm>
#include <unity.h>

#include <cstring>
#include <map>
#include <memory>
#include <set>
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
    m.act = SceneState::kWorking;
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

// The transitions (GelFace::showTransition): each between half a second and a
// second, from one Doing to another, over the new look, which has come at once;
// anything urgent cuts through, and none starts with it up.
void test_transitions_play_between_doings_and_anything_urgent_cuts_through() {
  for (const char* name : {"to-work", "to-rest", "to-sleep"}) {
    const rig::Clip* clip = rig::kRig.clip(name);
    TEST_ASSERT_NOT_NULL_MESSAGE(clip, name);
    TEST_ASSERT_TRUE_MESSAGE(clip->ms >= 500 && clip->ms <= 1000, name);
  }
  Board b(SceneState::kIdle, 0);
  b.to(2000);
  TEST_ASSERT_NULL(b.face().transition(b.t));
  b.m.base = SceneState::kWorking;
  b.b.onState(b.m, b.t);
  TEST_ASSERT_EQUAL(SceneState::kWorking, b.b.look(b.t));  // at once
  b.to(b.t + 32);
  TEST_ASSERT_EQUAL_PTR(rig::kRig.clip("to-work"), b.face().transition(b.t));
  b.to(b.t + rig::kRig.clip("to-work")->ms + 32);
  TEST_ASSERT_NULL(b.face().transition(b.t));
  b.m.base = SceneState::kIdle;
  b.b.onState(b.m, b.t);
  b.to(b.t + 32);
  TEST_ASSERT_EQUAL_PTR(rig::kRig.clip("to-rest"), b.face().transition(b.t));
  // A needs-you cuts through, and the clip's sound goes with it.
  b.to(b.t + rig::kRig.clip("to-rest")->ms + 32);
  b.m.base = SceneState::kWorking;
  b.b.onState(b.m, b.t);
  b.to(b.t + 32);
  TEST_ASSERT_EQUAL_PTR(rig::kRig.clip("to-work"), b.face().cueing());
  std::strcpy(b.m.agent, "claude"), std::strcpy(b.m.project, "api"), b.m.attnId = 3, b.m.attn = true;
  b.b.onState(b.m, b.t);
  b.to(b.t + 32);
  TEST_ASSERT_NULL(b.face().transition(b.t));
  TEST_ASSERT_NOT_EQUAL(rig::kRig.clip("to-work"), b.face().cueing());
  // Going to sleep under it starts none.
  b.m.base = SceneState::kAsleep;
  b.b.onState(b.m, b.t);
  b.to(b.t + 32);
  TEST_ASSERT_NULL(b.face().transition(b.t));
}

// Pins the table: every row's body is in the pack, a clip of its rig that
// plays once, a few seconds (a move up to 11), a bit of its engine (idle's
// only) or a take (at work or asleep); working's and idle's each need a
// tier or a tag, never both, and asleep's a wait or a tag; none is for
// while something needs you. At work: only a stretch, from tier2. Idle: a look around,
// a hopeful look, a hop, a yawn and a sneeze from tier1, a snooze from
// tier3. Asleep it rolls over from a minute, blows a snore bubble from 4,
// snores deeper at night and dreams after half an hour.
void test_every_pastime_has_its_clip_and_its_turn() {
  static_assert(kTiers == 3 && kPastimeCount == 11, "the table this test pins");
  for (int i = 0; i < kPastimeCount; ++i) {
    const PastimeInfo& p = kPastimes[i];
    TEST_ASSERT_EQUAL_INT(i + 1, int(p.id));
    TEST_ASSERT_EQUAL_PTR(&p, &info(p.id));
    TEST_ASSERT_TRUE(!p.move || p.look == SceneState::kWorking);
    TEST_ASSERT_TRUE(!p.tag || (tagsOf(p) && p.tier == 0));
    const bool tiered = p.look == SceneState::kWorking || p.look == SceneState::kIdle;
    if (tiered && !p.tag) TEST_ASSERT_TRUE(p.tier >= 1 && p.tier <= kTiers);
    if (p.body == Body::kBit) {
      TEST_ASSERT_TRUE_MESSAGE(bitOf(p) >= 0, p.name);
      TEST_ASSERT_TRUE(p.look == SceneState::kIdle);
      continue;
    }
    if (p.body == Body::kTake) {
      TEST_ASSERT_TRUE_MESSAGE(takeOf(p) >= 0, p.name);
      TEST_ASSERT_TRUE(p.look == SceneState::kWorking || p.look == SceneState::kAsleep);
      continue;
    }
    const rig::Clip* clip = clipOf(p);
    TEST_ASSERT_NOT_NULL_MESSAGE(clip, p.name);
    TEST_ASSERT_FALSE(clip->loop);
    TEST_ASSERT_TRUE(clip->additive);
    TEST_ASSERT_TRUE_MESSAGE(clip->ms >= 2000 && clip->ms <= (p.move ? 11000 : 6500), p.name);
    if (p.look == SceneState::kWorking || p.look == SceneState::kIdle) {
      TEST_ASSERT_TRUE(p.tier >= 1 && p.tier <= kTiers);
      TEST_ASSERT_EQUAL_INT(0, p.afterS);
    } else {
      TEST_ASSERT_TRUE(p.look == SceneState::kAsleep);
      TEST_ASSERT_EQUAL_INT(0, p.tier);
    }
  }
  for (const PastimeInfo& p : kPastimes) TEST_ASSERT_FALSE(p.move);  // no move is left
  TEST_ASSERT_EQUAL_INT(2, info(Pastime::kStretch).tier);
  // At work there is only the stretch: the tempo at work is yours.
  int atWork = 0;
  for (const PastimeInfo& p : kPastimes) atWork += p.look == SceneState::kWorking;
  TEST_ASSERT_EQUAL_INT(1, atWork);
  for (Pastime p : {Pastime::kLookAround, Pastime::kHopeful, Pastime::kHop, Pastime::kYawn, Pastime::kSneeze})
    TEST_ASSERT_EQUAL_INT(1, info(p).tier);
  TEST_ASSERT_EQUAL_INT(3, info(Pastime::kSnooze).tier);
  TEST_ASSERT_EQUAL_INT(60, info(Pastime::kRollOver).afterS);
  TEST_ASSERT_EQUAL_INT(240, info(Pastime::kSnoreBubble).afterS);
  TEST_ASSERT_EQUAL_INT(1800, info(Pastime::kDream).afterS);
  TEST_ASSERT_EQUAL_STRING("night", info(Pastime::kDeepSnore).tag);
  // The tiers: the Mac sends the last reached, and the board takes the
  // ones below it as on.
  for (int n = 1; n <= kTiers; ++n) {
    char name[8] = "tier0";
    name[4] = char('0' + n);
    TEST_ASSERT_EQUAL_UINT32(tagBit(name), tierBit(n));
    TEST_ASSERT_EQUAL_INT(n, tierOf(reached(tierBit(n))));
  }
  TEST_ASSERT_EQUAL_UINT32(tierBit(1) | tierBit(2) | tierBit(3), reached(tierBit(3)));
  TEST_ASSERT_EQUAL_UINT32(0, tierBit(0));
  TEST_ASSERT_EQUAL_UINT32(0, tierBit(4));  // the board's table keeps tier4 and tier5 for Pixel: the gel has none
  TEST_ASSERT_EQUAL_UINT32(tagBit("day"), reached(tagBit("day")));
  TEST_ASSERT_EQUAL_INT(0, tierOf(tagBit("night")));
}

// Each pastime with a clip moves the body, above the lane, and is over at
// its clip's end: nothing of it shows after.
void test_each_pastime_draws_and_ends() {
  std::vector<uint16_t> before(502 * 410), during(before.size()), after(before.size());
  std::vector<uint8_t> canvas(size_t(kWidth) * kHeight);
  Canvas c{canvas.data()};
  for (const PastimeInfo& p : kPastimes) {
    if (p.body != Body::kClip) continue;
    const bool tiered = p.look == SceneState::kWorking || p.look == SceneState::kIdle;
    Board board(p.look, tagBit("day") | (tiered ? tierBit(kTiers) : 0));
    GelFace& face = board.face();
    auto draw = [&](std::vector<uint16_t>& px) {
      Surface s{502, 410, px.data()};
      std::fill(px.begin(), px.end(), 0);
      face.draw(c, &s, face.show(board.t, false, 0), board.t, nullptr, nullptr, SignShow{}, DoneShow{}, Strip{}, false);
    };
    board.to(3008);
    draw(before);
    face.playPastime(p.id, board.t);
    const uint32_t start = board.t, ms = clipOf(p)->ms;
    board.to(start + ms / 2);
    TEST_ASSERT_EQUAL_INT_MESSAGE(int(p.id), int(face.pastimes(board.t).playing), p.name);
    TEST_ASSERT_EQUAL_INT_MESSAGE(255, face.pastimes(board.t).fade, p.name);
    draw(during);
    int changed = 0;
    for (size_t i = 0; i < before.size(); ++i) changed += before[i] != during[i];
    TEST_ASSERT_TRUE_MESSAGE(changed > 500, p.name);
    // The lane, the bottom fifth, is the host's.
    for (size_t i = size_t(502) * (410 * 4 / 5); i < before.size(); ++i)
      TEST_ASSERT_EQUAL_HEX16_MESSAGE(before[i], during[i], p.name);
    board.to(start + ms + 16);
    TEST_ASSERT_EQUAL_INT_MESSAGE(int(Pastime::kNone), int(face.pastimes(board.t).playing), p.name);
  }
}

// Pins kRestMinMs and kRestMaxMs: idle with tier1 on for three quarters
// of an hour, the face deals only idle pastimes of tier1, one
// at a time, never the same twice running, each after a rest of 20 to 45 s
// (the look's first too): calm, most of the time it only works. With no
// tier, none; and none while something needs you, however long.
void test_pastimes_are_dealt_by_tier_after_a_rest() {
  static_assert(kRestMinMs == 20000 && kRestMaxMs == 45000, "the rests this test pins");
  Board board(SceneState::kIdle, tagBit("day") | tierBit(1));
  GelFace& face = board.face();
  Pastime playing = Pastime::kNone, last = Pastime::kNone;
  uint32_t ended = 0;
  int dealt = 0;
  board.to(45 * 60 * 1000, [&] {
    const Pastime now = face.pastimes(board.t).playing;
    if (now == playing) return;
    if (now != Pastime::kNone) {
      const PastimeInfo& p = info(now);
      TEST_ASSERT_TRUE(p.look == SceneState::kIdle && p.tier <= 1);
      TEST_ASSERT_TRUE(now != last);
      const uint32_t rest = board.t - ended;
      TEST_ASSERT_TRUE(rest >= kRestMinMs && rest <= kRestMaxMs + 32);
      ++dealt, last = now;
    } else {
      ended = board.t;
    }
    playing = now;
  });
  TEST_ASSERT_TRUE(dealt > 50);
  // No tier, no pastime: at work or idle.
  for (SceneState look : {SceneState::kWorking, SceneState::kIdle}) {
    Board none(look, tagBit("day"));
    none.to(120000, [&] { TEST_ASSERT_EQUAL_INT(int(Pastime::kNone), int(none.face().pastimes(none.t).playing)); });
  }
  // While something needs you, none: the amber screen is the message.
  Board asking(SceneState::kNeedsYou, tagBit("day") | tiers(kTiers));
  asking.to(15 * 60 * 1000,
            [&] { TEST_ASSERT_EQUAL_INT(int(Pastime::kNone), int(asking.face().pastimes(asking.t).playing)); });
}

// The rows that need a tag play only while it's on: work has none, however
// busy; asleep
// snores deeper at night and dreams after half an hour. Idle has no tagged
// row: on any day, at any hour, only the yawn and the sneeze of the
// engine's bits, and with no tier, none.
void test_a_tagged_pastime_plays_only_while_its_tag_is_on() {
  // How often each row with a body of the engine's was dealt, over `ms`,
  // and how many were dealt in all.
  struct Dealt {
    std::map<Pastime, int> rows;
    int all = 0;
    bool has(Pastime p) const { return rows.count(p) > 0; }
  };
  auto deal = [](SceneState look, uint32_t when, int busy, uint32_t ms) {
    // The board's own tags from state.busy, as Device adds them.
    Board board(look, when | busyTags(busy));
    board.m.busy = busy;
    board.b.onState(board.m, 0);
    Dealt dealt;
    Pastime last = Pastime::kNone;
    board.to(ms, [&] {
      const Pastime now = board.face().pastimes(board.t).playing;
      if (now != last && now != Pastime::kNone) {
        ++dealt.all;
        const PastimeInfo& p = info(now);
        const Engine& e = board.face().engine();
        if (p.body == Body::kBit) {
          ++dealt.rows[now];
          TEST_ASSERT_EQUAL_INT(bitOf(p), e.acting.playing);
        } else if (p.body == Body::kTake) {
          ++dealt.rows[now];
          const Route& r = e.scenes.route;
          TEST_ASSERT_EQUAL_INT(takes(recipeState(r.state, r.outcome)) + takeOf(p), e.scenes.variant);
        }
      }
      last = now;
    });
    return dealt;
  };
  const uint32_t day = tagBit("day"), five = 30 * 60 * 1000;  // long enough for a few dozen deals
  const Dealt plain = deal(SceneState::kIdle, day | tierBit(1), 0, five);
  TEST_ASSERT_TRUE(plain.has(Pastime::kYawn) && plain.has(Pastime::kSneeze) && plain.rows.size() == 2);
  for (const char* tag : {"night", "morning", "party", "friday", "winter", "halloween", "valentines"}) {
    const Dealt tagged = deal(SceneState::kIdle, tagBit(tag) | tierBit(1), 0, five);
    TEST_ASSERT_TRUE_MESSAGE(tagged.has(Pastime::kYawn) && tagged.has(Pastime::kSneeze) && tagged.rows.size() == 2, tag);
  }
  TEST_ASSERT_EQUAL_INT(0, deal(SceneState::kIdle, day, 0, 120000).all);
  TEST_ASSERT_EQUAL_INT(0, deal(SceneState::kIdle, tagBit("night"), 0, 120000).all);
  // Work: nothing for being busy or frantic; the tempo at work is yours.
  for (int pace : {0, 2, 5}) TEST_ASSERT_TRUE(deal(SceneState::kWorking, day | tierBit(1), pace, five).rows.empty());
  // Asleep: deeper at night, a dream after half an hour.
  const Dealt deep = deal(SceneState::kAsleep, tagBit("night"), 0, 120000);
  TEST_ASSERT_TRUE(deep.has(Pastime::kDeepSnore) && deep.rows.size() == 1);
  TEST_ASSERT_TRUE(deal(SceneState::kAsleep, day, 0, 120000).rows.empty());
  TEST_ASSERT_TRUE(deal(SceneState::kAsleep, day, 0, 31 * 60 * 1000).has(Pastime::kDream));
}

// Pins working's base by tier (the rig's looks.json tiers): the last tier
// reached names it, none with no tier; the gel loops it while the look
// shows, its lids lower the further in (tier1's open, tier3's at 620 of
// 1000), and fades it out under a reaction and while something needs you.
void test_work_settles_by_tier() {
  const rig::Look* working = rig::kRig.look(SceneState::kWorking);
  TEST_ASSERT_NULL(working->tiered(tagBit("day")));
  TEST_ASSERT_EQUAL_PTR(rig::kRig.clip("work-easy"), working->tiered(reached(tierBit(1))));
  TEST_ASSERT_EQUAL_PTR(rig::kRig.clip("work-focused"), working->tiered(reached(tierBit(2))));
  TEST_ASSERT_EQUAL_PTR(rig::kRig.clip("work-zone"), working->tiered(reached(tierBit(3)) | tagBit("night")));
  TEST_ASSERT_NULL(rig::kRig.look(SceneState::kIdle)->tiered(reached(tierBit(3))));
  // Two seconds in, before any pastime's rest is over.
  auto at2s = [](SceneState look, uint32_t when) {
    Board board(look, when);
    board.to(2000);
    return board.face().mixer().channels();
  };
  const rig::Channels none = at2s(SceneState::kWorking, tagBit("day"));
  TEST_ASSERT_EQUAL_MEMORY(&rig::kRest, &none, sizeof none);
  TEST_ASSERT_EQUAL_INT(1000, at2s(SceneState::kWorking, tagBit("day") | tiers(1))[rig::Channel::kEyeOpenL]);
  TEST_ASSERT_INT_WITHIN(30, 620, at2s(SceneState::kWorking, tagBit("day") | tiers(3))[rig::Channel::kEyeOpenL]);
  TEST_ASSERT_TRUE(at2s(SceneState::kWorking, tagBit("day") | tiers(2))[rig::Channel::kEyeOpenL] < 800);
  TEST_ASSERT_EQUAL_INT(1000, at2s(SceneState::kNeedsYou, tagBit("day") | tiers(3))[rig::Channel::kEyeOpenL]);
  // A poke's reaction: the base fades out under it, and back after.
  Board board(SceneState::kWorking, tagBit("day") | tiers(3));
  board.to(2000);
  app::ReactionIn in;
  in.anim = SceneState::kPoked;
  in.id = 9;
  in.variant = board.b.pick(in.anim, board.m.mood, 255, in.outcome, board.rng);
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

// The four activities (router.h's Activity), each a pose of the whole body:
// every act the Mac may name is one of them; looking, running and waiting
// each loop their own clip (the rig's looks.json acts) whatever the tier,
// and typing the tier's; the pose comes over kPoseMs with no jump, leant
// in to the monitor as it looks, sat back as something runs, slumped as it
// waits; the paws leave their typing for the pose's, and of a look's
// pastimes only the stretch is dealt off typing.
void test_each_activity_is_a_pose() {
  using rig::Channel;
  const struct {
    SceneState act;
    Activity activity;
    SceneState shown;
  } acts[] = {{SceneState::kWorking, Activity::kTyping, SceneState::kWorking},
              {SceneState::kToolUse, Activity::kTyping, SceneState::kWorking},
              {SceneState::kPlanning, Activity::kTyping, SceneState::kWorking},
              {SceneState::kAnalyzing, Activity::kLooking, SceneState::kAnalyzing},
              {SceneState::kSearching, Activity::kLooking, SceneState::kAnalyzing},
              {SceneState::kTerminal, Activity::kRunning, SceneState::kTerminal},
              {SceneState::kTesting, Activity::kRunning, SceneState::kTerminal},
              {SceneState::kDelegating, Activity::kRunning, SceneState::kTerminal},
              {SceneState::kWaiting, Activity::kWaiting, SceneState::kWaiting}};
  for (const auto& a : acts) {
    TEST_ASSERT_EQUAL_INT(int(a.activity), int(activityOf(a.act)));
    TEST_ASSERT_EQUAL_INT(int(a.shown), int(deskStateOf(a.activity)));
  }
  const rig::Look* working = rig::kRig.look(SceneState::kWorking);
  TEST_ASSERT_NULL(working->acted(SceneState::kWorking));
  TEST_ASSERT_EQUAL_PTR(rig::kRig.clip("work-looking"), working->acted(SceneState::kAnalyzing));
  TEST_ASSERT_EQUAL_PTR(rig::kRig.clip("work-running"), working->acted(SceneState::kTerminal));
  TEST_ASSERT_EQUAL_PTR(rig::kRig.clip("work-waiting"), working->acted(SceneState::kWaiting));
  // From typing at tier3 to each, the body's channels step by step.
  auto pose = [](SceneState act, int* jump = nullptr) {
    Board board(SceneState::kWorking, tagBit("day") | tiers(3));
    board.to(2000);
    board.m.act = act;
    board.b.onState(board.m, board.t);
    rig::Channels last = board.face().mixer().channels();
    board.to(board.t + 2 * kPoseMs, [&] {
      const rig::Channels now = board.face().mixer().channels();
      for (Channel c : {Channel::kLean, Channel::kSquash, Channel::kX})
        if (jump) *jump = std::max(*jump, std::abs(now[c] - last[c]));
      last = now;
    });
    TEST_ASSERT_EQUAL_INT(int(deskStateOf(activityOf(act))), int(board.face().engine().scenes.route.state));
    return last;
  };
  int jump = 0;
  const rig::Channels looking = pose(SceneState::kAnalyzing, &jump), running = pose(SceneState::kTerminal, &jump),
                      waiting = pose(SceneState::kWaiting, &jump), typing = pose(SceneState::kToolUse);
  // Of 1000, a 16 ms step: no pop. The poses go further than they did
  // (looking presses up to the monitor), so a step may be a little larger.
  TEST_ASSERT_LESS_OR_EQUAL_INT(40, jump);
  TEST_ASSERT_TRUE(looking[Channel::kLean] <= -400 && looking[Channel::kX] <= -30 && looking[Channel::kGazeX] < -300);
  TEST_ASSERT_TRUE(running[Channel::kLean] >= 180 && running[Channel::kX] >= 25 && running[Channel::kSquash] <= -180);
  TEST_ASSERT_TRUE(waiting[Channel::kSquash] >= 240 && waiting[Channel::kGazeY] < -300);
  // Typing keeps the tier's: work-zone's low lids and no slide.
  TEST_ASSERT_INT_WITHIN(30, 620, typing[Channel::kEyeOpenL]);
  TEST_ASSERT_EQUAL_INT(0, typing[Channel::kX]);
  // The paws' poses come in as typing goes out.
  Board board(SceneState::kWorking, tagBit("day"));
  board.to(2000);
  const Scenes& s = board.face().engine().scenes;
  TEST_ASSERT_TRUE(s.posed(Activity::kTyping) > q(.99) && s.posed(Activity::kRunning) < q(.01));
  board.m.act = SceneState::kTerminal;
  board.b.onState(board.m, board.t);
  board.to(board.t + 2 * kPoseMs);
  TEST_ASSERT_TRUE(s.posed(Activity::kRunning) > q(.95) && s.posed(Activity::kTyping) < q(.05));
  // Two hours of running at tier3: nothing but the stretch is dealt.
  Board long_(SceneState::kWorking, tagBit("day") | tiers(3));
  long_.m.act = SceneState::kTerminal;
  long_.b.onState(long_.m, 0);
  int stretches = 0;
  Pastime playing = Pastime::kNone;
  long_.to(120 * 60 * 1000, [&] {
    const Pastime now = long_.face().pastimes(long_.t).playing;
    if (now != playing && now != Pastime::kNone) {
      TEST_ASSERT_EQUAL_INT(int(Pastime::kStretch), int(now));
      ++stretches;
    }
    playing = now;
  });
  TEST_ASSERT_TRUE(stretches > 10);
}

