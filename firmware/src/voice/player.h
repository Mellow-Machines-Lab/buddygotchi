// The voice player: plays a `say` of one or two recorded
// takes from the voice file on the SD card, each whole and at its recorded
// pitch, as 8-bit samples at 22.05 kHz for the DAC. The takes are
// 11.025 kHz; each is resampled 2× with linear interpolation as it plays.
// Pure C++: the board reads the voice file from its card, and tests and the
// simulator from a file on the Mac.
#pragma once
#include <cstddef>
#include <cstdint>

namespace voice {

constexpr uint32_t kOutRate = 22050;
constexpr uint32_t kRate = 11025;      // the takes' (voicegen's RATE)
constexpr uint32_t kMouthMs = 20;      // the mouth's resolution (voicegen's MOUTH_MS)
constexpr uint32_t kJoinGapMs = 180;   // between a `say`'s two takes
constexpr uint32_t kGapSamples = kRate * kJoinGapMs / 1000;
constexpr int kIdMax = 72;             // voicegen's ID_BYTES and TEXT_BYTES, with the NUL
constexpr int kTextMax = 36;
constexpr int kMaxFrames = 160;        // mouth frames: a take of up to 3.2 s

// Where the voice file's bytes come from: the card, or a file on the Mac.
struct Source {
  virtual ~Source() = default;
  // Reads `n` bytes at `at`; false when it can't.
  virtual bool read(uint32_t at, void* buf, uint32_t n) = 0;
};

// Opens the voice file, which lookups (on the main loop) and the player
// (the audio task) both read. False, and no voice, when it isn't a voice
// file voicegen wrote.
bool openFile(Source* source);
void closeFile();
bool fileOpen();
// The voice file's version, which the Mac compares with its own, or "none".
const char* assetsVersion();
// How many takes the voice file has.
int takeCount();

// A take by its id, loaded from the voice file into a small cache: a handle
// for the functions below, or -1 when there's no voice file or no such take.
// A handle stays good until a few more takes have been loaded.
int takeIndex(const char* id);
const char* takeId(int i);    // null for no take
const char* takeText(int i);  // the bubble's text; null for no take
uint32_t takeMs(int i);       // how long it plays, rounded down, as the Mac's Take.ms
// Whether the mouth is open `ms` into take i (the take's loud frames, one
// per kMouthMs); shut before and after it.
bool mouthOpen(int i, uint32_t ms);

// A `say`'s length and mouth: `take`, then, with `then` (-1 for none),
// the gap and `then`.
uint32_t sayMs(int take, int then);
bool sayMouthOpen(int take, int then, uint32_t ms);

// Where a take's samples are in the voice file.
struct Clip {
  uint32_t at = 0, len = 0;
};

// One `say`, as a do's `say` arg gave it, plus the volume
// from `state`. Its clips are filled in from the takes when it's made, so
// the audio task never looks a take up.
struct Say {
  int take = -1;    // the first take's handle, or -1: nothing plays
  int then = -1;    // the second's, or -1
  uint8_t vol = 6;  // 0–10, held in range by the device
  Clip a, b;
};
Say makeSay(int take, int then = -1, uint8_t vol = 6);

// How long a `say` lasts, in output samples: two for each of its own, the
// gap's included.
uint32_t saySamples(const Say& l);

class Player {
 public:
  void start(const Say& l);
  void stop();
  bool playing() const { return total_ > 0 && pos_ < total_; }

  // Fills `n` unsigned 8-bit samples (128 is silence). Returns how many
  // came from the `say`; the rest are silence.
  size_t render(uint8_t* out, size_t n);

  // The take playing (-1 for none) and the `say`'s length in output samples.
  int take() const { return take_; }
  uint32_t total() const { return total_; }

 private:
  int sample(uint32_t s);  // the `say`'s s-th source sample, around 0; 0 in the gap
  int take_ = -1;
  Clip a_, b_;
  uint32_t pos_ = 0;
  uint32_t total_ = 0;
  int gain_ = 0;       // 0–256
  int last_ = 0;       // the last sample out, around 0
  int fadeFrom_ = 0;   // what was cut, fading out over the next fade_ samples
  uint32_t fade_ = 0;
  // A window of the voice file's samples, read ahead from the card.
  static constexpr uint32_t kBuf = 1024;
  uint8_t buf_[kBuf];
  uint32_t bufAt_ = 0, bufLen_ = 0;
};

}  // namespace voice
