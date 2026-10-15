// Boop's face boundary. The app owns priority, voice and
// LinkKit's turn. A face owns its presentation clock, variations, drawing,
// its sound clips and when they play. No display-library types cross this
// boundary, and nothing outside render/<face>/ knows which face is built:
// makeFace is the one place that chooses.
#pragma once
#include <cstddef>
#include <memory>
#include "linkkit/clock.h"
#include "render/types.h"
#include "render/surface.h"
#include "render/screens.h"
#include "voice/clips.h"
#include "voice/effects.h"

namespace render {
// What the face follows (Behaviour::sourceAt): the moment playing, if any,
// else the look, with the host facts a variation is chosen for.
struct FaceSource {
  SceneState anim = SceneState::kNone;  // the moment's animation (isMoment), kNone for none
  uint32_t at = 0;
  SceneState look = SceneState::kIdle;
  uint8_t lookVariant = 0, animVariant = 0;
  Mood mood = kStartupMood;
  Outcome outcome = Outcome::kNone;
  StartCtx ctx = StartCtx::kNone;
  int loops = 1;
  // How long the animation's design plays its loops, from `at`; it rests
  // on its last frame after that, while the moment holds on for its line.
  uint32_t playMs = 0;
  uint32_t id = 0;
  bool operator==(const FaceSource& o) const {
    return anim == o.anim && at == o.at && look == o.look && lookVariant == o.lookVariant &&
           animVariant == o.animVariant && mood == o.mood && playMs == o.playMs;
  }
  SceneState state() const { return anim != SceneState::kNone ? anim : look; }
  uint8_t variant() const { return anim != SceneState::kNone ? animVariant : lookVariant; }
};
// What the Mac last said, as far as a face may use it.
struct FaceContext {
  Mood mood = kStartupMood;
  SceneState look = SceneState::kIdle;
  bool working = false;
  bool mayVary = false;
  SceneState base = SceneState::kIdle, act = SceneState::kWorking;
  bool attention = false, borrowed = false;
  uint32_t attentionId = 0;
  const char* agent = "";
  const char* project = "";
  const char* thread = "";
  int more = 0;
};
class Face {
 public:
  static constexpr int kMaxCues = 16;
  virtual ~Face() = default;
  virtual const char* name() const = 0;  // hello's `face`
  // Draws into the board's native RGB565 surface (Device allocates it, at
  // the panel's size) rather than the 8-bit canvas alone.
  virtual bool drawsNative() const { return false; }
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

  // Bookkeeping a face may ignore: a new needs-you request, the Mac's
  // variation of the look. lookVariant is the one showing: the Mac's, or
  // the face's own choice.
  virtual void alert(uint32_t t, bool replacing) { (void)t, (void)replacing; }
  virtual uint8_t lookVariant() const = 0;
  virtual void setLookVariant(uint8_t variant) { (void)variant; }

  // A moment's variation: pick chooses without changing anything (a
  // refused call leaves no trace); started is told what played.
  virtual uint8_t pick(SceneState anim, Mood mood, int wanted, Outcome outcome, StartCtx ctx,
                       linkkit::Rng& rng) const = 0;
  virtual void started(SceneState anim, Mood mood, uint8_t variant, Outcome outcome, StartCtx ctx) = 0;

  // Its designs' timing, which Behaviour plays moments and lines by.
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
  // Draws the face and the shared lane: into the canvas, or into `native`
  // when it draws natively. `dirty` when something besides the face's own
  // clock changed since the last frame. Returns false when the pixels have
  // not changed.
  virtual bool draw(Canvas& canvas, Surface* native, const SceneShow& show, uint32_t t, const char* bubble,
                    const Strip& strip, bool dirty) = 0;
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
