#include "render/canvas.h"

#include <cstring>

#include "render/maths.h"

namespace render {

Dither Dither::fade(int mix, bool incoming) {
  const uint8_t at = uint8_t(clamp((mix * 16 + 500) / 1000, 0, 16));
  return incoming ? Dither{0, at} : Dither{at, 16};
}

Dither Dither::within(Dither outer) const {
  const int span = outer.hi - outer.lo;
  return {uint8_t(outer.lo + span * lo / 16), uint8_t(outer.lo + span * hi / 16)};
}

void Canvas::fill(uint8_t color) { std::memset(px_, color, size_t(kWidth) * kHeight); }

static_assert(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__, "a row's four pixels are a word's bytes, the first lowest");

void Canvas::fillRect(int x, int y, int w, int h, uint8_t color, Dither d) {
  const int x0 = x < 0 ? 0 : x, y0 = y < 0 ? 0 : y;
  const int x1 = x + w > kWidth ? kWidth : x + w, y1 = y + h > kHeight ? kHeight : y + h;
  if (x1 <= x0 || d.lo >= d.hi) return;
  const uint32_t ink = color * 0x01010101u;
  for (int row = y0; row < y1; ++row) {
    uint8_t* p = px_ + row * kWidth;
    if (d.all()) {
      std::memset(p + x0, color, size_t(x1 - x0));
      continue;
    }
    // The row's four columns the dither draws, a byte of the word each, so
    // a word of four pixels takes the ink where they're set.
    uint32_t drawn = 0;
    for (int k = 0; k < 4; ++k) drawn |= d.draws(k, row) ? 0xFFu << (8 * k) : 0;
    int i = x0;
    for (; i < x1 && (i & 3); ++i)
      if (d.draws(i, row)) p[i] = color;
    for (; i + 4 <= x1; i += 4) {
      uint32_t word;
      std::memcpy(&word, p + i, 4);
      word = (word & ~drawn) | (ink & drawn);
      std::memcpy(p + i, &word, 4);
    }
    for (; i < x1; ++i)
      if (d.draws(i, row)) p[i] = color;
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
      if (edge(x0, y0, x1, y1, x, y) >= 0 && edge(x1, y1, x2, y2, x, y) >= 0 && edge(x2, y2, x0, y0, x, y) >= 0) {
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
