// The canvas palette: index → RGB565. Every colour on
// the screen comes from this one table: "Warm Terminal", black glass with
// grey text and one amber accent, plus the bring-up colours; then the
// animation bank's colours, flat, which faces.h lists.
//
// Anti-aliased edges (the text, and the strip's round icons) use ramps: 8 steps
// from black up to an ink colour. The table is computed with integer maths
// at compile time, so the board and the simulator agree.
#pragma once
#include <cstdint>

#include "faces.h"

namespace render {

constexpr uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b) {
  return uint16_t(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3));
}

struct Rgb {
  uint8_t r, g, b;
};

// The Warm Terminal colours.
constexpr Rgb kGlass = {0, 0, 0};          // the backlit black
constexpr Rgb kEyeRgb = {246, 244, 238};   // warm white: whose turn it was, the finish's mark
constexpr Rgb kAmberRgb = {255, 176, 0};   // the one accent: needs you, the bubble's text
constexpr Rgb kGreyRgb = {140, 132, 121};  // secondary text
constexpr Rgb kDimRgb = {74, 68, 62};      // faint text, dividers, rings, the bubble's box

// Fixed entries: the bring-up pattern's colours.
enum Color : uint8_t {
  kBlack = 0,
  kWhite,
  kRed,
  kGreen,
  kBlue,
  kAmber,
  kGrey,
  kFixedCount,
};

// Inks: colours drawn over black with an anti-aliased ramp.
enum Ink : uint8_t {
  kInkEye = 0,
  kInkAmber,
  kInkGrey,
  kInkDim,
  kInkCount,
};

constexpr int kLevels = 8;          // coverage 1..8 of 8; 0 is the background
constexpr int kInkBase = 16;        // ink i, level k at kInkBase + i * 8 + k - 1
// Black text on the needs-you screen's amber: a ramp from the amber down to
// black, level k at kOnAmberBase + k - 1, in the free entries before the
// ink ramps. Font drawing takes it as the ink kInkOnAmber.
constexpr int kOnAmberBase = 8;
constexpr int kInkOnAmber = 0x40;
static_assert(kOnAmberBase >= kFixedCount && kOnAmberBase + kLevels <= kInkBase, "the amber ramp fits before the inks");
constexpr int kPaletteUsed = kInkBase + kInkCount * kLevels;
static_assert(kPaletteUsed == faces::kSceneBase, "the scene colours start after the ramps");
static_assert(faces::kSceneBase + faces::kColorCount - 1 <= 256, "palette overflow");

// The index for ink `ink` at coverage `level` (0..8) over black.
constexpr uint8_t inkAt(int ink, int level) {
  return level <= 0 ? kBlack : uint8_t(kInkBase + ink * kLevels + (level > kLevels ? kLevels : level) - 1);
}
// The index for text in `ink` at coverage `level`: over black, or black
// over the needs-you screen's amber for kInkOnAmber.
constexpr uint8_t textAt(int ink, int level) {
  if (ink != kInkOnAmber) return inkAt(ink, level);
  return level <= 0 ? kAmber : uint8_t(kOnAmberBase + (level > kLevels ? kLevels : level) - 1);
}

constexpr Rgb mix(Rgb a, Rgb b, int num, int den) {
  return {uint8_t((a.r * (den - num) + b.r * num + den / 2) / den),
          uint8_t((a.g * (den - num) + b.g * num + den / 2) / den),
          uint8_t((a.b * (den - num) + b.b * num + den / 2) / den)};
}
constexpr uint16_t rgb565(Rgb c) { return rgb565(c.r, c.g, c.b); }

constexpr Rgb inkRgb(int ink) {
  if (ink == kInkEye) return kEyeRgb;
  if (ink == kInkAmber) return kAmberRgb;
  if (ink == kInkGrey) return kGreyRgb;
  return kDimRgb;
}

struct PaletteTable {
  uint16_t c[256];
};

constexpr PaletteTable makePalette() {
  PaletteTable p{};
  const Rgb fixed[kFixedCount] = {
      {0, 0, 0}, {255, 255, 255}, {255, 0, 0}, {0, 255, 0}, {0, 0, 255},
      kAmberRgb, {128, 128, 128},
  };
  for (int i = 0; i < kFixedCount; ++i) p.c[i] = rgb565(fixed[i]);
  for (int ink = 0; ink < kInkCount; ++ink) {
    for (int k = 1; k <= kLevels; ++k) p.c[inkAt(ink, k)] = rgb565(mix(kGlass, inkRgb(ink), k, kLevels));
  }
  for (int k = 1; k <= kLevels; ++k) p.c[textAt(kInkOnAmber, k)] = rgb565(mix(kAmberRgb, kGlass, k, kLevels));
  // The animation bank's colours, flat (render/scene.cpp), after the ramps.
  for (int i = 1; i < faces::kColorCount; ++i) {
    const faces::Color& c = faces::kColors[i];
    p.c[faces::kSceneBase + i - 1] = rgb565(c.r, c.g, c.b);
  }
  return p;
}

constexpr PaletteTable kPalette = makePalette();

// The full 256-entry table as sent in a screenshot; unused entries are black.
inline uint16_t paletteAt(int index) { return index >= 0 && index < 256 ? kPalette.c[index] : 0; }

}  // namespace render
