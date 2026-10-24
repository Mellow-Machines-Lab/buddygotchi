#include "render/rig/rig.h"

#include <cstring>

#include "render/maths.h"

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

int crossed(const Clip& clip, uint32_t from, uint32_t to, const char** out, int max) {
  int n = 0;
  if (!clip.cues.count || !after(to, from)) return 0;
  // Each loop's start from the one `from` is in; a clip that doesn't loop
  // has only its first.
  for (uint32_t start = clip.loop ? from - from % clip.ms : 0; after(to, start); start += clip.ms) {
    for (const Cue& cue : clip.cues) {
      const uint32_t at = start + cue.ms;
      if (!after(from, at) && after(to, at)) {
        if (n == max) return n;
        out[n++] = cue.name;
      }
    }
    if (!clip.loop) break;
  }
  return n;
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
const Accessory* Rig::accessory(Outfit outfit) const {
  return find(accessories, [&](const Accessory& a) { return a.outfit == outfit; });
}

}  // namespace render::rig
