// The CYD's sound output:
// ESP-IDF's continuous DAC on GPIO26 at 22.05 kHz into the on-board amp.
#include "board/audio_out.h"

#include <Arduino.h>
#include <driver/dac_continuous.h>

#include "board/config.h"
#include "voice/player.h"

namespace board::audio_out {

namespace {

// Four 1 KB DMA buffers; the driver widens each sample to 16 bits, so each
// holds one chunk of 512 samples (23 ms). If the DMA ever finishes its
// queue, the synchronous driver stops handing buffers back (seen on the
// board, 2026-09-26), so the voice task must never let it run dry.
constexpr size_t kDmaBufs = 4;
constexpr size_t kDmaBytes = 2 * kChunk;
constexpr int kWriteTimeoutMs = 200;

dac_continuous_handle_t dac = nullptr;

}  // namespace

bool begin() {
  pinMode(pins::kAmpEnable, OUTPUT);
  amp(false);
  dac_continuous_config_t cfg = {};
  static_assert(pins::kDac == 26, "DAC_CHANNEL_MASK_CH1 is GPIO26");
  cfg.chan_mask = DAC_CHANNEL_MASK_CH1;
  cfg.desc_num = kDmaBufs;
  cfg.buf_size = kDmaBytes;
  cfg.freq_hz = voice::kOutRate;
  cfg.offset = 0;
  cfg.clk_src = DAC_DIGI_CLK_SRC_DEFAULT;
  cfg.chan_mode = DAC_CHANNEL_MODE_SIMUL;
  if (dac_continuous_new_channels(&cfg, &dac) != ESP_OK) return false;
  return dac_continuous_enable(dac) == ESP_OK;
}

bool write(const uint8_t* chunk) {
  if (dac_continuous_write(dac, const_cast<uint8_t*>(chunk), kChunk, nullptr, kWriteTimeoutMs) == ESP_OK) return true;
  // Wedged anyway: restart the DAC so the next `say` can play.
  dac_continuous_disable(dac);
  dac_continuous_enable(dac);
  return false;
}

void amp(bool on) { digitalWrite(pins::kAmpEnable, on ? LOW : HIGH); }  // active low

bool ampOn() { return digitalRead(pins::kAmpEnable) == LOW; }

}  // namespace board::audio_out
