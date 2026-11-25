// The gel face's sound effects: slimegen's
// clips of the slime sound sketches, from assets/slime.h, three takes of
// each recipe named "<recipe>-<take>". The engine's contact cues pick them.
#pragma once
#include "voice/clips.h"

namespace render::gel {

const voice::EffectClips& clips();
// The clip for a cue's recipe and take (0–2); -1 if the bank has none.
int clipFor(const char* recipe, int take);

}  // namespace render::gel
