// What the gel holds up and wears over its body, drawn natively over the
// body, its face and its props: the sign a reaction holds up (its `sign`),
// a dark card in front of the body's lower half with a little gel hand at
// either side, the words on it. It slides up as the reaction starts, then
// bobs now and then while it's held. Pure drawing, by coverage like the
// rest of the gel.
#pragma once
#include "render/face.h"
#include "render/surface.h"

namespace render::gel {

struct SignLayer {
  static constexpr int kPad = 20;  // the words from the card's sides, clear of the hands
  static constexpr int kGap = 4;   // the card's bottom over the lane
  static constexpr uint32_t kRiseMs = 220;
  static constexpr uint32_t kBobEveryMs = 1400, kBobMs = 350;
  static constexpr int kBobPx = 3;
};

// How far the card sits below its place `ms` after it went up: sliding up,
// then bobbing.
int signOffset(uint32_t ms);
void paintSign(Surface& surface, const SignShow& sign, int dy);

}  // namespace render::gel
