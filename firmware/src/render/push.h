// How a native face's frames reach the panel: two surfaces
// it draws into alternately, what of each new frame to send, and the quarter
// turn into the panel's windows. Pure C++: the AMOLED's display.cpp sends
// what this plans from a task of its own, and the native tests apply the
// same windows to a model panel.
#pragma once
#include <array>
#include <cstdint>

#include "render/canvas.h"
#include "render/surface.h"

namespace render {

// What one frame sends: the surface in bands of kRows rows (kRows of the
// panel's columns, turned a quarter), and of each band the columns that
// may differ from the frame the panel shows. Spans start and end on even
// columns, as the CO5300 takes windows only at even addresses with even
// sizes; an empty span sends nothing.
struct PushPlan {
  static constexpr int kRows = 16;
  static constexpr int kMaxBands = (Surface::kTrackedRows + kRows - 1) / kRows;
  int width = 0, height = 0;  // the surface's
  int bands = 0;
  bool full = false;  // the whole surface: the first frame, a test pattern, the lane moved
  std::array<Span, kMaxBands> spans{};
  int rows(int band) const { return height - band * kRows < kRows ? height - band * kRows : kRows; }
  uint32_t pixels() const;
};

// A band's window on the panel, in panel pixels. The panel is the surface
// turned a quarter: as wide as the surface is tall.
struct PanelWindow {
  int x = 0, y = 0, w = 0, h = 0;
};

// The window band `band`'s span goes to, its pixels written to `out` in
// the panel's order and byte order (RGB565, high byte first): w × h of
// them, row by row. `topOnLeft` puts the surface's top on the panel's left
// edge (board/config.h's kTopOnPanelLeft).
PanelWindow packBand(const Surface& s, int band, Span span, bool topOnLeft, uint16_t* out);

// Two native surfaces a face draws into alternately: the next
// frame goes into back() while the board sends front(), the frame the
// panel shows or is being sent. Each surface keeps its own written spans,
// so each clears what it held two frames ago. The surfaces' pixels belong
// to the caller (Hal::allocateSurface).
class SurfacePair {
 public:
  SurfacePair(int width, int height, uint16_t* a, uint16_t* b, int corner = 0);
  // Both surfaces were had, and the plan can cover them.
  bool ready() const;
  // Where the next frame is drawn: never the surface being sent.
  Surface& back() { return s_[back_]; }
  const Surface& front() const { return s_[back_ ^ 1]; }
  // The newest frame: what is, or is about to be, on the panel.
  Surface& newest() { return drawn_ ? s_[back_] : s_[back_ ^ 1]; }
  // A frame was drawn into back().
  void drew() { drawn_ = true; }
  // Sends the newest frame: plans what of it may differ from front's, the
  // frame the panel shows, then swaps, so it is front. `canvas` is the
  // lane's source (blit): its changes since the last present say which
  // lane columns changed. With nothing drawn since, it plans nothing. The
  // caller sends the plan before drawing into the new back().
  const PushPlan& present(const Canvas& canvas);
  const PushPlan& plan() const { return plan_; }

 private:
  Surface s_[2];
  int back_ = 0;
  bool drawn_ = false;
  Changes lane_;  // the canvas as of the last present
  PushPlan plan_;
};

}  // namespace render
