// Mixes what a character does into its channels, the same stack for every
// pack and face, bottom up:
//
// - rest: a critically damped spring on each channel, the face's quicker
//   than the body's, holding it at rest;
// - the look's base clip, looping;
// - reactions: clips playing over it, a few at once, each with a weight
//   eased in over kWeightMs (a quarter of a shorter clip, so a blink still
//   shuts) as it starts and out as it ends. Additive clips add their
//   offsets, absolute ones blend toward their values by their weight, in
//   the order they started;
// - input: an impulse, velocity added to a channel's spring, which settles
//   back.
//
// A style, the eyes' or the mouth's, cross-fades over kFadeMs to the one
// asked for. Each frame: advance(dt), then channels() and the styles.
// Deterministic, and nothing allocates.
#pragma once
#include <cstdint>

#include "render/rig/rig.h"

namespace render::rig {

class Mixer {
 public:
  static constexpr int kPlays = 6;            // clips at once, the looks' included
  static constexpr uint32_t kWeightMs = 150;  // a clip's weight, in and out
  // The springs' frequencies, in radians a second, and the step past which
  // they've settled, so a longer one sets them at rest.
  static constexpr int kBodyRate = 12, kFaceRate = 20;
  static constexpr uint32_t kSettledMs = 1000;

  Mixer();
  // At rest in these styles (the face's numbers for its art), whole, with
  // the look's clip (none for nullptr) playing already.
  void reset(uint8_t eyes, uint8_t mouth, const Clip* look);
  // The styles to cross-fade to.
  void setStyles(uint8_t eyes, uint8_t mouth);
  // The look's loop. A new clip fades in over the old one, which fades out;
  // the same clip plays on.
  void setLook(const Clip* clip);
  // A reaction's clip, over everything playing. With kPlays playing, the
  // oldest gives way, but the look's own clip.
  void play(const Clip& clip);
  // Each play of a reaction's clip fades out, as a look's old clip does.
  void stop(const Clip& clip);
  // Velocity added to a channel's spring, in its units a second.
  void impulse(Channel channel, int velocity);
  void advance(uint32_t dt);

  const Channels& channels() const { return out_; }
  const Style& eyes() const { return eyes_.style; }
  const Style& mouth() const { return mouth_.style; }

 private:
  struct Spring {
    int32_t x = 0, v = 0;  // 256ths of the channel's unit, and of it a second
  };
  struct Play {
    const Clip* clip = nullptr;
    uint32_t age = 0;          // its own time, wrapped when it loops
    uint32_t in = 0, out = 0;  // ms since it started fading in, and out
    int from = 0;              // its weight when it started fading out
    bool base = false, cut = false;
  };
  struct Fader {
    Style style;
    uint8_t want = 0;
    uint32_t age = 0;
    void advance(uint32_t dt);
  };
  static uint32_t fadeMs(const Clip& clip);
  static int weight(const Play& p);
  void start(const Clip& clip, bool base);
  void fadeOut(Play& p);
  void mix();

  Spring springs_[kChannelCount];
  Channels out_ = kRest;
  Fader eyes_, mouth_;
  Play plays_[kPlays];
  int playing_ = 0;
};

}  // namespace render::rig
