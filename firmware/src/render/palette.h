// The canvas palette: index → RGB565. Every colour on
// the screen comes from this one table: "Warm Terminal", black glass with
// grey text and one amber accent, plus the bring-up colours; the finish's
// sage and clay in its last two entries; and between, from kFaceColorBase,
// the face's own colours, which a face that draws the canvas writes in as
// it's made (useFaceColors): the pixel face's designs'.
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
constexpr Rgb kEyeRgb = {246, 244, 238};   // warm white: whose turn it was, a reply's dots
constexpr Rgb kAmberRgb = {255, 176, 0};   // the one accent: needs you, the bubble's text
constexpr Rgb kGreyRgb = {140, 132, 121};  // secondary text
constexpr Rgb kDimRgb = {74, 68, 62};      // faint text, dividers, rings, the bubble's box
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
// The first entry of the face's own colours, after the ramps.
constexpr int kFaceColorBase = kInkBase + kInkCount * kLevels;
// The finish's marks, flat, in the last two entries.
constexpr uint8_t kSage = 254, kClay = 255;

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
  p.c[kSage] = rgb565(kSageRgb), p.c[kClay] = rgb565(kClayRgb);
  return p;
}

// The palette in use: the engine's colours, and the face's once it has
// written them.
inline PaletteTable& palette() {
  static PaletteTable p = makePalette();
  return p;
}

// A face's own colours, `colors[1]` on (0 is the black field), into the
// entries from kFaceColorBase: colour i at kFaceColorBase + i - 1, as many
// as fit before the sage.
template <class Color>
void useFaceColors(const Color* colors, int count) {
  for (int i = 1; i < count && kFaceColorBase + i - 1 < kSage; ++i)
    palette().c[kFaceColorBase + i - 1] = rgb565(colors[i].r, colors[i].g, colors[i].b);
}

// The full 256-entry table as sent in a screenshot; unused entries are black.
inline uint16_t paletteAt(int index) { return index >= 0 && index < 256 ? palette().c[index] : 0; }

}  // namespace render
