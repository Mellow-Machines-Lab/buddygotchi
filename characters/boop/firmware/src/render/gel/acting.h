#pragma once
#include <algorithm>
#include <array>
#include <string>
#include <vector>
#include "render/gel/motion.h"
#include "render/tags.h"
namespace render::gel {
// A profile's gestures, as slimegen sizes them: the first takes of idle and
// of every scene row.
constexpr int kGestures = int(std::size(slime::kProfile[0].performances));
// A shuffle bag of a key's takes. Its first round deals the
// first three, the ones every state has always had; from its second round on
// it deals every take, the comedy ones too. Never the take it dealt last.
template <int Capacity>
struct Bag {
  static_assert(Capacity >= kGestures, "every bag deals at least three takes");
  uint8_t values[Capacity]{}, left = 0, size = 0, last = 255;
  bool dealt = false;
  int next(Random& random, int takes = kGestures) {
    if (!left) {
      size = uint8_t(dealt ? std::min(takes, Capacity) : std::min(takes, kGestures));
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
// A contact as it fires: a scene's, or a gag's (requestId "gag"), named by
// its request, generation, iteration and index, never as one string:
// building one on every contact cost the board's heap a few allocations
// each.
struct ContactEvent {
  std::string requestId;
  int generation = 0, iteration = 0, index = 0;
  uint8_t kind = 0;
  int side = 0;
  T timeMs;
  F strength;
};
// A gag's target for a channel at its age, from (0, 0) at
// its start, a smoothstep to each of the channel's keys, then its last value.
F keyed(const slime::Gag& gag, int channel, T age);
struct Acting {
  // The six gesture springs, then a gag's own: the dome's slide, and how far
  // its lids are closed (critically damped).
  Spring channels[6], slide, lids;
  Bag<slime::kMaxGestures> bags[slime::kProfiles];
  // performance is the take playing (an idle occasion's numbered after the
  // takes), or -1; playing, a recipe's gag (kGags) playing in its place.
  int emotion = slime::kCalm, performance = -1, playing = -1, expression = slime::kCalm, chosen = -1, cursor = 0,
      contactCursor = 0, count = 0;
  T start, nextPerformance = 1;
  bool suppressed = false;
  // A recipe's gag held for one pass of it (the scene's generation and
  // iteration): acting deals nothing of its own meanwhile.
  bool holding = false;
  int heldGeneration = 0, heldIteration = 0;
  // The tags on and how long the look has shown (Engine::setOccasion).
  uint32_t when = 0, lookMs = 0;
  // This step's gag contacts, the sounds of a sneeze or the zoomies.
  std::vector<ContactEvent> contacts;
  Acting() { contacts.reserve(4); }
  // Idle's takes for an expression: its three gestures, its own gags, then
  // every expression's idle gags.
  static int takes(int profile) { return kGestures + slime::kProfile[profile].gagCount + slime::kIdleGagCount; }
  // A take's gag; none for the three gestures. After the takes, idle's
  // occasions.
  static const slime::Gag* gag(int profile, int take) {
    const auto& p = slime::kProfile[profile];
    if (take < kGestures) return nullptr;
    if (take >= takes(profile)) return &slime::kGags[slime::kIdleOccasions[take - takes(profile)].gag];
    take -= kGestures;
    return &slime::kGags[take < p.gagCount ? p.gags[take] : slime::kIdleGags[take - p.gagCount]];
  }
  // A take's impulses and timing.
  static const slime::Performance& gesture(int profile, int take) {
    const auto* g = gag(profile, take);
    return g ? g->gesture : slime::kProfile[profile].performances[take];
  }
  // What plays now: a recipe's gag, or the take's (none for a gesture of
  // the expression's own).
  const slime::Gag* current() const { return playing >= 0 ? &slime::kGags[playing] : gag(emotion, performance); }
  // The lids as drawn: a closure in [0, 1], like a blink's.
  F closure() const { return clamp(lids.x, 0, 1); }
  bool perform(T time, Random& random, int index = -1);
  // A recipe's gag (kGags; -1 lets go), once for each pass of the recipe.
  // It plays from now, and acting's own next gesture waits three seconds
  // after it ends.
  void hold(int gag, int generation, int iteration, T time);
  void setMood(int id, T time) {
    emotion = id;
    performance = playing = -1;
    nextPerformance = time + T::literal(.4);
  }
  void setSuppressed(bool value, T time) {
    if (value == suppressed) return;
    suppressed = value;
    performance = playing = -1;
    if (!value) nextPerformance = max(nextPerformance, time + T::literal(.4));
  }
  void advance(T dt, T time, bool grab, Random& random);
};
enum class Primitive { kSoft, kGather, kBlink, kRecoil };
struct Bridge {
  Spring channels[3];
  Bag<3> bags[slime::kEdgeCount];
  bool active = false, quiet = false, grab = false, attention = false, suppressed = false, expired = false;
  int from = -1, to = -1, edge = -1, variant = 0, category = -1, direction = 0;
  Primitive primitive = Primitive::kSoft;
  F amplitude;
  T elapsedMs, durationMs, deferredMs;
  void context(bool isQuiet, bool isGrab, bool isAttention) {
    quiet = isQuiet;
    grab = isGrab;
    attention = isAttention;
    if (active && (quiet || attention)) suppressed = true;
  }
  T retarget(int source, int target, T time, Random& random, int forced = -1);
  void advance(T dt);
  F progress() const { return active ? elapsedMs / durationMs : F(1); }
};
}  // namespace render::gel
