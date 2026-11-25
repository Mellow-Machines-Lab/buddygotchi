// The rig: the numbers a character is at any instant, the same set for
// every pack and every face, and a pack's data on them: its clips and
// looks, which characters/charactergen.py writes from the pack's
// rig/ into the staged rig_tables.h (characters/CHARACTER.md §15). A face
// turns the channels into pixels its own way, and reports where the body
// is (Anchors). Portable C++: the board, the native simulator and the
// WebAssembly one build it alike.
#pragma once
#include <algorithm>
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
  kGlass,
  kPatchX,
  kPatchY,
  kPatch,
  kHandLX,
  kHandLY,
  kHandLSize,
  kHandLShape,
  kHandLGlass,
  kHandRX,
  kHandRY,
  kHandRSize,
  kHandRShape,
  kHandRGlass,
  kTurn,
  kCount
};
constexpr int kChannelCount = int(Channel::kCount);

// Each channel's name in a pack's rig/ files, its range and its value at
// rest, where a face draws its art as drawn. In thousandths, but for lift,
// x and the hands' x and y: px of the 320 × 240 canvas, lift up and x to
// the right, far enough to leave the screen. squash runs from tall (-1000)
// to flat; lean, the body's, from left to right; reach stretches the
// body's right side out (1000) or its left (-1000), pinching the other in;
// melt lets it down into a puddle (1000); eyeOpen from shut (0); gaze from
// left or up (-1000) to right or down; eyeSize around the art's own (1000).
//
// The glass is the screen, a pane Boop lives behind. glass brings the
// whole body up to it (1000: as close as it comes); what of the body
// touches it shows a pale patch there, `patch` its size (0 for none), at
// patchX across the body's front (-1000 its left rim, 1000 its right) and
// patchY up it (0 its foot, 1000 its crown): a cheek, the forehead, the
// whole front.
//
// Two hands, left and right, each part of the body: hidden in it at rest
// (size 0), budding out as they grow, to x and y (px, y up) from the
// middle of the body's front low down, where it holds things (Anchors'
// handF); size in thousandths of a whole hand, as big again at 2000;
// shape a fist (-1000), a ball (0) or an open palm (1000), and between;
// and glass, how flat on the glass it's pressed (1000).
//
// turn: how far round the body has turned, in thousandths of a whole turn,
// to its right for more than 0: 250 a quarter, its face at its rim; 500
// its back to you; 1000 all the way round, a spin, as at rest. Only what's
// on the body's front moves round it; its outline stays. A face may draw
// only some: the gel draws them all.
// charactergen.py reads this table to check a pack's files.
struct ChannelInfo {
  const char* name;
  int16_t lo, hi, rest;
};
constexpr ChannelInfo kChannelInfo[kChannelCount] = {{"squash", -1000, 1000, 0},     {"lean", -1000, 1000, 0},
                                                     {"lift", -240, 240, 0},         {"x", -400, 400, 0},
                                                     {"reach", -1000, 1000, 0},      {"melt", 0, 1000, 0},
                                                     {"eyeOpenL", 0, 1000, 1000},    {"eyeOpenR", 0, 1000, 1000},
                                                     {"eyeSize", 500, 1500, 1000},   {"gazeX", -1000, 1000, 0},
                                                     {"gazeY", -1000, 1000, 0},      {"mouthOpen", 0, 1000, 0},
                                                     {"glass", 0, 1000, 0},          {"patchX", -1000, 1000, 0},
                                                     {"patchY", 0, 1000, 0},         {"patch", 0, 1000, 0},
                                                     {"handLX", -400, 400, 0},       {"handLY", -240, 240, 0},
                                                     {"handLSize", 0, 2000, 0},      {"handLShape", -1000, 1000, 0},
                                                     {"handLGlass", 0, 1000, 0},     {"handRX", -400, 400, 0},
                                                     {"handRY", -240, 240, 0},       {"handRSize", 0, 2000, 0},
                                                     {"handRShape", -1000, 1000, 0}, {"handRGlass", 0, 1000, 0},
                                                     {"turn", -2000, 2000, 0}};
// The body's channels, whose springs are slower than the face's.
constexpr bool body(Channel c) { return c <= Channel::kMelt; }
// The hands' channels: a hand's, `side` 0 the left and 1 the right, by
// its first (x) and how far past it (HandPart).
enum class HandPart : uint8_t { kX, kY, kSize, kShape, kGlass, kCount };
constexpr Channel hand(int side, HandPart part) {
  return Channel(int(Channel::kHandLX) + side * int(HandPart::kCount) + int(part));
}
static_assert(hand(1, HandPart::kGlass) == Channel::kHandRGlass && hand(0, HandPart::kShape) == Channel::kHandLShape,
              "each hand's channels in HandPart's order, the left's first");

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
// blend toward. A clip may be another's move at a size and a pace (its
// file's `of`): it shares that one's tracks and cues, their values times
// size / 1000 and their time, `own` ms long, played over its ms.
struct Clip {
  const char* id;
  uint16_t ms;
  bool loop, additive;
  List<Track> tracks;
  List<Cue> cues{};  // in order of time, each before ms (of `own`, for another's move)
  uint16_t size = 1000;
  uint16_t own = 0;  // its tracks' length, for another's move; 0 for its own, ms
  // Its own time t ms after it started: wrapped when it loops, else held
  // at its end.
  constexpr uint32_t local(uint32_t t) const { return loop ? t % ms : t < ms ? t : ms; }
  // The time in its tracks and cues at its own time `local`, and the other
  // way: when it reaches a time of theirs, `at` (the first ms at or after,
  // and before its end, so a cue near the end of a quicker move sounds).
  constexpr uint32_t keyed(uint32_t local) const { return own ? uint32_t(uint64_t(local) * own / ms) : local; }
  constexpr uint32_t played(uint32_t at) const {
    return own ? std::min<uint32_t>(uint32_t((uint64_t(at) * ms + own - 1) / own), ms - 1u) : at;
  }
  // A track's value at its own time `local`, at its size.
  int value(const Track& track, uint32_t local) const;
};
// A track's value at its clip's own time: its first key's before that key,
// its last's after the last.
int sample(const Track& track, uint32_t local);
// The cues a clip crosses from `from` to `to` ms after it started, in
// [from, to) and on every loop: up to `max` names into `out`, in order.
// How many.
int crossed(const Clip& clip, uint32_t from, uint32_t to, const char** out, int max);

// A base clip a look loops in place of its own while its tier (one of
// render/tags.h's tier bits) is the last reached.
struct TierClip {
  const Clip* clip;
  uint32_t when;
};
// A base clip a look loops in place of its own, and of any tier's, while
// the agents' activity is `act` (the state a `state`'s `act` names).
struct ActClip {
  const Clip* clip;
  SceneState act;
};
// A look: the base clip it loops, nullptr for none, its tiers' base clips
// and its activities'. The gel loops an activity's, else a tier's (its
// engine moves the body otherwise).
struct Look {
  SceneState state;
  const Clip* clip;
  List<TierClip> tiers{};
  List<ActClip> acts{};
  // The base clip of the last tier reached of those the look names, by
  // the tags on (render::reached sets every tier below), or nullptr.
  const Clip* tiered(uint32_t when) const;
  // The base clip of the activity `act`, or nullptr for one it doesn't name.
  const Clip* acted(SceneState act) const;
};

// A pack's rig, as rig_tables.h has it (kRig). Each lookup is nullptr for
// one the pack doesn't have.
struct Rig {
  List<Clip> clips;
  List<Look> looks;
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
// start (lap) and the bottom of the body's outline (hem); and the middle of
// the patch where it touches the glass, (0, 0) while none does.
struct Anchors {
  static constexpr int kRingPoints = 17;
  Point crown{}, brimL{}, brimF{}, brimR{}, handF{}, eyeL{}, eyeR{}, mouth{};
  Point lap[kRingPoints]{}, hem[kRingPoints]{};
  Point patch{};
};

}  // namespace render::rig
