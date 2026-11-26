// With you at the Mac besides typing along (render/gel/face.h, showWithYou)
// and where the eyes go for it (render/gel/gaze.h): the pointer, reading
// along, watching, music, a call, a copy held and typing fast; each rule's
// place against the others and against what has the body, and nothing at
// all while the Mac sends none of it.
#include <unity.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <memory>

#include "app/behaviour.h"
#include "render/gel/face.h"
#include "render/gel/gaze.h"
#include "render/gel/painter.h"
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
  void pointer(bool on, int x = 0, int y = 0, bool near = false) {
    m.pointer.on = on, m.pointer.x = int8_t(x), m.pointer.y = int8_t(y), m.pointer.near = near;
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
  // What the clips and the follows ask, under the motion layer
  // (render/gel/lively.h, which test_motion pins).
  int channel(rig::Channel c) { return face().clipChannels()[c]; }
  const char* cueing() { return face().cueing() ? face().cueing()->id : ""; }
};

const uint32_t kDay = tagBit("day");

}  // namespace

// Pins the rule list's order (gaze.h): needs you, typing along, thinking
// with you, a pose's clip, a call, the pointer, scrolling; each only while
// the eyes are free.
void test_the_eyes_with_you_in_order() {
  static_assert(Gaze::kThinkAfterMs == 8000 && Gaze::kThinkMs == 2000, "thinking with you, as this test pins");
  Gaze g;
  GazeFacts f;
  f.free = true;
  TEST_ASSERT_FALSE(g.look(f, 0).on);  // nothing with you: rest
  // The pointer: its way, as you see the board.
  f.pointer = true, f.pointerX = -10, f.pointerY = 0;
  GazePoint p = g.look(f, 16);
  TEST_ASSERT_TRUE(p.on && p.x < Gaze::kMidX - 300 && p.y == Gaze::kEyesY);
  f.pointerX = 5, f.pointerY = -10;
  p = g.look(f, 32);
  TEST_ASSERT_TRUE(p.x > Gaze::kMidX && p.y < Gaze::kYouY + 20);  // up and to its right
  f.pointerX = 1, f.pointerY = 0, f.pointerNear = true;
  p = g.look(f, 48);
  TEST_ASSERT_TRUE(p.x == Gaze::kMidX + Gaze::kNearReach && p.y == Gaze::kEyesY);  // right at it, at the edge
  f.pointerNear = false;
  // Above it: a call keeps the eyes still; a pose's clip has them; thinking
  // looks up at you; typing along is down at the keys; needs you first.
  f.with = WithYou::kCall;
  TEST_ASSERT_FALSE(g.look(f, 64).on);
  f.with = WithYou::kNone, f.posed = true;
  TEST_ASSERT_FALSE(g.look(f, 80).on);
  f.thinking = true, f.thinkMs = 100;
  TEST_ASSERT_TRUE(g.look(f, 96).y == Gaze::kYouY);
  f.thinkMs = Gaze::kThinkMs;
  TEST_ASSERT_FALSE(g.look(f, 112).on);  // its moment is over
  f.along = true;
  TEST_ASSERT_TRUE(g.look(f, 128).y == Gaze::kKeysY);
  f.needsYou = true, f.lookMs = 0;
  TEST_ASSERT_TRUE(g.look(f, 144).y == Gaze::kYouY);
  // Below the pointer: scrolling, forward, its clip darting the eyes.
  Gaze r;
  f = GazeFacts{};
  f.free = true, f.mac = 1, f.with = WithYou::kScrolling;
  TEST_ASSERT_FALSE(r.look(f, 1000).on);
  f.pointer = true, f.pointerX = -3;
  TEST_ASSERT_TRUE(r.look(f, 7016).x < Gaze::kMidX);  // the pointer comes first
  // The screen above it: needs you looks up at you, then up at the screen.
  Gaze up;
  GazeFacts u;
  u.free = u.needsYou = u.up = true, u.lookMs = Gaze::kNoticeMs;
  p = up.look(u, 100);
  TEST_ASSERT_TRUE(p.on && p.x == Gaze::kMidX && p.y == Gaze::kScreenUpY);
  f.free = false;
  TEST_ASSERT_FALSE(r.look(f, 7064).on);  // something else has the eyes
}

// Pins the pointer: idle, the eyes follow it and the body leans a little its
// way, further at the edge nearest the board, reaching up toward it; let
// go, back to rest. Not in a work pose, not under needs you, nothing with
// no pointer.
void test_the_eyes_follow_your_pointer() {
  static_assert(GelFace::kNearLean == 215 && GelFace::kPointerLean == 19 && GelFace::kPointerStretch == 8 &&
                    GelFace::kNearStretch == 68,
                "the lean this test pins");
  Board board(SceneState::kIdle, kDay | tierBit(1));
  GelFace& face = board.face();
  board.to(1000);
  TEST_ASSERT_FALSE(face.engine().motion.attending);
  TEST_ASSERT_EQUAL_INT(0, board.channel(rig::Channel::kLean) - face.mixer().channels()[rig::Channel::kLean]);
  board.pointer(true, -8, -4);
  board.to(board.t + 1200);
  TEST_ASSERT_TRUE(face.engine().motion.attending && face.engine().motion.attendX < F(0) &&
                   face.engine().motion.attendUp > F(0));
  const int lean = board.channel(rig::Channel::kLean) - face.mixer().channels()[rig::Channel::kLean];
  TEST_ASSERT_TRUE(lean < -135 && lean >= -152);  // its way: 19 a step, eased
  TEST_ASSERT_TRUE(board.channel(rig::Channel::kSquash) - face.mixer().channels()[rig::Channel::kSquash] <
                   -20);  // up: taller
  board.pointer(true, 9, 0);
  board.to(board.t + 1200);
  TEST_ASSERT_TRUE(face.engine().motion.attendX > F(0));
  // At the edge nearest the board: right at it, leaning in, stretched toward it.
  board.pointer(true, 1, 0, true);
  board.to(board.t + 1200);
  const rig::Channels mixed = face.mixer().channels();
  TEST_ASSERT_TRUE(board.channel(rig::Channel::kLean) - mixed[rig::Channel::kLean] > 200);
  TEST_ASSERT_TRUE(board.channel(rig::Channel::kSquash) - mixed[rig::Channel::kSquash] < -60);
  // Moving the eyes and the body never pops: the lean eases.
  board.pointer(true, -10, 0);
  int last = board.channel(rig::Channel::kLean) - face.mixer().channels()[rig::Channel::kLean], jump = 0;
  board.to(board.t + 800, [&] {
    const int now = board.channel(rig::Channel::kLean) - face.mixer().channels()[rig::Channel::kLean];
    jump = std::max(jump, std::abs(now - last)), last = now;
  });
  TEST_ASSERT_TRUE(jump <= 20);  // at most 20 thousandths a frame
  // The Mac stops sending it: rest.
  board.pointer(false);
  board.to(board.t + 2000);
  TEST_ASSERT_FALSE(face.engine().motion.attending);
  TEST_ASSERT_TRUE(std::abs(board.channel(rig::Channel::kLean) - face.mixer().channels()[rig::Channel::kLean]) <= 1);
  // At work in a pose with the eyes of its own: nothing.
  Board work(SceneState::kWorking, kDay);
  work.m.act = SceneState::kAnalyzing;
  work.pointer(true, -8, 0);
  work.to(3000, [&] {
    TEST_ASSERT_FALSE(work.face().engine().motion.attending && work.face().engine().motion.attendX < F(0));
  });
  // In its typing pose, yes.
  work.m.act = SceneState::kToolUse;
  work.state();
  work.to(work.t + 1200);
  TEST_ASSERT_TRUE(work.face().engine().motion.attending && work.face().engine().motion.attendX < F(0));
  // Needs you comes first.
  work.m.attn = true, work.m.attnId = 3;
  std::strcpy(work.m.agent, "claude");
  work.state();
  work.to(work.t + 600);
  TEST_ASSERT_TRUE(work.face().engine().motion.attendUp > F(0) && abs(work.face().engine().motion.attendX) < q(.01));
}

// Pins scrolling: while you scroll its eyes dart up and down, far and
// fast, the way you scroll: scrolling down they sweep down and snap back up
// (the snap the quicker), scrolling up the other way, and both by turns
// when the Mac doesn't know the way; no pastime dealt; it stops with the
// tag; none at work in a pose of its own.
void test_its_eyes_dart_while_you_scroll() {
  const uint32_t scrolling = tagBit("scrolling"), right = tagBit("macright");
  // The eyes' quickest step down and up, a frame, and their whole span.
  struct Darts {
    int down = 0, up = 0, low = 1 << 30, high = -(1 << 30);
  };
  auto darts = [&](uint32_t way) {
    Board board(SceneState::kIdle, kDay | tierBit(2) | right);
    board.to(1000);
    board.tags(kDay | tierBit(2) | right | scrolling | way);
    board.to(board.t + 1000);
    TEST_ASSERT_EQUAL_INT(int(WithYou::kScrolling), int(board.face().withYou()));
    TEST_ASSERT_EQUAL_STRING("scrolling", board.face().passing(board.t));
    Darts d;
    int last = board.channel(rig::Channel::kGazeY);
    bool pastime = false;
    board.to(board.t + 3000, [&] {
      const int now = board.channel(rig::Channel::kGazeY);
      d.down = std::max(d.down, now - last), d.up = std::max(d.up, last - now), last = now;
      d.low = std::min(d.low, now), d.high = std::max(d.high, now);
      pastime = pastime || board.face().pastimes(board.t).playing != Pastime::kNone;
    });
    TEST_ASSERT_FALSE(pastime);
    board.tags(kDay | tierBit(2) | right);
    board.to(board.t + 200);
    TEST_ASSERT_EQUAL_INT(int(WithYou::kNone), int(board.face().withYou()));
    return d;
  };
  const Darts down = darts(tagBit("scrolldown")), up = darts(tagBit("scrollup")), either = darts(0);
  for (const Darts& d : {down, up, either}) TEST_ASSERT_TRUE(d.high - d.low > 1200);  // far, up and down
  TEST_ASSERT_TRUE(down.up > down.down);  // down: the snap back up is the quicker
  TEST_ASSERT_TRUE(up.down > up.up);      // up: the snap back down is
  // At work in a pose of its own: the pose has the eyes.
  Board work(SceneState::kWorking, kDay | right | scrolling);
  work.m.act = SceneState::kTerminal;
  work.state();
  work.to(3000, [&] { TEST_ASSERT_EQUAL_INT(int(WithYou::kNone), int(work.face().withYou())); });
}

// Pins music: idle, it jams along the whole time it plays, eyes closed, a
// bounce on the beat (a lift) and its head bobbing side to side, no pastime
// dealt; as the music stops it looks round once. At work, in any pose, it
// jams smaller over the pose, still at its desk.
void test_it_jams_to_your_music() {
  const uint32_t music = tagBit("music");
  Board board(SceneState::kIdle, kDay | tierBit(1));
  GelFace& face = board.face();
  board.to(1000);
  board.tags(kDay | tierBit(1) | music);
  const uint32_t from = board.t;
  int low = 1 << 30, high = -(1 << 30), lifted = 0, lids = 1000;
  bool pastime = false;
  board.to(from + 120000, [&] {
    if (board.t < from + 1000) return;
    const int lean = board.channel(rig::Channel::kLean);
    low = std::min(low, lean), high = std::max(high, lean);
    lifted = std::max(lifted, board.channel(rig::Channel::kLift));
    lids = std::min(lids, board.channel(rig::Channel::kEyeOpenL));
    pastime = pastime || face.pastimes(board.t).playing != Pastime::kNone;
    if (face.withYou() != WithYou::kMusic) TEST_FAIL_MESSAGE("it stopped jamming while the music played");
  });
  TEST_ASSERT_EQUAL_STRING("music", face.passing(board.t));
  TEST_ASSERT_TRUE(high - low > 350);  // its head bobbing side to side
  TEST_ASSERT_TRUE(lifted >= 6);       // a bounce on the beat
  TEST_ASSERT_TRUE(lids < 650);        // eyes closed
  TEST_ASSERT_FALSE(pastime);
  board.tags(kDay | tierBit(1));
  board.to(board.t + 64);
  TEST_ASSERT_EQUAL_STRING("look-around", board.cueing());  // the music's stopped: a look round
  // At work, typing pose and a pose of its own: smaller, over the pose.
  for (SceneState act : {SceneState::kToolUse, SceneState::kAnalyzing}) {
    Board work(SceneState::kWorking, kDay);
    work.m.act = act;
    work.state();
    work.to(2000);
    const int rest = work.channel(rig::Channel::kLean);
    work.tags(kDay | music);
    int wlow = 1 << 30, whigh = -(1 << 30);
    work.to(12000, [&] {
      if (work.t < 4000) return;
      const int lean = work.channel(rig::Channel::kLean) - rest;
      wlow = std::min(wlow, lean), whigh = std::max(whigh, lean);
    });
    TEST_ASSERT_EQUAL_INT(int(WithYou::kNone), int(work.face().withYou()));
    TEST_ASSERT_TRUE(whigh - wlow > 60 && whigh - wlow < 300);  // jamming, smaller
    TEST_ASSERT_EQUAL_INT(255, work.face().engine().with.notes);
  }
}

// Pins the call: still and a little smaller, its eyes half closed; no
// typing along, no music, no pastime however long; a stretch as it ends.
// It comes before a read and music.
void test_a_call_keeps_it_still() {
  const uint32_t call = tagBit("oncall"), typing = tagBit("typing"), music = tagBit("music");
  Board board(SceneState::kIdle, kDay | tierBit(3));
  GelFace& face = board.face();
  board.to(1000);
  board.tags(kDay | tierBit(3) | call | typing | music | tagBit("scrolling"));
  bool moved = false;
  board.to(board.t + 300000, [&] {
    moved = moved || face.pastimes(board.t).tapping || face.pastimes(board.t).playing != Pastime::kNone;
  });
  TEST_ASSERT_FALSE(moved);
  TEST_ASSERT_EQUAL_INT(int(WithYou::kCall), int(face.withYou()));
  TEST_ASSERT_EQUAL_STRING("oncall", face.passing(board.t));
  TEST_ASSERT_TRUE(board.channel(rig::Channel::kSquash) > 120 && board.channel(rig::Channel::kEyeOpenL) < 650);
  TEST_ASSERT_FALSE(face.engine().motion.attending);  // its eyes still, forward
  board.tags(kDay | tierBit(3));
  board.to(board.t + 64);
  TEST_ASSERT_EQUAL_STRING("stretch", board.cueing());
}

// Pins typing fast: its paws tap quicker, as high, and its eyes open wider
// and it hunches in, no hop; the paws' place in their beat never jumps as
// fast comes and goes, and a flicker off doesn't restart its clip.
void test_typing_fast_is_quicker_not_higher() {
  static_assert(kFastMs < kBriskMs && kFastTapMs * kBriskMs == kBriskTapMs * kFastMs,
                "fast is quicker, the tap the same share of its beat");
  static_assert(GelFace::kFastLingerMs == 800, "the flicker this test pins");
  TEST_ASSERT_EQUAL_INT(kBriskLift, briskLift(2 * kBeat - kTapBeat / 2, -1));
  const uint32_t typing = tagBit("typing"), fast = tagBit("typingfast");
  Board board(SceneState::kIdle, kDay | tierBit(1));
  GelFace& face = board.face();
  board.tags(kDay | tierBit(1) | typing);
  board.to(1500);
  const int lids = board.channel(rig::Channel::kEyeOpenL), size = board.channel(rig::Channel::kEyeSize);
  TEST_ASSERT_FALSE(face.pastimes(board.t).fast);
  // On and off and on: each frame's paw a small step from the last.
  int jump = 0, lifted = 0, last = briskLift(face.pastimes(board.t).pawPhase, -1);
  auto watch = [&] {
    const int now = briskLift(face.pastimes(board.t).pawPhase, -1);
    jump = std::max(jump, std::abs(now - last)), last = now;
    lifted = std::max(lifted, board.channel(rig::Channel::kLift));
  };
  board.tags(kDay | tierBit(1) | typing | fast);
  board.to(board.t + 800, watch);
  TEST_ASSERT_TRUE(face.pastimes(board.t).tapping && face.pastimes(board.t).fast);
  TEST_ASSERT_TRUE(board.channel(rig::Channel::kEyeOpenL) - lids > 150 &&
                   board.channel(rig::Channel::kEyeSize) - size > 80);
  // A flicker off: still fast.
  board.tags(kDay | tierBit(1) | typing);
  board.to(board.t + 300, watch);
  TEST_ASSERT_TRUE(face.pastimes(board.t).fast);
  board.tags(kDay | tierBit(1) | typing | fast);
  board.to(board.t + 300, watch);
  board.tags(kDay | tierBit(1) | typing);
  board.to(board.t + 1000, watch);
  TEST_ASSERT_FALSE(face.pastimes(board.t).fast);
  TEST_ASSERT_TRUE(jump <= kBriskLift / 2);  // the paw moves, never snaps
  TEST_ASSERT_EQUAL_INT(0, lifted);          // and no hop
}

// Nothing with you while the Mac sends none of it; and every one gives way
// to needs you, a Moment's face, sleep and a work pose of its own.
void test_nothing_with_you_without_the_facts() {
  Board board(SceneState::kIdle, kDay | tierBit(2));
  GelFace& face = board.face();
  board.to(60000, [&] {
    TEST_ASSERT_EQUAL_INT(int(WithYou::kNone), int(face.withYou()));
    TEST_ASSERT_EQUAL_INT(face.mixer().channels()[rig::Channel::kLean], board.channel(rig::Channel::kLean));
  });
  const uint32_t all = tagBit("music") | tagBit("scrolling") | tagBit("scrolldown");
  for (SceneState look : {SceneState::kAsleep, SceneState::kNeedsYou}) {
    Board other(look == SceneState::kNeedsYou ? SceneState::kWorking : look, kDay | all);
    if (look == SceneState::kNeedsYou) {
      other.m.attn = true, other.m.attnId = 5;
      std::strcpy(other.m.agent, "codex");
      other.state();
    }
    other.to(5000, [&] { TEST_ASSERT_EQUAL_INT(int(WithYou::kNone), int(other.face().withYou())); });
  }
  // Asleep, the pointer moves no eye.
  Board asleep(SceneState::kAsleep, kDay);
  asleep.pointer(true, -9, -3);
  asleep.to(3000, [&] { TEST_ASSERT_FALSE(asleep.face().engine().motion.attending); });
  // Holding an agent's card, its hands are full: no pose.
  Board card(SceneState::kIdle, kDay | tagBit("scrolling"));
  CardShow held;
  held.on = true;
  card.face().card(held);
  card.to(3000, [&] { TEST_ASSERT_EQUAL_INT(int(WithYou::kNone), int(card.face().withYou())); });
}

// Pins speaking along: another app recording with no camera (`speaking`)
// leans it in and nods on the 1.6 s beat, and wins over typing along, one
// rhythm at a time; the layers draw its cupped hand while it does.
void test_speaking_wins_over_typing() {
  Board board(SceneState::kIdle, kDay | tierBit(1));
  GelFace& face = board.face();
  board.to(1000);
  board.tags(kDay | tierBit(1) | tagBit("typing") | tagBit("speaking"));
  board.to(board.t + 1000);
  TEST_ASSERT_EQUAL_INT(int(WithYou::kSpeaking), int(face.withYou()));
  TEST_ASSERT_EQUAL_STRING("speaking", face.passing(board.t));
  TEST_ASSERT_FALSE(face.pastimes(board.t).tapping);
  TEST_ASSERT_TRUE(face.engine().speaking);
  board.tags(kDay | tierBit(1) | tagBit("typing"));
  board.to(board.t + 1000);
  TEST_ASSERT_FALSE(face.engine().speaking);
  TEST_ASSERT_TRUE(face.pastimes(board.t).tapping);
}

// Pins what it has on or beside it (Engine::With), so each reads at a
// glance: the music's notes while music plays, through its pastimes, while
// it types along and at work in a pose of its own; a muted mic on a call
// and nothing else then; and nothing asleep. Scrolling has no mark.
void test_what_it_has_on_or_beside_it() {
  const uint32_t music = tagBit("music"), scrolling = tagBit("scrolling");
  Board board(SceneState::kIdle, kDay | tierBit(1));
  const Engine::With& w = board.face().engine().with;
  board.to(1000);
  TEST_ASSERT_TRUE(!w.notes && !w.muted);
  board.tags(kDay | tierBit(1) | music);
  board.to(board.t + 2000);
  TEST_ASSERT_EQUAL_INT(255, w.notes);
  board.tags(kDay | tierBit(1) | music | tagBit("typing"));
  board.to(board.t + 1000);
  TEST_ASSERT_TRUE(board.face().pastimes(board.t).tapping && w.notes == 255);
  board.tags(kDay | tierBit(1) | scrolling);
  board.to(board.t + 1000);
  TEST_ASSERT_TRUE(!w.notes && !w.muted);
  // A call: the muted mic, and nothing else.
  board.tags(kDay | tierBit(1) | music | tagBit("oncall"));
  board.to(board.t + 1000);
  TEST_ASSERT_TRUE(w.muted == 255 && !w.notes);
  // At work in a pose of its own: the notes too.
  Board work(SceneState::kWorking, kDay | music);
  work.m.act = SceneState::kAnalyzing;
  work.state();
  work.to(2000);
  TEST_ASSERT_EQUAL_INT(255, work.face().engine().with.notes);
  // Asleep, nothing.
  Board asleep(SceneState::kAsleep, kDay | music);
  asleep.to(3000, [&] { TEST_ASSERT_EQUAL_INT(0, asleep.face().engine().with.notes); });
}
