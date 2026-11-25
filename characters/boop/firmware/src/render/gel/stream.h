// The work stream on the gel (render/stream.h): the word that comes
// forward, flying from the desk's monitor at the body's anchors in front of
// it, with the stars and dizzy eyes of a failure as it lands. Drawn by
// coverage like the rest of the gel, at the device's time. The newest word
// itself is the strip's term (render/gel/lane.cpp), and the monitor's icon
// says the work (paintProps).
#pragma once
#include "render/rig/rig.h"
#include "render/screens.h"
#include "render/stream.h"
#include "render/surface.h"

namespace render::gel {

// The word forward and what it does, over the body and its props, aimed at
// `at`, the body's anchors this frame.
void paintStreamFront(Surface& surface, const Stream& stream, const rig::Anchors& at, uint32_t t);

}  // namespace render::gel
