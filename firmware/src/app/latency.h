// How long an input or a message from the Mac takes to reach the panel
// (`dbg.latency`; internal/VERIFICATION.md §8 has the budgets). An event is
// stamped in real ms when the device first knows of it; the next frame
// drawn carries it, and it counts once the board has sent that frame.
// Fixed-size and allocation-free, since it runs on every frame. Pure C++.
#pragma once
#include <cstdint>

namespace app {

class Latency {
 public:
  // What is timed: a press going down (BOOT or a touch), a tap's release,
  // a `state` that changes the picture and a `do` starting to play, each
  // to the first frame sent after it; and kFrame, from one frame sent to
  // the next.
  enum Kind : uint8_t { kPress, kTap, kState, kDo, kFrame, kKinds };
  // The latest samples of each kind that p95 and max cover: 64 bytes a
  // kind.
  static constexpr int kWindow = 32;
  // Frames handed to the board and not yet on the panel: one being sent
  // and one waiting behind it. A frame more drops the oldest's events.
  static constexpr int kInFlight = 2;
  static const char* name(Kind k);  // dbg.latency's keys

  // An event of kind k at real time `ms`. While one waits for its frame, a
  // later one of the same kind is shown by the same frame: the first
  // keeps its time, so a burst counts its longest wait.
  void mark(Kind k, uint32_t ms);
  // A frame was drawn: it shows every event marked since the last.
  void drawn();
  // The frames drawn since the last hand-over go to the board as one.
  void handed();
  // The oldest frame handed reached the panel at real time `ms`.
  void shown(uint32_t ms);
  // Forgets the samples (dbg.latency's `clear`), not the events waiting.
  void clear();

  struct Stats {
    uint32_t n = 0;              // samples since the last clear
    uint32_t p95 = 0, max = 0;   // of the latest kWindow, in ms
    uint32_t at = 0, shown = 0;  // the latest sample's event and frame, real ms
  };
  Stats stats(Kind k) const;

 private:
  struct Frame {
    uint8_t has = 0;  // a bit per kind
    uint32_t at[kFrame] = {};
    void merge(const Frame& o);
  };
  struct Window {
    uint16_t ms[kWindow] = {};
    uint32_t n = 0, at = 0, shown = 0;
  };
  void add(Kind k, uint32_t at, uint32_t shown);

  Frame pending_, drawing_;
  Frame flight_[kInFlight];
  int flights_ = 0;
  Window w_[kKinds];
  bool sent_ = false;  // a frame has been shown, at lastShown_
  uint32_t lastShown_ = 0;
};

}  // namespace app
