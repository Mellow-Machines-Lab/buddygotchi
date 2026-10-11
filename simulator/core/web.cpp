// The simulated board in a browser (simulator/README.md): the same Board
// as the Mac's (board.h), built to WebAssembly, with the page as its front
// end. There are no threads and no loop of its own here: the page calls
// sim_tick as often as it likes, and asks for each chunk of sound as its
// audio needs it. Built by simulator/web/build.sh only.
#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "board.h"
#include "speaker.h"

namespace {

using sim::Board;

// What the board says on USB, kept until the page takes it.
struct Lines : linkkit::Out {
  std::string said;
  void write(const char* s, size_t n) override { said.append(s, n); }
};

// The card: a voice pack the page fetched.
struct MemoryCard : sim::Card, voice::Source {
  std::vector<uint8_t> bytes;
  bool open() override { return !bytes.empty() && voice::openPack(this); }
  bool read(uint32_t at, void* buf, uint32_t n) override {
    if (uint64_t(at) + n > bytes.size()) return false;
    std::memcpy(buf, bytes.data() + at, n);
    return true;
  }
};

// The page's audio asks for each chunk, so the output's time is the
// chunks' own: as many as were made, at the rate they play.
struct PullSpeaker : sim::ChunkSpeaker {
  using ChunkSpeaker::ChunkSpeaker;
  uint8_t chunk[app::Sound::kChunk];
  uint64_t made = 0;
  bool write(const uint8_t* c) override {
    std::memcpy(chunk, c, sizeof(chunk));
    ++made;
    return true;
  }
  int64_t nowUs() override { return int64_t(made * app::Sound::kChunk * 1000000ull / voice::kOutRate); }
};

Lines lines;
MemoryCard card;
std::unique_ptr<Board> board;
std::unique_ptr<PullSpeaker> speaker;
std::vector<uint8_t> rgba;
int width = 0, height = 0;
std::string taken, parts;  // what the page was last handed
uint32_t boots = 0;

}  // namespace

extern "C" {

// Before power-on: BOOP_SIM_FACE, BOOP_SIM_NATIVE, BOOP_SIM_ID (sim_hal.h).
EMSCRIPTEN_KEEPALIVE void sim_env(const char* name, const char* value) { ::setenv(name, value, 1); }

// Power: on makes a new board, as a reset does; off leaves nothing of it.
EMSCRIPTEN_KEEPALIVE void sim_power(int on) {
  // A card taken out stays out through a reset, as a real one does.
  const bool out = board && !std::strcmp(board->hal().card, "no card") && !card.bytes.empty();
  if (board) board->hal().speaker = nullptr;
  speaker.reset();
  board.reset();
  voice::closePack();
  lines.said.clear();
  if (!on) return;
  parts.clear();
  board = std::make_unique<Board>(lines, /*frozenClock=*/false, (uint32_t(emscripten_get_now() * 1000) ^ ++boots << 24) | 1);
  speaker = std::make_unique<PullSpeaker>(board->hal());
  board->hal().speaker = speaker.get();
  board->setCard(card.bytes.empty() ? nullptr : &card, out);
}

// Room for a voice pack of `bytes` bytes, for the page to fill and then
// put in (`card in`). It stays in the slot through every power-on, until
// `card out`.
EMSCRIPTEN_KEEPALIVE uint8_t* sim_card(int bytes) {
  card.bytes.resize(size_t(bytes));
  if (board) board->setCard(&card, /*out=*/true);
  return card.bytes.data();
}

// One pass of the board's loop. 1 when it drew a frame: sim_frame is its
// RGBA pixels, sim_width by sim_height.
EMSCRIPTEN_KEEPALIVE int sim_tick() {
  if (!board) return 0;
  const double from = emscripten_get_now();
  if (!board->tick()) return 0;
  const Board::Frame f = board->frame();
  const size_t n = size_t(f.width) * f.height;
  rgba.resize(n * 4);
  for (size_t i = 0; i < n; ++i) {
    const uint16_t p = f.pixels[i];
    const uint8_t r = p >> 11, g = (p >> 5) & 0x3f, b = p & 0x1f;
    rgba[4 * i] = uint8_t(r << 3 | r >> 2);
    rgba[4 * i + 1] = uint8_t(g << 2 | g >> 4);
    rgba[4 * i + 2] = uint8_t(b << 3 | b >> 2);
    rgba[4 * i + 3] = 255;
  }
  width = f.width, height = f.height;
  board->device().shown(board->hal().realMs());
  board->device().noteFrame(uint32_t((emscripten_get_now() - from) * 1000), 0);  // dbg.ping's fps and draw_us
  return 1;
}
EMSCRIPTEN_KEEPALIVE const uint8_t* sim_frame() { return rgba.data(); }
EMSCRIPTEN_KEEPALIVE int sim_width() { return width; }
EMSCRIPTEN_KEEPALIVE int sim_height() { return height; }

// USB: text a host sends, each line with its newline, and the lines the
// board has said since last asked, or null for none.
EMSCRIPTEN_KEEPALIVE void sim_usb(const char* text) {
  if (board) board->usb(text, std::strlen(text));
}
EMSCRIPTEN_KEEPALIVE const char* sim_usb_out() {
  if (lines.said.empty()) return nullptr;
  taken.swap(lines.said);
  lines.said.clear();
  return taken.c_str();
}

// The page's inputs (Board::input).
EMSCRIPTEN_KEEPALIVE void sim_input(const char* line) {
  if (board) board->input(line);
}
// The board's parts (Board::parts) when one has changed since last asked, else null.
EMSCRIPTEN_KEEPALIVE const char* sim_parts() {
  if (!board) return nullptr;
  std::string now = board->parts();
  if (now == parts) return nullptr;
  parts.swap(now);
  return parts.c_str();
}

// The next chunk of sound: app::Sound::kChunk 8-bit unsigned samples at
// voice::kOutRate. Null when the amp is off, which is silence.
EMSCRIPTEN_KEEPALIVE const uint8_t* sim_sound() {
  if (!speaker) return nullptr;
  speaker->step();
  return board->hal().amp ? speaker->chunk : nullptr;
}

}  // extern "C"
#endif
