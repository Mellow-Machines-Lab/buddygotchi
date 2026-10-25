#include "render/gel/painter.h"
#include "render/gel/engine.h"
#include "render/gel/pastimes.h"
#include "render/gel/raster.h"
#include "render/gel/subpixel.h"
namespace render::gel {
namespace {
// The cards, in thousandths of the surface: x, y, width, height, radius.
struct Card {
  int x, y, w, h, radius;
};
constexpr Card kAlertCard{180, 75, 640, 215, 32}, kResultCard{270, 75, 460, 210, 30}, kStartCard{280, 85, 440, 132, 30};
// A card on a surface, in pixels, with its corners' radius as Raster::round
// clamps it.
struct Placed {
  int x, y, w, h, r;
};
Placed place(const Surface& surface, const Card& c) {
  const int w = surface.width * c.w / 1000, h = surface.height * c.h / 1000;
  return {surface.width * c.x / 1000, surface.height * c.y / 1000, w, h,
          std::clamp(surface.width * c.radius / 1000, 0, std::min(w, h) / 2)};
}
// Raster::round fills at the card's opacity: opaque from 253 on.
bool opaque(F visible) { return (visible * 255).integer() >= 253; }

// What the cards show, as a key that's the same exactly when their pixels
// are (never 0), when one card shows, opaque: 0 while one fades, and when
// two overlap, since the one on top covers the other's corners.
uint32_t cardsKey(const Scenes& s, T now) {
  uint32_t h = 2166136261u;
  auto add = [&](const void* data, size_t n) {
    for (size_t i = 0; i < n; ++i) h = (h ^ static_cast<const uint8_t*>(data)[i]) * 16777619u;
  };
  auto str = [&](const char* v) { add(v ? v : "", v ? std::strlen(v) + 1 : 1); };
  int shown = 0;
  for (auto prop : {Scenes::kStartProp, Scenes::kAlertProp, Scenes::kResultProp}) {
    const F seen = s.visible(prop, now);
    if (seen <= F(0)) continue;
    if (!opaque(seen) || ++shown > 1) return 0;
    // Its labels' and marks' soft edges still blend at 253 and 254.
    const int facts[] = {int(prop), (seen * 255).integer()};
    add(facts, sizeof facts);
    if (prop == Scenes::kStartProp) str(s.startProp.label);
    if (prop == Scenes::kResultProp) {
      const int facts[] = {int(s.resultProp.outcome), int(s.resultProp.state)};
      add(facts, sizeof facts);
      str(s.resultProp.label);
    }
  }
  return shown ? (h ? h : 1) : 0;
}

// The card's first row something's been drawn over yet this frame, or the
// row under it.
int firstDrawnRow(const Surface& surface, const Placed& c) {
  for (int y = std::max(0, c.y); y < std::min(surface.height, c.y + c.h); ++y) {
    const auto& row = surface.written[y];
    if (row.last && row.first < c.x + c.w && row.last > c.x) return y;
  }
  return c.y + c.h;
}
}  // namespace

int tapLift(const Scenes& s, int side) {
  const int age = F(s.ageMs).integer();
  for (int i = 0; i < s.recipe.count; ++i) {
    const auto& k = s.recipe.contacts[i];
    if (k.kind != kKey || k.side != side) continue;
    const int d = F(k.at).integer() - age;
    if (d >= 0 && d < kTapMs) return kTapLift * 4 * d * (kTapMs - d) / (kTapMs * kTapMs);
  }
  return 0;
}

int typeLift(uint32_t ms, int side) {
  // Each paw taps every other kTypeMs, the right's between the left's.
  const int period = 2 * kTypeMs, p = int((ms + (side > 0 ? kTypeMs : 0)) % period), d = (period - p) % period;
  return d < kTapMs ? kTypeLift * 4 * d * (kTapMs - d) / (kTapMs * kTapMs) : 0;
}

int opaqueCards(const Surface& surface, const Engine& e, Box* out) {
  const auto& s = e.scenes;
  const T now = e.timeMs();
  const int w = surface.width, bottom = surface.height * 4 / 5;
  int count = 0;
  auto add = [&](const Card& card, Scenes::Prop prop) {
    if (!opaque(s.visible(prop, now))) return;
    const auto [x, y, cw, ch, r] = place(surface, card);
    // Its whole rows between the corners, and the columns between them above and below.
    const Box boxes[] = {
        {x + r, y, x + cw - r, y + r}, {x, y + r, x + cw, y + ch - r}, {x + r, y + ch - r, x + cw - r, y + ch}};
    for (Box b : boxes) {
      b.x0 = std::max(b.x0, 0), b.x1 = std::min(b.x1, w), b.y0 = std::max(b.y0, 0), b.y1 = std::min(b.y1, bottom);
      if (b.x0 < b.x1 && b.y0 < b.y1 && count < Surface::kMaxKeep) out[count++] = b;
    }
  };
  add(kAlertCard, Scenes::kAlertProp);
  add(kResultCard, Scenes::kResultProp);
  add(kStartCard, Scenes::kStartProp);
  return count;
}

void paintProps(Surface& surface, const Engine& e, const Paws* paws) {
  if (!surface.pixels) return;
  Raster r{surface};
  auto& s = e.scenes;
  auto state = s.route.state;
  int w = surface.width, h = surface.height;
  auto x = [&](int p) { return w * p / 1000; };
  auto y = [&](int p) { return h * p / 1000; };
  auto round = [&](int a, int b, int c, int d, int radius, uint16_t ink) {
    r.round(x(a), y(b), x(c), y(d), x(radius), ink);
  };
  // A card, filled, and its one-pixel rim, a step lighter.
  auto fillCard = [&](const Card& c, uint16_t ink, uint16_t rim) {
    round(c.x, c.y, c.w, c.h, c.radius, ink);
    r.ring(x(c.x), y(c.y), x(c.w), y(c.h), x(c.radius), 1, rim);
  };
  // A card, and what's drawn on it, cut to the card. One this surface
  // already shows (cardKey) keeps its rows above the first that anything's
  // been drawn over yet this frame, or will be (`over`, a knock), or was
  // when the surface last showed it (cardKeyTo): the clear kept their
  // insides (opaqueCards), so only their corners, which it erased, are
  // drawn again. From that row down it's drawn whole. Drawing needs you's
  // again every frame cost 2.3 ms on the board.
  const uint32_t cards = cardsKey(s, e.timeMs());
  int cardsTo = 1 << 30;
  auto drawCard = [&](const Card& card, uint16_t ink, uint16_t rim, auto&& on, int over = 1 << 30) {
    const Placed c = place(surface, card);
    const int from =
        cards && cards == surface.cardKey ? std::min({firstDrawnRow(surface, c), surface.cardKeyTo, over}) : c.y;
    cardsTo = over;
    auto within = [&](Box b) {
      r.bounds = b;
      fillCard(card, ink, rim);
      on();
    };
    if (from > c.y) {
      r.touch(c.x, c.y, c.x + c.w, from);
      for (int top : {c.y, c.y + c.h - c.r})
        for (int left : {c.x, c.x + c.w - c.r}) within({left, top, left + c.r, std::min(top + c.r, from)});
    }
    within({c.x, from, c.x + c.w, c.y + c.h});
    r.bounds = Raster::kEverywhere;
  };
  auto text = [&](const char* label, int a, int b, uint16_t ink, const Font& font = kSmall) {
    r.text(label, x(a), y(b), ink, font);
  };
  const uint16_t dark = rgb565(20, 55, 72), green = rgb565(140, 223, 203), light = rgb565(184, 233, 245),
                 blue = rgb565(100, 184, 207), amber = rgb565(239, 189, 103);
  F contact = s.envelope(e.timeMs(), kKey), progress = clamp(s.ageMs / s.recipe.duration, 0, 1);
  if (s.desk.x > q(.001)) {
    r.alpha = (s.desk.x * 255).integer();
    round(150, 749, 700, 21, 10, rgb565(25, 59, 77));
    round(100, 600, 184, 116, 12, blue);
    round(104, 604, 176, 108, 10, dark);
    round(114, 611, 156, 89, 8, rgb565(7, 24, 32));
    round(178, 715, 26, 32, 8, dark);
    round(140, 739, 98, 10, 5, blue);
    auto deskState = isDesk(state) ? state : s.route.baseState;
    if (deskState == SceneState::kPlanning) {
      for (int i = 0; i < 3; ++i) {
        round(130, 627 + i * 23, 10, 8, 3, green);
        round(150, 628 + i * 23, 63 + i * 12, 4, 2, blue);
      }
    } else if (deskState == SceneState::kSearching) {
      int sx = 165 + (progress * 32).integer();
      r.disk(x(sx), y(645), 8, green);
      r.disk(x(sx), y(645), 5, dark);
      r.line({x(sx + 13), y(658)}, {x(sx + 28), y(675)}, 2, green);
    } else if (deskState == SceneState::kTesting) {
      for (int i = 0; i < 4; ++i) r.disk(x(143 + i * 31), y(644), 3, green);
      text("TEST", 191, 678, blue);
    } else if (deskState == SceneState::kAnalyzing) {
      round(135, 627, 38, 52, 4, blue);
      round(190, 627, 38, 52, 4, blue);
      round(139 + (progress * 55).integer(), 648, 30, 5, 2, green);
    } else if (deskState == SceneState::kToolUse) {
      r.disk(x(178), y(647), 7, green);
      r.disk(x(178), y(647), 4, dark);
      r.line({x(194), y(647)}, {x(219), y(647)}, 2, green);
      r.line({x(219), y(647)}, {x(219), y(658)}, 2, green);
    } else if (deskState == SceneState::kWaiting)
      text(". . .", 191, 647, blue);
    else {
      text(deskState == SceneState::kTerminal ? "> _" : ". . .", 162, 633, green);
      for (int i = 0; i < 3; ++i) round(129, 654 + i * 13, 100 - i * 24, 3, 1, blue);
    }
    round(387, 713, 258, 30, 8, rgb565(49, 88, 107));
    for (int row = 0; row < 2; ++row)
      for (int key = 0; key < 9; ++key) {
        bool pressed = contact > q(.35) && key == (s.hasLast && s.last.side < 0 ? 2 : 6);
        round(397 + key * 26, 718 + row * 10, 19, 6, 2, pressed ? light : rgb565(144, 170, 176));
      }
    for (int side : {-1, 1}) {
      const int i = side > 0, alpha = paws ? paws->alpha[i] : 255;
      if (alpha < 3) continue;
      const int lift = std::max(tapLift(s, side), typeLift(uint32_t(F(e.timeMs()).integer()), side)) +
                       (paws ? paws->lift[i] : 0);
      int yy = 711 + (s.hasLast && s.last.side == side ? (contact * 9).integer() : 0) - lift;
      r.alpha = (s.desk.x * alpha).integer();
      round(500 + side * 78 - 30 + (paws ? paws->dx[i] : 0), yy - 12, 60, 25, 13, rgb565(93, 166, 219));
    }
  }
  // Each prop's alpha is its ramped visibility; one fading out still draws
  // the content it last showed.
  const T now = e.timeMs();
  r.alpha = 255;
  if (F listening = s.visible(Scenes::kListeningProp, now); listening > F(0)) {
    r.alpha = (listening * 255).integer();
    // Its ring breathes in sixteenths of a pixel, two pixels wide, its
    // outer edge 15.5 to 21.5 px out.
    circle16(r, x(500) * 16 + 8, y(144) * 16 + 8, 15 * 16 - 8 + (s.listeningPulse * 96).integer(), 2 * 16, blue);
    round(492, 119, 16, 31, 8, light);
    r.line({x(500), y(153)}, {x(500), y(164)}, 2, blue);
    text("LISTENING", 500, 223, light);
  }
  if (F start = s.visible(Scenes::kStartProp, now); start > F(0)) {
    r.alpha = (start * 255).integer();
    drawCard(kStartCard, rgb565(27, 55, 78), rgb565(0x78, 0xa4, 0xc8),
             [&] { text(s.startProp.label, 500, 151, light, kLarge); });
  }
  if (F touch = s.visible(Scenes::kTouchProp, now); touch > F(0)) {
    F pulse = s.envelope(now, kBody);
    r.alpha = (touch * pulse * 255).integer();
    for (int i = 0; i < (s.touchKind == SceneState::kTapSpam ? 3 : 1); ++i)
      r.line({x(798 + i * 16), y(462)}, {x(820 + i * 16), y(480)}, 2, light);
  }
  r.alpha = 255;
  if (F alert = s.visible(Scenes::kAlertProp, now); alert > F(0)) {
    r.alpha = (alert * 255).integer();
    // A knock's disk reaches a row above its radius (Raster::disk).
    const F knock = state == SceneState::kNeedsYou ? s.envelope(now, kKnock) : F(0);
    const int knockY = y(246), knockRadius = 6 + (knock * 4).integer();
    drawCard(
        kAlertCard, amber, rgb565(0xf8, 0xd2, 0x94),
        [&] {
          // Sized to read at arm's length on the 2.06" panel.
          text("NEEDS YOU", 500, 133, rgb565(44, 37, 29), kSign);
          text("Continue on your Mac", 500, 227, rgb565(0x3d, 0x2f, 0x1f), kLarge);
        },
        knock > 0 ? knockY - knockRadius - 1 : 1 << 30);
    if (knock > 0) {
      r.alpha = (knock * 255).integer();
      r.disk(x(280), knockY, knockRadius, light);
    }
  }
  if (F result = s.visible(Scenes::kResultProp, now); result > F(0)) {
    r.alpha = (result * 255).integer();
    const auto& card = s.resultProp;
    bool success = card.outcome == Outcome::kSuccess,
         bad = card.outcome == Outcome::kFailure || card.state == SceneState::kError;
    const uint16_t ink = success ? rgb565(23, 63, 59)
                         : bad   ? rgb565(62, 43, 56)
                                 : rgb565(36, 56, 71),
                   rim = success ? rgb565(0x69, 0xb4, 0x9b)
                         : bad   ? rgb565(0xbf, 0x83, 0x99)
                                 : rgb565(0x83, 0xa8, 0xbf);
    drawCard(kResultCard, ink, rim, [&] {
      if (success) {
        Point trophy[] = {{x(466), y(106)}, {x(534), y(106)}, {x(524), y(151)}, {x(500), y(170)}, {x(476), y(151)}};
        r.polygon(trophy, 5, amber);
        round(496, 154, 8, 25, 2, amber);
        round(476, 177, 48, 7, 3, amber);
      } else if (bad) {
        r.line({x(478), y(111)}, {x(522), y(157)}, 4, rgb565(232, 169, 180));
        r.line({x(522), y(111)}, {x(478), y(157)}, 4, rgb565(232, 169, 180));
      } else {
        // A neutral result's mark, square on the panel: a soft stop square
        // when stopped, else three calm dots (ready, finished).
        const uint16_t soft = rgb565(0xac, 0xc8, 0xd9);
        if (card.state == SceneState::kStopped)
          r.round(x(478), y(134) - x(22), x(44), x(44), x(10), soft);
        else
          for (int dx : {-30, 0, 30}) r.disk(x(500 + dx), y(134), x(9), soft);
      }
      text(card.label, 500, 235,
           success ? rgb565(0xb4, 0xe5, 0xd4)
           : bad   ? rgb565(0xef, 0xb9, 0xc7)
                   : rgb565(0xd5, 0xe8, 0xf2),
           kLarge);
    });
    if (card.gift) {
      // A gift beside the card: the small bug Boop caught, held up proudly.
      const int bx = 795, by = 180;
      const uint16_t ink = rgb565(44, 37, 29);
      for (int side : {-1, 1}) {
        for (int row = -1; row <= 1; ++row)
          r.line({x(bx + side * 18), y(by + row * 16)}, {x(bx + side * 34), y(by + row * 20 + 6)}, 2, ink);
        r.line({x(bx + side * 6), y(by - 46)}, {x(bx + side * 16), y(by - 64)}, 2, ink);
      }
      r.disk(x(bx), y(by - 36), x(12), ink);
      round(bx - 24, by - 32, 48, 64, 24, amber);
      round(bx - 2, by - 30, 4, 60, 1, ink);
      for (const Point spot : {Point{-11, -12}, Point{11, -12}, Point{-12, 10}, Point{12, 10}})
        r.disk(x(bx + spot.x), y(by + spot.y), 2, ink);
    }
  }
  // Nothing after the cards draws over them.
  surface.cardKey = cards;
  surface.cardKeyTo = cardsTo;
}
}  // namespace render::gel
