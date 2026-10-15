// The host's lane under the gel: the status strip, or the
// bubble while a line plays, drawn at the panel's own size into the
// surface's bottom fifth, by coverage like the rest of the gel. The same
// content and rules as the canvas's lane (render/screens.h), which the
// pixel face keeps.
#pragma once
#include "render/screens.h"
#include "render/surface.h"

namespace render::gel {

void paintLane(Surface& surface, const char* bubble, const Strip& strip);
// What a lane shows, as a key that's the same exactly when its pixels are
// (never 0): what paintLane records as the surface's laneKey.
uint32_t laneKey(const char* bubble, const Strip& strip);
class Engine;
// A whole frame, as GelFace::draw draws it: the body, the face art, the
// props, then the lane unless this surface already shows it.
void paintFrame(Surface& surface, const Engine& e, bool mouthOpen, int dy, const char* bubble, const Strip& strip);
// The widest line the bubble holds on a surface this wide, in px: the
// longest take (22 glyphs) in its own font, a line of 34 in the large one
// (pinned by test_gel).
int bubbleRoom(int width);

}  // namespace render::gel
