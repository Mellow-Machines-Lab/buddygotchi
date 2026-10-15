// The needs-you sign: Boop holds up an amber sign that
// fills the screen, with who's asking in large type, and peeks over its top
// edge, ducking and popping up at the left corner, the right, then the
// middle. It replaces the mood's needs-you design; the design's sounds
// still play. Pure drawing, a function of the time since the request came.
#pragma once
#include <cstdint>

#include "render/canvas.h"
#include "render/screens.h"

namespace render {

struct Sign {
  // Timings, in ms from the request.
  static constexpr uint32_t kHoldMs = 500;         // the whole face first
  static constexpr uint32_t kRiseMs = 550;         // the sign comes up and the head shrinks behind it
  static constexpr uint32_t kSettledMs = 1200;     // the nudges and hops start
  static constexpr uint32_t kNudgeEveryMs = 3600;  // the sign bumps up, the alert
  static constexpr uint32_t kNudgeMs = 350;
  static constexpr int kNudgePx = 5;
  static constexpr uint32_t kHopMs = 4200;  // the head stays in one spot this long
  static constexpr uint32_t kDuckMs = 300;  // at a spot's end it ducks behind the sign
  static constexpr uint32_t kPopMs = 350;   // and pops up at the next
  // The sign, settled, and the head's spots along its top edge.
  static constexpr int kLeft = 8, kTop = 48, kWidth = 304, kHeight = 188;
  static constexpr int kSpots = 3;
  static constexpr int kSpotX[kSpots] = {64, 256, 160};  // left corner, right corner, the middle
  static constexpr int kHeadY = 43;      // the head's centre when it peeks
  static constexpr int kHeadScale = 29;  // its size then, in 64ths of the whole face
  static constexpr int kPad = 16;        // the sign's text from its edges
};

// Where everything is at one moment. Two equal poses draw the same pixels
// for the same text, so the device skips redrawing an unchanged one.
struct SignPose {
  int16_t signY = 0;         // the sign's top
  int16_t headX = 0, headY = 0;  // the face's centre
  uint8_t scale = 64;        // the face's size in 64ths
  int8_t glance = 0;         // the eyes look left (-1), ahead or right (1)
  bool eyesShut = false;     // a blink
  bool whole = true;         // the cheeks and mouth show, before the sign hides them
  bool hands = false;        // the mitts on the sign's top edge, either side of the head
  int16_t handX = 0, handY = 0;  // the spot the mitts are for, and their top
  bool operator==(const SignPose& o) const {
    return signY == o.signY && headX == o.headX && headY == o.headY && scale == o.scale && glance == o.glance &&
           eyesShut == o.eyesShut && whole == o.whole && hands == o.hands && handX == o.handX && handY == o.handY;
  }
};

// The pose `ms` after the request, with the device's blink and press dip.
SignPose signPose(uint32_t ms, bool eyesShut = false, int dy = 0);
// The needs-you screen: the strip until the sign covers it, the head, the
// sign over it with the strip's agent, thread (else project) and "+N more",
// and the mitts either side of the head.
void drawSignScreen(Canvas& c, const SignPose& p, const Strip& s);

}  // namespace render
