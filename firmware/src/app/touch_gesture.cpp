#include "app/touch_gesture.h"

#include <algorithm>
#include <cstdlib>

namespace app {

void TouchGesture::down(int x, int y) {
  x0_ = x_ = minX_ = maxX_ = x;
  y0_ = y_ = minY_ = maxY_ = y;
  path_ = 0;
}

void TouchGesture::move(int x, int y) {
  path_ += std::abs(x - x_) + std::abs(y - y_);
  x_ = x, y_ = y;
  minX_ = std::min(minX_, x), maxX_ = std::max(maxX_, x);
  minY_ = std::min(minY_, y), maxY_ = std::max(maxY_, y);
}

TouchGesture::Kind TouchGesture::up() const {
  const int dx = x_ - x0_, dy = y_ - y0_;
  const bool spot = maxX_ - minX_ <= kTickleSpotPx && maxY_ - minY_ <= kTickleSpotPx;
  if (spot && path_ >= kTicklePathPx) return kTickle;
  if (std::abs(dx) >= kStrokePx || std::abs(dy) >= kStrokePx) return -dy > std::abs(dx) ? kRuffle : kStroke;
  if (std::abs(x0_ - kNoseX) <= kNoseHalf && std::abs(y0_ - kNoseY) <= kNoseHalf) return kNose;
  return kTap;
}

bool gestureOf(TouchGesture::Kind k, render::Gesture& g) {
  switch (k) {
    case TouchGesture::kStroke: g = render::Gesture::kStroke; return true;
    case TouchGesture::kRuffle: g = render::Gesture::kRuffle; return true;
    case TouchGesture::kTickle: g = render::Gesture::kTickle; return true;
    case TouchGesture::kNose: g = render::Gesture::kNose; return true;
    default: return false;
  }
}

}  // namespace app
