#include "render/surface.h"

#include "render/canvas.h"
#include "render/palette.h"

namespace render {

void blit(const Canvas& canvas, Surface& surface) {
  if (!surface.pixels) return;
  const int width = surface.width, height = surface.height;
  surface.invalidate();
  for (int y = 0; y < height; ++y) {
    const auto* src = canvas.pixels() + (y * kHeight / height) * kWidth;
    auto* dst = surface.pixels + y * width;
    // Integer remainder stepping: x * kWidth / width without a divide per pixel.
    int at = 0, remainder = 0;
    for (int x = 0; x < width; ++x) {
      dst[x] = paletteAt(src[at]);
      remainder += kWidth;
      while (remainder >= width) {
        remainder -= width;
        ++at;
      }
    }
  }
}

}  // namespace render
