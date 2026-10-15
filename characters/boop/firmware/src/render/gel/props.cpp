#include "render/gel/painter.h"
#include "render/gel/engine.h"
#include "render/gel/raster.h"
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

void paintProps(Surface& surface, const Engine& e) {
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
  // A card, filled, and its one-pixel rim, a step lighter, as the design
  // source strokes it (render/props.mjs).
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
      int yy = 711 + (s.hasLast && s.last.side == side ? (contact * 9).integer() : 0);
      round(500 + side * 78 - 30, yy - 12, 60, 25, 13, rgb565(93, 166, 219));
    }
  }
  // Each prop's alpha is its ramped visibility; one fading out still draws
  // the content it last showed (CONTINUITY.md, Representative activity scenes).
  const T now = e.timeMs();
  r.alpha = 255;
  if (F helpers = s.visible(Scenes::kHelpersProp, now); helpers > F(0)) {
    r.alpha = (helpers * 255).integer();
    int direction = s.helpersProp.direction;
    F hp = s.helpersProp.progress;
    bool returning = s.helpersProp.returning;
    for (int i = 0; i < s.helpersProp.count; ++i) {
      int inner = 500 + direction * 170, outer = 500 + direction * (300 + i * 67),
          xx = returning ? outer + ((inner - outer) * hp).integer() : inner + ((outer - inner) * hp).integer(),
          yy = (direction < 0 ? 510 : 645) - (i % 2) * 32;
      round(xx - 32, yy - 45, 68, 68, 25, rgb565(89, 169, 224));
      for (int side : {-1, 1}) r.disk(x(xx + side * 11), y(yy - 5), 2, dark);
    }
    if (returning && s.helpersProp.report) {
      int xx = direction < 0 ? 130 : 775, yy = direction < 0 ? 545 : 699;
      round(xx, yy, 95, 65, 10, dark);
      for (int i = 0; i < 3; ++i) round(xx + 17, yy + 15 + i * 13, 60 - i * 14, 4, 2, light);
    }
  }
  r.alpha = 255;
  if (F listening = s.visible(Scenes::kListeningProp, now); listening > F(0)) {
    r.alpha = (listening * 255).integer();
    int radius = 15 + (s.listeningPulse * 6).integer();
    r.disk(x(500), y(144), radius, blue);
    r.disk(x(500), y(144), radius - 2, 0);
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
          // Sized to read at arm's length on the 2.06" panel (render/props.mjs).
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
      }
      text(card.label, 500, 235,
           success ? rgb565(0xb4, 0xe5, 0xd4)
           : bad   ? rgb565(0xef, 0xb9, 0xc7)
                   : rgb565(0xd5, 0xe8, 0xf2),
           kLarge);
    });
  }
  // Nothing after the cards draws over them.
  surface.cardKey = cards;
  surface.cardKeyTo = cardsTo;
}
}  // namespace render::gel
