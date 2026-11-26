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
#include "render/gel/layers.h"
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

// Pins who has what (render/gel/owners.h), a row a case: what's true, and
// each part's owner.
void test_who_has_what() {
  struct Row {
    const char* what;
    WhatsTrue f;
    BodyBy body;
    BeatBy beat;
    bool beatShows;
    EyesBy eyes;
    FaceBy face;
    MarkBy mark;
    bool keys;
  };
  auto facts = [](std::initializer_list<bool WhatsTrue::*> on) {
    WhatsTrue f;
    f.place = true;
    for (auto m : on) f.*m = true;
    return f;
  };
  using W = WhatsTrue;
  const Row rows[] = {
      {"nothing", facts({}), BodyBy::kLook, BeatBy::kBreath, false, EyesBy::kOwn, FaceBy::kMood, MarkBy::kNone, false},
      {"music", facts({&W::music}), BodyBy::kLook, BeatBy::kMusic, true, EyesBy::kJam, FaceBy::kJam, MarkBy::kNotes, false},
      {"music, a mood that keeps its face", facts({&W::music, &W::keepsFace}), BodyBy::kLook, BeatBy::kMusic, true,
       EyesBy::kJam, FaceBy::kMood, MarkBy::kNotes, false},
      {"music, scrolling", facts({&W::music, &W::scrolling}), BodyBy::kLook, BeatBy::kMusic, true, EyesBy::kScroll,
       FaceBy::kMood, MarkBy::kNotes, false},
      {"music, the pointer", facts({&W::music, &W::pointer}), BodyBy::kLook, BeatBy::kMusic, true, EyesBy::kPointer,
       FaceBy::kMood, MarkBy::kNotes, false},
      {"music, typing", facts({&W::music, &W::typing}), BodyBy::kLook, BeatBy::kMusic, true, EyesBy::kJam, FaceBy::kJam,
       MarkBy::kNotes, true},
      {"typing, speaking", facts({&W::typing, &W::speaking}), BodyBy::kLook, BeatBy::kSpeaking, true, EyesBy::kOwn,
       FaceBy::kMood, MarkBy::kEar, true},
      {"speaking, the Mac's side told, the pointer", facts({&W::speaking, &W::mac, &W::pointer}), BodyBy::kLook,
       BeatBy::kSpeaking, true, EyesBy::kSpeaking, FaceBy::kMood, MarkBy::kEar, false},
      {"typing, a sign up", facts({&W::typing, &W::signUp}), BodyBy::kLook, BeatBy::kTyping, true, EyesBy::kOwn,
       FaceBy::kMood, MarkBy::kNone, false},
      {"a call over all", facts({&W::call, &W::speaking, &W::music, &W::typing, &W::scrolling, &W::pointer}), BodyBy::kLook,
       BeatBy::kCall, true, EyesBy::kCall, FaceBy::kMood, MarkBy::kMuted, false},
      {"at work, music", facts({&W::music, &W::desk}), BodyBy::kLook, BeatBy::kMusic, true, EyesBy::kOwn, FaceBy::kMood,
       MarkBy::kNotes, false},
      {"light: a pose's eyes", facts({&W::light, &W::posed, &W::desk, &W::scrolling, &W::pointer, &W::music}),
       BodyBy::kLook, BeatBy::kMusic, true, EyesBy::kPose, FaceBy::kMood, MarkBy::kNotes, false},
      {"a card held: no scroll", facts({&W::light, &W::desk, &W::scrolling}), BodyBy::kLook, BeatBy::kBreath, false,
       EyesBy::kOwn, FaceBy::kMood, MarkBy::kNone, false},
      {"a pastime over music", facts({&W::pastime, &W::music, &W::typing}), BodyBy::kPastime, BeatBy::kMusic, false,
       EyesBy::kBody, FaceBy::kMood, MarkBy::kNotes, false},
      {"listening", facts({&W::listening, &W::music}), BodyBy::kListening, BeatBy::kMusic, false, EyesBy::kBody,
       FaceBy::kMood, MarkBy::kNone, false},
      {"needs you", facts({&W::needsYou, &W::music, &W::pointer}), BodyBy::kNeedsYou, BeatBy::kMusic, false, EyesBy::kOwn,
       FaceBy::kMood, MarkBy::kNone, false},
      {"a finger", facts({&W::finger, &W::music}), BodyBy::kFinger, BeatBy::kMusic, false, EyesBy::kFinger, FaceBy::kMood,
       MarkBy::kNone, false},
      {"a Moment, a finger", facts({&W::moment, &W::finger}), BodyBy::kMoment, BeatBy::kBreath, false, EyesBy::kFinger,
       FaceBy::kMoment, MarkBy::kNone, false},
  };
  for (const Row& r : rows) {
    const Owners o = whoHasWhat(r.f);
    TEST_ASSERT_EQUAL_INT_MESSAGE(int(r.body), int(o.body), r.what);
    TEST_ASSERT_EQUAL_INT_MESSAGE(int(r.beat), int(o.beat), r.what);
    TEST_ASSERT_EQUAL_MESSAGE(r.beatShows, o.beatShows, r.what);
    TEST_ASSERT_EQUAL_INT_MESSAGE(int(r.eyes), int(o.eyes), r.what);
    TEST_ASSERT_EQUAL_INT_MESSAGE(int(r.face), int(o.face), r.what);
    TEST_ASSERT_EQUAL_INT_MESSAGE(int(r.mark), int(o.mark), r.what);
    TEST_ASSERT_EQUAL_MESSAGE(r.keys, o.keys, r.what);
  }
  // Asleep, or the Mac gone: nothing with you, whatever's true.
  WhatsTrue away = facts({&W::music, &W::typing, &W::pointer});
  away.place = false;
  const Owners o = whoHasWhat(away);
  TEST_ASSERT_TRUE(!o.with && !o.beatShows && o.eyes == EyesBy::kOwn && o.mark == MarkBy::kNone && !o.keys);
}

// Pins where the eyes go for each owner (gaze.h): the pointer's way, as you
// see the board; its own gaze's list, needs you, typing along, thinking with
// you; any other owner rests the gaze.
void test_the_eyes_with_you_in_order() {
  static_assert(Gaze::kThinkAfterMs == 8000 && Gaze::kThinkMs == 2000, "thinking with you, as this test pins");
  Gaze g;
  GazeFacts f;
  TEST_ASSERT_FALSE(g.look(f, 0).on);  // nothing with you: rest
  // The pointer: its way, as you see the board.
  f.eyes = EyesBy::kPointer, f.pointerX = -10, f.pointerY = 0;
  GazePoint p = g.look(f, 16);
  TEST_ASSERT_TRUE(p.on && p.x < Gaze::kMidX - 300 && p.y == Gaze::kEyesY);
  f.pointerX = 5, f.pointerY = -10;
  p = g.look(f, 32);
  TEST_ASSERT_TRUE(p.x > Gaze::kMidX && p.y < Gaze::kYouY + 20);  // up and to its right
  f.pointerX = 1, f.pointerY = 0, f.pointerNear = true;
  p = g.look(f, 48);
  TEST_ASSERT_TRUE(p.x == Gaze::kMidX + Gaze::kNearReach && p.y == Gaze::kEyesY);  // right at it, at the edge
  // Speaking: to the Mac's side, where the sound comes from.
  f.eyes = EyesBy::kSpeaking, f.mac = 1;
  p = g.look(f, 56);
  TEST_ASSERT_TRUE(p.on && p.x == Gaze::kMidX + Gaze::kMacReach && p.y == Gaze::kEyesY);
  f.mac = 0;
  // Every other owner but its own gaze rests it, typing along and all.
  f.along = true;
  for (EyesBy other : {EyesBy::kJam, EyesBy::kScroll, EyesBy::kCall, EyesBy::kPose, EyesBy::kBody, EyesBy::kFinger}) {
    f.eyes = other;
    TEST_ASSERT_FALSE(g.look(f, 64).on);
  }
  // Its own: thinking looks up at you; typing along is down at the keys;
  // needs you first.
  f.eyes = EyesBy::kOwn, f.along = false;
  f.thinking = true, f.thinkMs = 100;
  TEST_ASSERT_TRUE(g.look(f, 96).y == Gaze::kYouY);
  f.thinkMs = Gaze::kThinkMs;
  TEST_ASSERT_FALSE(g.look(f, 112).on);  // its moment is over
  f.along = true;
  TEST_ASSERT_TRUE(g.look(f, 128).y == Gaze::kKeysY);
  f.needsYou = true, f.lookMs = 0;
  TEST_ASSERT_TRUE(g.look(f, 144).y == Gaze::kYouY);
  // The screen above it: needs you looks up at you, then up at the screen.
  Gaze up;
  GazeFacts u;
  u.needsYou = u.up = true, u.lookMs = Gaze::kNoticeMs;
  p = up.look(u, 100);
  TEST_ASSERT_TRUE(p.on && p.x == Gaze::kMidX && p.y == Gaze::kScreenUpY);
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
  TEST_ASSERT_EQUAL_INT(int(EyesBy::kScroll), int(face.owners().eyes));
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
  TEST_ASSERT_EQUAL_INT(int(EyesBy::kOwn), int(face.owners().eyes));
  TEST_ASSERT_TRUE(off(rig::Channel::kGazeY) <= -500);
  board.to(board.t + 1350);
  TEST_ASSERT_TRUE(std::abs(off(rig::Channel::kGazeY)) <= 10 && std::abs(nod) <= 5);
  // The way not known: nothing rather than a guess.
  board.tags(base | scrolling);
  board.to(board.t + 1000, [&] {
    TEST_ASSERT_EQUAL_INT(int(EyesBy::kOwn), int(face.owners().eyes));
    TEST_ASSERT_TRUE(std::abs(off(rig::Channel::kGazeY)) <= 10);
  });
  // At work in a pose of its own: the pose has the eyes.
  Board work(SceneState::kWorking, kDay | right | scrolling | tagBit("scrolldown"));
  work.m.act = SceneState::kTerminal;
  work.state();
  work.to(3000, [&] {
    TEST_ASSERT_EQUAL_INT(int(EyesBy::kPose), int(work.face().owners().eyes));
    TEST_ASSERT_EQUAL_INT(0, work.face().engine().faceNod);
  });
}

// Pins music: idle, it jams along the whole time it plays, eyes closed, a
// bounce on the beat (a lift) and its head bobbing side to side; its
// pastimes go on, each over the jam, the beat there again after; as the
// music stops it looks round once. At work, in any pose, it
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
    const bool passing = face.pastimes(board.t).playing != Pastime::kNone;
    pastime = pastime || passing;
    if (face.owners().beat != BeatBy::kMusic || (!passing && !face.owners().beatShows))
      TEST_FAIL_MESSAGE("it stopped jamming while the music played");
  });
  while (face.pastimes(board.t).playing != Pastime::kNone) board.to(board.t + 16);
  board.to(board.t + 16);
  TEST_ASSERT_EQUAL_STRING("music", face.passing(board.t));
  TEST_ASSERT_TRUE(high - low > 350);  // its head bobbing side to side
  TEST_ASSERT_TRUE(lifted >= 6);       // a bounce on the beat
  TEST_ASSERT_TRUE(lids < 650);        // eyes closed
  TEST_ASSERT_TRUE(pastime);           // and its own life goes on
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
    TEST_ASSERT_TRUE(work.face().owners().small && work.face().owners().eyes != EyesBy::kJam);
    TEST_ASSERT_TRUE(whigh - wlow > 60 && whigh - wlow < 300);  // jamming, smaller
    TEST_ASSERT_EQUAL_INT(255, work.face().engine().with.notes);
  }
}

// Pins the call: still and a little smaller, its eyes half closed and
// still, its muted mic the one mark, its paws at rest though you type; no
// pastime however long; a stretch as it ends. It has the beat over speaking
// and music, and the eyes over the scroll's look.
void test_a_call_keeps_it_still() {
  const uint32_t call = tagBit("oncall"), typing = tagBit("typing"), music = tagBit("music");
  Board board(SceneState::kIdle, kDay | tierBit(3));
  GelFace& face = board.face();
  board.to(1000);
  board.tags(kDay | tierBit(3) | call | typing | music | tagBit("scrolling"));
  bool moved = false;
  board.to(board.t + 300000, [&] { moved = moved || face.pastimes(board.t).playing != Pastime::kNone; });
  TEST_ASSERT_FALSE(moved);
  const Owners& o = face.owners();
  TEST_ASSERT_TRUE(o.beatShows && o.beat == BeatBy::kCall && o.eyes == EyesBy::kCall && o.mark == MarkBy::kMuted);
  TEST_ASSERT_TRUE(!face.pastimes(board.t).tapping && face.engine().with.ticks == 0);
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
    TEST_ASSERT_TRUE(!face.owners().beatShows && face.owners().mark == MarkBy::kNone);
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
    other.to(5000, [&] {
      TEST_ASSERT_FALSE(other.face().owners().with);
      if (other.t > rig::kFadeMs) TEST_ASSERT_EQUAL_INT(0, other.face().engine().with.notes);
    });
  }
  // Asleep, the pointer moves no eye.
  Board asleep(SceneState::kAsleep, kDay);
  asleep.pointer(true, -9, -3);
  asleep.to(3000, [&] { TEST_ASSERT_FALSE(asleep.face().engine().motion.attending); });
  // Holding an agent's card, it's light: the eyes stay its own.
  Board card(SceneState::kIdle, kDay | tagBit("scrolling") | tagBit("scrolldown"));
  CardShow held;
  held.on = true;
  card.face().card(held);
  card.to(3000, [&] { TEST_ASSERT_EQUAL_INT(int(EyesBy::kOwn), int(card.face().owners().eyes)); });
}

// Pins speaking along: another app recording with no camera (`speaking`)
// leans it in and nods on the 1.6 s beat: it has the beat and the mark over
// typing along, whose keys go on (one hand's at its ear, the rig's);
// the mark goes over to the key's ticks as you stop, fading.
void test_speaking_has_the_beat_over_typing() {
  Board board(SceneState::kIdle, kDay | tierBit(1));
  GelFace& face = board.face();
  board.to(1000);
  board.tags(kDay | tierBit(1) | tagBit("typing") | tagBit("speaking"));
  board.to(board.t + 1000);
  TEST_ASSERT_TRUE(face.owners().beat == BeatBy::kSpeaking && face.owners().mark == MarkBy::kEar);
  TEST_ASSERT_EQUAL_STRING("speaking", face.passing(board.t));
  TEST_ASSERT_TRUE(face.pastimes(board.t).tapping);
  TEST_ASSERT_TRUE(face.engine().ear && face.engine().with.heard == 255 && !face.engine().with.ticks);
  board.tags(kDay | tierBit(1) | tagBit("typing"));
  board.to(board.t + 100);
  const Engine::With& w = face.engine().with;
  TEST_ASSERT_TRUE(w.heard > 0 && w.heard < 255 && w.ticks > 0 && w.ticks < 255);  // one fades over the other
  board.to(board.t + 900);
  TEST_ASSERT_EQUAL_INT(0, face.engine().ear);
  TEST_ASSERT_TRUE(face.pastimes(board.t).tapping && w.ticks == 255 && !w.heard);
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
  static_assert(GelFace::kEarSize >= 1350 && GelFace::kEarSize <= 1550, "about 23 to 26 px, as a hand at an ear");
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
  TEST_ASSERT_EQUAL_INT(int(BeatBy::kSpeaking), int(card.face().owners().beat));
  TEST_ASSERT_EQUAL_INT(255, card.face().engine().with.heard);
}

// Pins the one mark beside it (Engine::With), so each reads at a glance:
// the music's notes while music plays, through its pastimes, over typing
// along's ticks and at work in a pose of its own; a muted mic on a call
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
  TEST_ASSERT_TRUE(board.face().pastimes(board.t).tapping && w.notes == 255 && !w.ticks);
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

// The sweep: each part's place as a frame draws it, frame by frame, as the
// facts of you at the Mac come and go, in pairs, on each base, and as
// something takes the body in the middle of music and typing. A part that
// moves further in one frame than today's Moments ever do, or than the
// quickest designed ease where no Moment moves it, has jumped.
namespace {
enum Item { kTicksMark = rig::kChannelCount, kNotesMark, kEarMark, kMutedMark, kNod, kGazeX, kGazeUp, kPawL, kPawR, kLids, kItems };
const char* itemName(int i) {
  static const char* rest[] = {"mark.ticks", "mark.notes", "mark.ear", "mark.muted", "nod",
                               "gazeX",      "gazeUp",     "paw.L",    "paw.R",      "lids"};
  return i < rig::kChannelCount ? rig::kChannelInfo[i].name : rest[i - rig::kChannelCount];
}
struct Probe {
  int v[kItems];
};
// The paws' lift as the desk draws it (render/gel/props.cpp), by its parts.
Probe probe(Board& b) {
  Probe p{};
  GelFace& f = b.face();
  const Engine& e = f.engine();
  const rig::Channels c = f.channels();
  for (int i = 0; i < rig::kChannelCount; ++i) p.v[i] = c.v[i];
  p.v[kTicksMark] = e.with.ticks, p.v[kNotesMark] = e.with.notes, p.v[kEarMark] = e.with.heard;
  p.v[kMutedMark] = e.with.muted, p.v[kNod] = e.faceNod;
  p.v[kGazeX] = (e.motion.gaze * 10000).integer(), p.v[kGazeUp] = (e.motion.gazeUp * 10000).integer();
  const PastimeShow s = f.pastimes(b.t);
  const int desk = (e.scenes.desk.x * 255).integer(), along = s.keys;
  const uint32_t ms = uint32_t(F(e.timeMs()).integer());
  for (int side : {-1, 1})
    p.v[side < 0 ? kPawL : kPawR] =
        std::max(desk, along) > 0
            ? (briskLift(s.pawPhase, side) * s.brisk + (desk >= along ? typeLift(ms, side) : 0) * (1000 - s.brisk)) / 1000
            : 0;
  p.v[kLids] = sleepyLids(e);
  return p;
}
// Whether channel `i` is a rig hand's with nothing to compare across these
// two frames: drawn in only one of them, it has no place in the other; and
// it comes out of the desk's paw, or goes back into it, a frame's step from
// where the paw is (Lively's kDeskX, the motion layer's route from the
// keys), about the paw's size.
bool handover(const Probe& a, const Probe& b, int i) {
  using rig::HandPart;
  for (int side = 0; side < 2; ++side) {
    const int size = int(rig::hand(side, HandPart::kSize));
    if (i < int(rig::hand(side, HandPart::kX)) || i > int(rig::hand(side, HandPart::kGlass))) continue;
    if (a.v[size] && b.v[size]) return false;
    if (i != size) return true;
    const Probe& out = a.v[size] ? a : b;
    return std::abs(std::abs(out.v[int(rig::hand(side, HandPart::kX))]) - Lively::kDeskX) <= 10 &&
           std::abs(out.v[int(rig::hand(side, HandPart::kY))] - Lively::kDeskY) <= 10 &&
           std::abs(out.v[size] - Lively::kDeskSize) <= 150;
  }
  return false;
}

// The most each part moved in a frame, and when.
struct Steps {
  int most[kItems]{}, at[kItems]{};
  Probe last{};
  bool seen = false;
  void add(const Probe& p, uint32_t t) {
    for (int i = 0; seen && i < kItems; ++i)
      if (std::abs(p.v[i] - last.v[i]) > most[i] && !handover(last, p, i))
        most[i] = std::abs(p.v[i] - last.v[i]), at[i] = int(t);
    last = p, seen = true;
  }
  void merge(const Steps& o) {
    for (int i = 0; i < kItems; ++i) most[i] = std::max(most[i], o.most[i]);
  }
};

enum Fact { kTyping, kFast, kSpeaking, kScrollDown, kScrollUp, kPointerMoving, kPointerNear, kMusic, kCall, kFacts };
const char* const kFactNames[] = {"typing", "fast", "speaking", "scrolldown", "scrollup", "pointer", "pointer-near", "music", "call"};
enum Base { kIdleBase, kTypingPose, kOtherPose, kCardHeld, kBases };
const char* const kBaseNames[] = {"idle", "work, typing", "work, looking", "a card"};

struct Run {
  Board board;
  bool on[kFacts]{};
  uint32_t tags;
  Steps steps;
  explicit Run(Base base)
      : board(base == kIdleBase || base == kCardHeld ? SceneState::kIdle : SceneState::kWorking, kDay),
        tags(kDay | tierBit(1) | tagBit("macright")) {
    if (base == kOtherPose) board.m.act = SceneState::kAnalyzing;
    if (base == kCardHeld) {
      CardShow held;
      held.on = true;
      board.face().card(held);
    }
    apply();
  }
  void apply() {
    uint32_t w = tags;
    if (on[kTyping] || on[kFast]) w |= tagBit("typing");
    if (on[kFast]) w |= tagBit("typingfast");
    if (on[kSpeaking]) w |= tagBit("speaking");
    if (on[kScrollDown] || on[kScrollUp]) w |= tagBit("scrolling") | tagBit(on[kScrollDown] ? "scrolldown" : "scrollup");
    if (on[kMusic]) w |= tagBit("music");
    if (on[kCall]) w |= tagBit("oncall");
    board.m.when = reached(w);
    // The pointer swept across, a step every 192 ms, or at the near edge.
    board.m.pointer.on = on[kPointerMoving] || on[kPointerNear];
    board.m.pointer.near = on[kPointerNear];
    board.m.pointer.x = on[kPointerNear] ? 1 : int8_t(-8 + int(board.t / 192 % 17));
    board.m.pointer.y = on[kPointerNear] ? 0 : -3;
    board.state();
  }
  void play(uint32_t ms) {
    board.to(board.t + ms, [&] {
      if (on[kPointerMoving] && board.t % 192 == 0) apply();
      steps.add(probe(board), board.t);
    });
  }
  void set(Fact f, bool value, uint32_t ms = 1500) {
    on[f] = value;
    apply();
    play(ms);
  }
};

void moment(Board& b, SceneState a, Outcome o) {
  app::ReactionIn in;
  in.anim = a, in.outcome = o;
  b.b.play(in, b.t);
}
void needYou(Board& b, bool on) {
  b.m.attn = on, b.m.attnId = 9;
  std::strcpy(b.m.agent, "claude");
  b.state();
}

// Today's Moments, which are fine, on each base: the most each part moves
// in a frame there.
Steps momentsSteps() {
  Steps all;
  for (int base = 0; base < kBases; ++base) {
    Run r{Base(base)};
    Board& b = r.board;
    r.play(1500);
    r.steps = Steps{};
    b.b.tap(b.t, b.rng);
    r.play(3000);
    moment(b, SceneState::kTaskComplete, Outcome::kSuccess);
    r.play(4000);
    moment(b, SceneState::kTaskComplete, Outcome::kFailure);
    r.play(4000);
    b.b.talkOn(b.t, b.rng);
    r.play(3000);
    b.b.talkOff(b.t);
    r.play(2000);
    needYou(b, true);
    r.play(6000);
    needYou(b, false);
    r.play(3000);
    b.m.base = b.m.base == SceneState::kIdle ? SceneState::kWorking : SceneState::kIdle;
    b.state();
    r.play(3000);
    all.merge(r.steps);
  }
  return all;
}

// Each part's limit a frame: a quarter over the Moments' most, and at least
// a tenth of a channel's range, a mark's ramp's (rig::Ramp, 200 ms), the
// scroll's quick look in (GelFace::kLookInMs), the eyes' turn to what
// they attend (Motion::kAttendRate), and a paw's fast tap with a little of
// its blend from the soft typing.
int limitOf(const Steps& moments, int i) {
  const int floor = i < rig::kChannelCount ? (rig::kChannelInfo[i].hi - rig::kChannelInfo[i].lo) / 10
                    : i <= kMutedMark      ? 40
                    : i == kNod            ? 30
                    : i <= kGazeUp         ? 150
                    : i <= kPawR           ? 4 * kBriskLift * 16 / kFastTapMs + 4
                                           : 1;
  return std::max(moments.most[i] + moments.most[i] / 4, floor);
}

void judge(const Steps& moments, const char* base, const char* what, const Steps& s, bool hands = true) {
  for (int i = 0; i < kItems; ++i) {
    // A move's hands are the Moment's own (render/gel/moves.h): the knock
    // slaps the glass in a frame.
    if (!hands && i >= int(rig::Channel::kHandLX) && i <= int(rig::Channel::kHandRGlass)) continue;
    char message[160];
    std::snprintf(message, sizeof message, "%s, %s: %s moved %d in a frame at %d ms, over its %d", base, what,
                  itemName(i), s.most[i], s.at[i], limitOf(moments, i));
    TEST_ASSERT_TRUE_MESSAGE(s.most[i] <= limitOf(moments, i), message);
  }
}
}  // namespace

// Pins rule 2 of who has what: never a cut. On each base, each pair of
// facts of you at the Mac on and off in turn (A, then B, A off, B off), and
// something taking the body in the middle of music and typing: no part of
// the frame moves further in a frame than a Moment's does.
void test_no_part_jumps_when_with_you_changes() {
  const Steps moments = momentsSteps();
  for (int base = 0; base < kBases; ++base)
    for (int a = 0; a < kFacts; ++a)
      for (int b = a + 1; b < kFacts; ++b) {
        // The Mac sends one way of scrolling, never both.
        if (a == kScrollDown && b == kScrollUp) continue;
        Run r{Base(base)};
        r.play(1500);
        r.steps = Steps{};
        r.set(Fact(a), true), r.set(Fact(b), true), r.set(Fact(a), false), r.set(Fact(b), false);
        char what[48];
        std::snprintf(what, sizeof what, "%s then %s", kFactNames[a], kFactNames[b]);
        judge(moments, kBaseNames[base], what, r.steps);
      }
  const char* const kOver[] = {"a poke", "a finish", "needs you", "listening", "a pastime",
                               "sleep",  "cross",    "sad",       "tired",     "a pastime over the jam alone"};
  for (int base : {int(kIdleBase), int(kTypingPose)})
    for (int k = 0; k < 10; ++k) {
      Run r{Base(base)};
      r.on[kMusic] = true, r.on[kTyping] = k != 9;
      r.apply();
      r.play(3000);
      r.steps = Steps{};
      Board& b = r.board;
      switch (k) {
        case 0: b.b.tap(b.t, b.rng); break;
        case 1: moment(b, SceneState::kTaskComplete, Outcome::kSuccess); break;
        case 2: needYou(b, true); break;
        case 3: b.b.talkOn(b.t, b.rng); break;
        case 4:
        case 9: b.face().playPastime(base == kIdleBase ? Pastime::kLookAround : Pastime::kStretch, b.t); break;
        case 5: b.m.base = SceneState::kAsleep, b.state(); break;
        case 6: b.m.mood = Mood::kGrumpy, b.state(); break;
        case 7: b.m.mood = Mood::kSad, b.state(); break;
        case 8: b.m.energy = Energy::kTired, b.state(); break;
      }
      r.play(4000);
      if (k == 2) needYou(b, false);
      if (k == 3) b.b.talkOff(b.t);
      r.play(4000);
      judge(moments, kBaseNames[base], kOver[k], r.steps, k != 2);
    }
}

// Pins rule 1 of who has what: covered, not stopped. The jam's beat runs on
// under the scroll's look, the pointer, typing and speaking, so as each
// leaves the bounce is where it would have been with the music alone; and
// the eyes, open for the scroll's look and the pointer, shut into the jam
// again as each goes.
void test_a_covered_beat_runs_on() {
  for (Fact over : {kScrollDown, kPointerMoving, kTyping, kSpeaking}) {
    Run r{kIdleBase};
    r.set(kMusic, true, 2000);
    r.set(over, true, 1500);
    const Owners o = r.board.face().owners();
    TEST_ASSERT_TRUE(o.beat == (over == kSpeaking ? BeatBy::kSpeaking : BeatBy::kMusic) && o.beatShows);
    if (over == kScrollDown || over == kPointerMoving)
      TEST_ASSERT_TRUE(r.board.channel(rig::Channel::kEyeOpenL) > 900);  // its eyes open, on you
    r.set(over, false, 2000);
    TEST_ASSERT_TRUE(r.board.channel(rig::Channel::kEyeOpenL) < 650);  // and shut in the jam again
    // In step with the music alone, at the same time since it began.
    Run alone{kIdleBase};
    alone.set(kMusic, true, r.board.t);
    char message[64];
    std::snprintf(message, sizeof message, "the jam's lean after %s", kFactNames[over]);
    TEST_ASSERT_INT_WITHIN_MESSAGE(4, alone.board.face().mixer().channels()[rig::Channel::kLean],
                                   r.board.face().mixer().channels()[rig::Channel::kLean], message);
  }
}
