#include "render/gel/sounds.h"

#include <cstring>

#include "slime.h"

namespace render::gel {

namespace {

class Bank final : public voice::EffectClips {
 public:
  int count() const override { return slime::kClipCount; }
  voice::EffectClip at(int i) const override {
    if (i < 0 || i >= count()) return {};
    const auto& c = slime::kClip[i];
    return {c.name, slime::kSamples + c.at, c.len};
  }
  const char* version() const override { return "gel-sketch-v1"; }
  uint32_t bytes() const override { return slime::kSampleBytes; }
};

}  // namespace

const voice::EffectClips& clips() {
  static const Bank bank;
  return bank;
}

int clipFor(const char* recipe, int take) {
  if (!recipe || take < 0 || take > 9) return -1;
  const size_t n = std::strlen(recipe);
  for (int i = 0; i < slime::kClipCount; ++i) {
    const char* name = slime::kClip[i].name;
    if (!std::strncmp(name, recipe, n) && name[n] == '-' && name[n + 1] == char('0' + take) && !name[n + 2]) return i;
  }
  return -1;
}

}  // namespace render::gel
