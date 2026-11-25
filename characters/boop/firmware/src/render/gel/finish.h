// The gel's finishes: what a successful task_complete plays, sized by the
// tier its turn reached (`turn`), or with none by how long it's held
// (`loops`).
//
// - Small, Little Win: the row's own takes (slime::kRecipes, with hiccups
//   for a fourth): a hop at the reveal, a little trophy over its head, a
//   ring of sparkles. Proud's second take holds up its bug beside it.
// - Medium, Confetti: Little Win with confetti cannons from both corners.
// - Big, Gold Rush: the screen floods gold, and a trophy lands on its head.
//
// A finish a size above small plays once, whatever its loops. A failure
// never plays one: its row keeps its card.
#pragma once
#include <cstdint>
#include "render/gel/geometry.h"
#include "render/types.h"
#include "slime.h"
namespace render::gel {
class Engine;
enum class Finish : uint8_t { kLittle, kConfetti, kGoldRush, kCount };
enum class FinishSize : uint8_t { kSmall, kMedium, kBig };
// The success row's variations: Little Win's takes, then each finish after
// it, from kFinishBase (kConfetti's).
constexpr int kFinishBase = slime::kMaxTakes;
constexpr int kBigFinishes = int(Finish::kCount) - 1;
constexpr int finishVariant(Finish f) { return kFinishBase + int(f) - 1; }
constexpr bool isFinishVariant(int variant) { return variant >= kFinishBase && variant < kFinishBase + kBigFinishes; }
constexpr Finish finishOf(int variant) {
  return isFinishVariant(variant) ? Finish(variant - kFinishBase + 1) : Finish::kLittle;
}
// The size: by how long its turn ran (`turn`, the tier it reached), so
// the more work, the bigger the party: small short of kLongTier (a
// minute), medium to kBigTier (5 minutes) and big from there. With no turn
// (render::kNoTurn: a finish that isn't a turn's, such as a level
// reached), by the hold instead: once small, twice medium, three times or
// more big. A sad mood's (`mood`, canonical) is small whatever else.
constexpr int kLongTier = 1, kBigTier = 2;
FinishSize finishSize(int loops, int turn, int mood);
// A finish's recipe: its length, its reveal (the fanfare, and where a
// `say` starts) and its landings.
const slime::Recipe& finishRecipe(Finish f);

// What a finish does to the body at `ageMs` into it, `revealMs` being its
// reveal's time: offsets in sixteenths of a pixel (up negative), its scale
// about where it stands, and squash and lean added to the pose's (Q12, as
// PaintControls').
struct FinishPose {
  int dx16 = 0, dy16 = 0, scale = 4096, squash = 0, lean = 0;
};
FinishPose finishPose(const Surface& s, Finish f, int ageMs, int revealMs);
// Where a finish scales the body about: the middle of where it stands.
Point finishAnchor(const Surface& s);
// What's drawn behind the body (the flood and its rays), and over it (the
// trophy, confetti, sparkles), at the body's anchors.
// `gift`: proud's bug beside its trophy.
// At night, Gold Rush's flood is half as bright.
void paintFinishBehind(Surface& s, Finish f, int ageMs, int revealMs, bool night = false);
void paintFinishFront(Surface& s, Finish f, int ageMs, int revealMs, const rig::Anchors& at, int scale, bool gift);
// The finish playing, if one is: which, how far into it and its reveal's
// time (ms), and whether proud's bug comes too (Scenes::finishShow).
struct FinishShow {
  bool on = false;
  Finish finish = Finish::kLittle;
  int ageMs = 0, revealMs = 0;
  bool gift = false;
};
// Whether a finish draws behind the body (paintFinishBehind), so the
// frame is erased whole before it, not band by band with the body.
constexpr bool drawsBehind(Finish f) { return f == Finish::kGoldRush; }
// The rows from the top a finish covers whole at `ageMs` (Gold Rush's
// flood, once it reaches every corner above the lane): erasing them first
// would only be painted over.
int finishCovers(const Surface& s, Finish f, int ageMs);
// Whether a finish covers the screen, so the desk goes while it plays.
constexpr bool takesOver(Finish f) { return f != Finish::kLittle && f != Finish::kConfetti; }
}  // namespace render::gel
