#include "render/gel/layers.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <initializer_list>

#include "render/font.h"
#include "render/gel/engine.h"
#include "render/gel/fixed.h"
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
// brim's front and its eyes, px.
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

constexpr uint16_t kNoteInk = rgb565(236, 232, 244);

// While music plays: a note rising from behind it, one at a time, every
// 3.2 s, from behind its shoulder on one side and then the other, drifting
// up over 3 s with a small sway and fading in and out, rimmed dark.
void notes(Raster& r, const rig::Anchors& at, uint32_t ms, int alpha) {
  constexpr int kEvery = 3200, kLife = 3000, kRise = 60, kSize = 6;
  const int n = int(ms / kEvery), age = int(ms % kEvery);
  if (age >= kLife) return;
  const int side = n % 2 ? 1 : -1;
  const Point sway = turn(age * 32 / 1500 % 32);
  const int x = at.crown.x / 16 + side * (48 + age * 12 / kLife) + 2 * sway.x / 4096;
  const int y = at.crown.y / 16 + 22 - age * kRise / kLife;
  r.alpha = alpha * std::min(255, std::min(age * 255 / 500, (kLife - age) * 255 / 1000)) / 255;
  // Behind the body: only what has come up over its shoulder shows.
  r.bounds = {0, 0, 1 << 30, at.crown.y / 16 + 12};
  for (int pass = 0; pass < 2; ++pass) {
    const uint16_t ink = pass ? kNoteInk : kCardInk;
    const int grow = pass ? 0 : 2;
    r.disk(x - kSize + 1, y + kSize + 2, kSize + grow, ink);
    r.line({x, y + kSize + 2}, {x, y - kSize * 2 - 2}, 2 + 2 * grow, ink);
    r.line({x, y - kSize * 2 - 2}, {x + kSize + 3, y - kSize}, 3 + 2 * grow, ink);
  }
  r.bounds = Raster::kEverywhere;
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

// While you speak: the sound coming in to its ear on `side`, from the
// Mac's side, a steady stream. Three arcs, each bowed toward the ear as a
// wave from far off is, a third of its nod's beat apart (`ms` into it), so
// two or three always show: each comes in from kFrom px out to the rim of
// the hand there (or with none, of its ear) over the whole beat, from
// kTall px tall and faint to kShort and whole, and is caught there, one at
// the nod's dip, kCaught into the beat. 3 px pale strokes, five points.
void heard(Raster& r, const Engine& e, const rig::Anchors& at, int side, uint32_t ms, int alpha) {
  constexpr int kBeat = 1600, kCaught = 700, kGone = 120;
  constexpr int kFrom = 70, kBow = 40, kTall = 40, kShort = 26;
  const Hand& hand = handsPlan().moved[side > 0];
  const bool held = e.ear && (e.ear > 0) == (side > 0) && hand.shown();
  const Ears ear = ears(at);
  const Point to = held ? Point{hand.x16, hand.y16}
                        : Point{(side > 0 ? ear.right + 6 : ear.left - 6) * 16, ear.y * 16};
  // Into the palm a little: a wave's caught, not stopped at its edge.
  const int rim16 = held ? hand.drawn16() * 4 / 5 : 8 * 16;
  for (int i = 0; i < 3; ++i) {
    const int age = int((ms + kBeat - kCaught + uint32_t(i) * kBeat / 3) % kBeat);  // 0 far out … kBeat caught
    const int in = age * 1000 / kBeat;
    // Faint far out, whole near; gone into the palm over its last kGone ms.
    const int fade = std::min(90 + in * 165 / 1000, (kBeat - age) * 255 / kGone);
    r.alpha = alpha * fade / 255;
    // The arc's circle, out beyond it from the ear: a wave going in, `tall`
    // px from end to end (its half kBow * sin(span), span in a turn's 4096ths).
    const int near16 = rim16 + (kFrom * 16 - rim16) * (1000 - in) / 1000;
    const int cx = to.x + side * (near16 + kBow * 16), cy = to.y;
    const int tall = kTall + (kShort - kTall) * in / 1000;
    const int span = tall * 4096 / (2 * kBow) * 1000 / 6283;  // asin(x) ~ x, near enough here
    Point arc[5];
    for (int k = 0; k < 5; ++k) {
      const int a = -span + k * span / 2;
      arc[k] = {cx - side * kBow * sinTurn(a + 1024) * 16 / 4096, cy + kBow * sinTurn(a) * 16 / 4096};
    }
    r.stroke16(arc, 5, 3 * 16, kShine);
  }
  r.alpha = 255;
}

void paintWith(Raster& r, const Engine& e, const rig::Anchors& at) {
  const Engine::With& w = e.with;
  if (w.heard) heard(r, e, at, w.side, w.heardMs, w.heard);
  if (w.notes) notes(r, at, w.notesMs, w.notes);
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
  paintWith(r, e, at);
  if (e.typingAlong) typingTicks(r, at, e.typingPhase, e.typingFast);
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
