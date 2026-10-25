// The rig: the numbers a character is at any instant, the same set for
// every pack and every face, and a pack's data on them: its expressions,
// clips and looks, which characters/charactergen.py writes from the pack's
// rig/ into the staged rig_tables.h (characters/CHARACTER.md §15). A face
// turns the channels into pixels its own way, and reports where the body
// is (Anchors). Portable C++: the board, the native simulator and the
// WebAssembly one build it alike.
#pragma once
#include <cstdint>

#include "render/maths.h"
#include "render/tags.h"
#include "render/types.h"

namespace render::rig {

// The body's, the eyes' and the mouth's: those a clip or a finger moves.
enum class Channel : uint8_t {
  kSquash,
  kLean,
  kLift,
  kX,
  kReach,
  kMelt,
  kEyeOpenL,
  kEyeOpenR,
  kEyeSize,
  kGazeX,
  kGazeY,
  kMouthOpen,
  kCount
};
constexpr int kChannelCount = int(Channel::kCount);

// Each channel's name in a pack's rig/ files, its range and its value at
// rest, where a face draws its art as drawn. In thousandths, but for lift
// and x: px of the 320 × 240 canvas, lift up and x to the right, far
// enough to leave the screen. squash runs from tall (-1000) to flat;
// lean, the body's, from left to right; reach stretches the body's right
// side out (1000) or its left (-1000), pinching the other in; melt lets
// it down into a puddle (1000); eyeOpen from shut (0); gaze from left or
// up (-1000) to right or down; eyeSize around the art's own (1000). A
// face may draw only some: Pixel's draws neither x, reach nor melt.
// charactergen.py reads this table to check a pack's files.
struct ChannelInfo {
  const char* name;
  int16_t lo, hi, rest;
};
constexpr ChannelInfo kChannelInfo[kChannelCount] = {
    {"squash", -1000, 1000, 0},  {"lean", -1000, 1000, 0},    {"lift", -240, 240, 0},
    {"x", -400, 400, 0},         {"reach", -1000, 1000, 0},   {"melt", 0, 1000, 0},
    {"eyeOpenL", 0, 1000, 1000}, {"eyeOpenR", 0, 1000, 1000}, {"eyeSize", 500, 1500, 1000},
    {"gazeX", -1000, 1000, 0},   {"gazeY", -1000, 1000, 0},   {"mouthOpen", 0, 1000, 0}};
// The body's channels, whose springs are slower than the face's.
constexpr bool body(Channel c) { return c <= Channel::kMelt; }

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

// A style slot, the eyes' or the mouth's: the art drawn, the face's own
// number for it, and while it cross-fades to another, that one and how far
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

// What a mood wears: its eyes' and its mouth's styles, by name, which the
// face draws its own art for (the shapes no channel reaches).
struct Expression {
  const char* mood;
  const char* eyes;
  const char* mouth;
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
// A moment in a clip that the face sounds: the name of one of its sounds.
struct Cue {
  uint16_t ms;
  const char* name;
};
// Keyframed curves on some channels, timed in ms, with cues. An additive
// clip's values are offsets on what's there; an absolute one's, values to
// blend toward.
struct Clip {
  const char* id;
  uint16_t ms;
  bool loop, additive;
  List<Track> tracks;
  List<Cue> cues{};  // in order of time, each before ms
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

// A look's occasion: a clip it plays now and then while every tag it needs
// is on and the look has shown its wait (render::fits).
struct Occasion {
  const Clip* clip;
  uint32_t when;  // render/tags.h's bits
  uint16_t afterS;
};
// How often a look plays an occasion while some fit, on Pixel's face: at
// each chance it gives it (a pass of the look's loop, while no occasion of
// its plays), one of those that fit this many percent of the time, any one
// alike. The gel deals them its own way, with its pastimes.
constexpr int kOccasionPct = 67;
// A base clip a look loops in place of its own while its tier (one of
// render/tags.h's tier bits) is the last reached.
struct TierClip {
  const Clip* clip;
  uint32_t when;
};
// A look: the base clip it loops, nullptr for none, its occasions, and its
// tiers' base clips. Pixel's face loops its clip; the gel loops a tier's
// (its engine moves the body otherwise).
struct Look {
  SceneState state;
  const Clip* clip;
  List<Occasion> occasions;
  List<TierClip> tiers{};
  // The base clip of the last tier reached of those the look names, by
  // the tags on (render::reached sets every tier below), or nullptr.
  const Clip* tiered(uint32_t when) const;
  // How many of its occasions fit now; and the clip of the i-th of those.
  int fitting(uint32_t when, uint32_t lookMs) const;
  const Clip* fitting(uint32_t when, uint32_t lookMs, int i) const;
};

// A pack's rig, as rig_tables.h has it (kRig). Each lookup is nullptr for
// one the pack doesn't have.
struct Rig {
  List<Expression> expressions;
  List<Clip> clips;
  List<Look> looks;
  const Expression* expression(const char* mood) const;
  const Clip* clip(const char* id) const;
  const Look* look(SceneState state) const;
};

// How long what comes and goes takes to: a style's cross-fade, the lane's
// strip and a reaction's sign, a layer's content (render/rig/layers.h), a
// switch from one design to another.
constexpr uint32_t kFadeMs = 200;

// An opacity, 0 … 1000, easing to its target over kFadeMs from when it was
// retargeted: a cubic Hermite from the value and slope it had then, so it
// starts from rest, turns back smoothly and ends exactly (the gel's props'
// ramp). From rest it's render::ease's smoothstep.
class Ramp {
 public:
  void retarget(int to, uint32_t t);
  int value(uint32_t t) const { return at(t).value; }
  int target() const { return to_; }
  // When it was last retargeted: it's there kFadeMs later.
  uint32_t since() const { return start_; }

 private:
  Hermite at(uint32_t t) const;
  int from_ = 0, to_ = 0, tangent_ = 0;
  uint32_t start_ = 0;
};

// A point in the face's own units (the gel's sixteenths of a pixel).
struct Point {
  int x, y;
};
// Where the body is this frame: the top of its head; a ring a little lower,
// at its sides and the middle of its front, where a hat's brim sits; the
// middle of its front lower down, where it holds things; its eyes'
// middles; and, on a face with them, two rings low on the body, each its
// front half from its left side to its right in kRingPoints: where the pyjamas
// start (lap) and the bottom of the body's outline (hem).
struct Anchors {
  static constexpr int kRingPoints = 17;
  Point crown{}, brimL{}, brimF{}, brimR{}, handF{}, eyeL{}, eyeR{};
  Point lap[kRingPoints]{}, hem[kRingPoints]{};
};

}  // namespace render::rig
