#include "render/pixel/held.h"

#include <initializer_list>

#include "render/font.h"
#include "render/palette.h"
#include "render/pixel/scene.h"
#include "render/screens.h"

namespace render {

int heldOffset(uint32_t ms, int dy) {
  int offset = dy;
  if (ms < Held::kRiseMs) {  // up from behind the lane, easing out
    const int left = int(Held::kRiseMs - ms);
    offset += 60 * left * left / int(Held::kRiseMs * Held::kRiseMs);
  } else {  // a little lift now and then, a parabola
    const int n = int((ms - Held::kRiseMs) % Held::kBobEveryMs);
    if (n < int(Held::kBobMs))
      offset -= 4 * Held::kBobPx * n * (int(Held::kBobMs) - n) / int(Held::kBobMs * Held::kBobMs);
  }
  return offset;
}

void drawHeld(Canvas& c, const char* text, int offset) {
  const Font& f = glyphCount(text) * kSign.w <= Held::kSignRoom ? kSign : kLarge;
  const int tw = stringWidth(f, text), w = tw + 2 * Held::kPad + 4, h = f.h + 8;
  const int left = (kWidth - w) / 2, top = Held::kBottom - h + offset;
  const uint8_t edge = inkAt(kInkEye, kLevels), mitt = sceneInk(1);
  // The card: black inside a 2 px edge with stepped corners, as the bubble.
  constexpr int L = 2;
  c.fillRect(left + 2 * L, top, w - 4 * L, h, edge);
  c.fillRect(left + L, top + L, w - 2 * L, h - 2 * L, edge);
  c.fillRect(left, top + 2 * L, w, h - 4 * L, edge);
  c.fillRect(left + 2 * L, top + L + 1, w - 4 * L, h - 2 * L - 2, kBlack);
  c.fillRect(left + L + 1, top + 2 * L, w - 2 * L - 2, h - 4 * L, kBlack);
  drawString(c, f, left + Held::kPad + 2, top + 4, text, kInkEye);
  // The mitts gripping its top edge near either end: three knuckles each.
  for (int x : {left + 8, left + w - 22}) {
    for (int i = 0; i < 3; ++i) {
      c.fillRect(x + i * 5, top - 6, 4, 11, mitt);
      c.fillRect(x + i * 5 + 1, top - 7, 2, 1, mitt);
    }
  }
  // Rising, it comes up from behind the lane.
  if (top + h > kLaneTop) c.fillRect(left, kLaneTop, w, top + h - kLaneTop, kBlack);
}

}  // namespace render
