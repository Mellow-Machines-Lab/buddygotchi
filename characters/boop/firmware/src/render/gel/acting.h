#pragma once
#include <algorithm>
#include <array>
#include <string>
#include <vector>
#include "render/gel/motion.h"
namespace render::gel {
// A shuffle bag of a key's takes (variation.mjs). Its first round deals the
// first three, the ones every state has always had; from its second round on
// it deals every take, the comedy ones too. Never the take it dealt last.
template <int Capacity>
struct Bag {
  static_assert(Capacity >= 3, "every bag deals at least three takes");
  uint8_t values[Capacity]{}, left = 0, size = 0, last = 255;
  bool dealt = false;
  int next(Random& random, int takes = 3) {
    if (!left) {
      size = uint8_t(dealt ? std::min(takes, Capacity) : std::min(takes, 3));
      dealt = true;
      for (int i = 0; i < size; ++i) values[i] = uint8_t(i);
      for (int i = size - 1; i > 0; --i) std::swap(values[i], values[random.index(i + 1)]);
      if (values[0] == last) std::swap(values[0], values[1]);
      left = size;
    }
    last = values[size - left--];
    return last;
  }
};
// A contact as it fires: a scene's, or a gag's (requestId "gag"). The
// reference's id for it is "requestId:generation:iteration:index", which
// nothing on the device reads, so only the trace check spells it out
// (gel-trace): building it on every contact cost the board's heap a few
// allocations each.
struct ContactEvent {
  std::string requestId;
  int generation = 0, iteration = 0, index = 0;
  uint8_t kind = 0;
  int side = 0;
  T timeMs;
  F strength;
};
// acting.mjs keyed: a gag's target for a channel at its age, from (0, 0) at
// its start, a smoothstep to each of the channel's keys, then its last value.
F keyed(const slime::Gag& gag, int channel, T age);
struct Acting {
  // The six gesture springs, then a gag's own: the dome's slide, and how far
  // its lids are closed (critically damped).
  Spring channels[6], slide, lids;
  Bag<slime::kMaxGestures> bags[slime::kProfiles];
  int emotion = slime::kCalm, performance = -1, expression = slime::kCalm, chosen = -1, cursor = 0, contactCursor = 0,
      count = 0;
  T start, nextPerformance = 1;
  bool suppressed = false;
  // A gag has played: its channels join the trace (gel-trace), as they do
  // the reference's inspection.
  bool gagged = false;
  // This step's gag contacts, the sounds of a sneeze or the zoomies.
  std::vector<ContactEvent> contacts;
  Acting() { contacts.reserve(4); }
  // Idle's takes for an expression: its three gestures, its own gags, then
  // every expression's idle gags.
  static int takes(int profile) { return 3 + slime::kProfile[profile].gagCount + slime::kIdleGagCount; }
  // A take's gag; none for the three gestures.
  static const slime::Gag* gag(int profile, int take) {
    const auto& p = slime::kProfile[profile];
    if (take < 3) return nullptr;
    take -= 3;
    return &slime::kGags[take < p.gagCount ? p.gags[take] : slime::kIdleGags[take - p.gagCount]];
  }
  // A take's impulses and timing.
  static const slime::Performance& gesture(int profile, int take) {
    const auto* g = gag(profile, take);
    return g ? g->gesture : slime::kProfile[profile].performances[take];
  }
  // The lids as drawn: a closure in [0, 1], like a blink's.
  F closure() const { return clamp(lids.x, 0, 1); }
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
  Bag<3> bags[slime::kEdgeCount];
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
