#include "render/tags.h"

#include <cstring>

namespace render {

uint32_t tagBit(const char* name) {
  if (!name) return 0;
  for (int i = 0; i < kTagCount; ++i)
    if (!std::strcmp(kTagNames[i], name)) return uint32_t(1) << i;
  return 0;
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
  auto on = [&](const char* tag) { return (when & tagBit(tag)) != 0; };
  if (on("halloween")) return Outfit::kWitchHat;
  if (on("party") || on("newyear") || on("lunar") || on("programmers")) return Outfit::kPartyHat;
  if (on("night")) return Outfit::kNightcap;
  if (on("winter")) return Outfit::kBobble;
  return Outfit::kNone;
}

}  // namespace render
