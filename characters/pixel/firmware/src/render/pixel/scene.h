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
constexpr int kMaxVariants = 16;  // faces.h checks it
int variants(Mood m, SceneState s);

// The moods the designs draw, by name (faces.h's), whatever the character
// pack's order: pixelIndex(m) is the place among them of the one m wears
// (faces.h's kWears), -1 for a mood faces.h doesn't name; pixelMood(i) is
// the i-th of the pixelMoods().
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
// Whether a variation may show now: every tag it needs is on in `when`
// (render/tags.h) and its look has shown its wait (`lookMs`). And whether
// it needs a tag at all: an occasion's, which the face prefers while it fits.
bool fits(Mood m, SceneState s, int variant, uint32_t when, uint32_t lookMs);
bool tagged(Mood m, SceneState s, int variant);

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
  // Where the face that shows is among the groups, kMaxGroups for none: a
  // faceless frame's rig face is drawn there (drawScene's `from` and `to`).
  uint16_t faceAt = kMaxGroups;
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

// A rectangle's pixels that `d` (render/canvas.h) draws, in `color`.
void fillDithered(Canvas& c, int x, int y, int w, int h, uint8_t color, Dither d);
// The small "o" the mouth becomes while a take is loud, at x, y (its top
// left corner), in `ink`.
constexpr int kTalkW = 14, kTalkH = 12;
void drawTalk(Canvas& c, int x, int y, uint8_t ink, Dither d = {});

// The scene a mood, state and variation show: some are shared, such as
// asleep and no app, which look the same in every mood.
int sceneOf(Mood m, SceneState s, int variant = 0);
// How long that design takes to play once through, in ms (faces.h's
// loopMs): what a moment's loops count.
uint32_t loopMs(Mood m, SceneState s, int variant = 0);
// Whether that design's face is its mood's resting face moved, under
// decorations of its own (a sparkle, a falling tear), as facegen found at
// every step: the rig face draws it in the design's place
// (render/pixel/rig_face.h), as drawn (idle's plain face, near enough).
// And where the face is, in px from where the mood's first idle has it, at
// the show's moment: its move, and its eyes' more.
bool rigFaced(Mood m, SceneState s, int variant = 0);
struct FaceMove {
  int dx = 0, dy = 0, ex = 0, ey = 0;
};
FaceMove faceMove(const SceneShow& s);
// `faceless`, the face that shows is left out but for its decorations, for
// the rig face to draw in its place, and so are its blink and talking.
SceneFrame sceneFrame(const SceneShow& s, bool faceless = false);
// Draws a frame sceneFrame made over what's on the canvas, the pixels `d`
// draws, its groups from `from` up to `to`; the screen clears it first.
// The device draws the frame it compared, so it lays each frame out once.
// The show's overload lays one out.
void drawScene(Canvas& c, const SceneFrame& f, Dither d = {}, int from = 0, int to = SceneFrame::kMaxGroups);
inline void drawScene(Canvas& c, const SceneShow& s, Dither d = {}) { drawScene(c, sceneFrame(s), d); }
// The palette entry for a design colour (faces::kColors).
uint8_t sceneInk(int color);

// What's drawn over the face: what it wears and the air around it, when it
// dresses (render/pixel/outfit.h: for `when`, in `mood`, at `ms`, `hatX`
// and `hatY` px from its place, as the rig face moves), and the sign it
// holds up, when there's one (`held`, `heldOffset` px below its place:
// render/pixel/held.h).
struct Overlays {
  bool dressed = false;
  Mood mood = kStartupMood;
  uint32_t when = 0, ms = 0;
  int hatX = 0, hatY = 0;
  const char* held = nullptr;
  int heldOffset = 0;
};
// The overlays over a face drawn, then the bubble with the line's text (its
// take's, in amber) when there's one, else the strip.
void drawOverlays(Canvas& c, const char* bubble, const Strip& s, const Overlays& over);
// The face as its design shows it, on black, and drawOverlays. The face is
// a frame sceneFrame made, or a show for the tests, as drawScene takes it.
void drawFaceScreen(Canvas& c, const SceneFrame& face, const char* bubble, const Strip& s, const Overlays& over = {});
inline void drawFaceScreen(Canvas& c, const SceneShow& face, const char* bubble, const Strip& s,
                           const Overlays& over = {}) {
  drawFaceScreen(c, sceneFrame(face), bubble, s, over);
}

}  // namespace render
