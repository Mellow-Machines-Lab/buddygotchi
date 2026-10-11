#include "port.h"

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

namespace sim {

Port::~Port() {
  if (!link_.empty()) ::unlink(link_.c_str());
  if (slave_ >= 0) ::close(slave_);
  if (master_ >= 0) ::close(master_);
}

bool Port::open(const std::string& link) {
  auto fail = [&](const char* what) {
    error_ = std::string(what) + ": " + std::strerror(errno);
    return false;
  };
  master_ = ::posix_openpt(O_RDWR | O_NOCTTY);
  if (master_ < 0 || ::grantpt(master_) || ::unlockpt(master_)) return fail("no pseudo-terminal");
  const char* name = ::ptsname(master_);
  if (!name) return fail("no name for the port");
  path_ = name;
  slave_ = ::open(name, O_RDWR | O_NOCTTY | O_NONBLOCK);
  if (slave_ < 0) return fail(name);
  // Raw from the start, as a serial port is: a terminal's echo would send
  // the board its own lines back.
  termios t;
  if (::tcgetattr(slave_, &t) == 0) {
    ::cfmakeraw(&t);
    t.c_cc[VMIN] = 0, t.c_cc[VTIME] = 0;
    ::tcsetattr(slave_, TCSANOW, &t);
  }
  ::fcntl(master_, F_SETFL, ::fcntl(master_, F_GETFL) | O_NONBLOCK);
  if (!link.empty()) {
    ::unlink(link.c_str());
    if (::symlink(name, link.c_str())) return fail(link.c_str());
    link_ = link;
  }
  return true;
}

size_t Port::read(char* buf, size_t n) {
  ssize_t got = ::read(master_, buf, n);
  if (got <= 0) return 0;
  listening_ = true;  // whoever sends, hears
  return size_t(got);
}

int Port::waiting() const {
  int n = 0;
  return ::ioctl(slave_, FIONREAD, &n) == 0 ? n : 0;
}

void Port::forget() {
  ::tcflush(slave_, TCIFLUSH);
  lastWaiting_ = 0;
}

void Port::write(const char* s, size_t n) {
  while (n) {
    ssize_t w = ::write(master_, s, n);
    if (w > 0) {
      s += w, n -= size_t(w);
      continue;
    }
    if (w < 0 && errno == EINTR) continue;
    if (w < 0 && errno != EAGAIN) return;
    // The port is full. A reader gets the time to take some; with none,
    // the newest words replace the oldest.
    if (listening_) {
      pollfd p{master_, POLLOUT, 0};
      if (::poll(&p, 1, kDeafMs) > 0) continue;
      listening_ = false;
    }
    forget();
    if (::write(master_, s, n) < 0) return;  // as much as fits; the rest is lost
    return;
  }
}

void Port::tick(uint32_t ms) {
  const int now = waiting();
  if (now < lastWaiting_) listening_ = true;  // someone took some
  if (now != lastWaiting_) changedAt_ = ms;
  lastWaiting_ = now;
  if (now > 0 && ms - changedAt_ > kStaleMs) {
    forget();
    listening_ = false;
  }
}

}  // namespace sim
