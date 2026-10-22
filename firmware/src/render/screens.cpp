#include "render/screens.h"

#include <algorithm>
#include <cstdio>

#include "render/font.h"
#include "render/palette.h"

namespace render {

namespace {

constexpr int kMargin = 12;

// The middle of the strip.
constexpr int kStripCy = (kStripTop + kHeight) / 2;

// The bubble: a box in the lane with stepped corners and a short tail up to
// the face, as the animation bank asks host text to be shown (its
// README), its outline 2 px of the dim ink.
constexpr int kBubbleTop = kLaneTop + 4;  // under the tail
constexpr int kBubbleBottom = kHeight - 2;
constexpr int kBubbleCy = (kBubbleTop + kBubbleBottom) / 2;
constexpr int kBubblePad = 10;  // from the outline to what's inside, left and right
constexpr int kBubbleLine = 2;

void plotInk(Canvas& c, int x, int y, int level, int ink) { c.pixels()[y * kWidth + x] = inkAt(ink, level); }

// The strip's two round icons, 10 × 10 px, as anti-aliased levels (0 is
// bare glass): the dot by who needs you and the ring by the working count.
constexpr char kDot[10][11] = {"0026886200", "0488888840", "2888888882", "6888888886", "7888888887",
                               "7888888887", "6888888886", "2888888882", "0488888840", "0026886200"};
constexpr char kRing[10][11] = {"0026886200", "0488888840", "2884004882", "6840000486", "7810000187",
                                "7810000187", "6840000486", "2884004882", "0488888840", "0026886200"};

void drawIcon(Canvas& c, int x, int y, const char (&icon)[10][11], int ink) {
  for (int j = 0; j < 10; ++j) {
    for (int i = 0; i < 10; ++i) {
      if (int level = icon[j][i] - '0') plotInk(c, x + i, y + j, level, ink);
    }
  }
}

// The box around `w` px of what's in it, centred, and the tail over its middle.
void drawBox(Canvas& c, int w) {
  const int L = kBubbleLine, ink = inkAt(kInkDim, kLevels);
  int bw = w + 2 * (kBubblePad + L), left = (kWidth - bw) / 2, top = kBubbleTop, h = kBubbleBottom - kBubbleTop;
  c.fillRect(left + 2 * L, top, bw - 4 * L, L, uint8_t(ink));          // the edges
  c.fillRect(left + 2 * L, top + h - L, bw - 4 * L, L, uint8_t(ink));
  c.fillRect(left, top + 2 * L, L, h - 4 * L, uint8_t(ink));
  c.fillRect(left + bw - L, top + 2 * L, L, h - 4 * L, uint8_t(ink));
  c.fillRect(left + L, top + L, L, L, uint8_t(ink));                   // the stepped corners
  c.fillRect(left + bw - 2 * L, top + L, L, L, uint8_t(ink));
  c.fillRect(left + L, top + h - 2 * L, L, L, uint8_t(ink));
  c.fillRect(left + bw - 2 * L, top + h - 2 * L, L, L, uint8_t(ink));
  c.fillRect(kWidth / 2 - 2 * L, top - L, 4 * L, L, uint8_t(ink));     // the tail, up to the face
  c.fillRect(kWidth / 2 - L, top - 2 * L, 2 * L, L, uint8_t(ink));
}

// The `say`'s text in its bubble, which takes the whole lane: the text
// centred in the large font, or the small one when it doesn't fit (20
// characters do; the longest take is 22), cut to fit the room.
void drawBubble(Canvas& c, const char* text) {
  c.fillRect(0, kLaneTop, kWidth, kHeight - kLaneTop, kBlack);  // the lane is the bubble's
  const int room = kWidth - 2 * kMargin - 2 * (kBubblePad + kBubbleLine);
  const bool large = stringWidth(kLarge, text) <= room;
  const Font& f = large ? kLarge : kSmall;
  int w = stringWidth(f, text);
  if (w > room) w = room;
  drawBox(c, w);
  drawStringFit(c, f, (kWidth - w) / 2, kBubbleCy - f.baseline + (large ? 8 : 5), text, kInkAmber, room);
}

// Status-strip icons, 16 px boxes with (x, y) at the top left.
void iconNoApp(Canvas& c, int x, int y) {  // a plug on its cord, pointing at nothing
  uint8_t g = inkAt(kInkGrey, kLevels);
  c.fillRect(x, y + 7, 5, 2, g);        // cord
  c.fillRect(x + 4, y + 3, 6, 10, g);   // body
  c.fillRect(x + 10, y + 5, 4, 2, g);   // prongs
  c.fillRect(x + 10, y + 9, 4, 2, g);
}

void iconTick(Canvas& c, int x, int y, uint8_t ink) {  // a tick, 2 px strokes
  for (int i = 0; i < 4; ++i) c.fillRect(x + 1 + i, y + 7 + i, 2, 2, ink);
  for (int i = 0; i < 7; ++i) c.fillRect(x + 5 + i, y + 9 - i, 2, 2, ink);
}

void iconCross(Canvas& c, int x, int y, uint8_t ink) {  // a cross, 2 px strokes
  for (int i = 0; i < 8; ++i) c.fillRect(x + 3 + i, y + 4 + i, 2, 2, ink), c.fillRect(x + 10 - i, y + 4 + i, 2, 2, ink);
}

void iconDots(Canvas& c, int x, int y, uint8_t ink) {  // three dots: something to say
  for (int i = 0; i < 3; ++i) c.fillRect(x + 2 + 4 * i, y + 9, 2, 2, ink);
}

}  // namespace

// A parcel, 10 × 10: the idle count's, what BOOT hands you.
void iconParcel(Canvas& c, int x, int y, uint8_t ink) {
  c.fillRect(x, y + 2, 10, 8, ink);
  c.fillRect(x + 4, y, 2, 2, ink);
  c.fillRect(x + 1, y + 5, 8, 1, inkAt(kInkDim, kLevels));
  c.fillRect(x + 4, y + 2, 2, 8, inkAt(kInkDim, kLevels));
}

// A mini, 10 × 10: a helper at work, a tiny face with two eyes.
void iconMini(Canvas& c, int x, int y, uint8_t ink) {
  c.fillRect(x + 1, y, 8, 10, ink);
  c.fillRect(x, y + 1, 10, 8, ink);
  c.fillRect(x + 2, y + 4, 2, 2, kBlack);
  c.fillRect(x + 6, y + 4, 2, 2, kBlack);
}

void drawStrip(Canvas& c, const Strip& s) {
  // An empty strip is bare glass: no divider under the face.
  if (!s.agent && !s.doneAgent && s.busy <= 0 && s.idle <= 0 && s.helpers <= 0 && !s.noApp) return;
  // The first pack's success designs for the finish fill the screen with
  // colour: the finish's names get a black band to be read on.
  if (s.doneAgent) c.fillRect(0, kStripTop, kWidth, kHeight - kStripTop, kBlack);
  // The divider, only over bare glass: an older mood's working look draws
  // its props down into the lane, and the divider mustn't cut through them.
  uint8_t* divider = c.pixels() + kStripTop * kWidth;
  for (int x = kMargin; x < kWidth - kMargin; ++x) {
    if (divider[x] == kBlack) divider[x] = inkAt(kInkDim, kLevels);
  }
  const int cy = kStripCy, ty = cy - 10;
  int x = kMargin;
  char busy[12];
  std::snprintf(busy, sizeof(busy), "%d", s.busy);
  // The room the counts after the names take: working, helpers and idle.
  auto room = [](int n, int icon) {
    char t[12];
    std::snprintf(t, sizeof(t), "%d", n);
    return n > 0 ? icon + 14 + stringWidth(kSmall, t) : 0;
  };
  const int minis = std::min(s.helpers, kMinis);
  const int counts = room(s.busy, 15) + (s.helpers > 0 ? minis * 12 + 4 + room(s.helpers - minis, 0) : 0) + room(s.idle, 15);
  if (s.agent) {
    drawIcon(c, x, cy - 5, kDot, kInkAmber);
    // Who needs you, cut to leave room for "+N" and the working count.
    char more[12] = "";
    if (s.more > 0) std::snprintf(more, sizeof(more), "+%d", s.more);
    int room = kWidth - kMargin - (x + 15) - (more[0] ? stringWidth(kSmall, more) + 8 : 0) -
               counts;
    char who[48];
    const char* what = s.name && *s.name ? s.name : s.project;
    std::snprintf(who, sizeof(who), "%s \xC2\xB7 %s", s.agent, what);
    x = drawStringFit(c, kSmall, x + 15, ty, who, kInkAmber, room);
    if (more[0]) x = drawString(c, kSmall, x + 8, ty, more, kInkGrey);
    x += 14;
  } else if (s.doneAgent) {
    uint8_t eye = inkAt(kInkEye, kLevels);
    if (s.doneOutcome == Outcome::kSuccess) iconTick(c, x - 1, cy - 8, eye);
    else if (s.doneOutcome == Outcome::kFailure) iconCross(c, x - 1, cy - 8, eye);
    else iconDots(c, x - 1, cy - 8, eye);
    // Who finished, cut to leave room for the working count.
    int room = kWidth - kMargin - (x + 15) - counts;
    char who[48];
    std::snprintf(who, sizeof(who), "%s \xC2\xB7 %s", s.doneAgent, s.doneThread ? s.doneThread : "");
    x = drawStringFit(c, kSmall, x + 15, ty, who, kInkEye, room) + 14;
  }
  if (s.busy > 0) {
    drawIcon(c, x, cy - 5, kRing, kInkGrey);
    x = drawString(c, kSmall, x + 15, ty, busy, kInkGrey) + 14;
  }
  // Then the helpers at work, and the agents idle, waiting for you.
  char count[12];
  if (s.helpers > 0) {
    for (int i = 0; i < minis; ++i) iconMini(c, x + i * 12, cy - 5, inkAt(kInkEye, kLevels));
    x += minis * 12 + 2;
    if (s.helpers > minis) {
      std::snprintf(count, sizeof(count), "+%d", s.helpers - minis);
      x = drawString(c, kSmall, x, ty, count, kInkGrey);
    }
    x += 12;
  }
  if (s.idle > 0) {
    std::snprintf(count, sizeof(count), "%d", s.idle);
    iconParcel(c, x, cy - 5, inkAt(kInkEye, kLevels));
    drawString(c, kSmall, x + 15, ty, count, kInkEye);
  }
  if (s.noApp) iconNoApp(c, kWidth - kMargin - 16, cy - 8);
}

void drawLane(Canvas& c, const char* bubble, const Strip& s) {
  if (bubble) drawBubble(c, bubble);
  else drawStrip(c, s);
}

}  // namespace render
