// Today's ring, the bar along the top: where its fill is, when it comes and
// goes, a met wish's heart flying into it, and its sparkle when it's full. It
// knows the day's XP in percent, and whether the screen is another's;
// Behaviour tells it those.
#pragma once
#include <cstdint>

#include "render/face.h"

namespace app {

class GrowthBar {
 public:
  // It comes when the XP has moved kStep points or more from where it last
  // showed, or it's full: less isn't a change you could see, and a busy agent
  // earns a point every few calls. Less than before is a new day: it empties
  // without showing, and if it's up it slides out first, as it was. Full, it
  // sparkles once.
  static constexpr int kStep = 5;

  // A state's XP, today's percent (-1 for a Mac that sends none: no bar).
  // `hidden`: what it says now isn't a change to show.
  void heard(int xp, bool hidden, uint32_t t);
  // A wish met: the bar comes for its heart, unless today's ring was already
  // full, and fills as it lands, whichever of
  // this and the state with the XP (`xp`, as last heard) it earned arrives
  // first, with the two close together: a `do` that waited in the queue finds the
  // bar already moved, and its heart lands on it as it is.
  // Today's ring that was full before the state that came last, with the bar
  // gone, takes no heart: that state wasn't this wish's.
  void heartComes(int xp, uint32_t t);
  // Clears it once it's gone, so its clock's differences can't wrap; and,
  // with the screen Boop's again (not `hidden`), shows a ring that filled
  // while it couldn't: it fills and sparkles then.
  void sweep(bool hidden, uint32_t t);
  render::GrowthShow show(bool hidden, uint32_t t) const;
  // A heart's on its way, or was, while the bar's up.
  bool heart() const { return heart_; }

 private:
  // The full ring's sparkle: none, due at sparkleAt_ (or playing, or
  // played while the bar's up), or done for this fill to 100.
  enum class Sparkle : uint8_t { kNone, kDue, kDone };

  int fill(uint32_t t) const;
  int sinceOff(uint32_t t) const { return int32_t(t - offAt_); }
  bool up(uint32_t t) const { return on_ && !emptying_ && sinceOff(t) < int(render::GrowthShow::kOutMs); }
  // The fill reaches 100 at `at`: it sparkles then, unless it has begun to.
  void fullAt(uint32_t at, uint32_t t);
  // When it goes: once it's filled, held, and sparkled if it does.
  void holdOn();
  // Gone: off, at its fill.
  void settle();

  int from_ = 0, to_ = -1, owedFrom_ = 0;
  uint32_t fillAt_ = 0, onAt_ = 0, offAt_ = 0, heartAt_ = 0, sparkleAt_ = 0;
  bool on_ = false, heart_ = false;
  // Full before the state that came last; filled to 100 while hidden, not yet
  // shown (from owedFrom_); sliding out for a new day, at its old fill.
  bool wasFull_ = false, owed_ = false, emptying_ = false;
  Sparkle sparkle_ = Sparkle::kNone;
};

}  // namespace app
