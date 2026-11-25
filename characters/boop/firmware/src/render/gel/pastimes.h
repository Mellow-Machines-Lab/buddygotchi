// What the gel does to pass the time: its pastimes, each a move of the
// body and nothing else, so something stirs at a glance however long the
// agents work or you're away.
//
// The pastimes are one table (kPastimes), a row each, and the face deals
// them all (GelFace), with dice of its own. A row's body is one of three:
// one of the pack's rig clips (rig/clips/: a stretch, a hop, a look
// around); a bit of the engine's (a yawn, a sneeze: slime::kGags, by
// name), which its acting plays in place of its next gesture; or a take of
// the engine's (a deeper snore, a dream:
// slime::kPastimeTakes, by name), which its scene plays as the look's next
// take. Each is for one look: working, idle or asleep; at work there is
// only the stretch (documentation/design/screen-guide.md in the engine,
// "Small details"). A working or idle one needs a tier (render/tags.h:
// `tier1` from a minute, `tier2` from 5, `tier3` from 15: the Mac's clock
// of the agents' working stretch or of their rest), and one asleep, a
// wait, the seconds its look has shown; a row that needs a tag (the night)
// needs no tier: it fits whenever its tag is on. They're dealt one
// at a time, a rest of kRestMinMs to kRestMaxMs between them, the newest
// kNewestPct of the time and an older one's the rest, never the same twice
// in a row: the newest are those of the highest tier, then the longest
// wait, and a row that needs a tag is newer than any while it fits. A row
// may be a move, the whole body going somewhere, rarer than the rest:
// never within kMoveGapMs of the last; none is now. A pastime that moves
// the desk's paws says where (pawsFor); none does now.
//
// THE SCREEN'S RULE, part two (part one is render/gel/layers.h): a pastime
// is the body's own. It brings nothing, holds nothing and leaves nothing:
// no headphones, mug, book or blanket, no note, heart, tick or thought
// cloud beside the face, and nothing on the monitor. The working screen is
// Boop, the desk, the falling words, the strip and, while a command worth
// naming runs, one low sign. The only things a pastime draws are sleep's:
// the Zs of a snooze and the bubble of a snore. They're dealt one at a
// time with a long rest between (kRestMinMs), never while a word of the
// work stream is forward or a finger is on it (GelFace::passTime), and
// none while something needs you: the amber screen is the message.
#pragma once
#include <cstdint>

#include "render/rig/rig.h"
#include "render/surface.h"
#include "render/types.h"

namespace render::gel {

enum class Pastime : uint8_t {
  kNone,
  // At work: only the stretch. The tempo at work is yours (typing along),
  // so Boop has no busier typing of its own.
  kStretch,
  // Idle.
  kLookAround,
  kHopeful,
  kHop,
  kYawn,
  kSneeze,
  kSnooze,
  // Asleep.
  kRollOver,
  kSnoreBubble,
  kDeepSnore,
  kDream,
  kCount
};

// What plays a pastime's body: a rig clip, an engine bit or an engine take.
enum class Body : uint8_t { kClip, kBit, kTake };
// A pastime: its body and that body's name, the look it's for, the tier it
// needs (1 to kTiers, 0 for none), the wait, in seconds of its look, the
// tag it needs (or none), and whether it's a move.
struct PastimeInfo {
  Pastime id;
  Body body;
  const char* name;
  SceneState look;
  uint8_t tier;
  uint16_t afterS;
  const char* tag = nullptr;
  bool move = false;
};
constexpr int kPastimeCount = int(Pastime::kCount) - 1;
extern const PastimeInfo kPastimes[kPastimeCount];
const PastimeInfo& info(Pastime p);
// A row's body in the pack: its rig clip, its bit (an index of
// slime::kGags) or its take (of slime::kPastimeTakes); none (nullptr or -1)
// for one of the other bodies, or one the pack hasn't got.
const rig::Clip* clipOf(const PastimeInfo& p);
int bitOf(const PastimeInfo& p);
int takeOf(const PastimeInfo& p);
// Whether the pack has a row's body, and the tag bits it needs any one of:
// each found once, by name, and kept.
bool hasBody(const PastimeInfo& p);
uint32_t tagsOf(const PastimeInfo& p);
// Whether a row fits now: its tier, wait and tag by the tags on and how
// long the look has shown.
bool fits(const PastimeInfo& p, uint32_t when, uint32_t lookMs);

// The rest between two, in ms of the device's clock, and how often the
// newest tier's are dealt while an older one's fit too, in percent.
constexpr uint32_t kRestMinMs = 20000, kRestMaxMs = 45000;
constexpr int kNewestPct = 60;
// A move starts at least this long after the last one did.
constexpr uint32_t kMoveGapMs = 300000;

// The tiers (render/tags.h's tier1 to tier3), the one `when` has reached
// (0 for none), and the tag bit of tier `n`.
constexpr int kTiers = 3;
int tierOf(uint32_t when);
uint32_t tierBit(int n);

// What the face shows of them at the device's time `t`: the pastime
// playing and how far in, at `fade` (0 … 255).
struct PastimeShow {
  Pastime playing = Pastime::kNone;
  uint32_t age = 0, ms = 1;
  int fade = 0;
  // Typing along with you (GelFace::showAlong): how far out its keyboard is
  // alone, idle (0 … 255), and whether its paws type with you now, there
  // or at its desk.
  int keys = 0;
  bool tapping = false;
  bool fast = false;  // and fast, with you typing fast
  int pawPhase = 0;   // where its paws are in their beats (briskLift)
};
// Where a pastime puts the desk's paws, each (0 left, 1 right) in the
// thousandths of the surface paintProps draws them in: lifted and moved
// out. At rest, typing as they do.
struct Paws {
  int lift[2] = {0, 0}, dx[2] = {0, 0};
  int melted = 0;  // how far it's melted, Q12 (PaintControls::melt): they fade with it, and the keyboard
  // With no desk out: its keyboard alone, this far out (0 … 255), as it
  // types along with you; and `tapping`, there or at its desk, its paws
  // typing briskly with you, `phase` where in their beats (briskLift).
  int keys = 0;
  bool tapping = false;
  int phase = 0;
};
Paws pawsFor(const PastimeShow& show);

// In front: a snooze's Zs and a snore's bubble, at the body's anchors.
void paintPastimes(Surface& surface, const PastimeShow& show, const rig::Anchors& at);

}  // namespace render::gel
