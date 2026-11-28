// Mixes what a character does into its channels, the same stack for every
// pack and face, bottom up:
//
// - rest: each channel's value at rest (kRest);
// - the look's base clip, looping;
// - reactions: clips playing over it, a few at once, each with a weight
//   eased in over kWeightMs (a quarter of a shorter clip, so a blink still
//   shuts) as it starts and out as it ends. Additive clips add their
//   offsets, absolute ones blend toward their values by their weight, in
//   the order they started.
//
// Each frame: advance(dt), then channels().
// Deterministic, and nothing allocates.
#pragma once
#include <cstdint>

#include "render/rig/rig.h"

namespace render::rig {

class Mixer {
 public:
  static constexpr int kPlays = 6;            // clips at once, the looks' included
  static constexpr uint32_t kWeightMs = 150;  // a clip's weight, in and out
  // At rest, with the look's clip (none for nullptr) playing already.
  void reset(const Clip* look);
  // The look's loop. A new clip fades in over the old one, which fades out,
  // each over `fadeMs` (a pose that moves the whole body wants longer than
  // kWeightMs); the same clip plays on.
  void setLook(const Clip* clip, uint32_t fadeMs = kWeightMs);
  // A reaction's clip, over everything playing. With kPlays playing, the
  // oldest gives way, but the look's own clip. Its weight comes and goes
  // over `fadeMs` (at most a quarter of the clip): a pose held over the
  // look wants longer than kWeightMs. A loop may start `from` ms into
  // itself, so one played again comes back in step with a beat that ran on.
  void play(const Clip& clip, uint32_t fadeMs = kWeightMs, uint32_t from = 0);
  // Each play of a reaction's clip fades out, as a look's old clip does.
  void stop(const Clip& clip);
  void advance(uint32_t dt);

  const Channels& channels() const { return out_; }

 private:
  struct Play {
    const Clip* clip = nullptr;
    uint32_t age = 0;          // its own time, wrapped when it loops
    uint32_t in = 0, out = 0;  // ms since it started fading in, and out
    int from = 0;              // its weight when it started fading out
    bool base = false, cut = false;
    uint32_t fade = kWeightMs;  // how long its weight takes, in and out
  };
  static uint32_t fadeMs(const Play& p);
  static int weight(const Play& p);
  void start(const Clip& clip, bool base, uint32_t fadeMs = kWeightMs, uint32_t from = 0);
  void fadeOut(Play& p);
  void mix();

  Channels out_ = kRest;
  Play plays_[kPlays];
  int playing_ = 0;
};

}  // namespace render::rig
