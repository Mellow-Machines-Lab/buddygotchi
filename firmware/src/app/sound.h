// What plays, a chunk at a time, the same on every board and in the
// simulator: it renders the voice player, mixes the sound effects in, and
// hands each chunk to the output, turning the amp on only while something
// plays. A task of the board's own runs it (board/audio.cpp), so a slow
// frame never stutters the sound.
#pragma once
#include <cstddef>
#include <cstdint>

#include "app/device.h"
#include "voice/effects.h"
#include "voice/player.h"

namespace app {

class Sound {
 public:
  // Samples per chunk: 8-bit unsigned at voice::kOutRate, 23 ms.
  static constexpr size_t kChunk = 512;
  // The amp stays on this many chunks (about a second) after the last
  // sound: what's queued has to play first, and a working design's clicks
  // come a few times a second, so it doesn't switch on and off between them.
  static constexpr int kAmpHold = 44;

  // Effects neither replace nor hush a line: they mix under it.
  enum class Kind : uint8_t { kSay, kHush, kEffect, kStopEffects };
  struct Cmd {
    Kind kind;
    voice::Line line;
    voice::Effect effect;
  };

  // Where the sound goes, and what keeps the figures whole between the
  // sound's task and the main loop.
  struct Out {
    virtual ~Out() = default;
    // Plays one chunk, blocking at the output's pace. False when it failed.
    virtual bool write(const uint8_t* chunk) = 0;
    virtual void amp(bool on) = 0;
    virtual int64_t nowUs() = 0;
    virtual void lock() = 0;
    virtual void unlock() = 0;
  };

  explicit Sound(Out& out) : out_(out) {}

  // The output started: dbg.state's audio.out.ready.
  void ready();
  // From the sound's task only: a line or an effect to start or stop, and
  // one chunk made and written. The task never lets the output run dry:
  // silence when there's nothing to say.
  void apply(const Cmd& c);
  void step();
  // The figures, from any task.
  AudioOut stats();

 private:
  // The line being played, for its timeline. Writes return at the output's
  // pace, so the time between the write before the line and the write that
  // finished it is how long the output took to play those chunks.
  struct Current {
    bool line = false;
    int take = -1;
    uint32_t planMs = 0;
    uint32_t samples = 0;  // line samples rendered
    uint32_t chunks = 0;   // chunks they span
    int64_t startUs = 0;
  };

  void finish(bool cut);
  void applyVoice(const Cmd& c);
  bool sounding() { return player_.playing() || effects_.playing(); }

  Out& out_;
  AudioOut stats_;  // guarded by the output's lock
  voice::Player player_;
  voice::Effects effects_;
  uint8_t chunk_[kChunk];
  Current cur_;
  int64_t lastWriteUs_ = 0;
  int drain_ = 0;  // chunks left before the amp goes off (kAmpHold)
};

}  // namespace app
