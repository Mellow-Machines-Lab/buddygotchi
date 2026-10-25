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
  // spans, a row is black: what the push plans by (render/push.h).
  struct Span {
    uint16_t first = 0, last = 0;
  };
  static constexpr int kTrackedRows = 512;
  std::array<Span, kTrackedRows> written{};
  bool invalid = true;
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
  // they are.
  void clear(const Box* keep = nullptr, int keepCount = 0, uint32_t keepLane = 0) {
    const Erasing e = beginClear(keep, keepCount, keepLane);
    erase(e, 0, height);
  }
  // The same clear in parts, for drawing that erases its rows just before
  // it draws them, while they're still in the cache, or on two cores:
  // beginClear says what to erase and keeps the surface's books, then
  // erase does rows [from, to), each row once, before anything is drawn in
  // it.
  struct Erasing {
    int to = 0;          // the rows from here down aren't erased
    bool whole = false;  // every pixel, not just the written spans
    const Box* keep = nullptr;
    int keepCount = 0;
  };
  Erasing beginClear(const Box* keep = nullptr, int keepCount = 0, uint32_t keepLane = 0) {
    Erasing e;
    if (!pixels) return e;
    if (invalid || height > kTrackedRows || keepCount <= 0) cardKey = 0;
    const bool laneKept = !invalid && height <= kTrackedRows && keepLane && keepLane == laneKey && laneKeyFrom >= 0 &&
                          laneKeyFrom <= height;
    e.whole = invalid || height > kTrackedRows;
    e.to = laneKept ? laneKeyFrom : height;
    e.keep = keep, e.keepCount = e.whole ? 0 : std::clamp(keepCount, 0, kMaxKeep);
    invalid = false;
    if (!laneKept) laneKey = 0, laneKeyFrom = -1;
    return e;
  }
  void erase(const Erasing& e, int from, int to) {
    if (!pixels) return;
    from = std::max(0, from), to = std::min(to, e.to);
    if (e.whole) {
      if (from < to) std::memset(pixels + size_t(from) * width, 0, size_t(to - from) * width * sizeof(uint16_t));
    } else {
      for (int y = from; y < to; ++y) {
        const auto& row = written[y];
        if (!row.last) continue;
        // The kept stretches of this row, in order, then the gaps erased.
        int starts[kMaxKeep], ends[kMaxKeep], n = 0;
        for (int k = 0; k < e.keepCount; ++k) {
          const Box& b = e.keep[k];
          if (y < b.y0 || y >= b.y1 || b.x1 <= b.x0) continue;
          int i = n++;
          for (; i > 0 && starts[i - 1] > b.x0; --i) starts[i] = starts[i - 1], ends[i] = ends[i - 1];
          starts[i] = b.x0, ends[i] = b.x1;
        }
        int x = row.first;
        for (int i = 0; i <= n && x < row.last; ++i) {
          const int end = i < n ? std::min<int>(starts[i], row.last) : row.last;
          if (end > x) std::memset(pixels + y * width + x, 0, (end - x) * sizeof(uint16_t));
          if (i < n) x = std::max(x, ends[i]);
        }
      }
    }
    for (int y = from; y < std::min(to, kTrackedRows); ++y) written[y] = {};
  }
  // Rows [from, to) that what's drawn next covers whole: their books are
  // kept as erase keeps them, and nothing is erased, since it would only be
  // painted over.
  void forget(const Erasing& e, int from, int to) {
    from = std::max(0, from), to = std::min(to, e.to);
    for (int y = from; y < std::min(to, kTrackedRows); ++y) written[y] = {};
  }
};
// The canvas, stretched to the whole surface (nearest pixel): the test
// pattern under a native face. It writes past what drawing tracks, so it
// invalidates the surface: the next clear erases it whole, and the push
// sends it whole.
void blit(const Canvas& canvas, Surface& surface);
}  // namespace render
