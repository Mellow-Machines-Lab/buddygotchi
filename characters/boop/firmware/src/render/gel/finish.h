// The gel's finishes: what a successful task_complete plays, sized by the
// tier its turn reached (`turn`), or with none by how long it's held
// (`loops`).
//
// - Small, Little Win: the row's own takes (slime::kRecipes, with hiccups
//   for a fourth): a hop at the reveal, a little trophy over its head, a
//   ring of sparkles. Proud's second take holds up its bug beside it.
// - Medium: Little Win with confetti cannons from both corners.
// - Big, the mood's (bigFinish): Gold Rush (the screen floods gold, a
//   trophy lands on its head), Jelly Fireworks (star eyes, bursts over the
//   black), Mini-Boop Parade (it splits into five little ones and back) or
//   Proud Spotlight (a podium, a crown, its smug sway).
// - Biggest, Mega Boop: it puffs up until its face fills the screen, then
//   pops back in a splash of jelly drops and confetti.
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
enum class Finish : uint8_t { kLittle, kConfetti, kGoldRush, kFireworks, kMegaBoop, kParade, kSpotlight, kCount };
enum class FinishSize : uint8_t { kSmall, kMedium, kBig, kBiggest };
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
// minute), medium to kBigTier (5 minutes), big to kBiggestTier (10) and
// biggest from there. With no turn (render::kNoTurn: a finish that isn't
// a turn's, such as growing a stage), by the hold instead: once small,
// twice medium, three times big, four or more biggest. A sad mood's
// (`mood`, canonical) is small whatever else.
constexpr int kLongTier = 2, kBigTier = 4, kBiggestTier = 5;
FinishSize finishSize(int loops, int turn, int mood);
// The big finish for the reaction's mood (canonical): its first, or its
// second when the first played last (`last`), or the one the Mac asked for
// (`wanted`, from 1, among its two); a proud board (`boardMood`) takes the
// spotlight whatever the reaction's mood.
Finish bigFinish(int mood, int boardMood, int wanted, Finish last);
// The two big finishes a mood (canonical) takes turns between.
void bigFinishes(int mood, Finish out[2]);
// A finish's recipe: its length, its reveal (the fanfare, and where a
// `say` starts) and its landings.
const slime::Recipe& finishRecipe(Finish f);

// What a finish does to the body at `ageMs` into it, `revealMs` being its
// reveal's time: offsets in sixteenths of a pixel (up negative), its scale
// about where it stands, and squash and lean added to the pose's (Q12, as
// PaintControls'). `minis` > 0: the parade's little ones stand in for it.
struct FinishPose {
  int dx16 = 0, dy16 = 0, scale = 4096, squash = 0, lean = 0;
  bool starEyes = false;
  int minis = 0;
};
FinishPose finishPose(const Surface& s, Finish f, int ageMs, int revealMs);
// Where a finish scales the body about: the middle of where it stands.
Point finishAnchor(const Surface& s);
// The parade's little ones at `ageMs`, into `out` (at most kParadeMinis): their
// count.
constexpr int kParadeMinis = 5;
int finishMinis(const Surface& s, int ageMs, FinishPose* out);
// What's drawn behind the body (the flood and its rays, the spotlight, the
// fireworks), and over it (the trophy, the crown, the podium, confetti,
// sparkles, jelly drops, the star eyes, the words), at the body's anchors.
// `gift`: proud's bug beside its trophy.
void paintFinishBehind(Surface& s, Finish f, int ageMs, int revealMs);
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
constexpr bool drawsBehind(Finish f) { return f == Finish::kGoldRush || f == Finish::kSpotlight; }
// The rows from the top a finish covers whole at `ageMs` (Gold Rush's
// flood, once it reaches every corner above the lane): erasing them first
// would only be painted over.
int finishCovers(const Surface& s, Finish f, int ageMs);
// Whether a finish covers the screen, so the desk goes while it plays.
constexpr bool takesOver(Finish f) { return f != Finish::kLittle && f != Finish::kConfetti; }
}  // namespace render::gel
