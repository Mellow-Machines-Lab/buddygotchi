// What every frame of the gel engine is held to, wherever a test drives it:
// each spring and channel inside its bounds, and what's drawn moving no more
// in one 16 ms frame than its ramp or spring can (the arts' weights and drawn
// sizes, the props, the desk). A test captures a frame after each step and
// checks the next against it.
#pragma once
#include <unity.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <string>

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
  F shut;
  F props[Scenes::kProps], desk;
};

inline Frame capture(const Engine& e) {
  Frame f;
  f.controls = e.face.controls;
  f.count = e.face.count;
  f.shut = e.face.shut.x;
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
  // (3/4, 4/3) of its own size, but an awake one as far smaller as the face
  // has squashed shut, falling asleep.
  const auto& f = e.face;
  TEST_ASSERT_TRUE(f.controls[6] >= F(0) && f.controls[6] <= F(1) && f.controls[7] >= F(0) && f.controls[7] <= F(1));
  TEST_ASSERT_TRUE(f.count >= 1 && f.count <= SemanticFace::kMaxLayers);
  F sum = 0;
  for (int i = 0; i < f.count; ++i) {
    const auto& l = f.layers[i];
    TEST_ASSERT_TRUE(l.weight >= F(0) && l.weight <= F(1));
    sum += l.weight;
    for (int j = 0; j < i; ++j) TEST_ASSERT_FALSE(f.layers[j].art == l.art && f.layers[j].sleeping == l.sleeping);
    const F low = l.sleeping ? q(.75) : q(.75) * (1 - f.shut.x);
    TEST_ASSERT_TRUE(f.shut.x >= F(0) && f.shut.x <= F(1));
    for (const F r : f.ratios(l)) TEST_ASSERT_TRUE(r > low - q(.0001) && r < q(4.0 / 3) + q(.0001));
  }
  TEST_ASSERT_TRUE(abs(sum - 1) <= q(.0001));
  if (!before) return;
  // Since the frame before: each art's weight by at most a Hermite's step,
  // its drawn size by no more than the control it follows (and, an awake
  // art, what squashing shut moves it: its own size times the shut's step),
  // each prop by at most its ramp's step, and the desk by at most its
  // spring's.
  const int sized[] = {2, 4, 5};
  for (int i = 0; i < f.count; ++i) {
    const auto& l = f.layers[i];
    const auto ratio = f.ratios(l);
    for (int j = 0; j < before->count; ++j) {
      const auto& was = before->layers[j];
      if (was.art != l.art || was.sleeping != l.sleeping) continue;
      TEST_ASSERT_TRUE(abs(l.weight - was.weight) <= kWeightStep);
      if (l.sleeping) continue;
      for (int r = 0; r < 3; ++r) {
        const F size = slime::kProfile[l.art].face[sized[r]];
        TEST_ASSERT_TRUE(abs(ratio[r] - was.ratio[r]) * size <= abs(f.controls[sized[r]] - before->controls[sized[r]]) +
                                                                    abs(f.shut.x - before->shut) * size + q(.00001));
      }
    }
  }
  for (int p = 0; p < Scenes::kProps; ++p)
    TEST_ASSERT_TRUE(abs(e.scenes.visible(Scenes::Prop(p), e.timeMs()) - before->props[p]) <= kRampStep);
  TEST_ASSERT_TRUE(abs(e.scenes.desk.x - before->desk) <= kDeskStep);
}

// No jolt at an event: in the frame just after the host says something (a
// mood, the facts, a request, a lost link, a finger), what's drawn changes
// its per-frame velocity at most twice as much as it does anywhere else in
// the same runs. Drawn is the face's controls (each art's drawn size
// counting in its control's family), the arts' weights, the mood's posture,
// the props and a card's reveal while it shows. Jolts keeps the runs'
// largest changes; each run's Track feeds it.
struct Jolts {
  enum {
    kControls = 0,
    kPosture = 8,
    kProps = 10,
    kDesk = kProps + Scenes::kProps,
    kReveal,
    kWeight = kReveal + 2,
    kFamilies
  };
  double event[kFamilies]{}, steady[kFamilies]{};
  void finish(double factor = 2) const {
    for (int f = 0; f < kFamilies; ++f) {
      char what[96];
      std::snprintf(what, sizeof what, "family %d jolts %.6f at an event, over %g x its %.6f elsewhere", f, event[f],
                    factor, steady[f]);
      TEST_ASSERT_TRUE_MESSAGE(event[f] <= factor * steady[f] + 1e-9, what);
    }
  }
};
struct Track {
  Jolts* jolts;
  explicit Track(Jolts* j) : jolts(j) {}
  // What the host has said, as the engine keeps it: a frame after it
  // changes is an event's.
  struct Said {
    SceneState base, act;
    bool attention, moment, timedOut, listening, overlay, grab;
    std::string attentionId, requestId;
    int overlayExpression, emotion;
    bool operator==(const Said& o) const {
      return base == o.base && act == o.act && attention == o.attention && moment == o.moment &&
             timedOut == o.timedOut && listening == o.listening && overlay == o.overlay && grab == o.grab &&
             attentionId == o.attentionId && requestId == o.requestId && overlayExpression == o.overlayExpression &&
             emotion == o.emotion;
    }
  };
  static Said said(const Engine& e) {
    const auto& r = e.router;
    return {r.facts.base, r.facts.act, r.facts.attention.on, r.hasMoment,        r.timedOut,          r.listening,
            r.hasOverlay, e.grab,      r.facts.attention.id, r.moment.requestId, r.overlayExpression, e.emotion};
  }
  Said last{};
  Frame frames[2];
  F posture[2][2], reveal[2][2];
  bool shown[2][2]{};
  int seen = 0;
  // Before a step: whether the host has said something since the last.
  bool heard(const Engine& e) const { return seen && !(said(e) == last); }
  // After a step, with what heard() said before it.
  void add(const Engine& e, bool isEvent) {
    const Frame now = capture(e);
    const auto p = e.posture();
    const T t = e.timeMs();
    const F nowPosture[2] = {p[0], p[1]};
    const F nowReveal[2] = {e.scenes.slots[Scenes::kResultProp].reveal.value(t),
                            e.scenes.slots[Scenes::kStartProp].reveal.value(t)};
    const bool nowShown[2] = {now.props[Scenes::kResultProp] > F(0), now.props[Scenes::kStartProp] > F(0)};
    if (seen >= 2) {
      auto& out = isEvent ? jolts->event : jolts->steady;
      auto d2 = [&](int family, F a, F b, F c) {
        out[family] = std::max(out[family], std::abs(double((c - b * 2 + a).raw) / F::scale));
      };
      for (int k = 0; k < 8; ++k)
        d2(Jolts::kControls + k, frames[0].controls[k], frames[1].controls[k], now.controls[k]);
      for (int k = 0; k < 2; ++k) d2(Jolts::kPosture + k, posture[0][k], posture[1][k], nowPosture[k]);
      for (int k = 0; k < Scenes::kProps; ++k)
        d2(Jolts::kProps + k, frames[0].props[k], frames[1].props[k], now.props[k]);
      d2(Jolts::kDesk, frames[0].desk, frames[1].desk, now.desk);
      for (int k = 0; k < 2; ++k)
        if (shown[0][k] && shown[1][k] && nowShown[k]) d2(Jolts::kReveal + k, reveal[0][k], reveal[1][k], nowReveal[k]);
      // Each art by its identity through the three frames: its weight, and
      // its drawn sizes in their controls' families.
      const int sized[] = {2, 4, 5};
      auto find = [](const Frame& f, const Layer& l) -> const Layer* {
        for (int i = 0; i < f.count; ++i)
          if (f.layers[i].art == l.art && f.layers[i].sleeping == l.sleeping) return &f.layers[i];
        return nullptr;
      };
      for (int i = 0; i < now.count; ++i) {
        const Layer &c = now.layers[i], *a = find(frames[0], c), *b = find(frames[1], c);
        if (!a || !b) continue;
        d2(Jolts::kWeight, a->weight, b->weight, c.weight);
        if (c.sleeping) continue;
        for (int r = 0; r < 3; ++r) {
          const F size = slime::kProfile[c.art].face[sized[r]];
          d2(Jolts::kControls + sized[r], a->ratio[r] * size, b->ratio[r] * size, c.ratio[r] * size);
        }
      }
    }
    frames[0] = frames[1], frames[1] = now;
    for (int k = 0; k < 2; ++k) {
      posture[0][k] = posture[1][k], posture[1][k] = nowPosture[k];
      reveal[0][k] = reveal[1][k], reveal[1][k] = nowReveal[k];
      shown[0][k] = shown[1][k], shown[1][k] = nowShown[k];
    }
    last = said(e);
    ++seen;
  }
};

}  // namespace render::gel::frames
