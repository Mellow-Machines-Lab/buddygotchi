// The agents' drawer on the gel (render/drawer.h): the strip rides up
// as its lid, the sheet of rows comes out under it, and the body is
// pressed flat against the top of the glass, its eyes squeezed shut and
// its cheeks pink, one paw hung over the sheet's edge.
#pragma once
#include <algorithm>

#include "render/drawer.h"
#include "render/rig/rig.h"
#include "render/screens.h"
#include "render/surface.h"

namespace render::gel {

// Where things are, on a surface w × h (the AMOLED's 502 × 410, its
// corners rounded by `corner`), in its pixels.
struct DrawerLayout {
  int w, h, corner;
  DrawerLayout(int width, int height, int cornerRadius);
  // A length laid out for the 410 rows of the AMOLED, on this surface.
  int u(int v) const { return v * h / 410; }
  // The sheet's top edge: the strip's rule when shut, near the top open.
  int restTop() const;
  int openTop() const { return u(66); }
  int top(int open) const { return restTop() + (openTop() - restTop()) * open / 1000; }
  // Where the rows start, under the lid; row i's top there, scrolled by
  // none; and the rows' height, the step from one to the next, sides and
  // corners.
  int listTop(int open) const { return top(open) + u(56); }
  int rowTop(int open, int i) const { return listTop(open) + i * pitch(); }
  int rowH() const { return u(48); }
  int pitch() const { return rowH() + u(5); }
  int margin() const;
  // How many rows the glass shows whole, open: a screenful, and how far a
  // list of `total` scrolls, canvas px, to bring its last row to the
  // screenful's last place.
  int fits() const { return (h - listTop(1000) + u(5)) / pitch(); }
  int scrollMax(int total) const { return scrolledBy(std::max(0, total - fits())); }
  // The scroll, canvas px, that brings row i to the top, and the nearest
  // such to `scroll`.
  int scrolledBy(int i) const { return i * pitch() * 2 / 3; }
  int snap(int scroll) const { return scrolledBy((scroll * 3 / 2 + pitch() / 2) / pitch()); }
  // The first and last rows any of which shows, scrolled as `d` is (none
  // when last < first).
  void shown(const Drawer& d, int& first, int& last) const;
  // The canvas's 320 × 240, as the panel's touch reads it, in this
  // surface's pixels: the canvas drawn half as large again, centred.
  int nativeX(int canvasX) const { return (w - 480) / 2 + canvasX * 3 / 2; }
  int nativeY(int canvasY) const { return (h - 360) / 2 + canvasY * 3 / 2; }
  // How far a finger moves, canvas px, to pull the sheet from shut to open.
  int travel() const { return (restTop() - openTop()) * 2 / 3; }
  // The session under the canvas point x, y with the drawer open, by its
  // place in the list (whether or not its row has come), or -1.
  int rowAt(const Drawer& d, int canvasX, int canvasY) const;
};

// How the body is pressed under the sheet: the rows it fills, top to
// bottom (it carries on behind the sheet's edge), how much wider it
// spreads (Q12), and whether it's squashed far enough that its eyes
// squeeze shut (then it wears none of its art, layers or props).
struct DrawerPose {
  int top = 0, bottom = 0, widen = 4096;
  bool squint = false;
};
DrawerPose drawerPose(const Surface& s, const Drawer& d);

// The squeezed face, on the body's front between the pose's top and the
// sheet's edge.
void paintSquint(Surface& s, const rig::Anchors& body, const DrawerPose& pose, int sheetTop);
// The sheet, its lid (the strip's counts, the working spinner on `spin`)
// and rows, and the paw over its edge.
void paintDrawer(Surface& s, const Drawer& d, const Strip& strip, const rig::Anchors& body, int spin = 0);

}  // namespace render::gel
