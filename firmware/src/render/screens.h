// The screen's bottom lane: the status strip, or the bubble while a `say`
// plays, as the device core decides it and a face draws it (Face::draw).
#pragma once
#include <cstdint>

#include "render/canvas.h"
#include "render/types.h"

namespace render {

// Screen bands on the 320×240 screen, in pixels: the lane at the bottom,
// whose lower part is the strip; the bubble takes the whole lane while a
// `say` plays, in the strip's place.
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
  int helpers = 0;  // helpers at work (hidden at zero)
  // The working agent's to-do list, as "3/7" after the other counts
  // (hidden with no list).
  int todoDone = 0, todoTotal = 0;
  bool noApp = false;
  // Boop's wish, for a lane with no thought bubble: "pet", or null.
  const char* wish = nullptr;
  // How strongly the lane draws it, 0 … 1000: it fades in as it comes and
  // out as it goes (Behaviour::strip).
  int opacity = 1000;
  // Several agents (`state.pips`): a pip each on the strip's line, by its
  // kind ('w' working, 'c' holding a card, 'i' idle, 'a' wanting you) and
  // its lane's slot (-1 for none); which one the screen follows, and its
  // name for the chip at the strip's right; a pill of news from another,
  // by its pip ("api finished"). None with one agent.
  static constexpr int kPips = 6;
  int pipCount = 0;
  char pipKind[kPips] = {};
  int8_t pipSlot[kPips] = {};
  int watch = -1;
  const char* who = "";
  int pillAt = -1;
  const char* pill = "";
  // Anything to show; with nothing, the strip is bare glass.
  bool shows() const {
    return agent || doneAgent || busy > 0 || idle > 0 || helpers > 0 || todoTotal > 0 || noApp || pipCount > 1;
  }
};

}  // namespace render
