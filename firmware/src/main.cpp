// Board entry point: allocate the canvas first, bring up the screen and
// Bluetooth, then run Boop on LinkKit with USB serial and BLE as its links.
#include <Arduino.h>
#include <esp_heap_caps.h>

#include "app/device.h"
#include "board/audio.h"
#include "board/board_hal.h"
#include "board/display.h"
#include "linkkit/ble.h"
#include "linkkit/kit.h"
#include "linkkit/line_reader.h"
#ifdef BOOP_GEL_PROFILE
#include "render/profile.h"
#endif

namespace {

struct SerialOut : linkkit::Out {
  void write(const char* s, size_t n) override { Serial.write(reinterpret_cast<const uint8_t*>(s), n); }
};

board::BoardHal hal;
SerialOut usbOut;
linkkit::LineReader usbLine;
linkkit::Ble ble;
app::Device* device = nullptr;
linkkit::Kit* kit = nullptr;

// Messages are handled for at most this long before the next frame is drawn.
constexpr uint32_t kLinesUs = 8000;
#ifdef BOOP_GEL_PROFILE
// The board's frame timings, printed once a second with the face's own.
// Diagnostic text, not link JSON: a profiling build only.
// A sample is about 350 bytes, past the 256 the USB core queues by
// default, so this build gives it room for two (setup).
constexpr size_t kProfileTxBytes = 1024;
uint32_t profileAt = 0, profileFrames = 0, profileDraw = 0, profilePush = 0, profileWait = 0, profilePixels = 0;

void printProfile(uint32_t span) {
  char sample[640];
  int n = snprintf(sample, sizeof(sample),
                   "gel_profile fps_milli=%lu draw_us=%lu push_us=%lu wait_us=%lu push_px=%lu internal_free=%u "
                   "internal_min=%u psram_free=%u audio_write_errors=%lu cpu_mhz=%u",
                   (unsigned long)(profileFrames * 1000000u / span), (unsigned long)(profileDraw / profileFrames),
                   (unsigned long)(profilePush / profileFrames), (unsigned long)(profileWait / profileFrames),
                   (unsigned long)(profilePixels / profileFrames),
                   unsigned(heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT)),
                   unsigned(heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT)),
                   unsigned(heap_caps_get_free_size(MALLOC_CAP_SPIRAM)), (unsigned long)hal.audioOut().errors,
                   unsigned(getCpuFrequencyMhz()));
  // Each latency's p95 and max (dbg.latency), then the face's own line.
  if (n > 0 && size_t(n) < sizeof(sample)) n += device->latencyFields(sample + n, sizeof(sample) - size_t(n));
  if (n > 0 && size_t(n) + 1 < sizeof(sample)) sample[n++] = '\n', sample[n] = 0;
  if (n > 0 && size_t(n) < sizeof(sample)) n += device->profile(sample + n, sizeof(sample) - size_t(n), profileFrames);
  // Profiling must never wait for a terminal to drain the USB queue.
  if (n > 0 && size_t(n) < sizeof(sample) && Serial.availableForWrite() >= n)
    Serial.write(reinterpret_cast<const uint8_t*>(sample), size_t(n));
}
#endif

}  // namespace

void setup() {
#ifdef BOOP_GEL_PROFILE
  render::profileClock = []() { return uint32_t(micros()); };
#endif
  // The canvas comes first, while one contiguous 76.8 KB block is still free.
  const size_t canvasBytes = size_t(render::kWidth) * render::kHeight;
  auto* pixels = static_cast<uint8_t*>(heap_caps_malloc(canvasBytes, MALLOC_CAP_8BIT));

  Serial.setRxBufferSize(2048);
#ifdef BOOP_GEL_PROFILE
  Serial.setTxBufferSize(kProfileTxBytes);
#endif
  Serial.begin(460800);  // the CH340 on macOS can't do 921600
  hal.begin();
  if (!pixels || !board::displayBegin()) {
    // Nothing to draw with: say so on USB and keep what light there is on.
    board::displayFailed();
    for (;;) {
      Serial.println("{\"t\":\"dbg.fatal\",\"why\":\"canvas or display init failed\"}");
      delay(2000);
    }
  }
  board::audioBegin();  // dbg.state audio.out.ready says whether it worked
  static app::Device dev(hal, pixels);
  if (!dev.ready()) {
    for (;;) {
      Serial.println("{\"t\":\"dbg.fatal\",\"why\":\"native surface allocation failed\"}");
      delay(2000);
    }
  }
  static linkkit::Kit k(hal, dev, /*frozenClock=*/false);
  device = &dev;
  kit = &k;
  kit->setOut(linkkit::Link::kUsb, &usbOut);
  // Bluetooth after the canvas, so the canvas got its contiguous block.
  if (ble.begin(app::kBleNamePrefix, app::kIdPrefix)) kit->setOut(linkkit::Link::kBle, &ble);
  hal.setBle(&ble);
  // From here a loop that stops coming round for 5 s (the core's task
  // watchdog) restarts the board, and its next hello says `watchdog`.
  // Setup's slow start (the screen, the card) comes before it.
  enableLoopWDT();
}

void loop() {
  // Every message waiting, then one frame. Drawing between messages (up to 31 ms a
  // frame) let a burst overflow the 2 KB receive buffers and lose messages. A
  // debug message ends the batch, since tests order it against ticks; each
  // reply still reflects every message before it.
  bool busy = false, debug = false;
  const uint32_t start = micros();
  for (bool more = true; more && !debug && micros() - start < kLinesUs;) {
    more = false;
    while (Serial.available() > 0) {
      if (!usbLine.feed(char(Serial.read()))) continue;
      debug = kit->handleLine(usbLine.line(), usbLine.length(), linkkit::Link::kUsb);
      busy = more = true;
      break;
    }
    if (!debug && ble.poll(*kit)) busy = more = true;
  }
  uint32_t t0 = micros();
  kit->tick();
  const bool drew = device->takeFrame();
  if (drew) {
    const uint32_t t1 = micros();
    uint32_t pushed, waited = 0;
    if (auto* frames = device->frames()) {
      // A native frame is sent by the board's push task while the loop
      // draws the next: this waits only for the frame
      // before, if it's still going, and the push is the last one sent.
      board::displayPush(*frames);
      waited = micros() - t1;
      pushed = board::displayPushUs();
    } else {
      board::displayPush(device->canvas());
      pushed = micros() - t1;
      device->shown(millis());  // the canvas is on the panel once its push returns
    }
    device->noteFrame(t1 - t0, pushed);
#ifdef BOOP_GEL_PROFILE
    ++profileFrames;
    profileDraw += t1 - t0;
    profilePush += pushed;
    profileWait += waited;
    if (auto* frames = device->frames()) profilePixels += frames->plan().pixels();
    const uint32_t now = millis();
    if (now - profileAt >= 1000) {
      printProfile(now - profileAt);
      profileAt = now;
      profileFrames = profileDraw = profilePush = profileWait = profilePixels = 0;
    }
#endif
  }
  // A native frame reaches the panel when the push task has sent it.
  for (uint32_t at; board::displayShown(at);) device->shown(at);
  // A quiet pass rests a moment, but not after a frame: the next is due.
  if (!busy && !drew) delay(1);
}
