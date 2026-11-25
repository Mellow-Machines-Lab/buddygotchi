// The card an agent handed Boop to hold (render/face.h's CardShow, the
// Mac's `state.card`): one main thing in the sign's font, read from a chair,
// and at most one small line under it, on a dark card rimmed in its agent's
// lane colour, a little gel hand at either side.
//
// THE SCREEN'S RULE for a card: it's part of Doing, as the work stream is.
// It's drawn only while nothing above Doing has the screen (needs you,
// listening, a Moment and its sign, an ask, a low sign, the drawer), which
// Behaviour::cardShow and paintFrame decide, and it comes back after. While
// Boop holds one its hands are full: no pastime is dealt and it doesn't type
// along (GelFace), and it stands up on the card (cardHop), so the
// card never covers its face. With more than one card to show, a row of dots
// under it says how many and which this is; a swipe across the card asks the
// Mac for the next, and a tap opens it (app/device.cpp).
#pragma once
#include "render/face.h"
#include "render/gel/painter.h"
#include "render/rig/rig.h"
#include "render/surface.h"

namespace render::gel {

struct CardLayout {
  // The words from the card's sides, clear of the hands; the card's bottom
  // over the lane; the hands' radius; their outer edges from the panel's
  // sides; and the row under the card for the dots, when there's more than
  // one.
  static constexpr int kPad = 20, kGap = 4, kHand = 12, kEdge = 8, kDotsRow = 14, kDot = 3;
  // It comes up over this long, from this far down.
  static constexpr uint32_t kRiseMs = 220;
  static constexpr int kRisePx = 28;
  // The narrowest card, hands' middles to middles.
  static constexpr int kMinWide = 200;
};

// The card's height on the surface, with its small line or without.
int cardHeight(const CardShow& card);
// How far the body stands up for the card it holds, in px: so the whole
// card, and its dots, fit under its mouth and above the lane; easing up as
// the card comes.
int cardHop(const CardShow& card);
// Where the card is on the surface, as paintCard draws it at rest.
Box cardBox(const Surface& surface, const CardShow& card);
// The card, over the body's front and under nothing but the lane.
void paintCard(Surface& surface, const CardShow& card, int dx = 0);

}  // namespace render::gel
