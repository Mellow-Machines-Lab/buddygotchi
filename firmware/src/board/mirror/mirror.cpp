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
#include <string>
#include <vector>

#include "board/hosted/board.h"

namespace {

// The clock is the page's; everything else is app::Hal's default: no
// touch, motion, light, sound or card.
struct MirrorHal : app::Hal {
  uint32_t realMs() override { return uint32_t(emscripten_get_now()); }
  const char* fwVersion() override { return "mirror"; }
  const char* gitSha() override { return "mirror"; }
  // Each power-on of a live mirror makes its own choices, as a board's does.
  uint32_t boot = 0;
  uint32_t bootId() override { return boot; }
};

// What the board says on USB in answer to the page's last call, and no
// more: the page reads a snapshot's dbg.state from it, and the tests
// everything; the rest is dropped at the next call.
struct Said : linkkit::Out {
  std::string text, taken;
  void write(const char* s, size_t n) override { text.append(s, n); }
};

MirrorHal hal;
Said said;
std::unique_ptr<hosted::Board> board;
std::vector<uint8_t> rgba;
int width = 0, height = 0;
uint32_t boots = 0;

}  // namespace

extern "C" {

// Power on a new board, as a reset does: its clock running, or with
// `frozen` at 0, moving only by dbg.clock, so every run draws the same.
EMSCRIPTEN_KEEPALIVE void mirror_power(int frozen) {
  board.reset();
  said.text.clear();
  hal.boot = frozen ? 0 : (uint32_t(emscripten_get_now() * 1000) ^ ++boots << 24) | 1;
  board = std::make_unique<hosted::Board>(hal, said, frozen != 0);
}

// Text a host sends on USB, each line with its newline (hosted::Board::usb):
// how many lines the board handled.
EMSCRIPTEN_KEEPALIVE int mirror_send(const char* text) {
  said.text.clear();
  return board ? board->usb(text, std::strlen(text)) : 0;
}

// One pass of the board's loop. 1 when it drew a frame: mirror_frame is
// its RGBA pixels, mirror_width by mirror_height.
EMSCRIPTEN_KEEPALIVE int mirror_tick() {
  said.text.clear();
  if (!board || !board->tick()) return 0;
  const hosted::Board::Frame f = board->frame();
  hosted::Board::rgba(f, rgba);
  width = f.width, height = f.height;
  board->device().shown(hal.realMs());
  return 1;
}
EMSCRIPTEN_KEEPALIVE const uint8_t* mirror_frame() { return rgba.data(); }
EMSCRIPTEN_KEEPALIVE int mirror_width() { return width; }
EMSCRIPTEN_KEEPALIVE int mirror_height() { return height; }

// What the board said during the last call, or null for nothing.
EMSCRIPTEN_KEEPALIVE const char* mirror_said() {
  if (said.text.empty()) return nullptr;
  said.taken.swap(said.text);
  said.text.clear();
  return said.taken.c_str();
}

}  // extern "C"
#endif
