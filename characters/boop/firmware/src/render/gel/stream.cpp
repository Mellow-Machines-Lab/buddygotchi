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
  // A lane's name's middle, by its place among the lanes showing
  // (render::laneX): clear of the head and its hat.
  int column(const Stream& s, uint8_t slot) const { return x(laneX(s.column(slot), s.laneCount)); }
};

constexpr int kTop = 10;  // where words start falling, from the top edge

// The props' inks, and a few of the stream's own.
constexpr uint16_t kPaper = 0xFFDE, kPaperLine = 0xA554, kNavy = 0x10E8, kBrick = 0xC3CA, kBrickRim = 0x8A26,
                   kPot = 0x3186, kSteel = 0x9CF3, kSmoke = 0x8410, kRocketRed = 0xE9A6, kFlame = 0xFD20, kIce = 0xA6FF,
                   kGrey = 0x8410;

uint16_t laneInk(uint8_t slot) { return kLaneInk[slot % Stream::kLanes]; }

// The ink a word forward is drawn in: a failure's red, a pass's green, a
// freeze's ice, a drop's grey, else its lane's.
uint16_t callInk(const Stream::Call& c) {
  switch (c.gag) {
    case CallGag::kBonk:
    case CallGag::kBonk2:
    case CallGag::kHelmet:
    case CallGag::kThrow:
    case CallGag::kNo:
    case CallGag::kTimeout:
    case CallGag::kHail:
    case CallGag::kTopple:
    case CallGag::kBuried: return kFailInk;
    case CallGag::kPass:
    case CallGag::kBuilt: return kPassInk;
    case CallGag::kFreeze: return kIce;
    case CallGag::kDrop: return kGrey;
    default: return laneInk(c.slot);
  }
}

// Where a falling word is at t, on a 502 × 410 surface's coordinates scaled
// to `l`'s: its middle, in sixteenths of a pixel.
Point wordAt(const Layout& l, const Stream::Word& w, uint32_t t) {
  const int age = std::max(0, int(int32_t(t - w.born)));
  return {l.x(w.x) * 16, l.y(kTop) * 16 + l.y16(int(int64_t(age) * w.speed * 16 / 1000))};
}

// Text centred on (cx16, cy16), sixteenths of a pixel, in `f`, at r's
// alpha (`behind`: only onto the background's black, so a word behind the
// body costs nothing to draw, clear or push). Its cells' corner is a whole
// pixel when the middle is, so text at rest is crisp; on a surface of
// another size, scaled to it.
void centred16(Raster& r, const Font& f, int cx16, int cy16, const char* s, uint16_t ink, bool behind = false) {
  const int left16 = cx16 - glyphCount(s) * f.w / 2 * 16, top16 = cy16 - f.h / 2 * 16;
  if (r.s.width == 502 && r.s.height == 410) return text16(r, f, left16, top16, s, ink, behind);
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

// A puff: grey balls swelling, rising and thinning, `ms` in of `over`, in
// sixteenths of a pixel.
void puff(Raster& r, const Layout& l, int cx, int cy, int ms, int over) {
  const int grow = std::min(ms, over);
  r.alpha = fadeBy(ms, over, over);
  for (int i = 0; i < 6; ++i)
    r.disk16(cx * 16 + 8 + l.x16(22 * 16) * cos40(i * 7) / 1000 * grow / over,
             cy * 16 + 8 + l.y16(14 * 16) * sin40(i * 7) / 1000 * grow / over - l.y16(grow * 16 / 40),
             l.x16((8 + (i % 3) * 2) * 16 + grow * 160 / over) + 8, kSmoke);
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

// A tower of `n` bricks on the desk's right end, its bottom at `base`,
// leaning `lean` px at its top and `fall` (0–1000) of the way to (toX, toY).
void tower(Raster& r, const Layout& l, int n, int base, int lean, int fall, int toX, int toY) {
  const int bw = l.x(46), bh = l.y(15), x0 = l.x(456);
  for (int i = 0; i < n; ++i) {
    const int bx = x0 - bw / 2 + lean * i / std::max(1, n - 1) + (i % 2 ? l.x(4) : -l.x(4)),
              by = base - (i + 1) * (bh + 2);
    const int fx = lerp(bx, toX - bw / 2 + (i - n / 2) * l.x(14), fall, 1000);
    const int fy = lerp(by, toY - (n - i) * l.y(6), easeIn(fall, 1000), 1000);
    r.round(fx, fy, bw, bh, l.y(3), kBrick);
    r.ring(fx, fy, bw, bh, l.y(3), 1, kBrickRim);
  }
}

// The two numbers of an edit's word, `edit +18 -2`: lines added, removed.
void editSize(const char* word, int& added, int& removed) {
  added = removed = 0;
  for (const char* p = word; *p; ++p) {
    if (*p == '+') added = std::atoi(p + 1);
    if (*p == '-' && p[1] >= '0' && p[1] <= '9') removed = std::atoi(p + 1);
  }
}

// The monitor answering the word forward: a check's spinner, crawl, count,
// tick or cross; a failure's crack up the ladder; the page a lookup reads
// scrolling; an edit's lines as bars; a globe for the web.
void monitor(Raster& r, const Surface& s, const Engine& e, const Stream::Call& c, int age) {
  const Screen m = screen(s, e);
  const int flight = int(callFlightMs(c.gag));
  const bool landed = age >= flight;
  switch (c.gag) {
    case CallGag::kCross:
    case CallGag::kStack:
    case CallGag::kLaunch:
    case CallGag::kBonk2:
    case CallGag::kHelmet:
    case CallGag::kThrow:
    case CallGag::kLook:
    case CallGag::kPlane:
    case CallGag::kLand: break;
    case CallGag::kPass:
    case CallGag::kBuilt:
    case CallGag::kHail:
    case CallGag::kTopple:
      if (landed) break;
      return;
    default: return;
  }
  if (m.alpha < 8) return;
  const int cx = m.x + m.w / 2, cy = m.y + m.h / 2;
  const bool crack = c.gag == CallGag::kBonk2 || c.gag == CallGag::kHelmet || c.gag == CallGag::kThrow;
  r.alpha = m.alpha;
  r.bounds = {m.x, m.y, m.x + m.w, m.y + m.h};
  if (!crack) r.round(m.x, m.y, m.w, m.h, 6, rgb565(7, 24, 32));
  switch (c.gag) {
    case CallGag::kCross:
      for (int i = 0; i < 8; ++i) {  // a spinner: eight dots, one bright going round
        const int lit = age / 90 % 8, on = (i - lit + 8) % 8;
        r.disk(cx + 12 * cos40(i * 5) / 1000, cy + 12 * sin40(i * 5) / 1000, 2,
               on == 0 ? 0xFFFF : rgb565(70, 110, 130));
      }
      break;
    case CallGag::kStack: {  // a bar that crawls and never says how far, in sixteenths of a pixel
      const int span = (m.w - 16) * 16, at = age * 2 % (span + 30 * 16) - 30 * 16;
      const int from = std::max(0, at), to = std::min(span, at + 30 * 16);
      r.round(m.x + 8, cy - 4, span / 16, 8, 4, rgb565(30, 60, 75));
      round16(r, (m.x + 8) * 16 + from, (cy - 4) * 16, to - from, 8 * 16, 4 * 16, laneInk(c.slot));
      break;
    }
    case CallGag::kLaunch: {  // the count to lift off
      char n[2] = {char('3' - std::min(2, age / 300)), 0};
      if (age < 900)
        centred(r, kLarge, cx, cy, n, kStarInk);
      else
        centred(r, kSmall, cx, cy, "LIFTOFF", kFlame);
      break;
    }
    case CallGag::kPass:
    case CallGag::kBuilt: {
      const Point tick[3] = {{cx - 12, cy}, {cx - 3, cy + 9}, {cx + 14, cy - 10}};
      r.line(tick[0], tick[1], 4, kPassInk), r.line(tick[1], tick[2], 4, kPassInk);
      break;
    }
    case CallGag::kHail:
    case CallGag::kTopple:
      r.line({cx - 11, cy - 11}, {cx + 11, cy + 11}, 4, kFailInk);
      r.line({cx + 11, cy - 11}, {cx - 11, cy + 11}, 4, kFailInk);
      break;
    case CallGag::kLook:  // a page scrolling past, in sixteenths of a pixel, a line lit as it's read
      for (int i = 0; i < 6; ++i) {
        const int y16 = (m.y + 4) * 16 + ((i * 8 * 16 - age * 16 / 25) % (48 * 16) + 48 * 16) % (48 * 16);
        round16(r, (m.x + 8) * 16, y16, (20 + (i * 37) % 44) * 16, 3 * 16, 16,
                i == 2 ? laneInk(c.slot) : rgb565(110, 160, 180));
      }
      break;
    case CallGag::kLand: {  // an edit's lines: green added, red removed, to scale
      int added = 0, removed = 0;
      editSize(c.text, added, removed);
      if (!added && !removed) break;
      auto bar = [&](int n) { return std::min(m.w - 30, 6 + n * (m.w - 36) / std::max(40, std::max(added, removed))); };
      const int grow = easeOut(std::min(400, age), 400);  // in sixteenths of a pixel
      round16(r, (m.x + 8) * 16, (cy - 9) * 16, bar(added) * 16 * grow / 400, 7 * 16, 3 * 16, kPassInk);
      round16(r, (m.x + 8) * 16, (cy + 3) * 16, bar(removed) * 16 * grow / 400, 7 * 16, 3 * 16, kFailInk);
      break;
    }
    case CallGag::kPlane: {  // a globe turning
      const int rad = 14, spin = age / 30;
      r.ring(cx - rad, cy - rad, 2 * rad, 2 * rad, rad, 2, laneInk(c.slot));
      for (int k = 0; k < 2; ++k) {
        const int wx = std::abs(rad * cos40(spin + k * 20) / 1000);
        if (wx > 2) r.ring(cx - wx, cy - rad, 2 * wx, 2 * rad, wx, 1, laneInk(c.slot));
      }
      r.line({cx - rad, cy}, {cx + rad, cy}, 1, laneInk(c.slot));
      break;
    }
    default: {  // a crack, longer up the ladder
      const int rungs = c.gag == CallGag::kBonk2 ? 2 : c.gag == CallGag::kHelmet ? 3 : 4;
      const Point at[6] = {{m.x + 6, m.y + 8},   {m.x + 20, m.y + 16}, {m.x + 30, m.y + 12},
                           {m.x + 44, m.y + 24}, {m.x + 56, m.y + 20}, {m.x + m.w - 6, m.y + m.h - 6}};
      for (int i = 0; i + 1 < std::min(6, rungs + 2); ++i) r.line(at[i], at[i + 1], 1, 0xFFFF);
      break;
    }
  }
  r.bounds = Raster::kEverywhere;
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

void paintStreamBehind(Surface& surface, const Stream& stream, uint32_t t) {
  if (!surface.pixels || !stream.drawn(t)) return;
  const Layout l{surface.width, surface.height};
  Raster r{surface};  // which stops at the lane's top
  // The words, dim, easing in as they come from the top and out before the
  // lane, falling in sixteenths of a pixel; held where they are, icy, while
  // a freeze lasts. A word the word forward takes is its to draw.
  for (const auto& w : stream.words) {
    if (!w.live || stream.taken(w)) continue;
    const bool held = stream.frozen() && int32_t(w.born - stream.call.at) <= 0;
    const int age = int(int32_t((held ? stream.call.at : t) - w.born));
    if (age < 0 || age >= int(Stream::kFallMs)) continue;
    const Point at = wordAt(l, w, held ? stream.call.at : t);
    const int in = std::min(255, age * 255 / 200), out = std::min(255, (int(Stream::kFallMs) - age) * 255 / 600);
    r.alpha = held ? 170 : std::min(in, out) * 110 / 255;
    if (r.alpha < 3) continue;
    centred16(r, kLarge, at.x, at.y, w.text, held ? kIce : laneInk(w.slot), true);
  }
}

void paintStreamDesk(Surface& surface, const Stream& stream, const Engine& e, const Strip& strip, uint32_t t) {
  // Only while the Mac plays the stream: it sends a lane for each agent at
  // work.
  if (!surface.pixels || !stream.on || stream.laneCount == 0) return;
  const Layout l{surface.width, surface.height};
  Raster r{surface};
  const Screen m = screen(surface, e);
  // While no lane has counted a new call for a while: a thought cloud.
  const int quiet = int(int32_t(t - stream.movedAt)) - int(Stream::kThinkMs);
  if (quiet >= 0 && !stream.call.live && isDesk(e.scenes.route.state)) {
    const int cx = l.x(330), cy = l.y(50), in = std::min(255, quiet * 255 / 400);
    r.alpha = in;
    r.disk(l.x(290), l.y(96), l.x(4), 0xFFFF);
    r.disk(l.x(302), l.y(80), l.x(6), 0xFFFF);
    for (int i = 0; i < 5; ++i)
      r.disk(cx + l.x(18) * cos40(i * 8) / 1000, cy + l.y(10) * sin40(i * 8) / 1000, l.x(16), 0xFFFF);
    const int dots = int(t / 400 % 4);
    for (int i = 0; i < 3; ++i)
      r.disk(cx - l.x(14) + i * l.x(14), cy, l.x(3), i < dots ? kNavy : rgb565(200, 200, 200));
  }
  if (m.alpha < 8) return;
  r.alpha = m.alpha;
  // The to-do list's progress along the screen's foot, and the turn's clock
  // in its corner, amber from the fourth tier (5 minutes of the agents'
  // working stretch).
  if (strip.todoTotal > 0) {
    const int span = m.w - 12, done = span * std::clamp(strip.todoDone, 0, strip.todoTotal) / strip.todoTotal;
    r.round(m.x + 6, m.y + m.h - 6, span, 3, 1, rgb565(30, 60, 75));
    if (done > 0) r.round(m.x + 6, m.y + m.h - 6, done, 3, 1, kPassInk);
  }
  const uint32_t secs = (t - stream.since) / 1000;
  if (secs >= 60) {
    char clock[8];
    std::snprintf(clock, sizeof(clock), "%u:%02u", unsigned(secs / 60 % 100), unsigned(secs % 60));
    const uint16_t ink = hasTag(e.scenes.when, "tier4") ? rgb565(239, 189, 103) : rgb565(110, 160, 180);
    r.bounds = {m.x, m.y, m.x + m.w, m.y + m.h};
    r.text(clock, m.x + m.w - glyphCount(clock) * kSmall.w / 2 - 4, m.y + 10, ink, kSmall);
    r.bounds = Raster::kEverywhere;
  }
}

namespace {

// The whole turn's moments, played over the words falling as the word came:
// gathered into its mouth at a turn's end, squashed into a cube that thuds
// onto the desk at a compaction, dropped when it's stopped, held icy at a
// rate limit, or piled up to its eyes as bricks when its context runs out.
void moment(Raster& r, const Layout& l, const Stream& stream, const rig::Anchors& at, int age, uint16_t ink,
            const char* word) {
  const auto& c = stream.call;
  const int flight = int(callFlightMs(c.gag)), end = int(Stream::kCallMs);
  const int eyesX = (at.eyeL.x + at.eyeR.x) / 32, eyesY = (at.eyeL.y + at.eyeR.y) / 32;
  const int crownX = at.crown.x / 16, crownY = at.crown.y / 16, deskY = l.y(305);
  const int mouthX = eyesX, mouthY = eyesY + l.y(36);
  // The words it takes, from where they were as it came, in sixteenths of
  // a pixel; with none on screen, and `own`, its own word from its lane's
  // name.
  int taken = 0;
  for (const auto& w : stream.words) taken += stream.taken(w);
  auto each = [&](bool own, auto&& draw) {
    for (const auto& w : stream.words)
      if (stream.taken(w)) draw(wordAt(l, w, c.at), w.text, laneInk(w.slot));
    if (!taken && own) draw(Point{l.column(stream, c.slot) * 16, l.y(kTop) * 16}, word, ink);
  };
  switch (callMove(c.gag)) {
    case CallMove::kGather: {  // into its mouth, and a happy "mm!"
      const int k = easeIn(std::min(age, flight), flight);
      each(age < flight, [&](Point p, const char* s, uint16_t in) {
        r.alpha = 255 - k * 155 / flight;
        centred16(r, kLarge, lerp(p.x, mouthX * 16, k, flight), lerp(p.y, mouthY * 16, k, flight), s, in);
      });
      if (age >= flight && age < flight + 900) {
        r.alpha = fadeBy(age, flight + 900, 300);
        centred(r, kSign, mouthX + l.x(70), mouthY - l.y(30), "mm!", kStarInk);
        twinkle(r, l, mouthX, mouthY, age, r.alpha);
      }
      break;
    }
    case CallMove::kCompact: {  // squashed together over its head, then a cube that drops onto the desk
      const int cubeX = crownX, cubeY = l.y(70), squash = 500, side = l.x(56);
      if (age < squash) {
        const int k = easeIn(age, squash);
        each(true, [&](Point p, const char* s, uint16_t in) {
          r.alpha = 255 - k * 200 / squash;
          centred16(r, kLarge, lerp(p.x, cubeX * 16, k, squash), lerp(p.y, cubeY * 16, k, squash), s, in);
        });
      }
      if (age >= squash - 120) {
        const int fall = easeIn(std::clamp(age - squash, 0, flight - squash), flight - squash);
        // In sixteenths of a pixel, the cube's corner a whole pixel once it's landed.
        const int bounce = age > flight && age < flight + 200 ? l.y16(6 * 16) * sin40((age - flight) / 10) / 1000 : 0;
        const int x = lerp(cubeX * 16, l.x(456) * 16, fall, flight - squash) - side * 8,
                  y = lerp(cubeY * 16, (deskY - side / 2) * 16, fall, flight - squash) - side * 8 - std::abs(bounce);
        r.alpha = std::min(fadeBy(age, end, 400), std::min(255, (age - squash + 120) * 255 / 120));
        round16(r, x, y, side * 16, side * 16, l.x16(8 * 16), rgb565(55, 65, 85));
        for (int i = 0; i < 3; ++i)
          round16(r, x + l.x16(7 * 16), y + l.y16((10 + i * 14) * 16), (side - l.x(14)) * 16, l.y16(7 * 16),
                  l.y16(3 * 16), kLaneInk[(c.slot + i) % Stream::kLanes]);
        centred16(r, kSmall, x + side * 8, y - l.y16(12 * 16), "context", rgb565(200, 210, 230));
      }
      break;
    }
    case CallMove::kDrop: {  // switched off: the words fall away, grey
      each(false, [&](Point p, const char* s, uint16_t) {
        r.alpha = std::max(0, 200 - age * 200 / 700);
        const int y = p.y + l.y16(int(int64_t(age) * age * 900 * 16 / 1000000));
        if (r.alpha > 2) centred16(r, kLarge, p.x, y, s, kGrey);
      });
      r.alpha = fadeBy(age, end, 500);
      centred16(r, kSign, crownX * 16, (crownY - l.y(40)) * 16 + l.y16(std::min(age, 400) * 16 / 20), word, ink);
      break;
    }
    case CallMove::kFreeze: {  // the words held icy (paintStreamBehind), a snowflake, and a poke
      r.alpha = fadeBy(age, end, 400);
      const int fx = crownX, fy = crownY - l.y(52);
      centred(r, kSign, fx, fy, word, ink);
      const int sx = fx + glyphCount(word) * kSign.w / 2 + l.x(22), sy = fy, arm = l.x(12), spin = age / 60;
      for (int i = 0; i < 3; ++i)
        r.line({sx - arm * cos40(spin + i * 13) / 1000, sy - arm * sin40(spin + i * 13) / 1000},
               {sx + arm * cos40(spin + i * 13) / 1000, sy + arm * sin40(spin + i * 13) / 1000}, l.x(2), kIce);
      break;
    }
    case CallMove::kBuried: {  // bricks of its words piling up, to its eyes
      const int bw = l.x(70), bh = l.y(18), rows = std::max(1, (deskY - eyesY) / bh), perRow = 4;
      const int count = rows * perRow, x0 = crownX - perRow * bw / 2;
      const char* texts[Stream::kWords + 1];
      int n = 0;
      for (const auto& w : stream.words)
        if (w.live) texts[n++] = w.text;
      if (!n) texts[n++] = "...";
      r.alpha = fadeBy(age, end, 400);
      const int a = r.alpha;
      for (int i = 0; i < count; ++i) {
        const int due = i * flight / count, k = std::min(150, age - due);
        if (k < 0) break;
        const int row = i / perRow, col = i % perRow, shift = row % 2 ? bw / 2 : 0;
        // Each brick drops its last 150 px gathering speed, in sixteenths of
        // a pixel.
        const int x = x0 + col * bw + shift - bw / 4,
                  y16 = (deskY - (row + 1) * bh) * 16 - l.y16((150 - easeIn(k, 150)) * 16);
        r.alpha = a;
        round16(r, (x + 1) * 16, y16 + 16, (bw - 2) * 16, (bh - 2) * 16, l.y16(4 * 16),
                mix565(0, kLaneInk[(row + col) % Stream::kLanes], 150));
        r.alpha = a * 3 / 4;
        centred16(r, kSmall, (x + bw / 2) * 16, y16 + bh / 2 * 16, texts[i % n], 0xFFFF);
      }
      r.alpha = a;
      centred(r, kSign, crownX, crownY - l.y(46), word, ink);
      break;
    }
    default: break;
  }
}

}  // namespace

void paintStreamFront(Surface& surface, const Stream& stream, const rig::Anchors& at, const Engine& e, uint32_t t) {
  const auto& c = stream.call;
  const int age = int(int32_t(t - c.at));
  if (!surface.pixels || !stream.drawn(t) || !c.live || age < 0 || age >= int(Stream::kCallMs)) return;
  const Layout l{surface.width, surface.height};
  Raster r{surface};
  monitor(r, surface, e, c, age);
  const Font& big = bubbleFont();
  const CallMove move = callMove(c.gag);
  const int flight = int(callFlightMs(c.gag)), after = age - flight, end = int(Stream::kCallMs);
  const uint16_t ink = callInk(c);
  char word[Stream::kWordBytes + 8];
  if (c.gag == CallGag::kCombo)
    std::snprintf(word, sizeof(word), "%s x%u", c.text, unsigned(c.count));
  else
    std::snprintf(word, sizeof(word), "%s", c.text);
  switch (move) {
    case CallMove::kGather:
    case CallMove::kCompact:
    case CallMove::kDrop:
    case CallMove::kFreeze:
    case CallMove::kBuried: moment(r, l, stream, at, age, ink, word); return;
    default: break;
  }

  // From its lane's name to where it lands on the body.
  const int fromX = l.column(stream, c.slot), fromY = l.y(kTop);
  const int eyesX = (at.eyeL.x + at.eyeR.x) / 32, eyesY = (at.eyeL.y + at.eyeR.y) / 32;
  const int crownX = at.crown.x / 16, crownY = at.crown.y / 16;
  const bool right = fromX >= surface.width / 2;
  const int sideX = (right ? at.brimR.x : at.brimL.x) / 16 + l.x(right ? 48 : -48), sideY = at.brimR.y / 16;
  const int potX = l.x(458), potY = l.y(286), deskY = l.y(305);
  int sx = fromX, sy = fromY;  // where its flight starts
  int toX = crownX, toY = crownY - l.y(18);
  switch (move) {
    case CallMove::kHit: toX = eyesX, toY = eyesY; break;
    case CallMove::kShrug:
    case CallMove::kLook:
    case CallMove::kPoof:
    case CallMove::kPhone:
    case CallMove::kPage:
    case CallMove::kStamp: toX = sideX, toY = sideY; break;
    case CallMove::kShatter: toY = crownY - l.y(50); break;
    case CallMove::kCheer:
    case CallMove::kCombo: toY = crownY - l.y(46); break;
    case CallMove::kStir: toX = potX, toY = potY - l.y(22); break;
    case CallMove::kPlane:
      sx = right ? surface.width + l.x(40) : -l.x(40), sy = l.y(150);
      toX = at.handF.x / 16 + l.x(right ? 70 : -70), toY = at.handF.y / 16 - l.y(30);
      break;
    case CallMove::kDesk:
      if (c.gag == CallGag::kStack) {
        toX = l.x(456), toY = deskY - l.y(110);
      } else {
        const Screen m = screen(surface, e);
        toX = m.x + m.w / 2, toY = m.y - l.y(14);
      }
      break;
    case CallMove::kTopple: toX = l.x(456), toY = deskY - l.y(130); break;
    default: break;
  }

  // In flight: a word from its lane; a plane from the edge.
  if (after < 0) {
    if (move == CallMove::kTopple) {  // the tower, built, wobbling
      const int wobble = l.x(10) * sin40(age / 12) / 1000 * age / flight;
      tower(r, l, 6, deskY, wobble, 0, toX, toY);
      r.alpha = 255;
      centred(r, kSign, l.x(456), deskY - l.y(118), word, ink);
      return;
    }
    const bool rises = move == CallMove::kCheer || move == CallMove::kCombo;
    const int k = rises ? easeOut(age, flight) : easeIn(age, flight);
    // In sixteenths of a pixel.
    int x = lerp(sx * 16, toX * 16, k, flight), y = lerp(sy * 16, toY * 16, k, flight);
    if (move == CallMove::kPlane) {  // a paper plane, swooping in
      y -= l.y16(60 * 16) * sin40(20 * age / flight) / 1000;
      const int dir = right ? -1 : 1;
      const Point plane[3] = {{x + dir * l.x16(26 * 16), y},
                              {x - dir * l.x16(20 * 16), y - l.y16(14 * 16)},
                              {x - dir * l.x16(12 * 16), y + l.y16(10 * 16)}};
      r.alpha = 255;
      r.polygon16(plane, 3, kPaper);
      const Point crease[2] = {{x + dir * l.x16(26 * 16), y}, {x - dir * l.x16(14 * 16), y + l.y16(2 * 16)}};
      r.stroke16(crease, 2, 16, kPaperLine);
      centred16(r, kLarge, x, y - l.y16(26 * 16), word, ink);
      return;
    }
    r.alpha = 255;
    centred16(r, big, x, y, word, ink);
    if (move == CallMove::kArrive) twinkle(r, l, x >> 4, y >> 4, age, 255);
    return;
  }

  switch (move) {
    case CallMove::kHit: {
      // It sticks a moment, then slides off (or is thrown back up), under
      // stars; a hit dizzies it, more up the ladder.
      if (c.gag == CallGag::kThrow && after >= 250) {
        const int k = std::min(400, after - 250);
        r.alpha = 255 - k * 255 / 400;
        centred16(r, big, lerp(toX * 16, fromX * 16, easeOut(k, 400), 400),
                  lerp(toY * 16, -l.y(40) * 16, easeOut(k, 400), 400), word, ink);
      } else {
        const int slide = std::max(0, after - 250), k = std::min(450, slide);
        r.alpha = 255 - k * 255 / 450;
        if (r.alpha > 2)
          centred16(r, big, toX * 16 + l.x16(k * 16 / 30), toY * 16 + l.y16(easeIn(k, 450) * 160 * 16 / 450), word,
                    ink);
      }
      const int daze = c.gag == CallGag::kBonk2                              ? 1300
                       : c.gag == CallGag::kThrow                            ? 700
                       : c.gag == CallGag::kNo || c.gag == CallGag::kTimeout ? 0
                                                                             : 1000;
      if (after < daze) dizzy(r, surface, l, at, after, fadeBy(after, daze, 200));
      if (c.gag == CallGag::kNo || c.gag == CallGag::kTimeout) break;
      const int stars = c.gag == CallGag::kBonk ? 3 : 5;
      if (after < 1100) {
        r.alpha = fadeBy(after, 1100, 200);
        for (int i = 0; i < stars; ++i) {
          const int turn = after / 40 + i * 40 / stars;
          const int cx = crownX + l.x(70) * cos40(turn) / 1000, cy = crownY - l.y(10) + l.y(14) * sin40(turn) / 1000;
          star(r, cx, cy, l.x(13), turn % 10, kStarInk);
        }
      }
      if (c.gag == CallGag::kHelmet && after < 1500) {
        // A dome on the crown, its brim down over the brow.
        r.alpha = fadeBy(after, 1500, 200);
        const int hw = l.x(70) * 16, drop = l.y16(std::max(0, 160 - after) * 4), cx = crownX * 16, cy = crownY * 16;
        round16(r, cx - hw, cy - l.y16(10 * 16) - drop, 2 * hw, l.y16(44 * 16), l.y16(30 * 16), rgb565(150, 160, 170));
        round16(r, cx - hw - l.x16(8 * 16), cy + l.y16(26 * 16) - drop, 2 * hw + l.x16(16 * 16), l.y16(9 * 16),
                l.y16(4 * 16), rgb565(95, 105, 115));
        r.disk16(cx - l.x16(26 * 16) + 8, cy + l.y16(4 * 16) - drop + 8, l.x16(6 * 16) + 8, rgb565(230, 235, 240));
      }
      break;
    }
    case CallMove::kSink:
    case CallMove::kArrive: {  // it sinks into the crown, a ring spreading out
      const int k = std::min(320, after);
      r.alpha = 255 - k * 255 / 320;
      if (r.alpha > 2) centred16(r, big, toX * 16, toY * 16 + l.y16(k * 34 * 16 / 320), word, ink);
      if (after < 500) {
        const int radius = l.x(20 + after * 90 / 500);
        r.alpha = 160 - after * 160 / 500;
        r.ring(crownX - radius, crownY - radius / 4, 2 * radius, radius / 2, radius / 4, 2, ink);
      }
      if (move == CallMove::kArrive && after < 700)
        twinkle(r, l, crownX, crownY - l.y(20), age, fadeBy(after, 700, 300));
      break;
    }
    case CallMove::kLook: {  // read through a magnifier sweeping across it
      r.alpha = fadeBy(after, end - flight, 400);
      centred(r, big, toX, toY, word, ink);
      const int span = glyphCount(word) * big.w / 2 + l.x(10);
      const int lx = toX - span + (after * 2 * span / 900) % (2 * span), ly = toY + l.y(4), rad = l.x(22);
      r.alpha = std::min(r.alpha, 70);
      r.disk(lx, ly, rad, 0xFFFF);
      r.alpha = fadeBy(after, end - flight, 400);
      r.ring(lx - rad, ly - rad, 2 * rad, 2 * rad, rad, l.x(4), kSteel);
      r.line({lx + rad * 7 / 10, ly + rad * 7 / 10}, {lx + rad * 3 / 2, ly + rad * 3 / 2}, l.x(6), rgb565(120, 80, 50));
      break;
    }
    case CallMove::kStir: {  // into the pot, bubbling and steaming
      r.alpha = fadeBy(after, end - flight, 300);
      const int pw = l.x(58), ph = l.y(34);
      r.round(potX - pw / 2, potY - ph / 2, pw, ph, l.y(14), kPot);
      r.round(potX - pw / 2 - l.x(5), potY - ph / 2 - l.y(4), pw + l.x(10), l.y(8), l.y(4), kSteel);
      for (int i = 0; i < 5; ++i) {
        const int life = (after + i * 170) % 700, bx = potX - l.x(16) + i * l.x(8);
        r.disk16(bx * 16 + 8, (potY - ph / 2) * 16 + 8 - l.y16(life * 16 / 18), l.x16(3 * 16 + life * 16 / 200) + 8,
                 rgb565(140, 223, 120));
      }
      const int sink = std::min(300, after);
      r.alpha = std::max(0, r.alpha - sink * 255 / 300);
      if (r.alpha > 2)
        centred16(r, kSign, potX * 16, (potY - ph / 2 - l.y(14)) * 16 + l.y16(sink * 16 / 10), word, ink);
      if (after > 250 && after < 1400) puff(r, l, potX, potY - ph, after - 250, 1150);
      break;
    }
    case CallMove::kStamp: {  // onto a card, and a stamp comes down on it
      r.alpha = fadeBy(after, end - flight, 400);
      const int cw = glyphCount(word) * kSign.w + l.x(24), ch = l.y(46);
      r.round(toX - cw / 2, toY - ch / 2, cw, ch, l.y(6), kPaper);
      centred(r, kSign, toX, toY, word, kNavy);
      if (after >= 300) {
        const int a = r.alpha;
        r.alpha = std::min(a, 220);
        r.ring(toX - l.x(26), toY - l.y(20), l.x(52), l.y(40), l.y(10), l.x(4), kFailInk);
        centred(r, kSmall, toX, toY + l.y(1), "OK", kFailInk);
        r.alpha = a;
      } else if (after >= 120) {  // the stamp, coming down
        const int k = after - 120, y = (toY - l.y(70)) * 16 + l.y16(70 * 16) * easeIn(k, 180) / 180, x = toX * 16;
        round16(r, x - l.x16(22 * 16), y - l.y16(26 * 16), l.x16(44 * 16), l.y16(16 * 16), l.y16(4 * 16),
                rgb565(140, 80, 50));
        round16(r, x - l.x16(8 * 16), y - l.y16(46 * 16), l.x16(16 * 16), l.y16(22 * 16), l.y16(6 * 16),
                rgb565(140, 80, 50));
      }
      break;
    }
    case CallMove::kRocket: {  // it sits on the crown, then lifts off on a rocket
      // In sixteenths of a pixel, the shapes' points on pixels' middles at rest.
      const int lift = std::max(0, after - 500),
                y = toY * 16 - l.y16(easeIn(std::min(lift, 900), 900) * 420 * 16 / 900);
      auto X = [&](int p) { return l.x16(p * 16); };
      auto Y = [&](int p) { return l.y16(p * 16); };
      r.alpha = 255;
      const int rx = toX * 16 + 8, ry = y + Y(38) + 8;
      if (lift > 0) {
        for (int i = 0; i < 4; ++i) {
          r.alpha = std::max(0, 200 - i * 50 - lift / 6);
          r.disk16(rx + X(i % 2 ? 6 : -6), ry + Y(30 + i * 16) + l.y16(lift * 16 / 30), X(7 + i * 3) + 8, kSmoke);
        }
        r.alpha = 255;
        const int flick = (age / 40) % 2 ? Y(6) : 0;
        const Point flame[3] = {{rx - X(8), ry + Y(16)}, {rx + X(8), ry + Y(16)}, {rx, ry + Y(36) + flick}};
        r.polygon16(flame, 3, kFlame);
      }
      round16(r, rx - 8 - X(10), ry - 8 - Y(18), X(20), Y(36), X(10), 0xFFFF);
      const Point fins[3] = {{rx - X(16), ry + Y(18)}, {rx + X(16), ry + Y(18)}, {rx, ry + Y(2)}};
      r.polygon16(fins, 3, kRocketRed);
      r.disk16(rx, ry - Y(4), X(4) + 8, rgb565(80, 160, 230));
      centred16(r, big, toX * 16, y, word, ink);
      break;
    }
    case CallMove::kPoof: {  // gone in a puff
      r.alpha = fadeBy(after, 260, 260);
      if (r.alpha > 2) centred(r, big, toX, toY, word, ink);
      puff(r, l, toX, toY, after, 900);
      break;
    }
    case CallMove::kPlane: {  // caught: it unfolds into the word, then goes
      r.alpha = fadeBy(after, end - flight, 400);
      centred16(r, big, toX * 16, toY * 16 - l.y16(after < 200 ? (20 * 16 - after * 16 / 10) : 0), word, ink);
      break;
    }
    case CallMove::kPhone: {  // a phone ringing beside it, the word its call
      const int shake = after < 900 ? l.x(3) * sin40(after / 6) / 1000 : 0;
      r.alpha = fadeBy(after, end - flight, 400);
      const int px = toX + shake, py = toY + l.y(8);
      // An old phone: its body, a dial, and the handset's arc on top.
      const uint16_t black = rgb565(50, 50, 60);
      r.round(px - l.x(26), py - l.y(4), l.x(52), l.y(28), l.y(10), black);
      r.ring(px - l.x(9), py + l.y(1), l.x(18), l.y(18), l.y(9), 2, rgb565(200, 200, 210));
      Point handset[9];
      for (int i = 0; i < 9; ++i)
        handset[i] = {(px + l.x(26) * cos40(20 - i * 20 / 8) / 1000) * 16,
                      (py - l.y(8) - l.y(14) * sin40(20 - i * 20 / 8) / 1000) * 16};
      r.stroke16(handset, 9, l.x(9) * 16, black);
      r.round(px - l.x(34), py - l.y(14), l.x(18), l.y(12), l.y(5), black);
      r.round(px + l.x(16), py - l.y(14), l.x(18), l.y(12), l.y(5), black);
      if (after < 900 && (after / 150) % 2 == 0)
        for (int i = 1; i <= 2; ++i)
          r.ring(px - l.x(30 + i * 8), py - l.y(24 + i * 6), l.x(60 + i * 16), l.y(40 + i * 12), l.y(20 + i * 6), 2,
                 laneInk(c.slot));
      const int bw = glyphCount(word) * kSign.w + l.x(20), by = py - l.y(58);
      r.round(px - bw / 2, by - l.y(20), bw, l.y(40), l.y(18), 0xFFFF);
      centred(r, kSign, px, by, word, ink == 0xFFFF ? kNavy : ink);
      break;
    }
    case CallMove::kPage: {  // a page beside it, its corner turning
      r.alpha = fadeBy(after, end - flight, 400);
      const int pw = l.x(70), ph = l.y(86), px = toX - pw / 2, py = toY - ph / 2;
      r.round(px, py, pw, ph, l.y(4), kPaper);
      for (int i = 0; i < 5; ++i)
        r.round(px + l.x(8), py + l.y(30 + i * 10), pw - l.x(16) - (i * 7) % 20, l.y(3), 1, kPaperLine);
      centred(r, kLarge, toX, py + l.y(16), word, ink);
      const int turn = (after / 450) % 2, fold = l.x(turn ? 22 : 14);
      const Point corner[3] = {{px + pw - fold, py}, {px + pw, py + fold}, {px + pw - fold, py + fold}};
      r.polygon(corner, 3, kPaperLine);
      break;
    }
    case CallMove::kShrug: {  // beside its head, and an empty bubble over it
      r.alpha = fadeBy(after, 1600, 300);
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
        const int out = easeOut(std::min(220, after), 220), in = easeIn(std::clamp(after - 320, 0, 480), 480);
        // In sixteenths of a pixel.
        const int bx = (toX + (i - n / 2) * kLarge.w) * 16 + l.x16(70 * 16) * cos40(i * 5) / 1000 * out / 220;
        const int by = toY * 16 + l.y16(46 * 16) * sin40(i * 5) / 1000 * out / 220;
        r.alpha = 255 - in * 200 / 480;
        char one[2] = {char(g + 0x20), 0};
        if (g + 0x20 < 0x7f)
          centred16(r, kLarge, lerp(bx, mouthX * 16, in, 480), lerp(by, mouthY * 16, in, 480), one, ink);
      }
      if (after >= 780 && after < 1100) {  // a burp
        r.alpha = fadeBy(after, 1100, 200);
        centred(r, kSmall, mouthX + l.x(46), mouthY - l.y(20), "burp", rgb565(200, 200, 200));
      }
      break;
    }
    case CallMove::kHail: {  // more of them, raining down; the umbrella comes up
                             // too late
      const int open = std::clamp(after - 400, 0, 160), umbrella = after >= 400 ? open : 0;
      const int roof = crownY - l.y(18) - (umbrella ? l.y(40) : 0);
      for (int i = 0; i < 5; ++i) {
        const int start = i * 180 - (i ? flight : 0), a = after - start;
        if (a < -flight || a > 400) continue;
        const int dx = l.x((i * 53) % 140 - 70);
        if (a < 0) {
          const int k = easeIn(a + flight, flight);
          r.alpha = 255;
          centred16(r, kSign, (crownX + dx) * 16, lerp(fromY * 16, roof * 16, k, flight), "FAIL", ink);
        } else {
          r.alpha = 255 - a * 255 / 400;
          const int side = dx < 0 ? -1 : 1;
          centred16(r, kSign, (crownX + dx) * 16 + side * l.x16(a * 90 * 16 / 400),
                    roof * 16 - l.y16(a * 60 * 16 / 400) + l.y16(a * a / 100), "FAIL", ink);
        }
      }
      if (umbrella) {
        r.alpha = fadeBy(after, end - flight, 300);
        const int rad = l.x(62) * open / 160, cy = crownY - l.y(34), cx = crownX + l.x(6);
        r.line({cx, cy}, {cx, crownY + l.y(10)}, l.x(3), rgb565(220, 220, 220));
        // Six panels round its top half, red and white.
        auto rim = [&](int k) { return Point{cx + rad * cos40(k) / 1000, cy - rad * 6 / 10 * sin40(k) / 1000}; };
        for (int s = 0; s < 6; ++s) {
          const Point wedge[3] = {{cx, cy}, rim(s * 20 / 6), rim((s + 1) * 20 / 6)};
          r.polygon(wedge, 3, s % 2 ? 0xFFFF : kFailInk);
        }
      }
      break;
    }
    case CallMove::kCheer:
    case CallMove::kCombo: {  // over its head; confetti, or its count popping
      r.alpha = fadeBy(after, 1900, 400);
      if (r.alpha > 2) centred16(r, big, toX * 16, toY * 16 - l.y16(std::min(after, 300) * 16 / 15), word, ink);
      if (move == CallMove::kCombo) {
        twinkle(r, l, toX, toY, age, fadeBy(after, 1500, 400));
        break;
      }
      if (c.gag == CallGag::kBuilt) {  // the tower, done, a flag on its top
        tower(r, l, 6, deskY, 0, 0, 0, 0);
        const int top = deskY - 6 * (l.y(15) + 2), rise = l.y(std::min(after, 300) * 30 / 300);
        r.alpha = 255;
        r.line({l.x(456), top}, {l.x(456), top - rise - l.y(10)}, l.x(2), rgb565(220, 220, 220));
        const Point flag[3] = {
            {l.x(456), top - rise - l.y(10)}, {l.x(482), top - rise - l.y(2)}, {l.x(456), top - rise + l.y(6)}};
        r.polygon(flag, 3, kPassInk);
      }
      if (after < 1300)
        for (int i = 0; i < 28; ++i) {
          const int vx = ((i * 97) % 200) - 100, vy = -60 - (i * 61) % 120, s = after;
          const int px = toX * 16 + l.x16(vx * s * 16 / 1000),
                    py = toY * 16 + l.y16(vy * s * 16 / 1000 + int(int64_t(260) * s * s * 16 / 1000000));
          r.alpha = 255 - after * 255 / 1300;
          round16(r, px, py, l.x16(7 * 16), l.y16(4 * 16), 16, i % 2 ? kLaneInk[i % Stream::kLanes] : kStarInk);
        }
      break;
    }
    case CallMove::kDesk: {
      if (c.gag == CallGag::kStack) {  // the build's bricks stacking up beside it
        tower(r, l, std::min(6, 1 + after / 300), deskY, 0, 0, 0, 0);
        r.alpha = fadeBy(after, 600, 300);
        if (r.alpha > 2) centred(r, kSign, toX, toY, word, ink);
        break;
      }
      r.alpha = std::max(0, 255 - after * 255 / 400);  // it settles on the monitor
      if (r.alpha > 2) centred16(r, kSign, toX * 16, toY * 16 + l.y16(after * 10 * 16 / 400), word, ink);
      break;
    }
    case CallMove::kTopple: {  // the tower comes down on its head, then lies about
      const int fall = std::min(1000, after * 1000 / 350);
      r.alpha = fadeBy(after, end - flight, 400);
      tower(r, l, 6, deskY, l.x(20), fall, crownX, crownY);
      if (after < 1000) dizzy(r, surface, l, at, after, fadeBy(after, 1000, 200));
      r.alpha = fadeBy(after, 900, 300);
      if (r.alpha > 2) centred(r, kSign, l.x(456), deskY - l.y(118), word, ink);
      break;
    }
  }
}

}  // namespace render::gel
