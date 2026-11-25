// The 8-bit indexed canvas every frame is drawn into.
// Pure C++: it builds for the board and for the Mac simulator.
#pragma once
#include <cstdint>
#include <cstddef>

namespace render {

// The logical screen: landscape, 320 wide and 240 tall. The
// panel itself is 410×502 on the AMOLED board, which turns the picture
// (board/config.h), so drawing code only ever sees this size.
constexpr int kWidth = 320;
constexpr int kHeight = 240;

class Canvas {
 public:
  // Takes a buffer of kWidth * kHeight bytes that outlives the canvas.
  explicit Canvas(uint8_t* pixels) : px_(pixels) {}

  uint8_t* pixels() { return px_; }
  const uint8_t* pixels() const { return px_; }

  void fill(uint8_t color);
  // A rectangle, cut to the canvas.
  void fillRect(int x, int y, int w, int h, uint8_t color);
  void plot(int x, int y, uint8_t color) { px_[y * kWidth + x] = color; }
  // Filled triangle; pixel centres inside or on an edge are drawn.
  void fillTriangle(int x0, int y0, int x1, int y1, int x2, int y2, uint8_t color);

 private:
  uint8_t* px_;
};

// Columns [x0, x1) of a band; empty when nothing in it changed.
struct Span {
  int x0 = 0, x1 = 0;
  bool empty() const { return x1 <= x0; }
};

}  // namespace render
