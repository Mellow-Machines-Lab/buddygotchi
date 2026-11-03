#include "app/growth_bar.h"

#include <algorithm>
#include <cstdlib>

#include "render/maths.h"

namespace app {

using G = render::GrowthShow;

void GrowthBar::sweep(uint32_t t) {
  if (on_ && sinceOff(t) >= int(G::kOutMs)) on_ = heart_ = false;
}

void GrowthBar::heartComes(int xp, uint32_t t) {
  if (to_ < 0) return;
  from_ = fill(t);
  if (int32_t(t - fillAt_) >= int32_t(G::kFillMs)) wrap_ = 0;  // past the bar's end: it isn't played again
  // A state with the XP that came first may have moved it too little to show.
  if (xp >= 0) to_ = xp;
  fillAt_ = t + G::kHeartWaitMs + G::kHeartFlyMs;
  if (!on_) onAt_ = t;
  on_ = heart_ = true;
  heartAt_ = t;
  offAt_ = fillAt_ + G::kFillMs * (wrap_ ? 2 : 1) + G::kHoldMs;
}

int GrowthBar::fill(uint32_t t) const {
  if (to_ < 0) return 0;
  const int ms = int(G::kFillMs), to = to_ * 10;
  int age = int32_t(t - fillAt_);
  if (!wrap_) return from_ + (to - from_) * render::ease1000(age, ms) / 1000;
  // Up to the bar's end and on from its start; or down, for a stage lost.
  const int end = wrap_ > 0 ? 1000 : 0;
  if (age < ms) return from_ + (end - from_) * render::ease1000(age, ms) / 1000;
  return 1000 - end + (to - (1000 - end)) * render::ease1000(age - ms, ms) / 1000;
}

void GrowthBar::heard(int xp, int wasStage, int nowStage, bool hidden, uint32_t t) {
  if (xp < 0) {
    *this = GrowthBar{};
    return;
  }
  if (to_ < 0 || hidden) {  // what it is, not a change to show
    *this = GrowthBar{};
    from_ = xp * 10, to_ = xp, fillAt_ = t;
    return;
  }
  const int fresh = nowStage > wasStage ? 1 : nowStage < wasStage ? -1 : 0;
  if (fresh > 0) grew_ = true, grewAt_ = t;
  if (xp == to_ && !fresh) return;
  // One still on its way to the bar's end carries on there.
  const int wrap = fresh ? fresh : int32_t(t - fillAt_) < int32_t(G::kFillMs) ? wrap_ : 0;
  const bool coming = heart_ && int32_t(t - fillAt_) < 0;
  if (coming) {  // it fills as the heart lands
    to_ = xp, wrap_ = wrap;
    offAt_ = fillAt_ + G::kFillMs * (wrap ? 2 : 1) + G::kHoldMs;
    return;
  }
  const bool up = on_ && sinceOff(t) < int(G::kOutMs);
  if (!up && !wrap && std::abs(xp - to_) < kStep) return;
  from_ = fill(t);
  to_ = xp, wrap_ = wrap, fillAt_ = t;
  if (!up) onAt_ = t;
  on_ = true;
  offAt_ = t + G::kFillMs * (wrap ? 2 : 1) + G::kHoldMs;
}

render::GrowthShow GrowthBar::show(int stage, bool hidden, uint32_t t) const {
  render::GrowthShow s;
  s.stage = stage;
  if (!on_) return s;
  // The stage it's filling up for, till it's past the bar's end.
  if (wrap_ && int32_t(t - fillAt_) < int32_t(G::kFillMs)) s.stage -= wrap_;
  const int fromPop = int32_t(t - heartAt_), flown = fromPop - int(G::kHeartWaitMs), landed = int32_t(t - fillAt_);
  const int out = sinceOff(t);
  if (out >= int(G::kOutMs) || hidden) return s;
  s.opacity = std::min<int>(255 * int32_t(t - onAt_) / int(G::kInMs), 255);
  if (out > 0) s.opacity = 255 - 255 * out / int(G::kOutMs);
  s.fill = fill(t);
  if (heart_ && flown >= 0 && landed < 0) s.flight = 1000 * flown / int(G::kHeartFlyMs);
  if (heart_ && landed >= 0 && landed < int(G::kGulpMs)) s.gulp = std::max(1, 1000 * landed / int(G::kGulpMs));
  return s;
}

}  // namespace app
