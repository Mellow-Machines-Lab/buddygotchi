#include "render/gel/raster.h"

#include <climits>
#include <cstring>

#include "render/gel/geometry.h"

namespace render::gel {

namespace {

// The row of coverage (Scratch::coverage) is all zero between rows;
// [touchedLo, touchedHi] is what a row wrote.
int touchedLo = Raster::kMaxWidth, touchedHi = -1;
void touched(int x) { touchedLo = std::min(touchedLo, x), touchedHi = std::max(touchedHi, x); }

// Floor division by 16 that's right for negative coordinates too.
int floor16(int v) { return v >= 0 ? v / 16 : -((15 - v) / 16); }

// A polygon's area, a row at a time, exactly: each edge's piece inside the
// row adds, to each pixel it passes, its height times the share of the
// pixel right of it, and the rest to the next pixel; summed along the row
// from the left, that's each pixel's covered area. Its edges' heights
// around the polygon cancel, so the sum is back at nothing past it. The
// art's polygons never cross themselves, so this winding count fills them
// as even-odd does.
//
// Positions inside are 256ths of a pixel; a whole pixel's area is
// 256 × 256 × 2, the 2 for an edge's middle taken as the sum of its ends.
struct Area {
  int* cell;   // a pixel's and one past the row's, zero between rows
  int lo, hi;  // the cells a row wrote
  // Each edge's x a sixteenth further down, in 65536ths of a sixteenth:
  // the edge into point i is from point i - 1 (wrapping).
  int slope[128];
  // The edges that aren't level, by where they start down the surface;
  // those from `next` on are below the rows so far, and `active` reach the
  // row.
  uint8_t order[128], active[128];
  int edges, next, live;
};

int before(int i, int n) { return i ? i - 1 : n - 1; }

// A polygon's edges, once: their slopes, and in order down the surface.
void prepare(const Point* v, int n, Area& a) {
  a.edges = a.next = a.live = 0;
  for (int i = 0, j = n - 1; i < n; j = i++) {
    const int dy = v[i].y - v[j].y, dx = v[i].x - v[j].x;
    if (!dy) continue;
    // Shifted in 32 bits while that fits, so the board divides in hardware.
    a.slope[i] = std::abs(dx) < (1 << 14) ? dx * 65536 / dy : int(int64_t(dx) * 65536 / dy);
    // Inserted in order of its top.
    const int top = std::min(v[i].y, v[j].y);
    int at = a.edges++;
    for (; at > 0; --at) {
      const int e = a.order[at - 1];
      if (std::min(v[e].y, v[before(e, n)].y) <= top) break;
      a.order[at] = uint8_t(e);
    }
    a.order[at] = uint8_t(i);
  }
}

// One piece of an edge inside the row, from (xa, ya) to (xb, yb), in 256ths
// (x across the surface, y down from the row's top), into the cells
// [x0, x1]: what lies left of x0 covers all of x0 onwards, and what lies
// right of x1 nothing that's drawn, but it leaves the row's sum standing
// through x1.
void addPiece(Area& a, int xa, int ya, int xb, int yb, int x0, int x1) {
  int sign = 1;
  if (xa > xb) std::swap(xa, xb), std::swap(ya, yb), sign = -1;
  const int left = x0 * 256, right = (x1 + 1) * 256;
  if (xa >= right) {
    a.hi = x1;
    return;
  }
  if (xa < left) {
    const int at = xb <= left ? yb : ya + (left - xa) * (yb - ya) / (xb - xa);
    a.cell[x0] += sign * (at - ya) * 512;
    a.lo = std::min(a.lo, x0), a.hi = std::max(a.hi, x0);
    if (xb <= left) return;
    xa = left, ya = at;
  }
  if (xb > right) yb = ya + (right - xa) * (yb - ya) / (xb - xa), xb = right;
  const int first = xa >> 8, last = std::max(first, (xb - 1) >> 8);
  a.lo = std::min(a.lo, first), a.hi = std::max(a.hi, last);
  int x = xa, y = ya;
  for (int c = first; c <= last; ++c) {
    // Where it leaves this cell: across its right side, or at its end.
    const int nx = c == last ? xb : (c + 1) * 256, ny = c == last ? yb : ya + (nx - xa) * (yb - ya) / (xb - xa);
    const int dy = sign * (ny - y),
              middle = x + nx - c * 512;  // twice its middle's x in the cell, 0–512
    a.cell[c] += dy * (512 - middle);
    a.cell[c + 1] += dy * middle;
    x = nx, y = ny;
  }
}

// Every edge's piece in row y, into the cells [x0, x1]: the rows come in
// order down the surface.
void addRow(const Point* v, int n, int y, int x0, int x1, Area& a) {
  const int top = y * 16, under = top + 16;
  a.lo = Raster::kMaxWidth, a.hi = -1;
  for (; a.next < a.edges; ++a.next) {
    const int i = a.order[a.next];
    if (std::min(v[i].y, v[before(i, n)].y) >= under) break;
    a.active[a.live++] = uint8_t(i);
  }
  for (int k = 0; k < a.live;) {
    const int i = a.active[k];
    const Point p = v[before(i, n)], q = v[i];
    if (std::max(p.y, q.y) <= top) {  // above this row, and every row to come
      a.active[k] = a.active[--a.live];
      continue;
    }
    ++k;
    // Its ends inside the row, each exact where it's a point's.
    auto xAt = [&](int y16) {
      if (y16 == p.y) return p.x * 16;
      if (y16 == q.y) return q.x * 16;
      return p.x * 16 + int((int64_t(a.slope[i]) * (y16 - p.y)) >> 12);
    };
    const int ya = std::clamp(p.y, top, under), yb = std::clamp(q.y, top, under);
    addPiece(a, xAt(ya), (ya - top) * 16, xAt(yb), (yb - top) * 16, x0, x1);
  }
}

// The row's area as coverage, 0–256 a pixel, in `out` for [x0, x1] and
// zero elsewhere in [lo, hi + 1]; the cells are zero again after.
void coverRow(Area& a, int x0, int x1, uint16_t* out) {
  int sum = 0;
  const int to = std::min(a.hi + 1, x1);
  for (int x = a.lo; x <= to; ++x) {
    sum += a.cell[x];
    a.cell[x] = 0;
    out[x] = uint16_t(std::min(256, (std::abs(sum) + 256) >> 9));
  }
  if (a.hi + 1 > to) std::fill(a.cell + to + 1, a.cell + a.hi + 2, 0);
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
struct Segment {
  Point a, b;
  int abx, aby, length2;
  int64_t reciprocal;  // 2^32 / its length in 256ths
  void set(Point from, Point to) {
    a = from, b = to, abx = to.x - from.x, aby = to.y - from.y;
    length2 = abx * abx + aby * aby;
    const int64_t length256 = std::max<int64_t>(1, root64(uint64_t(length2) << 8));
    reciprocal = ((int64_t(1) << 32) + length256 / 2) / length256;
  }
  // The distance from (px, py), or -1 when it's at least `beyond`, or 0
  // when it's at most `within` (so no square root was needed); all in
  // 256ths.
  int distance(int px, int py, int beyond, int within) const {
    const int apx = px - a.x, apy = py - a.y, along = apx * abx + apy * aby;
    if (along > 0 && along < length2) {
      const int cross = std::abs(apx * aby - apy * abx);
      return int((int64_t(cross) * reciprocal + (int64_t(1) << 23)) >> 24);
    }
    const int ex = along <= 0 ? apx : px - b.x, ey = along <= 0 ? apy : py - b.y;
    const uint32_t d2 = uint32_t(ex * ex + ey * ey) << 8;
    if (d2 >= uint32_t(beyond) * uint32_t(beyond)) return -1;
    return within > 0 && d2 <= uint32_t(within) * uint32_t(within) ? 0 : root(d2);
  }
};

// The longest stroke: the art's are 50 points at most.
constexpr int kMaxSegments = 64;
// A blend's columns at a time (Raster::blend); 32768 is a whole pixel.
constexpr int kBlendColumns = 128, kWholePixel = 32768;

// What drawing works in. Drawing is single-threaded and each shape
// finishes its rows before the next begins. What every pixel of a shape
// reads is in the board's internal memory, 6 KB of it: a row's coverage,
// 0–256 a pixel, and its opacities for a recording (Raster::recording), a
// stroke's segments and a polygon's row of cells.
uint16_t coverage[Raster::kMaxWidth];
uint8_t kept[Raster::kMaxWidth];
Segment segments[kMaxSegments];
int shapeCells[Raster::kMaxWidth + 2];
// The rest is one block made at start, so it comes from PSRAM, which has
// the room, and not from the internal memory, which hasn't (`perf` keeps
// 50 KB of it free).
struct Scratch {
  // A polygon's edges, its clip's, and the clip's cells and coverage.
  int clipCells[Raster::kMaxWidth + 2]{};
  Area shape{shapeCells}, clip{clipCells};
  uint16_t clipped[Raster::kMaxWidth];
  // A blend's: of each look, what its shapes leave of what's under them,
  // and the sum of each channel's ink so far.
  uint16_t through[kBlendColumns];
  int underneath[kBlendColumns], red[kBlendColumns], green[kBlendColumns], blue[kBlendColumns];
};
Scratch& work = *new Scratch();

// A pixel's coverage by a shape whose edge is `inside` sixteenths from its
// centre (negative outside): a box filter one pixel wide, 0–256.
int edgeCoverage(int inside) { return std::clamp((inside + 8) * 16, 0, 256); }

}  // namespace

void Raster::composite(int y, int x0, int x1, const uint16_t* row, uint16_t ink) {
  if (recording) {
    for (int x = x0; x <= x1; ++x) kept[x - x0] = uint8_t(std::min<int>(row[x], 256) * alpha >> 8);
    return recording->add(y, x0, x1, kept, ink);
  }
  auto* out = s.pixels + y * s.width;
  // A shape's inside is a run of whole pixels, all blended alike.
  const Blender whole(ink, shown(alpha));
  for (int x = x0; x <= x1;) {
    if (row[x] >= 256) {
      int end = x + 1;
      while (end <= x1 && row[end] >= 256) ++end;
      whole.run(out + x, end - x);
      x = end;
      continue;
    }
    const int a = shown(row[x] * alpha >> 8);
    if (a >= 253)
      out[x] = ink;
    else if (a > 2)
      out[x] = mix565(out[x], ink, a);
    ++x;
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
  Blender(ink, shown(alpha)).run(s.pixels + y * s.width + x0, x1 - x0 + 1);
}

void Raster::polygon16(const Point* v, int n, uint16_t ink, const Point* clip, int clipCount) {
  if (off() || n < 3 || alpha <= 2) return;
  int minX = INT_MAX, minY = INT_MAX, maxX = INT_MIN, maxY = INT_MIN;
  for (int i = 0; i < n; ++i) {
    minX = std::min(minX, v[i].x), maxX = std::max(maxX, v[i].x);
    minY = std::min(minY, v[i].y), maxY = std::max(maxY, v[i].y);
  }
  const int y0 = std::max({0, floor16(minY), bounds.y0}),
            y1 = std::min({bottom(), floor16(maxY - 1) + 1, bounds.y1}) - 1;
  const int x0 = std::max({0, floor16(minX), bounds.x0}),
            x1 = std::min({s.width, kMaxWidth, floor16(maxX - 1) + 1, bounds.x1}) - 1;
  if (y0 > y1 || x0 > x1) return;
  n = std::min(n, 128), clipCount = std::min(clipCount, 128);
  prepare(v, n, work.shape);
  if (clipCount) prepare(clip, clipCount, work.clip);
  // Its inside's pixels all blend alike.
  const Blender whole(ink, shown(alpha));
  for (int y = y0; y <= y1; ++y) {
    addRow(v, n, y, x0, x1, work.shape);
    if (work.shape.hi < 0) continue;
    if (!clipCount && !recording) {
      // Straight onto the surface: an edge's pixels one by one, and the
      // inside between, where no edge adds to the sum, as a run.
      Area& a = work.shape;
      int* const cell = a.cell;
      uint16_t* const out = s.pixels + y * s.width;
      const int to = std::min(a.hi + 1, x1);
      int sum = 0, lo = INT_MAX, hi = -1;
      for (int x = a.lo; x <= to;) {
        sum += cell[x];
        cell[x] = 0;
        const int c = std::min(256, (std::abs(sum) + 256) >> 9);
        if (c == 256 && !cell[x + 1] && x < to) {
          int end = x + 1;
          while (end <= to && !cell[end]) ++end;
          whole.run(out + x, end - x);
          lo = std::min(lo, x), hi = end - 1, x = end;
          continue;
        }
        if (c) {
          const int alpha = shown(c * this->alpha >> 8);
          if (alpha >= 253)
            out[x] = ink;
          else if (alpha > 2)
            out[x] = mix565(out[x], ink, alpha);
          lo = std::min(lo, x), hi = x;
        }
        ++x;
      }
      if (a.hi + 1 > to) std::fill(cell + to + 1, cell + a.hi + 2, 0);
      if (hi >= lo) touch(lo, y, hi + 1, y + 1);
      continue;
    }
    int lo = work.shape.lo, hi = std::min(work.shape.hi + 1, x1);
    coverRow(work.shape, x0, x1, coverage);
    if (clipCount) {
      // Where both cover part of a pixel, the less of the two: each edge
      // crossing the other's is rare, and the clip's lies under a stroke.
      addRow(clip, clipCount, y, x0, x1, work.clip);
      const int clo = work.clip.lo, chi = std::min(work.clip.hi + 1, x1);
      if (work.clip.hi >= 0) coverRow(work.clip, x0, x1, work.clipped);
      for (int x = lo; x <= hi; ++x) coverage[x] = x < clo || x > chi ? 0 : std::min(coverage[x], work.clipped[x]);
    }
    // Only what it covers: a pixel the row's edges pass but that's left
    // empty isn't marked.
    while (lo <= hi && !coverage[lo]) ++lo;
    while (hi >= lo && !coverage[hi]) coverage[hi--] = 0;
    if (lo > hi) continue;
    touchedLo = lo, touchedHi = hi;
    flush(y, ink);
  }
}

void Raster::stroke16(const Point* v, int n, int width16, uint16_t ink) {
  if (off() || n < 1 || alpha <= 2) return;
  const int radius = std::max(4, width16 / 2), outer = radius + 8;
  int minX = INT_MAX, minY = INT_MAX, maxX = INT_MIN, maxY = INT_MIN;
  for (int i = 0; i < n; ++i) {
    minX = std::min(minX, v[i].x), maxX = std::max(maxX, v[i].x);
    minY = std::min(minY, v[i].y), maxY = std::max(maxY, v[i].y);
  }
  const int y0 = std::max({0, floor16(minY - outer), bounds.y0}),
            y1 = std::min({bottom(), floor16(maxY + outer) + 1, bounds.y1}) - 1;
  const int x0 = std::max({0, floor16(minX - outer), bounds.x0}),
            x1 = std::min({s.width, kMaxWidth, floor16(maxX + outer) + 1, bounds.x1}) - 1;
  if (y0 > y1 || x0 > x1) return;
  const int count = std::min(kMaxSegments, std::max(1, n - 1));
  // A disk (one point): a pixel whose centre is inside its edge's band is
  // covered whole, with no square root.
  const int whole = radius * 16 - 128;
  const uint64_t whole2 = whole > 0 ? uint64_t(whole) * uint64_t(whole) : 0;
  for (int i = 0; i < count; ++i) segments[i].set(v[i], v[std::min(i + 1, n - 1)]);
  for (int y = y0; y <= y1; ++y) {
    const int cy = y * 16 + 8;
    for (int i = 0; i < count; ++i) {
      const Segment& segment = segments[i];
      const Point a = segment.a, b = segment.b;
      if (cy < std::min(a.y, b.y) - outer || cy > std::max(a.y, b.y) + outer) continue;
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
        // Within `whole` of it the pixel's covered whole: no root needed.
        const int d = segment.distance(x * 16 + 8, cy, outer * 16, whole);
        if (d < 0 || d >= outer * 16) continue;
        coverage[x] = uint16_t(std::max(int(coverage[x]), std::clamp(radius * 16 + 128 - d, 0, 256)));
        touched(x);
      }
    }
    flush(y, ink);
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
      if (qx <= 0) {  // the straight top or bottom edge: whole where the inner
                      // rectangle isn't
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

namespace {
// Walks a recorded span's runs from `code`, calling each(x, opacity) for
// its pixels in [from, to), and returns where the next span starts.
template <typename Each>
const uint8_t* runs(const uint8_t* code, const Span& span, int from, int to, Each each) {
  for (int x = span.x0, end = x + span.n; x < end;) {
    const int c = *code++;
    const int length = c & kRun ? (c & (kRun - 1)) + 1 : c + 1;
    const int lo = std::max(x, from), hi = std::min(x + length, to);
    if (c & kRun) {
      for (int p = lo; p < hi; ++p) each(p, code[0]);
      ++code;
    } else {
      for (int p = lo; p < hi; ++p) each(p, code[p - x]);
      code += length;
    }
    x += length;
  }
  return code;
}
}  // namespace

void Raster::blend(const CrossFade& f) {
  if (!s.pixels || !f.shapes) return;
  uint16_t* const through = work.through;
  int *const underneath = work.underneath, *const red = work.red, *const green = work.green, *const blue = work.blue;
  Box box{1 << 30, 1 << 30, -(1 << 30), -(1 << 30)};
  for (int i = 0; i < f.shapes; ++i) {
    const Box& b = f.shape[i].box;
    box.x0 = std::min(box.x0, b.x0), box.y0 = std::min(box.y0, b.y0);
    box.x1 = std::max(box.x1, b.x1), box.y1 = std::max(box.y1, b.y1);
  }
  int weight[CrossFade::kMaxLooks], rest = 4096;
  for (int l = 0; l < f.looks; ++l) weight[l] = shown(255) * f.weight[l] / 255, rest -= weight[l];
  rest = std::max(0, rest);
  // Each shape's next span, read in step down the rows.
  const uint8_t* at[CrossFade::kMaxShapes];
  for (int i = 0; i < f.shapes; ++i) at[i] = f.shape[i].data;
  for (int y = box.y0; y < box.y1; ++y) {
    Span span[CrossFade::kMaxShapes];
    bool here[CrossFade::kMaxShapes];
    int lo = 1 << 30, hi = -1;
    for (int i = 0; i < f.shapes; ++i) {
      const uint8_t* end = f.shape[i].data + f.shape[i].used;
      // A row's spans past its first (none of the art's shapes has two) are
      // passed over.
      for (here[i] = false; at[i] + sizeof(Span) <= end;) {
        std::memcpy(&span[i], at[i], sizeof(Span));
        if (span[i].y >= y) {
          here[i] = span[i].y == y;
          break;
        }
        at[i] = runs(at[i] + sizeof(Span), span[i], 0, 0, [](int, int) {});
      }
      if (here[i]) lo = std::min(lo, int(span[i].x0)), hi = std::max(hi, span[i].x0 + span[i].n - 1);
    }
    for (int from = lo; from <= hi; from += kBlendColumns) {
      const int to = std::min(hi + 1, from + kBlendColumns), n = to - from;
      std::fill(underneath, underneath + n, rest * (kWholePixel / 4096));
      std::fill(red, red + n, 0), std::fill(green, green + n, 0), std::fill(blue, blue + n, 0);
      for (int l = 0; l < f.looks; ++l) {
        std::fill(through, through + n, uint16_t(kWholePixel));
        const int w = weight[l];
        // Its shapes from the top down: each takes its share of what those
        // over it leave.
        for (int i = f.shapes - 1; i >= 0; --i) {
          if (f.lookOf[i] != l || !here[i]) continue;
          const uint16_t ink = span[i].ink;
          const int r = ink >> 11, g = (ink >> 5) & 63, b = ink & 31;
          runs(at[i] + sizeof(Span), span[i], from, to, [&](int x, int a) {
            const int k = x - from, took = through[k] * (a + (a >> 7)) >> 8, share = took * w >> 12;
            through[k] = uint16_t(through[k] - took);
            red[k] += share * r, green[k] += share * g, blue[k] += share * b;
          });
        }
        for (int k = 0; k < n; ++k) underneath[k] += through[k] * w >> 12;
      }
      uint16_t* out = s.pixels + y * s.width + from;
      for (int k = 0; k < n; ++k) {
        const int old = out[k], under = underneath[k], half = kWholePixel / 2;
        const int r = std::min(31, ((old >> 11) * under + red[k] + half) >> 15),
                  g = std::min(63, (((old >> 5) & 63) * under + green[k] + half) >> 15),
                  b = std::min(31, ((old & 31) * under + blue[k] + half) >> 15);
        out[k] = uint16_t(r << 11 | g << 5 | b);
      }
    }
    if (hi >= lo) touch(lo, y, hi + 1, y + 1);
    for (int i = 0; i < f.shapes; ++i)
      if (here[i]) at[i] = runs(at[i] + sizeof(Span), span[i], 0, 0, [](int, int) {});
  }
}

void Raster::replay16(const Recording& r, int dx16, int dy16) {
  const int fx = dx16 & 15, fy = dy16 & 15, dx = dx16 >> 4, dy = dy16 >> 4;
  if (!fx && !fy) return replay(r, dx, dy);
  if (!s.pixels) return;
  const int top = std::max(0, bounds.y0), under = std::min(bottom(), bounds.y1);
  const int left = std::max(0, bounds.x0), right = std::min({s.width, kMaxWidth, bounds.x1});
  // A shape's row: each pixel's opacity at its kept column plus one (so
  // column −1 is a zero), zero outside [lo, hi]; and its runs wholly clear
  // or wholly opaque, [a, b) in kept columns and the opacity, in order
  // (`runs` −1 when they're not known: two shapes of one ink met on it).
  // Most of a shape's row is one or the other, as most of a stroke's row is
  // clear between its segments.
  //
  // No memory of its own past a little stack (the board's internal heap
  // has little to spare): the two rows are the shapes' scratch, the
  // recording's row (`kept`) and the first half of the coverage row, both
  // cleared here; the coverage row's second half, never written, is the
  // row of nothing, and it's all zero again after, as shapes expect. So a
  // kept column is at most kMaxWidth − 3: a row's last sample reads two
  // past it.
  constexpr int kMostRuns = 16;
  struct Row {
    uint8_t* alpha;
    int lo, hi, runs;
    int16_t run[kMostRuns][3];
    void reset() { lo = 1 << 30, hi = -1, runs = 0; }
  };
  static_assert(sizeof(coverage) >= 2 * kMaxWidth && sizeof(kept) >= kMaxWidth, "the scratch replay16 borrows");
  uint8_t* const scratch = reinterpret_cast<uint8_t*>(coverage);
  std::memset(kept, 0, sizeof(kept));
  std::memset(coverage, 0, sizeof(coverage));
  Row rows[2], none;
  Row *here = &rows[0], *above = &rows[1];
  here->alpha = kept, above->alpha = scratch, none.alpha = scratch + kMaxWidth;
  here->reset(), above->reset(), none.reset();
  int hereY = 0;
  uint16_t ink = 0;
  bool gathering = false, hasAbove = false;
  const bool wholeShows = shown(255) >= 253;
  const int wx = 16 - fx, wy = 16 - fy;
  // Kept row y's pixel at x on the surface: the bilinear sample of its
  // four kept pixels around it, from `lower` and `upper` (the row before).
  auto sample = [&](uint16_t* out, int x, const uint8_t* lower, const uint8_t* upper) {
    const int k = x - dx + 1;  // the kept column, plus one
    const int l1 = lower[k], l0 = lower[k - 1], u1 = upper[k], u0 = upper[k - 1];
    if (!(l1 | l0 | u1 | u0)) return;
    const int alpha = shown(((wx * l1 + fx * l0) * wy + (wx * u1 + fx * u0) * fy + 128) >> 8);
    if (alpha >= 253)
      out[x] = ink;
    else if (alpha > 2)
      out[x] = mix565(out[x], ink, alpha);
  };
  // Blends kept row y into the surface: where the four samples are all
  // wholly opaque (both rows' runs, and the column before when fx), a fill;
  // where they're all clear, nothing; elsewhere sample by sample.
  auto emit = [&](int y, const Row& lower, const Row& upper) {
    const int out = y + dy, lo = std::min(lower.lo, upper.lo), hi = std::max(lower.hi, upper.hi);
    if (out < top || out >= under || lo > hi) return;
    uint16_t* row = s.pixels + out * s.width;
    const int from = std::max(lo + dx, left), to = std::min(hi + 1 + dx, right - 1);
    if (from > to) return;
    touch(from, out, to + 1, out + 1);
    int x = from;
    if (lower.runs > 0 && (!fy || upper.runs > 0)) {
      const Row& other = fy ? upper : lower;
      for (int i = 0, j = 0; i < lower.runs && j < other.runs;) {
        const int a = std::max(lower.run[i][0], other.run[j][0]) + (fx ? 1 : 0),
                  b = std::min(lower.run[i][1], other.run[j][1]), v = lower.run[i][2];
        const bool same = v == other.run[j][2];
        if (lower.run[i][1] < other.run[j][1])
          ++i;
        else
          ++j;
        const int runFrom = std::max(a + dx, x), runTo = std::min(b + dx, to + 1);
        if (!same || runFrom >= runTo || (v && !wholeShows)) continue;
        for (; x < runFrom; ++x) sample(row, x, lower.alpha, upper.alpha);
        if (v) std::fill(row + runFrom, row + runTo, ink);
        x = runTo;
      }
    }
    for (; x <= to; ++x) sample(row, x, lower.alpha, upper.alpha);
  };
  auto clear = [](Row* row) {
    if (row->hi >= row->lo) std::fill(row->alpha + row->lo, row->alpha + row->hi + 2, 0);
    row->reset();
  };
  // The row gathered, blended with the one above it; then it's the one above.
  auto finishRow = [&]() {
    if (!gathering) return;
    emit(hereY, *here, hasAbove ? *above : none);
    clear(above);
    std::swap(here, above);
    hasAbove = true, gathering = false;
  };
  // The shape's last row reaches fy sixteenths into the row under it.
  auto finishShape = [&]() {
    finishRow();
    if (!hasAbove) return;
    if (fy) emit(hereY + 1, none, *above);
    clear(above);
    hasAbove = false;
  };
  for (const uint8_t* code = r.data; code + sizeof(Span) <= r.data + r.used;) {
    Span span;
    std::memcpy(&span, code, sizeof span);
    code += sizeof span;
    // A row of one ink after the row above it in that ink: the same shape.
    if (!(gathering && span.ink == ink && span.y == hereY)) {
      const bool next = span.ink == ink && span.y == hereY + 1 && (gathering || hasAbove);
      if (next)
        finishRow();
      else
        finishShape();
      ink = span.ink, hereY = span.y, gathering = true;
    }
    // The span's kept columns, which a recording keeps on the surface.
    const int x0 = std::max(0, int(span.x0)), x1 = std::min(kMaxWidth - 3, span.x0 + span.n - 1);
    if (x0 > x1) {  // past the scratch: read past
      for (int x = span.x0, end = x + span.n; x < end;) {
        const int c = *code++;
        const int length = c & kRun ? (c & (kRun - 1)) + 1 : c + 1;
        code += c & kRun ? 1 : length, x += length;
      }
      continue;
    }
    // Two shapes of one ink on one row: where they meet, their union.
    const bool meets = x0 <= here->hi && x1 >= here->lo;
    if (meets) here->runs = -1;
    here->lo = std::min(here->lo, x0), here->hi = std::max(here->hi, x1);
    // [x, x + n) at the opacities `a` (one for all when `same`).
    auto put = [&](int x, int n, const uint8_t* a, bool same) {
      const int from = std::max(x, x0), to = std::min(x + n, x1 + 1);
      if (from >= to) return;
      uint8_t* v = here->alpha + 1 + from;
      if (!meets) {
        if (!same) return void(std::memcpy(v, a + (from - x), size_t(to - from)));
        std::memset(v, *a, size_t(to - from));
        if (*a != 0 && *a != 255) return;
        auto& runs = here->runs;
        if (runs > 0 && here->run[runs - 1][1] == from && here->run[runs - 1][2] == *a)
          here->run[runs - 1][1] = int16_t(to);
        else if (runs >= 0 && runs < kMostRuns)
          here->run[runs][0] = int16_t(from), here->run[runs][1] = int16_t(to), here->run[runs][2] = *a, ++runs;
        return;
      }
      for (int i = 0; i < to - from; ++i) {
        const int b = same ? *a : a[from - x + i];
        v[i] = uint8_t(v[i] ? v[i] + b - v[i] * b / 255 : b);
      }
    };
    for (int x = span.x0, end = x + span.n; x < end;) {
      const int c = *code++;
      if (c & kRun) {
        const int length = (c & (kRun - 1)) + 1;
        put(x, length, code, true);
        ++code, x += length;
      } else {
        put(x, c + 1, code, false);
        code += c + 1, x += c + 1;
      }
    }
  }
  finishShape();
}

}  // namespace render::gel
