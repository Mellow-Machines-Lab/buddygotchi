#include "render/pixel/effect_track.h"

namespace render::pixel {

void EffectTrack::reset() { *this = EffectTrack{}; }

int EffectTrack::follow(const render::SceneShow* s, voice::FxEvent* out, bool& changed) {
  changed = false;
  if (!s) {
    changed = on_;
    on_ = false;
    return 0;
  }
  uint8_t variant = s->variant < render::variants(s->mood, s->state) ? s->variant : 0;  // as the screen draws it
  if (!on_ || s->mood != mood_ || s->state != state_ || variant != variant_ || s->t < lastT_) {
    // Another design, or the same one starting over: its timeline picks up
    // where its clock is, so a mood changing mid-loop doesn't replay what
    // the loop already passed.
    changed = on_;
    on_ = true;
    mood_ = s->mood, state_ = s->state, variant_ = variant;
    score_ = score(pixelIndex(mood_), int(state_), variant_);
    loopMs_ = render::loopMs(mood_, state_, variant_);
    if (loopMs_ == 0) loopMs_ = 1;
    covered_ = s->t;
    cycle_ = -1;
  }
  lastT_ = s->t;
  if (s->t > covered_ + kLateMs) covered_ = s->t;  // stalled: what's that late would only jar
  const uint64_t until = uint64_t(s->t) + kLeadMs;
  int n = 0;
  while (covered_ < until) {
    int64_t cycle = int64_t(covered_ / loopMs_);
    uint64_t start = uint64_t(cycle) * loopMs_;
    uint64_t end = start + loopMs_ < until ? start + loopMs_ : until;
    if (cycle != cycle_) {
      cycle_ = cycle;
      bool sounds = false;
      switch (score_.policy) {
        case Policy::kLoop: sounds = true; break;
        case Policy::kEntry: sounds = cycle == 0; break;
        case Policy::kSparse: sounds = score_.every <= 1 || cycle % score_.every == 0; break;
        case Policy::kSilent: break;
      }
      // A routine design's loops each sound a few of its contacts, the
      // bank's picks for loop cycle % kLoops, each on its own frame.
      list_ = sounds ? events(score_, uint32_t(cycle)) : Events{};
    }
    for (int i = 0; i < list_.n; ++i) {
      voice::FxEvent e = fxEvent(list_.first + i);
      e.duck = score_.duck;
      uint64_t at = start + e.atMs;
      if (at < covered_ || at >= end) continue;
      if (n < kMaxOut) out[n++] = e;  // more at once than that would only be noise
    }
    covered_ = end;
  }
  return n;
}

}  // namespace render::pixel
