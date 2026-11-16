#include "app/growth_bar.h"

#include <algorithm>

#include "render/maths.h"

namespace app {

using G = render::GrowthShow;

void GrowthBar::settle() {
  on_ = heart_ = emptying_ = false;
  if (to_ >= 0) from_ = to_ * 10;
  if (sparkle_ == Sparkle::kDue) sparkle_ = Sparkle::kDone;
}

void GrowthBar::fullAt(uint32_t at, uint32_t t) {
  if (sparkle_ == Sparkle::kDone || (sparkle_ == Sparkle::kDue && int32_t(t - sparkleAt_) >= 0)) return;
  sparkle_ = Sparkle::kDue, sparkleAt_ = at;
}

void GrowthBar::holdOn() {
  offAt_ = fillAt_ + G::kFillMs + G::kHoldMs;
  const uint32_t sparkled = sparkleAt_ + G::kSparkleMs + G::kHoldMs;
  if (sparkle_ == Sparkle::kDue && int32_t(sparkled - offAt_) > 0) offAt_ = sparkled;
}

void GrowthBar::sweep(bool hidden, uint32_t t) {
  if (on_ && sinceOff(t) >= int(G::kOutMs)) settle();
  if (!owed_ || hidden) return;
  owed_ = false;
  const bool coming = heart_ && int32_t(t - fillAt_) < 0;
  from_ = owedFrom_;
  if (!coming) fillAt_ = t;
  if (!up(t)) onAt_ = t;
  on_ = true;
  sparkle_ = Sparkle::kNone;
  fullAt(fillAt_ + G::kFillMs, t);
  holdOn();
}

void GrowthBar::heartComes(int xp, uint32_t t) {
  if (emptying_) settle();
  // With the ring full before this wish, the bar doesn't come back today: the
  // heart stays in the bubble. A wish that fills it finds the bar up, or its
  // state the last.
  const bool isUp = up(t);
  if (to_ < 0 || (to_ >= 100 && wasFull_ && !isUp)) return;
  from_ = fill(t);
  // A state with the XP that came first may have moved it too little to show.
  if (xp >= 0) to_ = xp;
  fillAt_ = t + G::kHeartWaitMs + G::kHeartFlyMs;
  if (!isUp) onAt_ = t;
  on_ = heart_ = true;
  heartAt_ = t;
  if (to_ >= 100) fullAt(fillAt_ + G::kFillMs, t);
  holdOn();
}

int GrowthBar::fill(uint32_t t) const {
  if (to_ < 0) return 0;
  return from_ + (to_ * 10 - from_) * render::ease1000(int32_t(t - fillAt_), int(G::kFillMs)) / 1000;
}

void GrowthBar::heard(int xp, bool hidden, uint32_t t) {
  if (xp < 0) {
    *this = GrowthBar{};
    return;
  }
  if (emptying_) settle();  // another state before it's out: it's gone now
  const bool wasFull = to_ < 0 ? xp >= 100 : to_ >= 100;
  if (to_ >= 0 && !hidden && xp < to_ && up(t)) {
    // A new day while it's up: it slides out as it was, and is empty once gone.
    from_ = fill(t), to_ = xp, fillAt_ = t + G::kOutMs;
    if (sinceOff(t) < 0) offAt_ = t;
    heart_ = owed_ = false, emptying_ = true;
    sparkle_ = Sparkle::kNone;
    wasFull_ = wasFull;
    return;
  }
  if (to_ < 0 || hidden || xp < to_) {  // what it is, not a change to show: a new day empties it
    // Filled to 100 where it can't show: it shows once it can.
    const bool owed = to_ >= 0 && hidden && xp >= 100 && xp >= to_ && (to_ < 100 || owed_);
    const int owedFrom = owed_ ? owedFrom_ : fill(t);
    *this = GrowthBar{};
    from_ = xp * 10, to_ = xp, fillAt_ = t;
    owed_ = owed, owedFrom_ = owedFrom;
    wasFull_ = wasFull;
    return;
  }
  wasFull_ = wasFull;
  if (xp == to_) return;
  const bool coming = heart_ && int32_t(t - fillAt_) < 0;
  if (coming) {  // it fills as the heart lands
    to_ = xp;
    if (xp >= 100) fullAt(fillAt_ + G::kFillMs, t);
    holdOn();
    return;
  }
  const bool isUp = up(t);
  if (!isUp && xp < 100 && xp - to_ < kStep) return;
  from_ = fill(t);
  to_ = xp, fillAt_ = t;
  if (!isUp) onAt_ = t;
  on_ = true;
  owed_ = false;
  if (xp >= 100) fullAt(t + G::kFillMs, t);
  holdOn();
}

render::GrowthShow GrowthBar::show(bool hidden, uint32_t t) const {
  render::GrowthShow s;
  if (!on_) return s;
  // By when it lands, not by the fill, which a later state moves on.
  const int fromPop = int32_t(t - heartAt_), flown = fromPop - int(G::kHeartWaitMs),
            landed = flown - int(G::kHeartFlyMs);
  const int out = sinceOff(t);
  if (out >= int(G::kOutMs) || hidden) return s;
  s.opacity = std::min<int>(255 * int32_t(t - onAt_) / int(G::kInMs), 255);
  if (out > 0) s.opacity = 255 - 255 * out / int(G::kOutMs);
  s.fill = fill(t);
  if (heart_ && flown >= 0 && landed < 0) s.flight = 1000 * flown / int(G::kHeartFlyMs);
  if (heart_ && landed >= 0 && landed < int(G::kGulpMs)) s.gulp = std::max(1, 1000 * landed / int(G::kGulpMs));
  // Full: it sparkles once it gets there, once.
  const int full = int32_t(t - sparkleAt_);
  if (sparkle_ == Sparkle::kDue && full >= 0 && full < int(G::kSparkleMs))
    s.sparkle = std::max(1, 1000 * full / int(G::kSparkleMs));
  return s;
}

}  // namespace app
