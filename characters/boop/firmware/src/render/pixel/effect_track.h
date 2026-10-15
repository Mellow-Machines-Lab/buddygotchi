// When the pixel face's sound effects play: each
// design has a timeline of events on its own clock (render/pixel/sounds.h), and this
// follows the face the screen shows, handing over each event as the
// design's clock reaches it. Pure C++ and a function of the device clock,
// like Behaviour, so a frozen clock gives the same events on the board and
// in the simulator. Device plays what it hands over.
#pragma once
#include <cstdint>

#include "render/pixel/scene.h"
#include "render/pixel/sounds.h"

namespace render::pixel {

class EffectTrack {
 public:
  // Events go out this far ahead of their frame: about what the DAC's DMA
  // holds, so the sound leaves the speaker with the frame.
  static constexpr uint32_t kLeadMs = 70;
  // An event this far behind the design's clock (a stalled loop) is dropped.
  static constexpr uint32_t kLateMs = 150;
  static constexpr int kMaxOut = 16;

  void reset();
  // Follows `s`, the face now, or silence when it's null (a test pattern).
  // Its `t` is the design's clock as Behaviour::designMs gives it, which
  // doesn't wrap: the timeline loops on its own, and its loops are counted
  // from the design's start. Fills `out` with the events now due, in order,
  // and returns how many. `changed` is true when the design changed or
  // started over: the last one's sounds stop before these play.
  int follow(const render::SceneShow* s, voice::FxEvent* out, bool& changed);
  // Whether a line turns down the events follow hands over: their
  // design's rule (Score::duck), which each event also carries.
  bool duck() const { return score_.duck; }

 private:
  bool on_ = false;  // following a design
  render::Mood mood_ = render::kStartupMood;
  render::SceneState state_ = render::SceneState::kIdle;
  uint8_t variant_ = 0;
  Score score_;
  uint32_t loopMs_ = 1;
  uint32_t lastT_ = 0;    // the design's clock last time
  // Events before this, on the design's clock, are handled. 64-bit, so a
  // loop's end past 2^32 ms (a design's clock near its wrap) can't wrap.
  uint64_t covered_ = 0;
  int64_t cycle_ = -1;    // the loop covered_ is in, and its events: none when it doesn't sound
  Events list_;
};

}  // namespace render::pixel
