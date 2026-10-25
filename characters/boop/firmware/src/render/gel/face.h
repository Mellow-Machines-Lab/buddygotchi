// The gel face: the slime engine (render/gel/engine.h), painted natively. This
// adapter turns what Behaviour follows into the engine's facts, mood and
// one-shots; Behaviour keeps timing every moment (the engine holds each
// one until told), and the engine's contact cues become sounds. The staged
// pack's rig (render/rig/) plays its clips on the gel through a mixer of
// the face's own, whose channels the painter lays over the engine's pose
// (applyRig): the look's occasions and the gel's pastimes
// (render/gel/pastimes.h), one at a time after a rest, and a reaction's
// clip, a clip named as its state, as it starts. A clip's cues sound
// through the engine's contacts. The engine keeps its expressions,
// recipes, gags and springs. What it wears and the air around it come and
// go through the rig's layer stack, the face's own too, and so does the
// pastimes' kit.
#pragma once
#include "render/face.h"
#include "render/gel/drawer.h"
#include "render/gel/engine.h"
#include "render/gel/lane.h"
#include "render/gel/painter.h"
#include "render/gel/pastimes.h"
#include "render/rig/mixer.h"
#include "render/stream.h"
namespace render::gel {
class GelFace final : public Face {
 public:
  GelFace() : engine_(std::make_unique<Engine>()) {}
  const char* name() const override { return "gel"; }
  bool drawsNative() const override { return true; }
  // The body's material (render/gel/painter.h).
  const void* assets(size_t& bytes) const override;
  void readAssetsFrom(const void* copy) override;
  const voice::EffectClips& clips() const override;
  void reset(uint32_t t, linkkit::Rng&) override;
  void seed(uint32_t s) override;
  void sync(const FaceSource&, const FaceContext&, uint32_t) override;
  bool nextDue(uint32_t from, uint32_t to, uint32_t& at) override;
  void step(uint32_t t, linkkit::Rng&) override;
  // The engine picks the look's variations itself; the Mac's is ignored.
  uint8_t lookVariant() const override { return uint8_t(engine_->scenes.variant); }
  // A successful finish is sized by its turn, or its loops with none (render/gel/finish.h).
  uint8_t pick(SceneState, Mood, int, Outcome, StartCtx, linkkit::Rng&, int loops = 1,
               int turn = kNoTurn) const override;
  // A finish a size above small plays once.
  int plays(SceneState anim, uint8_t variant, int loops) const override;
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
  // The agents' drawer, up from the strip (render/gel/drawer.h).
  bool hasDrawer() const override { return true; }
  void drawer(const Drawer* drawer) override { drawer_ = drawer; }
  int drawerTravel() const override { return DrawerLayout(size_.width, size_.height, size_.corner).travel(); }
  int drawerRow(const Drawer& drawer, int x, int y) const override {
    return DrawerLayout(size_.width, size_.height, size_.corner).rowAt(drawer, x, y);
  }
  int drawerScrollMax(int total) const override {
    return DrawerLayout(size_.width, size_.height, size_.corner).scrollMax(total);
  }
  int drawerSnap(int scroll) const override { return DrawerLayout(size_.width, size_.height, size_.corner).snap(scroll); }
  void drawerShown(const Drawer& drawer, int& first, int& last) const override {
    DrawerLayout(size_.width, size_.height, size_.corner).shown(drawer, first, last);
  }
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
  bool draw(Canvas&, Surface*, const SceneShow&, uint32_t, const char*, const SignShow&, const DoneShow&, const Strip&,
            bool) override;
  int cues(uint32_t, bool, voice::FxEvent*, bool&) override;
  int profile(char* out, size_t n, uint32_t frames) override;
  const Engine& engine() const { return *engine_; }
  const rig::Mixer& mixer() const { return mixer_; }
  const rig::Layers& layers() const { return layers_; }
  // A pastime, from t, whoever's turn it would be (the face deals the rest
  // itself): for tests and pictures of each.
  void playPastime(Pastime p, uint32_t t);
  bool playPastime(const char* clip, uint32_t t) override;
  // What it shows of the pastimes at t: the one playing, and the kit.
  PastimeShow pastimes(uint32_t t) const;

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
  // The look's occasion or the pastime playing (kNone for an occasion's,
  // which draws nothing of its own), from when until when, and the look
  // it's for; the one stopped early, fading out from stoppedAt_; the clip
  // dealt last, and when the next may be. They're dealt with dice of their
  // own (dice_), so the engine's randomness goes as it always has.
  const rig::Clip* occasion_ = nullptr;
  Pastime pastime_ = Pastime::kNone;
  uint32_t occasionAt_ = 0, occasionEnds_ = 0, stoppedAt_ = 0, restUntil_ = 0, dice_ = kSeed;
  SceneState occasionLook_ = SceneState::kNone, dealtLook_ = SceneState::kNone;
  bool stopped_ = false;
  const rig::Clip* lastClip_ = nullptr;
  // The base clip on the mixer (showBase).
  const rig::Clip* base_ = nullptr;
  // The kit, each easing in and out, as the tiers and the look call for
  // it (showKit): when the work reached tier5, for the stack of mugs, and
  // how far the plant has grown.
  rig::Ramp mug_, headphones_, zone_, plant_;
  uint32_t zoneSince_ = 0;
  bool inZone_ = false;
  // Whether it wants the headphones on (working from tier3, its head free),
  // and has put them on since it last took them off (kPhonesOn).
  bool phonesWanted_ = false, phonesOn_ = false;
  // When the last move started (kMoveGapMs), if one has.
  uint32_t movedAt_ = 0;
  bool moved_ = false;
  int grown_ = 1;
  // The reply it played last (FaceContext::reply), its clip or its
  // pastime, by when it started, so each plays once.
  uint32_t replyAt_ = 0;
  bool replied_ = false;
  // The clip it last played, whose cues sound as it crosses them, and how
  // far into it it is.
  const rig::Clip* cueing_ = nullptr;
  uint32_t cueAge_ = 0;
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
  const Drawer* drawer_ = nullptr;
  // The surface it last drew on: the AMOLED's until it has (the drawer's
  // rows are laid out on it).
  Size size_{502, 410, 110};
  // The big finish it played last, which the next one isn't, where it can be.
  Finish lastBig_ = Finish::kLittle;
  // The word forward the body last answered, by when it came.
  uint32_t landedAt_ = 0;
  bool landed_ = true;
  void advanceTo(uint32_t);
  // While the look shows: its tier's base clip on the mixer (the rig's
  // looks.json tiers), none otherwise, the old one fading out.
  void showBase();
  // While the engine shows the look itself, and nothing else holds the
  // body: once the rest is over, a look's occasion or a pastime that fits;
  // the one playing fades out when the look gives way.
  void occasions(uint32_t t);
  // Whether the engine shows the look itself, with nothing over it (no
  // moment, listening or reaction, `anim` the one playing), and which look
  // that is: needs you's screen, or the base's.
  bool showsLook(SceneState anim, SceneState& look) const;
  // One of those that fit the look now, the newest tier's kNewestPct of the
  // time; none dealt while none fits.
  void deal(SceneState look, uint32_t t);
  // A clip starts as the one playing over `look`, the pastime's (kNone for
  // an occasion's): dealt, asked for by a reply or by a test. It counts as
  // the last dealt, so the deal doesn't play it again next, and the rest
  // before the next starts as it ends.
  void start(const rig::Clip& clip, Pastime p, SceneState look, uint32_t t);
  // The engine's own idle gestures wait for the clip dealt or asked for.
  void holdGestures(const rig::Clip& clip);
  // A reply asked for at t: its pastime (kReplyPastimes) while the look is
  // idle or asleep and shows, else its pack's clip, reply-<name>.
  void reply(const char* name, SceneState anim, uint32_t t);
  // The playing one stops, fading out unless it ran its length; the rest
  // before the next starts now.
  void endOccasion(uint32_t t, bool early);
  // The kit the tiers and the look call for now, from t.
  void showKit(uint32_t t);
  // A die from dice_: below `n`.
  uint32_t roll(uint32_t n);
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
