// What the gel wears and holds over its body, drawn natively by coverage
// like the rest of the gel, at the anchors of the pose that drew the body
// (the rig's Anchors, render/gel/painter.h), so each follows the body as it
// moves, squashes and leaves the screen, and is cut off there with it.
//
// THE SCREEN'S RULE, part one: the face comes first, and nothing is put on
// the screen for a time of day, a season or a holiday. Nothing hangs in the
// sky behind it and nothing drifts through the air round it: no sun, moon
// or stars, no snow, confetti or hearts, no coffee. It wears no hat or
// shades for a special day, and no nightcap at night: the time of day shows
// as energy, on its lids and in its tempo (sleepyLids). Only these show:
//
// - beside it: Zs rising while it sleeps at night;
// - with you at the Mac (GelFace::showWithYou, Engine::With): typing
//   along's ticks; speaking's cupped hand and rings; headphones while music
//   plays, and notes rising from them in the groove; a page beside it while
//   it reads along; a small screen beside it while it watches, its light on
//   the body; a muted mic by its ear on a call. Each is for what you do at
//   the Mac, never for a day;
// - the sign a reaction holds up (its `sign`): a dark card held at its
//   front, under its mouth, with a little gel hand at either side, the words
//   on it, sliding up as the reaction starts and bobbing while it's held. It
//   rises to stand on it, so the card leaves its mouth clear (signHop).
//
// Part two, what a pastime may show, is in render/gel/pastimes.h; part
// three, where its eyes look, in render/gel/gaze.h; what shares the top
// band and the lane, in render/gel/lane.cpp.
//
// Each comes and goes through the rig's layer stack (render/rig/layers.h,
// the face's), so the Zs as it falls asleep fade over the rig's fade; the
// sign fades out at the opacity Behaviour gives it. At night its lids hang
// a little lower (sleepyLids).
#pragma once
#include "render/face.h"
#include "render/gel/painter.h"
#include "render/rig/layers.h"
#include "render/surface.h"
#include "render/tags.h"

namespace render::gel {

struct SignLayer {
  static constexpr int kPad = 20;                 // the words from the card's sides, clear of the hands
  static constexpr int kGap = 4;                  // the card's bottom over the lane, at the lowest
  static constexpr int kRisePx = 90, kBobPx = 3;  // its signLift
  static constexpr int kHand = 12;                // the radius of the hand gripping either side
  static constexpr int kMinWide = 120;            // the narrowest card, hands' middles to middles
  // The hands' outer edges from the panel's sides, and clear of its rounded
  // corners, at the nearest: a lean or a finish carrying the body sideways
  // carries the sign only as far.
  static constexpr int kEdge = 8;
  // How far it rises to stand on its sign: the card, which can't go into
  // the lane, would cover its mouth.
  static constexpr int kHopPx = 14;
};

// How far its lids hang while it's tired (Engine::energy, the Mac's: at
// night or after a long stretch of work) (Q12, as PaintControls::blink): 0
// otherwise, and on the sleeping face, whose eyes are shut anyway: easing
// out as the awake face squashes shut, and back as it wakes.
constexpr int kNightLids = 1100;
// How much bigger its eyes are while it's bright (Q12).
constexpr int kBrightEyes = 4420;
class Engine;
int sleepyLids(const Engine& e);

// What the layer stack's layers (render/rig/layers.h) show for the
// engine's tags and state now: beside it the Zs while it sleeps at night.
// The stack's other layers stay empty: the screen's rule, above.
enum : uint32_t { kZs = 1 };
struct Contents {
  uint32_t beside;
};
Contents layerContents(const Engine& e);
// The Zs, over the body and its face, under the props: what
// the stack shows at t, at its layers' opacities; with none, whole in what
// the engine's tags and state call for.
void paintLayers(Surface& surface, const Engine& e, const rig::Anchors& at, const rig::Layers* layers = nullptr,
                 uint32_t t = 0);
// The sign, at the body's front (its hands' ring), over everything but
// the lane.
void paintSign(Surface& surface, const SignShow& sign, const rig::Anchors& at, int hop = 0);
// How far the body rises for its sign now (SignLayer::kHopPx), easing up with
// the card and down as it fades.
int signHop(const SignShow& sign);
// The wish: a small thought bubble beside the head with its icon (a hand,
// a speech dot, a laptop); met, the icon pops into a heart with sparks; left,
// the bubble fades.
void paintWish(Surface& surface, const WishShow& wish, const rig::Anchors& at);

}  // namespace render::gel
