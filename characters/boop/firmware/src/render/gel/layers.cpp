#include "render/gel/layers.h"

#include <initializer_list>

#include "render/font.h"
#include "render/gel/engine.h"
#include "render/gel/lane.h"
#include "render/gel/raster.h"
#include "render/palette.h"
#include "render/tags.h"

namespace render::gel {

namespace {

// The props' colours (render/gel/props.cpp): a card's ink and rim, its
// words, and the helpers' gel for the hands.
constexpr uint16_t kCardInk = rgb565(27, 55, 78), kCardRim = rgb565(0x78, 0xa4, 0xc8);
constexpr uint16_t kWords = rgb565(184, 233, 245), kGel = rgb565(89, 169, 224), kShine = rgb565(184, 233, 245);
constexpr uint16_t kCream = rgb565(246, 240, 226), kInk = rgb565(28, 24, 36);

// The ring through its left side, its front and its right side, as a
// curve (sixteenths), its `n` + 1 points from left to right, raised `up`.
int ring(const rig::Point& l, const rig::Point& f, const rig::Point& r, int up, Point* out, int n = 8) {
  const int cx = 2 * f.x - (l.x + r.x) / 2, cy = 2 * f.y - (l.y + r.y) / 2;  // through f at the middle
  for (int i = 0; i <= n; ++i) {
    const int64_t u = i, v = n - i, d = int64_t(n) * n;
    out[i] = {int((v * v * l.x + 2 * u * v * cx + u * u * r.x) / d),
              int((v * v * l.y + 2 * u * v * cy + u * u * r.y) / d) - up};
  }
  return n + 1;
}

// A brim's curve and the head's width across it (sixteenths).
struct Head {
  Point band[9];
  int width, cx, top;
};
Head head(const rig::Anchors& at, int up) {
  Head h;
  ring(at.brimL, at.brimF, at.brimR, up, h.band);
  h.width = std::max(16, at.brimR.x - at.brimL.x);
  h.cx = (at.brimL.x + at.brimR.x) / 2;
  h.top = at.crown.y;
  return h;
}

// A triangle wave, 0 to `amp` and back, once every `period` ms.
int wave(int ms, int period, int amp) {
  const int p = ms % period;
  return (p < period / 2 ? p : period - p) * 2 * amp / period;
}

void nightcap(Raster& r, const Head& h, int ms) {
  const int w = h.width, swing = wave(ms, 2000, w / 30);
  const Point tip{h.cx + w * 11 / 20 + swing, h.top - w / 20};
  Point v[16];
  int n = 0;
  for (const Point& p : h.band) v[n++] = p;
  v[n++] = {h.cx + w * 9 / 20, h.top - w / 8};  // the droop, down to the tip
  v[n++] = tip;
  v[n++] = {h.cx + w * 7 / 20, h.top - w * 7 / 20};
  v[n++] = {h.cx + w / 6, h.top - w * 9 / 20};  // its peak
  v[n++] = {h.cx - w / 6, h.top - w * 3 / 10};
  r.polygon16(v, n, rgb565(58, 62, 150));
  r.stroke16(h.band, 9, w / 9, kCream);  // the band
  r.disk16(tip.x, tip.y, w / 13, kCream);
}

// A small cone perched on top: its base the middle of the brim, drawn in
// toward the crown, and a pompom.
void partyHat(Raster& r, const Head& h, uint16_t a, uint16_t b) {
  const int w = h.width;
  const Point tip{h.cx + w / 24, h.top - w * 9 / 20};
  Point v[16], stripe[4], base[9];
  int n = 0;
  for (int i = 0; i < 9; ++i)
    base[i] = {h.cx + (h.band[i].x - h.cx) * 11 / 20, h.band[i].y - (h.band[i].y - h.top) * 2 / 5};
  for (const Point& p : base) v[n++] = p;
  v[n++] = tip;
  r.polygon16(v, n, a);
  for (int i = 1; i <= 2; ++i) {  // two stripes, cut to the cone
    const int y0 = h.top - w * (i * 14) / 100 + w / 20, y1 = y0 - w / 16;
    stripe[0] = {h.cx - w, y0}, stripe[1] = {h.cx + w, y0}, stripe[2] = {h.cx + w, y1}, stripe[3] = {h.cx - w, y1};
    r.polygon16(stripe, 4, b, v, n);
  }
  r.stroke16(base, 9, w / 16, b);
  r.disk16(tip.x, tip.y, w / 16, b);
}

void witchHat(Raster& r, const Head& h) {
  const int w = h.width;
  const uint16_t felt = rgb565(52, 34, 70);
  Point brim[9];  // wider than the head
  for (int i = 0; i < 9; ++i) brim[i] = {h.cx + (h.band[i].x - h.cx) * 7 / 5, h.band[i].y};
  r.stroke16(brim, 9, w / 10, felt);
  Point v[16];
  int n = 0;
  for (int i = 1; i < 8; ++i) v[n++] = {h.cx + (h.band[i].x - h.cx) * 3 / 4, h.band[i].y};
  v[n++] = {h.cx + w / 6, h.top - w * 7 / 20};
  v[n++] = {h.cx + w * 2 / 5, h.top - w * 3 / 5};  // the bent tip
  v[n++] = {h.cx - w / 20, h.top - w * 3 / 10};
  r.polygon16(v, n, felt);
  Point band[7];
  for (int i = 0; i < 7; ++i) band[i] = {v[i].x, v[i].y - w / 14};
  r.stroke16(band, 7, w / 14, rgb565(240, 140, 40));
}

void bobble(Raster& r, const Head& h) {
  const int w = h.width;
  const uint16_t knit = rgb565(200, 52, 60);
  Point v[16];
  int n = 0;
  for (const Point& p : h.band) v[n++] = p;
  // A dome over the crown, right to left.
  v[n++] = {h.cx + w * 2 / 5, h.top - w / 5};
  v[n++] = {h.cx + w / 5, h.top - w * 3 / 10};
  v[n++] = {h.cx, h.top - w * 8 / 25};
  v[n++] = {h.cx - w / 5, h.top - w * 3 / 10};
  v[n++] = {h.cx - w * 2 / 5, h.top - w / 5};
  r.polygon16(v, n, knit);
  r.stroke16(h.band, 9, w / 8, kCream);
  r.disk16(h.cx, h.top - w * 8 / 25, w / 11, kCream);
}

void shades(Raster& r, const rig::Anchors& at) {
  const int d = std::max(16, at.eyeR.x - at.eyeL.x), lw = d * 27 / 100, lh = d / 6;
  for (const rig::Point& e : {at.eyeL, at.eyeR}) {
    const Point lens[] = {
        {e.x - lw, e.y - lh}, {e.x + lw, e.y - lh}, {e.x + lw * 4 / 5, e.y + lh}, {e.x - lw * 4 / 5, e.y + lh}};
    r.polygon16(lens, 4, kInk);
    r.alpha = 150;
    r.disk16(e.x - lw / 2, e.y - lh / 2, d / 40 + 8, kCream);
    r.alpha = 255;
  }
  const Point bridge[] = {{at.eyeL.x + lw, at.eyeL.y - lh / 2}, {at.eyeR.x - lw, at.eyeR.y - lh / 2}};
  r.stroke16(bridge, 2, d / 30 + 16, kInk);
}

// A number below `range` from a particle's index, for where it starts.
int spread(int i, int salt, int range) {
  return int(((uint32_t(i) + 1) * 2654435761u ^ uint32_t(salt) * 40503u) % uint32_t(range));
}

void snow(Raster& r, int w, int bottom, int ms) {
  r.alpha = 220;
  for (int i = 0; i < 22; ++i) {
    const int speed = 20 + spread(i, 1, 18),
              y = (spread(i, 2, bottom) + ms / 1000 * speed + ms % 1000 * speed / 1000) % bottom;
    r.disk(spread(i, 3, w) + wave(ms + i * 370, 3000, 8), y, 3 + i % 2, kCream);
  }
  r.alpha = 255;
}

void confetti(Raster& r, int w, int bottom, int ms) {
  const uint16_t colors[] = {rgb565(240, 80, 120), rgb565(250, 200, 60), rgb565(90, 200, 140), rgb565(150, 120, 240)};
  for (int i = 0; i < 18; ++i) {
    const int speed = 40 + spread(i, 4, 30),
              y = (spread(i, 5, bottom) + ms / 1000 * speed + ms % 1000 * speed / 1000) % bottom;
    const int flip = (ms / 120 + i) % 3;
    r.round(spread(i, 6, w) + wave(ms + i * 290, 1600, 10), y, 10 - flip * 3, 5 + flip * 2, 1, colors[i % 4]);
  }
}

void heart(Raster& r, int x, int y, int s, uint16_t ink) {  // whole pixels, `s` its half-width
  r.disk(x - s / 2, y, s / 2, ink);
  r.disk(x + s / 2, y, s / 2, ink);
  const Point v[] = {{x - s, y + 1}, {x + s, y + 1}, {x, y + s + s / 2}};
  r.polygon(v, 3, ink);
}

// Hearts floating up either side of it.
void hearts(Raster& r, int w, int bottom, int ms) {
  for (int i = 0; i < 6; ++i) {
    const int speed = 25 + spread(i, 7, 15);
    const int y = bottom - 12 - (spread(i, 8, bottom) + ms / 1000 * speed + ms % 1000 * speed / 1000) % (bottom - 12);
    const int x = i % 2 ? w - 30 - spread(i, 9, w / 5) : 30 + spread(i, 9, w / 5);
    r.alpha = std::min(255, y * 3);
    heart(r, x + wave(ms + i * 500, 2400, 8), y, 7 + i % 3 * 2, i % 2 ? rgb565(240, 110, 150) : rgb565(220, 50, 80));
  }
  r.alpha = 255;
}

// Zs drifting up and right from beside its head, each for 2.4 s, a new
// one every 0.8 s, growing and fading as they go.
void zs(Raster& r, const rig::Anchors& at, int ms) {
  const Font* fonts[] = {&kSmall, &kLarge, &kSign};
  for (int i = 0; i < 3; ++i) {
    const int age = (ms + i * 800) % 2400, f = age * 3 / 2400;
    const int x = at.brimR.x / 16 + 24 + age / 40, y = at.brimR.y / 16 - age / 20;
    r.alpha = 255 - age * 200 / 2400;
    text(r, *fonts[f], x, y - fonts[f]->h, "z", kCream);
  }
  r.alpha = 255;
}

}  // namespace

int sleepyLids(const Engine& e) {
  return hasTag(e.scenes.when, "night") && e.scenes.route.state != SceneState::kAsleep ? kNightLids : 0;
}

void paintLayers(Surface& s, const Engine& e, const rig::Anchors& at) {
  if (!s.pixels) return;
  Raster r{s};
  const uint32_t when = e.scenes.when;
  const int ms = int(e.elapsedMs % 3600000u), bottom = s.height * 4 / 5;
  const SceneState state = e.scenes.route.state;
  const bool peekaboo = state == SceneState::kGesture && e.scenes.variant == int(Gesture::kPeekaboo);
  if (hasTag(when, "friday") && !hasTag(when, "night") && state != SceneState::kAsleep && !peekaboo) shades(r, at);
  if (!peekaboo) {
    const Head h = head(at, 0);
    switch (outfitFor(when)) {
      case Outfit::kWitchHat: witchHat(r, h); break;
      case Outfit::kPartyHat: {
        const bool lunar = hasTag(when, "lunar"), coder = hasTag(when, "programmers") && !hasTag(when, "party");
        partyHat(r, h,
                 lunar   ? rgb565(210, 40, 40)
                 : coder ? rgb565(30, 40, 36)
                         : rgb565(240, 80, 150),
                 lunar   ? rgb565(250, 200, 60)
                 : coder ? rgb565(90, 230, 120)
                         : rgb565(250, 210, 70));
        break;
      }
      case Outfit::kNightcap: nightcap(r, h, ms); break;
      case Outfit::kBobble: bobble(r, h); break;
      default: break;
    }
  }
  const uint8_t air = airFor(when);
  if (air & kSnow) snow(r, s.width, bottom, ms);
  if (air & kConfetti) confetti(r, s.width, bottom, ms);
  if (air & kHearts) hearts(r, s.width, bottom, ms);
  if (hasTag(when, "night") && state == SceneState::kAsleep) zs(r, at, ms);
}

void paintSign(Surface& s, const SignShow& sign, const rig::Anchors& at) {
  if (!s.pixels || !sign.text) return;
  Raster r{s};
  const int bottom = s.height * 4 / 5;  // the lane's top: shapes stop there
  const Font& f = kSign;
  const int tw = stringWidth(f, sign.text), w = tw + 2 * SignLayer::kPad, h = f.h + 10;
  // Centred on its front, held at its hands' ring, never into the lane.
  const int x = at.handF.x / 16 - w / 2;
  const int y = std::min(at.handF.y / 16 - h / 2, bottom - SignLayer::kGap - h) +
                signLift(sign.ms, SignLayer::kRisePx, SignLayer::kBobPx);
  r.round(x, y, w, h, 12, kCardInk);
  r.ring(x, y, w, h, 12, 2, kCardRim);
  text(r, f, x + SignLayer::kPad, y + 5, sign.text, kWords);
  // A little gel hand at either side, gripping it.
  for (int side : {-1, 1}) {
    const int hx = side < 0 ? x : x + w, hy = y + h / 2;
    r.disk(hx, hy, 12, kGel);
    r.alpha = 160;
    r.disk(hx - 4, hy - 5, 3, kShine);
    r.alpha = 255;
  }
}

}  // namespace render::gel
