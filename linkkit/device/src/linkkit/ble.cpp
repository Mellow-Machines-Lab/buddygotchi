// The board-only part of the kit: compiled where NimBLE-Arduino is, on an
// ESP32, and empty everywhere else (the simulator and the unit tests).
#if defined(ESP_PLATFORM) && __has_include(<NimBLEDevice.h>)
#include "linkkit/ble.h"

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <esp_bt.h>
#include <esp_mac.h>

#include <atomic>
#include <cstdio>

namespace linkkit {

namespace {

// The Nordic UART Service: RX is written by the host, TX notifies it.
constexpr const char* kService = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
constexpr const char* kRx = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
constexpr const char* kTx = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

// Written by the Bluetooth task, read by the main loop.
ByteRing<2048> rxRing;
std::atomic<bool> linkUp{false};
std::atomic<uint32_t> connects{0};     // bumps on every connect and disconnect,
std::atomic<uint16_t> mtu{23};         // so the loop never misses a quick pair
std::atomic<uint16_t> connHandle{0};
NimBLECharacteristic* tx = nullptr;

class ServerEvents : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo& info) override {
    connHandle = info.getConnHandle();
    mtu = 23;
    linkUp = true;
    ++connects;
  }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override {
    // A line the host was cut off in the middle of (a long `do` takes two
    // writes) mustn't join onto the next host's first line. This task is
    // the ring's only writer, as for onWrite.
    rxRing.endLine();
    linkUp = false;
    ++connects;
    // advertiseOnDisconnect (set in begin) starts advertising again.
  }
  void onMTUChange(uint16_t m, NimBLEConnInfo&) override { mtu = m; }
};

class RxEvents : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo&) override {
    NimBLEAttValue v = c->getValue();
    rxRing.put(v.data(), v.length());
  }
};

ServerEvents serverEvents;
RxEvents rxEvents;
uint32_t seenConnects = 0;

}  // namespace

Ble::Ble() : out_(sendPacket, this) {}

bool Ble::begin(const char* namePrefix, const char* idPrefix) {
  uint8_t mac[6] = {};
  esp_read_mac(mac, ESP_MAC_BT);
  // A prefix too long for the buffers is cut.
  std::snprintf(name_, sizeof(name_), "%.18s-%02X%02X", namePrefix, mac[4], mac[5]);
  std::snprintf(id_, sizeof(id_), "%.18s-%02x%02x", idPrefix, mac[4], mac[5]);

  // The kit only uses BLE: give Classic Bluetooth's memory back to the heap.
  esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT);
  if (!NimBLEDevice::init(name_)) return false;
  NimBLEDevice::setMTU(247);

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(&serverEvents, false);
  // Off by default since NimBLE-Arduino 2.0: without it the device goes
  // dark after the first disconnect until it's reset.
  server->advertiseOnDisconnect(true);
  NimBLEService* svc = server->createService(kService);
  tx = svc->createCharacteristic(kTx, NIMBLE_PROPERTY::NOTIFY);
  NimBLECharacteristic* rx = svc->createCharacteristic(kRx, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  rx->setCallbacks(&rxEvents);

  // Starting to advertise starts the server, and with it the service.
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->setName(name_);
  adv->addServiceUUID(kService);
  adv->enableScanResponse(true);
  started_ = adv->start();
  return started_;
}

bool Ble::poll(Kit& kit) {
  if (!started_) return false;
  uint32_t c = connects.load();
  if (c != seenConnects) {
    seenConnects = c;
    bool up = linkUp.load();
    if (connected_) {
      kit.disconnected();
      connected_ = false;
    }
    line_ = LineReader{};
    out_.clear();
    if (up) {
      connected_ = true;
      kit.connected();  // the host's first line gets the hello
    }
  }
  if (connected_) {
    uint16_t m = mtu.load();
    out_.setPayload(m > 3 ? m - 3 : 20);
    // A host that's gone quiet: let go, so advertising starts again.
    if (kit.shouldDrop()) NimBLEDevice::getServer()->disconnect(connHandle.load());
  } else if (!linkUp.load() && millis() - advCheckedAt_ >= 1000) {
    // Not connected and not advertising would leave the device unfindable
    // until it's reset, so check once a second and start it again.
    advCheckedAt_ = millis();
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    if (!adv->isAdvertising()) adv->start();
  }
  uint8_t b;
  while (rxRing.take(b)) {
    if (line_.feed(char(b))) {
      kit.handleLine(line_.line(), line_.length(), Link::kBle);
      return true;
    }
  }
  return false;
}

void Ble::write(const char* s, size_t n) {
  if (connected_ && linkUp.load()) out_.write(s, n);
}

void Ble::sendPacket(void*, const uint8_t* data, size_t n) {
  // Notifications queue in NimBLE's buffers; if they're full, give the
  // controller a moment and try again, then drop the packet.
  for (int i = 0; i < 20; ++i) {
    if (tx->notify(data, n)) return;
    if (!linkUp.load()) return;
    delay(2);
  }
}

const char* Ble::state() const {
  if (!started_) return "off";
  if (linkUp.load()) return "conn";
  return NimBLEDevice::getAdvertising()->isAdvertising() ? "adv" : "idle";
}

}  // namespace linkkit

#endif
