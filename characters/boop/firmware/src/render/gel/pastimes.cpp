#include "render/gel/pastimes.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <iterator>

#include "render/font.h"
#include "render/gel/engine.h"
#include "render/gel/lane.h"
#include "render/gel/layers.h"
#include "render/gel/raster.h"
#include "render/maths.h"
#include "render/palette.h"
#include "render/tags.h"

namespace render::gel {

const PastimeInfo kPastimes[kPastimeCount] = {
    {Pastime::kSip, "sip", SceneState::kWorking, 1, 0},
    {Pastime::kPeek, "peek", SceneState::kWorking, 1, 0},
    {Pastime::kHum, "hum", SceneState::kWorking, 1, 0},
    {Pastime::kDone, "done-beat", SceneState::kWorking, 1, 0},
    {Pastime::kPonder, "ponder", SceneState::kWorking, 2, 0},
    {Pastime::kRead, "read", SceneState::kWorking, 2, 0},
    {Pastime::kNod, "nod", SceneState::kWorking, 2, 0},
    {Pastime::kBop, "bop", SceneState::kWorking, 3, 0},
    {Pastime::kDrum, "drum", SceneState::kWorking, 3, 0},
    {Pastime::kSticky, "sticky", SceneState::kWorking, 3, 0},
    {Pastime::kPhonesOn, "phones-on", SceneState::kWorking, 3, 0},
    {Pastime::kReach, "coffee-reach", SceneState::kWorking, 3, 0, true},
    {Pastime::kRefill, "refill", SceneState::kWorking, 4, 0},
    {Pastime::kSnack, "snack", SceneState::kWorking, 4, 0},
    {Pastime::kMelt, "melt", SceneState::kWorking, 4, 0, true},
    {Pastime::kStretch, "stretch-break", SceneState::kWorking, 5, 0, true},
    {Pastime::kLookAround, "look-around", SceneState::kIdle, 1, 0},
    {Pastime::kHopeful, "hopeful", SceneState::kIdle, 1, 0},
    {Pastime::kHop, "hop", SceneState::kIdle, 1, 0},
    {Pastime::kBubble, "bubble", SceneState::kIdle, 2, 0},
    {Pastime::kFly, "fly", SceneState::kIdle, 2, 0},
    {Pastime::kDoodle, "doodle", SceneState::kIdle, 2, 0},
    {Pastime::kBook, "book", SceneState::kIdle, 3, 0},
    {Pastime::kGame, "game", SceneState::kIdle, 3, 0},
    {Pastime::kWater, "water", SceneState::kIdle, 3, 0},
    {Pastime::kBrb, "brb", SceneState::kIdle, 4, 0},
    {Pastime::kTower, "tower", SceneState::kIdle, 4, 0},
    {Pastime::kDance, "dance", SceneState::kIdle, 4, 0},
    {Pastime::kPlane, "plane", SceneState::kIdle, 4, 0},
    {Pastime::kSnooze, "snooze", SceneState::kIdle, 5, 0},
    {Pastime::kDream, "dream", SceneState::kIdle, 5, 0},
    {Pastime::kSnuggle, "snuggle", SceneState::kIdle, 5, 0},
    {Pastime::kWave, "wave", SceneState::kNeedsYou, 0, 30},
    {Pastime::kTap, "tap", SceneState::kNeedsYou, 0, 120},
    {Pastime::kWatch, "watch", SceneState::kNeedsYou, 0, 300},
    {Pastime::kDrowsy, "drowsy", SceneState::kNeedsYou, 0, 600},
    {Pastime::kRollOver, "roll-over", SceneState::kAsleep, 0, 60},
    {Pastime::kSheep, "sheep", SceneState::kAsleep, 0, 120},
    {Pastime::kSnoreBubble, "snore-bubble", SceneState::kAsleep, 0, 240},
};

const PastimeInfo& info(Pastime p) { return kPastimes[std::clamp(int(p), 1, kPastimeCount) - 1]; }

Pastime pastimeFor(const char* reply) {
  for (const auto& r : kReplyPastimes)
    if (reply && std::strcmp(reply, r.reply) == 0) return r.pastime;
  return Pastime::kNone;
}

uint32_t tierBit(int n) {
  static const uint32_t kBits[5] = {tagBit("tier1"), tagBit("tier2"), tagBit("tier3"), tagBit("tier4"),
                                    tagBit("tier5")};
  return n >= 1 && n <= 5 ? kBits[n - 1] : 0;
}

int tierOf(uint32_t when) {
  for (int n = 5; n >= 1; --n)
    if (when & tierBit(n)) return n;
  return 0;
}

namespace {

// The inks: the gel's and the cards', then the kit's and the pastimes'.
constexpr uint16_t kGel = rgb565(89, 169, 224), kShine = rgb565(184, 233, 245), kCream = rgb565(246, 240, 226),
                   kInk = rgb565(28, 24, 36), kCardInk = rgb565(27, 55, 78), kCardRim = rgb565(0x78, 0xa4, 0xc8),
                   kWords = rgb565(184, 233, 245), kAmber = rgb565(239, 189, 103);
constexpr uint16_t kMug = rgb565(214, 92, 84), kMugDark = rgb565(150, 56, 52), kCoffee = rgb565(110, 66, 40),
                   kSteam = rgb565(200, 210, 220), kPhones = rgb565(46, 48, 60), kPhonesCap = rgb565(86, 90, 110),
                   kCushion = rgb565(236, 104, 140), kCushionShade = rgb565(196, 82, 116),
                   kLeaf = rgb565(96, 196, 112), kLeafDark = rgb565(60, 140, 80), kPot = rgb565(204, 112, 72),
                   kSoil = rgb565(70, 46, 32), kPetal = rgb565(250, 130, 180), kNote = rgb565(255, 214, 120),
                   kHeart = rgb565(240, 96, 140), kBulb = rgb565(255, 228, 110), kTick = rgb565(110, 220, 140),
                   kCookie = rgb565(206, 150, 88), kChip = rgb565(90, 54, 30),
                   kGlass = rgb565(170, 196, 206),
                   kCheese = rgb565(255, 214, 96), kPepperoni = rgb565(200, 60, 50), kStar = rgb565(255, 240, 170),
                   kBlanket = rgb565(150, 104, 200), kBlanketDark = rgb565(104, 66, 150),
                   kPlaid = rgb565(214, 186, 240), kFly = rgb565(30, 30, 36),
                   kWing = rgb565(200, 230, 250), kBubbleRim = rgb565(190, 236, 255), kBook = rgb565(206, 72, 88),
                   kPage = rgb565(250, 246, 232), kLine = rgb565(170, 170, 190), kConsole = rgb565(124, 104, 210),
                   kScreen = rgb565(150, 230, 170), kCan = rgb565(90, 180, 120), kWater = rgb565(110, 190, 255),
                   kPaper = rgb565(250, 250, 255), kGold = rgb565(232, 190, 80), kSheep = rgb565(250, 250, 246),
                   kFence = rgb565(170, 120, 70), kGrass = rgb565(80, 170, 90), kGrey = rgb565(150, 150, 160);
constexpr uint16_t kBlocks[] = {rgb565(240, 96, 96),  rgb565(250, 200, 70),  rgb565(100, 200, 120),
                                rgb565(90, 160, 240), rgb565(170, 110, 230), rgb565(250, 150, 60)};
constexpr uint16_t kLights[] = {rgb565(255, 90, 160), rgb565(90, 220, 255), rgb565(255, 220, 80),
                                rgb565(140, 255, 140)};

// The cosine of `t` thousandths of a turn, in thousandths, from a table of
// fortieths and a straight line between: integer, so every board draws the
// same.
int cosT(int t) {
  static constexpr int kQuarter[11] = {1000, 988, 951, 891, 809, 707, 588, 454, 309, 156, 0};
  auto at = [](int s) {
    s = ((s % 40) + 40) % 40;
    const int q = s / 10, i = s % 10;
    return q == 0 ? kQuarter[i] : q == 1 ? -kQuarter[10 - i] : q == 2 ? -kQuarter[i] : kQuarter[10 - i];
  };
  t = ((t % 1000) + 1000) % 1000;
  const int s = t / 25, f = t % 25;
  return at(s) + (at(s + 1) - at(s)) * f / 25;
}
int sinT(int t) { return cosT(t - 250); }

// How far `age` is from `from` to `to`, 0 … 1024: linear, and eased in and
// out (render::ease's smoothstep).
int span(int age, int from, int to) { return age <= from ? 0 : age >= to ? 1024 : (age - from) * 1024 / (to - from); }
int eased(int age, int from, int to) { return age <= from ? 0 : age >= to ? 1024 : ease(age - from, to - from); }
int mix(int a, int b, int k) { return a + (b - a) * k / 1024; }
// 0 … 255: rising over `in` ms from `from`, falling over the `out` ms
// before `to`.
int window(int age, int from, int to, int in = 150, int out = 250) {
  if (age < from || age >= to) return 0;
  return std::min({255, (age - from) * 255 / std::max(1, in), (to - age) * 255 / std::max(1, out)});
}
// A triangle wave, -amp … amp, once every `period` ms.
int wobble(int ms, int period, int amp) {
  const int p = ((ms % period) + period) % period;
  return (p < period / 2 ? p : period - p) * 4 * amp / period - amp;
}
uint16_t blend(uint16_t a, uint16_t b, int k) { return mix565(a, b, std::clamp(k * 255 / 1024, 0, 255)); }

// Where things are this frame, in the surface's px: the layout's (a
// 502 × 410 surface, scaled to the one drawn on) and the body's anchors'.
struct Stage {
  Raster& r;
  int w, h;
  const rig::Anchors& at;
  int X(int p) const { return w * p / 502; }
  int Y(int p) const { return h * p / 410; }
  int eyesX() const { return (at.eyeL.x + at.eyeR.x) / 32; }
  int eyesY() const { return (at.eyeL.y + at.eyeR.y) / 32; }
  int mouthX() const { return eyesX(); }
  int mouthY() const { return eyesY() + Y(36); }
  int crownX() const { return at.crown.x / 16; }
  int crownY() const { return at.crown.y / 16; }
  int handX() const { return at.handF.x / 16; }
  int handY() const { return at.handF.y / 16; }
  int leftX() const { return at.brimL.x / 16; }
  int rightX() const { return at.brimR.x / 16; }
  int sideY() const { return (at.brimL.y + at.brimR.y) / 32; }
  // The desk's top, and the floor beside it.
  int deskY() const { return Y(307); }
  int floorY() const { return Y(318); }
};

// A little gel hand, as the sign's: the body's blue with a shine.
void hand(Raster& r, int x, int y, int radius = 9) {
  const int a = r.alpha;
  r.disk(x, y, radius, kGel);
  r.alpha = a * 160 / 255;
  r.disk(x - radius / 3, y - radius / 2, std::max(1, radius / 3), kShine);
  r.alpha = a;
}

// A note: its head, stem and flag, `s` the head's radius.
void note(Raster& r, int x, int y, int s, uint16_t ink) {
  r.disk(x, y, s, ink);
  r.line({x + s - 1, y}, {x + s - 1, y - 3 * s}, std::max(1, s / 2), ink);
  r.line({x + s - 1, y - 3 * s}, {x + 2 * s, y - 2 * s}, std::max(1, s / 2), ink);
}

// A four-pointed twinkle, `s` its reach.
void sparkle(Raster& r, int x, int y, int s, uint16_t ink) {
  const int t = std::max(1, s / 4);
  const Point v[] = {{x, y - s}, {x + t, y - t}, {x + s, y}, {x + t, y + t},
                     {x, y + s}, {x - t, y + t}, {x - s, y}, {x - t, y - t}};
  r.polygon(v, 8, ink);
}

// A five-pointed star, `s` its reach, turned `turn` thousandths.
void star(Raster& r, int x, int y, int s, int turn, uint16_t ink) {
  Point v[10];
  for (int i = 0; i < 10; ++i) {
    const int k = turn + i * 100, rr = i % 2 ? s * 2 / 5 : s;
    v[i] = {x + rr * sinT(k) / 1000, y - rr * cosT(k) / 1000};
  }
  r.polygon(v, 10, ink);
}

void heart(Raster& r, int x, int y, int s, uint16_t ink) {
  r.disk(x - s / 2, y, s / 2 + 1, ink);
  r.disk(x + s / 2, y, s / 2 + 1, ink);
  const Point v[] = {{x - s - 1, y + 1}, {x + s + 1, y + 1}, {x, y + s + s / 2}};
  r.polygon(v, 3, ink);
}

// A thought cloud `w` × `h` about (x, y), and its bubbles trailing down to
// (tx, ty).
void cloud(Raster& r, int x, int y, int w, int h, int tx, int ty, uint16_t ink) {
  r.round(x - w / 2, y - h / 2, w, h, h / 2, ink);
  for (int i = 0; i < 4; ++i) r.disk(x - w / 3 + i * w / 4, y - h / 2 + 2, h / 4 + (i % 2) * 3, ink);
  for (int i = 0; i < 2; ++i) r.disk(x - w / 2 + 4 + i * w / 3, y + h / 2 - 3, h / 5, ink);
  for (int i = 1; i <= 3; ++i) r.disk(mix(x, tx, i * 256), mix(y + h / 2, ty, i * 256), 6 - i, ink);
}

// Text centred on (x, y).
void say(Raster& r, const char* s, int x, int y, uint16_t ink, const Font& f = kSmall) { r.text(s, x, y, ink, f); }

// Zs drifting up and right from (x, y), a new one every 900 ms, each for
// 2.7 s, growing from 7 to 16 px tall by sixteenths of a pixel, fading in
// over its first 200 ms and out to nothing by its last.
void zs(Raster& r, int x, int y, int ms) {
  const int a = r.alpha;
  for (int i = 0; i < 3; ++i) {
    const int age = (ms + i * 900) % 2700;
    r.alpha = a * std::min(age * 255 / 200, 255 - age * 255 / 2700) / 255;
    r.zee(x * 16 + 16 + age * 16 / 40, y * 16 - 5 * 16 - age * 16 / 22 - age * 5 * 16 / 2700,
          7 * 16 + age * 9 * 16 / 2700, kCream);
  }
  r.alpha = a;
}

// A bubble of radius `rad` about (x, y): a faint film, its rim and a shine.
void bubble(Raster& r, int x, int y, int rad) {
  const int a = r.alpha;
  r.alpha = a * 60 / 255;
  r.disk(x, y, rad, kBubbleRim);
  r.alpha = a * 190 / 255;
  Point rim[33];
  for (int i = 0; i <= 32; ++i)
    rim[i] = {x * 16 + 8 + rad * 16 * cosT(i * 1000 / 32) / 1000, y * 16 + 8 + rad * 16 * sinT(i * 1000 / 32) / 1000};
  r.stroke16(rim, 33, 24, kBubbleRim);
  r.alpha = a * 220 / 255;
  r.disk(x - rad * 2 / 5, y - rad * 2 / 5, std::max(1, rad / 5), kCream);
  r.alpha = a;
}

// Droplets bursting from (x, y), `k` (0 … 1024) of the way out.
void burst(Raster& r, int x, int y, int reach, int k, uint16_t ink) {
  const int a = r.alpha;
  r.alpha = a * (1024 - k) / 1024;
  for (int i = 0; i < 8; ++i)
    r.disk(x + reach * k / 1024 * cosT(i * 125) / 1000, y + reach * k / 1024 * sinT(i * 125) / 1000, 2, ink);
  r.alpha = a;
}

// ---- The kit --------------------------------------------------------------

// A mug standing on `base` at x, `fill` of it coffee (0 … 1024), its steam
// rising on the device's clock.
void mug(Raster& r, int x, int base, int fill, uint32_t t, bool steam = true) {
  r.round(x - 9, base - 18, 18, 18, 4, kMug);
  r.disk(x + 10, base - 9, 6, kMug);
  r.disk(x + 10, base - 9, 3, kInk);
  r.round(x - 8, base - 18, 16, 4, 2, kMugDark);
  if (fill > 0) r.round(x - 7, base - 18 + 3 * (1024 - fill) / 1024, 14, 3, 1, kCoffee);
  r.alpha = r.alpha * 3 / 4;
  r.round(x - 6, base - 13, 3, 8, 1, kCream);  // its shine
  r.alpha = r.alpha * 4 / 3;
  if (!steam) return;
  const int a = r.alpha;
  for (int i = 0; i < 2; ++i) {
    const int age = int((t + i * 700) % 1400);
    Point wisp[4];
    for (int k = 0; k < 4; ++k)
      wisp[k] = {(x - 3 + i * 6) * 16 + wobble(age + k * 220, 900, 3) * 16, (base - 22 - age / 70 - k * 4) * 16};
    r.alpha = a * (1400 - age) / 1400 * 2 / 3;
    r.stroke16(wisp, 4, 28, kSteam);
  }
  r.alpha = a;
}

// In the zone: motes drifting up beside it, by turns on its left and its
// right, each from its lap's height to above its brim over kMoteMs,
// swaying, fading in and out.
void motes(const Stage& s, uint32_t t) {
  constexpr int kEnd = rig::Anchors::kRingPoints - 1;
  Raster& r = s.r;
  const int a = r.alpha;
  for (int i = 0; i < kMotes; ++i) {
    const int age = int((t + uint32_t(i) * kMoteMs / kMotes) % kMoteMs), side = i % 2 ? 1 : -1;
    const rig::Point& from = side > 0 ? s.at.lap[kEnd] : s.at.lap[0];
    const int x = from.x / 16 + side * (s.X(16) + (i * 7) % 11) + wobble(age + i * 300, 1800, 4);
    const int y = from.y / 16 - (from.y / 16 - s.sideY() + s.Y(30)) * age / int(kMoteMs);
    r.alpha = a * window(age, 0, int(kMoteMs), 900, 1400) / 255 * 4 / 5;
    r.disk(x, y, 2 + i % 2, kCream);
  }
  r.alpha = a;
}

// The mugs on the desk's right end: one, or a stack; the top one's base.
void mugs(Raster& r, const Stage& s, int n, uint32_t t) {
  for (int i = 0; i < n; ++i) mug(r, s.X(400), s.deskY() - i * 18, 1024, t, i == n - 1);
}
int topMug(const Stage& s, int n) { return s.deskY() - (n - 1) * 18; }

// An oval, filled, `rx` and `ry` its radii, all in sixteenths of a px.
constexpr Point kUnitCircle[24] = {{1000, 0},  {966, 259},   {866, 500},   {707, 707},   {500, 866},   {259, 966},
                                   {0, 1000},  {-259, 966},  {-500, 866},  {-707, 707},  {-866, 500},  {-966, 259},
                                   {-1000, 0}, {-966, -259}, {-866, -500}, {-707, -707}, {-500, -866}, {-259, -966},
                                   {0, -1000}, {259, -966},  {500, -866},  {707, -707},  {866, -500},  {966, -259}};
void oval16(Raster& r, int cx, int cy, int rx, int ry, uint16_t ink) {
  Point v[24];
  for (int i = 0; i < 24; ++i) v[i] = {cx + kUnitCircle[i].x * rx / 1000, cy + kUnitCircle[i].y * ry / 1000};
  r.polygon16(v, 24, ink);
}

// Where the headphones' cups sit, in sixteenths of a px: over its ears, on
// its sides between its eyes' height and the brim's, each from its
// cushion against the body (`inner`) out to its cap (`outer`), `ry` its
// half-height; `scale` is the brim's width, which sizes the rest.
struct Cups {
  int inner[2], outer[2], y[2], ry, scale;
};
Cups cupsOf(const rig::Anchors& at) {
  Cups c;
  const int midX = (at.eyeL.x + at.eyeR.x) / 2, half = (at.eyeR.x - at.eyeL.x) / 2;
  c.scale = std::max(16, at.brimR.x - at.brimL.x);
  c.ry = c.scale * 18 / 100;
  const int pad = c.scale * 9 / 100, cup = c.scale * 8 / 100;
  for (int side : {0, 1}) {
    const int out = side ? 1 : -1, edge = midX + out * half * 185 / 100;
    c.inner[side] = edge - out * pad / 2;
    c.outer[side] = c.inner[side] + out * (pad + cup);
    c.y[side] = side ? (at.eyeR.y * 2 + at.brimR.y) / 3 : (at.eyeL.y * 2 + at.brimL.y) / 3;
  }
  return c;
}

// Over its ears, each cup seen side-on: a cylinder, its pink cushion
// pressed to the body and its cap facing out, with a shine down it; the
// band from one cup's top to the other's over the crown. A card over its
// head hides the band's top, and the cups still say headphones.
void headphones(Raster& r, const rig::Anchors& at) {
  const Cups c = cupsOf(at);
  const int w = c.scale, end = w * 5 / 100, padRy = c.ry * 92 / 100;
  int bandX[2], bandY[2];
  for (int side : {0, 1}) {
    const int out = side ? 1 : -1, x0 = c.inner[side], x2 = c.outer[side], y = c.y[side];
    const int x1 = x0 + out * w * 9 / 100;  // where the cushion meets the cup
    bandX[side] = (x1 + x2) / 2, bandY[side] = y - c.ry * 9 / 10;
    oval16(r, x0, y, end, padRy, kCushionShade);
    const Point pad[4] = {{x0, y - padRy}, {x1, y - padRy}, {x1, y + padRy}, {x0, y + padRy}};
    r.polygon16(pad, 4, kCushion);
    oval16(r, x1, y, end, padRy, kCushion);
    const Point cup[4] = {{x1, y - c.ry}, {x2, y - c.ry}, {x2, y + c.ry}, {x1, y + c.ry}};
    r.polygon16(cup, 4, kPhones);
    oval16(r, x1, y, end, c.ry, kPhones);
    oval16(r, x2, y, end + w / 100, c.ry, kPhonesCap);
    const int a = r.alpha;
    r.alpha = a * 2 / 5;
    const int s0 = x1 + (x2 - x1) / 4, s1 = x1 + (x2 - x1) / 2;
    const Point shine[4] = {{s0, y - c.ry * 7 / 10}, {s1, y - c.ry * 7 / 10}, {s1, y + c.ry / 4}, {s0, y + c.ry / 4}};
    r.polygon16(shine, 4, kCream);
    r.alpha = a;
  }
  const int top = at.crown.y - w / 12, cx = at.crown.x, cy = 2 * top - (bandY[0] + bandY[1]) / 2;
  Point band[17];
  for (int i = 0; i <= 16; ++i) {
    const int64_t u = i, v = 16 - i;
    band[i] = {int((v * v * bandX[0] + 2 * u * v * cx + u * u * bandX[1]) / 256),
               int((v * v * bandY[0] + 2 * u * v * cy + u * u * bandY[1]) / 256)};
  }
  r.stroke16(band, 17, w / 16, kPhones);
}

// Where a note leaving cup `side` starts, in px: off its cap's top.
Point capTop(const Cups& c, int side) {
  return {(c.outer[side] + (side ? 1 : -1) * c.scale / 40) / 16, (c.y[side] - c.ry * 3 / 4) / 16};
}

// The tune the headphones play: each note up and out from its cup,
// swaying, fading in and out.
void tune(Raster& r, const rig::Anchors& at, uint32_t t) {
  const Cups c = cupsOf(at);
  const int a = r.alpha;
  for (int side : {0, 1}) {
    const int age = tuneNoteAge(t, side);
    if (age < 0) continue;
    const int out = side ? 1 : -1;
    const Point from = capTop(c, side);
    r.alpha = a * window(age, 0, int(kTuneNoteMs), 200, 500) / 255;
    note(r, from.x + out * age / 60 + wobble(age, 900, 3), from.y - age / 32, 6,
         kLights[(t / kTuneEveryMs + side) % 4]);
  }
  r.alpha = a;
}

// The plant beside it, grown `grown` (1 a sprout, 2 leafy, 3 in flower),
// swaying a little; `wiggle`, being watered.
void plant(Raster& r, const Stage& s, int grown, uint32_t t, int wiggle = 0) {
  const int x = s.X(446), base = s.floorY();
  const int height = grown == 1 ? 14 : grown == 2 ? 30 : 40, sway = wobble(int(t), 4000, 2) + wiggle;
  const Point tip{x + sway, base - 20 - height};
  r.line({x, base - 20}, tip, 3, kLeafDark);
  const int leaves = grown == 1 ? 1 : grown == 2 ? 2 : 3;
  for (int i = 0; i < leaves; ++i) {
    const int ly = base - 22 - height * (i + 1) / (leaves + 1), lx = x + sway * (i + 1) / (leaves + 1);
    for (int side : {-1, 1}) {
      const Point leaf[] = {{lx, ly}, {lx + side * 9, ly - 6}, {lx + side * 14, ly - 2}, {lx + side * 7, ly + 2}};
      r.polygon(leaf, 4, i % 2 ? kLeafDark : kLeaf);
    }
  }
  if (grown >= 3) {
    for (int i = 0; i < 5; ++i) r.disk(tip.x + 6 * cosT(i * 200) / 1000, tip.y + 6 * sinT(i * 200) / 1000, 4, kPetal);
    r.disk(tip.x, tip.y, 3, kBulb);
  } else {
    r.disk(tip.x, tip.y, 3, kLeaf);
  }
  const Point pot[] = {{x - 14, base - 22}, {x + 14, base - 22}, {x + 10, base}, {x - 10, base}};
  r.polygon(pot, 4, kPot);
  r.round(x - 16, base - 24, 32, 6, 2, kPot);
  r.round(x - 12, base - 22, 24, 3, 1, kSoil);
}

// ---- The pastimes ----------------------------------------------------------

// A coffee pot at (x, y), tipped `tilt` thousandths of a turn toward its
// spout on the left; where its spout is, into `spout`.
void coffeePot(Raster& r, int x, int y, int tilt, Point& spout) {
  auto at = [&](int dx, int dy) {
    return Point{x + (dx * cosT(tilt) + dy * sinT(tilt)) / 1000, y + (-dx * sinT(tilt) + dy * cosT(tilt)) / 1000};
  };
  const Point glass[] = {at(-12, -10), at(12, -10), at(15, 14), at(-15, 14)};
  r.polygon(glass, 4, kGlass);
  const Point brew[] = {at(-13, 2), at(13, 2), at(15, 14), at(-15, 14)};
  r.polygon(brew, 4, kCoffee);
  const Point lid[] = {at(-13, -16), at(13, -16), at(12, -10), at(-12, -10)};
  r.polygon(lid, 4, kPhones);
  const Point beak[] = {at(-12, -10), at(-20, -14), at(-12, -5)};
  r.polygon(beak, 3, kGlass);
  r.line(at(13, -6), at(21, 0), 3, kPhones);
  r.line(at(21, 0), at(15, 10), 3, kPhones);
  spout = at(-20, -14);
}

// A paper plane at (x, y), flying toward `dir` thousandths of a turn (0
// right, 250 down).
void plane(Raster& r, int x, int y, int dir) {
  auto at = [&](int dx, int dy) {
    return Point{x + (dx * cosT(dir) - dy * sinT(dir)) / 1000, y + (dx * sinT(dir) + dy * cosT(dir)) / 1000};
  };
  const Point wing[] = {at(12, 0), at(-10, -8), at(-6, 0), at(-10, 6)};
  r.polygon(wing, 4, kPaper);
  r.line(at(12, 0), at(-6, 0), 1, kLine);
}

// A sheep jumping a fence in a dream cloud about (x, y), `ms` in, counted.
void dream(const Stage& s, int x, int y, int ms) {
  Raster& r = s.r;
  cloud(r, x, y, s.X(130), s.Y(78), s.crownX() + s.X(60), s.crownY() + s.Y(36), kCream);
  const int ground = y + s.Y(24);
  r.line({x - s.X(52), ground}, {x + s.X(52), ground}, 2, kGrass);
  for (int dx : {-6, 6}) r.line({x + dx, ground}, {x + dx, ground - 16}, 3, kFence);
  r.line({x - 10, ground - 12}, {x + 10, ground - 12}, 2, kFence);
  const int hop = ms % 1500, k = hop * 1024 / 1500;
  const int sx = mix(x - s.X(44), x + s.X(44), k), sy = ground - 10 - 26 * sinT(k * 500 / 1024) / 1000;
  for (int i = 0; i < 4; ++i) r.disk(sx - 6 + i * 4, sy - 2 + (i % 2) * 3, 6, kSheep);
  r.disk(sx + 10, sy - 1, 4, kInk);
  if (hop < 1100) {
    r.line({sx - 4, sy + 5}, {sx - 5, sy + 10}, 2, kInk);
    r.line({sx + 4, sy + 5}, {sx + 5, sy + 10}, 2, kInk);
  }
  char count[4] = {char('1' + ms / 1500 % 9), 0};
  say(r, count, x + s.X(44), y - s.Y(20), kInk);
}

void sip(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  const int up = eased(age, 0, 600) - eased(age, 2200, 2800);
  const int x = mix(s.X(400), s.mouthX() + s.X(50), up), base = mix(topMug(s, p.mugs), s.mouthY() + s.Y(10), up);
  mug(r, x, base, 1024 - span(age, 700, 2000) / 4, p.t, up < 200);
  if (up > 100) hand(r, x - 11, base - 8);
  if (const int a = window(age, 2200, 2900); a) {
    const int base = r.alpha;
    r.alpha = a;
    say(r, "ahh", s.mouthX() - s.X(48), s.mouthY() - s.Y(10), kCream);
    r.alpha = base;
  }
}

void peek(const Stage& s, const PastimeShow& p) {
  const int age = int(p.age), a = window(age, 800, 2100);
  if (!a) return;
  s.r.alpha = a;
  heart(s.r, s.crownX() + s.X(84), s.crownY() + s.Y(36) - (age - 800) / 40, 4 + eased(age, 800, 1100) * 6 / 1024,
        kHeart);
  s.r.alpha = 255;
}

void hum(const Stage& s, const PastimeShow& p) {
  for (int i = 0; i < 3; ++i) {
    const int age = int(p.age) - 300 - i * 1000;
    if (age < 0 || age > 1700) continue;
    s.r.alpha = window(age, 0, 1700, 200, 500);
    note(s.r, s.mouthX() + s.X(40) + age / 30 + wobble(age, 800, 4), s.mouthY() - s.Y(10) - age / 18, 4,
         i == 1 ? kShine : kNote);
  }
  s.r.alpha = 255;
}

void ponder(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  if (const int a = window(age, 200, 1800)) {
    r.alpha = a;
    const int x = s.crownX() - s.X(118), y = s.crownY() + s.Y(28);
    cloud(r, x, y, s.X(46), s.Y(38), s.crownX() - s.X(70), s.crownY() + s.Y(64), kCream);
    say(r, "?", x, y, kInk, kLarge);
  }
  if (const int a = window(age, 1800, int(p.ms), 120, 400)) {
    r.alpha = a;
    const int x = s.crownX() - s.X(96), y = s.crownY() + s.Y(8), glow = eased(age, 1800, 2100);
    r.alpha = a * 70 / 255;
    r.disk(x, y, 10 + glow * 8 / 1024, kBulb);
    r.alpha = a;
    r.disk(x, y, 10, kBulb);
    r.round(x - 5, y + 8, 10, 8, 2, kGrey);
    for (int i = 0; i < 6; ++i) {
      const int k = 600 + i * 80, in = 15 + glow * 6 / 1024;
      r.line({x + in * cosT(k) / 1000, y + in * sinT(k) / 1000},
             {x + (in + 7) * cosT(k) / 1000, y + (in + 7) * sinT(k) / 1000}, 2, kBulb);
    }
  }
  r.alpha = 255;
}

// Something finished: a tick on the monitor as Enter goes down, and a
// sparkle off its corner.
void done(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  if (const int a = window(age, 600, 2300, 80, 500)) {
    r.alpha = a;
    const int x = s.X(96), y = s.Y(268), k = eased(age, 600, 800);
    r.line({x - 8, y}, {x - 8 + 6 * k / 1024, y + 6 * k / 1024}, 3, kTick);
    if (k == 1024) {
      const int up = eased(age, 800, 950);
      r.line({x - 2, y + 6}, {x - 2 + 14 * up / 1024, y + 6 - 14 * up / 1024}, 3, kTick);
    }
    if (const int b = window(age, 750, 1500, 80, 400)) {
      r.alpha = b;
      sparkle(r, s.X(140), s.Y(244), 4 + 3 * eased(age, 750, 950) / 1024, kShine);
    }
  }
  r.alpha = 255;
}

// Reading closely: the line its eyes are on lit on the monitor, a line
// further down every 700 ms; from tier4 it's close enough to fog the glass.
void read(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  if (const int a = window(age, 800, 3900, 150, 200)) {
    const int line = std::min(2, (age - 800) / 1050);
    r.alpha = a * 110 / 255;
    r.round(s.X(62), s.Y(265) + line * s.Y(5), s.X(56) - line * s.X(12), s.Y(5), 2, kShine);
    if (tierOf(p.when) >= 4)  // soft at its edge: rings of breath, thinner further out
      for (int ring = 0; ring < 3; ++ring) {
        r.alpha = a * (16 + ring * 14) / 255;
        r.disk(s.X(122), s.Y(270), 18 - ring * 5, kCream);
      }
  }
  r.alpha = 255;
}

// Putting the headphones on: a hand at each cup, bringing them down over
// its ears (the cups themselves are the kit's, dropped: paintWorn).
void phonesOn(const Stage& s, const PastimeShow& p) {
  const int a = window(int(p.age), 0, int(kPhonesOnMs) + 200, 150, 300);
  if (!a) return;
  const Cups c = cupsOf(s.at);
  s.r.alpha = a;
  for (int side : {0, 1}) hand(s.r, c.outer[side] / 16 + (side ? 4 : -4), c.y[side] / 16 - p.drop + 6, 10);
  s.r.alpha = 255;
}

void nod(const Stage& s, const PastimeShow& p) {
  for (int i = 0; i < 3; ++i) {
    const int age = int(p.age) - 300 - i * 800;
    if (age < 0 || age > 1200) continue;
    s.r.alpha = window(age, 0, 1200, 120, 400);
    const int x = s.X(80) + i * s.X(18), y = s.Y(236) - age / 25;
    s.r.line({x - 6, y}, {x - 1, y + 5}, 3, kTick);
    s.r.line({x - 1, y + 5}, {x + 8, y - 6}, 3, kTick);
  }
  s.r.alpha = 255;
}

void bop(const Stage& s, const PastimeShow& p, bool phones) {
  for (int i = 0; i < 8; ++i) {
    const int age = int(p.age) - i * 500;
    if (age < 0 || age > 1300) continue;
    s.r.alpha = window(age, 0, 1300, 120, 500);
    const int side = i % 2 ? 1 : -1;
    const Point cap = capTop(cupsOf(s.at), side > 0);  // with headphones on, off a cup
    const int x0 = phones ? cap.x : s.mouthX() + side * s.X(40);
    const int y0 = phones ? cap.y : s.mouthY() - s.Y(12);
    note(s.r, x0 + side * age / 30, y0 - age / 20, 4, kLights[i % 4]);
  }
  s.r.alpha = 255;
}

void drum(const Stage& s, const PastimeShow& p) {
  const int age = int(p.age);
  if (age < 200 || age > int(p.ms) - 400) return;
  const int beat = (age - 200) / 150, side = beat % 2 ? 1 : -1, k = (age - 200) % 150;
  const int x = side > 0 ? s.X(336) : s.X(184), y = s.deskY() - 6;
  s.r.alpha = 255 - k * 255 / 150;
  for (int i = -1; i <= 1; ++i) s.r.line({x + i * 7, y - 6}, {x + i * 15, y - 18}, 3, kCream);
  say(s.r, side > 0 ? "tk" : "ta", x + side * 16, y - 22, kShine);
  s.r.alpha = 255;
}

// A sticky note slapped on the monitor's corner, a scribble on it.
void sticky(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age), fly = eased(age, 500, 900);
  const Point from{s.mouthX() - s.X(60), s.mouthY()}, to{s.X(126), s.Y(238)};
  const int x = mix(from.x, to.x, fly),
            y = mix(from.y, to.y, fly) - (fly > 0 && fly < 1024 ? sinT(fly * 500 / 1024) * 20 / 1000 : 0);
  if (age < 900) hand(r, x + 10, y + 12);
  const int slap = age >= 900 && age < 1050 ? 3 : 0;
  r.round(x - 12 - slap, y - 12 - slap, 24 + 2 * slap, 24 + 2 * slap, 2, kCheese);
  if (age >= 1200) {
    const int k = span(age, 1200, 2000);
    Point squiggle[6];
    for (int i = 0; i < 6; ++i) squiggle[i] = {(x - 8 + i * 3) * 16, (y - 2 + (i % 2 ? -4 : 3)) * 16};
    const int n = std::max(2, 6 * k / 1024);
    r.stroke16(squiggle, n, 20, kInk);
    if (k == 1024) r.disk(x + 7, y + 6, 2, kPepperoni);
  }
}

void refill(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  const int in = eased(age, 0, 700) - eased(age, 2800, 3500);
  const int tilt = 920 - (eased(age, 700, 950) - eased(age, 2500, 2800)) * 120 / 1024 + 80;
  const int x = mix(s.X(540), s.X(438), in), y = mix(s.Y(120), s.deskY() - s.Y(64), in);
  Point spout;
  coffeePot(r, x, y, tilt % 1000, spout);
  if (age > 950 && age < 2500) {
    const int top = topMug(s, p.mugs) - 18;
    const Point pour[] = {
        {spout.x * 16, spout.y * 16}, {(spout.x - 4) * 16, (spout.y + 8) * 16}, {s.X(398) * 16, top * 16}};
    r.stroke16(pour, 3, 40, kCoffee);
  }
}

// The coffee reach: the top mug in its hand from when it reaches it till
// it lets go (kReachHolds), brought in to its mouth for the sip between,
// "ahh" after; on the stack, before and after, the kit's.
constexpr int kReachHolds = 1000, kReachLets = 4100;
void reach(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  const int in = eased(age, 1300, 1900) - eased(age, 3300, 3800);
  const int x = mix(s.X(400), s.mouthX() + s.X(44), in), base = mix(topMug(s, p.mugs), s.mouthY() + s.Y(12), in);
  if (age >= kReachHolds && age < kReachLets) {
    mug(r, x, base, 1024 - span(age, 1900, 3300) / 4, p.t, false);
    hand(r, x - 11, base - 8);
  }
  if (const int a = window(age, 3100, 3800)) {
    r.alpha = a;
    say(r, "ahh", s.mouthX() - s.X(48), s.mouthY() - s.Y(10), kCream);
    r.alpha = 255;
  }
}

// The melt: drips running down its sides to the desk as it goes, then,
// while it's a puddle, bubbles rising in it.
void melt(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  for (int i = 0; i < 6; ++i) {
    const int from = 800 + i * 230, k = span(age, from, from + 900);
    if (k <= 0 || k >= 1024) continue;
    const int side = i % 2 ? 1 : -1;
    const int x = (side > 0 ? s.rightX() : s.leftX()) - side * s.X(10 + i * 3) + side * k * 14 / 1024;
    const int y = mix(s.sideY() + s.Y(10), s.deskY() - 5, k * k / 1024);
    r.alpha = 255 - std::max(0, k - 800) * 255 / 224;
    r.disk(x, y, 4, kGel);
    const Point tip[] = {{x - 3, y - 1}, {x + 3, y - 1}, {x, y - 9}};
    r.polygon(tip, 3, kGel);
    r.disk(x - 1, y - 1, 1, kShine);
  }
  for (int i = 0; i < 4; ++i) {
    const int from = 2500 + i * 380, k = span(age, from, from + 900);
    if (k <= 0 || k >= 1024) continue;
    r.alpha = window(age, from, from + 900, 150, 300);
    bubble(r, s.crownX() + (i - 2) * s.X(34) + s.X(17), s.crownY() + s.Y(14) - k * s.Y(22) / 1024, 3 + i % 2);
  }
  r.alpha = 255;
}

// The stretch break: back at the desk, its hands up high either side of
// its head as it stretches tall, and down as it lets go.
void stretch(const Stage& s, const PastimeShow& p) {
  const int age = int(p.age), up = eased(age, 7250, 8000) - eased(age, 9000, 9400);
  if (!up) return;
  s.r.alpha = window(age, 7250, 9400, 150, 250);
  for (int side : {-1, 1}) {
    const int x = (side > 0 ? s.rightX() : s.leftX()) + side * (s.X(6) + s.X(8) * up / 1024);
    hand(s.r, x, s.sideY() - s.Y(10) - s.Y(46) * up / 1024, 10);
  }
  s.r.alpha = 255;
}

void snack(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  int bites = 0;
  for (int at : {900, 1600, 2300}) bites += age >= at;
  const int in = eased(age, 0, 400);
  const int x = s.mouthX() + s.X(46), y = mix(s.deskY(), s.mouthY() + s.Y(2), in);
  const int rad = 15 - bites * 5;
  if (rad > 0 && age < 2400) {
    r.disk(x, y, rad, kCookie);
    for (int i = 0; i < 4 - bites; ++i) r.disk(x - 5 + (i * 7) % 11, y - 4 + (i * 5) % 9, 2, kChip);
    hand(r, x + rad + 4, y + 2);
  }
  for (int at : {900, 1600, 2300})
    if (age >= at && age < at + 900)
      for (int i = 0; i < 4; ++i) {
        const int t = age - at, fall = t * t / 3000;
        r.alpha = 255 - t * 255 / 900;
        r.disk(x - 12 + i * 6, y + 4 + fall, 2, kCookie);
      }
  r.alpha = 255;
}

// A blanket tucked in round it as it naps: pulled up from the floor to
// just under its eyes as it starts, slipping back down as it ends. Wider
// than the body and pooled in folds on the floor, plaid, its top a cream
// sheet turned down over it. Nothing of it goes over its head, so it never
// reads as a hat.
void blanket(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  const int up = eased(age, 0, 900) - eased(age, int(p.ms) - 700, int(p.ms));
  if (!up) return;
  constexpr int kEnd = rig::Anchors::kRingPoints - 1;
  const auto& at = s.at;
  const int w = std::max(16, at.lap[kEnd].x - at.lap[0].x), out = w / 24;
  // The floor it pools on, under the hem, and how far up it comes: over
  // its face, the top of its head left out.
  int floor = 0;
  for (const Point& h : at.hem) floor = std::max(floor, h.y);
  floor += s.Y(4) * 16;
  const int top = at.crown.y + (floor - at.crown.y) * 2 / 5, sag = s.Y(14) * 16, fold = s.Y(18) * 16,
            tilt = s.Y(8) * 16;
  // Each point `up` of the way from the floor to where it reaches.
  auto lift = [&](int x, int y) { return Point{x, floor - int(int64_t(floor - y) * up / 1024)}; };
  // Where it meets the body's side at its top edge: the dome's outline
  // between where the brim and the lap are, widening quickly and then
  // slowly.
  auto onSide = [&](const Point& brim, const Point& lap) {
    const int span = std::max(16, lap.y - brim.y), t = std::clamp(top - brim.y, 0, span) * 1024 / span;
    return brim.x + (lap.x - brim.x) * (1024 - (1024 - t) * (1024 - t) / 1024) / 1024;
  };
  const int left = onSide(at.brimL, at.lap[0]) - out, right = onSide(at.brimR, at.lap[kEnd]) + out;
  // Its side hanging from there to the floor, bulging over the body's
  // widest and flaring where it lands: a quadratic curve, `i` sixths down.
  auto hang = [&](int x0, const Point& lap, const Point& hem, int dir, int i, int y0) {
    const int x1 = lap.x + dir * out * 2, y1 = lap.y, x2 = hem.x + dir * out * 3, y2 = floor - s.Y(6) * 16;
    const int t = i * 1024 / 6, a = (1024 - t) * (1024 - t) / 1024, b = 2 * (1024 - t) * t / 1024, c = t * t / 1024;
    return Point{(a * x0 + b * x1 + c * x2) / 1024, (a * (top + y0) + b * y1 + c * y2) / 1024};
  };
  // Its top edge, the front of a ring round the body: lowest in the
  // middle, nearest you, and pulled up higher on its left. `u` from 0, its
  // left end, to 16, its right.
  auto edge = [&](int u, int below) {
    const int m = u - 8;
    return Point{left + (right - left) * u / 16, top + below + sag * (64 - m * m) / 64 + tilt * m / 8};
  };
  // Down its left side, along the floor in folds, up its right, and back
  // along the top.
  Point v[48];
  int n = 0;
  for (int i = 0; i < 6; ++i) {
    const Point d = hang(left, at.lap[0], at.hem[0], -1, i, -tilt);
    v[n++] = lift(d.x, d.y);
  }
  for (int i = 0; i <= kEnd; ++i) {
    const int flare = out * 3 * (2 * i - kEnd) / kEnd, ripple = s.Y(2) * 16 * (1000 + cosT(i * 1000 / 8)) / 1000;
    v[n++] = lift(at.hem[i].x + flare, std::max(at.hem[i].y + s.Y(4) * 16, floor - s.Y(6) * 16) + ripple);
  }
  for (int i = 5; i >= 0; --i) {
    const Point d = hang(right, at.lap[kEnd], at.hem[kEnd], 1, i, tilt);
    v[n++] = lift(d.x, d.y);
  }
  for (int u = 16; u >= 0; --u) {
    const Point e = edge(u, 0);
    v[n++] = lift(e.x, e.y);
  }
  r.polygon16(v, n, kBlanket);
  // The plaid, cut to it, and its creases running down from the fold.
  const int cx = (left + right) / 2;
  r.alpha = 90;
  for (int k = -4; k <= 4; ++k) {
    const int x = cx + k * w / 8, y = lift(0, floor - (k + 5) * w / 18).y;
    const Point down[] = {{x - 24, -100 * 16}, {x + 24, -100 * 16}, {x + 24, 600 * 16}, {x - 24, 600 * 16}};
    r.polygon16(down, 4, kPlaid, v, n);
    const Point across[] = {{-100 * 16, y - 24}, {900 * 16, y - 24}, {900 * 16, y + 24}, {-100 * 16, y + 24}};
    r.polygon16(across, 4, kPlaid, v, n);
  }
  r.alpha = 110;
  for (int k : {-1, 1}) {
    const Point from = edge(8 + k * 4, fold), to = {from.x + k * out, floor - s.Y(4) * 16};
    const Point crease[] = {lift(from.x, from.y), lift((from.x + to.x) / 2 + k * out / 2, (from.y + to.y) / 2),
                            lift(to.x, to.y)};
    r.stroke16(crease, 3, w / 80 + 16, kBlanketDark);
  }
  // The sheet turned down over its top, a wave along its lower edge.
  Point f[34];
  int m = 0;
  for (int u = 0; u <= 16; ++u) {
    const Point e = edge(u, 0);
    f[m++] = lift(e.x, e.y);
  }
  for (int u = 16; u >= 0; --u) {
    const int d = u - 8;
    const Point e = edge(u, fold * (128 - d * d) / 128 + s.Y(2) * 16 * sinT(u * 1000 / 6) / 1000);
    f[m++] = lift(e.x, e.y);
  }
  r.alpha = 255;
  r.polygon16(f, m, kCream, v, n);
  r.alpha = 120;
  r.stroke16(f + m / 2, m / 2, w / 90 + 12, kBlanketDark);
  r.alpha = 255;
}

void lookAround(const Stage& s, const PastimeShow& p) {
  if (const int a = window(int(p.age), 2500, int(p.ms), 120, 300)) {
    s.r.alpha = a;
    say(s.r, "?", s.crownX() + s.X(86), s.crownY() + s.Y(26), kCream, kLarge);
    s.r.alpha = 255;
  }
}

void hopeful(const Stage& s, const PastimeShow& p) {
  const int age = int(p.age);
  if (age < 300) return;
  s.r.alpha = window(age, 300, int(p.ms), 100, 300);
  const int x = s.crownX() + s.X(70), y = s.crownY() + s.Y(20);
  for (int i = 0; i < 3; ++i)
    if (age >= 300 + i * 300) s.r.disk(x + i * s.X(12), y, 3, kCream);
  if (age >= 1400) say(s.r, "?", x + s.X(42), y - 2, kCream, kLarge);
  s.r.alpha = 255;
}

void hop(const Stage& s, const PastimeShow& p) {
  constexpr int kEnd = rig::Anchors::kRingPoints - 1;
  for (int at : {560, 1100, 1640}) {
    const int age = int(p.age) - at;
    if (age < 0 || age > 450) continue;
    s.r.alpha = 200 - age * 200 / 450;
    for (const auto& h : {s.at.hem[0], s.at.hem[kEnd]}) {
      const int side = h.x < s.at.crown.x ? -1 : 1;
      s.r.disk(h.x / 16 + side * (4 + age / 18), h.y / 16 - 2, 3 + age / 90, kGrey);
    }
  }
  s.r.alpha = 255;
}

void blow(const Stage& s, const PastimeShow& p, int from, int popAt) {
  Raster& r = s.r;
  const int age = int(p.age);
  if (age < from) return;
  const int grow = eased(age, from, from + 1600), rise = eased(age, from + 1700, popAt);
  const int rad = 3 + grow * 22 / 1024;
  const int x = s.mouthX() + rise * s.X(30) / 1024 + wobble(age, 1100, 3) * rise / 1024;
  const int y = s.mouthY() + s.Y(4) + rad - rise * s.Y(150) / 1024;
  if (age < popAt) {
    bubble(r, x, y - rad + 2, rad);
  } else if (age < popAt + 500) {
    burst(r, x, y - rad, rad + 12, span(age, popAt, popAt + 500), kBubbleRim);
    r.alpha = window(age, popAt, popAt + 700, 60, 300);
    say(r, "pop!", x + s.X(30), y - rad - s.Y(10), kCream);
    r.alpha = 255;
  }
}

// Where the fly is `age` in: looping round its head, then off up and away.
Point flyAt(const Stage& s, int age) {
  if (age < 3600)
    return {s.eyesX() + s.X(150) * sinT(age * 1000 / 1600) / 1000,
            s.crownY() + s.Y(44) + s.Y(36) * sinT(age * 2000 / 1600) / 1000};
  const int k = eased(age, 3700, 4500);
  const Point from{s.eyesX() + s.X(150), s.crownY() + s.Y(44)};
  return {mix(from.x, s.X(540), k), mix(from.y, -s.Y(30), k)};
}

void fly(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  const Point f = flyAt(s, age);
  const int flap = (p.t / 40) % 2;
  r.alpha = 170;
  r.disk(f.x - 3, f.y - 4 - flap, 4, kWing);
  r.disk(f.x + 3, f.y - 4 - flap, 4, kWing);
  r.alpha = 255;
  r.disk(f.x, f.y, 3, kFly);
  if (age % 1200 < 500) say(r, "bzz", f.x + s.X(22), f.y - s.Y(12), kGrey);
}

// A heart drawn on the glass with a fingertip, then admired.
void doodle(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age), drawn = span(age, 600, 3000);
  const int cx = s.X(452), cy = s.Y(150), size = s.X(30);
  Point trail[33];
  int n = 0;
  for (int i = 0; i <= 32 && i * 1024 / 32 <= drawn; ++i) {
    // A heart's curve, from its notch round and back.
    const int t = i * 1000 / 32, sn = sinT(t), c = cosT(t);
    const int hx = 16 * sn / 1000 * sn / 1000 * sn / 1000;
    const int hy = (13 * c - 5 * cosT(2 * t) - 2 * cosT(3 * t) - cosT(4 * t)) / 1000;
    trail[n++] = {(cx + hx * size / 16) * 16, (cy - hy * size / 16) * 16};
  }
  r.alpha = 170;
  if (n > 1) r.stroke16(trail, n, 56, kShine);
  r.alpha = 255;
  if (age > 600 && age < 3000 && n) hand(r, trail[n - 1].x / 16, trail[n - 1].y / 16, 7);
  if (age >= 3000) {
    r.alpha = window(age, 3000, int(p.ms), 150, 400) * 80 / 255;
    r.disk(cx, cy - size / 6, size / 2, kHeart);
    r.alpha = 255;
  }
}

void book(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  const int open = eased(age, 0, 500) - eased(age, int(p.ms) - 600, int(p.ms));
  const int x = s.handX(), y = s.handY() - s.Y(26), w = 34 + 18 * open / 1024, h = 44;
  if (open < 100) {
    r.round(x - w, y - h / 2, 2 * w, h, 4, kBook);
  } else {
    r.round(x - w - 3, y - h / 2 - 2, 2 * w + 6, h + 5, 4, kBook);
    for (int side : {-1, 1}) {
      r.round(side < 0 ? x - w : x + 1, y - h / 2, w - 1, h, 3, kPage);
      for (int line = 0; line < 4; ++line)
        r.line({x + side * 8, y - h / 2 + 9 + line * 9}, {x + side * (w - 8), y - h / 2 + 9 + line * 9}, 1, kLine);
    }
    if (age >= 3600 && age < 4100) {
      // A page turning over, right to left.
      const int k = span(age, 3600, 4100), edge = x + (w - 2) * cosT(k * 500 / 1024) / 1000;
      const Point leaf[] = {
          {x, y - h / 2}, {edge, y - h / 2 - 6 * sinT(k * 500 / 1024) / 1000}, {edge, y + h / 2}, {x, y + h / 2}};
      r.polygon(leaf, 4, kPage);
      r.line({x, y - h / 2}, {x, y + h / 2}, 1, kLine);
    }
  }
  hand(r, x - w - 2, y + 6);
  hand(r, x + w + 2, y + 6);
}

void game(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  const int up = eased(age, 0, 400) - eased(age, int(p.ms) - 500, int(p.ms));
  const int x = s.handX(), y = s.handY() - s.Y(20) + (1024 - up) * s.Y(40) / 1024;
  r.round(x - 34, y - 18, 68, 36, 10, kConsole);
  r.round(x - 14, y - 12, 28, 22, 3, kScreen);
  r.round(x - 28, y - 2, 10, 3, 1, kInk);
  r.round(x - 24, y - 6, 3, 11, 1, kInk);
  r.disk(x + 22, y - 4, 3, kPepperoni);
  r.disk(x + 27, y + 2, 3, kCan);
  if (age < 3800) {
    // A dot hopping the blocks that come at it.
    const int bx = x + 12 - (age / 8) % 28, hopping = std::abs(bx - (x - 6)) < 6;
    r.round(bx, y + 2, 4, 6, 1, kLeafDark);
    r.round(x - 8, y + 4 - (hopping ? 7 : 0), 4, 4, 1, kInk);
  } else {
    say(r, "WIN", x, y - 1, kInk);
    r.alpha = window(age, 3800, int(p.ms), 100, 300);
    star(r, x, y - s.Y(40) - (age - 3800) / 30, 9, age / 2, kStar);
    r.alpha = 255;
  }
  hand(r, x - 36, y + 6);
  hand(r, x + 36, y + 6);
}

void water(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age), in = eased(age, 0, 600) - eased(age, int(p.ms) - 600, int(p.ms));
  const int x = mix(s.X(560), s.X(482), in), y = s.floorY() - s.Y(84);
  r.round(x - 15, y - 12, 32, 25, 6, kCan);
  r.line({x - 12, y + 4}, {x - 32, y - 10}, 5, kCan);
  r.disk(x - 33, y - 11, 4, kCan);
  r.line({x + 14, y - 10}, {x + 24, y + 4}, 4, kLeafDark);
  if (age > 900 && age < 2700)
    for (int i = 0; i < 6; ++i) {
      const int t = (age - 900 + i * 133) % 800, dy = y - 6 + t * t / 4000 + t / 40;
      if (dy > s.floorY() - s.Y(26)) continue;  // into the soil
      r.alpha = 255 - t * 200 / 800;
      r.disk(x - 34 - i % 3 * 4, dy, 3, kWater);
    }
  r.alpha = window(age, 2900, int(p.ms), 120, 400);
  if (r.alpha) sparkle(r, s.X(446), s.floorY() - s.Y(64), 7, kStar);
  r.alpha = 255;
}

void brb(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  const int up = eased(age, 0, 700) - eased(age, int(p.ms) - 800, int(p.ms) - 100);
  const int w = s.X(170), h = s.Y(62), x = s.eyesX() - w / 2;
  const int y = mix(s.Y(340), s.eyesY() + s.Y(20), up);
  r.round(x, y, w, h, 12, kCardInk);
  r.ring(x, y, w, h, 12, 2, kCardRim);
  say(r, "brb", x + w / 2, y + h / 2, kWords, kSign);
  hand(r, x, y + h / 2, 11);
  hand(r, x + w, y + h / 2, 11);
}

void tower(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age), base = s.floorY(), bw = 24, bh = 15;
  const int fall = span(age, 4400, 5100), wobbleAt = age >= 3900 && age < 4400 ? wobble(age, 160, 3) : 0;
  for (int i = 0; i < 6; ++i) {
    const int at = 200 + i * 600;
    if (age < at) break;
    const int drop = 1024 - eased(age, at, at + 300);
    int x = s.X(54) - bw / 2 + (i % 2 ? 3 : -3) + wobbleAt * i, y = base - (i + 1) * (bh + 1) - drop * 60 / 1024;
    if (fall > 0) {
      x += fall * (i + 1) * 9 / 1024;
      y = mix(y, base - bh - (i % 3) * 3, fall * fall / 1024);
    }
    r.round(x, y, bw, bh, 3, kBlocks[i]);
  }
  if (const int a = window(age, 4500, int(p.ms), 100, 400)) {
    r.alpha = a;
    say(r, "oops!", s.X(84), base - s.Y(116), kCream);
    r.alpha = 255;
  }
}

// A disco ball over its head, and its lights sweeping round.
void dance(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age), down = eased(age, 0, 500) - eased(age, int(p.ms) - 500, int(p.ms));
  const int x = s.X(251), y = -s.Y(20) + down * s.Y(44) / 1024;
  r.line({x, 0}, {x, y - 12}, 1, kGrey);
  r.disk(x, y, 13, kGrey);
  for (int i = 0; i < 6; ++i) {
    const int k = i * 167 + age / 3, gx = x + 9 * cosT(k) / 1000;
    if (sinT(k) > 0) r.disk(gx, y - 6 + (i % 3) * 6, 2, kLights[i % 4]);
  }
  for (int i = 0; i < 4; ++i) {
    const int k = i * 250 + age / 4;
    r.alpha = 50 * down / 1024;
    r.disk(s.X(251) + s.X(170) * cosT(k) / 1000, s.Y(180) + s.Y(90) * sinT(k) / 1000, 22, kLights[i]);
  }
  r.alpha = 255;
  for (int i = 0; i < 4; ++i) {
    const int t = age - 400 - i * 1100;
    if (t < 0 || t > 1400) continue;
    r.alpha = window(t, 0, 1400, 100, 500);
    note(r, (i % 2 ? s.rightX() + s.X(20) : s.leftX() - s.X(20)) + wobble(t, 700, 5), s.sideY() - t / 20, 4,
         kLights[i % 4]);
  }
  r.alpha = 255;
}

// Where the plane is `age` in, and which way it flies: from its hand,
// thrown, looping round the screen, then into its head.
Point planeAt(const Stage& s, int age, int& dir) {
  const Point from{s.handX() + s.X(40), s.handY() - s.Y(30)}, crown{s.crownX(), s.crownY() + s.Y(8)};
  if (age < 700) {
    dir = 875;
    return from;
  }
  if (age < 4100) {
    const int k = span(age, 700, 4100), turn = k * 1000 / 1024;
    dir = (turn + 250) % 1000;
    return {s.X(251) + s.X(190) * cosT(turn - 250) / 1000 * (1024 - k / 4) / 1024,
            s.Y(130) + s.Y(80) * sinT(turn - 250) / 1000};
  }
  const int k = eased(age, 4100, 4400);
  const Point loop{s.X(251), s.Y(50)};
  dir = 300;
  return {mix(loop.x, crown.x, k), mix(loop.y, crown.y, k)};
}

void paperPlane(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age);
  if (age < 700) hand(r, s.handX() + s.X(30), s.handY() - s.Y(20));
  if (age < 4400) {
    int dir = 0;
    const Point at = planeAt(s, age, dir);
    plane(r, at.x, at.y, dir);
    return;
  }
  // Bonk: stars round its head, and the plane on the floor.
  r.alpha = window(age, 4400, int(p.ms), 60, 300);
  for (int i = 0; i < 3; ++i) {
    const int k = i * 333 + (age - 4400);
    star(r, s.crownX() + s.X(60) * cosT(k) / 1000, s.crownY() + s.Y(12) + s.Y(12) * sinT(k) / 1000, 7, k, kStar);
  }
  r.alpha = 255;
  plane(r, s.X(380), s.floorY() - 4, 40);
}

void snore(const Stage& s, const PastimeShow& p, int popAt) {
  Raster& r = s.r;
  const int age = int(p.age);
  if (age < 400) return;
  const int breath = 1024 + sinT(age * 1000 / 1500 - 250) * 1024 / 1000;  // 0 … 2048
  const int grow = eased(age, 400, popAt);
  const int rad = 3 + (4 + 10 * grow / 1024) * breath / 2048;
  const int x = s.mouthX() + s.X(10) + rad, y = s.mouthY() + s.Y(2);
  if (age < popAt)
    bubble(r, x, y, rad);
  else if (age < popAt + 500)
    burst(r, x, y, rad + 10, span(age, popAt, popAt + 500), kBubbleRim);
}

void wave(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age), swing = wobble(age, 600, 14);
  constexpr int kEnd = rig::Anchors::kRingPoints - 1;
  const int side = std::max(s.rightX(), s.at.lap[kEnd].x / 16);
  const int x = side + s.X(30) + swing, y = s.eyesY() - s.Y(10) - std::abs(swing) / 3;
  hand(r, x, y, 11);
  r.alpha = 160;
  for (int i = 0; i < 2; ++i) {
    const int k = 1 + i;
    r.line({x + (swing > 0 ? 14 : -14) * k, y - 10 - 4 * k}, {x + (swing > 0 ? 18 : -18) * k, y - 2 - 4 * k}, 2,
           kCream);
  }
  r.alpha = 255;
}

void tap(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  for (int at : {500, 900, 1300}) {
    const int age = int(p.age) - at;
    if (age < 0 || age > 700) continue;
    const int rad = 6 + age / 14;
    r.alpha = 200 - age * 200 / 700;
    r.ring(s.eyesX() - rad, s.eyesY() - s.Y(4) - rad, 2 * rad, 2 * rad, rad, 2, kCream);
    if (age < 400) say(r, "tap", s.eyesX() + s.X(60), s.eyesY() - s.Y(40), kCream);
  }
  r.alpha = 255;
}

void watch(const Stage& s, const PastimeShow& p) {
  Raster& r = s.r;
  const int age = int(p.age), up = eased(age, 0, 400) - eased(age, int(p.ms) - 400, int(p.ms));
  const int x = s.mouthX() + s.X(84), y = s.mouthY() + (1024 - up) * s.Y(40) / 1024;
  r.line({x - s.X(30), y + s.Y(24)}, {x, y}, 1, kGold);
  r.disk(x, y, 14, kGold);
  r.disk(x, y, 11, kCream);
  r.round(x - 3, y - 19, 6, 5, 2, kGold);
  const int tick = age / 500 * 83;
  r.line({x, y}, {x + 8 * sinT(tick) / 1000, y - 8 * cosT(tick) / 1000}, 2, kInk);
  r.line({x, y}, {x + 5, y}, 2, kInk);
  hand(r, x - 12, y + 10, 7);
  if (const int a = window(age, 2500, 3500, 100, 400)) {
    r.alpha = a * 160 / 255;
    r.disk(s.mouthX() - s.X(40) - (age - 2500) / 30, s.mouthY() - s.Y(6), 8, kSteam);
    r.disk(s.mouthX() - s.X(50) - (age - 2500) / 30, s.mouthY() - s.Y(12), 6, kSteam);
  }
  if (const int a = window(age, 2800, int(p.ms), 120, 400)) {
    r.alpha = a;
    for (int i = 0; i < 3; ++i)
      if (age >= 2800 + i * 250) r.disk(s.crownX() - s.X(12) + i * s.X(12), s.crownY() + s.Y(8), 3, kCream);
  }
  r.alpha = 255;
}

void drowsy(const Stage& s, const PastimeShow& p) {
  const int age = int(p.age);
  if (age >= 1600 && age < 3900) {
    s.r.alpha = window(age, 1600, 3900, 300, 300);
    zs(s.r, s.X(424), s.Y(170), age - 1600);
  }
  if (const int a = window(age, 4000, int(p.ms), 60, 300)) {
    s.r.alpha = a;
    say(s.r, "!", s.crownX() + s.X(80), s.crownY() + s.Y(20), kAmber, kSign);
  }
  s.r.alpha = 255;
}

void rollOver(const Stage& s, const PastimeShow& p) {
  if (const int a = window(int(p.age), 1700, 2700, 200, 400)) {
    s.r.alpha = a;
    say(s.r, "mm", s.crownX() + s.X(80), s.crownY() + s.Y(30), kCream);
    s.r.alpha = 255;
  }
}

}  // namespace

int tuneNoteAge(uint32_t t, int side) {
  const uint32_t age = t % kTuneEveryMs, from = side ? kTuneGapMs : 0;
  return age >= from && age < from + kTuneNoteMs ? int(age - from) : -1;
}

bool showsScenery(const PastimeShow& show) { return show.plant; }

void paintScenery(Surface& surface, const PastimeShow& show) {
  if (!surface.pixels || !showsScenery(show)) return;
  Raster r{surface};
  rig::Anchors none;
  const Stage s{r, surface.width, surface.height, none};
  r.fade = show.plant;
  plant(r, s, show.grown, show.t, show.playing == Pastime::kWater ? wobble(int(show.age), 300, 2) : 0);
}

void paintWorn(Surface& surface, const PastimeShow& show, const rig::Anchors& at) {
  if (!surface.pixels) return;
  Raster r{surface};
  if (show.headphones) {
    r.fade = show.headphones;
    rig::Anchors up = at;
    for (rig::Point* q : {&up.crown, &up.brimL, &up.brimR, &up.eyeL, &up.eyeR}) q->y -= show.drop * 16;
    headphones(r, up);
    // Bopping's notes are its own; none while they come down.
    if (show.playing != Pastime::kBop && !show.drop) tune(r, at, show.t);
  }
}

Paws pawsFor(const PastimeShow& show) {
  Paws paws;
  const int age = int(show.age);
  switch (show.playing) {
    case Pastime::kDone:  // the right one up, and down on Enter
      paws.lift[1] = 60 * (eased(age, 0, 450) - eased(age, 450, 600)) / 1024;
      break;
    case Pastime::kPhonesOn:  // both up at its head, holding them
      paws.alpha[0] = paws.alpha[1] = 255 - window(age, 0, int(kPhonesOnMs) + 200, 150, 300);
      break;
    case Pastime::kReach:  // the right one has the mug
      paws.alpha[1] = 255 - window(age, 700, 4400, 200, 200);
      break;
    case Pastime::kMelt: {  // spread out and down with the puddle
      const int spread = eased(age, 600, 2300) - eased(age, 4200, 4900);
      paws.dx[0] = -70 * spread / 1024, paws.dx[1] = 70 * spread / 1024;
      paws.lift[0] = paws.lift[1] = -10 * spread / 1024;
      break;
    }
    case Pastime::kStretch:  // away with it, then up high
      paws.alpha[0] = paws.alpha[1] = 255 - window(age, 250, 9400, 200, 300);
      break;
    default: return paws;
  }
  // A pastime stopped early gives them back as it fades.
  for (int side : {0, 1}) {
    paws.lift[side] = paws.lift[side] * show.fade / 255;
    paws.alpha[side] = 255 - (255 - paws.alpha[side]) * show.fade / 255;
  }
  return paws;
}

void paintPastimes(Surface& surface, const PastimeShow& show, const rig::Anchors& at, const Engine& e) {
  if (!surface.pixels) return;
  Raster r{surface};
  const Stage s{r, surface.width, surface.height, at};
  // The desk's kit fades with the desk.
  const int desk = std::clamp((e.scenes.desk.x * 255).integer(), 0, 255);
  if (show.mug) {  // the top one's in its hand while it sips or reaches for it
    r.fade = show.mug * desk / 255;
    const bool held = show.playing == Pastime::kSip ||
                      (show.playing == Pastime::kReach && show.age >= kReachHolds && show.age < kReachLets);
    mugs(r, s, show.mugs - held, show.t);
  }
  if (show.zone) {
    r.fade = show.zone;
    motes(s, show.t);
  }
  r.fade = show.fade;
  if (!show.fade) return;
  switch (show.playing) {
    case Pastime::kSip: sip(s, show); break;
    case Pastime::kPeek: peek(s, show); break;
    case Pastime::kHum: hum(s, show); break;
    case Pastime::kPonder: ponder(s, show); break;
    case Pastime::kDone: done(s, show); break;
    case Pastime::kRead: read(s, show); break;
    case Pastime::kPhonesOn: phonesOn(s, show); break;
    case Pastime::kNod: nod(s, show); break;
    case Pastime::kBop: bop(s, show, show.headphones > 0); break;
    case Pastime::kDrum: drum(s, show); break;
    case Pastime::kSticky: sticky(s, show); break;
    case Pastime::kRefill: refill(s, show); break;
    case Pastime::kSnack: snack(s, show); break;
    case Pastime::kReach: reach(s, show); break;
    case Pastime::kMelt: melt(s, show); break;
    case Pastime::kStretch: stretch(s, show); break;
    case Pastime::kLookAround: lookAround(s, show); break;
    case Pastime::kHopeful: hopeful(s, show); break;
    case Pastime::kHop: hop(s, show); break;
    case Pastime::kBubble: blow(s, show, 300, 3400); break;
    case Pastime::kFly: fly(s, show); break;
    case Pastime::kDoodle: doodle(s, show); break;
    case Pastime::kBook: book(s, show); break;
    case Pastime::kGame: game(s, show); break;
    case Pastime::kWater: water(s, show); break;
    case Pastime::kBrb: brb(s, show); break;
    case Pastime::kTower: tower(s, show); break;
    case Pastime::kDance: dance(s, show); break;
    case Pastime::kPlane: paperPlane(s, show); break;
    case Pastime::kSnooze:
      zs(r, s.rightX() + s.X(8), s.sideY(), int(show.age));
      snore(s, show, 5000);
      break;
    case Pastime::kDream:
    case Pastime::kSheep: dream(s, s.X(392), s.Y(56), int(show.age)); break;
    case Pastime::kSnuggle:
      blanket(s, show);
      // Asked for asleep at night, the look's own Zs rise already.
      if (show.age > 1200 && layerContents(e).beside != kZs)
        zs(r, s.rightX() + s.X(8), s.sideY(), int(show.age) - 1200);
      break;
    case Pastime::kWave: wave(s, show); break;
    case Pastime::kTap: tap(s, show); break;
    case Pastime::kWatch: watch(s, show); break;
    case Pastime::kDrowsy: drowsy(s, show); break;
    case Pastime::kRollOver: rollOver(s, show); break;
    case Pastime::kSnoreBubble: snore(s, show, 4600); break;
    default: break;
  }
  r.fade = 255;
}

}  // namespace render::gel
