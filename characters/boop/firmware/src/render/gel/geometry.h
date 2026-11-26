#pragma once
#include "render/gel/fixed.h"
#include "render/gel/painter.h"
#include "render/gel/raster.h"
#include <algorithm>
#include <cstdint>
namespace render::gel {
// Q12 world coordinates; the camera and dome are slimegen's mesh's.
// √(i · 2^24) in 256ths, for i from 64 to 256: root's first guess.
struct RootTable {
  uint32_t at[257];
  constexpr RootTable() : at() {
    for (int i = 64; i <= 256; ++i) {
      const uint64_t square = uint64_t(i) << 40;
      uint64_t lo = 0, hi = uint64_t(1) << 25;
      while (lo < hi) {
        const uint64_t middle = (lo + hi + 1) / 2;
        if (middle * middle <= square)
          lo = middle;
        else
          hi = middle - 1;
      }
      at[i] = uint32_t(lo);
    }
  }
};
inline constexpr RootTable kRootTable;
// ⌊√n⌋. A guess from the table, between its two nearest entries, is
// within one of it, and two comparisons make it exact: no division, where
// Newton's steps took three or four, a pixel at a stroke's edge.
inline int root(uint32_t n) {
  if (!n) return 0;
  const int shift = __builtin_clz(n) & ~1;
  const uint32_t x = n << shift, i = x >> 24, part = (x >> 8) & 0xffff;
  const uint32_t guess = kRootTable.at[i] + uint32_t(uint64_t(kRootTable.at[i + 1] - kRootTable.at[i]) * part >> 16);
  uint32_t r = guess >> (8 + shift / 2);
  while (uint64_t(r) * r > n) --r;
  while (uint64_t(r + 1) * (r + 1) <= n) ++r;
  return int(r);
}
inline int product(int a, int b) { return a * b / 4096; }
// The dome's radius at its widest, in world units (Q12); how far the rig's
// reach carries its reaching side out at its middle, and pinches the other
// in, and moves all of it toward the reach, at full reach; and how much of
// its height a full melt takes away, and how much wider it spreads.
constexpr int kDomeRadius = 4506, kReachOut = 1900, kReachIn = 600, kReachShift = 260;
constexpr int kMeltDrop = 2540, kMeltSpread = 1720;
struct World {
  int x, y, z;
};
struct Projector {
  const Surface& surface;
  const PaintControls& c;
  int sx, sy, sn, cs, turnSin, turnCos;
  // The controls' shares that every point takes alike, worked out once.
  int leanX, leanZ, dentZ, dentX, reachOut, reachIn, reachShift, height, focal;
  Projector(const Surface& s, const PaintControls& controls) : surface(s), c(controls) {
    turnSin = sinTurn(c.turn), turnCos = sinTurn(c.turn + 1024);
    sy = 4096 + product(c.squash, 2130);
    sx = 16777216 / std::max(1, root(uint32_t(std::max(3113, sy)) * 4096));
    sn = c.roll - product(product(c.roll, c.roll), c.roll) / 6;
    cs = 4096 - product(c.roll, c.roll) / 2;
    leanX = product(c.lean, 1393), leanZ = product(c.lean, 369);
    dentZ = product(c.dent, 492), dentX = product(c.dent, 102);
    reachOut = product(std::abs(c.reach), kReachOut), reachIn = product(std::abs(c.reach), kReachIn);
    reachShift = product(c.reach, kReachShift);
    height = s.height * 95 / 100, focal = height * 4586;
  }
  World deform(World p, int h, int h2, int front = 4096, int dent = 4096) const {
    p.x = product(p.x, sx) + product(leanX, h2);
    p.z = product(p.z, sx) + product(leanZ, h) - product(dentZ, dent);
    p.x += product(product(dentX, p.x), front);
    p.y = product(p.y, sy);
    // A finger's pull leans and squashes the body (Engine::pose); here it
    // carries the top a little further after the finger, front and back
    // alike, so the base stays put and the outline stays whole.
    int grabWeight = product(532, h2);
    p.x += product(c.grabX, grabWeight);
    p.y += product(c.grabY, grabWeight);
    int x = p.x, y = p.y - 2540;
    p.x = product(x, cs) - product(y, sn);
    p.y = std::max(74, product(x, sn) + product(y, cs) + 2540 + c.lift);
    p.z += product(c.forward, h2);
    if (c.reach) {
      // Its middle, between base and crown, most: the reaching side out
      // (kReachOut, a cube's ease from its middle), the other pinched in
      // (kReachIn), and all of it a little toward the reach (kReachShift).
      const int at = product(4 * h, 4096 - h), side = c.reach > 0 ? 1 : -1;
      const int t = std::clamp(side * p.x * 4096 / kDomeRadius, -4096, 4096);
      if (t > 0) p.x += side * product(reachOut, product(product(product(t, t), t), at));
      else p.x -= product(reachIn, product(p.x, at));
      p.x += product(reachShift, at);
    }
    p.x += c.slide;
    return p;
  }
  Point project(World p) const {
    // eye=(0,1.45,3.3), target=(0,.74,0), f=1/tan(.42).
    int y = p.y - 5939, z = p.z - 13517, vy = product(y, 4005) - product(z, 862),
        depth = std::max(1024, -product(y, 862) - product(z, 4005));
    int perspective = focal * 16 / depth;
    int px = surface.width * 8 + product(p.x, perspective), py = height * 8 - product(vy, perspective) + c.dy * 16;
    if (c.scale != 4096) {
      px = c.anchorX + int(int64_t(px - c.anchorX) * c.scale / 4096);
      py = c.anchorY + int(int64_t(py - c.anchorY) * c.scale / 4096);
    }
    px += c.offsetX, py += c.offsetY;
    if (c.squeezeBottom) {  // pressed flat under the drawer, on the screen
      const int top = restBodyTop(surface.height) * 16, bottom = restBodyBottom(surface.height) * 16;
      py = c.squeezeTop * 16 + int(int64_t(py - top) * (c.squeezeBottom - c.squeezeTop) * 16 / (bottom - top));
      px = surface.width * 8 + product(px - surface.width * 8, c.widen);
    } else if (c.melt) {  // melted down onto the desk: its base stays, the rest sinks and spreads
      const int top = restBodyTop(surface.height) * 16, bottom = restBodyBottom(surface.height) * 16;
      const int height = bottom - top, left = height - product(height, product(c.melt, kMeltDrop));
      py = bottom + int(int64_t(py - bottom) * left / height);
      px = surface.width * 8 + product(px - surface.width * 8, 4096 + product(c.melt, kMeltSpread));
    }
    return {px, py};
  }
  // Where a point of the face art (Q12 face units) is drawn, and how far it
  // faces the camera (`facing`, Q12: 4096 straight at it, 0 at the dome's
  // rim). Turned (the rig's turn), each point goes round the dome on its
  // own circle, so a feature near the rim narrows by itself; one gone round
  // behind is held at the rim, facing 0, for paintArt to fade.
  Point face(int x, int y, int* facing = nullptr) const {
    // Undo the face texture's 1.24 scale and .92 UV mapping.
    int bx = product(x, 5521), by = product(y, 5521), bz = root(uint32_t(std::max(0, 16777216 - bx * bx - by * by)));
    if (c.turn) {
      const int turnedX = product(bx, turnCos) + product(bz, turnSin),
                turnedZ = product(bz, turnCos) - product(bx, turnSin);
      bx = turnedX, bz = turnedZ;
      if (bz < 0) {  // behind: at the rim of its circle, on its side
        const int rim = root(uint32_t(std::max(0, bx * bx + bz * bz)));
        bx = bx < 0 ? -rim : rim, bz = 0;
      }
    }
    if (facing) *facing = bz;
    int raw = 2294 + product(3727, by), py = (raw + root(uint32_t(raw * raw + 53687))) / 2 + 78;
    int radius = 4506 - product(287, by), h = py * 4096 / 6103;
    World p{product(radius, bx), py, product(product(radius, bz), 3154)};
    int dist = product(bx, 15974), dy = product(by - 819, 12698);
    int dent = std::max(0, 4096 - int((int64_t(dist) * dist + int64_t(dy) * dy) / 4096));
    dent = product(dent, dent);
    Point at = project(deform(p, h, product(h, h), 4096, dent));
    // Trailing the body, at its size.
    at.x += int(int64_t(c.faceDx16) * c.scale / 4096), at.y += int(int64_t(c.faceDy16) * c.scale / 4096);
    return at;
  }
};
}  // namespace render::gel
