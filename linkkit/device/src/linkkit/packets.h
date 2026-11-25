// Moving message lines through Bluetooth packets (linkkit/SPEC.md §8).
// Pure C++, so the host tests cover it.
//
// ByteRing carries received bytes from the Bluetooth task to the main loop,
// which feeds them to a LineReader: one writer, one reader, no locks.
// PacketWriter collects a reply until its newline, then hands it out in
// packets no bigger than the link's payload size, so a line never
// interleaves with another. PacketOutbox keeps the packets the link can't
// take yet, so the main loop never waits on it.
#pragma once
#include <atomic>
#include <cstddef>
#include <cstdint>

#include "linkkit/line_reader.h"

namespace linkkit {

template <size_t N>
class ByteRing {
  static_assert((N & (N - 1)) == 0, "N must be a power of two");

 public:
  // Writer side. Returns how many bytes fit; the rest are dropped and
  // counted. The torn line then fails to parse and is ignored, like any
  // other lost message.
  size_t put(const uint8_t* data, size_t n) {
    size_t head = head_.load(std::memory_order_relaxed);
    size_t tail = tail_.load(std::memory_order_acquire);
    size_t room = N - (head - tail);
    size_t k = n < room ? n : room;
    for (size_t i = 0; i < k; ++i) buf_[(head + i) & (N - 1)] = data[i];
    head_.store(head + k, std::memory_order_release);
    if (k < n) dropped_.fetch_add(uint32_t(n - k), std::memory_order_relaxed);
    return k;
  }

  // Reader side. Returns false when empty.
  bool take(uint8_t& c) {
    size_t tail = tail_.load(std::memory_order_relaxed);
    if (tail == head_.load(std::memory_order_acquire)) return false;
    c = buf_[tail & (N - 1)];
    tail_.store(tail + 1, std::memory_order_release);
    return true;
  }

  uint32_t dropped() const { return dropped_.load(std::memory_order_relaxed); }

  // Writer side, when the link that wrote the bytes drops: ends whatever
  // part of a line it left, so the next link's first line comes out whole
  // rather than joined onto it (the part alone fails to parse).
  void endLine() {
    static const uint8_t nl = '\n';
    put(&nl, 1);
  }

 private:
  uint8_t buf_[N] = {};
  std::atomic<size_t> head_{0};
  std::atomic<size_t> tail_{0};
  std::atomic<uint32_t> dropped_{0};
};

class PacketWriter {
 public:
  using Send = void (*)(void* ctx, const uint8_t* data, size_t n);

  PacketWriter(Send send, void* ctx) : send_(send), ctx_(ctx) {}

  // The most bytes one packet may carry (the ATT MTU minus 3).
  void setPayload(size_t n) { payload_ = n < 1 ? 1 : n; }

  // Appends to the current line; a newline sends it. Lines longer than
  // LineReader::kMax are dropped whole, as the receiver would drop them.
  void write(const char* s, size_t n) {
    for (size_t i = 0; i < n; ++i) {
      if (len_ < sizeof(buf_)) {
        buf_[len_] = s[i];
      } else {
        overflow_ = true;
      }
      ++len_;
      if (s[i] == '\n') flush();
    }
  }

  // Forgets a half-written line, e.g. on disconnect.
  void clear() { len_ = 0, overflow_ = false; }

 private:
  void flush() {
    if (!overflow_) {
      for (size_t at = 0; at < len_; at += payload_) {
        size_t k = len_ - at < payload_ ? len_ - at : payload_;
        send_(ctx_, reinterpret_cast<const uint8_t*>(buf_) + at, k);
      }
    }
    clear();
  }

  Send send_;
  void* ctx_;
  size_t payload_ = 20;  // the default ATT MTU of 23, until negotiated
  char buf_[LineReader::kMax + 1] = {};
  size_t len_ = 0;
  bool overflow_ = false;
};

// Packets waiting for a link that can't take them yet (Bluetooth's
// notifications, while its buffers are full), in order, on the main loop
// alone. Each is sent as soon as the link takes it, and the rest wait for
// the next drain(). A packet with no room left is dropped whole and
// counted; the line it was part of then fails to parse, like any other
// lost message.
template <size_t N>
class PacketOutbox {
 public:
  // Sends one packet; false when the link can't take it now.
  using TrySend = bool (*)(void* ctx, const uint8_t* data, size_t n);

  // Queues a packet behind any waiting, then sends what the link takes.
  void send(const uint8_t* data, size_t n, TrySend trySend, void* ctx) {
    if (n > 0xffff || used_ + 2 + n > N) {
      ++dropped_;
    } else {
      buf_[used_] = uint8_t(n >> 8), buf_[used_ + 1] = uint8_t(n);
      for (size_t i = 0; i < n; ++i) buf_[used_ + 2 + i] = data[i];
      used_ += 2 + n;
    }
    drain(trySend, ctx);
  }

  // Sends from the front for as long as the link takes them.
  void drain(TrySend trySend, void* ctx) {
    size_t at = 0;
    while (at < used_) {
      const size_t n = size_t(buf_[at]) << 8 | buf_[at + 1];
      if (!trySend(ctx, buf_ + at + 2, n)) break;
      at += 2 + n;
    }
    for (size_t i = at; i < used_; ++i) buf_[i - at] = buf_[i];
    used_ -= at;
  }

  // Forgets every packet waiting, e.g. on disconnect.
  void clear() { used_ = 0; }
  size_t waiting() const { return used_; }
  uint32_t dropped() const { return dropped_; }

 private:
  uint8_t buf_[N] = {};
  size_t used_ = 0;
  uint32_t dropped_ = 0;
};

}  // namespace linkkit
