// The gel's moves: rig clips of the pack's (rig/clips/) it plays as a pure
// function of what shows and how long, not on the face's mixer, so the
// board, the simulator and the Mac's mirror draw the same frame however
// often each draws, and an interrupted one resumes where it was.
//
// - An invite's pose, payoff, miss and late turn (render/face.h's
//   InviteShow): `invite-<pose>` as it comes up, then `invite-<pose>-wait`
//   looping while it waits; `invite-<payoff>` for the touch;
//   `invite-<pose>-miss` with none; `invite-<pose>-late` as a late touch
//   brings it back, then the payoff. A pose or payoff the pack has no clip
//   for doesn't move the body.
// - The knock, as something needs you (the needs-you scene's own time,
//   which a needs-you interrupted keeps): `knock`, a fist on the glass, twice,
//   then the climb, `knock-climb`, from slime::kKnockClimbAtMs (slimegen's
//   scenes.mjs `knock`: straight after the knock, or after a wait with
//   nobody come).
//
// A clip's cues are where something hits the glass: the hand on it most
// rings there and the body shakes a little. The needs-you scene sounds the
// knock's own (its recipe's contacts), the face the climb's as it crosses
// them (GelFace::showMove); an invite's payoff has its own sound
// (render/gel/invite.h's inviteSound), so its cues are hits alone.
#pragma once
#include <cstdint>

#include "render/face.h"
#include "render/gel/hands.h"
#include "render/rig/rig.h"
#include "render/surface.h"

namespace render::gel {

class Engine;

struct MoveShow {
  const rig::Clip* clip = nullptr;
  uint32_t ms = 0;  // its own time
  // Whose cues the face sounds itself (not the knock's: its scene's do).
  bool sounds = false;
  bool on() const { return clip != nullptr; }
};
// The move playing now, if any.
MoveShow currentMove(const Engine& e);
// An invite's now, if the pack has a clip for its pose or payoff there.
MoveShow inviteMove(const InviteShow& v);
// The move's channels over `c`: its clip's tracks at its time, added, and
// after a hit a small shake (addShake), unless `shake` is false.
void addMove(rig::Channels& c, const MoveShow& m, bool shake = true);
// After a hit, the small shake alone: the glass's, over the motion layer
// (render/gel/lively.h), so no spring softens it.
void addShake(rig::Channels& c, const MoveShow& m);
// How long since its last hit, ms, or -1 for none yet.
int sinceHit(const MoveShow& m);
// A hit's ring and its shake last this long; the shake is kShakePx canvas
// px at first.
constexpr int kHitMs = 340, kShakeMs = 260, kShakePx = 3;
// The ring of the last hit, round the hand on the glass most of `hands`.
void paintHits(Surface& s, const MoveShow& m, const Hand hands[2]);

}  // namespace render::gel
