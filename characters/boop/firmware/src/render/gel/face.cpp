#include "render/gel/face.h"

#include <cstdio>
#include <cstring>

#include "render/gel/lane.h"
#include "render/gel/profile.h"
#include "render/palette.h"
#include "render/gel/sounds.h"

namespace render::gel {

namespace {

// The engine's profile for a mood: calm for one it doesn't know.
int profileFor(Mood mood) {
  int p = expressionFromName(moodName(mood));
  return p < 0 ? slime::kCalm : p;
}

constexpr int kTakes = int(sizeof(slime::kRecipes[0][0]) / sizeof(slime::kRecipes[0][0][0]));

}  // namespace

const voice::EffectClips& GelFace::clips() const { return gel::clips(); }

const slime::Recipe& GelFace::recipe(Mood mood, SceneState state, int variant, Outcome outcome, StartCtx ctx) {
  return slime::kRecipes[profileFor(mood)][recipeState(state, outcome, ctx)]
                        [std::max(0, std::min(kTakes - 1, variant))];
}

void GelFace::reset(uint32_t t, linkkit::Rng&) {
  engine_ = std::make_unique<Engine>(kSeed);
  engine_->step(0);
  origin_ = lastTick_ = lookAt_ = t;
  source_ = {};
  pendingCount_ = 0;
  revision_ = cueRevision_ = 0;
}

// Power-on only, right after reset: the same engine with the board's seed.
void GelFace::seed(uint32_t s) {
  engine_ = std::make_unique<Engine>(s);
  engine_->step(0);
}

// The engine steps on the reference's 16 ms grid from the last reset.
bool GelFace::nextDue(uint32_t from, uint32_t to, uint32_t& at) const {
  uint32_t next = origin_ + ((from - origin_) / 16 + 1) * 16;
  if (int32_t(to - next) < 0) return false;
  at = next;
  return true;
}

void GelFace::restartCues() {
  ++revision_;
  pendingCount_ = 0;
}

void GelFace::advanceTo(uint32_t t) {
  if (t == lastTick_) return;
  Measure measure(gel::profile.engine);
  engine_->step(t - origin_);
  lastTick_ = t;
  int kept = 0;
  for (int i = 0; i < pendingCount_; ++i)
    if (t - pendingAt_[i] <= kCueWaitMs) {
      pending_[kept] = pending_[i];
      pendingAt_[kept++] = pendingAt_[i];
    }
  pendingCount_ = kept;
  for (const auto& cue : engine_->cues) {
    int clip = clipFor(cue.recipe, cue.variant);
    if (clip < 0 || pendingCount_ >= kMaxCues) continue;
    pendingAt_[pendingCount_] = t;
    voice::FxEvent& e = pending_[pendingCount_++];
    e.atMs = 0;
    e.clip = uint8_t(clip);
    e.gain = uint8_t(clamp(cue.gain * 255, 0, 255).integer());
    e.pitch = uint16_t((cue.pitch * 1000).integer());
    e.duck = !cue.protectedCue;  // needs you's, a finish's and an error's stay up under a line
  }
}

void GelFace::step(uint32_t t, linkkit::Rng&, unsigned due) {
  if (due) advanceTo(t);
}

// Compares without building the engine's facts, so an unchanged state
// (every tick's sync) allocates nothing.
bool GelFace::factsChanged(const FaceContext& c) const {
  const auto& old = engine_->router.facts;
  char id[12];
  std::snprintf(id, sizeof id, "%lu", (unsigned long)c.attentionId);
  return old.base != c.base || old.act != c.act || old.attention.on != c.attention || old.attention.id != id ||
         old.attention.agent != c.agent || old.attention.project != c.project || old.attention.name != c.thread ||
         old.attention.more != c.more;
}

void GelFace::sync(const FaceSource& source, const FaceContext& context, uint32_t t) {
  advanceTo(t);
  Measure measure(gel::profile.sync);
  auto& e = *engine_;
  if (factsChanged(context)) {
    Facts f;
    f.base = context.base;
    f.act = context.act;
    f.attention = {context.attention, std::to_string(context.attentionId),
                   context.agent,     context.project,
                   context.thread,    context.more};
    const auto& old = e.router.facts.attention;
    // A request the alert hasn't shown: its knocks and ding are new.
    bool freshAttention = f.attention.on && (!old.on || old.id != f.attention.id || old.agent != f.attention.agent ||
                                             old.project != f.attention.project);
    if (freshAttention) restartCues();
    e.setFacts(f);
  }
  e.setMood(expressionFromName(moodName(context.mood)));
  bool timeout = source.look == SceneState::kNoApp;
  if (timeout != e.router.timedOut) e.linkTimedOut(timeout);
  const int borrowed = context.borrowed ? expressionFromName(moodName(source.mood)) : -1;
  bool nextMoment = source.anim != Anim::kNone && (source.anim != source_.anim || source.at != source_.at);
  if (nextMoment) {
    // Behaviour times the moment (its loops, its line), so the engine
    // holds it until the source moves on.
    Request r;
    r.anim = source.anim;
    r.hasId = true;
    r.id = source.id ? std::to_string(source.id) : "local-" + std::to_string(source.at);
    r.loops = source.loops;
    r.outcome = source.outcome;
    r.ctx = source.ctx;
    r.variant = source.animVariant;
    r.hold = true;
    r.expression = borrowed;
    r.say = true;
    e.oneShot(r);
    restartCues();
  } else if (source.anim == Anim::kNone && source_.anim != Anim::kNone && !timeout) {
    e.clearTransient();
    restartCues();
  }
  e.holdExpression(borrowed);
  if (source.state() != source_.state()) {
    lookAt_ = t;
    restartCues();
  }
  source_ = source;
}

// The engine's shuffle bag for the moment, drawn from copies: a call
// refused after its pick (Device::refuse) leaves the bag and the engine's
// randomness as they were. started draws the same take for real.
uint8_t GelFace::pick(Anim a, Mood mood, int, Outcome outcome, StartCtx ctx, linkkit::Rng&) const {
  Bag bag = engine_->scenes.bags[slime::kProfile[profileFor(mood)].canonical][recipeState(animState(a), outcome, ctx)];
  Random random = engine_->random;
  return uint8_t(bag.next(random));
}

void GelFace::started(Anim a, Mood mood, uint8_t, Outcome outcome, StartCtx ctx) {
  engine_->scenes.bags[slime::kProfile[profileFor(mood)].canonical][recipeState(animState(a), outcome, ctx)].next(
      engine_->random);
}

int GelFace::variants(Mood, SceneState) const { return kTakes; }

uint32_t GelFace::loopMs(Mood mood, SceneState state, int variant) const {
  return uint32_t(F(recipe(mood, state, variant, Outcome::kNone, StartCtx::kNone).duration).integer());
}

// A line over a moment starts at its first result contact (the card or
// the alert), less the speaker's lead.
uint32_t GelFace::voiceMs(Mood mood, SceneState state, int variant) const {
  const auto& r = recipe(mood, state, variant, Outcome::kNone, StartCtx::kNone);
  for (int i = 0; i < r.count; ++i)
    if (r.contacts[i].kind >= kAlert) return uint32_t(F(r.contacts[i].at).integer() + 70);
  return 0;
}

uint32_t GelFace::holdMs(Mood, int loops, uint32_t) const {
  uint32_t loop = uint32_t(F(engine_->scenes.recipe.duration).integer()),
           age = uint32_t(F(engine_->scenes.ageMs).integer());
  return loop * loops - age % loop;
}

int GelFace::cues(const SceneShow*, voice::FxEvent* out, bool& changed) {
  changed = revision_ != cueRevision_;
  cueRevision_ = revision_;
  int count = pendingCount_;
  for (int i = 0; i < count; ++i) out[i] = pending_[i];
  pendingCount_ = 0;
  return count;
}

// The lane is drawn at the panel's size too (render/gel/lane.h), so the
// canvas is left to the test pattern.
bool GelFace::draw(Canvas&, Surface* native, const SceneShow& show, uint32_t, const char* bubble, const Strip& strip,
                   bool) {
  if (!native || !native->pixels) return false;
  paintFrame(*native, *engine_, show.mouthOpen, show.dy, bubble, strip);
  return true;
}

int GelFace::profile(char* out, size_t n, uint32_t frames) {
  auto& p = gel::profile;
  if (!frames) return 0;
  int written = std::snprintf(
      out, n, "gel_parts engine_us=%lu sync_us=%lu body_us=%lu art_us=%lu props_us=%lu clear_us=%lu lane_us=%lu\n",
      (unsigned long)(p.engine / frames), (unsigned long)(p.sync / frames), (unsigned long)(p.body / frames),
      (unsigned long)(p.art / frames), (unsigned long)(p.props / frames), (unsigned long)(p.clear / frames),
      (unsigned long)(p.lane / frames));
  p = Profile{};
  return written > 0 && size_t(written) < n ? written : 0;
}

}  // namespace render::gel
