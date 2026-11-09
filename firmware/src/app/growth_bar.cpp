#include "app/growth_bar.h"

#include <algorithm>

#include "render/maths.h"

namespace app {

using G = render::GrowthShow;

void GrowthBar::sweep(uint32_t t) {
  if (on_ && sinceOff(t) >= int(G::kOutMs)) on_ = heart_ = false;
}

void GrowthBar::heartComes(int xp, uint32_t t) {
  if (to_ < 0) return;
  from_ = fill(t);
  // A state with the XP that came first may have moved it too little to show.
  if (xp >= 0) to_ = xp;
  fillAt_ = t + G::kHeartWaitMs + G::kHeartFlyMs;
  if (!on_) onAt_ = t;
  on_ = heart_ = true;
  heartAt_ = t;
  offAt_ = fillAt_ + G::kFillMs + G::kHoldMs;
}

int GrowthBar::fill(uint32_t t) const {
  if (to_ < 0) return 0;
  return from_ + (to_ * 10 - from_) * render::ease1000(int32_t(t - fillAt_), int(G::kFillMs)) / 1000;
}

void GrowthBar::heard(int xp, int wasStage, int nowStage, bool hidden, uint32_t t) {
  if (xp < 0) {
    *this = GrowthBar{};
    return;
  }
  if (to_ < 0 || hidden || xp < to_) {  // what it is, not a change to show: a new day empties it
    *this = GrowthBar{};
    from_ = xp * 10, to_ = xp, fillAt_ = t;
    return;
  }
  if (nowStage > wasStage) grew_ = true, grewAt_ = t;
  if (xp == to_) return;
  const bool coming = heart_ && int32_t(t - fillAt_) < 0;
  if (coming) {  // it fills as the heart lands
    to_ = xp;
    offAt_ = fillAt_ + G::kFillMs + G::kHoldMs;
    return;
  }
  const bool up = on_ && sinceOff(t) < int(G::kOutMs);
  if (!up && xp < 100 && xp - to_ < kStep) return;
  from_ = fill(t);
  to_ = xp, fillAt_ = t;
  if (!up) onAt_ = t;
  on_ = true;
  offAt_ = t + G::kFillMs + G::kHoldMs + (xp >= 100 ? G::kSparkleMs : 0);
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
  // Full: it sparkles once it gets there.
  const int full = int32_t(t - fillAt_) - int(G::kFillMs);
  if (to_ >= 100 && full >= 0 && full < int(G::kSparkleMs)) s.sparkle = std::max(1, 1000 * full / int(G::kSparkleMs));
  return s;
}

}  // namespace app
