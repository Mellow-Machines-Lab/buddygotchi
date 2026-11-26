// Where the gel looks by itself: THE SCREEN'S RULE, part three (parts one
// and two are render/gel/layers.h and pastimes.h). Who has the eyes is
// render/gel/owners.h's: this is where they go, given that. Your pointer:
// while it moves and the Mac knows where the board sits (`state.ptr`), its
// eyes follow it, as you see the board beside the screen, further the
// further it is, up to kPointerReach; at the edge of the screen nearest the
// board, right at it, to the Mac's side. While you speak, to the Mac's side,
// where the sound comes from. Its own gaze rests forward, and
// turns to one thing at a time, for a reason you can name, held long enough
// to read and never darting, the first that applies:
//
// 1. Something needs you: it looks up at you for kNoticeMs, then turns to
//    the Mac, on the side the Mac says it's on (the `macleft` or `macright`
//    tag), or up at it (`macup`), and stays turned while it waits. With
//    none told, it rests.
// 2. Typing along with you (render/gel/face.h), idle or at work, while its
//    paws tap: down at the keys, so no glances then: heads down, as you are.
// 3. Thinking with you: a stretch of typing along of kThinkAfterMs or more
//    has just stopped, and it looks up at you for kThinkMs, then rests.
//
// Any other owner of the eyes rests the gaze: the scroll's look and the
// jam's shut eyes are the face's, a pose's or a call's its clip's. The face
// gathers the facts (GelFace::showGaze) and the engine turns the eyes
// (Engine::attend), slower than they follow a finger.
#pragma once
#include <cstdint>

#include "render/gel/owners.h"

namespace render::gel {

// What there is to look at now.
struct GazeFacts {
  EyesBy eyes = EyesBy::kOwn;  // who has them (owners.h)
  bool needsYou = false;  // the needs-you look, shown for lookMs
  uint32_t lookMs = 0;
  int mac = 0;            // the Mac's side: -1 left, 1 right, 0 not told
  bool up = false;        // the Mac above it (`macup`), with no side
  bool along = false;     // typing along with you, its paws tapping
  bool thinking = false;  // a long stretch of typing along stopped, thinkMs ago
  uint32_t thinkMs = 0;
  bool pointerNear = false;  // the way to your pointer (state.ptr)
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
  // height, down at the keys, and up at the screen above it; how far across
  // and up or down the pointer takes the eyes each of its steps (state.ptr's
  // 10 at the furthest), and how far to the side the pointer at the edge
  // nearest the board does.
  static constexpr int kYouY = -160, kMacReach = 420, kEyesY = 205, kKeysY = 400, kMidX = 251, kScreenUpY = -320;
  static constexpr int kPointerReach = 10, kPointerX = 57, kPointerY = 48, kNearReach = 560;
  GazePoint look(const GazeFacts& f, uint32_t t);
  void reset() { *this = Gaze{}; }
};

}  // namespace render::gel
