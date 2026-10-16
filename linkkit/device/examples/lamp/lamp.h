// A lamp on LinkKit: about the smallest app worth the name, and the one
// linkkit/device/README.md walks through. Its `state` is {"level":0-255};
// it plays one `do`, `blink`, which blinks the light `times` times
// (1-10, 200 ms each) and ends `done`, or `cut` when the lamp's own
// button is pressed. The unit tests run it (test/test_kit).
#pragma once
#include <cstdint>

#include "linkkit/kit.h"

namespace lamp {

class Lamp : public linkkit::App {
 public:
  static constexpr uint32_t kBlinkMs = 200;

  const char* name() const override { return "lamp"; }
  int does(const char* const*& names) const override {
    static const char* const kDoes[] = {"blink"};
    names = kDoes;
    return 1;
  }

  void onState(JsonObjectConst state, uint32_t) override { level_ = state["level"] | 0; }

  // Busy while it blinks: a `next` blink waits in the queue, a `now` one cuts it.
  void onDo(const linkkit::Do& c, uint32_t t) override {
    int times = c.args["times"] | 1;
    times = times < 1 ? 1 : times > 10 ? 10 : times;
    blinking_ = c.key;
    until_ = t + kBlinkMs * uint32_t(times);
    at_ = t;
  }
  void advance(uint32_t t) override {
    if (blinking_ && int32_t(t - until_) >= 0) kit().ended(blinking_), blinking_ = 0;
  }
  // So a blink waiting starts the millisecond this one ends.
  bool nextDue(uint32_t from, uint32_t to, uint32_t& at) override {
    if (!blinking_ || int32_t(until_ - from) <= 0 || int32_t(until_ - to) > 0) return false;
    at = until_;
    return true;
  }
  void tick(uint32_t t) override {
    light_ = blinking_ && (t - at_) / (kBlinkMs / 2) % 2 == 0 ? 255 : level_;
  }

  // The lamp's own button: the device does this itself, so it doesn't
  // go through the queue; it cuts the blink and tells the host.
  void press() {
    if (blinking_) kit().cut("button"), blinking_ = 0;
    kit().emit("press", "stopped", nullptr, false);
  }
  uint8_t light() const { return light_; }

 private:
  uint8_t level_ = 0, light_ = 0;
  uint32_t blinking_ = 0;  // the `do` blinking, 0 for none
  uint32_t until_ = 0, at_ = 0;
};

}  // namespace lamp
