#include "render/gel/layers.h"

#include <algorithm>
#include <climits>
#include <initializer_list>

#include "render/font.h"
#include "render/gel/engine.h"
#include "render/gel/lane.h"
#include "render/gel/raster.h"
#include "render/maths.h"
#include "render/palette.h"
#include "render/tags.h"

namespace render::gel {

namespace {

// The props' colours (render/gel/props.cpp): a card's ink and rim, its
// words, and the helpers' gel for the hands.
constexpr uint16_t kCardInk = rgb565(27, 55, 78), kCardRim = rgb565(0x78, 0xa4, 0xc8);
constexpr uint16_t kWords = rgb565(184, 233, 245), kGel = rgb565(89, 169, 224), kShine = rgb565(184, 233, 245);
constexpr uint16_t kCream = rgb565(246, 240, 226), kInk = rgb565(28, 24, 36);
// The nightcap's and the pyjamas' flannel, its stripes and the cap's
// cuff, the moon's light, and the reading glasses' wire.
constexpr uint16_t kNightcloth = rgb565(62, 72, 168), kNightstripe = rgb565(176, 190, 238),
                   kNightcuff = rgb565(112, 124, 210), kMoonlight = rgb565(250, 230, 160),
                   kMug = rgb565(232, 112, 72), kCoffee = rgb565(92, 52, 30),
                   kWire = rgb565(206, 164, 92);

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
// The same, in sixteenths of a pixel.
int wave16(int ms, int period, int amp) { return wave(ms, period, amp * 16); }

// A long sleeping cap in striped flannel: up from a soft cuff, over the
// crown and flopping down its left side, its tassel hanging by its cheek
// and swaying out and back every 2 s: `ms` into the sway.
void nightcap(Raster& r, const Head& h, int ms) {
  const int w = h.width, sway = wave(ms, 2000, w / 24);
  // Thousandths of the head's width from the crown, and how far down the
  // flop each is (it sways more the lower it hangs).
  auto at = [&](int x, int y, int hang = 0) {
    return Point{h.cx + w * x / 1000 + sway * hang / 4, h.top + w * y / 1000};
  };
  Point v[28];
  int n = 0;
  for (const Point& p : h.band) v[n++] = p;
  v[n++] = at(380, -40);  // up its right side
  v[n++] = at(230, -210);
  v[n++] = at(80, -320);
  v[n++] = at(-120, -370);  // over the top, where it bends
  v[n++] = at(-330, -350, 1);
  v[n++] = at(-520, -250, 2);  // and down the flop's outside
  v[n++] = at(-640, -60, 3);
  v[n++] = at(-690, 150, 4);
  v[n++] = at(-700, 330, 5);
  v[n++] = at(-625, 310, 5);  // back up its inside
  v[n++] = at(-600, 110, 4);
  v[n++] = at(-545, -80, 3);
  v[n++] = at(-450, -190, 2);
  v[n++] = at(-330, -240, 1);
  v[n++] = at(-420, -60);  // and down the cap's left side to the cuff
  r.polygon16(v, n, kNightcloth);
  for (int i = -2; i < 4; ++i) {  // pale stripes across it, cut to the cap
    const int y0 = h.top + w * (60 - i * 130) / 1000, y1 = y0 - w * 55 / 1000;
    const Point stripe[] = {{h.cx - w, y0}, {h.cx + w, y0}, {h.cx + w, y1}, {h.cx - w, y1}};
    r.polygon16(stripe, 4, kNightstripe, v, n);
  }
  r.stroke16(h.band, 9, w / 14, kNightcuff);  // the cuff, rolled
  const Point cord[] = {at(-662, 320, 5), at(-665, 390, 6)};
  r.stroke16(cord, 2, w / 60 + 8, kNightstripe);
  r.disk16(cord[1].x, cord[1].y, w / 22, kNightstripe);  // the tassel
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

// The nightcap's pyjamas: from the lap's ring down past
// the body's hem, flaring out a little to it, in the cap's striped flannel
// with a cream frill along the top.
void pyjamas(Raster& r, const rig::Anchors& at) {
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
  r.polygon16(v, k, kNightcloth);
  for (int i = 1; i < n - 1; i += 2) {  // the cap's stripes, down it: a pair of rings' gap wide
    const Point &a = at.lap[i], &b = hem[i], &c = at.lap[i + 1], &d = hem[i + 1];
    const Point stripe[] = {
        {a.x, a.y - lip}, {(a.x + c.x) / 2, c.y - lip}, {(b.x + d.x) / 2, d.y + lip}, {b.x, b.y + lip}};
    r.polygon16(stripe, 4, kNightstripe, v, k);
  }
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

// How far something falling at `speed` px/s has gone by `ms`, from
// `start`, wrapped at `range`: in sixteenths of a pixel, so a slow flake
// drifts smoothly rather than stepping a whole pixel every other frame.
int fallen16(int start, int speed, int ms, int range) {
  return int((int64_t(start) * 16 + int64_t(ms) * speed * 16 / 1000) % (int64_t(range) * 16));
}

void snow(Raster& r, int w, int bottom, int ms) {
  r.alpha = 220;
  for (int i = 0; i < 22; ++i) {
    const int speed = 20 + spread(i, 1, 18), y16 = fallen16(spread(i, 2, bottom), speed, ms, bottom);
    r.disk16(spread(i, 3, w) * 16 + wave16(ms + i * 370, 3000, 8) + 8, y16 + 8, (3 + i % 2) * 16 + 8, kCream);
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

// A heart about (x16, y16), sixteenths of a pixel, `s` whole pixels its
// half-width.
void heart(Raster& r, int x16, int y16, int s, uint16_t ink) {
  const int half = s / 2 * 16, lobe = std::max(1, s / 2) * 16 + 8;
  r.disk16(x16 - half + 8, y16 + 8, lobe, ink);
  r.disk16(x16 + half + 8, y16 + 8, lobe, ink);
  const Point v[] = {{x16 - s * 16 + 8, y16 + 24}, {x16 + s * 16 + 8, y16 + 24}, {x16 + 8, y16 + (s + s / 2) * 16 + 8}};
  r.polygon16(v, 3, ink);
}

// Hearts floating up either side of it.
void hearts(Raster& r, int w, int bottom, int ms) {
  for (int i = 0; i < 6; ++i) {
    const int speed = 25 + spread(i, 7, 15);
    const int y16 = (bottom - 12) * 16 - fallen16(spread(i, 8, bottom), speed, ms, bottom - 12);
    const int x = i % 2 ? w - 30 - spread(i, 9, w / 5) : 30 + spread(i, 9, w / 5);
    r.alpha = std::min(255, y16 * 3 / 16);
    heart(r, x * 16 + wave16(ms + i * 500, 2400, 8), y16, 7 + i % 3 * 2,
          i % 2 ? rgb565(240, 110, 150) : rgb565(220, 50, 80));
  }
  r.alpha = 255;
}

// Zs drifting up and right from beside its head, each for 2.4 s, a new
// one every 0.8 s, growing from 7 to 16 px tall by sixteenths of a pixel,
// fading in over its first 200 ms and out to nothing by its last, so none
// pops in or off.
void zs(Raster& r, const rig::Anchors& at, int ms) {
  for (int i = 0; i < 3; ++i) {
    const int age = (ms + i * 800) % 2400;
    r.alpha = std::min(age * 255 / 200, 255 - age * 255 / 2400);
    r.zee(at.brimR.x + 25 * 16 + age * 16 / 40, at.brimR.y - 5 * 16 - age * 16 / 20 - age * 5 * 16 / 2400,
          7 * 16 + age * 9 * 16 / 2400, kCream);
  }
  r.alpha = 255;
}

// Drawing behind what's drawn: only onto the background's black, above
// the lane, at a fade, and the pixels it drew marked for the next clear.
struct Behind {
  Surface& s;
  int fade, bottom = s.height * 4 / 5;
  int x0 = s.width, y0 = bottom, x1 = -1, y1 = -1;
  void dot(int x, int y, uint16_t ink, int alpha) {
    if (x < 0 || y < 0 || x >= s.width || y >= bottom || alpha * fade < 255 * 3) return;
    uint16_t& p = s.pixels[y * s.width + x];
    if (p) return;
    p = mix565(0, ink, alpha * fade / 255);
    x0 = std::min(x0, x), x1 = std::max(x1, x), y0 = std::min(y0, y), y1 = std::max(y1, y);
  }
  // Each pixel in the box (sixteenths) at `cover`'s coverage of its middle,
  // 0 … 256.
  template <typename Cover>
  void fill(int bx0, int by0, int bx1, int by1, uint16_t ink, Cover cover) {
    for (int y = by0 / 16; y <= by1 / 16; ++y)
      for (int x = bx0 / 16; x <= bx1 / 16; ++x)
        if (const int a = cover(x * 16 + 8, y * 16 + 8)) dot(x, y, ink, a * 255 / 256);
  }
  ~Behind() {
    if (x1 >= 0) s.touch(x0, y0, x1 + 1, y1 + 1);
  }
};
// How far inside a circle about the origin a point is, as coverage: 0 … 16.
int inside(int dx, int dy, int radius) {
  return std::clamp((radius * radius - dx * dx - dy * dy) / (2 * radius) + 8, 0, 16);
}

// The night sky: a crescent moon high on its left and stars about it,
// each twinkling on a slow wave of its own.
void nightSky(Behind& b, int ms) {
  const Surface& s = b.s;
  // The moon: a disk with a smaller one cut from its upper right (sixteenths).
  const int mx = s.width * 13 * 16 / 100, my = s.height * 15 * 16 / 100, mr = s.width * 6 * 16 / 100;
  const int cx = mx + mr * 42 / 100, cy = my - mr * 25 / 100, cr = mr * 84 / 100;
  b.fill(mx - mr, my - mr, mx + mr, my + mr, kMoonlight,
         [&](int x, int y) { return inside(x - mx, y - my, mr) * (16 - inside(x - cx, y - cy, cr)); });
  // The stars: where each is (hundredths of the surface), how long its
  // rays reach, and a twinkle between dim and bright.
  static constexpr int8_t kStars[][3] = {{27, 7, 3},  {41, 3, 2}, {65, 6, 2}, {80, 13, 3}, {93, 29, 2},
                                         {89, 51, 3}, {5, 35, 2}, {9, 58, 3}, {23, 25, 2}};
  constexpr uint16_t kStarlight = rgb565(222, 230, 255);
  for (int i = 0; i < int(sizeof kStars / sizeof kStars[0]); ++i) {
    const int x = s.width * kStars[i][0] / 100, y = s.height * kStars[i][1] / 100, reach = kStars[i][2];
    const int glow = 110 + wave(ms + i * 737, 2600 + i * 190, 145);
    b.dot(x, y, kStarlight, glow);
    for (int d = 1; d <= reach; ++d) {
      const int a = glow * (reach + 1 - d) / (reach + 1);
      b.dot(x - d, y, kStarlight, a), b.dot(x + d, y, kStarlight, a), b.dot(x, y - d, kStarlight, a),
          b.dot(x, y + d, kStarlight, a);
    }
  }
}

// The morning's sun, up in the sky on its left where night's moon is: a
// pale core warming to an amber rim in a soft glow, and eight rounded rays
// off its rim, the long and the short in turn, breathing out and in
// against each other every 3 s as the ring of them turns once in 24 s.
void sun(Behind& b, int ms) {
  const Surface& s = b.s;
  // Its middle, its radius and the glow's reach (sixteenths).
  const int sx = s.width * 14 * 16 / 100, sy = s.height * 19 * 16 / 100, sr = s.width * 5 * 16 / 100;
  const int reach = sr * 9 / 5;
  const int64_t reach2 = int64_t(reach) * reach;
  constexpr uint16_t kCore = rgb565(255, 248, 220), kMid = rgb565(255, 208, 100), kRim = rgb565(255, 150, 64),
                     kGlow = rgb565(255, 160, 70);
  // The disk and its glow by the square of the distance from its middle,
  // worked out once for its radius: a lookup a pixel after that.
  constexpr int kSteps = 512;
  static uint16_t shade[kSteps];
  static int shadeFor = 0;
  if (shadeFor != sr) {
    for (int i = 0; i < kSteps; ++i) {
      // Its distance (sixteenths), the square root of the step's square, a bit at a time.
      uint32_t n = uint32_t(i * reach2 / (kSteps - 1)), root = 0;
      for (uint32_t bit = 1u << 30; bit; bit >>= 2)
        if (n >= root + bit)
          n -= root + bit, root = (root >> 1) + bit;
        else
          root >>= 1;
      const int d = int(root);
      // The glow: whole under the disk, falling off past its rim, at most 55%.
      const int g = d <= sr ? 256 : std::max(0, 256 - (d - sr) * 256 / (reach - sr));
      uint16_t c = mix565(0, kGlow, g * g / 256 * 140 / 256);
      // The disk over it, its edge smoothed: core to amber out to its rim.
      if (const int cover = std::clamp((sr - d + 8) * 16, 0, 256)) {
        const int t = std::min(256, d * 256 / sr);
        const uint16_t disk = t < 141 ? mix565(kCore, kMid, t * 255 / 141) : mix565(kMid, kRim, (t - 141) * 255 / 115);
        c = mix565(c, disk, cover * 255 / 256);
      }
      shade[i] = c;
    }
    shadeFor = sr;
  }
  const uint64_t perStep = (uint64_t(kSteps - 1) << 32) / uint64_t(reach2);
  auto shadeAt = [&](int x, int y) -> uint16_t {
    const int dx = x - sx, dy = y - sy;
    const int64_t d2 = int64_t(dx) * dx + int64_t(dy) * dy;
    return d2 < reach2 ? shade[uint64_t(d2) * perStep >> 32] : 0;
  };
  // The rays first, each a round-ended bar over the glow, from amber to
  // orange along it; the disk and glow then fill in about them.
  const int spin = ms % 24000 * 4096 / 24000, breath = sinTurn(ms % 3000 * 4096 / 3000);
  const int from = sr * 135 / 100, half = sr * 85 / 1000;
  for (int i = 0; i < 8; ++i) {
    const int angle = spin + i * 512, out = i % 2 ? -breath : breath;  // Q12
    const int len = sr * (i % 2 ? 42 : 70) / 100 * (4096 + out * 12 / 100) / 4096;
    const int cx = sinTurn(angle + 1024), cy = sinTurn(angle);
    const int ax = sx + from * cx / 4096, ay = sy + from * cy / 4096;
    const int bx = sx + (from + len) * cx / 4096, by = sy + (from + len) * cy / 4096;
    for (int y = (std::min(ay, by) - half) / 16; y <= (std::max(ay, by) + half) / 16; ++y)
      for (int x = (std::min(ax, bx) - half) / 16; x <= (std::max(ax, bx) + half) / 16; ++x) {
        // How far the pixel's middle is along the bar and from its spine.
        const int64_t vx = bx - ax, vy = by - ay, wx = x * 16 + 8 - ax, wy = y * 16 + 8 - ay;
        const int64_t k =
            std::clamp<int64_t>((wx * vx + wy * vy) * 4096 / std::max<int64_t>(1, vx * vx + vy * vy), 0, 4096);
        if (const int cover = inside(int(wx - vx * k / 4096), int(wy - vy * k / 4096), half) * 16)
          b.dot(x, y,
                mix565(shadeAt(x * 16 + 8, y * 16 + 8), mix565(kMid, kRim, int(k) * 255 / 4096), cover * 255 / 256),
                255);
      }
  }
  for (int y = (sy - reach) / 16; y <= (sy + reach) / 16; ++y)
    for (int x = (sx - reach) / 16; x <= (sx + reach) / 16; ++x)
      if (const uint16_t c = shadeAt(x * 16 + 8, y * 16 + 8)) b.dot(x, y, c, 255);
}

// Its morning coffee: a mug held in a little gel hand at its right side,
// steam curling up off it, lifted to its mouth for a sip once every
// OutfitLayer::kSipMs (`ms` into the engine's clock).
void coffee(Raster& r, const rig::Anchors& at, int ms) {
  const int d = std::max(16, at.eyeR.x - at.eyeL.x), mw = d * 36 / 100, mh = d * 39 / 100;
  // Where it rests and where it's sipped from, the mug's middle, and how
  // far up between them it is: up over 500 ms, held 800, down over 500.
  const Point rest{at.handF.x + d * 70 / 100, at.handF.y - d * 8 / 100};
  const Point sip{(at.eyeL.x + at.eyeR.x) / 2 + d * 16 / 100, (at.eyeL.y + at.eyeR.y) / 2 + d * 32 / 100};
  const int into = ms % OutfitLayer::kSipMs - (OutfitLayer::kSipMs - 1800);
  const int up = into < 0 ? 0 : into < 500 ? ease1000(into, 500) : into < 1300 ? 1000 : ease1000(1800 - into, 500);
  const int mx = rest.x + (sip.x - rest.x) * up / 1000, my = rest.y + (sip.y - rest.y) * up / 1000;
  const int top = my - mh / 2, bottom = my + mh / 2, l = mx - mw / 2, rt = mx + mw / 2, round = mw / 6;
  // The steam: three wisps, each rising from the rim for 1.8 s, swaying
  // as it goes and fading, none while it sips.
  if (!up)
    for (int i = 0; i < 3; ++i) {
      const int age = (ms + i * 600) % 1800, rise = mh * 3 / 2 * age / 1800;
      Point wisp[5];
      for (int k = 0; k < 5; ++k) {
        const int sway = (wave(ms + i * 400 + k * 260, 1200, mw / 5) - mw / 10) * (k + 1) / 5;
        wisp[k] = {mx + (i - 1) * mw / 4 + sway, top - mh / 10 - rise - k * mh / 7};
      }
      r.alpha = 190 - age * 180 / 1800;
      r.stroke16(wisp, 5, d / 20 + 8, kCream);
    }
  r.alpha = 255;
  // The handle, a loop off its right side.
  Point handle[9];
  for (int k = 0; k <= 8; ++k)  // from its top round to its bottom
    handle[k] = {rt + mw * 22 / 100 * turn((24 + k * 2) % 32).x / 4096,
                 my - mh / 10 + mh * 24 / 100 * turn((24 + k * 2) % 32).y / 4096};
  r.stroke16(handle, 9, mw / 7, kMug);
  // The mug, narrowing a little to its foot, with round corners there,
  // a cream band round it and the coffee in it.
  const Point body[] = {{l, top},
                        {rt, top},
                        {rt - mw / 20, bottom - round},
                        {rt - mw / 20 - round / 3, bottom - round / 4},
                        {rt - mw / 20 - round, bottom},
                        {l + mw / 20 + round, bottom},
                        {l + mw / 20 + round / 3, bottom - round / 4},
                        {l + mw / 20, bottom - round}};
  r.polygon16(body, 8, kMug);
  const int by0 = my - mh / 14, by1 = my + mh / 7;
  const Point band[] = {{l - mw, by0}, {rt + mw, by0}, {rt + mw, by1}, {l - mw, by1}};
  r.polygon16(band, 4, kCream, body, 8);
  r.round(l / 16 + 2, top / 16 - mh / 160, mw / 16 - 4, mh / 80 + 2, mh / 160 + 1, kCoffee);
  // The hand holding it, at its left side low down.
  r.disk16(l + mw / 12, my + mh / 5, mw / 4, kGel);
  r.alpha = 160;
  r.disk16(l + mw / 12 - mw / 14, my + mh / 5 - mw / 10, mw / 14, kShine);
  r.alpha = 255;
}

// What it wears besides where it sits: the hat, the party hat's colours,
// how far into its swing the nightcap is, on a step of kSwingMs (the hat's
// as one number), what's over its eyes, and the pyjamas that go with the
// nightcap.
struct Look {
  Outfit hat;
  int colors, swing;
  Eyewear eyes;
  bool pyjamas;
  uint32_t hatKey() const { return uint32_t(hat) | uint32_t(colors) << 4 | uint32_t(swing) << 8; }
};
// The nightcap's swing for the engine's clock.
int swingFor(const Engine& e) { return int(e.elapsedMs % 2000 / OutfitLayer::kSwingMs * OutfitLayer::kSwingMs); }
// Peekaboo's gesture takes it all off, and it sleeps with its eyes bare;
// the nightcap comes with its pyjamas, but while it wears its reading
// glasses.
Look lookFor(const Engine& e) {
  const uint32_t when = e.scenes.when;
  const SceneState state = e.scenes.route.state;
  if (state == SceneState::kGesture && e.scenes.variant == int(Gesture::kPeekaboo)) return {};
  const Outfit hat = outfitFor(when);
  const int colors = hasTag(when, "lunar") ? 1 : hasTag(when, "programmers") && !hasTag(when, "party") ? 2 : 0;
  const bool nightcap = hat == Outfit::kNightcap;
  const Eyewear eyes = state == SceneState::kAsleep ? Eyewear::kNone : eyewearFor(when);
  return {hat, hat == Outfit::kPartyHat ? colors : 0, nightcap ? swingFor(e) : 0, eyes,
          nightcap && eyes == Eyewear::kNone};
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
// The hat, on the brim's front; and the pyjamas, on the hem's front, or else
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
  // How far the body has moved it since it was kept, in sixteenths, by the
  // anchor it rides, and the most any other is off once it's moved that
  // far: how far its shape has changed. Still, it's drawn afresh unless it
  // moved whole pixels and kept its shape.
  int ox = 0, oy = 0, off = INT_MAX;
  if (kept.valid && kept.look == look) {
    ox = now[0].x - kept.at[0].x, oy = now[0].y - kept.at[0].y;
    off = 0;
    for (int i = 0; i < n; ++i)
      off = std::max({off, std::abs(now[i].x - kept.at[i].x - ox), std::abs(now[i].y - kept.at[i].y - oy)});
  }
  const bool whole = off == 0 && ox % 16 == 0 && oy % 16 == 0;
  if (!whole && !(moving && off <= OutfitLayer::kSlack)) {
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
  r.replay16(kept.shapes, kept.dx * 16 + ox, kept.dy * 16 + oy);
}

// The worn and hat layers' contents for a look, and the look a pair of
// them is, its nightcap swinging on the engine's clock.
constexpr uint32_t kPyjamas = 1u << 8;  // a worn content no eyewear has
uint32_t hatOf(const Look& l) { return l.hat == Outfit::kNone ? 0 : uint32_t(l.hat) | uint32_t(l.colors) << 4; }
uint32_t wornOf(const Look& l) { return l.pyjamas ? kPyjamas : uint32_t(l.eyes); }
Look lookOf(uint32_t hat, uint32_t worn, const Engine& e) {
  const Outfit kind = Outfit(hat & 15);
  return {kind, int(hat >> 4 & 15), kind == Outfit::kNightcap ? swingFor(e) : 0,
          worn == kPyjamas ? Eyewear::kNone : Eyewear(worn), worn == kPyjamas};
}

// The pyjamas or what's over its eyes, then the hat, each at its layer's
// fade.
void outfit(Raster& r, const Engine& e, const rig::Anchors& at, const Look& look, int wornFade, int hatFade) {
  constexpr int kEnd = rig::Anchors::kRingPoints - 1;
  r.fade = wornFade;
  if (look.pyjamas) {
    const Point now[] = {at.hem[kEnd / 2], at.hem[0], at.hem[kEnd], at.lap[0], at.lap[kEnd / 2], at.lap[kEnd]};
    wear(r, keptWorn, e, at, now, 6, 1u << 8, pyjamas);  // a look no eyewear has
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
  const uint32_t when = e.scenes.when;
  const SceneState state = e.scenes.route.state;
  const bool night = hasTag(when, "night"), morning = hasTag(when, "morning");
  const bool zs = night && state == SceneState::kAsleep;
  // Coffee while it's idle or at work in the morning, so not asleep, nor
  // in a gesture or a reaction's look.
  const bool awake = state == SceneState::kIdle || state == SceneState::kWorking;
  const uint32_t scene = night ? kNightSky : morning ? kSun : 0;
  return {scene, wornOf(look), hatOf(look), airFor(when), zs ? kZs : morning && awake ? kCoffeeMug : 0};
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
  const uint32_t beside = content(Layer::kBeside, now.beside);
  if (beside == kZs) zs(r, at, ms);
  if (beside == kCoffeeMug) coffee(r, at, ms);
}

void paintSky(Surface& s, const Engine& e, const rig::Layers* layers, uint32_t t) {
  if (!s.pixels) return;
  using rig::Layer;
  const uint32_t scene = layers ? layers->content(Layer::kScene, t) : layerContents(e).scene;
  if (!scene) return;
  Behind behind{s, layers ? (layers->opacity(Layer::kScene, t) * 255 + 500) / 1000 : 255};
  const int ms = int(e.elapsedMs % 3600000u);
  if (scene == kNightSky) nightSky(behind, ms);
  if (scene == kSun) sun(behind, ms);
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
