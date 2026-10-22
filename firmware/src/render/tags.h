// The tags on now: what the Mac sends in `state.when` (the part of the
// day, the weekday, a holiday, a milestone day), and how busy the agents
// are, which the board reads from `state.busy` (busyTags). A
// design or a gag that carries tags fits only while every one of them is on
// (characters/CHARACTER.md §9). The Mac's list is the same, in the same
// order (app/BoopKit/Core/Occasions.swift), and facegen numbers a design's
// tags by it.
#pragma once
#include <cstdint>

namespace render {

constexpr int kTagCount = 19;
constexpr const char* kTagNames[kTagCount] = {
    "morning",    "day",  "evening",   "night",  "friday",      "weekend", "friday13", "newyear", "valentines", "piday",
    "aprilfools", "may4", "halloween", "winter", "programmers", "lunar",   "party",    "busy",    "frantic"};

// The tag's bit in a set of tags, or 0 for a name that isn't one.
uint32_t tagBit(const char* name);

// How busy the agents are, the board's own tags from `state.busy`: busy
// with this many sessions working, frantic with this many and more.
constexpr int kBusyFrom = 2, kFranticFrom = 4;
uint32_t busyTags(int working);
// The working looks' pace then, in percent: a face plays them this much
// quicker while the agents are busy, and quicker again when frantic.
constexpr int kBusyPace = 125, kFranticPace = 160;
inline int workPace(int working) { return working >= kFranticFrom ? kFranticPace : working >= kBusyFrom ? kBusyPace : 100; }

}  // namespace render
