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
  // A rig clip's eyes (applyRig): their size about their middles, Q12, and
  // how far up they look, in face units (how far across is in gaze).
  int eyeSize = 4096, gazeUp = 0;
  // Pressed under the agents' drawer (render/gel/drawer.h): the rows the
  // body fills at rest (restBodyTop, restBodyBottom) mapped onto
  // [squeezeTop, squeezeBottom), in px, and spread wider by `widen` (Q12);
  // a squeezeBottom of 0 is none.
  int squeezeTop = 0, squeezeBottom = 0, widen = 4096;
  // A finish's (render/gel/finish.h): the whole body scaled (Q12) about
  // (anchorX, anchorY) and moved by (offsetX, offsetY), in sixteenths of a
  // pixel, its face and anchors with it; and its eyes left undrawn, for
  // the finish's own.
  int scale = 4096, anchorX = 0, anchorY = 0, offsetX = 0, offsetY = 0;
  bool eyes = true;
};
// The rows the body fills at rest, laid out on the AMOLED's 410.
inline int restBodyTop(int height) { return height * 92 / 410; }
inline int restBodyBottom(int height) { return height * 322 / 410; }
// Where the body is this frame, from the same pose that draws it: the rig's
// anchors (render/rig/rig.h), in sixteenths of a pixel, which a layer
// (render/gel/layers.h) sits on, so it moves, squashes and leaves the screen
// with the body; the face art adds the eyes' middles. The brim's, the
// hands', the lap's and the hem's are on these rings of the mesh, from the
// top (0) down: the hem's is the lowest the camera sees at the front.
constexpr int kBrimRing = 6, kHandRing = 15, kLapRing = 14, kHemRing = 17;
struct PastimeShow;
// The body; the surface's clear first keeps what this frame covers again
// (Surface::clear), and the pastimes' scenery goes behind it
// (render/gel/pastimes.h), when given. Its anchors into `anchors`, when
// given.
void paint(Surface& surface, const PaintControls& controls, const Box* keep = nullptr, int keepCount = 0,
           uint32_t keepLane = 0, rig::Anchors* anchors = nullptr, const PastimeShow* scenery = nullptr);
// The body alone, over what the surface holds.
void paintBody(Surface& surface, const PaintControls& controls, rig::Anchors* anchors = nullptr);
// The dome on the canvas: canvas pixels a body unit at its middle.
constexpr int kPxPerUnit = 85;
// The rig's gazeX and gazeY at their whole (1000) move the eyes this far,
// in face units (Q12 of a body unit); its mouthOpen from kRigMouthOpen
// opens the gel's one open mouth.
constexpr int kRigGaze = 205, kRigMouthOpen = 300;
// The rig's channels (render/rig/), what its clips play on the gel, as
// offsets from rest on the controls the engine gives: the body's squash
// (the rig's tall is the gel's up), lean and lift (canvas px, kPxPerUnit a
// body unit, never into the floor: the whole dome rises), the lids, shut
// as far as the more shut eye, and the eyes' size and where they look.
// The gel draws no other channel yet but the mouth (paint). At rest, none
// moves.
void applyRig(PaintControls& c, const rig::Channels& rig);
class Engine;
// The body, the face art, what it wears and the air around it
// (render/gel/layers.h) as the layer stack shows them at t (whole in the
// engine's tags and state with none), the pastimes' kit it wears, then the
// props, with the rig's channels on the engine's controls, and the
// pastimes' scenery behind it all; a lane that shows `keepLane` is kept
// from this surface's last frame. Its anchors into `anchors`.
// Pressed under the agents' drawer (`squeeze`, render/gel/drawer.h), it
// draws flattened, and with its eyes squeezed shut it draws the body alone.
struct DrawerPose;
void paint(Surface&, const Engine&, bool mouthOpen = false, int dy = 0, uint32_t keepLane = 0,
           rig::Anchors* anchors = nullptr, const rig::Channels& rig = rig::kRest, const rig::Layers* layers = nullptr,
           uint32_t t = 0, const PastimeShow* pastimes = nullptr, const DrawerPose* squeeze = nullptr);
void paintArt(Surface&, const Engine&, const PaintControls&, bool mouthOpen, rig::Anchors* anchors = nullptr);
void paintProps(Surface&, const Engine&);
// The cards paintProps will fill opaque this frame, as boxes of the pixels
// it covers whole (at most Surface::kMaxKeep), for the clear to leave.
int opaqueCards(const Surface&, const Engine&, Box* out);
}  // namespace render::gel
