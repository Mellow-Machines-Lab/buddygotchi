#include "render/rig/mixer.h"

#include <algorithm>
#include <initializer_list>

namespace render::rig {

void Mixer::reset(const Clip* look) {
  playing_ = 0;
  if (look) {
    start(*look, true);
    plays_[0].in = kWeightMs;
  }
  mix();
}

void Mixer::setLook(const Clip* clip, uint32_t fadeMs) {
  for (int i = 0; i < playing_; ++i) {
    Play& p = plays_[i];
    if (!p.base || p.cut) continue;
    if (p.clip == clip) return;
    // The old look leaves as slowly as the new one comes.
    p.in = p.in * fadeMs / p.fade, p.fade = fadeMs;
    fadeOut(p);
  }
  if (clip) start(*clip, true, fadeMs);
}

void Mixer::play(const Clip& clip, uint32_t fadeMs, uint32_t from) { start(clip, false, fadeMs, from); }

void Mixer::stop(const Clip& clip) {
  for (int i = 0; i < playing_; ++i)
    if (plays_[i].clip == &clip && !plays_[i].base && !plays_[i].cut) fadeOut(plays_[i]);
}

void Mixer::start(const Clip& clip, bool base, uint32_t fadeMs, uint32_t from) {
  if (playing_ == kPlays) {
    // Room: the oldest goes, but the look's own clip, the one look not
    // fading out (setLook fades out the others).
    int gone = 0;
    while (plays_[gone].base && !plays_[gone].cut) ++gone;
    for (int i = gone; i + 1 < playing_; ++i) plays_[i] = plays_[i + 1];
    --playing_;
  }
  plays_[playing_++] = {&clip, clip.loop ? from % clip.ms : 0, 0, 0, 0, base, false, fadeMs};
}

void Mixer::fadeOut(Play& p) {
  p.from = weight(p);
  p.cut = true;
  p.out = 0;
}

uint32_t Mixer::fadeMs(const Play& p) { return std::min<uint32_t>(p.fade, p.clip->ms / 4); }

int Mixer::weight(const Play& p) {
  const int fade = int(fadeMs(p));
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
    p.in = std::min(p.in + dt, p.fade);
    if (p.cut) p.out = std::min(p.out + dt, p.fade);
    if (p.clip->loop) p.age %= p.clip->ms;
    const bool over = (!p.clip->loop && p.age >= p.clip->ms) || (p.cut && p.out >= fadeMs(p));
    if (!over) plays_[kept++] = p;
  }
  playing_ = kept;
  mix();
}

void Mixer::mix() {
  int v[kChannelCount];
  for (int c = 0; c < kChannelCount; ++c) v[c] = kRest.v[c];
  // The looks' clips under the reactions', each in the order it started.
  for (const bool base : {true, false}) {
    for (int i = 0; i < playing_; ++i) {
      const Play& p = plays_[i];
      const int w = p.base == base ? weight(p) : 0;
      if (!w) continue;
      const uint32_t t = p.clip->local(p.age);
      for (const Track& track : p.clip->tracks) {
        int& to = v[int(track.channel)];
        const int value = p.clip->value(track, t);
        to += (p.clip->additive ? value : value - to) * w / 1024;
      }
    }
  }
  for (int c = 0; c < kChannelCount; ++c) out_.v[c] = int16_t(clamp(v[c], kChannelInfo[c].lo, kChannelInfo[c].hi));
}

}  // namespace render::rig
