// The rig: the numbers a character is at any instant, the same set for
// every pack and every face, and a pack's data on them: its expressions,
// clips, looks and accessories, which characters/charactergen.py writes
// from the pack's rig/ into the staged rig_tables.h (characters/CHARACTER.md
// §15). A face turns the channels into pixels its own way. Portable C++:
// the board, the native simulator and the WebAssembly one build it alike.
#pragma once
#include <cstdint>

#include "render/tags.h"
#include "render/types.h"

namespace render::rig {

// The body's, the eyes', the mouth's, and what else shows on the face.
enum class Channel : uint8_t {
  kX,
  kY,
  kSquash,
  kLean,
  kTilt,
  kLift,
  kEyeOpenL,
  kEyeOpenR,
  kEyeCurve,
  kEyeSize,
  kGazeX,
  kGazeY,
  kMouthWidth,
  kMouthCurve,
  kMouthOpen,
  kCheek,
  kTear,
  kSweat,
  kCount
};
constexpr int kChannelCount = int(Channel::kCount);

// Each channel's name in a pack's rig/ files, its range and its value at
// rest. In thousandths, but for x, y and lift: px of the 320 × 240 canvas,
// x right, y down and lift up. squash runs from tall (-1000) to flat; lean,
// the body's, from left to right; tilt, the head's, anticlockwise to
// clockwise; eyeOpen from shut (0); eyeCurve and mouthCurve from a sad arc
// or a frown (-1000) to a happy arc or a smile; gaze from left or up
// (-1000) to right or down; eyeSize and mouthWidth around the pack's own
// (1000). charactergen.py reads this table to check a pack's files.
struct ChannelInfo {
  const char* name;
  int16_t lo, hi, rest;
};
constexpr ChannelInfo kChannelInfo[kChannelCount] = {{"x", -320, 320, 0},           {"y", -240, 240, 0},
                                                     {"squash", -1000, 1000, 0},    {"lean", -1000, 1000, 0},
                                                     {"tilt", -1000, 1000, 0},      {"lift", -240, 240, 0},
                                                     {"eyeOpenL", 0, 1000, 1000},   {"eyeOpenR", 0, 1000, 1000},
                                                     {"eyeCurve", -1000, 1000, 0},  {"eyeSize", 500, 1500, 1000},
                                                     {"gazeX", -1000, 1000, 0},     {"gazeY", -1000, 1000, 0},
                                                     {"mouthWidth", 0, 1500, 1000}, {"mouthCurve", -1000, 1000, 0},
                                                     {"mouthOpen", 0, 1000, 0},     {"cheek", 0, 1000, 0},
                                                     {"tear", 0, 1000, 0},          {"sweat", 0, 1000, 0}};
// The body's channels, whose springs are slower than the face's.
constexpr bool body(Channel c) { return c <= Channel::kLift; }

// A value for every channel.
struct Channels {
  int16_t v[kChannelCount];
  constexpr int16_t operator[](Channel c) const { return v[int(c)]; }
  constexpr int16_t& operator[](Channel c) { return v[int(c)]; }
};
// Every channel at rest.
inline constexpr Channels kRest = [] {
  Channels c{};
  for (int i = 0; i < kChannelCount; ++i) c.v[i] = kChannelInfo[i].rest;
  return c;
}();

// A style slot, the eyes' or the mouth's: the art drawn, an index into the
// pack's styles, and while it cross-fades to another, that one and how far
// toward it it is (0 … 1000).
struct Style {
  uint8_t index = 0, next = 0;
  int16_t mix = 0;
};

// A run of a table's rows.
template <class T>
struct List {
  const T* items = nullptr;
  uint8_t count = 0;
  constexpr const T* begin() const { return items; }
  constexpr const T* end() const { return items + count; }
  constexpr const T& operator[](int i) const { return items[i]; }
};

// A pose: a target for every channel (those the pack's file doesn't name
// at rest) and a style for the eyes and the mouth.
struct Expression {
  const char* mood;
  Channels values;
  uint8_t eyes, mouth;
};

// How a key is reached from the one before.
enum class Ease : uint8_t { kLinear, kIn, kOut, kInOut };
// How far along `t` of `ms` is, 0 … 1024, in the ease's shape; kInOut is
// render::ease's smoothstep.
int eased(Ease e, int t, int ms);
struct Key {
  uint16_t ms;
  int16_t value;
  Ease ease;
};
struct Track {
  Channel channel;
  List<Key> keys;  // in order of time
};
struct Cue {
  uint16_t ms;
  const char* name;  // a sound or a contact, which the face plays
};
// Keyframed curves on some channels, timed in ms, with cues. An additive
// clip's values are offsets on what's there; an absolute one's, values to
// blend toward.
struct Clip {
  const char* id;
  uint16_t ms;
  bool loop, additive;
  List<Track> tracks;
  List<Cue> cues;  // in order of time, each before ms
  // Its own time t ms after it started: wrapped when it loops, else held
  // at its end.
  constexpr uint32_t local(uint32_t t) const { return loop ? t % ms : t < ms ? t : ms; }
};
// A track's value at its clip's own time: its first key's before that key,
// its last's after the last.
int sample(const Track& track, uint32_t local);
// The cues a clip crosses from `from` to `to` ms after it started, in
// [from, to) and on every loop: up to `max` names into `out`, in order.
// How many.
int crossed(const Clip& clip, uint32_t from, uint32_t to, const char** out, int max);

// A look: the base clip it loops (none for nullptr), its scene (0 for none,
// else one more than its index in the rig's scenes), and whether the
// character dresses for the tags in it.
struct Look {
  SceneState state;
  const Clip* clip;
  uint8_t scene;
  bool dresses;
};
// Where on the body an accessory sits (layers.h's Anchors).
enum class Anchor : uint8_t { kCrown, kBrim, kHands, kEyes };
// What the face draws for an outfit (render::outfitFor), and where.
struct Accessory {
  Outfit outfit;
  Anchor anchor;
  const char* art;
};

// A pack's rig, as rig_tables.h has it (kRig). Each lookup is nullptr for
// one the pack doesn't have.
struct Rig {
  List<const char*> eyeStyles, mouthStyles, scenes;
  List<Expression> expressions;
  List<Clip> clips;
  List<Look> looks;
  List<Accessory> accessories;
  const Expression* expression(const char* mood) const;
  const Clip* clip(const char* id) const;
  const Look* look(SceneState state) const;
  const Accessory* accessory(Outfit outfit) const;
};

}  // namespace render::rig
