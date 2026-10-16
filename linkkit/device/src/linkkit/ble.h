// Bluetooth (linkkit/SPEC.md §8): a NimBLE Nordic UART peripheral named
// <prefix>-XXXX, with no security. Received bytes cross from the Bluetooth
// task to the main loop through a ring, and the main loop does everything
// else, so the kit stays single-threaded. A link the host has gone quiet
// on is dropped (Kit::shouldDrop), so a killed app's leftover link can't
// stop the device advertising.
//
// Built only on an ESP32 with NimBLE-Arduino in the project (ble.cpp is
// empty elsewhere), so the portable part of the kit never needs it.
#pragma once
#include <cstddef>
#include <cstdint>

#include "linkkit/kit.h"
#include "linkkit/line_reader.h"
#include "linkkit/packets.h"

namespace linkkit {

class Ble : public Out {
 public:
  Ble();

  // Releases Classic Bluetooth's memory and starts advertising as
  // "<namePrefix>-XXXX", XXXX the last 4 hex digits of the Bluetooth MAC;
  // id() is "<idPrefix>-xxxx", the same digits in lower case. Call after
  // any large allocation that needs a contiguous block.
  bool begin(const char* namePrefix, const char* idPrefix);
  // From the main loop: connection changes and one whole received line go
  // to the kit. Returns true if it handled a line.
  bool poll(Kit& kit);

  // Replies and device → host messages, sent as notifications.
  void write(const char* s, size_t n) override;

  const char* state() const;                  // "off", "idle", "adv" or "conn"
  const char* name() const { return name_; }  // <namePrefix>-XXXX
  const char* id() const { return id_; }      // <idPrefix>-xxxx

 private:
  static void sendPacket(void* ctx, const uint8_t* data, size_t n);

  char name_[24] = "";  // both from the MAC, in begin()
  char id_[24] = "";
  bool started_ = false;
  bool connected_ = false;  // as the main loop last saw it
  uint32_t advCheckedAt_ = 0;
  LineReader line_;
  PacketWriter out_;
};

}  // namespace linkkit
