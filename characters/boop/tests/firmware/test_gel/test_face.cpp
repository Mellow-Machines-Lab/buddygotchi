// The semantic face: what a change of face does to it, frame by frame.
#include <unity.h>

#include <algorithm>
#include <cmath>
#include <memory>

#include "frames.h"

using namespace render;
using namespace render::gel;

namespace {

const T kFrame = T::ratio(16, 1000);

double number(F f) { return double(f.raw) / F::scale; }
// Unity here has no doubles: within `tolerance` of `want`.
#define TEST_NEAR(tolerance, want, got) TEST_ASSERT_TRUE(std::abs(double(want) - double(got)) <= (tolerance))

}  // namespace

// Seven moods asked for 48 ms apart: each retarget starts the face from its
// controls as they are; the controls stay within the span of everything
// they started from or were asked for; four arts cross over at once at the
// most; and the face settles on the last, alone, within a second.
void test_a_rapid_chain_settles_on_the_last() {
  auto e = std::make_unique<Engine>();
  uint32_t t = 0;
  e->step(t);
  frames::Frame last = frames::capture(*e);
  std::array<F, 8> lo = e->face.controls, hi = e->face.controls;
  int crowded = 0;
  const int chain[] = {slime::kCurious, slime::kSurprised, slime::kWounded, slime::kSad,
                       slime::kHappy,   slime::kLonely,    slime::kAngry};
  auto frame = [&] {
    e->step(t += 16);
    frames::check(*e, &last);
    last = frames::capture(*e);
    for (int k = 0; k < 8; ++k)
      TEST_ASSERT_TRUE(e->face.controls[k] >= lo[k] - q(.000001) && e->face.controls[k] <= hi[k] + q(.000001));
    crowded = std::max(crowded, e->face.count);
  };
  for (int i = 0; i < 7; ++i) {
    const auto before = e->face.controls;
    e->setMood(chain[i]);
    TEST_ASSERT_TRUE(e->face.from == before);
    for (int k = 0; k < 8; ++k) lo[k] = min(lo[k], e->face.to[k]), hi[k] = max(hi[k], e->face.to[k]);
    for (int k = 0; k < 3; ++k) frame();
  }
  for (const uint32_t end = t + 1024; t < end;) frame();
  TEST_ASSERT_EQUAL_INT(4, crowded);
  TEST_ASSERT_EQUAL_INT(1, e->face.count);
  TEST_ASSERT_EQUAL_INT(slime::kAngry, e->face.current().art);
}

// The face's controls each follow a critically damped spring at frequency
// 20, which keeps its velocity across a retarget and never overshoots from
// rest; a mood change draws nothing different at once, then crosses its
// arts over in the face's 180 ms, the new one's weight a smoothstep, the
// newest drawn last; waking takes the same window and spring; and an art is
// drawn at a ratio of its own size that is one at one, rises with slope one
// there and saturates inside (3/4, 4/3).
void test_the_semantic_face_numbers() {
  static_assert(SemanticFace::kFaceMs == 180 && SemanticFace::kFaceFrequency == 20, "the face's window and spring");
  // One frame of the spring, from where the controls are and as fast as
  // they're going, toward the target, at kScale.
  auto spring = [](double x, double v, double goal, double w, double& outV) {
    x *= SemanticFace::kScale, v *= 1, goal *= SemanticFace::kScale;
    for (double left = .016; left > 1e-12;) {
      const double h = std::min(left, 1.0 / 240);
      v += (w * w * (goal - x) - 2 * w * v) * h;
      x += v * h;
      left -= h;
    }
    outV = v;
    return x / SemanticFace::kScale;
  };
  for (int id = 0; id + 1 < slime::kProfiles; ++id) {
    SemanticFace f;
    f.setMood(id);
    for (int frame = 0; frame < 60; ++frame) f.advance(kFrame);
    TEST_ASSERT_EQUAL_INT(1, f.count);
    const SemanticFace settled = f;
    f.setMood(id + 1);
    TEST_ASSERT_EQUAL_INT(2, f.count);
    TEST_ASSERT_TRUE(f.controls == settled.controls && f.velocity == settled.velocity);
    TEST_ASSERT_TRUE(f.layers[0].weight == F(1) && f.layers[1].weight == F(0));
    TEST_ASSERT_TRUE(f.ratios(f.layers[0]) == settled.ratios(settled.layers[0]));
    const auto start = f.controls, goal = f.to;
    for (int frame = 1; frame <= 12; ++frame) {
      const auto was = f.controls;
      const auto speed = f.velocity;
      f.advance(kFrame);
      for (int k = 0; k < 6; ++k) {
        double v;
        const double x = spring(number(was[k]), number(speed[k]), number(goal[k]), 20, v);
        TEST_NEAR(2e-6, x, number(f.controls[k]));
        TEST_ASSERT_TRUE(f.controls[k] >= min(start[k], goal[k]) && f.controls[k] <= max(start[k], goal[k]));
      }
      if (frame < 12) {
        TEST_ASSERT_EQUAL_INT(2, f.count);
        TEST_ASSERT_EQUAL_INT(id + 1, f.current().art);
        const double s = frame * 16 / 180.0;
        TEST_NEAR(1e-4, s * s * (3 - 2 * s), number(f.layers[1].weight));
      } else {
        TEST_ASSERT_EQUAL_INT(1, f.count);
      }
    }
  }
  // A retarget mid-window keeps every control's velocity, the next frame
  // carrying on from it toward the new target, and draws the newest last.
  SemanticFace f;
  f.setMood(slime::kWounded);
  f.advance(kFrame);
  f.advance(kFrame);
  const auto moving = f.velocity;
  const auto at = f.controls;
  f.setMood(slime::kHappy);
  TEST_ASSERT_TRUE(f.velocity == moving);
  TEST_ASSERT_EQUAL_INT(3, f.count);
  TEST_ASSERT_EQUAL_INT(slime::kCalm, f.layers[0].art);
  TEST_ASSERT_EQUAL_INT(slime::kWounded, f.layers[1].art);
  TEST_ASSERT_EQUAL_INT(slime::kHappy, f.layers[2].art);
  f.advance(kFrame);
  for (int k = 0; k < 6; ++k) {
    double v;
    TEST_NEAR(2e-6, spring(number(at[k]), number(moving[k]), number(f.to[k]), 20, v), number(f.controls[k]));
  }
  // Waking from a settled sleeping face: the face's window, and its spring.
  SemanticFace sleeper;
  sleeper.setSleeping(true);
  for (int frame = 0; frame < 300; ++frame) sleeper.advance(kFrame);
  TEST_ASSERT_TRUE(sleeper.current().sleeping);
  sleeper.setMood(slime::kHappy);
  const auto asleep = sleeper.controls;
  sleeper.setSleeping(false);
  TEST_ASSERT_TRUE(sleeper.durationMs == T(SemanticFace::kFaceMs));
  sleeper.advance(kFrame);
  double v;
  TEST_NEAR(2e-6, spring(number(asleep[2]), 0, number(slime::kProfile[slime::kHappy].face[2]), 20, v),
            number(sleeper.controls[2]));
  for (int frame = 1; frame < 12; ++frame) sleeper.advance(kFrame);
  TEST_ASSERT_EQUAL_INT(1, sleeper.count);
  TEST_ASSERT_EQUAL_INT(slime::kHappy, sleeper.current().art);
  TEST_ASSERT_FALSE(sleeper.current().sleeping);
  // The drawn ratio of an art's own size.
  TEST_ASSERT_TRUE(softRatio(F(1)) == F(1));
  TEST_NEAR(5e-3, 1, (number(softRatio(q(1.001))) - number(softRatio(q(.999)))) / .002);
  F last = softRatio(F(0));
  TEST_ASSERT_TRUE(last > q(.75));
  for (int k = 1; k <= 1200; ++k) {
    const F now = softRatio(F::ratio(k, 100));
    TEST_ASSERT_TRUE(now > last && now > q(.75) && now < q(4.0 / 3));
    last = now;
  }
}
