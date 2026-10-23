#pragma once
#include "render/surface.h"
namespace render::gel {
// Q12 raster controls, fed by the deterministic engine.
struct PaintControls {
  int lean = 0, squash = 0, dent = 0, blink = 0, gaze = 0;
  int ripple = 0, lift = 0, roll = 0, forward = 0, grabX = 0, grabY = 0, dy = 0;
  int slide = 0;  // a gag's slide: the whole dome, sideways
};
// A point on the surface, in sixteenths of a pixel.
struct Spot {
  int x = 0, y = 0;
};
// Where the body is this frame, from the same pose that draws it: what
// a layer (render/gel/layers.h) sits on, so it moves, squashes and leaves
// the screen with the body. The dome's top (crown); a ring of it a little
// lower, its sides and its front's middle (where a hat's brim sits); a
// ring lower down, likewise (where it holds things); and the eyes'
// middles, which the face art adds.
struct Anchors {
  Spot crown;
  Spot brimL, brimF, brimR;
  Spot handL, handF, handR;
  Spot eyeL, eyeR;
};
// The mesh's rings the brim and the hands are on, from the top (0) down.
constexpr int kBrimRing = 6, kHandRing = 15;
// The body; the surface's clear first keeps what this frame covers again
// (Surface::clear). Its anchors into `anchors`, when given.
void paint(Surface& surface, const PaintControls& controls, const Box* keep = nullptr, int keepCount = 0,
           uint32_t keepLane = 0, Anchors* anchors = nullptr);
class Engine;
// The body, the face art, what it wears and the air around it
// (render/gel/layers.h), then the props; a lane that shows `keepLane` is
// kept from this surface's last frame. Its anchors into `anchors`.
void paint(Surface&, const Engine&, bool mouthOpen = false, int dy = 0, uint32_t keepLane = 0,
           Anchors* anchors = nullptr);
void paintArt(Surface&, const Engine&, const PaintControls&, bool mouthOpen, Anchors* anchors = nullptr);
void paintProps(Surface&, const Engine&);
// The cards paintProps will fill opaque this frame, as boxes of the pixels
// it covers whole (at most Surface::kMaxKeep), for the clear to leave.
int opaqueCards(const Surface&, const Engine&, Box* out);
}  // namespace render::gel
