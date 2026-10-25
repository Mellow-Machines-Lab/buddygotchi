// The work stream on the gel (render/stream.h): each lane's words falling
// behind the body from its agent's column, and the word that comes forward
// flying at the body's anchors in front of it, the stars, helmet, bubble,
// bits, hail and confetti of what it does as it lands, and the desk's
// monitor answering it. Drawn by coverage like the rest of the gel, at the
// device's time, so a word falls at the same speed however busy the engine.
#pragma once
#include "render/rig/rig.h"
#include "render/screens.h"
#include "render/stream.h"
#include "render/surface.h"

namespace render::gel {

class Engine;
// The lanes' falling words, each lane in its colour, behind the body:
// drawn after it, onto the background only, so the body, its props and
// what it wears cover them.
void paintStreamBehind(Surface& surface, const Stream& stream, uint32_t t);
// What the desk shows while they work: the to-do list's progress along the
// monitor's foot, the turn's clock in its corner (amber from tier4),
// and a thought cloud while no call has come for Stream::kThinkMs.
void paintStreamDesk(Surface& surface, const Stream& stream, const Engine& e, const Strip& strip, uint32_t t);
// The word forward and what it does, over the body and its props, aimed at
// `at`, the body's anchors this frame.
void paintStreamFront(Surface& surface, const Stream& stream, const rig::Anchors& at, const Engine& e, uint32_t t);

}  // namespace render::gel
