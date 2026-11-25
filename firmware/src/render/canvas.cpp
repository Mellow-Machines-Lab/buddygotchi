#include "render/canvas.h"

#include <cstring>

#include "render/maths.h"

namespace render {

void Canvas::fill(uint8_t color) { std::memset(px_, color, size_t(kWidth) * kHeight); }

void Canvas::fillRect(int x, int y, int w, int h, uint8_t color) {
  const int x0 = x < 0 ? 0 : x, y0 = y < 0 ? 0 : y;
  const int x1 = x + w > kWidth ? kWidth : x + w, y1 = y + h > kHeight ? kHeight : y + h;
  if (x1 <= x0) return;
  for (int row = y0; row < y1; ++row) std::memset(px_ + row * kWidth + x0, color, size_t(x1 - x0));
}

static int64_t edge(int ax, int ay, int bx, int by, int px, int py) {
  return int64_t(bx - ax) * (py - ay) - int64_t(by - ay) * (px - ax);
}

void Canvas::fillTriangle(int x0, int y0, int x1, int y1, int x2, int y2, uint8_t color) {
  if (edge(x0, y0, x1, y1, x2, y2) < 0) {  // make the winding consistent
    int tx = x1, ty = y1;
    x1 = x2, y1 = y2, x2 = tx, y2 = ty;
  }
  int minX = x0 < x1 ? (x0 < x2 ? x0 : x2) : (x1 < x2 ? x1 : x2);
  int maxX = x0 > x1 ? (x0 > x2 ? x0 : x2) : (x1 > x2 ? x1 : x2);
  int minY = y0 < y1 ? (y0 < y2 ? y0 : y2) : (y1 < y2 ? y1 : y2);
  int maxY = y0 > y1 ? (y0 > y2 ? y0 : y2) : (y1 > y2 ? y1 : y2);
  if (minX < 0) minX = 0;
  if (minY < 0) minY = 0;
  if (maxX >= kWidth) maxX = kWidth - 1;
  if (maxY >= kHeight) maxY = kHeight - 1;
  for (int y = minY; y <= maxY; ++y) {
    for (int x = minX; x <= maxX; ++x) {
      if (edge(x0, y0, x1, y1, x, y) >= 0 && edge(x1, y1, x2, y2, x, y) >= 0 && edge(x2, y2, x0, y0, x, y) >= 0) {
        px_[y * kWidth + x] = color;
      }
    }
  }
}

}  // namespace render
