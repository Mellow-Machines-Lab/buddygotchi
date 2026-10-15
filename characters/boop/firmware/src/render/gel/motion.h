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
// across retargets; render is what art.cpp draws.
struct SemanticFace {
  enum Render { kEye, kMouthWidth, kMouthHeight, kMouthDot, kCheek, kTear };
  // The springs run at kScale times the controls, so Q24 resolves them to
  // 2^-32: a size ratio over the smallest authored dimension (0.002) then
  // stays within the port tolerance. velocity is at the same scale.
  static constexpr int kScale = 256;
  std::array<F, 8> controls{}, scaled{}, velocity{}, target{}, from{}, to{};
  // The drawn art's eased size ratios, the mouth's swap dot, and the cheek
  // and tear opacities (CONTINUITY.md, Directed edge bridges).
  std::array<F, 6> render{};
  F mix[2]{1, 1}, start[5]{}, swap[2]{};  // cheek/tear dips; values captured at a retarget
  int targetId = slime::kCalm, artId = slime::kCalm;
  bool targetSleeping = false, sleeping = false, active = false, switched = false;
  T age, duration = T::literal(.18), elapsedMs, durationMs = 180;
  F startClosure, bridgeBlink;
  SemanticFace();
  void retarget(T ms = 180);
  void setMood(int id, T ms = 180);
  void setSleeping(bool value);
  void advance(T dt, bool reduced);
  // The drawn scales: the sleeping face is the tired art squashed to its own size.
  F eyeScale() const;
  F mouthScaleX() const;
  F mouthScaleY() const;

 private:
  void bridge(T dt);
  void updateRender();
};
// face.mjs softRatio: slope one at one, saturating inside (0.75, 4/3).
F softRatio(F value);
}  // namespace render::gel
