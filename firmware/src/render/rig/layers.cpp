#include "render/rig/layers.h"

namespace render::rig {

Layers::Slot Layers::Slot::at(uint32_t t) const {
  Slot s = *this;
  if (s.want != s.shows && s.ramp.target() == 0 && !within(t, s.ramp.since(), kFadeMs)) {
    s.shows = s.want;
    if (s.shows) s.ramp.retarget(1000, s.ramp.since() + kFadeMs);
  }
  return s;
}

void Layers::show(Layer layer, uint32_t content, uint32_t t) {
  Slot& s = slots_[int(layer)];
  s = s.at(t);
  s.want = content;
  if (s.want == s.shows || !s.shows) {
    s.shows = s.want;
    s.ramp.retarget(s.shows ? 1000 : 0, t);
  } else {
    s.ramp.retarget(0, t);  // the old fades out first
  }
}

}  // namespace render::rig
