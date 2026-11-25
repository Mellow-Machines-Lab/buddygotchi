#include "render/gel/low_sign.h"
#include "render/gel/hands.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

#include "render/font.h"
#include "render/gel/lane.h"
#include "render/gel/raster.h"
#include "render/maths.h"
#include "render/palette.h"
#include "render/screens.h"

namespace render::gel {
namespace {

constexpr int kPad = 16, kMarkWide = 18, kMarkGap = 10, kRim = 2, kRadius = 16, kCornerGap = 4;
// The rows between the lines, and from them to the card's rim, by the size;
// the fonts' cells have room of their own above and below.
constexpr int kLineStep = 27, kTallPad = 4;
constexpr int kHand = 10;  // the hands on its top corners, as a reaction's sign's
constexpr uint16_t kFill = rgb565(22, 20, 18);
// The XP chip: its pad round the words, its height, and the gap before it.
constexpr int kChipPad = 8, kChipTall = 28, kChipGap = 10;
// A medal's metal, and its rim a shade deeper.
constexpr uint16_t kMedal[3][2] = {{rgb565(242, 196, 86), rgb565(181, 122, 18)},
                                   {rgb565(207, 213, 220), rgb565(143, 152, 163)},
                                   {rgb565(211, 154, 106), rgb565(154, 98, 51)}};

// Where the card's top rests: its hands, a little above it, stay in the
// lane's rows.
int topOf(int height) { return height * kLaneTop / kHeight + kHand - 2; }

// A tick, a cross or three dots, 18 px wide, its left at x, its middle on cy.
void paintMark(Raster& r, LowSign::Mark mark, int x, int cy, uint16_t ink) {
  auto at = [&](int dx, int dy) { return Point{(x + dx) * 16, (cy + dy) * 16}; };
  switch (mark) {
    case LowSign::Mark::kTick: {
      const Point v[] = {at(2, 0), at(7, 5), at(16, -6)};
      r.stroke16(v, 3, 3 * 16, ink);
      break;
    }
    case LowSign::Mark::kCross: {
      const Point a[] = {at(3, -6), at(15, 6)}, b[] = {at(15, -6), at(3, 6)};
      r.stroke16(a, 2, 3 * 16, ink);
      r.stroke16(b, 2, 3 * 16, ink);
      break;
    }
    case LowSign::Mark::kDots:
      for (int i = 0; i < 3; ++i) r.disk16((x + 3 + 6 * i) * 16, cy * 16, 40, ink);
      break;
    case LowSign::Mark::kStar: {
      // Five points, 18 px across, its middle on the line's.
      // Each tenth of a turn clockwise from twelve o'clock, as sine and
      // minus cosine (Q12): the points out, the notches between them in.
      static constexpr int16_t kWay[10][2] = {{0, -4096},    {2408, -3314}, {3896, -1266}, {3896, 1266},
                                              {2408, 3314},  {0, 4096},     {-2408, 3314}, {-3896, 1266},
                                              {-3896, -1266}, {-2408, -3314}};
      Point v[10];
      for (int i = 0; i < 10; ++i) {
        const int reach = i % 2 ? 4 * 16 : 10 * 16;
        v[i] = {(x + 9) * 16 + 8 + reach * kWay[i][0] / 4096, (cy + 1) * 16 + 8 + reach * kWay[i][1] / 4096};
      }
      r.polygon16(v, 10, ink);
      break;
    }
    case LowSign::Mark::kRing:
      // Today's ring, full: a circle 18 px across, 4 px thick.
      r.disk16((x + 9) * 16 + 8, cy * 16 + 8, 9 * 16, ink);
      r.disk16((x + 9) * 16 + 8, cy * 16 + 8, 5 * 16, kFill);
      break;
    case LowSign::Mark::kGold:
    case LowSign::Mark::kSilver:
    case LowSign::Mark::kBronze: {
      // A medal: a disk of its metal with a deeper rim.
      const auto* metal = kMedal[int(mark) - int(LowSign::Mark::kGold)];
      r.disk16((x + 9) * 16 + 8, cy * 16 + 8, 10 * 16, metal[1]);
      r.disk16((x + 9) * 16 + 8, cy * 16 + 8, 8 * 16, metal[0]);
      break;
    }
    case LowSign::Mark::kNone: break;
  }
}

}  // namespace

int lowSignChip(int xp, char* out, int size) {
  if (xp <= 0 || size < 12) return 0;
  std::snprintf(out, size_t(size), "+%d XP", std::min(xp, 999));
  return glyphCount(out) * kLarge.w + 2 * kChipPad;
}

LowSignLayout lowSignLayout(int width, int height, int corner, const char* text, bool marked, bool oneLine, int chip) {
  LowSignLayout l;
  char folded[LowSignLayout::kLineBytes];
  foldText(text, kLowSignMostGlyphs, folded, sizeof folded);
  const int frame = 2 * kPad + (marked ? kMarkWide + kMarkGap : 0) + (chip ? chip + kChipGap : 0);
  const int top = topOf(height);
  // The card's bottom row sets how wide it may be, past the panel's corners.
  auto room = [&](int tall) {
    const int edge = Surface::insetOf(width, height, corner, top, top + tall, kRadius) + kCornerGap;
    return width - 2 * edge - frame;
  };
  const int tallSign = kSign.h + 2 * kTallPad, tallSmall = kLarge.h + 2 * kTallPad,
            tallTwo = kLarge.h + kLineStep + 2 * kTallPad;
  const int glyphs = glyphCount(folded);
  int tall;
  if (glyphs * kSign.w <= room(tallSign)) {
    l.large = true, l.lines = 1, tall = tallSign;
    std::strcpy(l.line[0], folded);
  } else if (glyphs * kLarge.w <= room(tallSmall)) {
    l.lines = 1, tall = tallSmall;
    std::strcpy(l.line[0], folded);
  } else if (oneLine) {
    // One line, cut where render::cutAt cuts it, ending "…".
    tall = tallSmall, l.lines = 1;
    const int most = room(tallSmall) / kLarge.w;
    const char* p = folded;
    int keep = cutAt(folded, most - 1), at = 0;
    for (int i = 0; i < keep && nextGlyph(p) >= 0; ++i) {
    }
    at = int(p - folded);
    std::memcpy(l.line[0], folded, size_t(at));
    std::memcpy(l.line[0] + at, "\xE2\x80\xA6", 4);
  } else {
    tall = tallTwo;
    l.lines = wrapText(folded, room(tallTwo) / kLarge.w, 2, l.line[0], LowSignLayout::kLineBytes);
  }
  const Font& f = l.large ? kSign : kLarge;
  int widest = 0;
  for (int i = 0; i < l.lines; ++i) widest = std::max(widest, glyphCount(l.line[i]) * f.w);
  l.w = frame + widest, l.h = tall;
  l.x = (width - l.w) / 2, l.y = top;
  return l;
}

int lowSignDrop(const LowSign& sign, int height) {
  const int most = height - topOf(height);
  int drop = 0;
  if (sign.ms < uint32_t(kLowSignRiseMs)) drop = most - most * ease(int(sign.ms), kLowSignRiseMs) / 1024;
  if (sign.leftMs >= 0 && sign.leftMs < kLowSignFallMs)
    drop = std::max(drop, most - most * ease(sign.leftMs, kLowSignFallMs) / 1024);
  return drop;
}

int lowSignStripAlpha(const LowSign& sign, int height) {
  const int most = height - topOf(height);
  return most > 0 ? std::max(0, 255 - 2 * 255 * (most - lowSignDrop(sign, height)) / most) : 0;
}

uint32_t lowSignKey(const LowSign& sign) {
  uint32_t h = 2166136261u;
  auto add = [&](const void* data, size_t n) {
    for (size_t i = 0; i < n; ++i) h = (h ^ static_cast<const uint8_t*>(data)[i]) * 16777619u;
  };
  if (sign.text) add(sign.text, std::strlen(sign.text));
  // The height doesn't matter here: any drop but 0 changes as it moves.
  const int numbers[] = {int(sign.mark), int(sign.ink), lowSignDrop(sign, kHeight * 16), int(sign.oneLine), sign.xp};
  add(numbers, sizeof numbers);
  return h ? h : 1;
}

void paintLowSign(Surface& s, const LowSign& sign) {
  if (!s.pixels || !sign.shows()) return;
  const bool marked = sign.mark != LowSign::Mark::kNone;
  char chip[12] = "";
  const int chipW = lowSignChip(sign.xp, chip, sizeof chip);
  const LowSignLayout l = lowSignLayout(s.width, s.height, s.corner, sign.text, marked, sign.oneLine, chipW);
  const Font& f = l.large ? kSign : kLarge;
  Raster r{s};
  r.limit = s.height;
  const int y = l.y + lowSignDrop(sign, s.height);
  r.round(l.x, y, l.w, l.h, kRadius, sign.ink);
  r.round(l.x + kRim, y + kRim, l.w - 2 * kRim, l.h - 2 * kRim, kRadius - kRim, kFill);
  int x = l.x + kPad;
  const int textTop = y + kTallPad;
  const int linesTall = f.h + (l.lines - 1) * kLineStep;
  if (marked) {
    paintMark(r, sign.mark, x, textTop + linesTall / 2, sign.ink);
    x += kMarkWide + kMarkGap;
  }
  for (int i = 0; i < l.lines; ++i) text(r, f, x, textTop + i * kLineStep, l.line[i], sign.ink);
  if (chipW) {
    // At its right end, on the middle of its lines: filled in its ink, the words dark.
    const int cx = l.x + l.w - kPad - chipW, cy = textTop + linesTall / 2 - kChipTall / 2;
    r.round(cx, cy, chipW, kChipTall, kChipTall / 2, sign.ink);
    text(r, kLarge, cx + kChipPad, cy + (kChipTall - kLarge.h) / 2, chip, kFill);
  }
  // Boop's hands on its top corners, holding it up.
  for (int side : {-1, 1})
    if (handsPlan().has(side, HandsAt::kLowSign))
      paintHand(r, holdingUp(side < 0 ? l.x + kRadius / 2 : l.x + l.w - kRadius / 2, y + 4, side, kHand));
}

}  // namespace render::gel
