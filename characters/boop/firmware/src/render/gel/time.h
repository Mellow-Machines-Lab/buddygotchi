// Software binary64 timing, using integer operations only: the clock rounds
// at exact cue boundaries the same on every board, with no ESP32 FPU.
// Body, shading and spring arithmetic remain Q24. No host floating point leaks
// into board/native timing. Only compile-time decimal literals use double.
#pragma once
#include "render/gel/fixed.h"
namespace render::gel {
class Time {
  int64_t m_ = 0;
  int e_ = 0;  // signed 53-bit significand * 2^exponent
  static constexpr uint64_t shr(uint64_t n, int bits) {
    return bits <= 0    ? n
           : bits >= 64 ? uint64_t(n != 0)
                        : (n >> bits) | uint64_t((n & ((uint64_t(1) << bits) - 1)) != 0);
  }
  static Time normalized(int64_t n, int e) {
    Time out;
    if (!n) return out;
    bool neg = n < 0;
    uint64_t u = neg ? uint64_t(-n) : uint64_t(n);
    int top = 63 - __builtin_clzll(u), shift = top - 55;
    if (shift > 0) {
      u = shr(u, shift);
      e += shift;
    } else if (shift < 0) {
      u <<= -shift;
      e += shift;
    }
    uint64_t v = u >> 3, rem = u & 7;
    if (rem > 4 || (rem == 4 && (v & 1))) ++v;
    if (v == (uint64_t(1) << 53)) {
      v >>= 1;
      ++e;
    }
    out.m_ = neg ? -int64_t(v) : int64_t(v);
    out.e_ = e + 3;
    return out;
  }

 public:
  constexpr Time() = default;
  Time(int n) { *this = normalized(int64_t(n), 0); }
  Time(F f) { *this = normalized(f.raw, -F::bits); }
  static constexpr Time literal(double d) {
    Time t;
    if (d == 0) return t;
    bool neg = d < 0;
    double a = neg ? -d : d;
    int e = 0;
    while (a >= 2) {
      a /= 2;
      ++e;
    }
    while (a < 1) {
      a *= 2;
      --e;
    }
    t.m_ = int64_t(a * 4503599627370496.0);
    if (neg) t.m_ = -t.m_;
    t.e_ = e - 52;
    return t;
  }
  static Time ratio(int n, int d) { return Time(n) / d; }
  operator F() const {
    int shift = e_ + F::bits;
    if (shift >= 0) return F::fromRaw(m_ * (int64_t(1) << shift));
    if (shift <= -63) return {};
    return F::fromRaw(m_ / (int64_t(1) << -shift));
  }
  Time operator-() const {
    Time t = *this;
    t.m_ = -t.m_;
    return t;
  }
  Time operator+(Time b) const {
    if (!m_) return b;
    if (!b.m_) return *this;
    Time a = *this;
    if (a.e_ < b.e_) std::swap(a, b);
    uint64_t bm = b.m_ < 0 ? uint64_t(-b.m_) : uint64_t(b.m_);
    int64_t tail = int64_t(shr(bm << 3, a.e_ - b.e_));
    if (b.m_ < 0) tail = -tail;
    return normalized(a.m_ * 8 + tail, a.e_ - 3);
  }
  Time operator-(Time b) const { return *this + -b; }
  Time operator*(int n) const { return normalized(m_ * n, e_); }
  F operator*(F value) const { return F(*this) * value; }
  Time operator/(int d) const {
    bool neg = (m_ < 0) != (d < 0);
    uint64_t u = m_ < 0 ? uint64_t(-m_) : uint64_t(m_), den = d < 0 ? uint64_t(-d) : uint64_t(d);
    if (!u || !den) return {};
    uint64_t whole = u / den, rem = u % den;
    int append = 0;
    while (whole < (uint64_t(1) << 55)) {
      whole <<= 1;
      rem <<= 1;
      if (rem >= den) {
        rem -= den;
        whole |= 1;
      }
      ++append;
    }
    if (rem) whole |= 1;
    return normalized(neg ? -int64_t(whole) : int64_t(whole), e_ - append);
  }

  F operator/(Time b) const { return F(*this) / F(b); }
  Time& operator+=(Time b) {
    *this = *this + b;
    return *this;
  }
  bool operator==(Time b) const { return m_ == b.m_ && (m_ == 0 || e_ == b.e_); }
  bool operator!=(Time b) const { return !(*this == b); }
  bool operator<(Time b) const {
    if ((m_ < 0) != (b.m_ < 0)) return m_ < 0;
    if (!m_) return b.m_ > 0;
    if (!b.m_) return m_ < 0;
    if (e_ != b.e_) return m_ < 0 ? e_ > b.e_ : e_ < b.e_;
    return m_ < b.m_;
  }
  bool operator>(Time b) const { return b < *this; }
  bool operator<=(Time b) const { return !(b < *this); }
  bool operator>=(Time b) const { return !(*this < b); }
};
using T = Time;
inline T min(T a, T b) { return a < b ? a : b; }
inline T max(T a, T b) { return a > b ? a : b; }
}  // namespace render::gel
