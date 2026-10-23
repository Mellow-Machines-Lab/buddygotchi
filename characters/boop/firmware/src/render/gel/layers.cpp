#include "render/gel/layers.h"

#include <initializer_list>

#include "render/font.h"
#include "render/gel/lane.h"
#include "render/gel/raster.h"
#include "render/palette.h"

namespace render::gel {

namespace {

// The props' colours (render/gel/props.cpp): a card's ink and rim, its
// words, and the helpers' gel for the hands.
constexpr uint16_t kCardInk = rgb565(27, 55, 78), kCardRim = rgb565(0x78, 0xa4, 0xc8);
constexpr uint16_t kWords = rgb565(184, 233, 245), kGel = rgb565(89, 169, 224), kShine = rgb565(184, 233, 245);

}  // namespace

int signOffset(uint32_t ms) {
  if (ms < SignLayer::kRiseMs) {  // up from behind the lane, easing out
    const int left = int(SignLayer::kRiseMs - ms);
    return 90 * left * left / int(SignLayer::kRiseMs * SignLayer::kRiseMs);
  }
  const int n = int((ms - SignLayer::kRiseMs) % SignLayer::kBobEveryMs);  // a little lift now and then
  if (n >= int(SignLayer::kBobMs)) return 0;
  return -4 * SignLayer::kBobPx * n * (int(SignLayer::kBobMs) - n) / int(SignLayer::kBobMs * SignLayer::kBobMs);
}

void paintSign(Surface& s, const SignShow& sign, int dy) {
  if (!s.pixels || !sign.text) return;
  Raster r{s};
  const int bottom = s.height * 4 / 5;  // the lane's top: shapes stop there
  const Font& f = kSign;
  const int tw = glyphCount(sign.text) * f.w, w = tw + 2 * SignLayer::kPad, h = f.h + 10;
  const int x = (s.width - w) / 2, y = bottom - SignLayer::kGap - h + signOffset(sign.ms) + dy;
  r.round(x, y, w, h, 12, kCardInk);
  r.ring(x, y, w, h, 12, 2, kCardRim);
  text(r, f, x + SignLayer::kPad, y + 5, sign.text, kWords);
  // A little gel hand at either side, gripping it.
  for (int side : {-1, 1}) {
    const int hx = side < 0 ? x : x + w, hy = y + h / 2;
    r.disk(hx, hy, 12, kGel);
    r.alpha = 160;
    r.disk(hx - 4, hy - 5, 3, kShine);
    r.alpha = 255;
  }
}

}  // namespace render::gel
