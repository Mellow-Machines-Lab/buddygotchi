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
#include "rig_tables.h"  // the staged pack's (characters/charactergen.py)

namespace render::gel {

const PastimeInfo kPastimes[kPastimeCount] = {
    {Pastime::kStretch, Body::kClip, "stretch", SceneState::kWorking, 2, 0},
    {Pastime::kLookAround, Body::kClip, "look-around", SceneState::kIdle, 1, 0},
    {Pastime::kHopeful, Body::kClip, "hopeful", SceneState::kIdle, 1, 0},
    {Pastime::kHop, Body::kClip, "hop", SceneState::kIdle, 1, 0},
    {Pastime::kYawn, Body::kBit, "yawn-and-settle", SceneState::kIdle, 1, 0},
    {Pastime::kSneeze, Body::kBit, "sneeze-and-shake", SceneState::kIdle, 1, 0},
    {Pastime::kSnooze, Body::kClip, "snooze", SceneState::kIdle, 3, 0},
    {Pastime::kRollOver, Body::kClip, "roll-over", SceneState::kAsleep, 0, 60},
    {Pastime::kSnoreBubble, Body::kClip, "snore-bubble", SceneState::kAsleep, 0, 240},
    {Pastime::kDeepSnore, Body::kTake, "deep-snore", SceneState::kAsleep, 0, 0, "night"},
    {Pastime::kDream, Body::kTake, "dream", SceneState::kAsleep, 0, 1800},
};

const PastimeInfo& info(Pastime p) { return kPastimes[std::clamp(int(p), 1, kPastimeCount) - 1]; }

namespace {
// A row as the pack has it, found by name once and kept: the tag bits any
// one of which it needs, and its body.
struct Resolved {
  bool found = false;
  uint32_t tags = 0;
  const rig::Clip* clip = nullptr;
  int gag = -1, take = -1;
};
const Resolved& resolved(const PastimeInfo& p) {
  static Resolved table[kPastimeCount];
  Resolved& r = table[std::clamp(int(p.id), 1, kPastimeCount) - 1];
  if (r.found) return r;
  r.found = true;
  for (const char* tag = p.tag; tag && *tag;) {
    const char* end = std::strchr(tag, '|');
    const size_t n = end ? size_t(end - tag) : std::strlen(tag);
    char name[24] = {};
    std::memcpy(name, tag, std::min(n, sizeof name - 1));
    r.tags |= tagBit(name);
    tag = end ? end + 1 : nullptr;
  }
  if (p.body == Body::kClip) r.clip = rig::kRig.clip(p.name);
  if (p.body == Body::kBit)
    for (int i = 0; i < slime::kGagCount && r.gag < 0; ++i)
      if (!std::strcmp(p.name, slime::kGags[i].gesture.type)) r.gag = i;
  if (p.body == Body::kTake)
    for (int i = 0; i < slime::kPastimeTakeCount && r.take < 0; ++i)
      if (!std::strcmp(p.name, slime::kPastimeTakes[i].id)) r.take = i;
  return r;
}
}  // namespace

const rig::Clip* clipOf(const PastimeInfo& p) { return resolved(p).clip; }
int bitOf(const PastimeInfo& p) { return resolved(p).gag; }
int takeOf(const PastimeInfo& p) { return resolved(p).take; }
bool hasBody(const PastimeInfo& p) { return clipOf(p) || bitOf(p) >= 0 || takeOf(p) >= 0; }
uint32_t tagsOf(const PastimeInfo& p) { return resolved(p).tags; }

bool fits(const PastimeInfo& p, uint32_t when, uint32_t lookMs) {
  const uint32_t tags = tagsOf(p);
  return render::fits(tierBit(p.tier), p.afterS, when, lookMs) && (!tags || (when & tags));
}

uint32_t tierBit(int n) {
  static const uint32_t kBits[kTiers] = {tagBit("tier1"), tagBit("tier2"), tagBit("tier3")};
  return n >= 1 && n <= kTiers ? kBits[n - 1] : 0;
}

int tierOf(uint32_t when) {
  for (int n = kTiers; n >= 1; --n)
    if (when & tierBit(n)) return n;
  return 0;
}

namespace {

// The inks: a Z's cream and a snore bubble's rim.
constexpr uint16_t kCream = rgb565(246, 240, 226), kBubbleRim = rgb565(190, 236, 255);

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

}  // namespace

Paws pawsFor(const PastimeShow& show) {
  Paws paws;
  paws.keys = show.keys, paws.tapping = show.tapping, paws.phase = show.pawPhase;
  return paws;
}

void paintPastimes(Surface& surface, const PastimeShow& show, const rig::Anchors& at) {
  if (!surface.pixels || !show.fade) return;
  Raster r{surface};
  const Stage s{r, surface.width, surface.height, at};
  r.fade = show.fade;
  switch (show.playing) {
    case Pastime::kSnooze: zs(r, s.rightX() + s.X(8), s.sideY(), int(show.age)); break;
    case Pastime::kSnoreBubble: snore(s, show, 4600); break;
    default: break;
  }
  r.fade = 255;
}

}  // namespace render::gel
