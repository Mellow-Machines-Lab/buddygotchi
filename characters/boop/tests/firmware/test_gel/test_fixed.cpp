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
  motion.impulse(false, q(.4));
  double x = 0, v = -2.6;
  for (int frame = 1; frame <= 180; ++frame) {
    double left = .016;
    while (left > 0) {
      double h = std::min(left, 1.0 / 240);
      v += (-121 * x - 4.6 * v) * h;
      x += v * h;
      left -= h;
    }
    motion.advance(q(.016), F::ratio(frame * 16, 1000), random);
    TEST_ASSERT_TRUE(std::abs(x - number(motion.modes[0].x)) <= .0002);
    TEST_ASSERT_TRUE(std::abs(v - number(motion.modes[0].v)) <= .0005);
  }
}
// A Divisor's quotient is exactly `/`'s across its range: divisors from 1/2,
// dividends under 128 either way (a face layer's ratios, motion.cpp).
void test_a_divisor_divides_exactly() {
  Random random{53};
  const int64_t edges[] = {0, 1, F::scale, (int64_t(1) << 31) - 1};
  for (int i = 0; i < 4000; ++i) {
    const F d = F::fromRaw(i < 2 ? (F::scale / 2) << i : F::scale / 2 + int64_t(random.next()) % (F::scale * 64));
    const Divisor divisor(d);
    for (int j = 0; j < 64; ++j) {
      const int64_t raw = j < 4 ? edges[j] : (int64_t(random.next()) << 15 | random.next() >> 17) % (int64_t(1) << 31);
      // Around a whole multiple of d too, where the quotient steps.
      const int64_t whole = std::min(d.raw * (j % 7), (int64_t(1) << 31) - 1);
      for (const F a : {F::fromRaw(raw), F::fromRaw(-raw), F::fromRaw(whole), F::fromRaw(whole - 1)})
        TEST_ASSERT_TRUE(divisor.divide(a) == a / d);
    }
  }
}
// Integer software timing decides boundaries as binary64 doubles do.
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
