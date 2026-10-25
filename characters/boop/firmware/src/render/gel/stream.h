// The work stream on the gel (render/stream.h): each lane's words falling
// behind the body from its agent's column, and the word that comes forward
// flying at the body's anchors in front of it, the stars, helmet, bubble,
// bits, hail and confetti of what it does as it lands, and the desk's
// monitor answering it. Drawn by coverage like the rest of the gel, at the
// device's time, so a word falls at the same speed however busy the engine.
#pragma once
#include "render/rig/rig.h"
#include "render/stream.h"
#include "render/surface.h"

namespace render::gel {

class Engine;
// The lanes' names along the top and their falling words: behind the body,
// drawn after the clear and before it.
void paintStreamBehind(Surface& surface, const Stream& stream, uint32_t t);
// The word forward and what it does, over the body and its props, aimed at
// `at`, the body's anchors this frame.
void paintStreamFront(Surface& surface, const Stream& stream, const rig::Anchors& at, const Engine& e, uint32_t t);

}  // namespace render::gel
