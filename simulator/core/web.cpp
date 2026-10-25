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

// The card: a voice file the page fetched.
struct MemoryCard : sim::Card, voice::Source {
  std::vector<uint8_t> bytes;
  bool open() override { return !bytes.empty() && voice::openFile(this); }
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

hosted::Said said;  // what the board says on USB, kept until the page takes it
MemoryCard card;
std::unique_ptr<Board> board;
std::unique_ptr<PullSpeaker> speaker;
std::string parts;  // what the page was last handed
uint32_t boots = 0;
const hosted::Board::Picture none;
const hosted::Board::Picture& picture() { return board ? board->hosted().picture() : none; }

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
  voice::closeFile();
  said.clear();
  if (!on) return;
  parts.clear();
  board =
      std::make_unique<Board>(said, /*frozenClock=*/false, (uint32_t(emscripten_get_now() * 1000) ^ ++boots << 24) | 1);
  speaker = std::make_unique<PullSpeaker>(board->hal());
  board->hal().speaker = speaker.get();
  board->setCard(card.bytes.empty() ? nullptr : &card, out);
}

// Room for a voice file of `bytes` bytes, for the page to fill and then
// put in (`card in`). It stays in the slot through every power-on, until
// `card out`.
EMSCRIPTEN_KEEPALIVE uint8_t* sim_card(int bytes) {
  card.bytes.resize(size_t(bytes));
  if (board) board->setCard(&card, /*out=*/true);
  return card.bytes.data();
}

// One pass of the board's loop. 1 when it drew a frame: sim_frame is its
// RGBA pixels, sim_width by sim_height.
EMSCRIPTEN_KEEPALIVE int sim_tick() { return board && board->hosted().tickRgba(); }
EMSCRIPTEN_KEEPALIVE const uint8_t* sim_frame() { return picture().rgba; }
EMSCRIPTEN_KEEPALIVE int sim_width() { return picture().width; }
EMSCRIPTEN_KEEPALIVE int sim_height() { return picture().height; }

// USB: text a host sends, each line with its newline, and the lines the
// board has said since last asked, or null for none.
EMSCRIPTEN_KEEPALIVE void sim_usb(const char* text) {
  if (board) board->hosted().usb(text, std::strlen(text));
}
EMSCRIPTEN_KEEPALIVE const char* sim_usb_out() { return said.take(); }

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
