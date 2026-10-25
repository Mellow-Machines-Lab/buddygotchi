// The body's motion, on the accepted V1 springs, and the semantic face.
#pragma once
#include <array>
#include "render/gel/fixed.h"
#include "slime.h"
namespace render::gel {
struct Motion {
  Spring modes[4];  // lean, squash, ripple, dent
  int emotion = slime::kCalm;
  T time, nextBlink = T::literal(2.8), blinkAt = -10, nextLook = T::literal(4.5);
  F gaze, gazeTarget;
  void advance(T dt, T now, Random& random);
  // A poke (at x across the dome: it leans away from where it's poked) or a shake.
  void impulse(bool shake, F x = 0);
  F blink() const;
  std::array<F, 4> pose() const;
};
// Each control is a critically damped spring that keeps its velocity
// across retargets. The arts drawn are layers, oldest first and the current
// one last, which art.cpp morphs or cross-fades by their weights.
struct SemanticFace {
  // The springs run at kScale times the controls, so Q24 resolves them to
  // 2^-32: a size ratio over the smallest authored dimension (0.002) then
  // stays well inside a ten-thousandth. velocity is at the same scale.
  static constexpr int kScale = 256;
  // At most this many arts at once.
  static constexpr int kMaxLayers = 4;
  // The face's own window and its controls' spring, and falling asleep's
  // spring, a slow one, which the controls keep until the face wakes.
  static constexpr int kFaceMs = 180, kFaceFrequency = 20, kSleepFrequency = 4;
  // Falling asleep, the awake face squashes shut: `shut` springs to one on
  // sleep's spring (back to nothing on the face's, waking), and the awake
  // arts' drawn sizes follow the controls under their saturation that far,
  // down to the sleeping face's sizes: the eyes to lines, the mouth to the
  // sleeping one's. Once it's kShutLine shut, about a second from awake,
  // the sleeping face crosses in over kSwapMs, the lines easing into its
  // lids: asleep, alone, by about 1.3 s.
  static constexpr F kShutLine = q(.9), kLineHalf = q(.015);
  static constexpr int kSwapMs = 360;
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
  Spring shut;
  // The window the arts cross over in, and how far into it they are.
  T elapsedMs, durationMs = kFaceMs;
  SemanticFace();
  const Layer& current() const { return layers[count - 1]; }
  // A layer's drawn size ratios, the eye's and the mouth's width and
  // height: the live controls over its own size.
  std::array<F, 3> ratios(const Layer& layer) const;
  // To the target's art (the sleeping face's while it sleeps), crossing
  // over in `ms`.
  void retarget(T ms = kFaceMs);
  void setMood(int id, T ms = kFaceMs);
  void setSleeping(bool value);
  void advance(T dt);

 private:
  void weigh(F s);
  // The controls toward the target's face (the sleeping face's sizes while
  // it sleeps), from where they are, its art unchanged.
  void aim();
  // Takes layer i out, the ones after it moving down.
  void drop(int i);
};
// How a layer's art is drawn, from its ratios: the sleeping face is the
// tired art squashed to its own size.
std::array<F, 3> drawnScale(const SemanticFace& face, const SemanticFace::Layer& layer);
// Slope one at one, saturating inside (0.75, 4/3).
F softRatio(F value);
}  // namespace render::gel
