// The low sign: a card Boop holds up in the strip's place, its words in two
// lines at most, the whole face clear above it. It holds a name too long
// for a reaction's sign (render/gel/layers.h), which crosses the lower face.
// It's the lane's to draw: it stays inside the lane's rows, so a frame whose
// sign hasn't moved keeps them and pushes nothing there.
// A function of the LowSign alone, so the board, the simulator and the Mac's
// mirror draw the same frame.
#pragma once
#include <cstdint>

#include "render/surface.h"

namespace render::gel {

struct LowSign {
  // kRing: today's ring, full; kGold to kBronze: a league's medal.
  enum class Mark : uint8_t { kNone, kTick, kCross, kDots, kStar, kRing, kGold, kSilver, kBronze };
  const char* text = nullptr;  // none: no sign
  Mark mark = Mark::kNone;     // before the words, in `ink`
  uint16_t ink = 0;            // its rim, its mark and its words
  uint32_t ms = 0;             // how long since it began to rise
  int32_t leftMs = -1;         // how long until it has fallen away, -1 for no end yet
  // One line at most, cut: under the rim's glow, a second line would run
  // into it at the panel's foot.
  bool oneLine = false;
  // The XP its moment earned, a chip at its right end, "+5 XP": filled in
  // `ink`, the words dark. 0 for none.
  int xp = 0;
  bool shows() const { return text && *text; }
};

// It rises over this long, and falls away over the last of its leftMs.
constexpr int kLowSignRiseMs = 280, kLowSignFallMs = 400;
// The most glyphs it holds, two lines of the small size; a longer text is cut
// as render::cutAt cuts it.
constexpr int kLowSignMostGlyphs = 50;

// How it lays out `text` on a surface: the font's size, its lines and the
// card, at rest. Pure, for the tests.
struct LowSignLayout {
  static constexpr int kLineBytes = 2 * kLowSignMostGlyphs + 1;
  bool large = false;  // the sign's font, for a short name; else the bubble's
  int lines = 0;
  char line[2][kLineBytes] = {};
  int x = 0, y = 0, w = 0, h = 0;
};
// `chip`: the XP chip's width, px, 0 for none (lowSignChipWidth).
LowSignLayout lowSignLayout(int width, int height, int corner, const char* text, bool marked, bool oneLine = false,
                            int chip = 0);
// The chip's words for `xp` ("+5 XP") into `out`, and its width in px; 0 for none.
int lowSignChip(int xp, char* out, int size);

// How far below its place it is now: 0 at rest.
int lowSignDrop(const LowSign& sign, int height);
// How much of the strip under it still shows, 255 (none of the sign up)
// to 0: gone by the time it's half way up, before its rim reaches the
// strip's words.
int lowSignStripAlpha(const LowSign& sign, int height);
// What it shows, as a key that's the same exactly when its pixels are, never 0.
uint32_t lowSignKey(const LowSign& sign);
// The sign, over whatever the lane drew.
void paintLowSign(Surface& surface, const LowSign& sign);

}  // namespace render::gel
