#include "render/gel/face.h"

#include <cstdio>
#include <cstring>

#include "render/gel/profile.h"
#include "render/maths.h"
#include "render/palette.h"
#include "render/gel/layers.h"
#include "render/gel/sounds.h"
#include "rig_tables.h"  // the staged pack's (characters/charactergen.py)

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
  int row = recipeState(state, outcome, ctx);
  // A finish timed without its outcome: its fourth take is a success's.
  if (state == SceneState::kTaskComplete && variant >= takes(row)) row = recipeState(state, Outcome::kSuccess, ctx);
  return take(profileFor(mood), row, std::max(0, std::min(takes(row) - 1, variant)));
}

void GelFace::reset(uint32_t t, linkkit::Rng&) {
  engine_ = std::make_unique<Engine>(kSeed);
  engine_->step(0);
  origin_ = lastTick_ = lookAt_ = t;
  engineMs_ = engineFrac_ = 0;
  pace_ = 100;
  source_ = {};
  finger_ = false;  // the new engine has no drag: a finger still down grabs it afresh
  pendingCount_ = 0;
  revision_ = cueRevision_ = 0;
  mixer_.reset(0, 0, nullptr);
  layers_ = {};
  occasion_ = cueing_ = nullptr;
  passGeneration_ = passIteration_ = -1;
}

// Power-on only, right after reset: the same engine with the board's seed.
void GelFace::seed(uint32_t s) {
  engine_ = std::make_unique<Engine>(s);
  engine_->step(0);
}

// The engine steps on a 16 ms grid from the last reset.
bool GelFace::nextDue(uint32_t from, uint32_t to, uint32_t& at) {
  uint32_t next = origin_ + ((from - origin_) / 16 + 1) * 16;
  if (after(next, to)) return false;
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
  const uint64_t scaled = uint64_t(t - lastTick_) * pace_ + engineFrac_;
  engineMs_ += uint32_t(scaled / 100);
  engineFrac_ = uint32_t(scaled % 100);
  // The cues the clip playing crosses sound with this step's contacts.
  if (cueing_) {
    const char* names[Engine::kClipCues];
    const int n = rig::crossed(*cueing_, cueAge_, cueAge_ + (t - lastTick_), names, Engine::kClipCues);
    for (int i = 0; i < n; ++i) engine_->contact(names[i]);
    cueAge_ += t - lastTick_;
    if (cueAge_ >= cueing_->ms) cueing_ = nullptr;
  }
  engine_->step(engineMs_);
  mixer_.advance(t - lastTick_);
  lastTick_ = t;
  occasions(t);
  showLayers(t);
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

void GelFace::showLayers(uint32_t t) {
  const Contents now = layerContents(*engine_);
  layers_.show(rig::Layer::kScene, now.scene, t);
  layers_.show(rig::Layer::kWorn, now.worn, t);
  layers_.show(rig::Layer::kHat, now.hat, t);
  layers_.show(rig::Layer::kAir, now.air, t);
  layers_.show(rig::Layer::kBeside, now.beside, t);
}

void GelFace::occasions(uint32_t t) {
  const Engine& e = *engine_;
  const Route& route = e.scenes.route;
  if (occasion_ && !after(occasionEnds_, t)) occasion_ = nullptr;
  if (source_.anim != SceneState::kNone || route.moment || route.state != e.router.facts.look()) {
    if (occasion_) mixer_.stop(*occasion_);
    occasion_ = nullptr;
    return;
  }
  if (e.scenes.generation == passGeneration_ && e.scenes.iteration == passIteration_) return;
  passGeneration_ = e.scenes.generation, passIteration_ = e.scenes.iteration;
  const rig::Look* look = rig::kRig.look(e.router.facts.base);
  const int fit = look && !occasion_ ? look->fitting(e.scenes.when, e.scenes.lookMs) : 0;
  // The engine's randomness is drawn on only while one fits.
  if (!fit || engine_->random.unit() >= F::ratio(rig::kOccasionPct, 100)) return;
  occasion_ = look->fitting(e.scenes.when, e.scenes.lookMs, engine_->random.index(fit));
  occasionEnds_ = t + occasion_->ms;
  play(*occasion_);
}

void GelFace::play(const rig::Clip& clip) {
  mixer_.play(clip);
  cueing_ = &clip;
  cueAge_ = 0;
}

// The finger in the engine's body units, where the dome stands: kPxPerUnit
// canvas pixels a unit, its middle at (kMidX, kMidY), and y up, as the
// engine's is and the canvas's isn't. The panel draws the canvas half as
// large again, so the dome, 128 panel pixels a unit at its middle, goes
// with the finger.
void GelFace::finger(bool down, int x, int y) {
  if (!down) {
    letGo(0, 0);
    return;
  }
  if (!finger_) {
    finger_ = true, fingerX_ = x, fingerY_ = y;
    // Where on the dome, -1 … 1 across its half-width and half-height.
    engine_->dragStart(F(x - kMidX) / kPxPerUnit / q(1.1), F(kMidY - y) / kPxPerUnit / q(.91));
    return;
  }
  engine_->dragMove(F(x - fingerX_) / kPxPerUnit, F(fingerY_ - y) / kPxPerUnit, F(0));
}

void GelFace::letGo(int vx, int vy) {
  if (finger_) engine_->dragEnd(F(vx) / kPxPerUnit, F(-vy) / kPxPerUnit, F(0));
  finger_ = false;
}

// At every stop of Behaviour's, on the grid or not.
void GelFace::step(uint32_t t, linkkit::Rng&) {
  advanceTo(t);
  if (!stream_ || !stream_->drawn(t) || !stream_->call.live) return;
  const auto& c = stream_->call;
  if (c.at != landedAt_) landed_ = false, landedAt_ = c.at;
  if (!landed_ && int32_t(t - c.at) >= int32_t(callFlightMs(c.gag))) {
    landed_ = true;
    land(c.gag);
  }
}

// What the body does as a word lands, in the pull's body units a second:
// knocked back and dazed by a failure, longer up the ladder; a squash as a
// word sinks in or a bit of hail lands; stretched up by a shrug or a cheer.
void GelFace::land(CallGag gag) {
  auto& e = *engine_;
  // Toward the word's side: its lane's half of the screen.
  const int column = stream_ ? stream_->column(stream_->call.slot) : 0;
  const F side = stream_ && 2 * column + 1 >= stream_->laneCount ? F(1) : F(-1);
  switch (callMove(gag)) {
    case CallMove::kHit:
      // A failure's knock; its dizzy eyes are the stream's to draw. Your
      // no makes it flinch and squeeze its eyes; a timeout lands on it
      // half asleep.
      if (gag == CallGag::kNo) e.jolt(q(-1.5), q(2.4), q(-2), q(.6), 450);
      else if (gag == CallGag::kTimeout) e.jolt(q(.6), q(2.8), q(-2), q(.9), 700);
      else e.jolt(q(1.2), q(3.2), q(-3));
      break;
    case CallMove::kTopple: e.jolt(q(-1.4), q(3.4), q(-2.6)); break;
    case CallMove::kSink:
    case CallMove::kArrive: e.jolt(0, q(1.8), 0); break;
    case CallMove::kBack: e.jolt(0, q(1.6), 0); break;
    case CallMove::kStamp: e.jolt(side * q(.4), q(1.2), 0); break;
    case CallMove::kPlane: e.jolt(side * q(.9), q(1.2), 0); break;
    case CallMove::kLook:
    case CallMove::kPhone:
    case CallMove::kPage: e.jolt(side * q(.8), q(-.4), q(.6)); break;
    case CallMove::kStir: e.jolt(q(.9), 0, q(.6)); break;
    case CallMove::kHelper: e.jolt(side * q(-.6), q(-.6), 0); break;
    case CallMove::kShatter: e.jolt(0, q(1.4), 0); break;
    case CallMove::kHail: e.jolt(q(.4), q(1.2), 0); break;
    case CallMove::kShrug:
    case CallMove::kPoof: e.jolt(0, q(-1.6), 0); break;
    case CallMove::kRocket:
    case CallMove::kCombo: e.jolt(0, q(-1.8), 0); break;
    case CallMove::kCheer: e.jolt(0, q(-2.6), 0); break;
    case CallMove::kDesk: e.jolt(q(-.6), 0, q(1)); break;
    // The whole turn's: a gulp at its end; the cube's thud; buried, its
    // lids heavy; leaning in to poke a frozen word; a blink as all goes off.
    case CallMove::kGather: e.jolt(0, q(1.6), q(.6)); break;
    case CallMove::kCompact: e.jolt(q(.6), q(1.2), 0); break;
    case CallMove::kBuried: e.jolt(0, q(1.8), 0, q(.5), 900); break;
    case CallMove::kFreeze: e.jolt(side * q(.8), 0, q(.8)); break;
    case CallMove::kDrop: e.jolt(0, q(.6), 0, q(.6), 300); break;
  }
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
  pace_ = context.pace;
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
  e.setOccasion(context.when, context.lookMs);
  // The Mac's borrowed expression, else a gesture's or a notice's own face
  // while it plays.
  int borrowed = context.borrowed ? expressionFromName(moodName(source.mood)) : -1;
  if (borrowed < 0 && source.anim == SceneState::kGesture)
    borrowed = slime::kGestureFaces[std::min<int>(source.animVariant, slime::kGestureCount - 1)];
  if (borrowed < 0 && source.anim == SceneState::kNotice)
    borrowed = slime::kNoticeFaces[std::min<int>(source.animVariant, slime::kNoticeCount - 1)];
  bool nextMoment = source.anim != SceneState::kNone && (source.anim != source_.anim || source.at != source_.at);
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
    if (const rig::Clip* clip = rig::kRig.clip(stateName(source.anim))) play(*clip);
  } else if (source.anim == SceneState::kNone && source_.anim != SceneState::kNone && !timeout) {
    e.clearTransient();
    restartCues();
  }
  e.holdExpression(borrowed);
  if (source.state() != source_.state()) {
    lookAt_ = t;
    restartCues();
  }
  source_ = source;
  showLayers(t);
}

// The engine's shuffle bag for the moment, drawn from copies: a call
// refused after its pick (Device::refuse) leaves the bag and the engine's
// randomness as they were. started draws the same take for real.
uint8_t GelFace::pick(SceneState a, Mood mood, int wanted, Outcome outcome, StartCtx ctx, linkkit::Rng&) const {
  // A gesture's take is the gesture asked for (from 1), never dealt.
  if (a == SceneState::kGesture) return uint8_t(wanted > 0 && wanted <= slime::kGestureCount ? wanted - 1 : 0);
  const int row = recipeState(a, outcome, ctx);
  auto bag = engine_->scenes.bags[slime::kProfile[profileFor(mood)].canonical][row];
  Random random = engine_->random;
  return uint8_t(bag.next(random, takes(row)));
}

void GelFace::started(SceneState a, Mood mood, uint8_t, Outcome outcome, StartCtx ctx) {
  if (a == SceneState::kGesture) return;
  const int row = recipeState(a, outcome, ctx);
  engine_->scenes.bags[slime::kProfile[profileFor(mood)].canonical][row].next(engine_->random, takes(row));
}

int GelFace::variants(Mood, SceneState s) const { return s == SceneState::kGesture ? slime::kGestureCount : kTakes; }

uint32_t GelFace::loopMs(Mood mood, SceneState state, int variant) const {
  return uint32_t(F(recipe(mood, state, variant, Outcome::kNone, StartCtx::kNone).duration).integer());
}

// A line over a moment starts at its first result contact (the card or
// the alert), less the speaker's lead.
uint32_t GelFace::voiceMs(Mood mood, SceneState state, int variant) const {
  const auto& r = recipe(mood, state, variant, Outcome::kNone, StartCtx::kNone);
  for (int i = 0; i < r.count; ++i)
    if (reveals(r.contacts[i].kind)) return uint32_t(F(r.contacts[i].at).integer() + 70);
  return 0;
}

uint32_t GelFace::holdMs(Mood, int loops, uint32_t) const {
  uint32_t loop = uint32_t(F(engine_->scenes.recipe.duration).integer()),
           age = uint32_t(F(engine_->scenes.ageMs).integer());
  return loop * loops - age % loop;
}

int GelFace::cues(uint32_t, bool, voice::FxEvent* out, bool& changed) {
  changed = revision_ != cueRevision_;
  cueRevision_ = revision_;
  int count = pendingCount_;
  for (int i = 0; i < count; ++i) out[i] = pending_[i];
  pendingCount_ = 0;
  return count;
}

// The lane is drawn at the panel's size too (render/gel/lane.h), so the
// canvas is left to the test pattern.
bool GelFace::draw(Canvas&, Surface* native, const SceneShow& show, uint32_t t, const char* bubble,
                   const SignShow& sign, const Strip& strip, bool) {
  if (!native || !native->pixels) return false;
  paintFrame(*native, *engine_, show.mouthOpen, show.dy, bubble, sign, strip, mixer_.channels(), &layers_, lastTick_,
             stream_, t);
  return true;
}

int GelFace::profile(char* out, size_t n, uint32_t frames) {
  auto& p = gel::profile;
  if (!frames) return 0;
  int written = std::snprintf(
      out, n,
      "gel_parts engine_us=%lu sync_us=%lu body_us=%lu art_us=%lu layers_us=%lu props_us=%lu clear_us=%lu "
      "lane_us=%lu stream_us=%lu\n",
      (unsigned long)(p.engine / frames), (unsigned long)(p.sync / frames), (unsigned long)(p.body / frames),
      (unsigned long)(p.art / frames), (unsigned long)(p.layers / frames), (unsigned long)(p.props / frames),
      (unsigned long)(p.clear / frames), (unsigned long)(p.lane / frames), (unsigned long)(p.stream / frames));
  p = Profile{};
  return written > 0 && size_t(written) < n ? written : 0;
}

}  // namespace render::gel
