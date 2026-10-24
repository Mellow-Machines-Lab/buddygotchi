// Projected, deforming gel dome. All frame work is integer and allocation-free.
#include "render/gel/painter.h"
#include "render/gel/engine.h"
#include "render/gel/profile.h"
#include "render/gel/geometry.h"
#include "render/gel/layers.h"
#include "slime_mesh.h"
#include <algorithm>
#include <array>
namespace render::gel {
namespace {
static_assert(slime::kMaterialWidth == 513 && slime::kMaterialHeight == 257,
              "UV rounding matches the generated material grid");
struct Vertex {
  int x, y, u, v;
};
int edge(const Vertex& a, const Vertex& b, int x, int y) { return (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x); }
int floor16(int v) { return v >= 0 ? v / 16 : -((15 - v) / 16); }
// An inner triangle, by pixel centre: most of the body, kept to the
// tightest loop.
void fill(Surface& s, Vertex a, Vertex b, Vertex c) {
  int area = edge(a, b, c.x, c.y);
  if (area <= 0) return;
  int x0 = std::max(0, (std::min({a.x, b.x, c.x}) + 7) / 16),
      x1 = std::min(s.width - 1, (std::max({a.x, b.x, c.x}) - 8) / 16);
  int y0 = std::max(0, (std::min({a.y, b.y, c.y}) + 7) / 16),
      y1 = std::min(s.height * 4 / 5 - 1, (std::max({a.y, b.y, c.y}) - 8) / 16);
  if (x0 > x1 || y0 > y1) return;
  s.touch(x0, y0, x1 + 1, y1 + 1);
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
  for (int y = y0; y <= y1; ++y) {
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
      int ut = tu + ux * lo, vt = tv + vx * lo;
      auto* row = s.pixels + y * s.width + x0;
      // UVs span [0, 2^20] × [0, 2^19]; round to the dense material grid.
      for (int x = lo; x <= hi; ++x) {
        int tx = std::clamp((ut + 1024) >> 11, 0, slime::kMaterialWidth - 1),
            ty = std::clamp((vt + 1024) >> 11, 0, slime::kMaterialHeight - 1);
        row[x] = slime::kMaterial[ty * slime::kMaterialWidth + tx];
        ut += ux;
        vt += vx;
      }
    }
    e0 += dy0;
    e1 += dy1;
    e2 += dy2;
    tu += uy;
    tv += vy;
  }
}

// Fills a front-facing triangle by pixel centre. Its edges named in `soft`
// (bit 0: b→c, 1: c→a, 2: a→b) are the body's outline: there each pixel
// takes the share of its area inside, falling to nothing half a pixel out,
// over the black the body is drawn on.
void triangle(Surface& s, Vertex a, Vertex b, Vertex c, unsigned soft) {
  if (!soft) return fill(s, a, b, c);
  int area = edge(a, b, c.x, c.y);
  if (area <= 0) return;
  const int pad = soft ? 8 : 0;
  int x0 = std::max(0, floor16(std::min({a.x, b.x, c.x}) - pad + 7)),
      x1 = std::min(s.width - 1, floor16(std::max({a.x, b.x, c.x}) + pad - 8));
  int y0 = std::max(0, floor16(std::min({a.y, b.y, c.y}) - pad + 7)),
      y1 = std::min(s.height * 4 / 5 - 1, floor16(std::max({a.y, b.y, c.y}) + pad - 8));
  if (x0 > x1 || y0 > y1) return;
  s.touch(x0, y0, x1 + 1, y1 + 1);
  int dx[3] = {(b.y - c.y) * 16, (c.y - a.y) * 16, (a.y - b.y) * 16};
  int dy[3] = {(c.x - b.x) * 16, (a.x - c.x) * 16, (b.x - a.x) * 16};
  int e[3] = {edge(b, c, x0 * 16 + 8, y0 * 16 + 8), edge(c, a, x0 * 16 + 8, y0 * 16 + 8),
              edge(a, b, x0 * 16 + 8, y0 * 16 + 8)};
  // Half a pixel, in edge-function units, and the edge's length, per edge.
  int half[3] = {0, 0, 0}, length[3] = {1, 1, 1};
  for (int k = 0; k < 3; ++k)
    if (soft >> k & 1) {
      length[k] = std::max(1, root(uint32_t(dx[k] / 16 * (dx[k] / 16) + dy[k] / 16 * (dy[k] / 16))));
      half[k] = 8 * length[k];
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
  auto texel = [](int ut, int vt) {
    // UVs span [0, 2^20] × [0, 2^19]; round to the dense material grid.
    int tx = std::clamp((ut + 1024) >> 11, 0, slime::kMaterialWidth - 1),
        ty = std::clamp((vt + 1024) >> 11, 0, slime::kMaterialHeight - 1);
    return slime::kMaterial[ty * slime::kMaterialWidth + tx];
  };
  for (int y = y0; y <= y1; ++y) {
    // [lo, hi] is covered at all, [inLo, inHi] wholly.
    int lo = 0, hi = x1 - x0, inLo = 0, inHi = x1 - x0;
    for (int k = 0; k < 3; ++k) {
      clip(e[k] + half[k], dx[k], lo, hi);
      clip(e[k] - half[k], dx[k], inLo, inHi);
    }
    auto* row = s.pixels + y * s.width + x0;
    // The outline's pixels, at the ends: each takes its coverage.
    auto partial = [&](int from, int to) {
      for (int x = from; x <= to; ++x) {
        int cover = 255;
        for (int k = 0; k < 3; ++k)
          if (soft >> k & 1) {
            // Within a pixel of the edge, so 32-bit, and the board divides
            // in hardware.
            const int inside = std::clamp(e[k] + dx[k] * x + half[k], 0, 2 * half[k]);
            cover = std::min(cover, inside * 255 / (16 * length[k]));
          }
        if (cover > 2) row[x] = mix565(row[x], texel(tu + ux * x, tv + vx * x), cover);
      }
    };
    const int fullLo = std::max(lo, inLo), fullHi = std::min(hi, inHi);
    if (fullLo > fullHi) {
      partial(lo, hi);
    } else {
      partial(lo, fullLo - 1);
      int ut = tu + ux * fullLo, vt = tv + vx * fullLo;
      for (int x = fullLo; x <= fullHi; ++x, ut += ux, vt += vx) row[x] = texel(ut, vt);
      partial(fullHi + 1, hi);
    }
    for (int k = 0; k < 3; ++k) e[k] += dy[k];
    tu += uy;
    tv += vy;
  }
}
}  // namespace
void paint(Surface& s, const PaintControls& c, const Box* keep, int keepCount, uint32_t keepLane,
           rig::Anchors* anchors) {
  if (!s.pixels) return;
  {
    Measure measure(profile.clear);
    s.clear(keep, keepCount, keepLane);
  }
  // Every vertex first, then which way each triangle faces, so a triangle
  // knows which of its edges are the outline: those whose neighbour faces
  // away. Positions are in sixteenths of a pixel; the UVs follow from the
  // grid. Kept small (internal RAM): 3.3 KB of positions, 1.6 KB of signs.
  constexpr int kRings = slime::kMeshRings, kSectors = slime::kMeshSectors;
  static int16_t px[kRings + 1][kSectors + 1], py[kRings + 1][kSectors + 1];
  static int8_t faces[kRings + 1][kSectors][2];
  Projector camera(s, c);
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
    }
  if (anchors) {  // the sides are the columns at the ends of x, the front's the quarter turn toward the camera
    auto at = [&](int ring, int col) { return rig::Point{px[ring][col], py[ring][col]}; };
    anchors->crown = at(0, 0);
    anchors->brimL = at(kBrimRing, kSectors / 2), anchors->brimF = at(kBrimRing, kSectors / 4);
    anchors->brimR = at(kBrimRing, 0);
    anchors->handF = at(kHandRing, kSectors / 4);
  }
  auto vertex = [&](int ring, int col) {
    return Vertex{px[ring][col], py[ring][col], col * 4096 / kSectors, ring * 2048 / kRings};
  };
  // A quad's two triangles: (above[c], here[c], above[c+1]) and
  // (above[c+1], here[c], here[c+1]).
  auto first = [&](int ring, int col) {
    return std::array<Vertex, 3>{vertex(ring - 1, col), vertex(ring, col), vertex(ring - 1, col + 1)};
  };
  auto second = [&](int ring, int col) {
    return std::array<Vertex, 3>{vertex(ring - 1, col + 1), vertex(ring, col), vertex(ring, col + 1)};
  };
  auto sign = [](int area) { return int8_t(area > 0 ? 1 : area < 0 ? -1 : 0); };
  for (int ring = 1; ring <= kRings; ++ring)
    for (int col = 0; col < kSectors; ++col) {
      auto t = first(ring, col), u = second(ring, col);
      faces[ring][col][0] = sign(edge(t[0], t[1], t[2].x, t[2].y));
      faces[ring][col][1] = sign(edge(u[0], u[1], u[2].x, u[2].y));
    }
  // A neighbour turned away makes the shared edge outline. The dome is
  // closed: the first ring's first triangles and the last ring's second
  // ones meet at its poles and have no area, so they never count.
  auto away = [&](int ring, int col, int which) {
    if (ring < 1 || ring > kRings) return false;
    col = (col + kSectors) % kSectors;
    const int facing = faces[ring][col][which];
    const bool pole = (ring == 1 && which == 0) || (ring == kRings && which == 1);
    return facing < 0 || (facing == 0 && !pole);
  };
  for (int ring = 1; ring <= kRings; ++ring)
    for (int col = 0; col < kSectors; ++col) {
      auto t = first(ring, col), u = second(ring, col);
      const unsigned firstSoft =
          (away(ring, col, 1) ? 1u : 0u) | (away(ring - 1, col, 1) ? 2u : 0u) | (away(ring, col - 1, 1) ? 4u : 0u);
      const unsigned secondSoft =
          (away(ring + 1, col, 0) ? 1u : 0u) | (away(ring, col + 1, 0) ? 2u : 0u) | (away(ring, col, 0) ? 4u : 0u);
      triangle(s, t[0], t[1], t[2], firstSoft);
      triangle(s, u[0], u[1], u[2], secondSoft);
    }
}
void paint(Surface& surface, const Engine& e, bool mouthOpen, int dy, uint32_t keepLane, rig::Anchors* anchors) {
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
  rig::Anchors local;
  if (!anchors) anchors = &local;
  {
    Measure measure(profile.body);
    Box cards[Surface::kMaxKeep];
    paint(surface, c, cards, opaqueCards(surface, e, cards), keepLane, anchors);
  }
  {
    Measure measure(profile.art);
    paintArt(surface, e, c, mouthOpen, anchors);
    paintLayers(surface, e, *anchors);
  }
  {
    Measure measure(profile.props);
    paintProps(surface, e);
  }
}
}  // namespace render::gel
