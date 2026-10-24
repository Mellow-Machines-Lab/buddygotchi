// The AMOLED board's sound output: the ES8311 codec
// over I2S at 22.05 kHz, 16-bit mono, and the NS4150B amp behind it.
#include "board/audio_out.h"

#include <Arduino.h>
#include <driver/i2s_std.h>

#include "board/amoled206/i2c.h"
#include "board/config.h"
#include "voice/player.h"

namespace board::audio_out {

namespace {

// Four DMA buffers of one chunk each, 16-bit.
constexpr size_t kDmaBufs = 4;
constexpr int kWriteTimeoutMs = 200;
// The ES8311 on I2C (board_hal starts the bus), and its DAC volume: 0xBF
// is 0 dB, in 0.5 dB steps.
constexpr uint8_t kCodec = 0x18;
constexpr uint8_t kCodecVolume = 0xBF;

i2s_chan_handle_t tx = nullptr;
int16_t wide[kChunk];  // the chunk as the codec takes it

bool codecWrite(uint8_t reg, uint8_t v) { return i2cWrite(kCodec, reg, v); }

// The register, or 0 if the codec didn't answer.
uint8_t codecRead(uint8_t reg) {
  uint8_t v = 0;
  return i2cRead(kCodec, reg, &v, 1) ? v : 0;
}

// The ES8311 as Espressif's driver sets it up: I2S slave, 16 bits, MCLK
// from its pin at 256 × 22.05 kHz, the DAC powered and its EQ bypassed.
bool codecBegin() {
  const uint8_t steps[][2] = {
      {0x00, 0x1F}, {0x00, 0x00}, {0x00, 0x80},  // reset, then power on
      {0x01, 0x3F},                              // all clocks on, MCLK from its pin
  };
  for (auto& s : steps)
    if (!codecWrite(s[0], s[1])) return false;
  codecWrite(0x06, codecRead(0x06) & ~0x20);  // SCLK not inverted
  // The clock dividers for MCLK 5.6448 MHz and 22.05 kHz (pre_div 1, ×1,
  // dividers 1, OSR 0x10, LRCK 256, BCLK ÷4).
  codecWrite(0x02, codecRead(0x02) & 0x07);
  codecWrite(0x03, 0x10);
  codecWrite(0x04, 0x10);
  codecWrite(0x05, 0x00);
  codecWrite(0x06, (codecRead(0x06) & 0xE0) | 0x03);
  codecWrite(0x07, codecRead(0x07) & 0xC0);
  codecWrite(0x08, 0xFF);
  codecWrite(0x00, codecRead(0x00) & 0xBF);  // slave
  codecWrite(0x09, 0x0C);                    // in: I2S, 16 bits
  codecWrite(0x0A, 0x0C);                    // out: I2S, 16 bits
  codecWrite(0x0D, 0x01);                    // analog power up
  codecWrite(0x0E, 0x02);
  codecWrite(0x12, 0x00);  // DAC power up
  codecWrite(0x13, 0x10);  // output to the HP driver
  codecWrite(0x1C, 0x6A);
  codecWrite(0x37, 0x08);  // DAC EQ bypassed
  codecWrite(0x31, codecRead(0x31) & ~0x60);  // unmuted
  return codecWrite(0x32, kCodecVolume);
}

}  // namespace

bool begin() {
  pinMode(pins::kAmpEnable, OUTPUT);
  amp(false);
  i2s_chan_config_t chan = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
  chan.dma_desc_num = kDmaBufs;
  chan.dma_frame_num = kChunk;
  chan.auto_clear = true;
  if (i2s_new_channel(&chan, &tx, nullptr) != ESP_OK) return false;
  i2s_std_config_t std = {};
  std.clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(voice::kOutRate);
  std.clk_cfg.mclk_multiple = I2S_MCLK_MULTIPLE_256;
  std.slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO);
  std.slot_cfg.slot_mask = I2S_STD_SLOT_BOTH;
  std.gpio_cfg.mclk = gpio_num_t(pins::kI2sMclk);
  std.gpio_cfg.bclk = gpio_num_t(pins::kI2sBclk);
  std.gpio_cfg.ws = gpio_num_t(pins::kI2sWs);
  std.gpio_cfg.dout = gpio_num_t(pins::kI2sDout);
  std.gpio_cfg.din = I2S_GPIO_UNUSED;
  if (i2s_channel_init_std_mode(tx, &std) != ESP_OK) return false;
  if (i2s_channel_enable(tx) != ESP_OK) return false;
  return codecBegin();
}

bool write(const uint8_t* chunk) {
  for (size_t i = 0; i < kChunk; ++i) wide[i] = int16_t((int(chunk[i]) - 128) << 8);
  size_t wrote = 0;
  return i2s_channel_write(tx, wide, sizeof(wide), &wrote, kWriteTimeoutMs) == ESP_OK && wrote == sizeof(wide);
}

void amp(bool on) { digitalWrite(pins::kAmpEnable, on ? HIGH : LOW); }  // active high

bool ampOn() { return digitalRead(pins::kAmpEnable) == HIGH; }

}  // namespace board::audio_out
