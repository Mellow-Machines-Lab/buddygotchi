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
// One ink at one opacity over many pixels, as mix565 blends each, with the
// ink's share worked out once.
struct Blender {
  uint16_t ink;
  int alpha;
  uint32_t keep, inkPair, inkGreen;
  Blender(uint16_t i, int a)
      : ink(i),
        alpha(a),
        keep(uint32_t(255 - a)),
        inkPair(((uint32_t(i & 31) | (uint32_t(i & 0xf800) << 5)) * uint32_t(a)) + 0x00800080),
        inkGreen(((i >> 5) & 63) * uint32_t(a) + 128) {}
  void run(uint16_t* out, int n) const {
    if (alpha >= 253) {
      std::fill(out, out + n, ink);
      return;
    }
    if (alpha <= 2) return;
    for (int x = 0; x < n; ++x) {
      const uint16_t old = out[x];
      uint32_t pair = (uint32_t(old & 31) | (uint32_t(old & 0xf800) << 5)) * keep + inkPair;
      pair = ((pair + ((pair >> 8) & 0x00ff00ff)) >> 8) & 0x001f001f;
      uint32_t green = ((old >> 5) & 63) * keep + inkGreen;
      green = (green + (green >> 8)) >> 8;
      out[x] = uint16_t((pair & 31) | ((pair >> 5) & 0xf800) | (green << 5));
    }
  }
};
// Shapes kept instead of drawn (Raster::recording), to blend again where
// they were or a whole number of pixels away (Raster::replay), as they'd
// have blended there: each row's span, its ink, and each pixel's opacity
// as the shape would have blended it, run-length coded, into the owner's
// `data`. It holds at most `room` bytes; a shape past that is lost, and the
// recording is `full`.
struct Recording {
  uint8_t* data;
  int room;
  int used = 0;
  bool full = false;
  Box box;  // the pixels its spans cover
  void clear() { used = 0, full = false, box = {1 << 30, 1 << 30, -(1 << 30), -(1 << 30)}; }
  // A row's span [x0, x1], each pixel's opacity `alpha[x]` (0–255).
  void add(int y, int x0, int x1, const uint8_t* alpha, uint16_t ink);
};

// Looks of one thing cross-fading (render/gel/art.cpp's eyes and mouth
// between arts of different shapes): each look's shapes kept in the order
// they'd be drawn (Raster::recording), then blended once (Raster::blend),
// each pixel taking every look laid over it alone, by the look's weight.
// Drawn one over the other instead, two looks covering a pixel at half
// weight each would let a quarter of what's under them show through.
struct CrossFade {
  static constexpr int kMaxLooks = 4, kMaxShapes = 32;
  uint8_t* data;
  int room;
  int looks = 0, shapes = 0;
  int weight[kMaxLooks]{};  // each look's share, 0–4096; they sum to at most 4096
  int lookOf[kMaxShapes]{};
  Recording shape[kMaxShapes]{};
  // Out of room or shapes: some shape wasn't kept, so it can't be blended.
  bool full = false;
  void clear() { looks = shapes = 0, full = false; }
  // The next look, at its weight.
  void look(int w) {
    if (looks == kMaxLooks) {
      full = true;
      return;
    }
    weight[looks++] = w;
  }
  // Where the look's next shape is kept, or nullptr when there's no room.
  Recording* next() {
    if (!looks || shapes == kMaxShapes) return full = true, nullptr;
    const int taken = used();
    Recording& r = shape[shapes];
    r.data = data + taken, r.room = room - taken, r.clear();
    lookOf[shapes++] = looks - 1;
    return &r;
  }
  bool kept() const {
    for (int i = 0; i < shapes; ++i)
      if (shape[i].full) return false;
    return !full;
  }
  int used() const { return shapes ? int(shape[shapes - 1].data - data) + shape[shapes - 1].used : 0; }
};
// The face art's room for its cross-fading groups' looks: twice what any
// two arts' eyes, mouth, tears or cheeks take at the face's own size (pinned
// in test_gel). Past it, as at a finish's zoom, they're drawn one over the
// other.
constexpr int kCrossingBytes = 12 * 1024;

struct Raster {
  // The widest surface a row of coverage holds.
  static constexpr int kMaxWidth = 512;
  Surface& s;
  int alpha = 255;  // the shape's opacity, 0–255, times each pixel's coverage
  // How much of everything drawn on the surface shows, 0–255: a layer's
  // opacity (render/rig/layers.h), times each shape's. A recording keeps
  // its shapes whole, and a replay blends them at it.
  int fade = 255;
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
  // What `f` kept, blended into the surface once, at the fade: each pixel
  // becomes the sum of each look's shapes laid over it, by the look's
  // weight, and of itself by what's left of the weight.
  void blend(const CrossFade& f);
  // The same, `dx16`, `dy16` sixteenths of a pixel away, so what's kept
  // glides with what it rides: on a whole pixel it's replay(); between,
  // each shape's opacities (its spans of one ink, a row apiece down it)
  // are sampled between its four nearest kept pixels, weighted by how near
  // (bilinear), and blended once a pixel.
  void replay16(const Recording& r, int dx16, int dy16);

  void touch(int x0, int y0, int x1, int y1) {
    if (!recording) s.touch(x0, y0, x1, std::min(y1, bottom()));
  }
  void pixel(int x, int y, uint16_t ink) {
    if (x >= std::max(0, bounds.x0) && x < std::min(s.width, bounds.x1) && y >= std::max(0, bounds.y0) &&
        y < std::min(bottom(), bounds.y1)) {
      auto& out = s.pixels[y * s.width + x];
      const int a = shown(alpha);
      if (a >= 253)
        out = ink;
      else if (a > 2)
        out = mix565(out, ink, a);
    }
  }

  // A filled polygon that doesn't cross itself, cut to a clip polygon when
  // there is one: each pixel takes the area of it the polygon covers,
  // exactly, so an edge moving a sixteenth of a pixel moves its ink by a
  // sixteenth, at any slope.
  void polygon16(const Point* v, int n, uint16_t ink, const Point* clip = nullptr, int clipCount = 0);
  // A polyline `width16` wide, with round joins and caps.
  void stroke16(const Point* v, int n, int width16, uint16_t ink);
  void disk16(int x16, int y16, int radius16, uint16_t ink) {
    Point centre{x16, y16};
    stroke16(&centre, 1, 2 * radius16, ink);
  }

  // A sleeper's z, `h16` tall and 7/8 as wide, its bottom left corner at
  // (x16, y16): a top bar, a diagonal and a bottom bar in one rounded pen a
  // fifth of its height, so it grows and drifts by sixteenths, where a
  // font's z steps a whole pixel and jumps between sizes.
  void zee(int x16, int y16, int h16, uint16_t ink) {
    const int pen = std::max(16, h16 / 5), in = pen / 2, w16 = h16 * 7 / 8;
    const Point v[] = {
        {x16 + in, y16 - h16 + in}, {x16 + w16 - in, y16 - h16 + in}, {x16 + in, y16 - in}, {x16 + w16 - in, y16 - in}};
    stroke16(v, 4, pen, ink);
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
            const int b = cells[xx >> 1], a = shown(alphaOf[xx & 1 ? b & 15 : b >> 4]);
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
  // An opacity as the surface takes it, at the fade.
  int shown(int a) const { return fade >= 255 ? a : a * fade / 255; }
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
