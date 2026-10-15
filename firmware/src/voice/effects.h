// Sound effects: a small mixer that adds a
// face's clips to the voice. Pure C++: the board mixes into the DAC's
// samples, and tests render into memory. Which clips there are is the
// face's (render::Face::clips, voice/clips.h), and when each plays is the
// face's too (the pixel face's render/pixel/effect_track.h, the gel's
// contact cues).
#pragma once
#include <cstddef>
#include <cstdint>

namespace voice {

// A sound the face hands over: a clip of its bank at a time into its
// design's loop (the pixel timelines' `atMs`; 0 for one due now).
struct FxEvent {
  uint16_t atMs = 0;
  uint8_t clip = 0;
  uint8_t gain = 255;     // 255 plays the clip as loud as a take
  uint16_t pitch = 1000;  // permille: 1000 plays the clip as made
  // A `say` turns it down; never needs you's, the finish's or an error's.
  // Each event carries its own, since one batch can mix both.
  bool duck = true;
};

// An event to play now, at the state's volume, with its clip's samples.
struct Effect {
  int clip = -1;  // its index in the face's bank, for dbg.state
  uint8_t gain = 255;
  uint16_t pitch = 1000;
  uint8_t vol = 6;                   // 0–10, as Say::vol
  bool duck = true;                  // a `say` turns it down (FxEvent::duck)
  const uint8_t* samples = nullptr;  // 11.025 kHz, unsigned 8-bit (voice/clips.h)
  uint32_t len = 0;
};

class Effects {
 public:
  static constexpr int kVoices = 4;  // effects at once; a fifth replaces the oldest
  static constexpr int kDuck = 64;   // of 256: under a `say`, a quarter as loud, the bank's level

  void play(const Effect& e);
  // Every effect fades out over 4 ms, so the cut doesn't click.
  void stop();
  bool playing() const;
  // Adds the effects into `out`, unsigned 8-bit samples at 22.05 kHz with
  // 128 as silence, turned down by kDuck while `duck`, but for those a
  // `say` never turns down.
  void mix(uint8_t* out, size_t n, bool duck);

 private:
  struct Voice {
    const uint8_t* samples = nullptr;  // null: free
    uint32_t len = 0;
    uint32_t src = 0;   // 16.16 source samples
    uint32_t step = 0;  // 16.16 source samples per output sample
    int gain = 0;       // of 65536
    bool duck = true;
    uint32_t fade = 0;  // cut: samples left of the fade, or 0
    uint32_t seq = 0;
  };
  Voice voices_[kVoices];
  uint32_t seq_ = 0;
};

}  // namespace voice
