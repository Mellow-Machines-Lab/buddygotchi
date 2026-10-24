// The gel face's 2D drawing: the face art, the props and
// their text, over the projected body. Every shape is drawn by coverage:
// each pixel takes the share of its area the shape covers, once, so edges
// are smooth and a translucent shape never darkens where its parts meet.
// Integer only, so the board and the simulator match pixel for pixel.
// Coordinates named ...16 are sixteenths of a pixel (the art's projected
// points); the plain ones are whole pixels, as the props lay them out.
#pragma once
#include "render/surface.h"
#include "render/palette.h"
#include "render/font.h"
#include "render/rig/rig.h"
#include <algorithm>
#include <cstring>
namespace render::gel {
using Point = rig::Point;
inline uint16_t mix565(uint16_t old, uint16_t ink, int alpha) {
  // Round to the closest RGB565 channel value. At either end, the maximum
  // possible channel change is 2*63/255 < 0.5, so no blend is necessary.
  if (alpha >= 253) return ink;
  if (alpha <= 2) return old;
  const uint32_t a = alpha, b = 255 - a;
  auto rb = [](uint16_t v) { return uint32_t(v & 31) | (uint32_t(v & 0xf800) << 5); };
  uint32_t pair = rb(old) * b + rb(ink) * a + 0x00800080;
  pair = ((pair + ((pair >> 8) & 0x00ff00ff)) >> 8) & 0x001f001f;
  uint32_t green = ((old >> 5) & 63) * b + ((ink >> 5) & 63) * a + 128;
  green = (green + (green >> 8)) >> 8;
  return uint16_t((pair & 31) | ((pair >> 5) & 0xf800) | (green << 5));
}
// Shapes kept instead of drawn (Raster::recording), to blend again where
// they were or a whole number of pixels away (Raster::replay), as they'd
// have blended there: each row's span, its ink, and each pixel's opacity
// as the shape would have blended it, run-length coded. It holds at most
// kBytes; a shape past that is lost, and the recording is `full`.
struct Recording {
  static constexpr int kBytes = 10 * 1024;
  uint8_t data[kBytes];
  int used = 0;
  bool full = false;
  Box box;  // the pixels its spans cover
  void clear() { used = 0, full = false, box = {1 << 30, 1 << 30, -(1 << 30), -(1 << 30)}; }
  // A row's span [x0, x1], each pixel's opacity `alpha[x]` (0–255).
  void add(int y, int x0, int x1, const uint8_t* alpha, uint16_t ink);
};

struct Raster {
  // The widest surface a row of coverage holds.
  static constexpr int kMaxWidth = 512;
  Surface& s;
  int alpha = 255;  // the shape's opacity, 0–255, times each pixel's coverage
  // The first row not drawn: 0 for the face and its props, which stop
  // above the host's lane, the bottom fifth; the lane's own drawing sets
  // the surface's height (render/gel/lane.cpp).
  int limit = 0;
  // Every shape draws only inside it, as a kept card draws just what it
  // must again (render/gel/props.cpp).
  static constexpr Box kEverywhere{0, 0, 1 << 30, 1 << 30};
  Box bounds = kEverywhere;
  // When set, the shapes (but text) are kept in it, not drawn: the surface
  // is left as it was.
  Recording* recording = nullptr;
  // What `r` kept, blended into the surface `dx`, `dy` pixels from where
  // it was kept, inside the bounds: pixel for pixel what its shapes would
  // have drawn there, had they been drawn that far over.
  void replay(const Recording& r, int dx, int dy);

  void touch(int x0, int y0, int x1, int y1) {
    if (!recording) s.touch(x0, y0, x1, std::min(y1, bottom()));
  }
  void pixel(int x, int y, uint16_t ink) {
    if (x >= std::max(0, bounds.x0) && x < std::min(s.width, bounds.x1) && y >= std::max(0, bounds.y0) &&
        y < std::min(bottom(), bounds.y1)) {
      auto& out = s.pixels[y * s.width + x];
      if (alpha >= 253)
        out = ink;
      else if (alpha > 2)
        out = mix565(out, ink, alpha);
    }
  }

  // A filled polygon (even-odd), cut to a clip polygon when there is one.
  // Four sub-rows a pixel row, with exact coverage across each span's ends.
  void polygon16(const Point* v, int n, uint16_t ink, const Point* clip = nullptr, int clipCount = 0);
  // A polyline `width16` wide, with round joins and caps.
  void stroke16(const Point* v, int n, int width16, uint16_t ink);
  void disk16(int x16, int y16, int radius16, uint16_t ink) {
    Point centre{x16, y16};
    stroke16(&centre, 1, 2 * radius16, ink);
  }

  // Whole-pixel shapes for the props. A disk of radius r covers the pixels
  // whose centres are within r of (x, y)'s centre, as before, now with
  // soft edges; a line is `width` pixels wide between the two centres.
  void disk(int x, int y, int radius, uint16_t ink) {
    disk16(x * 16 + 8, y * 16 + 8, std::max(1, radius) * 16 + 8, ink);
  }
  void line(Point a, Point b, int width, uint16_t ink) {
    Point ends[2] = {{a.x * 16 + 8, a.y * 16 + 8}, {b.x * 16 + 8, b.y * 16 + 8}};
    stroke16(ends, 2, std::max(1, width) * 16, ink);
  }
  // A polygon of up to 16 pixel centres.
  void polygon(const Point* v, int n, uint16_t ink) {
    Point centres[16];
    n = std::min(n, 16);
    for (int i = 0; i < n; ++i) centres[i] = {v[i].x * 16 + 8, v[i].y * 16 + 8};
    polygon16(centres, n, ink);
  }
  // The rectangle [x, x + w) × [y, y + h) with corners of `radius`.
  void round(int x, int y, int w, int h, int radius, uint16_t ink);
  // Only its outline, `line` px wide inside its edge, its corners keeping
  // the width: the inside is left as it was, so a box over black costs its
  // edge alone (the gel's lane).
  void ring(int x, int y, int w, int h, int radius, int line, uint16_t ink);

  void text(const char* value, int cx, int cy, uint16_t ink, const Font& font = kSmall) {
    const int w = std::max(1, int(font.w) * s.width / 502), h = std::max(1, int(font.h) * s.height / 410);
    const int len = int(std::strlen(value)), rowBytes = (font.w + 1) / 2, old = alpha;
    int x = cx - len * w / 2, y = cy - h / 2;
    touch(x, y, x + len * w, y + h);
    // At the font's own size each cell's coverage (0–15) is a pixel's
    // alpha, and a glyph is cut to the bounds once, not pixel by pixel.
    int alphaOf[16];
    for (int c = 0; c < 16; ++c) alphaOf[c] = old * c / 15;
    const int rowFrom = std::max({0, -y, bounds.y0 - y}), rowTo = std::min({h, bottom() - y, bounds.y1 - y});
    for (int i = 0; i < len; ++i, x += w) {
      unsigned char ch = value[i];
      int g = ch >= 32 && ch <= 126 ? ch - 32 : '?' - 32;
      const auto* src = font.data + g * rowBytes * font.h;
      if (w == font.w && h == font.h) {
        const int colFrom = std::max({0, -x, bounds.x0 - x}), colTo = std::min({w, s.width - x, bounds.x1 - x});
        for (int yy = rowFrom; yy < rowTo; ++yy) {
          const uint8_t* cells = src + yy * rowBytes;
          uint16_t* out = s.pixels + (y + yy) * s.width + x;
          for (int xx = colFrom; xx < colTo; ++xx) {
            const int b = cells[xx >> 1], a = alphaOf[xx & 1 ? b & 15 : b >> 4];
            if (a >= 253)
              out[xx] = ink;
            else if (a > 2)
              out[xx] = mix565(out[xx], ink, a);
          }
        }
        continue;
      }
      for (int yy = 0; yy < h; ++yy)
        for (int xx = 0; xx < w; ++xx) {
          int sum = 0, count = 0;
          for (int sy = yy * font.h / h; sy < (yy + 1) * font.h / h; ++sy)
            for (int sx = xx * font.w / w; sx < (xx + 1) * font.w / w; ++sx) {
              int b = src[sy * rowBytes + sx / 2];
              sum += sx & 1 ? b & 15 : b >> 4;
              ++count;
            }
          if (sum && count) {
            alpha = old * sum / (15 * count);
            pixel(x + xx, y + yy, ink);
          }
        }
    }
    alpha = old;
  }

 private:
  int bottom() const { return limit ? limit : s.height * 4 / 5; }
  // Nowhere to draw a shape: no pixels, and no recording.
  bool off() const { return !s.pixels && !recording; }
  // Composites the row's coverage where it was written, and zeroes it.
  void flush(int y, uint16_t ink);
  // Blends [x0, x1] of a row, wholly covered, with the ink.
  void fill(int y, int x0, int x1, uint16_t ink);
  // Blends one row's coverage (0–256 a pixel) for [x0, x1] with the ink.
  void composite(int y, int x0, int x1, const uint16_t* coverage, uint16_t ink);
};
}  // namespace render::gel
