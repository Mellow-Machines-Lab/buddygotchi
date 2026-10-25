#include "board/hosted/board.h"

#include <chrono>

#include "render/palette.h"

namespace hosted {

const char* Said::take() {
  if (text_.empty()) return nullptr;
  taken_.swap(text_);
  text_.clear();
  return taken_.c_str();
}

Board::Board(app::Hal& hal, linkkit::Out& usb, bool frozenClock)
    : hal_(hal), canvas_(size_t(render::kWidth) * render::kHeight, 0) {
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

bool Board::tickRgba() {
  using Clock = std::chrono::steady_clock;
  const auto from = Clock::now();
  if (!tick()) return false;
  // A native face's RGB565 surface, or the canvas's palette indices.
  const render::Surface* native = device_->surface();
  const int w = native ? native->width : render::kWidth, h = native ? native->height : render::kHeight;
  const size_t n = size_t(w) * h;
  rgba_.resize(n * 4);
  uint8_t* out = rgba_.data();
  auto put = [out](size_t i, uint16_t p) {
    const uint8_t r = p >> 11, g = (p >> 5) & 0x3f, b = p & 0x1f;
    out[4 * i] = uint8_t(r << 3 | r >> 2);
    out[4 * i + 1] = uint8_t(g << 2 | g >> 4);
    out[4 * i + 2] = uint8_t(b << 3 | b >> 2);
    out[4 * i + 3] = 255;
  };
  if (native) {
    for (size_t i = 0; i < n; ++i) put(i, native->pixels[i]);
  } else {
    const uint8_t* index = device_->canvas().pixels();
    for (size_t i = 0; i < n; ++i) put(i, render::kPalette.c[index[i]]);
  }
  picture_ = {out, w, h};
  device_->shown(hal_.realMs());
  device_->noteFrame(uint32_t(std::chrono::duration_cast<std::chrono::microseconds>(Clock::now() - from).count()), 0);
  return true;
}

}  // namespace hosted
