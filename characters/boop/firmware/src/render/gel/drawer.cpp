#include "render/gel/drawer.h"
#include "render/gel/hands.h"

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

// The sheet black, as the lane is; rows a touch lighter. Warm greys, as the
// lane's.
constexpr uint16_t kSheet = rgb565(0, 0, 0), kRow = rgb565(22, 28, 36), kRowNeedsYou = rgb565(42, 31, 0),
                   kRowPicked = rgb565(44, 57, 70), kTitle = rgb565(kEyeRgb), kResting = rgb565(kNarrationRgb),
                   kWorkingBar = rgb565(89, 97, 107), kIdleBar = rgb565(58, 65, 75), kEyes = rgb565(8, 36, 72),
                   kCheeks = rgb565(255, 140, 200);
constexpr int kRowRadius = 10, kBar = 6, kCornerGap = 4, kMargin = 18;
// How far the sheet's corners round as it opens, at its whole.
constexpr int kSheetRadius = 20;
// A thumb kThumbW × kThumbH beside the rows says how far down the list is.
constexpr int kThumbW = 3, kThumbH = 40;
constexpr int kFadeRows = DrawerLayout::kFadeRows;

uint16_t barInk(const Drawer::Row& row) {
  switch (row.status) {
    case Drawer::Status::kNeedsYou: return rgb565(kAmberRgb);
    case Drawer::Status::kWorking: return laneInkOr(row.slot, kWorkingBar);
    default: return kIdleBar;
  }
}

// One row: its bar in the session's colour, the thread's name in the
// sign's font, the agent and project under it in the large one, grey, and
// at its end what it's doing as the strip's mark says it.
void row(Raster& r, const DrawerLayout& l, const Drawer::Row& row, int y, bool picked, int spin) {
  const int x = l.margin(), w = l.w - 2 * l.margin(), h = l.rowH();
  const bool needs = row.status == Drawer::Status::kNeedsYou, idle = row.status == Drawer::Status::kIdle;
  r.round(x, y, w, h, kRowRadius, picked ? kRowPicked : needs ? kRowNeedsYou : kRow);
  const Box list = r.bounds;  // the bar is the row's own rounded left end
  r.bounds = {x, std::max(y, list.y0), x + kBar, std::min(y + h, list.y1)};
  r.round(x, y, kRowRadius * 2, h, kRowRadius, barInk(row));
  r.bounds = list;
  constexpr int kMarkBox = 18, kMarkPad = 14;
  const int markX = x + w - kMarkPad - kMarkBox;
  paintStatusMark(r, needs ? StatusMark::kNeedsYou : idle ? StatusMark::kIdle : StatusMark::kWorking, markX,
                  y + h / 2, spin);
  // The thread's name, and under it the agent and its project.
  const int tx = x + kBar + 14, room = markX - 12 - tx;
  text(r, kSign, tx, y + 3, row.title[0] ? row.title : "Untitled", needs ? rgb565(kAmberRgb) : idle ? kResting : kTitle,
       room);
  char under[48];
  if (row.project[0])
    std::snprintf(under, sizeof(under), "%s \xC2\xB7 %s", row.agent, row.project);
  else
    std::snprintf(under, sizeof(under), "%s", row.agent);
  text(r, kLarge, tx, y + 35, under, kResting, room);
}

}  // namespace

DrawerLayout::DrawerLayout(int width, int height, int cornerRadius) : w(width), h(height), corner(cornerRadius) {}

int DrawerLayout::restTop() const { return h * kStripTop / kHeight; }

int DrawerLayout::margin() const {
  // Clear of the panel's corners down to where the rows fade out: the last
  // row's foot, under that, is mostly gone.
  const int foot = h - kFadeRows;
  return std::max(kMargin, Surface::insetOf(w, h, corner, foot - 1, foot, kRowRadius) + kCornerGap);
}

void DrawerLayout::shown(const Drawer& d, int& first, int& last) const {
  const int scrolled = d.scroll * 3 / 2, hidden = scrolled - rowH();  // under the lid, past the first row's end
  first = hidden < 0 ? 0 : hidden / pitch() + 1;
  last = std::min(d.total() - 1, (h - 1 - listTop(d.open) + scrolled) / pitch());
}

int DrawerLayout::rowAt(const Drawer& d, int canvasX, int canvasY) const {
  const int x = nativeX(canvasX), y = nativeY(canvasY);
  if (x < margin() || x >= w - margin() || y < listTop(1000)) return -1;
  // The gap between two rows is the nearer one's: every pixel of the
  // list hits a row, each a pitch tall.
  const int top = listTop(1000) - d.scroll * 3 / 2, gap = pitch() - rowH();
  if (y < top - gap / 2) return -1;
  const int i = (y - top + gap / 2) / pitch();
  return i < d.total() ? i : -1;
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
  // On the rows' margin, or clear of the panel's corners where the lid is.
  const int lid = std::max(l.margin(), s.inset(cy - 19, cy + 19) + kCornerGap);
  paintRule(r, lid, s.width - lid, top, true);
  paintCounts(r, strip, lid, s.width - lid, cy, spin);
  // The rows, scrolled under the lid; a session whose row hasn't come
  // yet is an empty one till it does.
  int first, last;
  l.shown(d, first, last);
  r.bounds = {0, l.listTop(d.open), s.width, s.height};
  for (int i = first; i <= last; ++i) {
    const int y = l.rowTop(d.open, i) - d.scroll * 3 / 2;
    if (const Drawer::Row* at = d.at(i))
      row(r, l, *at, y, i == d.picked, spin);
    else
      r.round(l.margin(), y, l.w - 2 * l.margin(), l.rowH(), kRowRadius, kRow);
  }
  r.bounds = Raster::kEverywhere;
  // The rows fade into the sheet at the panel's foot, and with more than a
  // screenful, a thumb beside them says where the list is.
  for (int y = std::max(l.listTop(d.open), s.height - kFadeRows); y < s.height; ++y) {
    const int alpha = 255 * (s.height - y) / (kFadeRows + 1);
    uint16_t* line = s.pixels + y * s.width;
    for (int x = 0; x < s.width; ++x)
      if (line[x]) line[x] = mix565(0, line[x], alpha);
  }
  if (d.total() > l.fits() && open > 500) {
    const int most = l.scrollMax(d.total()), span = s.height - kFadeRows - l.listTop(d.open) - kThumbH;
    const int ty = l.listTop(d.open) + (most > 0 ? span * std::clamp(d.scroll, 0, most) / most : 0);
    r.round(s.width - l.margin() + 5, ty, kThumbW, kThumbH, 1, rgb565(kGrabberRgb));
  }
  // A hand, hung over the edge once it's open, dropping into place.
  if (d.paw > 0 && handsPlan().has(1, HandsAt::kDrawer)) {
    // Off to the side of its face, hanging down the sheet's edge.
    const int px = body.crown.x / 16 + l.u(104), py = top - 6 - (1000 - d.paw) * 14 / 1000;
    r.alpha = std::min(255, d.paw * 255 / 600);
    paintHand(r, hung(px, py + 10));
    r.alpha = 255;
  }
}

}  // namespace render::gel
