// The gel face: the slime engine (render/gel/engine.h), painted natively. This
// adapter turns what Behaviour follows into the engine's facts, mood and
// reactions; Behaviour times every reaction (the engine holds each one
// until told), and the engine's contact cues become sounds. The staged
// pack's rig (render/rig/) plays its clips on the gel through a mixer of
// the face's own, whose channels the painter lays over the engine's pose
// (applyRig): the gel's pastimes
// (render/gel/pastimes.h), one at a time after a rest, and a reaction's
// clip, a clip named as its state, as it starts. A clip's cues sound
// through the engine's contacts. The engine keeps its expressions,
// recipes, bits and springs. Its nightcap and the Zs beside it come and go
// through the rig's layer stack, the face's own too.
#pragma once
#include "render/face.h"
#include "render/gel/drawer.h"
#include "render/gel/engine.h"
#include "render/gel/lane.h"
#include "render/gel/lively.h"
#include "render/gel/gaze.h"
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
  uint8_t pick(SceneState, Mood, int, Outcome, linkkit::Rng&, int loops = 1, int turn = kNoTurn) const override;
  // A finish a size above small plays once.
  int plays(SceneState anim, uint8_t variant, int loops) const override;
  // A finger: the dome follows it (the engine's drag), from where it first
  // touched, leaning, squashing and stretching its way, and springs back
  // when it lets go, carried on a little by the finger's own speed.
  // The eyes follow it, and drift back as it goes.
  void finger(bool down, int x, int y) override;
  void letGo(int vx, int vy) override;
  // A finger kept still: it leans into the spot, its eyes shut, and breathes;
  // past that it dozes, and wakes as it lets go. Not while a Moment, a
  // needs-you screen or a work act has the body.
  bool leans(uint32_t t) const override;
  void lean(Lean level, uint32_t t) override;
  bool captionsTouches() const override { return true; }
  // An invite (render/gel/invite.h): its pose up at the glass, the place to
  // touch glowing, the payoff or a shrug. Over the look, as a Moment is:
  // no pastime, typing along, gaze or base pose while it shows.
  bool drawsInvites() const override { return true; }
  const char* passing(uint32_t t) const override;
  // The board's steady tilt: the body sloshes that way, while nothing else
  // moves it: no finger, Moment, needs-you, listening, work act, pastime,
  // transition or bit.
  void tilt(int mg, uint32_t t) override;
  // The work stream it draws, and whose word forward it answers as it
  // lands.
  void watch(const Stream* stream) override { stream_ = stream; }
  // A swipe flings the dome on, and plays nothing else.
  bool playsSwipe() const override { return false; }
  bool holdsUpFinish() const override { return true; }
  int noseDrop() const override;
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
  void started(SceneState, Mood, uint8_t, Outcome) override;
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
  bool draw(Canvas&, Surface*, const SceneShow&, uint32_t, const char*, const char*, const SignShow&, const DoneShow&,
            const Strip&, bool) override;
  void wish(const WishShow& show) override;
  void color(int index) override;
  void card(const CardShow& show) override { card_ = show; }
  bool cardAt(int x, int y) const override;
  int cues(uint32_t, bool, voice::FxEvent*, bool&) override;
  int profile(char* out, size_t n, uint32_t frames) override;
  const Engine& engine() const { return *engine_; }
  const rig::Mixer& mixer() const { return mixer_; }
  const rig::Layers& layers() const { return layers_; }
  // A pastime, from t, whoever's turn it would be (the face deals the rest
  // itself): for tests and pictures of each.
  void playPastime(Pastime p, uint32_t t);
  // The transition playing at t, or null.
  const rig::Clip* transition(uint32_t t) const { return transition_ && after(transitionEnds_, t) ? transition_ : nullptr; }
  const rig::Clip* cueing() const { return cueing_; }
  bool playPastime(const char* name, uint32_t t) override;
  // A rig clip of the pack's, by its id, over what's there now: for
  // scenarios and the Studio (the flop, which no Moment names yet).
  bool playClip(const char* name, uint32_t t) override;
  // A rule of the motion layer (render/gel/lively.h) on or off by name, or
  // "all": dbg.motion's. A reset puts every one back as kRules has it.
  bool motionRule(const char* rule, bool on) override { return lively_.set(rule, on); }
  const Lively& lively() const { return lively_; }
  // What it shows of the pastimes at t: the one playing.
  PastimeShow pastimes(uint32_t t) const;
  // How long its keyboard stays out after you stop typing (showAlong).
  static constexpr uint32_t kAlongLingerMs = 4000;
  // With you at the Mac (showWithYou): a pose's clip comes and goes over
  // kWithFadeMs; it reads along kReadLingerMs after your last scroll, and
  // settles in for a long read once it has read along kSettleMs, a gap of
  // kReadGapMs or more without a scroll starting the read again; with music
  // it gets into it kGrooveMs, then rests kGrooveRestMs, and again. A lean
  // toward the screen or the pointer is at most kLeanReach (the rig's lean,
  // thousandths), kPointerLean a step of the pointer's way across; up its
  // way, it stretches up kPointerStretch a step; and the body follows both
  // over about kLeanMs.
  static constexpr uint32_t kWithFadeMs = 600, kReadLingerMs = 6000, kSettleMs = 120000, kReadGapMs = 60000;
  static constexpr uint32_t kGrooveMs = 24000, kGrooveRestMs = 180000, kLeanMs = 350;
  static constexpr int kLeanReach = 160, kPointerLean = 14, kPointerStretch = 6, kNearStretch = 50;
  // The pointer also slides the body its way, kPointerSlide px a step at
  // most, and turns the eyes further than a look alone, kPointerGaze a step
  // across and kPointerGazeUp up or down (the rig's gaze, thousandths).
  static constexpr int kPointerSlide = 1, kPointerGaze = 55, kPointerGazeUp = 45;
  // Turned to the screen, watching: slid its way kScreenSlide px, its eyes
  // kScreenGaze across. Reading: further, kReadLean and kReadSlide, its eyes
  // lowered kPageGaze to the page. With the screen up (`macup`): its eyes
  // kScreenGazeUp up, and stretched up kUpStretch.
  static constexpr int kScreenSlide = 10, kScreenGaze = 450, kPageGaze = 350, kReadLean = 220, kReadSlide = 14;
  static constexpr int kScreenGazeUp = 600, kUpStretch = 150;
  // The page beside it scrolls this many px a second while you scroll.
  static constexpr int kPageScroll = 14;
  // Typing fast stays fast through a flicker off this long (showAlong).
  static constexpr uint32_t kFastLingerMs = 800;
  // What it does with you now besides typing along, and the rig's channels
  // as it paints them: the mixer's, with the lean it follows and the move
  // playing (clipChannels), under the motion layer, and a hit's shake.
  WithYou withYou() const { return with_; }
  rig::Channels channels() const;
  rig::Channels clipChannels() const;

 private:
  bool bodyFree() const;
  // A cue waits at most this long for Device to take it (one tick is 16 ms).
  static constexpr uint32_t kCueWaitMs = 150;
  // The engine's seed after a reset, so a reset board replays the same.
  static constexpr uint32_t kSeed = 53;
  // The dome's middle on the canvas (finger).
  static constexpr int kMidX = 160, kMidY = 129;
  // The eyes after a finger: how far they go at most, across and up, in
  // face units, and how far off (canvas px) the finger is
  // when they're half way there.
  static constexpr F kGazeReach = q(.09), kGazeUpReach = q(.07);
  static constexpr int kGazeKneePx = 40;
  // A lean's soft breath, so the sound engine says it: how often, how loud
  // (of 255, under the volume) and how low (permille). Dozing it's slower,
  // softer and lower. The bank has no purr: this is the snore's breath.
  static constexpr uint32_t kLeanBreathMs = 1800, kDozeBreathMs = 2800;
  static constexpr uint8_t kLeanBreathGain = 72, kDozeBreathGain = 56;
  static constexpr uint16_t kLeanBreathPitch = 900, kDozeBreathPitch = 800;
  std::unique_ptr<Engine> engine_;
  rig::Mixer mixer_;
  // The motion layer over the clips' channels, stepped with the engine.
  Lively lively_;
  void showLively(uint32_t dt, uint32_t t);
  // The Zs, as the engine's tags and state call for them
  // (layerContents), each fading in and out.
  rig::Layers layers_;
  // The transition playing (GelFace::showTransition), and until when, and
  // what it last saw: it plays once on the way from one Doing to another,
  // over what's already there, delaying nothing.
  const rig::Clip* transition_ = nullptr;
  uint32_t transitionEnds_ = 0;
  SceneState lastBase_ = SceneState::kNone;
  bool alone_ = false;
  // Boop's energy as last synced: from normal to bright (the day's first
  // hello), it stretches once.
  Energy energy_ = Energy::kNormal;
  void showTransition(uint32_t t);
  // The work act whose result the body last answered (answerAct), by when
  // it began, and the result it had then.
  uint32_t actAt_ = 0;
  ActResult actResult_ = ActResult::kRunning;
  void answerAct(uint32_t t);
  // How far the sign has lifted the body, as last drawn (signHop).
  int signHop_ = 0;
  // The move whose cues the face sounds (showMove), and how far into it it
  // was as last seen.
  const rig::Clip* move_ = nullptr;
  uint32_t moveMs_ = 0;
  void showMove();
  // The pastime playing, its clip on the mixer (none for a bit's or a
  // take's, which the engine plays), from when until when, and the look
  // it's for; the one stopped early, fading out from stoppedAt_; the one
  // dealt last, and when the next may be. They're dealt with dice of their
  // own (dice_), so the engine's randomness goes as it always has.
  Pastime pastime_ = Pastime::kNone, lastPastime_ = Pastime::kNone;
  const rig::Clip* clip_ = nullptr;
  uint32_t pastimeAt_ = 0, pastimeEnds_ = 0, stoppedAt_ = 0, restUntil_ = 0, dice_ = kSeed;
  SceneState pastimeLook_ = SceneState::kNone, dealtLook_ = SceneState::kNone;
  bool stopped_ = false;
  // The base clip on the mixer (showBase).
  const rig::Clip* base_ = nullptr;
  // The mood's idle move playing (Acting's move), and until when.
  const rig::Clip* idleMove_ = nullptr;
  uint32_t idleMoveEnds_ = 0;
  // Typing along with you (showAlong): while your hands are busy at the Mac
  // (the `typing` tag) it types as you do: its paws swing higher than the
  // agents' soft typing, and its body sways a little over the keys, keeping
  // time (the rig's `type-along` clip), never hopping. At work that's at its desk, in place of
  // the agents' soft typing, and only in its typing pose: looking, running
  // or waiting, its paws are off the keys and the pose has the body. Idle,
  // it has its keyboard out for it, its paws rest when you stop, and the
  // keyboard goes kAlongLingerMs after. It's the lowest thing there is: it
  // waits for a pastime or a transition to end, and gives way at once to a
  // finger, a Moment, a word forward, needs you or sleep. While the
  // keyboard is out alone no pastime is dealt; at work they're dealt as
  // ever, and it types with you again after each.
  rig::Ramp along_;
  bool tapping_ = false;
  uint32_t typedAt_ = 0;
  bool typed_ = false;
  void showAlong(uint32_t t);
  bool typingPose() const;
  bool light(SceneState look) const;
  // Free for you at the Mac: typing along and the poses of showWithYou.
  bool freeForYou(uint32_t t, SceneState& look) const;
  // Where its paws are in their beats (painter.h, briskLift), in
  // thousandths of a phase unit, and when typing fast was last seen.
  uint64_t pawPhaseQ_ = 0;
  uint32_t fastSeen_ = 0;
  void pawPhase(uint32_t dt);
  // Typing fast (the `typingfast` tag): its paws tap quicker and its eyes
  // open a little wider (the rig's `type-along-fast`). A stretch of typing
  // along kThinkAfterMs or longer that stops: it looks up at you
  // (render/gel/gaze.h, thinking with you).
  bool fast_ = false, typingTag_ = false, thought_ = false;
  uint32_t typingFrom_ = 0, thinkAt_ = 0;
  // With you at the Mac besides typing along: each is the body, the eyes and
  // the paws, and one mark on or beside it that reads at arm's length, as
  // typing along's ticks and speaking's rings do (Engine::With, drawn in
  // render/gel/layers.cpp). Lowest of all, below typing along: it waits for
  // a pastime or a transition, gives way at once to a finger, a Moment, a
  // word forward, needs you or sleep. At work in a pose of its own, or with
  // a card held, it's light (GelFace::light): a call and speaking show, and
  // the poses that move the whole body (reading, a video, music) give way to
  // the eyes, the marks staying. The one shown, first that fits:
  //
  // - on a call (`oncall`): still and a little smaller, its eyes half
  //   closed (`on-call`), a muted mic held still by its ear on the Mac's
  //   side and nothing else; no typing along, music or pastime, and its
  //   board silent (the Mac sends no volume). As the call ends, it stretches
  //   up (`stretch`);
  // - reading along while you scroll (`scrolling`), and kReadLingerMs after:
  //   a page beside it on the Mac's side, its lines scrolling up while you
  //   scroll; turned and slid that way (or up at it), lower, its eyes down
  //   on the page, travelling down a line and back up with a small nod
  //   (`read-along`); after kSettleMs, settled in lower, its lids half down
  //   (`read-along-settled`);
  // - a video (`video`): a small screen beside it on the Mac's side, a play
  //   mark on it, its light on the body, a new colour every few seconds;
  //   turned to it, taller and still, eyes wide, a slow blink, and now and
  //   then a small start (`video`);
  // - music (`music`): headphones on for as long as it plays, typing along
  //   too; it gets into it kGrooveMs, eyes half closed, a content face,
  //   swaying with a nod at each end (`groove`), notes rising from the
  //   headphones, then rests; as the music stops it opens its eyes and
  //   looks around (`look-around`).
  //
  // While a call, a read, a video or a groove is on, no pastime
  // is dealt. The pointer (state.ptr) moves the eyes (gaze.h) and leans the
  // body a little its way, more at the edge nearest the board.
  WithYou with_ = WithYou::kNone, wanted_ = WithYou::kNone;
  const rig::Clip* withClip_ = nullptr;
  bool scrolled_ = false, music_ = false, called_ = false, settled_ = false;
  // The clips it plays for you, found once (none for a pose: none plays):
  // a pose's by what it is, the long read's, typing along's and its fast
  // one, and the moves once.
  struct Clips {
    const rig::Clip* with[6];
    const rig::Clip *settled, *along, *fast, *stretch, *lookAround;
  };
  static const Clips clips_;
  uint32_t scrolledAt_ = 0, readFrom_ = 0, musicFrom_ = 0;
  // What it has on or beside it (Engine::With), each fading in and out over
  // the rig's fade: headphones, the page, the screen, the muted mic. The
  // page's lines scroll kPageScroll px a second while you scroll, from
  // where they were (scrolledMs_ of scrolling, to withAt_), kPageScroll.
  enum Mark { kHeadphones, kPage, kScreen, kMuted, kMarks };
  rig::Ramp marks_[kMarks];
  uint32_t scrolledMs_ = 0, withAt_ = 0;
  bool pointer_ = false, pointerNear_ = false;
  int pointerX_ = 0, pointerY_ = 0;
  // What it follows on the rig's channels, over the mixer's: the lean, the
  // stretch (squash), the whole body's slide (x, px) and the eyes' way
  // (gazeX, gazeY); where each is going, and where it is now, in 256ths.
  enum Follow { kFollowLean, kFollowSquash, kFollowX, kFollowGazeX, kFollowGazeY, kFollows };
  int followTo_[kFollows]{}, followBy_[kFollows]{};
  void showWithYou(uint32_t t);
  void followLean(uint32_t dt);
  // A move once, as one of them ends, if the body is free.
  void once(const rig::Clip& clip, uint32_t t);
  // Where it looks by itself (render/gel/gaze.h), from the facts now.
  Gaze gaze_;
  void showGaze(uint32_t t);
  // When the last move started (kMoveGapMs), if one has.
  uint32_t movedAt_ = 0;
  bool moved_ = false;
  // The invite as Behaviour last said (FaceContext::invite), from when on
  // the board's clock its phase began, and whether its payoff has sounded.
  InviteShow invite_;
  uint32_t inviteAt_ = 0;
  bool inviteSounded_ = false;
  // The engine's copy of it at t, the engine's own gestures held off while
  // it shows, and the payoff's one sound as the payoff begins.
  void showInvite(uint32_t t);
  // The reply it played last (FaceContext::reply), by when it started, so
  // each plays once.
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
  // The finger as last told, and the lean it's giving it: its next breath's
  // sound, a take from each in turn.
  int fingerNowX_ = 0, fingerNowY_ = 0;
  Lean lean_ = Lean::kNone;
  bool hasOwnFace_ = false;  // a Moment's face shows, which a lean gives way to
  uint32_t breathAt_ = 0;
  int breathTake_ = 0;
  // The eyes after a finger at x, y, and the spot it's on.
  void followFinger(int x, int y);
  void lookToward(int x, int y, bool finger);
  void leanOn(Lean level);
  void breathe(uint32_t t);
  voice::FxEvent pending_[kMaxCues];
  uint32_t pendingAt_[kMaxCues]{};
  int pendingCount_ = 0;
  const Stream* stream_ = nullptr;
  const Drawer* drawer_ = nullptr;
  // The surface it last drew on: the AMOLED's until it has (the drawer's
  // rows are laid out on it).
  Size size_{502, 410, 110};
  // The word forward the body last answered, by when it came.
  uint32_t landedAt_ = 0;
  bool landed_ = true;
  void advanceTo(uint32_t);
  // While the look shows: its tier's base clip on the mixer (the rig's
  // looks.json tiers), none otherwise, the old one fading out.
  void showBase();
  // While the engine shows the look itself, and nothing else holds the
  // body: once the rest is over, a pastime that fits; the one playing fades
  // out when the look gives way.
  void passTime(uint32_t t);
  // A pastime playing, not one fading out after an early stop.
  bool playing() const { return pastime_ != Pastime::kNone && !stopped_; }
  // Whether the engine shows the look itself, with nothing over it (no
  // listening or reaction, `anim` the one playing), and which look
  // that is: needs you's screen, or the base's.
  bool showsLook(SceneState anim, SceneState& look) const;
  // One of those that fit the look now, the newest kNewestPct of the time;
  // none dealt while none fits.
  void deal(SceneState look, uint32_t t);
  // A pastime starts as the one playing over `look`: dealt, or asked for
  // by a test. It counts as the last dealt, so the deal doesn't
  // play it again next, and the rest before the next starts as it ends.
  void start(const PastimeInfo& p, SceneState look, uint32_t t);
  // The engine's own idle gestures wait for the clip dealt or asked for.
  void holdGestures(const rig::Clip& clip);
  // A reply or a clip asked for: its pack's clip, reply-<name>, else
  // <name> itself (a skit's clip, the fix's flop).
  void reply(const char* name);
  // The playing one stops, fading out unless it ran its length; the rest
  // before the next starts now.
  void endPastime(uint32_t t, bool early);
  // A die from dice_: below `n`.
  uint32_t roll(uint32_t n);
  // The layers what the engine's tags and state call for now, from t.
  void showLayers(uint32_t t);
  // A clip played on the mixer, its cues to sound from now.
  void play(const rig::Clip& clip);
  // The body answers a word of the work stream as it lands.
  void land(CallStyle style);
  // The wish to show, the device's, set before each frame.
  WishShow wish_;
  // The card it holds (render/gel/card.h), as last given, and whether the
  // last frame drew it.
  CardShow card_;
  bool cardDrawn_ = false;
  // A new revision: the sounds already queued belong to what came before.
  void restartCues();
  bool factsChanged(const FaceContext& context) const;
  // The recipe a design names: its mood's profile, its row and take.
  static slime::Recipe recipe(Mood mood, SceneState state, int variant, Outcome outcome);
};
}  // namespace render::gel
