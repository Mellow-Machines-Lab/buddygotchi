// The gel face: the slime engine (render/gel/engine.h), painted natively. This
// adapter turns what Behaviour follows into the engine's facts, mood and
// one-shots; Behaviour keeps timing every moment (the engine holds each
// one until told), and the engine's contact cues become sounds. The staged
// pack's rig (render/rig/) plays its clips on the gel through a mixer of
// the face's own, whose channels the painter lays over the engine's pose
// (applyRig): the look's occasions, a chance at each pass of the look's
// scene, and a reaction's clip, a clip named as its state, as it starts.
// A clip's cues sound through the engine's contacts. The engine keeps its expressions, recipes, gags and springs. What
// it wears and the air around it come and go through the rig's layer
// stack, the face's own too.
#pragma once
#include "render/face.h"
#include "render/gel/engine.h"
#include "render/gel/lane.h"
#include "render/gel/painter.h"
#include "render/rig/mixer.h"
#include "render/stream.h"
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
  // A finger: the dome follows it (the engine's drag), from where it first
  // touched, leaning, squashing and stretching its way, and springs back
  // when it lets go, carried on a little by the finger's own speed.
  void finger(bool down, int x, int y) override;
  void letGo(int vx, int vy) override;
  // The work stream it draws, and whose word forward it answers as it
  // lands.
  void watch(const Stream* stream) override { stream_ = stream; }
  // A swipe flings the dome on, and plays nothing else.
  bool playsSwipe() const override { return false; }
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
  bool blinking(uint32_t) const override { return engine_->motion.blink() > F(0); }
  SceneShow show(uint32_t t, bool mouth, int dy) const override {
    return {source_.mood, source_.state(), uint8_t(engine_->scenes.variant), designMs(t), false, mouth, int16_t(dy)};
  }
  // Its engine keeps its own clock: it ignores draw's t and dirty, and
  // cues' t and shown (its contact cues play under the pattern too).
  bool draw(Canvas&, Surface*, const SceneShow&, uint32_t, const char*, const SignShow&, const Strip&,
            bool) override;
  int cues(uint32_t, bool, voice::FxEvent*, bool&) override;
  int profile(char* out, size_t n, uint32_t frames) override;
  const Engine& engine() const { return *engine_; }
  const rig::Mixer& mixer() const { return mixer_; }
  const rig::Layers& layers() const { return layers_; }

 private:
  // A cue waits at most this long for Device to take it (one tick is 16 ms).
  static constexpr uint32_t kCueWaitMs = 150;
  // The engine's seed after a reset, so a reset board replays the same.
  static constexpr uint32_t kSeed = 53;
  // The dome's middle on the canvas (finger).
  static constexpr int kMidX = 160, kMidY = 129;
  std::unique_ptr<Engine> engine_;
  rig::Mixer mixer_;
  // What it wears, the air and the Zs, as the engine's tags and state call
  // for them (layerContents), each fading in and out.
  rig::Layers layers_;
  // The look's occasion playing, until it ends; and the scene's pass that
  // last had its chance.
  const rig::Clip* occasion_ = nullptr;
  uint32_t occasionEnds_ = 0;
  // The clip it last played, whose cues sound as it crosses them, and how
  // far into it it is.
  const rig::Clip* cueing_ = nullptr;
  uint32_t cueAge_ = 0;
  int passGeneration_ = -1, passIteration_ = -1;
  FaceSource source_;
  uint32_t origin_ = 0, lastTick_ = 0, lookAt_ = 0, revision_ = 0, cueRevision_ = 0;
  // The engine's own clock, which runs quicker in the working looks while
  // the agents are busy (FaceContext::pace, in percent), and its hundredths.
  uint32_t engineMs_ = 0, engineFrac_ = 0;
  int pace_ = 100;
  bool finger_ = false;
  int fingerX_ = 0, fingerY_ = 0;
  voice::FxEvent pending_[kMaxCues];
  uint32_t pendingAt_[kMaxCues]{};
  int pendingCount_ = 0;
  const Stream* stream_ = nullptr;
  // The word forward the body last answered, by when it came.
  uint32_t landedAt_ = 0;
  bool landed_ = true;
  void advanceTo(uint32_t);
  // A look's occasion, at a new pass of its scene while none plays, while
  // the engine shows the look itself; the one playing fades out when the
  // look gives way.
  void occasions(uint32_t t);
  // The layers what the engine's tags and state call for now, from t.
  void showLayers(uint32_t t);
  // A clip played on the mixer, its cues to sound from now.
  void play(const rig::Clip& clip);
  // The body answers a word of the work stream as it lands.
  void land(CallGag gag);
  // A new revision: the sounds already queued belong to what came before.
  void restartCues();
  bool factsChanged(const FaceContext& context) const;
  // The recipe a design names: its mood's profile, its row and take.
  static const slime::Recipe& recipe(Mood mood, SceneState state, int variant, Outcome outcome, StartCtx ctx);
};
}  // namespace render::gel
