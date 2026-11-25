#pragma once
#include <cstddef>
#include "render/rig/layers.h"
#include "render/rig/rig.h"
#include "render/stream.h"
#include "render/surface.h"
namespace render {
struct CardShow;  // render/face.h
}
namespace render::gel {
// Q12 raster controls, fed by the deterministic engine.
struct PaintControls {
  int lean = 0, squash = 0, dent = 0, blink = 0, gaze = 0;
  int ripple = 0, lift = 0, roll = 0, forward = 0, grabX = 0, grabY = 0, dy = 0;
  int slide = 0;  // a gag's slide, and the rig's x: the whole dome, sideways
  // The rig's reach and melt (applyRig), Q12: one side stretched out, its
  // right for more than 0, and the other pinched in; and how far it has
  // melted down into a puddle, flatter and wider on the desk.
  int reach = 0, melt = 0;
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
  // pixel, its face and anchors with it.
  int scale = 4096, anchorX = 0, anchorY = 0, offsetX = 0, offsetY = 0;
  // The rig's turn (applyRig), Q12 of a whole turn, to its right for more
  // than 0: each point of the face art goes round the dome that far, so
  // the eye nearer its rim narrows on its own and goes behind it
  // (Projector::face), its outline and its light where they were.
  int turn = 0;
  // The face trailing the body (render/gel/lively.h's face rule): its art
  // drawn this far from where the body puts it, sixteenths of a panel px,
  // at the body's size.
  int faceDx16 = 0, faceDy16 = 0;
  // Up at the glass (the rig's glass, Q12): the whole body bigger about
  // where it stands (applyGlass), and where it touches the glass a pale
  // patch, `patch` its size (Q12 of kPatchPx), at patchX across its front
  // (Q12, -4096 its left rim) and patchY up it (Q12, 0 its foot).
  int glass = 0, patch = 0, patchX = 0, patchY = 0;
};
// The body at the glass whole is this much bigger (Q12): 1.15 at most, the
// one way anything comes up to the glass (a move's glass, an invite's turn
// away). A patch whole is kPatchPx across its middle, at the body's size.
constexpr int kGlassScale = 614, kPatchPx = 96;
// The glass's scale onto the controls, over a finish's, about where it
// stands.
void applyGlass(PaintControls& c, const Surface& s);
// The patch where the body touches the glass, over the body and under its
// face, by its anchors; its middle into `at`'s patch.
void paintPatch(Surface& s, const PaintControls& c, rig::Anchors& at);
// The canvas row the body stands on (restBodyBottom), and how far above it
// its eyes are.
constexpr int kDeskRow = 188, kEyesOverDesk = 50;
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
// (Surface::clear). Its anchors into `anchors`, when given.
void paint(Surface& surface, const PaintControls& controls, const Box* keep = nullptr, int keepCount = 0,
           uint32_t keepLane = 0, rig::Anchors* anchors = nullptr);
// The body's material, the texels it's drawn from, as linked: and a copy
// of them to read instead, made where they're quicker to read (on the
// AMOLED, PSRAM over flash: GelFace::readAssetsFrom), or none for these.
const void* materialTexels(size_t& bytes);
void readMaterialFrom(const void* copy);
// The body's colour, 0 to kBodyColors - 1, 0 the material as made: each
// other is the material turned in hue, saturation and brightness, once, into
// a copy of its own. With no room for the copy it stays as made.
constexpr int kBodyColors = 8;
void bodyColor(int index);
// The colour it's in now, as bodyColor last turned it: what else is the
// body's (its hands) takes it too.
int bodyColorIndex();
// One texel of the material, as colour `index` turns it. Pure, for tests.
uint16_t tinted(uint16_t texel, int index);
// The dome on the canvas: canvas pixels a body unit at its middle.
constexpr int kPxPerUnit = 85;
// The rig's gazeX and gazeY at their whole (1000) move the eyes this far,
// in face units (Q12 of a body unit); its mouthOpen from kRigMouthOpen
// opens the gel's one open mouth.
constexpr int kRigGaze = 205, kRigMouthOpen = 300;
// The rig's channels (render/rig/), what its clips play on the gel, as
// offsets from rest on the controls the engine gives: the body's squash
// (the rig's tall is the gel's up), lean, lift (canvas px, kPxPerUnit a
// body unit, never into the floor: the whole dome rises), x (canvas px,
// the whole dome sideways, off the screen if far enough), reach and melt,
// the lids, shut as far as the more shut eye, and the eyes' size and
// where they look; the glass and its patch; and the turn. The mouth is paint's, the
// hands render/gel/hands.h's. At rest, none moves.
void applyRig(PaintControls& c, const rig::Channels& rig);
class Engine;
// The body, the face art, the Zs beside it
// (render/gel/layers.h) as the layer stack shows them at t (whole in the
// engine's tags and state with none), then the props, their paws where the
// pastime playing puts them, with the rig's channels on the engine's controls; a lane that
// shows `keepLane` is kept
// from this surface's last frame. Its anchors into `anchors`.
// Pressed under the agents' drawer (`squeeze`, render/gel/drawer.h), it
// draws flattened, and with its eyes squeezed shut it draws the body alone.
struct DrawerPose;
// Ducking `duck` px (under the needs-you card), its
// crown comes down that far and its foot stays where it stands.
void paint(Surface&, const Engine&, bool mouthOpen = false, int dy = 0, uint32_t keepLane = 0,
           rig::Anchors* anchors = nullptr, const rig::Channels& rig = rig::kRest, const rig::Layers* layers = nullptr,
           uint32_t t = 0, const PastimeShow* pastimes = nullptr, const DrawerPose* squeeze = nullptr,
           int duck = 0, const Stream* stream = nullptr, uint32_t now = 0, const CardShow* held = nullptr);
void paintArt(Surface&, const Engine&, const PaintControls&, bool mouthOpen, rig::Anchors* anchors = nullptr);
// Turned, a path of the art is drawn whole while its outline faces the
// camera at least kFacingShown on average (Q12 of straight at it,
// Projector::face), fading to none at kFacingGone, round at the dome's rim.
constexpr int kFacingGone = 400, kFacingShown = 1000;
// How much of it shows at that (Q12).
int shownFacing(int facing);
// The most room a cross-fading group of the art has taken (kCrossingBytes).
extern int crossingPeak;
// The desk's paws are where a pastime puts them (render/gel/pastimes.h),
// typing with none.
struct Paws;
// The monitor shows what the work is (an icon each) and a failure or a
// timeout as it lands, by the work stream at `now`: none, by the look alone.
// While Boop holds an agent's card (`held`), the monitor's frame lights in
// that agent's lane colour: the card is the work's.
void paintProps(Surface&, const Engine&, const Paws* paws = nullptr, const Stream* stream = nullptr, uint32_t now = 0,
                const CardShow* held = nullptr);
// A paw types: before each of its key contacts in the recipe playing it
// lifts and comes back down over kTapMs, kTapLift thousandths of the
// surface's height at the top, landing on the contact (whose sound and
// dip it is). How far up the paw on `side` (-1 left, 1 right) is now.
constexpr int kTapMs = 180, kTapLift = 24;
struct Scenes;
int tapLift(const Scenes& scenes, int side);
// Between them it types on softly, without a sound: a tap every kTypeMs,
// the paws by turns, each lifting kTypeLift over kTapMs, at `ms` of the
// engine's clock.
// `brisk`, while you type and it types with you (GelFace::showAlong): a paw
// comes down every kBriskMs, swinging kBriskLift high over kBriskTapMs,
// clearly more than the soft typing but no bounce, and its key lights as it
// lands.
constexpr int kTypeMs = 340, kTypeLift = 12, kBriskMs = 300, kBriskLift = 30, kBriskTapMs = 280;
// `fast`, with you typing fast (the `typingfast` tag): a paw every kFastMs,
// as high, over kFastTapMs: quicker, not higher, the tap the same share of
// its beat, so the paws keep their place in it as the pace changes.
constexpr int kFastMs = 210, kFastTapMs = kFastMs * kBriskTapMs / kBriskMs;
// Typing with you, by where in its two beats it is (`phase`, 0 … 2000, a
// beat a thousand, which the face moves on by the time over the beat's
// length, GelFace::pawPhase): how far up the paw on `side` is. A change of
// pace changes how fast the phase moves, never where it is, so no paw snaps.
// A tap is kTapBeat of a beat (even, so its top lands on a whole phase).
constexpr int kBeat = 1000, kTapBeat = (kBriskTapMs * kBeat / kBriskMs + 1) / 2 * 2;
int briskLift(int phase, int side);
// Where each activity that isn't typing holds the paws (0 left, 1 right),
// in the thousandths paintProps draws them in: lifted, and moved right.
struct PawPose {
  int lift[2], dx[2];
};
constexpr PawPose kLookingPaws{{-14, -14}, {-96, -40}}, kRunningPaws{{40, 40}, {66, -30}},
    kWaitingPaws{{-8, -8}, {-10, 10}};
// A change of activity's pose takes this long (the rig's look, and so the
// body's lean; the paws' spring settles as fast).
constexpr uint32_t kPoseMs = 400;
int typeLift(uint32_t ms, int side, bool brisk = false);
// The cards paintProps will fill opaque this frame, as boxes of the pixels
// it covers whole (at most Surface::kMaxKeep), for the clear to leave.
int opaqueCards(const Surface&, const Engine&, Box* out);
}  // namespace render::gel
