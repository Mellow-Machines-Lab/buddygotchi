#include "render/gel/done.h"

#include <algorithm>
#include <iterator>

#include "render/font.h"
#include "render/gel/fixed.h"
#include "render/gel/lane.h"
#include "render/gel/raster.h"
#include "render/gel/subpixel.h"
#include "render/maths.h"
#include "render/palette.h"

namespace render::gel {
namespace {

// The ticket: its body's top at rest and its height, its corners, its rim,
// the room either side of its mark and words, and how far it stays in from
// the panel's rounded corners. Its words are the bubble's size.
constexpr int kTicketTop = 26, kTicketTall = 40, kTicketRadius = 10, kTicketRim = 2, kTicketPad = 12, kMarkWide = 18,
              kMarkGap = 8, kCornerGap = 6, kMostGlyphs = 20;
// Beside a success's trophy, which pops up over the middle: its string
// hangs from a quarter of the way across, and it stays left of the
// trophy's edge (thousandths of the width).
constexpr int kBesideTrophyAt = 250, kBesideTrophyTo = 420;
// Once in, it sways on its string: a swing that dies away over kSwingMs,
// then a little one that goes on.
constexpr int kSwingPx = 5, kSwingMs = 1500, kSwingPeriodMs = 900, kSwayPx16 = 24, kSwayPeriodMs = 2600;
constexpr uint16_t kTicketFill = rgb565(22, 20, 18);

uint16_t inkOf(Outcome o) {
  return o == Outcome::kSuccess ? rgb565(kSageRgb) : o == Outcome::kFailure ? rgb565(kClayRgb) : rgb565(kEyeRgb);
}

uint32_t isqrt(uint32_t v) {
  uint32_t root = 0, bit = 1u << 30;
  while (bit > v) bit >>= 2;
  while (bit) {
    if (v >= root + bit) {
      v -= root + bit;
      root = (root >> 1) + bit;
    } else {
      root >>= 1;
    }
    bit >>= 2;
  }
  return root;
}

// Its mark, the strip's for a finish: a tick for a success, a cross for a
// failure, else three dots, from x16, its middle on row cy16.
void mark16(Raster& r, Outcome o, int x16, int cy16, uint16_t ink) {
  auto at = [&](int dx, int dy) { return Point{x16 + dx * 16, cy16 + dy * 16}; };
  if (o == Outcome::kSuccess) {
    const Point v[] = {at(2, 0), at(7, 5), at(16, -6)};
    r.stroke16(v, 3, 3 * 16, ink);
  } else if (o == Outcome::kFailure) {
    const Point a[] = {at(3, -6), at(15, 6)}, b[] = {at(15, -6), at(3, 6)};
    r.stroke16(a, 2, 3 * 16, ink);
    r.stroke16(b, 2, 3 * 16, ink);
  } else {
    for (int i = 0; i < 3; ++i) r.disk16(x16 + (3 + 6 * i) * 16, cy16, 40, ink);
  }
}

}  // namespace

int doneGlow(const DoneShow& d) {
  if (!d.shows()) return 0;
  const int peak = d.outcome == Outcome::kNone ? kGlowPeakFaint : kGlowPeak;
  int g = peak * ease(int(std::min<uint32_t>(d.ms, kGlowInMs)), kGlowInMs) / 1024;
  if (d.leftMs >= 0) g = g * ease(std::min(int(d.leftMs), kGlowOutMs), kGlowOutMs) / 1024;
  return g;
}

void paintTicket(Surface& s, const DoneShow& d) {
  if (!s.pixels || !d.shows()) return;
  Raster r{s};
  const Font& f = kLarge;
  const uint16_t ink = inkOf(d.outcome), string = rgb565(kGreyRgb);
  // Where it may hang: clear of the panel's corners on its rows, and of a
  // success's trophy.
  const int edge = s.inset(kTicketTop, kTicketTop + kTicketTall, kTicketRadius) + kCornerGap;
  const bool trophy = d.outcome == Outcome::kSuccess;
  const int from = edge, to = trophy ? s.width * kBesideTrophyTo / 1000 : s.width - edge,
            at = trophy ? s.width * kBesideTrophyAt / 1000 : s.width / 2;
  const int frame = 2 * kTicketPad + kMarkWide + kMarkGap;
  // Its thread's name, else the agent's, cut to what fits.
  char label[64];
  const int most = std::clamp((to - from - frame) / f.w, 4, kMostGlyphs);
  foldText(d.thread && *d.thread ? d.thread : d.agent, most, label, sizeof label);
  const int wide = frame + glyphCount(label) * f.w;
  const int x0 = std::clamp(at - wide / 2, from, std::max(from, to - wide));
  const int hang = x0 + wide / 2;  // where its string's tied, on the panel's top edge

  // Down from above the top, a little past its place and back, as it
  // comes; back up as it goes.
  const int ms = int(std::min<uint32_t>(d.ms, 1u << 30)), lift = (kTicketTop + kTicketTall + 8) * 16;
  int dy16 = 0;
  if (ms < kTicketDropMs) {
    static constexpr struct {
      int t, v;
    } kDrop[] = {{0, -4096}, {380, 400}, {540, -140}, {kTicketDropMs, 0}};
    for (size_t i = 1; i < std::size(kDrop); ++i)
      if (ms <= kDrop[i].t) {
        const int e = ease(ms - kDrop[i - 1].t, kDrop[i].t - kDrop[i - 1].t);
        dy16 = lerp(kDrop[i - 1].v, kDrop[i].v, e, 1024) * lift / 4096;
        break;
      }
  }
  if (d.leftMs >= 0 && d.leftMs < kTicketRiseMs) dy16 -= lift * ease(kTicketRiseMs - d.leftMs, kTicketRiseMs) / 1024;
  // Swinging on its string once it's in, a swing that dies away, and a
  // little sway that doesn't.
  int dx16 = kSwayPx16 * sinTurn(ms * 4096 / kSwayPeriodMs) / 4096;
  if (const int in = ms - kTicketDropMs / 2; in > 0 && in < kSwingMs)
    dx16 += kSwingPx * 16 * (kSwingMs - in) / kSwingMs * sinTurn(in * 4096 / kSwingPeriodMs) / 4096;

  const int x16 = x0 * 16 + dx16, y16 = kTicketTop * 16 + dy16, w16 = wide * 16, h16 = kTicketTall * 16;
  if (y16 + h16 <= 0) return;
  // The string, from the top edge to the eyelet on its top.
  const Point line[] = {{hang * 16 + 8, -16}, {x16 + w16 / 2, y16 + 4 * 16}};
  r.stroke16(line, 2, 2 * 16, string);
  round16(r, x16, y16, w16, h16, kTicketRadius * 16, ink);
  const int rim = kTicketRim * 16;
  round16(r, x16 + rim, y16 + rim, w16 - 2 * rim, h16 - 2 * rim, (kTicketRadius - kTicketRim) * 16, kTicketFill);
  r.disk16(x16 + w16 / 2, y16 + 4 * 16, 3 * 16 + 8, string);
  const int cy16 = y16 + h16 / 2;
  mark16(r, d.outcome, x16 + kTicketPad * 16, cy16, ink);
  text16(r, f, x16 + (kTicketPad + kMarkWide + kMarkGap) * 16, cy16 - f.h * 8, label, ink);
}

// Each pixel takes the outcome's ink by how far in from the panel's edge
// it is, d: (1 - d / kGlowPx)², strongest at the edge. Round the corners
// that's how far in from their arcs; elsewhere from the nearer edge. A row
// holds it only within kGlowPx of an edge, or of a corner's arc.
void paintGlow(Surface& s, const DoneShow& d, int from, int to) {
  const int peak = doneGlow(d);
  if (!s.pixels || peak <= 2) return;
  const uint16_t ink = inkOf(d.outcome);
  const int w = s.width, h = s.height, reach = kGlowPx * 16;
  const int radius = std::clamp(s.corner, 0, std::min(w, h) / 2), r16 = radius * 16;
  uint8_t alphaOf[kGlowPx * 16];
  for (int i = 0; i < reach; ++i) alphaOf[i] = uint8_t(peak * (reach - i) * (reach - i) / (reach * reach));
  // How far in a pixel is, in sixteenths, from its middle; past the reach,
  // or outside the panel, none.
  auto alphaAt = [&](int x, int ey16) {
    const int xc = x * 16 + 8, ex16 = std::min(xc, w * 16 - xc);
    int in;
    if (ex16 < r16 && ey16 < r16) {
      const int cx = r16 - ex16, cy = r16 - ey16;
      in = r16 - int(isqrt(uint32_t(cx * cx + cy * cy)));
    } else {
      in = std::min(ex16, ey16);
    }
    return in < 0 || in >= reach ? 0 : int(alphaOf[in]);
  };
  auto blend = [&](uint16_t* px, int a) {
    if (a > 2) *px = mix565(*px, ink, a);
  };
  for (int y = std::max(0, from); y < std::min(h, to); ++y) {
    const int yc = y * 16 + 8, ey16 = std::min(yc, h * 16 - yc);
    uint16_t* row = s.pixels + y * w;
    // How far in the panel's edge is on this row, past its corners.
    int edge = 0;
    if (ey16 < r16) {
      const int cy = r16 - ey16;
      edge = (r16 - int(isqrt(uint32_t(r16 * r16 - cy * cy)))) / 16;
    }
    if (ey16 < reach) {
      // Near the top or the bottom: all of it, the middle at one strength.
      const int a = alphaOf[ey16];
      for (int x = 0; x < radius; ++x) blend(row + x, alphaAt(x, ey16)), blend(row + w - 1 - x, alphaAt(x, ey16));
      if (a > 2) Blender(ink, a).run(row + radius, w - 2 * radius);
      s.touch(0, y, w, y + 1);
      continue;
    }
    const int band = std::min(w / 2, edge + kGlowPx + 1);
    for (int x = 0; x < band; ++x) {
      const int a = alphaAt(x, ey16);
      blend(row + x, a), blend(row + w - 1 - x, a);
    }
    s.touch(0, y, band, y + 1);
    s.touch(w - band, y, w, y + 1);
  }
}

}  // namespace render::gel
