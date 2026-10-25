// The behaviour state machine, with
// every timing checked to the millisecond.
#include <unity.h>

#include "voice_file.h"  // internal/firmware/

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "app/behaviour.h"
#include "app/device.h"
#include "render/palette.h"
#include "render/pixel/anim.h"
#include "render/pixel/sounds.h"
#include "render/pixel/scene.h"
#include "render/tags.h"
#include "linkkit/kit.h"
#include "voice/player.h"

void setUp() {}
void tearDown() {}

using app::Behaviour;
using app::Model;
using app::ReactionIn;
using render::SceneShow;
using render::SceneState;
using render::loopMs;

namespace {

// A take with a known length (a `say` speaks for its take's
// length, and its bubble stays kBubbleReadMs longer).
constexpr const char* kGo = "previous.go";  // 7042 samples: 638 ms
constexpr uint32_t kGoMs = 638;

// A reaction from the Mac as LinkKit hands it over (linkkit/SPEC.md §4):
// admitted (the kit's refuse), then played. True when its `say` plays;
// false when it was refused or has no `say`.
bool onReaction(Behaviour& b, const ReactionIn& in, uint32_t t) { return !b.admit(in, t) && b.play(in, t); }

struct Rig {
  Behaviour b;
  app::Rng rng;
  uint32_t t = 0;
  Rig() { b.reset(0, rng); }
  void at(uint32_t to) {
    t = to;
    b.advance(t, rng);
  }
  void state(Model m) { b.onState(m, t); }
  // Pins the look's variation `v` (from 0), as dbg.look does, from now.
  void look(uint8_t v) {
    b.face().showLookVariant(v);
    b.advance(t, rng);
  }
  void react(SceneState a) {
    ReactionIn m;
    m.anim = a;
    onReaction(b, m, t);
  }
  // A line on its own: take `id` ("Go", 638 ms, by default); null for a
  // `say` with no take.
  bool say(const char* id = kGo) {
    ReactionIn m;
    m.said = true, m.take = voice::takeIndex(id);
    return onReaction(b, m, t);
  }
  // stop_listening.
  void stop() {
    ReactionIn m;
    m.empty = true;
    onReaction(b, m, t);
  }
  void talkOn() { b.talkOn(t, rng); }
  void talkOff() { b.talkOff(t); }
  SceneState anim() {
    uint32_t left;
    return b.reaction(t, left);
  }
  // When needs you's performance last started for a new needs-you.
  std::string alert() {
    uint32_t at;
    return b.alerted(at) ? "alert@" + std::to_string(at) : "";
  }
};

Model base(const char* b) {
  Model m;
  m.base = app::baseFromName(b);
  return m;
}

Model attn(const char* project = "landing") {
  Model m = base("working");
  m.attn = true;
  std::strcpy(m.agent, "codex");
  std::strcpy(m.project, project);
  return m;
}

// Keeps the Mac talking every 10 s up to `to`, so "no app" stays away.
void keepAlive(Rig& r, const Model& m, uint32_t to) {
  while (r.t + 10000 <= to) {
    r.at(r.t + 10000);
    r.state(m);
  }
  r.at(to);
}

// The face screen: the look is neither no app nor needs you.
bool onFace(const Behaviour& b, uint32_t t) {
  const SceneState look = b.look(t);
  return look != SceneState::kNoApp && look != SceneState::kNeedsYou;
}

}  // namespace

// A look's variations rotate, the face's own picks. Each
// shows at least render::pixel::PixelFace::kTurnMinMs, then each end of its loop moves
// to another (never itself) or plays another loop, and the move blinks
// and starts the new one's clock. Only those that fit turn up: with no
// tags on and the look new, never an occasion's (working's coffee and
// sweat) nor one that waits (its stretch, after 20 minutes). The Mac's
// same state again doesn't start them over. Needs you and a finish hold
// the variation showing.
static void test_the_looks_variations_rotate() {
  Rig r;
  Model m = base("working");
  r.state(m);
  r.look(2);
  uint8_t shown = 2;
  uint32_t since = 0;
  int turns = 0, stays = 0;
  bool seen[8] = {};
  seen[2] = true;
  for (uint32_t t = 10; t <= 600000; t += 10) {
    r.at(t);
    if (t % 10000 == 0) r.state(m);  // the Mac, saying the same
    SceneShow s = r.b.show(t);
    TEST_ASSERT_TRUE(s.state == SceneState::kWorking);
    if (s.variant == shown) continue;
    uint32_t loop = loopMs(render::Mood::kHappy, SceneState::kWorking, shown);
    TEST_ASSERT_TRUE(t - since >= render::pixel::PixelFace::kTurnMinMs);
    TEST_ASSERT_EQUAL_UINT32(0, (t - since) % loop);  // at a loop's end
    TEST_ASSERT_EQUAL_UINT32(0, s.t);
    if (t - since >= render::pixel::PixelFace::kTurnMinMs + loop) ++stays;  // it played another loop first
    shown = s.variant, since = t, ++turns;
    seen[shown] = true;
  }
  for (int v = 0; v < 5; ++v) TEST_ASSERT_TRUE(seen[v]);
  for (int v = 5; v < 8; ++v) TEST_ASSERT_FALSE(seen[v]);
  TEST_ASSERT_TRUE(turns >= 40 && turns <= 110);  // about one every 8 s
  TEST_ASSERT_TRUE(stays > 0);

  // A pinned variation (dbg.look) shows at once.
  r.look(uint8_t((shown + 1) % 5));
  TEST_ASSERT_EQUAL((shown + 1) % 5, r.b.show(r.t).variant);

  // Needs you holds its variation, and so does a finish.
  Model a = attn();
  r.state(a);
  r.at(r.t);
  const int held = r.b.show(r.t).variant;
  for (uint32_t t = r.t; t <= r.t + 60000; t += 1000) {
    r.at(t);
    if (t % 10000 == 0) r.state(a);
    TEST_ASSERT_EQUAL(held, r.b.show(t).variant);
  }
  r.state(m);
  r.at(r.t + 20000);
  shown = r.b.lookVariant();
  ReactionIn c;
  c.anim = SceneState::kTaskComplete, c.loops = Behaviour::kMaxLoops;
  onReaction(r.b, c, r.t);
  uint32_t left;
  r.b.reaction(r.t, left);
  for (uint32_t t = r.t, end = r.t + left; t < end; t += 100) {
    r.at(t);
    TEST_ASSERT_EQUAL(shown, r.b.lookVariant());
  }
}

// The performance, with its knocks and ding, once when
// a needs-you starts, amber at half until it's answered, and nothing grows
// or nudges while it waits.
static void test_needs_you_alerts_once_and_stays_amber() {
  Rig r;
  r.at(1000);
  r.state(attn());
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kNeedsYou);
  TEST_ASSERT_EQUAL_STRING("alert@1000", r.alert().c_str());
  TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));
  // The performance plays once, then holds its pending pose.
  r.at(1000 + render::loopMs(render::Mood::kHappy, SceneState::kNeedsYou) + 500);
  SceneShow first = r.b.show(r.t);
  TEST_ASSERT_TRUE(first.state == SceneState::kNeedsYou);
  first.eyesShut = false;
  for (uint32_t t = 20000; t <= 300000; t += 10000) {
    r.at(t);
    r.state(attn());  // the same needs-you: the performance doesn't play again
    TEST_ASSERT_EQUAL_STRING("alert@1000", r.alert().c_str());
    TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(t));
    TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(t + 5000));
    SceneShow now = r.b.show(t);
    now.eyesShut = false;  // blinks go on
    TEST_ASSERT_TRUE(render::sceneFrame(first) == render::sceneFrame(now));  // nothing else moves
  }
  // A different needs-you plays the performance again, from its start.
  r.state(attn("other"));
  TEST_ASSERT_EQUAL_STRING("alert@300000", r.alert().c_str());
  TEST_ASSERT_EQUAL_UINT32(0, r.b.designMs(r.t));
  r.at(300000 + 400);
  TEST_ASSERT_EQUAL_UINT32(400, r.b.show(r.t).t);
}

// A different needs-you shown alerts once more, even with
// the same agent and project (two worktrees of one repo): the Mac numbers
// each needs-you in `attn.id`. More waiting behind it, a
// resent state, or a Mac too old to send a number, doesn't.
static void test_a_different_needs_you_with_the_same_names_alerts() {
  Rig r;
  r.at(1000);
  Model a = attn();
  a.attnId = 7;
  r.state(a);
  TEST_ASSERT_EQUAL_STRING("alert@1000", r.alert().c_str());
  r.at(2000);
  Model more = a;
  more.more = 1;
  r.state(more);  // another waits behind it: "+1" only
  r.state(more);  // resent
  TEST_ASSERT_EQUAL_STRING("alert@1000", r.alert().c_str());
  r.at(3000);
  Model b = attn();
  b.attnId = 8;
  r.state(b);  // the first answered: the other needs-you is shown
  TEST_ASSERT_EQUAL_STRING("alert@3000", r.alert().c_str());
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kNeedsYou);
  r.at(4000);
  r.state(attn());  // no number: agent and project alone, as before
  r.at(5000);
  r.state(attn());
  TEST_ASSERT_EQUAL_STRING("alert@4000", r.alert().c_str());
}

// A tap while something needs you is the press dip
// only, with no reaction, and it stays amber.
static void test_tap_during_needs_you_is_only_the_dip_and_stays_amber() {
  Rig r;
  r.state(attn());
  r.at(10000);
  const SceneShow before = r.b.show(r.t);
  r.b.pressDown(r.t);
  r.at(10100);
  TEST_ASSERT_EQUAL_INT(before.dy + Behaviour::kPressPx, r.b.show(r.t).dy);  // the press shows
  r.b.pressUp();
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  TEST_ASSERT_EQUAL(0u, r.b.reactionSeq());
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kNeedsYou);
  keepAlive(r, attn(), 125000);
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kNeedsYou);
  TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(r.t));
  TEST_ASSERT_EQUAL_STRING("alert@0", r.alert().c_str());
}

// Answered on the Mac, the face goes back to the base
// look with no reaction: the needs-you screen dissolves away, with no blink.
static void test_answering_on_the_mac_goes_back() {
  Rig r;
  r.state(attn());
  r.at(5000);
  r.state(base("working"));
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  TEST_ASSERT_TRUE(onFace(r.b, r.t));
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kWorking);
  TEST_ASSERT_FALSE(r.b.show(r.t).eyesShut);
  TEST_ASSERT_EQUAL(0u, r.b.reactionSeq());
}

// While something needs you, no animation plays and no
// `say` shows.
static void test_needs_you_wins_over_reactions() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("working"));
  r.react(SceneState::kTaskComplete);
  TEST_ASSERT_EQUAL(SceneState::kTaskComplete, r.anim());
  r.at(100);
  r.state(attn());  // needs you cuts the finish
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  r.react(SceneState::kTaskComplete);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  r.react(SceneState::kPoked);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  TEST_ASSERT_FALSE(r.say());  // a `say` on its own is ignored
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  ReactionIn say;
  say.anim = SceneState::kTaskComplete, say.said = true, say.take = voice::takeIndex(kGo);
  TEST_ASSERT_FALSE(onReaction(r.b, say, r.t));
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  // A `say` that was showing goes when something starts needing you.
  Rig m;
  m.state(base("idle"));
  TEST_ASSERT_TRUE(m.say());
  m.at(100);
  m.state(attn());
  TEST_ASSERT_NULL(m.b.bubble(m.t));
}

// Attention arriving under a finish (which it ends) or a poke shows the
// needs-you design at once, its clock starting at the change: its placard
// rises in on its own, with no blink.
static void test_changes_mid_motion_start_the_new_design() {
  const SceneState anims[] = {SceneState::kTaskComplete, SceneState::kPoked};
  const char* const bases[] = {"working", "idle"};
  for (int i = 0; i < 2; ++i) {
    for (uint32_t when : {300u, 650u}) {
      Rig r;
      r.state(base(bases[i]));
      r.react(anims[i]);
      r.at(when);
      r.state(attn());
      SceneShow s = r.b.show(r.t);
      TEST_ASSERT_TRUE(s.state == SceneState::kNeedsYou);
      TEST_ASSERT_FALSE(s.eyesShut);
      TEST_ASSERT_EQUAL_UINT32(0, s.t);
    }
  }
}

// The design a show draws. Asleep and no app share one design
// across moods, so a mood change there switches nothing.
static int designOf(const SceneShow& s) { return render::sceneOf(s.mood, s.state, s.variant); }

// The face's frame at t, drawn into `px` as Device draws one: `dirty`
// after a message, when an unchanged picture is drawn again too.
static void drawFace(Rig& r, std::vector<uint8_t>& px, bool dirty) {
  render::Canvas c{px.data()};
  r.b.face().draw(c, nullptr, r.b.show(r.t), r.t, r.b.bubble(r.t), r.b.sign(r.t), r.b.done(r.t), r.b.strip(r.t), dirty);
}
// The needs-you screen shows.
static bool needsYouShows(Rig& r) { return r.b.strip(r.t).agent && r.b.show(r.t).state == SceneState::kNeedsYou; }
// How many pixels above the lane two frames share.
static int alike(const std::vector<uint8_t>& a, const std::vector<uint8_t>& b) {
  int n = 0;
  for (int i = 0; i < render::kWidth * render::kLaneTop; ++i) n += a[i] == b[i];
  return n;
}
// A switch of design doesn't cut hard: it dissolves over the rig's fade,
// its first frame a sixteenth of the new design's pixels, so the frame
// just after it is the frame before but for at most an eighth of the
// pixels above the lane (the strip and the bubble come and go on their
// own).
static bool dissolves(const std::vector<uint8_t>& before, const std::vector<uint8_t>& after) {
  return render::kWidth * render::kLaneTop - alike(before, after) <= render::kWidth * render::kLaneTop / 8;
}

// A brain's reaction: a `say` with a mood, held for
// `loops` loops of the design it's drawn in.
static ReactionIn reaction(render::Mood mood, int loops = 2) {
  ReactionIn m;
  m.take = voice::takeIndex(kGo);
  m.expr = true, m.mood = mood, m.loops = loops;
  return m;
}

// An animation from the Mac, of `loops`, in the mood `mood` if it's given
// one (else Boop's), with a `say` when `take` names one.
static ReactionIn animated(SceneState a, int variant = 0, const char* take = nullptr, bool expr = false,
                         render::Mood mood = render::Mood::kHappy, int loops = 1) {
  ReactionIn m;
  m.anim = a, m.variant = uint8_t(variant), m.loops = loops;
  m.said = take != nullptr, m.take = voice::takeIndex(take);
  m.expr = expr, m.mood = mood;
  return m;
}

// Every way round: whatever state Boop is in, whatever is playing, and
// whatever arrives (any message or input), the design just after the
// change is the design just before it, at the same instant of its clock, or
// else the face dissolves from the one to the other, the needs-you screen
// too, into it, out of it and from one to another. The states
// span the first pack's moods and the new moods' flip-books and what the
// agents are doing; what plays includes a reaction's borrowed face, a
// finish in a mood, a rule's reaction and a poke; what arrives the same, a finish
// with its `say`, a reply and a mood change.
static void test_no_change_ever_cuts_hard() {
  using render::Mood;
  Model busy3 = base("working");
  busy3.busy = 3;
  Model muted = base("idle");
  muted.vol = 0;
  Model grumpy = base("idle");
  grumpy.mood = Mood::kGrumpy;
  Model sadAsleep = base("asleep");
  sadAsleep.mood = Mood::kSad;
  Model testing = base("working");
  testing.act = SceneState::kTesting;
  Model calm = base("idle");
  calm.mood = Mood::kCalm;
  Model woundedTerminal = base("working");
  woundedTerminal.mood = Mood::kWounded, woundedTerminal.act = SceneState::kTerminal;
  Model engagedAsleep = base("asleep");
  engagedAsleep.mood = Mood::kEngaged;
  Model irritatedAttn = attn();
  irritatedAttn.mood = Mood::kIrritated;
  const Model states[] = {base("idle"), base("working"), busy3, base("asleep"), attn(), attn("jetpack"), muted,
                          grumpy, sadAsleep, testing, calm, woundedTerminal, engagedAsleep, irritatedAttn};
  const int kStates = int(sizeof(states) / sizeof(states[0]));
  enum Playing {
    kNothing, kCheer, kWiggle, kSay, kCheerSay, kNoApp, kReaction, kMoodyCheer, kListening, kReplyWait,
    kRuleReaction, kCalmReaction, kFinishLine, kPlayingCount
  };
  const int kEvents = kStates + 14;  // every state, then the reactions and inputs
  int checked = 0;
  std::vector<uint8_t> was(size_t(render::kWidth) * render::kHeight), now(was.size());
  for (int from = 0; from < kStates; ++from) {
    for (int playing = 0; playing < kPlayingCount; ++playing) {
      for (int event = 0; event < kEvents; ++event) {
        for (uint32_t when : {40u, 333u, 1210u}) {
          Rig r;
          r.state(states[from]);
          r.at(500);
          switch (playing) {
            case kCheer: r.react(SceneState::kTaskComplete); break;
            case kWiggle: r.b.tap(r.t, r.rng); break;
            case kSay: r.say(); break;
            case kCheerSay: onReaction(r.b, animated(SceneState::kTaskComplete, 0, kGo), r.t); break;
            case kNoApp: r.at(500 + Behaviour::kNoAppMs); break;
            case kReaction: onReaction(r.b, reaction(Mood::kSad), r.t); break;
            case kMoodyCheer: onReaction(r.b, animated(SceneState::kTaskComplete, 1, nullptr, true, Mood::kExcited, 2), r.t); break;
            case kListening: r.talkOn(); break;
            case kReplyWait:
              r.talkOn();
              r.at(900);
              r.talkOff();
              break;
            case kRuleReaction: r.react(SceneState::kStarting); break;
            case kCalmReaction: onReaction(r.b, reaction(Mood::kCalm), r.t); break;
            case kFinishLine: onReaction(r.b, animated(SceneState::kTaskComplete, 3, "new.d14", true, Mood::kWhiny), r.t); break;
            default: break;
          }
          r.at(r.t + when);
          SceneShow before = r.b.show(r.t);
          drawFace(r, was, true);
          if (event < kStates) {
            r.state(states[event]);
          } else {
            switch (event - kStates) {
              case 0: r.react(SceneState::kTaskComplete); break;
              case 1: r.b.tap(r.t, r.rng); break;
              case 2: r.say(); break;
              case 3: r.react(SceneState::kPoked); break;
              case 4: onReaction(r.b, reaction(Mood::kProud, 3), r.t); break;
              case 5: r.talkOn(); break;
              case 6: r.talkOff(); break;
              case 7: r.stop(); break;
              case 8: r.react(SceneState::kListening); break;
              case 9: onReaction(r.b, animated(SceneState::kTaskComplete, 2, nullptr, true, Mood::kCurious, 3), r.t); break;
              case 10: r.react(SceneState::kError); break;
              case 11: onReaction(r.b, animated(SceneState::kReplyReady, 1, kGo, true, Mood::kAnnoyed), r.t); break;
              case 12: onReaction(r.b, reaction(Mood::kWounded), r.t); break;
              default: {
                Model m = r.b.model();
                m.mood = Mood::kEngaged;
                r.state(m);
                break;
              }
            }
          }
          SceneShow after = r.b.show(r.t);
          bool same = designOf(before) == designOf(after) && before.t == after.t;
          drawFace(r, now, true);
          if (!same && !dissolves(was, now)) {
            char why[160];
            std::snprintf(why, sizeof(why), "from state %d, playing %d, event %d at +%u ms: design %d at %u, then %d at %u",
                          from, playing, event, unsigned(when), designOf(before), unsigned(before.t), designOf(after),
                          unsigned(after.t));
            TEST_FAIL_MESSAGE(why);
          }
          ++checked;
        }
      }
    }
  }
  TEST_ASSERT_EQUAL(kStates * kPlayingCount * kEvents * 3, checked);
}

// A switch of design dissolves over the rig's fade (render::rig::kFadeMs,
// 200 ms), with no blink: from asleep's design to a finish's, each frame
// shows as much of the finish as the one before or more, by the face's
// ordered dither, and at 200 ms it's the finish whole, as a board that drew
// nothing before the switch draws it.
static void test_a_switch_dissolves_over_200_ms() {
  static_assert(render::rig::kFadeMs == 200, "a switch dissolves over the rig's 200 ms");
  Rig r, fresh;
  for (Rig* x : {&r, &fresh}) x->state(base("asleep")), x->at(1000);
  std::vector<uint8_t> px(size_t(render::kWidth) * render::kHeight), whole(px.size());
  drawFace(r, px, true);
  for (Rig* x : {&r, &fresh}) x->react(SceneState::kTaskComplete);
  int last = 0;
  for (uint32_t ms = 0; ms <= render::rig::kFadeMs; ms += 20) {
    for (Rig* x : {&r, &fresh}) x->at(1000 + ms);
    drawFace(r, px, true);
    drawFace(fresh, whole, true);
    int shown = 0;
    for (size_t i = 0; i < px.size(); ++i) shown += px[i] == whole[i];
    TEST_ASSERT_FALSE(r.b.show(r.t).eyesShut);
    TEST_ASSERT_TRUE(shown >= last);
    if (ms == 0) TEST_ASSERT_TRUE(shown < int(px.size()));  // some of asleep's still
    last = shown;
  }
  TEST_ASSERT_TRUE(px == whole);
}

// A design drawn whole into px, as a board that showed nothing else draws
// it, but for what's under the lane.
static void drawWhole(const SceneShow& s, std::vector<uint8_t>& px) {
  render::Canvas c{px.data()};
  c.fill(render::kBlack);
  render::drawScene(c, s);
}
// A second switch mid-way through a dissolve dissolves from the picture
// that shows more, as it last showed, whole: 100 ms (half way) and 190 ms
// (all but a frame) into idle's rig face dissolving into a finish, a
// wake-up comes in over the finish. Every pixel of every frame after is
// the finish's as it showed or the wake-up's: nothing of idle comes back,
// and the finish, a baked design, draws as one, with no rig face on it.
static void test_a_switch_mid_dissolve_dissolves_from_what_shows_more() {
  using render::rigFaced;
  for (uint32_t gap : {100u, 190u}) {
    Rig r;
    r.state(base("idle"));
    r.at(1000);
    std::vector<uint8_t> px(size_t(render::kWidth) * render::kHeight), finish(px.size()), wake(px.size());
    drawFace(r, px, true);
    SceneShow s = r.b.show(r.t);
    TEST_ASSERT_TRUE(rigFaced(s.mood, s.state, s.variant));
    r.react(SceneState::kTaskComplete);
    for (uint32_t ms = 10; ms <= gap; ms += 10) {
      r.at(1000 + ms);
      drawFace(r, px, true);
    }
    const SceneShow was = r.b.show(r.t);
    TEST_ASSERT_EQUAL(int(SceneState::kTaskComplete), int(was.state));
    TEST_ASSERT_EQUAL_STRING("happy", render::moodName(was.mood));
    TEST_ASSERT_FALSE(rigFaced(was.mood, was.state, was.variant));
    drawWhole(was, finish);
    r.react(SceneState::kWakeUp);
    TEST_ASSERT_EQUAL(SceneState::kWakeUp, r.anim());
    for (uint32_t ms = 0; ms <= render::rig::kFadeMs; ms += 20) {
      r.at(1000 + gap + ms);
      drawFace(r, px, true);
      s = r.b.show(r.t);
      TEST_ASSERT_FALSE(rigFaced(s.mood, s.state, s.variant));
      drawWhole(s, wake);
      for (int i = 0; i < render::kWidth * render::kLaneTop; ++i) {
        if (px[i] != finish[i] && px[i] != wake[i]) {
          char why[96];
          std::snprintf(why, sizeof why, "+%u ms, then +%u ms: pixel %d is neither's", unsigned(gap), unsigned(ms), i);
          TEST_FAIL_MESSAGE(why);
        }
      }
    }
  }
}

// The needs-you screen dissolves as a picture, its lane in it, both ways
// over the rig's fade: 100 ms into a switch from asleep's design to it, and
// from it back to asleep's, every pixel of the frame is one of the two
// pictures' as a board that drew nothing before draws each whole, above
// the lane the one the dither gives it, and it holds some of each.
static void test_the_needs_you_screen_dissolves_both_ways() {
  const render::Dither in = render::Dither::fade(render::ease1000(100, int(render::rig::kFadeMs)), true);
  for (bool into : {true, false}) {
    Rig r, fresh;
    const Model from = into ? base("asleep") : attn(), to = into ? attn() : base("asleep");
    for (Rig* x : {&r, &fresh}) x->state(from), x->at(3000);
    std::vector<uint8_t> was(size_t(render::kWidth) * render::kHeight), px(was.size()), whole(was.size());
    drawFace(r, was, true);
    TEST_ASSERT_EQUAL(!into, needsYouShows(r));
    for (Rig* x : {&r, &fresh}) x->state(to), x->at(3100);
    TEST_ASSERT_EQUAL(into, needsYouShows(r));
    drawFace(r, px, true);
    drawFace(fresh, whole, true);
    int ofWas = 0, ofNew = 0;
    for (int y = 0; y < render::kHeight; ++y) {
      for (int x = 0; x < render::kWidth; ++x) {
        const size_t i = size_t(y) * render::kWidth + x;
        if (px[i] != was[i] && px[i] != whole[i]) {
          char why[96];
          std::snprintf(why, sizeof why, "%s: pixel (%d, %d) is neither's", into ? "into" : "out of", x, y);
          TEST_FAIL_MESSAGE(why);
        }
        if (y < render::kLaneTop) TEST_ASSERT_EQUAL_UINT8(in.draws(x, y) ? whole[i] : was[i], px[i]);
        ofWas += px[i] == was[i] && px[i] != whole[i], ofNew += px[i] == whole[i] && px[i] != was[i];
      }
    }
    TEST_ASSERT_TRUE(ofWas > 1000 && ofNew > 1000);
  }
}

// A switch back mid-way through the needs-you screen's dissolve dissolves
// from the picture that shows more, as it last showed, so neither pops:
// answered 150 ms into asleep dissolving into it, every pixel of the
// screen that showed still shows in the frame just after, but for the new
// dissolve's first sixteenth; answered 50 ms in, every pixel of asleep's.
static void test_a_switch_back_mid_needs_you_dissolve_doesnt_pop() {
  for (uint32_t gap : {50u, 150u}) {
    Rig r;
    r.state(base("asleep"));
    r.at(3000);
    std::vector<uint8_t> before(size_t(render::kWidth) * render::kHeight), after(before.size());
    drawFace(r, before, true);
    r.state(attn());
    for (uint32_t ms = 10; ms <= gap; ms += 10) {
      r.at(3000 + ms);
      drawFace(r, before, true);
    }
    TEST_ASSERT_TRUE(needsYouShows(r));
    r.state(base("asleep"));
    drawFace(r, after, true);
    const render::Dither shown = render::Dither::fade(render::ease1000(int(gap), int(render::rig::kFadeMs)), true);
    const render::Dither more = gap > render::rig::kFadeMs / 2 ? shown : render::Dither{shown.hi, 16};
    const render::Dither stays = more.both({1, 16});
    int kept = 0;
    for (int y = 0; y < render::kLaneTop; ++y) {
      for (int x = 0; x < render::kWidth; ++x) {
        if (!stays.draws(x, y)) continue;
        const size_t i = size_t(y) * render::kWidth + x;
        TEST_ASSERT_EQUAL_UINT8(before[i], after[i]);
        kept += before[i] != render::kBlack;
      }
    }
    TEST_ASSERT_TRUE(kept > 100);
  }
}

// Two taps 150 ms apart: the second poke dissolves from the first as it
// showed, which shows more by then, so idle doesn't flash back between
// them. The frame just after the second shares no more of idle's pixels
// than the frame just before it.
static void test_a_double_tap_doesnt_flash_back() {
  Rig r;
  r.state(base("idle"));
  r.at(1000);
  std::vector<uint8_t> idle(size_t(render::kWidth) * render::kHeight), before(idle.size()), after(idle.size());
  drawFace(r, idle, true);
  r.b.tap(r.t, r.rng);
  for (uint32_t ms = 20; ms <= 150; ms += 10) {
    r.at(1000 + ms);
    drawFace(r, before, true);
  }
  TEST_ASSERT_TRUE(alike(before, idle) < render::kWidth * render::kLaneTop);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(SceneState::kPoked, r.anim());
  drawFace(r, after, true);
  TEST_ASSERT_TRUE(alike(after, idle) <= alike(before, idle));
}

// A reaction's design plays its own moves, under no look's clip: poked
// while asleep, the rig face is the poke's design as drawn, its eyes open,
// not shut by asleep's doze.
static void test_a_poke_while_asleep_has_its_own_eyes() {
  Rig r;
  r.state(base("asleep"));
  r.at(1000);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(SceneState::kPoked, r.anim());
  r.at(1400);  // the dissolve over, and asleep's clip faded out
  const SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(render::rigFaced(s.mood, s.state, s.variant));
  TEST_ASSERT_FALSE(render::faceMove(s).shut);
  std::vector<uint8_t> px(size_t(render::kWidth) * render::kHeight), poke(px.size());
  drawFace(r, px, true);
  drawWhole(s, poke);
  TEST_ASSERT_EQUAL_INT(render::kWidth * render::kLaneTop, alike(px, poke));
}

// A press kicks the rig face only if it began while the rig face showed:
// held on the needs-you screen through its dismissal, the face that
// dissolves in isn't poked (it draws as one with no finger); a press that
// begins on it squashes it.
static void test_only_a_press_on_the_rig_face_kicks_it() {
  Rig held, none, pressed;
  std::vector<uint8_t> a(size_t(render::kWidth) * render::kHeight), b(a.size()), c(a.size());
  for (Rig* r : {&held, &none, &pressed}) {
    r->state(attn());
    r->at(1000);
  }
  drawFace(held, a, true);
  drawFace(none, b, true);
  drawFace(pressed, c, true);
  TEST_ASSERT_TRUE(needsYouShows(held));
  held.b.face().finger(true, 160, 120);
  for (Rig* r : {&held, &none, &pressed}) {
    r->at(1500);
    r->state(base("idle"));
  }
  const SceneShow s = held.b.show(held.t);
  TEST_ASSERT_TRUE(render::rigFaced(s.mood, s.state, s.variant));
  bool squashed = false;
  for (uint32_t ms = 0; ms <= 600; ms += 20) {
    held.at(1500 + ms), none.at(1500 + ms), pressed.at(1500 + ms);
    held.b.face().finger(true, 160, 120);  // as the board says it each frame
    drawFace(held, a, true);
    drawFace(none, b, true);
    drawFace(pressed, c, true);
    if (ms == 200) pressed.b.face().finger(true, 160, 120);
    TEST_ASSERT_TRUE(a == b);
    squashed = squashed || c != b;
  }
  TEST_ASSERT_TRUE(squashed);
}

// The lane draws its opacity as a dither level, and so a frame is keyed by
// it: one whose strip's opacity differs from the last frame's only within a
// level isn't drawn again; another level is.
static void test_a_lane_at_the_same_dither_level_isnt_drawn_again() {
  Rig r;
  r.state(base("idle"));
  r.at(1000);
  std::vector<uint8_t> px(size_t(render::kWidth) * render::kHeight);
  render::Canvas c{px.data()};
  render::Strip strip = r.b.strip(r.t);
  auto draw = [&](int opacity, bool dirty) {
    strip.opacity = opacity;
    return r.b.face().draw(c, nullptr, r.b.show(r.t), r.t, nullptr, r.b.sign(r.t), r.b.done(r.t), strip, dirty);
  };
  TEST_ASSERT_EQUAL_INT(8, render::Dither::fade(500, true).hi);
  TEST_ASSERT_EQUAL_INT(8, render::Dither::fade(530, true).hi);
  TEST_ASSERT_TRUE(draw(500, true));
  TEST_ASSERT_FALSE(draw(530, false));
  TEST_ASSERT_TRUE(draw(600, false));
}

// Over time: as whatever plays runs out on its own (a finish's loops, a
// reaction's borrowed face at its loop boundary, over a look, over the
// finish or across a look change, a poke, a rule's reaction, a `say`, a finish
// held on for its `say`, the Mac going quiet), the face never cuts hard.
// From one 20 ms frame to the next the design goes on at the same instant of
// its clock, or the face dissolves from the one to the other. An animation's design
// starting over at each of its loop boundaries is its clock going on, and
// so is resting on its last frame.
static void test_nothing_cuts_hard_as_it_plays_out() {
  using render::Mood;
  Model grumpyWorking = base("working");
  grumpyWorking.mood = Mood::kGrumpy;
  Model proudIdle = base("idle");
  proudIdle.mood = Mood::kProud;
  Model calmWorking = base("working");
  calmWorking.mood = Mood::kCalm;
  Model whinyTesting = base("working");
  whinyTesting.mood = Mood::kWhiny, whinyTesting.act = SceneState::kTesting;
  const Model states[] = {base("idle"), grumpyWorking, proudIdle, base("asleep"), calmWorking, whinyTesting};
  enum Playing {
    kCheer1, kCheer3, kMoodyCheer, kReaction, kSameMood, kLongReaction, kOverCheer, kAcrossLook, kCheerEnds,
    kWiggle, kSay, kQuiet, kRuleReaction, kFinishLine, kNewMoodReaction, kPlayingCount
  };
  int frames = 0;
  std::vector<uint8_t> was(size_t(render::kWidth) * render::kHeight), now(was.size());
  for (const Model& m : states) {
    for (int playing = 0; playing < kPlayingCount; ++playing) {
      Rig r;
      r.state(m);
      r.at(777);
      ReactionIn cheer;
      cheer.anim = SceneState::kTaskComplete;
      switch (playing) {
        case kCheer1: onReaction(r.b, cheer, r.t); break;
        case kCheer3: cheer.loops = 3, onReaction(r.b, cheer, r.t); break;
        case kMoodyCheer:
          cheer.loops = 2, cheer.expr = true, cheer.mood = Mood::kSad;
          onReaction(r.b, cheer, r.t);
          break;
        case kReaction: onReaction(r.b, reaction(Mood::kExcited, 2), r.t); break;
        case kSameMood: onReaction(r.b, reaction(m.mood, 2), r.t); break;
        case kLongReaction: onReaction(r.b, reaction(Mood::kCurious, 6), r.t); break;
        case kOverCheer:
          cheer.loops = 2, onReaction(r.b, cheer, r.t);
          r.at(r.t + 700);
          onReaction(r.b, reaction(Mood::kDetermined, 1), r.t);
          break;
        case kAcrossLook:
          onReaction(r.b, reaction(Mood::kSad, 3), r.t);
          break;
        case kCheerEnds:  // a reaction late in the finish holds past its end
          onReaction(r.b, cheer, r.t);
          r.at(r.t + 1900);
          onReaction(r.b, reaction(Mood::kHappy, 2), r.t);
          break;
        case kWiggle: r.b.tap(r.t, r.rng); break;
        case kSay: r.say(); break;
        case kRuleReaction: r.react(SceneState::kHelperReturn); break;
        case kFinishLine: onReaction(r.b, animated(SceneState::kTaskComplete, 4, "new.d20", true, Mood::kGrumpy), r.t); break;
        case kNewMoodReaction: onReaction(r.b, reaction(Mood::kIrritated, 2), r.t); break;
        default: break;
      }
      SceneShow before = r.b.show(r.t);
      drawFace(r, now, true);
      const uint32_t end = playing == kQuiet ? Behaviour::kNoAppMs + 2000 : r.t + 60000;
      bool moved = false;
      uint32_t alive = r.t + 10000;
      for (uint32_t t = r.t + 20; t <= end; t += 20) {
        r.at(t);
        if (playing == kAcrossLook && !moved && t >= 2000) {
          r.state(base(m.base == SceneState::kIdle ? "working" : "idle"));
          moved = true;
        }
        if (playing != kQuiet && t >= alive) r.state(r.b.model()), alive += 10000;  // the Mac's keepalive
        SceneShow after = r.b.show(t);
        bool same = designOf(before) == designOf(after);
        uint32_t next = before.t + 20;
        bool animation = after.state != r.b.model().look() && after.state != SceneState::kNeedsYou &&
                         after.state != SceneState::kNoApp;
        if (same && animation) next %= loopMs(after.mood, after.state, after.variant);
        bool rests = same && animation && after.t >= before.t && after.t - before.t <= 20;
        const bool goesOn = same && (after.t == next || rests);
        if (!goesOn) was = now;
        drawFace(r, now, false);
        if (!goesOn && !dissolves(was, now)) {
          char why[112];
          std::snprintf(why, sizeof(why), "state %d/%d, playing %d: design %d at %u, then %d at %u, at t=%u",
                        int(m.base), int(m.mood), playing, designOf(before), unsigned(before.t), designOf(after),
                        unsigned(after.t), unsigned(t));
          TEST_FAIL_MESSAGE(why);
        }
        before = after;
        ++frames;
      }
    }
  }
  TEST_ASSERT_TRUE(frames > 100000);
}

// No app holds however long the Mac stays away, even
// past the 24.9 days where the clock's differences wrap, and whatever had
// finished stays finished when they come round again at 49.7 days: the
// no-app design, no old `say`, press dip or backlight fade.
static void test_no_app_holds_for_weeks() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("working"));
  r.at(1000);
  TEST_ASSERT_TRUE(r.say());  // over by 2500
  r.b.pressDown(r.t);
  r.at(1100);
  r.b.pressUp();
  r.at(Behaviour::kNoAppMs);
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kNoApp);
  const uint32_t start = Behaviour::kNoAppMs + 200;
  r.at(start);
  const SceneShow noApp = r.b.show(start);
  TEST_ASSERT_TRUE(noApp.state == SceneState::kNoApp);
  // The clock moves on a minute at a time, as the ticks would take it.
  uint64_t now = start;
  auto walk = [&](uint64_t to) {
    while (now + 60000 < to) now += 60000, r.at(uint32_t(now));
    now = to;
    r.at(uint32_t(now));
  };
  // The no-app design repeats every loop.
  const uint64_t loop = render::loopMs(render::Mood::kHappy, SceneState::kNoApp);
  walk(start + loop * ((1ull << 31) / loop + 1));  // past 2^31 ms, on a whole loop after the switch to no app
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kNoApp);
  TEST_ASSERT_TRUE(render::sceneFrame(noApp) == render::sceneFrame(r.b.show(r.t)));
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  walk(0x100000000ull + 1150);  // 2^32 ms after the release, 150 after the `say` started
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  // No `say`'s bubble or mouth, no press, no blink: only the design.
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kNoApp);
  TEST_ASSERT_FALSE(s.mouthOpen);
  TEST_ASSERT_FALSE(s.eyesShut);
  TEST_ASSERT_EQUAL_INT(0, s.dy);
  walk(0x100000000ull + Behaviour::kNoAppMs + 50);  // 2^32 ms after the dimming began
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kNoApp);
  r.state(base("idle"));
  TEST_ASSERT_TRUE(onFace(r.b, r.t));
}

// ---- Push-to-talk ----------------------------------------------------------

// Push-to-talk shows listening at once, in the mood's
// listening design, and on release the same design carries on, with no
// new blend, while it waits for the reply.
static void test_push_to_talk_listens_then_waits() {
  Rig r;
  Model m = base("working");
  m.mood = render::Mood::kGrumpy;
  r.state(m);
  r.talkOn();
  TEST_ASSERT_EQUAL(SceneState::kListening, r.anim());
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kListening);
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kListening);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kGrumpy);
  TEST_ASSERT_EQUAL_UINT32(0, s.t);  // its design from the start
  r.at(2000);
  const SceneShow held = r.b.show(r.t);
  TEST_ASSERT_EQUAL_UINT32(2000 % loopMs(render::Mood::kGrumpy, SceneState::kListening, held.variant), held.t);
  const uint32_t seq = r.b.reactionSeq();
  r.talkOff();
  TEST_ASSERT_EQUAL(SceneState::kListening, r.anim());
  TEST_ASSERT_EQUAL(seq, r.b.reactionSeq());  // the same reaction
  const SceneShow after = r.b.show(r.t);
  TEST_ASSERT_TRUE(after.state == held.state && after.variant == held.variant && after.t == held.t);
  TEST_ASSERT_FALSE(after.eyesShut);  // no blend
}

// Listening holds until the reply. Another animation (a
// finish, a poke) doesn't replace it, and a tap shows only the press dip.
// Any reaction with a `say` is the reply: it ends listening, then plays as
// it would have, its finish and its face included.
static void test_listening_holds_until_the_reply() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));
  r.talkOn();
  r.at(500);
  r.b.tap(r.t, r.rng);  // a touch while BOOT is held
  TEST_ASSERT_EQUAL(SceneState::kListening, r.anim());
  r.at(1000);
  r.talkOff();
  r.at(2000);
  const uint32_t seq = r.b.reactionSeq();
  r.react(SceneState::kTaskComplete);
  r.react(SceneState::kPoked);
  r.b.tap(r.t, r.rng);
  uint32_t left;
  TEST_ASSERT_EQUAL(SceneState::kListening, r.b.reaction(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(Behaviour::kReplyWaitMs - 1000, left);  // the wait runs on
  TEST_ASSERT_EQUAL(seq, r.b.reactionSeq());
  ReactionIn skipped;  // a reaction the Mac waits on, refused: the kit skips it
  skipped.anim = SceneState::kTaskComplete, skipped.key = 7;
  TEST_ASSERT_EQUAL_STRING("listening", r.b.admit(skipped, r.t));
  app::PlayedOut e;
  TEST_ASSERT_FALSE(r.b.takePlayedOut(e));
  // The brain's reply: a finish with a `say` in proud's face, its `say` at
  // the design's voice window.
  ReactionIn reply;
  reply.anim = SceneState::kTaskComplete, reply.said = true, reply.take = voice::takeIndex(kGo);
  reply.expr = true, reply.mood = render::Mood::kProud, reply.key = 8;
  TEST_ASSERT_TRUE(onReaction(r.b, reply, r.t));
  TEST_ASSERT_EQUAL(SceneState::kTaskComplete, r.anim());
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_TRUE(r.b.sayAhead(r.t));
  render::Mood mood;
  TEST_ASSERT_TRUE(r.b.expression(r.t, mood) && mood == render::Mood::kProud);
  TEST_ASSERT_FALSE(r.b.takePlayedOut(e));  // it plays
  r.at(r.t + render::pixel::score(render::pixelIndex(render::Mood::kProud), int(SceneState::kTaskComplete), 0).voiceMs);
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  // A `say` on its own ends it too, and plays over the look.
  Rig s;
  s.state(base("idle"));
  s.talkOn();
  s.at(700);
  TEST_ASSERT_TRUE(s.say());
  TEST_ASSERT_EQUAL(SceneState::kNone, s.anim());
  TEST_ASSERT_NOT_NULL(s.b.bubble(s.t));
  TEST_ASSERT_TRUE(s.b.show(s.t).state == SceneState::kIdle);
}

// While something needs you, listening is the one reaction
// that plays; one showing when needs you starts plays on. The reply can't
// show, but it ends listening.
static void test_listening_plays_while_something_needs_you() {
  Rig a;
  a.state(attn());
  a.talkOn();
  TEST_ASSERT_EQUAL(SceneState::kListening, a.anim());
  TEST_ASSERT_TRUE(a.b.look(a.t) == SceneState::kNeedsYou);
  TEST_ASSERT_TRUE(a.b.show(a.t).state == SceneState::kListening);
  a.at(500);
  a.react(SceneState::kTaskComplete);
  TEST_ASSERT_EQUAL(SceneState::kListening, a.anim());
  TEST_ASSERT_FALSE(a.say());
  TEST_ASSERT_EQUAL(SceneState::kNone, a.anim());
  TEST_ASSERT_NULL(a.b.bubble(a.t));
  TEST_ASSERT_TRUE(a.b.show(a.t).state == SceneState::kNeedsYou);
  // The Mac's own listening plays too, and survives a new needs-you.
  Rig m;
  m.state(base("idle"));
  m.react(SceneState::kListening);
  m.at(300);
  m.state(attn());
  TEST_ASSERT_EQUAL(SceneState::kListening, m.anim());
  m.at(400);
  m.state(attn("jetpack"));
  TEST_ASSERT_EQUAL(SceneState::kListening, m.anim());
  m.stop();
  TEST_ASSERT_EQUAL(SceneState::kNone, m.anim());
}

// stop_listening (empty) ends listening and does nothing
// else. It never ends a finish, a poke or a `say`.
static void test_the_empty_reaction_ends_only_listening() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));
  r.react(SceneState::kListening);  // from the Mac: its own mic is on
  r.at(4000);
  TEST_ASSERT_EQUAL(SceneState::kListening, r.anim());
  r.stop();
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  // After the release, too.
  r.at(r.t + 1000);
  r.talkOn();
  r.at(r.t + 1000);
  r.talkOff();
  r.at(r.t + 2000);
  r.stop();
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  // Nothing playing: nothing happens.
  const uint32_t seq = r.b.reactionSeq();
  r.at(r.t + 1000);
  r.stop();
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  TEST_ASSERT_EQUAL(seq, r.b.reactionSeq());
  // A finish, a poke and a `say` carry on.
  r.react(SceneState::kTaskComplete);
  r.at(r.t + 100);
  r.stop();
  TEST_ASSERT_EQUAL(SceneState::kTaskComplete, r.anim());
  r.react(SceneState::kPoked);
  r.stop();
  TEST_ASSERT_EQUAL(SceneState::kPoked, r.anim());
  r.at(r.t + 1000);
  TEST_ASSERT_TRUE(r.say());
  r.stop();
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_EQUAL(seq + 3, r.b.reactionSeq());  // finish, poke, `say`; the stops add none
}

// Listening lasts at most kListenMs (30 s) of talking and
// then kReplyWaitMs (8 s) for the reply; the release cuts the wait to 8 s
// from then. With no reply, the face blends back with nothing else.
static void test_push_to_talk_timeouts() {
  TEST_ASSERT_EQUAL_UINT32(30000, Behaviour::kListenMs);
  TEST_ASSERT_EQUAL_UINT32(8000, Behaviour::kReplyWaitMs);
  Model m = base("idle");
  Rig r;
  r.state(m);
  r.talkOn();
  keepAlive(r, m, 3000);
  r.talkOff();
  uint32_t left;
  TEST_ASSERT_EQUAL(SceneState::kListening, r.b.reaction(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(8000, left);
  keepAlive(r, m, 3000 + 7999);
  TEST_ASSERT_EQUAL(SceneState::kListening, r.anim());
  r.at(3000 + 8000);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());  // no reply came
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kIdle);
  // BOOT's own 30 s cap is a release: 8 s more for the reply.
  Rig c;
  c.state(m);
  c.talkOn();
  keepAlive(c, m, 30000);
  c.talkOff();
  keepAlive(c, m, 30000 + 7999);
  TEST_ASSERT_EQUAL(SceneState::kListening, c.anim());
  c.at(38000);
  TEST_ASSERT_EQUAL(SceneState::kNone, c.anim());
  c.talkOff();  // a late release has nothing to wait on
  TEST_ASSERT_EQUAL(SceneState::kNone, c.anim());
  // The Mac's listening, with no release on the device, holds 38 s at most.
  Rig k;
  k.state(m);
  k.react(SceneState::kListening);
  TEST_ASSERT_EQUAL(SceneState::kListening, k.b.reaction(k.t, left));
  TEST_ASSERT_EQUAL_UINT32(38000, left);
  // Held on the device while the Mac listens: the same face, time topped up.
  k.at(5000);
  const uint32_t seq = k.b.reactionSeq();
  k.talkOn();
  TEST_ASSERT_EQUAL(seq, k.b.reactionSeq());
  TEST_ASSERT_EQUAL(SceneState::kListening, k.b.reaction(k.t, left));
  TEST_ASSERT_EQUAL_UINT32(38000, left);
  k.talkOff();
  TEST_ASSERT_EQUAL(SceneState::kListening, k.b.reaction(k.t, left));
  TEST_ASSERT_EQUAL_UINT32(8000, left);
}

// Which variation of listening shows is picked at random,
// never the last one; a `variant` the Mac sends is shown as it says.
static void test_listening_rotates_its_variations() {
  TEST_ASSERT_EQUAL_INT(3, render::variants(render::Mood::kHappy, SceneState::kListening));
  Rig r;
  r.state(base("idle"));
  int last = -1;
  bool seen[3] = {};
  for (int i = 0; i < 60; ++i) {
    r.state(base("idle"));  // the Mac's keepalive: no app would show over listening
    r.talkOn();
    int v = r.b.show(r.t).variant;
    TEST_ASSERT_NOT_EQUAL(last, v);
    seen[v] = true, last = v;
    r.talkOff();
    r.stop();
    r.at(r.t + 1000);
  }
  for (bool s : seen) TEST_ASSERT_TRUE(s);
  ReactionIn m;
  m.anim = SceneState::kListening, m.variant = 2;
  onReaction(r.b, m, r.t);
  TEST_ASSERT_EQUAL_INT(2, r.b.show(r.t).variant);
  TEST_ASSERT_NOT_EQUAL(2, r.b.pick(SceneState::kListening, render::Mood::kHappy, 0, render::Outcome::kNone, render::StartCtx::kNone, r.rng));
}

// The finish plays its loops of the mood's task-complete
// design, one unless the reaction says more, with no light; a new reaction
// replaces the one playing.
static void test_reactions_end_and_replace() {
  Rig r;
  r.state(base("idle"));
  r.react(SceneState::kTaskComplete);
  const uint32_t loop = loopMs(render::Mood::kHappy, SceneState::kTaskComplete);
  r.at(loop - 1);
  TEST_ASSERT_EQUAL(SceneState::kTaskComplete, r.anim());
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));
  TEST_ASSERT_EQUAL_STRING("", r.alert().c_str());
  r.at(loop);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  r.react(SceneState::kTaskComplete);
  r.at(r.t + 10);
  r.react(SceneState::kPoked);  // a new reaction replaces the old one
  TEST_ASSERT_EQUAL(SceneState::kPoked, r.anim());
  const uint32_t start = r.t, poke = loopMs(render::Mood::kHappy, SceneState::kPoked);
  r.at(start + poke - 1);
  TEST_ASSERT_EQUAL(SceneState::kPoked, r.anim());
  r.at(start + poke);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
}

// An animation's `loops` is how many times its design
// plays, each time from its start, timed by the design of the mood it's
// drawn in.
static void test_a_cheer_plays_its_loops() {
  Rig r;
  Model m = base("working");
  m.mood = render::Mood::kProud;
  r.state(m);
  r.at(1000);
  ReactionIn in;
  in.anim = SceneState::kTaskComplete, in.loops = 3;
  onReaction(r.b, in, r.t);
  const uint32_t loop = loopMs(render::Mood::kProud, SceneState::kTaskComplete);
  uint32_t left;
  TEST_ASSERT_EQUAL(SceneState::kTaskComplete, r.b.reaction(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(3 * loop, left);
  TEST_ASSERT_EQUAL_UINT32(loop - 1, r.b.show(1000 + loop - 1).t);
  SceneShow s = r.b.show(1000 + loop + 100);
  TEST_ASSERT_TRUE(s.state == SceneState::kTaskComplete);
  TEST_ASSERT_EQUAL_UINT32(100, s.t);  // the design starts over
  r.at(1000 + 3 * loop - 1);
  TEST_ASSERT_EQUAL(SceneState::kTaskComplete, r.anim());
  r.at(1000 + 3 * loop);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  // Drawn in a reaction's mood, the finish's loops are that mood's design's.
  r.at(20000);
  r.state(m);
  in.loops = 1, in.expr = true, in.mood = render::Mood::kSad;
  onReaction(r.b, in, r.t);
  r.b.reaction(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(loopMs(render::Mood::kSad, SceneState::kTaskComplete), left);
  ReactionIn w;  // the dashboard's poke too
  w.anim = SceneState::kPoked, w.loops = 4;
  onReaction(r.b, w, r.t);
  r.b.reaction(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(4 * loopMs(render::Mood::kProud, SceneState::kPoked), left);
}

// The bubble shows the take's text, the `say` speaks for the
// take's length, and the mouth is an "o" while the take is loud (its mouth
// frames, voice::mouthOpen), shut once it's said.
static void test_a_take_moves_the_mouth() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));
  ReactionIn m;
  m.said = true, m.take = voice::takeIndex(kGo);
  TEST_ASSERT_TRUE(onReaction(r.b, m, r.t));
  TEST_ASSERT_EQUAL_STRING("Go", r.b.bubble(r.t));
  TEST_ASSERT_EQUAL(m.take, r.b.take());
  TEST_ASSERT_TRUE(r.b.speaking(kGoMs - 1));  // 7042 samples at 11.025 kHz
  TEST_ASSERT_FALSE(r.b.speaking(kGoMs));
  int open = 0, shut = 0;
  for (uint32_t t = 0; t < kGoMs; ++t) {
    TEST_ASSERT_EQUAL(voice::mouthOpen(m.take, t), r.b.show(t).mouthOpen);
    (r.b.show(t).mouthOpen ? open : shut)++;
  }
  TEST_ASSERT_TRUE(open > 0 && shut > 0);
  TEST_ASSERT_FALSE(r.b.show(kGoMs).mouthOpen);
  TEST_ASSERT_FALSE(r.b.show(kGoMs + 500).mouthOpen);  // the bubble stays, the mouth shut
  TEST_ASSERT_NOT_NULL(r.b.bubble(kGoMs + 500));
}

// A `say` of two takes shows both words, speaks for both
// and the gap between them, and moves the mouth for each.
static void test_a_say_of_two_takes() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));
  ReactionIn m;
  m.said = true, m.take = voice::takeIndex("previous.tsk");
  m.then = voice::takeIndex("phase1.word.test.test__annoyed__contained");
  TEST_ASSERT_TRUE(onReaction(r.b, m, r.t));
  TEST_ASSERT_EQUAL_STRING("Tsk... Test", r.b.bubble(r.t));
  const uint32_t ms = 1377 + voice::kJoinGapMs + 868;
  TEST_ASSERT_TRUE(r.b.speaking(ms - 1));
  TEST_ASSERT_FALSE(r.b.speaking(ms));
  for (uint32_t t = 0; t < ms; t += 7) TEST_ASSERT_EQUAL(voice::sayMouthOpen(m.take, m.then, t), r.b.show(t).mouthOpen);
  TEST_ASSERT_NOT_NULL(r.b.bubble(ms + Behaviour::kBubbleReadMs - 1));
  TEST_ASSERT_NULL(r.b.bubble(ms + Behaviour::kBubbleReadMs));
}

// The first millisecond the mouth is open into take `id`.
static uint32_t firstOpen(const char* id) {
  uint32_t t = 0;
  while (!voice::mouthOpen(voice::takeIndex(id), t)) ++t;
  return t;
}

// A `say` on its own plays over whatever
// face is showing and doesn't change it. The bubble stays for the take
// and 1.2 s to read.
static void test_a_say_alone_plays_over_the_face() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("working"));
  r.at(1000);
  TEST_ASSERT_TRUE(r.say());
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kWorking);
  TEST_ASSERT_TRUE(r.b.speaking(1000 + kGoMs - 1));
  TEST_ASSERT_FALSE(r.b.speaking(1000 + kGoMs));
  TEST_ASSERT_TRUE(r.b.show(1000 + firstOpen(kGo)).mouthOpen);
  TEST_ASSERT_TRUE(r.b.show(1500).state == SceneState::kWorking);  // the face goes on as it was
  r.at(1000 + kGoMs + Behaviour::kBubbleReadMs - 1);
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  r.at(1000 + kGoMs + Behaviour::kBubbleReadMs);
  TEST_ASSERT_NULL(r.b.bubble(r.t));

  // Over a finish, the finish keeps its own timing.
  r.at(10000);
  r.react(SceneState::kTaskComplete);
  r.at(10500);
  r.say();
  uint32_t left;
  TEST_ASSERT_EQUAL(SceneState::kTaskComplete, r.b.reaction(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(loopMs(render::Mood::kHappy, SceneState::kTaskComplete) - 500, left);
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  // A tap's poke replaces the reaction's animation; the `say` plays on.
  r.at(10600);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(SceneState::kPoked, r.anim());
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));

  // A `say` with no take is nothing.
  Rig e;
  e.state(base("idle"));
  TEST_ASSERT_FALSE(e.say(nullptr));
  TEST_ASSERT_EQUAL(0u, e.b.reactionSeq());
}

// A face on its own (a mood, no animation, no `say`) plays
// that face for its loops, exactly as a face with a `say` would, and a
// reaction the Mac waits on ends done when it's over. A `say` playing plays
// on under it. While something needs you, or with no app, it's skipped.
static std::string ended(Rig& r);
static void test_a_face_alone_plays_its_loops() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));
  r.at(1000);
  ReactionIn f;
  f.expr = true, f.mood = render::Mood::kProud, f.loops = 2, f.key = 30;
  const uint32_t loop = loopMs(render::Mood::kProud, SceneState::kIdle, r.b.lookVariant());
  const uint32_t end = r.t + loop - r.b.designMs(r.t) % loop + loop;
  TEST_ASSERT_FALSE(onReaction(r.b, f, r.t));  // no `say`
  render::Mood e;
  TEST_ASSERT_TRUE(r.b.expression(r.t, e) && e == render::Mood::kProud);
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kProud);
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  r.at(end - 1);
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(end);
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  TEST_ASSERT_EQUAL_STRING("30 done", ended(r).c_str());
  // Under a `say` playing, the `say` plays on.
  r.at(20000);
  r.say();
  const uint32_t seq = r.b.reactionSeq();
  f.key = 31;
  onReaction(r.b, f, r.t);
  TEST_ASSERT_EQUAL(seq, r.b.reactionSeq());
  TEST_ASSERT_EQUAL_STRING("Go", r.b.bubble(r.t));
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  // Skipped while something needs you, and with no app.
  r.at(30000);
  r.state(attn());
  ended(r);
  f.key = 32;
  TEST_ASSERT_EQUAL_STRING("needs_you", r.b.admit(f, r.t));  // the kit skips it
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  Rig n;
  n.at(Behaviour::kNoAppMs);
  f.key = 33;
  TEST_ASSERT_EQUAL_STRING("no_app", n.b.admit(f, n.t));
  TEST_ASSERT_FALSE(n.b.expression(n.t, e));
  TEST_ASSERT_EQUAL_STRING("", ended(n).c_str());
}

// Starts of blinks between 0 and `to` ms, with the Mac sending `m` every
// 10 s (or never, for no app). A design that blinks in a step of its own,
// as the comedy's idles the look's variations turn to do, gets none of the
// device's blinks: kSelfBlink marks where one showed, and no gap spans it.
constexpr uint32_t kSelfBlink = 0xFFFFFFFF;
std::vector<uint32_t> blinkStarts(const Model& m, bool mac, uint32_t to) {
  Rig r;
  r.state(m);
  std::vector<uint32_t> starts;
  bool prev = false;
  for (uint32_t t = 1; t <= to; ++t) {
    if (mac && t % 10000 == 0) r.at(t), r.state(m);
    r.at(t);
    bool blink = r.b.blinking(t);
    SceneShow s = r.b.show(t);
    if (blink) TEST_ASSERT_TRUE(s.eyesShut);
    if (render::blinksItself(s.mood, s.state, s.variant)) {
      TEST_ASSERT_FALSE(blink);
      if (starts.empty() || starts.back() != kSelfBlink) starts.push_back(kSelfBlink);
    }
    if (blink && !prev) starts.push_back(t);
    prev = blink;
  }
  return starts;
}

// The device's own blinks among them, without the marks.
std::vector<uint32_t> deviceBlinks(const std::vector<uint32_t>& starts) {
  std::vector<uint32_t> out;
  for (uint32_t t : starts)
    if (t != kSelfBlink) out.push_back(t);
  return out;
}

void checkGaps(const std::vector<uint32_t>& starts, uint32_t from, uint32_t lo, uint32_t hi) {
  int n = 0;
  for (size_t i = 1; i < starts.size(); ++i) {
    if (starts[i] == kSelfBlink || starts[i - 1] == kSelfBlink || starts[i - 1] < from) continue;
    uint32_t gap = starts[i] - starts[i - 1];
    TEST_ASSERT_TRUE(gap >= lo + render::pixel::PixelFace::kBlinkMs);  // the gap follows the blink
    TEST_ASSERT_TRUE(gap <= hi + render::pixel::PixelFace::kBlinkMs);
    ++n;
  }
  TEST_ASSERT_TRUE(n >= 5);
}

// Idle and working life is blinks only, every 2–6 s idle,
// 2–5 s working, however many agents are busy, except while a design that
// blinks itself shows. Asleep, as with no app, never blinks.
// A reaction's `mood` is its expression. With no animation,
// the look is drawn in that mood for the reaction's loops of the design it's
// drawn in, ending on a loop boundary of that design's clock (so the first
// loop ends at the next boundary), and at least as long as the `say` and
// its bubble; then it goes back to the state's mood. A look
// change meanwhile keeps the expression and its end; a new reaction, a tap
// or "needs you" ends it.
static ReactionIn expressive(render::Mood mood, const char* take = kGo, int loops = 1) {
  ReactionIn m;
  m.said = take != nullptr, m.take = voice::takeIndex(take);
  m.expr = true, m.mood = mood, m.loops = loops;
  return m;
}

static void test_an_expression_holds_its_loops() {
  NEEDS_VOICE_PACK();
  Rig r;
  Model m = base("working");  // happy, the working design's clock from 0
  r.state(m);
  const uint32_t loop = loopMs(render::Mood::kProud, SceneState::kWorking);
  r.at(1000);
  TEST_ASSERT_TRUE(onReaction(r.b, expressive(render::Mood::kProud), r.t));
  render::Mood e;
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  TEST_ASSERT_TRUE(e == render::Mood::kProud);
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kWorking);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kProud);
  TEST_ASSERT_EQUAL_UINT32(1000, s.t);  // the look's clock goes on
  // "Go"'s 638 ms, then the bubble's 1.2 s: the line is over first, and
  // the face holds to the design's next boundary.
  const uint32_t said = 1000 + kGoMs + Behaviour::kBubbleReadMs;
  TEST_ASSERT_TRUE(said < loop);
  r.at(said);
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kProud);
  r.at(loop - 1);
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  r.at(loop);
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kHappy);  // back to the state's mood
  TEST_ASSERT_TRUE(s.state == SceneState::kWorking);

  // Three loops, from partway into one: to the third boundary of the
  // look's clock, which a change of variation may have started over.
  r.at(2 * loop + 300);
  r.state(m);
  onReaction(r.b, expressive(render::Mood::kProud, kGo, 3), r.t);
  const uint32_t turned = loopMs(render::Mood::kProud, SceneState::kWorking, r.b.lookVariant());
  const uint32_t third = r.t + turned - r.b.designMs(r.t) % turned + 2 * turned;
  r.at(third - 1);
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  r.at(third);
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));

  // A `say` longer than its loop: the face holds as long as it plays.
  r.at(6 * loop);
  r.state(m);
  ReactionIn in = expressive(render::Mood::kExcited, "new.d20");  // "Mwahaha...", 2434 ms
  onReaction(r.b, in, r.t);
  const uint32_t end = r.t + 2434 + Behaviour::kBubbleReadMs;
  TEST_ASSERT_TRUE(end - r.t > loopMs(render::Mood::kExcited, SceneState::kWorking));
  r.at(end - 1);
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  r.at(end);
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
}

static void test_an_expression_over_the_cheer_and_across_a_look_change() {
  Rig r;
  Model m = base("working");
  m.mood = render::Mood::kCurious;
  r.state(m);
  r.at(1000);
  r.react(SceneState::kTaskComplete);  // a finish with no face, in curious
  const uint32_t cheer = loopMs(render::Mood::kCurious, SceneState::kTaskComplete);
  const uint32_t proud = loopMs(render::Mood::kProud, SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kCurious);
  r.at(1200);
  m.base = SceneState::kIdle;  // the agent's turn is over
  r.state(m);
  onReaction(r.b, expressive(render::Mood::kProud), r.t);  // Jev: proud
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kProud);
  TEST_ASSERT_EQUAL_UINT32(200, s.t);  // the finish keeps its clock
  uint32_t left;
  TEST_ASSERT_EQUAL(SceneState::kTaskComplete, r.b.reaction(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(cheer - 200, left);  // a `say` doesn't cut the finish
  // The face holds one loop of the finish's design in proud, on the
  // finish's clock: to 1000 + proud's loop, after the `say` (1200 + 638 +
  // 1200). A finish's variation loops alike in every mood, so the finish
  // ends then too.
  TEST_ASSERT_TRUE(1200 + kGoMs + Behaviour::kBubbleReadMs < 1000 + proud);
  TEST_ASSERT_EQUAL_UINT32(cheer, proud);
  r.at(1000 + proud - 1);
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kProud);
  r.at(1000 + proud);
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kIdle);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kCurious);

  // A look change while it plays: the expression goes with the new look,
  // and ends where it would have, at the working design's boundary.
  Rig l;
  l.state(base("working"));
  l.at(1000);
  onReaction(l.b, expressive(render::Mood::kProud), l.t);
  l.at(1500);
  l.state(base("idle"));
  s = l.b.show(l.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kIdle);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kProud);
  const uint32_t working = loopMs(render::Mood::kProud, SceneState::kWorking);
  l.at(working - 1);
  TEST_ASSERT_TRUE(l.b.show(l.t).mood == render::Mood::kProud);
  l.at(working);
  TEST_ASSERT_TRUE(l.b.show(l.t).mood == render::Mood::kHappy);

  // With an animation in the same reaction, it lasts the longer of the two:
  // here the finish, a loop of excited's design.
  Rig a;
  a.state(base("idle"));
  a.at(1000);
  ReactionIn in = expressive(render::Mood::kExcited);
  in.anim = SceneState::kTaskComplete;
  onReaction(a.b, in, a.t);
  const uint32_t excited = loopMs(render::Mood::kExcited, SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(kGoMs + Behaviour::kBubbleReadMs < excited);
  a.at(1000 + excited - 1);
  TEST_ASSERT_TRUE(a.b.show(a.t).mood == render::Mood::kExcited);
  a.at(1000 + excited);
  TEST_ASSERT_TRUE(a.b.show(a.t).mood == render::Mood::kHappy);
  // An animation alone with a mood: as long as it plays.
  a.at(10000);
  ReactionIn poke;
  poke.anim = SceneState::kPoked, poke.expr = true, poke.mood = render::Mood::kSad;
  onReaction(a.b, poke, a.t);
  const uint32_t sadPoke = loopMs(render::Mood::kSad, SceneState::kPoked);
  a.at(10000 + sadPoke - 1);
  TEST_ASSERT_TRUE(a.b.show(a.t).mood == render::Mood::kSad);
  a.at(10000 + sadPoke);
  TEST_ASSERT_TRUE(a.b.show(a.t).mood == render::Mood::kHappy);
}

static void test_an_expression_ends_with_its_reaction() {
  NEEDS_VOICE_PACK();
  render::Mood e;
  // A new `say` without a mood replaces the `say`, and the expression.
  Rig r;
  r.state(base("working"));
  r.at(1000);
  onReaction(r.b, expressive(render::Mood::kGrumpy), r.t);
  r.at(1500);
  r.say();
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kHappy);
  // A tap's poke doesn't: the poke is drawn in the reaction's mood.
  r.at(5000);
  onReaction(r.b, expressive(render::Mood::kSad), r.t);
  r.at(5100);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_TRUE(r.b.expression(r.t, e) && e == render::Mood::kSad);
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kSad);
  // "Needs you" stops the line, and the expression with it.
  r.at(9000);
  onReaction(r.b, expressive(render::Mood::kExcited), r.t);
  r.at(9100);
  r.state(attn());
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kNeedsYou);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kHappy);
  // While something needs you, a reaction with a mood plays nothing and
  // borrows no face.
  r.at(9500);
  TEST_ASSERT_FALSE(onReaction(r.b, expressive(render::Mood::kGrumpy), r.t));
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kHappy);
  // No expression: the state's mood, as before.
  Rig n;
  Model m = base("idle");
  m.mood = render::Mood::kDetermined;
  n.state(m);
  n.at(100);
  n.say();
  TEST_ASSERT_FALSE(n.b.expression(n.t, e));
  TEST_ASSERT_TRUE(n.b.show(n.t).mood == render::Mood::kDetermined);
}

// A reaction from the Mac ends exactly once, when no part of
// it plays any more (the `say` and its bubble, an animation, the borrowed
// face): done when it played out, or when only the face it holds after
// its `say` was ended early; cut, and by what, when a tap's poke or
// "needs you" stopped its animation or its line. A newer call or
// dbg.reset gives no reason: the kit has already ended the one playing
// then. Only the reaction that last played is followed: a newer reaction is the
// kit's holder, so the one it replaced is the kit's to have ended. (One
// none of which would play is refused, and the kit skips it; the kit
// passes on only the end of the one playing: test_device, test_queue.)
static std::string ended(Rig& r) {
  std::string out;
  app::PlayedOut e;
  while (r.b.takePlayedOut(e)) {
    if (!out.empty()) out += ", ";
    out += std::to_string(e.key) + (e.by == app::CutBy::kNone ? " done" : " cut");
    if (const char* by = app::cutByName(e.by)) out += std::string(" by ") + by;
  }
  return out;
}

static ReactionIn waited(uint32_t id, const char* take = kGo) {
  ReactionIn m = expressive(render::Mood::kProud, take);
  m.key = id;
  return m;
}

// A reaction's sign (Behaviour::kSignMinMs, 2.5 s): held up from the
// reaction's start for as long as any of its parts plays, and at least
// 2.5 s so it can be read; the reaction isn't played out until it's down.
// A tap's poke leaves it up; a newer reaction's animation and needs you
// take it down. Once down it fades out over the rig's fade, its words
// kept (render::SignShow::opacity), but under needs you, which takes it at
// once.
static void test_a_sign_shows_while_its_reaction_plays() {
  Rig r;
  r.state(base("idle"));
  r.at(1000);
  auto holding = [](const char* text, uint32_t key) {
    ReactionIn m;
    std::snprintf(m.sign, sizeof m.sign, "%s", text);
    m.key = key;
    return m;
  };
  auto sign = [&] { return std::string(r.b.signUp(r.t) ? r.b.sign(r.t).text : "-"); };
  // What the face draws: the words and how much of them.
  auto drawn = [&] {
    const render::SignShow s = r.b.sign(r.t);
    return s.text ? std::string(s.text) + " " + std::to_string(s.opacity) : std::string("-");
  };
  // On its own: 2.5 s.
  TEST_ASSERT_NULL(r.b.admit(holding("bye bye code", 1), r.t));
  r.b.play(holding("bye bye code", 1), r.t);
  TEST_ASSERT_EQUAL_STRING("bye bye code", sign().c_str());
  r.at(1000 + Behaviour::kSignMinMs - 1);
  TEST_ASSERT_EQUAL_STRING("bye bye code", sign().c_str());
  TEST_ASSERT_EQUAL_UINT32(Behaviour::kSignMinMs - 1, r.b.sign(r.t).ms);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  TEST_ASSERT_EQUAL_STRING("bye bye code 1000", drawn().c_str());
  r.at(1000 + Behaviour::kSignMinMs);
  TEST_ASSERT_EQUAL_STRING("-", sign().c_str());
  TEST_ASSERT_EQUAL_STRING("1 done", ended(r).c_str());
  static_assert(render::rig::kFadeMs == 200, "a sign fades out over the rig's 200 ms");
  TEST_ASSERT_EQUAL_STRING("bye bye code 1000", drawn().c_str());
  r.at(1000 + Behaviour::kSignMinMs + 100);
  TEST_ASSERT_EQUAL_STRING("bye bye code 500", drawn().c_str());
  TEST_ASSERT_EQUAL_UINT32(Behaviour::kSignMinMs + 100, r.b.sign(r.t).ms);  // still bobbing as it was
  r.at(1000 + Behaviour::kSignMinMs + 200);
  TEST_ASSERT_EQUAL_STRING("-", drawn().c_str());

  // With a finish longer than that: as long as the finish plays.
  r.at(10000);
  r.state(base("idle"));
  ReactionIn cheer = holding("ship it", 2);
  cheer.anim = SceneState::kTaskComplete;
  onReaction(r.b, cheer, r.t);
  uint32_t left;
  r.b.reaction(r.t, left);
  TEST_ASSERT_TRUE(left > Behaviour::kSignMinMs);
  r.at(10000 + left - 1);
  TEST_ASSERT_EQUAL_STRING("ship it", sign().c_str());
  r.at(10000 + left);
  TEST_ASSERT_EQUAL_STRING("-", sign().c_str());
  TEST_ASSERT_EQUAL_STRING("2 done", ended(r).c_str());

  // A short `say` (638 ms, and 1.2 s to read it) holds it 2.5 s, after
  // its bubble has gone.
  if (voice::takeIndex(kGo) >= 0) {
    r.at(20000);
    r.state(base("idle"));
    ReactionIn brief = holding("oops", 3);
    brief.said = true, brief.take = voice::takeIndex(kGo);
    onReaction(r.b, brief, r.t);
    r.at(20000 + kGoMs + Behaviour::kBubbleReadMs);
    TEST_ASSERT_NULL(r.b.bubble(r.t));
    TEST_ASSERT_EQUAL_STRING("oops", sign().c_str());
    r.at(20000 + Behaviour::kSignMinMs - 1);
    TEST_ASSERT_EQUAL_STRING("oops", sign().c_str());
    r.at(20000 + Behaviour::kSignMinMs);
    TEST_ASSERT_EQUAL_STRING("-", sign().c_str());
  }

  // A tap's poke plays under it; a newer reaction's animation takes it down.
  r.at(30000);
  r.state(base("idle"));
  onReaction(r.b, holding("hello", 4), r.t);
  r.at(30100);
  TEST_ASSERT_EQUAL_STRING("poked", r.b.tap(r.t, r.rng));
  TEST_ASSERT_EQUAL_STRING("hello", sign().c_str());
  r.react(SceneState::kStarting);
  TEST_ASSERT_EQUAL_STRING("-", sign().c_str());
  TEST_ASSERT_EQUAL_STRING("hello 1000", drawn().c_str());  // fading out from now
  r.at(r.t + render::rig::kFadeMs);
  TEST_ASSERT_EQUAL_STRING("-", drawn().c_str());

  // Needs you takes it down, and no sign plays while it waits.
  r.at(40000);
  r.state(base("idle"));
  onReaction(r.b, holding("hello", 5), r.t);
  r.state(attn());
  TEST_ASSERT_EQUAL_STRING("-", sign().c_str());
  TEST_ASSERT_EQUAL_STRING("-", drawn().c_str());
  TEST_ASSERT_EQUAL_STRING("needs_you", r.b.admit(holding("again", 6), r.t));
}

static void test_a_waited_reaction_says_how_it_ended() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));  // the idle design's clock from 0
  r.at(1000);
  TEST_ASSERT_TRUE(onReaction(r.b, waited(7), r.t));
  // Its `say` is over at 1000 + 638 + 1.2 s, and its face at the idle
  // design's next boundary, or with the `say` if that's later.
  const uint32_t look = loopMs(render::Mood::kProud, SceneState::kIdle);
  uint32_t end = (1000 / look + 1) * look;
  if (end < 1000 + kGoMs + Behaviour::kBubbleReadMs) end = 1000 + kGoMs + Behaviour::kBubbleReadMs;
  r.at(1000 + kGoMs + Behaviour::kBubbleReadMs - 1);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(end - 1);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(end);
  TEST_ASSERT_EQUAL_STRING("7 done", ended(r).c_str());
  r.at(10000);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());  // once

  // Over a finish that isn't part of it: its face holds a loop
  // of the finish's design in proud, on the finish's clock, and the finish
  // plays on as it would have.
  r.react(SceneState::kTaskComplete);
  r.at(10500);
  onReaction(r.b, waited(8), r.t);
  r.at(10500 + kGoMs + Behaviour::kBubbleReadMs);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  TEST_ASSERT_EQUAL(SceneState::kTaskComplete, r.anim());
  r.at(10000 + loopMs(render::Mood::kProud, SceneState::kTaskComplete));
  TEST_ASSERT_EQUAL_STRING("8 done", ended(r).c_str());
  // A finish the Mac waits on plays on under a newer `say`, which doesn't
  // stop it: done when the finish is.
  r.at(20000);
  ReactionIn cheer;
  cheer.anim = SceneState::kTaskComplete, cheer.key = 9;
  onReaction(r.b, cheer, r.t);
  r.at(20500);
  r.say();
  const uint32_t cheered = 20000 + loopMs(render::Mood::kHappy, SceneState::kTaskComplete);
  r.at(cheered - 1);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(cheered);
  TEST_ASSERT_EQUAL_STRING("9 done", ended(r).c_str());

  // A tap's poke doesn't cut its `say` or face: it
  // plays out, done.
  {
    Rig p;
    p.state(base("idle"));
    p.at(1000);
    onReaction(p.b, waited(10), p.t);
    p.at(1100);
    p.b.tap(p.t, p.rng);
    TEST_ASSERT_EQUAL_STRING("", ended(p).c_str());
    p.at(1000 + 2 * look + kGoMs + Behaviour::kBubbleReadMs);
    TEST_ASSERT_EQUAL_STRING("10 done", ended(p).c_str());
  }
  // Replaced by a newer reaction (a finish, a `say`, the Mac's next): over
  // at once, with no reason, since the kit already cut it. Cut short by
  // "needs you".
  r.at(30000);
  r.state(base("idle"));  // no app would skip them
  r.at(31000);
  onReaction(r.b, waited(11), r.t);
  r.react(SceneState::kTaskComplete);
  TEST_ASSERT_EQUAL_STRING("11 done", ended(r).c_str());
  r.at(35000);
  onReaction(r.b, waited(12), r.t);
  r.at(35100);
  r.say();
  TEST_ASSERT_EQUAL_STRING("12 done", ended(r).c_str());
  r.at(40000);
  onReaction(r.b, waited(13), r.t);
  onReaction(r.b, waited(14), r.t);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());  // the kit ended 13 when 14 started
  r.at(40100);
  r.state(attn());
  TEST_ASSERT_EQUAL_STRING("14 cut by needs_you", ended(r).c_str());
  // Refused, and so skipped by the kit: something needs you, so none of
  // it would play.
  TEST_ASSERT_EQUAL_STRING("needs_you", r.b.admit(waited(15), r.t));
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());

  // Its face holds on after its `say` is over. A newer
  // reaction or "needs you" then ends it at once, but doesn't cut the
  // reaction: it was seen and heard, so it's done. A tap's poke plays in it.
  Rig h;
  Model hm = base("idle");
  h.state(hm);
  h.look(1);  // the idle design's second variation, a long loop, its clock from 0
  const uint32_t idle = loopMs(render::Mood::kProud, SceneState::kIdle, 1);
  // The look's variations take turns at their loops' ends between the
  // parts below, so each part pins the second again, its clock from the
  // part's start: another variation from the Mac, then this one, starts
  // the turns over from it.
  auto pin = [&](Rig& g) {
    g.state(hm);
    g.look(0);
    g.look(1);
  };
  render::Mood face;
  {
    Rig p;
    p.state(hm);
    p.look(1);
    p.at(1000);
    onReaction(p.b, waited(17), p.t);
    p.at(1000 + kGoMs + Behaviour::kBubbleReadMs + 100);
    TEST_ASSERT_TRUE(p.t < idle);
    TEST_ASSERT_NULL(p.b.bubble(p.t));
    TEST_ASSERT_TRUE(p.b.expression(p.t, face));
    p.b.tap(p.t, p.rng);
    TEST_ASSERT_TRUE(p.b.expression(p.t, face) && face == render::Mood::kProud);
    TEST_ASSERT_EQUAL_STRING("", ended(p).c_str());
    p.at(idle);
    TEST_ASSERT_EQUAL_STRING("17 done", ended(p).c_str());
  }
  h.at(2 * idle + 1000);
  pin(h);
  onReaction(h.b, waited(18), h.t);
  h.at(2 * idle + 1000 + kGoMs + Behaviour::kBubbleReadMs + 100);
  TEST_ASSERT_NULL(h.b.bubble(h.t));
  TEST_ASSERT_EQUAL_STRING("", ended(h).c_str());
  h.state(attn());
  TEST_ASSERT_EQUAL_STRING("18 done", ended(h).c_str());
  h.at(4 * idle + 1000);
  pin(h);
  onReaction(h.b, waited(19), h.t);
  h.at(4 * idle + 1000 + kGoMs + Behaviour::kBubbleReadMs + 100);
  h.react(SceneState::kTaskComplete);
  TEST_ASSERT_EQUAL_STRING("19 done", ended(h).c_str());
  h.at(6 * idle + 1000);
  pin(h);
  onReaction(h.b, waited(20), h.t);
  h.at(6 * idle + 1000 + kGoMs + Behaviour::kBubbleReadMs + 100);
  h.say();  // a newer `say`
  TEST_ASSERT_EQUAL_STRING("20 done", ended(h).c_str());
  // During its bubble, after the take, it's still its `say`, which a tap
  // doesn't cut.
  h.at(8 * idle + 1000);
  pin(h);
  onReaction(h.b, waited(21), h.t);
  h.at(8 * idle + 1000 + kGoMs + Behaviour::kBubbleReadMs - 1);
  TEST_ASSERT_NOT_NULL(h.b.bubble(h.t));
  h.b.tap(h.t, h.rng);
  TEST_ASSERT_NOT_NULL(h.b.bubble(h.t));
  TEST_ASSERT_EQUAL_STRING("", ended(h).c_str());
  h.at(9 * idle + 1000);
  TEST_ASSERT_EQUAL_STRING("21 done", ended(h).c_str());
  // The Mac's next reaction, sent once this one's `say` has played:
  // it replaces the face held for its loops, and this one is done, as the
  // kit said when the next started.
  h.at(10 * idle + 1000);
  pin(h);
  ReactionIn held = expressive(render::Mood::kProud, kGo, 4);  // held four times
  held.key = 22;
  onReaction(h.b, held, h.t);
  h.at(10 * idle + 1000 + kGoMs + Behaviour::kBubbleReadMs + 100);
  TEST_ASSERT_NULL(h.b.bubble(h.t));
  TEST_ASSERT_TRUE(h.b.expression(h.t, face));
  ReactionIn next = expressive(render::Mood::kGrumpy);
  next.key = 23;
  TEST_ASSERT_TRUE(onReaction(h.b, next, h.t));
  TEST_ASSERT_EQUAL_STRING("", ended(h).c_str());  // 23 is followed now
  TEST_ASSERT_FALSE(h.b.expression(h.t, face) && face == render::Mood::kProud);
  TEST_ASSERT_NOT_NULL(h.b.bubble(h.t));
  TEST_ASSERT_TRUE(h.b.expression(h.t, face));
  TEST_ASSERT_EQUAL(render::Mood::kGrumpy, face);

  // dbg.reset forgets the reaction, and what it owes: the kit has already
  // told the Mac.
  r.at(50000);
  r.state(base("idle"));
  onReaction(r.b, waited(16), r.t);
  r.b.reset(r.t, r.rng);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());

  // A reaction with no id never ends out loud.
  Rig n;
  n.state(base("idle"));
  n.say();
  n.b.tap(n.t, n.rng);
  n.react(SceneState::kTaskComplete);
  n.at(10000);
  TEST_ASSERT_EQUAL_STRING("", ended(n).c_str());
}

// A tool may move the frozen clock back (dbg.clock). The animation that
// started later is over, and the look's design clock starts at the new
// time rather than reading a wrapped, huge one, which the sound effects
// following it would spin through (a hang on main, found by fuzzing).
static void test_the_clock_going_back_starts_the_look_over() {
  Rig r;
  r.state(base("idle"));
  r.at(9001);
  ReactionIn in;
  in.anim = SceneState::kHelperReturn, in.loops = 2;
  onReaction(r.b, in, r.t);
  TEST_ASSERT_EQUAL(SceneState::kHelperReturn, r.anim());
  r.at(4201);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  TEST_ASSERT_EQUAL_UINT32(0, r.b.designMs(r.t));
  r.at(4301);
  TEST_ASSERT_EQUAL_UINT32(100, r.b.designMs(r.t));
  TEST_ASSERT_TRUE(r.b.show(r.t).t < loopMs(render::Mood::kHappy, SceneState::kIdle));
}

static void test_life_is_blinks_at_their_pace() {
  checkGaps(blinkStarts(base("idle"), true, 120000), 0, 2000, 6000);
  Model w = base("working");
  w.busy = 1;
  checkGaps(blinkStarts(w, true, 120000), 0, 2000, 5000);
  w.busy = 3;
  checkGaps(blinkStarts(w, true, 120000), 0, 2000, 5000);
  std::vector<uint32_t> none = deviceBlinks(blinkStarts(base("idle"), false, 180000));
  TEST_ASSERT_TRUE(none.empty() || none.back() < 30000);  // no app: no blinks after 30 s
}

static void test_asleep_breathes_and_never_blinks() {
  Rig r;
  r.state(base("asleep"));
  for (uint32_t t = 1; t <= 20000; t += 7) {
    if (t % 10000 < 7) r.state(base("asleep"));
    r.at(t);
    TEST_ASSERT_FALSE(r.b.blinking(t));
    // Breathing is the asleep design's own 8 s breath,
    // looked at before its loop ends and its variations may rotate.
    if (t != 8989) continue;
    TEST_ASSERT_TRUE(r.b.show(1000).state == SceneState::kAsleep);
    TEST_ASSERT_TRUE(render::sceneFrame(r.b.show(1000)) != render::sceneFrame(r.b.show(3000)));
    TEST_ASSERT_TRUE(render::sceneFrame(r.b.show(1000)) == render::sceneFrame(r.b.show(9000)));
  }
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
}

// Each look shows its design in the mood the Mac
// sent. A finish shows the task_complete design on its own clock; the mood
// changing mid-finish blinks to the new mood's design and keeps that clock.
static void test_each_look_shows_its_design_in_the_mood() {
  struct Case {
    const char* base;
    bool attn;
    SceneState state;
  };
  const Case cases[] = {{"idle", false, SceneState::kIdle},
                        {"working", false, SceneState::kWorking},
                        {"asleep", false, SceneState::kAsleep},
                        {"working", true, SceneState::kNeedsYou}};
  for (const Case& c : cases) {
    for (render::Mood mood : {render::Mood::kHappy, render::Mood::kGrumpy, render::Mood::kSad}) {
      Rig r;
      Model m = c.attn ? attn() : base(c.base);
      m.mood = mood;
      r.state(m);
      r.at(500);
      SceneShow s = r.b.show(r.t);
      TEST_ASSERT_TRUE(s.state == c.state);
      TEST_ASSERT_TRUE(s.mood == mood);
      TEST_ASSERT_EQUAL_UINT32(500, s.t);
    }
  }
  Rig r;
  Model m = base("working");
  m.mood = render::Mood::kDetermined;
  r.state(m);
  r.at(1000);
  r.react(SceneState::kTaskComplete);
  r.at(1500);
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kTaskComplete);
  TEST_ASSERT_EQUAL_UINT32(500, s.t);
  m.mood = render::Mood::kProud;
  r.state(m);
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kProud);
  TEST_ASSERT_EQUAL_UINT32(500, s.t);
  r.at(1000 + loopMs(render::Mood::kProud, SceneState::kTaskComplete));  // the finish is over: back to working, still proud
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kWorking);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kProud);
}

// A tap plays the mood's poked design once, from
// its start, then the look comes back. The third tap in a row, and each after it, plays
// tap_spam instead. A tap is in a row when it comes within
// Behaviour::kTapRunMs of the one before, and tap_spam starts at
// Behaviour::kTapSpamFrom: the Mac's TranscriptView.inARowMs (3000) and
// answersRunFrom (3).
static void test_taps_poke_and_a_run_spams() {
  TEST_ASSERT_EQUAL_UINT32(3000, Behaviour::kTapRunMs);  // TranscriptView.inARowMs
  TEST_ASSERT_EQUAL_INT(3, Behaviour::kTapSpamFrom);     // TranscriptView.answersRunFrom
  Rig r;
  Model m = base("working");
  r.state(m);
  r.at(1000);
  r.b.tap(r.t, r.rng);
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_EQUAL(SceneState::kPoked, r.anim());
  TEST_ASSERT_TRUE(s.state == SceneState::kPoked);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kHappy);
  TEST_ASSERT_EQUAL_UINT32(0, s.t);
  TEST_ASSERT_FALSE(s.eyesShut);
  uint32_t left;
  r.b.reaction(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(loopMs(render::Mood::kHappy, SceneState::kPoked), left);  // once
  TEST_ASSERT_EQUAL_INT(1, r.b.taps());
  // The second, just inside 3 s, is in the run, and pokes again.
  r.at(1000 + Behaviour::kTapRunMs - 1);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(SceneState::kPoked, r.anim());
  TEST_ASSERT_EQUAL_INT(2, r.b.taps());
  // The third plays tap_spam, and so does each one after it in the run.
  for (int i = 3; i <= 6; ++i) {
    r.at(r.t + 1000);
    r.b.tap(r.t, r.rng);
    TEST_ASSERT_EQUAL(SceneState::kTapSpam, r.anim());
    TEST_ASSERT_EQUAL_INT(i, r.b.taps());
    s = r.b.show(r.t);
    TEST_ASSERT_TRUE(s.state == SceneState::kTapSpam && s.t == 0);
  }
  r.b.reaction(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(loopMs(render::Mood::kHappy, SceneState::kTapSpam), left);
  // 3 s after the last: a new run, which pokes.
  r.at(r.t + Behaviour::kTapRunMs);
  r.state(m);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(SceneState::kPoked, r.anim());
  TEST_ASSERT_EQUAL_INT(1, r.b.taps());
  // Played once, the look comes back.
  r.b.reaction(r.t, left);
  r.at(r.t + left);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kWorking);
}

// A mood with several poked or tap_spam designs plays one
// at random each time, never the one it played last; the poke is drawn in
// Boop's mood.
static void test_taps_rotate_their_variations() {
  for (SceneState a : {SceneState::kPoked, SceneState::kTapSpam}) {
    Rig r;
    Model m = base("idle");
    m.mood = render::Mood::kCalm;
    r.state(m);
    const int n = render::variants(render::Mood::kCalm, a);
    TEST_ASSERT_EQUAL_INT(3, n);
    int last = -1;
    bool seen[3] = {};
    for (int i = 0; i < 60; ++i) {
      r.at(r.t + (a == SceneState::kPoked ? Behaviour::kTapRunMs : 100));
      r.state(m);  // the Mac's keepalive
      r.b.tap(r.t, r.rng);
      if (a == SceneState::kTapSpam && i < 2) continue;  // the run's first two poke
      TEST_ASSERT_EQUAL(a, r.anim());
      SceneShow s = r.b.show(r.t);
      TEST_ASSERT_TRUE(s.mood == render::Mood::kCalm);
      TEST_ASSERT_NOT_EQUAL(last, s.variant);
      seen[s.variant] = true, last = s.variant;
    }
    for (bool v : seen) TEST_ASSERT_TRUE(v);
  }
}

// With no app, while something needs you and while
// listening waits for the reply, a tap only dips the face. It still counts
// in the run, as the Mac counts every poke.
static void test_a_held_face_counts_taps_but_only_dips() {
  Rig r;
  r.state(attn());
  r.at(1000);
  r.b.tap(r.t, r.rng);
  r.at(1500);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  TEST_ASSERT_EQUAL_INT(2, r.b.taps());
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNeedsYou);
  r.state(base("idle"));  // answered on the Mac
  r.at(2000);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(SceneState::kTapSpam, r.anim());  // the third in the run
  // Listening.
  Rig l;
  l.state(base("idle"));
  l.talkOn();
  l.at(500);
  l.b.tap(l.t, l.rng);
  TEST_ASSERT_EQUAL(SceneState::kListening, l.anim());
  TEST_ASSERT_EQUAL_INT(1, l.b.taps());
  // No app.
  Rig n;
  n.state(base("idle"));
  n.at(Behaviour::kNoAppMs);
  const uint32_t seq = n.b.reactionSeq();
  n.b.tap(n.t, n.rng);
  TEST_ASSERT_TRUE(n.b.look(n.t) == SceneState::kNoApp);
  TEST_ASSERT_TRUE(n.b.show(n.t).state == SceneState::kNoApp);
  TEST_ASSERT_EQUAL(seq, n.b.reactionSeq());
}

// With no state for 30 s the device shows the no-app
// design (backlight 60), with the unplugged icon in the strip; on
// reconnect the face dissolves into whatever the next state says.
static void test_no_app_at_30s_and_reconnect_comes_back() {
  Rig r;
  r.at(1000);
  Model m = attn();  // even a stale "needs you" gives way
  m.busy = 2;
  r.state(m);
  r.at(30999);
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kNeedsYou);
  TEST_ASSERT_EQUAL_STRING("codex", r.b.strip(r.t).agent);
  r.at(31000);
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kNoApp);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNoApp);
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));  // dimming over kBacklightEaseMs
  TEST_ASSERT_TRUE(r.b.backlight(r.t + Behaviour::kBacklightEaseMs / 2) < 255);
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  // The strip keeps only the unplugged icon: the counts are stale.
  render::Strip strip = r.b.strip(r.t);
  TEST_ASSERT_TRUE(strip.noApp);
  TEST_ASSERT_NULL(strip.agent);
  TEST_ASSERT_EQUAL(0, strip.busy);
  r.at(31000 + Behaviour::kBacklightEaseMs);
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kNoApp);
  TEST_ASSERT_FALSE(s.eyesShut);
  r.at(40000);
  r.state(base("idle"));
  r.state(base("idle"));
  TEST_ASSERT_TRUE(onFace(r.b, r.t));
  TEST_ASSERT_FALSE(r.b.blinking(r.t));
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kIdle);
  TEST_ASSERT_FALSE(s.eyesShut);
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t + Behaviour::kBacklightEaseMs));
}

// The brain's finish with `who` names that agent and
// thread in the strip while it plays and kFinishLingerMs after, and no
// longer, after a mark for what its design is for: a tick for a success, a cross for a failure, none for
// a reply. A poke, or a finish without one, names nobody.
static void test_a_cheer_names_whose_turn_in_the_strip() {
  Rig r;
  r.at(1000);
  Model m = base("idle");
  m.busy = 1;
  r.state(m);
  ReactionIn in;
  in.anim = SceneState::kTaskComplete;
  in.whoAgent = "codex";
  in.whoThread = "fix-nav";
  onReaction(r.b, in, r.t);
  render::Strip strip = r.b.strip(r.t);
  TEST_ASSERT_EQUAL_STRING("codex", strip.doneAgent);
  TEST_ASSERT_EQUAL_STRING("fix-nav", strip.doneThread);
  TEST_ASSERT_TRUE(strip.doneOutcome == render::Outcome::kSuccess);  // happy's first finish is a success
  TEST_ASSERT_NULL(strip.agent);
  TEST_ASSERT_EQUAL(1, strip.busy);
  uint32_t left;
  r.b.reaction(r.t, left);
  const uint32_t end = r.t + left;
  r.at(end - 1);
  TEST_ASSERT_EQUAL_STRING("codex", r.b.strip(r.t).doneAgent);
  r.at(end);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  TEST_ASSERT_EQUAL_STRING("fix-nav", r.b.strip(r.t).doneThread);  // lingering
  r.at(end + Behaviour::kFinishLingerMs - 1);
  TEST_ASSERT_EQUAL_STRING("codex", r.b.strip(r.t).doneAgent);
  r.at(end + Behaviour::kFinishLingerMs);
  TEST_ASSERT_NULL(r.b.strip(r.t).doneAgent);  // gone after its linger
  onReaction(r.b, in, r.t);
  r.b.tap(r.t, r.rng);  // a tap's poke replaces it
  TEST_ASSERT_NULL(r.b.strip(r.t).doneAgent);
  r.at(r.t + 5000);
  r.react(SceneState::kTaskComplete);  // no `who`
  TEST_ASSERT_NULL(r.b.strip(r.t).doneAgent);
  // A failure, and a reply.
  in.variant = 4;  // happy's failed finish
  TEST_ASSERT_TRUE(render::variantOutcome(render::Mood::kHappy, SceneState::kTaskComplete, 4) ==
                   render::Outcome::kFailure);
  onReaction(r.b, in, r.t);
  TEST_ASSERT_TRUE(r.b.strip(r.t).doneOutcome == render::Outcome::kFailure);
  in.anim = SceneState::kReplyReady, in.variant = 0;
  onReaction(r.b, in, r.t);
  TEST_ASSERT_EQUAL_STRING("codex", r.b.strip(r.t).doneAgent);
  TEST_ASSERT_TRUE(r.b.strip(r.t).doneOutcome == render::Outcome::kNone);
  in.anim = SceneState::kStarting;  // not a finish: nobody's named
  onReaction(r.b, in, r.t);
  TEST_ASSERT_NULL(r.b.strip(r.t).doneAgent);
}

// A tap while the brain's finish names whose turn it was, as it plays or
// lingers after, takes you to that thread: the press dip only, the finish plays on,
// and the tap carries its id for the Mac. A finish the Mac doesn't wait on (no id) or that names nobody is poked.
// The lane's fade, decided once for every face: the strip fades in over the
// rig's 200 ms from the millisecond it came, and out from the one it went,
// still showing what it last showed, names and all; what it shows while it
// shows changes at once (a count going 3 to 4), and one turning back
// mid-fade starts from where it was. No app and a finish come and go at
// their own times.
static void test_the_lane_fades_as_the_strip_comes_and_goes() {
  constexpr uint32_t kFade = render::rig::kFadeMs;
  static_assert(kFade == 200, "the lane fades on the props' 200 ms");
  Rig r;
  r.at(1000);
  Model m = base("idle");
  r.state(m);
  TEST_ASSERT_FALSE(r.b.strip(r.t).shows());
  m.busy = 3;
  r.state(m);
  TEST_ASSERT_EQUAL(3, r.b.strip(r.t).busy);  // what it shows, at once
  TEST_ASSERT_EQUAL(0, r.b.strip(r.t).opacity);
  r.at(1000 + kFade / 2);
  TEST_ASSERT_INT_WITHIN(5, 500, r.b.strip(r.t).opacity);
  r.at(1000 + kFade - 16);
  TEST_ASSERT_TRUE(r.b.strip(r.t).opacity < 1000);
  r.at(1000 + kFade);
  TEST_ASSERT_EQUAL(1000, r.b.strip(r.t).opacity);
  m.busy = 4;
  r.state(m);
  TEST_ASSERT_EQUAL(4, r.b.strip(r.t).busy);
  TEST_ASSERT_EQUAL(1000, r.b.strip(r.t).opacity);
  // Going: still the 4, fading.
  r.at(2000);
  m.busy = 0;
  r.state(m);
  TEST_ASSERT_EQUAL(4, r.b.strip(r.t).busy);
  TEST_ASSERT_EQUAL(1000, r.b.strip(r.t).opacity);
  r.at(2000 + kFade / 2);
  TEST_ASSERT_EQUAL(4, r.b.strip(r.t).busy);
  const int half = r.b.strip(r.t).opacity;
  TEST_ASSERT_INT_WITHIN(5, 500, half);
  // Back before it has gone: from where it was, with what shows now.
  m.idle = 1;
  r.state(m);
  TEST_ASSERT_EQUAL(1, r.b.strip(r.t).idle);
  TEST_ASSERT_EQUAL(0, r.b.strip(r.t).busy);
  TEST_ASSERT_EQUAL(half, r.b.strip(r.t).opacity);
  r.at(r.t + 16);
  TEST_ASSERT_INT_WITHIN(134, half, r.b.strip(r.t).opacity);  // no step past a 16 ms slice of the ramp
  r.at(3000);
  TEST_ASSERT_EQUAL(1000, r.b.strip(r.t).opacity);
  m.idle = 0;
  r.state(m);
  r.at(3000 + kFade);
  TEST_ASSERT_EQUAL(0, r.b.strip(r.t).opacity);
  TEST_ASSERT_FALSE(r.b.strip(r.t).shows());  // gone, it's bare glass again
  // A finish naming whose turn: in as it starts, out as its linger ends,
  // named.
  ReactionIn in;
  in.anim = SceneState::kTaskComplete, in.whoAgent = "codex", in.whoThread = "fix-nav";
  onReaction(r.b, in, r.t);
  uint32_t left, start = r.t;
  r.b.reaction(r.t, left);
  TEST_ASSERT_EQUAL_STRING("codex", r.b.strip(r.t).doneAgent);
  TEST_ASSERT_EQUAL(0, r.b.strip(r.t).opacity);
  r.at(start + left);
  TEST_ASSERT_EQUAL_STRING("codex", r.b.strip(r.t).doneAgent);
  TEST_ASSERT_EQUAL(1000, r.b.strip(r.t).opacity);
  r.at(start + left + Behaviour::kFinishLingerMs);
  TEST_ASSERT_EQUAL_STRING("codex", r.b.strip(r.t).doneAgent);
  TEST_ASSERT_EQUAL(1000, r.b.strip(r.t).opacity);
  r.at(start + left + Behaviour::kFinishLingerMs + kFade / 2);
  TEST_ASSERT_EQUAL_STRING("fix-nav", r.b.strip(r.t).doneThread);
  TEST_ASSERT_INT_WITHIN(5, 500, r.b.strip(r.t).opacity);
  // No app: the plug from the moment the Mac's silence turns into it.
  const uint32_t gone = 3000 + Behaviour::kNoAppMs;
  r.at(gone - 1);
  TEST_ASSERT_FALSE(r.b.strip(r.t).shows());
  r.at(gone + kFade / 2);
  TEST_ASSERT_TRUE(r.b.strip(r.t).noApp);
  TEST_ASSERT_INT_WITHIN(5, 500, r.b.strip(r.t).opacity);
}

// A to-do list is something the strip shows: one alone fades the strip in
// as any count does, and out still showing it once its turn stops working.
static void test_a_todo_list_alone_shows_the_strip() {
  constexpr uint32_t kFade = render::rig::kFadeMs;
  Rig r;
  r.at(1000);
  Model m = base("working");
  r.state(m);
  TEST_ASSERT_FALSE(r.b.strip(r.t).shows());
  m.todoDone = 3, m.todoTotal = 7;
  r.state(m);
  TEST_ASSERT_TRUE(r.b.strip(r.t).shows());
  TEST_ASSERT_EQUAL(7, r.b.strip(r.t).todoTotal);
  TEST_ASSERT_EQUAL(0, r.b.strip(r.t).opacity);
  r.at(1000 + kFade);
  TEST_ASSERT_EQUAL(1000, r.b.strip(r.t).opacity);
  r.at(2000);
  r.state(base("idle"));
  r.at(2000 + kFade / 2);
  TEST_ASSERT_EQUAL(3, r.b.strip(r.t).todoDone);  // the list it last showed, fading
  TEST_ASSERT_INT_WITHIN(5, 500, r.b.strip(r.t).opacity);
  r.at(2000 + kFade);
  TEST_ASSERT_FALSE(r.b.strip(r.t).shows());
}

// The lane is a function of the clock, not of how often frames are drawn: a
// board drawing every 16 ms and one drawing every 200 ms show the same lane
// wherever both draw, mid-fade and settled, its strip coming and going
// between their frames. Each draws as Device does, dirty only after a
// message, so a frame drawn mid-fade isn't skipped. Pixel's canvas has no
// alpha: half way, half the strip's pixels, by its dither.
static void test_the_lane_is_the_same_whatever_the_draw_cadence() {
  struct Run {
    Rig r;
    std::vector<uint8_t> px = std::vector<uint8_t>(size_t(render::kWidth) * render::kHeight);
    render::Canvas c{px.data()};
    bool dirty = true;
    std::vector<std::vector<uint8_t>> lanes;
    void play(uint32_t every) {
      const uint32_t messages[] = {1100, 2300}, shots[] = {1200, 1600, 2400, 2800};
      int next = 0;
      for (uint32_t t = 0; t <= 2800; t += every) {
        for (; next < 2 && messages[next] <= t; ++next) {
          Model m = base("idle");
          m.busy = next == 0 ? 2 : 0;
          r.at(messages[next]);
          r.state(m);
          dirty = true;
        }
        r.at(t);
        r.b.face().draw(c, nullptr, r.b.show(t), t, r.b.bubble(t), r.b.sign(t), r.b.done(t), r.b.strip(t), dirty);
        dirty = false;
        for (uint32_t shot : shots)
          if (shot == t) lanes.emplace_back(px.begin() + render::kStripTop * render::kWidth, px.end());
      }
    }
  };
  auto lit = [](const std::vector<uint8_t>& lane) {
    int n = 0;
    for (uint8_t p : lane) n += p != render::kBlack;
    return n;
  };
  Run often, seldom;
  often.play(16);
  seldom.play(200);
  TEST_ASSERT_EQUAL(4, int(often.lanes.size()));
  TEST_ASSERT_EQUAL(4, int(seldom.lanes.size()));
  for (int i = 0; i < 4; ++i) TEST_ASSERT_TRUE(often.lanes[i] == seldom.lanes[i]);
  const int whole = lit(often.lanes[1]);
  TEST_ASSERT_TRUE(whole > 100);
  TEST_ASSERT_INT_WITHIN(whole / 10, whole / 2, lit(often.lanes[0]));  // fading in
  TEST_ASSERT_INT_WITHIN(whole / 10, whole / 2, lit(often.lanes[2]));  // fading out
  TEST_ASSERT_EQUAL(0, lit(often.lanes[3]));
}

// A reaction with no animation for a finished turn (its `who`) marks it as
// a finish does: named in the strip, and the face's DoneShow, from its
// start while any part of it plays (no end known), then counting down
// kFinishLingerMs, then nothing. A newer reaction naming nothing takes it
// down: no longer named, it leaves in kDoneLeaveMs. A new needs-you takes
// it at once.
static void test_a_face_for_a_finished_turn_marks_it() {
  static_assert(Behaviour::kFinishLingerMs == 3000, "a finished turn stays marked 3 s after its reaction");
  static_assert(Behaviour::kDoneLeaveMs == 400, "taken down, it leaves in 400 ms");
  Rig r;
  r.at(1000);
  r.state(base("idle"));
  ReactionIn in;
  in.expr = true, in.mood = render::Mood::kHappy;
  in.whoAgent = "claude", in.whoThread = "fix-nav";
  in.key = 5, in.id = 5;
  const uint32_t start = r.t;
  onReaction(r.b, in, r.t);
  render::DoneShow d = r.b.done(r.t);
  TEST_ASSERT_EQUAL_STRING("claude", d.agent);
  TEST_ASSERT_EQUAL_STRING("fix-nav", d.thread);
  TEST_ASSERT_TRUE(d.outcome == render::Outcome::kNone);  // a face has no outcome of its own
  TEST_ASSERT_EQUAL(-1, d.leftMs);
  TEST_ASSERT_EQUAL_STRING("claude", r.b.strip(r.t).doneAgent);
  TEST_ASSERT_EQUAL_UINT32(5, r.b.finishShown(r.t));
  uint32_t end;
  TEST_ASSERT_TRUE(r.b.nextEnd(r.t, r.t + 60000, end));  // its face's loop
  r.at(end - 1);
  TEST_ASSERT_EQUAL(-1, r.b.done(r.t).leftMs);
  TEST_ASSERT_EQUAL_UINT32(end - 1 - start, r.b.done(r.t).ms);
  r.at(end);
  TEST_ASSERT_EQUAL(int(Behaviour::kFinishLingerMs), r.b.done(r.t).leftMs);
  r.at(end + Behaviour::kFinishLingerMs - 1);
  TEST_ASSERT_EQUAL(1, r.b.done(r.t).leftMs);
  TEST_ASSERT_EQUAL_STRING("fix-nav", r.b.strip(r.t).doneThread);
  r.at(end + Behaviour::kFinishLingerMs);
  TEST_ASSERT_FALSE(r.b.done(r.t).shows());
  TEST_ASSERT_EQUAL_UINT32(0, r.b.finishShown(r.t));  // the strip fades out with it
  // A face naming nothing takes the next one down.
  r.at(r.t + 1000);
  onReaction(r.b, in, r.t);
  r.at(r.t + 100);
  ReactionIn other;
  other.expr = true, other.mood = render::Mood::kGrumpy;
  other.key = 6, other.id = 6;
  onReaction(r.b, other, r.t);
  TEST_ASSERT_EQUAL_UINT32(0, r.b.finishShown(r.t));
  TEST_ASSERT_EQUAL(int(Behaviour::kDoneLeaveMs), r.b.done(r.t).leftMs);  // leaving
  r.at(r.t + Behaviour::kDoneLeaveMs);
  TEST_ASSERT_FALSE(r.b.done(r.t).shows());
  // So does a finish of another turn, which names its own at once.
  r.at(r.t + 1000);
  onReaction(r.b, in, r.t);
  ReactionIn finish = in;
  finish.expr = false, finish.anim = SceneState::kTaskComplete, finish.whoThread = "landing", finish.key = 7;
  onReaction(r.b, finish, r.t);
  TEST_ASSERT_EQUAL_STRING("landing", r.b.done(r.t).thread);
  TEST_ASSERT_EQUAL(-1, r.b.done(r.t).leftMs);
  // A new needs-you takes it at once.
  r.state(attn());
  TEST_ASSERT_FALSE(r.b.done(r.t).shows());
  r.state(base("idle"));
  TEST_ASSERT_FALSE(r.b.done(r.t).shows());
  TEST_ASSERT_EQUAL_UINT32(0, r.b.finishShown(r.t));
}

static void test_a_tap_on_a_named_finish_opens_its_thread() {
  Rig r;
  r.at(1000);
  r.state(base("idle"));
  ReactionIn in;
  in.anim = SceneState::kTaskComplete;
  in.whoAgent = "claude";
  in.whoThread = "fix-nav";
  in.key = 9, in.id = 9;
  onReaction(r.b, in, r.t);
  TEST_ASSERT_EQUAL_UINT32(9, r.b.finishShown(r.t));
  r.at(r.t + 100);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(SceneState::kTaskComplete, r.anim());
  TEST_ASSERT_EQUAL_STRING("fix-nav", r.b.strip(r.t).doneThread);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(r.t + 100);
  r.b.tap(r.t, r.rng);
  uint32_t left;
  r.b.reaction(r.t, left);
  const uint32_t end = r.t + left;
  r.at(end);
  TEST_ASSERT_EQUAL_STRING("9 done", ended(r).c_str());  // played out: the queue moves on
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  // Lingering: still named, and a tap still opens it, with only the dip.
  r.at(end + Behaviour::kFinishLingerMs - 1);
  TEST_ASSERT_EQUAL_UINT32(9, r.b.finishShown(r.t));
  TEST_ASSERT_EQUAL_STRING("dip", r.b.tap(r.t, r.rng));
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  r.at(end + Behaviour::kFinishLingerMs);
  TEST_ASSERT_EQUAL_UINT32(0, r.b.finishShown(r.t));  // over
  r.at(r.t + 5000);
  in.key = 0, in.id = 0;  // one the Mac doesn't wait on
  onReaction(r.b, in, r.t);
  TEST_ASSERT_EQUAL_UINT32(0, r.b.finishShown(r.t));
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(SceneState::kPoked, r.anim());
  r.at(r.t + 5000);
  in.key = 10, in.id = 10, in.whoAgent = nullptr, in.whoThread = nullptr;  // names nobody
  onReaction(r.b, in, r.t);
  TEST_ASSERT_EQUAL_UINT32(0, r.b.finishShown(r.t));
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(SceneState::kPoked, r.anim());
}

// A finish's linger ends early when the face is taken: another
// animation (a newer finish names its own turn), or a needs-you; one cut
// short never lingers.
static void test_a_finish_linger_ends_when_the_face_is_taken() {
  Rig r;
  r.at(1000);
  r.state(base("idle"));
  ReactionIn in;
  in.anim = SceneState::kTaskComplete, in.whoAgent = "claude", in.whoThread = "fix-nav", in.key = 9, in.id = 9;
  auto playOut = [&] {
    onReaction(r.b, in, r.t);
    uint32_t left;
    r.b.reaction(r.t, left);
    r.at(r.t + left + 100);
    TEST_ASSERT_EQUAL_UINT32(in.id, r.b.finishShown(r.t));
  };
  playOut();
  in.key = 10, in.id = 10, in.whoAgent = "codex", in.whoThread = "landing";
  onReaction(r.b, in, r.t);  // a newer finish: its own turn
  TEST_ASSERT_EQUAL_UINT32(10, r.b.finishShown(r.t));
  TEST_ASSERT_EQUAL_STRING("landing", r.b.strip(r.t).doneThread);
  uint32_t left;
  r.b.reaction(r.t, left);
  r.at(r.t + left + 100);
  r.react(SceneState::kStarting);  // another animation
  TEST_ASSERT_EQUAL_UINT32(0, r.b.finishShown(r.t));
  TEST_ASSERT_TRUE(r.b.strip(r.t).opacity > 0);  // fading out from what it showed
  r.at(r.t + render::rig::kFadeMs);
  TEST_ASSERT_NULL(r.b.strip(r.t).doneAgent);
  r.at(r.t + 5000);
  r.state(base("idle"));
  in.key = 11, in.id = 11;
  playOut();
  Model m = base("idle");
  m.attn = true, m.attnId = 1;
  app::copyStr(m.agent, sizeof(m.agent), "claude");
  r.state(m);  // a needs-you
  TEST_ASSERT_EQUAL_UINT32(0, r.b.finishShown(r.t));
  r.at(r.t + 5000);
  r.state(base("idle"));
  in.key = 12, in.id = 12;
  onReaction(r.b, in, r.t);
  r.at(r.t + 100);
  r.state(m);  // cut short by a needs-you as it plays
  r.state(base("idle"));
  r.at(r.t + 100);
  TEST_ASSERT_EQUAL_UINT32(0, r.b.finishShown(r.t));
}

static void test_press_shows_within_20ms() {
  Rig r;
  r.state(base("idle"));
  r.at(500);
  const SceneShow before = r.b.show(500);
  r.b.pressDown(500);
  TEST_ASSERT_EQUAL_INT(before.dy + Behaviour::kPressPx, r.b.show(500).dy);  // at once
  TEST_ASSERT_TRUE(r.b.pressEasing(516));  // and the redraw cap lets it through
}

// ---- What the agents are doing, the rules' reactions and the finish -----------

// While working, `act` draws what the
// agents are doing in working's place, in the mood, from the Mac's
// variation, and a new one starts its design from the start behind a
// blink. Without one, or with one the device doesn't know, it's working's
// design; with needs you, or when the base isn't working, it's ignored.
static void test_an_act_shows_in_workings_place() {
  using render::Mood;
  TEST_ASSERT_TRUE(app::actFromName("terminal") == SceneState::kTerminal);
  TEST_ASSERT_TRUE(app::actFromName("waiting") == SceneState::kWaiting);
  for (const char* other : {"dancing", "", "working", "idle", "needs_you", "starting", "poked", "Terminal"}) {
    TEST_ASSERT_TRUE_MESSAGE(app::actFromName(other) == SceneState::kWorking, other);
  }
  TEST_ASSERT_TRUE(app::actFromName(nullptr) == SceneState::kWorking);
  Rig r;
  Model m = base("working");
  m.act = SceneState::kTerminal, m.mood = Mood::kCalm;
  r.state(m);
  r.look(2);
  r.at(700);
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kTerminal && s.mood == Mood::kCalm);
  TEST_ASSERT_EQUAL_INT(2, s.variant);
  TEST_ASSERT_EQUAL_UINT32(700, s.t);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kTerminal);
  // Another activity: its design from its start.
  m.act = SceneState::kAnalyzing;
  r.state(m);
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kAnalyzing && s.t == 0 && !s.eyesShut);
  // None: working's.
  m.act = SceneState::kWorking;
  r.state(m);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kWorking);
  // Ignored by an idle base, and under needs you.
  Model idle = base("idle");
  idle.act = SceneState::kTesting;
  r.state(idle);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kIdle);
  Model a = attn();
  a.act = SceneState::kTesting;
  r.state(a);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNeedsYou);
}

// An activity's variations rotate at
// loop ends like working's, when the mood has more than one; with one,
// it plays on.
static void test_an_acts_variations_rotate() {
  Rig r;
  Model m = base("working");
  m.act = SceneState::kSearching, m.mood = render::Mood::kWounded;
  r.state(m);
  bool seen[3] = {};
  int turns = 0;
  uint8_t shown = 0;
  for (uint32_t t = 100; t <= 300000; t += 100) {
    r.at(t);
    if (t % 10000 == 0) r.state(m);
    SceneShow s = r.b.show(t);
    TEST_ASSERT_TRUE(s.state == SceneState::kSearching);
    if (s.variant != shown) ++turns, shown = s.variant;
    seen[s.variant] = true;
  }
  for (bool v : seen) TEST_ASSERT_TRUE(v);
  TEST_ASSERT_TRUE(turns >= 10);
  // Happy has one design of searching: it plays on.
  Rig h;
  m.mood = render::Mood::kHappy;
  h.state(m);
  for (uint32_t t = 100; t <= 60000; t += 100) {
    h.at(t);
    if (t % 10000 == 0) h.state(m);
    TEST_ASSERT_EQUAL_INT(0, h.b.show(t).variant);
  }
}

// The rules' reactions (starting,
// stopped, error, helper_return) play their design once in Boop's mood,
// from its start, then the look comes back.
// They carry no id, so no `ended` goes back.
static void test_a_rules_reaction_plays_once() {
  for (SceneState a : {SceneState::kStarting, SceneState::kStopped, SceneState::kError, SceneState::kHelperReturn}) {
    for (render::Mood mood : {render::Mood::kHappy, render::Mood::kCalm}) {
      Rig r;
      Model m = base("working");
      m.act = SceneState::kTerminal, m.mood = mood;
      r.state(m);
      r.at(1000);
      ReactionIn in;
      in.anim = a, in.variant = uint8_t(render::variants(mood, a) - 1);
      TEST_ASSERT_FALSE(onReaction(r.b, in, r.t));  // no `say`
      SceneShow s = r.b.show(r.t);
      TEST_ASSERT_TRUE(s.state == a && s.mood == mood && s.variant == in.variant);
      TEST_ASSERT_TRUE(s.t == 0 && !s.eyesShut);
      const uint32_t loop = loopMs(mood, a, in.variant);
      r.at(1000 + loop - 1);
      TEST_ASSERT_EQUAL(a, r.anim());
      TEST_ASSERT_EQUAL_UINT32(loop - 1, r.b.show(r.t).t);
      r.at(1000 + loop);
      TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
      s = r.b.show(r.t);
      TEST_ASSERT_TRUE(s.state == SceneState::kTerminal && !s.eyesShut);
      app::PlayedOut e;
      TEST_ASSERT_FALSE(r.b.takePlayedOut(e));
    }
  }
}

// An animation's variation is the Mac's when it's one of
// its design's for the reaction's facts (a finish's outcome, a start's
// context); otherwise the device picks one of those at random, never the
// one it showed last.
static void test_a_reaction_plays_a_fitting_variation() {
  using render::Mood;
  using render::Outcome;
  using render::StartCtx;
  Rig r;
  Model calm = base("idle");
  calm.mood = Mood::kCalm;
  r.state(calm);
  // Happy's starts: one each for a new task, a session and carrying on.
  TEST_ASSERT_EQUAL_INT(1, r.b.pick(SceneState::kStarting, Mood::kHappy, 2, Outcome::kNone, StartCtx::kSession, r.rng));
  TEST_ASSERT_EQUAL_INT(1, r.b.pick(SceneState::kStarting, Mood::kHappy, 1, Outcome::kNone, StartCtx::kSession, r.rng));
  TEST_ASSERT_EQUAL_INT(1, r.b.pick(SceneState::kStarting, Mood::kHappy, 0, Outcome::kNone, StartCtx::kSession, r.rng));
  TEST_ASSERT_EQUAL_INT(2, r.b.pick(SceneState::kStarting, Mood::kHappy, 9, Outcome::kNone, StartCtx::kContinuation, r.rng));
  // Without a context, any; the Mac's first among them.
  TEST_ASSERT_EQUAL_INT(0, r.b.pick(SceneState::kStarting, Mood::kHappy, 1, Outcome::kNone, StartCtx::kNone, r.rng));
  // Happy's finishes: four successes, and a failure, the fifth.
  TEST_ASSERT_EQUAL_INT(4, r.b.pick(SceneState::kTaskComplete, Mood::kHappy, 0, Outcome::kFailure, StartCtx::kNone, r.rng));
  TEST_ASSERT_EQUAL_INT(4, r.b.pick(SceneState::kTaskComplete, Mood::kHappy, 2, Outcome::kFailure, StartCtx::kNone, r.rng));
  TEST_ASSERT_EQUAL_INT(2, r.b.pick(SceneState::kTaskComplete, Mood::kHappy, 3, Outcome::kSuccess, StartCtx::kNone, r.rng));
  // Calm's starts for a new task, the first three of nine, picked in order:
  // never the one shown last, and all of them.
  bool seen[9] = {};
  int last = -1;
  for (int i = 0; i < 60; ++i) {
    ReactionIn in;
    in.anim = SceneState::kStarting;
    in.variant = r.b.pick(in.anim, Mood::kCalm, 0, Outcome::kNone, StartCtx::kNewTask, r.rng);
    TEST_ASSERT_TRUE(render::variantCtx(Mood::kCalm, SceneState::kStarting, in.variant) == StartCtx::kNewTask);
    TEST_ASSERT_NOT_EQUAL(last, in.variant);
    last = in.variant, seen[in.variant] = true;
    r.at(r.t + 100);
    onReaction(r.b, in, r.t);
  }
  TEST_ASSERT_TRUE(seen[0] && seen[1] && seen[2]);
  // Calm's failed finishes, likewise.
  last = -1;
  for (int i = 0; i < 30; ++i) {
    ReactionIn in;
    in.anim = SceneState::kTaskComplete;
    in.variant = r.b.pick(in.anim, Mood::kCalm, 1, Outcome::kFailure, StartCtx::kNone, r.rng);  // 1 is a success
    TEST_ASSERT_TRUE(render::variantOutcome(Mood::kCalm, SceneState::kTaskComplete, in.variant) == Outcome::kFailure);
    TEST_ASSERT_NOT_EQUAL(last, in.variant);
    last = in.variant;
    r.at(r.t + 100);
    onReaction(r.b, in, r.t);
  }
  // One to choose from: no roll.
  app::Rng a, b;
  r.b.pick(SceneState::kReplyReady, Mood::kHappy, 0, Outcome::kNone, StartCtx::kNone, a);
  TEST_ASSERT_EQUAL_UINT32(b.next(), a.next());
}

// A brain's face with no animation that comes during a
// rule's reaction or a poke plays over it without cutting it: the rule's reaction's
// design, drawn in the brain's mood, on its own clock, which ends when it
// would have.
static void test_a_face_plays_over_a_rules_reaction() {
  NEEDS_VOICE_PACK();
  for (SceneState a : {SceneState::kError, SceneState::kPoked}) {
    Rig r;
    r.state(base("working"));
    r.at(1000);
    ReactionIn in;
    in.anim = a;
    onReaction(r.b, in, r.t);
    const uint32_t loop = loopMs(render::Mood::kHappy, a);
    r.at(1500);
    const uint32_t seq = r.b.reactionSeq();
    TEST_ASSERT_TRUE(onReaction(r.b, expressive(render::Mood::kGrumpy), r.t));
    TEST_ASSERT_EQUAL(seq + 1, r.b.reactionSeq());  // the `say` only
    SceneShow s = r.b.show(r.t);
    TEST_ASSERT_TRUE(s.state == a && s.mood == render::Mood::kGrumpy);
    TEST_ASSERT_EQUAL_UINT32(500, s.t);
    uint32_t left;
    TEST_ASSERT_EQUAL(a, r.b.reaction(r.t, left));
    TEST_ASSERT_EQUAL_UINT32(loop - 500, left);
    TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  }
}

// None of the rules' reactions plays while something needs
// you or listening waits for the reply.
static void test_no_rules_reaction_while_the_face_is_held() {
  for (SceneState a : {SceneState::kStarting, SceneState::kStopped, SceneState::kError, SceneState::kHelperReturn, SceneState::kReplyReady}) {
    Rig r;
    r.state(attn());
    ReactionIn in;
    in.anim = a, in.key = 3;
    TEST_ASSERT_EQUAL_STRING("needs_you", r.b.admit(in, r.t));  // the kit skips it
    TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
    TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNeedsYou);
    TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
    Rig l;
    l.state(base("idle"));
    l.talkOn();
    in.key = 0;
    onReaction(l.b, in, l.t);
    TEST_ASSERT_EQUAL(SceneState::kListening, l.anim());
  }
}

// Only the reply ends listening: a reaction
// with a `say` (a take or none), or stop_listening. A rule's reaction, a finish
// or a poke with no `say` and a face on its own leave it be.
static void test_only_the_reply_ends_listening() {
  Rig r;
  r.state(base("idle"));
  r.talkOn();
  const uint32_t seq = r.b.reactionSeq();
  for (SceneState a : {SceneState::kStarting, SceneState::kStopped, SceneState::kError, SceneState::kHelperReturn, SceneState::kTaskComplete,
                 SceneState::kReplyReady, SceneState::kPoked, SceneState::kTapSpam}) {
    ReactionIn in;
    in.anim = a;
    onReaction(r.b, in, r.t);
    TEST_ASSERT_EQUAL(SceneState::kListening, r.anim());
  }
  ReactionIn face;  // a mood and nothing else
  face.expr = true, face.mood = render::Mood::kProud;
  onReaction(r.b, face, r.t);
  ReactionIn unknown;  // an animation the device doesn't know reads as none, and isn't empty
  onReaction(r.b, unknown, r.t);
  TEST_ASSERT_EQUAL(SceneState::kListening, r.anim());
  TEST_ASSERT_EQUAL(seq, r.b.reactionSeq());
  ReactionIn said;  // a `say` with no take is still the reply
  said.said = true;
  onReaction(r.b, said, r.t);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  r.talkOn();
  r.stop();
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
}

// What shows, first first: no app, listening, needs you,
// a tap's poke and the reactions, then the look.
static void test_what_shows_first() {
  Rig r;
  Model m = base("working");
  m.act = SceneState::kTesting;
  r.state(m);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kTesting);  // 5. the look
  r.at(1000);
  r.react(SceneState::kStarting);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kStarting);  // 4. a reaction
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kPoked);  // 4. a poke replaces it
  r.react(SceneState::kError);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kError);  // and a reaction the poke
  r.state(attn());
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNeedsYou);  // 3. needs you cuts them
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  r.b.tap(r.t, r.rng);
  r.react(SceneState::kStopped);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNeedsYou);
  r.talkOn();
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kListening);  // 2. listening over needs you
  r.at(1000 + Behaviour::kNoAppMs);
  TEST_ASSERT_EQUAL(SceneState::kListening, r.anim());
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNoApp);  // 1. no app over all of it
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kNoApp);
}

// A `say` that comes with an animation starts at its design's
// voice window (render::pixel::Score::voiceMs), bubble and mouth alike, and the
// animation holds on at least until the `say` and its bubble are over,
// resting on its last frame, rather than the `say` being hurried. The
// expression holds as long. A `say` on its own starts at once.
static void test_a_finishs_say_waits_for_its_voice_window() {
  NEEDS_VOICE_PACK();
  using render::Mood;
  Rig r;
  Model m = base("idle");
  m.mood = Mood::kGrumpy;
  r.state(m);
  r.at(1000);
  ReactionIn in;
  in.anim = SceneState::kTaskComplete, in.variant = 4;  // grumpy's failed finish
  in.said = true, in.take = voice::takeIndex("new.d20");  // "Mwahaha...", 2434 ms
  in.expr = true, in.mood = Mood::kGrumpy, in.key = 5;
  const uint32_t voice = render::pixel::score(render::pixelIndex(Mood::kGrumpy), int(SceneState::kTaskComplete), 4).voiceMs;
  const uint32_t loop = loopMs(Mood::kGrumpy, SceneState::kTaskComplete, 4);
  uint32_t line = 2434 + Behaviour::kBubbleReadMs;
  TEST_ASSERT_TRUE(voice > 0 && voice + line > loop);  // it doesn't fit: the hold stretches
  TEST_ASSERT_TRUE(onReaction(r.b, in, r.t));
  uint32_t left;
  r.b.reaction(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(voice + line, left);
  r.at(1000 + voice - 1);
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_TRUE(r.b.sayAhead(r.t));
  TEST_ASSERT_FALSE(r.b.speaking(r.t));
  TEST_ASSERT_FALSE(r.b.show(r.t).mouthOpen);
  r.at(1000 + voice);
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_TRUE(r.b.speaking(r.t));
  TEST_ASSERT_TRUE(r.b.show(r.t + firstOpen("new.d20")).mouthOpen);
  // Past its loop, the design rests on its last frame, in the brain's face.
  r.at(1000 + loop + 200);
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kTaskComplete && s.mood == Mood::kGrumpy);
  TEST_ASSERT_EQUAL_UINT32(loop - 1, s.t);
  r.at(1000 + voice + line - 1);
  TEST_ASSERT_EQUAL(SceneState::kTaskComplete, r.anim());
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(1000 + voice + line);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  render::Mood face;
  TEST_ASSERT_FALSE(r.b.expression(r.t, face));
  TEST_ASSERT_EQUAL_STRING("5 done", ended(r).c_str());
  // A `say` that fits ends first: the animation plays its loops, and the
  // strip comes back once the bubble goes.
  r.state(m);
  in.anim = SceneState::kReplyReady, in.variant = 0, in.key = 6;
  in.take = voice::takeIndex(kGo);
  line = kGoMs + Behaviour::kBubbleReadMs;
  in.whoAgent = "codex", in.whoThread = "landing";
  onReaction(r.b, in, r.t);
  const uint32_t reply = render::pixel::score(render::pixelIndex(Mood::kGrumpy), int(SceneState::kReplyReady), 0).voiceMs;
  const uint32_t replyLoop = loopMs(Mood::kGrumpy, SceneState::kReplyReady);
  TEST_ASSERT_TRUE(reply + line < replyLoop);
  r.b.reaction(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(replyLoop, left);
  const uint32_t at = r.t;
  r.at(at + reply + line);
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_EQUAL_STRING("codex", r.b.strip(r.t).doneAgent);
  r.at(at + replyLoop);
  TEST_ASSERT_EQUAL_STRING("6 done", ended(r).c_str());
  // Tapped before its `say`: the poke replaces the finish, which was cut,
  // but the `say` still plays at its window, over the poke. (One that
  // names whose turn it was isn't poked: the tap opens that thread.)
  r.at(at + replyLoop + 1000);
  r.state(m);
  in.key = 7, in.whoAgent = nullptr, in.whoThread = nullptr;
  onReaction(r.b, in, r.t);
  const uint32_t tapped = r.t;
  r.at(r.t + 100);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(SceneState::kPoked, r.anim());
  TEST_ASSERT_TRUE(r.b.sayAhead(r.t));
  r.at(tapped + reply);
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(tapped + replyLoop);  // its face holds for the finish's loop
  TEST_ASSERT_EQUAL_STRING("7 cut by tap", ended(r).c_str());
}

// A new mood's flip-book blinks in a step
// of its own, so the device gives it none of its blinks; a change of design
// to or from one dissolves as any other does, its eyes open.
static void test_flip_books_blink_by_themselves() {
  Model calm = base("idle");
  calm.mood = render::Mood::kCalm;
  TEST_ASSERT_TRUE(deviceBlinks(blinkStarts(calm, true, 120000)).empty());
  Model working = base("working");
  working.mood = render::Mood::kWounded;
  TEST_ASSERT_TRUE(deviceBlinks(blinkStarts(working, true, 120000)).empty());
  TEST_ASSERT_TRUE(render::blinksItself(render::Mood::kCalm, SceneState::kIdle, 0));
  TEST_ASSERT_FALSE(render::blinksItself(render::Mood::kHappy, SceneState::kIdle, 0));
  Rig r;
  r.state(calm);
  r.at(3000);
  const SceneShow open = r.b.show(r.t);  // between its own blinks
  TEST_ASSERT_FALSE(open.eyesShut || render::eyesClosed(open));
  r.state(working);
  const SceneShow s = r.b.show(r.t);
  TEST_ASSERT_FALSE(s.eyesShut || render::eyesClosed(s));
}

// ---- Through the device core: gestures and the input messages ------------

namespace {

struct FakeHal : app::Hal {
  uint32_t realMs() override { return 0; }
  const char* fwVersion() override { return "t"; }
  const char* gitSha() override { return "t"; }
};
struct Capture : linkkit::Out {
  std::string text;
  void write(const char* s, size_t n) override { text.append(s, n); }
};
struct DevRig {
  FakeHal hal;
  Capture usb;
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(render::kWidth) * render::kHeight);
  app::Device dev{hal, px.data()};
  linkkit::Kit kit{hal, dev, true};
  DevRig() {
    kit.setOut(linkkit::Link::kUsb, &usb);
    line("{\"t\":\"state\",\"base\":\"idle\"}");
  }
  void line(const char* s) {
    kit.handleLine(s, std::strlen(s), linkkit::Link::kUsb);
    kit.tick();
  }
  void clock(uint32_t t) {
    std::string s = "{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(t) + "}";
    line(s.c_str());
  }
  bool has(const char* needle) const { return usb.text.find(needle) != std::string::npos; }
  // What's on the screen, as dbg.state says.
  std::string screen() {
    line("{\"t\":\"dbg.state\"}");
    size_t i = usb.text.rfind("\"screen\":\"") + 10;
    return usb.text.substr(i, usb.text.find('"', i) - i);
  }
  int count(const char* needle) const {
    int n = 0;
    for (size_t at = usb.text.find(needle); at != std::string::npos; at = usb.text.find(needle, at + 1)) ++n;
    return n;
  }
};

}  // namespace

const char* const kTap = "{\"t\":\"ev\",\"kind\":\"tap\",";  // with what it did
const char* const kTalkOn = "{\"t\":\"ev\",\"kind\":\"talk_on\",\"did\":\"listening\"}";
const char* const kTalkOff = "{\"t\":\"ev\",\"kind\":\"talk_off\"}";

// A BOOT press under 400 ms is a tap and a hold is
// push-to-talk; a touch anywhere, the strip included, is a tap sent on
// release, however long it was held.
static void test_gestures_send_the_right_inputs() {
  DevRig r;
  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":100}");  // tap the face
  r.clock(100);
  TEST_ASSERT_EQUAL(1, r.count(kTap));
  r.line("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(r.has("\"anim\":\"poked\""));

  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":2000}");  // a long touch on the face
  r.clock(1500);
  TEST_ASSERT_EQUAL(1, r.count(kTap));  // nothing yet
  r.clock(2100);
  TEST_ASSERT_EQUAL(2, r.count(kTap));  // a tap, on release

  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":222,\"ms\":800}");  // hold the strip
  r.clock(3000);
  TEST_ASSERT_EQUAL(3, r.count(kTap));
  TEST_ASSERT_EQUAL_STRING("face", r.screen().c_str());

  r.line("{\"t\":\"dbg.press\",\"ms\":100}");  // BOOT tap
  r.clock(3200);
  TEST_ASSERT_EQUAL(4, r.count(kTap));
  r.clock(3300);
  r.line("{\"t\":\"dbg.press\",\"ms\":800}");  // BOOT held
  r.clock(3699);
  TEST_ASSERT_EQUAL(0, r.count(kTalkOn));  // not yet 400 ms
  r.clock(3700);
  TEST_ASSERT_EQUAL(1, r.count(kTalkOn));
  r.clock(4100);
  TEST_ASSERT_EQUAL(1, r.count(kTalkOff));
  TEST_ASSERT_EQUAL(4, r.count(kTap));  // no tap on release
  // Only these three inputs exist.
  TEST_ASSERT_EQUAL(r.count("\"t\":\"ev\""), r.count(kTap) + r.count(kTalkOn) + r.count(kTalkOff));
}

// A long touch during needs you is a tap too: the squash, and no reaction.
static void test_a_long_touch_during_needs_you_is_a_tap() {
  DevRig r;
  r.line("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"landing\"}}");
  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":800}");
  r.clock(700);
  TEST_ASSERT_FALSE(r.has(kTap));
  r.clock(800);
  TEST_ASSERT_TRUE(r.has(kTap));
  r.usb.text.clear();
  r.line("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(r.has("\"screen\":\"needs_you\""));
  TEST_ASSERT_TRUE(r.has("\"moment\":null"));
}

// Occasions (render/tags.h): a look's variation that needs tags shows
// only while they're all on. A new look starts on it while it fits, the
// turns keep to those that fit (an occasion's kTaggedPct of the time), and
// one whose tags go off turns away at its loop's end. Happy's idle: the
// morning coffee is its 7th variation (index 6), the nightcap its 8th.
static void test_an_occasion_shows_only_while_its_tags_are_on() {
  using render::pixel::PixelFace;
  const int coffee = 6, nightcap = 7;
  TEST_ASSERT_TRUE(render::tagged(render::Mood::kHappy, SceneState::kIdle, coffee));
  TEST_ASSERT_FALSE(render::tagged(render::Mood::kHappy, SceneState::kIdle, 0));
  Rig r;
  r.state(base("asleep"));
  r.at(5);
  Model m = base("idle");
  m.when = render::tagBit("morning");
  r.state(m);
  r.at(10);
  TEST_ASSERT_EQUAL_INT(coffee, r.b.show(r.t).variant);  // a new look starts on it
  // Of the turns from an ordinary variation, about two in three go to the
  // coffee, the only occasion that fits; a turn from it goes elsewhere.
  int shown = coffee, occasions = 0, turns = 0;
  for (uint32_t t = 20; t <= 1800000; t += 10) {
    r.at(t);
    if (t % 10000 == 0) r.state(m);
    int v = r.b.show(t).variant;
    TEST_ASSERT_TRUE(v != nightcap);  // night isn't on
    if (v == shown) continue;
    if (shown != coffee) ++turns, occasions += v == coffee;
    shown = v;
  }
  TEST_ASSERT_TRUE(turns >= 30);
  TEST_ASSERT_TRUE(occasions * 100 >= turns * (PixelFace::kTaggedPct - 15));
  TEST_ASSERT_TRUE(occasions * 100 <= turns * (PixelFace::kTaggedPct + 15));
  // Morning ends: the coffee turns away at its loop's end, whatever the odds.
  r.look(uint8_t(coffee));
  m.when = render::tagBit("day");
  r.state(m);
  const uint32_t loop = render::loopMs(render::Mood::kHappy, SceneState::kIdle, coffee);
  r.at(r.t + loop + 10);
  TEST_ASSERT_NOT_EQUAL(coffee, r.b.show(r.t).variant);
  // A tag the board doesn't know is no tag.
  TEST_ASSERT_EQUAL_UINT32(0, render::tagBit("someday"));
  TEST_ASSERT_EQUAL_UINT32(1u << 18, render::tagBit("frantic"));
}

// A variation with a wait (`after`) shows only once its look has shown
// that long: the snore (asleep's 4th, index 3) after 10 minutes asleep.
// A new look starts the wait over.
static void test_a_variation_waits_for_its_look() {
  const int snore = 3;
  Rig r;
  Model m = base("asleep");
  r.state(m);
  bool early = false, late = false;
  for (uint32_t t = 100; t <= 3600000; t += 100) {
    r.at(t);
    if (t % 10000 == 0) r.state(m);
    if (r.b.show(t).variant != snore) continue;
    (t < 10 * 60000 ? early : late) = true;
  }
  TEST_ASSERT_FALSE(early);
  TEST_ASSERT_TRUE(late);
  r.state(base("idle"));
  r.state(m);
  r.at(r.t + 10);
  TEST_ASSERT_NOT_EQUAL(snore, r.b.show(r.t).variant);
}

// Nodding off (happy's idle 6th, index 4) and the long stretch (working's
// last) wait for the Mac's tiers, not for a time: idle's last, `tier5`,
// and the working stretch's `tier4`. An hour of either look without its
// tag never shows it; with the tag on it shows.
static void test_nodding_off_and_the_stretch_wait_for_the_tiers() {
  const int nodding = 4;
  const int stretch = render::variants(render::Mood::kHappy, SceneState::kWorking) - 1;
  const auto happy = render::Mood::kHappy;
  TEST_ASSERT_FALSE(render::fits(happy, SceneState::kIdle, nodding, 0, 7200000));
  TEST_ASSERT_TRUE(render::fits(happy, SceneState::kIdle, nodding, render::tagBit("tier5"), 0));
  TEST_ASSERT_FALSE(render::fits(happy, SceneState::kWorking, stretch, 0, 7200000));
  TEST_ASSERT_TRUE(render::fits(happy, SceneState::kWorking, stretch, render::tagBit("tier4"), 0));
  auto shows = [](const char* look, int variant, uint32_t when) {
    Rig r;
    Model m = base(look);
    m.when = when;
    r.state(m);
    bool shown = false;
    for (uint32_t t = 100; t <= 3600000 && !shown; t += 100) {
      r.at(t);
      if (t % 10000 == 0) r.state(m);
      shown = r.b.show(t).variant == variant;
    }
    return shown;
  };
  TEST_ASSERT_FALSE(shows("idle", nodding, 0));
  TEST_ASSERT_TRUE(shows("idle", nodding, render::tagBit("tier5")));
  TEST_ASSERT_FALSE(shows("working", stretch, 0));
  TEST_ASSERT_TRUE(shows("working", stretch, render::tagBit("tier4")));
}

// The working looks quicken with the agents working (render::workPace, which Behaviour hands the face as
// FaceContext::pace): calm with one, busy (125%) with two or three,
// frantic (160%) with four or more; the loop keeps its place as it changes.
static void test_the_working_looks_quicken_with_the_agents() {
  TEST_ASSERT_EQUAL_INT(100, render::workPace(1));
  TEST_ASSERT_EQUAL_INT(125, render::workPace(2));
  TEST_ASSERT_EQUAL_INT(125, render::workPace(3));
  TEST_ASSERT_EQUAL_INT(160, render::workPace(4));
  Rig r;
  Model m = base("working");
  m.busy = 1;
  r.state(m);
  r.look(0);
  r.at(1000);
  uint32_t calm = r.b.show(r.t).t;
  m.busy = 4;
  r.state(m);
  r.at(1000);
  TEST_ASSERT_EQUAL_UINT32(calm, r.b.show(r.t).t);  // no jump as it changes
  r.at(1500);
  TEST_ASSERT_UINT32_WITHIN(1, calm + 800, r.b.show(r.t).t);  // half a second at 160%
  r.state(base("idle"));
  r.at(1600);
  uint32_t idle = r.b.show(r.t).t;
  r.at(2100);
  TEST_ASSERT_EQUAL_UINT32(idle + 500, r.b.show(r.t).t);  // idle keeps its pace
  // So does needs you, however busy the agents.
  m.attn = true;
  r.state(m);
  r.at(2200);
  uint32_t asking = r.b.face().designMs(r.t);
  r.at(2700);
  TEST_ASSERT_EQUAL_UINT32(asking + 500, r.b.face().designMs(r.t));
}

// A reaction whose occasion is on plays it, whatever the Mac asked for:
// the party wake-up (wake_up's 2nd) on a party day, else the plain one.
static void test_a_reactions_occasion_wins_while_on() {
  Rig r;
  Model m = base("idle");
  r.state(m);
  r.at(10);
  for (int i = 0; i < 20; ++i)
    TEST_ASSERT_EQUAL_INT(0, r.b.face().pick(SceneState::kWakeUp, render::Mood::kHappy, 1, render::Outcome::kNone,
                                               render::StartCtx::kNone, r.rng));
  m.when = render::tagBit("party") | render::tagBit("morning");
  r.state(m);
  r.at(20);
  for (int i = 0; i < 20; ++i)
    TEST_ASSERT_EQUAL_INT(1, r.b.face().pick(SceneState::kWakeUp, render::Mood::kHappy, 1, render::Outcome::kNone,
                                               render::StartCtx::kNone, r.rng));
}

// BOOT (Behaviour::press): while something needs you or an agent sits
// idle, it hands you the next one, and the board plays gesture's hand-off
// (its first variation, render::Gesture::kHandoff); with neither, it's a
// tap, a poke.
static void test_boot_hands_over_while_someone_waits() {
  Rig r;
  r.state(base("idle"));
  r.at(1000);
  TEST_ASSERT_EQUAL_STRING("poked", r.b.press(r.t, r.rng));
  TEST_ASSERT_TRUE(r.anim() == SceneState::kPoked);
  Model m = base("idle");
  m.idle = 2;
  r.state(m);
  r.at(5000);
  TEST_ASSERT_EQUAL_STRING("handoff", r.b.press(r.t, r.rng));
  TEST_ASSERT_TRUE(r.anim() == SceneState::kGesture);
  TEST_ASSERT_EQUAL_INT(int(render::Gesture::kHandoff), r.b.show(r.t).variant);
  r.at(9000);
  r.state(attn());
  r.at(9100);
  TEST_ASSERT_EQUAL_STRING("handoff", r.b.press(r.t, r.rng));  // needs you, idle or not
  TEST_ASSERT_EQUAL_STRING("handoff", render::gestureName(render::Gesture::kHandoff));
  TEST_ASSERT_EQUAL_STRING("peekaboo", render::gestureName(render::Gesture::kPeekaboo));
}

// The work stream's model (render/stream.h): a lane whose count moves drops
// a word for each new call, at most kDropsPerState a `state`, each
// kWordGapPx behind its lane's newest and never faster, so they never
// overlap, or none if that's over kMostWaitMs away; a new lane drops its
// latest; a lane gone, or the stream hidden (needs you), takes its words; a
// word falls for kFallMs and a word forward lasts kCallMs.
static void test_the_work_streams_words() {
  TEST_ASSERT_EQUAL_UINT32(3200, render::Stream::kFallMs);
  TEST_ASSERT_EQUAL_INT(2, render::Stream::kDropsPerState);
  TEST_ASSERT_EQUAL_INT(36, render::Stream::kWordGapPx);
  TEST_ASSERT_EQUAL_UINT32(800, render::Stream::kMostWaitMs);
  TEST_ASSERT_EQUAL_UINT32(2500, render::Stream::kCallMs);
  render::Stream s;
  render::Stream::Lane lanes[2];
  lanes[0].slot = 0, lanes[0].count = 4, std::strcpy(lanes[0].word, "grep");
  auto live = [&] {
    int n = 0;
    for (const auto& w : s.words) n += w.live;
    return n;
  };
  s.setLanes(lanes, 1, true, false, 0);
  TEST_ASSERT_EQUAL_INT(1, live());
  lanes[0].count = 5;
  s.setLanes(lanes, 1, true, false, 100);
  TEST_ASSERT_EQUAL_INT(2, live());
  lanes[0].count = 15;  // ten calls in one state: two words
  s.setLanes(lanes, 1, true, false, 200);
  TEST_ASSERT_EQUAL_INT(4, live());
  // Each a word behind the one before: dropping once it's fallen
  // kWordGapPx, never faster.
  const render::Stream::Word* byAge[4];
  for (int i = 0; i < 4; ++i) byAge[i] = &s.words[i];
  std::sort(byAge, byAge + 4, [](auto* a, auto* b) { return int32_t(a->born - b->born) < 0; });
  for (int i = 1; i < 4; ++i) {
    const auto &before = *byAge[i - 1], &after = *byAge[i];
    TEST_ASSERT_TRUE(after.speed <= before.speed);
    TEST_ASSERT_TRUE(int(after.born - before.born) * before.speed >= render::Stream::kWordGapPx * 1000);
  }
  const uint32_t last = byAge[3]->born;
  s.setLanes(lanes, 1, true, false, 300);  // the same count: none
  TEST_ASSERT_EQUAL_INT(4, live());
  lanes[1].slot = 2, lanes[1].count = 1, std::strcpy(lanes[1].word, "sed");
  s.setLanes(lanes, 2, true, false, 300);
  TEST_ASSERT_EQUAL_INT(5, live());
  TEST_ASSERT_EQUAL_INT(1, s.column(2));
  // The first lane's session rests: its words fall on where they dropped.
  const int16_t x = s.words[0].x;
  s.setLanes(&lanes[1], 1, true, false, 400);
  TEST_ASSERT_EQUAL_INT(5, live());
  TEST_ASSERT_EQUAL_INT(-1, s.column(0));
  TEST_ASSERT_EQUAL_INT(x, s.words[0].x);
  s.prune(last + render::Stream::kFallMs - 1);
  TEST_ASSERT_EQUAL_INT(1, live());
  s.prune(last + render::Stream::kFallMs);
  TEST_ASSERT_EQUAL_INT(0, live());
  s.startCall("make", 2, render::callGagFromName("bonk"), 0, 5000);
  TEST_ASSERT_TRUE(s.call.live && s.call.gag == render::CallGag::kBonk);
  TEST_ASSERT_EQUAL_STRING("bonk", render::callGagName(s.call.gag));
  TEST_ASSERT_TRUE(render::callGagFromName("nonsense") == render::CallGag::kLand);
  s.prune(5000 + render::Stream::kCallMs);
  TEST_ASSERT_FALSE(s.call.live);

  // The agents done: the stream off, its words linger kEndMs, and a word
  // forward may still come in that time.
  TEST_ASSERT_EQUAL_UINT32(1500, render::Stream::kEndMs);
  TEST_ASSERT_EQUAL_UINT32(700, render::Stream::kTakeMs);
  lanes[0].count = 16;
  s.setLanes(lanes, 1, true, false, 10000);
  TEST_ASSERT_EQUAL_INT(1, live());
  s.setLanes(nullptr, 0, false, false, 10100);
  TEST_ASSERT_TRUE(s.ending && s.accepts(10100 + render::Stream::kEndMs - 1));
  TEST_ASSERT_FALSE(s.accepts(10100 + render::Stream::kEndMs));
  TEST_ASSERT_EQUAL_INT(1, live());
  // A turn's end gathers its lane's words: they're its for kTakeMs, then gone.
  s.startCall("done", 0, render::callGagFromName("gather"), 0, 10200);
  int taken = 0;
  for (const auto& w : s.words) taken += s.taken(w);
  TEST_ASSERT_EQUAL_INT(1, taken);
  s.prune(10200 + render::Stream::kTakeMs - 1);
  TEST_ASSERT_EQUAL_INT(1, live());
  s.prune(10200 + render::Stream::kTakeMs);
  TEST_ASSERT_EQUAL_INT(0, live());
  TEST_ASSERT_TRUE(s.drawn(10200 + render::Stream::kTakeMs));

  // A freeze holds the words falling where they are; after it they fall on
  // from there.
  s.setLanes(lanes, 1, true, false, 20000);
  TEST_ASSERT_EQUAL_INT(1, live());
  s.startCall("rate limit", 0, render::CallGag::kFreeze, 0, 21000);
  TEST_ASSERT_TRUE(s.frozen());
  s.prune(21000 + render::Stream::kCallMs - 1);
  TEST_ASSERT_EQUAL_INT(1, live());  // 3.5 s old, held
  s.prune(21000 + render::Stream::kCallMs);
  TEST_ASSERT_FALSE(s.frozen());
  TEST_ASSERT_EQUAL_INT(1, live());
  for (const auto& w : s.words)
    if (w.live) TEST_ASSERT_EQUAL_UINT32(20000 + render::Stream::kCallMs, w.born);

  // Something needs you: everything goes at once.
  s.startCall("make", 0, render::CallGag::kBonk, 0, 24000);
  s.setLanes(nullptr, 0, false, true, 24100);
  TEST_ASSERT_FALSE(s.call.live);
  TEST_ASSERT_EQUAL_INT(0, live());
  TEST_ASSERT_FALSE(s.accepts(24100));
}

int main() {
  UNITY_BEGIN();
  if (!voicefile::open()) std::printf("no voice file: the chosen character pack has none\n");
  RUN_TEST(test_the_work_streams_words);
  RUN_TEST(test_needs_you_alerts_once_and_stays_amber);
  RUN_TEST(test_a_different_needs_you_with_the_same_names_alerts);
  RUN_TEST(test_tap_during_needs_you_is_only_the_dip_and_stays_amber);
  RUN_TEST(test_answering_on_the_mac_goes_back);
  RUN_TEST(test_needs_you_wins_over_reactions);
  RUN_TEST(test_changes_mid_motion_start_the_new_design);
  RUN_TEST(test_no_app_holds_for_weeks);
  RUN_TEST(test_no_change_ever_cuts_hard);
  RUN_TEST(test_a_switch_dissolves_over_200_ms);
  RUN_TEST(test_a_switch_mid_dissolve_dissolves_from_what_shows_more);
  RUN_TEST(test_the_needs_you_screen_dissolves_both_ways);
  RUN_TEST(test_a_switch_back_mid_needs_you_dissolve_doesnt_pop);
  RUN_TEST(test_a_double_tap_doesnt_flash_back);
  RUN_TEST(test_a_poke_while_asleep_has_its_own_eyes);
  RUN_TEST(test_only_a_press_on_the_rig_face_kicks_it);
  RUN_TEST(test_a_lane_at_the_same_dither_level_isnt_drawn_again);
  RUN_TEST(test_nothing_cuts_hard_as_it_plays_out);
  RUN_TEST(test_push_to_talk_listens_then_waits);
  RUN_TEST(test_listening_holds_until_the_reply);
  RUN_TEST(test_listening_plays_while_something_needs_you);
  RUN_TEST(test_the_empty_reaction_ends_only_listening);
  RUN_TEST(test_push_to_talk_timeouts);
  RUN_TEST(test_listening_rotates_its_variations);
  RUN_TEST(test_reactions_end_and_replace);
  RUN_TEST(test_a_cheer_plays_its_loops);
  RUN_TEST(test_a_take_moves_the_mouth);
  RUN_TEST(test_a_say_of_two_takes);
  RUN_TEST(test_a_say_alone_plays_over_the_face);
  RUN_TEST(test_a_face_alone_plays_its_loops);
  RUN_TEST(test_an_expression_holds_its_loops);
  RUN_TEST(test_an_expression_over_the_cheer_and_across_a_look_change);
  RUN_TEST(test_an_expression_ends_with_its_reaction);
  RUN_TEST(test_a_waited_reaction_says_how_it_ended);
  RUN_TEST(test_the_clock_going_back_starts_the_look_over);
  RUN_TEST(test_life_is_blinks_at_their_pace);
  RUN_TEST(test_asleep_breathes_and_never_blinks);
  RUN_TEST(test_taps_poke_and_a_run_spams);
  RUN_TEST(test_taps_rotate_their_variations);
  RUN_TEST(test_a_held_face_counts_taps_but_only_dips);
  RUN_TEST(test_an_act_shows_in_workings_place);
  RUN_TEST(test_an_acts_variations_rotate);
  RUN_TEST(test_a_rules_reaction_plays_once);
  RUN_TEST(test_a_reaction_plays_a_fitting_variation);
  RUN_TEST(test_a_face_plays_over_a_rules_reaction);
  RUN_TEST(test_no_rules_reaction_while_the_face_is_held);
  RUN_TEST(test_only_the_reply_ends_listening);
  RUN_TEST(test_what_shows_first);
  RUN_TEST(test_a_finishs_say_waits_for_its_voice_window);
  RUN_TEST(test_flip_books_blink_by_themselves);
  RUN_TEST(test_each_look_shows_its_design_in_the_mood);
  RUN_TEST(test_the_looks_variations_rotate);
  RUN_TEST(test_an_occasion_shows_only_while_its_tags_are_on);
  RUN_TEST(test_a_variation_waits_for_its_look);
  RUN_TEST(test_nodding_off_and_the_stretch_wait_for_the_tiers);
  RUN_TEST(test_the_working_looks_quicken_with_the_agents);
  RUN_TEST(test_a_reactions_occasion_wins_while_on);
  RUN_TEST(test_boot_hands_over_while_someone_waits);
  RUN_TEST(test_no_app_at_30s_and_reconnect_comes_back);
  RUN_TEST(test_a_cheer_names_whose_turn_in_the_strip);
  RUN_TEST(test_the_lane_fades_as_the_strip_comes_and_goes);
  RUN_TEST(test_a_todo_list_alone_shows_the_strip);
  RUN_TEST(test_the_lane_is_the_same_whatever_the_draw_cadence);
  RUN_TEST(test_a_face_for_a_finished_turn_marks_it);
  RUN_TEST(test_a_tap_on_a_named_finish_opens_its_thread);
  RUN_TEST(test_a_finish_linger_ends_when_the_face_is_taken);
  RUN_TEST(test_press_shows_within_20ms);
  RUN_TEST(test_gestures_send_the_right_inputs);
  RUN_TEST(test_a_long_touch_during_needs_you_is_a_tap);
  RUN_TEST(test_a_sign_shows_while_its_reaction_plays);
  return UNITY_END();
}
