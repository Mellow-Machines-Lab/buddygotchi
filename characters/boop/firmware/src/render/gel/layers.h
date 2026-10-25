// What the gel wears and holds over its body, drawn natively by coverage
// like the rest of the gel, at the anchors of the pose that drew the body
// (the rig's Anchors, render/gel/painter.h), so each follows the body as it
// moves, squashes and leaves the screen, and is cut off there with it:
//
// - the outfit, by the tags on now (state.when): a nightcap at night, and
//   its gown on the body's lower rings while it sleeps, a party hat on a
//   party day, New Year's Day, Lunar New Year and Programmers' Day, a
//   witch hat at Halloween, a bobble hat in winter; reading glasses while
//   the latest prompt was an essay or for docs, else shades on a Friday's
//   day, both off while it sleeps;
// - the air around it: snow in winter, confetti on a party day and New
//   Year's Day, hearts on Valentine's, and Zs rising while it sleeps at
//   night;
// - the sign a reaction holds up (its `sign`): a dark card held at its
//   front with a little gel hand at either side, the words on it, sliding
//   up as the reaction starts and bobbing while it's held.
//
// A scene may hide a layer: peekaboo's gesture takes the outfit off while
// the slime comes up from nothing. At night its lids also hang a little
// lower (sleepyLids).
#pragma once
#include "render/face.h"
#include "render/gel/painter.h"
#include "render/surface.h"

namespace render::gel {

// Each part of the outfit (the hat, riding the brim's front; the gown,
// riding the hem's front, or else what's over its eyes, riding the left
// eye, since it sleeps with its eyes bare) is drawn into a recording of
// its own (render/gel/raster.h) when its look changes or the body has
// moved it more than kSlack sixteenths of a pixel past a whole number of
// pixels, and blended from it in every other frame: their filled area is
// most of what the layers cost. While the body moves (a
// frame of the same body up to kMovingMs before, and its anchors moved
// within kStillMs), a frame may show a part as it was kept, within kSlack
// of where it is; still, it's drawn where it is, so a still frame is the
// same as drawing it afresh. The nightcap's swing steps every kSwingMs, as
// Pixel's pompom does. A part is kept in a frame as wide as the surface
// and kFrameHeight tall, with the anchor it rides kFrameY down its middle:
// room around for any of them. Past its edges, or the recording's room,
// it's drawn straight on the surface.
struct OutfitLayer {
  static constexpr int kSlack = 12, kSwingMs = 400;
  static constexpr uint32_t kMovingMs = 100, kStillMs = 200;
  static constexpr int kFrameY = 288, kFrameHeight = 512;
  static constexpr int kHatBytes = 5 * 1024, kWornBytes = 7 * 1024;  // the hat's room, and the gown's or eyewear's
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

// The outfit and the air, over the body and its face, under the props.
void paintLayers(Surface& surface, const Engine& e, const rig::Anchors& at);
// How far the card sits below its place `ms` after it went up: sliding up,
// then bobbing.
int signOffset(uint32_t ms);
// The sign, at the body's front (its hands' ring), over everything but
// the lane.
void paintSign(Surface& surface, const SignShow& sign, const rig::Anchors& at);

}  // namespace render::gel
