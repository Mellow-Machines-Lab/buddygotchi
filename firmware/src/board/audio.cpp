// The voice task, the same on every board: it runs the sound (app/sound.h)
// into the board's output (board/audio_out.h), fed by a small queue.
#include "board/audio.h"

#include <Arduino.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/task.h>

#include "app/sound.h"
#include "board/audio_out.h"
#include "board/board_hal.h"

namespace board {

namespace {

using Cmd = app::Sound::Cmd;
using Kind = app::Sound::Kind;
static_assert(app::Sound::kChunk == audio_out::kChunk, "the output takes the chunks the sound makes");

// Deep enough for the busiest design's events between two passes of the
// main loop, and a line.
constexpr int kQueue = 8;

QueueHandle_t queue = nullptr;
portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;

// The board's output and amp (board/audio_out.h), and a critical section
// around the figures.
struct BoardOut : app::Sound::Out {
  bool write(const uint8_t* chunk) override { return audio_out::write(chunk); }
  void amp(bool on) override { audio_out::amp(on); }
  int64_t nowUs() override { return esp_timer_get_time(); }
  void lock() override { portENTER_CRITICAL(&mux); }
  void unlock() override { portEXIT_CRITICAL(&mux); }
};
BoardOut out;
app::Sound sound(out);

void task(void*) {
  Cmd c;
  for (;;) {
    while (xQueueReceive(queue, &c, 0) == pdTRUE) sound.apply(c);
    sound.step();
  }
}

void send(const Cmd& c) {
  if (!queue) return;
  if (xQueueSend(queue, &c, 0) != pdTRUE) {  // full: the newest wins
    Cmd old;
    xQueueReceive(queue, &old, 0);
    xQueueSend(queue, &c, 0);
  }
}

}  // namespace

bool audioBegin() {
  if (!audio_out::begin()) return false;
  queue = xQueueCreate(kQueue, sizeof(Cmd));
  if (!queue) return false;
  // Above Bluetooth's host task, so the DMA never runs dry. Its stack has
  // room for reading the card (FatFs and the SPI driver) as it plays.
  if (xTaskCreatePinnedToCore(task, "voice", 6144, nullptr, configMAX_PRIORITIES - 3, nullptr, 0) != pdPASS)
    return false;
  sound.ready();
  return true;
}

// BoardHal's sound: the queue to the task, its figures and the amp.
void BoardHal::say(const voice::Line& l) { send({Kind::kSay, l, {}}); }
void BoardHal::hush() { send({Kind::kHush, {}, {}}); }
void BoardHal::effect(const voice::Effect& e) { send({Kind::kEffect, {}, e}); }
void BoardHal::stopEffects() { send({Kind::kStopEffects, {}, {}}); }

app::AudioOut BoardHal::audioOut() { return sound.stats(); }

bool BoardHal::ampOn() { return audio_out::ampOn(); }

}  // namespace board
