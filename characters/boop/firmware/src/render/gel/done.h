// The finished turn the brain's reaction is about (render::DoneShow), as
// the gel marks it: the panel's rim glowing in its outcome's colour, and,
// once its words have ended, its thread's name held up on the low sign
// (render/gel/low_sign.h). The glow comes as the reaction starts; both go
// once it has lingered (app/behaviour.h), the glow fading out over its last
// second, the sign dropping away.
// Integer, and a function of the DoneShow alone, so the board, the
// simulator and the Mac's mirror draw the same frame.
#pragma once
#include "render/face.h"
#include "render/gel/low_sign.h"
#include "render/surface.h"

namespace render::gel {

// How long the glow takes to come, and to fade as the finished turn goes.
constexpr int kGlowInMs = 300, kGlowOutMs = 1000;
// How far in from the panel's edge the glow reaches, in px, and how strong
// it is at the edge (0–255): a reply's, or a face's with no finish of its
// own, fainter.
constexpr int kGlowPx = 26, kGlowPeak = 200, kGlowPeakFaint = 110;
// Fainter than this, a pixel of it is none: its 565 tail only tints.
constexpr int kGlowFaintest = 12;

// The glow's strength at the panel's edge, 0–255: 0 for none.
int doneGlow(const DoneShow& done);
// The low sign that names it: none until it's up.
LowSign finishSign(const DoneShow& done);
// A celebration's gold (render::SignShow's `gold`): its words on the low
// sign, a star before them, rim and words gold, kGoldAfterMs after the
// reaction starts, so the sign it may come with rises first; and the rim
// glowing gold as a finish's does in its outcome's colour.
constexpr int kGoldAfterMs = 400;
struct GoldShow {
  LowSign sign;
  int glow = 0;  // its strength at the panel's edge, 0–255
};
GoldShow goldShow(const SignShow& sign);

// The glow, on rows [from, to), over whatever's drawn there.
void paintGlow(Surface& surface, const DoneShow& done, int from, int to);
// A glow of `ink` at `peak` (0–255) at the panel's edge: the finished
// turn's, or a celebration's gold.
void paintGlow(Surface& surface, int peak, uint16_t ink, int from, int to);

}  // namespace render::gel
