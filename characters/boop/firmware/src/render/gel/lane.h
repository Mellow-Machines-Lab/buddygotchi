// The host's lane under the gel: the status strip, or the
// bubble while a line plays, drawn at the panel's own size into the
// surface's bottom fifth, by coverage like the rest of the gel. The same
// content and rules as the canvas's lane (render/screens.h), which the
// pixel face keeps.
#pragma once
#include "render/face.h"
#include "render/drawer.h"
#include "render/font.h"
#include "render/palette.h"
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
// The same text, its cells' top left at (x16, y16), sixteenths of a pixel,
// so a word that moves glides rather than steps: on a whole pixel it's
// text()'s, and between them each pixel takes its four nearest cells'
// coverage, each by how near it is. `behind`: only onto the background's
// black, as words behind the body are. It touches only the pixels it
// draws.
void text16(Raster& r, const Font& f, int x16, int y16, const char* s, uint16_t ink, bool behind = false);
// The bubble's font, the gel's largest (fonts_gel.h, which only lane.cpp
// holds).
const Font& bubbleFont();

// The chips' inks, the strip's working and idle counts' as the drawer's
// rows' (render/gel/drawer.h): the working one's bright, the idle one's
// resting.
constexpr uint16_t kWorkingRing = rgb565(89, 97, 107), kWorkingInk = rgb565(238, 242, 245),
                   kIdleRing = rgb565(51, 58, 66), kIdleInk = rgb565(154, 163, 173);
// The working count's spinner: kSpinSteps spokes, the lit one a step on
// every kSpinStepMs, a turn a second, and the step it's on at the
// device's time `now`.
constexpr int kSpinSteps = 8, kSpinStepMs = 125;
inline int spinStep(uint32_t now) { return int(now / kSpinStepMs % kSpinSteps); }

// The strip's counts (how many work, the helpers, the idle and the to-do
// list), from x, their middle on row cy, the working spinner on `spin`:
// the agents' drawer carries them up as its lid (render/gel/drawer.h).
// Returns the x after them.
int paintCounts(Raster& r, const Strip& strip, int x, int cy, int spin = 0);
// The strip's rule from x0 to x1 on row y, broken in its middle by a
// chevron, pointing up (the drawer under it) or down (it shuts).
void paintRule(Raster& r, int x0, int x1, int y, bool down, uint16_t ink);
// The bubble, or else the strip at its opacity, its spinner on `spin`.
void paintLane(Surface& surface, const char* bubble, const Strip& strip, int spin = 0);
// What a lane shows, as a key that's the same exactly when its pixels are
// (never 0): what paintLane records as the surface's laneKey. The spinner
// only turns while sessions work, so only then does its step change it.
uint32_t laneKey(const char* bubble, const Strip& strip, int spin = 0);
class Engine;
struct PastimeShow;
// A whole frame, as GelFace::draw draws it: the body, with the rig's
// channels on it, the face art, what it wears and the air around it as the
// layer stack shows them at t, the props, the pastimes (render/gel/
// pastimes.h: their scenery behind the body, their kit, and the one
// playing in front), the work stream at `now`, the device's time
// (render/gel/stream.h: its words behind the body, the desk's to-do bar,
// clock and thought cloud, and the word forward), the sign it holds up
// (render/gel/layers.h), the finished turn's ticket, then the lane, unless
// this surface already shows it, and over all of it the finished turn's
// glow (render/gel/done.h). While the agents' drawer shows (render/gel/drawer.h) it takes the
// lane's place, the body pressed flat above it, and the pastimes, the
// stream, the sign, the sky and the finished turn wait for it to shut.
void paintFrame(Surface& surface, const Engine& e, bool mouthOpen, int dy, const char* bubble, const SignShow& sign,
                const Strip& strip, const DoneShow& done = {}, const rig::Channels& rig = rig::kRest,
                const rig::Layers* layers = nullptr,
                uint32_t t = 0, const Stream* stream = nullptr, uint32_t now = 0,
                const PastimeShow* pastimes = nullptr, const Drawer* drawer = nullptr);
// The widest line the bubble holds on a surface, in px, clear of its
// rounded corners: on the AMOLED's, the longest take (22 glyphs) in the
// sign's font, a line of 34 in the small one (pinned by test_gel).
int bubbleRoom(const Surface& surface);

}  // namespace render::gel
