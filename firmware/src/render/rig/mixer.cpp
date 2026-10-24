#include "render/rig/mixer.h"

#include <algorithm>
#include <cstdlib>
#include <initializer_list>

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
  age = age + dt < kFadeMs ? age + dt : kFadeMs;
  style.mix = int16_t(ease1000(int(age), int(kFadeMs)));
  // Whole: the next style is the one drawn. A newer one fades in after.
  if (age == kFadeMs) style = {style.next, style.next, 0};
}

void Mixer::reset(uint8_t eyes, uint8_t mouth, const Clip* look) {
  for (int c = 0; c < kChannelCount; ++c) springs_[c] = {kRest.v[c] * 256, 0};
  eyes_ = {{eyes, eyes, 0}, eyes, 0};
  mouth_ = {{mouth, mouth, 0}, mouth, 0};
  playing_ = 0;
  if (look) {
    start(*look, true);
    plays_[0].in = kWeightMs;
  }
  mix();
}

void Mixer::setStyles(uint8_t eyes, uint8_t mouth) {
  eyes_.want = eyes;
  mouth_.want = mouth;
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

uint32_t Mixer::fadeMs(const Clip& clip) { return std::min<uint32_t>(kWeightMs, clip.ms / 4); }

int Mixer::weight(const Play& p) {
  const int fade = int(fadeMs(*p.clip));
  int w = ease(int(p.in), fade);
  if (!p.clip->loop) w = std::min(w, ease(int(p.clip->ms) - int(p.age), fade));
  if (p.cut) w = std::min(w, p.from * (1024 - ease(int(p.out), fade)) / 1024);
  return w;
}

void Mixer::advance(uint32_t dt) {
  int kept = 0;
  for (int i = 0; i < playing_; ++i) {
    Play p = plays_[i];
    p.age += dt;
    p.in = std::min(p.in + dt, kWeightMs);
    if (p.cut) p.out = std::min(p.out + dt, kWeightMs);
    if (p.clip->loop) p.age %= p.clip->ms;
    const bool over = (!p.clip->loop && p.age >= p.clip->ms) || (p.cut && p.out >= fadeMs(*p.clip));
    if (!over) plays_[kept++] = p;
  }
  playing_ = kept;
  for (int c = 0; c < kChannelCount; ++c) {
    Spring& s = springs_[c];
    const int32_t rest = kRest.v[c] * 256;
    const int64_t rate = body(Channel(c)) ? kBodyRate : kFaceRate;
    if (dt >= kSettledMs) s = {rest, 0};
    // A step at a time while it moves; within half a unit of rest and all
    // but still, it's at rest. |v| · h fits: v is held.
    for (uint32_t left = dt; left && (s.v || s.x != rest);) {
      const uint32_t h = std::min(left, kStepMs);
      s.v = held(s.v + (rate * rate * (rest - s.x) - 2 * rate * s.v) * int64_t(h) / 1000);
      s.x += s.v * int32_t(h) / 1000;
      if (std::abs(s.x - rest) < 128 && std::abs(s.v) < 128) s = {rest, 0};
      left -= h;
    }
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
