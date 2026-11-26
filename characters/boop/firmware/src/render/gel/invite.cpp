#include "render/gel/invite.h"

#include <algorithm>
#include <cstring>

#include "render/font.h"
#include "render/gel/finish.h"
#include "render/gel/fixed.h"
#include "render/gel/frame.h"
#include "render/gel/lane.h"
#include "render/gel/moves.h"
#include "render/gel/raster.h"
#include "render/palette.h"

namespace render::gel {

namespace {

using Phase = InviteShow::Phase;

// The props' inks (render/gel/layers.cpp): a dark rim; the glow's warm
// light, sparks' pale gold, a heart's pink.
constexpr uint16_t kRim = rgb565(27, 55, 78);
constexpr uint16_t kCream = rgb565(246, 240, 226), kGlow = rgb565(255, 226, 150), kWhite = rgb565(255, 255, 255);
constexpr uint16_t kSpark = rgb565(250, 230, 160), kHeart = rgb565(226, 78, 104);

int of(int v, int q12) { return int(int64_t(v) * q12 / 4096); }

// How much of the glow and its word show (Q12): in just after the pose,
// out at a miss; a touch flashes it away (the payoff's ring).
int glowShown(const InviteShow& v) {
  const int ms = int(v.ms);
  // A palm's once it's up on the glass, its back once it's turned (their
  // clips'), the lean's as it comes.
  if (v.phase == Phase::kPose)
    return v.pose == InvitePose::kPalm   ? ease(ms, 600, 900)
           : v.pose == InvitePose::kBack ? ease(ms, 1000, 1300)
                                         : ease(ms, 150, 600);
  if (v.phase == Phase::kShrug) return 4096 - ease(ms, 0, 250);
  if (v.phase == Phase::kPayoff) return 4096 - ease(ms, 0, 180);
  return 0;
}

// A circle of `n` points about (cx, cy), px, `radius` px.
void circle(Raster& r, int cx, int cy, int radius, int width16, uint16_t ink) {
  Point ring[25];
  for (int i = 0; i <= 24; ++i) {
    const int a = i * 4096 / 24;
    ring[i] = {cx * 16 + 8 + int(int64_t(radius) * 16 * sinTurn(a + 1024) / 4096),
               cy * 16 + 8 + int(int64_t(radius) * 16 * sinTurn(a) / 4096)};
  }
  r.stroke16(ring, 25, width16, ink);
}

// The glow: soft light breathing about the spot, brightest at its middle,
// and now and then a ripple going out from it. The light is ten faint warm
// gold disks laid over each other, so it falls off smoothly, and a white
// middle: drawn as one pass out from the middle, each pixel blended once by
// how far it is from it, each disk's edge a pixel soft, rather than disk by
// disk. A pixel's distance, in quarters of a pixel, steps out along its row,
// so a row needs one root.
void glow(Raster& r, Point at, int radius, int shown, int ms) {
  const int breath = 2900 + of(1196, (sinTurn(ms * 4096 / kGlowBreathMs) + 4096) / 2);
  const int a = of(shown, breath);
  constexpr int kDisks = 10, kReach = 255;  // px from the middle, at most
  const int outer = std::max(1, radius * (12 + (kDisks - 1) * 2) / 16);
  const int quarters = std::min(outer + 2, kReach) * 4;
  // Each quarter pixel out: how much gold, and then white, it takes.
  uint8_t gold[kReach * 4], white[kReach * 4];
  const int middle16 = std::max(1, radius * 9 / 16) * 16 + 8, middle = of(90, a);
  for (int q = 0; q < quarters; ++q) {
    const int d16 = q * 4 + 2;
    auto covered = [d16](int edge16) { return std::clamp(edge16 - d16 + 8, 0, 16); };
    int keep = 1 << 16;  // the share of what's under it left, in 65536ths
    for (int i = 0; i < kDisks; ++i) {
      const int edge16 = std::max(1, radius * (12 + i * 2) / 16) * 16 + 8;
      keep -= keep * (of(26 - i * 2, a) * covered(edge16) / 16) / 255;
    }
    gold[q] = uint8_t(255 - ((keep * 255 + (1 << 15)) >> 16));
    white[q] = uint8_t(middle * covered(middle16) / 16);
  }
  const int y0 = std::max(0, at.y - quarters / 4), y1 = std::min(r.s.height, at.y + quarters / 4 + 1);
  r.touch(at.x - quarters / 4, y0, at.x + quarters / 4 + 1, y1);
  auto light = [&](int x, int y, int q) {
    if (gold[q]) r.alpha = gold[q], r.pixel(x, y, kGlow);
    if (white[q]) r.alpha = white[q], r.pixel(x, y, kWhite);
  };
  for (int y = y0; y < y1; ++y) {
    const int dy = y - at.y;
    for (int dx = 0, q = root(uint32_t(16 * dy * dy));; ++dx) {
      const int v = 16 * (dx * dx + dy * dy);
      while ((q + 1) * (q + 1) <= v) ++q;
      if (q >= quarters) break;
      light(at.x + dx, y, q);
      if (dx) light(at.x - dx, y, q);
    }
  }
  const int age = ms % kRippleMs;
  if (age < 1000) {
    r.alpha = of(of(220, 4096 - age * 4096 / 1000), shown);
    circle(r, at.x, at.y, radius * (18 + age * 22 / 1000) / 16, 3 * 16, kGlow);
  }
  r.alpha = 255;
}

// How far along a stroke's pass is (Q12), and how much of it shows. The
// glide is half eased, half steady, so it eases in and out yet never stands
// still: it fades in already moving and fades out still moving, and between
// glides nothing shows.
struct PassTime {
  int head = 0, shown = 0;
};

PassTime passTime(const InviteShow& v) {
  if (!invitesStroke(v) || v.phase != Phase::kPose) return {};
  const int u = int(v.ms % kPassMs);
  PassTime p;
  if (u >= kPassGlideMs) return p.head = 4096, p;  // at its end, unseen
  p.head = (rampIn(u, 0, kPassGlideMs) + ease(u, 0, kPassGlideMs)) / 2;
  p.shown = of(of(ease(u, 0, 110), 4096 - ease(u, kPassGlideMs - 160, kPassGlideMs)), glowShown(v));
  return p;
}

// The pass: a soft round light about its head, a fingertip's size, a white
// middle, and its trail behind, thinning and dimming to nothing at its far
// end. Drawn as
// one pass over its box, each pixel blended once by the brighter of its
// distances to the head and to the trail's line, each column's share
// worked out once.
void pass(Raster& r, const InvitePass& p) {
  constexpr int kCols = 256, kWhiteIn = 56;  // the white middle: 56/256ths of its reach, squared
  if (p.shown <= 0 || p.reach <= 0) return;
  const int x0 = std::max(0, std::min(p.tail, p.head - p.reach));
  const int x1 = std::min({r.s.width, p.head + p.reach + 1, x0 + kCols});
  const int y0 = std::max(0, p.y - p.reach), y1 = std::min(r.s.height, p.y + p.reach + 1);
  if (x0 >= x1 || y0 >= y1) return;
  const int gold = of(215, p.shown), white = of(160, p.shown);
  // A distance squared times `per`, >> 16, is 256ths of the reach squared.
  const uint32_t perHead = (256u << 16) / uint32_t(p.reach * p.reach);
  struct Column {
    uint16_t head2, dim;  // its distance to the head, squared; the trail's light here (Q12)
    uint32_t per;         // the trail's reach here, as `per`
  } col[kCols];
  for (int x = x0; x < x1; ++x) {
    Column& c = col[x - x0];
    c.head2 = uint16_t((x - p.head) * (x - p.head));
    c.dim = 0, c.per = 0;
    if (x >= p.tail && x < p.head) {
      const int along = (x - p.tail) * 4096 / (p.head - p.tail);
      const int reach = std::max(2, of(p.reach, 1300 + of(2796, along)));
      c.dim = uint16_t(4096 - of(4096 - along, 4096 - along)), c.per = (256u << 16) / uint32_t(reach * reach);
    }
  }
  r.touch(x0, y0, x1, y1);
  for (int y = y0; y < y1; ++y) {
    const uint32_t dy2 = uint32_t((y - p.y) * (y - p.y));
    for (int x = x0; x < x1; ++x) {
      const Column& c = col[x - x0];
      const uint32_t near = ((c.head2 + dy2) * perHead) >> 16;
      const int head = near < 256 ? 256 - int(near) : 0;
      int lit = head * head;  // of 65536
      if (c.dim) {
        const uint32_t off = (dy2 * c.per) >> 16;
        const int trail = off < 256 ? 256 - int(off) : 0;
        lit = std::max(lit, of(trail * trail, c.dim));
      }
      // The white middle: the head's, and a line down the trail, fading.
      int whiteLit = 0;  // of 65536
      if (near < kWhiteIn) whiteLit = (kWhiteIn - int(near)) * (kWhiteIn - int(near)) * 65536 / (kWhiteIn * kWhiteIn);
      if (c.dim) {
        const uint32_t off = (dy2 * c.per) >> 16;
        if (off < kWhiteIn) {
          const int w = kWhiteIn - int(off);
          whiteLit = std::max(whiteLit, of(w * w * 65536 / (kWhiteIn * kWhiteIn), of(c.dim, c.dim) * 3 / 4));
        }
      }
      if (const int a = gold * lit >> 16) r.alpha = a, r.pixel(x, y, kGlow);
      if (const int a = white * whiteLit >> 16) r.alpha = a, r.pixel(x, y, kWhite);
    }
  }
  r.alpha = 255;
}

// The label: one short word, big, rimmed dark to read over anything, its
// letters rippling a little, one after another.
void label(Raster& r, const char* word, int x, int y, int shown, int ms) {
  const Font& f = kSign;
  r.alpha = of(255, shown);
  int i = 0;
  for (const char* p = word; *p; ++i) {
    // One glyph at a time (a UTF-8 one whole), each with its own lift.
    int n = 1;
    while (p[n] && (p[n] & 0xC0) == 0x80) ++n;
    char one[8] = {};
    std::memcpy(one, p, size_t(std::min(n, 7)));
    p += n;
    const int gx = x + i * f.w, gy = y + 3 * sinTurn(ms * 4096 / 900 - i * 700) / 4096;
    // Its rim: the glyph 2 px to each side, under it.
    for (const Point d : {Point{-2, 0}, Point{2, 0}, Point{0, -2}, Point{0, 2}})
      text(r, f, gx + d.x, gy + d.y, one, kRim);
    text(r, f, gx, gy, one, kCream);
  }
  r.alpha = 255;
}

int glyphsIn(const char* s) {
  int n = 0;
  for (; *s; ++s) n += (*s & 0xC0) != 0x80;
  return n;
}

// Sparks flying out from (x, y), px: `n` four-pointed ones, `age` ms in.
void sparks(Raster& r, Point at, int from, int age, int life, int n) {
  if (age < 0 || age >= life) return;
  r.alpha = 255 - age * 255 / life;
  for (int i = 0; i < n; ++i) {
    const int a = i * 4096 / n + 256;
    const int d = from + age * from / life * 2, size = 6 - age * 3 / life;
    const int x = at.x + d * sinTurn(a + 1024) / 4096, y = at.y + d * sinTurn(a) / 4096;
    r.line({x - size, y}, {x + size, y}, 3, kSpark);
    r.line({x, y - size}, {x, y + size}, 3, kSpark);
  }
  r.alpha = 255;
}

// A heart about (x, y), px, `s` its half-width (render/gel/layers.cpp's).
void heart(Raster& r, int x, int y, int s, uint16_t ink) {
  const int x16 = x * 16, y16 = y * 16, half = s / 2 * 16, lobe = std::max(1, s / 2) * 16 + 8;
  r.disk16(x16 - half + 8, y16 + 8, lobe, ink);
  r.disk16(x16 + half + 8, y16 + 8, lobe, ink);
  const Point v[] = {{x16 - s * 16 + 8, y16 + 24}, {x16 + s * 16 + 8, y16 + 24}, {x16 + 8, y16 + (s + s / 2) * 16 + 8}};
  r.polygon16(v, 3, ink);
}

}  // namespace

int payoffAge(const InviteShow& v) {
  if (v.phase == Phase::kPayoff) return int(v.ms);
  if (v.phase == Phase::kLate && v.ms >= InviteShow::kTurnMs) return int(v.ms - InviteShow::kTurnMs);
  return -1;
}

const char* inviteFace(const InviteShow& v) {
  const int age = payoffAge(v);
  if (v.phase == Phase::kLate && age < 0) return "happy";
  if (age >= 0) {
    switch (v.payoff) {
      case InvitePayoff::kHighFive: return "excited";
      case InvitePayoff::kPurr: return "affectionate";
      case InvitePayoff::kSigh: return age < 500 ? nullptr : "pleased";
      default: return nullptr;
    }
  }
  if (v.phase != Phase::kPose) return nullptr;
  switch (v.pose) {
    case InvitePose::kPalm: return "happy";
    case InvitePose::kLean: return "happy";
    case InvitePose::kBack: return "side_eye";  // over its shoulder: did you see?
    default: return nullptr;
  }
}

Point inviteSpot(const InviteShow& v, const rig::Anchors& at, const Hand hands[2], int& radius) {
  radius = of(kGlowRadius, 4096 + kGlassScale);
  if (v.pose == InvitePose::kPalm && hands[1].shown()) {  // the palm on the glass
    radius = std::max(radius, hands[1].drawn16() / 16 + 4);
    return {hands[1].x16 / 16, hands[1].y16 / 16};
  }
  if (v.pose == InvitePose::kLean && (at.patch.x || at.patch.y)) return {at.patch.x / 16, at.patch.y / 16};
  const Point eyes{(at.eyeL.x + at.eyeR.x) / 2, (at.eyeL.y + at.eyeR.y) / 2};
  switch (v.pose) {
    case InvitePose::kPalm:  // held up at its right side, clear of its eye
      return {(at.eyeR.x + (at.eyeR.x - at.eyeL.x) * 7 / 16) / 16, (at.eyeR.y + at.mouth.y * 2) / 3 / 16 + 8};
    case InvitePose::kLean:  // its forehead, on the glass
      return {(at.crown.x * 3 + eyes.x * 2) / 5 / 16, (at.crown.y * 3 + eyes.y * 2) / 5 / 16};
    case InvitePose::kBack:  // its back, the side away from its face (round to its left)
      return {(at.brimL.x * 3 + at.brimR.x * 5) / 8 / 16, (at.brimF.y + at.handF.y) / 2 / 16};
    default: return {at.crown.x / 16, at.crown.y / 16};
  }
}

bool invitesStroke(const InviteShow& v) { return v.pose == InvitePose::kLean || v.pose == InvitePose::kBack; }

InvitePass invitePass(const InviteShow& v, const Surface& s, const rig::Anchors& at, int radius) {
  InvitePass p;
  if (!invitesStroke(v) || !v.shows()) return p;
  const PassTime t = passTime(v);
  p.reach = radius * 5 / 4;
  // Across most of the body, a fifth of its width in from each side: its
  // back's middle, or the lean's brow, above its eyes, clear of its face.
  // Its outline's widest (`lap`), not its brim's.
  int left = at.lap[0].x, right = left;  // the body's outline, its widest
  for (const Point q : at.lap) left = std::min(left, q.x), right = std::max(right, q.x);
  left /= 16;
  const int width = right / 16 - left;
  const int eyes = (at.eyeL.y + at.eyeR.y) / 32;
  const int row =
      v.pose == InvitePose::kBack ? (at.brimF.y + at.handF.y) / 32 : at.crown.y / 16 + (eyes - at.crown.y / 16) * 2 / 5;
  p.y = std::max(p.reach, std::min(row, s.height * 4 / 5 - p.reach - 2));
  const int edge = s.inset(p.y - p.reach, p.y + p.reach) + 2;
  p.from = std::max(edge + p.reach, left + width / 5), p.to = std::min(s.width - edge - p.reach, left + width * 4 / 5);
  p.to = std::max(p.to, p.from + 1);
  // The head, and its trail a third of the way behind its edge, though
  // never further back than half that before the way's start.
  const int way = p.to - p.from;
  p.head = p.from + of(way, t.head);
  p.tail = std::max(p.from - way / 6, p.head - p.reach / 2 - way / 3);
  p.shown = t.shown;
  return p;
}

void addInvitePass(rig::Channels& c, const InviteShow& v) {
  const PassTime t = passTime(v);
  if (t.shown <= 0) return;
  // Most as the light crosses the middle of its way.
  const int by = of(sinTurn(t.head / 2), t.shown);
  auto add = [&](rig::Channel ch, int most) {
    const rig::ChannelInfo& info = rig::kChannelInfo[int(ch)];
    c[ch] = int16_t(std::clamp(int(c[ch]) + of(most, by), int(info.lo), int(info.hi)));
  };
  add(rig::Channel::kLean, 60);
  add(rig::Channel::kSquash, 40);
}

void paintInviteGlow(Surface& s, const InviteShow& v, const rig::Anchors& at, Point spot, int radius) {
  const int shown = glowShown(v);
  if (!v.shows() || !s.pixels) return;
  Raster r{s};
  if (invitesStroke(v))
    pass(r, invitePass(v, s, at, radius));
  else if (shown > 0)
    glow(r, spot, radius, shown, int(v.ms));
}

void paintInvite(Surface& s, const InviteShow& v, const rig::Anchors& at, Point spot, int radius) {
  if (!v.shows() || !s.pixels) return;
  Raster r{s};
  const int ms = int(v.ms), age = payoffAge(v), shown = glowShown(v);
  // A ring round the palm, breathing with the glow.
  if (shown > 0 && v.pose == InvitePose::kPalm) {
    const int breath = (sinTurn(ms * 4096 / kGlowBreathMs) + 4096) / 2;
    r.alpha = of(of(150, 2000 + of(2096, breath)), shown);
    circle(r, spot.x, spot.y, radius * 21 / 16, 3 * 16, kGlow);
    r.alpha = 255;
  }
  // The word by the glow: beside the palm, on the side away from the head's
  // tilt, under the glow on its back; under a stroke's pass, where it
  // glides, so it never runs through it; inside the panel.
  if (v.label && shown > 0) {
    const Font& f = kSign;
    const int w = glyphsIn(v.label) * f.w, reach = radius * 2;
    int x = spot.x + reach, y = spot.y - f.h / 2;
    if (invitesStroke(v)) {
      // By the middle of the passes' way: under it on its back, over it on
      // the lean's brow, its face under it.
      const InvitePass p = invitePass(v, s, at, radius);
      x = (p.from + p.to - w) / 2;
      y = v.pose == InvitePose::kBack ? p.y + p.reach * 3 / 4 : std::max(4, p.y - p.reach - f.h);
    } else if (v.pose != InvitePose::kLean) {
      // Under the palm, and under the glow on its back.
      x = spot.x - w / 2, y = spot.y + radius * (v.pose == InvitePose::kPalm ? 2 : 3) / 2;
    } else if (spot.x < (at.eyeL.x + at.eyeR.x) / 32) {
      x = spot.x - reach - w;  // beside the cheek, on the side away from the face
    }
    const int edge = s.inset(y, y + f.h) + 10;
    if (!invitesStroke(v) && x + w > s.width - edge) x = spot.x - reach - w;
    x = std::clamp(x, edge, s.width - edge - w);
    y = std::min(y, s.height * 4 / 5 - f.h - 4);
    label(r, v.label, x, y, shown, ms);
  }
  if (age < 0) {
    // A late one, as it turns round: a pop of sparks by its head.
    if (v.phase == Phase::kLate) sparks(r, {at.crown.x / 16, at.crown.y / 16 + 10}, 24, ms - 100, 450, 5);
    return;
  }
  switch (v.payoff) {
    case InvitePayoff::kHighFive:
      // Sparks flying off the palm (its clap's ring is the hit's).
      sparks(r, spot, radius * 2, age, 800, 8);
      break;
    case InvitePayoff::kPurr: {
      // Little hearts rising from its head, one after another.
      for (int i = 0; i < 3; ++i) {
        const int life = age - 150 - i * 500;
        if (life < 0 || life >= 1100) continue;
        r.alpha = std::min({255, life * 255 / 150, (1100 - life) * 255 / 400});
        const int x = spot.x + (i - 1) * 26 + 4 * sinTurn(life * 4096 / 700) / 4096, y = spot.y - 12 - life * 54 / 1100;
        heart(r, x, y, 10 + life * 4 / 1100, kHeart);
      }
      r.alpha = 255;
      break;
    }
    case InvitePayoff::kSigh: {
      // A puff of breath from its mouth, drifting off and thinning.
      const int life = age - 500;
      if (life < 0 || life >= 1200) break;
      const int mx = at.mouth.x / 16, my = at.mouth.y / 16;
      for (int i = 0; i < 3; ++i) {
        const int d = life * (30 + i * 16) / 1200;
        r.alpha = std::max(0, std::min(200, (1200 - life) * 200 / 600) - i * 40);
        r.disk(mx + 14 + d + i * 10, my - 4 - i * 6 - life * 10 / 1200, 5 + i * 2 + life * 4 / 1200, kCream);
      }
      r.alpha = 255;
      break;
    }
    default: break;
  }
}

LowSign inviteSign(const InviteShow& v) {
  LowSign l;
  const int age = payoffAge(v);
  if (age < 0 || v.xp <= 0) return l;
  static constexpr const char* kWords[] = {nullptr, "high five", "purr", "better now"};
  l.text = kWords[std::min(int(v.payoff), 3)];
  l.ink = rgb565(kEyeRgb);
  l.ms = uint32_t(age);
  l.leftMs = int32_t(InviteShow::kPayoffMs) - age;
  l.oneLine = true;
  l.xp = v.xp;
  return l;
}

InviteSound inviteSound(InvitePayoff p) {
  switch (p) {
    case InvitePayoff::kHighFive: return {"cheer", 150, 1000};
    case InvitePayoff::kPurr: return {"breath", 120, 700};
    case InvitePayoff::kSigh: return {"breath", 140, 850};
    default: return {};
  }
}

}  // namespace render::gel
