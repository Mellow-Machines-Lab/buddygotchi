// The Mac's mirror of the board (characters/CHARACTER.md §9): the board's
// firmware as WebAssembly, for the page the popover and onboarding show
// as Boop's face (a pack's mac/mirror/, firmware/tools/mirror.sh builds
// it). The page hands it the messages the Mac sends the board and draws
// its frames. It has no touch, motion sensor, light, sound or card of its
// own, and nothing it says on USB goes further than the page, which reads
// only a snapshot's dbg.state: no `ended` or `ev` of its can act.
#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>

#include <cstring>
#include <memory>

#include "board/hosted/board.h"

namespace {

// The clock is the page's; everything else is app::Hal's default: no
// touch, motion, light, sound or card.
struct MirrorHal : app::Hal {
  uint32_t realMs() override { return uint32_t(emscripten_get_now()); }
  const char* fwVersion() override { return "mirror"; }
  const char* gitSha() override { return "mirror"; }
};

MirrorHal hal;
// What the board says on USB in answer to the page's last call, and no
// more: the page reads a snapshot's dbg.state from it, and the tests
// everything; the rest is dropped at the next call.
hosted::Said said;
std::unique_ptr<hosted::Board> board;
const hosted::Board::Picture none;
const hosted::Board::Picture& picture() { return board ? board->picture() : none; }

}  // namespace

extern "C" {

// Power on a new board, as a reset does, on a frozen clock: it starts at 0
// and moves only by dbg.clock, so the page settles it in its first state
// as a scenario's shot is drawn, and then runs it.
EMSCRIPTEN_KEEPALIVE void mirror_power() {
  board.reset();
  said.clear();
  board = std::make_unique<hosted::Board>(hal, said, /*frozenClock=*/true);
}

// Text a host sends on USB, each line with its newline (hosted::Board::usb):
// how many lines the board handled.
EMSCRIPTEN_KEEPALIVE int mirror_send(const char* text) {
  said.clear();
  return board ? board->usb(text, std::strlen(text)) : 0;
}

// One pass of the board's loop. 1 when it drew a frame: mirror_frame is
// its RGBA pixels, mirror_width by mirror_height.
EMSCRIPTEN_KEEPALIVE int mirror_tick() {
  said.clear();
  return board && board->tickRgba();
}
EMSCRIPTEN_KEEPALIVE const uint8_t* mirror_frame() { return picture().rgba; }
EMSCRIPTEN_KEEPALIVE int mirror_width() { return picture().width; }
EMSCRIPTEN_KEEPALIVE int mirror_height() { return picture().height; }

// What the board said during the last call, or null for nothing.
EMSCRIPTEN_KEEPALIVE const char* mirror_said() { return said.take(); }

}  // extern "C"
#endif
