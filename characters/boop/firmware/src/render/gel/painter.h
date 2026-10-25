#pragma once
#include "render/rig/layers.h"
#include "render/rig/rig.h"
#include "render/surface.h"
namespace render::gel {
// Q12 raster controls, fed by the deterministic engine.
struct PaintControls {
  int lean = 0, squash = 0, dent = 0, blink = 0, gaze = 0;
  int ripple = 0, lift = 0, roll = 0, forward = 0, grabX = 0, grabY = 0, dy = 0;
  int slide = 0;  // a gag's slide: the whole dome, sideways
};
// Where the body is this frame, from the same pose that draws it: the rig's
// anchors (render/rig/rig.h), in sixteenths of a pixel, which a layer
// (render/gel/layers.h) sits on, so it moves, squashes and leaves the screen
// with the body; the face art adds the eyes' middles. The brim's, the
// hands', the lap's and the hem's are on these rings of the mesh, from the
// top (0) down: the hem's is the lowest the camera sees at the front.
constexpr int kBrimRing = 6, kHandRing = 15, kLapRing = 14, kHemRing = 17;
// The body; the surface's clear first keeps what this frame covers again
// (Surface::clear). Its anchors into `anchors`, when given.
void paint(Surface& surface, const PaintControls& controls, const Box* keep = nullptr, int keepCount = 0,
           uint32_t keepLane = 0, rig::Anchors* anchors = nullptr);
// The dome on the canvas: canvas pixels a body unit at its middle.
constexpr int kPxPerUnit = 85;
// The rig's channels (render/rig/), what its clips play on the gel, as
// offsets from rest on the controls the engine gives: the body's squash
// (the rig's tall is the gel's up), lean and lift (canvas px, kPxPerUnit a
// body unit, never into the floor), and the lids, shut as far as the more
// shut eye. The gel draws no other channel yet. At rest, none moves.
void applyRig(PaintControls& c, const rig::Channels& rig);
class Engine;
// The body, the face art, what it wears and the air around it
// (render/gel/layers.h) as the layer stack shows them at t (whole in the
// engine's tags and state with none), then the props, with the rig's
// channels on the engine's controls; a lane that shows `keepLane` is kept
// from this surface's last frame. Its anchors into `anchors`.
void paint(Surface&, const Engine&, bool mouthOpen = false, int dy = 0, uint32_t keepLane = 0,
           rig::Anchors* anchors = nullptr, const rig::Channels& rig = rig::kRest, const rig::Layers* layers = nullptr,
           uint32_t t = 0);
void paintArt(Surface&, const Engine&, const PaintControls&, bool mouthOpen, rig::Anchors* anchors = nullptr);
void paintProps(Surface&, const Engine&);
// The cards paintProps will fill opaque this frame, as boxes of the pixels
// it covers whole (at most Surface::kMaxKeep), for the clear to leave.
int opaqueCards(const Surface&, const Engine&, Box* out);
}  // namespace render::gel
