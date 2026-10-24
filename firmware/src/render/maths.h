// Integer maths the device and the simulator share, so they agree to the
// pixel and the millisecond.
#pragma once
#include <cstdint>

namespace render {

// Smoothstep ease-in-out: t of `dur` → 0..1024.
constexpr int ease(int t, int dur) {
  if (dur <= 0 || t >= dur) return 1024;
  if (t <= 0) return 0;
  int64_t u = int64_t(t) * 1024 / dur;  // 0..1024
  return int(u * u * (3 * 1024 - 2 * u) / (1024 * 1024));
}
// The same, in thousandths: 0..1000.
constexpr int ease1000(int t, int dur) { return ease(t, dur) * 1000 / 1024; }

// The cubic Hermite from `from`, leaving with slope `tangent`, to `to`,
// arriving flat, s of the way (0..1024): its value, and its slope, both per
// the whole way. With no tangent, it's ease's smoothstep.
struct Hermite {
  int value, slope;
};
constexpr Hermite hermite(int from, int tangent, int to, int s) {
  const int64_t u = s, left = 1024 - u, rise = int64_t(to) - from;
  const int64_t h01 = ease(s, 1024), h10 = u * left * left / (1024 * 1024);
  return {int(from + (rise * h01 + tangent * h10) / 1024),
          int((rise * 6 * u * left / 1024 + tangent * left * (1024 - 3 * u) / 1024) / 1024)};
}

// q of the way (0 … one) from a to b.
constexpr int lerp(int a, int b, int q, int one) { return a + int(int64_t(b - a) * q / one); }

// v, held within [lo, hi].
constexpr int clamp(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

// Millisecond times, which wrap every 49 days: a later than b, and t in
// [from, from + ms).
constexpr bool after(uint32_t a, uint32_t b) { return int32_t(a - b) > 0; }
constexpr bool within(uint32_t t, uint32_t from, uint32_t ms) {
  return int32_t(t - from) >= 0 && int32_t(t - from) < int32_t(ms);
}

}  // namespace render
