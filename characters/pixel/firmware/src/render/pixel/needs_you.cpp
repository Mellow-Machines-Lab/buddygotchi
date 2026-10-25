#include "render/pixel/needs_you.h"

#include <cstdio>

#include "render/font.h"
#include "render/maths.h"
#include "render/palette.h"
#include "render/pixel/scene.h"

namespace render {

namespace {

// Fractions in 1024ths, in integers so the board and the simulator agree.
constexpr int kOne = 1024;

int clampQ(int64_t v) { return v < 0 ? 0 : v > kOne ? kOne : int(v); }
// How far `ms` is into a span of `len` from `from`, 0..kOne.
int progress(int64_t ms, int64_t from, int64_t len) { return clampQ((ms - from) * kOne / len); }
// Eases out: fast, then settling.
int easeOut(int u) {
  int64_t v = kOne - u;
  return int(kOne - v * v * v / (int64_t(kOne) * kOne));
}
// Eases out past the end and back, for the placard's bounce and the head's pop.
int easeBack(int u) {  // 1 + 2.9 v³ + 1.9 v², v = u - 1
  int64_t v = u - kOne;
  return int(kOne + 29 * v * v * v / (int64_t(kOne) * kOne) / 10 + 19 * v * v / kOne / 10);
}

// `v` full-face pixels at `s` 64ths, rounded half away from zero.
int sc(int v, int s) {
  int n = v * s;
  return n >= 0 ? (n + 32) / 64 : -((-n + 32) / 64);
}

// The face drawn at `s` 64ths of its size, the whole face's layout (the
// pixel face): two window eyes of four panes, pink
// cheeks and a small "o" of a mouth.
void drawHead(Canvas& c, const NeedsYouPose& p) {
  const int s = p.scale, cx = p.headX, cy = p.headY;
  const uint8_t white = sceneInk(1), pink = sceneInk(2);
  const int look = sc(6 * p.glance, s);
  auto rect = [&](int x, int y, int w, int h, uint8_t ink) { c.fillRect(x, y, w < 1 ? 1 : w, h < 1 ? 1 : h, ink); };
  for (int side = -1; side <= 1; side += 2) {
    const int ex = cx + sc(72 * side, s) + look, ey = cy - sc(12, s);
    if (p.eyesShut) {
      rect(ex - sc(26, s), ey - sc(2, s), sc(52, s), sc(5, s) < 2 ? 2 : sc(5, s), white);
    } else {
      const int pane = sc(24, s), cut = sc(3, s) < 1 ? 1 : sc(3, s);
      for (int dx = -1; dx <= 1; dx += 2) {
        for (int dy = -1; dy <= 1; dy += 2) {
          int x = ex + sc(dx < 0 ? -26 : 2, s), y = ey + sc(dy < 0 ? -26 : 2, s);
          rect(x + cut, y, pane - 2 * cut, pane, white);
          rect(x, y + cut, pane, pane - 2 * cut, white);
        }
      }
    }
    if (p.whole) {
      const int k = cx + sc(72 * side, s);
      rect(k + sc(side < 0 ? -37 : 5, s), cy + sc(28, s), sc(14, s), sc(9, s), pink);
      rect(k + sc(side < 0 ? -19 : 23, s), cy + sc(28, s), sc(14, s), sc(9, s), pink);
    }
  }
  if (p.whole && p.flat) {  // the stare's mouth, a flat line
    rect(cx - sc(12, s), cy + sc(34, s), sc(24, s), sc(3, s), white);
  } else if (p.whole) {  // the mouth, a small "o" of surprise
    const int mx = cx + look / 2;
    rect(mx - sc(7, s), cy + sc(30, s), sc(14, s), sc(3, s), white);
    rect(mx - sc(7, s), cy + sc(39, s), sc(14, s), sc(3, s), white);
    rect(mx - sc(10, s), cy + sc(33, s), sc(3, s), sc(6, s), white);
    rect(mx + sc(7, s), cy + sc(33, s), sc(3, s), sc(6, s), white);
  }
}

// A mitt gripping the placard's top edge: three knuckles.
void drawMitt(Canvas& c, int x, int y) {
  const uint8_t white = sceneInk(1);
  for (int i = 0; i < 3; ++i) {
    c.fillRect(x + i * 5, y, 4, 12, white);
    c.fillRect(x + i * 5 + 1, y - 1, 2, 1, white);
  }
}

// A mitt let go of the placard to wave: the gripping mitt's three knuckles,
// bigger, on a round palm that rises from behind the placard's edge at
// `edge`, its thumb out to `side` (-1 left, 1 right). It tilts `tilt` px
// at the knuckles, half that at the thumb, as a hand rocks when it waves.
void drawMitten(Canvas& c, int x, int y, int side, int tilt, int edge) {
  const uint8_t white = sceneInk(1);
  const int mid = x + tilt / 2;
  for (int i = 0; i < 3; ++i) {
    c.fillRect(x + tilt - 8 + i * 6, y + 1, 4, 3, white);  // a knuckle, rounded
    c.fillRect(x + tilt - 7 + i * 6, y, 2, 1, white);
  }
  c.fillRect(x + tilt - 8, y + 3, 16, 1, white);
  c.fillRect(mid - 9, y + 4, 18, 6, white);  // the palm, rocking less toward the wrist
  c.fillRect(x - 9, y + 10, 18, edge - y - 10, white);
  c.fillRect(side < 0 ? mid - 12 : mid + 9, y + 8, 3, 5, white);  // the thumb
  c.fillRect(side < 0 ? mid - 11 : mid + 9, y + 7, 2, 1, white);
}

// The placard: amber with stepped corners, like the bubble's, and who's asking
// in black on it, `dx` from its place.
void drawPlacard(Canvas& c, int top, const Strip& s, int dx) {
  constexpr int L = 3, w = NeedsYou::kWidth, h = NeedsYou::kHeight, pad = NeedsYou::kPad;
  const int x = NeedsYou::kLeft + dx;
  c.fillRect(x + 2 * L, top, w - 4 * L, h, kAmber);
  c.fillRect(x + L, top + L, w - 2 * L, h - 2 * L, kAmber);
  c.fillRect(x, top + 2 * L, w, h - 4 * L, kAmber);
  // The header: a dot, and "CLAUDE  NEEDS YOU".
  const int hy = top + 10;
  const uint8_t ink = textAt(kInkOnAmber, kLevels);
  c.fillRect(x + pad + 1, hy + 5, 6, 8, ink);
  c.fillRect(x + pad, hy + 6, 8, 6, ink);
  char head[40];
  int n = std::snprintf(head, sizeof(head), "%s", s.agent ? s.agent : "");
  for (int i = 0; i < n && i < int(sizeof(head)); ++i) {
    if (head[i] >= 'a' && head[i] <= 'z') head[i] = char(head[i] - 'a' + 'A');
  }
  std::snprintf(head + n, sizeof(head) - size_t(n), "  NEEDS YOU");
  drawStringFit(c, kSmall, x + pad + 14, hy, head, kInkOnAmber, w - 2 * pad - 14);
  c.fillRect(x + pad, hy + kSmall.h + 4, w - 2 * pad, 2, textAt(kInkOnAmber, 3));
  // The thread's name, else the project, wrapped in kSign.
  char more[16] = "";
  if (s.more > 0) std::snprintf(more, sizeof(more), "+%d more", s.more);
  const int ty = hy + kSmall.h + 14;
  const int bottom = top + h - 10 - (more[0] ? kSmall.h + 2 : 0);
  const int cols = (w - 2 * pad) / kSign.w;
  int rows = (bottom - ty) / kSign.h;
  if (rows > 3) rows = 3;
  char lines[3][48];
  const char* what = s.name && *s.name ? s.name : s.project ? s.project : "";
  n = wrapText(what, cols, rows, &lines[0][0], sizeof(lines[0]));
  for (int i = 0; i < n; ++i) drawString(c, kSign, x + pad, ty + i * kSign.h, lines[i], kInkOnAmber);
  if (more[0]) {
    drawString(c, kSmall, x + w - pad - stringWidth(kSmall, more), top + h - 10 - kSmall.h, more, kInkOnAmber);
  }
}

// A swing from -kOne to kOne and back once every `period` ms, starting at 0.
int swing(int64_t ms, int64_t period) {
  int64_t q = (ms % period) * 4 * kOne / period;
  return int(q < kOne ? q : q < 3 * kOne ? 2 * kOne - q : q - 4 * kOne);
}
// A hop, 0 to kOne and back once every `period` ms.
int hop(int64_t ms, int64_t period) {
  int64_t ph = ms % period;
  return int(4 * kOne * ph * (period - ph) / (period * period));
}

// The head `ph` ms into peeking, a spot every `hopMs`: the spot, and how
// far it has ducked (0 up, kOne all the way down; below 0 past the top as
// it pops up at the next).
void peek(int64_t ph, int64_t hopMs, int& spot, int& pop) {
  spot = 0, pop = 0;
  if (ph <= 0) return;
  const int64_t duck = NeedsYou::kDuckMs < hopMs / 4 ? NeedsYou::kDuckMs : hopMs / 4;
  const int64_t up = NeedsYou::kPopMs < hopMs / 4 ? NeedsYou::kPopMs : hopMs / 4;
  const int64_t n = ph / hopMs, into = ph % hopMs;
  spot = int(n % NeedsYou::kSpots);
  if (into > hopMs - duck) pop = easeOut(progress(into, hopMs - duck, duck));
  else if (into < up && n > 0) pop = kOne - easeBack(progress(into, 0, up));
}

}  // namespace

NeedsYouPose needsYouPose(uint32_t ms, bool eyesShut, int dy) {
  NeedsYouPose p;
  const int64_t t = ms;
  const int rise = progress(ms, NeedsYou::kHoldMs, NeedsYou::kRiseMs);
  const int in = easeOut(rise);
  const bool gaveUp = t >= Arc::kGiveUpAt, staring = t >= Arc::kStareAt && !gaveUp;
  int nudge = 0, spot = 0, pop = 0, sway = 0, bob = 0;
  int64_t beat = 0, into = 0;
  if (t < Arc::kSwayAt || gaveUp) {
    // Calm: the nudge, the placard bumping up and back (a parabola standing
    // for a sine), and the head peeking from spot to spot. After giving
    // up, the same again from then.
    const int64_t ph = gaveUp ? t - Arc::kGiveUpAt : t - int64_t(NeedsYou::kSettledMs);
    if (ph > 0) {
      int64_t n = ph % NeedsYou::kNudgeEveryMs;
      if (n < NeedsYou::kNudgeMs)
        nudge = int(4 * NeedsYou::kNudgePx * n * (NeedsYou::kNudgeMs - n) /
                    (int64_t(NeedsYou::kNudgeMs) * NeedsYou::kNudgeMs));
    }
    peek(ph, NeedsYou::kHopMs, spot, pop);
  } else if (!staring) {
    // Swaying, then shaking: the placard goes side to side and bobs on the
    // beat; swaying, the head pops from spot to spot faster, and shaking it
    // bounces in the middle.
    const bool shaking = t >= Arc::kShakeAt;
    into = t - (shaking ? Arc::kShakeAt : Arc::kSwayAt);
    beat = shaking ? Arc::kShakeBeatMs : Arc::kSwayBeatMs;
    sway = (shaking ? Arc::kShake : Arc::kSway) * swing(into, beat) / kOne;
    bob = (shaking ? Arc::kShakeBob : Arc::kSwayBob) * hop(into, beat) / kOne;
    if (shaking) spot = 2;
    else peek(into, Arc::kSwayHopMs, spot, pop);
  } else {
    spot = 2;  // the middle
  }
  // The stare lowers the placard and brings the head up close; giving up
  // takes it back.
  int lowered = 0;
  if (staring) lowered = easeOut(progress(t, Arc::kStareAt, Arc::kLowerMs));
  else if (gaveUp) lowered = kOne - easeOut(progress(t, Arc::kGiveUpAt, Arc::kLowerMs));
  if (lowered) pop = 0;
  const int x = NeedsYou::kSpotX[spot] + sway;
  const int top = lerp(NeedsYou::kTop, Arc::kStareTop, lowered, kOne);
  p.placardX = int16_t(sway);
  p.placardY = int16_t(lerp(kHeight + 4, top, easeBack(rise), kOne) - nudge - bob + dy);
  p.scale = uint8_t(lerp(lerp(64, NeedsYou::kHeadScale, in, kOne), Arc::kStareScale, lowered, kOne));
  p.headX = int16_t(lerp(lerp(kWidth / 2, x, in, kOne), kWidth / 2, lowered, kOne));
  const int peekY = lerp(96, NeedsYou::kHeadY, in, kOne) + pop * 44 / kOne - nudge * 6 / 10 - bob;
  p.headY = int16_t(lerp(peekY, Arc::kStareY, lowered, kOne) + dy);
  // The eyes look toward the placard's middle; in the middle, from side to
  // side. Shaking, they dart on the beat; staring, straight at you.
  if (rise >= kOne * 9 / 10 && !lowered) {
    if (beat == Arc::kShakeBeatMs) p.glance = int8_t((into / beat) % 2 ? 1 : -1);
    else if (x < kWidth / 2) p.glance = 1;
    else if (x > kWidth / 2) p.glance = -1;
    else
      p.glance = int8_t(((gaveUp ? t - Arc::kGiveUpAt : t - int64_t(NeedsYou::kSettledMs)) / 1500) % 2 ? 1 : -1);
  }
  p.eyesShut = eyesShut && !staring;  // a stare doesn't blink
  p.whole = rise <= kOne / 2 || lowered > kOne / 2;
  p.flat = lowered > kOne / 2;
  p.hands = rise > kOne / 5;
  if (p.hands)
    p.handX = int16_t(lerp(x, kWidth / 2, lowered, kOne)), p.handY = int16_t(p.placardY - 6 + pop * 8 / kOne);
  // Swaying, a mitt lets go and waves back and forth over the edge, well
  // clear of the head: the right one, or the left with the head at the
  // right corner. Shaking, both do, faster, either side of the head.
  if (beat && p.hands) {
    const bool shaking = beat == Arc::kShakeBeatMs;
    const int64_t period = shaking ? Arc::kShakeWaveMs : Arc::kSwayWaveMs;
    const int w = swing(into, period);
    const int wave = (shaking ? Arc::kShakeWave : Arc::kSwayWave) * w / kOne;
    p.tilt = int8_t(Arc::kTilt * w / kOne);
    p.waveY = int16_t(p.placardY - Arc::kMittUp);
    if (shaking) {
      p.waving = 2;
      p.waveX = int16_t(p.handX + Arc::kMittOut + wave), p.waveX2 = int16_t(p.handX - Arc::kMittOut + wave);
    } else {
      p.waving = 1;
      const int side = x > kWidth / 2 + NeedsYou::kSpotX[2] / 4 ? -1 : 1;
      p.waveX = int16_t(p.handX + side * Arc::kMittOut + wave);
    }
  }
  return p;
}

void drawNeedsYouScreen(Canvas& c, const NeedsYouPose& p, const Strip& s) {
  if (!c.mask().all()) c.fillRect(0, 0, kWidth, kHeight, kBlack);  // its black too, dissolving
  drawStrip(c, s);  // until the placard comes up over it
  drawHead(c, p);   // behind the placard
  drawPlacard(c, p.placardY, s, p.placardX);
  if (p.hands) {
    // The thumbs point toward the head.
    if (!p.waving || (p.waving == 1 && p.waveX < p.handX)) drawMitt(c, p.handX + 48, p.handY);
    if (!p.waving || (p.waving == 1 && p.waveX > p.handX)) drawMitt(c, p.handX - 62, p.handY);
    if (p.waving) drawMitten(c, p.waveX, p.waveY, p.waveX < p.handX ? 1 : -1, p.tilt, p.placardY);
    if (p.waving == 2) drawMitten(c, p.waveX2, p.waveY, 1, p.tilt, p.placardY);
  }
}

}  // namespace render
