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
// with you, a pose's clip, a call, the pointer, reading along, a video;
// each only while the eyes are free.
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
  TEST_ASSERT_TRUE(p.x == Gaze::kMidX + Gaze::kMacReach && p.y == Gaze::kEyesY);  // right at it, at the edge
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
  // Below the pointer: reading along, then a video.
  Gaze r;
  f = GazeFacts{};
  f.free = true, f.mac = 1, f.with = WithYou::kReading;
  p = r.look(f, 1000);
  TEST_ASSERT_TRUE(p.on && p.x == Gaze::kMidX + Gaze::kPageReach && p.y == Gaze::kPageY);  // at the page
  f.pointer = true, f.pointerX = -3;
  TEST_ASSERT_TRUE(r.look(f, 7016).x < Gaze::kMidX);  // the pointer comes first
  f.pointer = false, f.mac = 0;
  TEST_ASSERT_EQUAL_INT(Gaze::kMidX, r.look(f, 7032).x);  // no side told: forward
  f.up = true;
  TEST_ASSERT_EQUAL_INT(Gaze::kPageUpY, r.look(f, 7040).y);  // the screen above: its page up there
  f.up = false;
  f.with = WithYou::kVideo, f.mac = -1;
  p = r.look(f, 7048);
  TEST_ASSERT_TRUE(p.x == Gaze::kMidX - Gaze::kPageReach && p.y == Gaze::kEyesY);
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
  static_assert(GelFace::kLeanReach == 160 && GelFace::kPointerLean == 14 && GelFace::kPointerStretch == 6 &&
                    GelFace::kNearStretch == 50,
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
  TEST_ASSERT_TRUE(lean < -100 && lean >= -112);  // its way: 14 a step, eased
  TEST_ASSERT_TRUE(board.channel(rig::Channel::kSquash) - face.mixer().channels()[rig::Channel::kSquash] <
                   -20);  // up: taller
  board.pointer(true, 9, 0);
  board.to(board.t + 1200);
  TEST_ASSERT_TRUE(face.engine().motion.attendX > F(0));
  // At the edge nearest the board: right at it, leaning in, stretched toward it.
  board.pointer(true, 1, 0, true);
  board.to(board.t + 1200);
  const rig::Channels mixed = face.mixer().channels();
  TEST_ASSERT_TRUE(board.channel(rig::Channel::kLean) - mixed[rig::Channel::kLean] > 150);
  TEST_ASSERT_TRUE(board.channel(rig::Channel::kSquash) - mixed[rig::Channel::kSquash] < -45);
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

// Pins reading along: while you scroll, and kReadLingerMs after, it reads
// along, turned to the Mac's side and a little lower, no pastime dealt; a
// read of kSettleMs settles it in, its lids half down; and none at work in
// a pose of its own.
void test_it_reads_along_while_you_scroll() {
  static_assert(GelFace::kReadLingerMs == 6000 && GelFace::kSettleMs == 120000 && GelFace::kReadGapMs == 60000,
                "the times this test pins");
  const uint32_t scrolling = tagBit("scrolling"), right = tagBit("macright");
  Board board(SceneState::kIdle, kDay | tierBit(2) | right);
  GelFace& face = board.face();
  board.to(1000);
  board.tags(kDay | tierBit(2) | right | scrolling);
  board.to(board.t + 1000);
  TEST_ASSERT_EQUAL_INT(int(WithYou::kReading), int(face.withYou()));
  TEST_ASSERT_EQUAL_STRING("reading", face.passing(board.t));
  TEST_ASSERT_TRUE(face.engine().motion.attending && face.engine().motion.attendX > F(0));  // to the Mac, on its right
  TEST_ASSERT_TRUE(board.channel(rig::Channel::kLean) > 120 && board.channel(rig::Channel::kSquash) > 20);
  // You stop: it reads on a while, then rests.
  board.tags(kDay | tierBit(2) | right);
  const uint32_t stopped = board.t;
  board.to(stopped + GelFace::kReadLingerMs - 64);
  TEST_ASSERT_EQUAL_INT(int(WithYou::kReading), int(face.withYou()));
  board.to(stopped + GelFace::kReadLingerMs + 64);
  TEST_ASSERT_EQUAL_INT(int(WithYou::kNone), int(face.withYou()));
  // Two minutes of reading along, scrolling now and then: settled in, lids
  // half down, and never a pastime over it.
  bool pastime = false;
  int lids = 1000;
  for (int i = 0; i < 30; ++i) {
    board.tags(kDay | tierBit(2) | right | scrolling);
    board.to(board.t + 2000, [&] { pastime = pastime || face.pastimes(board.t).playing != Pastime::kNone; });
    board.tags(kDay | tierBit(2) | right);
    board.to(board.t + 3000, [&] { pastime = pastime || face.pastimes(board.t).playing != Pastime::kNone; });
  }
  board.to(board.t + 800, [&] { lids = std::min(lids, int(board.channel(rig::Channel::kEyeOpenL))); });
  TEST_ASSERT_FALSE(pastime);
  TEST_ASSERT_TRUE(lids < 600);  // settled in for a comfortable read
  // At work in a pose of its own: no reading along.
  Board work(SceneState::kWorking, kDay | right | scrolling);
  work.m.act = SceneState::kTerminal;
  work.state();
  work.to(3000, [&] { TEST_ASSERT_EQUAL_INT(int(WithYou::kNone), int(work.face().withYou())); });
}

// Pins music: it gets into it kGrooveMs (eyes half closed, a slow sway and
// a nod, no hop), then rests kGrooveRestMs, and again; as the music stops
// it looks round once. Watching a video: turned to the screen, still.
void test_it_grooves_to_your_music_and_watches_with_you() {
  static_assert(GelFace::kGrooveMs == 24000 && GelFace::kGrooveRestMs == 180000, "the groove this test pins");
  const uint32_t music = tagBit("music"), left = tagBit("macleft");
  Board board(SceneState::kIdle, kDay | tierBit(1) | left);
  GelFace& face = board.face();
  board.to(1000);
  board.tags(kDay | tierBit(1) | left | music);
  const uint32_t from = board.t;
  int low = 1 << 30, high = -(1 << 30), lifted = 0, lids = 1000;
  board.to(from + 12000, [&] {
    if (board.t < from + 1000) return;
    const int lean = board.channel(rig::Channel::kLean);
    low = std::min(low, lean), high = std::max(high, lean),
    lifted = std::max(lifted, board.channel(rig::Channel::kLift));
    lids = std::min(lids, board.channel(rig::Channel::kEyeOpenL));
  });
  TEST_ASSERT_EQUAL_INT(int(WithYou::kMusic), int(face.withYou()));
  TEST_ASSERT_TRUE(high - low > 100 && high - low < 200);  // a slow sway, side to side
  TEST_ASSERT_EQUAL_INT(0, lifted);                        // never a hop
  TEST_ASSERT_TRUE(lids < 650);                            // eyes half closed
  board.to(from + GelFace::kGrooveMs + 100);
  TEST_ASSERT_EQUAL_INT(int(WithYou::kNone), int(face.withYou()));  // it rests
  board.to(from + GelFace::kGrooveMs + GelFace::kGrooveRestMs + 100);
  TEST_ASSERT_EQUAL_INT(int(WithYou::kMusic), int(face.withYou()));  // and again
  board.tags(kDay | tierBit(1) | left);
  board.to(board.t + 64);
  TEST_ASSERT_EQUAL_STRING("look-around", board.cueing());  // the music's stopped: a look round
  // Watching: to the screen, on its left, its eyes still.
  Board video(SceneState::kIdle, kDay | tierBit(1) | left | tagBit("video"));
  video.to(2000);
  TEST_ASSERT_EQUAL_INT(int(WithYou::kVideo), int(video.face().withYou()));
  TEST_ASSERT_TRUE(video.face().engine().motion.attendX < F(0) && video.channel(rig::Channel::kLean) < -120);
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
  const uint32_t all = tagBit("music") | tagBit("video") | tagBit("scrolling");
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
// glance: headphones while music plays, the groove's notes only in the
// groove, kept through its rest, while it types along and at work in a pose
// of its own; a page beside it while it reads along, on the Mac's side,
// whose lines scroll kPageScroll px a second only while you scroll; a
// screen while it watches; a muted mic on a call and nothing else then;
// and none of them asleep or with a card held but the headphones.
void test_what_it_wears_and_has_beside_it() {
  static_assert(GelFace::kPageScroll == 14, "the page's scroll this test pins");
  const uint32_t music = tagBit("music"), scrolling = tagBit("scrolling"), left = tagBit("macleft");
  Board board(SceneState::kIdle, kDay | tierBit(1));
  const Engine::With& w = board.face().engine().with;
  board.to(1000);
  TEST_ASSERT_TRUE(!w.headphones && !w.page && !w.screen && !w.muted && !w.notes);
  board.tags(kDay | tierBit(1) | music);
  const uint32_t from = board.t;
  board.to(from + 2000);
  TEST_ASSERT_TRUE(w.headphones == 255 && w.notes);
  board.tags(kDay | tierBit(1) | music | tagBit("typing"));
  board.to(board.t + 1000);
  TEST_ASSERT_TRUE(board.face().pastimes(board.t).tapping && w.headphones == 255 && !w.notes);
  board.tags(kDay | tierBit(1) | music);
  // Resting from the groove, through its pastimes: still on, no notes.
  board.to(from + GelFace::kGrooveMs + 1000);
  board.to(from + GelFace::kGrooveMs + 60000, [&] { TEST_ASSERT_TRUE(w.headphones == 255 && !w.notes); });
  // Reading along: the page on the Mac's side, scrolling while you do.
  board.tags(kDay | tierBit(1) | left | scrolling);
  board.to(board.t + 1000);
  const int scrolled = w.scroll;
  TEST_ASSERT_TRUE(w.page == 255 && w.side == -1 && !w.headphones && !w.screen);
  board.to(board.t + 1000);
  TEST_ASSERT_INT_WITHIN(1, GelFace::kPageScroll, w.scroll - scrolled);
  board.tags(kDay | tierBit(1) | left);
  const int stopped = w.scroll;
  board.to(board.t + 2000);
  TEST_ASSERT_TRUE(w.page == 255 && w.scroll == stopped);  // you stopped: it reads on, the page still
  // A video: the screen, not the page.
  board.to(board.t + GelFace::kReadLingerMs);
  board.tags(kDay | tierBit(1) | left | tagBit("video"));
  board.to(board.t + 1000);
  TEST_ASSERT_TRUE(w.screen == 255 && !w.page);
  // A call: the muted mic, and nothing else.
  board.tags(kDay | tierBit(1) | left | tagBit("video") | music | tagBit("oncall"));
  board.to(board.t + 1000);
  TEST_ASSERT_TRUE(w.muted == 255 && !w.screen && !w.headphones && !w.page);
  // At work in a pose of its own: the light size has them too.
  Board work(SceneState::kWorking, kDay | music);
  work.m.act = SceneState::kAnalyzing;
  work.state();
  work.to(2000);
  TEST_ASSERT_EQUAL_INT(255, work.face().engine().with.headphones);
  work.tags(kDay | scrolling);
  work.to(4000);
  TEST_ASSERT_EQUAL_INT(255, work.face().engine().with.page);
  // Asleep, nothing; a card held, its hands are full: nothing beside it.
  Board asleep(SceneState::kAsleep, kDay | music | scrolling);
  asleep.to(3000, [&] { TEST_ASSERT_TRUE(!asleep.face().engine().with.headphones && !asleep.face().engine().with.page); });
  Board card(SceneState::kIdle, kDay | scrolling);
  CardShow held;
  held.on = true;
  card.face().card(held);
  card.to(3000, [&] { TEST_ASSERT_EQUAL_INT(0, card.face().engine().with.page); });
}
