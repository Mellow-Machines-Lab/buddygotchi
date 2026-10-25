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
static_assert(slime::kMaterialWidth == 513 && slime::kMaterialHeight == 257,
              "UV rounding matches the generated material grid");
struct Vertex {
  int x, y, u, v;
};
int edge(const Vertex& a, const Vertex& b, int x, int y) { return (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x); }
int floor16(int v) { return v >= 0 ? v / 16 : -((15 - v) / 16); }
// UVs span [0, 2^20] × [0, 2^19]; each rounds to the dense material grid.
int texelAt(int t) { return (t + 1024) >> 11; }
uint16_t texel(int ut, int vt) {
  int tx = std::clamp(texelAt(ut), 0, slime::kMaterialWidth - 1), ty = std::clamp(texelAt(vt), 0, slime::kMaterialHeight - 1);
  return slime::kMaterial[ty * slime::kMaterialWidth + tx];
}
// `n` pixels of the material from (ut, vt), a step of (ux, vx) a pixel.
// The UVs step evenly, so when both ends round onto the grid every pixel
// between does: the loop that takes most of the body's time needs no clamp.
void texture(uint16_t* row, int ut, int vt, int ux, int vx, int n) {
  if (n <= 0) return;
  const auto on = [](int t, int size) { return unsigned(texelAt(t)) < unsigned(size); };
  if (!on(ut, slime::kMaterialWidth) || !on(ut + ux * (n - 1), slime::kMaterialWidth) ||
      !on(vt, slime::kMaterialHeight) || !on(vt + vx * (n - 1), slime::kMaterialHeight)) {
    for (int x = 0; x < n; ++x, ut += ux, vt += vx) row[x] = texel(ut, vt);
    return;
  }
  ut += 1024, vt += 1024;
  for (int x = 0; x < n; ++x, ut += ux, vt += vx) row[x] = slime::kMaterial[(vt >> 11) * slime::kMaterialWidth + (ut >> 11)];
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
      texture(s.pixels + y * s.width + x0 + lo, tu + ux * lo, tv + vx * lo, ux, vx, hi - lo + 1);
    }
    e0 += dy0;
    e1 += dy1;
    e2 += dy2;
    tu += uy;
    tv += vy;
  }
}

// Fills a front-facing triangle by pixel centre, in rows [from, to). Its
// edges named in `soft` (bit 0: b→c, 1: c→a, 2: a→b) are the body's
// outline: there each pixel takes the share of its area inside, falling to
// nothing half a pixel out, over the black the body is drawn on.
void triangle(Surface& s, Vertex a, Vertex b, Vertex c, unsigned soft, int from, int to) {
  if (!soft) return fill(s, a, b, c, from, to);
  int area = edge(a, b, c.x, c.y);
  if (area <= 0) return;
  const int pad = soft ? 8 : 0;
  int x0 = std::max(0, floor16(std::min({a.x, b.x, c.x}) - pad + 7)),
      x1 = std::min(s.width - 1, floor16(std::max({a.x, b.x, c.x}) + pad - 8));
  int y0 = std::max(0, floor16(std::min({a.y, b.y, c.y}) - pad + 7)),
      y1 = std::min(to - 1, floor16(std::max({a.y, b.y, c.y}) + pad - 8));
  const int start = std::max(y0, from);
  if (x0 > x1 || start > y1) return;
  s.touch(x0, start, x1 + 1, y1 + 1);
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
  const int skip = start - y0;  // as fill's
  for (int k = 0; k < 3; ++k) e[k] += dy[k] * skip;
  tu += uy * skip, tv += vy * skip;
  for (int y = start; y <= y1; ++y) {
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
      texture(row + fullLo, tu + ux * fullLo, tv + vx * fullLo, ux, vx, fullHi - fullLo + 1);
      partial(fullHi + 1, hi);
    }
    for (int k = 0; k < 3; ++k) e[k] += dy[k];
    tu += uy;
    tv += vy;
  }
}

// The projected mesh, for the frame being drawn: every vertex, in
// sixteenths of a pixel, and of each quad's two triangles which of their
// edges are the outline. Kept small (internal RAM): 3.3 KB of positions,
// 1.6 KB of edges.
constexpr int kRings = slime::kMeshRings, kSectors = slime::kMeshSectors;
int16_t px[kRings + 1][kSectors + 1], py[kRings + 1][kSectors + 1];
uint8_t softs[kRings + 1][kSectors][2];
Vertex vertex(int ring, int col) {
  return Vertex{px[ring][col], py[ring][col], col * 4096 / kSectors, ring * 2048 / kRings};
}
// The rows each ring's triangles reach, an outline's half pixel included.
int16_t ringTop[kRings + 1], ringLow[kRings + 1];
// The body's rows [from, to): every front-facing triangle there, in the same
// order whichever core draws them, so a row comes out the same.
void body(Surface& s, int from, int to) {
  // A quad's two triangles: (above[c], here[c], above[c+1]) and
  // (above[c+1], here[c], here[c+1]).
  for (int ring = 1; ring <= kRings; ++ring)
    for (int col = 0; col < kSectors && ringTop[ring] < to && ringLow[ring] >= from; ++col) {
      triangle(s, vertex(ring - 1, col), vertex(ring, col), vertex(ring - 1, col + 1), softs[ring][col][0], from, to);
      triangle(s, vertex(ring - 1, col + 1), vertex(ring, col), vertex(ring, col + 1), softs[ring][col][1], from, to);
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
constexpr int kEraseBand = 16;
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
      softs[ring][col][0] = uint8_t((away(ring, col, 1) ? 1u : 0u) | (away(ring - 1, col, 1) ? 2u : 0u) |
                                    (away(ring, col - 1, 1) ? 4u : 0u));
      softs[ring][col][1] = uint8_t((away(ring + 1, col, 0) ? 1u : 0u) | (away(ring, col + 1, 0) ? 2u : 0u) |
                                    (away(ring, col, 0) ? 4u : 0u));
    }
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
  Rows upper{&s, erase, 0, erase ? s.height : rows, rows, 0};
  if (!helper) return draw(upper);
  const int first = std::clamp(top / 16, 0, rows), last = std::clamp(low / 16 + 2, first, rows);
  static Rows lower;
  upper.to = first + (last - first) * share / 1024;
  lower = {&s, erase, upper.to, erase ? s.height : rows, rows, 0};
  helper.start(helped, &lower);
  const uint32_t start = helper.micros();
  draw(upper);
  const uint32_t mine = helper.micros() - start;
  helper.join();
  share = std::clamp(share + (lower.us > mine ? 8 : -8), 128, 896);
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
