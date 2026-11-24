// A show's picture (render/face.h's CardShow, the Mac's ShowPicture): the
// agent's picture, kShowW by kShowH, in one of 16 colours a pixel, run-
// length coded so a mostly empty picture is small on the link. Each run is
// one byte, its colour in the high four bits and its length less one in
// the low four (1–15); a low four of 15 means the length is 16 plus the
// next byte (16–271). Runs go row after row, left to right. Colour 0 is
// none (the card shows through); 6 is the agent's lane colour.
#pragma once
#include <cstddef>
#include <cstdint>

#include "render/palette.h"

namespace render {

// The colours by index, RGB565, as the Mac's ShowPicture.palette: none,
// the show's rule colours (ink, dim, good, bad, not checked), the lane's
// (its own, drawn by the caller), then a ramp of greys for a picture made
// from a PNG.
constexpr int kShowColours = 16, kShowLane = 6;
constexpr uint16_t kShowInk[kShowColours] = {
    0,
    rgb565(0xe8, 0xe6, 0xe0),
    rgb565(0x9a, 0xa0, 0xa8),
    rgb565(0x5f, 0xae, 0x5a),
    rgb565(0xf0, 0x8a, 0x6c),
    rgb565(0xf0, 0xb5, 0x6c),
    0,
    rgb565(0x20, 0x20, 0x20),
    rgb565(0x38, 0x38, 0x38),
    rgb565(0x50, 0x50, 0x50),
    rgb565(0x68, 0x68, 0x68),
    rgb565(0x80, 0x80, 0x80),
    rgb565(0xb0, 0xb0, 0xb0),
    rgb565(0xc8, 0xc8, 0xc8),
    rgb565(0xf8, 0xf8, 0xf8),
    rgb565(0x10, 0x10, 0x10),
};

// Calls f(x, y, n, colour) for each run of a colour other than 0 in the
// picture `data` of `size` bytes, `w` wide and `h` high, a run never
// crossing a row's end. Stops at the picture's end or a byte short. Returns
// whether the runs filled the picture exactly.
template <typename F>
bool forEachShowRun(const uint8_t* data, size_t size, int w, int h, F&& f) {
  int x = 0, y = 0;
  size_t i = 0;
  while (i < size && y < h) {
    const int colour = data[i] >> 4, low = data[i] & 15;
    ++i;
    int n = low + 1;
    if (low == 15) {
      if (i >= size) return false;
      n = 16 + data[i++];
    }
    while (n > 0 && y < h) {
      const int k = n < w - x ? n : w - x;
      if (colour) f(x, y, k, colour);
      x += k, n -= k;
      if (x == w) x = 0, ++y;
    }
  }
  return i == size && y == h && x == 0;
}

}  // namespace render
