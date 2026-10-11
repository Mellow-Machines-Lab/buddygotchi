#include "live.h"

#include <atomic>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <mutex>
#include <poll.h>
#include <string>
#include <thread>
#include <unistd.h>

#include "board.h"
#include "file_card.h"
#include "speaker.h"

namespace sim {

namespace {

using Clock = std::chrono::steady_clock;

// A SIGTERM or SIGINT came: the loop ends, and a write waiting on the front end gives up.
volatile std::sig_atomic_t stopped = 0;

// The way to the front end, shared by the loop and the sound's thread: one
// whole message at a time.
class Panel {
 public:
  explicit Panel(int fd) : fd_(fd) {}
  int fd() const { return fd_; }
  bool gone() const { return gone_; }

  // A message of `head` then `body`. False once the front end is gone;
  // with none from the start it goes nowhere.
  bool send(const char* tag, const void* head, size_t headBytes, const void* body, size_t bodyBytes) {
    if (fd_ < 0) return true;
    std::lock_guard<std::mutex> l(m_);
    const uint32_t n = uint32_t(headBytes + bodyBytes);
    const uint8_t start[8] = {uint8_t(tag[0]), uint8_t(tag[1]), uint8_t(tag[2]),  uint8_t(tag[3]),
                              uint8_t(n),      uint8_t(n >> 8), uint8_t(n >> 16), uint8_t(n >> 24)};
    if (!all(start, sizeof(start)) || !all(head, headBytes) || !all(body, bodyBytes)) gone_ = true;
    return !gone_;
  }

 private:
  // Writes all of it, waiting while the front end is behind.
  bool all(const void* data, size_t n) {
    auto* p = static_cast<const uint8_t*>(data);
    while (n && !stopped) {
      ssize_t w = ::write(fd_, p, n);
      if (w < 0 && errno == EINTR) continue;
      if (w <= 0) return false;
      p += w, n -= size_t(w);
    }
    return n == 0;
  }

  int fd_;
  std::mutex m_;
  std::atomic<bool> gone_{false};
};

// The board's sound task (board/audio.cpp) as a thread: each chunk sent to
// the front end at the pace a DAC plays it.
class LiveSpeaker : public ChunkSpeaker {
 public:
  LiveSpeaker(Panel& panel, SimHal& hal) : ChunkSpeaker(hal), panel_(panel) {
    thread_ = std::thread([this] { run(); });
  }
  ~LiveSpeaker() override {
    stop_ = true;
    thread_.join();
  }

 private:
  void run() {
    // The loop's thread takes the signals that stop the board.
    sigset_t stop;
    sigemptyset(&stop);
    sigaddset(&stop, SIGTERM);
    sigaddset(&stop, SIGINT);
    pthread_sigmask(SIG_BLOCK, &stop, nullptr);
    due_ = Clock::now();
    while (!stop_ && !panel_.gone()) step();
  }

  // Silence isn't sent, but takes as long.
  bool write(const uint8_t* chunk) override {
    if (hal_.amp) panel_.send("AUD1", nullptr, 0, chunk, app::Sound::kChunk);
    due_ += std::chrono::microseconds(app::Sound::kChunk * 1000000ull / voice::kOutRate);
    const auto now = Clock::now();
    if (due_ < now - std::chrono::milliseconds(200)) due_ = now;  // the Mac slept: don't catch up
    std::this_thread::sleep_until(due_);
    return true;
  }
  int64_t nowUs() override {
    return std::chrono::duration_cast<std::chrono::microseconds>(Clock::now().time_since_epoch()).count();
  }

  Panel& panel_;
  Clock::time_point due_;
  std::atomic<bool> stop_{false};
  std::thread thread_;
};

uint32_t us(Clock::duration d) { return uint32_t(std::chrono::duration_cast<std::chrono::microseconds>(d).count()); }

}  // namespace

int live(Port& port, int panelFd) {
  // Without SA_RESTART, so a write waiting on the front end returns.
  struct sigaction stop = {};
  stop.sa_handler = [](int) { stopped = 1; };
  ::sigaction(SIGTERM, &stop, nullptr);
  ::sigaction(SIGINT, &stop, nullptr);
  std::signal(SIGPIPE, SIG_IGN);  // a front end that went away is a write that fails

  Clock::time_point start = Clock::now();
  Board board(port, (uint32_t(us(start.time_since_epoch())) ^ uint32_t(::getpid()) << 16) | 1);
  FileCard card;
  board.hal().insertCard(&card);  // the voice pack, as on the board's card
  Panel panel(panelFd);
  LiveSpeaker speaker(panel, board.hal());
  board.hal().speaker = &speaker;
  std::string inputs, sent;
  while (!stopped) {
    pollfd fds[2] = {{port.fd(), POLLIN, 0}, {panel.fd(), POLLIN, 0}};
    ::poll(fds, panel.fd() < 0 ? 1 : 2, 1);
    char buf[2048];
    for (size_t n; (n = port.read(buf, sizeof(buf))) > 0;) board.usb(buf, n);
    if (panel.fd() >= 0 && fds[1].revents & (POLLIN | POLLHUP)) {
      ssize_t n = ::read(panel.fd(), buf, sizeof(buf));
      if (n == 0) break;
      if (n > 0) inputs.append(buf, size_t(n));
      for (size_t end; (end = inputs.find('\n')) != std::string::npos; inputs.erase(0, end + 1))
        if (!board.input(inputs.c_str()) && !inputs.compare(0, 7, "card in")) board.hal().insertCard(&card);
    }
    const auto drawFrom = Clock::now();
    const bool drew = board.tick(panel.fd() >= 0);
    const auto drawn = Clock::now();
    port.tick(board.hal().realMs());
    if (std::string now = board.parts(); now != sent) {
      sent = now;
      if (!panel.send("STA1", nullptr, 0, sent.data(), sent.size())) break;
    }
    if (!drew) continue;
    const Board::Frame f = board.frame();
    const uint8_t size[4] = {uint8_t(f.width), uint8_t(f.width >> 8), uint8_t(f.height), uint8_t(f.height >> 8)};
    if (!panel.send("FRM1", size, sizeof(size), f.pixels, size_t(f.width) * f.height * 2)) break;
    board.shown(us(drawn - drawFrom), us(Clock::now() - drawn));  // the push is the front end taking the frame
  }
  board.hal().speaker = nullptr;
  return 0;
}

}  // namespace sim
