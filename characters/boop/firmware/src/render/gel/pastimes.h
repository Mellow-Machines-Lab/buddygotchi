// What the gel does to pass the time: its pastimes, a little scene each,
// and the kit the tiers put out round it, so something new shows at every
// glance however long the agents work or you're away.
//
// A pastime is one of the pack's rig clips (rig/clips/, its body: a sip, a
// hop, a lean to look) and what the board draws with it, in time with it
// (the mug coming up to its mouth, the bubble it blows, the book it
// reads). Each is for one look: working, idle, needs you or asleep. A
// working or idle one needs a tier (render/tags.h, `tier1` from 30
// seconds to `tier5` from 10 minutes: the Mac's clock of the agents'
// working stretch or of their rest), and one while something needs you or
// asleep, a wait, the seconds its look has shown (the needs-you screen's
// from the request). The face deals them (GelFace) with the look's own
// occasions (the rig's looks.json, which both faces play), one at a time,
// a rest of kRestMinMs to kRestMaxMs between them, the newest tier's
// kNewestPct of the time and an older one's the rest, never the same twice
// in a row. A few are moves, the whole body going somewhere (reaching
// for its coffee, melting, a stretch break off the screen), rarer than the
// rest: never within kMoveGapMs of the last. While a pastime moves the
// desk's paws (Enter pressed, the hands up at its head, spread as it
// melts, away with it), they're where it puts them (pawsFor).
//
// The kit stays out while its tier lasts, fading in and out on the rig's
// fade: at work a mug on the desk (tier1; in the morning its coffee is in
// its hand instead, so neither the mug nor a sip or refill from it), a
// mug more stacked on it every kMugEveryMs from tier5, and headphones
// from tier3, the hat winning where it has one: put on where you can see
// it (kPhonesOn, the first pastime dealt once they're wanted), so they
// say it has settled in, and on from then while they're wanted; and in
// the zone (tier5) a few motes drifting up beside it, kMotes of them, each
// over kMoteMs. Idle, a plant that grows (tier3 to tier5). Behind the
// body: the plant. In front: everything else, at the body's anchors.
#pragma once
#include <cstdint>

#include "render/rig/rig.h"
#include "render/surface.h"
#include "render/types.h"

namespace render::gel {

class Engine;

enum class Pastime : uint8_t {
  kNone,
  // At work.
  kSip,
  kPeek,
  kHum,
  kDone,
  kPonder,
  kRead,
  kNod,
  kBop,
  kDrum,
  kSticky,
  kPhonesOn,
  kReach,
  kRefill,
  kSnack,
  kMelt,
  kStretch,
  // Idle.
  kLookAround,
  kHopeful,
  kHop,
  kBubble,
  kFly,
  kDoodle,
  kBook,
  kGame,
  kWater,
  kBrb,
  kTower,
  kDance,
  kPlane,
  kSnooze,
  kDream,
  kSnuggle,
  // While something needs you.
  kWave,
  kTap,
  kWatch,
  kDrowsy,
  // Asleep.
  kRollOver,
  kSheep,
  kSnoreBubble,
  kCount
};

// A pastime: the rig clip its body plays, the look it's for, the tier it
// needs (1 to 5, 0 for none), the wait, in seconds of its look, and
// whether it's a move.
struct PastimeInfo {
  Pastime id;
  const char* clip;
  SceneState look;
  uint8_t tier;
  uint16_t afterS;
  bool move = false;
};
constexpr int kPastimeCount = int(Pastime::kCount) - 1;
extern const PastimeInfo kPastimes[kPastimeCount];
const PastimeInfo& info(Pastime p);

// The replies to what you said (FaceContext::reply) that are a pastime's
// own: asked for while the look is idle or asleep, the face plays the
// pastime itself, at once, whatever its tier; at work, the reply's clip
// alone (rig/clips/reply-<name>.json). A nap is the snuggle under its
// blanket, a dance the dance.
struct ReplyPastime {
  const char* reply;
  Pastime pastime;
};
constexpr ReplyPastime kReplyPastimes[] = {{"nap", Pastime::kSnuggle}, {"dance", Pastime::kDance}};
// The pastime a reply asks for, kNone for one that asks for none.
Pastime pastimeFor(const char* reply);

// The rest between two, in ms of the device's clock, and how often the
// newest tier's are dealt while an older one's fit too, in percent.
constexpr uint32_t kRestMinMs = 4000, kRestMaxMs = 10000;
constexpr int kNewestPct = 60;
// A move starts at least this long after the last one did.
constexpr uint32_t kMoveGapMs = 90000;
// From tier5, a mug more on the desk's stack every this long, up to kMostMugs.
constexpr uint32_t kMugEveryMs = 10 * 60 * 1000;
constexpr int kMostMugs = 4;
// In the zone, this many motes beside it, each drifting up over this long.
constexpr int kMotes = 5;
constexpr uint32_t kMoteMs = 4500;
// Putting the headphones on: they come down from kPhonesDropPx above its
// ears, held by a hand at each, and are on kPhonesOnMs in. While it melts
// they're off its head (it has none to hold them): gone over kMeltOffMs
// from kMeltOffAt, back over kMeltOnMs by kMeltOnBy.
constexpr int kPhonesDropPx = 120;
constexpr uint32_t kPhonesOnMs = 1300;
constexpr int kMeltOffAt = 600, kMeltOffMs = 600, kMeltOnBy = 5400, kMeltOnMs = 500;

// While the headphones are on, a note floats up from each cup in turn: a
// pair every kTuneEveryMs, the right's kTuneGapMs after the left's, each
// up for kTuneNoteMs, then a rest; none while bopping, whose notes are its
// own.
constexpr uint32_t kTuneEveryMs = 3000, kTuneGapMs = 600, kTuneNoteMs = 1600;
// How far, in ms, the note from cup `side` (0 left, 1 right) is into its
// flight at the device's time `t`, or -1 while it's not out.
int tuneNoteAge(uint32_t t, int side);

// The tier `when` has reached (render/tags.h's tier1 to tier5), 0 for none.
int tierOf(uint32_t when);
// The tag bit of tier `n` (1 to 5).
uint32_t tierBit(int n);

// What the face shows of them at the device's time `t`, with the tags on:
// the pastime playing (or a look's occasion, with no drawing of its own)
// and how far in, at `fade` (0 … 255), and the kit, each at its opacity
// (0 … 255): the desk's mug and how many are stacked, the headphones, the
// zone's motes, and the plant and how far it has grown (1 to 3).
struct PastimeShow {
  Pastime playing = Pastime::kNone;
  uint32_t age = 0, ms = 1;
  int fade = 0;
  uint32_t t = 0, when = 0;
  int mug = 0, mugs = 1, headphones = 0, zone = 0, plant = 0, grown = 1;
  // How far above its ears the headphones are, in px: coming down while
  // they're put on.
  int drop = 0;
};
// Where a pastime puts the desk's paws, each (0 left, 1 right) in the
// thousandths of the surface paintProps draws them in: lifted, moved out
// and at an opacity (0 … 255). At rest, typing as they do.
struct Paws {
  int lift[2] = {0, 0}, dx[2] = {0, 0}, alpha[2] = {255, 255};
};
Paws pawsFor(const PastimeShow& show);

// The plant: drawn after the clear and before the body, so the body
// covers it.
void paintScenery(Surface& surface, const PastimeShow& show);
// Whether paintScenery draws anything: only then is the whole surface
// erased before the body (render/gel/painter.cpp), rather than a band at
// a time as the body draws.
bool showsScenery(const PastimeShow& show);
// The kit it wears, the headphones and their tune, after what it wears
// for the tags (render/gel/layers.h) and before the cards.
void paintWorn(Surface& surface, const PastimeShow& show, const rig::Anchors& at);
// In front: the desk's mugs and the zone's motes, then what the pastime
// playing holds, throws, blows or dreams, at the body's anchors.
void paintPastimes(Surface& surface, const PastimeShow& show, const rig::Anchors& at, const Engine& e);

}  // namespace render::gel
