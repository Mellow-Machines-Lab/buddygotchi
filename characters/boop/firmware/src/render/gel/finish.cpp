// The gel's finishes (render/gel/finish.h): integer and deterministic, a
// pure function of how far into the finish it is, so the board, the
// simulator and the Mac's mirror draw the same frame at the same time.
#include "render/gel/finish.h"
#include <algorithm>
#include <cstdlib>
#include <iterator>
#include <utility>
#include "render/gel/frame.h"
#include "render/gel/lane.h"
#include "render/gel/raster.h"
#include "render/gel/scenes.h"
namespace render::gel {
namespace {
// Colours: the finish's golds and its outline, cream, the confetti's six
// and the jelly's blue.
// The flood's two golds are at 70% of the trophy's: it fills most of the
// panel, and at full strength it's a flash in a dark room (and at night,
// half of that). On it the trophy takes a darker, wider outline.
constexpr uint16_t kGold = rgb565(255, 201, 60), kGoldDeep = rgb565(255, 176, 32), kOutline = rgb565(122, 74, 0),
                   kFloodGold = rgb565(178, 140, 42), kFloodGoldDeep = rgb565(178, 123, 22),
                   kNightGold = rgb565(89, 70, 21), kNightGoldDeep = rgb565(89, 62, 11), kOutlineOnGold = rgb565(90, 51, 0),
                   kCream = rgb565(255, 244, 199),
                   kWhite = rgb565(255, 255, 255);
constexpr uint16_t kConfettiInk[] = {rgb565(255, 213, 74),  rgb565(255, 122, 182), rgb565(92, 225, 230),
                                     rgb565(140, 242, 122), rgb565(255, 255, 255), rgb565(181, 140, 255)};
constexpr int kInks = int(std::size(kConfettiInk));

// Keyframes, eased between: (time, value) pairs in order.
struct Key {
  int t, v;
};
template <size_t N>
int keys(const Key (&k)[N], int t) {
  if (t <= k[0].t) return k[0].v;
  for (size_t i = 1; i < N; ++i)
    if (t <= k[i].t) return lerp(k[i - 1].v, k[i].v, ease(t, k[i - 1].t, k[i].t));
  return k[N - 1].v;
}
F seconds(int ms) { return F::ratio(ms, 1000); }
// e^-x for x >= 0: the series converges only for small x, so the
// reciprocal of e^x, and nothing past 12.
F decay(F x) { return x <= F(0) ? F(1) : x > F(12) ? F(0) : F(1) / exp(x); }
// An angle in radians as a turn's 4096ths (4096 / 2π, Q16).
int turnOf(F rad) { return int((rad.raw * 42722830) >> 40); }
int sin12(F x) { return sinTurn(turnOf(x)); }
F lsin(F x) { return F::fromRaw(int64_t(sin12(x)) << 12); }
F lcos(F x) { return F::fromRaw(int64_t(sinTurn(turnOf(x) + 1024)) << 12); }
// A length in px as sixteenths of a pixel.
int px16(F v) { return int(v.raw >> (F::bits - 4)); }
// A body's height scale (Q12) as PaintControls' squash.
int squashFor(int sy) { return (sy - 4096) * 4096 / 2130; }

// One hop: squat, launch, the air (a parabola, stretched going up and
// coming down), and a wobbling landing. Its height in px, up negative, and
// its height scale (Q12).
struct Hop {
  int dy = 0, sy = 4096;
};
constexpr int kSquatMs = 160, kLandMs = 500;
Hop hop(int t, int at, int height, int airMs) {
  const int d = t - at;
  if (d < 0) return {};
  if (d < kSquatMs) return {0, 4096 - 737 * ease(d, 0, kSquatMs) / 4096};
  if (d < kSquatMs + airMs) {
    const int p = (d - kSquatMs) * 4096 / airMs;
    const int y = -int(int64_t(height) * 4 * p * (4096 - p) / (4096 * 4096));
    return {y, p < 2048 ? lerp(4751, 4178, p * 2) : lerp(4178, 4424, (p - 2048) * 2)};
  }
  const int p = std::min(d - kSquatMs - airMs, kLandMs);
  if (p >= kLandMs) return {};
  const F s = seconds(p);
  return {0, 4096 - 901 * scalar(decay(s * 12) * lcos(s * 36)) / 4096};
}
// The latest hop under way wins.
template <size_t N>
Hop hops(const Hop (&h)[N]) {
  Hop out;
  for (const auto& one : h)
    if (one.dy || one.sy != 4096) out = one;
  return out;
}
// When a hop that squats at `at` lands.
constexpr int landing(int at, int airMs) { return at + kSquatMs + airMs; }

Frame turned(int x16, int y16, int scale, F angle) { return {x16, y16, scale, sin12(angle + pi / 2), sin12(angle)}; }

// A sparkle: a four-pointed star, `r` px from its middle.
// Small shapes straight onto the surface, a pixel's coverage from four
// samples of it: a polygon's exact area (Raster::polygon16) costs more to
// set up than a confetti piece or a spark takes to fill, and they're
// dozens a frame. Each blends at the raster's opacity, above the lane.
void plot(Raster& r, int x, int y, int cover, uint16_t ink) {
  auto& out = r.s.pixels[y * r.s.width + x];
  const int a = r.alpha * cover / 256;
  if (a >= 253)
    out = ink;
  else if (a > 2)
    out = mix565(out, ink, a);
}
// A convex polygon (at most 64 corners, either way round), in sixteenths of
// a pixel: two sample rows a pixel row, each the span between where its
// edges cross it; the pixels inside both spans filled as a run, those at
// their ends by how many of their four samples are in.
void convex16(Raster& r, const Point* v, int n, uint16_t ink) {
  if (r.alpha <= 2 || !r.s.pixels || n < 3) return;
  int minY = v[0].y, maxY = v[0].y;
  for (int i = 1; i < n; ++i) minY = std::min(minY, v[i].y), maxY = std::max(maxY, v[i].y);
  const int y0 = std::max(0, minY >> 4), y1 = std::min(r.s.height * 4 / 5 - 1, maxY >> 4), w = r.s.width;
  const int whole = r.alpha;
  for (int y = y0; y <= y1; ++y) {
    int from[2], to[2];
    for (int half = 0; half < 2; ++half) {
      const int sy = y * 16 + 4 + half * 8;
      int lo = 1 << 30, hi = -(1 << 30);
      for (int k = 0; k < n; ++k) {
        const Point a = v[k], b = v[k + 1 < n ? k + 1 : 0];
        if ((a.y <= sy) == (b.y <= sy)) continue;  // doesn't cross this sample row
        // In 32 bits while it fits, so the board divides in hardware.
        const int dy = sy - a.y, dx = b.x - a.x;
        const int x = a.x + (std::abs(dy) < 32768 && std::abs(dx) < 32768 ? dy * dx / (b.y - a.y)
                                                                          : int(int64_t(dy) * dx / (b.y - a.y)));
        lo = std::min(lo, x), hi = std::max(hi, x);
      }
      from[half] = lo, to[half] = hi;
    }
    const int left = std::max(0, std::min(from[0], from[1]) >> 4), right = std::min(w - 1, std::max(to[0], to[1]) >> 4);
    if (left > right) continue;
    // Pixels whose four samples are all in: from the first whose left
    // samples clear both spans' starts to the last whose right ones do.
    const int inL = std::max(left, (std::max(from[0], from[1]) - 4 + 15) >> 4),
              inR = std::min(right, (std::min(to[0], to[1]) - 12) >> 4);
    uint16_t* out = r.s.pixels + y * w;
    auto edge = [&](int x) {
      int in = 0;
      for (int half = 0; half < 2; ++half)
        for (const int sx : {x * 16 + 4, x * 16 + 12}) in += sx >= from[half] && sx <= to[half];
      if (in) plot(r, x, y, in * 64, ink);
    };
    if (inL > inR) {
      for (int x = left; x <= right; ++x) edge(x);
    } else {
      for (int x = left; x < inL; ++x) edge(x);
      if (whole >= 253)
        std::fill(out + inL, out + inR + 1, ink);
      else
        for (int x = inL; x <= inR; ++x) out[x] = mix565(out[x], ink, whole);
      for (int x = inR + 1; x <= right; ++x) edge(x);
    }
    r.touch(left, y, right + 1, y + 1);
  }
}
void quad16(Raster& r, const Point (&v)[4], uint16_t ink) { convex16(r, v, 4, ink); }
// A dot `radius16` round: full inside half a pixel of its edge, nothing
// half a pixel out, and between by the square of its distance.
void dot16(Raster& r, int x16, int y16, int radius16, uint16_t ink) {
  if (r.alpha <= 2 || !r.s.pixels || radius16 <= 0) return;
  const int x0 = std::max(0, (x16 - radius16 - 8) >> 4), x1 = std::min(r.s.width - 1, (x16 + radius16 + 8) >> 4);
  const int y0 = std::max(0, (y16 - radius16 - 8) >> 4),
            y1 = std::min(r.s.height * 4 / 5 - 1, (y16 + radius16 + 8) >> 4);
  const int inner = std::max(0, radius16 - 8), outer = radius16 + 8;
  const int in2 = inner * inner, out2 = outer * outer;
  for (int y = y0; y <= y1; ++y) {
    int lo = 1 << 30, hi = -1;
    const int dy = y * 16 + 8 - y16;
    for (int x = x0; x <= x1; ++x) {
      const int dx = x * 16 + 8 - x16, d2 = dx * dx + dy * dy;
      if (d2 >= out2) continue;
      plot(r, x, y, d2 <= in2 ? 256 : (out2 - d2) * 256 / (out2 - in2), ink);
      lo = std::min(lo, x), hi = x;
    }
    if (hi >= lo) r.touch(lo, y, hi + 1, y + 1);
  }
}
// A sparkle: a four-pointed star `radius16` from its middle, two thin
// diamonds across each other.
void sparkle(Raster& r, int x16, int y16, int radius16, int alpha, uint16_t ink) {
  if (alpha <= 2 || radius16 <= 0) return;
  const int waist = radius16 * 22 / 100 * 2896 / 4096;  // the old star's waist
  r.alpha = std::min(255, alpha);
  quad16(r, {{x16, y16 - radius16}, {x16 + waist, y16}, {x16, y16 + radius16}, {x16 - waist, y16}}, ink);
  quad16(r, {{x16 - radius16, y16}, {x16, y16 - waist}, {x16 + radius16, y16}, {x16, y16 + waist}}, ink);
  r.alpha = 255;
}
// A polygon with an outline round it, `width16` wide: the outline's
// colour filled first a little larger, each corner moved out along its two
// edges' normals, then the shape over it; two fills, where a stroke would
// measure every pixel's distance to every edge.
void outlined(Raster& r, const Point* v, int n, uint16_t ink, uint16_t line, int width16, bool convex = false) {
  n = std::min(n, 16);
  int64_t area = 0;
  for (int i = 0; i < n; ++i) area += int64_t(v[i].x) * v[(i + 1) % n].y - int64_t(v[(i + 1) % n].x) * v[i].y;
  const int sign = area < 0 ? -1 : 1;
  auto normal = [&](Point a, Point b, int& nx, int& ny) {
    const int dx = b.x - a.x, dy = b.y - a.y, len = std::max(1, root(uint32_t(dx * dx + dy * dy)));
    nx = sign * dy * 1024 / len, ny = -sign * dx * 1024 / len;
  };
  Point grown[16];
  for (int i = 0; i < n; ++i) {
    int ax, ay, bx, by;
    normal(v[(i + n - 1) % n], v[i], ax, ay);
    normal(v[i], v[(i + 1) % n], bx, by);
    const int sx = ax + bx, sy = ay + by, len = std::max(1, root(uint32_t(sx * sx + sy * sy)));
    grown[i] = {v[i].x + sx * width16 / len, v[i].y + sy * width16 / len};
  }
  if (convex) {
    convex16(r, grown, n, line);
    convex16(r, v, n, ink);
  } else {
    r.polygon16(grown, n, line);
    r.polygon16(v, n, ink);
  }
}
// A five-pointed star in a frame, `R` and `rIn` units out, with an
// outline when given one.
void star(Raster& r, const Frame& f, int R, int rIn, uint16_t ink, int outline = -1) {
  Point v[11];
  for (int i = 0; i < 10; ++i) {
    const F a = -pi / 2 + pi * i / 5;
    const int len = i % 2 ? rIn : R;
    v[i] = f.at(len * sin12(a + pi / 2) / 4096, len * sin12(a) / 4096);
  }
  if (outline >= 0)
    outlined(r, v, 10, ink, uint16_t(outline), f.size16(3) / 2);
  else
    r.polygon16(v, 10, ink);
}
// The trophy: a gold cup with its handles, stem and foot, a star on it,
// standing on its foot's middle.
void trophy(Raster& r, const Frame& f, bool onGold = false) {
  const uint16_t outline = onGold ? kOutlineOnGold : kOutline;
  const int line = onGold ? f.size16(5) / 2 : f.size16(3) / 2;
  static constexpr int kCup[][2] = {{-30, -62}, {30, -62}, {29, -48},  {25, -36},  {18, -26}, {9, -19},
                                    {0, -16},   {-9, -19}, {-18, -26}, {-25, -36}, {-29, -48}};
  constexpr int n = int(std::size(kCup));
  Point cup[n];
  for (int i = 0; i < n; ++i) cup[i] = f.at(kCup[i][0], kCup[i][1]);
  // Each handle a band round its arc: outlined, then gold.
  for (int side : {-1, 1})
    for (const auto [half, ink] : {std::pair{4, outline}, std::pair{2, kGoldDeep}}) {
      Point band[14];
      for (int k = 0; k < 7; ++k) {
        const int a = -1024 + 2048 * k / 6, c = sinTurn(a + 1024), sn = sinTurn(a);
        band[k] = f.at(side * (27 + (13 + half) * c / 4096), -42 + (15 + half) * sn / 4096);
        band[13 - k] = f.at(side * (27 + (13 - half) * c / 4096), -42 + (15 - half) * sn / 4096);
      }
      r.polygon16(band, 14, ink);
    }
  outlined(r, cup, n, kGold, outline, line, true);
  const Point stem[] = {f.at(-6, -17), f.at(6, -17), f.at(6, -8), f.at(-6, -8)};
  const Point foot[] = {f.at(-20, -9), f.at(20, -9), f.at(20, 1), f.at(-20, 1)};
  for (const auto* part : {stem, foot}) outlined(r, part, 4, kGoldDeep, outline, line, true);
  Point shine[6];
  for (int k = 0; k < 6; ++k) {
    const F a = pi * k / 3;
    shine[k] = f.at(-14 + 4 * sin12(a + pi / 2) / 4096, -47 + 10 * sin12(a) / 4096);
  }
  r.alpha = 200;
  r.polygon16(shine, 6, kCream);
  r.alpha = 255;
  // The star on the cup, not its foot.
  const Point mid = f.at(0, -42);
  star(r, {mid.x, mid.y, f.scale, f.c12, f.s12}, 9, 4, kCream);
}
// Proud's bug, held up beside its trophy: the small one Boop caught.
void gift(Raster& r, const Surface& s) {
  auto x = [&](int p) { return s.width * p / 1000; };
  auto y = [&](int p) { return s.height * p / 1000; };
  const int bx = 795, by = 180;
  const uint16_t ink = rgb565(44, 37, 29), amber = rgb565(239, 189, 103);
  for (int side : {-1, 1}) {
    for (int row = -1; row <= 1; ++row)
      r.line({x(bx + side * 18), y(by + row * 16)}, {x(bx + side * 34), y(by + row * 20 + 6)}, 2, ink);
    r.line({x(bx + side * 6), y(by - 46)}, {x(bx + side * 16), y(by - 64)}, 2, ink);
  }
  r.disk(x(bx), y(by - 36), x(12), ink);
  r.round(x(bx - 24), y(by - 32), x(48), y(64), x(24), amber);
  r.round(x(bx - 2), y(by - 30), x(4), y(60), x(1), ink);
  for (const Point spot : {Point{-11, -12}, Point{11, -12}, Point{-12, 10}, Point{12, 10}})
    r.disk(x(bx + spot.x), y(by + spot.y), 2, ink);
}
// Confetti fired from (x0, y0) px at `at`: each piece off at its own angle
// about `dir` and speed, slowed by the air and falling, fluttering as it
// turns; gone by `lifeMs`, fading over its last half second.
void confetti(Raster& r, int age, int at, int x0, int y0, int count, uint32_t seed, F dir, F spread, int speed,
              int lifeMs = 2600) {
  const int d = age - at;
  if (d < 0 || d > lifeMs) return;
  const F t = seconds(d), drag = (F(1) - decay(t * q(1.6))) / q(1.6);
  Random rnd(seed);
  r.alpha = std::clamp((lifeMs - d) * 255 / 500, 0, 255);
  for (int i = 0; i < count; ++i) {
    const F a = dir + (rnd.unit() - q(.5)) * spread, v = F(speed) * (q(.55) + rnd.unit() * q(.6));
    const uint16_t ink = kConfettiInk[rnd.index(kInks)];
    const F wob = rnd.unit(), flap = rnd.unit(), spin = rnd.unit(), w = 12 + rnd.unit() * 5, h = 7 + rnd.unit() * 3;
    const F x = x0 + lcos(a) * v * drag + lsin(t * (5 + wob * 4) + i) * 10 * t;
    const F y = y0 + lsin(a) * v * drag + t * t * 90;
    const F flip = max(q(.12), abs(lcos(t * (8 + flap * 8) + i)));
    const Frame f = turned(px16(x), px16(y), 4096, t * (3 + spin * 5) + i);
    const int hw = scalar(w) / 2 / 4096, hh = std::max(1, scalar(h * flip) / 2 / 4096);
    quad16(r, {f.at(-hw, -hh), f.at(hw, -hh), f.at(hw, hh), f.at(-hw, hh)}, ink);
  }
  r.alpha = 255;
}
// The recipes: each finish's length, its reveal (the cheer, and where a
// `say` starts) and its landings, in the order of Finish after kLittle.
using slime::Contact;
constexpr F kStrong = q(.8);
#define AT(ms) T::literal(ms)
const slime::Recipe kFinishRecipes[kBigFinishes] = {
    // Confetti: Little Win's hop at its reveal, a second one later.
    {AT(3600),
     F(0),
     3,
     1,
     false,
     false,
     false,
     -1,
     {{AT(500), kSuccess, 0, kStrong},
      {AT(landing(340, 420)), kBody, 0, kStrong},
      {AT(landing(1500, 340)), kBody, 0, kStrong}}},
    // Gold Rush: the cheer as the gold floods in, and four landings.
    {AT(4600),
     F(0),
     5,
     1,
     false,
     false,
     false,
     -1,
     {{AT(300), kSuccess, 0, kStrong},
      {AT(landing(250, 550)), kBody, 0, kStrong},
      {AT(landing(1550, 380)), kBody, 0, kStrong},
      {AT(landing(2250, 380)), kBody, 0, kStrong},
      {AT(landing(2950, 320)), kBody, 0, kStrong}}},
};
#undef AT
}  // namespace

Point finishAnchor(const Surface& s) { return {s.width * 8, floorY(s) * 16}; }

FinishSize finishSize(int loops, int turn, int mood) {
  const bool sad = mood == slime::kSad || mood == slime::kWounded;
  if (sad) return FinishSize::kSmall;
  if (turn < 0) return FinishSize(std::clamp(loops - 1, 0, 2));
  if (turn >= kBigTier) return FinishSize::kBig;
  return turn >= kLongTier ? FinishSize::kMedium : FinishSize::kSmall;
}

const slime::Recipe& finishRecipe(Finish f) { return kFinishRecipes[std::clamp(int(f) - 1, 0, kBigFinishes - 1)]; }

FinishPose finishPose(const Surface& s, Finish f, int age, int reveal) {
  FinishPose p;
  auto body = [&](Hop h) {
    p.dy16 = h.dy * 16;
    p.squash = squashFor(h.sy);
  };
  switch (f) {
    case Finish::kLittle: body(hop(age, reveal - kSquatMs, 34, 400)); break;
    case Finish::kConfetti: body(hops({hop(age, reveal - kSquatMs, 40, 420), hop(age, reveal + 1000, 24, 340)})); break;
    case Finish::kGoldRush:
      // It steps back to make room for the party, and hops through it.
      p.scale = keys({{200, 4096}, {700, 3440}, {3900, 3440}, {4400, 4096}}, age);
      body(hops({hop(age, 250, 70, 550), hop(age, 1550, 34, 380), hop(age, 2250, 34, 380), hop(age, 2950, 22, 320)}));
      break;
    default: break;
  }
  return p;
}

// Gold Rush's flood, px: out from behind it, and back at the end.
int goldRadius(int age) { return keys({{300, 0}, {750, 430}, {3900, 430}, {4400, 0}}, age); }
// The gold disk `radius16` round (cx16, cy16) and its rays, a row at a
// time, each pixel written once: kRays deep wedges in the gold, the first
// from `turn` (a turn's 4096ths). Each row's ray edges are where the lines
// from the middle at their angles cross it; between them it's one gold or
// the other, and the disk's own ends are blended by how much they cover.
void goldBurst(Raster& r, int cx16, int cy16, int radius16, int turn, bool night) {
  if (!r.s.pixels || radius16 <= 0) return;
  constexpr int kRays = 18, kEdges = 2 * kRays, kStep = 4096 / kEdges;
  const uint16_t kGold = night ? kNightGold : kFloodGold, kGoldDeep = night ? kNightGoldDeep : kFloodGoldDeep;
  // Edge j starts wedge j: deep when j is even.
  auto ink = [&](int j) { return ((j % kEdges) + kEdges) % 2 ? kGold : kGoldDeep; };
  int sn[kEdges], cs[kEdges];
  for (int j = 0; j < kEdges; ++j) sn[j] = sinTurn(turn + j * kStep), cs[j] = sinTurn(turn + j * kStep + 1024);
  const int w = r.s.width, y0 = std::max(0, (cy16 - radius16) >> 4),
            y1 = std::min(r.s.height * 4 / 5 - 1, (cy16 + radius16) >> 4);
  const int64_t r2 = int64_t(radius16) * radius16;
  for (int y = y0; y <= y1; ++y) {
    int dy = y * 16 + 8 - cy16;
    if (!dy) dy = 1;  // the middle row, as the one just under it
    const int64_t room = r2 - int64_t(dy) * dy;
    if (room <= 0) continue;
    const int half = root(uint32_t(std::min<int64_t>(room, 0xffffffff))), left16 = cx16 - half, right16 = cx16 + half;
    const int xl = std::max(0, left16 >> 4), xr = std::min(w - 1, (right16 - 1) >> 4);
    if (xl > xr) continue;
    // The edges this row's half of the disk has, by where they cross it.
    int at[kEdges], edge[kEdges], n = 0;
    for (int j = 0; j < kEdges; ++j) {
      if ((sn[j] > 0) != (dy > 0) || !sn[j]) continue;
      // A row's offset is under 2^14 and a Q12 cosine at most 2^12, so this
      // fits an int: a 64-bit division here is 18 a row, in software on the
      // board.
      const int x = std::clamp(cx16 + dy * cs[j] / sn[j], -(1 << 24), 1 << 24);
      int k = n++;
      for (; k > 0 && at[k - 1] > x; --k) at[k] = at[k - 1], edge[k] = edge[k - 1];
      at[k] = x, edge[k] = j;
    }
    // Below the middle, the angle grows leftward; above it, rightward:
    // the wedge right of an edge is the one before it, or its own.
    uint16_t* out = r.s.pixels + y * w;
    const int before = dy > 0 ? -1 : 0;
    int k = 0, x = xl;
    uint16_t colour = n ? ink(edge[0] + (dy > 0 ? 0 : -1)) : kGold;
    while (x <= xr) {
      while (k < n && at[k] <= x * 16 + 8) colour = ink(edge[k] + before), ++k;
      const int stop = std::min(xr, k < n ? ((at[k] - 8) >> 4) : xr);
      std::fill(out + x, out + std::max(x, stop) + 1, colour);
      x = std::max(x, stop) + 1;
    }
    // The disk's ends, by how much of each pixel they cover.
    for (const int end : {xl, xr}) {
      const int cover = std::clamp(std::min(right16, end * 16 + 16) - std::max(left16, end * 16), 0, 16) * 16;
      if (cover < 256) out[end] = mix565(0, out[end], cover >= 253 ? 255 : cover);
    }
    r.touch(xl, y, xr + 1, y + 1);
  }
}
int finishCovers(const Surface& s, Finish f, int age) {
  if (f != Finish::kGoldRush) return 0;
  // The farthest corner above the lane from the flood's middle.
  const int bottom = s.height * 4 / 5, cx = s.width / 2, cy = s.height * 560 / 1000;
  const int dx = std::max(cx, s.width - cx), dy = std::max(cy, bottom - cy);
  const int reach = root(uint32_t(dx * dx + dy * dy)) + 2;
  return goldRadius(age) >= reach ? bottom : 0;
}

void paintFinishBehind(Surface& s, Finish f, int age, int reveal, bool night) {
  (void)reveal;
  Raster r{s};
  if (f == Finish::kGoldRush) {
    // The gold floods out from behind it, its rays turning slowly, and
    // drains back at the end.
    const int radius = goldRadius(age);
    if (radius <= 0) return;
    const int cx = s.width * 8, cy = s.height * 560 / 1000 * 16;
    goldBurst(r, cx, cy, radius * 16, turnOf(seconds(age) * q(.35)), night);
  }
}

void paintFinishFront(Surface& s, Finish f, int age, int reveal, const rig::Anchors& at, int scale, bool gifted) {
  Raster r{s};
  const int w = s.width, h = s.height;
  // A ring of sparkles about the body, opening out, in the confetti's colours.
  auto ring = [&](int from, int lifeMs, int count, int cy) {
    const int d = age - from;
    if (d < 0 || d > lifeMs) return;
    const int alpha = keys({{0, 0}, {lifeMs / 6, 255}, {lifeMs, 0}}, d), out = 120 + d * 60 / 1000;
    for (int i = 0; i < count; ++i) {
      const F a = pi * 2 * i / count + q(.2);
      sparkle(r, w * 8 + out * 115 / 100 * sin12(a + pi / 2) / 256, cy * 16 + out * 75 / 100 * sin12(a) / 256, 11 * 16,
              alpha, kConfettiInk[i % kInks]);
    }
  };
  // Sparkles twinkling here and there, `from` to `to`.
  auto twinkle = [&](int count, uint32_t seed, int from, int to, uint16_t ink, int maxY) {
    if (age < from || age > to) return;
    Random rnd(seed);
    const int fade = keys({{from, 0}, {from + 200, 4096}, {to - 300, 4096}, {to, 0}}, age);
    for (int i = 0; i < count; ++i) {
      const int x = 30 + rnd.index(440), y = 20 + rnd.index(std::max(1, maxY - 20));
      const int glow = std::max(0, sin12(seconds(age) * 5 + rnd.unit() * 6));
      sparkle(r, (x * w / 502) * 16, (y * h / 410) * 16, 11 * 16, glow * 255 / 4096 * fade / 4096, ink);
    }
  };
  switch (f) {
    case Finish::kLittle:
    case Finish::kConfetti: {
      // A little trophy pops up over its head as it lands, and goes.
      const int up = reveal + 420, gone = reveal + 2400;
      if (age > up && age < gone) {
        const int p = ease(age, up, up + 300), back = 4096 - ease(age, gone - 400, gone);
        const int pop = p + 1100 * sin12(F::ratio(p, 4096) * pi) / 4096;  // past its size, and back
        trophy(r, {at.crown.x, at.crown.y - 6 * 16 - 26 * p / 4096 * 16, 2900 * pop / 4096 * back / 4096});
      }
      ring(reveal + 350, 1100, 8, h * 470 / 1000);
      if (gifted) gift(r, s);
      if (f == Finish::kConfetti) {
        for (int i = 0; i < 2; ++i) {
          confetti(r, age, reveal + 900 * i, 0, h, 30 - 10 * i, 3 + 2 * i, -q(1.0), q(.7), 600 - 60 * i, 2000);
          confetti(r, age, reveal + 900 * i, w, h, 30 - 10 * i, 4 + 2 * i, -pi + q(1.0), q(.7), 600 - 60 * i, 2000);
        }
      }
      break;
    }
    case Finish::kGoldRush: {
      // The trophy drops onto its head as it lands from its leap, and rides
      // it; confetti cannons from both corners, twice.
      if (age > 700 && age < 4300) {
        const int drop = age < 1000
                             ? -150 + 150 * ease(age, 700, 1000) / 4096
                             : scalar(decay(seconds(age - 1000) * 6) * lsin(seconds(age - 1000) * 20) * 6) / 4096;
        const int shrink = 4096 - ease(age, 3900, 4300);
        trophy(r,
               turned(at.crown.x, at.crown.y + (8 + drop) * 16 * scale / 4096, 3700 * scale / 4096 * shrink / 4096,
                      lsin(seconds(age) * 6) / 16),
               true);
      }
      confetti(r, age, 700, 0, h, 24, 3, -q(1.0), q(.7), 620);
      confetti(r, age, 700, w, h, 24, 4, -pi + q(1.0), q(.7), 620);
      confetti(r, age, 1600, 0, h, 8, 5, -q(1.15), q(.5), 470);
      confetti(r, age, 1600, w, h, 8, 6, -pi + q(1.15), q(.5), 470);
      twinkle(5, 40, 700, 3900, kWhite, 230);
      break;
    }
    default: break;
  }
}
}  // namespace render::gel
