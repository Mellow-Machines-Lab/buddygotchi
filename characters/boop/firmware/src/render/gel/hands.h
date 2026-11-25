// The gel's two hands: gel stubs that are part of its body, budding out of
// it when they act and sinking back in. They're drawn in one place
// (paintHand), each a gel disk with a flat pad: a ball, an open palm (at
// most three small fingertips over it) or a fist, tighter, and between; pressed on
// the glass it grows, goes flat and pale, and shows its contact patch, as a
// paw on a window does. There's one pair: each frame says who has each
// hand (HandsPlan), and only that one draws it, in its place among the
// frame's drawing.
//
// - a move (the rig's hand channels, a clip's: render/gel/moves.h): the
//   invite's palm, the knock, the flop;
// - a sign or a card held up, a hand gripping either side (gripping);
// - the low sign, held up by its top corners (holdingUp);
// - speaking along with you, one cupped at its ear (cupped);
// - the desk, a pad flat on the keys, typing (onKeys);
// - the agents' drawer, one hung over the sheet's edge (hung).
//
// Pure functions of their numbers, so the board, the simulator and the
// Mac's mirror draw the same.
#pragma once
#include <cstdint>

#include "render/gel/raster.h"
#include "render/rig/rig.h"

namespace render::gel {

// The radius of a whole hand (the rig's size 1000), px on the panel at the
// body's own size. Pressed on the glass it's kHandGlassGrow (Q12) bigger
// again: a palm on the glass is about 85 px across.
constexpr int kHandPx = 17, kHandGlassGrow = 6144;

struct Hand {
  int x16 = 0, y16 = 0;  // its middle, sixteenths of a pixel
  int radius16 = 0;      // off the glass; none under a pixel
  int shape = 0;         // Q12: a fist (-4096), a ball (0), an open palm (4096)
  int glass = 0;         // Q12: how flat on the glass it's pressed
  int flat = 0;          // Q12: a pad resting on something, wider and lower
  int turn = 0;          // 4096ths of a turn its fingertips are turned from up
  int alpha = 255;
  bool shown() const { return radius16 >= 16 && alpha > 0; }
  // Its radius drawn, the glass's growth in.
  int drawn16() const { return radius16 + int(int64_t(radius16) * kHandGlassGrow / 4096 * glass / 4096); }
};

// Who holds each hand this frame.
enum class HandsAt : uint8_t { kAny, kNone, kMove, kSign, kCard, kLowSign, kEar, kDesk, kDrawer };
// Each hand's (0 the left, 1 the right). kAny, as a frame starts and in a
// test that draws one part alone: that part draws its own.
struct HandsPlan {
  HandsAt at[2] = {HandsAt::kAny, HandsAt::kAny};
  // The rig's hands this frame, as the body's drawing found them (paint).
  Hand moved[2];
  // Whether a part may draw hand `side` (-1 or 0 the left, 1 the right).
  bool has(int side, HandsAt who) const {
    const HandsAt a = at[side > 0 ? 1 : 0];
    return a == who || a == HandsAt::kAny;
  }
};
// The plan of the frame being drawn (paintFrame says it): each part asks it
// before drawing a hand.
HandsPlan& handsPlan();

// A hand: the one way one is drawn, within the raster's bounds and rows.
void paintHand(Raster& r, const Hand& h);

// The poses. A hand gripping a held card's or sign's side at (x, y), px, on
// `side` (-1 left); `px` its radius.
Hand gripping(int x, int y, int side, int px);
// Holding the low sign up by its top corner at (x, y), px.
Hand holdingUp(int x, int y, int side, int px);
// Cupped at its ear on `side`, by the body's anchors.
Hand cupped(const rig::Anchors& at, int side);
// A pad flat on the keys at (x, y), px: its middle; `px` its radius.
Hand onKeys(int x, int y, int px);
// Hung over the drawer's sheet at (x, y), px, its fingertips down.
Hand hung(int x, int y);
// The rig's hand `side` (0 left, 1 right): its channels from the body's
// front low down (`at`'s handF), at the body's scale (Q12).
Hand fromRig(const rig::Channels& c, const rig::Anchors& at, int side, int scale);

}  // namespace render::gel
