// Sound on the board: a task on
// core 0 renders the voice player, mixes the sound effects in, and feeds
// the board's output at 22.05 kHz (board/audio_out.h: the CYD's DAC on
// GPIO26, the AMOLED board's ES8311), turning the amp on only while
// something plays. The main loop hands it `say`s and effects through a
// small queue, so a slow frame never stutters the sound.
#pragma once

namespace board {

// Starts the output and the task. BoardHal's say, hush, effect,
// stopEffects and audioOut feed it.
bool audioBegin();

}  // namespace board
