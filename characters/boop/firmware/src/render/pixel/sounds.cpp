#include "render/pixel/sounds.h"

#include "sfx.h"
#include "voice/player.h"

namespace render::pixel {

namespace {

static_assert(sfx_assets::kRate * 2 == voice::kOutRate, "clips are half the output rate, as the voice's are");
static_assert(sfx_assets::kLoops == kLoops, "the baked loops");

class Bank final : public voice::EffectClips {
 public:
  int count() const override { return sfx_assets::kClips; }
  voice::EffectClip at(int i) const override {
    if (i < 0 || i >= count()) return {};
    const auto& c = sfx_assets::kClip[i];
    return {c.name, sfx_assets::kSamples + c.at, c.len};
  }
  const char* version() const override { return sfx_assets::kVersion; }
  uint32_t bytes() const override { return sfx_assets::kBytes; }
};

int scoreIndex(int mood, int state, int variant) {
  if (mood < 0 || mood >= sfx_assets::kMoods || state < 0 || state >= sfx_assets::kStates) return -1;
  if (variant < 0 || variant >= sfx_assets::kVariants[mood][state]) variant = 0;
  return sfx_assets::kFirst[mood][state] + variant;
}

}  // namespace

const voice::EffectClips& clips() {
  static const Bank bank;
  return bank;
}

Score score(int mood, int state, int variant) {
  int i = scoreIndex(mood, state, variant);
  if (i < 0) return {};
  const sfx_assets::Score& s = sfx_assets::kScore[i];
  return {Policy(s.policy), s.every, s.duck, s.voiceMs, s.lists, s.loop0};
}

Events events(const Score& s, uint32_t loop) {
  if (s.lists <= 0) return {};
  const sfx_assets::List& l = sfx_assets::kList[sfx_assets::kLoopList[s.loop0 + int(loop % uint32_t(s.lists))]];
  return {l.first, l.n};
}

voice::FxEvent fxEvent(int i) {
  const sfx_assets::Event& e = sfx_assets::kEvent[i];
  return {e.atMs, e.clip, e.gain, e.pitch};
}

}  // namespace render::pixel
