#include "render/gel/lane.h"
#include "render/gel/done.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

#include "fonts_gel.h"
#include "render/gel/drawer.h"
#include "render/font.h"
#include "render/gel/layers.h"
#include "render/gel/painter.h"
#include "render/gel/pastimes.h"
#include "render/gel/profile.h"
#include "render/gel/raster.h"
#include "render/gel/stream.h"
#include "render/palette.h"

namespace render::gel {

namespace {

// The canvas's lane (render/screens.h) at the surface's size: the same
// rows, in proportion, and the same inks, at full strength.
struct Lane {
  Raster r;
  int w, h;
  int y(int canvasRow) const { return h * canvasRow / kHeight; }
};

uint16_t inkRgb565(int ink) { return paletteAt(inkAt(ink, kLevels)); }

constexpr int kMargin = 18;  // from the panel's edges, as the canvas's 12 px
constexpr int kIcon = 18;    // the strip's round icons, and the gap after them
// How far what's laid out by the panel's rounded corners keeps from them
// (Surface::inset), as their very edge may show dim.
constexpr int kCornerGap = 4;
constexpr int kBubbleMargin = 10;
constexpr int kBubblePad = 12;  // from the outline to the text, left and right
constexpr int kBubbleLine = 2;
constexpr int kBubbleRadius = 14;

// The bubble's rows, and how far in from either side it stands:
// kBubbleMargin, or clear of the panel's rounded corners, its own corners
// cut away like theirs. Its foot stands off the panel's, where the
// corners take the most.
struct BubbleBox {
  int top, bottom, margin;
  explicit BubbleBox(const Surface& s)
      : top(s.height * (kLaneTop + 4) / kHeight),
        bottom(s.height * (kHeight - 9) / kHeight),
        margin(std::max(kBubbleMargin, s.inset(top, bottom, kBubbleRadius) + kCornerGap)) {}
  int room(int width) const { return width - 2 * (margin + kBubblePad + kBubbleLine); }
};

// One glyph's 4-bit coverage, its cell's top left at (x, y).
void glyph(Raster& r, const Font& f, int x, int y, int g, uint16_t ink) {
  const int rowBytes = (f.w + 1) / 2, opacity = r.alpha;
  const uint8_t* src = f.data + size_t(g) * rowBytes * f.h;
  r.touch(x, y, x + f.w, y + f.h);
  for (int yy = 0; yy < f.h; ++yy)
    for (int xx = 0; xx < f.w; ++xx) {
      const int b = src[yy * rowBytes + xx / 2], coverage = xx & 1 ? b & 15 : b >> 4;
      if (!coverage) continue;
      r.alpha = opacity * coverage / 15;
      r.pixel(x + xx, y + yy, ink);
    }
  r.alpha = opacity;
}

}  // namespace

const Font& bubbleFont() { return kFontBubble; }

int text(Raster& r, const Font& f, int x, int y, const char* s, uint16_t ink, int room) {
  const int n = glyphCount(s);
  const bool fits = n * f.w <= room;
  for (int left = fits ? n : cutAt(s, room / f.w - 2), g; left > 0 && (g = nextGlyph(s)) >= 0; --left, x += f.w)
    glyph(r, f, x, y, g, ink);
  if (!fits)
    for (int i = 0; i < 2; ++i, x += f.w) glyph(r, f, x, y, '.' - 0x20, ink);
  return x;
}

void text16(Raster& r, const Font& f, int x16, int y16, const char* s, uint16_t ink, bool behind) {
  // On the stack, not the board's scarce internal heap: a word forward and
  // a combo's count, in the widest font (the bubble's, 20 px).
  constexpr int kMostGlyphs = 20, kMostCells = kMostGlyphs * 20 + 1;
  if (!r.s.pixels || r.alpha <= 2 || f.w * kMostGlyphs >= kMostCells) return;
  int glyphs[kMostGlyphs], n = 0;
  for (int g; n < kMostGlyphs && (g = nextGlyph(s)) >= 0;) glyphs[n++] = g;
  const int x0 = x16 >> 4, y0 = y16 >> 4, fx = x16 & 15, fy = y16 & 15;
  const int cells = n * f.w, rows = f.h + (fy ? 1 : 0), rowBytes = (f.w + 1) / 2;
  // What it may draw on: the surface, the raster's bounds, and above its
  // bottom (as Raster::pixel: the lane's top unless a limit is set).
  const int bottom = r.limit ? r.limit : r.s.height * 4 / 5;
  const int top = std::max(0, r.bounds.y0), under = std::min(bottom, r.bounds.y1);
  const int left = std::max(0, r.bounds.x0), right = std::min(r.s.width, r.bounds.x1);
  // Columns u of the string's cells drawn, and the cell before each.
  const int uFrom = std::max(0, left - x0), uTo = std::min(cells + (fx ? 1 : 0), right - x0);
  if (uFrom >= uTo) return;
  // A row of the string's cells (0–15) at index u + 1, a zero before them;
  // whether it has any.
  uint8_t rowA[kMostCells + 2] = {}, rowB[kMostCells + 2] = {};
  uint8_t *here = rowA, *above = rowB;
  bool hereInk = false, aboveInk = false;
  auto decode = [&](int v, uint8_t* out) {
    if (v < 0 || v >= f.h) return false;
    bool any = false;
    for (int i = 0; i < n; ++i) {
      const uint8_t* src = f.data + size_t(glyphs[i]) * rowBytes * f.h + v * rowBytes;
      uint8_t* o = out + 1 + i * f.w;
      for (int xx = 0; xx < f.w; xx += 2) {
        const uint8_t b = src[xx >> 1];
        any |= b != 0;
        o[xx] = b >> 4;
        if (xx + 1 < f.w) o[xx + 1] = b & 15;
      }
    }
    return any;
  };
  // An opacity from a sample's sum (at most 15 × 256), as Raster::text's
  // and Raster::pixel's: the shape's opacity, then the layer's fade.
  const int opacity = r.fade >= 255 ? r.alpha : r.alpha * r.fade / 255;
  // Behind, over black: the ink at each sixtieth of the most a sum can be.
  uint16_t shade[61];
  if (behind)
    for (int k = 0; k <= 60; ++k) shade[k] = mix565(0, ink, opacity * k / 60);
  const int wx = 16 - fx, wy = 16 - fy;
  int bx0 = 1 << 30, by0 = 1 << 30, bx1 = -1, by1 = -1;
  for (int v = 0; v < rows; ++v) {
    const bool stale = aboveInk;  // the row about to be written over had ink
    std::swap(here, above);
    aboveInk = hereInk;
    if (stale) std::fill(here, here + cells + 2, 0);
    hereInk = decode(v, here);
    const int y = y0 + v;
    if (y < top || y >= under || !(hereInk || (fy && aboveInk))) continue;
    uint16_t* row = r.s.pixels + y * r.s.width + x0;
    int lo = 1 << 30, hi = -1;
    for (int u = uFrom; u < uTo; ++u) {
      // The cells at u and u − 1 (index u + 1 and u), this row and the one
      // above, weighted by how near.
      const int sum = fx ? (wx * here[u + 1] + fx * here[u]) * wy + (wx * above[u + 1] + fx * above[u]) * fy
                         : (wy * here[u + 1] + fy * above[u + 1]) * 16;
      if (!sum) continue;
      uint16_t& out = row[u];
      if (behind) {
        if (out) continue;
        out = shade[sum / 64];
      } else {
        const int a = opacity * sum / (15 * 256);
        if (a >= 253)
          out = ink;
        else if (a > 2)
          out = mix565(out, ink, a);
        else
          continue;
      }
      lo = std::min(lo, u), hi = u;
    }
    if (hi < 0) continue;
    bx0 = std::min(bx0, x0 + lo), bx1 = std::max(bx1, x0 + hi), by0 = std::min(by0, y), by1 = y;
  }
  if (bx1 >= 0) r.touch(bx0, by0, bx1 + 1, by1 + 1);
}

namespace {

// The line in its bubble, which takes the whole lane: a box with round
// corners and a short tail up to the face, the text centred in the
// bubble's font, or the sign's, the large or the small one when it doesn't
// fit (on the AMOLED, the longest take, 22, fits the sign's; a line of 34,
// the small), cut to fit.
void bubble(Lane& l, const char* line) {
  const uint16_t dim = inkRgb565(kInkDim);
  const BubbleBox box(l.r.s);
  const int room = box.room(l.w);
  const Font* f = &kFontBubble;
  for (const Font* smaller : {&kSign, &kLarge, &kSmall})
    if (glyphCount(line) * f->w > room) f = smaller;
  const int tw = std::min(glyphCount(line) * f->w, room);
  const int bw = tw + 2 * (kBubblePad + kBubbleLine), left = (l.w - bw) / 2;
  const int top = box.top, bottom = box.bottom, cx = l.w / 2;
  l.r.ring(left, top, bw, bottom - top, kBubbleRadius, kBubbleLine, dim);
  const Point tail[] = {{cx - 9, top + kBubbleLine}, {cx + 9, top + kBubbleLine}, {cx, l.y(kLaneTop)}};
  l.r.polygon(tail, 3, dim);
  text(l.r, *f, (l.w - tw) / 2, (top + bottom) / 2 - f->h / 2, line, inkRgb565(kInkAmber), room);
}

// The strip's marks, each in a kIcon box with its middle at (x + 9, cy).
void dot(Raster& r, int x, int cy, uint16_t ink) { r.disk(x + 9, cy, 8, ink); }
// The working count's: a spinner of kSpinSteps spokes turning clockwise,
// the one on `spin` lit and the ones it passed fading behind it, as a
// computer shows it's busy.
void spinner(Raster& r, int x, int cy, int spin, uint16_t ink) {
  // Each spoke's way out from the middle, in sixteenths of a pixel per
  // pixel, clockwise from twelve o'clock.
  static constexpr Point kWay[kSpinSteps] = {{0, -16}, {11, -11}, {16, 0},  {11, 11},
                                             {0, 16},  {-11, 11}, {-16, 0}, {-11, -11}};
  const int cx16 = (x + 9) * 16 + 8, cy16 = cy * 16 + 8;
  for (int i = 0; i < kSpinSteps; ++i) {
    const int behind = (spin - i + kSpinSteps) % kSpinSteps;
    const Point spoke[] = {{cx16 + kWay[i].x * 4, cy16 + kWay[i].y * 4}, {cx16 + kWay[i].x * 8, cy16 + kWay[i].y * 8}};
    r.stroke16(spoke, 2, 40, mix565(0, ink, 255 - behind * 27));
  }
}
// The idle count's: a sleeper's z, and a smaller one rising after it.
void sleeper(Raster& r, int x, int cy, uint16_t ink) {
  r.zee((x + 1) * 16, (cy + 7) * 16, 12 * 16, ink);
  r.zee((x + 12) * 16, (cy - 2) * 16, 7 * 16, ink);
}
void tick(Raster& r, int x, int cy, uint16_t ink) {
  r.line({x + 2, cy}, {x + 7, cy + 5}, 3, ink);
  r.line({x + 7, cy + 5}, {x + 16, cy - 6}, 3, ink);
}
void cross(Raster& r, int x, int cy, uint16_t ink) {
  r.line({x + 3, cy - 6}, {x + 15, cy + 6}, 3, ink);
  r.line({x + 15, cy - 6}, {x + 3, cy + 6}, 3, ink);
}
void dots(Raster& r, int x, int cy, uint16_t ink) {
  for (int i = 0; i < 3; ++i) r.disk(x + 3 + 6 * i, cy + 5, 2, ink);
}
void plug(Raster& r, int x, int cy, uint16_t ink) {  // a plug on its cord, pointing at nothing
  r.round(x, cy - 2, 8, 4, 2, ink);                  // cord
  r.round(x + 7, cy - 9, 10, 18, 3, ink);            // body
  r.round(x + 17, cy - 6, 7, 3, 1, ink);             // prongs
  r.round(x + 17, cy + 3, 7, 3, 1, ink);
}

// The working and idle counts' chip, as the drawer's rows have theirs: a
// box with round corners outlined in `ring` round a mark and the number
// in `ink`.
// Its padding before the mark, and after the number (less, as a digit's
// cell has room either side of it), the gap between the two, and after
// it, before the next count: less than a mark's, as its outline parts
// them.
constexpr int kChipH = 36, kChipRadius = 9, kChipPad = 8, kChipEnd = 7, kChipGap = 4, kChipAfter = 12;

// The counts after the names: how many sessions work, by a spinner on
// `spin`, the helpers at work (a mini each, a little droplet of the gel
// with two eyes), the agents idle, by a sleeper's z, the two in chips, and
// last, as Pixel's strip has it, how far down its to-do list the longest
// turn with one is ("3/7"), from x, each with the gap after it. Drawn when
// r is given; either way, the x after them, so the names leave them the
// room they take.
int counts(Raster* r, const Strip& s, int x, int cy, int spin) {
  const Font& f = kSign;
  const int ty = cy - f.h / 2;
  const uint16_t grey = inkRgb565(kInkGrey), eye = inkRgb565(kInkEye);
  char n[24];
  auto number = [&](int at, uint16_t ink) { return r ? text(*r, f, at, ty, n, ink) : at + glyphCount(n) * f.w; };
  // The chip from x round its mark and count; the x after it, with the gap.
  auto chip = [&](int count, uint16_t ring, uint16_t ink, auto mark) {
    std::snprintf(n, sizeof(n), "%d", count);
    const int w = kChipPad + kIcon + kChipGap + glyphCount(n) * f.w + kChipEnd;
    if (r) {
      r->ring(x, cy - kChipH / 2, w, kChipH, kChipRadius, 2, ring);
      mark(x + kChipPad);
      number(x + kChipPad + kIcon + kChipGap, ink);
    }
    return x + w + kChipAfter;
  };
  if (s.busy > 0) x = chip(s.busy, kWorkingRing, kWorkingInk, [&](int at) { spinner(*r, at, cy, spin, kWorkingInk); });
  if (s.helpers > 0) {
    const int minis = std::min(s.helpers, kMinis), miniW = 20;
    const uint16_t gel = 0x75BE, ink = 0x0000;
    for (int i = 0; r && i < minis; ++i) {
      const int mx = x + i * miniW;
      r->round(mx, cy - 7, 16, 15, 7, gel);
      r->round(mx + 4, cy - 2, 3, 3, 1, ink);
      r->round(mx + 9, cy - 2, 3, 3, 1, ink);
    }
    x += minis * miniW;
    if (s.helpers > minis) {
      std::snprintf(n, sizeof(n), "+%d", s.helpers - minis);
      x = number(x + 2, grey);
    }
    x += kIcon;
  }
  if (s.idle > 0) x = chip(s.idle, kIdleRing, kIdleInk, [&](int at) { sleeper(*r, at, cy, kIdleInk); });
  if (s.todoTotal > 0) {
    std::snprintf(n, sizeof(n), "%d/%d", s.todoDone, s.todoTotal);
    x = number(x, eye) + kIcon;
  }
  return x;
}

}  // namespace

int paintCounts(Raster& r, const Strip& s, int x, int cy, int spin) { return counts(&r, s, x, cy, spin); }

void paintRule(Raster& r, int x0, int x1, int y, bool down, uint16_t ink) {
  const int cx = (x0 + x1) / 2, tip = down ? y + 6 : y - 5, foot = down ? y - 3 : y + 4;
  r.round(x0, y, cx - 18 - x0, 2, 1, ink);
  r.round(cx + 18, y, x1 - cx - 18, 2, 1, ink);
  r.line({cx - 10, foot}, {cx, tip}, 3, ink);
  r.line({cx, tip}, {cx + 10, foot}, 3, ink);
}

namespace {

// The status strip: who needs you, or whose turn the finish was, then how
// many sessions work, and the plug with no app (render/screens.h's Strip).
void strip(Lane& l, const Strip& s, int spin) {
  if (!s.shows()) return;
  Raster& r = l.r;
  const uint16_t dim = inkRgb565(kInkDim), grey = inkRgb565(kInkGrey);
  const Font& f = kSign;
  const int cy = l.y((kStripTop + kHeight) / 2), ty = cy - f.h / 2;
  // In from the sides, and clear of the panel's rounded corners on the
  // rows of the marks and the digits, and of the chips, whose round
  // corners may stand nearer.
  const Surface& panel = l.r.s;
  const int margin = std::max(
      kMargin,
      std::max(panel.inset(cy - 12, cy + 12), panel.inset(cy - kChipH / 2, cy + kChipH / 2, kChipRadius)) + kCornerGap);
  // Its rule, with a chevron for the agents' drawer under it while there
  // are any (render/gel/drawer.h).
  if (s.agent || s.busy > 0 || s.idle > 0)
    paintRule(r, margin, l.w - margin, l.y(kStripTop), false, dim);
  else
    r.round(margin, l.y(kStripTop), l.w - 2 * margin, 2, 1, dim);
  const int countsWidth = counts(nullptr, s, 0, cy, spin);
  int x = margin;
  if (s.agent) {
    const uint16_t amber = inkRgb565(kInkAmber);
    dot(r, x, cy, amber);
    char more[12] = "";
    if (s.more > 0) std::snprintf(more, sizeof(more), "+%d", s.more);
    const int moreRoom = more[0] ? glyphCount(more) * f.w + 12 : 0;
    char who[48];
    std::snprintf(who, sizeof(who), "%s \xC2\xB7 %s", s.agent, s.name && *s.name ? s.name : s.project);
    x = text(r, f, x + 2 * kIcon, ty, who, amber, l.w - margin - (x + 2 * kIcon) - moreRoom - countsWidth);
    if (more[0]) x = text(r, f, x + 12, ty, more, grey);
    x += kIcon;
  } else if (s.doneAgent) {
    const uint16_t eye = inkRgb565(kInkEye);
    if (s.doneOutcome == Outcome::kSuccess)
      tick(r, x, cy, rgb565(kSageRgb));
    else if (s.doneOutcome == Outcome::kFailure)
      cross(r, x, cy, rgb565(kClayRgb));
    else
      dots(r, x, cy, eye);
    char who[48];
    std::snprintf(who, sizeof(who), "%s \xC2\xB7 %s", s.doneAgent, s.doneThread ? s.doneThread : "");
    x = text(r, f, x + 2 * kIcon, ty, who, eye, l.w - margin - (x + 2 * kIcon) - countsWidth) + kIcon;
  }
  // Then how many work, the helpers at work, and the agents idle, waiting
  // for you.
  counts(&r, s, x, cy, spin);
  if (s.noApp) plug(r, l.w - margin - 24, cy, grey);
}

// The strip, drawn at full strength, blended once at its opacity (0–255):
// its rows hold nothing else, over black, so that is scaling each pixel it
// wrote, in place, with no buffer of its own; a hole (the working mark's
// inside, a mini's eyes) stays one, and where its shapes meet it blends
// once.
void fade(Surface& s, int from, int alpha) {
  if (alpha >= 253) return;
  const bool tracked = s.height <= Surface::kTrackedRows;
  for (int y = from; y < s.height; ++y) {
    uint16_t* row = s.pixels + y * s.width;
    const int x1 = tracked ? s.written[y].last : s.width;
    for (int x = tracked ? s.written[y].first : 0; x < x1; ++x)
      if (row[x]) row[x] = mix565(0, row[x], alpha);
  }
}

// What the lane shows, as a key that's the same exactly when its pixels
// are (FNV-1a over the line or the strip's fields; never 0).
}  // namespace

uint32_t laneKey(const char* line, const Strip& s, int spin) {
  uint32_t h = 2166136261u;
  auto add = [&](const void* data, size_t n) {
    for (size_t i = 0; i < n; ++i) h = (h ^ static_cast<const uint8_t*>(data)[i]) * 16777619u;
  };
  auto str = [&](const char* v) { add(v ? v : "\x01", v ? std::strlen(v) + 1 : 1); };
  str(line);
  if (!line) {
    str(s.agent), str(s.project), str(s.name), str(s.doneAgent), str(s.doneThread);
    const int numbers[] = {s.more,     int(s.doneOutcome), s.busy,  s.idle,    s.helpers,
                           s.todoDone, s.todoTotal,        s.noApp, s.opacity, s.busy > 0 ? spin : 0};
    add(numbers, sizeof(numbers));
  }
  return h ? h : 1;
}

int bubbleRoom(const Surface& surface) { return BubbleBox(surface).room(surface.width); }

void paintLane(Surface& surface, const char* line, const Strip& s, int spin) {
  if (!surface.pixels) return;
  Lane l{Raster{surface}, surface.width, surface.height};
  l.r.limit = surface.height;
  if (line) {
    bubble(l, line);
  } else {
    strip(l, s, spin);
    fade(surface, l.y(kLaneTop), (s.opacity * 255 + 500) / 1000);
  }
  surface.laneKey = laneKey(line, s, spin);
  surface.laneKeyFrom = l.y(kLaneTop);
}

void paintFrame(Surface& surface, const Engine& e, bool mouthOpen, int dy, const char* line, const SignShow& sign,
                const Strip& s, const DoneShow& done, const rig::Channels& rig, const rig::Layers* layers, uint32_t t,
                const Stream* stream, uint32_t now, const PastimeShow* pastimes, const Drawer* drawer) {
  rig::Anchors at;
  if (drawer && drawer->shows()) {
    // The lane's rows are the sheet's: erased, and drawn again after.
    const DrawerPose pose = drawerPose(surface, *drawer);
    paint(surface, e, mouthOpen, dy, 0, &at, rig, layers, t, nullptr, &pose);
    if (pose.squint) paintSquint(surface, at, pose, DrawerLayout(surface.width, surface.height, surface.corner).top(drawer->open));
    Measure measure(profile.lane);
    paintDrawer(surface, *drawer, s, at, spinStep(now));
    return;
  }
  // A lane that shows what this surface's already shows is kept, not
  // erased and drawn again (Surface::clear): the glow over it too.
  const int glow = doneGlow(done);
  const int spin = spinStep(now);
  uint32_t key = laneKey(line, s, spin);
  if (glow) key = ((key ^ uint32_t(glow << 8 | int(done.outcome))) * 16777619u) | 1;
  // The ticket swings over where a card may be, so a card is drawn whole
  // while it hangs, not kept.
  if (done.shows()) surface.cardKey = 0;
  paint(surface, e, mouthOpen, dy, key, &at, rig, layers, t, pastimes);
  if (pastimes) {
    Measure measure(profile.props);
    paintPastimes(surface, *pastimes, at, e);
  }
  if (stream) {
    Measure measure(profile.stream);
    paintStreamBehind(surface, *stream, now);
    paintStreamDesk(surface, *stream, e, s, now);
    paintStreamFront(surface, *stream, at, e, now);
  }
  if (sign.text) paintSign(surface, sign, at);
  paintSky(surface, e, layers, t);
  paintTicket(surface, done);
  Measure measure(profile.lane);
  const bool lane = surface.laneKey != key;
  if (lane) paintLane(surface, line, s, spin), surface.laneKey = key;
  // A kept lane keeps its glow.
  paintGlow(surface, done, 0, lane ? surface.height : surface.laneKeyFrom);
}

}  // namespace render::gel
