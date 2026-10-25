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
  for (int b = 0; b < bands; ++b) n += uint32_t(rows(b)) * uint32_t(spans[b].empty() ? 0 : spans[b].x1 - spans[b].x0);
  return n;
}

PanelWindow packBand(const Surface& s, int band, Span span, bool topOnLeft, uint16_t* out) {
  const int y = band * PushPlan::kRows, count = std::min(PushPlan::kRows, s.height - y);
  const int i0 = span.x0, i1 = span.x1;
  // Each panel row is a surface column, read down the band's rows (or up).
  const int step = topOnLeft ? s.width : -s.width;
  for (int row = 0; row < i1 - i0; ++row) {
    const int x = topOnLeft ? i1 - 1 - row : i0 + row;
    const uint16_t* src = s.pixels + (topOnLeft ? y : y + count - 1) * s.width + x;
    for (int col = 0; col < count; ++col, src += step) *out++ = uint16_t((*src << 8) | (*src >> 8));
  }
  return {topOnLeft ? y : s.height - y - count, topOnLeft ? s.width - i1 : i0, count, i1 - i0};
}

SurfacePair::SurfacePair(int width, int height, uint16_t* a, uint16_t* b, int corner) {
  s_[0].width = s_[1].width = width;
  s_[0].height = s_[1].height = height;
  s_[0].corner = s_[1].corner = corner;
  s_[0].pixels = a;
  s_[1].pixels = b;
}

bool SurfacePair::ready() const {
  return s_[0].pixels && s_[1].pixels && s_[0].height <= Surface::kTrackedRows && s_[0].width <= 0xffff;
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
  plan_.bands = ceilDiv(height, PushPlan::kRows);
  plan_.full = shown.invalid || next.invalid;
  const int same = next.laneKey && next.laneKey == shown.laneKey && next.laneKeyFrom == shown.laneKeyFrom &&
                           next.laneKeyFrom >= 0
                       ? next.laneKeyFrom
                       : height;
  for (int band = 0; band < plan_.bands; ++band) {
    Span span = plan_.full ? Span{0, width} : Span{};
    if (!plan_.full)
      for (int y = band * PushPlan::kRows; y < std::min(same, band * PushPlan::kRows + plan_.rows(band)); ++y)
        span = unite(span, unite(written(shown.written[y]), written(next.written[y])));
    if (!span.empty()) span = {span.x0 & ~1, std::min(width, (span.x1 + 1) & ~1)};
    plan_.spans[band] = span;
  }
  back_ ^= 1;
  drawn_ = false;
  return plan_;
}

}  // namespace render
