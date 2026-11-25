// The behaviour state machine, with
// every timing checked to the millisecond.
#include <unity.h>

#include "voice_file.h"  // internal/firmware/
#include "stub_face.h"  // internal/firmware/
#include "wrapped_face.h"  // internal/firmware/

#include <algorithm>
#include <cstdio>
#include <memory>
#include <cstring>
#include <string>
#include <vector>

#include "app/behaviour.h"
#include "app/device.h"
#include "render/font.h"
#include "render/palette.h"
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
using testface::loopMs;

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
  Behaviour b{std::make_unique<testface::StubFace>()};
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

// The performance, with its knocks and ding, once when
// a needs-you starts, and nothing grows or nudges while it waits.
static void test_needs_you_alerts_once() {
  Rig r;
  r.at(1000);
  r.state(attn());
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kNeedsYou);
  TEST_ASSERT_EQUAL_STRING("alert@1000", r.alert().c_str());
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));
  // The performance plays once, then holds its pending pose.
  r.at(1000 + testface::loopMs(render::Mood::kHappy, SceneState::kNeedsYou) + 500);
  SceneShow first = r.b.show(r.t);
  TEST_ASSERT_TRUE(first.state == SceneState::kNeedsYou);
  first.eyesShut = false;
  for (uint32_t t = 20000; t <= 300000; t += 10000) {
    r.at(t);
    r.state(attn());  // the same needs-you: the performance doesn't play again
    TEST_ASSERT_EQUAL_STRING("alert@1000", r.alert().c_str());
    SceneShow now = r.b.show(t);
    TEST_ASSERT_TRUE(now.state == first.state && now.t == first.t);  // nothing else moves
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

// The face's frame at t, drawn into `px` as Device draws one: `dirty`
// after a message, when an unchanged picture is drawn again too.
static void drawFace(Rig& r, std::vector<uint8_t>& px, bool dirty) {
  render::Canvas c{px.data()};
  r.b.face().draw(c, nullptr, r.b.show(r.t), r.t, r.b.bubble(r.t), r.b.caption(r.t), r.b.sign(r.t), r.b.done(r.t), r.b.strip(r.t), dirty);
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

// Alone holds however long the Mac stays away, even past the 24.9 days where
// the clock's differences wrap, and whatever had finished stays finished when
// they come round again at 49.7 days: resting, then asleep, with no old `say`
// or press dip.
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
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kIdle);  // not working: nothing works with no app
  uint64_t now = r.t;
  // The clock moves on a minute at a time, as the ticks would take it.
  auto walk = [&](uint64_t to) {
    while (now + 60000 < to) now += 60000, r.at(uint32_t(now));
    now = to;
    r.at(uint32_t(now));
  };
  walk((1ull << 31) + 5000);  // past 2^31 ms
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kAsleep);
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  walk(0x100000000ull + 1150);  // 2^32 ms after the release, 150 after the `say` started
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kAsleep);
  TEST_ASSERT_FALSE(s.mouthOpen);
  TEST_ASSERT_FALSE(s.eyesShut);
  TEST_ASSERT_EQUAL_INT(0, s.dy);
  TEST_ASSERT_FALSE(r.b.strip(r.t).noApp);
  r.state(base("idle"));
  TEST_ASSERT_FALSE(r.b.noApp(r.t));
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
  r.at(r.t + testface::voiceMs(render::Mood::kProud, SceneState::kTaskComplete, 0));
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
// that plays; one showing when needs you starts plays on. A reply with no
// face of its own can't show, but it ends listening; the reply to what
// you said, with its face, shows its face and sign over needs you, never
// its `say`, and then the needs-you screen is back.
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
  // "Tell claude yes": the reply shakes its head and holds up its sign.
  a.talkOn();
  a.at(1000);
  ReactionIn refusal;
  refusal.said = true, refusal.expr = true, refusal.mood = render::Mood::kProud, refusal.take = voice::takeIndex(kGo);
  snprintf(refusal.sign, sizeof(refusal.sign), "%s", "that's ur job");
  snprintf(refusal.reply, sizeof(refusal.reply), "%s", "no");
  TEST_ASSERT_NULL(a.b.admit(refusal, a.t));
  TEST_ASSERT_FALSE(a.b.play(refusal, a.t));  // its say doesn't play
  TEST_ASSERT_EQUAL(SceneState::kNone, a.anim());
  TEST_ASSERT_TRUE(a.b.look(a.t) == SceneState::kNeedsYou);
  TEST_ASSERT_EQUAL_STRING("that's ur job", a.b.sign(a.t).text);
  TEST_ASSERT_NULL(a.b.bubble(a.t));  // no voice over needs you
  a.at(a.b.signEnd() + render::rig::kFadeMs + 1);
  TEST_ASSERT_NULL(a.b.sign(a.t).text);
  TEST_ASSERT_TRUE(a.b.show(a.t).state == SceneState::kNeedsYou);
  // A sign that isn't a reply still waits.
  ReactionIn plain;
  plain.expr = true, plain.mood = render::Mood::kHappy;
  snprintf(plain.sign, sizeof(plain.sign), "%s", "yay");
  TEST_ASSERT_EQUAL_STRING("needs_you", a.b.admit(plain, a.t));
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
  TEST_ASSERT_EQUAL_INT(3, testface::variants(render::Mood::kHappy, SceneState::kListening));
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
// A reaction's reason (`reason`) is the lane's caption while the reaction
// plays, as long as its sign would show, never the bubble's words; a newer
// reaction with none takes it down, and while something needs you it
// doesn't show.
static void test_a_reason_is_the_lanes_caption() {
  Rig r;
  r.state(base("idle"));
  r.at(1000);
  ReactionIn stroked = expressive(render::Mood::kAffectionate, nullptr);
  std::snprintf(stroked.reason, sizeof stroked.reason, "%s", "stroked");
  stroked.key = 1;
  auto lane = [&] { const char* s = r.b.caption(r.t); return std::string(s ? s : "-"); };
  onReaction(r.b, stroked, r.t);
  TEST_ASSERT_EQUAL_STRING("stroked", lane().c_str());
  TEST_ASSERT_NULL(r.b.laneBubble(r.t));  // alone, never as a bubble
  r.at(1000 + Behaviour::kSignMinMs - 1);
  TEST_ASSERT_EQUAL_STRING("stroked", lane().c_str());
  // A newer reaction with no reason takes it down.
  ReactionIn plain = expressive(render::Mood::kHappy, nullptr);
  plain.key = 2;
  onReaction(r.b, plain, r.t);
  TEST_ASSERT_EQUAL_STRING("-", lane().c_str());
  // While something needs you, a reason doesn't show.
  r.at(20000);
  r.state(attn());
  ReactionIn back = expressive(render::Mood::kHappy, nullptr);
  std::snprintf(back.reason, sizeof back.reason, "%s", "away 12 h");
  back.key = 3;
  onReaction(r.b, back, r.t);
  TEST_ASSERT_EQUAL_STRING("-", lane().c_str());
}

// A spoken reaction shows its words in the bubble and its reason as the
// caption under it, both at once.
static void test_a_spoken_reaction_shows_its_words_and_its_caption() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));
  r.at(1000);
  ReactionIn picked = expressive(render::Mood::kHappy);
  std::snprintf(picked.reason, sizeof picked.reason, "%s", "you picked Boop up");
  picked.key = 1;
  onReaction(r.b, picked, r.t);
  for (int i = 0; i < 100 && !r.b.bubble(r.t); ++i) r.at(r.t + 20);
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_EQUAL_STRING(r.b.bubble(r.t), r.b.laneBubble(r.t));
  TEST_ASSERT_EQUAL_STRING("you picked Boop up", r.b.caption(r.t));
}

// After the bubble the caption stays to be read: a spoken reaction's reason
// lasts kSignMinMs past its words, as a face with one row for both shows the
// bubble first.
static void test_a_spoken_reactions_caption_outlasts_its_words() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));
  r.at(1000);
  ReactionIn picked = expressive(render::Mood::kHappy);
  std::snprintf(picked.reason, sizeof picked.reason, "%s", "you picked Boop up");
  picked.key = 1;
  onReaction(r.b, picked, r.t);
  for (int i = 0; i < 100 && !r.b.bubble(r.t); ++i) r.at(r.t + 20);
  for (int i = 0; i < 1000 && r.b.bubble(r.t); ++i) r.at(r.t + 20);
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_EQUAL_STRING("you picked Boop up", r.b.caption(r.t));
  r.at(r.t + Behaviour::kSignMinMs);
  TEST_ASSERT_NULL(r.b.caption(r.t));
}

// A celebration's gold (`gold`, "level 13!") shows beside the sign, from
// the reaction's start, at least a low sign's time; a gold alone plays too.
// It takes the caption's row, a newer reaction takes it down, and while
// something needs you it doesn't show.
static void test_a_gold_shows_beside_the_sign() {
  Rig r;
  r.state(base("idle"));
  r.at(1000);
  ReactionIn both = expressive(render::Mood::kProud, nullptr);
  std::snprintf(both.sign, sizeof both.sign, "%s", "today's done!");
  std::snprintf(both.gold, sizeof both.gold, "%s", "level 13!");
  std::snprintf(both.reason, sizeof both.reason, "%s", "level 13!");
  both.key = 1;
  onReaction(r.b, both, r.t);
  render::SignShow s = r.b.sign(r.t);
  TEST_ASSERT_EQUAL_STRING("today's done!", s.text);
  TEST_ASSERT_EQUAL_STRING("level 13!", s.gold);
  TEST_ASSERT_EQUAL_UINT32(0, s.goldMs);
  TEST_ASSERT_NULL(r.b.caption(r.t));
  r.at(1000 + Behaviour::kLowSignMinMs - 1);
  TEST_ASSERT_EQUAL_STRING("level 13!", r.b.sign(r.t).gold);
  r.at(1000 + Behaviour::kLowSignMinMs);
  TEST_ASSERT_NULL(r.b.sign(r.t).gold);
  // Alone.
  r.at(10000);
  ReactionIn alone = expressive(render::Mood::kProud, nullptr);
  std::snprintf(alone.gold, sizeof alone.gold, "%s", "level 14!");
  alone.key = 2;
  TEST_ASSERT_NULL(r.b.admit(alone, r.t));
  onReaction(r.b, alone, r.t);
  TEST_ASSERT_EQUAL_STRING("level 14!", r.b.sign(r.t).gold);
  TEST_ASSERT_NULL(r.b.sign(r.t).text);
  // A newer reaction takes it down.
  ReactionIn plain = expressive(render::Mood::kHappy, nullptr);
  plain.key = 3;
  onReaction(r.b, plain, r.t);
  TEST_ASSERT_NULL(r.b.sign(r.t).gold);
  // Needs you hides it.
  onReaction(r.b, alone, r.t);
  r.state(attn());
  TEST_ASSERT_NULL(r.b.sign(r.t).gold);
}

// The wish on the board: the kind while the Mac says it waits; met or left,
// how it went for WishShow::kPopMs, whatever state comes under it; no pop
// with no wish shown before.
static void test_the_wish_shows_and_pops() {
  Rig r;
  Model m = base("idle");
  r.state(m);
  r.at(1000);
  TEST_ASSERT_EQUAL(int(render::WishShow::kNone), int(r.b.wishShow(r.t).kind));
  r.b.wishPopped(true, r.t);
  TEST_ASSERT_EQUAL(int(render::WishShow::kWaiting), int(r.b.wishShow(r.t).pop));
  m.wish = render::WishShow::kPet;
  r.state(m);
  TEST_ASSERT_EQUAL(int(render::WishShow::kPet), int(r.b.wishShow(r.t).kind));
  m.wish = render::WishShow::kNone;
  r.state(m);
  r.b.wishPopped(true, r.t);
  r.at(r.t + render::WishShow::kPopMs - 1);
  TEST_ASSERT_EQUAL(int(render::WishShow::kPet), int(r.b.wishShow(r.t).kind));
  TEST_ASSERT_EQUAL(int(render::WishShow::kMet), int(r.b.wishShow(r.t).pop));
  r.at(r.t + 1);
  TEST_ASSERT_EQUAL(int(render::WishShow::kNone), int(r.b.wishShow(r.t).kind));
}

// With no app the Mac's tags go, as they're stale: a night's or a holiday's
// would stay up all the next day.
static void test_alone_the_macs_tags_go() {
  const uint32_t party = render::tagBit("party");
  auto face = std::make_unique<testface::WrappedFace>();
  testface::WrappedFace& f = *face;
  Behaviour b(std::move(face));
  app::Rng rng;
  b.reset(0, rng);
  Model m = base("idle");
  m.when = party;
  b.onState(m, 100);
  b.advance(200, rng);
  TEST_ASSERT_EQUAL_HEX32(party, f.context.when);
  b.advance(100 + Behaviour::kNoAppMs, rng);
  TEST_ASSERT_TRUE(b.noApp(100 + Behaviour::kNoAppMs));
  TEST_ASSERT_EQUAL_HEX32(0, f.context.when);
}

// With no app the wish's bubble goes: nothing waits on a Mac that isn't there,
// and no touch could meet it. It comes back with the app, if it's still open.
static void test_the_wish_goes_with_the_app() {
  Rig r;
  Model m = base("idle");
  m.wish = render::WishShow::kPet;
  r.state(m);
  r.at(1000);
  TEST_ASSERT_EQUAL(int(render::WishShow::kPet), int(r.b.wishShow(r.t).kind));
  r.at(r.t + Behaviour::kNoAppMs);
  TEST_ASSERT_TRUE(r.b.noApp(r.t));
  TEST_ASSERT_EQUAL(int(render::WishShow::kNone), int(r.b.wishShow(r.t).kind));
  r.state(m);
  TEST_ASSERT_EQUAL(int(render::WishShow::kPet), int(r.b.wishShow(r.t).kind));
}

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
  in.anim = SceneState::kStarting, in.loops = 2;
  onReaction(r.b, in, r.t);
  TEST_ASSERT_EQUAL(SceneState::kStarting, r.anim());
  r.at(4201);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  TEST_ASSERT_EQUAL_UINT32(0, r.b.designMs(r.t));
  r.at(4301);
  TEST_ASSERT_EQUAL_UINT32(100, r.b.designMs(r.t));
  TEST_ASSERT_TRUE(r.b.show(r.t).t < loopMs(render::Mood::kHappy, SceneState::kIdle));
}

// Asleep, the screen dims.
static void test_asleep_dims() {
  Rig r;
  r.state(base("asleep"));
  r.at(20000);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kAsleep);
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
    const int n = testface::variants(render::Mood::kCalm, a);
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
}

// With no state for 30 s Boop rests, with the unplugged icon in the strip, and
// a stale needs you is gone; on reconnect it shows what the next state says,
// after a small hello.
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
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kIdle);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kIdle);
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));
  // The strip keeps only the unplugged icon: the counts are stale.
  render::Strip strip = r.b.strip(r.t);
  TEST_ASSERT_TRUE(strip.noApp);
  TEST_ASSERT_NULL(strip.agent);
  TEST_ASSERT_EQUAL(0, strip.busy);
  r.at(40000);
  r.state(base("idle"));
  TEST_ASSERT_EQUAL(SceneState::kNotice, r.anim());  // the hello
  r.at(40000 + 20000);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kIdle);
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));
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
  TEST_ASSERT_TRUE(strip.doneOutcome == render::Outcome::kSuccess);  // the first finish is a success
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
  in.variant = 1;  // the failed finish
  TEST_ASSERT_TRUE(testface::outcomeOf(SceneState::kTaskComplete, 1, render::Outcome::kNone) == render::Outcome::kFailure);
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
// message, so a frame drawn mid-fade isn't skipped: half way, the strip at
// half its opacity.
static void test_the_lane_is_the_same_whatever_the_draw_cadence() {
  struct Run {
    Rig r;
    std::vector<uint8_t> px = std::vector<uint8_t>(size_t(render::kWidth) * render::kHeight);
    render::Canvas c{px.data()};
    bool dirty = true;
    std::vector<std::vector<uint8_t>> lanes;
    std::vector<int> opacity;
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
        r.b.face().draw(c, nullptr, r.b.show(t), t, r.b.bubble(t), r.b.caption(t), r.b.sign(t), r.b.done(t), r.b.strip(t), dirty);
        dirty = false;
        for (uint32_t shot : shots)
          if (shot == t) {
            lanes.emplace_back(px.begin() + render::kStripTop * render::kWidth, px.end());
            opacity.push_back(r.b.strip(t).shows() ? r.b.strip(t).opacity : 0);
          }
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
  for (int i = 0; i < 4; ++i) {
    TEST_ASSERT_TRUE(often.lanes[i] == seldom.lanes[i]);
    TEST_ASSERT_EQUAL(often.opacity[i], seldom.opacity[i]);
  }
  TEST_ASSERT_TRUE(lit(often.lanes[1]) > 100);
  TEST_ASSERT_EQUAL(1000, often.opacity[1]);
  TEST_ASSERT_INT_WITHIN(100, 500, often.opacity[0]);  // fading in
  TEST_ASSERT_INT_WITHIN(100, 500, often.opacity[2]);  // fading out
  TEST_ASSERT_EQUAL(0, lit(often.lanes[3]));
}

// A reaction with no animation for a finished turn (its `who`) marks it as
// a finish does: named in the strip, and the face's DoneShow, from its
// start while any part of it plays (no end known), then counting down
// kFinishLingerMs, then nothing. A newer reaction naming nothing takes it
// down: no longer named, it leaves in kDoneLeaveMs. A new needs-you takes
// it at once.
static void test_a_face_for_a_finished_turn_marks_it() {
  static_assert(Behaviour::kFinishLingerMs == 5000, "a finished turn stays marked 5 s after its reaction");
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

// The rules' reaction (starting) plays its design once in Boop's mood,
// from its start, then the look comes back.
// They carry no id, so no `ended` goes back.
static void test_a_rules_reaction_plays_once() {
  for (SceneState a : {SceneState::kStarting}) {
    for (render::Mood mood : {render::Mood::kHappy, render::Mood::kCalm}) {
      Rig r;
      Model m = base("working");
      m.act = SceneState::kTerminal, m.mood = mood;
      r.state(m);
      r.at(1000);
      ReactionIn in;
      in.anim = a, in.variant = uint8_t(testface::variants(mood, a) - 1);
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

// A brain's face with no animation that comes during a
// rule's reaction or a poke plays over it without cutting it: the rule's reaction's
// design, drawn in the brain's mood, on its own clock, which ends when it
// would have.
static void test_a_face_plays_over_a_rules_reaction() {
  NEEDS_VOICE_PACK();
  for (SceneState a : {SceneState::kStarting, SceneState::kPoked}) {
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
  for (SceneState a : {SceneState::kStarting, SceneState::kReplyReady}) {
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
  for (SceneState a : {SceneState::kStarting, SceneState::kTaskComplete,
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
  r.react(SceneState::kWakeUp);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kWakeUp);  // and a reaction the poke
  r.state(attn());
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNeedsYou);  // 3. needs you cuts them
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  r.b.tap(r.t, r.rng);
  r.react(SceneState::kWakeUp);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNeedsYou);
  r.talkOn();
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kListening);  // 2. listening over needs you
  r.at(1000 + Behaviour::kNoAppMs);
  TEST_ASSERT_EQUAL(SceneState::kListening, r.anim());
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kIdle);  // 1. no app over all of it: only resting
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kIdle);
}

// A `say` that comes with an animation starts at its design's
// voice window (render::Face::voiceMs), bubble and mouth alike, and the
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
  in.anim = SceneState::kTaskComplete, in.variant = 1;  // the failed finish
  in.said = true, in.take = voice::takeIndex("new.d20");  // "Mwahaha...", 2434 ms
  in.expr = true, in.mood = Mood::kGrumpy, in.key = 5;
  const uint32_t voice = testface::voiceMs(Mood::kGrumpy, SceneState::kTaskComplete, 1);
  const uint32_t loop = loopMs(Mood::kGrumpy, SceneState::kTaskComplete, 1);
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
  const uint32_t reply = testface::voiceMs(Mood::kGrumpy, SceneState::kReplyReady, 0);
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

// The dream counts as told only if its sign was seen, so what takes the sign
// down before its time reports a cut the Mac won't read as done: a needs-you
// over an earlier stroke, the mic, face down. A stroke alone leaves the sign up.
static void test_a_greeting_whose_sign_is_lost_is_not_told() {
  const auto greet = [](Rig& r) {
    r.at(1000);
    r.state(base("idle"));
    ReactionIn in;
    in.greeting = true, in.key = 7;
    in.anim = SceneState::kNotice;
    in.expr = true, in.mood = render::Mood::kHappy;
    std::snprintf(in.sign, sizeof(in.sign), "had a dream");
    onReaction(r.b, in, r.t);
  };
  {  // A stroke, then a needs-you: the needs-you's report stands.
    Rig r;
    greet(r);
    r.at(1100);
    r.b.gesture(render::Gesture::kStroke, r.t);
    Model m = base("idle");
    m.attn = true, m.attnId = 3;
    r.at(1200);
    r.state(m);
    r.at(1300);
    TEST_ASSERT_EQUAL_STRING("7 cut by needs_you", ended(r).c_str());
  }
  {  // A stroke, and the sign plays out: you were there, as for any tap.
    Rig r;
    greet(r);
    r.at(1100);
    r.b.gesture(render::Gesture::kStroke, r.t);
    TEST_ASSERT_TRUE(r.b.signUp(r.t));
    r.at(1000 + Behaviour::kSignMinMs + 20000);
    TEST_ASSERT_EQUAL_STRING("7 cut by tap", ended(r).c_str());
  }
  {  // BOOT.
    Rig r;
    greet(r);
    r.at(1100);
    r.talkOn();
    r.at(1200);
    TEST_ASSERT_EQUAL_STRING("7 cut by mic_on", ended(r).c_str());
  }
  {  // Face down.
    Rig r;
    greet(r);
    r.at(1100);
    r.b.setFaceDown(true, r.t);
    r.at(1000 + 20000);
    TEST_ASSERT_EQUAL_STRING("7 cut by facedown", ended(r).c_str());
  }
  {  // A sign alone, no animation to cut: still.
    Rig r;
    r.at(1000);
    r.state(base("idle"));
    ReactionIn in;
    in.greeting = true, in.key = 8;
    in.expr = true, in.mood = render::Mood::kHappy;
    std::snprintf(in.sign, sizeof(in.sign), "had a dream");
    onReaction(r.b, in, r.t);
    r.at(1100);
    r.talkOn();
    r.at(1200);
    TEST_ASSERT_EQUAL_STRING("8 cut by mic_on", ended(r).c_str());
  }
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
  app::Device dev{hal, px.data(), std::make_unique<testface::StubFace>()};
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

// Pins the needs-you screen's tap: a touch on it shorter than
// Device::kNeedsYouTapMs (300 ms), and inside a hold's spot, is the tap that
// opens the waiting thread; a longer one, short of the hold that dismisses,
// or one that strays, was a hold let go early and sends nothing. Each
// shows only the squash, and plays no reaction.
static void test_a_long_touch_during_needs_you_sends_nothing() {
  TEST_ASSERT_EQUAL_UINT32(300, app::Device::kNeedsYouTapMs);
  DevRig r;
  r.line("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"landing\"}}");
  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":800}");
  r.clock(700);
  TEST_ASSERT_FALSE(r.has(kTap));
  r.clock(800);
  r.clock(900);
  TEST_ASSERT_FALSE(r.has(kTap));
  TEST_ASSERT_FALSE(r.has("\"did\":\"dismiss\""));
  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"to_x\":260,\"to_y\":100,\"ms\":200}");  // strays
  r.clock(1000);
  r.clock(1100);
  r.clock(1200);
  TEST_ASSERT_FALSE(r.has(kTap));
  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":200}");  // a tap
  r.clock(1300);
  r.clock(1400);
  TEST_ASSERT_TRUE(r.has(kTap));
  r.usb.text.clear();
  r.line("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(r.has("\"screen\":\"needs_you\""));
  TEST_ASSERT_TRUE(r.has("\"moment\":null"));
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

// An act hides while listening holds the screen, as while something needs
// you, and comes back where it got to: the Mac's `state` leaves `wact` out then.
static void test_listening_hides_an_act_and_it_resumes() {
  Rig r;
  r.at(1000);
  Model m = base("working");
  m.workAct.kind = render::ActKind::kPush;
  r.state(m);
  r.at(3000);
  TEST_ASSERT_EQUAL_INT(2000, r.b.stream().actNow(r.t).ageMs);
  r.talkOn();
  Model gone = m;
  gone.workAct = render::Stream::ActIn{};
  r.state(gone);
  TEST_ASSERT_FALSE(r.b.stream().actNow(r.t).shows());
  r.at(4000);
  r.state(m);
  TEST_ASSERT_TRUE(r.b.stream().actNow(r.t).shows());
  TEST_ASSERT_EQUAL_INT(3000, r.b.stream().actNow(r.t).ageMs);
  // With nothing holding the screen, an act gone from the state is over.
  r.stop();
  r.state(gone);
  r.state(m);
  TEST_ASSERT_EQUAL_INT(0, r.b.stream().actNow(r.t).ageMs);
}

// The work stream's model (render/stream.h): a lane whose count moves, or a
// new lane, makes its word the newest, the work's term, and its word as it
// changes; the same counts leave it on that lane; its lane gone, the newest
// is the last lane's; no lanes clear it. A word forward lasts kCallMs; the stream
// off, one may still come for kEndMs; something needing you takes all at
// once.
static void test_the_work_streams_newest_word() {
  TEST_ASSERT_EQUAL_UINT32(2500, render::Stream::kCallMs);
  TEST_ASSERT_EQUAL_UINT32(1500, render::Stream::kEndMs);
  render::Stream s;
  render::Stream::Lane lanes[2];
  lanes[0].slot = 0, lanes[0].count = 4, std::strcpy(lanes[0].word, "grep");
  s.setLanes(lanes, 1, true, false, 0);
  TEST_ASSERT_EQUAL_STRING("grep", s.newest);
  lanes[1].slot = 2, lanes[1].count = 1, std::strcpy(lanes[1].word, "sed");
  s.setLanes(lanes, 2, true, false, 100);
  TEST_ASSERT_EQUAL_STRING("sed", s.newest);
  TEST_ASSERT_EQUAL_INT(1, s.column(2));
  // The first lane's count moves: its word is the newest again.
  lanes[0].count = 5, std::strcpy(lanes[0].word, "Core.swift");
  s.setLanes(lanes, 2, true, false, 200);
  TEST_ASSERT_EQUAL_STRING("Core.swift", s.newest);
  // The same counts: it stays.
  s.setLanes(lanes, 2, true, false, 300);
  TEST_ASSERT_EQUAL_STRING("Core.swift", s.newest);
  // Its word changes at the same count, as the Mac's does after its hold
  // ("thinking"): the newest follows it, not the other lane's.
  std::strcpy(lanes[0].word, "thinking"), std::strcpy(lanes[1].word, "sed -n");
  s.setLanes(lanes, 2, true, false, 350);
  TEST_ASSERT_EQUAL_STRING("thinking", s.newest);
  // Its lane goes: the newest is the word of the lane that's left.
  render::Stream::Lane left[1] = {lanes[1]};
  s.setLanes(left, 1, true, false, 360);
  TEST_ASSERT_EQUAL_STRING("sed -n", s.newest);
  s.setLanes(lanes, 2, true, false, 370);
  TEST_ASSERT_EQUAL_STRING("thinking", s.newest);  // it came back: a new lane
  std::strcpy(lanes[0].word, "Core.swift");
  s.setLanes(lanes, 2, true, false, 380);
  s.startCall("make", 2, render::callStyleFromName("bonk"), 5000);
  TEST_ASSERT_TRUE(s.call.live && s.call.style == render::CallStyle::kBonk);
  TEST_ASSERT_EQUAL_STRING("bonk", render::callStyleName(s.call.style));
  TEST_ASSERT_TRUE(render::callStyleFromName("nonsense") == render::CallStyle::kLand);
  TEST_ASSERT_TRUE(s.moving(5000 + render::Stream::kCallMs - 1));
  s.prune(5000 + render::Stream::kCallMs);
  TEST_ASSERT_FALSE(s.call.live);
  TEST_ASSERT_FALSE(s.moving(5000 + render::Stream::kCallMs));
  for (const char* gone : {"compact", "buried", "freeze"})
    TEST_ASSERT_TRUE(render::callStyleFromName(gone) == render::CallStyle::kLand);

  // The agents done: a word forward may still come for kEndMs.
  s.setLanes(nullptr, 0, false, false, 10100);
  TEST_ASSERT_EQUAL_STRING("", s.newest);
  TEST_ASSERT_TRUE(s.ending && s.accepts(10100 + render::Stream::kEndMs - 1));
  TEST_ASSERT_FALSE(s.accepts(10100 + render::Stream::kEndMs));
  s.startCall("done", 0, render::callStyleFromName("gather"), 10200);
  TEST_ASSERT_TRUE(s.drawn(10200));

  // Something needs you: everything goes at once.
  s.setLanes(lanes, 1, true, false, 20000);
  s.startCall("make", 0, render::CallStyle::kBonk, 24000);
  s.setLanes(nullptr, 0, false, true, 24100);
  TEST_ASSERT_FALSE(s.call.live);
  TEST_ASSERT_FALSE(s.accepts(24100));
}

// Pins that a gesture leaves the brain's finish alone: a stroke, a tickle
// or the board picked up while a finish names whose turn it was (playing
// or lingering) neither cuts it nor stops a tap opening its thread; only
// BOOT's hand-off, which hands it over, takes it down.
static void test_a_gesture_leaves_a_named_finish_alone() {
  Rig r;
  r.at(1000);
  r.state(base("idle"));
  ReactionIn in;
  in.anim = SceneState::kTaskComplete, in.whoAgent = "claude", in.whoThread = "fix-nav", in.key = 9, in.id = 9;
  onReaction(r.b, in, r.t);
  r.at(r.t + 100);
  for (render::Gesture g : {render::Gesture::kStroke, render::Gesture::kTickle, render::Gesture::kPickup}) {
    r.b.gesture(g, r.t);
    TEST_ASSERT_EQUAL(SceneState::kTaskComplete, r.anim());
    TEST_ASSERT_EQUAL_UINT32(9, r.b.finishShown(r.t));
  }
  uint32_t left;
  r.b.reaction(r.t, left);
  r.at(r.t + left + 100);  // lingering
  r.b.gesture(render::Gesture::kPutdown, r.t);
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  TEST_ASSERT_EQUAL_UINT32(9, r.b.finishShown(r.t));
  TEST_ASSERT_EQUAL_STRING("dip", r.b.tap(r.t, r.rng));
  r.b.gesture(render::Gesture::kHandoff, r.t);
  TEST_ASSERT_EQUAL(SceneState::kGesture, r.anim());
  TEST_ASSERT_EQUAL_UINT32(0, r.b.finishShown(r.t));
  // With no finish, a gesture plays.
  r.at(r.t + 10000);
  r.b.gesture(render::Gesture::kStroke, r.t);
  TEST_ASSERT_EQUAL(SceneState::kGesture, r.anim());
}

// The first moment of your day (ReactionIn::greeting), which plays whole:
// its sign waits until its words end, or shows at once with none; the work
// stream waits until it's over, an act where it would have got to; and a
// needs-you cuts it, its sign still to come or up, as cut.
static void test_a_greeting_plays_whole_then_the_work_stream() {
  const auto greet = [](Rig& r, bool words) {
    ReactionIn in;
    in.greeting = true, in.key = 7;
    in.expr = true, in.mood = render::Mood::kHappy;
    std::snprintf(in.sign, sizeof(in.sign), "had a dream");
    if (words) in.said = true, in.take = voice::takeIndex(kGo);
    onReaction(r.b, in, r.t);
  };
  {  // No words: at once.
    Rig r;
    r.at(1000);
    r.state(base("idle"));
    greet(r, false);
    TEST_ASSERT_TRUE(r.b.signUp(r.t));
  }
  if (voicefile::open()) {  // Words: as they end, for as long as a sign is read, the face held.
    Rig r;
    r.at(1000);
    r.state(base("idle"));
    greet(r, true);
    TEST_ASSERT_FALSE(r.b.signUp(r.t));
    TEST_ASSERT_TRUE(r.b.signPending(r.t));
    r.at(1000 + kGoMs - 1);
    TEST_ASSERT_FALSE(r.b.signUp(r.t));
    r.at(1000 + kGoMs);
    TEST_ASSERT_TRUE(r.b.signUp(r.t));
    TEST_ASSERT_EQUAL_STRING("had a dream", r.b.sign(r.t).text);
    render::Mood mood;
    r.at(1000 + kGoMs + Behaviour::kSignMinMs - 1);
    TEST_ASSERT_TRUE(r.b.signUp(r.t));
    TEST_ASSERT_TRUE(r.b.expression(r.t, mood));
    TEST_ASSERT_TRUE(r.b.greetingOn(r.t));
    r.at(1000 + kGoMs + Behaviour::kSignMinMs);
    TEST_ASSERT_FALSE(r.b.signUp(r.t));
    TEST_ASSERT_FALSE(r.b.greetingOn(r.t));
    app::PlayedOut out;
    TEST_ASSERT_TRUE(r.b.takePlayedOut(out));
    TEST_ASSERT_EQUAL_UINT32(7, out.key);
    TEST_ASSERT_EQUAL(app::CutBy::kNone, out.by);
  }
  {  // The stream waits: no words, no word forward, no act; then they come.
    Rig r;
    r.at(1000);
    Model m = base("working");
    m.laneCount = 1;
    m.lanes[0].slot = 0, m.lanes[0].count = 1;
    std::snprintf(m.lanes[0].word, sizeof(m.lanes[0].word), "edit");
    m.workAct.kind = render::ActKind::kBuild;
    std::snprintf(m.workAct.text, sizeof(m.workAct.text), "building");
    r.state(m);
    TEST_ASSERT_TRUE(r.b.stream().on);
    TEST_ASSERT_TRUE(r.b.stream().actNow(r.t).shows());
    const uint32_t began = r.b.stream().act.at;
    TEST_ASSERT_TRUE(r.b.callShows(r.t));
    greet(r, false);
    TEST_ASSERT_FALSE(r.b.stream().on);
    TEST_ASSERT_FALSE(r.b.stream().actNow(r.t).shows());
    TEST_ASSERT_FALSE(r.b.callShows(r.t));
    r.state(m);  // a state changes nothing while it plays
    TEST_ASSERT_FALSE(r.b.stream().on);
    TEST_ASSERT_FALSE(r.b.stream().actNow(r.t).shows());
    r.at(1000 + Behaviour::kSignMinMs + 5000);
    TEST_ASSERT_TRUE(r.b.stream().on);
    TEST_ASSERT_TRUE(r.b.callShows(r.t));
    TEST_ASSERT_TRUE(r.b.stream().actNow(r.t).shows());
    TEST_ASSERT_EQUAL_UINT32(began, r.b.stream().act.at);
  }
  {  // A needs-you cuts it, its sign up.
    Rig r;
    r.at(1000);
    r.state(base("idle"));
    greet(r, false);
    Model m = base("idle");
    m.attn = true, m.attnId = 3;
    r.at(1500);
    r.state(m);
    TEST_ASSERT_FALSE(r.b.signUp(r.t));
    TEST_ASSERT_FALSE(r.b.greetingOn(r.t));
    r.at(1600);
    app::PlayedOut out;
    TEST_ASSERT_TRUE(r.b.takePlayedOut(out));
    TEST_ASSERT_EQUAL(app::CutBy::kNeedsYou, out.by);
  }
}

// A low sign (ReactionIn::low): held in the lane for Behaviour::kLowSignMinMs,
// once its words end, the whole line kept, and not a reply's: it doesn't show
// over needs you.
static void test_a_low_sign_waits_for_its_words_and_holds_a_long_line() {
  TEST_ASSERT_EQUAL_size_t(41, app::kSignTextBytes);
  const char* line = "you stay up very late on fridays, boss!!";
  TEST_ASSERT_EQUAL_size_t(40, std::strlen(line));
  if (!voicefile::open()) return;
  Rig r;
  r.at(1000);
  r.state(base("idle"));
  ReactionIn in;
  in.low = true, in.key = 8;
  in.expr = true, in.mood = render::Mood::kHappy;
  std::snprintf(in.sign, sizeof(in.sign), "%s", line);
  std::snprintf(in.clip, sizeof(in.clip), "remember");
  in.said = true, in.take = voice::takeIndex(kGo);
  onReaction(r.b, in, r.t);
  TEST_ASSERT_FALSE(r.b.signUp(r.t));
  r.at(1000 + kGoMs);
  TEST_ASSERT_TRUE(r.b.sign(r.t).low);
  TEST_ASSERT_EQUAL_STRING(line, r.b.sign(r.t).text);
  TEST_ASSERT_EQUAL_INT32(Behaviour::kLowSignMinMs, r.b.sign(r.t).leftMs);
  r.at(1000 + kGoMs + Behaviour::kLowSignMinMs - 1);
  TEST_ASSERT_TRUE(r.b.signUp(r.t));
  r.at(1000 + kGoMs + Behaviour::kLowSignMinMs);
  TEST_ASSERT_FALSE(r.b.signUp(r.t));
  TEST_ASSERT_NULL(r.b.sign(r.t).text);
  // Over needs you it doesn't show, unlike a reply's.
  Rig n;
  n.at(1000);
  Model m = base("idle");
  m.attn = true;
  n.state(m);
  ReactionIn alone;
  alone.low = true, alone.expr = true, alone.mood = render::Mood::kHappy;
  std::snprintf(alone.sign, sizeof(alone.sign), "%s", line);
  std::snprintf(alone.clip, sizeof(alone.clip), "remember");
  TEST_ASSERT_NOT_NULL(n.b.admit(alone, n.t));
}

// Pins what the board starts with and what no app takes away: silent
// (volume 0) until the Mac's first state, and with no app none of the
// Mac's tags (a night's, a holiday's) reach the face, which would dress
// for them all the next day; the next state brings them back.
// A Boop asleep when the Mac goes quiet stays
// asleep with no plug, until a touch shows the plug; awake, the plug shows
// at the same 30 s as ever; the Mac's next state ends it.
static void test_a_finishs_sign_lifts_as_its_words_end() {
  TEST_ASSERT_EQUAL_UINT32(5000, Behaviour::kFinishLingerMs);
  TEST_ASSERT_EQUAL_UINT32(3000, Behaviour::kFinishSignByMs);
  TEST_ASSERT_EQUAL_size_t(52, app::kThreadBytes);
  const auto finish = [](Rig& r, const char* take) {
    r.state(base("idle"));
    ReactionIn in;
    in.anim = SceneState::kTaskComplete;
    in.whoAgent = "codex", in.whoThread = "fix-nav";
    in.key = 5;
    if (take) in.said = true, in.take = voice::takeIndex(take);
    onReaction(r.b, in, r.t);
  };
  {  // No words: at once.
    Rig r;
    r.at(1000);
    finish(r, nullptr);
    TEST_ASSERT_EQUAL_INT32(0, r.b.done(r.t).signMs);
    r.at(r.t + 500);
    TEST_ASSERT_EQUAL_INT32(500, r.b.done(r.t).signMs);
  }
  if (voicefile::open()) {
    {  // Short words: as they end.
      Rig r;
      r.at(1000);
      r.state(base("idle"));
      ReactionIn in;  // a face for the turn, so its words start at once
      in.whoAgent = "codex", in.whoThread = "fix-nav";
      in.key = 5;
      in.said = true, in.take = voice::takeIndex(kGo);
      onReaction(r.b, in, r.t);
      TEST_ASSERT_EQUAL_INT32(-1, r.b.done(r.t).signMs);
      TEST_ASSERT_TRUE(r.b.done(r.t).shows());
      uint32_t t = r.t;
      while (r.b.laneBubble(t) || r.b.sayAhead(t)) r.at(t += 16);
      TEST_ASSERT_TRUE(r.b.done(t).signMs >= 0 && r.b.done(t).signMs <= 16);
    }
  }
  if (voicefile::open()) {  // The latest: kFinishSignByMs, the words going on.
    Rig r;
    r.at(1000);
    r.state(base("idle"));
    ReactionIn in;
    in.anim = SceneState::kTaskComplete;
    in.whoAgent = "codex", in.whoThread = "fix-nav";
    in.key = 5;
    in.said = true, in.take = voice::takeIndex(kGo), in.then = voice::takeIndex(kGo);
    onReaction(r.b, in, r.t);
    r.at(1000 + Behaviour::kFinishSignByMs - 1);
    TEST_ASSERT_EQUAL_INT32(-1, r.b.done(r.t).signMs);
    r.at(1000 + Behaviour::kFinishSignByMs);
    TEST_ASSERT_TRUE(r.b.laneBubble(r.t) != nullptr || r.b.sayAhead(r.t));  // still talking
    TEST_ASSERT_EQUAL_INT32(0, r.b.done(r.t).signMs);
  }
  {  // A reaction naming none takes it down, with its fall.
    Rig r;
    r.at(1000);
    finish(r, nullptr);
    r.at(r.t + 500);
    r.react(SceneState::kPoked);
    r.at(r.t + 1);
    TEST_ASSERT_TRUE(r.b.done(r.t).leftMs >= 0 && r.b.done(r.t).leftMs <= int32_t(Behaviour::kDoneLeaveMs));
  }
}

// Pins `Behaviour::sleepsOn`: a Boop that goes on sleeping when the Mac goes
// quiet has no plug until touched, and one that falls asleep alone is the same.
static void test_a_sleeping_boop_gets_no_plug_until_touched() {
  auto silent = [](Rig& r) {
    r.at(Behaviour::kNoAppMs + 1);
    TEST_ASSERT_TRUE(r.b.noApp(r.t));
  };
  Rig awake;
  awake.state(base("idle"));
  silent(awake);
  TEST_ASSERT_TRUE(awake.b.look(awake.t) == SceneState::kIdle);
  TEST_ASSERT_TRUE(awake.b.strip(awake.t).noApp);  // awake, the small plug

  Rig r;
  r.state(base("asleep"));
  silent(r);
  r.at(r.t + 1000);
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kAsleep);
  TEST_ASSERT_FALSE(r.b.strip(r.t).noApp);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kAsleep);
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  // Still gone, so a Moment is refused as ever.
  ReactionIn in;
  in.anim = SceneState::kPoked;
  TEST_ASSERT_EQUAL_STRING("no_app", r.b.admit(in, r.t));

  r.b.pressDown(r.t);
  r.b.pressUp();
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kIdle);
  r.at(r.t + 500);
  TEST_ASSERT_TRUE(r.b.strip(r.t).noApp);
  r.at(r.t + 60000);
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kIdle);  // it stays awake a while

  // The Mac back and asleep, then gone again: asleep again, no plug.
  r.state(base("asleep"));
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kAsleep);
  r.at(r.t + Behaviour::kNoAppMs + 1);
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kAsleep);

  // A motion gesture is a touch too.
  r.b.gesture(render::Gesture::kPickup, r.t);
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kIdle);
}

// Alone, it rests, falls asleep on the board's clock with the plug gone, and a
// touch wakes it for the same time again. A touch that sleeps on no Mac's
// model works from a stale needs you or a working look too.
static void test_alone_it_rests_then_sleeps_and_a_touch_wakes_it() {
  Rig r;
  r.state(attn());
  const uint32_t gone = Behaviour::kNoAppMs;
  r.at(gone);
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kIdle);
  TEST_ASSERT_TRUE(r.b.strip(r.t).noApp);
  r.at(gone + Behaviour::kAloneSleepMs - 1);
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kIdle);
  TEST_ASSERT_TRUE(r.b.plugShows(r.t));
  r.at(gone + Behaviour::kAloneSleepMs);
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kAsleep);
  TEST_ASSERT_FALSE(r.b.plugShows(r.t));
  r.at(r.t + Behaviour::kBacklightEaseMs + render::rig::kFadeMs);  // the strip and the light ease out
  TEST_ASSERT_FALSE(r.b.strip(r.t).shows());
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));

  const uint32_t touch = r.t;
  r.b.gesture(render::Gesture::kStroke, touch);
  TEST_ASSERT_TRUE(r.b.look(touch) == SceneState::kIdle);
  TEST_ASSERT_TRUE(r.b.plugShows(touch));
  r.at(touch + Behaviour::kAloneSleepMs - 1);
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kIdle);
  r.at(touch + Behaviour::kAloneSleepMs);
  TEST_ASSERT_TRUE(r.b.look(r.t) == SceneState::kAsleep);
}

// The held rule's change: with no app a touch is no longer held. A poke and a
// stroke play the board's own reaction in the last mood, and voice, a sign and
// the Mac's reactions stay refused.
static void test_alone_a_touch_gets_the_boards_own_reaction() {
  Rig r;
  Model m = base("working");
  m.mood = render::Mood::kGrumpy;
  r.state(m);
  r.at(Behaviour::kNoAppMs);
  TEST_ASSERT_FALSE(r.b.held(r.t));
  TEST_ASSERT_EQUAL_STRING("poked", r.b.tap(r.t, r.rng));
  SceneShow poked = r.b.show(r.t);
  TEST_ASSERT_TRUE(poked.state == SceneState::kPoked);
  TEST_ASSERT_TRUE(poked.mood == render::Mood::kGrumpy);
  r.at(r.t + 20000);
  r.b.gesture(render::Gesture::kStroke, r.t);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kGesture);

  // A stale needs you holds nothing either.
  Rig n;
  n.state(attn());
  n.at(Behaviour::kNoAppMs);
  TEST_ASSERT_EQUAL_STRING("poked", n.b.tap(n.t, n.rng));

  ReactionIn in;
  in.anim = SceneState::kWakeUp;
  TEST_ASSERT_EQUAL_STRING("no_app", r.b.admit(in, r.t));
  r.b.talkOn(r.t, r.rng);  // nobody to hear it
  TEST_ASSERT_EQUAL(SceneState::kGesture, r.anim());
}

// The Mac's return is a small hello, by the board, unless there is something
// else to show: a needs you, a sleeping Boop, or a board face down. The first
// state after power-on is no return.
static void test_the_macs_return_gets_a_small_hello() {
  auto back = [](Model m, Rig& r) {
    r.at(r.t + Behaviour::kNoAppMs);
    r.state(m);
  };
  Rig r;
  r.state(base("idle"));
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  r.at(5000);
  r.state(base("idle"));  // a keepalive is no return
  TEST_ASSERT_EQUAL(SceneState::kNone, r.anim());
  back(base("working"), r);
  TEST_ASSERT_EQUAL(SceneState::kNotice, r.anim());
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());

  Rig boot;
  boot.b.startWithNoApp();
  boot.state(base("idle"));
  TEST_ASSERT_EQUAL(SceneState::kNone, boot.anim());

  Rig needs;
  needs.state(base("idle"));
  back(attn(), needs);
  TEST_ASSERT_EQUAL(SceneState::kNone, needs.anim());

  Rig sleeping;
  sleeping.state(base("idle"));
  back(base("asleep"), sleeping);
  TEST_ASSERT_EQUAL(SceneState::kNone, sleeping.anim());

  Rig down;
  down.state(base("idle"));
  down.b.setFaceDown(true, down.t);
  back(base("idle"), down);
  TEST_ASSERT_EQUAL(SceneState::kNone, down.anim());
}

static void test_no_app_is_silent_and_wears_no_tags() {
  TEST_ASSERT_EQUAL_INT(0, Model{}.vol);
  auto face = std::make_unique<testface::WrappedFace>();
  testface::WrappedFace& f = *face;
  Behaviour b(std::move(face));
  app::Rng rng;
  b.reset(0, rng);
  TEST_ASSERT_EQUAL_INT(0, b.model().vol);
  Model m = base("idle");
  m.when = render::tagBit("night") | render::tagBit("halloween");
  b.onState(m, 100);
  TEST_ASSERT_EQUAL_UINT32(m.when, f.context.when);
  b.advance(100 + Behaviour::kNoAppMs, rng);
  TEST_ASSERT_TRUE(b.noApp(100 + Behaviour::kNoAppMs));
  TEST_ASSERT_EQUAL_UINT32(0, f.context.when);
  b.onState(m, 100 + Behaviour::kNoAppMs + 1000);
  TEST_ASSERT_EQUAL_UINT32(m.when, f.context.when);
}

int main() {
  UNITY_BEGIN();
  if (!voicefile::open()) std::printf("no voice file: the chosen character pack has none\n");
  RUN_TEST(test_listening_hides_an_act_and_it_resumes);
  RUN_TEST(test_the_work_streams_newest_word);
  RUN_TEST(test_a_gesture_leaves_a_named_finish_alone);
  RUN_TEST(test_no_app_is_silent_and_wears_no_tags);
  RUN_TEST(test_a_sleeping_boop_gets_no_plug_until_touched);
  RUN_TEST(test_a_finishs_sign_lifts_as_its_words_end);
  RUN_TEST(test_a_greeting_plays_whole_then_the_work_stream);
  RUN_TEST(test_a_greeting_whose_sign_is_lost_is_not_told);
  RUN_TEST(test_a_low_sign_waits_for_its_words_and_holds_a_long_line);
  RUN_TEST(test_needs_you_alerts_once);
  RUN_TEST(test_a_different_needs_you_with_the_same_names_alerts);
  RUN_TEST(test_tap_during_needs_you_is_only_the_dip_and_stays_amber);
  RUN_TEST(test_answering_on_the_mac_goes_back);
  RUN_TEST(test_needs_you_wins_over_reactions);
  RUN_TEST(test_changes_mid_motion_start_the_new_design);
  RUN_TEST(test_no_app_holds_for_weeks);
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
  RUN_TEST(test_asleep_dims);
  RUN_TEST(test_taps_poke_and_a_run_spams);
  RUN_TEST(test_taps_rotate_their_variations);
  RUN_TEST(test_a_held_face_counts_taps_but_only_dips);
  RUN_TEST(test_an_act_shows_in_workings_place);
  RUN_TEST(test_a_rules_reaction_plays_once);
  RUN_TEST(test_a_face_plays_over_a_rules_reaction);
  RUN_TEST(test_no_rules_reaction_while_the_face_is_held);
  RUN_TEST(test_only_the_reply_ends_listening);
  RUN_TEST(test_what_shows_first);
  RUN_TEST(test_a_finishs_say_waits_for_its_voice_window);
  RUN_TEST(test_each_look_shows_its_design_in_the_mood);
  RUN_TEST(test_the_working_looks_quicken_with_the_agents);
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
  RUN_TEST(test_a_long_touch_during_needs_you_sends_nothing);
  RUN_TEST(test_a_reason_is_the_lanes_caption);
  RUN_TEST(test_the_wish_shows_and_pops);
  RUN_TEST(test_the_wish_goes_with_the_app);
  RUN_TEST(test_a_spoken_reaction_shows_its_words_and_its_caption);
  RUN_TEST(test_a_spoken_reactions_caption_outlasts_its_words);
  RUN_TEST(test_a_gold_shows_beside_the_sign);
  RUN_TEST(test_a_sign_shows_while_its_reaction_plays);
  RUN_TEST(test_alone_it_rests_then_sleeps_and_a_touch_wakes_it);
  RUN_TEST(test_alone_the_macs_tags_go);
  RUN_TEST(test_alone_a_touch_gets_the_boards_own_reaction);
  RUN_TEST(test_the_macs_return_gets_a_small_hello);
  return UNITY_END();
}

