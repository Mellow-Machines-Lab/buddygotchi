// What Pixel wears and the air around it by the tags on, drawn over a
// look's design that isn't an occasion of its own: the same hats as its
// occasion art (characters/pixel/design/.../occasion-art.mjs), at the same
// place over the face, so the occasions keep their own art and the other
// variations of idle and asleep dress the same way. The working looks and
// the reactions draw their own props where a hat would go, so they stay as
// they are. Pure drawing, a function of the tags, the mood and the time.
#pragma once
#include <cstdint>

#include "render/canvas.h"
#include "render/types.h"

namespace render {

// Whether a design dresses up: idle or asleep, and not an occasion.
bool dresses(Mood m, SceneState s, int variant);
// What the overlay shows at `ms`, as a key that changes whenever its
// pixels do; 0 for nothing.
uint32_t outfitKey(uint32_t when, Mood m, uint32_t ms);
void drawOutfit(Canvas& c, uint32_t when, Mood m, uint32_t ms);

}  // namespace render
