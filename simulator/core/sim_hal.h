// The simulated board's side of app::Hal: the host's clock, and whatever
// stands in for its finger, button, speaker, light, backlight and card.
#pragma once
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>

#include "app/device.h"

namespace sim {

// The speaker (speaker.h); none for a board that plays nothing.
struct Speaker {
  virtual ~Speaker() = default;
  virtual void say(const voice::Say& l) = 0;
  virtual void hush() = 0;
  virtual void effect(const voice::Effect& e) = 0;
  virtual void stopEffects() = 0;
  virtual app::AudioOut stats() = 0;
};

// The microSD card that holds the voice file: a folder on the Mac
// (file_card.h), or bytes in the browser (web.cpp).
struct Card {
  virtual ~Card() = default;
  // Opens its voice file; false when it holds none.
  virtual bool open() = 0;
  // Copying a new voice file onto it over USB (dbg.card), as app::Hal has them.
  virtual bool copyBegin(bool keep, uint32_t& have, const char*& why) {
    (void)keep, have = 0, why = "no card";
    return false;
  }
  virtual bool copyAppend(const uint8_t* d, size_t n, uint32_t& have) {
    (void)d, (void)n, have = 0;
    return false;
  }
  virtual bool copyEnd(uint32_t size, uint32_t crc, const char*& why) {
    (void)size, (void)crc, why = "no card";
    return false;
  }
};

struct SimHal : app::Hal {
  explicit SimHal(uint32_t bootId = 0) : boot(bootId) {}

  uint32_t realMs() override {
    using namespace std::chrono;
    return uint32_t(duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count());
  }
  const char* fwVersion() override { return "sim"; }
  const char* gitSha() override { return "sim"; }

  // BOOP_SIM_ID is the device's ID, for more than one at once.
  std::string id = std::getenv("BOOP_SIM_ID") ? std::getenv("BOOP_SIM_ID") : app::kDefaultDeviceId;
  const char* deviceId() override { return id.c_str(); }
  // Each power-on of a live board differs, as on a real one; a frozen
  // board's is 0, so every run is the same.
  uint32_t boot = 0;
  uint32_t bootId() override { return boot; }

  // The panel a native face draws: the AMOLED's, or BOOP_SIM_NATIVE=WxH,
  // its corners rounded in proportion.
  render::Size nativeSize() override {
    render::Size size = app::Hal::nativeSize();
    const int height = size.height;
    if (const char* s = std::getenv("BOOP_SIM_NATIVE")) std::sscanf(s, "%dx%d", &size.width, &size.height);
    size.corner = size.corner * size.height / height;
    return size;
  }

  // The panel's finger and the BOOT button, as whoever holds them last
  // said. A press is seen at least once, however soon it's let go: a click
  // is over sooner than the board looks.
  void setTouch(bool on, int tx = 0, int ty = 0) {
    down = on;
    if (on) x = tx, y = ty, touched = true;
  }
  void setBoot(bool on) {
    pressed = on;
    if (on) booted = true;
  }
  bool bootDown() override {
    const bool was = pressed || booted;
    booted = false;
    return was;
  }
  // The motion sensor, once something has tilted it: until then the board
  // has none, as the CYD hasn't.
  void setMotion(int x, int y, int z) { tilt[0] = x, tilt[1] = y, tilt[2] = z, tilted = true; }
  bool motion(int& ax, int& ay, int& az) override {
    if (!tilted) return false;
    ax = tilt[0], ay = tilt[1], az = tilt[2];
    return true;
  }
  bool touch(int& tx, int& ty) override {
    const bool was = down || touched;
    touched = false;
    tx = x, ty = y;
    return was;
  }

  int tilt[3] = {0, 0, 1000};
  bool tilted = false;

  // The light, the backlight and the amp, to be shown.
  uint32_t led = 0;
  uint8_t backlight = 255;
  std::atomic<bool> amp{false};
  void setLed(uint32_t rgb) override { led = rgb; }
  void setBacklight(uint8_t level) override { backlight = level; }
  bool ampOn() override { return amp; }

  Speaker* speaker = nullptr;
  void say(const voice::Say& l) override {
    if (speaker) speaker->say(l);
  }
  void hush() override {
    if (speaker) speaker->hush();
  }
  void effect(const voice::Effect& e) override {
    if (speaker) speaker->effect(e);
  }
  void stopEffects() override {
    if (speaker) speaker->stopEffects();
  }
  app::AudioOut audioOut() override { return speaker ? speaker->stats() : app::AudioOut{}; }

  // The card in the slot, if one is; `card` is dbg.ping's word for it.
  // The board keeps the card that goes back in (Board::setCard).
  Card* slot = nullptr;
  const char* card = "no card";
  const char* cardState() override { return card; }
  void insertCard(Card* c) {
    slot = c;
    card = c && c->open() ? "ok" : c ? "no pack" : "no card";
  }
  void ejectCard() {
    voice::closeFile();
    slot = nullptr;
    card = "no card";
  }
  bool copyBegin(bool keep, uint32_t& have, const char*& why) override {
    if (!slot) return have = 0, why = "no card", false;
    return slot->copyBegin(keep, have, why);
  }
  bool copyAppend(const uint8_t* d, size_t n, uint32_t& have) override {
    return slot ? slot->copyAppend(d, n, have) : (have = 0, false);
  }
  bool copyEnd(uint32_t size, uint32_t crc, const char*& why) override {
    if (!slot) return why = "no card", false;
    card = "no pack";
    const bool ok = slot->copyEnd(size, crc, why);
    if (ok) card = "ok";
    return ok;
  }

 private:
  bool down = false, pressed = false;
  bool touched = false, booted = false;  // pressed since last looked at
  int x = 0, y = 0;
};

}  // namespace sim
