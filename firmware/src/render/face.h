// Boop's face boundary. The app owns priority, voice and
// LinkKit's queue. A face owns its presentation clock, variations, drawing,
// its sound clips and when they play. No display-library types cross this
// boundary, and nothing outside render/<face>/ knows which face is built:
// makeFace is the one place that chooses.
#pragma once
#include <cstddef>
#include <memory>
#include "linkkit/clock.h"
#include "render/types.h"
#include "render/drawer.h"
#include "render/surface.h"
#include "render/screens.h"
#include "render/stream.h"
#include "voice/clips.h"
#include "voice/effects.h"

namespace render {
// What the face follows (Behaviour::sourceAt): the reaction playing, if any,
// else the look, with the host facts a variation is chosen for.
struct FaceSource {
  SceneState anim = SceneState::kNone;  // the reaction's animation (isReaction), kNone for none
  uint32_t at = 0;
  SceneState look = SceneState::kIdle;
  uint8_t lookVariant = 0, animVariant = 0;
  Mood mood = kStartupMood;
  Outcome outcome = Outcome::kNone;
  StartCtx ctx = StartCtx::kNone;
  int loops = 1;
  // How long the animation's design plays its loops, from `at`; it rests
  // on its last frame after that, while the reaction holds on for its `say`.
  uint32_t playMs = 0;
  uint32_t id = 0;
  // The animation is a finish that names whose turn it was (DoneShow): a
  // face that marks that on screen may leave out a result card of its own.
  // Not part of the design: changing it starts nothing over.
  bool named = false;
  bool operator==(const FaceSource& o) const {
    return anim == o.anim && at == o.at && look == o.look && lookVariant == o.lookVariant &&
           animVariant == o.animVariant && mood == o.mood && playMs == o.playMs;
  }
  SceneState state() const { return anim != SceneState::kNone ? anim : look; }
  uint8_t variant() const { return anim != SceneState::kNone ? animVariant : lookVariant; }
};
// The sign a reaction holds up while it plays (its `sign`): the words, at
// most Behaviour::kSignGlyphs glyphs of the fonts, how long it has shown,
// and how much of it, 0 … 1000: whole while it's up, then fading out over
// the rig's fade once it goes (app/behaviour.h). No text for none.
struct SignShow {
  const char* text = nullptr;
  uint32_t ms = 0;
  int opacity = 1000;
};
// The finished turn the brain's reaction is about (its `who`), while the
// reaction plays and lingers after (app/behaviour.h): whose turn, how it
// ended (kNone for a reply, or a face with no finish of its own), how long
// it has shown, and how long until it goes, -1 while its reaction still
// plays. A face may mark it on screen; the strip names it either way. No
// agent for none: with no app, or while something needs you, there's none.
struct DoneShow {
  const char* agent = nullptr;
  const char* thread = "";
  Outcome outcome = Outcome::kNone;
  uint32_t ms = 0;
  int32_t leftMs = -1;
  bool shows() const { return agent != nullptr; }
};
// How far a sign sits below its place `ms` after it went up, the same on
// every face: sliding up from `rise` px below, easing out, then lifting
// `bob` px now and then, a parabola.
constexpr uint32_t kSignRiseMs = 220, kSignBobEveryMs = 1400, kSignBobMs = 350;
inline int signLift(uint32_t ms, int rise, int bob) {
  if (ms < kSignRiseMs) {
    const int left = int(kSignRiseMs - ms);
    return rise * left * left / int(kSignRiseMs * kSignRiseMs);
  }
  const int n = int((ms - kSignRiseMs) % kSignBobEveryMs);
  return n < int(kSignBobMs) ? -4 * bob * n * (int(kSignBobMs) - n) / int(kSignBobMs * kSignBobMs) : 0;
}
// What the Mac last said, as far as a face may use it.
struct FaceContext {
  Mood mood = kStartupMood;
  SceneState look = SceneState::kIdle;
  bool working = false;
  bool mayVary = false;
  SceneState base = SceneState::kIdle, act = SceneState::kWorking;
  bool attention = false, borrowed = false;
  // While it's borrowed, the Mac's reply to what you said that it came
  // with ("" for none) and when it started: a face may play a move for it,
  // once (the gel, its pack's `reply-<name>` clip).
  const char* reply = "";
  uint32_t replyAt = 0;
  uint32_t attentionId = 0;
  const char* agent = "";
  const char* project = "";
  const char* thread = "";
  int more = 0;
  // The tags on (render/tags.h), how long the look (or needs you) has
  // shown, and the working looks' pace, in percent: quicker while the
  // agents are busy (render::workPace), 100 for any other look.
  uint32_t when = 0, lookMs = 0;
  int pace = 100;
};
class Face {
 public:
  static constexpr int kMaxCues = 16;
  virtual ~Face() = default;
  virtual const char* name() const = 0;  // hello's `face`
  // Draws into the board's native RGB565 surface (Device allocates it, at
  // the panel's size) rather than the 8-bit canvas alone.
  virtual bool drawsNative() const { return false; }
  // Read-only data it draws from often, which the board may copy where
  // it's quicker to read (Hal::quickerCopy) and hand back: the face then
  // reads the copy, the same bytes.
  virtual const void* assets(size_t& bytes) const { return bytes = 0, nullptr; }
  virtual void readAssetsFrom(const void* copy) { (void)copy; }
  // The clips its cues name (voice/clips.h).
  virtual const voice::EffectClips& clips() const = 0;

  // The presentation clock: reset at power-on and dbg.reset, rewound when
  // the device clock steps back (by default, reset again). Behaviour::advance
  // stops at every instant something changes, so each change happens at its
  // exact millisecond: nextDue gives the face's own next one after `from`,
  // at most `to`, and at each stop Behaviour syncs the face to the instant,
  // then steps it there. What's due at a stop is the face's to remember
  // from nextDue, since the sync can change it.
  virtual void reset(uint32_t t, linkkit::Rng& rng) = 0;
  // Power-on with the clock running: a seed from the board's randomness,
  // for a face that keeps randomness of its own (the gel's engine), so no
  // two boots replay the same choices. A tool's reset keeps the face's
  // fixed seed, so the board and the simulator still draw alike.
  virtual void seed(uint32_t s) { (void)s; }
  virtual void sync(const FaceSource& source, const FaceContext& context, uint32_t t) = 0;
  virtual void rewind(uint32_t t, linkkit::Rng& rng) { reset(t, rng); }
  virtual bool nextDue(uint32_t from, uint32_t to, uint32_t& at) = 0;
  virtual void step(uint32_t t, linkkit::Rng& rng) = 0;

  // Bookkeeping a face may ignore: a new needs-you, a new look. The face
  // picks each look's variation itself, from those whose tags are on
  // (FaceContext::when) and whose wait is over (lookMs); lookVariant is the
  // one showing.
  virtual void alert(uint32_t t, bool replacing) { (void)t, (void)replacing; }
  virtual uint8_t lookVariant() const = 0;
  virtual void newLook() {}
  // Shows the look's variation v (from 0) until it turns: dbg.look's, for
  // scenarios and tools. A face that picks by its own clock may ignore it.
  virtual void showLookVariant(uint8_t v) { (void)v; }
  // Plays the pastime whose clip is `clip` from t, whoever's turn it would
  // be: dbg.pastime's, for scenarios and tools. False for one the face
  // hasn't (a face with none has none).
  virtual bool playPastime(const char* clip, uint32_t t) {
    (void)clip, (void)t;
    return false;
  }
  // The work stream to draw (render/stream.h), the device's, set before
  // each frame: a face that has no stream ignores it.
  virtual void watch(const Stream* stream) { (void)stream; }
  // A finger on the screen (down, at x, y on the 320 × 240 canvas) or
  // let go: a face may follow it, as the gel's dome leans into a stroke.
  virtual void finger(bool down, int x, int y) { (void)down, (void)x, (void)y; }
  // The finger let go moving at vx, vy (canvas px a second, y down): a face
  // may carry the motion on, as the gel's dome does after a swipe.
  virtual void letGo(int vx, int vy) { (void)vx, (void)vy, finger(false, 0, 0); }
  // Whether a quick swipe plays the stroke (or the ruffle) it would be,
  // slower, as it does on a face that doesn't follow the finger; one that
  // carries it on as it lets go may only feel it go by.
  virtual bool playsSwipe() const { return true; }
  // The agents' drawer (render/drawer.h): whether this face has one, the
  // device's, set before each frame as the stream is, how far a finger
  // pulls it from shut to open (canvas px), the session open under a
  // finger at x, y on the canvas, by its place in the list (-1 for none),
  // how far a list of `total` sessions scrolls (canvas px), the nearest
  // scroll to `scroll` that starts on a whole row, and the first and last
  // sessions any of whose rows show, scrolled as `drawer` is. A face with
  // none never opens one: a swipe up its strip is the swipe it was.
  virtual bool hasDrawer() const { return false; }
  virtual void drawer(const Drawer* drawer) { (void)drawer; }
  virtual int drawerTravel() const { return 0; }
  virtual int drawerRow(const Drawer& drawer, int x, int y) const { return (void)drawer, (void)x, (void)y, -1; }
  virtual int drawerScrollMax(int total) const { return (void)total, 0; }
  virtual int drawerSnap(int scroll) const { return scroll; }
  virtual void drawerShown(const Drawer& drawer, int& first, int& last) const { (void)drawer, first = 0, last = -1; }

  // A reaction's variation: pick chooses without changing anything (a
  // refused reaction leaves no trace); started is told what played. A
  // finish also says how long it's held (`loops`) and the tier its turn
  // reached (`turn`), which a face may size it by.
  virtual uint8_t pick(SceneState anim, Mood mood, int wanted, Outcome outcome, StartCtx ctx, linkkit::Rng& rng,
                       int loops = 1, int turn = kNoTurn) const = 0;
  virtual void started(SceneState anim, Mood mood, uint8_t variant, Outcome outcome, StartCtx ctx) = 0;
  // How many times variation `variant` of `anim` plays when it's asked to
  // play `loops` times: a design sized by them plays once.
  virtual int plays(SceneState anim, uint8_t variant, int loops) const { return (void)anim, (void)variant, loops; }

  // Its designs' timing, which Behaviour plays reactions and `say`s by.
  virtual int variants(Mood mood, SceneState state) const = 0;
  virtual uint32_t loopMs(Mood mood, SceneState state, int variant) const = 0;
  // The result a finish shows in the strip: its design's, or the one asked for.
  virtual Outcome outcome(Mood mood, SceneState state, int variant, Outcome requested) const = 0;
  virtual uint32_t voiceMs(Mood mood, SceneState state, int variant) const = 0;
  virtual uint32_t holdMs(Mood mood, int loops, uint32_t t) const = 0;
  virtual uint32_t designMs(uint32_t t) const = 0;
  virtual bool blinking(uint32_t t) const = 0;

  // What shows at t, with the device's additions: the mouth talking and
  // the press's dip.
  virtual SceneShow show(uint32_t t, bool mouthOpen, int dy) const = 0;
  // Draws the face, the sign it holds up, the finished turn its reaction
  // is about if it marks one, and the shared lane: into the canvas, or into
  // `native` when it draws natively. `dirty` when something besides the
  // face's own clock changed since the last frame. Returns false when the
  // pixels have not changed.
  virtual bool draw(Canvas& canvas, Surface* native, const SceneShow& show, uint32_t t, const char* bubble,
                    const SignShow& sign, const DoneShow& done, const Strip& strip, bool dirty) = 0;
  // The sounds due at t, each with its own duck, and whether the last
  // ones should stop first; `shown` is false while the test pattern hides
  // the face.
  virtual int cues(uint32_t t, bool shown, voice::FxEvent* out, bool& changed) = 0;

  // BOOP_GEL_PROFILE builds: the face's own stage timings since the last
  // call, averaged over `frames`, as one line of text; 0 for none.
  virtual int profile(char* out, size_t n, uint32_t frames) {
    (void)out, (void)n, (void)frames;
    return 0;
  }
};
// The only build-time selection point. Native tests default to pixel.
std::unique_ptr<Face> makeFace();
}  // namespace render
