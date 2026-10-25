#include "app/touch_gesture.h"

#include <algorithm>
#include <cstdlib>

namespace app {

void TouchGesture::down(int x, int y, uint32_t t) {
  x0_ = minX_ = maxX_ = x;
  y0_ = minY_ = maxY_ = y;
  path_ = 0;
  t0_ = t;
  count_ = 0;
  sample(x, y, t);
}

void TouchGesture::move(int x, int y, uint32_t t) {
  path_ += std::abs(x - last().x) + std::abs(y - last().y);
  minX_ = std::min(minX_, x), maxX_ = std::max(maxX_, x);
  minY_ = std::min(minY_, y), maxY_ = std::max(maxY_, y);
  sample(x, y, t);
}

// A reading at the same time as the last (the loop ran again on a frozen
// clock) takes its place, so the readings kept span time.
void TouchGesture::sample(int x, int y, uint32_t t) {
  if (count_ && last().t == t) --count_;
  samples_[count_++ % kSamples] = {x, y, t};
}

bool TouchGesture::held(uint32_t t) const {
  return t - t0_ >= kHoldMs && maxX_ - minX_ <= kHoldSpotPx && maxY_ - minY_ <= kHoldSpotPx;
}

TouchGesture::Path TouchGesture::path() const { return {x0_, y0_, last().x, last().y, last().t - t0_}; }

TouchGesture::Kind TouchGesture::up(render::Gesture& g) const {
  const int dx = last().x - x0_, dy = last().y - y0_, far = std::max(std::abs(dx), std::abs(dy));
  const bool spot = maxX_ - minX_ <= kTickleSpotPx && maxY_ - minY_ <= kTickleSpotPx;
  if (spot && path_ >= kTicklePathPx) {
    g = render::Gesture::kTickle;
  } else if (far >= kStrokePx) {
    g = -dy > std::abs(dx) ? render::Gesture::kRuffle : render::Gesture::kStroke;
    int vx, vy;
    velocity(vx, vy);
    if (int64_t(vx) * vx + int64_t(vy) * vy > int64_t(kSwipePxPerS) * kSwipePxPerS) return kSwipe;
  } else if (std::abs(x0_ - kNoseX) <= kNoseHalf && std::abs(y0_ - kNoseY) <= kNoseHalf) {
    g = render::Gesture::kNose;
  } else {
    return kTap;
  }
  return kGesture;
}

void TouchGesture::velocity(int& vx, int& vy) const {
  vx = vy = 0;
  if (count_ < 2) return;
  const Sample& end = last();
  // Back to the newest reading at least kFlingMs before the last, else the
  // oldest kept.
  const int oldest = std::max(0, count_ - kSamples);
  int i = count_ - 2;
  while (i > oldest && end.t - samples_[i % kSamples].t < kFlingMs) --i;
  const Sample& first = samples_[i % kSamples];
  const int64_t ms = int64_t(end.t - first.t);
  if (ms <= 0) return;
  vx = int(int64_t(end.x - first.x) * 1000 / ms);
  vy = int(int64_t(end.y - first.y) * 1000 / ms);
}

}  // namespace app
