// The pixel face's presentation clock and asset adapter.
#pragma once
#include "render/face.h"
#include "render/pixel/effect_track.h"
#include "render/pixel/held.h"
#include "render/pixel/outfit.h"
#include "render/pixel/rig_face.h"
#include "render/pixel/scene.h"
#include "render/pixel/needs_you.h"
#include "render/pixel/sounds.h"
namespace render::pixel {
class PixelFace final : public Face {
 public:
  static constexpr uint32_t kBlinkMs = 180, kTurnMinMs = 5000;
  static constexpr int kTurnPct = 67;
  // While an occasion's variation fits (one with tags, all on), a look
  // turns to one of those this often, so a costume or a coffee shows more
  // than its share, as the rig's occasions play; reactions always take one.
  static constexpr int kTaggedPct = rig::kOccasionPct;

  const char* name() const override { return "pixel"; }
  const voice::EffectClips& clips() const override { return render::pixel::clips(); }
  void reset(uint32_t t, linkkit::Rng& rng) override;
  void sync(const FaceSource& source, const FaceContext& context, uint32_t t) override;
  void rewind(uint32_t t, linkkit::Rng& rng) override;
  bool nextDue(uint32_t from, uint32_t to, uint32_t& at) override;
  void step(uint32_t t, linkkit::Rng& rng) override;
  void alert(uint32_t t, bool replacing) override;
  void finger(bool down, int x, int y) override;
  void started(SceneState a, Mood mood, uint8_t variant, Outcome outcome, StartCtx ctx) override;
  uint8_t lookVariant() const override { return lookVariant_; }
  void newLook() override { pending_ = true; }
  // Shows variation v (from 0) of the look until it turns (dbg.look).
  void showLookVariant(uint8_t v) override { lookVariant_ = v, pending_ = false; }
  uint8_t pick(SceneState a, Mood mood, int wanted, Outcome o, StartCtx c, linkkit::Rng& rng, int loops,
               int turn) const override;
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
  bool draw(Canvas&, Surface*, const SceneShow&, uint32_t, const char*, const SignShow&, const DoneShow&, const Strip&,
            bool) override;
  int cues(uint32_t t, bool shown, voice::FxEvent* out, bool& changed) override;
  const RigFace& rigFace() const { return rig_; }

 private:
  // What a step at nextDue's instant does: a blink, a turn of the look's
  // variation, or both.
  enum Due : uint8_t { kBlink = 1, kTurn = 2 };
  uint32_t blinkGap(linkkit::Rng& rng) const;
  uint32_t loopEnd(uint32_t t) const;
  bool turnable() const;
  // The rig's look (the state's base), while the look shows, else nullptr;
  // and how many of its occasions fit now.
  const rig::Look* rigLook() const;
  int occasionsFit() const;
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
  // Whether the rig face draws mood m's state s, variation v: a design
  // whose face is its mood's resting face moved (rigFaced: as the bank
  // tags it, at every step, which the rig face draws exactly), in a mood with
  // a pose (RigFace::pose), in the design's place. The baked designs draw
  // the rest.
  bool rigDraws(Mood m, SceneState s, int v) const { return RigFace::pose(m) && rigFaced(m, s, v); }
  bool rigDraws() const { return rigDraws(src_.mood, src_.state(), src_.variant()); }
  // A frame draws the needs-you screen, a design, or a design with the rig
  // face in it; kNone, nothing yet.
  enum class Drew : uint8_t { kNone, kNeedsYou, kDesign, kRig };
  // A picture shown: what it drew, and the design's show; for the
  // needs-you screen, its pose and what it asked (the strip's agent, its
  // thread else project, and how many more), which the strip no longer
  // has once it's answered.
  struct Shown {
    Drew kind = Drew::kNone;
    SceneShow show;
    NeedsYouPose needsYou;
    char agent[16] = "", what[64] = "";
    int more = 0;
  };
  // A switch dissolves what shows into what's next over the rig's fade
  // (rig::kFadeMs), the whole picture; from the rig face to the rig face,
  // the designs around it, the face staying whole as it moves from where
  // the one had it to where the other has it. Into and out of the
  // needs-you screen, which has a lane of its own, the face's lane and what
  // it wears and holds go with the face. One mid-way through a dissolve
  // dissolves from the picture that shows more, as it last showed, so
  // nothing comes back.
  void startSwitch(uint32_t t);
  // How much of what comes in shows, 0 … 1000: all of it but while a
  // switch dissolves.
  int mix(uint32_t t) const {
    const bool fading = from_.kind != Drew::kNone && within(t, switchAt_, rig::kFadeMs);
    return fading ? ease1000(int(t - switchAt_), int(rig::kFadeMs)) : 1000;
  }
  // Everything a frame's pixels depend on but the words it shows: what it
  // draws, what a switch dissolves it from (kNone for nothing) and the
  // pixels of it that come in, the lane's dither level and whether the
  // bubble shows, the held sign's place and dither level, the hat's, the
  // outfit's look, and the needs-you screen's pose or the frames laid out.
  // Two equal pictures draw the same pixels, so a frame whose picture
  // hashes as the last one's isn't drawn again. Each is laid out once,
  // into picture_: off the stack, which a dissolve's outgoing frame needs.
  struct Picture {
    Drew kind, from;
    bool bubble, held;
    Dither in;
    uint8_t heldIn;  // the held sign's dither level
    int16_t lane, heldAt, hatX, hatY;
    uint32_t dress;
    NeedsYouPose needsYou;
    RigFrame face;
    SceneFrame design;
  };
  FaceSource src_;
  FaceContext context_;
  uint32_t lookAt_ = 0;
  uint8_t lookVariant_ = 0;
  // A new look waits for its variation, picked at the next sync from those
  // that fit then.
  bool pending_ = true;
  // The working looks' pace now, in percent (FaceContext::pace).
  int pace_ = 100;
  bool blink_ = false;
  uint32_t switchAt_ = 0, blinkAt_ = 0, nextBlink_ = 0;
  // A finger is down, and its press began while the rig face showed.
  bool pressing_ = false, rigPress_ = false;
  // What nextDue found due, at dueAt_: Due bits, 0 for nothing.
  uint8_t due_ = 0;
  uint32_t dueAt_ = 0;
  uint8_t last_[int(SceneState::kCount)] = {};
  EffectTrack fx_;
  // The needs-you arc's cues (kArcCues) before this, on the request's clock,
  // are handled; off while the face isn't needs you.
  bool arcOn_ = false;
  uint32_t arcCovered_ = 0;
  RigFace rig_;
  // The rig look's occasion playing on the rig face, until it ends: one
  // plays at the end of a look's loop, while the rig face draws it, and
  // fades out when the look gives way.
  const rig::Clip* occasion_ = nullptr;
  uint32_t occasionEnds_ = 0;
  SceneState occasionBase_ = SceneState::kNone;
  // What the last frame drew (coming in, while a switch dissolves) and its
  // picture's key; and what a switch dissolves from, kNone for nothing.
  Shown drawn_, from_;
  uint64_t drawnKey_ = 0;
  Picture picture_;
};
}  // namespace render::pixel
