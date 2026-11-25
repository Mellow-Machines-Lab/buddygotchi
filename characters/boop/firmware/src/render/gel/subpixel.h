// The props' shapes placed in sixteenths of a pixel, for what moves: a
// whole-pixel shape steps a pixel at a time and judders at the frame rate,
// one placed between pixels glides. Built on the raster's own sub-pixel
// shapes (render/gel/raster.h), so they blend by coverage like the rest.
#pragma once
#include <algorithm>

#include "render/gel/raster.h"

namespace render::gel {

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
