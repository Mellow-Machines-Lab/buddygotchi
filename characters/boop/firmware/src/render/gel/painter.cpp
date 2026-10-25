// Projected, deforming gel dome. All frame work is integer and allocation-free.
#include "render/gel/painter.h"
#include "render/gel/drawer.h"
#include "render/gel/engine.h"
#include "render/gel/profile.h"
#include "render/gel/geometry.h"
#include "render/gel/layers.h"
#include "render/gel/finish.h"
#include "render/gel/pastimes.h"
#include "render/helper.h"
#include "slime_mesh.h"
#include <algorithm>
#include <array>
namespace render::gel {
namespace {
using render::helper;
// UVs span [0, 2^20] × [0, 2^19], a grid of 2^n + 1 texels each way: a
// texel is 2^kUShift of u and 2^kVShift of v.
constexpr int bits(int n) { return n > 1 ? 1 + bits(n / 2) : 0; }
constexpr int kUShift = 20 - bits(slime::kMaterialWidth - 1), kVShift = 19 - bits(slime::kMaterialHeight - 1);
static_assert((slime::kMaterialWidth - 1) << kUShift == 1 << 20 && (slime::kMaterialHeight - 1) << kVShift == 1 << 19,
              "UV rounding matches the generated material grid");
struct Vertex {
  int x, y, u, v;
};
int edge(const Vertex& a, const Vertex& b, int x, int y) { return (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x); }
int floor16(int v) { return v >= 0 ? v / 16 : -((15 - v) / 16); }
// Each UV rounds to the dense material grid.
int texelU(int t) { return (t + (1 << (kUShift - 1))) >> kUShift; }
int texelV(int t) { return (t + (1 << (kVShift - 1))) >> kVShift; }
uint16_t texel(int ut, int vt) {
  int tx = std::clamp(texelU(ut), 0, slime::kMaterialWidth - 1),
      ty = std::clamp(texelV(vt), 0, slime::kMaterialHeight - 1);
  return slime::kMaterial[ty * slime::kMaterialWidth + tx];
}
// `n` pixels of the material from (ut, vt), a step of (ux, vx) a pixel.
// The UVs step evenly, so when both ends round onto the grid every pixel
// between does: the loop that takes most of the body's time needs no clamp.
void texture(uint16_t* row, int ut, int vt, int ux, int vx, int n) {
  if (n <= 0) return;
  const auto onU = [](int t) { return unsigned(texelU(t)) < unsigned(slime::kMaterialWidth); };
  const auto onV = [](int t) { return unsigned(texelV(t)) < unsigned(slime::kMaterialHeight); };
  if (!onU(ut) || !onU(ut + ux * (n - 1)) || !onV(vt) || !onV(vt + vx * (n - 1))) {
    for (int x = 0; x < n; ++x, ut += ux, vt += vx) row[x] = texel(ut, vt);
    return;
  }
  ut += 1 << (kUShift - 1), vt += 1 << (kVShift - 1);
  for (int x = 0; x < n; ++x, ut += ux, vt += vx)
    row[x] = slime::kMaterial[(vt >> kVShift) * slime::kMaterialWidth + (ut >> kUShift)];
}
// A triangle's UVs as a plane: at pixel (x, y)'s centre, and their steps
// a pixel right and down. Each is its first corner's plus the others'
// differences from it, weighed by the edge functions over the triangle's
// `area` (edge's, twice its area) to 30 bits, so two triangles' UVs meet
// where they do (materialSeam). Whole UVs over 24 bits were a texel apart
// there, a dozen on a finish's body three times the size.
struct Plane {
  int tu, tv, ux, vx, uy, vy;
};
Plane uvPlane(const Vertex& a, const Vertex& b, const Vertex& c, int area, int x, int y) {
  const int e1 = edge(c, a, x * 16 + 8, y * 16 + 8), e2 = edge(a, b, x * 16 + 8, y * 16 + 8);
  const int dx1 = (c.y - a.y) * 16, dx2 = (a.y - b.y) * 16, dy1 = (a.x - c.x) * 16, dy2 = (b.x - a.x) * 16;
  const int64_t reciprocal = ((1u << 30) + unsigned(area) / 2) / unsigned(area);
  auto weigh = [&](int from, int to1, int to2, int w1, int w2) {
    return int(((int64_t(to1 - from) * w1 + int64_t(to2 - from) * w2) * reciprocal) >> 22);
  };
  return {a.u * 256 + weigh(a.u, b.u, c.u, e1, e2), a.v * 256 + weigh(a.v, b.v, c.v, e1, e2),
          weigh(a.u, b.u, c.u, dx1, dx2),           weigh(a.v, b.v, c.v, dx1, dx2),
          weigh(a.u, b.u, c.u, dy1, dy2),           weigh(a.v, b.v, c.v, dy1, dy2)};
}
// An inner triangle, by pixel centre: most of the body, kept to the
// tightest loop.
void fill(Surface& s, Vertex a, Vertex b, Vertex c, int from, int to) {
  int area = edge(a, b, c.x, c.y);
  if (area <= 0) return;
  int x0 = std::max(0, (std::min({a.x, b.x, c.x}) + 7) / 16),
      x1 = std::min(s.width - 1, (std::max({a.x, b.x, c.x}) - 8) / 16);
  int y0 = std::max(0, (std::min({a.y, b.y, c.y}) + 7) / 16),
      y1 = std::min(to - 1, (std::max({a.y, b.y, c.y}) - 8) / 16);
  const int start = std::max(y0, from);
  if (x0 > x1 || start > y1) return;
  s.touch(x0, start, x1 + 1, y1 + 1);
  int dx0 = (b.y - c.y) * 16, dx1 = (c.y - a.y) * 16, dx2 = (a.y - b.y) * 16;
  int dy0 = (c.x - b.x) * 16, dy1 = (a.x - c.x) * 16, dy2 = (b.x - a.x) * 16;
  int e0 = edge(b, c, x0 * 16 + 8, y0 * 16 + 8), e1 = edge(c, a, x0 * 16 + 8, y0 * 16 + 8),
      e2 = edge(a, b, x0 * 16 + 8, y0 * 16 + 8);
  const Plane uv = uvPlane(a, b, c, area, x0, y0);
  int tu = uv.tu, tv = uv.tv;
  const int ux = uv.ux, vx = uv.vx, uy = uv.uy, vy = uv.vy;
  // Set up at the triangle's own first row and stepped to `from`: the same
  // numbers as stepping row by row, so rows split between cores match.
  const int skip = start - y0;
  e0 += dy0 * skip, e1 += dy1 * skip, e2 += dy2 * skip, tu += uy * skip, tv += vy * skip;
  for (int y = start; y <= y1; ++y) {
    int lo = 0, hi = x1 - x0;
    auto clip = [&](int value, int step) {
      if (step > 0) {
        if (value < 0) lo = std::max(lo, (-value + step - 1) / step);
      } else if (step < 0) {
        if (value < 0)
          hi = -1;
        else
          hi = std::min(hi, value / -step);
      } else if (value < 0)
        hi = -1;
    };
    clip(e0, dx0);
    clip(e1, dx1);
    clip(e2, dx2);
    if (lo <= hi) {
      texture(s.pixels + y * s.width + x0 + lo, tu + ux * lo, tv + vx * lo, ux, vx, hi - lo + 1);
    }
    e0 += dy0;
    e1 += dy1;
    e2 += dy2;
    tu += uy;
    tv += vy;
  }
}

// The projected mesh, for the frame being drawn: every vertex, in
// sixteenths of a pixel. Kept small (internal RAM): 3.3 KB of positions.
constexpr int kRings = slime::kMeshRings, kSectors = slime::kMeshSectors;
int16_t px[kRings + 1][kSectors + 1], py[kRings + 1][kSectors + 1];
Vertex vertex(int ring, int col) {
  return Vertex{px[ring][col], py[ring][col], col * 4096 / kSectors, ring * 2048 / kRings};
}
// The rows each ring's triangles reach.
int16_t ringTop[kRings + 1], ringLow[kRings + 1];

// The outline: every edge between a front-facing triangle and one that
// isn't, wound as that triangle winds it, with its UVs as a plane from the
// pixel holding its first corner. The outline's pixels take the share of
// their area the body covers, from all of it at once (Outline::row), so
// the edge moves as smoothly as the mesh does: when a triangle turns away
// it has no area left, and neither has its share of the outline.
struct Rim {
  int16_t x0, y0, x1, y1;  // sixteenths of a pixel, its top end first
  int16_t ox, oy;          // its UVs' plane's origin, in pixels
  int sign;                // 1 if the triangle winds it downward, else -1
  int dxdy, dydx;          // its slopes, 16.16
  Plane uv;
};
// 9 KB; the most a pose has drawn is 138.
constexpr int kMaxRims = 192;
Rim rims[kMaxRims];
int rimCount = 0;
// Coverage as exact areas, in a 256th of a pixel high by half a 256th
// wide: a whole pixel is 256 × 512.
constexpr int kWhole = 256 * 512;
static_assert(kWhole == 1 << 17, "a pixel's coverage is the sum's top bits");
// The widest surface whose outline is drawn by coverage; a wider one's
// edges are drawn by pixel centre.
constexpr int kMaxWidth = 512;
// What a core keeps while it draws a band of rows' outline: each pixel the
// outline crosses, with what was under it and what goes over it.
struct Outline {
  int32_t acc[kMaxWidth + 2];
  uint8_t owner[kMaxWidth + 2];  // 1 + the rim whose plane shades the pixel, or 0
  struct Cell {
    int16_t x;
    uint16_t under;
    uint8_t alpha, rim;
  };
  // A band's rows' worth; a row has at most kMaxWidth.
  static constexpr int kMaxCells = 640;
  Cell cells[kMaxCells];
  int count = 0;
  int16_t rowStart[17];
  uint8_t near[kMaxRims];  // the rims in the band, in order of their tops
  int nearCount = 0;
  // A run of pixels a row's rims cross, [from, to].
  struct Run {
    int16_t from, to;
  };
  static constexpr int kMaxRuns = 48;
  Run runs[kMaxRuns];
  int runCount = 0;
  bool spill = false;  // more runs than that: the row's walked from the first
  int lowest = 0;
  // Adds rim r's part in pixel row y, in 256ths of a pixel: each pixel it
  // crosses takes the (signed, doubled) area to its right, the next pixel
  // the rest, so the sum along the row is the area the body covers.
  void add(int r, int y, int width) {
    const Rim& rim = rims[r];
    const int y0 = rim.y0 * 16, y1 = rim.y1 * 16, sign = rim.sign;
    const int ya = std::max(y0, y * 256), yb = std::min(y1, y * 256 + 256);
    if (ya >= yb) return;
    auto xAt = [&](int at) {
      return at >= y1 ? rim.x1 * 16 : rim.x0 * 16 + int((int64_t(rim.dxdy) * (at - y0)) >> 16);
    };
    int xa = xAt(ya), xb = xAt(yb), ta = ya, tb = yb;
    if (xa > xb) std::swap(xa, xb), std::swap(ta, tb);  // left to right
    const int lowY = std::min(ta, tb), highY = std::max(ta, tb);
    auto yAt = [&](int at) { return std::clamp(ta + int((int64_t(rim.dydx) * (at - xa)) >> 16), lowY, highY); };
    const int right = width * 256;
    if (xa >= right) return;  // nothing it covers shows
    int from = xa, fromY = ta;
    if (from < 0) {  // left of the surface, the whole row is to its right
      const int cut = xb <= 0 ? tb : yAt(0);
      acc[0] += sign * std::abs(cut - ta) * 512;
      from = 0, fromY = cut;
    }
    const int to = std::min(std::max(xb, 0), right), first = from >> 8;
    int last = first;
    for (int cell = first;; ++cell) {
      const int end = std::min(to, (cell + 1) * 256), endY = end >= xb ? tb : yAt(end);
      const int dy = sign * std::abs(endY - fromY), f = from - cell * 256, g = end - cell * 256;
      acc[cell] += dy * (512 - f - g);
      acc[cell + 1] += dy * (f + g);
      owner[cell] = uint8_t(r + 1);
      from = end, fromY = endY, last = cell;
      if (end >= to) break;
    }
    lowest = std::min(lowest, first);
    if (runCount < kMaxRuns)
      runs[runCount++] = {int16_t(first), int16_t(std::min(last + 1, width - 1))};
    else
      spill = true;
  }
  // Row y's outline pixels into the cells: each with its coverage, what's
  // under it now and the rim it's shaded by.
  void row(const Surface& s, int y) {
    runCount = 0, spill = false, lowest = s.width;
    for (int i = 0; i < nearCount; ++i) {
      const Rim& rim = rims[near[i]];
      if (rim.y0 >= (y + 1) * 16) break;  // in order of their tops: the rest start below
      if (rim.y1 > y * 16) add(near[i], y, s.width);
    }
    if (!runCount && !spill) return;
    if (spill) {
      runs[0] = {int16_t(lowest), int16_t(s.width - 1)}, runCount = 1;
    }
    for (int i = 1; i < runCount; ++i)  // in order along the row
      for (int j = i; j > 0 && runs[j - 1].from > runs[j].from; --j) std::swap(runs[j - 1], runs[j]);
    const uint16_t* pixels = s.pixels + y * s.width;
    // Between the runs the sum holds: the body's whole there, or none of
    // it, unless a level edge crosses the row, when those pixels are its
    // share too.
    int sum = 0, next = 0, shade = 0, alpha = 0;
    for (int i = 0; i < runCount; ++i) {
      const int from = std::max<int>(next, alpha > 0 && alpha < 255 ? next : runs[i].from);
      for (int x = from; x <= runs[i].to; ++x) {
        sum += acc[x], acc[x] = 0;
        if (owner[x]) shade = owner[x], owner[x] = 0;
        alpha = std::min(255, std::abs(sum) * 255 >> 17);
        // Wholly covered, its centre is in a triangle, which fills it; a
        // pixel barely covered may hold a sliver's centre, and is put back.
        if (alpha >= 253) continue;
        cells[count++] = {int16_t(x), pixels[x], uint8_t(alpha), uint8_t(shade - 1)};
      }
      next = std::max<int>(next, runs[i].to + 1);
    }
    acc[s.width] = acc[s.width + 1] = 0, owner[s.width] = owner[s.width + 1] = 0;
  }
};
Outline outlines[2];
// Each rim's UVs: its triangle's, from the pixel holding its first corner.
void plane(Rim& rim, Vertex a, Vertex b, Vertex c) {
  rim.ox = int16_t(floor16(a.x)), rim.oy = int16_t(floor16(a.y));
  rim.uv = uvPlane(a, b, c, edge(a, b, c.x, c.y), rim.ox, rim.oy);
}
// The body's rows [from, to), a band at most: the outline's pixels found
// and what's under them kept, every front-facing triangle filled by pixel
// centre, then the outline's pixels laid over by their coverage. All in
// the same order whichever core draws them, so a row comes out the same.
void body(Surface& s, Outline& o, int from, int to) {
  const bool outlined = s.width <= kMaxWidth;
  o.nearCount = 0;
  if (outlined)
    for (int i = 0; i < rimCount; ++i) {
      const Rim& r = rims[i];
      if (r.y1 > from * 16 && r.y0 < to * 16) {
        int j = o.nearCount++;
        for (; j > 0 && rims[o.near[j - 1]].y0 > r.y0; --j) o.near[j] = o.near[j - 1];
        o.near[j] = uint8_t(i);
      }
    }
  for (int y = from; y < to;) {
    // As many rows as the cells hold (a row takes at most the surface's
    // width).
    o.count = 0;
    int end = y;
    static_assert(Outline::kMaxCells >= kMaxWidth, "a row's cells fit");
    for (; end < to && (!outlined || o.count + s.width <= Outline::kMaxCells); ++end) {
      o.rowStart[end - y] = int16_t(o.count);
      if (outlined) o.row(s, end);
    }
    o.rowStart[end - y] = int16_t(o.count);
    // A quad's two triangles: (above[c], here[c], above[c+1]) and
    // (above[c+1], here[c], here[c+1]).
    for (int ring = 1; ring <= kRings; ++ring)
      for (int col = 0; col < kSectors && ringTop[ring] < end && ringLow[ring] >= y; ++col) {
        fill(s, vertex(ring - 1, col), vertex(ring, col), vertex(ring - 1, col + 1), y, end);
        fill(s, vertex(ring - 1, col + 1), vertex(ring, col), vertex(ring, col + 1), y, end);
      }
    for (int row = y; row < end; ++row) {
      uint16_t* pixels = s.pixels + row * s.width;
      int lo = s.width, hi = -1;
      for (int i = o.rowStart[row - y]; i < o.rowStart[row - y + 1]; ++i) {
        const auto& cell = o.cells[i];
        if (cell.alpha <= 2) {
          pixels[cell.x] = cell.under;
          continue;
        }
        const Rim& rim = rims[cell.rim];
        const int dx = cell.x - rim.ox, dy = row - rim.oy;
        const Plane& uv = rim.uv;
        const uint16_t ink = texel(uv.tu + uv.ux * dx + uv.uy * dy, uv.tv + uv.vx * dx + uv.vy * dy);
        pixels[cell.x] = mix565(cell.under, ink, cell.alpha);
        lo = std::min<int>(lo, cell.x), hi = std::max<int>(hi, cell.x);
      }
      if (lo <= hi) s.touch(lo, row, hi + 1, row + 1);
    }
    y = end;
  }
}
// Rows [from, to) of the frame, a band at a time: each band erased
// (Surface::erase), unless it was before anything was drawn behind the
// body, then the body's triangles drawn in it while its pixels are still
// in the cache. The body stops at row `body`, above the host's lane.
struct Rows {
  Surface* s;
  const Surface::Erasing* erasing;
  Outline* outline;
  int from, to, body;
  uint32_t us;  // how long they took
};
constexpr int kEraseBand = 16;
void draw(Rows& rows) {
  for (int y = rows.from; y < rows.to; y += kEraseBand) {
    const int end = std::min(rows.to, y + kEraseBand);
    if (rows.erasing) rows.s->erase(*rows.erasing, y, end);
    if (y < rows.body) body(*rows.s, *rows.outline, y, std::min(end, rows.body));
  }
}
// The rows the helper draws (render/helper.h).
void helped(void* job) {
  auto& rows = *static_cast<Rows*>(job);
  const uint32_t start = helper.micros();
  draw(rows);
  rows.us = helper.micros() - start;
}
// The share of the body's rows this core keeps when the helper draws the
// rest, in 1/1024: moved each frame toward both finishing together.
int share = 512;
}  // namespace
void paint(Surface& s, const PaintControls& c, const Box* keep, int keepCount, uint32_t keepLane, rig::Anchors* anchors,
           const PastimeShow* scenery) {
  if (!s.pixels) return;
  // What the last frame wrote is erased with the body, row by row
  // (paintBody): the clear's own time is only its books. Scenery behind the
  // body needs the whole surface erased before it's drawn.
  Surface::Erasing erasing;
  {
    Measure measure(profile.clear);
    erasing = s.beginClear(keep, keepCount, keepLane);
  }
  const bool behind = scenery && showsScenery(*scenery);
  if (behind) {
    Measure measure(profile.props);
    s.erase(erasing, 0, s.height);
    paintScenery(s, *scenery);
  }
  paintBody(s, c, anchors, behind ? nullptr : &erasing);
}
void paintBody(Surface& s, const PaintControls& c, rig::Anchors* anchors, const Surface::Erasing* erase) {
  if (!s.pixels) return;
  // Every vertex first, then which way each triangle faces, so a triangle
  // knows which of its edges are the outline: those whose neighbour faces
  // away. Positions are in sixteenths of a pixel; the UVs follow from the
  // grid.
  static int8_t faces[kRings + 1][kSectors][2];
  Projector camera(s, c);
  int top = 1 << 30, low = -(1 << 30);
  for (int ring = 0; ring <= kRings; ++ring)
    for (int col = 0; col <= kSectors; ++col) {
      const auto& src = slime::kMesh[ring * (kSectors + 1) + col];
      World world{src.x + product(c.ripple, src.wx), src.y, src.z + product(c.ripple, src.wz)};
      int dx = product(src.bx, 15974), dy = product(src.by - 819, 12698),
          dent = std::max(0, 4096 - int((int64_t(dx) * dx + int64_t(dy) * dy) / 4096));
      dent = product(product(dent, dent), src.front);
      auto p = camera.project(camera.deform(world, src.h, src.h2, src.front, dent));
      px[ring][col] = int16_t(std::clamp(p.x, -32000, 32000));
      py[ring][col] = int16_t(std::clamp(p.y, -32000, 32000));
      top = std::min<int>(top, py[ring][col]), low = std::max<int>(low, py[ring][col]);
    }
  if (anchors) {  // the sides are the columns at the ends of x, the front's the quarter turn toward the camera
    auto at = [&](int ring, int col) { return rig::Point{px[ring][col], py[ring][col]}; };
    anchors->crown = at(0, 0);
    anchors->brimL = at(kBrimRing, kSectors / 2), anchors->brimF = at(kBrimRing, kSectors / 4);
    anchors->brimR = at(kBrimRing, 0);
    anchors->handF = at(kHandRing, kSectors / 4);
    static_assert(rig::Anchors::kRingPoints == kSectors / 2 + 1, "a ring's front half, a point a column");
    for (int i = 0; i < rig::Anchors::kRingPoints; ++i)
      anchors->lap[i] = at(kLapRing, kSectors / 2 - i), anchors->hem[i] = at(kHemRing, kSectors / 2 - i);
  }
  auto sign = [](int area) { return int8_t(area > 0 ? 1 : area < 0 ? -1 : 0); };
  for (int ring = 1; ring <= kRings; ++ring)
    for (int col = 0; col < kSectors; ++col) {
      const Vertex a = vertex(ring - 1, col), b = vertex(ring, col), c1 = vertex(ring - 1, col + 1),
                   d = vertex(ring, col + 1);
      faces[ring][col][0] = sign(edge(a, b, c1.x, c1.y));
      faces[ring][col][1] = sign(edge(c1, b, d.x, d.y));
    }
  // The outline: each front-facing triangle's edges to a neighbour that
  // isn't. A triangle with no area left counts as turned away, so where it
  // lies between two that face, the rims on either side of it cancel. The
  // poles' openings are a sixteenth of a pixel across, and count as closed.
  auto away = [&](int ring, int col, int which) {
    return ring >= 1 && ring <= kRings && faces[ring][(col + kSectors) % kSectors][which] <= 0;
  };
  rimCount = 0;
  for (int ring = 1; ring <= kRings && rimCount >= 0; ++ring)
    for (int col = 0; col < kSectors && rimCount >= 0; ++col) {
      // A quad's two triangles, (above, here, next) and (next, here,
      // below); bit k of `soft`, the edge opposite corner k.
      const unsigned soft[2] = {
          (away(ring, col, 1) ? 1u : 0u) | (away(ring - 1, col, 1) ? 2u : 0u) | (away(ring, col - 1, 1) ? 4u : 0u),
          (away(ring + 1, col, 0) ? 1u : 0u) | (away(ring, col + 1, 0) ? 2u : 0u) | (away(ring, col, 0) ? 4u : 0u)};
      const Vertex above = vertex(ring - 1, col), here = vertex(ring, col), next = vertex(ring - 1, col + 1),
                   below = vertex(ring, col + 1);
      for (int which = 0; which < 2; ++which) {
        if (faces[ring][col][which] <= 0 || !soft[which]) continue;
        const Vertex v[3] = {which ? next : above, here, which ? below : next};
        Rim rim{};
        plane(rim, v[0], v[1], v[2]);
        for (int k = 0; k < 3; ++k)
          if (soft[which] >> k & 1) {
            if (rimCount == kMaxRims) {  // past any pose's: drawn by pixel centre
              rimCount = -1;
              break;
            }
            const Vertex &from = v[(k + 1) % 3], &to = v[(k + 2) % 3];
            if (from.y == to.y) continue;  // level: no area to its right changes
            const bool down = to.y > from.y;
            const Vertex &top = down ? from : to, &end = down ? to : from;
            rim.x0 = int16_t(top.x), rim.y0 = int16_t(top.y), rim.x1 = int16_t(end.x), rim.y1 = int16_t(end.y);
            rim.sign = down ? 1 : -1;
            const int64_t dx = end.x - top.x, dy = end.y - top.y;
            rim.dxdy = int(std::clamp<int64_t>((dx << 16) / dy, INT32_MIN, INT32_MAX));
            rim.dydx = dx ? int(std::clamp<int64_t>((dy << 16) / dx, INT32_MIN, INT32_MAX)) : 0;
            rims[rimCount++] = rim;
          }
        if (rimCount < 0) break;
      }
    }
  rimCount = std::max(rimCount, 0);
  for (int ring = 1; ring <= kRings; ++ring) {
    int lo = 1 << 30, hi = -(1 << 30);
    for (int col = 0; col <= kSectors; ++col)
      for (int r : {ring - 1, ring}) lo = std::min<int>(lo, py[r][col]), hi = std::max<int>(hi, py[r][col]);
    ringTop[ring] = int16_t(std::clamp(floor16(lo - 16), -1, 32000)), ringLow[ring] = int16_t(std::clamp(hi / 16 + 1, -1, 32000));
  }
  // The body stops above the host's lane, the bottom fifth. With a helper,
  // it draws (and erases) the lower rows while this core does the upper
  // ones; the rows it erases are all the surface's.
  const int rows = s.height * 4 / 5;
  Rows upper{&s, erase, &outlines[0], 0, erase ? s.height : rows, rows, 0};
  if (!helper) return draw(upper);
  const int first = std::clamp(top / 16, 0, rows), last = std::clamp(low / 16 + 2, first, rows);
  static Rows lower;
  upper.to = first + (last - first) * share / 1024;
  lower = {&s, erase, &outlines[1], upper.to, erase ? s.height : rows, rows, 0};
  helper.start(helped, &lower);
  const uint32_t start = helper.micros();
  draw(upper);
  const uint32_t mine = helper.micros() - start;
  helper.join();
  share = std::clamp(share + (lower.us > mine ? 8 : -8), 128, 896);
}
int materialSeam(Surface& s, const PaintControls& c) {
  paintBody(s, c);
  int worst = 0;
  // Two triangles meeting on edge pq, each its UVs' plane at both of the
  // edge's ends (from the pixels holding them); each a pixel in size at
  // least (at the poles, where u has no one value, they're slivers).
  auto meet = [&](Vertex a0, Vertex b0, Vertex c0, Vertex a1, Vertex b1, Vertex c1, Vertex p, Vertex q) {
    const int area0 = edge(a0, b0, c0.x, c0.y), area1 = edge(a1, b1, c1.x, c1.y);
    if (area0 < 2 * 256 || area1 < 2 * 256) return;
    for (const Vertex& at : {p, q}) {
      const int x = floor16(at.x), y = floor16(at.y), dx = at.x - x * 16 - 8, dy = at.y - y * 16 - 8;
      const Plane one = uvPlane(a0, b0, c0, area0, x, y), other = uvPlane(a1, b1, c1, area1, x, y);
      const int du = one.tu - other.tu + ((one.ux - other.ux) * dx + (one.uy - other.uy) * dy) / 16,
                dv = one.tv - other.tv + ((one.vx - other.vx) * dx + (one.vy - other.vy) * dy) / 16;
      worst = std::max({worst, (std::abs(du) << 8) >> kUShift, (std::abs(dv) << 8) >> kVShift});
    }
  };
  for (int ring = 1; ring <= kRings; ++ring)
    for (int col = 0; col < kSectors; ++col) {
      const Vertex above = vertex(ring - 1, col), here = vertex(ring, col), next = vertex(ring - 1, col + 1),
                   below = vertex(ring, col + 1);
      // The quad's diagonal, then its edges with the next quad and the one below.
      meet(above, here, next, next, here, below, here, next);
      if (col + 1 < kSectors) meet(next, here, below, next, below, vertex(ring - 1, col + 2), next, below);
      if (ring < kRings) meet(next, here, below, here, vertex(ring + 1, col), below, here, below);
    }
  return worst;
}
void applyRig(PaintControls& c, const rig::Channels& rig) {
  using rig::Channel;
  const auto off = [&](Channel ch) { return rig[ch] - rig::kRest[ch]; };
  // The engine's own bounds on its pose and life (Engine::pose, life).
  c.lean = std::clamp(c.lean + off(Channel::kLean) * 4096 / 1000, -5120, 5120);
  c.squash = std::clamp(c.squash - off(Channel::kSquash) * 4096 / 1000, -5407, 5407);
  c.lift = std::clamp(c.lift + off(Channel::kLift) * 4096 / kPxPerUnit, 0, 983);
  const int open = std::min(rig[Channel::kEyeOpenL], rig[Channel::kEyeOpenR]);
  c.blink = std::max(c.blink, (1000 - open) * 4096 / 1000);
  c.eyeSize = rig[Channel::kEyeSize] * 4096 / 1000;
  c.gaze += off(Channel::kGazeX) * kRigGaze / 1000;
  c.gazeUp = -off(Channel::kGazeY) * kRigGaze / 1000;
}
void paint(Surface& surface, const Engine& e, bool mouthOpen, int dy, uint32_t keepLane, rig::Anchors* anchors,
           const rig::Channels& rig, const rig::Layers* layers, uint32_t t, const PastimeShow* pastimes,
           const DrawerPose* squeeze) {
  auto pose = e.pose();
  auto life = e.life();
  PaintControls c;
  c.lean = scalar(pose[0]);
  c.squash = scalar(pose[1]);
  c.ripple = scalar(pose[2]);
  c.dent = scalar(pose[3]);
  c.blink = scalar(e.blink());
  c.slide = scalar(e.acting.slide.x);
  c.gaze = scalar(e.motion.gaze);
  c.lift = scalar(life[0]);
  c.roll = scalar(life[1]);
  c.forward = scalar(life[2] + e.pull[2].x * q(.3));
  c.grabX = scalar(e.pull[0].x);
  c.grabY = scalar(e.pull[1].x);
  c.dy = dy;
  c.blink = std::max(c.blink, sleepyLids(e));
  applyRig(c, rig);
  if (squeeze) c.squeezeTop = squeeze->top, c.squeezeBottom = squeeze->bottom, c.widen = squeeze->widen;
  const bool bodyAlone = squeeze && squeeze->squint;
  // A finish moves, scales and squashes the body, its face with it; under
  // the drawer it waits.
  const FinishShow finish = squeeze ? FinishShow{} : e.scenes.finishShow();
  FinishPose move;
  if (finish.on) {
    move = finishPose(surface, finish.finish, finish.ageMs, finish.revealMs);
    const Point anchor = finishAnchor(surface);
    c.anchorX = anchor.x, c.anchorY = anchor.y;
    c.offsetX = move.dx16, c.offsetY = move.dy16, c.scale = move.scale;
    c.squash = std::clamp(c.squash + move.squash, -5407, 5407);
    c.lean = std::clamp(c.lean + move.lean, -5120, 5120);
    c.eyes = !move.starEyes;
  }
  const bool mouth = mouthOpen || rig[rig::Channel::kMouthOpen] >= kRigMouthOpen;
  rig::Anchors local;
  if (!anchors) anchors = &local;
  {
    Measure measure(profile.body);
    Box cards[Surface::kMaxKeep];
    const int kept = bodyAlone ? 0 : opaqueCards(surface, e, cards);
    // The last frame's pixels are erased as the body is drawn over them
    // (paintBody), unless something goes under the body first, or the
    // parade's several bodies stand in for it.
    const bool scenery = pastimes && !bodyAlone && showsScenery(*pastimes);
    Surface::Erasing erasing;
    {
      Measure clear(profile.clear);
      erasing = surface.beginClear(cards, kept, keepLane);
      if (scenery || finish.on) surface.erase(erasing, 0, surface.height);
    }
    if (scenery) {
      Measure measure(profile.props);
      paintScenery(surface, *pastimes);
    }
    if (finish.on) paintFinishBehind(surface, finish.finish, finish.ageMs, finish.revealMs);
    if (!move.minis) paintBody(surface, c, anchors, scenery || finish.on ? nullptr : &erasing);
  }
  if (bodyAlone) return;
  if (move.minis) {
    // The parade: its little ones stand in for it, each with its face.
    FinishPose minis[kParadeMinis];
    const int n = finishMinis(surface, finish.ageMs, minis);
    for (int i = 0; i < n; ++i) {
      PaintControls m = c;
      m.offsetX = minis[i].dx16, m.offsetY = minis[i].dy16, m.scale = minis[i].scale;
      m.squash = std::clamp(c.squash + minis[i].squash, -5407, 5407);
      m.lean = std::clamp(c.lean + minis[i].lean, -5120, 5120);
      paintBody(surface, m);
      paintArt(surface, e, m, mouth);
    }
  } else {
    Measure measure(profile.art);
    paintArt(surface, e, c, mouth, anchors);
  }
  if (!move.minis) {
    Measure measure(profile.layers);
    paintLayers(surface, e, *anchors, layers, t);
    if (pastimes) paintWorn(surface, *pastimes, *anchors);
  }
  if (finish.on)
    paintFinishFront(surface, finish.finish, finish.ageMs, finish.revealMs, *anchors, c.scale, finish.gift);
  {
    Measure measure(profile.props);
    paintProps(surface, e);
  }
}
}  // namespace render::gel
