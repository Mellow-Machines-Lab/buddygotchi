// Touch calibration: an affine map from the touch controller's
// raw readings to screen pixels. `boopctl calibrate` fits it from 4 taps and
// sends it with dbg.touchcal; the board keeps it in NVS. Until then the
// board's default map is used (BoardHal). Pure C++.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>

#include "render/canvas.h"
#include "render/maths.h"

namespace app {

struct TouchCal {
  // x = (ax·rx + bx·ry + cx) / 65536, and the same for y.
  int32_t ax = 0, bx = 0, cx = 0;
  int32_t ay = 0, by = 0, cy = 0;
  bool valid = false;

  void map(int rx, int ry, int& x, int& y) const {
    int64_t fx = int64_t(ax) * rx + int64_t(bx) * ry + cx;
    int64_t fy = int64_t(ay) * rx + int64_t(by) * ry + cy;
    x = render::clamp(int((fx + 32768) >> 16), 0, render::kWidth - 1);
    y = render::clamp(int((fy + 32768) >> 16), 0, render::kHeight - 1);
  }
};

// What NVS keeps: the map and the screen it was fitted on. A map fitted on
// another screen, like a portrait build's or one from before kRotation was
// flipped, is never applied; the default map is used until `boopctl
// calibrate` runs again.
// The board's default map, before `boopctl calibrate`: a panel of
// `panelWidth` × `panelHeight` pixels, portrait, that shows the whole
// surface turned a quarter (render::packBand), its top on the panel's left
// edge or its right, read back as the 320 × 240 screen the face is drawn
// over (each canvas pixel `width / 320` surface pixels across).
inline TouchCal wholePanelTouchCal(int panelWidth, int panelHeight, bool topOnLeft) {
  const int32_t across = int32_t(int64_t(65536) * render::kWidth / panelHeight),
                down = int32_t(int64_t(65536) * render::kHeight / panelWidth);
  TouchCal c;
  if (topOnLeft) {
    c.bx = -across, c.cx = (panelHeight - 1) * across;  // x = (panelHeight - 1 - ry) · 320 / panelHeight
    c.ay = down;                                        // y = rx · 240 / panelWidth
  } else {
    c.bx = across;                                 // x = ry · 320 / panelHeight
    c.ay = -down, c.cy = (panelWidth - 1) * down;  // y = (panelWidth - 1 - rx) · 240 / panelWidth
  }
  c.valid = true;
  return c;
}

struct SavedTouchCal {
  uint16_t w = 0, h = 0;
  uint8_t rotation = 0;
  TouchCal cal;
};

inline SavedTouchCal saveTouchCal(const TouchCal& c, int rotation) {
  SavedTouchCal s;
  s.w = uint16_t(render::kWidth), s.h = uint16_t(render::kHeight), s.rotation = uint8_t(rotation);
  s.cal = c;
  return s;
}

// The stored map, if `n` bytes at `blob` were saved for this screen size and
// rotation. False for anything else, including the old portrait record.
inline bool loadTouchCal(const void* blob, size_t n, int rotation, TouchCal& out) {
  SavedTouchCal s;
  if (!blob || n != sizeof(s)) return false;
  std::memcpy(&s, blob, sizeof(s));
  if (s.w != render::kWidth || s.h != render::kHeight || s.rotation != rotation || !s.cal.valid) return false;
  out = s.cal;
  return true;
}

}  // namespace app
