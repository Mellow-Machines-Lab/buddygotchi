// The sign a reaction holds up (its `sign`): a little card under the face,
// gripped by two mitts at its top edge, with the words on it. It slides up
// from the lane as the reaction starts, then bobs now and then while it's
// held. Pure drawing, a function of how long it has shown.
#pragma once
#include <cstdint>

#include "render/canvas.h"

namespace render {

struct Held {
  static constexpr int kBottom = 188;             // the card's bottom edge, over the lane
  static constexpr int kPad = 10;                 // the words from the card's sides
  static constexpr int kSignRoom = 272;           // the widest words in the sign's font, else the large one
  static constexpr int kRisePx = 60, kBobPx = 2;  // its signLift
};

// How far the card sits below its place `ms` after it went up: sliding up,
// then bobbing; and the press's dip.
int heldOffset(uint32_t ms, int dy);
// The card, its mitts and its words, `offset` px below its place, cut off
// at the lane.
void drawHeld(Canvas& c, const char* text, int offset);

}  // namespace render
