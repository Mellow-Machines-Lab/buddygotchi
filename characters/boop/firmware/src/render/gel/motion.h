// Fixed-point port of the locked V1 motion blocks and semantic face interpolator.
// Source locks remain in the JS reference; equivalence is checked by traces.
#pragma once
#include <array>
#include "render/gel/fixed.h"
#include "slime.h"
namespace render::gel {
struct Motion {
  Spring modes[4];  // lean, squash, ripple, dent
  F weights[slime::kProfiles]{};
  int emotion = slime::kCalm;
  T time, nextBlink = T::literal(2.8), blinkAt = -10, nextLook = T::literal(4.5);
  F contactX, contactY = q(.2), gaze, gazeTarget;
  Motion() { weights[slime::kCalm] = 1; }
  void advance(T dt, T now, Random& random, bool reduced);
  void impulse(bool shake, bool reduced, F x = 0, F y = q(.2));
  F blink() const;
  std::array<F, 4> pose(bool reduced) const;
};
// face.mjs: each control is a critically damped spring that keeps its velocity
// across retargets. The arts drawn are layers, oldest first and the current
// one last, which art.cpp morphs or cross-fades by their weights
// (CONTINUITY.md, Directed edge bridges).
struct SemanticFace {
  // The springs run at kScale times the controls, so Q24 resolves them to
  // 2^-32: a size ratio over the smallest authored dimension (0.002) then
  // stays within the port tolerance. velocity is at the same scale.
  static constexpr int kScale = 256;
  // At most this many arts at once (face.mjs faceRender.layers).
  static constexpr int kMaxLayers = 4;
  // Falling asleep's window and its controls' spring (face.mjs
  // sleepTransition): the lids droop shut.
  static constexpr int kSleepMs = 480, kSleepFrequency = 8;
  struct Layer {
    int art = slime::kCalm;
    bool sleeping = false;
    // A Hermite from (from, tangent) toward `to` over the window; weight is
    // its share of them all.
    F from = 1, tangent, to = 1, weight = 1;
    // Its own size at kScale, the eye's and the mouth's width and height,
    // which its drawn ratios are over: its art's, or the sleeping face's.
    std::array<Divisor, 3> size;
  };
  std::array<F, 8> controls{}, scaled{}, velocity{}, target{}, from{}, to{};
  std::array<Layer, kMaxLayers> layers{};
  int count = 1, targetId = slime::kCalm;
  bool targetSleeping = false;
  // The window the arts cross over in, how far into it they are, and the
  // controls' spring until the next.
  T elapsedMs, durationMs = 180;
  F frequency = 20;
  SemanticFace();
  const Layer& current() const { return layers[count - 1]; }
  // A layer's drawn size ratios, the eye's and the mouth's width and
  // height: the live controls over its own size.
  std::array<F, 3> ratios(const Layer& layer) const;
  void retarget(T ms = 180, F spring = 20);
  void setMood(int id, T ms = 180);
  void setSleeping(bool value);
  void advance(T dt, bool reduced);

 private:
  void weigh(F s);
  // Takes layer i out, the ones after it moving down.
  void drop(int i);
};
// How a layer's art is drawn, from its ratios: the sleeping face is the
// tired art squashed to its own size.
std::array<F, 3> drawnScale(const SemanticFace& face, const SemanticFace::Layer& layer);
// face.mjs softRatio: slope one at one, saturating inside (0.75, 4/3).
F softRatio(F value);
}  // namespace render::gel
