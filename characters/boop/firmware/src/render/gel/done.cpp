#include "render/gel/done.h"

#include <algorithm>

#include "render/gel/raster.h"
#include "render/maths.h"
#include "render/palette.h"

namespace render::gel {
namespace {

uint16_t inkOf(Outcome o) {
  return o == Outcome::kSuccess ? rgb565(kSageRgb) : o == Outcome::kFailure ? rgb565(kClayRgb) : rgb565(kEyeRgb);
}

uint32_t isqrt(uint32_t v) {
  uint32_t root = 0, bit = 1u << 30;
  while (bit > v) bit >>= 2;
  while (bit) {
    if (v >= root + bit) {
      v -= root + bit;
      root = (root >> 1) + bit;
    } else {
      root >>= 1;
    }
    bit >>= 2;
  }
  return root;
}

}  // namespace

int doneGlow(const DoneShow& d) {
  if (!d.shows()) return 0;
  const int peak = d.outcome == Outcome::kNone ? kGlowPeakFaint : kGlowPeak;
  int g = peak * ease(int(std::min<uint32_t>(d.ms, kGlowInMs)), kGlowInMs) / 1024;
  if (d.leftMs >= 0) g = g * ease(std::min(int(d.leftMs), kGlowOutMs), kGlowOutMs) / 1024;
  return g;
}

LowSign finishSign(const DoneShow& d) {
  LowSign sign;
  if (!d.shows() || d.signMs < 0) return sign;
  sign.text = d.thread && *d.thread ? d.thread : d.agent;
  sign.mark = d.outcome == Outcome::kSuccess   ? LowSign::Mark::kTick
              : d.outcome == Outcome::kFailure ? LowSign::Mark::kCross
                                               : LowSign::Mark::kDots;
  sign.ink = inkOf(d.outcome);
  sign.ms = uint32_t(d.signMs);
  sign.leftMs = d.leftMs;
  sign.oneLine = true;  // under the glow
  if (d.outcome == Outcome::kSuccess) sign.xp = d.xp;
  return sign;
}

GoldShow goldShow(const SignShow& s) {
  GoldShow g;
  if (!s.gold || !*s.gold || s.goldMs < uint32_t(kGoldAfterMs)) return g;
  const uint32_t ms = s.goldMs - kGoldAfterMs;
  g.sign.text = s.gold;
  g.sign.mark = s.goldMark == GoldMark::kRing     ? LowSign::Mark::kRing
                : s.goldMark == GoldMark::kGold   ? LowSign::Mark::kGold
                : s.goldMark == GoldMark::kSilver ? LowSign::Mark::kSilver
                : s.goldMark == GoldMark::kBronze ? LowSign::Mark::kBronze
                                                  : LowSign::Mark::kStar;
  g.sign.ink = rgb565(kGoldRgb);
  g.sign.ms = ms;
  g.sign.leftMs = s.goldLeftMs;
  g.sign.oneLine = true;
  g.glow = kGlowPeak * ease(int(std::min<uint32_t>(ms, kGlowInMs)), kGlowInMs) / 1024;
  if (s.goldLeftMs >= 0) g.glow = g.glow * ease(std::min(int(s.goldLeftMs), kGlowOutMs), kGlowOutMs) / 1024;
  return g;
}

// Each pixel takes the ink by how far in from the panel's edge it is, d:
// (1 - d / kGlowPx)², strongest at the edge. Round the corners that's how
// far in from their arcs; elsewhere from the nearer edge. A row holds it
// only within kGlowPx of an edge, or of a corner's arc. The panel's 565
// colour would show the fade's tail as bands, and a shift of hue where its
// three channels step apart: so each pixel's opacity is moved by a 2 × 2
// ordered dither, half a step either way, and the faintest are none.
void paintGlow(Surface& s, int peak, uint16_t ink, int from, int to) {
  if (!s.pixels || peak <= 2) return;
  const int w = s.width, h = s.height, reach = kGlowPx * 16;
  const int radius = std::clamp(s.corner, 0, std::min(w, h) / 2), r16 = radius * 16;
  uint8_t alphaOf[kGlowPx * 16];
  for (int i = 0; i < reach; ++i) alphaOf[i] = uint8_t(peak * (reach - i) * (reach - i) / (reach * reach));
  // How far in a pixel is, in sixteenths, from its middle; past the reach,
  // or outside the panel, none.
  auto alphaAt = [&](int x, int ey16) {
    const int xc = x * 16 + 8, ex16 = std::min(xc, w * 16 - xc);
    int in;
    if (ex16 < r16 && ey16 < r16) {
      const int cx = r16 - ex16, cy = r16 - ey16;
      in = r16 - int(isqrt(uint32_t(cx * cx + cy * cy)));
    } else {
      in = std::min(ex16, ey16);
    }
    return in < 0 || in >= reach ? 0 : int(alphaOf[in]);
  };
  // The dither's offset at (x, y), and an opacity moved by it.
  static constexpr int kDither[4] = {-6, 2, 6, -2};
  auto dithered = [](int a, int x, int y) {
    if (a < kGlowFaintest) return 0;
    return std::clamp(a + kDither[(y & 1) * 2 + (x & 1)], 0, 255);
  };
  auto blend = [&](uint16_t* px, int a) {
    if (a > 2) *px = mix565(*px, ink, a);
  };
  for (int y = std::max(0, from); y < std::min(h, to); ++y) {
    const int yc = y * 16 + 8, ey16 = std::min(yc, h * 16 - yc);
    uint16_t* row = s.pixels + y * w;
    // How far in the panel's edge is on this row, past its corners.
    int edge = 0;
    if (ey16 < r16) {
      const int cy = r16 - ey16;
      edge = (r16 - int(isqrt(uint32_t(r16 * r16 - cy * cy)))) / 16;
    }
    if (ey16 < reach) {
      // Near the top or the bottom: all of it, the middle at one strength
      // but for the dither, every other pixel at each of its two.
      for (int x = 0; x < radius; ++x) {
        const int a = alphaAt(x, ey16);
        blend(row + x, dithered(a, x, y)), blend(row + w - 1 - x, dithered(a, w - 1 - x, y));
      }
      const int a = alphaOf[ey16];
      if (a >= kGlowFaintest) {
        const Blender even(ink, dithered(a, 0, y)), odd(ink, dithered(a, 1, y));
        for (int x = radius; x < w - radius; ++x) (x & 1 ? odd : even).run(row + x, 1);
      }
      s.touch(0, y, w, y + 1);
      continue;
    }
    const int band = std::min(w / 2, edge + kGlowPx + 1);
    for (int x = 0; x < band; ++x) {
      const int a = alphaAt(x, ey16);
      blend(row + x, dithered(a, x, y)), blend(row + w - 1 - x, dithered(a, w - 1 - x, y));
    }
    s.touch(0, y, band, y + 1);
    s.touch(w - band, y, w, y + 1);
  }
}

void paintGlow(Surface& s, const DoneShow& d, int from, int to) { paintGlow(s, doneGlow(d), inkOf(d.outcome), from, to); }

}  // namespace render::gel
