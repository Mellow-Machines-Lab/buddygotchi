#include "render/gel/painter.h"
#include "render/gel/engine.h"
#include "render/gel/hands.h"
#include "render/gel/pastimes.h"
#include "render/gel/raster.h"
#include "render/gel/subpixel.h"
#include "render/gel/lane.h"
#include "render/gel/router.h"
#include "render/palette.h"
#include "render/tags.h"
namespace render::gel {
namespace {
// What a request asks of you, as the needs-you card says it after
// "NEEDS YOU": short enough for its second line (16 glyphs at most).
const char* attnKindWords(AttnKind k) {
  switch (k) {
    case AttnKind::kApprove: return "a yes or no";
    case AttnKind::kQuestion: return "a question";
    case AttnKind::kPlan: return "a plan to read";
    case AttnKind::kNone: break;
  }
  return "";
}
// The cards, in thousandths of the surface: x, y, width, height, radius.
struct Card {
  int x, y, w, h, radius;
};
// The needs-you card stands in the top band, 344 × 76 px on the AMOLED from
// y 16, clear of the crown, which ducks under it (paintFrame's duck).
constexpr Card kAlertCard{158, 40, 685, 186, 40};
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

// What the needs-you card shows, as a key that's the same exactly when its
// pixels are (never 0), while it shows, opaque: 0 while it fades.
uint32_t cardsKey(const Scenes& s, T now) {
  const F seen = s.visible(Scenes::kAlertProp, now);
  if (seen <= F(0) || !opaque(seen)) return 0;
  // Its labels' and marks' soft edges still blend at 253 and 254.
  uint32_t h = 2166136261u;
  const int facts[] = {int(Scenes::kAlertProp), (seen * 255).integer()};
  for (size_t i = 0; i < sizeof facts; ++i) h = (h ^ reinterpret_cast<const uint8_t*>(facts)[i]) * 16777619u;
  return h ? h : 1;
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

namespace {
// A hand's radius on the keys, px: a pad about as wide as two keys.
constexpr int kDeskHandPx = 13;
// What the desk's monitor shows (paintProps).
enum class MonitorIcon : uint8_t { kPencil, kGlass, kPrompt, kFlask, kHourglass, kCross, kClock, kTick };
// A word forward that hit: a failure or a timeout, not your no.
bool fails(const Stream::Call& c) {
  return c.live && callMove(c.style) == CallMove::kHit && c.style != CallStyle::kNo;
}
MonitorIcon monitorIcon(const Stream* stream, uint32_t now, Activity activity) {
  if (stream && fails(stream->call) && now - stream->call.at < Stream::kCallMs)
    return stream->call.style == CallStyle::kTimeout ? MonitorIcon::kClock : MonitorIcon::kCross;
  const Stream::ActNow act = stream ? stream->actNow(now) : Stream::ActNow{};
  if (act.shows() && act.result != ActResult::kRunning)
    return act.result == ActResult::kPass ? MonitorIcon::kTick : MonitorIcon::kCross;
  if (act.shows() && act.kind == ActKind::kTests) return MonitorIcon::kFlask;
  switch (activity) {
    case Activity::kLooking: return MonitorIcon::kGlass;
    case Activity::kRunning: return MonitorIcon::kPrompt;
    case Activity::kWaiting: return MonitorIcon::kHourglass;
    default: return MonitorIcon::kPencil;
  }
}
// How far up a paw flails for a failure that landed: for kFlailMs after
// the knock, the paws by turns every 90 ms.
constexpr uint32_t kFlailMs = 1100;
int flailLift(const Stream* stream, uint32_t now, int side) {
  if (!stream || !fails(stream->call)) return 0;
  const uint32_t landed = stream->call.at + callFlightMs(stream->call.style);
  if (int32_t(now - landed) < 0 || now - landed >= kFlailMs) return 0;
  return ((now - landed) / 90 + (side > 0 ? 1 : 0)) % 2 ? 34 : 4;
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

int briskLift(int phase, int side) {
  const int p = (phase + (side > 0 ? kBeat : 0)) % (2 * kBeat), d = (2 * kBeat - p) % (2 * kBeat);
  const int tap = kTapBeat;
  return d < tap ? kBriskLift * 4 * d * (tap - d) / (tap * tap) : 0;
}

int typeLift(uint32_t ms, int side, bool brisk) {
  // Each paw taps every other kTypeMs (kBriskMs, brisk), the right's between the left's.
  const int every = brisk ? kBriskMs : kTypeMs, most = brisk ? kBriskLift : kTypeLift, tap = brisk ? kBriskTapMs : kTapMs;
  const int period = 2 * every, p = int((ms + (side > 0 ? every : 0)) % period), d = (period - p) % period;
  return d < tap ? most * 4 * d * (tap - d) / (tap * tap) : 0;
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
  return count;
}

void paintProps(Surface& surface, const Engine& e, const Paws* paws, const Stream* stream, uint32_t streamNow,
                const CardShow* held) {
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
  Box drawn[Surface::kMaxCards];
  int drawnCount = 0;
  auto drawCard = [&](const Card& card, uint16_t ink, uint16_t rim, auto&& on, int over = 1 << 30) {
    const Placed c = place(surface, card);
    if (drawnCount < Surface::kMaxCards) drawn[drawnCount++] = {c.x, c.y, c.x + c.w, c.y + c.h};
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
  auto text = [&](const char* label, int a, int b, uint16_t ink, const Font& font) {
    r.text(label, x(a), y(b), ink, font);
  };
  const uint16_t dark = rgb565(20, 55, 72), green = rgb565(140, 223, 203), light = rgb565(184, 233, 245),
                 blue = rgb565(100, 184, 207);
  F contact = s.envelope(e.timeMs(), kKey);
  if (s.desk.x > q(.001)) {
    r.alpha = (s.desk.x * 255).integer();
    round(150, 749, 700, 21, 10, rgb565(25, 59, 77));
    // The frame lights in the agent's colour while Boop holds its card, and
    // in the watched one's with several agents, so you know whose it is.
    const int slot = held && held->slot >= 0 ? held->slot : watchedSlot();
    const bool lit = slot >= 0 && slot < Stream::kLanes;
    round(100, 600, 184, 116, 12, lit ? kLaneInk[slot] : blue);
    round(104, 604, 176, 108, 10, dark);
    round(114, 611, 156, 89, 8, rgb565(7, 24, 32));
    round(178, 715, 26, 32, 8, dark);
    round(140, 739, 98, 10, 5, blue);
    // The monitor says what the work is, in one icon that fills it: a
    // pencil writing as it types, a magnifying glass drifting as it looks,
    // a prompt as something runs, a flask filling as the tests run, an
    // hourglass as it waits. A failure landing turns it to a red cross, a
    // timeout to an amber clock, and a work act's result to a tick or a
    // cross, for as long as each shows.
    const auto deskState = isDesk(state) ? state : s.route.baseState;
    const uint32_t ms = uint32_t(F(e.timeMs()).integer());
    const MonitorIcon icon = monitorIcon(stream, streamNow, activityOf(deskState));
    if (icon == MonitorIcon::kCross || icon == MonitorIcon::kClock)
      round(114, 611, 156, 89, 8, icon == MonitorIcon::kCross ? rgb565(70, 18, 20) : rgb565(62, 42, 6));
    else if (icon == MonitorIcon::kTick)
      round(114, 611, 156, 89, 8, rgb565(16, 52, 28));
    const int cx = x(192), cy = y(656);
    const uint16_t clay = rgb565(kClayRgb), sage = rgb565(kSageRgb), amber = rgb565(kAmberRgb);
    auto seg = [&](int ax, int ay, int bx, int by, int width, uint16_t ink) {
      r.line({cx + ax, cy + ay}, {cx + bx, cy + by}, width, ink);
    };
    // A row of px, `from` across `n`.
    auto row = [&](int yy, int from, int n, uint16_t ink) { r.round(cx + from, cy + yy, n, 1, 0, ink); };
    // A triangle wave over `period` ms, 0 … `span` and back.
    auto swing = [&](int period, int span) {
      const int at = int(ms % uint32_t(period)), half = period / 2;
      return (at < half ? at : period - at) * span / half;
    };
    switch (icon) {
      case MonitorIcon::kPencil: {
        // It writes a line left to right, then lifts and starts again.
        const int go = std::min(int(ms % 2400), 2000) * 40 / 2000, px = -20 + go;
        if (go > 1) seg(-22, 13, -22 + go, 13, 2, green);
        seg(px, 9, px + 18, -9, 6, light);
        seg(px - 3, 12, px, 9, 3, green);
        break;
      }
      case MonitorIcon::kGlass: {
        const int dx = swing(2800, 18) - 9, dy = swing(1900, 6) - 3;
        r.ring(cx + dx - 16, cy + dy - 14, 20, 20, 10, 3, light);
        seg(dx + 1, dy + 3, dx + 11, dy + 13, 4, light);
        break;
      }
      case MonitorIcon::kPrompt:
        seg(-24, -9, -14, 0, 3, green);
        seg(-14, 0, -24, 9, 3, green);
        if (ms % 1000 < 600) r.round(cx - 8, cy + 5, 16, 5, 2, green);
        break;
      case MonitorIcon::kFlask: {
        // The liquid rises over 2.4 s, and again.
        const int level = 13 - std::min(int(ms % 3000), 2400) * 11 / 2400;
        for (int yy = level; yy <= 13; ++yy) {
          const int half = 4 + (yy + 5) * 10 / 19;
          if (yy >= -5) row(yy, -half + 2, 2 * half - 4, green);
        }
        seg(-4, -15, -4, -5, 2, light);
        seg(4, -15, 4, -5, 2, light);
        seg(-7, -15, 7, -15, 2, light);
        seg(-4, -5, -14, 14, 2, light);
        seg(4, -5, 14, 14, 2, light);
        seg(-14, 14, 14, 14, 2, light);
        break;
      }
      case MonitorIcon::kHourglass: {
        // The sand runs down over 4 s, and again.
        const int run = int(ms % 4000) * 11 / 4000;
        for (int yy = -11 + run; yy < 0; ++yy) row(yy, yy * 9 / 12, -yy * 9 / 6, blue);
        for (int yy = 12 - run; yy <= 12; ++yy) row(yy, -yy * 9 / 12, yy * 9 / 6, blue);
        seg(-11, -14, 11, -14, 3, light);
        seg(-11, 14, 11, 14, 3, light);
        seg(-9, -12, 9, 12, 2, light);
        seg(9, -12, -9, 12, 2, light);
        break;
      }
      case MonitorIcon::kCross:
        seg(-11, -11, 11, 11, 5, clay);
        seg(11, -11, -11, 11, 5, clay);
        break;
      case MonitorIcon::kClock:
        r.ring(cx - 14, cy - 14, 28, 28, 14, 3, amber);
        seg(0, 0, 0, -9, 3, amber);
        seg(0, 0, 7, 3, 3, amber);
        break;
      case MonitorIcon::kTick:
        seg(-12, 0, -3, 9, 5, sage);
        seg(-3, 9, 13, -9, 5, sage);
        break;
    }
  }
  // The keyboard and the paws: out with the desk, or alone while it types
  // along with you (Paws::keys).
  const int deskAlpha = (s.desk.x * 255).integer(), alongAlpha = paws ? paws->keys : 0;
  if (std::max(deskAlpha, alongAlpha) > 0) {
    const uint32_t ms = uint32_t(F(e.timeMs()).integer());
    // They go as it melts, which would leave them lying across its face.
    r.alpha = std::max(deskAlpha, alongAlpha) * (4096 - (paws ? paws->melted : 0)) / 4096;
    // At the desk the paws type on softly between its keys; while you type
    // they type with you, briskly, at the desk or with the keyboard alone;
    // the keyboard alone and you still, they rest.
    const bool brisk = paws && paws->tapping, soft = brisk || deskAlpha >= alongAlpha;
    auto lift = [&](int side) { return brisk ? briskLift(paws->phase, side) : typeLift(ms, side); };
    round(387, 713, 258, 30, 8, rgb565(49, 88, 107));
    for (int row = 0; row < 2; ++row)
      for (int key = 0; key < 9; ++key) {
        bool pressed = contact > q(.35) && key == (s.hasLast && s.last.side < 0 ? 2 : 6);
        // Typing with you: the keys under a paw light as it comes down.
        if (brisk && (key == 1 || key == 2 || key == 6 || key == 7))
          pressed = pressed || lift(key < 4 ? -1 : 1) < kBriskLift / 3;
        round(397 + key * 26, 718 + row * 10, 19, 6, 2, pressed ? light : rgb565(144, 170, 176));
      }
    // The paws, by the activity, easing from one pose to the next
    // (Scenes::pose): on the keys and typing; off the keys and still on the
    // desk, to the monitor's side, as it looks; lifted and held together in
    // front as something runs; flat on the keys as it waits.
    const F looking = s.posed(Activity::kLooking), running = s.posed(Activity::kRunning),
            waiting = s.posed(Activity::kWaiting), typing = clamp(F(1) - looking - running - waiting, 0, 1);
    for (int side : {-1, 1}) {
      const int i = side > 0;
      const int taps = (typing * std::max(tapLift(s, side), soft ? lift(side) : 0)).integer();
      const int lift =
          taps + (paws ? paws->lift[i] : 0) +
          (looking * kLookingPaws.lift[i] + running * kRunningPaws.lift[i] + waiting * kWaitingPaws.lift[i]).integer();
      const int dx =
          (paws ? paws->dx[i] : 0) +
          (looking * kLookingPaws.dx[i] + running * kRunningPaws.dx[i] + waiting * kWaitingPaws.dx[i]).integer();
      // A failure landing: the paws flail up and down, by turns, a beat
      // after the knock.
      const int flail = flailLift(stream, streamNow, side);
      int yy = 711 + (s.hasLast && s.last.side == side ? (contact * 9).integer() : 0) - lift - flail;
      // Its hand, a pad flat on the keys, unless the hand's elsewhere.
      if (handsPlan().has(side, HandsAt::kDesk))
        paintHand(r, onKeys(x(500 + side * (78 + flail / 3) + dx), y(yy), kDeskHandPx));
    }
  }
  // Each prop's alpha is its ramped visibility; one fading out still draws
  // the content it last showed.
  const T now = e.timeMs();
  r.alpha = 255;
  if (F listening = s.visible(Scenes::kListeningProp, now); listening > F(0)) {
    r.alpha = (listening * 255).integer();
    // The mic and its label in a row over the head, centred together, the
    // label in the large font to read at arm's length, as the cards' do,
    // and clear of the dome's top. The ring breathes in sixteenths of a
    // pixel, two pixels wide, its outer edge 15.5 to 21.5 px out.
    constexpr int kMic = 372, kLabel = 555;
    circle16(r, x(kMic) * 16 + 8, y(144) * 16 + 8, 15 * 16 - 8 + (s.listeningPulse * 96).integer(), 2 * 16, blue);
    round(kMic - 8, 119, 16, 31, 8, light);
    r.line({x(kMic), y(153)}, {x(kMic), y(164)}, 2, blue);
    text("LISTENING", kLabel, 144, light, kLarge);
  }
  r.alpha = 255;
  if (F alert = s.visible(Scenes::kAlertProp, now); alert > F(0)) {
    r.alpha = (alert * 255).integer();
    // A knock's ring round the kind's mark reaches a row above its radius.
    const F knock = state == SceneState::kNeedsYou ? s.envelope(now, kKnock) : F(0);
    const Placed c = place(surface, kAlertCard);
    const AttnKind kind = e.router.facts.attention.kind;
    const uint16_t fill = rgb565(kAmberRgb), ink = rgb565(kNeedsYouInkRgb), soft = mix565(fill, ink, 204);
    // The kind's mark in its column on the left, the two lines after it,
    // left-aligned, so the card scans as a mark and two lines; with no kind
    // the two centred, the second the old one.
    const int markX = c.x + 36, markY = c.y + c.h / 2, lines = c.x + 64;
    const int knockRadius = 22 + (knock * 5).integer();
    drawCard(
        kAlertCard, fill, fill,
        [&] {
          const int top = c.y + 4, second = top + 30;
          if (kind == AttnKind::kNone) {
            const char* more = "Continue on your Mac";
            render::gel::text(r, kSign, c.x + (c.w - 9 * kSign.w) / 2, top, "NEEDS YOU", ink);
            render::gel::text(r, kLarge, c.x + (c.w - glyphCount(more) * kLarge.w) / 2, second + 4, more, soft);
            return;
          }
          if (kind == AttnKind::kPlan) {
            // A page, three lines on it.
            r.round(markX - 14, markY - 18, 28, 36, 4, ink);
            for (int i = 0; i < 3; ++i) r.round(markX - 9, markY - 10 + i * 8, i == 2 ? 11 : 18, 3, 1, fill);
          } else {
            r.disk(markX, markY, 18, ink);
            if (kind == AttnKind::kQuestion) {
              render::gel::text(r, kSign, markX - kSign.w / 2, markY - 25, "?", fill);
            } else {
              // A yes and a no, split: a tick on the left half, a cross on the right.
              r.line({markX - 12, markY}, {markX - 8, markY + 5}, 3, fill);
              r.line({markX - 8, markY + 5}, {markX - 2, markY - 6}, 3, fill);
              r.line({markX + 3, markY - 5}, {markX + 11, markY + 5}, 3, fill);
              r.line({markX + 11, markY - 5}, {markX + 3, markY + 5}, 3, fill);
            }
          }
          render::gel::text(r, kSign, lines, top, "NEEDS YOU", ink);
          render::gel::text(r, kSign, lines, second, attnKindWords(kind), soft, c.x + c.w - 12 - lines);
        },
        knock > 0 && kind != AttnKind::kNone ? markY - knockRadius - 1 : 1 << 30);
    if (knock > 0 && kind != AttnKind::kNone) {
      r.alpha = (knock * 255).integer();
      circle16(r, markX * 16 + 8, markY * 16 + 8, knockRadius * 16, 2 * 16, ink);
    }
  }
  // What's drawn over the cards after them, as the frame goes on, lowers
  // cardKeyTo (Surface::touch).
  surface.cardKey = cards;
  surface.cardKeyTo = cardsTo;
  std::copy(drawn, drawn + drawnCount, surface.cardBoxes);
  surface.cardBoxCount = drawnCount;
}
}  // namespace render::gel
