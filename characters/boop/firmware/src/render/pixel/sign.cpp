#include "render/pixel/sign.h"

#include <cstdio>

#include "render/font.h"
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
// Eases out past the end and back, for the sign's bounce and the head's pop.
int easeBack(int u) {  // 1 + 2.9 v³ + 1.9 v², v = u - 1
  int64_t v = u - kOne;
  return int(kOne + 29 * v * v * v / (int64_t(kOne) * kOne) / 10 + 19 * v * v / kOne / 10);
}
int lerp(int a, int b, int q) { return a + int(int64_t(b - a) * q / kOne); }

// `v` full-face pixels at `s` 64ths, rounded half away from zero.
int sc(int v, int s) {
  int n = v * s;
  return n >= 0 ? (n + 32) / 64 : -((-n + 32) / 64);
}

// The face drawn at `s` 64ths of its size, the whole face's layout (the
// pixel face): two window eyes of four panes, pink
// cheeks and a small "o" of a mouth.
void drawHead(Canvas& c, const SignPose& p) {
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
  if (p.whole) {  // the mouth, a small "o" of surprise
    const int mx = cx + look / 2;
    rect(mx - sc(7, s), cy + sc(30, s), sc(14, s), sc(3, s), white);
    rect(mx - sc(7, s), cy + sc(39, s), sc(14, s), sc(3, s), white);
    rect(mx - sc(10, s), cy + sc(33, s), sc(3, s), sc(6, s), white);
    rect(mx + sc(7, s), cy + sc(33, s), sc(3, s), sc(6, s), white);
  }
}

// A mitt gripping the sign's top edge: three knuckles.
void drawMitt(Canvas& c, int x, int y) {
  const uint8_t white = sceneInk(1);
  for (int i = 0; i < 3; ++i) {
    c.fillRect(x + i * 5, y, 4, 12, white);
    c.fillRect(x + i * 5 + 1, y - 1, 2, 1, white);
  }
}

// The sign: amber with stepped corners, like the bubble's, and who's asking
// in black on it.
void drawSign(Canvas& c, int top, const Strip& s) {
  constexpr int L = 3, x = Sign::kLeft, w = Sign::kWidth, h = Sign::kHeight, pad = Sign::kPad;
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
  // The thread's name, else the project, wrapped in the sign's font.
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

}  // namespace

SignPose signPose(uint32_t ms, bool eyesShut, int dy) {
  SignPose p;
  const int rise = progress(ms, Sign::kHoldMs, Sign::kRiseMs);
  const int in = easeOut(rise);
  const int64_t ph = int64_t(ms) - int64_t(Sign::kSettledMs);  // into the hold, once settled
  // The nudge: the sign bumps up and back, a parabola standing for a sine.
  int nudge = 0;
  if (ph > 0) {
    int64_t n = ph % Sign::kNudgeEveryMs;
    if (n < Sign::kNudgeMs) nudge = int(4 * Sign::kNudgePx * n * (Sign::kNudgeMs - n) / (int64_t(Sign::kNudgeMs) * Sign::kNudgeMs));
  }
  // The hops: a spot for kHopMs, ducking at its end and popping up at the next.
  int spot = 0, pop = 0;  // pop: 0 up, kOne all the way down; below 0 past the top
  if (ph > 0) {
    const int64_t hop = ph / Sign::kHopMs, into = ph % Sign::kHopMs;
    spot = int(hop % Sign::kSpots);
    if (into > int64_t(Sign::kHopMs - Sign::kDuckMs)) pop = easeOut(progress(into, Sign::kHopMs - Sign::kDuckMs, Sign::kDuckMs));
    else if (into < int64_t(Sign::kPopMs) && hop > 0) pop = kOne - easeBack(progress(into, 0, Sign::kPopMs));
  }
  const int x = Sign::kSpotX[spot];
  p.signY = int16_t(lerp(kHeight + 4, Sign::kTop, easeBack(rise)) - nudge + dy);
  p.scale = uint8_t(lerp(64, Sign::kHeadScale, in));
  p.headX = int16_t(lerp(kWidth / 2, x, in));
  p.headY = int16_t(lerp(96, Sign::kHeadY, in) + pop * 44 / kOne - nudge * 6 / 10 + dy);
  // The eyes look toward the sign's middle; in the middle, from side to side.
  if (rise >= kOne * 9 / 10) {
    if (x < kWidth / 2) p.glance = 1;
    else if (x > kWidth / 2) p.glance = -1;
    else p.glance = int8_t((ph / 1500) % 2 ? 1 : -1);
  }
  p.eyesShut = eyesShut;
  p.whole = rise <= kOne / 2;
  p.hands = rise > kOne / 5;
  if (p.hands) p.handX = int16_t(x), p.handY = int16_t(p.signY - 6 + pop * 8 / kOne);
  return p;
}

void drawSignScreen(Canvas& c, const SignPose& p, const Strip& s) {
  c.fill(kBlack);
  drawStrip(c, s);  // until the sign comes up over it
  drawHead(c, p);   // behind the sign
  drawSign(c, p.signY, s);
  if (p.hands) {
    drawMitt(c, p.handX - 62, p.handY);
    drawMitt(c, p.handX + 48, p.handY);
  }
}

}  // namespace render
