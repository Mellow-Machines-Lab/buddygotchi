// The animation bank's designs as the device draws them: a scene for each
// mood, state and variation, from characters/pixel/firmware/include/faces.h, which
// characters/pixel/tools/facegen/facegen.py generates from the designs' SVGs. A
// scene is rectangles in groups that move, show and change colour in
// steps on the scene's own clock, so the device draws each design as the
// SVG does. The few things the device adds of its own are in SceneShow.
#pragma once
#include <cstdint>

#include "render/types.h"
#include "render/canvas.h"
#include "render/screens.h"

namespace render {

// Each mood has its own variations of each state's design, 1 to kMaxVariants
// of them; a variation is 0..variants(m, s) - 1 here, and 1..variants(m, s)
// on the wire. One out of range draws the first.
constexpr int kMaxVariants = 12;  // faces.h checks it
int variants(Mood m, SceneState s);

// The moods the designs draw, by name (faces.h's), whatever the character
// pack's order: pixelIndex(m) is m's place among them, -1 for one they
// don't draw; pixelMood(i) is the i-th of the pixelMoods().
int pixelMoods();
int pixelIndex(Mood m);
Mood pixelMood(int i);

Outcome variantOutcome(Mood m, SceneState s, int variant);  // the first's for one out of range
StartCtx variantCtx(Mood m, SceneState s, int variant);
// The variations (from 0) of m's design for s that fit an outcome and a
// context, kNone fitting any, in order into `out` (room for kMaxVariants),
// and how many; every variation when none fits, as the Mac's
// FaceLoops.variants does.
int fitting(Mood m, SceneState s, Outcome o, StartCtx c, uint8_t* out);

// A flip-book, one of the new moods' designs, blinks in a step of its own on
// its own clock, so the device's blinks leave it be.
bool blinksItself(Mood m, SceneState s, int variant);
// The show draws the design's closed eyes: the first pack's, or a
// flip-book's blink step; or the design has no eyes to open, as the first
// pack's asleep and no app.
bool eyesClosed(const SceneShow& s);

// Everything a scene's pixels depend on: the scene, the additions, and
// where each group sits, whether it shows and its fill. Two shows with the
// same frame draw the same pixels, so the device skips drawing one whose
// frame hasn't changed. A step to the same place (the
// designs often hold a value over several steps) leaves the frame as it was.
struct SceneFrame {
  static constexpr int kMaxGroups = 288;  // groups in a scene; faces.h checks it
  uint16_t scene = 0xFFFF;
  // The talking "o": where it goes, and its colour, which is never black;
  // -1, -1 and black while the mouth doesn't talk.
  int16_t talkX = -1, talkY = -1;
  uint8_t talkInk = 0;
  int16_t x[kMaxGroups] = {}, y[kMaxGroups] = {};  // 0 while the group doesn't show
  uint8_t on[kMaxGroups] = {};
  uint8_t fill[kMaxGroups] = {};
};
bool operator==(const SceneFrame& a, const SceneFrame& b);
inline bool operator!=(const SceneFrame& a, const SceneFrame& b) { return !(a == b); }

// The scene a mood, state and variation show: some are shared, such as
// asleep and no app, which look the same in every mood.
int sceneOf(Mood m, SceneState s, int variant = 0);
// How long that design takes to play once through, in ms (faces.h's
// loopMs): what a moment's loops count.
uint32_t loopMs(Mood m, SceneState s, int variant = 0);
SceneFrame sceneFrame(const SceneShow& s);
// Draws a frame sceneFrame made over what's on the canvas; the screen
// clears it first. The device draws the frame it compared, so it lays each
// frame out once. The show's overload, for the tests, lays one out.
void drawScene(Canvas& c, const SceneFrame& f);
inline void drawScene(Canvas& c, const SceneShow& s) { drawScene(c, sceneFrame(s)); }
// The palette entry for a design colour (faces::kColors), for the tests.
uint8_t sceneInk(int color);

// The face as its design shows it, and the bubble with the line's text
// (its take's, in amber) when there's one, else the strip. The face is a
// frame sceneFrame made, or a show for the tests, as drawScene takes it.
void drawFaceScreen(Canvas& c, const SceneFrame& face, const char* bubble, const Strip& s);
inline void drawFaceScreen(Canvas& c, const SceneShow& face, const char* bubble, const Strip& s) {
  drawFaceScreen(c, sceneFrame(face), bubble, s);
}

}  // namespace render
