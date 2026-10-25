// What the gel wears and holds over its body, drawn natively by coverage
// like the rest of the gel, at the anchors of the pose that drew the body
// (the rig's Anchors, render/gel/painter.h), so each follows the body as it
// moves, squashes and leaves the screen, and is cut off there with it:
//
// - the sky behind it: at night a crescent moon and twinkling stars, in
//   the morning the sun up on its left, glowing, its rays turning, only
//   where nothing else is drawn;
// - the outfit, by the tags on now (state.when): a striped nightcap at
//   night, and its pyjamas on the body's lower rings but while it wears
//   reading glasses, a party hat on a party day, New Year's Day, Lunar New
//   Year and Programmers' Day, a witch hat at Halloween, a bobble hat in
//   winter; reading glasses while the latest prompt was an essay or for
//   docs, else shades on a Friday's day, both off while it sleeps;
// - the air around it: snow in winter, confetti on a party day and New
//   Year's Day, hearts on Valentine's;
// - beside it: Zs rising while it sleeps at night, or its coffee, steaming
//   in a little gel hand, while it's idle or at work in the morning;
// - the sign a reaction holds up (its `sign`): a dark card held at its
//   front with a little gel hand at either side, the words on it, sliding
//   up as the reaction starts and bobbing while it's held.
//
// Each comes and goes through the rig's layer stack (render/rig/layers.h,
// the face's), so the sky, a hat and the pyjamas at midnight, the Zs as
// it falls asleep, shades on a Friday and the snow each fade over the
// rig's fade, and a new one waits for the old to go; the sign fades out
// at the opacity Behaviour gives it. A scene may hide a layer: peekaboo's
// gesture takes the outfit off while the slime comes up from nothing. At
// night its lids also hang a little lower (sleepyLids).
#pragma once
#include "render/face.h"
#include "render/gel/painter.h"
#include "render/rig/layers.h"
#include "render/surface.h"

namespace render::gel {

// Each part of the outfit (the hat, riding the brim's front; the pyjamas,
// riding the hem's front, or else what's over its eyes, riding the left
// eye, since it sleeps with its eyes bare) is drawn into a recording of
// its own (render/gel/raster.h) when its look changes or the body has
// changed its shape (its anchors moved apart from the one it rides) by
// more than kSlack sixteenths of a pixel, and blended from it in every
// other frame, moved to the sixteenth with the anchor it rides
// (Raster::replay16): their filled area is most of what the layers cost.
// While the body moves (a frame of the same body up to kMovingMs before,
// and its anchors moved within kStillMs), a frame may show a part in the
// shape it was kept, within kSlack of its own; still, it's drawn where it
// is unless it moved whole pixels in the same shape, so a still frame is
// the same as drawing it afresh. The nightcap's swing steps every kSwingMs, as
// Pixel's pompom does. A part is kept in a frame as wide as the surface
// and kFrameHeight tall, with the anchor it rides kFrameY down its middle:
// room around for any of them. Past its edges, or the recording's room,
// it's drawn straight on the surface.
struct OutfitLayer {
  static constexpr int kSlack = 12, kSwingMs = 400, kSipMs = 9000;
  static constexpr uint32_t kMovingMs = 100, kStillMs = 200;
  static constexpr int kFrameY = 288, kFrameHeight = 512;
  static constexpr int kHatBytes = 7 * 1024, kWornBytes = 10 * 1024;  // the hat's room, and the pyjamas' or eyewear's
};

struct SignLayer {
  static constexpr int kPad = 20;                 // the words from the card's sides, clear of the hands
  static constexpr int kGap = 4;                  // the card's bottom over the lane, at the lowest
  static constexpr int kRisePx = 90, kBobPx = 3;  // its signLift
};

// How far its lids hang at night (Q12, as PaintControls::blink): 0 by day,
// and on the sleeping face, whose eyes are shut anyway: easing out as the
// awake face squashes shut, and back as it wakes.
constexpr int kNightLids = 1100;
class Engine;
int sleepyLids(const Engine& e);

// What the layer stack's layers (render/rig/layers.h) show for the
// engine's tags and state now: the sky behind it (the night's, or the
// morning's sun), what it wears over its eyes or on its body (worn)
// and its hat, each a content of its own (0 for none), the air's bits, and
// beside it the Zs while it sleeps at night, or its coffee while it's idle
// or at work in the morning.
enum : uint32_t { kNightSky = 1, kSun = 2 };
enum : uint32_t { kZs = 1, kCoffeeMug = 2 };
struct Contents {
  uint32_t scene, worn, hat, air, beside;
};
Contents layerContents(const Engine& e);
// The outfit, the air and the Zs, over the body and its face, under the
// props: what the stack shows at t, at its layers' opacities; with none,
// whole in what the engine's tags and state call for.
void paintLayers(Surface& surface, const Engine& e, const rig::Anchors& at, const rig::Layers* layers = nullptr,
                 uint32_t t = 0);
// The night sky, as the stack shows it at t (whole in the engine's tags
// with none), behind everything: drawn last, only onto the background's
// black, so the body, what it wears, the stream's words and the sign all
// stay in front, and none of it is drawn over them.
void paintSky(Surface& surface, const Engine& e, const rig::Layers* layers = nullptr, uint32_t t = 0);
// How far the card sits below its place `ms` after it went up: sliding up,
// then bobbing.
int signOffset(uint32_t ms);
// The sign, at the body's front (its hands' ring), over everything but
// the lane.
void paintSign(Surface& surface, const SignShow& sign, const rig::Anchors& at);

}  // namespace render::gel
