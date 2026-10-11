// boop-sim: Boop on LinkKit, on the Mac (simulator/README.md). It behaves
// like the board on USB: protocol and dbg.* lines in, replies out.
//
// On its own, USB is stdin and stdout, and the clock starts frozen at 0:
// nothing moves but by a line. `boopctl sim` drives it with the same
// scenario runner as the board, so a device screenshot and a simulator
// screenshot come from the same messages.
//
// With --live it runs in real time, as a board does, and its USB is a
// serial port of its own (port.h): it prints `port /dev/ttysNNN`, and
// BOOP_SIM_PORT names a path that will lead there too.
#ifndef PIO_UNIT_TESTING
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "board.h"
#include "file_card.h"
#include "live.h"

namespace {

struct StdOut : linkkit::Out {
  void write(const char* s, size_t n) override { std::fwrite(s, 1, n, stdout); }
};

}  // namespace

int main(int argc, char** argv) {
  if (argc > 1 && !std::strcmp(argv[1], "--live")) {
    sim::Port port;
    const char* link = std::getenv("BOOP_SIM_PORT");
    if (!port.open(link ? link : "")) return std::fprintf(stderr, "boop-sim: %s\n", port.error().c_str()), 1;
    std::printf("port %s\n", port.path().c_str());
    std::fflush(stdout);
    return sim::live(port);
  }

  StdOut out;
  sim::Board board(out, /*frozenClock=*/true);
  sim::FileCard card;
  board.setCard(&card);  // the voice pack, as on the board's card
  for (int c; (c = std::getchar()) != EOF;) {
    const char byte = char(c);
    if (!board.usb(&byte, 1)) continue;
    // A frame is on the simulator's "panel" as soon as it's taken (dbg.latency).
    if (board.tick()) board.device().shown(board.hal().realMs());
    std::fflush(stdout);
  }
  return 0;
}
#endif
