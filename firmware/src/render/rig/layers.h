// The layers a face draws, back to front, each with an opacity that eases
// in and out, so nothing appears or goes in one frame (the lane included),
// and the anchors the face reports each frame from the pose it draws, so
// accessories and what it holds ride the body.
#pragma once
#include <cstdint>

#include "render/rig/rig.h"

namespace render::rig {

enum class Layer : uint8_t {
  kScene,  // the look's: the desk, the computer
  kBody,
  kFace,
  kAccessories,  // hats, glasses: on the head's anchors
  kHeld,         // a sign, a trophy, a mug: on the hands'
  kAir,          // snow, confetti, Zs: screen space
  kLane,         // the strip, the needs-you sign
  kCount
};
constexpr int kLayerCount = int(Layer::kCount);
constexpr uint32_t kLayerFadeMs = 200;

// A point in the face's own units (the gel's sixteenths of a pixel).
struct Point {
  int x = 0, y = 0;
};
// Where the body is this frame: the top of its head; a ring a little lower,
// at its sides and the middle of its front, where a hat's brim sits; a ring
// lower down, likewise, where it holds things; and its eyes' middles.
struct Anchors {
  Point crown, brimL, brimF, brimR, handL, handF, handR, eyeL, eyeR;
};

// An opacity, 0 … 1000, easing to its target over kLayerFadeMs: a cubic
// Hermite from the value and slope it has, so it starts from rest, turns
// back smoothly and ends exactly (the gel's props' ramp).
class Ramp {
 public:
  void retarget(int to);
  void advance(uint32_t dt) { age_ = age_ + dt < kLayerFadeMs ? age_ + dt : kLayerFadeMs; }
  void finish() { age_ = kLayerFadeMs; }
  int value() const;
  int target() const { return to_; }

 private:
  void at(int& value, int& slope) const;
  int from_ = 0, to_ = 0, tangent_ = 0;
  uint32_t age_ = kLayerFadeMs;
};

class Layers {
 public:
  // What a layer shows: 0 for nothing, else the face's own number for it (a
  // scene, an outfit, the air's bits, 1 for on). A new one waits for the old
  // to fade out, then fades in.
  void show(Layer layer, uint8_t content);
  // The accessories and the air the tags on call for: the outfit
  // (render::outfitFor) when the look dresses, and the air (render::airFor).
  void dress(uint32_t when, bool dresses);
  void advance(uint32_t dt);
  // Every fade done at once: at power-on.
  void finish();
  // What a layer draws: while a new content waits, the old one fading out.
  uint8_t content(Layer layer) const { return slots_[int(layer)].shows; }
  int opacity(Layer layer) const { return slots_[int(layer)].ramp.value(); }

 private:
  struct Slot {
    uint8_t want = 0, shows = 0;
    Ramp ramp;
    void settle();
  };
  Slot slots_[kLayerCount];
};

}  // namespace render::rig
