// The tags on now: what the Mac sends in `state.when` (the part of the
// day, Friday, a holiday, a milestone day, every tier the agents'
// working stretch or their rest has reached,
// your hands at the Mac, `typing` or `reading`, the side of Boop the Mac is on, `macleft` or `macright`,
// the rest of you at the Mac: `scrolling`, `typingfast`, `music`, `scrollup`, `oncall`, `scrolldown` (the
// way you scroll, in the places of `video` and `copied`, no longer sent), `macup`, the screen above the
// board, and `speaking`, another app recording with no camera),
// and how busy the agents are, which the board reads from `state.busy`
// (busyTags). A design or a pastime that carries tags fits only while every
// one of them is on (characters/CHARACTER.md §9). The Mac sends only these,
// in this order (Tags.board, app/BoopKit/Core/Tags.swift), and a pack
// numbers its designs' tags by it. The Mac's tiers are three, a
// minute, 5 and 15: `tier4`, `tier5` and `hushed` are never sent, and stay
// so the others keep their bits. A new tag goes at the end, so no pack's
// numbering of the others moves.
#pragma once
#include <cstdint>

namespace render {

constexpr int kTagCount = 32;
constexpr const char* kTagNames[kTagCount] = {
    "morning",   "day",        "evening", "night",  "friday", "newyear", "valentines", "halloween",
    "winter",    "programmers", "lunar",  "party",  "busy",   "frantic", "tier1",      "tier2",
    "tier3",     "tier4",      "tier5",   "hushed", "typing", "reading", "macleft",    "macright",
    "scrolling", "typingfast", "music",   "scrollup", "oncall", "scrolldown", "macup",   "speaking"};
static_assert(kTagCount <= 32, "a set of tags is 32 bits");

// The tag's bit in a set of tags, or 0 for a name that isn't one.
uint32_t tagBit(const char* name);
// Whether the tag `name` is on in `when`.
inline bool hasTag(uint32_t when, const char* name) { return (when & tagBit(name)) != 0; }
// Whether a pastime fits: every tag it needs is on and its look has shown
// its wait, `afterS` seconds.
constexpr bool fits(uint32_t needs, uint16_t afterS, uint32_t when, uint32_t lookMs) {
  return (needs & ~when) == 0 && uint32_t(afterS) * 1000 <= lookMs;
}

// `when` with every tier below the one on (tier1 to tier5): the Mac sends
// only the last reached, and a design for tier2 shows from then on.
uint32_t reached(uint32_t when);
// A tag's place in kTagNames, -1 for none, at compile time.
constexpr int tagIndex(const char* name) {
  for (int i = 0; i < kTagCount; ++i) {
    const char *a = kTagNames[i], *b = name;
    while (*a && *a == *b) ++a, ++b;
    if (*a == *b) return i;
  }
  return -1;
}
static_assert(tagIndex("tier5") - tagIndex("tier1") == 4, "the tiers follow each other in order, as reached needs");

// How busy the agents are, the board's own tags from `state.busy`: busy
// with this many sessions working, frantic with this many and more.
constexpr int kBusyFrom = 2, kFranticFrom = 4;
uint32_t busyTags(int working);
// The working looks' pace then, in percent: a face plays them this much
// quicker while the agents are busy, and quicker again when frantic.
constexpr int kBusyPace = 125, kFranticPace = 160;
int workPace(int working);

}  // namespace render
