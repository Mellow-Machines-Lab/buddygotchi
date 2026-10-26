#include "render/tags.h"

#include <cstring>

namespace render {

uint32_t tagBit(const char* name) {
  if (!name) return 0;
  for (int i = 0; i < kTagCount; ++i)
    if (!std::strcmp(kTagNames[i], name)) return uint32_t(1) << i;
  return 0;
}

uint32_t reached(uint32_t when) {
  // tier1 to tier5 are five bits in a row: every one below the highest on.
  const uint32_t first = tagBit("tier1");
  for (uint32_t bit = tagBit("tier5"); bit > first; bit >>= 1)
    if (when & bit) return when | (bit - first);
  return when;
}

namespace {
// The rung of the ladder: 0 below busy, 1 busy, 2 frantic.
int rung(int working) { return working >= kFranticFrom ? 2 : working >= kBusyFrom ? 1 : 0; }
}  // namespace

uint32_t busyTags(int working) {
  static constexpr const char* kRungs[] = {nullptr, "busy", "frantic"};
  return tagBit(kRungs[rung(working)]);
}

int workPace(int working) {
  static constexpr int kPaces[] = {100, kBusyPace, kFranticPace};
  return kPaces[rung(working)];
}

Outfit outfitFor(uint32_t when) {
  auto on = [&](const char* tag) { return hasTag(when, tag); };
  if (on("halloween")) return Outfit::kWitchHat;
  if (on("party") || on("newyear") || on("lunar") || on("programmers")) return Outfit::kPartyHat;
  if (on("night")) return Outfit::kNightcap;
  if (on("winter")) return Outfit::kBobble;
  return Outfit::kNone;
}

Eyewear eyewearFor(uint32_t when) {
  if (hasTag(when, "reading")) return Eyewear::kGlasses;
  if (hasTag(when, "friday") && !hasTag(when, "night") && !hasTag(when, "morning")) return Eyewear::kShades;
  return Eyewear::kNone;
}

uint8_t airFor(uint32_t when) {
  return (hasTag(when, "winter") ? kSnow : 0) | (hasTag(when, "party") || hasTag(when, "newyear") ? kConfetti : 0) |
         (hasTag(when, "valentines") ? kHearts : 0);
}

}  // namespace render
