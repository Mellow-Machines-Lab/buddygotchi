// The canvas palette: index → RGB565. Every colour on
// the screen comes from this one table: "Warm Terminal", black glass with
// grey text and one amber accent, plus the bring-up colours; the entries
// past the ramps are black.
//
// Anti-aliased edges (the text, and the strip's round icons) use ramps: 8 steps
// from black up to an ink colour. The table is computed with integer maths
// at compile time, so the board and the simulator agree.
#pragma once
#include <cstdint>

namespace render {

constexpr uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b) {
  return uint16_t(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3));
}

struct Rgb {
  uint8_t r, g, b;
};

// The Warm Terminal colours.
constexpr Rgb kGlass = {0, 0, 0};          // the backlit black
constexpr Rgb kEyeRgb = {246, 244, 238};   // warm white: whose turn it was, the voice's words, the numbers
// The one accent, and it means needs you only: its dot, its name, the
// drawer's row, and on the gel the card itself, filled, its words in
// kNeedsYouInkRgb on it. Gold celebrates (kGoldRgb); neither is ever the voice.
constexpr Rgb kAmberRgb = {255, 176, 0};
constexpr Rgb kNeedsYouInkRgb = {28, 20, 0};
constexpr Rgb kGreyRgb = {140, 132, 121};  // secondary text
constexpr Rgb kDimRgb = {74, 68, 62};      // faint text, dividers, rings, the bubble's box
// The gel's reading greys, warm: the narration and the strip's words, a
// line a person reads in grey; the drawer's grabber; the lane's rule.
constexpr Rgb kNarrationRgb = {173, 163, 150};
constexpr Rgb kGrabberRgb = {112, 104, 96};
constexpr Rgb kRuleRgb = {58, 54, 50};
// Celebration: today's ring full, a level, the trophy. A shape's colour, or
// a celebration's low sign's, never the voice's words.
constexpr Rgb kGoldRgb = {242, 196, 86};
// The finish's marks on the strip: a success's tick in sage, a failure's
// cross in clay, the Mac's own inks for them on dark (its Theme).
constexpr Rgb kSageRgb = {163, 204, 144};
constexpr Rgb kClayRgb = {240, 147, 132};

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
  return p;
}

// The palette in use.
inline PaletteTable& palette() {
  static PaletteTable p = makePalette();
  return p;
}

// The full 256-entry table as sent in a screenshot; unused entries are black.
inline uint16_t paletteAt(int index) { return index >= 0 && index < 256 ? palette().c[index] : 0; }

}  // namespace render
