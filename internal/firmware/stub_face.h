// A small face for the engine's tests, so they test the engine (the
// behaviour state machine, the queue, the invite, the effects mixer) and
// not a pack's art: plain tables for its designs' timing, a canvas
// picture that changes with what it shows, and a bank of two clips. Every
// timing a test reads is one of the functions below, never a number of
// its own, so a table can change and the tests still hold.
#pragma once
#include <cstdint>
#include <cstring>

#include "linkkit/clock.h"
#include "render/face.h"
#include "render/maths.h"
#include "render/palette.h"

namespace testface {

using render::Mood;
using render::Outcome;
using render::SceneState;

// How many variations each state's design has: several where a test
// needs a choice, one elsewhere.
inline int variants(Mood, SceneState s) {
  switch (s) {
    case SceneState::kIdle:
    case SceneState::kWorking:
    case SceneState::kTaskComplete: return 2;
    case SceneState::kListening:
    case SceneState::kTerminal:
    case SceneState::kPoked:
    case SceneState::kTapSpam: return 3;
    case SceneState::kGesture: return int(render::Gesture::kCount);  // one for each kind of touch
    default: return 1;
  }
}
// How long a design takes to play once through, by its state: the same in
// every mood and for every variation.
inline uint32_t loopMs(Mood, SceneState s, int = 0) {
  static constexpr uint32_t kLoop[int(SceneState::kCount)] = {
      4000,  // idle
      3200,  // working
      3000,  // needs you
      5400,  // task complete
      6000,  // asleep
      3000,  // no app
      1600,  // listening
      2000, 2000, 2000, 2000, 2000, 2000, 2000, 2000,  // planning … waiting
      3000,  // reply ready
      800,   // poked
      1400,  // tap spam
      1500,  // wake up
      1000,  // gesture
      1200,  // notice
  };
  return int(s) < int(SceneState::kCount) ? kLoop[int(s)] : 1000;
}
// Where a line over the design may start, into its loop: half way into a
// finish, a third of the way into a reply, at once for the rest.
inline uint32_t voiceMs(Mood m, SceneState s, int v = 0) {
  if (s == SceneState::kTaskComplete) return loopMs(m, s, v) / 2;
  return s == SceneState::kReplyReady ? loopMs(m, s, v) / 3 : 0;
}

// The result a design shows: a finish's own, the first a success and the
// second a failure; for the rest, the one asked for.
inline Outcome outcomeOf(SceneState s, int v, Outcome requested) {
  if (s != SceneState::kTaskComplete) return requested;
  return v == 1 ? Outcome::kFailure : Outcome::kSuccess;
}

// Its sound clips: a short tick and a longer tone, each a full-scale
// square wave, and a ding for needs you.
class Clips final : public voice::EffectClips {
 public:
  Clips() {
    for (uint32_t i = 0; i < kTick; ++i) tick_[i] = (i / 8) % 2 ? 255 : 1;
    for (uint32_t i = 0; i < kTone; ++i) tone_[i] = (i / 16) % 2 ? 255 : 1;
  }
  int count() const override { return 3; }
  voice::EffectClip at(int clip) const override {
    switch (clip) {
      case 0: return {"tick", tick_, kTick};
      case 1: return {"tone", tone_, kTone};
      case 2: return {"ding", tone_, kTone / 2};
      default: return {};
    }
  }
  const char* version() const override { return "stub"; }
  uint32_t bytes() const override { return kTick + kTone; }

 private:
  static constexpr uint32_t kTick = 441, kTone = 4410;  // 40 ms and 400 ms
  uint8_t tick_[kTick], tone_[kTone];
};
inline const Clips& clips() {
  static const Clips c;
  return c;
}

// When its designs sound: a working design (the work's looks) a tick at
// the start of each loop, needs you a ding once, a second in, and a
// finish a tone once as it starts, neither turned down by a `say`; the
// rest are silent.
enum class Sounds : uint8_t { kSilent, kEveryLoop, kOnce };
inline Sounds sounds(SceneState s) {
  if (s == SceneState::kWorking || (int(s) >= int(SceneState::kPlanning) && int(s) <= int(SceneState::kWaiting)))
    return Sounds::kEveryLoop;
  if (s == SceneState::kNeedsYou || s == SceneState::kTaskComplete) return Sounds::kOnce;
  return Sounds::kSilent;
}
inline uint32_t onceAt(SceneState s) { return s == SceneState::kNeedsYou ? 1000 : 0; }
inline int clipOf(SceneState s) {
  return s == SceneState::kNeedsYou ? 2 : s == SceneState::kTaskComplete ? 1 : 0;
}

// A hash of what a strip says, which the stub marks it by.
inline uint32_t says(const render::Strip& s) {
  uint32_t h = 2166136261u;
  auto add = [&](uint32_t v) { h = (h ^ v) * 16777619u; };
  for (const char* text : {s.agent, s.project, s.name, s.doneAgent, s.doneThread, s.who, s.pill, s.wish})
    for (const char* p = text ? text : ""; *p; ++p) add(uint8_t(*p));
  for (int v : {s.more, s.busy, s.idle, s.helpers, s.todoDone, s.todoTotal, s.pipCount, s.watch, int(s.noApp)})
    add(uint32_t(v));
  return h;
}

class StubFace : public render::Face {
 public:
  // A design's picture moves a step every kStepMs (asleep's every
  // kAsleepStepMs), and sparks for kSparkMs as each step starts: two
  // pictures 3 ms apart, as a busy design's are, but few in a second.
  static constexpr uint32_t kStepMs = 200, kAsleepStepMs = 1500, kSparkMs = 3;

  // Its body, a box about where the gel's stands at rest, from (kBodyX0,
  // kBodyY0) to (kBodyX1, kBodyY1) on the canvas, its rim's margin in: the
  // nose's spot is on it, the lane and the screen's corners aren't. The
  // bar starts under its desk, at kBarTop, inside the rim's margin, as the
  // gel's does.
  static constexpr int kBodyX0 = 64, kBodyY0 = 40, kBodyX1 = 256, kBodyY1 = 190, kBarTop = 178;

  const char* name() const override { return "stub"; }
  const voice::EffectClips& clips() const override { return testface::clips(); }
  bool bodyAt(int x, int y) const override { return x >= kBodyX0 && x < kBodyX1 && y >= kBodyY0 && y < kBodyY1; }
  int barTop() const override { return kBarTop; }
  void reset(uint32_t t, linkkit::Rng&) override { *this = StubFace{}, lookAt_ = t; }
  void sync(const render::FaceSource& next, const render::FaceContext& context, uint32_t t) override {
    context_ = context;
    // The working looks keep their place in the loop as the pace changes.
    if (context.pace != pace_) {
      const uint32_t into = designMs(t);
      pace_ = context.pace > 0 ? context.pace : 100;
      lookAt_ = t - uint32_t((uint64_t(into) * 100 + pace_ - 1) / pace_);
    }
    render::FaceSource wanted = next;
    if (pinned_ >= 0) wanted.lookVariant = uint8_t(pinned_);
    if (wanted.lookVariant >= variants(wanted.mood, wanted.look)) wanted.lookVariant = 0;
    if (!(wanted == src_)) {
      if (wanted.look != src_.look || wanted.lookVariant != src_.lookVariant) lookAt_ = t;
      src_ = wanted;
    }
  }
  // The clock went back: the look's design starts over at the new time.
  void rewind(uint32_t t, linkkit::Rng&) override { lookAt_ = t; }
  bool nextDue(uint32_t, uint32_t, uint32_t&) override { return false; }
  void step(uint32_t, linkkit::Rng&) override {}
  void alert(uint32_t t, bool) override { lookAt_ = t; }
  uint8_t lookVariant() const override { return src_.lookVariant; }
  void newLook() override { pinned_ = -1; }
  bool showLookVariant(uint8_t v) override { return pinned_ = v, true; }

  // A finish's design for the outcome asked for; else the variation asked
  // for, if it has it, else one it didn't play last.
  uint8_t pick(SceneState s, Mood mood, int wanted, Outcome o, linkkit::Rng& rng, int, int) const override {
    if (s == SceneState::kTaskComplete && o != Outcome::kNone) return o == Outcome::kFailure ? 1 : 0;
    const int n = variants(mood, s);
    if (wanted >= 1 && wanted <= n) return uint8_t(wanted - 1);
    if (n == 1 || int(s) >= int(SceneState::kCount)) return 0;
    const int v = rng.range(0, n - 2);
    return uint8_t(v >= last_[int(s)] - 1 && last_[int(s)] ? v + 1 : v);
  }
  void started(SceneState s, Mood, uint8_t variant, Outcome) override {
    if (int(s) < int(SceneState::kCount)) last_[int(s)] = uint8_t(variant + 1);
  }
  int variants(Mood m, SceneState s) const override { return testface::variants(m, s); }
  uint32_t loopMs(Mood m, SceneState s, int v) const override { return testface::loopMs(m, s, v); }
  Outcome outcome(Mood, SceneState s, int v, Outcome requested) const override { return outcomeOf(s, v, requested); }
  uint32_t voiceMs(Mood m, SceneState s, int v) const override { return testface::voiceMs(m, s, v); }
  // What's left of the loop playing, then `loops` - 1 more.
  uint32_t holdMs(Mood mood, int loops, uint32_t t) const override {
    const uint32_t loop = testface::loopMs(mood, src_.state(), src_.variant());
    return loop - designMs(t) % loop + uint32_t(loops - 1) * loop;
  }
  uint32_t designMs(uint32_t t) const override {
    return src_.anim != SceneState::kNone ? t - src_.at : uint32_t(uint64_t(t - lookAt_) * pace_ / 100);
  }
  bool blinking(uint32_t) const override { return false; }
  render::SceneShow show(uint32_t t, bool mouthOpen, int dy) const override {
    render::SceneShow s;
    s.mood = src_.mood, s.state = src_.state(), s.variant = src_.variant();
    const uint32_t loop = testface::loopMs(s.mood, s.state, s.variant);
    // A look's clock runs on; a reaction loops until its design has
    // played, then rests on its last frame; needs you plays once, then
    // holds its first.
    s.t = designMs(t);
    if (src_.anim != SceneState::kNone) s.t = s.t >= src_.playMs ? loop - 1 : s.t % loop;
    if (s.state == SceneState::kNeedsYou && s.t >= loop) s.t = 0;
    s.mouthOpen = mouthOpen, s.dy = int16_t(dy);
    return s;
  }

  // A bar along the top for the design (its state, mood and variation),
  // a block that moves a step at a time with a spark as each starts, and
  // in the lane the bubble or the strip, marked by what it says and keyed by
  // its opacity.
  bool draw(render::Canvas& c, render::Surface*, const render::SceneShow& show, uint32_t, const char* bubble,
            const char*, const render::SignShow& sign, const render::DoneShow&, const render::Strip& strip,
            bool dirty) override {
    const uint32_t step = show.state == SceneState::kAsleep ? kAsleepStepMs : kStepMs;
    const bool spark = show.state != SceneState::kAsleep && show.t % step < kSparkMs;
    const uint32_t key[] = {uint32_t(show.state), uint32_t(show.mood), show.variant, show.t / step,
                            uint32_t(spark), uint32_t(show.mouthOpen), uint32_t(show.dy & 0xFFFF),
                            uint32_t(bubble != nullptr), uint32_t(strip.shows()), uint32_t(strip.opacity),
                            uint32_t(sign.text != nullptr), says(strip)};
    if (!dirty && drawn_ && !std::memcmp(key, key_, sizeof key)) return false;
    std::memcpy(key_, key, sizeof key), drawn_ = true;
    c.fill(render::kBlack);
    c.fillRect(0, 0, 8 + 8 * int(show.state), 4, render::kWhite);
    c.fillRect(0, 4, 8 + 4 * int(show.mood), 4, render::kAmber);
    c.fillRect(0, 8, 8 + 8 * show.variant, 4, render::kWhite);
    c.fillRect(16 * int(show.t / step % 16), 40 + show.dy, 16, 16, render::kWhite);
    if (spark) c.fillRect(300, 40, 8, 8, render::kAmber);
    if (show.mouthOpen) c.fillRect(150, 120, 20, 10, render::kAmber);
    if (sign.text) c.fillRect(100, 60, 120, 30, render::kAmber);
    if (bubble) {
      c.fillRect(0, render::kLaneTop, render::kWidth, render::kHeight - render::kLaneTop, render::kAmber);
    } else if (strip.shows() && strip.opacity > 0) {
      c.fillRect(0, render::kStripTop, render::kWidth, render::kHeight - render::kStripTop,
                 strip.agent ? render::kAmber : render::kWhite);
      c.fillRect(int(says(strip) % uint32_t(render::kWidth - 8)), render::kStripTop + 8, 8, 8, render::kBlack);
    }
    return true;
  }

  // Each design's sounds (sounds()), on its clock: a cue as it's due,
  // handed over once; a new design stops the last's.
  int cues(uint32_t t, bool shown, voice::FxEvent* out, bool& changed) override {
    const render::SceneShow s = show(t, false, 0);
    const uint32_t loop = testface::loopMs(s.mood, s.state, s.variant), into = designMs(t);
    const uint64_t design = uint64_t(src_.anim != SceneState::kNone ? src_.at : lookAt_) << 16 |
                            uint64_t(s.state) << 8 | s.variant;
    const int64_t n = shown ? int64_t(into / loop) : -1;
    changed = !shown || design != design_ || n < heard_;
    if (changed) design_ = design, heard_ = -1, once_ = false;
    if (!shown) return 0;
    const Sounds when = sounds(s.state);
    bool due = false;
    if (when == Sounds::kEveryLoop && n > heard_) due = true, heard_ = n;
    if (when == Sounds::kOnce && !once_ && into >= onceAt(s.state)) due = true, once_ = true;
    if (!due) return 0;
    out[0] = {};
    out[0].clip = uint8_t(clipOf(s.state));
    out[0].duck = when == Sounds::kEveryLoop;
    return 1;
  }

  const render::FaceContext& context() const { return context_; }

 private:
  render::FaceSource src_;
  render::FaceContext context_;
  uint32_t lookAt_ = 0;
  int pace_ = 100;  // the working looks' pace now, in percent (FaceContext::pace)
  int pinned_ = -1;  // dbg.look's variation, until the look turns
  uint8_t last_[int(SceneState::kCount)] = {};
  uint32_t key_[12] = {};
  bool drawn_ = false;
  uint64_t design_ = 0;
  int64_t heard_ = -1;  // the loops of an every-loop design handed over
  bool once_ = false;   // a once design's cue handed over
};

}  // namespace testface
