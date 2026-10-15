#pragma once
#include <array>
#include "render/gel/motion.h"
namespace render::gel {
struct Bag {
  uint8_t values[3]{}, left = 0, last = 255;
  int next(Random& random) {
    if (!left) {
      for (int i = 0; i < 3; ++i) values[i] = uint8_t(i);
      for (int i = 2; i > 0; --i) std::swap(values[i], values[random.index(i + 1)]);
      if (values[0] == last) std::swap(values[0], values[1]);
      left = 3;
    }
    last = values[3 - left--];
    return last;
  }
};
struct Acting {
  Spring channels[6];
  Bag bags[slime::kProfiles];
  int emotion = slime::kCalm, performance = -1, expression = slime::kCalm, chosen = -1, cursor = 0, count = 0;
  T start, nextPerformance = 1;
  bool suppressed = false;
  bool perform(T time, Random& random, int index = -1);
  void setMood(int id, T time) {
    emotion = id;
    performance = -1;
    nextPerformance = time + T::literal(.4);
  }
  void setSuppressed(bool value, T time) {
    if (value == suppressed) return;
    suppressed = value;
    performance = -1;
    if (!value) nextPerformance = max(nextPerformance, time + T::literal(.4));
  }
  void advance(T dt, T time, bool grab, bool reduced, Random& random);
};
enum class Primitive { kSoft, kGather, kBlink, kRecoil };
struct Bridge {
  Spring channels[3];
  Bag bags[slime::kEdgeCount];
  bool active = false, quiet = false, grab = false, attention = false, suppressed = false, expired = false;
  int from = -1, to = -1, edge = -1, variant = 0, category = -1, direction = 0;
  Primitive primitive = Primitive::kSoft;
  F amplitude;
  T elapsedMs, durationMs, startedAtMs, deferredMs;
  void context(bool isQuiet, bool isGrab, bool isAttention) {
    quiet = isQuiet;
    grab = isGrab;
    attention = isAttention;
    if (active && (quiet || attention)) suppressed = true;
  }
  T retarget(int source, int target, T time, Random& random, int forced = -1);
  void advance(T dt, bool reduced);
  F progress() const { return active ? elapsedMs / durationMs : F(1); }
  bool deferred() const { return active && elapsedMs < durationMs && grab && !suppressed && !expired; }
  const char* phase() const;
};
}  // namespace render::gel
