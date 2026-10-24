#include "render/canvas.h"

#include <cstring>

#include "render/maths.h"

namespace render {

// The dither's thresholds, a 4 × 4 Bayer matrix: a picture with a share of
// them draws its pixels spread evenly.
constexpr uint8_t kBayer[4][4] = {{0, 8, 2, 10}, {12, 4, 14, 6}, {3, 11, 1, 9}, {15, 7, 13, 5}};

Dither Dither::fade(int mix, bool incoming) {
  const uint8_t at = uint8_t(clamp((mix * 16 + 500) / 1000, 0, 16));
  return incoming ? Dither{0, at} : Dither{at, 16};
}

Dither Dither::within(Dither outer) const {
  const int span = outer.hi - outer.lo;
  return {uint8_t(outer.lo + span * lo / 16), uint8_t(outer.lo + span * hi / 16)};
}

bool Dither::draws(int x, int y) const {
  const uint8_t k = kBayer[y & 3][x & 3];
  return k >= lo && k < hi;
}

void Canvas::fill(uint8_t color) { std::memset(px_, color, size_t(kWidth) * kHeight); }

void Canvas::fillRect(int x, int y, int w, int h, uint8_t color) {
  int x0 = x < 0 ? 0 : x, y0 = y < 0 ? 0 : y;
  int x1 = x + w > kWidth ? kWidth : x + w, y1 = y + h > kHeight ? kHeight : y + h;
  for (int row = y0; row < y1; ++row) {
    if (x1 > x0) std::memset(px_ + row * kWidth + x0, color, size_t(x1 - x0));
  }
}

static int64_t edge(int ax, int ay, int bx, int by, int px, int py) {
  return int64_t(bx - ax) * (py - ay) - int64_t(by - ay) * (px - ax);
}

void Canvas::fillTriangle(int x0, int y0, int x1, int y1, int x2, int y2, uint8_t color) {
  if (edge(x0, y0, x1, y1, x2, y2) < 0) {  // make the winding consistent
    int tx = x1, ty = y1;
    x1 = x2, y1 = y2, x2 = tx, y2 = ty;
  }
  int minX = x0 < x1 ? (x0 < x2 ? x0 : x2) : (x1 < x2 ? x1 : x2);
  int maxX = x0 > x1 ? (x0 > x2 ? x0 : x2) : (x1 > x2 ? x1 : x2);
  int minY = y0 < y1 ? (y0 < y2 ? y0 : y2) : (y1 < y2 ? y1 : y2);
  int maxY = y0 > y1 ? (y0 > y2 ? y0 : y2) : (y1 > y2 ? y1 : y2);
  if (minX < 0) minX = 0;
  if (minY < 0) minY = 0;
  if (maxX >= kWidth) maxX = kWidth - 1;
  if (maxY >= kHeight) maxY = kHeight - 1;
  for (int y = minY; y <= maxY; ++y) {
    for (int x = minX; x <= maxX; ++x) {
      if (edge(x0, y0, x1, y1, x, y) >= 0 && edge(x1, y1, x2, y2, x, y) >= 0 &&
          edge(x2, y2, x0, y0, x, y) >= 0) {
        px_[y * kWidth + x] = color;
      }
    }
  }
}

uint32_t Canvas::hash(int x, int y, int w, int h) const {
  uint32_t v = 2166136261u;
  for (int row = y; row < y + h; ++row) {
    // Aligned: the canvas is malloc'd, and kWidth and x are multiples of 4.
    const uint8_t* p = static_cast<const uint8_t*>(__builtin_assume_aligned(px_ + row * kWidth + x, 4));
    for (int i = 0; i < w; i += 4) {
      uint32_t word;
      std::memcpy(&word, p + i, 4);
      // Each step is a bijection, so one changed word always changes the
      // hash; the shift carries a change in the top bits back down, where
      // the multiply alone would let two of them cancel.
      v = (v ^ word) * 0x9E3779B1u;
      v ^= v >> 16;
    }
  }
  return v;
}

Span Changes::band(const Canvas& canvas, int b) {
  Span s{kWidth, 0};
  for (int t = 0; t < kWidth / kTile; ++t) {
    uint32_t h = canvas.hash(t * kTile, b * kBand, kTile, kBand);
    if (!seen_[b] || h != hashes_[b][t]) {
      if (s.x0 > t * kTile) s.x0 = t * kTile;
      s.x1 = (t + 1) * kTile;
    }
    hashes_[b][t] = h;
  }
  seen_[b] = true;
  return s.empty() ? Span{} : s;
}

}  // namespace render
