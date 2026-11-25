#include "render/gel/stream.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>

#include "render/font.h"
#include "render/gel/engine.h"
#include "render/gel/lane.h"
#include "render/gel/raster.h"
#include "render/gel/subpixel.h"
#include "render/palette.h"
#include "render/tags.h"

namespace render::gel {

namespace {

// Where on the surface things sit, in px of a 502 × 410 surface, scaled to
// the one drawn on.
struct Layout {
  int w, h;
  int x(int p) const { return w * p / 502; }
  int y(int p) const { return h * p / 410; }
  // Sixteenths of a pixel of the 502 × 410 surface, as sixteenths of this
  // one's: what moves is placed in them (render/gel/subpixel.h).
  int x16(int p16) const { return w * p16 / 502; }
  int y16(int p16) const { return h * p16 / 410; }
};

// Where a word forward comes from, px of the 502 × 410 surface: the desk's
// monitor, whose work it is (paintProps draws the monitor).
constexpr int kMonitorX = 96, kMonitorY = 262;

// The props' inks, and a few of the stream's own.
constexpr uint16_t kNavy = 0x10E8, kGrey = 0x8410;

uint16_t laneInk(uint8_t slot) { return kLaneInk[slot % Stream::kLanes]; }

// The ink a word forward is drawn in: a failure's red, a drop's grey, else
// its lane's.
uint16_t callInk(const Stream::Call& c) {
  switch (c.style) {
    case CallStyle::kBonk:
    case CallStyle::kBonk2:
    case CallStyle::kBonk3:
    case CallStyle::kThrow:
    case CallStyle::kNo:
    case CallStyle::kTimeout: return kFailInk;
    case CallStyle::kDrop: return kGrey;
    default: return laneInk(c.slot);
  }
}

// Text centred on (cx16, cy16), sixteenths of a pixel, in `f`, at r's
// alpha. Its cells' corner is a whole
// pixel when the middle is, so text at rest is crisp; on a surface of
// another size, scaled to it.
void centred16(Raster& r, const Font& f, int cx16, int cy16, const char* s, uint16_t ink) {
  const int left16 = cx16 - glyphCount(s) * f.w / 2 * 16, top16 = cy16 - f.h / 2 * 16;
  if (r.s.width == 502 && r.s.height == 410) return text16(r, f, left16, top16, s, ink);
  bool ascii = true;
  for (const char* p = s; *p && ascii; ++p) ascii = *p >= 32 && *p <= 126;
  if (ascii)
    r.text(s, cx16 >> 4, cy16 >> 4, ink, f);
  else
    text(r, f, left16 >> 4, top16 >> 4, s, ink);
}
void centred(Raster& r, const Font& f, int cx, int cy, const char* s, uint16_t ink) {
  centred16(r, f, cx * 16, cy * 16, s, ink);
}

// The cosine of s fortieths of a turn, in thousandths; its sine.
int cos40(int s) {
  static constexpr int kQuarter[11] = {1000, 988, 951, 891, 809, 707, 588, 454, 309, 156, 0};
  s = ((s % 40) + 40) % 40;
  const int q = s / 10, i = s % 10;
  return q == 0 ? kQuarter[i] : q == 1 ? -kQuarter[10 - i] : q == 2 ? -kQuarter[i] : kQuarter[10 - i];
}
int sin40(int s) { return cos40(s - 10); }

int lerp(int a, int b, int num, int den) { return den <= 0 ? b : a + (b - a) * num / den; }
// num/den eased in (quadratic) or out, as a fraction of den.
int easeIn(int num, int den) { return den <= 0 ? den : int(int64_t(num) * num / den); }
int easeOut(int num, int den) { return den <= 0 ? den : den - easeIn(den - num, den); }
// 255 from `from` ms before `end`, fading to 0 at `end`.
int fadeBy(int at, int end, int over) { return std::clamp((end - at) * 255 / std::max(1, over), 0, 255); }

void star(Raster& r, int cx, int cy, int radius, int turn, uint16_t ink) {
  Point v[10];
  for (int i = 0; i < 10; ++i) {
    const int k = i * 4 + turn, rr = i % 2 ? radius * 2 / 5 : radius;
    v[i] = {cx + rr * cos40(k) / 1000, cy + rr * sin40(k) / 1000};
  }
  r.polygon(v, 10, ink);
}

// Four sparkles twinkling round (cx, cy), `ms` in.
void twinkle(Raster& r, const Layout& l, int cx, int cy, int ms, int alpha) {
  for (int i = 0; i < 4; ++i) {
    const int phase = (ms / 60 + i * 3) % 8, size = l.x(phase < 4 ? 3 + phase * 2 : 11 - (phase - 4) * 2);
    r.alpha = alpha;
    star(r, cx + l.x(46) * cos40(i * 10 + 5) / 1000, cy + l.y(30) * sin40(i * 10 + 5) / 1000, size, ms / 50, kStarInk);
  }
}

// Dizzy eyes: each eye hidden under the body's own colour, a spiral turning
// over it.
void dizzy(Raster& r, Surface& s, const Layout& l, const rig::Anchors& at, int ms, int alpha) {
  const int mx = (at.eyeL.x + at.eyeR.x) / 32, my = (at.eyeL.y + at.eyeR.y) / 32 - l.y(8);
  if (mx < 0 || mx >= s.width || my < 0 || my >= s.height) return;
  const uint16_t skin = s.pixels[my * s.width + mx];
  for (const auto& eye : {at.eyeL, at.eyeR}) {
    const int ex = eye.x / 16, ey = eye.y / 16;
    r.alpha = alpha;
    r.disk(ex, ey, l.x(13), skin);
    Point spiral[24];
    for (int i = 0; i < 24; ++i) {
      const int rad = l.x(2) * 16 + i * l.x(11) * 16 / 24, turn = i * 3 + ms / 18 * (eye.x == at.eyeL.x ? 1 : -1);
      spiral[i] = {eye.x + rad * cos40(turn) / 1000, eye.y + rad * sin40(turn) / 1000};
    }
    r.stroke16(spiral, 24, l.x(3) * 16, kNavy);
  }
}

}  // namespace

namespace {

// The whole turn's moments: its word gulped down at a turn's end, or
// dropped when it's stopped or has failed.
void moment(Raster& r, const Layout& l, const Stream& stream, const rig::Anchors& at, int age, uint16_t ink,
            const char* word) {
  const auto& c = stream.call;
  const int flight = int(callFlightMs(c.style)), end = int(Stream::kCallMs);
  const int eyesX = (at.eyeL.x + at.eyeR.x) / 32, eyesY = (at.eyeL.y + at.eyeR.y) / 32;
  const int crownX = at.crown.x / 16, crownY = at.crown.y / 16;
  const int mouthX = eyesX, mouthY = eyesY + l.y(36);
  switch (callMove(c.style)) {
    case CallMove::kGather: {  // from the monitor into its mouth, and a happy "mm!"
      const int k = easeIn(std::min(age, flight), flight);
      if (age < flight) {
        r.alpha = 255 - k * 155 / flight;
        centred16(r, kLarge, lerp(l.x(kMonitorX) * 16, mouthX * 16, k, flight),
                  lerp(l.y(kMonitorY) * 16, mouthY * 16, k, flight), word, ink);
      }
      if (age >= flight && age < flight + 900) {
        r.alpha = fadeBy(age, flight + 900, 300);
        centred(r, kSign, mouthX + l.x(70), mouthY - l.y(30), "mm!", kStarInk);
        twinkle(r, l, mouthX, mouthY, age, r.alpha);
      }
      break;
    }
    case CallMove::kDrop: {  // switched off: its word drops onto its crown
      r.alpha = fadeBy(age, end, 500);
      centred16(r, kSign, crownX * 16, (crownY - l.y(40)) * 16 + l.y16(std::min(age, 400) * 16 / 20), word, ink);
      break;
    }
    default: break;
  }
}

}  // namespace

void paintStreamFront(Surface& surface, const Stream& stream, const rig::Anchors& at, uint32_t t) {
  const auto& c = stream.call;
  const int age = int(int32_t(t - c.at));
  if (!surface.pixels || !stream.drawn(t) || !c.live || age < 0 || age >= int(Stream::kCallMs)) return;
  const Layout l{surface.width, surface.height};
  Raster r{surface};
  const Font& big = bubbleFont();
  const CallMove move = callMove(c.style);
  const int flight = int(callFlightMs(c.style)), after = age - flight, end = int(Stream::kCallMs);
  const uint16_t ink = callInk(c);
  switch (move) {
    case CallMove::kGather:
    case CallMove::kDrop: moment(r, l, stream, at, age, ink, c.text); return;
    default: break;
  }

  // From the monitor to where it lands on the body.
  const int fromX = l.x(kMonitorX), fromY = l.y(kMonitorY);
  const int eyesX = (at.eyeL.x + at.eyeR.x) / 32, eyesY = (at.eyeL.y + at.eyeR.y) / 32;
  const int crownX = at.crown.x / 16, crownY = at.crown.y / 16;
  const bool right = fromX >= surface.width / 2;
  const int sideX = (right ? at.brimR.x : at.brimL.x) / 16 + l.x(right ? 48 : -48), sideY = at.brimR.y / 16;
  int toX = crownX, toY = crownY - l.y(18);
  switch (move) {
    case CallMove::kHit: toX = eyesX, toY = eyesY; break;
    case CallMove::kShrug: toX = sideX, toY = sideY; break;
    case CallMove::kShatter: toY = crownY - l.y(50); break;
    default: break;
  }

  // In flight: a c.text from the monitor.
  if (after < 0) {
    const int k = easeIn(age, flight);
    // In sixteenths of a pixel.
    int x = lerp(fromX * 16, toX * 16, k, flight), y = lerp(fromY * 16, toY * 16, k, flight);
    r.alpha = 255;
    centred16(r, big, x, y, c.text, ink);
    return;
  }

  switch (move) {
    case CallMove::kHit: {
      // It sticks a moment, then slides off (or is thrown back up), under
      // stars; a hit dizzies it, more up the ladder.
      if (c.style == CallStyle::kThrow && after >= 250) {
        const int k = std::min(400, after - 250);
        r.alpha = 255 - k * 255 / 400;
        centred16(r, big, lerp(toX * 16, fromX * 16, easeOut(k, 400), 400),
                  lerp(toY * 16, -l.y(40) * 16, easeOut(k, 400), 400), c.text, ink);
      } else {
        const int slide = std::max(0, after - 250), k = std::min(450, slide);
        r.alpha = 255 - k * 255 / 450;
        if (r.alpha > 2)
          centred16(r, big, toX * 16 + l.x16(k * 16 / 30), toY * 16 + l.y16(easeIn(k, 450) * 160 * 16 / 450), c.text,
                    ink);
      }
      const int daze = c.style == CallStyle::kBonk2                              ? 1300
                       : c.style == CallStyle::kThrow                            ? 700
                       : c.style == CallStyle::kNo || c.style == CallStyle::kTimeout ? 0
                                                                             : 1000;
      if (after < daze) dizzy(r, surface, l, at, after, fadeBy(after, daze, 200));
      if (c.style == CallStyle::kNo || c.style == CallStyle::kTimeout) break;
      const int stars = c.style == CallStyle::kBonk ? 3 : 5;
      if (after < 1100) {
        r.alpha = fadeBy(after, 1100, 200);
        for (int i = 0; i < stars; ++i) {
          const int turn = after / 40 + i * 40 / stars;
          const int cx = crownX + l.x(70) * cos40(turn) / 1000, cy = crownY - l.y(10) + l.y(14) * sin40(turn) / 1000;
          star(r, cx, cy, l.x(13), turn % 10, kStarInk);
        }
      }
      break;
    }
    case CallMove::kSink: {  // it sinks into the crown, a ring spreading out
      const int k = std::min(320, after);
      r.alpha = 255 - k * 255 / 320;
      if (r.alpha > 2) centred16(r, big, toX * 16, toY * 16 + l.y16(k * 34 * 16 / 320), c.text, ink);
      if (after < 500) {
        const int radius = l.x(20 + after * 90 / 500);
        r.alpha = 160 - after * 160 / 500;
        r.ring(crownX - radius, crownY - radius / 4, 2 * radius, radius / 2, radius / 4, 2, ink);
      }
      break;
    }
    case CallMove::kShrug: {  // beside its head, as it shrugs
      r.alpha = fadeBy(after, 1600, 300);
      if (r.alpha >= 3) centred(r, big, toX, toY, c.text, ink);
      break;
    }
    case CallMove::kShatter: {  // bursting into its glyphs, which it swallows
      const char* p = c.text;
      const int n = std::max(1, glyphCount(c.text)), mouthX = eyesX, mouthY = eyesY + l.y(36);
      for (int i = 0, g; (g = nextGlyph(p)) >= 0; ++i) {
        const int out = easeOut(std::min(220, after), 220), in = easeIn(std::clamp(after - 320, 0, 480), 480);
        // In sixteenths of a pixel.
        const int bx = (toX + (i - n / 2) * kLarge.w) * 16 + l.x16(70 * 16) * cos40(i * 5) / 1000 * out / 220;
        const int by = toY * 16 + l.y16(46 * 16) * sin40(i * 5) / 1000 * out / 220;
        r.alpha = 255 - in * 200 / 480;
        char one[2] = {char(g + 0x20), 0};
        if (g + 0x20 < 0x7f)
          centred16(r, kLarge, lerp(bx, mouthX * 16, in, 480), lerp(by, mouthY * 16, in, 480), one, ink);
      }
      break;
    }
  }
}

}  // namespace render::gel
