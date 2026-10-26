// The screen: each board's display.cpp is the only
// code that knows the display library, and pushes the 8-bit canvas (the
// CYD) or a native face's frames (the AMOLED) to its panel. Touch is
// board/touch.h; the panel settings are in board/config.h.
#pragma once
#include <cstdint>

#include "render/canvas.h"
#include "render/push.h"

namespace board {

bool displayBegin();
// Pushes what changed since the last push: of each band of rows, the
// columns that changed, in DMA batches (render::Changes). Nothing where
// every face draws natively.
void displayPush(const render::Canvas& canvas);
// A native face's frames, supported by AMOLED: waits for
// the frame before to finish sending, presents the newest
// (render::SurfacePair::present) and sends what may have changed from a
// task on core 0, returning at once, so the loop draws the next frame
// meanwhile. False where the panel can't take the frames.
bool displayPush(render::SurfacePair& frames);
// How long the last native frame to finish sending took, in microseconds.
uint32_t displayPushUs();
// How native frames meet the panel's refresh (amoled206/display.cpp):
// kScanOff sends each as it's ready, kScanDown and kScanUp in the panel's
// scan order from the start of a scan, the scan going down its rows from
// the first or up from the last. -1 where the panel has no refresh to
// meet. Its stats: the refresh's rate (0 with none seen lately), and the
// frames sent in step with it, and of those, torn.
constexpr int kScanOff = 0, kScanDown = 1, kScanUp = 2;
void displayScanMode(int mode);
int displayScanMode();
void displayScanStats(uint32_t& hz, uint32_t& pushes, uint32_t& tears);
// A native frame finished sending since the last call: true once for each,
// with the real ms (millis) it finished at, for the latency's frames
// (app::Latency). False where there are no native frames.
bool displayShown(uint32_t& atMs);
void displayBacklight(uint8_t level);
// The screen couldn't start: light what can be lit, so a person sees the
// board is on (main.cpp's fatal loop).
void displayFailed();

}  // namespace board
