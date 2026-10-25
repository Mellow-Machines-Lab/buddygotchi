#include "render/gel/stream.h"

#include <algorithm>
#include <cstdio>

#include "render/font.h"
#include "render/gel/engine.h"
#include "render/gel/lane.h"
#include "render/gel/raster.h"
#include "render/palette.h"

namespace render::gel {

namespace {

// Where on the surface things sit, in px of a 502 × 410 surface, scaled to
// the one drawn on.
struct Layout {
  int w, h;
  int x(int p) const { return w * p / 502; }
  int y(int p) const { return h * p / 410; }
  // A lane's column's middle, by its place among the lanes showing.
  int column(const Stream& s, uint8_t slot) const {
    const int i = s.column(slot), n = std::max(1, s.laneCount);
    return i < 0 ? w / 2 : w * (2 * i + 1) / (2 * n);
  }
};

constexpr int kTop = 26;  // where words start falling, under the lanes' names

uint16_t laneInk(uint8_t slot) { return kLaneInk[slot % Stream::kLanes]; }

// The ink a word forward is drawn in: a failure's red, a pass's green, else
// its lane's.
uint16_t callInk(const Stream::Call& c) {
  switch (c.gag) {
    case CallGag::kBonk:
    case CallGag::kBonk2:
    case CallGag::kHelmet:
    case CallGag::kThrow:
    case CallGag::kNo:
    case CallGag::kTimeout:
    case CallGag::kHail: return kFailInk;
    case CallGag::kPass:
    case CallGag::kBuilt: return kPassInk;
    default: return laneInk(c.slot);
  }
}

// Text centred on (cx, cy) in `f`, at r's alpha.
void centred(Raster& r, const Font& f, int cx, int cy, const char* s, uint16_t ink) {
  text(r, f, cx - glyphCount(s) * f.w / 2, cy - f.h / 2, s, ink);
}

// The cosine of s fortieths of a turn, in thousandths.
int cos40(int s) {
  static constexpr int kQuarter[11] = {1000, 988, 951, 891, 809, 707, 588, 454, 309, 156, 0};
  s %= 40;
  const int q = s / 10, i = s % 10;
  return q == 0 ? kQuarter[i] : q == 1 ? -kQuarter[10 - i] : q == 2 ? -kQuarter[i] : kQuarter[10 - i];
}

int lerp(int a, int b, int num, int den) { return den <= 0 ? b : a + (b - a) * num / den; }
// num/den eased in (quadratic) or out, as a fraction of den.
int easeIn(int num, int den) { return den <= 0 ? den : int(int64_t(num) * num / den); }
int easeOut(int num, int den) { return den <= 0 ? den : den - easeIn(den - num, den); }

void star(Raster& r, int cx, int cy, int radius, int turn, uint16_t ink) {
  Point v[10];
  // Ten points round, every other one in: sin and cos in thousandths, a
  // tenth of a turn apart, turned by `turn` tenths.
  static constexpr int kCos[10] = {1000, 809, 309, -309, -809, -1000, -809, -309, 309, 809};
  static constexpr int kSin[10] = {0, 588, 951, 951, 588, 0, -588, -951, -951, -588};
  for (int i = 0; i < 10; ++i) {
    const int k = (i + turn) % 10, rr = i % 2 ? radius * 2 / 5 : radius;
    v[i] = {cx + rr * kCos[k] / 1000, cy + rr * kSin[k] / 1000};
  }
  r.polygon(v, 10, ink);
}

// The desk's monitor's screen, as the props draw it, and how much the desk
// shows.
struct Screen {
  int x, y, w, h, alpha;
};
Screen screen(const Surface& s, const Engine& e) {
  auto x = [&](int p) { return s.width * p / 1000; };
  auto y = [&](int p) { return s.height * p / 1000; };
  return {x(114), y(611), x(156), y(89), (e.scenes.desk.x * 255).integer()};
}

// The monitor answering the word forward: a test run's spinner, then its
// result; a build's crawl; a deploy's count; a crack that grows with the
// failures' ladder.
void monitor(Raster& r, const Surface& s, const Engine& e, const Stream::Call& c, uint32_t age) {
  const Screen m = screen(s, e);
  const int flight = int(callFlightMs(c.gag));
  // The screen answers a check, and a failure up the ladder; anything else
  // leaves it to the props.
  switch (c.gag) {
    case CallGag::kCross:
    case CallGag::kStack:
    case CallGag::kLaunch:
    case CallGag::kBonk2:
    case CallGag::kHelmet:
    case CallGag::kThrow: break;
    case CallGag::kPass:
    case CallGag::kBuilt:
    case CallGag::kHail:
      if (int(age) >= flight) break;
      return;
    default: return;
  }
  if (m.alpha < 8) return;
  const int cx = m.x + m.w / 2, cy = m.y + m.h / 2;
  r.alpha = m.alpha;
  r.bounds = {m.x, m.y, m.x + m.w, m.y + m.h};
  if (c.gag != CallGag::kBonk2 && c.gag != CallGag::kHelmet && c.gag != CallGag::kThrow)
    r.round(m.x, m.y, m.w, m.h, 6, rgb565(7, 24, 32));
  switch (c.gag) {
    case CallGag::kCross:
      for (int i = 0; i < 8; ++i) {  // a spinner: eight dots, one bright going round
        static constexpr int kCos[8] = {1000, 707, 0, -707, -1000, -707, 0, 707};
        static constexpr int kSin[8] = {0, 707, 1000, 707, 0, -707, -1000, -707};
        const int lit = int(age / 90) % 8, ink = (i - lit + 8) % 8;
        r.disk(cx + 12 * kCos[i] / 1000, cy + 12 * kSin[i] / 1000, 2, ink == 0 ? 0xFFFF : rgb565(70, 110, 130));
      }
      break;
    case CallGag::kStack: {  // a bar that crawls and never says how far
      const int span = m.w - 16, at = int(age / 8) % (span + 30) - 30;
      r.round(m.x + 8, cy - 4, span, 8, 4, rgb565(30, 60, 75));
      r.round(m.x + 8 + std::max(0, at), cy - 4, std::min(30, span - std::max(0, at)), 8, 4, laneInk(c.slot));
      break;
    }
    case CallGag::kLaunch: {
      char n[2] = {char('3' - std::min(2, int(age) / 450)), 0};
      if (int(age) < 1350) centred(r, kLarge, cx, cy, n, kStarInk);
      break;
    }
    case CallGag::kPass:
    case CallGag::kBuilt:
      if (int(age) >= flight) {
        const Point tick[3] = {{cx - 12, cy}, {cx - 3, cy + 9}, {cx + 14, cy - 10}};
        r.line(tick[0], tick[1], 4, kPassInk), r.line(tick[1], tick[2], 4, kPassInk);
      }
      break;
    case CallGag::kHail:
      if (int(age) >= flight) {
        r.line({cx - 11, cy - 11}, {cx + 11, cy + 11}, 4, kFailInk);
        r.line({cx + 11, cy - 11}, {cx - 11, cy + 11}, 4, kFailInk);
      }
      break;
    case CallGag::kBonk2:
    case CallGag::kHelmet:
    case CallGag::kThrow: {  // a crack, longer up the ladder
      const int rungs = c.gag == CallGag::kBonk2 ? 2 : c.gag == CallGag::kHelmet ? 3 : 4;
      const Point crack[6] = {{m.x + 6, m.y + 8},       {m.x + 20, m.y + 16}, {m.x + 30, m.y + 12},
                              {m.x + 44, m.y + 24},     {m.x + 56, m.y + 20}, {m.x + m.w - 6, m.y + m.h - 6}};
      for (int i = 0; i + 1 < std::min(6, rungs + 2); ++i) r.line(crack[i], crack[i + 1], 1, 0xFFFF);
      break;
    }
    default: break;
  }
  r.bounds = Raster::kEverywhere;
}

}  // namespace

void paintStreamBehind(Surface& surface, const Stream& stream, uint32_t t) {
  if (!surface.pixels || !stream.on) return;
  const Layout l{surface.width, surface.height};
  Raster r{surface};
  // Each lane's name along the top, in its colour.
  for (int i = 0; i < stream.laneCount; ++i) {
    const auto& lane = stream.lanes[i];
    r.alpha = 170;
    centred(r, kSmall, l.column(stream, lane.slot), l.y(13), lane.label, laneInk(lane.slot));
  }
  // The words, dim, easing in as they leave the name and out before the lane.
  for (const auto& w : stream.words) {
    const int age = int(int32_t(t - w.born));
    if (!w.live || age < 0 || age >= int(Stream::kFallMs)) continue;
    const int y = l.y(kTop) + l.y(int(int64_t(age) * w.speed / 1000));
    const int in = std::min(255, age * 255 / 200), out = std::min(255, (int(Stream::kFallMs) - age) * 255 / 600);
    r.alpha = std::min(in, out) * 110 / 255;
    if (r.alpha < 3) continue;
    centred(r, kLarge, l.column(stream, w.slot) + l.x(w.dx), y, w.text, laneInk(w.slot));
  }
}

void paintStreamFront(Surface& surface, const Stream& stream, const rig::Anchors& at, const Engine& e, uint32_t t) {
  const auto& c = stream.call;
  const int age = int(int32_t(t - c.at));
  if (!surface.pixels || !stream.on || !c.live || age < 0 || age >= int(Stream::kCallMs)) return;
  const Layout l{surface.width, surface.height};
  Raster r{surface};
  monitor(r, surface, e, c, uint32_t(age));
  const Font& big = bubbleFont();
  const CallMove move = callMove(c.gag);
  const int flight = int(callFlightMs(c.gag)), after = age - flight;
  const uint16_t ink = callInk(c);
  char word[Stream::kWordBytes + 8];
  if (c.gag == CallGag::kCombo)
    std::snprintf(word, sizeof(word), "%s x%u", c.text, unsigned(c.count));
  else
    std::snprintf(word, sizeof(word), "%s", c.text);

  // From its lane's name to where it lands on the body.
  const int fromX = l.column(stream, c.slot), fromY = l.y(kTop);
  const int eyesX = (at.eyeL.x + at.eyeR.x) / 32, eyesY = (at.eyeL.y + at.eyeR.y) / 32;
  const int crownX = at.crown.x / 16, crownY = at.crown.y / 16;
  const bool right = fromX >= surface.width / 2;
  int toX = crownX, toY = crownY - l.y(18);
  switch (move) {
    case CallMove::kHit: toX = eyesX, toY = eyesY; break;
    case CallMove::kShrug: toX = (right ? at.brimR.x : at.brimL.x) / 16 + l.x(right ? 44 : -44), toY = at.brimR.y / 16; break;
    case CallMove::kShatter: toY = crownY - l.y(50); break;
    case CallMove::kCheer: toY = crownY - l.y(46); break;
    case CallMove::kDesk: {
      const Screen m = screen(surface, e);
      toX = m.x + m.w / 2, toY = m.y - l.y(14);
      break;
    }
    default: break;
  }

  if (after < 0) {  // in flight
    const bool rises = move == CallMove::kCheer;
    const int k = rises ? easeOut(age, flight) : easeIn(age, flight);
    r.alpha = 255;
    centred(r, big, lerp(fromX, toX, k, flight), lerp(fromY, toY, k, flight), word, ink);
    return;
  }

  switch (move) {
    case CallMove::kHit: {
      // It sticks a moment, then slides off (or is thrown back up).
      if (c.gag == CallGag::kThrow && after >= 250) {
        const int k = std::min(400, after - 250);
        r.alpha = 255 - k * 255 / 400;
        centred(r, big, lerp(toX, fromX, easeOut(k, 400), 400), lerp(toY, -l.y(40), easeOut(k, 400), 400), word, ink);
      } else {
        const int slide = std::max(0, after - 250), k = std::min(450, slide);
        r.alpha = 255 - k * 255 / 450;
        if (r.alpha > 2) centred(r, big, toX + l.x(k / 30), toY + l.y(easeIn(k, 450) * 160 / 450), word, ink);
      }
      // Stars round its head, more up the ladder; a helmet on the third.
      const int stars = c.gag == CallGag::kBonk ? 3 : 5;
      if (after < 1100) {
        r.alpha = after < 900 ? 255 : (1100 - after) * 255 / 200;
        for (int i = 0; i < stars; ++i) {
          const int turn = (after / 40 + i * 40 / stars) % 40;  // 40 steps a turn
          const int cx = crownX + l.x(70) * cos40(turn) / 1000, cy = crownY - l.y(10) + l.y(14) * cos40(turn + 30) / 1000;
          star(r, cx, cy, l.x(13), turn % 10, kStarInk);
        }
      }
      if (c.gag == CallGag::kHelmet && after < 1500) {
        r.alpha = after < 1300 ? 255 : (1500 - after) * 255 / 200;
        // A dome on the crown, its brim down over the brow.
        const int hw = l.x(70), drop = l.y(std::max(0, 160 - after) / 4);
        r.round(crownX - hw, crownY - l.y(10) - drop, 2 * hw, l.y(44), l.y(30), rgb565(150, 160, 170));
        r.round(crownX - hw - l.x(8), crownY + l.y(26) - drop, 2 * hw + l.x(16), l.y(9), l.y(4), rgb565(95, 105, 115));
        r.disk(crownX - l.x(26), crownY + l.y(4) - drop, l.x(6), rgb565(230, 235, 240));
      }
      break;
    }
    case CallMove::kSink: {  // it sinks into the crown, a ring spreading out
      const int k = std::min(320, after);
      r.alpha = 255 - k * 255 / 320;
      if (r.alpha > 2) centred(r, big, toX, toY + l.y(k * 34 / 320), word, ink);
      if (after < 500) {
        const int radius = l.x(20 + after * 90 / 500);
        r.alpha = 160 - after * 160 / 500;
        r.ring(crownX - radius, crownY - radius / 4, 2 * radius, radius / 2, radius / 4, 2, ink);
      }
      break;
    }
    case CallMove::kShrug: {  // beside its head, and an empty bubble over it
      const int fade = std::max(0, after - 1300);
      r.alpha = std::max(0, 255 - fade * 255 / 300);
      if (r.alpha < 3) break;
      centred(r, big, toX, toY, word, ink);
      const int bx = toX - l.x(32), by = toY - l.y(64), bw = l.x(64), bh = l.y(32);
      r.round(bx, by, bw, bh, bh / 2, 0xFFFF);
      for (int i = -1; i <= 1; ++i) r.disk(toX + i * l.x(14), by + bh / 2, l.x(4), rgb565(40, 40, 40));
      break;
    }
    case CallMove::kShatter: {  // bursting into its glyphs, which it swallows
      const char* p = word;
      const int n = std::max(1, glyphCount(word)), mouthX = eyesX, mouthY = eyesY + l.y(36);
      for (int i = 0, g; (g = nextGlyph(p)) >= 0; ++i) {
        static constexpr int kCos[8] = {1000, 707, 0, -707, -1000, -707, 0, 707};
        static constexpr int kSin[8] = {0, 707, 1000, 707, 0, -707, -1000, -707};
        const int out = easeOut(std::min(220, after), 220), in = easeIn(std::clamp(after - 320, 0, 480), 480);
        const int bx = toX + (i - n / 2) * kLarge.w + l.x(70) * kCos[i % 8] / 1000 * out / 220;
        const int by = toY + l.y(46) * kSin[i % 8] / 1000 * out / 220;
        r.alpha = 255 - in * 200 / 480;
        char one[2] = {char(g + 0x20), 0};
        if (g + 0x20 < 0x7f) centred(r, kLarge, lerp(bx, mouthX, in, 480), lerp(by, mouthY, in, 480), one, ink);
      }
      break;
    }
    case CallMove::kHail: {  // more of them, raining on its head and bouncing off
      for (int i = 0; i < 5; ++i) {
        const int start = i * 180 - (i ? flight : 0), a = after - start;
        if (a < -flight || a > 400) continue;
        const int dx = l.x((i * 53) % 140 - 70);
        if (a < 0) {
          const int k = easeIn(a + flight, flight);
          r.alpha = 255;
          centred(r, kSign, crownX + dx, lerp(fromY, toY, k, flight), "FAIL", ink);
        } else {
          r.alpha = 255 - a * 255 / 400;
          const int side = dx < 0 ? -1 : 1;
          centred(r, kSign, crownX + dx + side * l.x(a * 90 / 400), toY - l.y(a * 60 / 400) + l.y(a * a / 1600), "FAIL", ink);
        }
      }
      break;
    }
    case CallMove::kCheer: {  // over its head, and confetti
      r.alpha = after < 1500 ? 255 : std::max(0, 255 - (after - 1500) * 255 / 400);
      if (r.alpha > 2) centred(r, big, toX, toY - l.y(std::min(after, 300) / 15), word, ink);
      if (after < 1300)
        for (int i = 0; i < 28; ++i) {
          const int vx = ((i * 97) % 200) - 100, vy = -60 - (i * 61) % 120, s = after;
          const int px = toX + l.x(vx * s / 1000), py = toY + l.y(vy * s / 1000 + 260 * s / 1000 * s / 1000);
          r.alpha = 255 - after * 255 / 1300;
          r.round(px, py, l.x(7), l.y(4), 1, i % 2 ? kLaneInk[i % Stream::kLanes] : kStarInk);
        }
      break;
    }
    case CallMove::kDesk: {  // it settles on the monitor
      r.alpha = std::max(0, 255 - after * 255 / 400);
      if (r.alpha > 2) centred(r, kSign, toX, toY + l.y(after * 10 / 400), word, ink);
      break;
    }
  }
}

}  // namespace render::gel
