#include "render/gel/drawer.h"

#include <algorithm>
#include <cstdio>

#include "render/font.h"
#include "render/gel/lane.h"
#include "render/gel/painter.h"
#include "render/gel/raster.h"
#include "render/palette.h"
#include "render/stream.h"

namespace render::gel {

namespace {

constexpr uint16_t kSheet = rgb565(13, 16, 21), kRow = rgb565(20, 25, 32), kRowNeedsYou = rgb565(42, 31, 0),
                   kRowPicked = rgb565(44, 57, 70), kTitle = rgb565(238, 242, 245), kResting = rgb565(154, 163, 173),
                   kWorkingBar = rgb565(89, 97, 107), kIdleBar = rgb565(58, 65, 75), kEyes = rgb565(8, 36, 72),
                   kCheeks = rgb565(255, 140, 200), kGel = rgb565(89, 169, 224), kToes = rgb565(66, 140, 210),
                   kShine = rgb565(184, 233, 245);
constexpr int kRowRadius = 10, kBar = 6, kCornerGap = 4, kMargin = 18;
// How far the sheet's corners round as it opens, at its whole.
constexpr int kSheetRadius = 20;

uint16_t barInk(const Drawer::Row& row) {
  switch (row.status) {
    case Drawer::Status::kNeedsYou: return rgb565(kAmberRgb);
    case Drawer::Status::kWorking: return row.slot >= 0 && row.slot < Stream::kLanes ? kLaneInk[row.slot] : kWorkingBar;
    default: return kIdleBar;
  }
}

// One row: its bar in the session's colour, the thread's name, the agent
// and project under it, and what it's doing in a chip at its end.
void row(Raster& r, const DrawerLayout& l, const Drawer::Row& row, int y, bool picked) {
  const int x = l.margin(), w = l.w - 2 * l.margin(), h = l.rowH();
  const bool needs = row.status == Drawer::Status::kNeedsYou, idle = row.status == Drawer::Status::kIdle;
  r.round(x, y, w, h, kRowRadius, picked ? kRowPicked : needs ? kRowNeedsYou : kRow);
  const Box list = r.bounds;  // the bar is the row's own rounded left end
  r.bounds = {x, std::max(y, list.y0), x + kBar, std::min(y + h, list.y1)};
  r.round(x, y, kRowRadius * 2, h, kRowRadius, barInk(row));
  r.bounds = list;
  // The chip: filled amber for needs you, else an outline in the strip's
  // working or idle count's inks.
  const char* label = needs ? "NEEDS YOU" : idle ? "IDLE" : "WORKING";
  const int chipW = glyphCount(label) * kSmall.w + 14, chipH = kSmall.h + 6;
  const int chipX = x + w - 10 - chipW, chipY = y + (h - chipH) / 2;
  const uint16_t amber = rgb565(kAmberRgb);
  if (needs)
    r.round(chipX, chipY, chipW, chipH, 6, amber);
  else
    r.ring(chipX, chipY, chipW, chipH, 6, 2, idle ? kIdleRing : kWorkingRing);
  text(r, kSmall, chipX + 7, chipY + 3, label, needs ? rgb565(0, 0, 0) : idle ? kIdleInk : kWorkingInk);
  // The thread's name, and under it the agent and its project.
  const int tx = x + kBar + 14, room = chipX - 12 - tx;
  text(r, kLarge, tx, y + 1, row.title[0] ? row.title : "Untitled", needs ? amber : idle ? kResting : kTitle, room);
  char under[48];
  if (row.project[0])
    std::snprintf(under, sizeof(under), "%s \xC2\xB7 %s", row.agent, row.project);
  else
    std::snprintf(under, sizeof(under), "%s", row.agent);
  text(r, kSmall, tx, y + h - kSmall.h - 3, under, paletteAt(inkAt(kInkGrey, kLevels)), room);
}

}  // namespace

DrawerLayout::DrawerLayout(int width, int height, int cornerRadius) : w(width), h(height), corner(cornerRadius) {}

int DrawerLayout::restTop() const { return h * kStripTop / kHeight; }

int DrawerLayout::margin() const {
  const int last = rowTop(1000, fits() - 1);
  return std::max(kMargin, Surface::insetOf(w, h, corner, last, last + rowH(), kRowRadius) + kCornerGap);
}

void DrawerLayout::shown(const Drawer& d, int& first, int& last) const {
  const int scrolled = d.scroll * 3 / 2, hidden = scrolled - rowH();  // under the lid, past the first row's end
  first = hidden < 0 ? 0 : hidden / pitch() + 1;
  last = std::min(d.total() - 1, (h - 1 - listTop(d.open) + scrolled) / pitch());
}

int DrawerLayout::rowAt(const Drawer& d, int canvasX, int canvasY) const {
  const int x = nativeX(canvasX), y = nativeY(canvasY);
  if (x < margin() || x >= w - margin() || y < listTop(1000)) return -1;
  const int top = listTop(1000) - d.scroll * 3 / 2;
  if (y < top) return -1;
  const int i = (y - top) / pitch();
  return i < d.total() && y - top - i * pitch() < rowH() ? i : -1;
}

DrawerPose drawerPose(const Surface& s, const Drawer& d) {
  const DrawerLayout l(s.width, s.height, s.corner);
  const int restTop = restBodyTop(s.height), restBottom = restBodyBottom(s.height), tall = restBottom - restTop;
  DrawerPose p;
  // Pushed up by the sheet's edge until it meets the glass, then flattened.
  p.bottom = std::min(restBottom, l.top(d.open) + l.u(6));
  p.top = std::max(l.u(6), p.bottom - tall);
  const int k = (p.bottom - p.top) * 4096 / tall;  // how tall it still is, Q12
  p.widen = 4096 + (4096 - k) * 300 / 4096;
  p.squint = k < 4096 * 62 / 100;
  return p;
}

void paintSquint(Surface& s, const rig::Anchors& body, const DrawerPose& pose, int sheetTop) {
  Raster r{s};
  r.limit = s.height;
  const int cx = body.crown.x / 16, ey = (pose.top + std::min(pose.bottom, sheetTop)) / 2 + 2;
  // Squeezed shut, > <, and a wobbly mouth between them.
  for (int side : {-1, 1}) {
    const int x = cx + side * 30;
    const Point eye[3] = {{(x + side * 6) * 16, (ey - 6) * 16}, {(x - side * 4) * 16, ey * 16},
                          {(x + side * 6) * 16, (ey + 6) * 16}};
    r.stroke16(eye, 3, 4 * 16, kEyes);
    r.alpha = 80;
    r.round(x + side * 15 - 7, ey + 6, 14, 7, 3, kCheeks);
    r.alpha = 255;
  }
  const Point mouth[5] = {{(cx - 6) * 16, (ey + 7) * 16},
                          {(cx - 3) * 16, (ey + 10) * 16},
                          {cx * 16, (ey + 7) * 16},
                          {(cx + 3) * 16, (ey + 10) * 16},
                          {(cx + 6) * 16, (ey + 7) * 16}};
  r.stroke16(mouth, 5, 40, kEyes);
}

void paintDrawer(Surface& s, const Drawer& d, const Strip& strip, const rig::Anchors& body, int spin) {
  const DrawerLayout l(s.width, s.height, s.corner);
  Raster r{s};
  r.limit = s.height;
  const int top = l.top(d.open), open = std::clamp(d.open, 0, 1000);
  // The sheet, black behind the strip as it starts up, its corners
  // rounding as it comes.
  r.alpha = std::min(255, open * 255 / 200);
  const int radius = l.u(kSheetRadius) * open / 1000;
  r.round(0, top, s.width, s.height - top + radius + 1, radius, kSheet);
  r.alpha = 255;
  // Its lid: the strip's rule and counts, riding up, clear of the
  // panel's corners where they are.
  const int cy = top + l.u(31);
  const int lid = std::max(kMargin, s.inset(cy - 12, cy + 12) + kCornerGap);
  paintRule(r, lid, s.width - lid, top, open > 500, paletteAt(inkAt(kInkDim, kLevels)));
  paintCounts(r, strip, lid, cy, spin);
  // The rows, scrolled under the lid; a session whose row hasn't come
  // yet is an empty one till it does.
  int first, last;
  l.shown(d, first, last);
  r.bounds = {0, l.listTop(d.open), s.width, s.height};
  for (int i = first; i <= last; ++i) {
    const int y = l.rowTop(d.open, i) - d.scroll * 3 / 2;
    if (const Drawer::Row* at = d.at(i))
      row(r, l, *at, y, i == d.picked);
    else
      r.round(l.margin(), y, l.w - 2 * l.margin(), l.rowH(), kRowRadius, kRow);
  }
  r.bounds = Raster::kEverywhere;
  // The paw, hung over the edge once it's open, dropping into place.
  if (d.paw > 0) {
    // Off to the side of its face, hanging down the sheet's edge.
    const int px = body.crown.x / 16 + l.u(104), py = top - 6 - (1000 - d.paw) * 14 / 1000;
    r.alpha = std::min(255, d.paw * 255 / 600);
    r.round(px - 14, py, 28, 22, 10, kGel);
    for (int i = -1; i <= 1; ++i) r.disk(px + i * 8, py + 21 + (i ? 0 : 2), 5, kToes);
    r.alpha = r.alpha * 160 / 255;
    r.disk(px - 6, py + 5, 3, kShine);
    r.alpha = 255;
  }
}

}  // namespace render::gel
