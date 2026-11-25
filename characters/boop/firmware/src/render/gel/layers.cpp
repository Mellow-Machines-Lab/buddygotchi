#include "render/gel/layers.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <initializer_list>

#include "render/font.h"
#include "render/gel/engine.h"
#include "render/gel/hands.h"
#include "render/gel/lane.h"
#include "render/gel/painter.h"
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
// The pale gold of a wish's sparks.
constexpr uint16_t kMoonlight = rgb565(250, 230, 160);

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

// A heart about (x16, y16), sixteenths of a pixel, `s` whole pixels its
// half-width.
void heart(Raster& r, int x16, int y16, int s, uint16_t ink) {
  const int half = s / 2 * 16, lobe = std::max(1, s / 2) * 16 + 8;
  r.disk16(x16 - half + 8, y16 + 8, lobe, ink);
  r.disk16(x16 + half + 8, y16 + 8, lobe, ink);
  const Point v[] = {{x16 - s * 16 + 8, y16 + 24}, {x16 + s * 16 + 8, y16 + 24}, {x16 + 8, y16 + (s + s / 2) * 16 + 8}};
  r.polygon16(v, 3, ink);
}

// The wish's icons in its thought bubble, about (cx, cy), whole pixels.
void wishIcon(Raster& r, const WishShow& wish, int cx, int cy, uint16_t ink) {
  switch (wish.kind) {
    case WishShow::kPet: {  // an open hand: a palm and four fingers
      r.round(cx - 9, cy - 1, 18, 13, 5, ink);
      for (int i = 0; i < 4; ++i) r.line({cx - 7 + i * 5, cy + 1}, {cx - 7 + i * 5, cy - 11 + (i == 0 || i == 3 ? 3 : 0)}, 4, ink);
      break;
    }
    case WishShow::kChat:  // a speech dot: three in a row
      for (int i = -1; i <= 1; ++i) r.disk(cx + i * 10, cy, 4, ink);
      break;
    case WishShow::kWork:  // a little laptop: its screen and its base
      r.ring(cx - 11, cy - 10, 22, 15, 3, 3, ink);
      r.round(cx - 15, cy + 7, 30, 4, 2, ink);
      break;
    case WishShow::kNone:
      break;
  }
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

// Listening to you speak: a gel hand cupped at its ear on `side` (-1 left,
// 1 right), and three rings beside it, each swelling out and fading on the
// 1.6 s beat of its nod, `ms` into it.
void speakingHand(Raster& r, const rig::Anchors& at, int side, int ms) {
  const Hand hand = cupped(at, side);
  const int hx = hand.x16 / 16, hy = hand.y16 / 16;
  r.alpha = 255;
  if (handsPlan().has(side, HandsAt::kEar)) paintHand(r, hand);
  const int beat = ms % 1600;
  for (int i = 0; i < 3; ++i) {
    const int age = (beat + 1600 - i * 330) % 1600, radius = 26 + i * 11 + age * 12 / 1600;
    r.alpha = std::max(0, 255 - age * 255 / 1600);
    // A third of a turn about the hand, facing out: turn() counts
    // thirty-seconds clockwise from the right.
    Point arc[11];
    for (int k = 0; k < 11; ++k) {
      const Point p = turn((side > 0 ? 32 : 16) + k - 5);
      arc[k] = {hx * 16 + radius * p.x / 256, hy * 16 + radius * p.y / 256};
    }
    r.stroke16(arc, 11, 3 * 16, kShine);
  }
  r.alpha = 255;
}

// Typing along with you: on each of the paws' beats, a key's tick beside
// the paw that taps, three short strokes bursting out and up from it and
// fading by its next tap, the left's and the right's in turn; brighter and
// longer typing fast. `phase` is briskLift's, 0 … 2 kBeat.
void typingTicks(Raster& r, const rig::Anchors& at, int phase, bool fast) {
  for (int side = -1; side <= 1; side += 2) {
    const int p = (phase + (side > 0 ? kBeat : 0)) % (2 * kBeat);  // 0 as this paw comes down
    const int age = p * 1000 / (2 * kBeat);                      // 0 … 1000 over its two beats
    if (age > 750) continue;
    // Just off its side, low, where the paws reach the keys.
    const Point edge = at.hem[side > 0 ? rig::Anchors::kRingPoints - 1 : 0];
    const int x = edge.x + side * 40 * 16, y = edge.y - 44 * 16;
    r.alpha = age < 350 ? 255 : std::max(0, 255 - (age - 350) * 255 / 400);
    const int reach = (fast ? 34 : 28) * (500 + age / 2) / 1000, from = 6 + reach / 2;  // px
    // Out to the side, out and up, and up: thirty-seconds of a turn from
    // the right, clockwise.
    const int dirs[3] = {side > 0 ? 0 : 16, side > 0 ? 28 : 20, 24};
    for (int k = 0; k < 3; ++k) {
      const Point d = turn(dirs[k]);
      Point line[2] = {{x + from * d.x / 256, y + from * d.y / 256},
                       {x + (from + reach) * d.x / 256, y + (from + reach) * d.y / 256}};
      r.stroke16(line, 2, 6 * 16, kCardInk);  // rimmed dark, to read over anything
      r.stroke16(line, 2, 3 * 16, kShine);
    }
  }
  r.alpha = 255;
}

// With you at the Mac (Engine::With): what it has on or beside it, each a
// drawn shape at the body's anchors, rimmed dark to read over anything.

// Where its ears would be: the brim ring's sides, at the height between the
// brim's front and its eyes (speaking's hand is held there too), px.
struct Ears {
  int left, right, y;
};
Ears ears(const rig::Anchors& at) {
  return {at.brimL.x / 16, at.brimR.x / 16, (at.brimF.y + at.eyeL.y) / 2 / 16};
}
// How far the body reaches either way, its widest across the rings the
// anchors know, px: what stands beside it stands clear of this.
struct Sides {
  int left, right;
};
Sides sides(const rig::Anchors& at) {
  Sides s{std::min(at.brimL.x, at.brimR.x) / 16, std::max(at.brimL.x, at.brimR.x) / 16};
  for (const Point& p : at.lap) s.left = std::min(s.left, p.x / 16), s.right = std::max(s.right, p.x / 16);
  for (const Point& p : at.hem) s.left = std::min(s.left, p.x / 16), s.right = std::max(s.right, p.x / 16);
  return s;
}

constexpr uint16_t kPhones = rgb565(236, 232, 244), kCushion = rgb565(70, 74, 104), kPageInk = rgb565(132, 140, 160);

// Headphones: a band over the top of its head from ear to ear, hugging the
// dome a little above it, and a cup over each ear.
void headphones(Raster& r, const rig::Anchors& at, int alpha) {
  const Ears e = ears(at);
  const int cx = (e.left + e.right) * 8, cy = e.y * 16;  // sixteenths
  const int rx = (e.right - e.left) * 8 + 2 * 16, ry = cy - at.crown.y + 6 * 16;
  Point band[17];
  for (int k = 0; k <= 16; ++k) {
    const Point p = turn(16 + k);  // from its left, over the top, to its right
    band[k] = {cx + rx * p.x / 4096, cy - 8 * 16 + ry * p.y / 4096};
  }
  r.alpha = alpha;
  r.stroke16(band, 17, 10 * 16, kCardInk);
  r.stroke16(band, 17, 6 * 16, kPhones);
  for (int side = -1; side <= 1; side += 2) {
    const int x = (side > 0 ? e.right : e.left) + side * 3, y = e.y;
    r.round(x - 10, y - 17, 20, 34, 9, kCardInk);
    r.round(x - 8, y - 15, 16, 30, 7, kPhones);
    r.round(x - 5 + side * 2, y - 11, 6, 22, 3, kCushion);
  }
  r.alpha = 255;
}

// Notes rising from the headphones while it grooves: one every 1.5 s from
// each cup in turn, drifting up and out over 2.4 s and fading on the way.
void notes(Raster& r, const rig::Anchors& at, uint32_t ms, int alpha) {
  constexpr int kEvery = 1500, kLife = 2400;
  const Ears e = ears(at);
  for (int i = 0; i < 2; ++i) {
    const int n = int(ms / kEvery) - i;
    if (n < 0) continue;
    const int age = int(ms - uint32_t(n) * kEvery);
    if (age >= kLife) continue;
    const int side = n % 2 ? 1 : -1;
    const int x = (side > 0 ? e.right : e.left) + side * (18 + age * 14 / kLife) + (age / 300 % 2 ? 2 : -2);
    const int y = e.y - 28 - age * 46 / kLife;
    r.alpha = alpha * std::min(255, std::min(age * 255 / 200, (kLife - age) * 255 / 900)) / 255;
    const bool two = n % 3 == 1;  // now and then a pair, beamed
    for (int pass = 0; pass < 2; ++pass) {
      const uint16_t ink = pass ? kPhones : kCardInk;
      const int grow = pass ? 0 : 2;
      r.disk(x - 4, y + 6, 5 + grow, ink);
      r.line({x, y + 6}, {x, y - 12}, 2 + 2 * grow, ink);
      if (two) {
        r.disk(x + 10, y + 3, 5 + grow, ink);
        r.line({x + 14, y + 3}, {x + 14, y - 15}, 2 + 2 * grow, ink);
        r.line({x, y - 12}, {x + 14, y - 15}, 4 + 2 * grow, ink);
      } else {
        r.line({x, y - 12}, {x + 7, y - 5}, 3 + 2 * grow, ink);
      }
    }
  }
  r.alpha = 255;
}

// A page beside it on the Mac's side, a little below its eyes, where it
// reads: lines of words scrolling up as you scroll, and the scroll bar's
// thumb going down with them.
void page(Raster& r, const Surface& s, const rig::Anchors& at, int side, int scroll, int alpha) {
  constexpr int kW = 58, kH = 74, kGap = 10, kLine = 10;
  const Ears e = ears(at);
  const Sides b = sides(at);
  const int y = e.y - 8, edge = s.inset(y, y + kH) + 4;
  const int x = std::clamp(side > 0 ? b.right + kGap : b.left - kGap - kW, edge, s.width - edge - kW);
  r.alpha = alpha;
  r.round(x - 2, y - 2, kW + 4, kH + 4, 7, kCardInk);
  r.round(x, y, kW, kH, 5, kCream);
  // The lines, cut to the page's inside.
  static constexpr int kLengths[] = {40, 32, 42, 24, 36, 42, 30, 18, 34, 41};
  r.bounds = {x + 4, y + 5, x + kW - 4, y + kH - 5};
  const int first = scroll / kLine, off = scroll % kLine;
  for (int i = 0; i < 8; ++i) {
    const int len = kLengths[(first + i) % 10];
    r.round(x + 6, y + 6 + i * kLine - off, len, 4, 2, kPageInk);
  }
  r.bounds = Raster::kEverywhere;
  const int thumb = scroll / 2 % (kH - 24);
  r.round(x + kW - 7, y + 4 + thumb, 4, 18, 2, kGel);
  r.alpha = 255;
}

// A video's light: the colour its screen shows now, a new scene every
// 2.6 s, crossing over 0.5 s.
uint16_t sceneLight(uint32_t ms) {
  static constexpr uint16_t kScenes[] = {rgb565(255, 168, 92), rgb565(214, 120, 236), rgb565(120, 232, 168),
                                         rgb565(255, 236, 200)};
  constexpr uint32_t kHold = 2600, kCross = 500;
  const uint32_t n = ms / kHold, into = ms % kHold;
  const uint16_t now = kScenes[n % 4];
  if (into >= kCross || !n) return now;
  return mix565(kScenes[(n + 3) % 4], now, int(into * 255 / kCross));
}

// The screen's light on its body: the light added to each pixel of the
// body by how bright it is, so the dark eyes and mouth keep their shape,
// strongest on the side the screen is on. Only what's drawn (not the
// black round it) and above the lane.
void screenLight(Surface& s, const rig::Anchors& at, int side, uint16_t light, int alpha) {
  int x0 = at.crown.x / 16, x1 = x0, y1 = at.crown.y / 16;
  for (const Point& p : at.hem) x0 = std::min(x0, p.x / 16), x1 = std::max(x1, p.x / 16), y1 = std::max(y1, p.y / 16);
  for (const Point& p : at.lap) x0 = std::min(x0, p.x / 16), x1 = std::max(x1, p.x / 16);
  x0 = std::max(0, x0 - 24), x1 = std::min(s.width, x1 + 24);
  const int y0 = std::max(0, at.crown.y / 16 - 4);
  y1 = std::min({s.height * 4 / 5, y1 + 4, Surface::kTrackedRows});
  if (x1 <= x0) return;
  for (int y = y0; y < y1; ++y) {
    uint16_t* row = s.pixels + y * s.width;
    for (int x = x0; x < x1; ++x) {
      const uint16_t p = row[x];
      if (!p) continue;
      const int luma = ((p >> 11) * 2 * 77 + ((p >> 5) & 63) * 150 + (p & 31) * 2 * 29) >> 6;  // 0–255
      const int across = side > 0 ? (x - x0) * 255 / (x1 - x0) : (x1 - x) * 255 / (x1 - x0);
      const int a = alpha * across / 255 * luma / 255 * 230 / 255;
      if (a <= 0) continue;
      // Added, as light is: the gel brighter and warmer or cooler for it.
      const int r5 = std::min(31, (p >> 11) + (light >> 11) * a / 255);
      const int g6 = std::min(63, ((p >> 5) & 63) + ((light >> 5) & 63) * a / 255);
      const int b5 = std::min(31, (p & 31) + (light & 31) * a / 255);
      row[x] = uint16_t(r5 << 11 | g6 << 5 | b5);
    }
  }
}

// The screen it watches, beside it on the Mac's side at its eyes' height:
// lit in the scene's colour, a play mark on it.
void screen(Raster& r, const Surface& s, const rig::Anchors& at, int side, uint16_t light, int alpha) {
  constexpr int kW = 66, kH = 44, kGap = 10;
  const Sides b = sides(at);
  const int y = at.eyeL.y / 16 - kH / 2 - 10, edge = s.inset(y, y + kH) + 4;
  const int x = std::clamp(side > 0 ? b.right + kGap : b.left - kGap - kW, edge, s.width - edge - kW);
  r.alpha = alpha;
  r.round(x - 3, y - 3, kW + 6, kH + 6, 7, kCardInk);
  r.round(x, y, kW, kH, 4, mix565(light, kCardInk, 50));
  const int cx = x + kW / 2, cy = y + kH / 2;
  const Point play[] = {{cx - 8, cy - 12}, {cx + 13, cy}, {cx - 8, cy + 12}};
  r.polygon(play, 3, rgb565(255, 255, 255));
  // Its stand.
  r.round(cx - 3, y + kH + 3, 6, 5, 1, kCardInk);
  r.round(cx - 12, y + kH + 7, 24, 4, 2, kCardRim);
  r.alpha = 255;
}

// On a call: a muted mic by its ear on the Mac's side, where speaking's
// hand would be, held still.
void mutedMic(Raster& r, const rig::Anchors& at, int side, int alpha) {
  const Ears e = ears(at);
  const Sides b = sides(at);
  const int hx = (side > 0 ? b.right - 4 : b.left + 4) + side * 8, hy = e.y - 24;
  r.alpha = alpha;
  r.disk(hx, hy, 22, kCardInk);
  r.disk(hx, hy, 20, kCardRim);
  r.disk(hx, hy, 18, kCardInk);
  r.round(hx - 5, hy - 13, 10, 17, 5, kShine);
  Point cup[7];
  for (int k = 0; k < 7; ++k) {
    const Point p = turn(k * 16 / 6);  // its lower half, right round to left
    cup[k] = {hx * 16 + 10 * 16 * p.x / 4096, (hy - 4) * 16 + 10 * 16 * p.y / 4096};
  }
  r.stroke16(cup, 7, 3 * 16, kShine);
  r.line({hx, hy + 6}, {hx, hy + 11}, 3, kShine);
  r.line({hx - 5, hy + 12}, {hx + 5, hy + 12}, 3, kShine);
  // The slash, rimmed so it cuts across the mic.
  r.line({hx - 12, hy - 13}, {hx + 12, hy + 13}, 7, kCardInk);
  r.line({hx - 12, hy - 13}, {hx + 12, hy + 13}, 3, kShine);
  r.alpha = 255;
}

void paintWith(Surface& s, Raster& r, const Engine& e, const rig::Anchors& at, int ms) {
  const Engine::With& w = e.with;
  if (w.screen) {
    const uint16_t light = sceneLight(uint32_t(ms));
    screenLight(s, at, w.side, light, w.screen);
    screen(r, s, at, w.side, light, w.screen);
  }
  if (w.page) page(r, s, at, w.side, w.scroll, w.page);
  if (w.headphones) {
    headphones(r, at, w.headphones);
    if (w.notes) notes(r, at, w.notesMs, w.headphones);
  }
  if (w.muted) mutedMic(r, at, w.side, w.muted);
}

}  // namespace

int sleepyLids(const Engine& e) {
  if (e.energy != Energy::kTired) return 0;
  // They go as the face squashes shut, gone by when it's a line, and come
  // back as it wakes.
  const F open = max(0, 1 - e.face.shut.x / SemanticFace::kShutLine);
  return int((open.raw * kNightLids + F::scale / 2) / F::scale);
}

Contents layerContents(const Engine& e) {
  const bool zs = hasTag(e.scenes.when, "night") && e.scenes.route.state == SceneState::kAsleep;
  return {zs ? kZs : 0u};
}

void paintLayers(Surface& s, const Engine& e, const rig::Anchors& at, const rig::Layers* layers, uint32_t t) {
  if (!s.pixels) return;
  Raster r{s};
  const int ms = int(e.elapsedMs % 3600000u);
  // Each layer's content and fade: the stack's, or with none, whole in
  // what the engine's tags and state call for.
  using rig::Layer;
  const Contents now = layerContents(e);
  auto content = [&](Layer l, uint32_t whole) { return layers ? layers->content(l, t) : whole; };
  auto fade = [&](Layer l) { return layers ? (layers->opacity(l, t) * 255 + 500) / 1000 : 255; };
  paintWith(s, r, e, at, ms);
  if (e.speaking) speakingHand(r, at, e.speakingSide, ms);
  else if (e.typingAlong) typingTicks(r, at, e.typingPhase, e.typingFast);
  r.fade = fade(Layer::kBeside);
  if (content(Layer::kBeside, now.beside) == kZs) zs(r, at, ms);
}

namespace {
constexpr int kWishRadius = 26;
// The wish bubble's middle: up and to the right of the head, held on the panel.
Point wishCentre(const Surface& s, const rig::Anchors& at) {
  return {std::min(s.width - kWishRadius - 8, at.brimR.x / 16 + 30), std::max(kWishRadius + 6, at.crown.y / 16 + 6)};
}
}  // namespace

void paintWish(Surface& s, const WishShow& wish, const rig::Anchors& at) {
  if (wish.kind == WishShow::kNone || !s.pixels) return;
  Raster r{s};
  constexpr int kRadius = kWishRadius;
  const Point centre = wishCentre(s, at);
  const int cx = centre.x, cy = centre.y;
  const int age = int(wish.popAge), pop = int(WishShow::kPopMs);
  // A wish goes by shrinking, as a cloud thins: its disks overlap, and fading
  // them would leave a muddy patch where they do. A wish left goes at once; one
  // met turns white once its heart has popped.
  const int goes = wish.pop == WishShow::kGone ? 0 : pop / 2;
  const int gone = wish.pop == WishShow::kWaiting || age <= goes ? 0 : ease1000(age - goes, pop - goes);
  const auto size = [gone](int radius) { return radius * (1000 - gone) / 1000; };
  const uint16_t cloud = gone && wish.pop == WishShow::kMet ? rgb565(255, 255, 255) : kCream;
  // The thought's trail down to the head, then the cloud.
  r.disk(cx - kRadius - 6, cy + kRadius + 6, size(4), cloud);
  r.disk(cx - kRadius + 4, cy + kRadius - 3, size(7), cloud);
  r.disk(cx - 10, cy + 8, size(kRadius - 8), cloud);
  r.disk(cx + 10, cy + 8, size(kRadius - 8), cloud);
  r.disk(cx, cy - 4, size(kRadius - 2), cloud);
  if (wish.pop == WishShow::kMet) {
    // The icon pops into a heart, with sparks flying out from it.
    constexpr uint16_t kHeart = rgb565(226, 78, 104);
    heart(r, cx * 16, (cy - 10) * 16, size(std::min(18, 4 + age / 20)), kHeart);
    r.alpha = 255 * std::max(0, pop - age) / pop;
    for (int i = 0; i < 6; ++i) {
      const Point out = turn(i * 32 / 6);
      const int d = kRadius + age / 18;
      r.disk(cx + d * out.x / 4096, cy + d * out.y / 4096, 2, kMoonlight);
    }
  } else {
    r.alpha = 255 * (1000 - gone) / 1000;
    wishIcon(r, wish, cx, cy, kInk);
  }
  r.alpha = 255;
}

int signHop(const SignShow& sign) {
  if (!sign.text || sign.low) return 0;
  const int in = std::min<int>(sign.ms, kSignRiseMs) * 1000 / int(kSignRiseMs);
  return SignLayer::kHopPx * ease1000(in, 1000) / 1000 * sign.opacity / 1000;
}

void paintSign(Surface& s, const SignShow& sign, const rig::Anchors& at, int hop) {
  if (!s.pixels || !sign.text) return;
  Raster r{s};
  r.fade = (sign.opacity * 255 + 500) / 1000;
  const int bottom = s.height * 4 / 5;  // the lane's top: shapes stop there
  const Font& f = kSign;
  // Never narrower than kMinWide, so a short one ("<3") isn't smaller than
  // the hands that hold it.
  const int tw = stringWidth(f, sign.text), w = std::max(tw + 2 * SignLayer::kPad, SignLayer::kMinWide), h = f.h + 10;
  // Centred on its front, held at its hands' ring, never into the lane,
  // nor past the panel's sides.
  // A card held under the mouth, which is the deepest an open one reaches, so
  // nothing of it pokes above the card.
  // (A wide laugh's open mouth reaches a sixth of the eyes' spacing under its
  // middle.)
  const int underMouth = (at.mouth.y + (at.eyeR.x - at.eyeL.x) / 6) / 16 + hop;
  const int y = std::min(std::max(at.handF.y / 16 + hop - h / 2, underMouth), bottom - SignLayer::kGap - h) +
                signLift(sign.ms, SignLayer::kRisePx, SignLayer::kBobPx);
  // (A hand's disk takes the kHand pixels either side of its middle's.)
  const int edge = s.inset(y, y + h) + SignLayer::kEdge + SignLayer::kHand, most = s.width - 1 - edge - w;
  const int x = most < edge ? (s.width - w) / 2 : std::clamp(at.handF.x / 16 - w / 2, edge, most);
  r.round(x, y, w, h, 12, kCardInk);
  r.ring(x, y, w, h, 12, 2, kCardRim);
  text(r, f, x + (w - tw) / 2, y + 5, sign.text, kWords);
  // A hand at either side, gripping it.
  for (int side : {-1, 1})
    if (handsPlan().has(side, HandsAt::kSign)) paintHand(r, gripping(side < 0 ? x : x + w, y + h / 2, side, SignLayer::kHand));
}

}  // namespace render::gel
