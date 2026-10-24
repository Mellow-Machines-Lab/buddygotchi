#include "render/rig/mixer.h"

#include <algorithm>
#include <initializer_list>

#include "render/maths.h"

namespace render::rig {

namespace {
// The springs' step: at most this many ms, so the stiffest stays stable.
constexpr uint32_t kStepMs = 4;
// A spring's velocity in 256ths a second, held within 100000 units a second.
constexpr int32_t held(int64_t v) { return int32_t(std::clamp<int64_t>(v, -100000 * 256, 100000 * 256)); }
// A 256ths value, rounded to whole units.
constexpr int32_t whole(int32_t q) { return q >= 0 ? (q + 128) / 256 : -((128 - q) / 256); }
}  // namespace

Mixer::Mixer() {
  for (int c = 0; c < kChannelCount; ++c) springs_[c].x = kRest.v[c] * 256;
}

void Mixer::Fader::advance(uint32_t dt) {
  if (style.next == style.index) {
    if (want == style.index) return;
    style.next = want;
    age = 0;
  }
  age = age + dt < kStyleMs ? age + dt : kStyleMs;
  style.mix = int16_t(ease(int(age), int(kStyleMs)) * 1000 / 1024);
  // Whole: the next style is the one drawn. A newer one fades in after.
  if (age == kStyleMs) style = {style.next, style.next, 0};
}

void Mixer::reset(const Expression& mood, const Clip* look) {
  targets_ = mood.values;
  for (int c = 0; c < kChannelCount; ++c) springs_[c] = {targets_.v[c] * 256, 0};
  eyes_ = {{mood.eyes, mood.eyes, 0}, mood.eyes, 0};
  mouth_ = {{mood.mouth, mood.mouth, 0}, mood.mouth, 0};
  playing_ = cueCount_ = 0;
  if (look) {
    start(*look, true);
    plays_[0].in = kFadeMs;
  }
  mix();
}

void Mixer::setMood(const Expression& mood) {
  targets_ = mood.values;
  eyes_.want = mood.eyes;
  mouth_.want = mood.mouth;
}

void Mixer::setLook(const Clip* clip) {
  for (int i = 0; i < playing_; ++i) {
    Play& p = plays_[i];
    if (!p.base || p.cut) continue;
    if (p.clip == clip) return;
    fadeOut(p);
  }
  if (clip) start(*clip, true);
}

void Mixer::play(const Clip& clip) { start(clip, false); }

void Mixer::cut() {
  for (int i = 0; i < playing_; ++i)
    if (!plays_[i].base && !plays_[i].cut) fadeOut(plays_[i]);
}

void Mixer::impulse(Channel channel, int velocity) {
  Spring& s = springs_[int(channel)];
  s.v = held(s.v + int64_t(velocity) * 256);
}

void Mixer::start(const Clip& clip, bool base) {
  if (playing_ == kPlays) {
    // Room: the oldest reaction fading out goes, else the oldest reaction,
    // else (only looks playing) the oldest look's.
    const auto rank = [](const Play& p) { return p.base ? 2 : p.cut ? 0 : 1; };
    int gone = 0;
    for (int i = 1; i < playing_; ++i)
      if (rank(plays_[i]) < rank(plays_[gone])) gone = i;
    for (int i = gone; i + 1 < playing_; ++i) plays_[i] = plays_[i + 1];
    --playing_;
  }
  plays_[playing_++] = {&clip, 0, 0, 0, 0, base, false};
}

void Mixer::fadeOut(Play& p) {
  p.from = weight(p);
  p.cut = true;
  p.out = 0;
}

int Mixer::weight(const Play& p) {
  int w = ease(int(p.in), int(kFadeMs));
  if (!p.clip->loop) w = std::min(w, ease(int(p.clip->ms) - int(p.age), int(kFadeMs)));
  if (p.cut) w = std::min(w, p.from * (1024 - ease(int(p.out), int(kFadeMs))) / 1024);
  return w;
}

void Mixer::advance(uint32_t dt) {
  cueCount_ = 0;
  int kept = 0;
  for (int i = 0; i < playing_; ++i) {
    Play p = plays_[i];
    const uint32_t was = p.age;
    p.age += dt;
    p.in = std::min(p.in + dt, kFadeMs);
    if (p.cut) p.out = std::min(p.out + dt, kFadeMs);
    if (!p.cut) cueCount_ += crossed(*p.clip, was, p.age, cues_ + cueCount_, kMaxCues - cueCount_);
    if (p.clip->loop) p.age %= p.clip->ms;
    const bool over = (!p.clip->loop && p.age >= p.clip->ms) || (p.cut && p.out >= kFadeMs);
    if (!over) plays_[kept++] = p;
  }
  playing_ = kept;
  for (uint32_t left = dt; left;) {
    const uint32_t h = std::min(left, kStepMs);
    for (int c = 0; c < kChannelCount; ++c) {
      Spring& s = springs_[c];
      const int64_t rate = body(Channel(c)) ? kBodyRate : kFaceRate;
      const int64_t a = rate * rate * (int64_t(targets_.v[c]) * 256 - s.x) - 2 * rate * s.v;
      s.v = held(s.v + a * int64_t(h) / 1000);
      s.x += int32_t(int64_t(s.v) * int64_t(h) / 1000);
    }
    left -= h;
  }
  eyes_.advance(dt);
  mouth_.advance(dt);
  mix();
}

void Mixer::mix() {
  int v[kChannelCount];
  for (int c = 0; c < kChannelCount; ++c) v[c] = whole(springs_[c].x);
  // The looks' clips under the reactions', each in the order it started.
  for (const bool base : {true, false}) {
    for (int i = 0; i < playing_; ++i) {
      const Play& p = plays_[i];
      const int w = p.base == base ? weight(p) : 0;
      if (!w) continue;
      const uint32_t t = p.clip->local(p.age);
      for (const Track& track : p.clip->tracks) {
        int& to = v[int(track.channel)];
        const int value = sample(track, t);
        to += (p.clip->additive ? value : value - to) * w / 1024;
      }
    }
  }
  for (int c = 0; c < kChannelCount; ++c) out_.v[c] = int16_t(clamp(v[c], kChannelInfo[c].lo, kChannelInfo[c].hi));
}

}  // namespace render::rig
