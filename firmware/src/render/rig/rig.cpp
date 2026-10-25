#include "render/rig/rig.h"

#include <cstring>

namespace render::rig {

int eased(Ease e, int t, int ms) {
  const int u = ms <= 0 || t >= ms ? 1024 : t <= 0 ? 0 : t * 1024 / ms;
  switch (e) {
    case Ease::kIn: return u * u / 1024;
    case Ease::kOut: return 1024 - (1024 - u) * (1024 - u) / 1024;
    case Ease::kInOut: return ease(t, ms);
    default: return u;
  }
}

int sample(const Track& track, uint32_t local) {
  const List<Key>& keys = track.keys;
  if (!keys.count) return 0;
  if (local <= keys[0].ms) return keys[0].value;
  for (int i = 1; i < keys.count; ++i) {
    const Key &a = keys[i - 1], &b = keys[i];
    if (local < b.ms) return a.value + (b.value - a.value) * eased(b.ease, int(local - a.ms), b.ms - a.ms) / 1024;
  }
  return keys[keys.count - 1].value;
}

namespace {
template <class T, class Match>
const T* find(const List<T>& list, Match match) {
  for (const T& item : list)
    if (match(item)) return &item;
  return nullptr;
}
}  // namespace

const Expression* Rig::expression(const char* mood) const {
  return find(expressions, [&](const Expression& e) { return !std::strcmp(e.mood, mood); });
}
const Clip* Rig::clip(const char* id) const {
  return find(clips, [&](const Clip& c) { return !std::strcmp(c.id, id); });
}
const Look* Rig::look(SceneState state) const {
  return find(looks, [&](const Look& l) { return l.state == state; });
}

int Look::fitting(uint32_t when, uint32_t lookMs) const {
  int n = 0;
  for (const Occasion& o : occasions) n += fits(o.when, o.afterS, when, lookMs);
  return n;
}
const Clip* Look::fitting(uint32_t when, uint32_t lookMs, int i) const {
  for (const Occasion& o : occasions)
    if (fits(o.when, o.afterS, when, lookMs) && !i--) return o.clip;
  return nullptr;
}

Hermite Ramp::at(uint32_t t) const {
  if (!within(t, start_, kFadeMs)) return {to_, 0};
  const Hermite h = hermite(from_, tangent_, to_, int(t - start_) * 1024 / int(kFadeMs));
  return {clamp(h.value, 0, 1000), h.slope};
}

void Ramp::retarget(int to, uint32_t t) {
  if (to == to_) return;
  const Hermite h = at(t);
  from_ = h.value, tangent_ = h.slope, to_ = to, start_ = t;
}

}  // namespace render::rig
