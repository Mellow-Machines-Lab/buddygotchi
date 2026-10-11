// The behaviour state machine, with
// every timing checked to the millisecond.
#include <unity.h>

#include "pack_file.h"  // internal/firmware/

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "app/behaviour.h"
#include "app/device.h"
#include "render/pixel/anim.h"
#include "render/pixel/sounds.h"
#include "linkkit/kit.h"
#include "voice/player.h"

void setUp() {}
void tearDown() {}

using app::Behaviour;
using app::Model;
using app::MomentIn;
using app::Screen;
using render::Anim;
using render::SceneShow;
using render::SceneState;
using render::loopMs;

namespace {

// A take with a known length (a line speaks for its take's
// length, and its bubble stays kBubbleReadMs longer).
constexpr const char* kGo = "previous.go";  // 7042 samples: 638 ms
constexpr uint32_t kGoMs = 638;

// A call from the Mac as LinkKit hands it over (linkkit/SPEC.md §4):
// admitted (the kit's refuse), then played. True when its line plays;
// false when it was refused or has no line.
bool onMoment(Behaviour& b, const MomentIn& in, uint32_t t) { return !b.admit(in, t) && b.play(in, t); }

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
  void moment(Anim a) {
    MomentIn m;
    m.anim = a;
    onMoment(b, m, t);
  }
  // A line on its own: take `id` ("Go", 638 ms, by default); null for a
  // `say` with no take.
  bool say(const char* id = kGo) {
    MomentIn m;
    m.said = true, m.take = voice::takeIndex(id);
    return onMoment(b, m, t);
  }
  // stop_listening.
  void stop() {
    MomentIn m;
    m.empty = true;
    onMoment(b, m, t);
  }
  void talkOn() { b.talkOn(t, rng); }
  void talkOff() { b.talkOff(t); }
  Anim anim() {
    uint32_t left;
    return b.moment(t, left);
  }
  // When needs you's performance last started for a new request.
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

}  // namespace

// A look's variations take turns. Each
// shows at least render::pixel::PixelFace::kTurnMinMs, then each end of its loop moves
// to another (never itself) or plays another loop, and the move blinks
// and starts the new one's clock. The Mac's same state again doesn't
// start them over; its new variation does. Needs you and a finish hold the
// variation showing.
static void test_the_looks_variations_take_turns() {
  Rig r;
  Model m = base("working");
  m.variant = 2;
  r.state(m);
  uint8_t shown = 2;
  uint32_t since = 0;
  int turns = 0, stays = 0;
  bool seen[5] = {};
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
    TEST_ASSERT_TRUE(s.eyesShut);
    TEST_ASSERT_EQUAL_UINT32(0, s.t);
    if (t - since >= render::pixel::PixelFace::kTurnMinMs + loop) ++stays;  // it played another loop first
    shown = s.variant, since = t, ++turns;
    seen[shown] = true;
  }
  for (bool v : seen) TEST_ASSERT_TRUE(v);
  TEST_ASSERT_TRUE(turns >= 40 && turns <= 110);  // about one every 8 s
  TEST_ASSERT_TRUE(stays > 0);

  // The Mac's own new variation shows at once.
  m.variant = uint8_t((shown + 1) % 5);
  r.state(m);
  TEST_ASSERT_EQUAL(m.variant, r.b.show(r.t).variant);

  // Needs you holds its variation, and so does a finish.
  Model a = attn();
  a.variant = 1;
  r.state(a);
  for (uint32_t t = r.t; t <= r.t + 60000; t += 1000) {
    r.at(t);
    if (t % 10000 == 0) r.state(a);
    TEST_ASSERT_EQUAL(1, r.b.show(t).variant);
  }
  r.state(m);
  r.at(r.t + 20000);
  shown = r.b.lookVariant();
  MomentIn c;
  c.anim = Anim::kTaskComplete, c.loops = Behaviour::kMaxLoops;
  onMoment(r.b, c, r.t);
  uint32_t left;
  r.b.moment(r.t, left);
  for (uint32_t t = r.t, end = r.t + left; t < end; t += 100) {
    r.at(t);
    TEST_ASSERT_EQUAL(shown, r.b.lookVariant());
  }
}

// The performance, with its knocks and ding, once when
// a request starts, amber at half until it's answered, and nothing grows
// or nudges while it waits.
static void test_needs_you_alerts_once_and_stays_amber() {
  Rig r;
  r.at(1000);
  r.state(attn());
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
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
    r.state(attn());  // the same request: the performance doesn't play again
    TEST_ASSERT_EQUAL_STRING("alert@1000", r.alert().c_str());
    TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(t));
    TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(t + 5000));
    SceneShow now = r.b.show(t);
    now.eyesShut = false;  // blinks go on
    TEST_ASSERT_TRUE(render::sceneFrame(first) == render::sceneFrame(now));  // nothing else moves
  }
  // A different request plays the performance again, from its start.
  r.state(attn("other"));
  TEST_ASSERT_EQUAL_STRING("alert@300000", r.alert().c_str());
  TEST_ASSERT_EQUAL_UINT32(0, r.b.designMs(r.t));
  r.at(300000 + 400);
  TEST_ASSERT_EQUAL_UINT32(400, r.b.show(r.t).t);
}

// A different request shown alerts once more, even with
// the same agent and project (two worktrees of one repo): the Mac numbers
// each request in `attn.id`. More waiting behind it, a
// resent state, or a Mac too old to send a number, doesn't.
static void test_a_different_request_with_the_same_names_alerts() {
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
  r.state(b);  // the first answered: the other request is shown
  TEST_ASSERT_EQUAL_STRING("alert@3000", r.alert().c_str());
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  r.at(4000);
  r.state(attn());  // no number: agent and project alone, as before
  r.at(5000);
  r.state(attn());
  TEST_ASSERT_EQUAL_STRING("alert@4000", r.alert().c_str());
}

// A tap while something needs you is the press dip
// only, with no moment, and it stays amber.
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
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_EQUAL(0u, r.b.momentSeq());
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  keepAlive(r, attn(), 125000);
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(r.t));
  TEST_ASSERT_EQUAL_STRING("alert@0", r.alert().c_str());
}

// Answered on the Mac, the face blinks back to the
// base look with no moment.
static void test_answering_on_the_mac_blinks_back() {
  Rig r;
  r.state(attn());
  r.at(5000);
  r.state(base("working"));
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kWorking);
  TEST_ASSERT_TRUE(r.b.show(r.t).eyesShut);  // a blink hides the switch
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kWorking);
  TEST_ASSERT_EQUAL(0u, r.b.momentSeq());
}

// While something needs you, no animation plays and no
// line shows.
static void test_attention_wins_over_moments() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("working"));
  r.moment(Anim::kTaskComplete);
  TEST_ASSERT_EQUAL(Anim::kTaskComplete, r.anim());
  r.at(100);
  r.state(attn());  // attention cuts the finish
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  r.moment(Anim::kTaskComplete);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  r.moment(Anim::kPoked);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_FALSE(r.say());  // a line on its own is ignored
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  MomentIn say;
  say.anim = Anim::kTaskComplete, say.said = true, say.take = voice::takeIndex(kGo);
  TEST_ASSERT_FALSE(onMoment(r.b, say, r.t));
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  // A line that was showing goes when something starts needing you.
  Rig m;
  m.state(base("idle"));
  TEST_ASSERT_TRUE(m.say());
  m.at(100);
  m.state(attn());
  TEST_ASSERT_NULL(m.b.bubble(m.t));
}

// Nothing cuts hard. Attention arriving under a finish (which it
// ends) or a poke shows the needs-you design behind a blink of
// kBlendMs, and the design's clock starts at the change.
static void test_changes_mid_motion_blink_into_the_new_design() {
  const Anim anims[] = {Anim::kTaskComplete, Anim::kPoked};
  const char* const bases[] = {"working", "idle"};
  for (int i = 0; i < 2; ++i) {
    for (uint32_t when : {300u, 650u}) {
      Rig r;
      r.state(base(bases[i]));
      r.moment(anims[i]);
      r.at(when);
      r.state(attn());
      SceneShow s = r.b.show(r.t);
      TEST_ASSERT_TRUE(s.state == SceneState::kNeedsYou);
      TEST_ASSERT_TRUE(s.eyesShut);
      TEST_ASSERT_EQUAL_UINT32(0, s.t);
      TEST_ASSERT_TRUE(r.b.show(r.t + render::pixel::PixelFace::kBlendMs - 1).eyesShut);
      r.at(r.t + render::pixel::PixelFace::kBlendMs);
      TEST_ASSERT_TRUE(!r.b.show(r.t).eyesShut || r.b.blinking(r.t));
    }
  }
}

// The design a show draws. Asleep and no app share one design
// across moods, so a mood change there switches nothing.
static int designOf(const SceneShow& s) { return render::sceneOf(s.mood, s.state, s.variant); }

// A change of design is hidden when the eyes are shut and show shut: the
// first pack's closed eyes, or a new mood's flip-book on its blink step
// (render::eyesClosed).
static bool hidden(const SceneShow& s) { return s.eyesShut && render::eyesClosed(s); }

// A brain's reaction: a line with a mood, held for
// `loops` loops of the design it's drawn in.
static MomentIn reaction(render::Mood mood, int loops = 2) {
  MomentIn m;
  m.take = voice::takeIndex(kGo);
  m.expr = true, m.mood = mood, m.loops = loops;
  return m;
}

// An animation from the Mac, of `loops`, in the mood `mood` if it's given
// one (else Boop's), with a line when `take` names one.
static MomentIn animated(Anim a, int variant = 0, const char* take = nullptr, bool expr = false,
                         render::Mood mood = render::Mood::kHappy, int loops = 1) {
  MomentIn m;
  m.anim = a, m.variant = uint8_t(variant), m.loops = loops;
  m.said = take != nullptr, m.take = voice::takeIndex(take);
  m.expr = expr, m.mood = mood;
  return m;
}

// Every way round: whatever state Boop is in, whatever is playing, and
// whatever arrives (any message or input), the design just after the
// change is the design just before it, at the same moment of its clock, or
// else the eyes are shut, and show shut, to hide the switch. The states
// span the first pack's moods and the new moods' flip-books and what the
// agents are doing; what plays includes a reaction's borrowed face, a
// finish in a mood, a one-shot and a poke; what arrives the same, a finish
// with its line, a reply and a mood change.
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
    kOneShot, kCalmReaction, kFinishLine, kPlayingCount
  };
  const int kEvents = kStates + 14;  // every state, then the moments and inputs
  int checked = 0;
  for (int from = 0; from < kStates; ++from) {
    for (int playing = 0; playing < kPlayingCount; ++playing) {
      for (int event = 0; event < kEvents; ++event) {
        for (uint32_t when : {40u, 333u, 1210u}) {
          Rig r;
          r.state(states[from]);
          r.at(500);
          switch (playing) {
            case kCheer: r.moment(Anim::kTaskComplete); break;
            case kWiggle: r.b.tap(r.t, r.rng); break;
            case kSay: r.say(); break;
            case kCheerSay: onMoment(r.b, animated(Anim::kTaskComplete, 0, kGo), r.t); break;
            case kNoApp: r.at(500 + Behaviour::kNoAppMs); break;
            case kReaction: onMoment(r.b, reaction(Mood::kSad), r.t); break;
            case kMoodyCheer: onMoment(r.b, animated(Anim::kTaskComplete, 1, nullptr, true, Mood::kExcited, 2), r.t); break;
            case kListening: r.talkOn(); break;
            case kReplyWait:
              r.talkOn();
              r.at(900);
              r.talkOff();
              break;
            case kOneShot: r.moment(Anim::kStarting); break;
            case kCalmReaction: onMoment(r.b, reaction(Mood::kCalm), r.t); break;
            case kFinishLine: onMoment(r.b, animated(Anim::kTaskComplete, 3, "new.d14", true, Mood::kWhiny), r.t); break;
            default: break;
          }
          r.at(r.t + when);
          SceneShow before = r.b.show(r.t);
          if (event < kStates) {
            r.state(states[event]);
          } else {
            switch (event - kStates) {
              case 0: r.moment(Anim::kTaskComplete); break;
              case 1: r.b.tap(r.t, r.rng); break;
              case 2: r.say(); break;
              case 3: r.moment(Anim::kPoked); break;
              case 4: onMoment(r.b, reaction(Mood::kProud, 3), r.t); break;
              case 5: r.talkOn(); break;
              case 6: r.talkOff(); break;
              case 7: r.stop(); break;
              case 8: r.moment(Anim::kListening); break;
              case 9: onMoment(r.b, animated(Anim::kTaskComplete, 2, nullptr, true, Mood::kCurious, 3), r.t); break;
              case 10: r.moment(Anim::kError); break;
              case 11: onMoment(r.b, animated(Anim::kReplyReady, 1, kGo, true, Mood::kAnnoyed), r.t); break;
              case 12: onMoment(r.b, reaction(Mood::kWounded), r.t); break;
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
          if (!same && !hidden(after)) {
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

// Over time: as whatever plays runs out on its own (a finish's loops, a
// reaction's borrowed face at its loop boundary, over a look, over the
// finish or across a look change, a poke, a one-shot, a line, a finish
// held on for its line, the Mac going quiet), the face never cuts hard.
// From one 20 ms frame to the next the design goes on at the same moment of
// its clock, or the eyes are shut and show shut. An animation's design
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
    kWiggle, kSay, kQuiet, kOneShot, kFinishLine, kNewMoodReaction, kPlayingCount
  };
  int frames = 0;
  for (const Model& m : states) {
    for (int playing = 0; playing < kPlayingCount; ++playing) {
      Rig r;
      r.state(m);
      r.at(777);
      MomentIn cheer;
      cheer.anim = Anim::kTaskComplete;
      switch (playing) {
        case kCheer1: onMoment(r.b, cheer, r.t); break;
        case kCheer3: cheer.loops = 3, onMoment(r.b, cheer, r.t); break;
        case kMoodyCheer:
          cheer.loops = 2, cheer.expr = true, cheer.mood = Mood::kSad;
          onMoment(r.b, cheer, r.t);
          break;
        case kReaction: onMoment(r.b, reaction(Mood::kExcited, 2), r.t); break;
        case kSameMood: onMoment(r.b, reaction(m.mood, 2), r.t); break;
        case kLongReaction: onMoment(r.b, reaction(Mood::kCurious, 6), r.t); break;
        case kOverCheer:
          cheer.loops = 2, onMoment(r.b, cheer, r.t);
          r.at(r.t + 700);
          onMoment(r.b, reaction(Mood::kDetermined, 1), r.t);
          break;
        case kAcrossLook:
          onMoment(r.b, reaction(Mood::kSad, 3), r.t);
          break;
        case kCheerEnds:  // a reaction late in the finish holds past its end
          onMoment(r.b, cheer, r.t);
          r.at(r.t + 1900);
          onMoment(r.b, reaction(Mood::kHappy, 2), r.t);
          break;
        case kWiggle: r.b.tap(r.t, r.rng); break;
        case kSay: r.say(); break;
        case kOneShot: r.moment(Anim::kHelperReturn); break;
        case kFinishLine: onMoment(r.b, animated(Anim::kTaskComplete, 4, "new.d20", true, Mood::kGrumpy), r.t); break;
        case kNewMoodReaction: onMoment(r.b, reaction(Mood::kIrritated, 2), r.t); break;
        default: break;
      }
      SceneShow before = r.b.show(r.t);
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
        if (!(same && (after.t == next || rests)) && !hidden(after)) {
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
// no-app design, no old line, press dip or backlight fade.
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
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
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
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
  TEST_ASSERT_TRUE(render::sceneFrame(noApp) == render::sceneFrame(r.b.show(r.t)));
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  walk(0x100000000ull + 1150);  // 2^32 ms after the release, 150 after the line started
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  // No line's bubble or mouth, no press, no blink: only the design.
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kNoApp);
  TEST_ASSERT_FALSE(s.mouthOpen);
  TEST_ASSERT_FALSE(s.eyesShut);
  TEST_ASSERT_EQUAL_INT(0, s.dy);
  walk(0x100000000ull + Behaviour::kNoAppMs + 50);  // 2^32 ms after the dimming began
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
  r.state(base("idle"));
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
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
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kListening);
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kListening);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kGrumpy);
  TEST_ASSERT_EQUAL_UINT32(0, s.t);  // its design from the start
  r.at(2000);
  const SceneShow held = r.b.show(r.t);
  TEST_ASSERT_EQUAL_UINT32(2000 % loopMs(render::Mood::kGrumpy, SceneState::kListening, held.variant), held.t);
  const uint32_t seq = r.b.momentSeq();
  r.talkOff();
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  TEST_ASSERT_EQUAL(seq, r.b.momentSeq());  // the same moment
  const SceneShow after = r.b.show(r.t);
  TEST_ASSERT_TRUE(after.state == held.state && after.variant == held.variant && after.t == held.t);
  TEST_ASSERT_FALSE(after.eyesShut);  // no blend
}

// Listening holds until the reply. Another animation (a
// finish, a poke) doesn't replace it, and a tap shows only the press dip.
// Any moment with a `say` is the reply: it ends listening, then plays as
// it would have, its finish and its face included.
static void test_listening_holds_until_the_reply() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));
  r.talkOn();
  r.at(500);
  r.b.tap(r.t, r.rng);  // a touch while BOOT is held
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  r.at(1000);
  r.talkOff();
  r.at(2000);
  const uint32_t seq = r.b.momentSeq();
  r.moment(Anim::kTaskComplete);
  r.moment(Anim::kPoked);
  r.b.tap(r.t, r.rng);
  uint32_t left;
  TEST_ASSERT_EQUAL(Anim::kListening, r.b.moment(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(Behaviour::kReplyWaitMs - 1000, left);  // the wait runs on
  TEST_ASSERT_EQUAL(seq, r.b.momentSeq());
  MomentIn skipped;  // a call the Mac waits on, refused: the kit skips it
  skipped.anim = Anim::kTaskComplete, skipped.call = 7;
  TEST_ASSERT_EQUAL_STRING("listening", r.b.admit(skipped, r.t));
  app::Ended e;
  TEST_ASSERT_FALSE(r.b.takeEnded(e));
  // The brain's reply: a finish with a line in proud's face, its line at
  // the design's voice window.
  MomentIn reply;
  reply.anim = Anim::kTaskComplete, reply.said = true, reply.take = voice::takeIndex(kGo);
  reply.expr = true, reply.mood = render::Mood::kProud, reply.call = 8;
  TEST_ASSERT_TRUE(onMoment(r.b, reply, r.t));
  TEST_ASSERT_EQUAL(Anim::kTaskComplete, r.anim());
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_TRUE(r.b.lineAhead(r.t));
  render::Mood mood;
  TEST_ASSERT_TRUE(r.b.expression(r.t, mood) && mood == render::Mood::kProud);
  TEST_ASSERT_FALSE(r.b.takeEnded(e));  // it plays
  r.at(r.t + render::pixel::score(render::pixelIndex(render::Mood::kProud), int(SceneState::kTaskComplete), 0).voiceMs);
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  // A line on its own ends it too, and plays over the look.
  Rig s;
  s.state(base("idle"));
  s.talkOn();
  s.at(700);
  TEST_ASSERT_TRUE(s.say());
  TEST_ASSERT_EQUAL(Anim::kNone, s.anim());
  TEST_ASSERT_NOT_NULL(s.b.bubble(s.t));
  TEST_ASSERT_TRUE(s.b.show(s.t).state == SceneState::kIdle);
}

// While something needs you, listening is the one moment
// that plays; one showing when needs you starts plays on. The reply can't
// show, but it ends listening.
static void test_listening_plays_while_something_needs_you() {
  Rig a;
  a.state(attn());
  a.talkOn();
  TEST_ASSERT_EQUAL(Anim::kListening, a.anim());
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, a.b.screen(a.t));
  TEST_ASSERT_TRUE(a.b.show(a.t).state == SceneState::kListening);
  a.at(500);
  a.moment(Anim::kTaskComplete);
  TEST_ASSERT_EQUAL(Anim::kListening, a.anim());
  TEST_ASSERT_FALSE(a.say());
  TEST_ASSERT_EQUAL(Anim::kNone, a.anim());
  TEST_ASSERT_NULL(a.b.bubble(a.t));
  TEST_ASSERT_TRUE(a.b.show(a.t).state == SceneState::kNeedsYou);
  // The Mac's own listening plays too, and survives a new request.
  Rig m;
  m.state(base("idle"));
  m.moment(Anim::kListening);
  m.at(300);
  m.state(attn());
  TEST_ASSERT_EQUAL(Anim::kListening, m.anim());
  m.at(400);
  m.state(attn("jetpack"));
  TEST_ASSERT_EQUAL(Anim::kListening, m.anim());
  m.stop();
  TEST_ASSERT_EQUAL(Anim::kNone, m.anim());
}

// stop_listening (empty) ends listening and does nothing
// else. It never ends a finish, a poke or a line.
static void test_the_empty_moment_ends_only_listening() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));
  r.moment(Anim::kListening);  // from the Mac: its own mic is on
  r.at(4000);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  r.stop();
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_TRUE(r.b.show(r.t).eyesShut);  // blending back
  // After the release, too.
  r.at(r.t + 1000);
  r.talkOn();
  r.at(r.t + 1000);
  r.talkOff();
  r.at(r.t + 2000);
  r.stop();
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  // Nothing playing: nothing happens.
  const uint32_t seq = r.b.momentSeq();
  r.at(r.t + 1000);
  r.stop();
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_EQUAL(seq, r.b.momentSeq());
  // A finish, a poke and a line carry on.
  r.moment(Anim::kTaskComplete);
  r.at(r.t + 100);
  r.stop();
  TEST_ASSERT_EQUAL(Anim::kTaskComplete, r.anim());
  r.moment(Anim::kPoked);
  r.stop();
  TEST_ASSERT_EQUAL(Anim::kPoked, r.anim());
  r.at(r.t + 1000);
  TEST_ASSERT_TRUE(r.say());
  r.stop();
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_EQUAL(seq + 3, r.b.momentSeq());  // finish, poke, line; the stops add none
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
  TEST_ASSERT_EQUAL(Anim::kListening, r.b.moment(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(8000, left);
  keepAlive(r, m, 3000 + 7999);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  r.at(3000 + 8000);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());  // no reply came
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kIdle);
  TEST_ASSERT_TRUE(r.b.show(r.t).eyesShut);
  // BOOT's own 30 s cap is a release: 8 s more for the reply.
  Rig c;
  c.state(m);
  c.talkOn();
  keepAlive(c, m, 30000);
  c.talkOff();
  keepAlive(c, m, 30000 + 7999);
  TEST_ASSERT_EQUAL(Anim::kListening, c.anim());
  c.at(38000);
  TEST_ASSERT_EQUAL(Anim::kNone, c.anim());
  c.talkOff();  // a late release has nothing to wait on
  TEST_ASSERT_EQUAL(Anim::kNone, c.anim());
  // The Mac's listening, with no release on the device, holds 38 s at most.
  Rig k;
  k.state(m);
  k.moment(Anim::kListening);
  TEST_ASSERT_EQUAL(Anim::kListening, k.b.moment(k.t, left));
  TEST_ASSERT_EQUAL_UINT32(38000, left);
  // Held on the device while the Mac listens: the same face, time topped up.
  k.at(5000);
  const uint32_t seq = k.b.momentSeq();
  k.talkOn();
  TEST_ASSERT_EQUAL(seq, k.b.momentSeq());
  TEST_ASSERT_EQUAL(Anim::kListening, k.b.moment(k.t, left));
  TEST_ASSERT_EQUAL_UINT32(38000, left);
  k.talkOff();
  TEST_ASSERT_EQUAL(Anim::kListening, k.b.moment(k.t, left));
  TEST_ASSERT_EQUAL_UINT32(8000, left);
}

// Which variation of listening shows is picked at random,
// never the last one; a `variant` the Mac sends is shown as it says.
static void test_listening_takes_turns_between_variations() {
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
  MomentIn m;
  m.anim = Anim::kListening, m.variant = 2;
  onMoment(r.b, m, r.t);
  TEST_ASSERT_EQUAL_INT(2, r.b.show(r.t).variant);
  TEST_ASSERT_NOT_EQUAL(2, r.b.pick(Anim::kListening, render::Mood::kHappy, 0, render::Outcome::kNone, render::StartCtx::kNone, r.rng));
}

// The finish plays its loops of the mood's task-complete
// design, one unless the moment says more, with no light; a new moment
// replaces the one playing.
static void test_moments_end_and_replace() {
  Rig r;
  r.state(base("idle"));
  r.moment(Anim::kTaskComplete);
  const uint32_t loop = loopMs(render::Mood::kHappy, SceneState::kTaskComplete);
  r.at(loop - 1);
  TEST_ASSERT_EQUAL(Anim::kTaskComplete, r.anim());
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));
  TEST_ASSERT_EQUAL_STRING("", r.alert().c_str());
  r.at(loop);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  r.moment(Anim::kTaskComplete);
  r.at(r.t + 10);
  r.moment(Anim::kPoked);  // a new moment replaces the old one
  TEST_ASSERT_EQUAL(Anim::kPoked, r.anim());
  const uint32_t start = r.t, poke = loopMs(render::Mood::kHappy, SceneState::kPoked);
  r.at(start + poke - 1);
  TEST_ASSERT_EQUAL(Anim::kPoked, r.anim());
  r.at(start + poke);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
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
  MomentIn in;
  in.anim = Anim::kTaskComplete, in.loops = 3;
  onMoment(r.b, in, r.t);
  const uint32_t loop = loopMs(render::Mood::kProud, SceneState::kTaskComplete);
  uint32_t left;
  TEST_ASSERT_EQUAL(Anim::kTaskComplete, r.b.moment(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(3 * loop, left);
  TEST_ASSERT_EQUAL_UINT32(loop - 1, r.b.show(1000 + loop - 1).t);
  SceneShow s = r.b.show(1000 + loop + 100);
  TEST_ASSERT_TRUE(s.state == SceneState::kTaskComplete);
  TEST_ASSERT_EQUAL_UINT32(100, s.t);  // the design starts over
  r.at(1000 + 3 * loop - 1);
  TEST_ASSERT_EQUAL(Anim::kTaskComplete, r.anim());
  r.at(1000 + 3 * loop);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  // Drawn in a reaction's mood, the finish's loops are that mood's design's.
  r.at(20000);
  r.state(m);
  in.loops = 1, in.expr = true, in.mood = render::Mood::kSad;
  onMoment(r.b, in, r.t);
  r.b.moment(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(loopMs(render::Mood::kSad, SceneState::kTaskComplete), left);
  MomentIn w;  // the dashboard's poke too
  w.anim = Anim::kPoked, w.loops = 4;
  onMoment(r.b, w, r.t);
  r.b.moment(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(4 * loopMs(render::Mood::kProud, SceneState::kPoked), left);
}

// The bubble shows the take's text, the line speaks for the
// take's length, and the mouth is an "o" while the take is loud (its mouth
// frames, voice::mouthOpen), shut once it's said.
static void test_a_take_moves_the_mouth() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));
  MomentIn m;
  m.said = true, m.take = voice::takeIndex(kGo);
  TEST_ASSERT_TRUE(onMoment(r.b, m, r.t));
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

// A line of two takes shows both words, speaks for both
// and the gap between them, and moves the mouth for each.
static void test_a_line_of_two_takes() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));
  MomentIn m;
  m.said = true, m.take = voice::takeIndex("previous.tsk");
  m.then = voice::takeIndex("phase1.word.test.test__annoyed__contained");
  TEST_ASSERT_TRUE(onMoment(r.b, m, r.t));
  TEST_ASSERT_EQUAL_STRING("Tsk... Test", r.b.bubble(r.t));
  const uint32_t ms = 1377 + voice::kJoinGapMs + 868;
  TEST_ASSERT_TRUE(r.b.speaking(ms - 1));
  TEST_ASSERT_FALSE(r.b.speaking(ms));
  for (uint32_t t = 0; t < ms; t += 7) TEST_ASSERT_EQUAL(voice::lineMouthOpen(m.take, m.then, t), r.b.show(t).mouthOpen);
  TEST_ASSERT_NOT_NULL(r.b.bubble(ms + Behaviour::kBubbleReadMs - 1));
  TEST_ASSERT_NULL(r.b.bubble(ms + Behaviour::kBubbleReadMs));
}

// The first millisecond the mouth is open into take `id`.
static uint32_t firstOpen(const char* id) {
  uint32_t t = 0;
  while (!voice::mouthOpen(voice::takeIndex(id), t)) ++t;
  return t;
}

// A line on its own plays over whatever
// face is showing and doesn't change it. The bubble stays for the take
// and 1.2 s to read.
static void test_a_line_alone_plays_over_the_face() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("working"));
  r.at(1000);
  TEST_ASSERT_TRUE(r.say());
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
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
  r.moment(Anim::kTaskComplete);
  r.at(10500);
  r.say();
  uint32_t left;
  TEST_ASSERT_EQUAL(Anim::kTaskComplete, r.b.moment(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(loopMs(render::Mood::kHappy, SceneState::kTaskComplete) - 500, left);
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  // A tap's poke replaces the moment's animation; the line plays on.
  r.at(10600);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(Anim::kPoked, r.anim());
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));

  // A `say` with no take is nothing.
  Rig e;
  e.state(base("idle"));
  TEST_ASSERT_FALSE(e.say(nullptr));
  TEST_ASSERT_EQUAL(0u, e.b.momentSeq());
}

// A face on its own (a mood, no animation, no line) plays
// that face for its loops, exactly as a face with a line would, and a
// moment the Mac waits on ends done when it's over. A line playing plays
// on under it. While something needs you, or with no app, it's skipped.
static std::string ended(Rig& r);
static void test_a_face_alone_plays_its_loops() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));
  r.at(1000);
  MomentIn f;
  f.expr = true, f.mood = render::Mood::kProud, f.loops = 2, f.call = 30;
  const uint32_t loop = loopMs(render::Mood::kProud, SceneState::kIdle, r.b.lookVariant());
  const uint32_t end = r.t + loop - r.b.designMs(r.t) % loop + loop;
  TEST_ASSERT_FALSE(onMoment(r.b, f, r.t));  // no line
  render::Mood e;
  TEST_ASSERT_TRUE(r.b.expression(r.t, e) && e == render::Mood::kProud);
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kProud);
  TEST_ASSERT_TRUE(r.b.show(r.t).eyesShut);  // it blinks into the face
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  r.at(end - 1);
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(end);
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  TEST_ASSERT_EQUAL_STRING("30 done", ended(r).c_str());
  // Under a line playing, the line plays on.
  r.at(20000);
  r.say();
  const uint32_t seq = r.b.momentSeq();
  f.call = 31;
  onMoment(r.b, f, r.t);
  TEST_ASSERT_EQUAL(seq, r.b.momentSeq());
  TEST_ASSERT_EQUAL_STRING("Go", r.b.bubble(r.t));
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  // Skipped while something needs you, and with no app.
  r.at(30000);
  r.state(attn());
  ended(r);
  f.call = 32;
  TEST_ASSERT_EQUAL_STRING("needs_you", r.b.admit(f, r.t));  // the kit skips it
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  Rig n;
  n.at(Behaviour::kNoAppMs);
  f.call = 33;
  TEST_ASSERT_EQUAL_STRING("no_app", n.b.admit(f, n.t));
  TEST_ASSERT_FALSE(n.b.expression(n.t, e));
  TEST_ASSERT_EQUAL_STRING("", ended(n).c_str());
}

// Starts of blinks between 0 and `to` ms, with the Mac sending `m` every
// 10 s (or never, for no app).
std::vector<uint32_t> blinkStarts(const Model& m, bool mac, uint32_t to) {
  Rig r;
  r.state(m);
  std::vector<uint32_t> starts;
  bool prev = false;
  for (uint32_t t = 1; t <= to; ++t) {
    if (mac && t % 10000 == 0) r.at(t), r.state(m);
    r.at(t);
    bool blink = r.b.blinking(t);
    if (blink) TEST_ASSERT_TRUE(r.b.show(t).eyesShut);
    if (blink && !prev) starts.push_back(t);
    prev = blink;
  }
  return starts;
}

void checkGaps(const std::vector<uint32_t>& starts, uint32_t from, uint32_t lo, uint32_t hi) {
  int n = 0;
  for (size_t i = 1; i < starts.size(); ++i) {
    if (starts[i - 1] < from) continue;
    uint32_t gap = starts[i] - starts[i - 1];
    TEST_ASSERT_TRUE(gap >= lo + render::pixel::PixelFace::kBlinkMs);  // the gap follows the blink
    TEST_ASSERT_TRUE(gap <= hi + render::pixel::PixelFace::kBlinkMs);
    ++n;
  }
  TEST_ASSERT_TRUE(n >= 5);
}

// Idle and working life is blinks only, every 2–6 s idle,
// 2–5 s working, however many agents are busy. Asleep, as with no app,
// never blinks.
// A moment's `mood` is its expression. With no animation,
// the look is drawn in that mood for the moment's loops of the design it's
// drawn in, ending on a loop boundary of that design's clock (so the first
// loop ends at the next boundary), and at least as long as the line and
// its bubble; then it goes back to the state's mood behind a blink. A look
// change meanwhile keeps the expression and its end; a new moment, a tap
// or "needs you" ends it.
static MomentIn expressive(render::Mood mood, const char* take = kGo, int loops = 1) {
  MomentIn m;
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
  TEST_ASSERT_TRUE(onMoment(r.b, expressive(render::Mood::kProud), r.t));
  render::Mood e;
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  TEST_ASSERT_TRUE(e == render::Mood::kProud);
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kWorking);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kProud);
  TEST_ASSERT_TRUE(s.eyesShut);  // it blinks into the expression
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
  TEST_ASSERT_TRUE(s.eyesShut);  // behind a blink

  // Three loops, from partway into one: to the third boundary of the
  // look's clock, which a turn of its variations may have started over.
  r.at(2 * loop + 300);
  r.state(m);
  onMoment(r.b, expressive(render::Mood::kProud, kGo, 3), r.t);
  const uint32_t turned = loopMs(render::Mood::kProud, SceneState::kWorking, r.b.lookVariant());
  const uint32_t third = r.t + turned - r.b.designMs(r.t) % turned + 2 * turned;
  r.at(third - 1);
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  r.at(third);
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));

  // A line longer than its loop: the face holds as long as it plays.
  r.at(6 * loop);
  r.state(m);
  MomentIn in = expressive(render::Mood::kExcited, "new.d20");  // "Mwahaha...", 2434 ms
  onMoment(r.b, in, r.t);
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
  r.moment(Anim::kTaskComplete);  // a finish with no face, in curious
  const uint32_t cheer = loopMs(render::Mood::kCurious, SceneState::kTaskComplete);
  const uint32_t proud = loopMs(render::Mood::kProud, SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kCurious);
  r.at(1200);
  m.base = SceneState::kIdle;  // the turn is over
  r.state(m);
  onMoment(r.b, expressive(render::Mood::kProud), r.t);  // Jev: proud
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kProud);
  TEST_ASSERT_EQUAL_UINT32(200, s.t);  // the finish keeps its clock
  uint32_t left;
  TEST_ASSERT_EQUAL(Anim::kTaskComplete, r.b.moment(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(cheer - 200, left);  // a line doesn't cut the finish
  // The face holds one loop of the finish's design in proud, on the
  // finish's clock: to 1000 + proud's loop, after the line (1200 + 638 +
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
  onMoment(l.b, expressive(render::Mood::kProud), l.t);
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

  // With an animation in the same moment, it lasts the longer of the two:
  // here the finish, a loop of excited's design.
  Rig a;
  a.state(base("idle"));
  a.at(1000);
  MomentIn in = expressive(render::Mood::kExcited);
  in.anim = Anim::kTaskComplete;
  onMoment(a.b, in, a.t);
  const uint32_t excited = loopMs(render::Mood::kExcited, SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(kGoMs + Behaviour::kBubbleReadMs < excited);
  a.at(1000 + excited - 1);
  TEST_ASSERT_TRUE(a.b.show(a.t).mood == render::Mood::kExcited);
  a.at(1000 + excited);
  TEST_ASSERT_TRUE(a.b.show(a.t).mood == render::Mood::kHappy);
  // An animation alone with a mood: as long as it plays.
  a.at(10000);
  MomentIn poke;
  poke.anim = Anim::kPoked, poke.expr = true, poke.mood = render::Mood::kSad;
  onMoment(a.b, poke, a.t);
  const uint32_t sadPoke = loopMs(render::Mood::kSad, SceneState::kPoked);
  a.at(10000 + sadPoke - 1);
  TEST_ASSERT_TRUE(a.b.show(a.t).mood == render::Mood::kSad);
  a.at(10000 + sadPoke);
  TEST_ASSERT_TRUE(a.b.show(a.t).mood == render::Mood::kHappy);
}

static void test_an_expression_ends_with_its_moment() {
  NEEDS_VOICE_PACK();
  render::Mood e;
  // A new line without a mood replaces the line, and the expression.
  Rig r;
  r.state(base("working"));
  r.at(1000);
  onMoment(r.b, expressive(render::Mood::kGrumpy), r.t);
  r.at(1500);
  r.say();
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kHappy);
  // A tap's poke doesn't: the poke is drawn in the reaction's mood.
  r.at(5000);
  onMoment(r.b, expressive(render::Mood::kSad), r.t);
  r.at(5100);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_TRUE(r.b.expression(r.t, e) && e == render::Mood::kSad);
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kSad);
  // "Needs you" stops the line, and the expression with it.
  r.at(9000);
  onMoment(r.b, expressive(render::Mood::kExcited), r.t);
  r.at(9100);
  r.state(attn());
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kNeedsYou);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kHappy);
  // While something needs you, a moment with a mood plays nothing and
  // borrows no face.
  r.at(9500);
  TEST_ASSERT_FALSE(onMoment(r.b, expressive(render::Mood::kGrumpy), r.t));
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

// A call from the Mac ends exactly once, when no part of
// it plays any more (the line and its bubble, an animation, the borrowed
// face): done when it played out, or when only the face it holds after
// its line was ended early; cut, and by what, when a tap's poke, a newer
// call, "needs you" or dbg.reset stopped its animation or its line. (One
// none of which would play is refused, and the kit skips it; the kit
// passes on only the holder's end: test_device, test_turn.)
static std::string ended(Rig& r) {
  std::string out;
  app::Ended e;
  while (r.b.takeEnded(e)) {
    if (!out.empty()) out += ", ";
    out += std::to_string(e.call) + (e.by == app::CutBy::kNone ? " done" : " cut");
    if (const char* by = app::cutByName(e.by)) out += std::string(" by ") + by;
  }
  return out;
}

static MomentIn waited(uint32_t id, const char* take = kGo) {
  MomentIn m = expressive(render::Mood::kProud, take);
  m.call = id;
  return m;
}

static void test_a_waited_moment_says_how_it_ended() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.state(base("idle"));  // the idle design's clock from 0
  r.at(1000);
  TEST_ASSERT_TRUE(onMoment(r.b, waited(7), r.t));
  // Its line is over at 1000 + 638 + 1.2 s, and its face at the idle
  // design's next boundary, or with the line if that's later.
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
  r.moment(Anim::kTaskComplete);
  r.at(10500);
  onMoment(r.b, waited(8), r.t);
  r.at(10500 + kGoMs + Behaviour::kBubbleReadMs);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  TEST_ASSERT_EQUAL(Anim::kTaskComplete, r.anim());
  r.at(10000 + loopMs(render::Mood::kProud, SceneState::kTaskComplete));
  TEST_ASSERT_EQUAL_STRING("8 done", ended(r).c_str());
  // A finish the Mac waits on plays on under a newer line, which doesn't
  // stop it: done when the finish is.
  r.at(20000);
  MomentIn cheer;
  cheer.anim = Anim::kTaskComplete, cheer.call = 9;
  onMoment(r.b, cheer, r.t);
  r.at(20500);
  r.say();
  const uint32_t cheered = 20000 + loopMs(render::Mood::kHappy, SceneState::kTaskComplete);
  r.at(cheered - 1);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(cheered);
  TEST_ASSERT_EQUAL_STRING("9 done", ended(r).c_str());

  // A tap's poke doesn't cut its line or face: it
  // plays out, done.
  {
    Rig p;
    p.state(base("idle"));
    p.at(1000);
    onMoment(p.b, waited(10), p.t);
    p.at(1100);
    p.b.tap(p.t, p.rng);
    TEST_ASSERT_EQUAL_STRING("", ended(p).c_str());
    p.at(1000 + 2 * look + kGoMs + Behaviour::kBubbleReadMs);
    TEST_ASSERT_EQUAL_STRING("10 done", ended(p).c_str());
  }
  // Cut short: by a newer moment (a finish, a line, the Mac's next), and
  // by "needs you".
  r.at(30000);
  r.state(base("idle"));  // no app would skip them
  r.at(31000);
  onMoment(r.b, waited(11), r.t);
  r.moment(Anim::kTaskComplete);
  TEST_ASSERT_EQUAL_STRING("11 cut by now", ended(r).c_str());
  r.at(35000);
  onMoment(r.b, waited(12), r.t);
  r.at(35100);
  r.say();
  TEST_ASSERT_EQUAL_STRING("12 cut by now", ended(r).c_str());
  r.at(40000);
  onMoment(r.b, waited(13), r.t);
  onMoment(r.b, waited(14), r.t);
  TEST_ASSERT_EQUAL_STRING("13 cut by now", ended(r).c_str());
  r.at(40100);
  r.state(attn());
  TEST_ASSERT_EQUAL_STRING("14 cut by needs_you", ended(r).c_str());
  // Refused, and so skipped by the kit: something needs you, so none of
  // it would play.
  TEST_ASSERT_EQUAL_STRING("needs_you", r.b.admit(waited(15), r.t));
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());

  // Its face holds on after its line is over. A newer
  // moment or "needs you" then ends it at once, but doesn't cut the
  // moment: it was seen and heard, so it's done. A tap's poke plays in it.
  Rig h;
  Model hm = base("idle");
  hm.variant = 1;  // the idle design's second variation, a long loop, its clock from 0
  h.state(hm);
  const uint32_t idle = loopMs(render::Mood::kProud, SceneState::kIdle, 1);
  render::Mood face;
  {
    Rig p;
    p.state(hm);
    p.at(1000);
    onMoment(p.b, waited(17), p.t);
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
  h.state(hm);
  onMoment(h.b, waited(18), h.t);
  h.at(2 * idle + 1000 + kGoMs + Behaviour::kBubbleReadMs + 100);
  TEST_ASSERT_NULL(h.b.bubble(h.t));
  TEST_ASSERT_EQUAL_STRING("", ended(h).c_str());
  h.state(attn());
  TEST_ASSERT_EQUAL_STRING("18 done", ended(h).c_str());
  h.at(4 * idle + 1000);
  h.state(hm);
  onMoment(h.b, waited(19), h.t);
  h.at(4 * idle + 1000 + kGoMs + Behaviour::kBubbleReadMs + 100);
  h.moment(Anim::kTaskComplete);
  TEST_ASSERT_EQUAL_STRING("19 done", ended(h).c_str());
  h.at(6 * idle + 1000);
  h.state(hm);
  onMoment(h.b, waited(20), h.t);
  h.at(6 * idle + 1000 + kGoMs + Behaviour::kBubbleReadMs + 100);
  h.say();  // a newer line
  TEST_ASSERT_EQUAL_STRING("20 done", ended(h).c_str());
  // During its bubble, after the take, it's still its line, which a tap
  // doesn't cut.
  h.at(8 * idle + 1000);
  h.state(hm);
  onMoment(h.b, waited(21), h.t);
  h.at(8 * idle + 1000 + kGoMs + Behaviour::kBubbleReadMs - 1);
  TEST_ASSERT_NOT_NULL(h.b.bubble(h.t));
  h.b.tap(h.t, h.rng);
  TEST_ASSERT_NOT_NULL(h.b.bubble(h.t));
  TEST_ASSERT_EQUAL_STRING("", ended(h).c_str());
  h.at(9 * idle + 1000);
  TEST_ASSERT_EQUAL_STRING("21 done", ended(h).c_str());
  // The Mac's next reaction, sent once this one's line has played:
  // it replaces the face held for its loops, and
  // this one is done.
  h.at(10 * idle + 1000);
  h.state(hm);
  MomentIn held = expressive(render::Mood::kProud, kGo, 4);  // held four times
  held.call = 22;
  onMoment(h.b, held, h.t);
  h.at(10 * idle + 1000 + kGoMs + Behaviour::kBubbleReadMs + 100);
  TEST_ASSERT_NULL(h.b.bubble(h.t));
  TEST_ASSERT_TRUE(h.b.expression(h.t, face));
  MomentIn next = expressive(render::Mood::kGrumpy);
  next.call = 23;
  TEST_ASSERT_TRUE(onMoment(h.b, next, h.t));
  TEST_ASSERT_EQUAL_STRING("22 done", ended(h).c_str());
  TEST_ASSERT_NOT_NULL(h.b.bubble(h.t));
  TEST_ASSERT_TRUE(h.b.expression(h.t, face));
  TEST_ASSERT_EQUAL(render::Mood::kGrumpy, face);

  // dbg.reset forgets the moment, which the Mac is still told of.
  r.at(50000);
  r.state(base("idle"));
  onMoment(r.b, waited(16), r.t);
  r.b.reset(r.t, r.rng);
  TEST_ASSERT_EQUAL_STRING("16 cut by reset", ended(r).c_str());

  // A moment with no id never ends out loud.
  Rig n;
  n.state(base("idle"));
  n.say();
  n.b.tap(n.t, n.rng);
  n.moment(Anim::kTaskComplete);
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
  MomentIn in;
  in.anim = Anim::kHelperReturn, in.loops = 2;
  onMoment(r.b, in, r.t);
  TEST_ASSERT_EQUAL(Anim::kHelperReturn, r.anim());
  r.at(4201);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
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
  std::vector<uint32_t> none = blinkStarts(base("idle"), false, 180000);
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
    // looked at before its loop ends and its variations may take turns.
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
  r.moment(Anim::kTaskComplete);
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
  TEST_ASSERT_TRUE(s.eyesShut);
  r.at(1000 + loopMs(render::Mood::kProud, SceneState::kTaskComplete));  // the finish is over: back to working, still proud
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kWorking);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kProud);
}

// A tap plays the mood's poked design once, from
// its start and behind the blink that hides any change of design, then the
// look comes back. The third tap in a row, and each after it, plays
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
  TEST_ASSERT_EQUAL(Anim::kPoked, r.anim());
  TEST_ASSERT_TRUE(s.state == SceneState::kPoked);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kHappy);
  TEST_ASSERT_EQUAL_UINT32(0, s.t);
  TEST_ASSERT_TRUE(s.eyesShut && render::eyesClosed(s));
  uint32_t left;
  r.b.moment(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(loopMs(render::Mood::kHappy, SceneState::kPoked), left);  // once
  TEST_ASSERT_EQUAL_INT(1, r.b.taps());
  // The second, just inside 3 s, is in the run, and pokes again.
  r.at(1000 + Behaviour::kTapRunMs - 1);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(Anim::kPoked, r.anim());
  TEST_ASSERT_EQUAL_INT(2, r.b.taps());
  // The third plays tap_spam, and so does each one after it in the run.
  for (int i = 3; i <= 6; ++i) {
    r.at(r.t + 1000);
    r.b.tap(r.t, r.rng);
    TEST_ASSERT_EQUAL(Anim::kTapSpam, r.anim());
    TEST_ASSERT_EQUAL_INT(i, r.b.taps());
    s = r.b.show(r.t);
    TEST_ASSERT_TRUE(s.state == SceneState::kTapSpam && s.t == 0 && s.eyesShut);
  }
  r.b.moment(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(loopMs(render::Mood::kHappy, SceneState::kTapSpam), left);
  // 3 s after the last: a new run, which pokes.
  r.at(r.t + Behaviour::kTapRunMs);
  r.state(m);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(Anim::kPoked, r.anim());
  TEST_ASSERT_EQUAL_INT(1, r.b.taps());
  // Played once, the look comes back, behind a blink.
  r.b.moment(r.t, left);
  r.at(r.t + left);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kWorking && s.eyesShut);
}

// A mood with several poked or tap_spam designs plays one
// at random each time, never the one it played last; the poke is drawn in
// Boop's mood.
static void test_taps_take_turns_between_variations() {
  for (Anim a : {Anim::kPoked, Anim::kTapSpam}) {
    Rig r;
    Model m = base("idle");
    m.mood = render::Mood::kCalm;
    r.state(m);
    const int n = render::variants(render::Mood::kCalm, render::animState(a));
    TEST_ASSERT_EQUAL_INT(3, n);
    int last = -1;
    bool seen[3] = {};
    for (int i = 0; i < 60; ++i) {
      r.at(r.t + (a == Anim::kPoked ? Behaviour::kTapRunMs : 100));
      r.state(m);  // the Mac's keepalive
      r.b.tap(r.t, r.rng);
      if (a == Anim::kTapSpam && i < 2) continue;  // the run's first two poke
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
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_EQUAL_INT(2, r.b.taps());
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNeedsYou);
  r.state(base("idle"));  // answered on the Mac
  r.at(2000);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(Anim::kTapSpam, r.anim());  // the third in the run
  // Listening.
  Rig l;
  l.state(base("idle"));
  l.talkOn();
  l.at(500);
  l.b.tap(l.t, l.rng);
  TEST_ASSERT_EQUAL(Anim::kListening, l.anim());
  TEST_ASSERT_EQUAL_INT(1, l.b.taps());
  // No app.
  Rig n;
  n.state(base("idle"));
  n.at(Behaviour::kNoAppMs);
  const uint32_t seq = n.b.momentSeq();
  n.b.tap(n.t, n.rng);
  TEST_ASSERT_EQUAL(Screen::kNoApp, n.b.screen(n.t));
  TEST_ASSERT_TRUE(n.b.show(n.t).state == SceneState::kNoApp);
  TEST_ASSERT_EQUAL(seq, n.b.momentSeq());
}

// With no state for 30 s the device shows the no-app
// design (backlight 60), with the unplugged icon in the strip; on
// reconnect the face blinks into whatever the next state says.
static void test_no_app_at_30s_and_reconnect_blinks_back() {
  Rig r;
  r.at(1000);
  Model m = attn();  // even a stale "needs you" gives way
  m.busy = 2;
  r.state(m);
  r.at(30999);
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_STRING("codex", r.b.strip(r.t).agent);
  r.at(31000);
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNoApp);
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));  // dimming over kBlendMs
  TEST_ASSERT_TRUE(r.b.backlight(r.t + render::pixel::PixelFace::kBlendMs / 2) < 255);
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  // The strip keeps only the unplugged icon: the counts are stale.
  render::Strip strip = r.b.strip(r.t);
  TEST_ASSERT_TRUE(strip.noApp);
  TEST_ASSERT_NULL(strip.agent);
  TEST_ASSERT_EQUAL(0, strip.busy);
  r.at(31000 + render::pixel::PixelFace::kBlendMs);
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kNoApp);
  TEST_ASSERT_FALSE(s.eyesShut);
  r.at(40000);
  r.state(base("idle"));
  r.state(base("idle"));
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
  TEST_ASSERT_FALSE(r.b.blinking(r.t));
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kIdle);
  TEST_ASSERT_TRUE(s.eyesShut);  // a blink hides the switch
  TEST_ASSERT_FALSE(r.b.show(r.t + render::pixel::PixelFace::kBlendMs).eyesShut);
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t + render::pixel::PixelFace::kBlendMs));
}

// The brain's finish with `who` names that agent and
// thread in the strip while it plays, and no longer, after a mark for what
// its design is for: a tick for a success, a cross for a failure, none for
// a reply. A poke, or a finish without one, names nobody.
static void test_a_cheer_names_whose_turn_in_the_strip() {
  Rig r;
  r.at(1000);
  Model m = base("idle");
  m.busy = 1;
  r.state(m);
  MomentIn in;
  in.anim = Anim::kTaskComplete;
  in.whoAgent = "codex";
  in.whoThread = "fix-nav";
  onMoment(r.b, in, r.t);
  render::Strip strip = r.b.strip(r.t);
  TEST_ASSERT_EQUAL_STRING("codex", strip.doneAgent);
  TEST_ASSERT_EQUAL_STRING("fix-nav", strip.doneThread);
  TEST_ASSERT_TRUE(strip.doneOutcome == render::Outcome::kSuccess);  // happy's first finish is a success
  TEST_ASSERT_NULL(strip.agent);
  TEST_ASSERT_EQUAL(1, strip.busy);
  uint32_t left;
  r.b.moment(r.t, left);
  r.at(r.t + left - 1);
  TEST_ASSERT_EQUAL_STRING("codex", r.b.strip(r.t).doneAgent);
  r.at(r.t + 1);
  TEST_ASSERT_NULL(r.b.strip(r.t).doneAgent);  // gone with the finish
  onMoment(r.b, in, r.t);
  r.b.tap(r.t, r.rng);  // a tap's poke replaces it
  TEST_ASSERT_NULL(r.b.strip(r.t).doneAgent);
  r.at(r.t + 5000);
  r.moment(Anim::kTaskComplete);  // no `who`
  TEST_ASSERT_NULL(r.b.strip(r.t).doneAgent);
  // A failure, and a reply.
  in.variant = 4;  // happy's failed finish
  TEST_ASSERT_TRUE(render::variantOutcome(render::Mood::kHappy, SceneState::kTaskComplete, 4) ==
                   render::Outcome::kFailure);
  onMoment(r.b, in, r.t);
  TEST_ASSERT_TRUE(r.b.strip(r.t).doneOutcome == render::Outcome::kFailure);
  in.anim = Anim::kReplyReady, in.variant = 0;
  onMoment(r.b, in, r.t);
  TEST_ASSERT_EQUAL_STRING("codex", r.b.strip(r.t).doneAgent);
  TEST_ASSERT_TRUE(r.b.strip(r.t).doneOutcome == render::Outcome::kNone);
  in.anim = Anim::kStarting;  // not a finish: nobody's named
  onMoment(r.b, in, r.t);
  TEST_ASSERT_NULL(r.b.strip(r.t).doneAgent);
}

// A tap while the brain's finish names whose turn it
// was takes you to that thread: the press dip only, the finish plays on,
// and the tap carries its id for the Mac. A finish the Mac doesn't wait on (no id) or that names nobody is poked.
static void test_a_tap_on_a_named_finish_opens_its_thread() {
  Rig r;
  r.at(1000);
  r.state(base("idle"));
  MomentIn in;
  in.anim = Anim::kTaskComplete;
  in.whoAgent = "claude";
  in.whoThread = "fix-nav";
  in.call = 9, in.id = 9;
  onMoment(r.b, in, r.t);
  TEST_ASSERT_EQUAL_UINT32(9, r.b.finishShown(r.t));
  r.at(r.t + 100);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(Anim::kTaskComplete, r.anim());
  TEST_ASSERT_EQUAL_STRING("fix-nav", r.b.strip(r.t).doneThread);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(r.t + 100);
  r.b.tap(r.t, r.rng);
  uint32_t left;
  r.b.moment(r.t, left);
  r.at(r.t + left);
  TEST_ASSERT_EQUAL_UINT32(0, r.b.finishShown(r.t));  // over
  TEST_ASSERT_EQUAL_STRING("9 done", ended(r).c_str());
  r.at(r.t + 5000);
  in.call = 0, in.id = 0;  // one the Mac doesn't wait on
  onMoment(r.b, in, r.t);
  TEST_ASSERT_EQUAL_UINT32(0, r.b.finishShown(r.t));
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(Anim::kPoked, r.anim());
  r.at(r.t + 5000);
  in.call = 10, in.id = 10, in.whoAgent = nullptr, in.whoThread = nullptr;  // names nobody
  onMoment(r.b, in, r.t);
  TEST_ASSERT_EQUAL_UINT32(0, r.b.finishShown(r.t));
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(Anim::kPoked, r.anim());
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

// ---- What the agents are doing, the one-shots and the finish -----------

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
  m.act = SceneState::kTerminal, m.mood = Mood::kCalm, m.variant = 2;
  r.state(m);
  r.at(700);
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kTerminal && s.mood == Mood::kCalm);
  TEST_ASSERT_EQUAL_INT(2, s.variant);
  TEST_ASSERT_EQUAL_UINT32(700, s.t);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kTerminal);
  // Another activity: its design from its start, behind a blink.
  m.act = SceneState::kAnalyzing, m.variant = 0;
  r.state(m);
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kAnalyzing && s.t == 0 && s.eyesShut && render::eyesClosed(s));
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

// An activity's variations take turns at
// loop ends like working's, when the mood has more than one; with one,
// it plays on.
static void test_an_acts_variations_take_turns() {
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

// The rules' one-shots (starting,
// stopped, error, helper_return) play their design once in Boop's mood,
// from its start behind a blink, then the look comes back behind another.
// They carry no id, so no `ended` goes back.
static void test_a_rules_one_shot_plays_once() {
  for (Anim a : {Anim::kStarting, Anim::kStopped, Anim::kError, Anim::kHelperReturn}) {
    for (render::Mood mood : {render::Mood::kHappy, render::Mood::kCalm}) {
      Rig r;
      Model m = base("working");
      m.act = SceneState::kTerminal, m.mood = mood;
      r.state(m);
      r.at(1000);
      MomentIn in;
      in.anim = a, in.variant = uint8_t(render::variants(mood, render::animState(a)) - 1);
      TEST_ASSERT_FALSE(onMoment(r.b, in, r.t));  // no line
      SceneShow s = r.b.show(r.t);
      TEST_ASSERT_TRUE(s.state == render::animState(a) && s.mood == mood && s.variant == in.variant);
      TEST_ASSERT_TRUE(s.t == 0 && s.eyesShut && render::eyesClosed(s));
      const uint32_t loop = loopMs(mood, render::animState(a), in.variant);
      r.at(1000 + loop - 1);
      TEST_ASSERT_EQUAL(a, r.anim());
      TEST_ASSERT_EQUAL_UINT32(loop - 1, r.b.show(r.t).t);
      r.at(1000 + loop);
      TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
      s = r.b.show(r.t);
      TEST_ASSERT_TRUE(s.state == SceneState::kTerminal && s.eyesShut && render::eyesClosed(s));
      app::Ended e;
      TEST_ASSERT_FALSE(r.b.takeEnded(e));
    }
  }
}

// An animation's variation is the Mac's when it's one of
// its design's for the moment's facts (a finish's outcome, a start's
// context); otherwise the device picks one of those at random, never the
// one it showed last.
static void test_a_moment_plays_a_fitting_variation() {
  using render::Mood;
  using render::Outcome;
  using render::StartCtx;
  Rig r;
  Model calm = base("idle");
  calm.mood = Mood::kCalm;
  r.state(calm);
  // Happy's starts: one each for a new task, a session and carrying on.
  TEST_ASSERT_EQUAL_INT(1, r.b.pick(Anim::kStarting, Mood::kHappy, 2, Outcome::kNone, StartCtx::kSession, r.rng));
  TEST_ASSERT_EQUAL_INT(1, r.b.pick(Anim::kStarting, Mood::kHappy, 1, Outcome::kNone, StartCtx::kSession, r.rng));
  TEST_ASSERT_EQUAL_INT(1, r.b.pick(Anim::kStarting, Mood::kHappy, 0, Outcome::kNone, StartCtx::kSession, r.rng));
  TEST_ASSERT_EQUAL_INT(2, r.b.pick(Anim::kStarting, Mood::kHappy, 9, Outcome::kNone, StartCtx::kContinuation, r.rng));
  // Without a context, any; the Mac's first among them.
  TEST_ASSERT_EQUAL_INT(0, r.b.pick(Anim::kStarting, Mood::kHappy, 1, Outcome::kNone, StartCtx::kNone, r.rng));
  // Happy's finishes: four successes, and a failure, the fifth.
  TEST_ASSERT_EQUAL_INT(4, r.b.pick(Anim::kTaskComplete, Mood::kHappy, 0, Outcome::kFailure, StartCtx::kNone, r.rng));
  TEST_ASSERT_EQUAL_INT(4, r.b.pick(Anim::kTaskComplete, Mood::kHappy, 2, Outcome::kFailure, StartCtx::kNone, r.rng));
  TEST_ASSERT_EQUAL_INT(2, r.b.pick(Anim::kTaskComplete, Mood::kHappy, 3, Outcome::kSuccess, StartCtx::kNone, r.rng));
  // Calm's starts for a new task, the first three of nine, picked in turn:
  // never the one shown last, and all of them.
  bool seen[9] = {};
  int last = -1;
  for (int i = 0; i < 60; ++i) {
    MomentIn in;
    in.anim = Anim::kStarting;
    in.variant = r.b.pick(in.anim, Mood::kCalm, 0, Outcome::kNone, StartCtx::kNewTask, r.rng);
    TEST_ASSERT_TRUE(render::variantCtx(Mood::kCalm, SceneState::kStarting, in.variant) == StartCtx::kNewTask);
    TEST_ASSERT_NOT_EQUAL(last, in.variant);
    last = in.variant, seen[in.variant] = true;
    r.at(r.t + 100);
    onMoment(r.b, in, r.t);
  }
  TEST_ASSERT_TRUE(seen[0] && seen[1] && seen[2]);
  // Calm's failed finishes, likewise.
  last = -1;
  for (int i = 0; i < 30; ++i) {
    MomentIn in;
    in.anim = Anim::kTaskComplete;
    in.variant = r.b.pick(in.anim, Mood::kCalm, 1, Outcome::kFailure, StartCtx::kNone, r.rng);  // 1 is a success
    TEST_ASSERT_TRUE(render::variantOutcome(Mood::kCalm, SceneState::kTaskComplete, in.variant) == Outcome::kFailure);
    TEST_ASSERT_NOT_EQUAL(last, in.variant);
    last = in.variant;
    r.at(r.t + 100);
    onMoment(r.b, in, r.t);
  }
  // One to choose from: no roll.
  app::Rng a, b;
  r.b.pick(Anim::kReplyReady, Mood::kHappy, 0, Outcome::kNone, StartCtx::kNone, a);
  TEST_ASSERT_EQUAL_UINT32(b.next(), a.next());
}

// A brain's face with no animation that comes during a
// one-shot or a poke plays over it without cutting it: the one-shot's
// design, drawn in the brain's mood, on its own clock, which ends when it
// would have.
static void test_a_face_plays_over_a_one_shot() {
  NEEDS_VOICE_PACK();
  for (Anim a : {Anim::kError, Anim::kPoked}) {
    Rig r;
    r.state(base("working"));
    r.at(1000);
    MomentIn in;
    in.anim = a;
    onMoment(r.b, in, r.t);
    const uint32_t loop = loopMs(render::Mood::kHappy, render::animState(a));
    r.at(1500);
    const uint32_t seq = r.b.momentSeq();
    TEST_ASSERT_TRUE(onMoment(r.b, expressive(render::Mood::kGrumpy), r.t));
    TEST_ASSERT_EQUAL(seq + 1, r.b.momentSeq());  // the line only
    SceneShow s = r.b.show(r.t);
    TEST_ASSERT_TRUE(s.state == render::animState(a) && s.mood == render::Mood::kGrumpy);
    TEST_ASSERT_EQUAL_UINT32(500, s.t);
    uint32_t left;
    TEST_ASSERT_EQUAL(a, r.b.moment(r.t, left));
    TEST_ASSERT_EQUAL_UINT32(loop - 500, left);
    TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  }
}

// None of the one-shots plays while something needs
// you or listening waits for the reply.
static void test_no_one_shot_while_the_face_is_held() {
  for (Anim a : {Anim::kStarting, Anim::kStopped, Anim::kError, Anim::kHelperReturn, Anim::kReplyReady}) {
    Rig r;
    r.state(attn());
    MomentIn in;
    in.anim = a, in.call = 3;
    TEST_ASSERT_EQUAL_STRING("needs_you", r.b.admit(in, r.t));  // the kit skips it
    TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
    TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNeedsYou);
    TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
    Rig l;
    l.state(base("idle"));
    l.talkOn();
    in.call = 0;
    onMoment(l.b, in, l.t);
    TEST_ASSERT_EQUAL(Anim::kListening, l.anim());
  }
}

// Only the reply ends listening: a call
// with a `say` (a take or none), or stop_listening. A one-shot, a finish
// or a poke with no `say` and a face on its own leave it be.
static void test_only_the_reply_ends_listening() {
  Rig r;
  r.state(base("idle"));
  r.talkOn();
  const uint32_t seq = r.b.momentSeq();
  for (Anim a : {Anim::kStarting, Anim::kStopped, Anim::kError, Anim::kHelperReturn, Anim::kTaskComplete,
                 Anim::kReplyReady, Anim::kPoked, Anim::kTapSpam}) {
    MomentIn in;
    in.anim = a;
    onMoment(r.b, in, r.t);
    TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  }
  MomentIn face;  // a mood and nothing else
  face.expr = true, face.mood = render::Mood::kProud;
  onMoment(r.b, face, r.t);
  MomentIn unknown;  // an animation the device doesn't know reads as none, and isn't empty
  onMoment(r.b, unknown, r.t);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  TEST_ASSERT_EQUAL(seq, r.b.momentSeq());
  MomentIn said;  // a `say` with no take is still the reply
  said.said = true;
  onMoment(r.b, said, r.t);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  r.talkOn();
  r.stop();
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
}

// What shows, first first: no app, listening, needs you,
// a tap's poke and the moments, then the look.
static void test_what_shows_first() {
  Rig r;
  Model m = base("working");
  m.act = SceneState::kTesting;
  r.state(m);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kTesting);  // 5. the look
  r.at(1000);
  r.moment(Anim::kStarting);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kStarting);  // 4. a moment
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kPoked);  // 4. a poke replaces it
  r.moment(Anim::kError);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kError);  // and a moment the poke
  r.state(attn());
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNeedsYou);  // 3. needs you cuts them
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  r.b.tap(r.t, r.rng);
  r.moment(Anim::kStopped);
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNeedsYou);
  r.talkOn();
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kListening);  // 2. listening over needs you
  r.at(1000 + Behaviour::kNoAppMs);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kNoApp);  // 1. no app over all of it
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
}

// A line that comes with an animation starts at its design's
// voice window (render::pixel::Score::voiceMs), bubble and mouth alike, and the
// animation holds on at least until the line and its bubble are over,
// resting on its last frame, rather than the line being hurried. The
// expression holds as long. A line on its own starts at once.
static void test_a_finishs_line_waits_for_its_voice_window() {
  NEEDS_VOICE_PACK();
  using render::Mood;
  Rig r;
  Model m = base("idle");
  m.mood = Mood::kGrumpy;
  r.state(m);
  r.at(1000);
  MomentIn in;
  in.anim = Anim::kTaskComplete, in.variant = 4;  // grumpy's failed finish
  in.said = true, in.take = voice::takeIndex("new.d20");  // "Mwahaha...", 2434 ms
  in.expr = true, in.mood = Mood::kGrumpy, in.call = 5;
  const uint32_t voice = render::pixel::score(render::pixelIndex(Mood::kGrumpy), int(SceneState::kTaskComplete), 4).voiceMs;
  const uint32_t loop = loopMs(Mood::kGrumpy, SceneState::kTaskComplete, 4);
  uint32_t line = 2434 + Behaviour::kBubbleReadMs;
  TEST_ASSERT_TRUE(voice > 0 && voice + line > loop);  // it doesn't fit: the hold stretches
  TEST_ASSERT_TRUE(onMoment(r.b, in, r.t));
  uint32_t left;
  r.b.moment(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(voice + line, left);
  r.at(1000 + voice - 1);
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_TRUE(r.b.lineAhead(r.t));
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
  TEST_ASSERT_EQUAL(Anim::kTaskComplete, r.anim());
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(1000 + voice + line);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  render::Mood face;
  TEST_ASSERT_FALSE(r.b.expression(r.t, face));
  TEST_ASSERT_EQUAL_STRING("5 done", ended(r).c_str());
  // A line that fits ends first: the animation plays its loops, and the
  // strip comes back once the bubble goes.
  r.state(m);
  in.anim = Anim::kReplyReady, in.variant = 0, in.call = 6;
  in.take = voice::takeIndex(kGo);
  line = kGoMs + Behaviour::kBubbleReadMs;
  in.whoAgent = "codex", in.whoThread = "landing";
  onMoment(r.b, in, r.t);
  const uint32_t reply = render::pixel::score(render::pixelIndex(Mood::kGrumpy), int(SceneState::kReplyReady), 0).voiceMs;
  const uint32_t replyLoop = loopMs(Mood::kGrumpy, SceneState::kReplyReady);
  TEST_ASSERT_TRUE(reply + line < replyLoop);
  r.b.moment(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(replyLoop, left);
  const uint32_t at = r.t;
  r.at(at + reply + line);
  TEST_ASSERT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_EQUAL_STRING("codex", r.b.strip(r.t).doneAgent);
  r.at(at + replyLoop);
  TEST_ASSERT_EQUAL_STRING("6 done", ended(r).c_str());
  // Tapped before its line: the poke replaces the finish, which was cut,
  // but the line still plays at its window, over the poke. (One that
  // names whose turn it was isn't poked: the tap opens that thread.)
  r.at(at + replyLoop + 1000);
  r.state(m);
  in.call = 7, in.whoAgent = nullptr, in.whoThread = nullptr;
  onMoment(r.b, in, r.t);
  const uint32_t tapped = r.t;
  r.at(r.t + 100);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(Anim::kPoked, r.anim());
  TEST_ASSERT_TRUE(r.b.lineAhead(r.t));
  r.at(tapped + reply);
  TEST_ASSERT_NOT_NULL(r.b.bubble(r.t));
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(tapped + replyLoop);  // its face holds for the finish's loop
  TEST_ASSERT_EQUAL_STRING("7 cut by tap", ended(r).c_str());
}

// A new mood's flip-book blinks in a step
// of its own, so the device gives it none of its blinks; a change of design
// to or from one shows its blink step, as the first pack's shut their eyes.
static void test_flip_books_blink_by_themselves() {
  Model calm = base("idle");
  calm.mood = render::Mood::kCalm;
  TEST_ASSERT_TRUE(blinkStarts(calm, true, 120000).empty());
  Model working = base("working");
  working.mood = render::Mood::kWounded;
  TEST_ASSERT_TRUE(blinkStarts(working, true, 120000).empty());
  TEST_ASSERT_TRUE(render::blinksItself(render::Mood::kCalm, SceneState::kIdle, 0));
  TEST_ASSERT_FALSE(render::blinksItself(render::Mood::kHappy, SceneState::kIdle, 0));
  Rig r;
  r.state(calm);
  r.at(3000);
  const SceneShow open = r.b.show(r.t);  // between its own blinks
  TEST_ASSERT_FALSE(open.eyesShut || render::eyesClosed(open));
  r.state(working);
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.eyesShut && render::eyesClosed(s));
  r.at(3000 + render::pixel::PixelFace::kBlendMs);
  TEST_ASSERT_FALSE(r.b.show(r.t).eyesShut);
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

// A long touch during needs you is a tap too: the squash, and no moment.
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

int main() {
  UNITY_BEGIN();
  if (!packfile::open()) std::printf("no voice pack: the chosen character pack has none\n");
  RUN_TEST(test_needs_you_alerts_once_and_stays_amber);
  RUN_TEST(test_a_different_request_with_the_same_names_alerts);
  RUN_TEST(test_tap_during_needs_you_is_only_the_dip_and_stays_amber);
  RUN_TEST(test_answering_on_the_mac_blinks_back);
  RUN_TEST(test_attention_wins_over_moments);
  RUN_TEST(test_changes_mid_motion_blink_into_the_new_design);
  RUN_TEST(test_no_app_holds_for_weeks);
  RUN_TEST(test_no_change_ever_cuts_hard);
  RUN_TEST(test_nothing_cuts_hard_as_it_plays_out);
  RUN_TEST(test_push_to_talk_listens_then_waits);
  RUN_TEST(test_listening_holds_until_the_reply);
  RUN_TEST(test_listening_plays_while_something_needs_you);
  RUN_TEST(test_the_empty_moment_ends_only_listening);
  RUN_TEST(test_push_to_talk_timeouts);
  RUN_TEST(test_listening_takes_turns_between_variations);
  RUN_TEST(test_moments_end_and_replace);
  RUN_TEST(test_a_cheer_plays_its_loops);
  RUN_TEST(test_a_take_moves_the_mouth);
  RUN_TEST(test_a_line_of_two_takes);
  RUN_TEST(test_a_line_alone_plays_over_the_face);
  RUN_TEST(test_a_face_alone_plays_its_loops);
  RUN_TEST(test_an_expression_holds_its_loops);
  RUN_TEST(test_an_expression_over_the_cheer_and_across_a_look_change);
  RUN_TEST(test_an_expression_ends_with_its_moment);
  RUN_TEST(test_a_waited_moment_says_how_it_ended);
  RUN_TEST(test_the_clock_going_back_starts_the_look_over);
  RUN_TEST(test_life_is_blinks_at_their_pace);
  RUN_TEST(test_asleep_breathes_and_never_blinks);
  RUN_TEST(test_taps_poke_and_a_run_spams);
  RUN_TEST(test_taps_take_turns_between_variations);
  RUN_TEST(test_a_held_face_counts_taps_but_only_dips);
  RUN_TEST(test_an_act_shows_in_workings_place);
  RUN_TEST(test_an_acts_variations_take_turns);
  RUN_TEST(test_a_rules_one_shot_plays_once);
  RUN_TEST(test_a_moment_plays_a_fitting_variation);
  RUN_TEST(test_a_face_plays_over_a_one_shot);
  RUN_TEST(test_no_one_shot_while_the_face_is_held);
  RUN_TEST(test_only_the_reply_ends_listening);
  RUN_TEST(test_what_shows_first);
  RUN_TEST(test_a_finishs_line_waits_for_its_voice_window);
  RUN_TEST(test_flip_books_blink_by_themselves);
  RUN_TEST(test_each_look_shows_its_design_in_the_mood);
  RUN_TEST(test_the_looks_variations_take_turns);
  RUN_TEST(test_no_app_at_30s_and_reconnect_blinks_back);
  RUN_TEST(test_a_cheer_names_whose_turn_in_the_strip);
  RUN_TEST(test_a_tap_on_a_named_finish_opens_its_thread);
  RUN_TEST(test_press_shows_within_20ms);
  RUN_TEST(test_gestures_send_the_right_inputs);
  RUN_TEST(test_a_long_touch_during_needs_you_is_a_tap);
  return UNITY_END();
}
