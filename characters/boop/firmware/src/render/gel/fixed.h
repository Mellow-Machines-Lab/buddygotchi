// Signed Q24 arithmetic for the gel engine. Runtime calculations
// use integers on both native and ESP32; decimal constants fold at compile time.
#pragma once
#include <algorithm>
#include <cstdint>
namespace render::gel {
class Fixed {
 public:
  static constexpr int bits = 24;
  static constexpr int64_t scale = int64_t(1) << bits;
  int64_t raw = 0;
  constexpr Fixed() = default;
  constexpr Fixed(int n) : raw(int64_t(n) * scale) {}
  static constexpr Fixed fromRaw(int64_t n) {
    Fixed x;
    x.raw = n;
    return x;
  }
  static constexpr Fixed decimal(double n) { return fromRaw(int64_t(n * scale + (n >= 0 ? .5 : -.5))); }
  static constexpr Fixed ratio(int64_t n, int64_t d) { return fromRaw((n * scale + (n >= 0 ? d / 2 : -d / 2)) / d); }
  int integer() const { return int(raw / scale); }
  int floor() const { return int(raw / scale - (raw < 0 && raw % scale != 0)); }
  constexpr Fixed operator-() const { return fromRaw(-raw); }
  constexpr Fixed operator+(Fixed b) const { return fromRaw(raw + b.raw); }
  constexpr Fixed operator-(Fixed b) const { return fromRaw(raw - b.raw); }
  Fixed operator*(Fixed b) const {
    int64_t a = raw, v = b.raw;
    if ((a < 0 ? -a : a) < (v < 0 ? -v : v)) std::swap(a, v);
    return fromRaw((a / scale) * v + (a % scale) * v / scale);
  }
  Fixed operator/(Fixed b) const {
    const bool negative = (raw < 0) != (b.raw < 0);
    uint64_t a = raw < 0 ? uint64_t(-raw) : uint64_t(raw), d = b.raw < 0 ? uint64_t(-b.raw) : uint64_t(b.raw);
    if (!d) return {};
    uint64_t whole = a / d, rem = a % d, frac = 0;
    for (int i = 0; i < bits; ++i) {
      rem *= 2;
      frac <<= 1;
      if (rem >= d) rem -= d, frac |= 1;
    }
    int64_t result = int64_t(whole * scale + frac);
    return fromRaw(negative ? -result : result);
  }
  constexpr Fixed operator*(int n) const { return fromRaw(raw * n); }
  constexpr Fixed operator/(int n) const { return fromRaw(raw / n); }
  Fixed& operator+=(Fixed b) {
    raw += b.raw;
    return *this;
  }
  Fixed& operator-=(Fixed b) {
    raw -= b.raw;
    return *this;
  }
  Fixed& operator*=(Fixed b) {
    *this = *this * b;
    return *this;
  }
  constexpr bool operator<(Fixed b) const { return raw < b.raw; }
  constexpr bool operator>(Fixed b) const { return raw > b.raw; }
  constexpr bool operator<=(Fixed b) const { return raw <= b.raw; }
  constexpr bool operator>=(Fixed b) const { return raw >= b.raw; }
  constexpr bool operator==(Fixed b) const { return raw == b.raw; }
  constexpr bool operator!=(Fixed b) const { return raw != b.raw; }
};
using F = Fixed;
constexpr F operator+(int a, F b) { return F(a) + b; }
constexpr F operator-(int a, F b) { return F(a) - b; }
constexpr F operator*(int a, F b) { return b * a; }
constexpr F q(double n) { return F::decimal(n); }
// A value in the painters' Q12 (4096 is one), toward zero.
inline int scalar(F v) { return int(v.raw / (F::scale / 4096)); }
// Dividing by one divisor many times: its reciprocal, worked out once,
// makes each quotient a multiply and one correction, exactly the quotient
// `/` gives (toward zero). For a divisor of at least 1/2 and a dividend
// under 128: then the multiply fits 64 bits and overshoots by less than one.
class Divisor {
 public:
  constexpr Divisor() = default;  // one
  explicit Divisor(F d) : d_(d.raw), m_(((uint64_t(1) << (2 * F::bits + 8)) + uint64_t(d.raw) - 1) / uint64_t(d.raw)) {}
  F divide(F a) const {
    const uint64_t n = a.raw < 0 ? uint64_t(-a.raw) : uint64_t(a.raw);
    uint64_t quotient = n * m_ >> (F::bits + 8);
    if (quotient * uint64_t(d_) > n << F::bits) --quotient;
    return F::fromRaw(a.raw < 0 ? -int64_t(quotient) : int64_t(quotient));
  }

 private:
  int64_t d_ = F::scale;
  uint64_t m_ = uint64_t(1) << (F::bits + 8);  // 2^56 / d_, rounded up
};
inline F clamp(F x, F lo, F hi) { return x < lo ? lo : x > hi ? hi : x; }
inline F abs(F x) { return x.raw < 0 ? -x : x; }
inline F min(F a, F b) { return a < b ? a : b; }
inline F max(F a, F b) { return a > b ? a : b; }
inline F square(F x) { return x * x; }
constexpr F pi = q(3.14159265358979323846);
inline F sin(F x) {
  x = F::fromRaw(x.raw % (pi.raw * 2));
  if (x > pi) x -= pi * 2;
  if (x < -pi) x += pi * 2;
  if (x > pi / 2)
    x = pi - x;
  else if (x < -pi / 2)
    x = -pi - x;
  const F xx = x * x;
  F result = x, term = x;
  for (int n = 1; n < 9; ++n) {
    term = -term * xx / ((2 * n) * (2 * n + 1));
    result += term;
  }
  return result;
}
inline F cos(F x) { return sin(x + pi / 2); }
// The sine of a turn's 4096ths, Q12, from a quarter wave's 64 steps and a
// line between each two: the series above divides 64-bit numbers nine
// times a call, which the board does in software.
inline constexpr int16_t kQuarter[65] = {0,     402,   804,   1205,  1606,  2006,  2404,  2801,  3196,  3590,  3981,
                                         4370,  4756,  5139,  5520,  5897,  6270,  6639,  7005,  7366,  7723,  8076,
                                         8423,  8765,  9102,  9434,  9760,  10080, 10394, 10702, 11003, 11297, 11585,
                                         11866, 12140, 12406, 12665, 12916, 13160, 13395, 13623, 13842, 14053, 14256,
                                         14449, 14635, 14811, 14978, 15137, 15286, 15426, 15557, 15679, 15791, 15893,
                                         15986, 16069, 16143, 16207, 16261, 16305, 16340, 16364, 16379, 16384};
inline int sinTurn(int t) {
  t &= 4095;
  const int half = t >> 10, within = t & 1023, i = half & 1 ? 1024 - within : within, at = i >> 4;
  const int v = at >= 64 ? kQuarter[64] : kQuarter[at] + (kQuarter[at + 1] - kQuarter[at]) * (i & 15) / 16;
  return half & 2 ? -(v >> 2) : v >> 2;
}
inline F exp(F x) {
  F result = 1, term = 1;
  for (int n = 1; n < 24; ++n) {
    term = term * x / n;
    result += term;
    if (!term.raw) break;
  }
  return result;
}
inline F sqrt(F x) {
  if (x.raw <= 0) return {};
  uint64_t n = uint64_t(x.raw) * F::scale, res = 0, bit = uint64_t(1) << 62;
  while (bit > n) bit >>= 2;
  while (bit) {
    if (n >= res + bit)
      n -= res + bit, res = (res >> 1) + bit;
    else
      res >>= 1;
    bit >>= 2;
  }
  return F::fromRaw(int64_t(res));
}
inline F smooth(F x) {
  x = clamp(x, 0, 1);
  return x * x * (F(3) - x * 2);
}
// A Hermite: the cubic from (from, tangent) to `to` at s, its
// value held within [0, 1] and its slope per unit of s, flat where it's held
// (so a retarget never brings back what it held at zero); at its end,
// exactly to.
inline void hermite(F from, F tangent, F to, F s, F& value, F& slope) {
  if (s >= F(1)) {
    value = to;
    slope = 0;
    return;
  }
  F s2 = s * s, s3 = s2 * s;
  const F cubic = (s3 * 2 - s2 * 3 + 1) * from + (s3 - s2 * 2 + s) * tangent + (s2 * 3 - s3 * 2) * to;
  value = clamp(cubic, 0, 1);
  slope = value == cubic ? (s2 * 6 - s * 6) * from + (s2 * 3 - s * 4 + 1) * tangent + (s * 6 - s2 * 6) * to : F(0);
}
struct Spring {
  F x, v;
};
inline void integrate(Spring& m, F dt, F target, F frequency, F damping, F positionLimit, F velocityLimit) {
  for (F left = dt; left > F(0);) {
    F h = min(left, q(1.0 / 240));
    m.v += (frequency * frequency * (target - m.x) - damping * m.v) * h;
    m.x += m.v * h;
    left -= h;
  }
  m.x = clamp(m.x, -positionLimit, positionLimit);
  m.v = clamp(m.v, -velocityLimit, velocityLimit);
}
struct Random {
  uint32_t state = 1729;
  explicit Random(uint32_t seed = 1729) : state(seed) {}
  uint32_t next() {
    state = state * 1664525u + 1013904223u;
    return state;
  }
  F unit() { return F::fromRaw(next() >> 8); }
  int index(int n) { return int(uint64_t(next()) * unsigned(n) >> 32); }
};
}  // namespace render::gel
