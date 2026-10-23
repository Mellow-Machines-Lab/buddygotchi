// The pixel face's presentation clock and asset adapter.
#pragma once
#include "render/face.h"
#include "render/pixel/effect_track.h"
#include "render/pixel/held.h"
#include "render/pixel/scene.h"
#include "render/pixel/sign.h"
#include "render/pixel/sounds.h"
namespace render::pixel {
class PixelFace final : public Face {
 public:
  static constexpr uint32_t kBlendMs = 150, kBlinkMs = 180, kTurnMinMs = 5000;
  static constexpr int kTurnPct = 67;
  // While an occasion's variation fits (one with tags, all on), a look
  // turns to one of those this often, so a costume or a coffee shows more
  // than its share; reactions always take one.
  static constexpr int kTaggedPct = 67;

  const char* name() const override { return "pixel"; }
  const voice::EffectClips& clips() const override { return render::pixel::clips(); }
  void reset(uint32_t t, linkkit::Rng& rng) override;
  void sync(const FaceSource& source, const FaceContext& context, uint32_t t) override;
  void rewind(uint32_t t, linkkit::Rng& rng) override;
  bool nextDue(uint32_t from, uint32_t to, uint32_t& at) override;
  void step(uint32_t t, linkkit::Rng& rng) override;
  void alert(uint32_t t, bool replacing) override;
  void started(SceneState a, Mood mood, uint8_t variant, Outcome outcome, StartCtx ctx) override;
  uint8_t lookVariant() const override { return lookVariant_; }
  void newLook() override { pending_ = true; }
  // Shows variation v (from 0) of the look until it turns (dbg.look).
  void showLookVariant(uint8_t v) override { lookVariant_ = v, pending_ = false; }
  uint8_t pick(SceneState a, Mood mood, int wanted, Outcome o, StartCtx c, linkkit::Rng& rng) const override;
  int variants(Mood m, SceneState s) const override { return render::variants(m, s); }
  uint32_t loopMs(Mood m, SceneState s, int v) const override { return render::loopMs(m, s, v); }
  // Its designs carry their own result.
  Outcome outcome(Mood m, SceneState s, int v, Outcome) const override { return variantOutcome(m, s, v); }
  uint32_t voiceMs(Mood m, SceneState s, int v) const override { return score(pixelIndex(m), int(s), v).voiceMs; }
  uint32_t holdMs(Mood mood, int loops, uint32_t t) const override;
  uint32_t designMs(uint32_t t) const override {
    return src_.anim != SceneState::kNone ? t - src_.at : uint32_t(uint64_t(t - lookAt_) * pace_ / 100);
  }
  bool blinking(uint32_t t) const override;
  SceneShow show(uint32_t t, bool mouthOpen, int dy) const override;
  bool draw(Canvas&, Surface*, const SceneShow&, uint32_t, const char*, const SignShow&, const Strip&,
            bool) override;
  int cues(uint32_t t, bool shown, voice::FxEvent* out, bool& changed) override;

 private:
  // What a step at nextDue's instant does: a blink, a turn of the look's
  // variation, or both.
  enum Due : uint8_t { kBlink = 1, kTurn = 2 };
  uint32_t blinkGap(linkkit::Rng& rng) const;
  uint32_t loopEnd(uint32_t t) const;
  bool turnable() const;
  // A variation of the look that fits now, never `avoid` while another
  // does, an occasion's kTaggedPct of the time while one fits.
  uint8_t pickLook(Mood m, SceneState s, int avoid, linkkit::Rng& rng) const;
  // A new look's variation: the first occasion's that fits, else the first
  // that fits, else the first.
  uint8_t firstLook(Mood m, SceneState s) const;
  // The variations of mood m's look s that fit now, but `avoid`, into out;
  // how many.
  int fittingLooks(Mood m, SceneState s, int avoid, uint8_t* out) const;
  bool lookFits(Mood m, SceneState s, int v) const { return fits(m, s, v, context_.when, context_.lookMs); }
  FaceSource src_;
  FaceContext context_;
  uint32_t lookAt_ = 0;
  uint8_t lookVariant_ = 0;
  // A new look waits for its variation, picked at the next sync from those
  // that fit then.
  bool pending_ = true;
  // The working looks' pace now, in percent (FaceContext::pace).
  int pace_ = 100;
  bool switched_ = false, blink_ = false;
  uint32_t switchAt_ = 0, blinkAt_ = 0, nextBlink_ = 0;
  // What nextDue found due, at dueAt_: Due bits, 0 for nothing.
  uint8_t due_ = 0;
  uint32_t dueAt_ = 0;
  uint8_t last_[int(SceneState::kCount)] = {};
  EffectTrack fx_;
  // The needs-you arc's cues (kArcCues) before this, on the request's clock,
  // are handled; off while the face isn't needs you.
  bool arcOn_ = false;
  uint32_t arcCovered_ = 0;
  uint64_t drawnKey_ = 0;
  bool drawnSign_ = false;
  SignPose drawnPose_{};
};
}  // namespace render::pixel
