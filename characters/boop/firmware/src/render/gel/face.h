// The gel face: the slime engine (render/gel/engine.h), the
// port of characters/boop/design/slime-blob/engine/, painted natively. This
// adapter turns what Behaviour follows into the engine's facts, mood and
// one-shots; Behaviour keeps timing every moment (the engine holds each
// one until told), and the engine's contact cues become sounds.
#pragma once
#include "render/face.h"
#include "render/gel/engine.h"
#include "render/gel/painter.h"
namespace render::gel {
class GelFace final : public Face {
 public:
  GelFace() : engine_(std::make_unique<Engine>()) {}
  const char* name() const override { return "gel"; }
  bool drawsNative() const override { return true; }
  const voice::EffectClips& clips() const override;
  void reset(uint32_t t, linkkit::Rng&) override;
  void seed(uint32_t s) override;
  void sync(const FaceSource&, const FaceContext&, uint32_t) override;
  bool nextDue(uint32_t from, uint32_t to, uint32_t& at) override;
  void step(uint32_t t, linkkit::Rng&) override;
  // The engine picks the look's variations itself; the Mac's is ignored.
  uint8_t lookVariant() const override { return uint8_t(engine_->scenes.variant); }
  uint8_t pick(SceneState, Mood, int, Outcome, StartCtx, linkkit::Rng&) const override;
  // A finger: the dome leans after it (the engine's drag), from where it
  // first touched, and springs back when it lets go.
  void finger(bool down, int x, int y) override;
  void started(SceneState, Mood, uint8_t, Outcome, StartCtx) override;
  int variants(Mood, SceneState) const override;
  uint32_t loopMs(Mood, SceneState, int variant) const override;
  // Its recipes are chosen for the outcome asked for.
  Outcome outcome(Mood, SceneState, int, Outcome requested) const override { return requested; }
  uint32_t voiceMs(Mood, SceneState, int) const override;
  uint32_t holdMs(Mood, int loops, uint32_t t) const override;
  uint32_t designMs(uint32_t t) const override {
    return t - (source_.anim != SceneState::kNone ? source_.at : lookAt_);
  }
  bool blinking(uint32_t) const override { return max(engine_->face.bridgeBlink, engine_->motion.blink()) > 0; }
  SceneShow show(uint32_t t, bool mouth, int dy) const override {
    return {source_.mood, source_.state(), uint8_t(engine_->scenes.variant), designMs(t), false, mouth, int16_t(dy)};
  }
  // Its engine keeps its own clock: it ignores draw's t and dirty, and
  // cues' t and shown (its contact cues play under the pattern too).
  bool draw(Canvas&, Surface*, const SceneShow&, uint32_t, const char*, const Strip&, bool) override;
  int cues(uint32_t, bool, voice::FxEvent*, bool&) override;
  int profile(char* out, size_t n, uint32_t frames) override;
  const Engine& engine() const { return *engine_; }

 private:
  // A cue waits at most this long for Device to take it (one tick is 16 ms).
  static constexpr uint32_t kCueWaitMs = 150;
  // The engine's seed after a reset: the reference traces' (check-port.py).
  static constexpr uint32_t kSeed = 53;
  std::unique_ptr<Engine> engine_;
  FaceSource source_;
  uint32_t origin_ = 0, lastTick_ = 0, lookAt_ = 0, revision_ = 0, cueRevision_ = 0;
  // The engine's own clock, which runs quicker in the working looks while
  // the agents are busy (render::workPace, in percent), and its hundredths.
  uint32_t engineMs_ = 0, engineFrac_ = 0;
  int pace_ = 100;
  bool finger_ = false;
  int fingerX_ = 0, fingerY_ = 0;
  voice::FxEvent pending_[kMaxCues];
  uint32_t pendingAt_[kMaxCues]{};
  int pendingCount_ = 0;
  void advanceTo(uint32_t);
  // A new revision: the sounds already queued belong to what came before.
  void restartCues();
  bool factsChanged(const FaceContext& context) const;
  // The recipe a design names: its mood's profile, its row and take.
  static const slime::Recipe& recipe(Mood mood, SceneState state, int variant, Outcome outcome, StartCtx ctx);
};
}  // namespace render::gel
