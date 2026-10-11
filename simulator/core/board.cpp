#include "board.h"

#include <cstdio>
#include <cstring>

#include "render/palette.h"

namespace sim {

Board::Board(linkkit::Out& usb, bool frozenClock, uint32_t bootId) : canvas_(size_t(render::kWidth) * render::kHeight, 0) {
  hal_.boot = bootId;
  device_ = std::make_unique<app::Device>(hal_, canvas_.data());
  kit_ = std::make_unique<linkkit::Kit>(hal_, *device_, frozenClock);
  kit_->setOut(linkkit::Link::kUsb, &usb);
  kit_->tick();
}

void Board::setCard(Card* card, bool out) {
  card_ = card;
  if (!out) hal_.insertCard(card);
}

int Board::usb(const char* bytes, size_t n) {
  int lines = 0;
  for (size_t i = 0; i < n; ++i) {
    if (!line_.feed(bytes[i])) continue;
    // Through the board's own LineReader, so a line over its limit
    // (linkkit/SPEC.md §2) is dropped here exactly as on USB.
    kit_->handleLine(line_.line(), line_.length(), linkkit::Link::kUsb);
    ++lines;
  }
  return lines;
}

bool Board::tick() {
  kit_->tick();
  if (!device_->takeFrame()) return false;
  // A native face's frames turn as on the board, so a screenshot comes
  // from the same two surfaces.
  if (auto* frames = device_->frames()) frames->present(device_->canvas());
  return true;
}

Board::Frame Board::frame() {
  if (auto* s = device_->surface()) return {s->pixels, uint16_t(s->width), uint16_t(s->height)};
  rgb_.resize(canvas_.size());
  const uint8_t* index = device_->canvas().pixels();
  for (size_t i = 0; i < rgb_.size(); ++i) rgb_[i] = render::kPalette.c[index[i]];
  return {rgb_.data(), render::kWidth, render::kHeight};
}

void Board::input(const char* line) {
  int a = 0, b = 0;
  if (std::sscanf(line, "touch %d %d", &a, &b) == 2) hal_.setTouch(true, a, b);
  else if (!std::strncmp(line, "release", 7)) hal_.setTouch(false);
  else if (std::sscanf(line, "boot %d", &a) == 1) hal_.setBoot(a != 0);
  else if (!std::strncmp(line, "card in", 7)) hal_.insertCard(card_);
  else if (!std::strncmp(line, "card out", 8)) hal_.ejectCard();
}

std::string Board::parts() const {
  char s[160];
  std::snprintf(s, sizeof(s), "{\"led\":%u,\"backlight\":%u,\"amp\":%s,\"card\":\"%s\"}", unsigned(hal_.led),
                unsigned(hal_.backlight), hal_.amp ? "true" : "false", hal_.card);
  return s;
}

}  // namespace sim
