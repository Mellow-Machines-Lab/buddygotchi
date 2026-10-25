// Native RGB565 surface. Allocation belongs to the platform; drawing stays pure.
#pragma once
#include <cstddef>
#include <cstdint>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
namespace render {
class Canvas;
struct Size {
  int width = 0, height = 0;
  // A panel's rounded corners' radius, in its pixels: they show nothing.
  int corner = 0;
  bool empty() const { return width <= 0 || height <= 0; }
};
// A rectangle of whole pixels, [x0, x1) × [y0, y1).
struct Box {
  int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
};
struct Surface {
  int width = 0, height = 0;
  uint16_t* pixels = nullptr;
  // The panel's rounded corners' radius (Size::corner): 0 for square.
  int corner = 0;
  // How far in from either side something must stand to show whole on
  // every row of [y0, y1), past the panel's rounded corners; with corners
  // of its own, of `radius`, it may stand nearer, as they're cut away too.
  int inset(int y0, int y1, int radius = 0) const { return insetOf(width, height, corner, y0, y1, radius); }
  // The same for a surface of that size, corner and all, before it has pixels.
  static int insetOf(int width, int height, int corner, int y0, int y1, int radius = 0) {
    const int r = std::min(corner, std::min(width, height) / 2) - std::max(0, radius);
    const int edge = std::max(0, std::min(y0, height - y1));  // whole rows to the nearer edge
    if (r <= 0 || 2 * edge + 1 >= 2 * r) return 0;
    const float dy = r - edge - 0.5f;  // from the corner's centre to its row's middle
    return int(std::ceil(r - std::sqrt(float(r) * r - dy * dy)));
  }
  size_t bytes() const { return size_t(width) * size_t(height) * sizeof(uint16_t); }
  // Drawing records each row's written span. The next frame only erases those
  // pixels; direct whole-surface writers must invalidate this history. A
  // surface taller than this is cleared whole every frame. Outside its
  // spans and the lane, a row is black: what the push plans by
  // (render/push.h).
  struct Span {
    uint16_t first = 0, last = 0;
  };
  static constexpr int kTrackedRows = 512;
  std::array<Span, kTrackedRows> written{};
  bool invalid = true;
  // The rows from here down hold the canvas, written whole by blit since
  // the last clear (the shared lane under a native face, or a whole test
  // pattern); -1 when blit hasn't run since.
  int lane = -1;
  // A lane a face draws itself, from row `laneKeyFrom` down, where nothing
  // else draws: `laneKey` names what it shows (a hash, never 0), so two
  // frames with the same key hold the same pixels there and the push
  // needn't send those rows (render/push.h). 0 when none was drawn since
  // the last clear.
  uint32_t laneKey = 0;
  int laneKeyFrom = -1;
  // What the boxes a clear keeps hold above row `cardKeyTo`, when a face
  // draws whole cards there (a hash, never 0): a frame whose cards have the
  // same key needn't draw those rows again (render/gel/props.cpp). 0 when
  // no clear has kept boxes since they were drawn.
  uint32_t cardKey = 0;
  int cardKeyTo = 0;
  void invalidate() { invalid = true; }
  void touch(int x0, int y0, int x1, int y1) {
    if (height > kTrackedRows) {
      invalid = true;
      return;
    }
    x0 = std::max(0, x0);
    x1 = std::min(width, x1);
    if (x0 >= x1) return;
    for (int y = std::max(0, y0); y < std::min(height, y1); ++y) {
      auto& row = written[y];
      row.first = row.last ? std::min<int>(row.first, x0) : x0;
      row.last = std::max<int>(row.last, x1);
    }
  }
  // The most boxes a clear keeps (render/gel/props.cpp's cards, three each).
  static constexpr int kMaxKeep = 9;
  // Erases what the last frame wrote, but for what the frame about to be
  // drawn covers anyway: `keep`'s boxes, which it fills with
  // opaque ink, and its own lane, when `keepLane` names what this surface's
  // lane already shows (laneKey), whose rows and spans are then left as
  // they are. The rows blit wrote are left as it wrote them, since blit
  // writes them whole again; until it does, they count as written, so a
  // frame that skips blit erases them next time.
  void clear(const Box* keep = nullptr, int keepCount = 0, uint32_t keepLane = 0) {
    if (!pixels) return;
    const int canvasFrom = lane >= 0 && lane < height && height <= kTrackedRows ? lane : height;
    if (invalid || height > kTrackedRows || keepCount <= 0) cardKey = 0;
    const bool laneKept = !invalid && height <= kTrackedRows && keepLane && keepLane == laneKey && laneKeyFrom >= 0 &&
                          laneKeyFrom <= canvasFrom;
    const int erasedTo = laneKept ? laneKeyFrom : canvasFrom;
    if (invalid || height > kTrackedRows) {
      std::memset(pixels, 0, bytes());
    } else {
      keepCount = std::clamp(keepCount, 0, kMaxKeep);
      for (int y = 0; y < erasedTo; ++y) {
        const auto& row = written[y];
        if (!row.last) continue;
        // The kept stretches of this row, in order, then the gaps erased.
        int from[kMaxKeep], to[kMaxKeep], n = 0;
        for (int k = 0; k < keepCount; ++k) {
          const Box& b = keep[k];
          if (y < b.y0 || y >= b.y1 || b.x1 <= b.x0) continue;
          int i = n++;
          for (; i > 0 && from[i - 1] > b.x0; --i) from[i] = from[i - 1], to[i] = to[i - 1];
          from[i] = b.x0, to[i] = b.x1;
        }
        int x = row.first;
        for (int i = 0; i <= n && x < row.last; ++i) {
          const int end = i < n ? std::min<int>(from[i], row.last) : row.last;
          if (end > x) std::memset(pixels + y * width + x, 0, (end - x) * sizeof(uint16_t));
          if (i < n) x = std::max(x, to[i]);
        }
      }
    }
    for (int y = 0; y < erasedTo; ++y) written[y] = {};
    for (int y = canvasFrom; y < height; ++y) written[y] = invalid ? Span{} : Span{0, uint16_t(width)};
    invalid = false;
    lane = -1;
    if (!laneKept) laneKey = 0, laneKeyFrom = -1;
  }
};
// The canvas, stretched to the surface's size (nearest pixel), into its
// rows from `fromRow` down: the shared lane under a native face, or a
// whole test pattern. Rows it writes are written whole every time, so they
// need no tracked clearing; it records them as the surface's `lane`.
void blit(const Canvas& canvas, Surface& surface, int fromRow);
}  // namespace render
