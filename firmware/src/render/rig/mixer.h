// Mixes what a character does into its channels, the same stack for every
// pack and face, bottom up:
//
// - the mood: its expression's values are the targets of a critically
//   damped spring on each channel, the face's quicker than the body's. A
//   new mood moves the targets and keeps each spring's velocity, so
//   nothing jumps;
// - the look's base clip, looping;
// - reactions: clips playing over it, a few at once, each with a weight
//   eased in over kFadeMs as it starts and out as it ends or is cut.
//   Additive clips add their offsets, absolute ones blend toward their
//   values by their weight, in the order they started;
// - input: an impulse, velocity added to a channel's spring.
//
// A style, the eyes' or the mouth's, cross-fades over kStyleMs to the
// mood's. Each frame: advance(dt), then channels(), the styles and the
// cues crossed. Deterministic, and nothing allocates.
#pragma once
#include <cstdint>

#include "render/rig/rig.h"

namespace render::rig {

class Mixer {
 public:
  static constexpr int kPlays = 6;           // clips at once, the looks' included
  static constexpr int kMaxCues = 8;         // the most one advance reports
  static constexpr uint32_t kFadeMs = 150;   // a clip's weight, in and out
  static constexpr uint32_t kStyleMs = 200;  // a style's cross-fade
  // The springs' frequencies, in radians a second.
  static constexpr int kBodyRate = 12, kFaceRate = 20;

  Mixer();
  // At rest in the expression, its styles whole, with the look's clip (none
  // for nullptr) playing already.
  void reset(const Expression& mood, const Clip* look);
  void setMood(const Expression& mood);
  // The look's loop. A new clip fades in over the old one, which fades out;
  // the same clip plays on.
  void setLook(const Clip* clip);
  // A reaction's clip, over everything playing. With kPlays playing, the
  // oldest reaction gives way, one fading out first.
  void play(const Clip& clip);
  // Fades out every reaction playing.
  void cut();
  // Velocity added to a channel's spring, in its units a second.
  void impulse(Channel channel, int velocity);
  void advance(uint32_t dt);

  const Channels& channels() const { return out_; }
  const Style& eyes() const { return eyes_.style; }
  const Style& mouth() const { return mouth_.style; }
  // The cues the clips playing crossed in the last advance, in order.
  int cueCount() const { return cueCount_; }
  const char* cue(int i) const { return cues_[i]; }

 private:
  struct Spring {
    int32_t x = 0, v = 0;  // 256ths of the channel's unit, and of it a second
  };
  struct Play {
    const Clip* clip = nullptr;
    uint32_t age = 0;          // its own time, wrapped when it loops
    uint32_t in = 0, out = 0;  // ms since it started fading in, and out
    int from = 0;              // its weight when cut
    bool base = false, cut = false;
  };
  struct Fader {
    Style style;
    uint8_t want = 0;
    uint32_t age = 0;
    void advance(uint32_t dt);
  };
  static int weight(const Play& p);
  void start(const Clip& clip, bool base);
  void fadeOut(Play& p);
  void mix();

  Spring springs_[kChannelCount];
  Channels targets_ = kRest, out_ = kRest;
  Fader eyes_, mouth_;
  Play plays_[kPlays];
  int playing_ = 0;
  const char* cues_[kMaxCues] = {};
  int cueCount_ = 0;
};

}  // namespace render::rig
