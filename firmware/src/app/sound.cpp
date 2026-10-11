#include "app/sound.h"

namespace app {

namespace {

struct Locked {
  explicit Locked(Sound::Out& out) : out_(out) { out_.lock(); }
  ~Locked() { out_.unlock(); }
  Sound::Out& out_;
};

}  // namespace

void Sound::ready() {
  Locked l(out_);
  stats_.ready = true;
}

AudioOut Sound::stats() {
  Locked l(out_);
  return stats_;
}

void Sound::finish(bool cut) {
  if (!cur_.line) return;
  uint32_t wall = 0;
  if (cur_.chunks) {  // the output's pace, over the line's own samples
    int64_t us = (lastWriteUs_ - cur_.startUs) * int64_t(cur_.samples) / int64_t(cur_.chunks * kChunk);
    wall = uint32_t(us / 1000);
  }
  {
    Locked l(out_);
    ++stats_.lines;
    stats_.take = cur_.take;
    stats_.planMs = cur_.planMs;
    stats_.outMs = cur_.samples * 1000 / voice::kOutRate;
    stats_.wallMs = wall;
    stats_.cut = cut;
  }
  cur_ = Current{};
}

void Sound::applyVoice(const Cmd& c) {
  if (cur_.line) finish(true);  // anything new replaces a line
  switch (c.kind) {
    case Kind::kSay:
      player_.start(c.line);
      if (player_.playing()) {
        cur_.line = true;
        cur_.take = c.line.take;
        cur_.planMs = voice::lineSamples(c.line) * 1000 / voice::kOutRate;
        cur_.startUs = lastWriteUs_;
      }
      break;
    case Kind::kHush: player_.stop(); break;
    default: break;
  }
}

void Sound::apply(const Cmd& c) {
  if (c.kind == Kind::kEffect || c.kind == Kind::kStopEffects) {
    if (c.kind == Kind::kEffect) effects_.play(c.effect);
    else effects_.stop();
  } else {
    applyVoice(c);
  }
  if (sounding()) {
    out_.amp(true);
    drain_ = 0;
    Locked l(out_);
    stats_.playing = true;
  } else if (drain_ == 0) {
    drain_ = kAmpHold;  // hushed: let the queue play out, then the amp goes off
  }
}

void Sound::step() {
  bool was = player_.playing();
  bool wasAny = sounding();
  bool speaking = player_.playing();  // a line, which the effects go under
  size_t made = player_.render(chunk_, kChunk);
  effects_.mix(chunk_, kChunk, speaking);
  if (!out_.write(chunk_)) {
    Locked l(out_);
    ++stats_.errors;
  }
  lastWriteUs_ = out_.nowUs();
  if (cur_.line && made) cur_.samples += made, ++cur_.chunks;
  if (was && !player_.playing()) finish(false);
  if (wasAny && !sounding()) drain_ = kAmpHold;
  if (drain_ > 0 && --drain_ == 0 && !sounding()) {
    out_.amp(false);
    Locked l(out_);
    stats_.playing = false;
  }
}

}  // namespace app
