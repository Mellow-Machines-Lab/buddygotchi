// boop-sim: Boop on LinkKit, on the Mac (simulator/README.md). It behaves
// like the board on USB: protocol and dbg.* lines on stdin, replies on
// stdout.
//
// On its own, the clock starts frozen at 0 and nothing moves but by a
// line: `boopctl sim` drives it with the same scenario runner as the
// board, so a device screenshot and a simulator screenshot come from the
// same messages.
//
// With --live it runs in real time, as a board does, and its USB is a
// serial port of its own (port.h): it prints `port /dev/ttysNNN`, and
// BOOP_SIM_PORT names a path that will lead there too. The window
// (live.h) is on the descriptor BOOP_SIM_PANEL names; without one it's a
// board with nobody looking, for tests and tools.
#ifndef PIO_UNIT_TESTING
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <vector>

#include "app/device.h"
#include "linkkit/kit.h"
#include "linkkit/line_reader.h"
#include "file_card.h"
#include "live.h"
#include "sim_hal.h"

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
    const char* panel = std::getenv("BOOP_SIM_PANEL");
    return sim::live(port, panel ? std::atoi(panel) : -1);
  }

  sim::SimHal hal;
  sim::FileCard card;
  hal.insertCard(&card);  // the voice pack, as on the board's card
  std::vector<uint8_t> pixels(size_t(render::kWidth) * render::kHeight, 0);
  app::Device device(hal, pixels.data());
  linkkit::Kit kit(hal, device, /*frozenClock=*/true);
  StdOut out;
  kit.setOut(linkkit::Link::kUsb, &out);
  kit.tick();

  // Lines go through the board's own LineReader, so a line over its limit
  // (linkkit/SPEC.md §2) is dropped here exactly as on USB.
  linkkit::LineReader reader;
  for (int c; (c = std::getchar()) != EOF;) {
    if (!reader.feed(char(c))) continue;
    kit.handleLine(reader.line(), reader.length(), linkkit::Link::kUsb);
    kit.tick();
    // A native face's frames turn as on the board, so its
    // screenshots come from the same two surfaces. A frame is on the
    // simulator's "panel" as soon as it's taken (dbg.latency).
    if (device.takeFrame()) {
      if (auto* frames = device.frames()) frames->present(device.canvas());
      device.shown(hal.realMs());
    }
    std::fflush(stdout);
  }
  return 0;
}
#endif
