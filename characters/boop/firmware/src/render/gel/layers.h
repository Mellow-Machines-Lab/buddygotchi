// What the gel wears and holds over its body, drawn natively by coverage
// like the rest of the gel, at the anchors of the pose that drew the body
// (render/gel/painter.h's Anchors), so each follows the body as it moves,
// squashes and leaves the screen, and is cut off there with it:
//
// - the outfit, by the tags on now (state.when): a nightcap at night, a
//   party hat on a party day, New Year's Day, Lunar New Year and
//   Programmers' Day, a witch hat at Halloween, a bobble hat in winter,
//   and shades on a Friday's day;
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

struct SignLayer {
  static constexpr int kPad = 20;                 // the words from the card's sides, clear of the hands
  static constexpr int kGap = 4;                  // the card's bottom over the lane, at the lowest
  static constexpr int kRisePx = 90, kBobPx = 3;  // its signLift
};

// How far its lids hang at night (Q12, as PaintControls::blink): 0 by day,
// and asleep, when they're shut anyway.
constexpr int kNightLids = 1100;
class Engine;
int sleepyLids(const Engine& e);

// The outfit and the air, over the body and its face, under the props.
void paintLayers(Surface& surface, const Engine& e, const Anchors& at);
// How far the card sits below its place `ms` after it went up: sliding up,
// then bobbing.
int signOffset(uint32_t ms);
// The sign, at the body's front (its hands' ring), over everything but
// the lane.
void paintSign(Surface& surface, const SignShow& sign, const Anchors& at);

}  // namespace render::gel
