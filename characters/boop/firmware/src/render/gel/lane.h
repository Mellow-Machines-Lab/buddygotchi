// The host's lane under the gel: the status strip, or the
// bubble while a line plays, drawn at the panel's own size into the
// surface's bottom fifth, by coverage like the rest of the gel. The same
// content and rules as the canvas's lane (render/screens.h), which the
// pixel face keeps.
#pragma once
#include "render/face.h"
#include "render/font.h"
#include "render/rig/layers.h"
#include "render/screens.h"
#include "render/stream.h"
#include "render/surface.h"

namespace render::gel {

struct Raster;
// Text in the fonts' glyphs (render::nextGlyph), its cells' top left at
// (x, y): at most `room` px of it, cut as render::cutAt cuts it, as the
// canvas's drawStringFit. Returns the x after it.
int text(Raster& r, const Font& f, int x, int y, const char* s, uint16_t ink, int room = 1 << 20);
// The bubble's font, the gel's largest (fonts_gel.h, which only lane.cpp
// holds).
const Font& bubbleFont();

// The bubble, or else the strip at its opacity.
void paintLane(Surface& surface, const char* bubble, const Strip& strip);
// What a lane shows, as a key that's the same exactly when its pixels are
// (never 0): what paintLane records as the surface's laneKey.
uint32_t laneKey(const char* bubble, const Strip& strip);
class Engine;
struct PastimeShow;
// A whole frame, as GelFace::draw draws it: the body, with the rig's
// channels on it, the face art, what it wears and the air around it as the
// layer stack shows them at t, the props, the pastimes (render/gel/
// pastimes.h: their scenery behind the body, their kit, and the one
// playing in front), the work stream at `now`, the device's time
// (render/gel/stream.h: its words behind the body, the desk's to-do bar,
// clock and thought cloud, and the word forward), the sign it holds up
// (render/gel/layers.h), then the lane, unless this surface already shows
// it.
void paintFrame(Surface& surface, const Engine& e, bool mouthOpen, int dy, const char* bubble, const SignShow& sign,
                const Strip& strip, const rig::Channels& rig = rig::kRest, const rig::Layers* layers = nullptr,
                uint32_t t = 0, const Stream* stream = nullptr, uint32_t now = 0,
                const PastimeShow* pastimes = nullptr);
// The widest line the bubble holds on a surface, in px, clear of its
// rounded corners: on the AMOLED's, the longest take (22 glyphs) in the
// sign's font, a line of 34 in the small one (pinned by test_gel).
int bubbleRoom(const Surface& surface);

}  // namespace render::gel
