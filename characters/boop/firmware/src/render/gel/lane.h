// The host's lane under the gel: the status strip, or the
// bubble while a line plays, drawn at the panel's own size into the
// surface's bottom fifth, by coverage like the rest of the gel. The same
// content and rules as the canvas's lane (render/screens.h).
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
// canvas's drawStringFit, but ending in one cell's "…". Returns the x after
// it.
int text(Raster& r, const Font& f, int x, int y, const char* s, uint16_t ink, int room = 1 << 20);
// The same text, its cells' top left at (x16, y16), sixteenths of a pixel,
// so a word that moves glides rather than steps: on a whole pixel it's
// text()'s, and between them each pixel takes its four nearest cells'
// coverage, each by how near it is. It touches only the pixels it draws.
void text16(Raster& r, const Font& f, int x16, int y16, const char* s, uint16_t ink);
// The gel's largest font (fonts_gel.h, which only lane.cpp holds): the
// work stream's word forward.
const Font& bubbleFont();

// The strip's marks' inks, as the drawer's rows' (render/gel/drawer.h):
// the working spinner and the numbers in warm white, the idle z in grey.
constexpr uint16_t kWorkingInk = rgb565(kEyeRgb), kIdleInk = rgb565(kNarrationRgb);
// The working count's spinner: kSpinSteps spokes, the lit one a step on
// every kSpinStepMs, a turn a second, and the step it's on at the
// device's time `now`.
constexpr int kSpinSteps = 8, kSpinStepMs = 125;
inline int spinStep(uint32_t now) { return int(now / kSpinStepMs % kSpinSteps); }

// The strip's counts from x to `right`, their middle on row cy: in words
// ("2 working · 1 idle", the to-do list's "3/7" at the right end) when
// they fit, else as marks (a spinner on `spin` and a number, a sleeper's z
// and a number). The agents' drawer carries them up as its lid
// (render/gel/drawer.h). Returns the x after them.
int paintCounts(Raster& r, const Strip& strip, int x, int right, int cy, int spin = 0);
// A session's mark, as the strip shows its count's: the working spinner
// on `spin`, the idle sleeper's z, or needs you's amber dot, in an 18 px box
// from x, its middle on cy.
enum class StatusMark : uint8_t { kWorking, kIdle, kNeedsYou };
void paintStatusMark(Raster& r, StatusMark mark, int x, int cy, int spin = 0);
// The lane's rule from x0 to x1 on row y, with the agents' drawer's
// grabber in its middle when there's a drawer to pull.
void paintRule(Raster& r, int x0, int x1, int y, bool grabber);
// The lane: the rule, and under it one row, which shows the bubble while
// Boop speaks, else the caption (the reaction's reason, the narration, in
// the large font and a light grey), else the strip at its opacity, its
// spinner on `spin`, and at `rowAlpha` (0–255) while a low sign rises over
// it.
void paintLane(Surface& surface, const char* bubble, const Strip& strip, int spin = 0, const char* caption = nullptr,
               int rowAlpha = 255);
// What a lane shows, as a key that's the same exactly when its pixels are
// (never 0): what paintLane records as the surface's laneKey. The spinner
// only turns while sessions work, so only then does its step change it.
uint32_t laneKey(const char* bubble, const Strip& strip, int spin = 0, const char* caption = nullptr,
                 int rowAlpha = 255);
class Engine;
struct PastimeShow;
// A whole frame, as GelFace::draw draws it: the body, with the rig's
// channels on it, the face art, what it wears as the layer stack shows it
// at t, the props, the pastime playing (render/gel/pastimes.h), the work
// stream at `now`, the device's time (render/gel/stream.h: the word
// forward), the card it holds
// (render/gel/card.h; true when it drew it) or the sign it holds up (render/gel/layers.h), then the lane, unless this surface already shows
// it, with the low sign (a finished turn's, render/gel/done.h) in the
// strip's place, and the work's term first in the strip, the counts as marks after it, and over all of it the finished turn's glow. While the agents' drawer shows (render/gel/drawer.h) it takes the
// lane's place, the body pressed flat above it, and the pastimes, the
// stream, the sign and the finished turn wait for it to shut.
bool paintFrame(Surface& surface, const Engine& e, bool mouthOpen, int dy, const char* bubble, const SignShow& sign,
                const Strip& strip, const DoneShow& done = {}, const rig::Channels& rig = rig::kRest,
                const rig::Layers* layers = nullptr,
                uint32_t t = 0, const Stream* stream = nullptr, uint32_t now = 0,
                const PastimeShow* pastimes = nullptr, const Drawer* drawer = nullptr, const char* caption = nullptr,
                const WishShow* wish = nullptr, const CardShow* card = nullptr);
// The widest line the bubble holds on a surface, in px, clear of its
// rounded corners: on the AMOLED's, the longest take (22 glyphs) in the
// sign's font (pinned by test_gel).
int bubbleRoom(const Surface& surface);

// Switching the agent the screen follows (several agents, the screen
// guide's map): the strip's row and the card slide in from the side you
// swiped toward over kSwitchMs while Boop stays, and when the set of
// agents changes two arrows at the strip's ends say there are others to
// swipe to, for kArrowsMs. noteSwitch reads each frame's strip;
// switchDx is how far off, in px, the watched agent's things are now,
// and switchArrows how strong the arrows are (0 … 255).
constexpr uint32_t kSwitchMs = 320, kArrowsMs = 1800;
constexpr int kSwitchPx = 90;
void noteSwitch(const Strip& strip, uint32_t now);
int switchDx(uint32_t now);
int switchArrows(uint32_t now);
// The watched agent's lane slot this frame, with several agents, else -1:
// the desk's monitor is lit in its colour.
int watchedSlot();

}  // namespace render::gel
