// Q24 functions and springs have bounded quantization error.
#include <unity.h>
#include <cmath>
#include "render/gel/fixed.h"
#include "render/gel/motion.h"
using namespace render::gel;
static double number(F f) { return double(f.raw) / F::scale; }
void test_fixed_math_and_motion() {
  for (int i = -2048; i <= 2048; ++i) {
    F x = F::ratio(i, 16);
    TEST_ASSERT_TRUE(std::abs(std::sin(number(x)) - number(sin(x))) <= .000008);
  }
  for (int i = 0; i <= 100; ++i) {
    F x = F::ratio(-i, 50);
    TEST_ASSERT_TRUE(std::abs(std::exp(number(x)) - number(exp(x))) <= .000003);
  }
  Random random{53};
  Motion motion;
  motion.impulse(false, false, q(.4), q(.2));
  double x = 0, v = -2.6;
  for (int frame = 1; frame <= 180; ++frame) {
    double left = .016;
    while (left > 0) {
      double h = std::min(left, 1.0 / 240);
      v += (-121 * x - 4.6 * v) * h;
      x += v * h;
      left -= h;
    }
    motion.advance(q(.016), F::ratio(frame * 16, 1000), random, false);
    TEST_ASSERT_TRUE(std::abs(x - number(motion.modes[0].x)) <= .0002);
    TEST_ASSERT_TRUE(std::abs(v - number(motion.modes[0].v)) <= .0005);
  }
}
// Integer software timing retains JS double boundary decisions.
void test_software_clock_matches_binary64() {
  T time = 0;
  double expected = 0;
  for (int i = 0; i < 20000; ++i) {
    int ms = i % 46;
    T dt = T::ratio(ms, 1000);
    double d = double(ms) / 1000;
    time += dt;
    expected += d;
    TEST_ASSERT_TRUE(time == T::literal(expected));
    TEST_ASSERT_TRUE(time * 1000 == T::literal(expected * 1000));
    TEST_ASSERT_TRUE((time - T::literal(.4)) == T::literal(expected - .4));
  }
}
