#include "render/pixel/outfit.h"

#include <cstring>

#include "faces.h"
#include "render/palette.h"
#include "render/pixel/scene.h"
#include "render/tags.h"

namespace render {

namespace {

// The bank's palette (visual/base.mjs), as the designs' colours.
uint8_t ink(uint8_t r, uint8_t g, uint8_t b) {
  for (int i = 1; i < faces::kColorCount; ++i)
    if (faces::kColors[i].r == r && faces::kColors[i].g == g && faces::kColors[i].b == b) return sceneInk(i);
  return sceneInk(1);
}
uint8_t white() { return ink(248, 247, 239); }
uint8_t blue() { return ink(113, 183, 245); }
uint8_t red() { return ink(255, 89, 108); }
uint8_t amber() { return ink(244, 188, 80); }
uint8_t gold() { return ink(255, 213, 74); }
uint8_t dark() { return ink(48, 35, 56); }
uint8_t cheek() { return ink(241, 120, 125); }

// The older moods' faces sit 6 px lower than the newer ones' (wake-art.mjs's lineUp).
int lineUp(Mood m) {
  static const char* const kOlder[] = {"happy", "excited", "proud", "curious", "determined", "grumpy", "sad"};
  for (const char* name : kOlder)
    if (!std::strcmp(moodName(m), name)) return 0;
  return -6;
}

// A rect with its corners cut, as the bank's `slab`.
void slab(Canvas& c, int x, int y, int w, int h, uint8_t color) {
  c.fillRect(x + 1, y, w - 2, h, color);
  c.fillRect(x, y + 1, w, h - 2, color);
}

// The step the air and the nightcap's pompom are on: one every 400 ms.
uint32_t phase(uint32_t ms) { return ms / 400; }

void nightcap(Canvas& c, int x, int y, int swing) {
  c.fillRect(x + 96, y + 40, 128, 10, white());
  c.fillRect(x + 104, y + 28, 116, 12, blue());
  c.fillRect(x + 118, y + 16, 96, 12, blue());
  c.fillRect(x + 140, y + 6, 68, 10, blue());
  c.fillRect(x + 200, y + 4, 22, 8, blue());
  c.fillRect(x + 218 + swing, y + 10, 10, 10, blue());
  slab(c, x + 222 + swing, y + 18, 16, 16, white());
}

void partyHat(Canvas& c, int x, int y) {
  c.fillRect(x + 152, y + 8, 16, 10, red());
  c.fillRect(x + 146, y + 18, 28, 10, amber());
  c.fillRect(x + 140, y + 28, 40, 10, red());
  c.fillRect(x + 134, y + 38, 52, 10, amber());
  c.fillRect(x + 128, y + 48, 64, 8, red());
  slab(c, x + 152, y - 6, 16, 16, gold());
}

void witchHat(Canvas& c, int x, int y) {
  c.fillRect(x + 150, y + 2, 20, 12, dark());
  c.fillRect(x + 140, y + 14, 40, 14, dark());
  c.fillRect(x + 128, y + 28, 64, 14, dark());
  c.fillRect(x + 124, y + 42, 72, 6, amber());
  c.fillRect(x + 96, y + 48, 128, 10, dark());
}

void bobble(Canvas& c, int x, int y) {
  c.fillRect(x + 100, y + 42, 120, 12, white());
  c.fillRect(x + 108, y + 24, 104, 18, red());
  c.fillRect(x + 124, y + 12, 72, 12, red());
  slab(c, x + 150, y - 2, 20, 18, white());
}

void snow(Canvas& c, uint32_t p) {
  static constexpr int kAt[][2] = {{24, 10},  {60, 40},  {110, 4},   {200, 30}, {250, 8},
                                   {292, 44}, {40, 120}, {280, 110}, {16, 70},  {300, 150}};
  for (const auto& f : kAt) c.fillRect(f[0], int((f[1] + p * 12) % 186), 4, 4, white());
}

void confetti(Canvas& c, uint32_t p) {
  static constexpr int kAt[][2] = {{30, 20}, {70, 52}, {262, 28}, {290, 64}, {48, 140}, {276, 128}};
  const uint8_t colors[] = {red(), amber(), blue(), gold()};
  for (int i = 0; i < 6; ++i) c.fillRect(kAt[i][0], int((kAt[i][1] + p * 14) % 170), 6, 6, colors[(i + p) % 4]);
}

void heart(Canvas& c, int x, int y, uint8_t color) {
  c.fillRect(x, y, 6, 6, color);
  c.fillRect(x + 10, y, 6, 6, color);
  c.fillRect(x - 2, y + 4, 20, 6, color);
  c.fillRect(x, y + 10, 16, 4, color);
  c.fillRect(x + 4, y + 14, 8, 4, color);
}

void hearts(Canvas& c, uint32_t p) {
  static constexpr int kAt[][2] = {{40, 140}, {260, 120}, {80, 40}, {230, 30}};
  for (int i = 0; i < 4; ++i) heart(c, kAt[i][0], int((kAt[i][1] + 180 - p * 16 % 180) % 180), i % 2 ? cheek() : red());
}

}  // namespace

bool dresses(Mood m, SceneState s, int variant) {
  return (s == SceneState::kIdle || s == SceneState::kAsleep) && !tagged(m, s, variant);
}

uint32_t outfitKey(uint32_t when, Mood m, uint32_t ms) {
  const Outfit o = outfitFor(when);
  const bool air = airFor(when) != kNoAir;
  if (o == Outfit::kNone && !air) return 0;
  const uint32_t moving = air || o == Outfit::kNightcap ? phase(ms) % 1000 : 0;
  return 1 + uint32_t(o) + 8 * uint32_t(lineUp(m) != 0) + 16 * moving;
}

void drawOutfit(Canvas& c, uint32_t when, Mood m, uint32_t ms, int dx, int dy) {
  const uint32_t p = phase(ms);
  const uint8_t air = airFor(when);
  if (air & kSnow) snow(c, p);
  if (air & kConfetti) confetti(c, p);
  if (air & kHearts) hearts(c, p);
  switch (outfitFor(when)) {
    case Outfit::kWitchHat: witchHat(c, dx, dy); break;
    case Outfit::kPartyHat: partyHat(c, dx, dy); break;
    case Outfit::kNightcap: nightcap(c, dx, dy + lineUp(m), p % 2 ? 4 : 0); break;
    case Outfit::kBobble: bobble(c, dx, dy); break;
    default: break;
  }
}

}  // namespace render
