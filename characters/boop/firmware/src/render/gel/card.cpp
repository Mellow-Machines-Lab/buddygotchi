#include "render/gel/card.h"
#include "render/gel/hands.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>

#include "render/font.h"
#include "render/gel/lane.h"
#include "render/gel/raster.h"
#include "render/maths.h"
#include "render/palette.h"
#include "render/show.h"
#include "render/stream.h"

namespace render::gel {

namespace {
constexpr uint16_t kCardInk = rgb565(16, 20, 24), kBarWords = rgb565(10, 30, 34), kCardRim = rgb565(0x78, 0xa4, 0xc8), kWords = rgb565(232, 242, 250),
                   kSmallWords = rgb565(143, 166, 184), kOver = rgb565(255, 122, 122), kDotOff = rgb565(58, 74, 90);
const Font& kMain = kSign;
const Font& kSmallFont = kLarge;

bool hasSmall(const CardShow& c) { return c.small && c.small[0]; }
// The agent's title bar, as a window's: its name in the large font on its
// lane's colour, so the card reads as the agent's and never as one of
// Boop's own round, glowing signs. None with no agent named.
bool hasBar(const CardShow& c) { return c.agent && c.agent[0]; }
// With a bar the words sit closer in, so the card isn't much taller and
// Boop needn't stand much higher on it.
constexpr int kBar = 24, kCorner = 5;
int pad(const CardShow& c) { return hasBar(c) ? 2 : 6; }
int dotsRow(const CardShow& c) { return c.count > 1 ? CardLayout::kDotsRow : 0; }
}  // namespace

// A picture's window: nearly the panel's width and about half its height,
// read from a chair (the engine's documentation/design/screen-guide.md,
// the map's 8).
constexpr int kPicW = 454, kPicH = 188;
constexpr uint16_t kGood = rgb565(0x5f, 0xae, 0x5a), kBad = rgb565(0xf0, 0x8a, 0x6c), kTrack = rgb565(42, 49, 56);

// A show's window: its headline's row, then the agent's picture at the
// board's own pixels, a margin round it.
constexpr int kShowMargin = 8, kHeadRow = 34;

int cardHeight(const CardShow& c) {
  if (c.pic == 's') return kBar + kHeadRow + CardShow::kShowH + kShowMargin;
  if (c.pic) return kPicH;
  return (hasBar(c) ? kBar : 0) + pad(c) + kMain.h + (hasSmall(c) ? kSmallFont.h : 0) + pad(c);
}

int cardHop(const CardShow& c) {
  if (!c.on) return 0;
  // Its mouth is this far over the lane at rest.
  constexpr int room = 62;
  const int needs = cardHeight(c) + dotsRow(c) + CardLayout::kGap + 8;
  const int in = int(std::min<uint32_t>(c.ms, CardLayout::kRiseMs)) * 1000 / int(CardLayout::kRiseMs);
  return std::max(0, needs - room) * ease1000(in, 1000) / 1000;
}

Box cardBox(const Surface& s, const CardShow& c) {
  const int h = cardHeight(c), bottom = s.height * 4 / 5 - CardLayout::kGap - dotsRow(c), y = bottom - h;
  if (c.pic) {
    const int wide = c.pic == 's' ? CardShow::kShowW + 2 * kShowMargin : kPicW;
    const int w = std::min(wide, s.width - 2 * (CardLayout::kEdge + CardLayout::kHand)), x = (s.width - w) / 2;
    return {x, y, x + w, y + h};
  }
  const int widest = std::max(stringWidth(kMain, c.text), hasSmall(c) ? stringWidth(kSmallFont, c.small) : 0);
  // (The bar's name is short, `claude` or `codex`: the main line is wider.)
  const int edge = s.inset(y, y + h) + CardLayout::kEdge + CardLayout::kHand;
  const int w = std::clamp(widest + 2 * CardLayout::kPad, CardLayout::kMinWide, s.width - 2 * edge);
  const int x = (s.width - w) / 2;
  return {x, y, x + w, y + h};
}

namespace {
// The plan: a block a step, those done filled, the one on outlined; its
// words for the step; and a ring for its guess of the minutes left.
void paintPlan(Raster& r, const CardShow& c, int x, int y, int w, uint16_t ink) {
  const int total = std::clamp(c.b, 1, 12), done = std::clamp(c.a, 0, total);
  const int ring = c.left != CardShow::kNoLeft ? 104 : 0, room = w - 36 - (ring ? ring + 16 : 0);
  const int gap = 6, bw = (room - gap * (total - 1)) / total;
  for (int i = 0; i < total; ++i) {
    const int bx = x + 18 + i * (bw + gap), by = y + 18;
    if (i < done)
      r.round(bx, by, bw, 22, 2, ink);
    else if (i == done)
      r.round(bx, by, bw, 22, 2, kTrack), r.ring(bx, by, bw, 22, 2, 3, ink);
    else
      r.round(bx, by, bw, 22, 2, kTrack);
  }
  // The step's words over where it is ("step 2 of 4"); with no words,
  // where it is alone, as the blocks already show what's done.
  char line[40];
  std::snprintf(line, sizeof line, "step %d of %d", std::min(done + 1, total), total);
  const bool named = c.step && *c.step;
  text(r, kMain, x + 18, y + 52, named ? c.step : line, kWords, room);
  if (named) text(r, kSmallFont, x + 18, y + 52 + kMain.h + 4, line, kSmallWords, room);
  if (ring) {
    const int cx = x + w - 18 - ring / 2, cy = y + 18 + ring / 2;
    r.disk(cx, cy, ring / 2, c.left < 0 ? kBad : ink);
    r.disk(cx, cy, ring / 2 - 9, kCardInk);
    std::snprintf(line, sizeof line, "%d", c.left < 0 ? -c.left : c.left);
    const int lw = stringWidth(kMain, line);
    text(r, kMain, cx - lw / 2, cy - kMain.h / 2 - 8, line, kWords, ring);
    const char* unit = c.left < 0 ? "over" : "min";
    text(r, kSmallFont, cx - stringWidth(kSmallFont, unit) / 2, cy + 10, unit, kSmallWords, ring);
  }
}

// A show: the agent's headline in the sign's font, then its picture, each
// run of a colour a row's span of pixels, the lane's colour its own; the
// headline alone until the picture has come.
void paintShow(Raster& r, const CardShow& c, int x, int y, int w, uint16_t lane) {
  const int room = w - 2 * 12;
  const int hw = std::min(stringWidth(kMain, c.headline), room);
  text(r, kMain, x + (w - hw) / 2, y + (kHeadRow - kMain.h) / 2 + 1, c.headline, kWords, room);
  if (!c.picture || !c.pictureBytes) return;
  const int px = x + (w - CardShow::kShowW) / 2, py = y + kHeadRow;
  forEachShowRun(c.picture, c.pictureBytes, CardShow::kShowW, CardShow::kShowH, [&](int rx, int ry, int n, int colour) {
    const uint16_t ink = colour == kShowLane ? lane : kShowInk[colour];
    for (int i = 0; i < n; ++i) r.pixel(px + rx + i, py + ry, ink);
  });
  r.touch(px, py, px + CardShow::kShowW, py + CardShow::kShowH);
}

// The changes: a row a file, its name, a green bar for lines added and a
// red one for lines removed, to one scale, and the numbers.
void paintChanges(Raster& r, const CardShow& c, int x, int y, int w) {
  int most = 1;
  for (int i = 0; i < c.rows; ++i) most = std::max(most, c.added[i] + c.removed[i]);
  const int name = 150, nums = 110, barRoom = w - 36 - name - nums;
  for (int i = 0; i < c.rows; ++i) {
    const int ry = y + 18 + i * 48, cy = ry + kLarge.h / 2;
    text(r, kLarge, x + 18, ry, c.file[i], kWords, name - 8);
    const int add = c.added[i] * barRoom / most, cut = c.removed[i] * barRoom / most;
    if (add) r.round(x + 18 + name, cy - 11, add, 22, 2, kGood);
    if (cut) r.round(x + 18 + name + add + (add ? 3 : 0), cy - 11, cut, 22, 2, kBad);
    char n[24];
    std::snprintf(n, sizeof n, "+%d -%d", c.added[i], c.removed[i]);
    text(r, kSmallFont, x + w - 18 - nums + 8, ry, n, kSmallWords, nums - 8);
  }
}

// The helpers: a lane each, a bar running while it works, full when done.
void paintHelpers(Raster& r, const CardShow& c, int x, int y, int w, uint16_t ink, uint32_t ms) {
  const int n = std::clamp(c.a + c.b, 1, 4);
  for (int i = 0; i < n; ++i) {
    const int ry = y + 18 + i * 38, track = w - 36 - 120;
    const bool done = i >= std::min(c.a, 4);
    char name[16];
    std::snprintf(name, sizeof name, "helper %d", i + 1);
    text(r, kLarge, x + 18, ry, name, kWords, 120);
    r.round(x + 18 + 120, ry + 4, track, 22, 2, done ? kGood : kTrack);
    if (!done) {
      const int run = track / 3, at = int(ms / 4 % uint32_t(track + run)) - run;
      const int x0 = std::max(0, at), x1 = std::min(track, at + run);
      if (x1 > x0) r.round(x + 18 + 120 + x0, ry + 4, x1 - x0, 22, 2, ink);
    }
  }
}
}  // namespace

void paintCard(Surface& s, const CardShow& c, int dx) {
  if (!s.pixels || !c.on) return;
  Raster r{s};
  const int in = int(std::min<uint32_t>(c.ms, CardLayout::kRiseMs)) * 1000 / int(CardLayout::kRiseMs);
  const int eased = ease1000(in, 1000);
  // Sliding in as you switch agents (switchDx): faded by how far off it is.
  r.fade = eased * 255 / 1000 * (2 * kSwitchPx - std::min(std::abs(dx), kSwitchPx)) / (2 * kSwitchPx);
  Box b = cardBox(s, c);
  b.x0 += dx, b.x1 += dx;
  const int down = CardLayout::kRisePx * (1000 - eased) / 1000, w = b.x1 - b.x0, h = b.y1 - b.y0;
  const int x = b.x0, y = b.y0 + down;
  const uint16_t rim = laneInkOr(c.slot, kCardRim);
  // A window's corners, square-ish, against the round signs Boop holds up.
  r.round(x, y, w, h, kCorner, kCardInk);
  const int bar = hasBar(c) ? kBar : 0;
  // The window's title bar in the agent's colour, and its three dots.
  const auto paintBar = [&] {
    r.round(x, y, w, kBar + kCorner, kCorner, rim);
    r.round(x, y + kBar, w, kCorner, 0, kCardInk);
    for (int i = 0; i < 3; ++i) r.disk(x + w - 16 - i * 11, y + kBar / 2, 3, kBarWords);
  };
  if (bar) {
    paintBar();
    const int room = w - 2 * CardLayout::kPad - 40;
    text(r, kSmallFont, x + 12, y + (bar - kSmallFont.h) / 2 + 1, c.agent, kBarWords, room);
  }
  r.ring(x, y, w, h, kCorner, 2, rim);
  if (c.pic) {
    // The bar says whose and which picture; the picture fills the rest.
    static const char* const kWhat[] = {"plan", "changes", "helpers", "show"};
    const char* what = kWhat[c.pic == 'p' ? 0 : c.pic == 'c' ? 1 : c.pic == 's' ? 3 : 2];
    char title[32];
    std::snprintf(title, sizeof title, "%s \xC2\xB7 %s", bar ? c.agent : "agent", what);
    if (!bar) paintBar();
    r.round(x + 6, y + 2, w - 60, kBar - 4, 0, rim);  // clear the bar's name
    text(r, kSmallFont, x + 12, y + (kBar - kSmallFont.h) / 2 + 1, title, kBarWords, w - 70);
    if (c.pic == 's') paintShow(r, c, x, y + kBar, w, rim);
    else if (c.pic == 'p') paintPlan(r, c, x, y + kBar, w, rim);
    else if (c.pic == 'c') paintChanges(r, c, x, y + kBar, w);
    else paintHelpers(r, c, x, y + kBar, w, rim, c.ms);
  }
  const int room = w - 2 * CardLayout::kPad;
  const int tw = std::min(stringWidth(kMain, c.text), room);
  if (!c.pic) text(r, kMain, x + (w - tw) / 2, y + bar + pad(c), c.text, kWords, room);
  if (hasSmall(c) && !c.pic) {
    const int sw = std::min(stringWidth(kSmallFont, c.small), room);
    text(r, kSmallFont, x + (w - sw) / 2, y + bar + pad(c) + kMain.h - 2, c.small, c.over ? kOver : kSmallWords, room);
  }
  // A hand at either side, gripping it.
  for (int side : {-1, 1})
    if (handsPlan().has(side, HandsAt::kCard))
      paintHand(r, gripping(side < 0 ? x : x + w, y + bar + (h - bar) / 2, side, CardLayout::kHand));
  // The dots: one for each card there is, this one lit in its colour.
  if (c.count > 1) {
    const int gap = 14, x0 = s.width / 2 - (c.count - 1) * gap / 2, dy = b.y1 + down + CardLayout::kDotsRow / 2;
    for (int i = 0; i < c.count; ++i) r.disk(x0 + i * gap, dy, CardLayout::kDot + (i + 1 == c.index), i + 1 == c.index ? rim : kDotOff);
  }
}

}  // namespace render::gel
