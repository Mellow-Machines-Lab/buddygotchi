// Where the gel looks by itself: THE SCREEN'S RULE, part three (parts one
// and two are render/gel/layers.h and pastimes.h). Its eyes rest forward,
// and turn to one thing at a time, for a reason you can name, held long
// enough to read and never darting:
//
// 1. Something needs you: it looks up at you for kNoticeMs, then turns to
//    the Mac, on the side the Mac says it's on (the `macleft` or `macright`
//    tag), or up at it (`macup`), and stays turned while it waits. With
//    none told, it rests.
// 2. Typing along with you (render/gel/face.h), idle or at work, while its
//    paws tap: down at the keys, so no glances then: heads down, as you are.
// 3. Thinking with you: a stretch of typing along of kThinkAfterMs or more
//    has just stopped, and it looks up at you for kThinkMs, then rests.
// 4. At work in an activity's own pose, looking, running or waiting: rest.
//    The pose's clip moves the eyes itself (the rig's gazeX and gazeY: down
//    a page, fixed on the monitor, out at you), and a glance on top would
//    pull against it. One it was in the middle of is dropped.
// 5. On a call (the `oncall` tag), with you at the Mac (GelFace::showWithYou):
//    rest. It keeps still.
// 6. The pointer: while your pointer moves and the Mac knows where the board
//    sits (`state.ptr`), its eyes follow it, as you see the board beside the
//    screen: further the further it is, up to kPointerReach. At the edge of
//    the screen nearest the board, it looks right at it, to the Mac's side.
//    Let go once the Mac stops sending it (still 3 s): rest.
// 7. Reading along while you scroll (the `scrolling` tag, showWithYou):
//    at the page, to the Mac's side, or up at it, or forward with none told;
//    the line-by-line travel down and back is its clip's (`read-along`).
// 8. A video with you (the `video` tag): to the Mac's side at the eyes'
//    height, or up at it, and still.
//
// At work, typing, with none of these: forward, at rest.
//
// The first that applies wins, and none applies while anything else has
// the eyes: a finger, a Moment, a pastime, a transition, a word forward,
// sleep. A new kind of look is one more rule here and nothing anywhere
// else: the face gathers the facts (GelFace::showGaze) and the engine turns
// the eyes (Engine::attend), slower than they follow a finger.
#pragma once
#include <cstdint>

namespace render::gel {

// What it does with you at the Mac besides typing along, the one the face
// shows (GelFace::showWithYou), lowest first.
enum class WithYou : uint8_t { kNone, kMusic, kVideo, kReading, kSpeaking, kCall };

// What there is to look at now.
struct GazeFacts {
  bool free = false;      // the look shows, and nothing else has the eyes
  bool needsYou = false;  // the needs-you look, shown for lookMs
  uint32_t lookMs = 0;
  int mac = 0;            // the Mac's side: -1 left, 1 right, 0 not told
  bool up = false;        // the Mac above it (`macup`), with no side
  bool along = false;     // typing along with you, its paws tapping
  bool thinking = false;  // a long stretch of typing along stopped, thinkMs ago
  uint32_t thinkMs = 0;
  bool posed = false;                         // at work in a pose whose clip has the eyes: looking, running, waiting
  WithYou with = WithYou::kNone;              // what it does with you besides
  bool pointer = false, pointerNear = false;  // the way to your pointer (state.ptr)
  int pointerX = 0, pointerY = 0;
};

// A point to look at, in the screen's px (it may be off the screen), or
// nothing: rest.
struct GazePoint {
  bool on = false;
  int x = 0, y = 0;
};

class Gaze {
 public:
  static constexpr uint32_t kNoticeMs = 1200;
  // Thinking with you: after typing along this long, it looks up this long.
  static constexpr uint32_t kThinkAfterMs = 8000, kThinkMs = 2000;
  // Where the points are: up at you, off to the Mac's side at the eyes'
  // height, down at the keys, and up at the screen above it; the reading's
  // page to the Mac's side, or up; how far across and up or down the
  // pointer at its furthest (state.ptr's 10) takes the eyes.
  static constexpr int kYouY = -160, kMacReach = 420, kEyesY = 205, kKeysY = 400, kMidX = 251, kScreenUpY = -320;
  static constexpr int kPageReach = 300, kPageY = 300, kPageUpY = -60;
  static constexpr int kPointerReach = 10, kPointerX = 42, kPointerY = 36;
  GazePoint look(const GazeFacts& f, uint32_t t);
  void reset() { *this = Gaze{}; }
};

}  // namespace render::gel
