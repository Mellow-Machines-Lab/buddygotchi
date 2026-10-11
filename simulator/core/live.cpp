#include "live.h"

#include <atomic>
#include <chrono>
#include <csignal>
#include <poll.h>
#include <thread>
#include <unistd.h>

#include "board.h"
#include "file_card.h"
#include "speaker.h"

namespace sim {

namespace {

using Clock = std::chrono::steady_clock;

volatile std::sig_atomic_t stopped = 0;

// The board's sound task (board/audio.cpp) as a thread: each chunk takes
// as long as a DAC takes to play it, and goes nowhere.
class LiveSpeaker : public ChunkSpeaker {
 public:
  explicit LiveSpeaker(SimHal& hal) : ChunkSpeaker(hal) {
    thread_ = std::thread([this] {
      // The loop's thread takes the signals that stop the board.
      sigset_t stop;
      sigemptyset(&stop);
      sigaddset(&stop, SIGTERM);
      sigaddset(&stop, SIGINT);
      pthread_sigmask(SIG_BLOCK, &stop, nullptr);
      due_ = Clock::now();
      while (!stop_) step();
    });
  }
  ~LiveSpeaker() override {
    stop_ = true;
    thread_.join();
  }

 private:
  bool write(const uint8_t*) override {
    due_ += std::chrono::microseconds(app::Sound::kChunk * 1000000ull / voice::kOutRate);
    const auto now = Clock::now();
    if (due_ < now - std::chrono::milliseconds(200)) due_ = now;  // the Mac slept: don't catch up
    std::this_thread::sleep_until(due_);
    return true;
  }
  int64_t nowUs() override {
    return std::chrono::duration_cast<std::chrono::microseconds>(Clock::now().time_since_epoch()).count();
  }

  Clock::time_point due_;
  std::atomic<bool> stop_{false};
  std::thread thread_;
};

uint32_t us(Clock::duration d) { return uint32_t(std::chrono::duration_cast<std::chrono::microseconds>(d).count()); }

}  // namespace

int live(Port& port) {
  std::signal(SIGTERM, [](int) { stopped = 1; });
  std::signal(SIGINT, [](int) { stopped = 1; });

  // Each power-on differs, as a board's does.
  Board board(port, /*frozenClock=*/false, (us(Clock::now().time_since_epoch()) ^ uint32_t(::getpid()) << 16) | 1);
  FileCard card;
  board.setCard(&card);  // the voice pack, as on the board's card
  LiveSpeaker speaker(board.hal());
  board.hal().speaker = &speaker;
  while (!stopped) {
    pollfd usb{port.fd(), POLLIN, 0};
    ::poll(&usb, 1, 1);
    char buf[2048];
    for (size_t n; (n = port.read(buf, sizeof(buf))) > 0;) board.usb(buf, n);
    const auto from = Clock::now();
    const bool drew = board.tick();
    port.tick(board.hal().realMs());
    if (!drew) continue;
    // A frame is on this board's "panel" as soon as it's drawn: dbg.ping's
    // fps and draw_us, and dbg.latency.
    board.device().shown(board.hal().realMs());
    board.device().noteFrame(us(Clock::now() - from), 0);
  }
  board.hal().speaker = nullptr;
  return 0;
}

}  // namespace sim
