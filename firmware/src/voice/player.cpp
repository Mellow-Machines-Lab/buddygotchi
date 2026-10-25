#include "voice/player.h"

#include <cstdlib>
#include <cstring>

namespace voice {

namespace {

// The voice file's layout (voicegen's HEADER and RECORD),
// little-endian: a 64-byte header, then fixed-size records sorted by id,
// then each take's mouth (a byte per frame) and samples.
constexpr char kMagic[8] = {'B', 'O', 'O', 'P', 'V', 'O', 'X', '1'};
constexpr uint32_t kHeader = 64;
constexpr uint32_t kRecord = 128;

// A `say` cut short (hushed, or replaced) fades from where it was to
// silence over 4 ms, under whatever comes next: a step in one sample clicks.
constexpr uint32_t kCutFade = kOutRate * 4 / 1000;
// The mouth's frames are this many source samples.
constexpr uint32_t kMouthSamples = kRate * kMouthMs / 1000;
static_assert(kOutRate == 2 * kRate, "the takes play at half a source sample per output sample");

uint32_t u32(const uint8_t* p) { return p[0] | p[1] << 8 | p[2] << 16 | uint32_t(p[3]) << 24; }

struct VoiceFile {
  Source* source = nullptr;
  char version[17] = "none";
  uint32_t count = 0, indexAt = 0;
  // Every record's id, read once as the file opens, so a lookup on the
  // main loop searches memory and reads the card once, for its take's
  // mouth, not a dozen times. Null where there's no room for them (the
  // CYD: 2722 takes' ids are 196 KB), which searches the card instead.
  char* ids = nullptr;
};
VoiceFile file;
// The index is read this many records at a time as the file opens.
constexpr uint32_t kIdsChunk = 32;

// The takes looked up lately, each by the handle it was given.
struct Loaded {
  int handle = -1;
  char id[kIdMax] = "";
  char text[kTextMax] = "";
  Clip clip;
  uint16_t frames = 0;
  uint8_t mouth[(kMaxFrames + 7) / 8] = {};
};
constexpr int kSlots = 8;
Loaded slots[kSlots];
int nextHandle = 0;

const Loaded* slot(int i) {
  if (i < 0) return nullptr;
  const Loaded& s = slots[i % kSlots];
  return s.handle == i ? &s : nullptr;
}

// Record `i` of the index, its id and text NUL-ended.
bool record(uint32_t i, uint8_t (&r)[kRecord]) {
  if (!file.source->read(file.indexAt + i * kRecord, r, kRecord)) return false;
  r[kIdMax - 1] = r[kIdMax + kTextMax - 1] = 0;
  return true;
}

}  // namespace

bool openFile(Source* source) {
  closeFile();
  uint8_t h[kHeader];
  if (!source || !source->read(0, h, kHeader) || std::memcmp(h, kMagic, 8)) return false;
  if (u32(h + 28) != kRecord || u32(h + 36) != kRate || u32(h + 40) != kMouthMs) return false;
  file.source = source;
  std::memcpy(file.version, h + 8, 16);
  file.version[16] = 0;
  file.count = u32(h + 24);
  file.indexAt = u32(h + 32);
  file.ids = static_cast<char*>(std::malloc(size_t(file.count) * kIdMax));
  auto* chunk = static_cast<uint8_t*>(std::malloc(kIdsChunk * kRecord));
  for (uint32_t i = 0; file.ids && i < file.count; i += kIdsChunk) {
    const uint32_t n = file.count - i < kIdsChunk ? file.count - i : kIdsChunk;
    if (!chunk || !source->read(file.indexAt + i * kRecord, chunk, n * kRecord)) {
      std::free(file.ids);
      file.ids = nullptr;
      break;
    }
    for (uint32_t k = 0; k < n; ++k) {
      std::memcpy(file.ids + (i + k) * kIdMax, chunk + k * kRecord, kIdMax);
      file.ids[(i + k) * kIdMax + kIdMax - 1] = 0;
    }
  }
  std::free(chunk);
  return true;
}

void closeFile() {
  std::free(file.ids);
  file = VoiceFile{};
  for (Loaded& s : slots) s.handle = -1;
}

bool fileOpen() { return file.source != nullptr; }
const char* assetsVersion() { return file.version; }
int takeCount() { return int(file.count); }

int takeIndex(const char* id) {
  if (!id || !file.source) return -1;
  for (const Loaded& s : slots)
    if (s.handle >= 0 && !std::strcmp(s.id, id)) return s.handle;
  // Binary search of the index, which voicegen sorted by id's bytes.
  uint8_t r[kRecord];
  uint32_t lo = 0, hi = file.count;
  while (lo < hi) {
    uint32_t mid = (lo + hi) / 2;
    if (!file.ids && !record(mid, r)) return -1;
    int c = std::strcmp(file.ids ? file.ids + mid * kIdMax : reinterpret_cast<const char*>(r), id);
    if (c == 0) {
      if (file.ids && !record(mid, r)) return -1;
      const uint8_t* f = r + kIdMax + kTextMax;
      uint32_t frames = u32(f + 12);
      uint8_t bytes[kMaxFrames];
      if (frames > kMaxFrames || !file.source->read(u32(f + 8), bytes, frames)) return -1;
      int handle = nextHandle++;
      Loaded& s = slots[handle % kSlots];
      s = Loaded{};
      s.handle = handle;
      std::strncpy(s.id, reinterpret_cast<const char*>(r), kIdMax - 1);
      std::strncpy(s.text, reinterpret_cast<const char*>(r + kIdMax), kTextMax - 1);
      s.clip.at = u32(f);
      s.clip.len = u32(f + 4);
      s.frames = uint16_t(frames);
      for (uint32_t k = 0; k < frames; ++k)
        if (bytes[k]) s.mouth[k / 8] |= uint8_t(1 << (k % 8));
      return handle;
    }
    if (c < 0) lo = mid + 1;
    else hi = mid;
  }
  return -1;
}

const char* takeId(int i) { return slot(i) ? slot(i)->id : nullptr; }
const char* takeText(int i) { return slot(i) ? slot(i)->text : nullptr; }

uint32_t takeMs(int i) {
  const Loaded* s = slot(i);
  return s ? s->clip.len * 1000 / kRate : 0;  // as the Mac's Take.ms
}

bool mouthOpen(int i, uint32_t ms) {
  const Loaded* s = slot(i);
  if (!s) return false;
  uint32_t frame = uint32_t(uint64_t(ms) * kRate / 1000) / kMouthSamples;
  return frame < s->frames && (s->mouth[frame / 8] >> (frame % 8) & 1);
}

uint32_t sayMs(int take, int then) {
  if (!slot(take)) return 0;
  return takeMs(take) + (slot(then) ? kJoinGapMs + takeMs(then) : 0);
}

bool sayMouthOpen(int take, int then, uint32_t ms) {
  uint32_t first = takeMs(take);
  if (ms < first) return mouthOpen(take, ms);
  return slot(then) && ms >= first + kJoinGapMs && mouthOpen(then, ms - first - kJoinGapMs);
}

Say makeSay(int take, int then, uint8_t vol) {
  Say l;
  l.vol = vol;
  if (!slot(take)) return l;
  l.take = take;
  l.a = slot(take)->clip;
  if (slot(then)) {
    l.then = then;
    l.b = slot(then)->clip;
  }
  return l;
}

uint32_t saySamples(const Say& l) {
  if (!l.a.len) return 0;
  return 2u * (l.a.len + (l.b.len ? kGapSamples + l.b.len : 0));
}

void Player::start(const Say& l) {
  stop();
  gain_ = l.vol * 256 / 10;
  const bool plays = l.a.len && gain_ && file.source;  // muted, no take or no card: nothing to play
  take_ = plays ? l.take : -1;
  a_ = plays ? l.a : Clip{};
  b_ = plays ? l.b : Clip{};
  total_ = plays ? saySamples(l) : 0;
  bufLen_ = 0;
}

void Player::stop() {
  fadeFrom_ = playing() || fade_ ? last_ : 0;
  fade_ = fadeFrom_ ? kCutFade : 0;
  take_ = -1;
  pos_ = total_ = 0;
}

int Player::sample(uint32_t s) {
  uint32_t at;
  if (s < a_.len) {
    at = a_.at + s;
  } else if (b_.len && s >= a_.len + kGapSamples && s < a_.len + kGapSamples + b_.len) {
    at = b_.at + (s - a_.len - kGapSamples);
  } else {
    return 0;  // the gap, or past the end
  }
  if (at < bufAt_ || at >= bufAt_ + bufLen_) {
    // Refill from here: a clip's end may cut the window short.
    const Clip& c = s < a_.len ? a_ : b_;
    uint32_t n = c.at + c.len - at < kBuf ? c.at + c.len - at : kBuf;
    bufLen_ = file.source && file.source->read(at, buf_, n) ? n : 0;
    bufAt_ = at;
    if (!bufLen_) {
      // The card failed: the rest of the `say` goes, fading out, rather
      // than asking the card again for every sample.
      if (pos_ < total_) fadeFrom_ = last_, fade_ = kCutFade, total_ = pos_;
      return 0;
    }
  }
  return int(buf_[at - bufAt_]) - 128;
}

size_t Player::render(uint8_t* out, size_t n) {
  size_t made = 0;
  for (size_t j = 0; j < n; ++j) {
    int v = 0;
    if (pos_ < total_) {
      // Half a source sample per output sample: every other one is the
      // midpoint of two neighbours (linear interpolation, 16.16 step 32768).
      uint32_t s = pos_ >> 1;
      int a = sample(s);
      v = pos_ & 1 ? (a + sample(s + 1)) / 2 : a;
      ++pos_;
      ++made;
    }
    v = 128 + ((v * gain_) >> 8);
    if (fade_) v += fadeFrom_ * int(fade_--) / int(kCutFade);  // what was cut, fading out
    out[j] = uint8_t(v < 0 ? 0 : v > 255 ? 255 : v);
    last_ = out[j] - 128;
  }
  return made;
}

}  // namespace voice
