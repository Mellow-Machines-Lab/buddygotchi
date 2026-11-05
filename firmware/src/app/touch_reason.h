// The board's own caption for a touch, which plays before the Mac or Jev hears
// of it: "you poked Boop". The same words as the Mac's narration, Touch.narration
// and Narration.of (a test holds the two to each other), so a reason the Mac
// sends a moment later is known for the same one (Behaviour::play). Pure C++.
#pragma once
#include <cstddef>

namespace app {

struct TouchReason {
  const char* gesture;  // render::gestureName's, or `lean`
  const char* fact;     // {name} where the buddy's name goes
};
inline constexpr TouchReason kTouchReasons[] = {
    {"stroke", "you stroked {name}"},
    {"lean", "you held {name}"},
    {"ruffle", "you ruffled {name}"},
    {"nose", "you booped {name}"},
    {"tickle", "you tickled {name}"},
    {"dizzy", "you shook {name}"},
    {"pickup", "you picked {name} up"},
    {"putdown", "you put {name} down"},
    {"startle", "a thump nearby"},
    {"peekaboo", "you flipped {name} up"},
};
// Each with the name, else with "it" when that won't fit a caption's
// `most` glyphs, as Narration.fit does. False for a gesture with none.
bool touchReason(const char* gesture, const char* name, int most, char* out, size_t n);
// A poke, by the run it's in and whether it woke Boop.
void pokeReason(int run, bool asleep, const char* name, int most, char* out, size_t n);

}  // namespace app
