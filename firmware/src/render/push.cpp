#include "render/push.h"

#include <algorithm>

namespace render {

namespace {

int ceilDiv(int a, int b) { return (a + b - 1) / b; }

Span unite(Span a, Span b) {
  if (a.empty()) return b;
  if (b.empty()) return a;
  return {std::min(a.x0, b.x0), std::max(a.x1, b.x1)};
}

Span written(const Surface::Span& s) { return s.last ? Span{s.first, s.last} : Span{}; }

}  // namespace

uint32_t PushPlan::pixels() const {
  uint32_t n = 0;
  for (int b = 0; b < bands; ++b)
    for (int r = 0; r < runCount[b]; ++r) n += uint32_t(columns(b)) * uint32_t(runs[b][r].x1 - runs[b][r].x0);
  return n;
}

PanelWindow packBand(const Surface& s, int band, Span span, bool topOnLeft, uint16_t* out) {
  const int x0 = band * PushPlan::kColumns, count = std::min(PushPlan::kColumns, s.width - x0);
  const int y0 = span.x0, y1 = span.x1, w = y1 - y0;
  // Each panel row is one of the band's surface columns, the last first
  // with the top on the left (else the first), its pixels the surface's
  // rows down (else up). Read a surface row's few columns at a time, a
  // cache line, and scatter them into the panel's rows.
  for (int y = y0; y < y1; ++y) {
    const uint16_t* src = s.pixels + y * s.width + x0;
    const int i = topOnLeft ? y - y0 : y1 - 1 - y;
    for (int c = 0; c < count; ++c) {
      const int row = topOnLeft ? count - 1 - c : c;
      out[row * w + i] = uint16_t((src[c] << 8) | (src[c] >> 8));
    }
  }
  return {topOnLeft ? y0 : s.height - y1, topOnLeft ? s.width - x0 - count : x0, w, count};
}

SurfacePair::SurfacePair(int width, int height, uint16_t* a, uint16_t* b, int corner) {
  s_[0].width = s_[1].width = width;
  s_[0].height = s_[1].height = height;
  s_[0].corner = s_[1].corner = corner;
  s_[0].pixels = a;
  s_[1].pixels = b;
}

bool SurfacePair::ready() const {
  return s_[0].pixels && s_[1].pixels && s_[0].height <= Surface::kTrackedRows && s_[0].width <= PushPlan::kMaxWidth;
}

// What may differ from front's frame. Each surface is black outside its
// written spans (Surface::clear), so only the spans either frame wrote can
// differ. A lane the face drew itself under the same key in both frames is
// the same pixels, so its rows can't differ at all. A surface written whole
// (a test pattern) sends the whole surface.
const PushPlan& SurfacePair::present() {
  plan_ = PushPlan{};
  if (!drawn_) return plan_;
  const Surface& next = s_[back_];
  const Surface& shown = s_[back_ ^ 1];
  const int width = next.width, height = next.height;
  plan_.width = width;
  plan_.height = height;
  plan_.bands = ceilDiv(width, PushPlan::kColumns);
  plan_.full = shown.invalid || next.invalid;
  const int same =
      next.laneKey && next.laneKey == shown.laneKey && next.laneKeyFrom == shown.laneKeyFrom && next.laneKeyFrom >= 0
          ? next.laneKeyFrom
          : height;
  if (plan_.full) {
    for (int band = 0; band < plan_.bands; ++band) plan_.runs[band][0] = {0, height}, plan_.runCount[band] = 1;
  } else {
    // Each row either frame wrote joins every band its columns cross: the
    // band's last run, if it ended within kRunGap rows, else a new one
    // (the last, once there are kRuns).
    for (int y = 0; y < same; ++y) {
      const Span row = unite(written(shown.written[y]), written(next.written[y]));
      if (row.empty()) continue;
      const int last = std::min(plan_.bands, ceilDiv(row.x1, PushPlan::kColumns));
      for (int band = row.x0 / PushPlan::kColumns; band < last; ++band) {
        uint8_t& n = plan_.runCount[band];
        auto& runs = plan_.runs[band];
        if (n && (y - runs[n - 1].x1 <= PushPlan::kRunGap || n == PushPlan::kRuns))
          runs[n - 1].x1 = y + 1;
        else
          runs[n++] = {y, y + 1};
      }
    }
    // Out to even rows, joining runs that then meet.
    for (int band = 0; band < plan_.bands; ++band) {
      auto& runs = plan_.runs[band];
      int kept = 0;
      for (int r = 0; r < plan_.runCount[band]; ++r) {
        const Span even{runs[r].x0 & ~1, std::min(height, (runs[r].x1 + 1) & ~1)};
        if (kept && even.x0 <= runs[kept - 1].x1)
          runs[kept - 1].x1 = std::max(runs[kept - 1].x1, even.x1);
        else
          runs[kept++] = even;
      }
      plan_.runCount[band] = uint8_t(kept);
    }
  }
  for (int band = 0; band < plan_.bands; ++band)
    if (plan_.runCount[band])
      plan_.spans[band] = {plan_.runs[band][0].x0, plan_.runs[band][plan_.runCount[band] - 1].x1};
  back_ ^= 1;
  drawn_ = false;
  return plan_;
}

}  // namespace render
