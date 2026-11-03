// The growth bar along the top: where its fill is, when it comes and goes, and
// a met wish's heart flying into it. It knows the XP and stage the Mac says, and
// whether the screen is another's; Behaviour tells it those.
#pragma once
#include <cstdint>

#include "render/face.h"

namespace app {

class GrowthBar {
 public:
  // It comes when the XP has moved kStep points or more from where it last
  // showed, or the stage changed: less isn't a change you could see, and a
  // busy agent earns a point every few calls.
  static constexpr int kStep = 5;
  // The Mac sends a stage reached a moment ahead of the `do` of the wish that
  // reached it, and the body mustn't start before the heart: at most this long.
  static constexpr uint32_t kStageWaitMs = 300;

  // A state's XP (-1 for a Mac that sends none: no bar) and the stage it was and
  // is. `hidden`: what it says now isn't a change to show.
  void heard(int xp, int wasStage, int nowStage, bool hidden, uint32_t t);
  // A wish met: the bar comes for its heart, and fills as it lands, whichever of
  // this and the state with the XP (`xp`, as last heard) it earned arrives
  // first, with the two close together: a `do` that waited in the queue finds the
  // bar and the body already moved, and its heart lands on them as they are.
  void heartComes(int xp, uint32_t t);
  // Clears it once it's gone, so its clock's differences can't wrap.
  void sweep(uint32_t t);
  render::GrowthShow show(int stage, bool hidden, uint32_t t) const;
  // A heart's on its way, or was, while the bar's up.
  bool heart() const { return heart_; }
  // A new stage's body waits: a heart hasn't landed, or the stage has just come.
  bool waits(uint32_t t) const {
    return (heart_ && int32_t(t - fillAt_) < 0) || (grew_ && t - grewAt_ < kStageWaitMs);
  }

 private:
  int fill(uint32_t t) const;
  int sinceOff(uint32_t t) const { return int32_t(t - offAt_); }

  int from_ = 0, to_ = -1, wrap_ = 0;
  uint32_t fillAt_ = 0, onAt_ = 0, offAt_ = 0, heartAt_ = 0, grewAt_ = 0;
  bool on_ = false, heart_ = false, grew_ = false;
};

}  // namespace app
