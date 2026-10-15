// The pixel face's sound effects: the
// animation bank's clips and each design's timeline, from assets/sfx.h.
// render/pixel/effect_track.h decides when each event plays.
#pragma once
#include <cstdint>

#include "voice/clips.h"
#include "voice/effects.h"

namespace render::pixel {

// The bank's 49 clips.
const voice::EffectClips& clips();

// When a design's events play: never, every loop, the design's first loop
// only, or its first loop and every `every`th after it, as the bank's player
// counts them.
enum class Policy : uint8_t { kSilent, kLoop, kEntry, kSparse };

// A design's timeline. `mood`, `state` and `variant` (from 0) number the
// designs as faces.h does (render/types.h, render/pixel/scene.h); a variation out
// of range takes the first, as the screen does, and anything else unknown
// is silent. A routine design's loops don't all sound alike: the bank's mix
// picks a few of its contacts afresh each loop, and sfx.h keeps its picks
// for kLoops loops, so loop n plays list n % kLoops.
struct Score {
  Policy policy = Policy::kSilent;
  int every = 1;             // sparse: the loops that sound are 0, every, 2 × every…
  bool duck = true;          // a line turns it down; never needs you's, the finish's or an error's
  uint16_t voiceMs = 0;      // its voice window's start: a line over the design starts no sooner
  int lists = 0, loop0 = 0;  // its loops' event lists (1, or kLoops), for events()
};
constexpr int kLoops = 8;
Score score(int mood, int state, int variant);
// The events of a design's loop `loop` (from 0), when that loop sounds:
// fxEvent(first) .. fxEvent(first + n - 1), by time.
struct Events {
  int first = 0, n = 0;
};
Events events(const Score& s, uint32_t loop);
voice::FxEvent fxEvent(int i);

}  // namespace render::pixel
