#include "app/touch_gesture.h"

#include <algorithm>
#include <cstdlib>

namespace app {

void TouchGesture::down(int x, int y, uint32_t t) {
  x0_ = x_ = minX_ = maxX_ = x;
  y0_ = y_ = minY_ = maxY_ = y;
  path_ = 0;
  t0_ = t;
}

void TouchGesture::move(int x, int y) {
  path_ += std::abs(x - x_) + std::abs(y - y_);
  x_ = x, y_ = y;
  minX_ = std::min(minX_, x), maxX_ = std::max(maxX_, x);
  minY_ = std::min(minY_, y), maxY_ = std::max(maxY_, y);
}

bool TouchGesture::held(uint32_t t) const {
  return t - t0_ >= kHoldMs && maxX_ - minX_ <= kHoldSpotPx && maxY_ - minY_ <= kHoldSpotPx;
}

bool TouchGesture::up(render::Gesture& g) const {
  const int dx = x_ - x0_, dy = y_ - y0_;
  const bool spot = maxX_ - minX_ <= kTickleSpotPx && maxY_ - minY_ <= kTickleSpotPx;
  if (spot && path_ >= kTicklePathPx)
    g = render::Gesture::kTickle;
  else if (std::abs(dx) >= kStrokePx || std::abs(dy) >= kStrokePx)
    g = -dy > std::abs(dx) ? render::Gesture::kRuffle : render::Gesture::kStroke;
  else if (std::abs(x0_ - kNoseX) <= kNoseHalf && std::abs(y0_ - kNoseY) <= kNoseHalf)
    g = render::Gesture::kNose;
  else
    return false;
  return true;
}

}  // namespace app
