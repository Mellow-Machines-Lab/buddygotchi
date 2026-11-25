#pragma once
#include <algorithm>
#include <array>
#include <string>
#include <vector>
#include "render/gel/motion.h"
#include "render/gel/router.h"
#include "render/tags.h"
namespace render::gel {
// The first takes every scene row has (slime::kRecipes).
constexpr int kFirstTakes = 3;
// A shuffle bag of a key's takes. Its first round deals the
// first three, the ones every state has always had; from its second round on
// it deals every take, the comedy ones too. Never the take it dealt last,
// while it has another.
template <int Capacity>
struct Bag {
  static_assert(Capacity >= kFirstTakes, "every bag deals at least three takes");
  uint8_t values[Capacity]{}, left = 0, size = 0, last = 255;
  bool dealt = false;
  int next(Random& random, int takes = kFirstTakes) {
    if (!left) {
      size = uint8_t(dealt ? std::min(takes, Capacity) : std::min(takes, kFirstTakes));
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
// A contact as it fires: a scene's, or a bit's (Shows::kBit), named by what
// showed, its generation, iteration and index.
struct ContactEvent {
  uint64_t key = 0;
  int generation = 0, iteration = 0, index = 0;
  uint8_t kind = 0;
  int side = 0;
  T timeMs;
  F strength;
};
// A bit's target for a channel at its age, from (0, 0) at
// its start, a smoothstep to each of the channel's keys, then its last value.
F keyed(const slime::Gag& gag, int channel, T age);
struct Acting {
  // The six gesture springs, then a bit's own: the dome's slide, and how far
  // its lids are closed (critically damped).
  Spring channels[6], slide, lids;
  Bag<kFirstTakes> bags[slime::kProfiles];
  // performance is the take playing, or -1; playing, a recipe's or a
  // pastime's bit (kGags) playing in its place.
  int emotion = slime::kCalm, performance = -1, playing = -1, expression = slime::kCalm, chosen = -1, cursor = 0,
      contactCursor = 0, count = 0;
  T start, nextPerformance = 1;
  bool suppressed = false;
  // A recipe's bit held for one pass of it (the scene's generation and
  // iteration): acting deals nothing of its own meanwhile.
  bool holding = false;
  int heldGeneration = 0, heldIteration = 0;
  // This step's bit contacts, the sounds of a sneeze or the zoomies.
  std::vector<ContactEvent> contacts;
  Acting() { contacts.reserve(4); }
  // Idle's takes for an expression: its lasting mood's one move (take 0, the
  // rig clip slime::kIdleMoves names, which the face plays: `move`), then
  // its own bits. The comedy every mood shares is the face's to deal, as
  // pastimes.
  static_assert(slime::kIdleTakes <= kFirstTakes, "a bag deals every idle take in its first round");
  static int takes(int profile) { return 1 + slime::kProfile[profile].gagCount; }
  // A take's bit; none for the move.
  static const slime::Gag* gag(int profile, int take) {
    if (take < 1) return nullptr;
    return &slime::kGags[slime::kProfile[profile].gags[take - 1]];
  }
  // How long a take plays: its bit's, or its move's clip's.
  static T duration(int profile, int take);
  // The mood's move, dealt and not yet played: its clip's id, which the
  // face plays and clears.
  const char* move = nullptr;
  // What plays now: a recipe's bit, or the take's (none for a gesture of
  // the expression's own).
  const slime::Gag* current() const { return playing >= 0 ? &slime::kGags[playing] : gag(emotion, performance); }
  // The lids as drawn: a closure in [0, 1], like a blink's.
  F closure() const { return clamp(lids.x, 0, 1); }
  bool perform(T time, Random& random, int index = -1);
  // A recipe's bit (kGags; -1 lets go), once for each pass of the recipe.
  // It plays from now, and acting's own next gesture waits three seconds
  // after it ends.
  void hold(int gag, int generation, int iteration, T time);
  // A pastime's bit (kGags), which the face dealt: it plays from now in
  // place of the next gesture, which waits three seconds after it ends.
  void play(int gag, T time);
  // Bit g starts now, in place of a performance: hold's and play's start.
  void begin(int g, T time);
  void setMood(int id, T time) {
    emotion = id;
    performance = playing = -1;
    move = nullptr;
    nextPerformance = time + T::literal(.4);
  }
  void setSuppressed(bool value, T time) {
    if (value == suppressed) return;
    suppressed = value;
    performance = playing = -1;
    move = nullptr;
    if (!value) nextPerformance = max(nextPerformance, time + T::literal(.4));
  }
  void advance(T dt, T time, bool grab, Random& random);
};
// The body's small beat at a change of mood: a change of face within one
// mood (happy to pleased) has none. One of three, dealt afresh each time.
enum class Primitive { kSoft, kGather, kBlink };
struct MoodBeat {
  Spring channels[3];
  bool active = false, quiet = false, grab = false, attention = false, suppressed = false, expired = false;
  int from = -1, to = -1, variant = 0, direction = 0;
  bool moves = false;
  Primitive primitive = Primitive::kSoft;
  F amplitude;
  T elapsedMs, durationMs, deferredMs;
  void context(bool isQuiet, bool isGrab, bool isAttention) {
    quiet = isQuiet;
    grab = isGrab;
    attention = isAttention;
    if (active && (quiet || attention)) suppressed = true;
  }
  // Starts the beat for a change from one face to another, and returns how
  // long the face takes to cross over.
  T retarget(int source, int target, Random& random);
  void advance(T dt);
  F progress() const { return active ? elapsedMs / durationMs : F(1); }
};
}  // namespace render::gel
