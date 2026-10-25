// Projected, deforming gel dome. All frame work is integer and allocation-free.
#include "render/gel/painter.h"
#include "render/gel/drawer.h"
#include "render/gel/engine.h"
#include "render/gel/finish.h"
#include "render/gel/geometry.h"
#include "render/gel/layers.h"
#include "render/gel/pastimes.h"
#include "render/gel/profile.h"
#include "render/helper.h"
#include "slime_mesh.h"
#include <algorithm>
#include <array>
#include <cstring>
namespace render::gel {
namespace {
using render::helper;
struct Vertex {
  int x, y, u, v;
  // On the outline, where the fringes of its two edges there part: the
  // line through it across (bx, by), the sum of their directions, the
  // larger of the two 127. Or, where the outline turns back more than a
  // right angle, each fringe ends square (bx kSquare); where it passes
  // twice, each runs a pixel past (kOverlap).
  int bx = 0, by = 0;
};
constexpr int kSquare = 1, kOverlap = -128;
bool turns(const Vertex& v) { return std::max(std::abs(v.bx), std::abs(v.by)) == 127; }
int edge(const Vertex& a, const Vertex& b, int x, int y) { return (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x); }
int floor16(int v) { return v >= 0 ? v / 16 : -((15 - v) / 16); }
// The material at its two sizes (slime_mesh.h), one after the other: each
// a grid of texels from `offset`, a texel every 2^shift of the UVs, which
// span [0, 2^20] × [0, 2^19]. A triangle whose texels crowd under its
// pixels reads the smaller.
struct Level {
  int offset, width, height, shift;
};
constexpr Level kLevels[2] = {{0, slime::kMaterialWidth, slime::kMaterialHeight, 10},
                              {slime::kMaterialHalf, slime::kMaterialHalfWidth, slime::kMaterialHalfHeight, 11}};
static_assert((slime::kMaterialWidth - 1) << 10 == 1 << 20 && (slime::kMaterialHeight - 1) << 10 == 1 << 19 &&
                  (slime::kMaterialHalfWidth - 1) << 11 == 1 << 20 && (slime::kMaterialHalfHeight - 1) << 11 == 1 << 19,
              "UV rounding matches the generated material grids");
int texelAt(int t, int shift) { return (t + (1 << shift >> 1)) >> shift; }
// Where the body reads the material: as linked, or a copy the board made
// somewhere quicker to read (readMaterialFrom).
const uint16_t* material = slime::kMaterial;
uint16_t texel(int ut, int vt, const Level& l) {
  int tx = std::clamp(texelAt(ut, l.shift), 0, l.width - 1), ty = std::clamp(texelAt(vt, l.shift), 0, l.height - 1);
  return material[l.offset + ty * l.width + tx];
}
// `n` pixels of the material from (ut, vt), a step of (ux, vx) a pixel.
// The UVs step evenly, so when both ends round onto the grid every pixel
// between does: the loop that takes most of the body's time needs no clamp.
void texture(uint16_t* row, int ut, int vt, int ux, int vx, int n, const Level& l) {
  if (n <= 0) return;
  const auto on = [&](int t, int size) { return unsigned(texelAt(t, l.shift)) < unsigned(size); };
  if (!on(ut, l.width) || !on(ut + ux * (n - 1), l.width) || !on(vt, l.height) || !on(vt + vx * (n - 1), l.height)) {
    for (int x = 0; x < n; ++x, ut += ux, vt += vx) row[x] = texel(ut, vt, l);
    return;
  }
  const uint16_t* texels = material + l.offset;
  const int width = l.width, shift = l.shift;
  ut += 1 << shift >> 1, vt += 1 << shift >> 1;
  for (int x = 0; x < n; ++x, ut += ux, vt += vx) row[x] = texels[(vt >> shift) * width + (ut >> shift)];
}
// The rows drawn at a time (draw).
constexpr int kEraseBand = 16;
// An inner triangle, by pixel centre: most of the body, kept to the
// tightest loop.
void fill(Surface& s, Vertex a, Vertex b, Vertex c, const Level& level, int from, int to) {
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
  const int reciprocal = (1 << 24) / area;
  auto color = [&](int ar, int br, int cr, int u, int v, int w) {
    return int((int64_t(ar) * u + int64_t(br) * v + int64_t(cr) * w) * reciprocal / 65536);
  };
  int tu = color(a.u, b.u, c.u, e0, e1, e2), tv = color(a.v, b.v, c.v, e0, e1, e2);
  int ux = color(a.u, b.u, c.u, dx0, dx1, dx2), vx = color(a.v, b.v, c.v, dx0, dx1, dx2);
  int uy = color(a.u, b.u, c.u, dy0, dy1, dy2), vy = color(a.v, b.v, c.v, dy0, dy1, dy2);
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
      texture(s.pixels + y * s.width + x0 + lo, tu + ux * lo, tv + vx * lo, ux, vx, hi - lo + 1, level);
    }
    e0 += dy0;
    e1 += dy1;
    e2 += dy2;
    tu += uy;
    tv += vy;
  }
}

// Fills a front-facing triangle by pixel centre, in rows [from, to). Its
// edges named in `outline` (bit 0: b→c, 1: c→a, 2: a→b) are the body's
// outline, and each has a soft fringe a pixel wide beyond it: there a
// pixel takes the share of the pixel beyond the edge it's nearer than, over
// what's behind the body. So the body is drawn a half pixel fuller, each
// pixel its share of that shape. A fringe ends at its edge's ends, where it
// meets the next edge's fringe (Vertex's bx, by), not where the triangle's
// other edges would end it: a sliver of a triangle on the outline, about to
// turn away or just turned toward the camera, still draws the fringe beyond
// it, and the outline doesn't jump as the mesh turns.
void triangle(Surface& s, Vertex a, Vertex b, Vertex c, unsigned outline, const Level& level, int from, int to) {
  if (!outline) return fill(s, a, b, c, level, from, to);
  int area = edge(a, b, c.x, c.y);
  if (area <= 0) return;
  constexpr int pad = 16;  // the fringe
  int x0 = std::max(0, floor16(std::min({a.x, b.x, c.x}) - pad + 7)),
      x1 = std::min(s.width - 1, floor16(std::max({a.x, b.x, c.x}) + pad - 8));
  int y0 = std::max(0, floor16(std::min({a.y, b.y, c.y}) - pad + 7)),
      y1 = std::min(to - 1, floor16(std::max({a.y, b.y, c.y}) + pad - 8));
  const int start = std::max(y0, from);
  if (x0 > x1 || start > y1) return;
  s.touch(x0, start, x1 + 1, y1 + 1);
  const Vertex* corners[3] = {&a, &b, &c};
  int dx[3] = {(b.y - c.y) * 16, (c.y - a.y) * 16, (a.y - b.y) * 16};
  int dy[3] = {(c.x - b.x) * 16, (a.x - c.x) * 16, (b.x - a.x) * 16};
  int e[3] = {edge(b, c, x0 * 16 + 8, y0 * 16 + 8), edge(c, a, x0 * 16 + 8, y0 * 16 + 8),
              edge(a, b, x0 * 16 + 8, y0 * 16 + 8)};
  // Per outline edge, from p to q: a pixel, in edge-function units (16 of
  // the edge's lengths), and which side of the lines where its fringe ends
  // each pixel's centre is: (centre - p)·p's bend and (q - centre)·q's, both
  // at least 0 beside it.
  int pixel[3] = {0, 0, 0};
  int after[3] = {0, 0, 0}, before[3] = {0, 0, 0};
  int afterX[3] = {0, 0, 0}, afterY[3] = {0, 0, 0}, beforeX[3] = {0, 0, 0}, beforeY[3] = {0, 0, 0};
  for (int k = 0; k < 3; ++k) {
    if (!(outline >> k & 1)) continue;
    const Vertex &p = *corners[(k + 1) % 3], &q = *corners[(k + 2) % 3];
    const int tx = q.x - p.x, ty = q.y - p.y;
    pixel[k] = 16 * std::max(1, root(uint32_t(tx * tx + ty * ty)));
    // Square ends go across the edge itself, and an overlapping one a
    // pixel past its end: its direction, as large as a bend's.
    const int most = std::max(1, std::max(std::abs(tx), std::abs(ty))), sx = tx * 127 / most, sy = ty * 127 / most;
    const int past = 16 * root(uint32_t(sx * sx + sy * sy));
    const bool turnP = turns(p), turnQ = turns(q);
    const int px = turnP ? p.bx : sx, py = turnP ? p.by : sy, qx = turnQ ? q.bx : sx, qy = turnQ ? q.by : sy;
    // 32-bit: a bend's parts are under 128.
    after[k] = (x0 * 16 + 8 - p.x) * px + (y0 * 16 + 8 - p.y) * py + (p.bx == kOverlap ? past : 0);
    before[k] = (q.x - x0 * 16 - 8) * qx + (q.y - y0 * 16 - 8) * qy + (q.bx == kOverlap ? past : 0);
    afterX[k] = px * 16, afterY[k] = py * 16, beforeX[k] = -qx * 16, beforeY[k] = -qy * 16;
  }
  const int reciprocal = (1 << 24) / area;
  auto color = [&](int ar, int br, int cr, int u, int v, int w) {
    return int((int64_t(ar) * u + int64_t(br) * v + int64_t(cr) * w) * reciprocal / 65536);
  };
  int tu = color(a.u, b.u, c.u, e[0], e[1], e[2]), tv = color(a.v, b.v, c.v, e[0], e[1], e[2]);
  int ux = color(a.u, b.u, c.u, dx[0], dx[1], dx[2]), vx = color(a.v, b.v, c.v, dx[0], dx[1], dx[2]);
  int uy = color(a.u, b.u, c.u, dy[0], dy[1], dy[2]), vy = color(a.v, b.v, c.v, dy[0], dy[1], dy[2]);
  // The columns from 0 where value + step * x >= 0 stay within [lo, hi].
  auto clip = [](int value, int step, int& lo, int& hi) {
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
  const int skip = start - y0;  // as fill's
  for (int k = 0; k < 3; ++k) e[k] += dy[k] * skip, after[k] += afterY[k] * skip, before[k] += beforeY[k] * skip;
  tu += uy * skip, tv += vy * skip;
  for (int y = start; y <= y1; ++y) {
    auto* row = s.pixels + y * s.width + x0;
    // Inside, by pixel centre.
    int lo = 0, hi = x1 - x0;
    for (int k = 0; k < 3; ++k) clip(e[k], dx[k], lo, hi);
    if (lo <= hi) texture(row + lo, tu + ux * lo, tv + vx * lo, ux, vx, hi - lo + 1, level);
    // Each outline edge's fringe: centres beyond it by under a pixel, and
    // beside it.
    for (int k = 0; k < 3; ++k) {
      if (!pixel[k]) continue;
      int from = 0, to = x1 - x0;
      clip(-e[k] - 1, -dx[k], from, to);
      clip(e[k] + pixel[k] - 1, dx[k], from, to);
      clip(after[k], afterX[k], from, to);
      clip(before[k], beforeX[k], from, to);
      for (int x = from; x <= to; ++x) {
        // Within a pixel of the edge, so 32-bit, and the board divides in
        // hardware.
        const int cover = (e[k] + dx[k] * x + pixel[k]) * 255 / pixel[k];
        if (cover > 2) row[x] = mix565(row[x], texel(tu + ux * x, tv + vx * x, level), cover);
      }
    }
    for (int k = 0; k < 3; ++k) e[k] += dy[k], after[k] += afterY[k], before[k] += beforeY[k];
    tu += uy;
    tv += vy;
  }
}

// The projected mesh, for the frame being drawn: every vertex, in
// sixteenths of a pixel, and of each quad's two triangles whether it faces
// the camera (bit 3) and which of its edges are the outline (the rest, as
// triangle's `outline`). Kept small (internal RAM): 3.3 KB of positions,
// 1.6 KB of triangles.
constexpr int kRings = slime::kMeshRings, kSectors = slime::kMeshSectors;
int16_t px[kRings + 1][kSectors + 1], py[kRings + 1][kSectors + 1];
uint8_t tris[kRings + 1][kSectors][2];
constexpr uint8_t kToward = 8;
// Each outline vertex's bend (Vertex's bx, by). A pole is one point, but
// each of its columns keeps its own: the outline may pass it more than once.
int8_t bends[kRings + 1][kSectors][2];
int8_t* bend(int ring, int col) { return bends[ring][col % kSectors]; }
Vertex vertex(int ring, int col) {
  const int8_t* b = bend(ring, col);
  return Vertex{px[ring][col], py[ring][col], col * 4096 / kSectors, ring * 2048 / kRings, b[0], b[1]};
}
// A quad's two triangles: (above[c], here[c], above[c+1]) and
// (above[c+1], here[c], here[c+1]), `which` 0 and 1.
struct Tri {
  int ring, col, which;
  bool operator==(const Tri& t) const { return ring == t.ring && col == t.col && which == t.which; }
};
constexpr int8_t kCorner[2][3][2] = {{{-1, 0}, {0, 0}, {-1, 1}}, {{-1, 1}, {0, 0}, {0, 1}}};
Vertex corner(Tri t, int i) { return vertex(t.ring + kCorner[t.which][i][0], t.col + kCorner[t.which][i][1]); }
// The triangle across edge k (0: b→c, 1: c→a, 2: a→b) of t, its column
// within the ring. The dome is closed: the first ring's first triangles and
// the last ring's second ones meet at its poles and have no area, so
// they're no one's neighbours: across the edges they'd share, a pole's
// triangles meet the triangles beside them in the ring (the crown's are on
// the outline, seen from the camera's height).
Tri across(Tri t, int k) {
  const bool crown = t.ring == 1, base = t.ring == kRings;
  Tri n;
  if (t.which == 0)
    n = k == 0   ? (base ? Tri{t.ring, t.col + 1, 0} : Tri{t.ring, t.col, 1})
        : k == 1 ? Tri{t.ring - 1, t.col, 1}
                 : (base ? Tri{t.ring, t.col - 1, 0} : Tri{t.ring, t.col - 1, 1});
  else
    n = k == 0   ? Tri{t.ring + 1, t.col, 0}
        : k == 1 ? (crown ? Tri{t.ring, t.col + 1, 1} : Tri{t.ring, t.col + 1, 0})
                 : (crown ? Tri{t.ring, t.col - 1, 1} : Tri{t.ring, t.col, 0});
  n.col = (n.col + kSectors) % kSectors;
  return n;
}
// Whether t faces the camera; past the poles, nothing does.
bool toward(Tri t) { return t.ring >= 1 && t.ring <= kRings && tris[t.ring][t.col][t.which] & kToward; }
// The rows each ring's triangles reach, an outline's fringe included.
int16_t ringTop[kRings + 1], ringLow[kRings + 1];
// The body's rows [from, to): every front-facing triangle there, in the same
// order whichever core draws them, so a row comes out the same.
// Which triangles read the smaller material, a bit each (col * 2 + which):
// those whose texels crowd more than one and a half under a pixel, at
// rest, as the AMOLED draws the dome. Fixed, so a triangle's grain never
// changes as it moves.
uint64_t smaller[kRings + 1];
void body(Surface& s, int from, int to) {
  // Whether a quad's rows, its fringe's included, reach [from, to): asked
  // first, of its corners' rows alone, as most of a ring's don't.
  const auto reaches = [&](int ring, int col) {
    const int lo = std::min({py[ring - 1][col], py[ring - 1][col + 1], py[ring][col], py[ring][col + 1]}),
              hi = std::max({py[ring - 1][col], py[ring - 1][col + 1], py[ring][col], py[ring][col + 1]});
    return floor16(lo - 9) < to && floor16(hi + 8) >= from;
  };
  for (int ring = 1; ring <= kRings; ++ring)
    for (int col = 0; col < kSectors && ringTop[ring] < to && ringLow[ring] >= from; ++col) {
      if (!reaches(ring, col)) continue;
      for (int which = 0; which < 2; ++which) {
        const uint8_t t = tris[ring][col][which];
        if (!(t & kToward)) continue;
        const Vertex a = vertex(ring - 1, col + which), b = vertex(ring, col),
                     c = which ? vertex(ring, col + 1) : vertex(ring - 1, col + 1);
        const Level& level = kLevels[smaller[ring] >> (col * 2 + which) & 1];
        triangle(s, a, b, c, t & 7, level, from, to);
      }
    }
}
// Rows [from, to) of the frame, a band at a time: each band erased
// (Surface::erase), unless it was before anything was drawn behind the
// body, then the body's triangles drawn in it while its pixels are still
// in the cache. The body stops at row `body`, above the host's lane.
struct Rows {
  Surface* s;
  const Surface::Erasing* erasing;
  int from, to, body;
  uint32_t us;  // how long they took
};
void draw(Rows& rows) {
  for (int y = rows.from; y < rows.to; y += kEraseBand) {
    const int end = std::min(rows.to, y + kEraseBand);
    if (rows.erasing) rows.s->erase(*rows.erasing, y, end);
    if (y < rows.body) body(*rows.s, y, std::min(end, rows.body));
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
void drawBody(Surface& s, const PaintControls& c, rig::Anchors* anchors, const Surface::Erasing* erase);
void project(const Surface& s, const PaintControls& c);
void chooseSizes(const Surface& s);
}  // namespace
void paint(Surface& s, const PaintControls& c, const Box* keep, int keepCount, uint32_t keepLane, rig::Anchors* anchors,
           const PastimeShow* scenery) {
  if (!s.pixels) return;
  // What the last frame wrote is erased with the body, row by row (draw):
  // the clear's own time is only its books. Scenery behind the body needs
  // the whole surface erased before it's drawn.
  Surface::Erasing erasing;
  {
    Measure measure(profile.clear);
    erasing = s.beginClear(keep, keepCount, keepLane);
  }
  // The pastimes' scenery, behind the body.
  const bool behind = scenery && showsScenery(*scenery);
  if (behind) {
    Measure measure(profile.props);
    s.erase(erasing, 0, s.height);
    paintScenery(s, *scenery);
  }
  drawBody(s, c, anchors, behind ? nullptr : &erasing);
}
void paintBody(Surface& s, const PaintControls& c, rig::Anchors* anchors) { drawBody(s, c, anchors, nullptr); }
const void* materialTexels(size_t& bytes) {
  bytes = sizeof slime::kMaterial;
  return slime::kMaterial;
}
void readMaterialFrom(const void* copy) { material = copy ? static_cast<const uint16_t*>(copy) : slime::kMaterial; }
namespace {
// Every vertex, deformed and projected, into px and py.
// The surface and controls the mesh is projected for (projectRings).
const Surface* projecting = nullptr;
const PaintControls* projectingControls = nullptr;
// Rings [from, to)'s vertices, deformed and projected, into px and py.
void projectRings(int from, int to) {
  const PaintControls& c = *projectingControls;
  Projector camera(*projecting, c);
  for (int ring = from; ring < to; ++ring)
    for (int col = 0; col <= kSectors; ++col) {
      const auto& src = slime::kMesh[ring * (kSectors + 1) + col];
      World world{src.x + product(c.ripple, src.wx), src.y, src.z + product(c.ripple, src.wz)};
      int dx = product(src.bx, 15974), dy = product(src.by - 819, 12698),
          dent = std::max(0, 4096 - int((int64_t(dx) * dx + int64_t(dy) * dy) / 4096));
      dent = product(product(dent, dent), src.front);
      auto p = camera.project(camera.deform(world, src.h, src.h2, src.front, dent));
      px[ring][col] = int16_t(std::clamp(p.x, -32000, 32000));
      py[ring][col] = int16_t(std::clamp(p.y, -32000, 32000));
    }
}
// Rings [from, to)'s triangles: which face the camera.
void faceRings(int from, int to) {
  for (int ring = from; ring < to; ++ring)
    for (int col = 0; col < kSectors; ++col)
      for (int which = 0; which < 2; ++which) {
        const Tri t{ring, col, which};
        const Vertex a = corner(t, 0), b = corner(t, 1), c = corner(t, 2);
        tris[ring][col][which] = edge(a, b, c.x, c.y) > 0 ? kToward : 0;
      }
}
// Rings [from, to)'s triangles toward the camera: which of their edges are
// the outline, a neighbour turned away or edge on. One toward the camera
// alone, all its neighbours turned away, is a sliver of a fold at the
// outline, there a frame or two: its fringe would flash a streak a pixel
// wide, so it's left out (none of its neighbours asks after it).
void outlineRings(int from, int to) {
  for (int ring = from; ring < to; ++ring)
    for (int col = 0; col < kSectors; ++col)
      for (int which = 0; which < 2; ++which) {
        const Tri t{ring, col, which};
        if (!toward(t)) continue;
        for (int k = 0; k < 3; ++k) tris[ring][col][which] |= uint8_t(toward(across(t, k)) ? 0 : 1 << k);
        if (tris[ring][col][which] == (kToward | 7)) tris[ring][col][which] = 0;
      }
}
// fn over [from, to), half on the helper's core when there's one: each
// element worked out alone, so the same whichever core does it.
struct Half {
  void (*fn)(int, int);
  int from, to;
};
void runHalf(void* half) {
  const auto& h = *static_cast<Half*>(half);
  h.fn(h.from, h.to);
}
void shared(void (*fn)(int, int), int from, int to) {
  if (!helper) return fn(from, to);
  static Half half;
  const int middle = (from + to) / 2;
  half = {fn, middle, to};
  helper.start(runHalf, &half);
  fn(from, middle);
  helper.join();
}
void project(const Surface& s, const PaintControls& c) {
  projecting = &s, projectingControls = &c;
  shared(projectRings, 0, kRings + 1);
}
// `smaller`, from the dome at rest on the first surface drawn on (the
// panel's, 502 × 410, on the board as in the simulator and the mirror): a
// triangle's texels a pixel at the larger size, the most of its UVs' steps
// a pixel.
void chooseSizes(const Surface& s) {
  project(s, PaintControls{});
  for (int ring = 1; ring <= kRings; ++ring)
    for (int col = 0; col < kSectors; ++col)
      for (int which = 0; which < 2; ++which) {
        const Tri t{ring, col, which};
        const Vertex a = corner(t, 0), b = corner(t, 1), c = corner(t, 2);
        const int area = edge(a, b, c.x, c.y);
        if (!area) continue;
        const int dx[3] = {(b.y - c.y) * 16, (c.y - a.y) * 16, (a.y - b.y) * 16},
                  dy[3] = {(c.x - b.x) * 16, (a.x - c.x) * 16, (b.x - a.x) * 16};
        int most = 0;
        for (const int* d : {dx, dy})
          for (int uv = 0; uv < 2; ++uv) {
            const int64_t sum =
                int64_t(uv ? a.v : a.u) * d[0] + int64_t(uv ? b.v : b.u) * d[1] + int64_t(uv ? c.v : c.u) * d[2];
            most = std::max<int64_t>(most, std::abs(sum * ((1 << 24) / std::abs(area)) / 65536));
          }
        if (most > (1 << kLevels[0].shift) * 3 / 2) smaller[ring] |= uint64_t(1) << (col * 2 + which);
      }
}
// The body over the surface; with `erase`, the last frame's pixels are
// erased band by band just ahead of it (draw).
void drawBody(Surface& s, const PaintControls& c, rig::Anchors* anchors, const Surface::Erasing* erase) {
  if (!s.pixels) return;
  // Every vertex first, then which way each triangle faces, so a triangle
  // knows how to draw its edges: soft where they're the outline.
  // Positions are in sixteenths of a pixel; the UVs follow from the grid.
  static const bool sized = (chooseSizes(s), true);
  (void)sized;
  project(s, c);
  int top = 1 << 30, low = -(1 << 30);
  for (int ring = 0; ring <= kRings; ++ring)
    for (int col = 0; col <= kSectors; ++col)
      top = std::min<int>(top, py[ring][col]), low = std::max<int>(low, py[ring][col]);
  if (anchors) {  // the sides are the columns at the ends of x, the front's the
                  // quarter turn toward the camera
    auto at = [&](int ring, int col) { return rig::Point{px[ring][col], py[ring][col]}; };
    anchors->crown = at(0, 0);
    anchors->brimL = at(kBrimRing, kSectors / 2), anchors->brimF = at(kBrimRing, kSectors / 4);
    anchors->brimR = at(kBrimRing, 0);
    anchors->handF = at(kHandRing, kSectors / 4);
    static_assert(rig::Anchors::kRingPoints == kSectors / 2 + 1, "a ring's front half, a point a column");
    for (int i = 0; i < rig::Anchors::kRingPoints; ++i)
      anchors->lap[i] = at(kLapRing, kSectors / 2 - i), anchors->hem[i] = at(kHemRing, kSectors / 2 - i);
  }
  shared(faceRings, 1, kRings + 1);
  shared(outlineRings, 1, kRings + 1);
  // Each outline edge's end, where it meets the next: found turning about
  // that corner through the triangles toward the camera, from the edge's
  // own, until an edge from it is the outline.
  std::memset(bends, 0, sizeof bends);
  auto unit = [](int x, int y) {
    const int n = std::max(1, root(uint32_t(x * x + y * y)));
    return std::array<int, 2>{x * 1024 / n, y * 1024 / n};
  };
  for (int ring = 1; ring <= kRings; ++ring)
    for (int col = 0; col < kSectors; ++col)
      for (int which = 0; which < 2; ++which)
        for (int k = 0; k < 3; ++k) {
          if ((tris[ring][col][which] & (kToward | 1 << k)) != (kToward | 1 << k)) continue;
          const Tri t{ring, col, which};
          const Vertex p = corner(t, (k + 1) % 3), q = corner(t, (k + 2) % 3);
          // The edge in x that ends at q is i; the one after it starts there.
          Tri x = t;
          int i = k, next = -1;
          for (int step = 0; step < 12 && next < 0; ++step) {
            const int after = (i + 1) % 3;
            if (tris[x.ring][x.col][x.which] >> after & 1) {
              next = after;
              break;
            }
            const Tri y = across(x, after);
            if (!toward(y)) break;
            int shared = 0;
            while (shared < 2 && !(across(y, shared) == x)) ++shared;
            x = y, i = shared;
          }
          const auto in = unit(q.x - p.x, q.y - p.y);
          std::array<int, 2> out = in;
          if (next >= 0) {
            const Vertex r = corner(x, (next + 2) % 3);
            out = unit(r.x - q.x, r.y - q.y);
          }
          const int bx = in[0] + out[0], by = in[1] + out[1], most = std::max(std::abs(bx), std::abs(by));
          int8_t turn[2] = {int8_t(kSquare), 0};
          if (in[0] * out[0] + in[1] * out[1] >= 0)
            turn[0] = int8_t(bx * 127 / most), turn[1] = int8_t(by * 127 / most);
          // Where this edge ends, and where the next starts, as each names it.
          for (int8_t* b : {bend(ring + kCorner[which][(k + 2) % 3][0], col + kCorner[which][(k + 2) % 3][1]),
                            next < 0 ? nullptr
                                     : bend(x.ring + kCorner[x.which][(next + 1) % 3][0],
                                            x.col + kCorner[x.which][(next + 1) % 3][1])}) {
            if (!b) continue;
            if ((b[0] || b[1]) && (b[0] != turn[0] || b[1] != turn[1]))
              b[0] = b[1] = int8_t(kOverlap);
            else
              b[0] = turn[0], b[1] = turn[1];
          }
        }
  for (int ring = 1; ring <= kRings; ++ring) {
    int lo = 1 << 30, hi = -(1 << 30);
    for (int col = 0; col <= kSectors; ++col)
      for (int r : {ring - 1, ring}) lo = std::min<int>(lo, py[r][col]), hi = std::max<int>(hi, py[r][col]);
    ringTop[ring] = int16_t(std::clamp(floor16(lo - 16), -1, 32000)),
    ringLow[ring] = int16_t(std::clamp(hi / 16 + 1, -1, 32000));
  }
  // The body stops above the host's lane, the bottom fifth. With a helper,
  // it erases and draws the lower rows while this core does the upper ones.
  const int rows = s.height * 4 / 5;
  Rows upper{&s, erase, 0, s.height, rows, 0};
  if (!helper) return draw(upper);
  const int first = std::clamp(top / 16, 0, rows), last = std::clamp(low / 16 + 2, first, rows);
  static Rows lower;
  upper.to = first + (last - first) * share / 1024;
  lower = {&s, erase, upper.to, s.height, rows, 0};
  helper.start(helped, &lower);
  const uint32_t start = helper.micros();
  draw(upper);
  const uint32_t mine = helper.micros() - start;
  helper.join();
  share = std::clamp(share + (lower.us > mine ? 8 : -8), 128, 896);
}
}  // namespace
void applyRig(PaintControls& c, const rig::Channels& rig) {
  using rig::Channel;
  const auto off = [&](Channel ch) { return rig[ch] - rig::kRest[ch]; };
  // The engine's own bounds on its pose and life (Engine::pose, life).
  c.lean = std::clamp(c.lean + off(Channel::kLean) * 4096 / 1000, -5120, 5120);
  c.squash = std::clamp(c.squash - off(Channel::kSquash) * 4096 / 1000, -5407, 5407);
  c.lift = std::clamp(c.lift + off(Channel::kLift) * 4096 / kPxPerUnit, 0, 983);
  c.slide += off(Channel::kX) * 4096 / kPxPerUnit;
  c.reach = std::clamp(c.reach + off(Channel::kReach) * 4096 / 1000, -4096, 4096);
  c.melt = std::clamp(c.melt + off(Channel::kMelt) * 4096 / 1000, 0, 4096);
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
    // What the last frame wrote is erased with the body, row by row, unless
    // something is drawn behind it first: then all of it, at once.
    Surface::Erasing erasing;
    {
      Measure clear(profile.clear);
      erasing = surface.beginClear(cards, kept, keepLane);
    }
    const bool scenery = pastimes && !bodyAlone && showsScenery(*pastimes);
    const bool behind = scenery || (finish.on && drawsBehind(finish.finish)) || move.minis;
    if (behind) {
      // Rows a finish covers whole aren't erased first.
      const int covered = finish.on ? finishCovers(surface, finish.finish, finish.ageMs) : 0;
      surface.forget(erasing, 0, covered);
      surface.erase(erasing, covered, surface.height);
    }
    if (scenery) {
      Measure measure(profile.props);
      paintScenery(surface, *pastimes);
    }
    if (finish.on) paintFinishBehind(surface, finish.finish, finish.ageMs, finish.revealMs);
    if (!move.minis) drawBody(surface, c, anchors, behind ? nullptr : &erasing);
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
    const Paws paws = pastimes ? pawsFor(*pastimes) : Paws{};
    paintProps(surface, e, &paws);
  }
}
}  // namespace render::gel
