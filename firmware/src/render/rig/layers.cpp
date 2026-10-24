#include "render/rig/layers.h"

#include "render/maths.h"

namespace render::rig {

void Ramp::at(int& value, int& slope) const {
  if (age_ >= kLayerFadeMs) {
    value = to_;
    slope = 0;
    return;
  }
  // The Hermite basis at s, in 1024ths; the slope is per the whole ramp.
  const int s = int(age_) * 1024 / int(kLayerFadeMs), s2 = s * s / 1024, s3 = s2 * s / 1024;
  value = ((2 * s3 - 3 * s2 + 1024) * from_ + (s3 - 2 * s2 + s) * tangent_ + (3 * s2 - 2 * s3) * to_) / 1024;
  value = clamp(value, 0, 1000);
  slope = ((6 * s2 - 6 * s) * from_ + (3 * s2 - 4 * s + 1024) * tangent_ + (6 * s - 6 * s2) * to_) / 1024;
}

int Ramp::value() const {
  int value, slope;
  at(value, slope);
  return value;
}

void Ramp::retarget(int to) {
  if (to == to_) return;
  int value, slope;
  at(value, slope);
  from_ = value, tangent_ = slope, to_ = to;
  age_ = 0;
}

void Layers::Slot::settle() {
  if (want == shows) {
    ramp.retarget(shows ? 1000 : 0);
  } else if (!shows || (ramp.target() == 0 && ramp.value() == 0)) {
    shows = want;  // nothing showed, or the old one has gone
    ramp.retarget(shows ? 1000 : 0);
  } else {
    ramp.retarget(0);
  }
}

void Layers::show(Layer layer, uint8_t content) {
  Slot& s = slots_[int(layer)];
  s.want = content;
  s.settle();
}

void Layers::dress(uint32_t when, bool dresses) {
  show(Layer::kAccessories, dresses ? uint8_t(outfitFor(when)) : 0);
  show(Layer::kAir, airFor(when));
}

void Layers::advance(uint32_t dt) {
  for (Slot& s : slots_) {
    s.ramp.advance(dt);
    s.settle();
  }
}

void Layers::finish() {
  for (Slot& s : slots_) {
    s.shows = s.want;
    s.ramp.retarget(s.want ? 1000 : 0);
    s.ramp.finish();
  }
}

}  // namespace render::rig
