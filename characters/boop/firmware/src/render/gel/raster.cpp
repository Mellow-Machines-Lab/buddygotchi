#include "render/gel/raster.h"

#include <climits>
#include <cstring>

#include "render/gel/geometry.h"

namespace render::gel {

namespace {

// One row's coverage, 0–256 a pixel. Drawing is single-threaded and each
// shape composites its rows before the next begins.
// It's all zero between rows; [touchedLo, touchedHi] is what a row wrote.
uint16_t coverage[Raster::kMaxWidth];
int touchedLo = Raster::kMaxWidth, touchedHi = -1;
// A row's opacities for a recording (Raster::recording).
uint8_t kept[Raster::kMaxWidth];
void touched(int x) { touchedLo = std::min(touchedLo, x), touchedHi = std::max(touchedHi, x); }

// Floor division by 16 that's right for negative coordinates too.
int floor16(int v) { return v >= 0 ? v / 16 : -((15 - v) / 16); }

// A polygon's edges that reach a pixel row, as pairs of point indices.
int rowEdges(const Point* v, int n, int y, uint8_t (*edges)[2]) {
  int count = 0;
  const int top = y * 16, under = top + 16;
  for (int i = 0, j = n - 1; i < n; j = i++)
    if (std::max(v[i].y, v[j].y) > top && std::min(v[i].y, v[j].y) < under) {
      edges[count][0] = uint8_t(i), edges[count][1] = uint8_t(j);
      ++count;
    }
  return count;
}

// Where those edges cross the horizontal line at y16, sorted.
int crossings(const Point* v, const uint8_t (*edges)[2], int n, int y16, int* hits) {
  int count = 0;
  for (int k = 0; k < n; ++k) {
    const int i = edges[k][0], j = edges[k][1];
    if ((v[i].y > y16) != (v[j].y > y16) && count < 128)
      // Sixteenths stay under 2^13, so the product fits 32 bits and the
      // board divides in hardware.
      hits[count++] = v[i].x + (v[j].x - v[i].x) * (y16 - v[i].y) / (v[j].y - v[i].y);
  }
  std::sort(hits, hits + count);
  return count;
}

// Adds a sub-row's span [xl, xr), in sixteenths, to the row's coverage:
// each pixel gets the share of its width the span covers, a quarter of
// full coverage for each of the four sub-rows.
void addSpan(int xl, int xr, int px0, int px1) {
  xl = std::max(xl, px0 * 16);
  xr = std::min(xr, (px1 + 1) * 16);
  if (xl >= xr) return;
  const int first = floor16(xl), last = floor16(xr - 1);
  touched(first), touched(last);
  if (first == last) {
    coverage[first] += uint16_t((xr - xl) * 4);
    return;
  }
  coverage[first] += uint16_t(((first + 1) * 16 - xl) * 4);
  for (int p = first + 1; p < last; ++p) coverage[p] += 64;
  coverage[last] += uint16_t((xr - last * 16) * 4);
}

// Floor square root of a 64-bit value (a segment's setup, not per pixel).
uint32_t root64(uint64_t n) {
  if (n < (uint64_t(1) << 32)) return uint32_t(root(uint32_t(n)));
  uint64_t r = uint64_t(1) << ((64 - __builtin_clzll(n)) / 2 + 1);
  for (;;) {
    const uint64_t next = (r + n / r) / 2;
    if (next >= r) return uint32_t(r);
    r = next;
  }
}

// A segment of a stroke, ready for distances: from a pixel centre, the
// distance to its line is |cross| / length, without a square root, and only
// its round ends need one. Distances are in 256ths of a pixel, rounded.
// A segment of a stroke, from a to b, ready for distances: from a pixel
// centre, the distance to its line is |cross| / length, without a square
// root, and only its round ends need one. Distances are in 256ths of a
// pixel, rounded.
struct Segment {
  Point a, b;
  int abx, aby, length2;
  int64_t reciprocal;  // 2^32 / its length in 256ths
  Segment(Point from, Point to, const int64_t& r) : a(from), b(to), reciprocal(r) {
    abx = to.x - from.x, aby = to.y - from.y, length2 = abx * abx + aby * aby;
  }
  // 2^32 over the length from `from` to `to`, in 256ths: a segment's setup,
  // its one square root, kept between the rows.
  static int64_t reciprocalOf(Point from, Point to) {
    const int abx = to.x - from.x, aby = to.y - from.y;
    const int64_t length256 = std::max<int64_t>(1, root64(uint64_t(abx * abx + aby * aby) << 8));
    return ((int64_t(1) << 32) + length256 / 2) / length256;
  }
  // The distance from (px, py), or -1 when it's at least `beyond` (so no
  // square root was needed); `beyond` and the result in 256ths.
  int distance(int px, int py, int beyond) const {
    const int apx = px - a.x, apy = py - a.y, along = apx * abx + apy * aby;
    if (along > 0 && along < length2) {
      const int cross = std::abs(apx * aby - apy * abx);
      return int((int64_t(cross) * reciprocal + (int64_t(1) << 23)) >> 24);
    }
    const int ex = along <= 0 ? apx : px - b.x, ey = along <= 0 ? apy : py - b.y;
    const uint32_t d2 = uint32_t(ex * ex + ey * ey) << 8;
    return d2 >= uint32_t(beyond) * uint32_t(beyond) ? -1 : root(d2);
  }
};

// The strokes' segments' reciprocals, worked out once a stroke (drawing is
// single-threaded): a stroke has at most kMaxSegments, and the strokes a sum
// draws at once share kSummedSegments.
constexpr int kMaxSegments = 96, kSummedSegments = 2 * kMaxSegments;  // the longest art path, twice
int64_t reciprocals[kSummedSegments];

// A pixel's coverage by a shape whose edge is `inside` sixteenths from its
// centre (negative outside): a box filter one pixel wide, 0–256.
int edgeCoverage(int inside) { return std::clamp((inside + 8) * 16, 0, 256); }

// One row of a polygon's coverage (even-odd), cut to its clip when it has
// one, added to the row's across [x0, x1]: four sub-rows, with exact
// coverage across each span's ends.
void polygonRow(const Point* v, int n, const Point* clip, int clipCount, int y, int x0, int x1) {
  int hits[128], clips[128];
  uint8_t edges[128][2], clipEdges[128][2];
  const int active = rowEdges(v, std::min(n, 128), y, edges),
            clipActive = clipCount ? rowEdges(clip, std::min(clipCount, 128), y, clipEdges) : 0;
  for (int sub = 0; sub < 4; ++sub) {
    const int y16 = y * 16 + sub * 4 + 2;
    const int count = crossings(v, edges, active, y16, hits),
              clipped = clipCount ? crossings(clip, clipEdges, clipActive, y16, clips) : 0;
    for (int i = 0; i + 1 < count; i += 2) {
      if (!clipCount)
        addSpan(hits[i], hits[i + 1], x0, x1);
      else
        for (int j = 0; j + 1 < clipped; j += 2)
          addSpan(std::max(hits[i], clips[j]), std::min(hits[i + 1], clips[j + 1]), x0, x1);
    }
  }
}

// A stroke `radius` sixteenths wide either side, ready to draw by rows: its
// segments from `reciprocal`, and the pixels it reaches.
struct Stroke {
  const Point* v = nullptr;
  int n = 0, count = 0, radius = 0, outer = 0;
  uint64_t whole2 = 0;  // a disk's: within this (in 256ths, squared) of its centre, a pixel is whole
  const int64_t* reciprocal = nullptr;
  // Its segments' reciprocals into `r`, at most `room` of them.
  void set(const Point* points, int pointCount, int width16, int64_t* r, int room) {
    v = points, n = pointCount, reciprocal = r;
    radius = std::max(4, width16 / 2), outer = radius + 8;
    count = std::min(room, std::max(1, n - 1));
    // A disk (one point): a pixel whose centre is inside its edge's band is
    // covered whole, with no square root.
    const int whole = radius * 16 - 128;
    whole2 = whole > 0 ? uint64_t(whole) * uint64_t(whole) : 0;
    for (int i = 0; i < count; ++i) r[i] = Segment::reciprocalOf(v[i], v[std::min(i + 1, n - 1)]);
  }
  // Row y of its coverage across [x0, x1], into the row's: each pixel the
  // most any segment gives it.
  void row(int y, int x0, int x1) const {
    const int cy = y * 16 + 8;
    for (int i = 0; i < count; ++i) {
      const Point a = v[i], b = v[std::min(i + 1, n - 1)];
      if (cy < std::min(a.y, b.y) - outer || cy > std::max(a.y, b.y) + outer) continue;
      const Segment segment(a, b, reciprocal[i]);
      const int from = std::max(x0, floor16(std::min(a.x, b.x) - outer)),
                to = std::min(x1, floor16(std::max(a.x, b.x) + outer));
      for (int x = from; x <= to; ++x) {
        if (coverage[x] >= 256) continue;
        if (n == 1 && whole2) {
          const int64_t ex = x * 16 + 8 - a.x, ey = cy - a.y;
          if (uint64_t(ex * ex + ey * ey) << 8 <= whole2) {
            coverage[x] = 256;
            touched(x);
            continue;
          }
        }
        // 256ths of a pixel: coverage is the share of the pixel inside.
        const int d = segment.distance(x * 16 + 8, cy, outer * 16);
        if (d < 0 || d >= outer * 16) continue;
        coverage[x] = uint16_t(std::max(int(coverage[x]), std::clamp(radius * 16 + 128 - d, 0, 256)));
        touched(x);
      }
    }
  }
};

// A sum's row (Raster::sum): the picture being drawn's opacity, 0–255 a
// pixel, and the pictures' so far, each times its weight, added.
uint8_t picture[Raster::kMaxWidth];
uint16_t summed[Raster::kMaxWidth];

}  // namespace

void Raster::composite(int y, int x0, int x1, const uint16_t* row, uint16_t ink) {
  if (recording) {
    for (int x = x0; x <= x1; ++x) kept[x - x0] = uint8_t(std::min<int>(row[x], 256) * alpha >> 8);
    return recording->add(y, x0, x1, kept, ink);
  }
  auto* out = s.pixels + y * s.width;
  for (int x = x0; x <= x1; ++x) {
    const int a = shown(std::min<int>(row[x], 256) * alpha >> 8);
    if (a >= 253)
      out[x] = ink;
    else if (a > 2)
      out[x] = mix565(out[x], ink, a);
  }
}

// Marks only the pixels the row wrote as changed, not the shape's whole box:
// a hat's or a stroke's box is mostly empty, and what's marked is cleared and
// pushed again next frame.
void Raster::flush(int y, uint16_t ink) {
  if (touchedLo > touchedHi) return;
  touch(touchedLo, y, touchedHi + 1, y + 1);
  composite(y, touchedLo, touchedHi, coverage, ink);
  std::fill(coverage + touchedLo, coverage + touchedHi + 1, 0);
  touchedLo = kMaxWidth, touchedHi = -1;
}

void Raster::fill(int y, int x0, int x1, uint16_t ink) {
  if (x0 > x1) return;
  if (recording) {
    std::fill(kept, kept + (x1 - x0 + 1), uint8_t(alpha));
    return recording->add(y, x0, x1, kept, ink);
  }
  auto* out = s.pixels + y * s.width;
  const int a = shown(alpha);
  if (a >= 253)
    std::fill(out + x0, out + x1 + 1, ink);
  else
    for (int x = x0; x <= x1; ++x) out[x] = mix565(out[x], ink, a);
}

bool Raster::polygonBox(const Point* v, int n, Box& box) const {
  int minX = INT_MAX, minY = INT_MAX, maxX = INT_MIN, maxY = INT_MIN;
  for (int i = 0; i < n; ++i) {
    minX = std::min(minX, v[i].x), maxX = std::max(maxX, v[i].x);
    minY = std::min(minY, v[i].y), maxY = std::max(maxY, v[i].y);
  }
  box.y0 = std::max({0, floor16(minY), bounds.y0}), box.y1 = std::min({bottom(), floor16(maxY - 1) + 1, bounds.y1});
  box.x0 = std::max({0, floor16(minX), bounds.x0});
  box.x1 = std::min({s.width, kMaxWidth, floor16(maxX - 1) + 1, bounds.x1});
  return box.y0 < box.y1 && box.x0 < box.x1;
}

bool Raster::strokeBox(const Point* v, int n, int width16, Box& box) const {
  const int outer = std::max(4, width16 / 2) + 8;
  int minX = INT_MAX, minY = INT_MAX, maxX = INT_MIN, maxY = INT_MIN;
  for (int i = 0; i < n; ++i) {
    minX = std::min(minX, v[i].x), maxX = std::max(maxX, v[i].x);
    minY = std::min(minY, v[i].y), maxY = std::max(maxY, v[i].y);
  }
  box.y0 = std::max({0, floor16(minY - outer), bounds.y0});
  box.y1 = std::min({bottom(), floor16(maxY + outer) + 1, bounds.y1});
  box.x0 = std::max({0, floor16(minX - outer), bounds.x0});
  box.x1 = std::min({s.width, kMaxWidth, floor16(maxX + outer) + 1, bounds.x1});
  return box.y0 < box.y1 && box.x0 < box.x1;
}

void Raster::polygon16(const Point* v, int n, uint16_t ink, const Point* clip, int clipCount) {
  Box box;
  if (off() || n < 3 || alpha <= 2 || !polygonBox(v, n, box)) return;
  for (int y = box.y0; y < box.y1; ++y) {
    polygonRow(v, n, clip, clipCount, y, box.x0, box.x1 - 1);
    flush(y, ink);
  }
}

void Raster::stroke16(const Point* v, int n, int width16, uint16_t ink) {
  Box box;
  if (off() || n < 1 || alpha <= 2 || !strokeBox(v, n, width16, box)) return;
  Stroke stroke;
  stroke.set(v, n, width16, reciprocals, kMaxSegments);
  for (int y = box.y0; y < box.y1; ++y) {
    stroke.row(y, box.x0, box.x1 - 1);
    flush(y, ink);
  }
}

void Raster::sum(const Shape* shapes, int count, uint16_t ink) {
  constexpr int kMost = 12;
  if (off() || count <= 0 || alpha <= 2) return;
  count = std::min(count, kMost);
  // Each shape's pixels, and its strokes' segments, which must all fit at
  // once; else each is drawn on its own, at its opacity and weight, one over
  // the other.
  Box boxes[kMost], all{INT_MAX, INT_MAX, INT_MIN, INT_MIN};
  bool drawn[kMost];
  int segments = 0;
  for (int i = 0; i < count; ++i) {
    const Shape& shape = shapes[i];
    drawn[i] = shape.alpha > 0 && shape.weight > 0 &&
               (shape.width16 ? shape.n >= 1 && strokeBox(shape.v, shape.n, shape.width16, boxes[i])
                              : shape.n >= 3 && polygonBox(shape.v, shape.n, boxes[i]));
    if (!drawn[i]) continue;
    if (shape.width16) segments += std::min(kMaxSegments, std::max(1, shape.n - 1));
    all.x0 = std::min(all.x0, boxes[i].x0), all.x1 = std::max(all.x1, boxes[i].x1);
    all.y0 = std::min(all.y0, boxes[i].y0), all.y1 = std::max(all.y1, boxes[i].y1);
  }
  if (all.y0 >= all.y1) return;
  if (segments > kSummedSegments) {
    const int old = alpha;
    for (int i = 0; i < count; ++i) {
      alpha = old * shapes[i].alpha / 255 * std::min(4096, shapes[i].weight) / 4096;
      if (shapes[i].width16)
        stroke16(shapes[i].v, shapes[i].n, shapes[i].width16, ink);
      else
        polygon16(shapes[i].v, shapes[i].n, ink, shapes[i].clip, shapes[i].clipCount);
    }
    alpha = old;
    return;
  }
  // The strokes, set up once: their segments' reciprocals, one after another.
  Stroke strokes[kMost];
  for (int i = 0, used = 0; i < count; ++i)
    if (drawn[i] && shapes[i].width16) {
      strokes[i].set(shapes[i].v, shapes[i].n, shapes[i].width16, reciprocals + used, kMaxSegments);
      used += strokes[i].count;
    }
  for (int y = all.y0; y < all.y1; ++y) {
    int lo = kMaxWidth, hi = -1, pictureLo = kMaxWidth, pictureHi = -1;
    for (int i = 0; i < count; ++i) {
      if (drawn[i] && y >= boxes[i].y0 && y < boxes[i].y1) {
        if (shapes[i].width16)
          strokes[i].row(y, boxes[i].x0, boxes[i].x1 - 1);
        else
          polygonRow(shapes[i].v, shapes[i].n, shapes[i].clip, shapes[i].clipCount, y, boxes[i].x0, boxes[i].x1 - 1);
        // Over the picture so far: one ink, so only its opacity grows.
        const int a = shapes[i].alpha;
        for (int x = touchedLo; x <= touchedHi; ++x) {
          const int over = std::min<int>(coverage[x], 256) * a >> 8, under = picture[x];
          picture[x] = uint8_t(under + over - (under * over + 127) / 255);
          coverage[x] = 0;
        }
        pictureLo = std::min(pictureLo, touchedLo), pictureHi = std::max(pictureHi, touchedHi);
        touchedLo = kMaxWidth, touchedHi = -1;
      }
      // A picture's end: its opacity, at its weight, into the sum.
      if (i + 1 < count && shapes[i + 1].joined) continue;
      const int w = std::min(4096, shapes[i].weight);
      for (int x = pictureLo; x <= pictureHi; ++x) {
        summed[x] = uint16_t(summed[x] + ((picture[x] * w + 2048) >> 12));
        picture[x] = 0;
      }
      lo = std::min(lo, pictureLo), hi = std::max(hi, pictureHi);
      pictureLo = kMaxWidth, pictureHi = -1;
    }
    if (lo > hi) continue;
    touch(lo, y, hi + 1, y + 1);
    for (int x = lo; x <= hi; ++x) {
      const int a = std::min<int>(summed[x], 255) * alpha / 255;
      summed[x] = 0;
      if (recording)
        kept[x - lo] = uint8_t(a);
      else if (shown(a) >= 253)
        s.pixels[y * s.width + x] = ink;
      else if (shown(a) > 2)
        s.pixels[y * s.width + x] = mix565(s.pixels[y * s.width + x], ink, shown(a));
    }
    if (recording) recording->add(y, lo, hi, kept, ink);
  }
}

void Raster::round(int x, int y, int w, int h, int radius, uint16_t ink) {
  if (off() || w <= 0 || h <= 0 || alpha <= 2) return;
  radius = std::clamp(radius, 0, std::min(w, h) / 2);
  const int y0 = std::max({0, y, bounds.y0}), y1 = std::min({bottom(), y + h, bounds.y1}) - 1;
  const int x0 = std::max({0, x, bounds.x0}), x1 = std::min({s.width, kMaxWidth, x + w, bounds.x1}) - 1;
  if (y0 > y1 || x0 > x1) return;
  touch(x0, y0, x1 + 1, y1 + 1);
  const int r16 = radius * 16;
  // The columns of the left and right corners; the rest of a row is whole.
  const int leftEnd = std::min(x1, x + radius - 1), rightStart = std::max(x0, x + w - radius);
  for (int row = y0; row <= y1; ++row) {
    // How far the pixel centre is into the top or bottom corners' band.
    const int cy = row * 16 + 8, qy = std::max(y * 16 + r16 - cy, cy - ((y + h) * 16 - r16));
    if (qy <= 0) {
      fill(row, x0, x1, ink);
      continue;
    }
    auto corner = [&](int col) {
      const int cx = col * 16 + 8, qx = std::max(x * 16 + r16 - cx, cx - ((x + w) * 16 - r16));
      coverage[col] = uint16_t(qx > 0 ? edgeCoverage(r16 - root(uint32_t(qx * qx + qy * qy))) : 256);
    };
    for (int col = x0; col <= leftEnd; ++col) corner(col);
    for (int col = std::max(x0, rightStart); col <= x1; ++col) corner(col);
    composite(row, x0, leftEnd, coverage, ink);
    if (leftEnd + 1 <= rightStart - 1) fill(row, std::max(x0, leftEnd + 1), std::min(x1, rightStart - 1), ink);
    if (rightStart > leftEnd) composite(row, std::max(x0, rightStart), x1, coverage, ink);
    if (x0 <= leftEnd) std::fill(coverage + x0, coverage + leftEnd + 1, 0);
    if (rightStart <= x1) std::fill(coverage + std::max(x0, rightStart), coverage + x1 + 1, 0);
  }
}

void Raster::ring(int x, int y, int w, int h, int radius, int line, uint16_t ink) {
  if (off() || line <= 0 || w <= 2 * line || h <= 2 * line || alpha <= 2) return;
  radius = std::clamp(radius, line, std::min(w, h) / 2);
  const int y0 = std::max({0, y, bounds.y0}), y1 = std::min({bottom(), y + h, bounds.y1}) - 1;
  const int x0 = std::max({0, x, bounds.x0}), x1 = std::min({s.width, kMaxWidth, x + w, bounds.x1}) - 1;
  if (y0 > y1 || x0 > x1) return;
  touch(x0, y0, x1 + 1, y1 + 1);
  // The inner edge's corners share the outer's centres, so the width holds,
  // and a pixel's coverage is the outer corner's less the inner's, both by
  // its one distance from that centre. Only pixels within half a pixel of
  // either arc need the square root (as round() takes it): nearer the centre
  // than the inner arc, or past the outer, they're none; between, whole.
  const int outer16 = radius * 16, inner16 = (radius - line) * 16;
  auto cover = [](int r16, uint32_t d2, uint32_t& d) {
    if (r16 > 7 && d2 < uint32_t((r16 - 7) * (r16 - 7))) return 256;
    if (d2 >= uint32_t((r16 + 8) * (r16 + 8))) return 0;
    if (d == UINT32_MAX) d = root(d2);
    return edgeCoverage(r16 - int(d));
  };
  const int leftEnd = std::min(x1, x + radius - 1), rightStart = std::max(x0, x + w - radius);
  for (int row = y0; row <= y1; ++row) {
    if (row >= y + radius && row < y + h - radius) {  // between the corners: just the sides
      fill(row, x0, std::min(x1, x + line - 1), ink);
      fill(row, std::max(x0, x + w - line), x1, ink);
      continue;
    }
    const int cy = row * 16 + 8, qy = std::max(y * 16 + outer16 - cy, cy - ((y + h) * 16 - outer16));
    auto corner = [&](int col) {
      const int cx = col * 16 + 8, qx = std::max(x * 16 + outer16 - cx, cx - ((x + w) * 16 - outer16));
      if (qx <= 0) {  // the straight top or bottom edge: whole where the inner rectangle isn't
        coverage[col] = uint16_t(row < y + line || row >= y + h - line ? 256 : 0);
        return;
      }
      const uint32_t d2 = uint32_t(qx * qx + qy * qy);
      uint32_t d = UINT32_MAX;
      const int outer = cover(outer16, d2, d);
      // The inner rectangle starts `line` in: outside it, nothing to take away.
      const bool inInner = col >= x + line && col < x + w - line && row >= y + line && row < y + h - line;
      const int inner = inInner ? cover(inner16, d2, d) : 0;
      coverage[col] = uint16_t(std::max(0, outer - inner));
    };
    for (int col = x0; col <= leftEnd; ++col) corner(col);
    for (int col = std::max(x0, rightStart); col <= x1; ++col) corner(col);
    composite(row, x0, leftEnd, coverage, ink);
    // Between the corners only the top and bottom edges' rows are ink.
    const bool edgeRow = row < y + line || row >= y + h - line;
    if (edgeRow && leftEnd + 1 <= rightStart - 1)
      fill(row, std::max(x0, leftEnd + 1), std::min(x1, rightStart - 1), ink);
    if (rightStart > leftEnd) composite(row, std::max(x0, rightStart), x1, coverage, ink);
    if (x0 <= leftEnd) std::fill(coverage + x0, coverage + leftEnd + 1, 0);
    if (rightStart <= x1) std::fill(coverage + std::max(x0, rightStart), coverage + x1 + 1, 0);
  }
}

namespace {
// A recorded span: its row, its first pixel and how many, and its ink; its
// runs follow it, as many as cover its pixels.
struct Span {
  int16_t y, x0;
  uint16_t n, ink;
};
// A run's code: kRun and its length less one for that many pixels of the
// one opacity after it; else its length less one, and that many opacities.
constexpr int kRun = 0x80, kMaxRun = 128;
}  // namespace

void Recording::add(int y, int x0, int x1, const uint8_t* alpha, uint16_t ink) {
  const int n = x1 - x0 + 1;
  if (full || n <= 0) return;
  // At most a code and an opacity a pixel.
  if (used + int(sizeof(Span)) + 2 * n > room) {
    full = true;
    return;
  }
  uint8_t* const start = data + used + sizeof(Span);
  uint8_t* out = start;
  for (int i = 0; i < n;) {
    int run = 1;
    while (i + run < n && run < kMaxRun && alpha[i + run] == alpha[i]) ++run;
    if (run >= 3) {
      *out++ = uint8_t(kRun | (run - 1)), *out++ = alpha[i];
      i += run;
      continue;
    }
    // One by one, up to where three alike start.
    int j = i;
    while (j < n && j - i < kMaxRun && !(j + 2 < n && alpha[j] == alpha[j + 1] && alpha[j] == alpha[j + 2])) ++j;
    *out++ = uint8_t(j - i - 1);
    std::memcpy(out, alpha + i, size_t(j - i));
    out += j - i;
    i = j;
  }
  const Span span{int16_t(y), int16_t(x0), uint16_t(n), ink};
  std::memcpy(data + used, &span, sizeof span);
  used = int(out - data);
  box.x0 = std::min(box.x0, x0), box.x1 = std::max(box.x1, x1 + 1);
  box.y0 = std::min(box.y0, y), box.y1 = std::max(box.y1, y + 1);
}

void Raster::replay(const Recording& r, int dx, int dy) {
  if (!s.pixels) return;
  const int top = std::max(0, bounds.y0), under = std::min(bottom(), bounds.y1);
  const int left = std::max(0, bounds.x0), right = std::min({s.width, kMaxWidth, bounds.x1});
  for (const uint8_t* code = r.data; code + sizeof(Span) <= r.data + r.used;) {
    Span span;
    std::memcpy(&span, code, sizeof span);
    code += sizeof span;
    const int y = span.y + dy, from = std::max(left, span.x0 + dx), to = std::min(right, span.x0 + dx + span.n);
    // A row off the surface is only read past.
    uint16_t* row = y >= top && y < under && from < to ? s.pixels + y * s.width : nullptr;
    if (row) touch(from, y, to, y + 1);
    // [x0, x1) at opacity a, as composite blends it.
    auto blend = [&](int x0, int x1, int a) {
      x0 = std::max(x0, from), x1 = std::min(x1, to);
      a = shown(a);
      if (a >= 253) {
        if (x0 < x1) std::fill(row + x0, row + x1, span.ink);
      } else if (a > 2) {
        for (int x = x0; x < x1; ++x) row[x] = mix565(row[x], span.ink, a);
      }
    };
    for (int x = span.x0 + dx, end = x + span.n; x < end;) {
      const int c = *code++;
      if (c & kRun) {
        const int length = (c & (kRun - 1)) + 1;
        if (row) blend(x, x + length, *code);
        ++code, x += length;
      } else {
        if (row)
          for (int k = 0; k <= c; ++k) blend(x + k, x + k + 1, code[k]);
        code += c + 1, x += c + 1;
      }
    }
  }
}

}  // namespace render::gel
