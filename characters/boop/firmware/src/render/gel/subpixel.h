// The props' shapes placed in sixteenths of a pixel, for what moves: a
// whole-pixel shape steps a pixel at a time and judders at the frame rate,
// one placed between pixels glides. Built on the raster's own sub-pixel
// shapes (render/gel/raster.h), so they blend by coverage like the rest.
#pragma once
#include <algorithm>

#include "render/gel/raster.h"

namespace render::gel {

// The rectangle [x16, x16 + w16) × [y16, y16 + h16) with corners of
// `radius16`, each corner's arc in eight chords (at a 20 px radius they
// stray under 0.1 px from the arc). On whole pixels it covers what
// Raster::round does, to within the chords.
inline void round16(Raster& r, int x16, int y16, int w16, int h16, int radius16, uint16_t ink) {
  if (w16 <= 0 || h16 <= 0) return;
  // The cosine of i/8 of a quarter turn, in 4096ths.
  static constexpr int kCos[9] = {4096, 4017, 3784, 3406, 2896, 2276, 1567, 799, 0};
  const int rad = std::clamp(radius16, 0, std::min(w16, h16) / 2);
  const Point centres[4] = {{x16 + rad, y16 + rad},
                            {x16 + w16 - rad, y16 + rad},
                            {x16 + w16 - rad, y16 + h16 - rad},
                            {x16 + rad, y16 + h16 - rad}};
  // Each corner's quarter, clockwise on the screen: from the left edge's
  // top round to the top edge's left, and so on.
  static constexpr int kSides[4][2] = {{-1, -1}, {1, -1}, {1, 1}, {-1, 1}};
  Point v[36];
  int n = 0;
  for (int c = 0; c < 4; ++c)
    for (int i = 0; i <= 8; ++i) {
      // Top-left and bottom-right run from the horizontal; the other two
      // from the vertical.
      const int along = c % 2 ? kCos[8 - i] : kCos[i], across = c % 2 ? kCos[i] : kCos[8 - i];
      v[n++] = {centres[c].x + kSides[c][0] * rad * along / 4096, centres[c].y + kSides[c][1] * rad * across / 4096};
    }
  r.polygon16(v, n, ink);
}

// A circle's outline round (cx16, cy16), `radius16` to the middle of its
// line, `width16` wide: 32 chords, stroked.
inline void circle16(Raster& r, int cx16, int cy16, int radius16, int width16, uint16_t ink) {
  static constexpr int kCos[9] = {4096, 4017, 3784, 3406, 2896, 2276, 1567, 799, 0};
  Point v[33];
  for (int i = 0; i < 32; ++i) {
    const int q = i / 8, k = i % 8;
    const int c = q == 0 ? kCos[k] : q == 1 ? -kCos[8 - k] : q == 2 ? -kCos[k] : kCos[8 - k];
    const int s = q == 0 ? kCos[8 - k] : q == 1 ? kCos[k] : q == 2 ? -kCos[8 - k] : -kCos[k];
    v[i] = {cx16 + radius16 * c / 4096, cy16 + radius16 * s / 4096};
  }
  v[32] = v[0];
  r.stroke16(v, 33, width16, ink);
}

}  // namespace render::gel
