#include "board/hosted/board.h"

#include "render/palette.h"

namespace hosted {

Board::Board(app::Hal& hal, linkkit::Out& usb, bool frozenClock)
    : canvas_(size_t(render::kWidth) * render::kHeight, 0) {
  device_ = std::make_unique<app::Device>(hal, canvas_.data());
  kit_ = std::make_unique<linkkit::Kit>(hal, *device_, frozenClock);
  kit_->setOut(linkkit::Link::kUsb, &usb);
  kit_->tick();
}

int Board::usb(const char* bytes, size_t n) {
  held_.append(bytes, n);
  return ticked_ ? lines() : 0;
}

int Board::lines() {
  int handled = 0;
  size_t i = 0;
  while (i < held_.size()) {
    // Through the board's own LineReader, so a line over its limit
    // (linkkit/SPEC.md §2) is dropped here exactly as on USB.
    if (!line_.feed(held_[i++])) continue;
    ++handled;
    if (kit_->handleLine(line_.line(), line_.length(), linkkit::Link::kUsb)) {
      ticked_ = false;
      break;
    }
  }
  held_.erase(0, i);
  return handled;
}

bool Board::tick() {
  kit_->tick();
  ticked_ = true;
  const bool drew = device_->takeFrame();
  // A native face's frames turn as on the board, so a screenshot comes
  // from the same two surfaces.
  if (drew) {
    if (auto* frames = device_->frames()) frames->present(device_->canvas());
  }
  lines();
  return drew;
}

Board::Frame Board::frame() {
  if (auto* s = device_->surface()) return {s->pixels, uint16_t(s->width), uint16_t(s->height)};
  rgb_.resize(canvas_.size());
  const uint8_t* index = device_->canvas().pixels();
  for (size_t i = 0; i < rgb_.size(); ++i) rgb_[i] = render::kPalette.c[index[i]];
  return {rgb_.data(), render::kWidth, render::kHeight};
}

void Board::rgba(const Frame& f, std::vector<uint8_t>& out) {
  const size_t n = size_t(f.width) * f.height;
  out.resize(n * 4);
  for (size_t i = 0; i < n; ++i) {
    const uint16_t p = f.pixels[i];
    const uint8_t r = p >> 11, g = (p >> 5) & 0x3f, b = p & 0x1f;
    out[4 * i] = uint8_t(r << 3 | r >> 2);
    out[4 * i + 1] = uint8_t(g << 2 | g >> 4);
    out[4 * i + 2] = uint8_t(b << 3 | b >> 2);
    out[4 * i + 3] = 255;
  }
}

}  // namespace hosted
