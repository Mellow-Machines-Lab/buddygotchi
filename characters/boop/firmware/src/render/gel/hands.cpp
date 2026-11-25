#include "render/gel/hands.h"

#include <algorithm>

#include "render/gel/fixed.h"
#include "render/gel/painter.h"
#include "render/palette.h"

namespace render::gel {

namespace {

// The gel's inks, as the body's material has them about where a hand sits:
// the shadow it casts on what's behind it, its pale rim, as the dome's,
// the gel in shadow and in light, and its shine; the contact patch's pale fill and its rim. Each turned to the buddy's
// colour (bodyColor), as the body is.
constexpr uint16_t kShade = rgb565(8, 30, 66), kEdge = rgb565(150, 214, 255);
constexpr uint16_t kDeep = rgb565(43, 127, 214), kGel = rgb565(74, 163, 240);
constexpr uint16_t kLight = rgb565(124, 198, 255), kShine = rgb565(236, 248, 255);
constexpr uint16_t kPatch = rgb565(216, 241, 255), kPatchRim = rgb565(240, 250, 255);

int of(int v, int q12) { return int(int64_t(v) * q12 / 4096); }

HandsPlan gPlan;

// The hand's outline as a pen: a disk, or flat, a short bar of the same
// pen, which strokes a pad wider than tall with round ends.
struct Pad {
  int x16, y16, half16, radius16;
  void fill(Raster& r, int grow16, int dx16, int dy16, int scale, uint16_t ink) const {
    const int rad = std::max(8, of(radius16, scale) + grow16), half = of(half16, scale);
    const Point ends[2] = {{x16 + dx16 - half, y16 + dy16}, {x16 + dx16 + half, y16 + dy16}};
    if (half > 0)
      r.stroke16(ends, 2, 2 * rad, ink);
    else
      r.disk16(x16 + dx16, y16 + dy16, rad, ink);
  }
};

}  // namespace

HandsPlan& handsPlan() { return gPlan; }

void paintHand(Raster& r, const Hand& h) {
  if (!h.shown()) return;
  const int color = bodyColorIndex();
  auto ink = [&](uint16_t c) { return tinted(c, color); };
  const int R = h.drawn16(), palm = std::max(0, h.shape), fist = std::max(0, -h.shape), g = h.glass;
  // A fist is a little tighter; flat, it's wider and lower.
  const int radius = of(R, 4096 - of(500, fist));
  const Pad pad{h.x16, h.y16, of(of(radius, 2250), h.flat), of(radius, 4096 - of(1850, h.flat))};
  const int base = r.alpha;
  r.alpha = base * h.alpha / 255;
  // Its fingertips, an open palm's: three small disks over its top, out
  // as it opens, the middle one highest.
  const int cosT = sinTurn(h.turn + 1024), sinT = sinTurn(h.turn);
  auto turned = [&](int ux, int uy) {  // a point (ux, uy) of the hand's own,
                                       // turned, in 16ths from its middle
    return Point{int((int64_t(ux) * cosT - int64_t(uy) * sinT) / 4096),
                 int((int64_t(ux) * sinT + int64_t(uy) * cosT) / 4096)};
  };
  Point tips[3];
  const int tipR = of(of(radius, 1360), palm);
  for (int i = 0; i < 3; ++i) {
    const int a = -1460 + i * 440;  // about up, 4096ths of a turn, the outer two splayed
    tips[i] = turned(of(of(radius, 3700), sinTurn(a + 1024)), of(of(radius, 3700), sinTurn(a)));
  }
  // The rim, then the gel: darker low and to its right, lighter up and to
  // its left, where the light comes from; on the glass it pales and evens.
  // Fading (a part's or the layer's opacity), it's one flat shape, so it
  // fades as evenly as any other; whole, it's shaded.
  if ((r.fade >= 255 ? r.alpha : r.alpha * r.fade / 255) * h.alpha / 255 < 250) {
    if (tipR >= 12)
      for (const Point& t : tips) r.disk16(h.x16 + t.x, h.y16 + t.y, tipR, ink(kGel));
    pad.fill(r, 0, 0, 0, 4096, ink(kGel));
    r.alpha = base;
    return;
  }
  // Its shadow, down and to its right, so it reads apart from the body it's
  // in front of; less on the glass, where it's flat.
  r.alpha = base * h.alpha / 255 * (110 - of(60, g)) / 255;
  pad.fill(r, 16, 24, 40, 4096, kShade);
  r.alpha = base * h.alpha / 255;
  if (tipR >= 12)
    for (const Point& t : tips) r.disk16(h.x16 + t.x, h.y16 + t.y, tipR + 20, ink(kEdge));
  pad.fill(r, 20, 0, 0, 4096, ink(kEdge));
  if (tipR >= 12)
    for (const Point& t : tips) r.disk16(h.x16 + t.x, h.y16 + t.y, tipR, ink(kDeep));
  pad.fill(r, 0, 0, 0, 4096, ink(kDeep));
  const int lit = 4096 - of(2600, g);
  pad.fill(r, 0, -of(radius, 300), -of(radius, 380), 3500, ink(mix565(kGel, kPatch, of(120, g))));
  r.alpha = base * h.alpha / 255 * lit / 4096;
  pad.fill(r, 0, -of(radius, 1100), -of(radius, 1300), 1900, ink(kLight));
  if (tipR >= 12)
    for (const Point& t : tips)
      r.disk16(h.x16 + t.x - of(tipR, 1200), h.y16 + t.y - of(tipR, 1400), of(tipR, 2000), ink(kLight));
  r.alpha = base * h.alpha / 255 * 200 / 255 * lit / 4096;
  r.disk16(h.x16 - of(radius, 1500) + of(pad.half16, -2048), h.y16 - of(radius, 1700), std::max(16, of(radius, 600)),
           kShine);
  // On the glass: its contact patch, pale, rimmed, where it presses.
  if (g > 0) {
    const int patch = of(radius, fist > 2048 ? 2150 : 2500);
    r.alpha = base * h.alpha / 255 * of(80, g) / 255;
    r.disk16(h.x16, h.y16 + of(radius, 250), patch, kPatch);
    r.alpha = base * h.alpha / 255 * of(140, g) / 255;
    Point ring[25];
    for (int i = 0; i <= 24; ++i) {
      const int a = i * 4096 / 24;
      ring[i] = {h.x16 + of(patch, sinTurn(a + 1024)), h.y16 + of(radius, 250) + of(patch, sinTurn(a))};
    }
    r.stroke16(ring, 25, 24, kPatchRim);
  }
  r.alpha = base;
}

Hand gripping(int x, int y, int side, int px) {
  Hand h;
  // Its rim and shadow inside the `px` its holder leaves it.
  h.x16 = x * 16 + 8, h.y16 = y * 16 + 8, h.radius16 = (px - 2) * 16;
  h.turn = side < 0 ? -700 : 700;  // its crease toward the card
  h.shape = -1500;                 // curled round its edge
  return h;
}

Hand holdingUp(int x, int y, int side, int px) {
  Hand h = gripping(x, y, side, px);
  h.turn = side < 0 ? -400 : 400;
  return h;
}

Hand cupped(const rig::Anchors& at, int side) {
  // Beside its ear, its open palm toward the sound, fingertips leaning in.
  const int ear = side > 0 ? at.brimR.x : at.brimL.x, earY = (at.brimF.y + at.eyeL.y) / 2;
  Hand h;
  h.x16 = ear + side * 14 * 16, h.y16 = earY;
  h.radius16 = 15 * 16;
  h.shape = 2900, h.turn = -side * 300;
  return h;
}

Hand onKeys(int x, int y, int px) {
  Hand h;
  h.x16 = x * 16 + 8, h.y16 = y * 16 + 8, h.radius16 = px * 16;
  h.flat = 4096;
  return h;
}

Hand hung(int x, int y) {
  Hand h;
  h.x16 = x * 16 + 8, h.y16 = y * 16 + 8, h.radius16 = 13 * 16;
  h.shape = 3300, h.turn = 2048;  // its fingertips over the edge, down
  return h;
}

Hand fromRig(const rig::Channels& c, const rig::Anchors& at, int side, int scale) {
  using rig::HandPart;
  const auto ch = [&](HandPart p) { return int(c[rig::hand(side, p)]); };
  Hand h;
  // Canvas px to the panel's as the body's own lift and x are: 128 a body
  // unit at its middle, of kPxPerUnit (render/gel/painter.h).
  const int px16 = 16 * 128, unit = kPxPerUnit;
  h.x16 = at.handF.x + of(ch(HandPart::kX) * px16 / unit, scale);
  h.y16 = at.handF.y - of(ch(HandPart::kY) * px16 / unit, scale);
  h.radius16 = of(ch(HandPart::kSize) * kHandPx * 16 / 1000, scale);
  h.shape = ch(HandPart::kShape) * 4096 / 1000;
  h.glass = ch(HandPart::kGlass) * 4096 / 1000;
  return h;
}

}  // namespace render::gel
