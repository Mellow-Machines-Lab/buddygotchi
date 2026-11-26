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
// with you, a pose's clip, a call, scrolling, the pointer; each only while
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
  // Above the pointer: scrolling rests the look, the face's own look has the eyes.
  Gaze r;
  f = GazeFacts{};
  f.free = true, f.mac = 1, f.with = WithYou::kScrolling;
  TEST_ASSERT_FALSE(r.look(f, 1000).on);
  f.pointer = true, f.pointerX = -3;
  TEST_ASSERT_FALSE(r.look(f, 7016).on);  // scrolling comes first
  f.with = WithYou::kNone;
  TEST_ASSERT_TRUE(r.look(f, 7032).x < Gaze::kMidX);
  // The screen above it: needs you looks up at you, then up at the screen.
  Gaze up;
  GazeFacts u;
  u.free = u.needsYou = u.up = true, u.lookMs = Gaze::kNoticeMs;
  p = up.look(u, 100);
  TEST_ASSERT_TRUE(p.on && p.x == Gaze::kMidX && p.y == Gaze::kScreenUpY);
  // Speaking: to the Mac's side, where the sound comes from, over the
  // pointer; with no side, the pointer's.
  f.with = WithYou::kSpeaking;
  p = r.look(f, 7048);
  TEST_ASSERT_TRUE(p.on && p.x == Gaze::kMidX + Gaze::kMacReach && p.y == Gaze::kEyesY);
  f.mac = 0;
  TEST_ASSERT_TRUE(r.look(f, 7056).x < Gaze::kMidX);
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
  TEST_ASSERT_TRUE(lean < -170 && lean >= -186);  // its way: 19 a step, a fifth more out here, eased
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

// Pins the pointer toward its reach: from 4 of its 10 steps out, on a smooth
// curve, the lean, the slide and the stretch go up to a quarter further,
// and the face turns its way across and nods its way up or down; in the
// middle, all as it was.
void test_the_pointer_a_little_more_at_its_reach() {
  static_assert(GelFace::kEdgeFrom == 4 && GelFace::kEdgeFull == 9 && GelFace::kEdgeMore == 250 &&
                    GelFace::kEdgeTurn == 15 && GelFace::kEdgeNod == 60,
                "the edge this test pins");
  struct Seen {
    int lean, x, turn, nod;
  };
  auto at = [](int px, int py) {
    Board board(SceneState::kIdle, kDay | tierBit(1));
    board.to(1000);
    board.pointer(true, px, py);
    board.to(board.t + 2500);
    const rig::Channels mixed = board.face().mixer().channels();
    return Seen{board.channel(rig::Channel::kLean) - mixed[rig::Channel::kLean],
                board.channel(rig::Channel::kX) - mixed[rig::Channel::kX],
                board.channel(rig::Channel::kTurn) - mixed[rig::Channel::kTurn], board.face().engine().faceNod};
  };
  const Seen middle = at(4, 0), edge = at(9, 0), left = at(-9, 0), high = at(0, -9), low = at(0, 9);
  TEST_ASSERT_TRUE(std::abs(middle.lean - 4 * GelFace::kPointerLean) <= 1);  // as it was
  TEST_ASSERT_TRUE(middle.turn == 0 && middle.nod == 0);
  TEST_ASSERT_TRUE(std::abs(edge.lean - 9 * GelFace::kPointerLean * 5 / 4) <= 2);  // a quarter more
  TEST_ASSERT_TRUE(edge.x >= 1 && edge.turn >= GelFace::kEdgeTurn - 1 && left.turn <= -GelFace::kEdgeTurn + 1);
  TEST_ASSERT_TRUE(edge.nod == 0 && high.nod <= -GelFace::kEdgeNod + 1 && low.nod >= GelFace::kEdgeNod - 1);
  TEST_ASSERT_TRUE(high.turn == 0);
}

// Pins scrolling: while you scroll it looks straight the way you scroll and
// holds it, its eyes all the way, its face nodded that way, flatter looking
// down and taller and up a little looking up; in quick, back slower as you
// stop, and from one straight to the other as the way changes, never
// stopping between. With the way not known, nothing; no pastime dealt; the
// pointer waits; none at work in a pose of its own.
void test_it_looks_the_way_you_scroll() {
  static_assert(GelFace::kLookInMs == 90 && GelFace::kLookOutMs == 300 && GelFace::kLookNod == 170 &&
                    GelFace::kLookSquash == 120 && GelFace::kLookStretch == 140 && GelFace::kLookLift == 4,
                "the look this test pins");
  const uint32_t scrolling = tagBit("scrolling"), right = tagBit("macright"), base = kDay | tierBit(2) | right;
  Board board(SceneState::kIdle, base);
  GelFace& face = board.face();
  auto off = [&](rig::Channel c) { return board.channel(c) - face.mixer().channels()[c]; };
  const int& nod = face.engine().faceNod;
  board.to(1000);
  // Down: the eyes all the way within a quarter second, and held still.
  board.tags(base | scrolling | tagBit("scrolldown"));
  board.to(board.t + 250);
  TEST_ASSERT_EQUAL_INT(int(WithYou::kScrolling), int(face.withYou()));
  TEST_ASSERT_EQUAL_STRING("scrolling", face.passing(board.t));
  TEST_ASSERT_TRUE(off(rig::Channel::kGazeY) >= 900 && nod >= GelFace::kLookNod * 9 / 10);
  int low = 1 << 30, high = -(1 << 30);
  bool pastime = false;
  board.pointer(true, -9, 0);  // the pointer waits
  board.to(board.t + 500);
  board.to(board.t + 3000, [&] {
    low = std::min(low, off(rig::Channel::kGazeY)), high = std::max(high, off(rig::Channel::kGazeY));
    pastime = pastime || face.pastimes(board.t).playing != Pastime::kNone;
  });
  TEST_ASSERT_TRUE(low >= 990 && high <= 1000 && !pastime);
  TEST_ASSERT_TRUE(off(rig::Channel::kSquash) > 100 && off(rig::Channel::kLean) == 0);
  // Straight to up, never stopping between, and there within 0.4 s.
  board.tags(base | scrolling | tagBit("scrollup"));
  int last = off(rig::Channel::kGazeY);
  board.to(board.t + 400, [&] {
    TEST_ASSERT_TRUE(off(rig::Channel::kGazeY) < last || off(rig::Channel::kGazeY) <= -990);
    last = off(rig::Channel::kGazeY);
  });
  TEST_ASSERT_TRUE(last <= -900 && nod <= -GelFace::kLookNod * 9 / 10);
  TEST_ASSERT_TRUE(off(rig::Channel::kSquash) < -100 && off(rig::Channel::kLift) >= 3);  // taller, up a little
  // Stopped: back, slower than it came: half way still after 0.15 s, home by 1.5 s.
  board.pointer(false);
  board.tags(base);
  board.to(board.t + 150);
  TEST_ASSERT_EQUAL_INT(int(WithYou::kNone), int(face.withYou()));
  TEST_ASSERT_TRUE(off(rig::Channel::kGazeY) <= -500);
  board.to(board.t + 1350);
  TEST_ASSERT_TRUE(std::abs(off(rig::Channel::kGazeY)) <= 10 && std::abs(nod) <= 5);
  // The way not known: nothing rather than a guess.
  board.tags(base | scrolling);
  board.to(board.t + 1000, [&] {
    TEST_ASSERT_EQUAL_INT(int(WithYou::kNone), int(face.withYou()));
    TEST_ASSERT_TRUE(std::abs(off(rig::Channel::kGazeY)) <= 10);
  });
  // At work in a pose of its own: the pose has the eyes.
  Board work(SceneState::kWorking, kDay | right | scrolling | tagBit("scrolldown"));
  work.m.act = SceneState::kTerminal;
  work.state();
  work.to(3000, [&] {
    TEST_ASSERT_EQUAL_INT(int(WithYou::kNone), int(work.face().withYou()));
    TEST_ASSERT_EQUAL_INT(0, work.face().engine().faceNod);
  });
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
// rhythm at a time; its hand is at its ear while it does.
void test_speaking_wins_over_typing() {
  Board board(SceneState::kIdle, kDay | tierBit(1));
  GelFace& face = board.face();
  board.to(1000);
  board.tags(kDay | tierBit(1) | tagBit("typing") | tagBit("speaking"));
  board.to(board.t + 1000);
  TEST_ASSERT_EQUAL_INT(int(WithYou::kSpeaking), int(face.withYou()));
  TEST_ASSERT_EQUAL_STRING("speaking", face.passing(board.t));
  TEST_ASSERT_FALSE(face.pastimes(board.t).tapping);
  TEST_ASSERT_NOT_EQUAL_INT(0, face.engine().ear);
  board.tags(kDay | tierBit(1) | tagBit("typing"));
  board.to(board.t + 1000);
  TEST_ASSERT_EQUAL_INT(0, face.engine().ear);
  TEST_ASSERT_TRUE(face.pastimes(board.t).tapping);
}

namespace {
// A frame's rig hand on `side` (0 the left), as the motion layer draws it.
struct Drawn {
  int x, y, size;
};
Drawn drawn(GelFace& face, int side) {
  const rig::Channels c = face.channels();
  using rig::HandPart;
  return {c[rig::hand(side, HandPart::kX)], c[rig::hand(side, HandPart::kY)], c[rig::hand(side, HandPart::kSize)]};
}
// Steps `board` to `until`, each frame's hand on `side` no more than
// `size` thousandths bigger or smaller than the last, nor `place` px from
// it, once it's out (`from`, the first frame out, its size then), but as
// the desk's paw takes it back at the keys; the other hand in.
void noPop(Board& board, uint32_t until, int side, int size = 200, int place = 30, Drawn* from = nullptr) {
  Drawn last = drawn(board.face(), side);
  board.to(until, [&] {
    const Drawn now = drawn(board.face(), side);
    const bool home = !now.size && std::abs(now.x - Lively::kDeskX) <= Lively::kHome &&
                      std::abs(now.y - Lively::kDeskY) <= Lively::kHome;
    if (!last.size && now.size && from) *from = now, from = nullptr;
    else if (!home) TEST_ASSERT_INT_WITHIN(size, last.size, now.size);
    if (last.size && now.size) TEST_ASSERT_TRUE(std::abs(now.x - last.x) + std::abs(now.y - last.y) <= place);
    TEST_ASSERT_EQUAL_INT(0, drawn(board.face(), 1 - side).size);
    last = now;
  });
}
}  // namespace

// Pins speaking's hand: the rig's on the Mac's side, budding out of the
// body to its ear and an open palm there, and sinking back in as you stop,
// never a frame's pop either way; the other hand stays in. With the
// keyboard out it goes from its keys and back to them. Holding a card,
// the card keeps its hands: the sound comes in, no hand.
void test_speakings_hand_buds_out_at_the_macs_side() {
  static_assert(GelFace::kEarSize >= 1150 && GelFace::kEarSize <= 1400, "about 20 to 24 px, as a hand at an ear");
  for (int side = 0; side < 2; ++side) {
    const uint32_t mac = tagBit(side ? "macright" : "macleft");
    Board board(SceneState::kIdle, kDay | tierBit(1) | mac);
    GelFace& face = board.face();
    board.to(1000);
    board.tags(kDay | tierBit(1) | mac | tagBit("speaking"));
    noPop(board, board.t + 66, side);
    TEST_ASSERT_TRUE(drawn(face, side).size < GelFace::kEarSize / 2);  // on its way
    noPop(board, board.t + 1500, side);
    TEST_ASSERT_EQUAL_INT(side ? 1000 : -1000, face.engine().ear);
    const Drawn out = drawn(face, side);
    TEST_ASSERT_INT_WITHIN(40, GelFace::kEarSize, out.size);
    TEST_ASSERT_INT_WITHIN(4, (side ? 1 : -1) * GelFace::kEarX, out.x);
    TEST_ASSERT_EQUAL_INT(1000, face.channels()[rig::hand(side, rig::HandPart::kShape)]);  // an open palm
    TEST_ASSERT_GREATER_THAN_INT(0, face.engine().with.heard);
    board.tags(kDay | tierBit(1) | mac);
    noPop(board, board.t + 1500, side);
    TEST_ASSERT_TRUE(face.engine().ear == 0 && drawn(face, side).size == 0 && face.engine().with.heard == 0);
  }
  // From the keys: its first frame out is a step from the desk's paw, where
  // the desk had it, and back at the desk it's the desk's again.
  const uint32_t typing = kDay | tierBit(1) | tagBit("macright") | tagBit("typing");
  Board keys(SceneState::kIdle, typing);
  keys.to(2000);
  TEST_ASSERT_TRUE(keys.face().pastimes(keys.t).keys > 128);
  keys.tags(typing | tagBit("speaking"));
  Drawn from{};
  noPop(keys, keys.t + 1500, 1, 200, 30, &from);
  TEST_ASSERT_INT_WITHIN(150, Lively::kDeskSize, from.size);
  TEST_ASSERT_TRUE(std::abs(from.x - Lively::kDeskX) <= 10 && std::abs(from.y - Lively::kDeskY) <= 10);
  TEST_ASSERT_INT_WITHIN(40, GelFace::kEarSize, drawn(keys.face(), 1).size);
  keys.tags(typing);
  noPop(keys, keys.t + 1500, 1);
  TEST_ASSERT_TRUE(keys.face().engine().ear == 0 && drawn(keys.face(), 1).size == 0);
  TEST_ASSERT_TRUE(keys.face().pastimes(keys.t).tapping);
  // A card held: its hands are the card's.
  Board card(SceneState::kIdle, kDay | tierBit(1) | tagBit("macright"));
  CardShow held;
  held.on = true;
  card.face().card(held);
  card.to(1000);
  card.tags(kDay | tierBit(1) | tagBit("macright") | tagBit("speaking"));
  card.to(card.t + 2000, [&] {
    TEST_ASSERT_TRUE(!drawn(card.face(), 0).size && !drawn(card.face(), 1).size && !card.face().engine().ear);
  });
  TEST_ASSERT_EQUAL_INT(int(WithYou::kSpeaking), int(card.face().withYou()));
  TEST_ASSERT_EQUAL_INT(255, card.face().engine().with.heard);
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
