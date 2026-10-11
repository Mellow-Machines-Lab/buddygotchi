#include "board.h"

#include <cstdio>
#include <cstring>

#include "render/palette.h"

namespace sim {

Board::Board(linkkit::Out& usb, uint32_t bootId)
    : canvas_(size_t(render::kWidth) * render::kHeight, 0), rgb_(canvas_.size()) {
  hal_.boot = bootId;
  device_ = std::make_unique<app::Device>(hal_, canvas_.data());
  kit_ = std::make_unique<linkkit::Kit>(hal_, *device_, /*frozenClock=*/false);
  kit_->setOut(linkkit::Link::kUsb, &usb);
  kit_->tick();
}

void Board::usb(const char* bytes, size_t n) {
  for (size_t i = 0; i < n; ++i)
    if (line_.feed(bytes[i])) kit_->handleLine(line_.line(), line_.length(), linkkit::Link::kUsb);
}

bool Board::tick(bool convert) {
  kit_->tick();
  if (!device_->takeFrame()) return false;
  if (auto* frames = device_->frames()) {
    frames->present(device_->canvas());
    auto* s = device_->surface();
    frame_ = {s->pixels, uint16_t(s->width), uint16_t(s->height)};
  } else {
    if (convert) {
      const uint8_t* index = device_->canvas().pixels();
      for (size_t i = 0; i < rgb_.size(); ++i) rgb_[i] = render::kPalette.c[index[i]];
    }
    frame_ = {rgb_.data(), render::kWidth, render::kHeight};
  }
  return true;
}

void Board::shown(uint32_t drawUs, uint32_t pushUs) {
  device_->shown(hal_.realMs());
  device_->noteFrame(drawUs, pushUs);  // dbg.ping's fps, draw_us and push_us
}

bool Board::input(const char* line) {
  int a = 0, b = 0;
  if (std::sscanf(line, "touch %d %d", &a, &b) == 2) hal_.down = true, hal_.x = a, hal_.y = b;
  else if (!std::strncmp(line, "release", 7)) hal_.down = false;
  else if (std::sscanf(line, "boot %d", &a) == 1) hal_.pressed = a != 0;
  else if (!std::strncmp(line, "card out", 8)) hal_.ejectCard();
  else return false;
  return true;
}

std::string Board::parts() const {
  char s[160];
  std::snprintf(s, sizeof(s), "{\"led\":%u,\"backlight\":%u,\"amp\":%s,\"card\":\"%s\"}", unsigned(hal_.led),
                unsigned(hal_.backlight), hal_.amp ? "true" : "false", hal_.card);
  return s;
}

}  // namespace sim
