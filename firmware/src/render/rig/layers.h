// The layers a face draws that come and go with what it shows, each in its
// place among the face's own drawing: each shows a content (the face's own
// number for what it draws there, 0 for nothing) at an opacity easing in
// and out on the rig's fade, so nothing appears or goes in one frame. A
// new content waits for the old to fade out, then fades in: a hat changes
// at midnight without a pop. The board's state says what each shows as it
// changes, and the face reads them each frame. The lane and a reaction's
// sign, whose times Behaviour keeps, fade on its ramps (app/behaviour.h):
// what they show changes at once.
#pragma once
#include <cstdint>

#include "render/rig/rig.h"

namespace render::rig {

// Back to front, as a face draws them.
enum class Layer : uint8_t {
  kScene,   // behind the body: the gel's night sky
  kWorn,    // over the eyes or on the body: glasses, pyjamas
  kHat,     // on the head's anchors
  kAir,     // snow, confetti, hearts: screen space
  kBeside,  // beside the head: Zs while it sleeps at night
  kCount
};
constexpr int kLayerCount = int(Layer::kCount);

class Layers {
 public:
  // What the layer shows from t.
  void show(Layer layer, uint32_t content, uint32_t t);
  // What it draws at t (while a new content waits, the old one fading out)
  // and how much of it, 0 … 1000: functions of the time since each show,
  // however often they're read.
  uint32_t content(Layer layer, uint32_t t) const { return slots_[int(layer)].at(t).shows; }
  int opacity(Layer layer, uint32_t t) const { return slots_[int(layer)].at(t).ramp.value(t); }

 private:
  struct Slot {
    uint32_t want = 0, shows = 0;
    Ramp ramp;  // how much of `shows`
    // As it is at t: once the old content has faded out, the new one, from
    // the instant it had.
    Slot at(uint32_t t) const;
  };
  Slot slots_[kLayerCount];
};

}  // namespace render::rig
