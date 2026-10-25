// What every frame of the gel engine is held to, wherever a test drives it:
// each spring and channel inside its bounds, and what's drawn moving no more
// in one 16 ms frame than its ramp or spring can (the arts' weights and drawn
// sizes, the props, the desk). A test captures a frame after each step and
// checks the next against it.
#pragma once
#include <unity.h>

#include <array>
#include <cmath>

#include "render/gel/engine.h"

namespace render::gel::frames {

// A layer's weight moves at most this much in a 16 ms frame: the steepest
// Hermite over the shortest face window. A prop's visibility (a card's
// reveal with it) at most this, its 200 ms ramp's.
inline const F kWeightStep = q(.149), kRampStep = q(.134);

// The desk's steepest 16 ms frame: its spring's (frequency 10, damping 14)
// from rest, integrated as the engine does, in 1/240 s substeps.
inline double deskStep() {
  double x = 0, v = 0, most = 0;
  for (int frame = 0; frame < 120; ++frame) {
    const double was = x;
    for (double left = .016; left > 1e-12;) {
      const double h = std::min(left, 1.0 / 240);
      v += (100 * (1 - x) - 14 * v) * h;
      x += v * h;
      left -= h;
    }
    x = std::min(1.0, std::max(0.0, x));
    most = std::max(most, x - was);
  }
  return most;
}

struct Layer {
  int art = -1;
  bool sleeping = false;
  F weight;
  std::array<F, 3> ratio;
};
struct Frame {
  std::array<F, 8> controls;
  std::array<Layer, SemanticFace::kMaxLayers> layers;
  int count = 0;
  F props[Scenes::kProps], desk;
};

inline Frame capture(const Engine& e) {
  Frame f;
  f.controls = e.face.controls;
  f.count = e.face.count;
  for (int i = 0; i < e.face.count; ++i) {
    const auto& l = e.face.layers[i];
    f.layers[i] = {l.art, l.sleeping, l.weight, e.face.ratios(l)};
  }
  for (int p = 0; p < Scenes::kProps; ++p) f.props[p] = e.scenes.visible(Scenes::Prop(p), e.timeMs());
  f.desk = e.scenes.desk.x;
  return f;
}

inline bool within(F value, F bound) { return abs(value) <= bound; }

// Every bound one frame keeps, and, given the frame 16 ms before, how far
// it may have moved since.
inline void check(const Engine& e, const Frame* before = nullptr) {
  static const F kDeskStep = q(deskStep() + .0001);
  // The body's four modes (motion.cpp), the gestures' springs, a gag's slide
  // and lids (acting.cpp), the bridge's (acting.cpp), a finger's pull
  // (engine.h) and a scene's activity (scenes.cpp).
  for (const auto& m : e.motion.modes) TEST_ASSERT_TRUE(within(m.x, q(.72)) && within(m.v, 9));
  const F gesture[] = {q(.42), q(.42), q(.42), q(.24), q(.12), q(.18)};
  for (int i = 0; i < 6; ++i)
    TEST_ASSERT_TRUE(within(e.acting.channels[i].x, gesture[i]) && within(e.acting.channels[i].v, 5));
  TEST_ASSERT_TRUE(within(e.acting.slide.x, q(.7)) && within(e.acting.slide.v, 5));
  TEST_ASSERT_TRUE(within(e.acting.lids.x, 1) && within(e.acting.lids.v, 20));
  const F bridge[] = {q(.06), q(.05), q(.04)}, activity[] = {q(.08), q(.06), q(.05)};
  for (int i = 0; i < 3; ++i) {
    TEST_ASSERT_TRUE(within(e.bridge.channels[i].x, bridge[i]) && within(e.bridge.channels[i].v, 1));
    TEST_ASSERT_TRUE(within(e.scenes.activity[i].x, activity[i]) && within(e.scenes.activity[i].v, q(1.2)));
    TEST_ASSERT_TRUE(within(e.pull[i].x, Engine::kGrabLimit) && within(e.pull[i].v, Engine::kGrabVelocity));
    TEST_ASSERT_TRUE(within(e.target[i], Engine::kGrabReach));
  }
  // What the body is drawn with: its pose and its life, inside their bounds.
  const auto pose = e.pose();
  const F poseBounds[] = {q(1.25), q(1.32), q(1.14), q(.72)};
  for (int i = 0; i < 4; ++i) TEST_ASSERT_TRUE(within(pose[i], poseBounds[i]));
  const auto life = e.life();
  TEST_ASSERT_TRUE(life[0] >= F(0) && life[0] <= q(.24) && within(life[1], q(.12)) && within(life[2], q(.23)));
  // The eyes: a blink, a gag's lids or both, never past shut; the gaze a
  // glance either way.
  TEST_ASSERT_TRUE(e.blink() >= F(0) && e.blink() <= F(1) && within(e.motion.gaze, q(.014)));
  // The face: the cheeks' and tears' strengths in [0, 1]; at most four
  // arts, each once, their weights shares of one, each drawn within
  // (3/4, 4/3) of its own size.
  const auto& f = e.face;
  TEST_ASSERT_TRUE(f.controls[6] >= F(0) && f.controls[6] <= F(1) && f.controls[7] >= F(0) && f.controls[7] <= F(1));
  TEST_ASSERT_TRUE(f.count >= 1 && f.count <= SemanticFace::kMaxLayers);
  F sum = 0;
  for (int i = 0; i < f.count; ++i) {
    const auto& l = f.layers[i];
    TEST_ASSERT_TRUE(l.weight >= F(0) && l.weight <= F(1));
    sum += l.weight;
    for (int j = 0; j < i; ++j) TEST_ASSERT_FALSE(f.layers[j].art == l.art && f.layers[j].sleeping == l.sleeping);
    for (const F r : f.ratios(l)) TEST_ASSERT_TRUE(r > q(.75) - q(.0001) && r < q(4.0 / 3) + q(.0001));
  }
  TEST_ASSERT_TRUE(abs(sum - 1) <= q(.0001));
  if (!before) return;
  // Since the frame before: each art's weight by at most a Hermite's step,
  // its drawn size by no more than the control it follows, each prop by at
  // most its ramp's step, and the desk by at most its spring's.
  const int sized[] = {2, 4, 5};
  for (int i = 0; i < f.count; ++i) {
    const auto& l = f.layers[i];
    const auto ratio = f.ratios(l);
    for (int j = 0; j < before->count; ++j) {
      const auto& was = before->layers[j];
      if (was.art != l.art || was.sleeping != l.sleeping) continue;
      TEST_ASSERT_TRUE(abs(l.weight - was.weight) <= kWeightStep);
      if (l.sleeping) continue;
      for (int r = 0; r < 3; ++r)
        TEST_ASSERT_TRUE(abs(ratio[r] - was.ratio[r]) * slime::kProfile[l.art].face[sized[r]] <=
                         abs(f.controls[sized[r]] - before->controls[sized[r]]) + q(.00001));
    }
  }
  for (int p = 0; p < Scenes::kProps; ++p)
    TEST_ASSERT_TRUE(abs(e.scenes.visible(Scenes::Prop(p), e.timeMs()) - before->props[p]) <= kRampStep);
  TEST_ASSERT_TRUE(abs(e.scenes.desk.x - before->desk) <= kDeskStep);
}

}  // namespace render::gel::frames
