// The screen: the face, drawn as its mood design, and in the bottom lane
// the status strip, or the bubble while a `say` plays. The same drawing
// serves the face, needs-you and no-app screens; only what it shows differs.
// Pure drawing: the device core decides what to show and passes it in.
#pragma once
#include <cstdint>

#include "render/canvas.h"
#include "render/types.h"

namespace render {

// Screen bands on the 320×240 screen, in pixels. The animation bank's
// designs leave the bottom 48 px, the lane, for text: the strip sits in it,
// and the bubble takes the whole lane while a `say` plays, in the strip's
// place. The first pack's looks and its successes for the finish draw into
// the lane too; the bubble blanks it.
constexpr int kLaneTop = 192;   // the bottom lane: the bubble's
constexpr int kStripTop = 204;  // the status strip, the bottom 36 px

struct Strip {
  // While something needs you (amber; null when nothing does): who, the
  // oldest waiting session, and how many more are waiting. Its thread's
  // name shows in the project's place when there is one.
  const char* agent = nullptr;
  const char* project = "";
  const char* name = "";
  int more = 0;
  // While the brain's finish plays, whose turn it was (null for none),
  // after a tick for a success, a cross for a failure, or dots for a
  // reply. Needs you's names win: the finish doesn't play then.
  const char* doneAgent = nullptr;
  const char* doneThread = "";
  Outcome doneOutcome = Outcome::kNone;
  int busy = 0;     // sessions working (grey; hidden at zero)
  int idle = 0;     // sessions idle, waiting for your next prompt: a parcel each for BOOT (hidden at zero)
  int helpers = 0;  // helpers at work: a mini each, up to kMinis, then +N (hidden at zero)
  bool noApp = false;
  // How strongly the lane draws it, 0 … 1000: it fades in as it comes and
  // out as it goes (Behaviour::strip).
  int opacity = 1000;
  // Anything to show; with nothing, the strip is bare glass.
  bool shows() const { return agent || doneAgent || busy > 0 || idle > 0 || helpers > 0 || noApp; }
};

// How many helpers the strip draws as minis; more show as +N.
constexpr int kMinis = 4;

// The bubble, or else the strip, at its opacity: while it fades, the
// pixels of it an ordered dither draws (render/canvas.h's Dither).
void drawLane(Canvas& c, const char* bubble, const Strip& s);
void drawStrip(Canvas& c, const Strip& s);

}  // namespace render
