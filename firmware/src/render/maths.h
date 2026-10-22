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

// v, held within [lo, hi].
constexpr int clamp(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

// Millisecond times, which wrap every 49 days: a later than b, and t in
// [from, from + ms).
constexpr bool after(uint32_t a, uint32_t b) { return int32_t(a - b) > 0; }
constexpr bool within(uint32_t t, uint32_t from, uint32_t ms) {
  return int32_t(t - from) >= 0 && int32_t(t - from) < int32_t(ms);
}

}  // namespace render
