// The host's lane under the gel: the status strip, or the
// bubble while a line plays, drawn at the panel's own size into the
// surface's bottom fifth, by coverage like the rest of the gel. The same
// content and rules as the canvas's lane (render/screens.h), which the
// pixel face keeps.
#pragma once
#include "render/face.h"
#include "render/font.h"
#include "render/gel/scenes.h"
#include "render/screens.h"
#include "render/surface.h"

namespace render::gel {

struct Raster;
// Text in the fonts' glyphs (render::nextGlyph), its cells' top left at
// (x, y): at most `room` px of it, ending ".." when cut, as the canvas's
// drawStringFit. Returns the x after it.
int text(Raster& r, const Font& f, int x, int y, const char* s, uint16_t ink, int room = 1 << 20);

// The bubble, or else the strip at `alpha` (0 to 255).
void paintLane(Surface& surface, const char* bubble, const Strip& strip, int alpha = 255);
// What a lane shows, as a key that's the same exactly when its pixels are
// (never 0): what paintLane records as the surface's laneKey.
uint32_t laneKey(const char* bubble, const Strip& strip, int alpha = 255);
// The strip, eased in as it comes and out as it goes on the props' 200 ms
// ramp, as the desk comes and goes: one going still shows what it last
// showed, its names copied; while it shows, what it shows changes at once.
class LaneFade {
 public:
  // What to draw at `time` (the engine's ms) for `strip`, and how strongly.
  const Strip& fade(const Strip& strip, T time, int& alpha);

 private:
  Ramp ramp_;
  Strip shown_;
  char names_[5][48]{};
};
class Engine;
// A whole frame, as GelFace::draw draws it: the body, the face art, the
// props, the sign it holds up (render/gel/layers.h), then the lane, its
// strip at `laneAlpha`, unless this surface already shows it.
void paintFrame(Surface& surface, const Engine& e, bool mouthOpen, int dy, const char* bubble, const SignShow& sign,
                const Strip& strip, int laneAlpha = 255);
// The widest line the bubble holds on a surface this wide, in px: the
// longest take (22 glyphs) in its own font, a line of 34 in the large one
// (pinned by test_gel).
int bubbleRoom(int width);

}  // namespace render::gel
