#include "render/gel/lane.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

#include "fonts_gel.h"
#include "render/font.h"
#include "render/gel/layers.h"
#include "render/gel/painter.h"
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
constexpr int kBubbleMargin = 10;
constexpr int kBubblePad = 12;  // from the outline to the text, left and right
constexpr int kBubbleLine = 2;
constexpr int kBubbleRadius = 14;

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

namespace {

// The line in its bubble, which takes the whole lane: a box with round
// corners and a short tail up to the face, the text centred in the
// bubble's font, or the sign's or the large one when it doesn't fit (the
// longest take, 22, fits the first; a line of 34, the last), cut to fit.
void bubble(Lane& l, const char* line) {
  const uint16_t dim = inkRgb565(kInkDim);
  const int room = bubbleRoom(l.w);
  const Font* f = &kFontBubble;
  for (const Font* smaller : {&kSign, &kLarge})
    if (glyphCount(line) * f->w > room) f = smaller;
  const int tw = std::min(glyphCount(line) * f->w, room);
  const int bw = tw + 2 * (kBubblePad + kBubbleLine), left = (l.w - bw) / 2;
  const int top = l.y(kLaneTop + 4), bottom = l.y(kHeight - 2), cx = l.w / 2;
  l.r.ring(left, top, bw, bottom - top, kBubbleRadius, kBubbleLine, dim);
  const Point tail[] = {{cx - 9, top + kBubbleLine}, {cx + 9, top + kBubbleLine}, {cx, l.y(kLaneTop)}};
  l.r.polygon(tail, 3, dim);
  text(l.r, *f, (l.w - tw) / 2, (top + bottom) / 2 - f->h / 2, line, inkRgb565(kInkAmber), room);
}

// The strip's marks, each in a kIcon box with its middle at (x + 9, cy).
void dot(Raster& r, int x, int cy, uint16_t ink) { r.disk(x + 9, cy, 8, ink); }
// The working count's: a ring with its left half filled, which no digit
// reads as.
void working(Raster& r, int x, int cy, uint16_t ink) {
  r.disk(x + 9, cy, 8, ink);
  r.disk(x + 9, cy, 5, 0);
  r.bounds = {x, cy - 9, x + 9, cy + 10};
  r.disk(x + 9, cy, 5, ink);
  r.bounds = Raster::kEverywhere;
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

// The counts after the names: how many sessions work, the helpers at work
// (a mini each, a little droplet of the gel with two eyes), the agents idle
// (a parcel each for BOOT to hand over), and last, as Pixel's strip has it,
// how far down its to-do list the longest turn with one is ("3/7"), from x,
// each with the gap after it. Drawn when r is given; either way, the x
// after them, so the names leave them the room they take.
int counts(Raster* r, const Strip& s, int x, int cy) {
  const Font& f = kSign;
  const int ty = cy - f.h / 2;
  const uint16_t dim = inkRgb565(kInkDim), grey = inkRgb565(kInkGrey), eye = inkRgb565(kInkEye);
  char n[24];
  auto number = [&](int at, uint16_t ink) { return r ? text(*r, f, at, ty, n, ink) : at + glyphCount(n) * f.w; };
  if (s.busy > 0) {
    if (r) working(*r, x, cy, grey);
    std::snprintf(n, sizeof(n), "%d", s.busy);
    x = number(x + kIcon + 8, grey) + kIcon;
  }
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
  if (s.idle > 0) {
    if (r) {
      r->round(x, cy - 6, 16, 13, 2, eye);
      r->round(x + 7, cy - 6, 2, 13, 0, dim);
      r->round(x, cy - 1, 16, 2, 0, dim);
    }
    std::snprintf(n, sizeof(n), "%d", s.idle);
    x = number(x + kIcon + 10, eye) + kIcon;
  }
  if (s.todoTotal > 0) {
    std::snprintf(n, sizeof(n), "%d/%d", s.todoDone, s.todoTotal);
    x = number(x, eye) + kIcon;
  }
  return x;
}

// The status strip: who needs you, or whose turn the finish was, then how
// many sessions work, and the plug with no app (render/screens.h's Strip).
void strip(Lane& l, const Strip& s) {
  if (!s.shows()) return;
  Raster& r = l.r;
  const uint16_t dim = inkRgb565(kInkDim), grey = inkRgb565(kInkGrey);
  r.round(kMargin, l.y(kStripTop), l.w - 2 * kMargin, 2, 1, dim);
  const Font& f = kSign;
  const int cy = l.y((kStripTop + kHeight) / 2), ty = cy - f.h / 2;
  const int countsWidth = counts(nullptr, s, 0, cy);
  int x = kMargin;
  if (s.agent) {
    const uint16_t amber = inkRgb565(kInkAmber);
    dot(r, x, cy, amber);
    char more[12] = "";
    if (s.more > 0) std::snprintf(more, sizeof(more), "+%d", s.more);
    const int moreRoom = more[0] ? glyphCount(more) * f.w + 12 : 0;
    char who[48];
    std::snprintf(who, sizeof(who), "%s \xC2\xB7 %s", s.agent, s.name && *s.name ? s.name : s.project);
    x = text(r, f, x + 2 * kIcon, ty, who, amber, l.w - kMargin - (x + 2 * kIcon) - moreRoom - countsWidth);
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
    x = text(r, f, x + 2 * kIcon, ty, who, eye, l.w - kMargin - (x + 2 * kIcon) - countsWidth) + kIcon;
  }
  // Then how many work, the helpers at work, and the agents idle, waiting
  // for you.
  counts(&r, s, x, cy);
  if (s.noApp) plug(r, l.w - kMargin - 24, cy, grey);
}

// The strip, drawn at full strength, blended once at its opacity (0–255):
// its rows hold nothing else, over black, so that is scaling each pixel it
// wrote, in place, with no buffer of its own; a hole (the working mark's
// open half, a mini's eyes) stays one, and where its shapes meet it blends
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

uint32_t laneKey(const char* line, const Strip& s) {
  uint32_t h = 2166136261u;
  auto add = [&](const void* data, size_t n) {
    for (size_t i = 0; i < n; ++i) h = (h ^ static_cast<const uint8_t*>(data)[i]) * 16777619u;
  };
  auto str = [&](const char* v) { add(v ? v : "\x01", v ? std::strlen(v) + 1 : 1); };
  str(line);
  if (!line) {
    str(s.agent), str(s.project), str(s.name), str(s.doneAgent), str(s.doneThread);
    const int numbers[] = {s.more, int(s.doneOutcome), s.busy, s.idle, s.helpers, s.todoDone, s.todoTotal, s.noApp, s.opacity};
    add(numbers, sizeof(numbers));
  }
  return h ? h : 1;
}

int bubbleRoom(int width) { return width - 2 * (kBubbleMargin + kBubblePad + kBubbleLine); }

void paintLane(Surface& surface, const char* line, const Strip& s) {
  if (!surface.pixels) return;
  Lane l{Raster{surface}, surface.width, surface.height};
  l.r.limit = surface.height;
  if (line) {
    bubble(l, line);
  } else {
    strip(l, s);
    fade(surface, l.y(kLaneTop), (s.opacity * 255 + 500) / 1000);
  }
  surface.laneKey = laneKey(line, s);
  surface.laneKeyFrom = l.y(kLaneTop);
}

void paintFrame(Surface& surface, const Engine& e, bool mouthOpen, int dy, const char* line, const SignShow& sign,
                const Strip& s, const rig::Channels& rig, const rig::Layers* layers, uint32_t t, const Stream* stream,
                uint32_t now) {
  // A lane that shows what this surface's already shows is kept, not
  // erased and drawn again (Surface::clear).
  const uint32_t key = laneKey(line, s);
  rig::Anchors at;
  paint(surface, e, mouthOpen, dy, key, &at, rig, layers, t);
  if (stream) {
    Measure measure(profile.stream);
    paintStreamBehind(surface, *stream, now);
    paintStreamDesk(surface, *stream, e, s, now);
    paintStreamFront(surface, *stream, at, e, now);
  }
  if (sign.text) paintSign(surface, sign, at);
  paintSky(surface, e, layers, t);
  Measure measure(profile.lane);
  if (surface.laneKey != key) paintLane(surface, line, s);
}

}  // namespace render::gel
