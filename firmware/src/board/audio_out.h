// Where the board's sound goes: the voice task (board/audio.cpp) mixes a
// chunk at a time and hands it here, the AMOLED board's ES8311 over I2S
// (amoled206/audio_out.cpp).
#pragma once
#include <cstddef>
#include <cstdint>

namespace board::audio_out {

// Samples per chunk: 8-bit unsigned at voice::kOutRate, 23 ms.
constexpr size_t kChunk = 512;

// Sets up the output and its DMA buffers, with the amp off.
bool begin();
// Plays one chunk, blocking at the output's pace. False when it failed and
// had to be restarted (counted as audio.out.errors).
bool write(const uint8_t* chunk);
void amp(bool on);
bool ampOn();

}  // namespace board::audio_out
