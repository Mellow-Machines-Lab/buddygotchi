// The 8-bit indexed canvas every frame is drawn into.
// Pure C++: it builds for the board and for the Mac simulator.
#pragma once
#include <cstdint>
#include <cstddef>

namespace render {

// The logical screen: landscape, 320 wide and 240 tall. The
// panel itself is 240×320 on the CYD, 410×502 on the AMOLED board; each
// board turns the picture (board/config.h), so drawing code only ever sees this size.
constexpr int kWidth = 320;
constexpr int kHeight = 240;

class Canvas {
 public:
  // Takes a buffer of kWidth * kHeight bytes that outlives the canvas.
  explicit Canvas(uint8_t* pixels) : px_(pixels) {}

  uint8_t* pixels() { return px_; }
  const uint8_t* pixels() const { return px_; }

  void fill(uint8_t color);
  void fillRect(int x, int y, int w, int h, uint8_t color);
  // Filled triangle; pixel centres inside or on an edge are drawn.
  void fillTriangle(int x0, int y0, int x1, int y1, int x2, int y2, uint8_t color);

  // A hash of a block, so the pusher can skip what didn't change. x and w
  // are multiples of 4: it reads the pixels four at a time.
  uint32_t hash(int x, int y, int w, int h) const;

 private:
  uint8_t* px_;
};

// Which pixels a picture draws while it fades (the canvas has no alpha): a
// 4 × 4 ordered dither gives each pixel a threshold, 0 … 15, and a picture
// draws those whose threshold is in [lo, hi). Every pixel is [0, 16).
struct Dither {
  uint8_t lo = 0, hi = 16;
  // The new picture's share `mix` (0 … 1000) of the way into a fade, or
  // the old one's.
  static Dither fade(int mix, bool incoming);
  // This one, of what `outer` draws.
  Dither within(Dither outer) const;
  bool all() const { return lo == 0 && hi >= 16; }
  bool draws(int x, int y) const;
  bool operator==(const Dither& o) const { return lo == o.lo && hi == o.hi; }
};

// What the pusher sends (each board's display.cpp): the screen in
// bands of kBand rows, and of each band only the columns that changed since
// it was last pushed, found by hashing kTile-wide tiles.
constexpr int kBand = 6, kTile = 32;
static_assert(kHeight % kBand == 0 && kWidth % kTile == 0, "bands and tiles must tile the screen");

// Columns [x0, x1) of a band; empty when nothing in it changed.
struct Span {
  int x0 = 0, x1 = 0;
  bool empty() const { return x1 <= x0; }
};

class Changes {
 public:
  // The columns of band b (rows b * kBand up to the next band) that changed
  // since the last call for it: every column the first time.
  Span band(const Canvas& canvas, int b);

 private:
  uint32_t hashes_[kHeight / kBand][kWidth / kTile] = {};
  bool seen_[kHeight / kBand] = {};
};

}  // namespace render
