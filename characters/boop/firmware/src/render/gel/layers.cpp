#include "render/gel/layers.h"

#include <algorithm>
#include <climits>
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
// The nightcap's and the gown's cloth, and the reading glasses' wire.
constexpr uint16_t kNightcloth = rgb565(58, 62, 150), kWire = rgb565(206, 164, 92);

// The point `i` thirty-seconds of a turn round a circle, as cosine and
// sine (Q12).
Point turn(int i) {
  static constexpr int16_t kCos[] = {4096, 4017, 3784, 3406, 2896, 2276, 1567, 799, 0};  // a quarter's
  const int j = i % 8;
  switch (i / 8 % 4) {
    case 0: return {kCos[j], kCos[8 - j]};
    case 1: return {-kCos[8 - j], kCos[j]};
    case 2: return {-kCos[j], -kCos[8 - j]};
    default: return {kCos[8 - j], -kCos[j]};
  }
}

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

// Its tip swings out and back every 2 s: `ms` into the swing.
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
  r.polygon16(v, n, kNightcloth);
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

// Reading glasses: a round wire rim about each eye, a glint on its glass,
// and a bridge arching between them.
void glasses(Raster& r, const rig::Anchors& at) {
  const int d = std::max(16, at.eyeR.x - at.eyeL.x), radius = d / 5, wire = d / 50 + 16;
  for (const rig::Point& e : {at.eyeL, at.eyeR}) {
    Point rim[33], glint[4];
    for (int i = 0; i <= 32; ++i) rim[i] = {e.x + radius * turn(i).x / 4096, e.y + radius * turn(i).y / 4096};
    for (int i = 0; i < 4; ++i)  // up and to the left, inside the rim
      glint[i] = {e.x + radius * 7 / 10 * turn(18 + i).x / 4096, e.y + radius * 7 / 10 * turn(18 + i).y / 4096};
    r.alpha = 170;
    r.stroke16(glint, 4, wire, kCream);
    r.alpha = 255;
    r.stroke16(rim, 33, wire, kWire);
  }
  const Point bridge[] = {{at.eyeL.x + radius, at.eyeL.y - radius / 5},
                          {(at.eyeL.x + at.eyeR.x) / 2, (at.eyeL.y + at.eyeR.y) / 2 - radius * 2 / 5},
                          {at.eyeR.x - radius, at.eyeR.y - radius / 5}};
  r.stroke16(bridge, 3, wire, kWire);
}

// The nightcap's gown, while it sleeps: from the lap's ring down past the
// body's hem, flaring out a little to it, in a lighter cloth than the
// cap's with soft pleats down it and a cream frill along the top.
void gown(Raster& r, const rig::Anchors& at) {
  constexpr int n = rig::Anchors::kRingPoints;
  const int w = std::max(16, at.lap[n - 1].x - at.lap[0].x), flare = w / 22, lip = w / 90 + 8;
  // The hem a lip below the body's outline, flared out to the sides.
  Point hem[n];
  for (int i = 0; i < n; ++i) hem[i] = {at.hem[i].x + flare * (2 * i - (n - 1)) / (n - 1), at.hem[i].y + lip};
  // A side from the lap's end down to the hem's, bowed out as the body is
  // between them: a quadratic's points a quarter, a half and three quarters
  // down.
  Point v[2 * n + 6];
  int k = 0;
  auto side = [&](Point from, Point to, int out) {
    const Point c{(from.x + to.x) / 2 + out, (from.y + to.y) / 2};
    for (int t : {1, 2, 3})
      v[k++] = {((4 - t) * (4 - t) * from.x + 2 * t * (4 - t) * c.x + t * t * to.x) / 16,
                ((4 - t) * (4 - t) * from.y + 2 * t * (4 - t) * c.y + t * t * to.y) / 16};
  };
  for (int i = 0; i < n; ++i) v[k++] = at.lap[i];
  side(at.lap[n - 1], hem[n - 1], w / 24);
  for (int i = n - 1; i >= 0; --i) v[k++] = hem[i];
  side(hem[0], at.lap[0], -w / 24);
  r.polygon16(v, k, rgb565(88, 92, 184));
  r.alpha = 110;
  for (int i : {5, 11}) {  // a pleat from under the frill to the hem
    const Point &a = at.lap[i], &b = hem[i];
    const Point pleat[] = {{a.x + (b.x - a.x) / 4, a.y + (b.y - a.y) / 4}, {b.x, b.y - lip}};
    r.stroke16(pleat, 2, w / 70 + 8, kNightcloth);
  }
  r.alpha = 255;
  // The frill: a cream band along the top short of the sides, where the
  // ring turns away, and under it a scallop between each two of its
  // points, as one shape: from inside the band, along its lower edge and
  // back.
  const int band = w / 34, first = 1, last = n - 2;
  r.stroke16(at.lap + first, last - first + 1, band, kCream);
  static constexpr int kScallop[] = {0, 3, 4, 3};  // eighths of the band, down past its edge
  Point f[n + 4 * (n - 1) + 1];
  int m = 0;
  for (int i = first; i <= last; ++i) f[m++] = at.lap[i];
  for (int i = last; i > first; --i)
    for (int q = 0; q < 4; ++q) {
      const Point &a = at.lap[i], &b = at.lap[i - 1];
      f[m++] = {a.x + (b.x - a.x) * q / 4, a.y + (b.y - a.y) * q / 4 + band / 2 + band * kScallop[q] / 8};
    }
  f[m++] = {at.lap[first].x, at.lap[first].y + band / 2};
  r.polygon16(f, m, kCream);
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

// What it wears besides where it sits: the hat, the party hat's colours,
// how far into its swing the nightcap is, on a step of kSwingMs (the hat's
// as one number), what's over its eyes, and the gown under the nightcap
// while it sleeps.
struct Look {
  Outfit hat;
  int colors, swing;
  Eyewear eyes;
  bool gown;
  uint32_t hatKey() const { return uint32_t(hat) | uint32_t(colors) << 4 | uint32_t(swing) << 8; }
};
// The nightcap's swing for the engine's clock.
int swingFor(const Engine& e) { return int(e.elapsedMs % 2000 / OutfitLayer::kSwingMs * OutfitLayer::kSwingMs); }
// Peekaboo's gesture takes it all off, and it sleeps with its eyes bare.
Look lookFor(const Engine& e) {
  const uint32_t when = e.scenes.when;
  const SceneState state = e.scenes.route.state;
  if (state == SceneState::kGesture && e.scenes.variant == int(Gesture::kPeekaboo)) return {};
  const Outfit hat = outfitFor(when);
  const int colors = hasTag(when, "lunar") ? 1 : hasTag(when, "programmers") && !hasTag(when, "party") ? 2 : 0;
  const bool nightcap = hat == Outfit::kNightcap, asleep = state == SceneState::kAsleep;
  return {hat, hat == Outfit::kPartyHat ? colors : 0, nightcap ? swingFor(e) : 0,
          asleep ? Eyewear::kNone : eyewearFor(when), nightcap && asleep};
}

void eyewear(Raster& r, const rig::Anchors& at, Eyewear eyes) {
  if (eyes == Eyewear::kGlasses) glasses(r, at);
  if (eyes == Eyewear::kShades) shades(r, at);
}

void hat(Raster& r, const rig::Anchors& at, const Look& look) {
  const Head h = head(at, 0);
  switch (look.hat) {
    case Outfit::kWitchHat: witchHat(r, h); break;
    case Outfit::kPartyHat: {
      static constexpr uint16_t kColors[][2] = {{rgb565(240, 80, 150), rgb565(250, 210, 70)},  // a party's
                                                {rgb565(210, 40, 40), rgb565(250, 200, 60)},   // Lunar New Year's
                                                {rgb565(30, 40, 36), rgb565(90, 230, 120)}};   // Programmers' Day's
      partyHat(r, h, kColors[look.colors][0], kColors[look.colors][1]);
      break;
    }
    case Outfit::kNightcap: nightcap(r, h, look.swing); break;
    case Outfit::kBobble: bobble(r, h); break;
    default: break;
  }
}

// The anchors `at` moved `dx`, `dy` sixteenths.
rig::Anchors moved(rig::Anchors at, int dx, int dy) {
  for (Point* p : {&at.crown, &at.brimL, &at.brimF, &at.brimR, &at.handF, &at.eyeL, &at.eyeR}) p->x += dx, p->y += dy;
  for (int i = 0; i < rig::Anchors::kRingPoints; ++i) {
    at.lap[i].x += dx, at.lap[i].y += dy;
    at.hem[i].x += dx, at.hem[i].y += dy;
  }
  return at;
}

// Part of what it wears as last drawn into a recording (OutfitLayer): what
// it looked like, the anchors it was drawn at, the one it rides first, and
// the last frame it was blended into.
struct Kept {
  static constexpr int kAnchors = 6;
  Recording shapes;
  bool valid = false;
  uint32_t look = 0;
  Point at[kAnchors]{};
  int dx = 0, dy = 0;  // the surface's pixels from the recording's
  // The last frame's body, time and anchors, and when its anchors last
  // moved.
  const Engine* engine = nullptr;
  uint32_t ms = 0, movedAt = 0;
  Point last[kAnchors]{};
};
uint8_t hatBytes[OutfitLayer::kHatBytes], wornBytes[OutfitLayer::kWornBytes];
// The hat, on the brim's front; and the gown, on the hem's front, or else
// what's over its eyes, on the left eye (it never wears both).
Kept keptHat{{hatBytes, OutfitLayer::kHatBytes}}, keptWorn{{wornBytes, OutfitLayer::kWornBytes}};

int floor16(int v) { return v >= 0 ? v / 16 : -((15 - v) / 16); }

// `draw` at `at`, which looks like `look` and rides the `n` anchors `now`:
// blended from what `kept` holds while that fits, else drawn into its
// recording first; drawn straight on the surface when it doesn't fit the
// recording's frame or its room.
template <typename Draw>
void wear(Raster& r, Kept& kept, const Engine& e, const rig::Anchors& at, const Point* now, int n, uint32_t look,
          Draw draw) {
  // Moving: a frame of the same body just before, and its anchors moved
  // within kStillMs.
  const uint32_t t = e.elapsedMs;
  for (int i = 0; i < n; ++i)
    if (now[i].x != kept.last[i].x || now[i].y != kept.last[i].y) kept.movedAt = t;
  const bool moving = kept.engine == &e && t != kept.ms && t - kept.ms <= OutfitLayer::kMovingMs &&
                      t - kept.movedAt < OutfitLayer::kStillMs;
  kept.engine = &e, kept.ms = t;
  std::copy(now, now + n, kept.last);
  // How far the body has moved it since it was kept, to the nearest pixel,
  // by the anchor it rides, and the most any is off once it's moved that far.
  int ox = 0, oy = 0, off = INT_MAX;
  if (kept.valid && kept.look == look) {
    ox = floor16(now[0].x - kept.at[0].x + 8), oy = floor16(now[0].y - kept.at[0].y + 8);
    off = 0;
    for (int i = 0; i < n; ++i)
      off = std::max({off, std::abs(now[i].x - kept.at[i].x - ox * 16), std::abs(now[i].y - kept.at[i].y - oy * 16)});
  }
  if (off != 0 && !(moving && off <= OutfitLayer::kSlack)) {
    // Kept in a frame as wide as the surface and taller, the anchor it rides
    // a whole number of pixels from its middle, as far into its pixel as it
    // is.
    const int fx = r.s.width / 2 - floor16(now[0].x), fy = OutfitLayer::kFrameY - floor16(now[0].y);
    Raster record{r.s};
    record.limit = OutfitLayer::kFrameHeight;
    record.recording = &kept.shapes;
    kept.shapes.clear();
    draw(record, moved(at, fx * 16, fy * 16));
    const Box& b = kept.shapes.box;
    kept.valid = !kept.shapes.full && b.x0 > 0 && b.y0 > 0 && b.x1 < r.s.width && b.y1 < OutfitLayer::kFrameHeight;
    if (!kept.valid) return draw(r, at);  // past the frame's edge, or its room
    kept.look = look, kept.dx = -fx, kept.dy = -fy, ox = oy = 0;
    std::copy(now, now + n, kept.at);
  }
  r.replay(kept.shapes, kept.dx + ox, kept.dy + oy);
}

// The worn and hat layers' contents for a look, and the look a pair of
// them is, its nightcap swinging on the engine's clock.
constexpr uint32_t kGown = 1u << 8;  // a worn content no eyewear has
uint32_t hatOf(const Look& l) { return l.hat == Outfit::kNone ? 0 : uint32_t(l.hat) | uint32_t(l.colors) << 4; }
uint32_t wornOf(const Look& l) { return l.gown ? kGown : uint32_t(l.eyes); }
Look lookOf(uint32_t hat, uint32_t worn, const Engine& e) {
  const Outfit kind = Outfit(hat & 15);
  return {kind, int(hat >> 4 & 15), kind == Outfit::kNightcap ? swingFor(e) : 0,
          worn == kGown ? Eyewear::kNone : Eyewear(worn), worn == kGown};
}

// The gown or what's over its eyes, then the hat, each at its layer's
// fade.
void outfit(Raster& r, const Engine& e, const rig::Anchors& at, const Look& look, int wornFade, int hatFade) {
  constexpr int kEnd = rig::Anchors::kRingPoints - 1;
  r.fade = wornFade;
  if (look.gown) {
    const Point now[] = {at.hem[kEnd / 2], at.hem[0], at.hem[kEnd], at.lap[0], at.lap[kEnd / 2], at.lap[kEnd]};
    wear(r, keptWorn, e, at, now, 6, 1u << 8, gown);  // a look no eyewear has
  } else if (look.eyes != Eyewear::kNone) {
    const Point now[] = {at.eyeL, at.eyeR};
    wear(r, keptWorn, e, at, now, 2, uint32_t(look.eyes),
         [&look](Raster& r, const rig::Anchors& at) { eyewear(r, at, look.eyes); });
  }
  r.fade = hatFade;
  if (look.hat != Outfit::kNone) {
    const Point now[] = {at.brimF, at.crown, at.brimL, at.brimR};
    wear(r, keptHat, e, at, now, 4, look.hatKey(), [&look](Raster& r, const rig::Anchors& at) { hat(r, at, look); });
  }
  r.fade = 255;
}

}  // namespace

int sleepyLids(const Engine& e) {
  if (!hasTag(e.scenes.when, "night")) return 0;
  // They go as the face squashes shut, gone by when it's a line, and come
  // back as it wakes.
  const F open = max(0, 1 - e.face.shut.x / SemanticFace::kShutLine);
  return int((open.raw * kNightLids + F::scale / 2) / F::scale);
}

Contents layerContents(const Engine& e) {
  const Look look = lookFor(e);
  const bool zs = hasTag(e.scenes.when, "night") && e.scenes.route.state == SceneState::kAsleep;
  return {wornOf(look), hatOf(look), airFor(e.scenes.when), zs ? 1u : 0u};
}

void paintLayers(Surface& s, const Engine& e, const rig::Anchors& at, const rig::Layers* layers, uint32_t t) {
  if (!s.pixels) return;
  Raster r{s};
  const int ms = int(e.elapsedMs % 3600000u), bottom = s.height * 4 / 5;
  // Each layer's content and fade: the stack's, or with none, whole in
  // what the engine's tags and state call for.
  using rig::Layer;
  const Contents now = layerContents(e);
  auto content = [&](Layer l, uint32_t whole) { return layers ? layers->content(l, t) : whole; };
  auto fade = [&](Layer l) { return layers ? (layers->opacity(l, t) * 255 + 500) / 1000 : 255; };
  outfit(r, e, at, lookOf(content(Layer::kHat, now.hat), content(Layer::kWorn, now.worn), e), fade(Layer::kWorn),
         fade(Layer::kHat));
  const uint32_t air = content(Layer::kAir, now.air);
  r.fade = fade(Layer::kAir);
  if (air & kSnow) snow(r, s.width, bottom, ms);
  if (air & kConfetti) confetti(r, s.width, bottom, ms);
  if (air & kHearts) hearts(r, s.width, bottom, ms);
  r.fade = fade(Layer::kBeside);
  if (content(Layer::kBeside, now.beside)) zs(r, at, ms);
}

void paintSign(Surface& s, const SignShow& sign, const rig::Anchors& at) {
  if (!s.pixels || !sign.text) return;
  Raster r{s};
  r.fade = (sign.opacity * 255 + 500) / 1000;
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
