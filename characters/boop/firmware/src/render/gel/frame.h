// What the gel's finishes and work acts share: their Q12 motion, and art's own
// coordinates turned and scaled onto the surface. Integer and deterministic,
// so the board, the simulator and the Mac's mirror draw the same frame.
#pragma once
#include <algorithm>
#include <cstdint>
#include "render/gel/fixed.h"
#include "render/gel/geometry.h"
#include "render/gel/raster.h"
namespace render::gel {
// Where t is between a and b (Q12), straight. In 32 bits: spans are well
// under the 17 minutes that would overflow them, and the board divides those
// in hardware.
inline int rampIn(int t, int a, int b) {
  return t <= a ? 0 : t >= b ? 4096 : int(uint32_t(t - a) * 4096u / uint32_t(b - a));
}
// The smoothstep of the same.
inline int ease(int t, int a, int b) {
  const int64_t p = rampIn(t, a, b);
  return int(p * p * (3 * 4096 - 2 * p) / (4096 * 4096));
}
inline int lerp(int a, int b, int e12) { return a + int(int64_t(b - a) * e12 / 4096); }
// The row the body stands on.
inline int floorY(const Surface& s) { return s.height * 783 / 1000; }

// A point `u` units (px at scale 1, y down) from a centre in sixteenths,
// turned by `c12`/`s12` (Q12 cosine and sine) and scaled (Q12).
struct Frame {
  int x16, y16, scale, c12 = 4096, s12 = 0;
  Point at(int ux, int uy) const {
    const int64_t rx = int64_t(ux) * c12 - int64_t(uy) * s12, ry = int64_t(ux) * s12 + int64_t(uy) * c12;
    return {x16 + int(rx * scale * 16 / (int64_t(4096) * 4096)), y16 + int(ry * scale * 16 / (int64_t(4096) * 4096))};
  }
  int size16(int u) const { return std::max(8, u * scale * 16 / 4096); }
};
}  // namespace render::gel
