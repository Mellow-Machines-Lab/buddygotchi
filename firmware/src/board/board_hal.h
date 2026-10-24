// The board's side of app::Hal (and LinkKit's Platform): buttons, touch,
// LED, backlight, sound, the amp, heap figures and Bluetooth's state.
// What every board shares is in
// board/board_hal.cpp, the sound and the card's methods in board/audio.cpp
// and board/card.cpp; each board's start-up, LED and default touch map
// are in its own hal.cpp (cyd24/, amoled206/).
#pragma once
#include "app/device.h"
#include "board/config.h"

namespace linkkit {
class Ble;
}

namespace board {

class BoardHal : public app::Hal {
 public:
  void begin();  // the board's own start-up, then the saved touch calibration
  // Bluetooth, once it has started (or failed to): its state, name and the
  // device ID it took from the MAC.
  void setBle(const linkkit::Ble* ble) { ble_ = ble; }

  uint32_t realMs() override;
  bool bootDown() override;
  bool touch(int& x, int& y) override;
  // The board's motion sensor, if it has one (the AMOLED's QMI8658;
  // amoled206/imu.cpp); the CYD has none.
  bool motion(int& ax, int& ay, int& az) override;
  void touchRaw(int& x, int& y, int& z, bool& irq) override;
  void setTouchCal(const app::TouchCal& c) override;
  app::TouchCal touchCal() override { return cal_; }
  void setLed(uint32_t rgb) override;
  void setBacklight(uint8_t level) override;
  render::Size nativeSize() override;
  void* allocateSurface(size_t bytes) override;
  uint32_t heapFree() override;
  uint32_t heapMin() override;
  bool ampOn() override;
  void say(const voice::Say& l) override;
  void hush() override;
  void effect(const voice::Effect& e) override;
  void stopEffects() override;
  app::AudioOut audioOut() override;
  const char* deviceId() override;
  const char* bleState() override;
  const char* bleName() override;
  const char* cardState() override;
  bool copyBegin(bool keep, uint32_t& have, const char*& why) override;
  bool copyAppend(const uint8_t* d, size_t n, uint32_t& have) override;
  bool copyEnd(uint32_t size, uint32_t crc, const char*& why) override;
  const char* fwVersion() override;
  uint32_t bootId() override;
  const char* gitSha() override;
  const char* resetReason() override;
  const char* boardName() override { return kBoardName; }

 private:
  // The board's own start-up (its hal.cpp): its pins, buses, touch and
  // card, and the default touch map.
  void beginBoard();

  app::TouchCal cal_;         // from NVS; invalid until `boopctl calibrate` has run on this rotation
  app::TouchCal defaultCal_;  // used until then: the raw range, turned by kRotation
  const linkkit::Ble* ble_ = nullptr;
};

}  // namespace board
