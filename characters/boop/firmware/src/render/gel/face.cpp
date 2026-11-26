#include "render/gel/face.h"
#include "render/gel/card.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <iterator>

#include "render/gel/geometry.h"
#include "render/gel/invite.h"
#include "render/gel/moves.h"
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

constexpr int kTakes = int(sizeof(slime::kRecipes[0]) / sizeof(slime::kRecipes[0][0]));

// A clip of the staged pack's, which it must have: its lookup at start.
const rig::Clip& clipNamed(const char* name) {
  const rig::Clip* c = rig::kRig.clip(name);
  return c ? *c : *rig::kRig.clip("breathe");
}

// The tags of you at the Mac, as bits, found once at compile time: they're
// read every tick.
constexpr uint32_t bitOf(const char* name) { return 1u << tagIndex(name); }
constexpr uint32_t kCallTag = bitOf("oncall"), kScrollingTag = bitOf("scrolling"),
                   kMusicTag = bitOf("music"), kScrollUpTag = bitOf("scrollup"),
                   kScrollDownTag = bitOf("scrolldown"), kFastTag = bitOf("typingfast"),
                   kTypingTag = bitOf("typing"), kMacLeftTag = bitOf("macleft"),
                   kMacRightTag = bitOf("macright"), kMacUpTag = bitOf("macup"),
                   kSpeakingTag = bitOf("speaking");

}  // namespace

const voice::EffectClips& GelFace::clips() const { return gel::clips(); }

// By BeatBy's order: its own breath (no clip), typing, music, speaking, on
// a call.
const GelFace::Clips GelFace::clips_ = {
    {nullptr, &clipNamed("type-along"), &clipNamed("jam"), &clipNamed("speak-along"), &clipNamed("on-call")},
    &clipNamed("jam-desk"),
    &clipNamed("type-along-fast"),
    &clipNamed("stretch"),
    &clipNamed("look-around")};

slime::Recipe GelFace::recipe(Mood mood, SceneState state, int variant, Outcome outcome) {
  if (state == SceneState::kTaskComplete && outcome != Outcome::kFailure && isFinishVariant(variant))
    return finishRecipe(finishOf(variant));
  int row = recipeState(state, outcome);
  // A finish timed without its outcome: its fourth take is a success's.
  if (state == SceneState::kTaskComplete && variant >= takes(row)) row = recipeState(state, Outcome::kSuccess);
  return take(profileFor(mood), row, std::max(0, std::min(takes(row) - 1, variant)));
}

// Where the nose is now: up by its sign's hop (in the surface's rows, of
// 410, to the canvas's, of 240).
int GelFace::noseDrop() const { return -signHop_ * 240 / 410; }
void GelFace::reset(uint32_t t, linkkit::Rng&) {
  engine_ = std::make_unique<Engine>(kSeed);
  engine_->step(0);
  origin_ = lastTick_ = lookAt_ = t;
  engineMs_ = engineFrac_ = 0;
  pace_ = 100;
  source_ = {};
  replyAt_ = 0, replied_ = false;
  invite_ = {}, inviteAt_ = 0, inviteSounded_ = false;
  move_ = nullptr, moveMs_ = 0;
  finger_ = false;  // the new engine has no drag: a finger still down grabs it afresh
  signHop_ = 0;
  lean_ = Lean::kNone, breathTake_ = 0;
  pendingCount_ = 0;
  revision_ = cueRevision_ = 0;
  mixer_.reset(0, 0, nullptr);
  lively_.reset();
  layers_ = {};
  clip_ = cueing_ = base_ = idleMove_ = nullptr;
  idleMoveEnds_ = 0;
  pastime_ = lastPastime_ = Pastime::kNone;
  pastimeAt_ = pastimeEnds_ = stoppedAt_ = restUntil_ = 0;
  moved_ = false;
  movedAt_ = 0;
  pastimeLook_ = dealtLook_ = SceneState::kNone;
  stopped_ = false;
  dice_ = kSeed;
  transition_ = nullptr, transitionEnds_ = 0, lastBase_ = SceneState::kNone, alone_ = false, energy_ = Energy::kNormal;
  actAt_ = 0, actResult_ = ActResult::kRunning;
  along_ = rig::Ramp{};
  tapping_ = typed_ = false, typedAt_ = 0;
  fast_ = fastOn_ = typingTag_ = thought_ = false, thinkAt_ = 0;
  owners_ = {}, brisk_ = shut_ = rig::Ramp{}, signUp_ = false;
  beatClip_ = nullptr, called_ = false;
  for (int i = 0; i < 5; ++i) beatFrom_[i] = 0, beatOn_[i] = false;
  for (auto& m : marks_) m = rig::Ramp{};
  earSide_ = 1;
  pawPhaseQ_ = 0, fastSeen_ = 0;
  pointer_ = pointerNear_ = false, pointerX_ = pointerY_ = 0;
  for (int i = 0; i < kFollows; ++i) followTo_[i] = followBy_[i] = 0;
  lookTo_ = lookBy_ = 0;
  gaze_.reset();
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

const void* GelFace::assets(size_t& bytes) const { return materialTexels(bytes); }
void GelFace::readAssetsFrom(const void* copy) { readMaterialFrom(copy); }
void GelFace::color(int index) { bodyColor(index); }

void GelFace::restartCues() {
  ++revision_;
  pendingCount_ = 0;
}

void GelFace::advanceTo(uint32_t t) {
  if (t == lastTick_) return;
  const uint32_t dt = t - lastTick_;
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
  // Idle's mood move, as its acting deals it: the mood's rig clip, which
  // fades out as acting is held off (anything but idle, a finger), as its
  // own takes stop.
  if (const char* id = engine_->acting.move) {
    engine_->acting.move = nullptr;
    if (const rig::Clip* clip = rig::kRig.clip(id)) play(*clip), idleMove_ = clip, idleMoveEnds_ = t + clip->ms;
  }
  if (idleMove_ && (!after(idleMoveEnds_, t) || engine_->acting.suppressed)) {
    if (after(idleMoveEnds_, t)) mixer_.stop(*idleMove_);
    idleMove_ = nullptr;
  }
  mixer_.advance(t - lastTick_);
  lastTick_ = t;
  passTime(t);
  showBase();
  showTransition(t);
  showLayers(t);
  answerAct(t);
  showAlong(t);
  pawPhase(dt);
  engine_->typingFast = fast_, engine_->typingPhase = int(pawPhaseQ_ / 1000);
  showWithYou(t);
  followLean(dt);
  showGaze(t);
  int kept = 0;
  for (int i = 0; i < pendingCount_; ++i)
    if (t - pendingAt_[i] <= kCueWaitMs) {
      pending_[kept] = pending_[i];
      pendingAt_[kept++] = pendingAt_[i];
    }
  pendingCount_ = kept;
  breathe(t);
  showInvite(t);
  showMove();
  showLively(dt, t);
  for (const auto& cue : engine_->cues) {
    int clip = clipFor(cue.recipe, cue.variant);
    if (clip < 0 || pendingCount_ >= kMaxCues) continue;
    pendingAt_[pendingCount_] = t;
    voice::FxEvent& e = pending_[pendingCount_++];
    e.atMs = 0;
    e.clip = uint8_t(clip);
    e.gain = uint8_t(clamp(cue.gain * 255, 0, 255).integer());
    e.pitch = uint16_t((cue.pitch * 1000).integer());
    e.duck = !cue.protectedCue;  // needs you's and a finish's stay up under a line
  }
}

void GelFace::showLayers(uint32_t t) {
  const Contents now = layerContents(*engine_);
  layers_.show(rig::Layer::kBeside, now.beside, t);
}

uint32_t GelFace::roll(uint32_t n) {
  dice_ ^= dice_ << 13, dice_ ^= dice_ >> 17, dice_ ^= dice_ << 5;  // xorshift32
  return n ? dice_ % n : 0;
}

void GelFace::endPastime(uint32_t t, bool early) {
  if (early && clip_) mixer_.stop(*clip_);
  // A bit at the desk gives way as a clip does; idle, the engine stops it.
  if (early && pastimeLook_ == SceneState::kWorking) engine_->stopBit();
  // One stopped early fades out what it draws; a bit's or a take's draws
  // nothing, and the engine stops it itself as the look gives way.
  stopped_ = early && clip_;
  stoppedAt_ = t;
  if (!stopped_) pastime_ = Pastime::kNone;
  clip_ = nullptr;
  restUntil_ = t + kRestMinMs + roll(kRestMaxMs - kRestMinMs);
}

bool GelFace::showsLook(SceneState anim, SceneState& look) const {
  const Engine& e = *engine_;
  const bool needsYou = e.router.facts.attention.on;
  look = needsYou ? SceneState::kNeedsYou : e.router.facts.base;
  const Route& route = e.scenes.route;
  return anim == SceneState::kNone && !route.reaction && !invite_.shows() &&
         route.state == (needsYou ? SceneState::kNeedsYou : e.router.facts.look());
}

void GelFace::showBase() {
  SceneState look;
  const bool shows = showsLook(source_.anim, look);
  const rig::Look* l = rig::kRig.look(look);
  // The activity's pose, else the typing pose's variant for the tier.
  const rig::Clip* clip = nullptr;
  if (l && shows) {
    if (look == SceneState::kWorking) clip = l->acted(engine_->router.facts.look());
    if (!clip) clip = l->tiered(engine_->scenes.when);
  }
  if (clip != base_) mixer_.setLook(base_ = clip, kPoseMs);
}

// A clip for the way from one Doing to another: half a second to a second,
// over the new look, which has already come, so it delays nothing. Whatever
// takes the face (a reaction, a needs-you, a finger, a word forward) cuts
// through it, and with one of those already up it doesn't start; nor with
// the Mac gone, which is no Doing changing.
void GelFace::showTransition(uint32_t t) {
  const Engine& e = *engine_;
  const auto& facts = e.router.facts;
  const SceneState base = facts.base;
  const bool taken = finger_ || facts.attention.on || e.scenes.route.reaction || e.router.reacting || e.router.expression >= 0 ||
                     source_.anim != SceneState::kNone || alone_ || (stream_ && stream_->call.live);
  const char* name = nullptr;
  if (lastBase_ != SceneState::kNone && base != lastBase_) {
    if (base == SceneState::kAsleep) name = "to-sleep";
    else if (base == SceneState::kWorking && lastBase_ == SceneState::kIdle) name = "to-work";
    else if (base == SceneState::kIdle && lastBase_ == SceneState::kWorking) name = "to-rest";
  }
  lastBase_ = base;
  if (transition_ && (taken || !after(transitionEnds_, t))) {
    if (taken) {
      if (cueing_ == transition_) cueing_ = nullptr;
      mixer_.stop(*transition_);
    }
    transition_ = nullptr;
  }
  if (taken || !name) return;
  if (const rig::Clip* clip = rig::kRig.clip(name)) {
    if (transition_) mixer_.stop(*transition_);
    transition_ = clip, transitionEnds_ = t + clip->ms;
    play(*clip);
    holdGestures(clip->ms);
  }
}

// A work act's result, once, as its sign changes: a pleased hop at a pass,
// a flinch at a fail. Not while something else has the body.
void GelFace::answerAct(uint32_t t) {
  if (!stream_) return;
  const Stream::ActNow act = stream_->actNow(t);
  const uint32_t at = act.shows() ? stream_->act.at : 0;
  const ActResult result = act.shows() ? act.result : ActResult::kRunning;
  const bool fresh = result != ActResult::kRunning && (at != actAt_ || actResult_ == ActResult::kRunning);
  actAt_ = at, actResult_ = result;
  if (!fresh || finger_ || !bodyFree()) return;
  if (result == ActResult::kPass) engine_->jolt(0, q(-1.6), 0);
  else engine_->jolt(q(-1.2), q(2.4), q(-2), q(.6), 450);
}

void GelFace::passTime(uint32_t t) {
  if (stopped_ && !within(t, stoppedAt_, rig::kFadeMs)) stopped_ = false, pastime_ = Pastime::kNone;
  if (playing() && !after(pastimeEnds_, t)) endPastime(t, false);
  SceneState look;
  const bool shows = showsLook(source_.anim, look);
  if (playing() && (!shows || look != pastimeLook_)) endPastime(t, true);
  // A new look rests before its first.
  if (look != dealtLook_) dealtLook_ = look, restUntil_ = t + kRestMinMs + roll(kRestMaxMs - kRestMinMs);
  // Holding a card, its hands are full: no pastime is dealt over it.
  if (card_.on && playing()) endPastime(t, true);
  // Nor one over its keyboard, out to type along with you, nor on a call,
  // while you speak or in the scroll's look. Music holds none off: it may
  // play for hours, and the jam's beat is there again after each.
  const Owners& o = owners_;
  const bool busy = finger_ || card_.on || along_.target() || (o.beatShows && o.beat >= BeatBy::kSpeaking) ||
                    o.eyes == EyesBy::kScroll || (stream_ && stream_->drawn(t) && stream_->call.live);
  if (!shows || pastime_ != Pastime::kNone || busy || after(restUntil_, t)) return;
  deal(look, t);
}

void GelFace::deal(SceneState look, uint32_t t) {
  const Engine& e = *engine_;
  const uint32_t when = e.scenes.when, lookMs = e.scenes.lookMs;
  struct Option {
    const PastimeInfo* row;
    int rank;  // the newest is the highest
  } options[kPastimeCount];
  int n = 0;
  // A move waits its gap.
  const bool moveWaits = moved_ && within(t, movedAt_, kMoveGapMs);
  // At work, off typing only a stretch: the other poses have the eyes and
  // the paws (looking, running, waiting), and a melt from one would leave
  // the screen. Typing, its paws stay on the keys through each.
  const SceneState desk = e.scenes.route.state;
  const bool types = isDesk(desk) && activityOf(desk) == Activity::kTyping;
  const bool tired = e.energy == Energy::kTired;
  for (const auto& p : kPastimes) {
    // Tired, idle: a yawn now and then, whatever the tier, and the newest.
    const bool yawn = tired && look == SceneState::kIdle && p.id == Pastime::kYawn;
    if (p.look != look || !(fits(p, when, lookMs) || yawn) || (p.move && moveWaits) || !hasBody(p)) continue;
    if ((look == SceneState::kWorking && !types && p.id != Pastime::kStretch))
      continue;
    // At the desk it yawns only tired: at night, or deep in a long stretch.
    if (p.id == Pastime::kDeskYawn && !tired) continue;
    // The highest tier, then the longest wait, is the newest; one that
    // needs a tag is newer than any while it fits.
    options[n++] = {&p, yawn ? 2000000 : (p.tag ? 1000000 : p.tier * 100000) + p.afterS};
  }
  // Never the one dealt last, while there's another.
  if (n > 1)
    for (int i = 0; i < n; ++i)
      if (options[i].row->id == lastPastime_) {
        options[i] = options[--n];
        break;
      }
  if (!n) return;
  int top = 0, newest = 0;
  for (int i = 0; i < n; ++i) top = std::max(top, options[i].rank);
  for (int i = 0; i < n; ++i) newest += options[i].rank == top;
  // The newest kNewestPct of the time, an older one the rest.
  const bool fresh = newest == n || int(roll(100)) < kNewestPct;
  int pick = int(roll(uint32_t(fresh ? newest : n - newest)));
  const Option* chosen = nullptr;
  for (int i = 0; i < n && !chosen; ++i)
    if ((options[i].rank == top) == fresh && pick-- == 0) chosen = &options[i];
  start(*chosen->row, look, t);
}

void GelFace::start(const PastimeInfo& p, SceneState look, uint32_t t) {
  if (playing()) endPastime(t, true);
  pastime_ = lastPastime_ = p.id;
  clip_ = nullptr;
  if (p.move) movedAt_ = t, moved_ = true;
  stopped_ = false;
  pastimeLook_ = dealtLook_ = look;
  pastimeAt_ = t;
  uint32_t ms = 1;
  if (const rig::Clip* clip = clipOf(p)) {
    clip_ = clip;
    ms = clip->ms;
    play(*clip);
    holdGestures(clip->ms);
  } else if (const int gag = bitOf(p); gag >= 0) {
    engine_->playBit(gag);
    ms = uint32_t(F(slime::kGags[gag].gesture.duration * 1000).integer());
  } else if (const int take = takeOf(p); take >= 0) {
    engine_->playTake(take);
    // The engine's time runs at the look's pace.
    ms = uint32_t(F(slime::kPastimeTakes[take].recipe.duration).integer()) * 100 / uint32_t(pace_);
  }
  pastimeEnds_ = t + std::max<uint32_t>(1, ms);
}

void GelFace::holdGestures(uint32_t ms) {
  auto& acting = engine_->acting;
  acting.nextPerformance = max(acting.nextPerformance, engine_->motion.time + int(ms / 1000) + 2);
}

void GelFace::playPastime(Pastime p, uint32_t t) {
  const PastimeInfo& i = info(p);
  if (hasBody(i)) start(i, i.look, t);
}

void GelFace::reply(const char* name) {
  char clip[24];
  std::snprintf(clip, sizeof(clip), "reply-%s", name);
  const rig::Clip* c = rig::kRig.clip(clip);
  if (!c) c = rig::kRig.clip(name);
  if (c) play(*c);
}

bool GelFace::playPastime(const char* name, uint32_t t) {
  // The row for the look showing, else the first by that name.
  SceneState look;
  showsLook(source_.anim, look);
  const PastimeInfo* row = nullptr;
  for (const PastimeInfo& p : kPastimes)
    if (!std::strcmp(p.name, name) && (!row || p.look == look)) row = &p;
  if (!row) return false;
  advanceTo(t);
  playPastime(row->id, t);
  return true;
}

// Whether the working look's pose is typing's: no activity's own clip
// (looking, running, waiting) has the body and the eyes.
bool GelFace::typingPose() const {
  const rig::Look* l = rig::kRig.look(SceneState::kWorking);
  return !(l && l->acted(engine_->router.facts.look()));
}

// What's true now for who has what (owners.h): what has the body over its
// own look, whether that look is idle or work's with the Mac here (going
// with you rides only on it, the engine's documentation/design/theory.md,
// "One body, three channels"), and you at the Mac.
WhatsTrue GelFace::truths(uint32_t t, SceneState* lookOut) const {
  const Engine& e = *engine_;
  const uint32_t when = e.scenes.when;
  SceneState look;
  const bool shows = showsLook(source_.anim, look);
  if (lookOut) *lookOut = look;
  WhatsTrue f;
  f.moment = source_.anim != SceneState::kNone || e.scenes.route.reaction || invite_.shows() ||
             (stream_ && stream_->drawn(t) && stream_->call.live);
  f.finger = finger_;
  f.needsYou = shows && look == SceneState::kNeedsYou;
  f.listening = e.router.listening;
  f.pastime = playing() || transition(t) || e.acting.current();
  f.place = shows && (look == SceneState::kIdle || look == SceneState::kWorking) && !alone_;
  f.light = light(look);
  f.posed = look == SceneState::kWorking && !typingPose();
  f.desk = f.light || look == SceneState::kWorking;
  f.signUp = signUp_;
  f.keepsFace = slime::kKeepsFaceThroughGestures[e.emotion];
  f.call = when & kCallTag, f.speaking = when & kSpeakingTag, f.music = when & kMusicTag;
  f.typing = when & kTypingTag, f.pointer = pointer_, f.mac = when & (kMacLeftTag | kMacRightTag);
  // Only the way known: with none, nothing rather than a guess.
  f.scrolling = (when & kScrollingTag) && (when & (kScrollDownTag | kScrollUpTag));
  return f;
}

// Whether going with you is at its light size: at work in a pose of its
// own, or holding a card. The body is the work's then: the beat rides on
// it small, the eyes and the paws stay the pose's, and the mark shows.
bool GelFace::light(SceneState look) const {
  return card_.on || (look == SceneState::kWorking && !typingPose());
}

// Who has what this frame (owners.h), and typing along with you (face.h):
// while the keys have its hands, its paws type briskly with you. Idle, its
// keyboard comes out for it, and stays a little longer after you stop, its
// paws at rest, so a pause in your typing doesn't put the keyboard away and
// bring it back; at work the desk is out already, and its paws go back to
// the agents' soft typing.
void GelFace::showAlong(uint32_t t) {
  const Engine& e = *engine_;
  SceneState look;
  const WhatsTrue now = truths(t, &look);
  owners_ = whoHasWhat(now);
  const uint32_t when = e.scenes.when;
  const bool typing = now.typing;
  const bool was = tapping_;
  tapping_ = owners_.keys;
  brisk_.retarget(tapping_ && !now.light ? 1000 : 0, t);
  // Fast, its paws tap quicker (pawPhase), and its eyes open wider and it
  // hunches in (showWithYou). A flicker off shorter than kFastLingerMs
  // doesn't stop it.
  const bool fastNow = tapping_ && (when & kFastTag);
  if (fastNow) fastSeen_ = t;
  fast_ = fastNow || (fast_ && tapping_ && within(t, fastSeen_, kFastLingerMs));
  // A long stretch of typing along that you stop: it looks up at you, as
  // if thinking it over with you (render/gel/gaze.h).
  const uint32_t typingFrom = beatFrom_[int(BeatBy::kTyping)];
  if (!typing && typingTag_ && was && t - typingFrom >= Gaze::kThinkAfterMs) thought_ = true, thinkAt_ = t;
  typingTag_ = typing;
  const bool idle = now.place && look == SceneState::kIdle;
  const bool alone = tapping_ && idle;  // with its keyboard alone
  if (alone) typed_ = true, typedAt_ = t;
  const bool out = idle && typed_ && (alone || within(t, typedAt_, kAlongLingerMs));
  if (!out) typed_ = alone;
  if (along_.target() != (out ? 1000 : 0)) {
    along_.retarget(out ? 1000 : 0, t);
    // Put away: a rest before the next pastime, as a new look has.
    if (!out) restUntil_ = t + kRestMinMs + roll(kRestMaxMs - kRestMinMs);
  }
}

// Where the paws are in their beats, moved on by the time over the beat's
// length now (painter.h, briskLift): a change of pace changes only how
// fast it moves, so no paw snaps up as typing fast comes or goes.
void GelFace::pawPhase(uint32_t dt) {
  const uint64_t beat = uint64_t(fast_ ? kFastMs : kBriskMs) * 100;
  pawPhaseQ_ = (pawPhaseQ_ + uint64_t(dt) * uint64_t(pace_) * kBeat * 1000 / beat) % (2 * kBeat * 1000);
}

// With you at the Mac (face.h), as who has what says: the beat's clip, the
// eyes' look or follow, the jam's shut eyes, the one mark, and a move once
// as a call or the music ends.
void GelFace::showWithYou(uint32_t t) {
  const uint32_t when = engine_->scenes.when;
  const Owners& o = owners_;
  // When each beat's fact came: a beat covered runs on from there, unseen.
  const bool on[5] = {false, bool(when & kTypingTag), bool(when & kMusicTag), bool(when & kSpeakingTag),
                      bool(when & kCallTag)};
  const bool call = on[int(BeatBy::kCall)], musicStopped = beatOn_[int(BeatBy::kMusic)] && !on[int(BeatBy::kMusic)];
  for (int i = 0; i < 5; ++i) {
    if (on[i] && !beatOn_[i]) beatFrom_[i] = t;
    beatOn_[i] = on[i];
  }
  // As each ends: a stretch back up after a call, a look round as the
  // music stops. Not over anything else.
  if (called_ && !call) once(*clips_.stretch, t);
  else if (musicStopped && !call) once(*clips_.lookAround, t);
  called_ = call;
  // The beat's clip, the jam at the desk's size there, fading in over the
  // last from where its own beat has got to.
  const rig::Clip* clip = !o.beatShows                             ? nullptr
                          : o.beat == BeatBy::kMusic && o.small ? clips_.deskJam
                                                                   : clips_.beat[int(o.beat)];
  if (clip != beatClip_) {
    if (beatClip_) mixer_.stop(*beatClip_);
    if (clip) mixer_.play(*clip, kWithFadeMs, t - beatFrom_[int(o.beat)]);
    beatClip_ = clip;
  }
  const bool fast = o.beatShows && o.beat == BeatBy::kTyping && fast_;
  if (fast != fastOn_) fast ? mixer_.play(*clips_.fast) : mixer_.stop(*clips_.fast);
  fastOn_ = fast;
  // The engine's own idle gestures wait while it's with you.
  if (o.beatShows || o.eyes == EyesBy::kScroll) holdGestures(0);
  const int mac = (when & kMacLeftTag) ? -1 : (when & kMacRightTag) ? 1 : 0, side = mac < 0 ? -1 : 1;
  // The scroll's look: straight the way you scroll (followLean eases it).
  lookTo_ = o.eyes != EyesBy::kScroll ? 0 : (when & kScrollDownTag) ? 1000 : -1000;
  shut_.retarget(o.eyes == EyesBy::kJam ? 1000 : 0, t);
  // The one mark beside it, each fading in and out; the ear's on the Mac's
  // side, gone in before it comes out on the other.
  if (side != earSide_ && !marks_[int(MarkBy::kEar) - 1].value(t)) earSide_ = side;
  for (int i = 0; i < kMarks; ++i)
    marks_[i].retarget(int(o.mark) == i + 1 && (o.mark != MarkBy::kEar || side == earSide_) ? 1000 : 0, t);
  Engine::With& w = engine_->with;
  auto opacity = [&](MarkBy m) { return (marks_[int(m) - 1].value(t) * 255 + 500) / 1000; };
  w.ticks = opacity(MarkBy::kTicks), w.notes = opacity(MarkBy::kNotes), w.heard = opacity(MarkBy::kEar),
  w.muted = opacity(MarkBy::kMuted);
  w.side = mac ? mac : 1;
  w.notesMs = t - beatFrom_[int(BeatBy::kMusic)], w.heardMs = t - beatFrom_[int(BeatBy::kSpeaking)];
  // To the pointer while it has the eyes, a little more toward its reach,
  // and further at the edge nearest the board, reaching toward it.
  const bool up = !mac && (when & kMacUpTag);
  int* to = followTo_;
  for (int i = 0; i < kFollows; ++i) to[i] = 0;
  if (o.eyes == EyesBy::kPointer) {
    const int side = pointerX_ > 0 ? 1 : pointerX_ < 0 ? -1 : mac;
    if (pointerNear_) {
      to[kFollowLean] = side * kNearLean, to[kFollowSquash] = -kNearStretch;
      to[kFollowX] = side * Gaze::kPointerReach * kPointerSlide / 10;
      to[kFollowGazeX] = side * Gaze::kPointerReach * kPointerGaze;
      if (!side && up) to[kFollowGazeY] = -kScreenGazeUp;
    } else {
      // How far toward its reach, 0 to 1000: none in the middle.
      auto edge = [](int step) {
        const int e = std::clamp((std::abs(step) - kEdgeFrom) * 1000 / (kEdgeFull - kEdgeFrom), 0, 1000);
        return e * e / 1000 * (3000 - 2 * e) / 1000;
      };
      const int edgeX = edge(pointerX_), edgeY = edge(pointerY_);
      const int moreX = 1000 + edgeX * kEdgeMore / 1000, moreY = 1000 + edgeY * kEdgeMore / 1000;
      to[kFollowLean] = pointerX_ * kPointerLean * moreX / 1000;
      to[kFollowSquash] = pointerY_ < 0 ? pointerY_ * kPointerStretch * moreY / 1000 : 0;
      to[kFollowX] = pointerX_ * kPointerSlide * moreX / 10000;
      to[kFollowGazeX] = pointerX_ * kPointerGaze, to[kFollowGazeY] = pointerY_ * kPointerGazeUp;
      // The turn's to its own right, which is your right as its face goes round.
      to[kFollowTurn] = (pointerX_ > 0 ? 1 : -1) * edgeX * kEdgeTurn / 1000;
      to[kFollowNod] = (pointerY_ > 0 ? 1 : -1) * edgeY * kEdgeNod / 1000;
    }
  }
  // Speaking's beat leans the body to the Mac's side, but at the light size.
  if (o.beatShows && o.beat == BeatBy::kSpeaking && !o.light) to[kFollowLean] += side * kEarLean;
}

void GelFace::once(const rig::Clip& clip, uint32_t t) {
  if (!owners_.with || tapping_) return;
  play(clip);
  holdGestures(clip.ms);
  // No pastime straight after it.
  if (after(t + clip.ms + kRestMinMs, restUntil_)) restUntil_ = t + clip.ms + kRestMinMs;
}

// The lean and the stretch ease to where they're going, over about kLeanMs;
// the scroll's look in over about kLookInMs and back over kLookOutMs.
void GelFace::followLean(uint32_t dt) {
  auto follow = [&](int& by, int to, uint32_t ms) {
    const int64_t goal = int64_t(to) * 256;
    by = int(by + (goal - by) * int64_t(dt) / int64_t(dt + ms));
  };
  for (int i = 0; i < kFollows; ++i) follow(followBy_[i], followTo_[i], kLeanMs);
  follow(lookBy_, lookTo_, lookTo_ ? kLookInMs : kLookOutMs);
  engine_->faceNod = followBy_[kFollowNod] / 256 + lookBy_ / 256 * kLookNod / 1000;
  engine_->ear = ear();
}

bool GelFace::deskOut(uint32_t t) const { return engine_->scenes.desk.x > q(.5) || along_.value(t) > 500; }

int GelFace::ear(bool reach) const {
  // A card held keeps its hands. With the desk out the hand goes from its
  // keys and back to them, and the motion layer's springs carry it all the
  // way.
  const rig::Ramp& r = marks_[int(MarkBy::kEar) - 1];
  const int ear = card_.on ? 0 : earSide_ * (reach && deskOut(lastTick_) ? r.target() : r.value(lastTick_));
  return mixer_.channels()[rig::hand(ear > 0, rig::HandPart::kSize)] > 0 ? 0 : ear;
}

rig::Channels GelFace::channels() const {
  rig::Channels c = lively_.apply(clipChannels());
  addShake(c, currentMove(*engine_));
  return c;
}

// The motion layer, a step after what the clips ask now: the body's place
// the engine's own lift and slide too, in canvas px, and the face's lag for
// the painter.
void GelFace::showLively(uint32_t dt, uint32_t t) {
  Engine& e = *engine_;
  const F unit = F(kPxPerUnit);
  lively_.advance(dt, clipChannels(), e.life()[0] * unit, e.acting.slide.x * unit, deskOut(t));
  e.faceLagX16 = lively_.faceX16(), e.faceLagY16 = lively_.faceY16();
}

rig::Channels GelFace::clipChannels() const {
  rig::Channels c = mixer_.channels();
  auto add = [&](rig::Channel ch, int by) {
    const rig::ChannelInfo& info = rig::kChannelInfo[int(ch)];
    c[ch] = int16_t(std::clamp(int(c[ch]) + by, int(info.lo), int(info.hi)));
  };
  add(rig::Channel::kLean, followBy_[kFollowLean] / 256);
  add(rig::Channel::kSquash, followBy_[kFollowSquash] / 256);
  add(rig::Channel::kX, followBy_[kFollowX] / 256);
  add(rig::Channel::kGazeX, followBy_[kFollowGazeX] / 256);
  add(rig::Channel::kGazeY, followBy_[kFollowGazeY] / 256);
  add(rig::Channel::kTurn, followBy_[kFollowTurn] / 256);
  // The jam's eyes, shut while it has them.
  const int shut = kJamShut * shut_.value(lastTick_) / 1000;
  add(rig::Channel::kEyeOpenL, -shut);
  add(rig::Channel::kEyeOpenR, -shut);
  // The hand at its ear: out of the body as it grows, its palm opening.
  using rig::HandPart;
  if (const int reach = ear(true)) {
    const int side = reach > 0 ? 1 : -1, out = std::abs(reach);
    add(rig::hand(reach > 0, HandPart::kX), side * (kEarX - kEarFrom + kEarFrom * out / 1000));
    add(rig::hand(reach > 0, HandPart::kY), kEarY);
    add(rig::hand(reach > 0, HandPart::kSize), kEarSize * out / 1000);
  }
  if (const int open = ear()) add(rig::hand(open > 0, HandPart::kShape), std::abs(open));
  // The scroll's look: the eyes all the way, the body flatter looking down,
  // taller and up a little looking up.
  const int look = lookBy_ / 256;
  add(rig::Channel::kGazeY, look);
  add(rig::Channel::kSquash, look * (look > 0 ? kLookSquash : kLookStretch) / 1000);
  add(rig::Channel::kLift, look < 0 ? -look * kLookLift / 1000 : 0);
  // A move (an invite's, the knock): its clip at its time, over the rest;
  // and the body going a little with a stroke's pass.
  addMove(c, currentMove(*engine_), false);
  addInvitePass(c, engine_->invite);
  return c;
}

// The move playing sounds its cues as it crosses them, once each, where its
// scene doesn't (render/gel/moves.h): a clip new or started again from its
// own time, it's the cues from there.
void GelFace::showMove() {
  const MoveShow m = currentMove(*engine_);
  if (!m.on() || !m.sounds) {
    move_ = nullptr;
    return;
  }
  if (m.clip == move_ && !after(moveMs_, m.ms)) {
    const char* names[Engine::kClipCues];
    const int n = rig::crossed(*m.clip, moveMs_, m.ms, names, Engine::kClipCues);
    for (int i = 0; i < n; ++i) engine_->contact(names[i]);
  }
  move_ = m.clip, moveMs_ = m.ms;
}

bool GelFace::playClip(const char* name, uint32_t t) {
  const rig::Clip* clip = rig::kRig.clip(name);
  if (!clip) return false;
  advanceTo(t);
  play(*clip);
  return true;
}

// Where it looks by itself (render/gel/gaze.h): the facts now, and the
// eyes turned to the point they give, or let go.
void GelFace::showGaze(uint32_t t) {
  Engine& e = *engine_;
  SceneState look;
  GazeFacts f;
  showsLook(source_.anim, look);
  const uint32_t when = e.scenes.when;
  f.eyes = owners_.eyes;
  f.needsYou = look == SceneState::kNeedsYou;
  f.lookMs = e.scenes.lookMs;
  f.mac = (when & kMacLeftTag) ? -1 : (when & kMacRightTag) ? 1 : 0;
  f.up = !f.mac && (when & kMacUpTag);
  f.along = tapping_ && !light(look);
  f.thinking = thought_ && within(t, thinkAt_, Gaze::kThinkMs), f.thinkMs = t - thinkAt_;
  if (!f.thinking) thought_ = false;
  f.pointerNear = pointerNear_, f.pointerX = pointerX_, f.pointerY = pointerY_;
  const GazePoint p = gaze_.look(f, t);
  if (!p.on) return e.unattend();
  // The point, from the screen's px to the canvas's, as a finger's is.
  lookToward(p.x * 320 / 502, p.y * 240 / 410, false);
}

PastimeShow GelFace::pastimes(uint32_t t) const {
  PastimeShow s;
  // Light (a work pose of its own, a card held), its paws stay the pose's:
  // the body sways with you, the paws don't tap.
  SceneState look;
  const bool lit = showsLook(source_.anim, look) && light(look);
  s.keys = (along_.value(t) * 255 + 500) / 1000, s.tapping = tapping_ && !lit, s.fast = fast_ && !lit;
  s.brisk = brisk_.value(t);
  s.pawPhase = int(pawPhaseQ_ / 1000);
  if (pastime_ != Pastime::kNone) {
    s.playing = pastime_;
    s.age = t - pastimeAt_;
    s.ms = pastimeEnds_ - pastimeAt_;
    // In over 150 ms, out over its last 250; one stopped early, out over
    // the rig's fade from then.
    int fade = int(std::min<uint32_t>({255, s.age * 255 / 150, s.age < s.ms ? (s.ms - s.age) * 255 / 250 : 0}));
    if (stopped_) fade = fade * int(rig::kFadeMs - std::min(rig::kFadeMs, t - stoppedAt_)) / int(rig::kFadeMs);
    s.fade = std::max(0, fade);
  }
  return s;
}

// Whether the canvas's (x, y) is on the card it holds, a finger's width
// round it: the card's box on the surface, in the canvas's 320 by 240. Only
// a card the last frame drew: under a work act or a sign there's none.
bool GelFace::cardAt(int x, int y) const {
  if (!card_.on || !cardDrawn_ || !size_.width) return false;
  const Surface s{size_.width, size_.height, nullptr, size_.corner};
  const Box b = cardBox(s, card_);
  const int sx = x * size_.width / 320, sy = y * size_.height / 240;
  return sx >= b.x0 - 16 && sx < b.x1 + 16 && sy >= b.y0 - 12 && sy < b.y1 + CardLayout::kDotsRow + 8;
}

// The canvas's (x, y) on the surface, in its sixteenths, and the margin
// with it, as wide across as the canvas's.
bool GelFace::bodyAt(int x, int y) const {
  const int x16 = x * size_.width * 16 / 320, y16 = y * size_.height * 16 / 240;
  const int margin16 = kBodyMarginPx * size_.width * 16 / 320;
  if (gel::bodyAt(x16, y16, margin16)) return true;
  for (const Hand& h : handsPlan().moved) {
    if (!h.shown()) continue;
    const int64_t dx = x16 - h.x16, dy = y16 - h.y16, r = h.drawn16() + margin16;
    if (dx * dx + dy * dy <= r * r) return true;
  }
  return false;
}

// The finger's way across, canvas px, as the panel's.
void GelFace::swipe(int dx) { dragSwitch(dx * size_.width / 320); }

void GelFace::wish(const WishShow& show) {
  // A wish left: a silent sigh and slump as its bubble fades.
  if (show.pop == WishShow::kGone && wish_.pop != WishShow::kGone)
    if (const rig::Clip* c = rig::kRig.clip("wish-gone")) play(*c);
  wish_ = show;
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
  fingerNowX_ = x, fingerNowY_ = y;
  followFinger(x, y);
  if (!finger_) {
    finger_ = true, fingerX_ = x, fingerY_ = y;
    // Where on the dome, -1 … 1 across its half-width and half-height.
    const F unit = F(kPxPerUnit);
    engine_->dragStart(F(x - kMidX) / unit / q(1.1), F(kMidY - y) / unit / q(.91));
    return;
  }
  if (lean_ != Lean::kNone) leanOn(lean_);
  else {
    const F unit = F(kPxPerUnit);
    engine_->dragMove(F(x - fingerX_) / unit, F(fingerY_ - y) / unit, F(0));
  }
}

void GelFace::letGo(int vx, int vy) {
  if (finger_) {
    const bool woke = lean_ == Lean::kDoze;
    engine_->lookAway();
    const F unit = F(kPxPerUnit);
    engine_->dragEnd(F(vx) / unit, F(-vy) / unit, F(0));
    // Woken by your hand going: a little start, up.
    if (woke && !engine_->scenes.route.quiet) engine_->jolt(0, q(2.2), 0);
  }
  lean_ = Lean::kNone;
  finger_ = false;
}

void GelFace::followFinger(int x, int y) { lookToward(x, y, true); }

// The eyes toward (x, y) on the canvas, which may be off it: after a
// finger, or to what it looks at by itself.
void GelFace::lookToward(int x, int y, bool finger) {
  const int across = x - kMidX, up = kDeskRow - kEyesOverDesk - y;
  const F dx = F(across), dy = F(up), away = F(root(uint32_t(across * across + up * up)) + kGazeKneePx);
  const F gx = kGazeReach * dx / away, gy = kGazeUpReach * dy / away;
  if (finger) engine_->lookAt(gx, gy);
  else engine_->attend(gx, gy);
}

// Nothing has the body: no animation, its own face, reaction or needs-you.
bool GelFace::bodyFree() const {
  const Engine& e = *engine_;
  return source_.anim == SceneState::kNone && !hasOwnFace_ && !e.scenes.route.reaction && !e.router.reacting &&
         !e.router.facts.attention.on;
}

bool GelFace::leans(uint32_t) const {
  return finger_ && bodyFree();
}

void GelFace::lean(Lean level, uint32_t t) {
  if (!finger_) level = Lean::kNone;
  if (level == lean_) return;
  if (lean_ == Lean::kNone) {
    if (playing()) endPastime(t, true);
    breathAt_ = t + kLeanBreathMs / 3;
  }
  lean_ = level;
  leanOn(level);
}

const char* GelFace::passing(uint32_t t) const {
  if (const rig::Clip* clip = transition(t)) return clip->id;
  if (playing()) return info(pastime_).name;
  const Owners& o = owners_;
  if (o.beatShows && o.beat == BeatBy::kCall) return "oncall";
  if (o.beatShows && o.beat == BeatBy::kSpeaking) return "speaking";
  if (o.eyes == EyesBy::kScroll) return "scrolling";
  if (o.beatShows && o.beat == BeatBy::kMusic) return "music";
  if (tapping_) return "along";
  return nullptr;
}

void GelFace::tilt(int mg, uint32_t t) {
  if (!mg) return engine_->tilt(0);
  const Engine& e = *engine_;
  const bool free = !finger_ && bodyFree() && !e.router.listening && !playing() && !transition(t) && !e.acting.current() &&
                    !(stream_ && stream_->call.live);
  engine_->tilt(free ? mg : 0);
}

void GelFace::leanOn(Lean level) {
  // The dome's half-width and half-height on the canvas.
  const F wide = F(kPxPerUnit * 11 / 10), tall = F(kPxPerUnit * 91 / 100);
  // A mood that keeps its own face through a touch shuts its own eyes; the
  // others wear a stroke's, which are shut.
  const bool keeps = slime::kKeepsFaceThroughGestures[engine_->emotion];
  engine_->lean(int(level), clamp(F(fingerNowX_ - kMidX) / wide, -1, 1), clamp(F(kMidY - fingerNowY_) / tall, -1, 1), keeps);
}

void GelFace::showInvite(uint32_t t) {
  engine_->invite = invite_;
  if (!invite_.shows()) return;
  engine_->invite.ms = t - inviteAt_;
  auto& acting = engine_->acting;
  acting.nextPerformance = max(acting.nextPerformance, engine_->motion.time + 2);
  if (inviteSounded_ || payoffAge(engine_->invite) < 0 || pendingCount_ >= kMaxCues) return;
  inviteSounded_ = true;
  const InviteSound sound = inviteSound(invite_.payoff);
  const int clip = clipFor(sound.recipe, 0);
  if (clip < 0) return;
  pendingAt_[pendingCount_] = t;
  voice::FxEvent& e = pending_[pendingCount_++];
  e.atMs = 0;
  e.clip = uint8_t(clip);
  e.gain = sound.gain;
  e.pitch = sound.pitch;
  e.duck = true;
}

// While it leans, a soft breath now and then, through the same queue as the
// engine's contacts: the volume and face down are the device's to mind.
void GelFace::breathe(uint32_t t) {
  if (lean_ == Lean::kNone || after(breathAt_, t) || pendingCount_ >= kMaxCues) return;
  const bool dozing = lean_ == Lean::kDoze;
  breathAt_ = t + (dozing ? kDozeBreathMs : kLeanBreathMs);
  const int clip = clipFor("breath", breathTake_);
  breathTake_ = (breathTake_ + 1) % 3;
  if (clip < 0) return;
  pendingAt_[pendingCount_] = t;
  voice::FxEvent& e = pending_[pendingCount_++];
  e.atMs = 0;
  e.clip = uint8_t(clip);
  e.gain = dozing ? kDozeBreathGain : kLeanBreathGain;
  e.pitch = dozing ? kDozeBreathPitch : kLeanBreathPitch;
  e.duck = true;
}

// At every stop of Behaviour's, on the grid or not.
void GelFace::step(uint32_t t, linkkit::Rng&) {
  advanceTo(t);
  if (!stream_ || !stream_->drawn(t) || !stream_->call.live) return;
  const auto& c = stream_->call;
  if (c.at != landedAt_) landed_ = false, landedAt_ = c.at;
  if (!landed_ && int32_t(t - c.at) >= int32_t(callFlightMs(c.style))) {
    landed_ = true;
    land(c.style);
  }
}

// What the body does as a word lands, in the pull's body units a second:
// knocked back and dazed by a failure, longer up the ladder; a squash as a
// word sinks in or a bit of hail lands; stretched up by a shrug or a cheer.
void GelFace::land(CallStyle style) {
  auto& e = *engine_;
  switch (callMove(style)) {
    case CallMove::kHit:
      // A failure's knock; its dizzy eyes are the stream's to draw. Your
      // no makes it flinch and squeeze its eyes; a timeout lands on it
      // half asleep.
      if (style == CallStyle::kNo) e.jolt(q(-1.5), q(2.4), q(-2), q(.6), 450);
      else if (style == CallStyle::kTimeout) e.jolt(q(.6), q(2.8), q(-2), q(.9), 700);
      else e.jolt(q(1.2), q(3.2), q(-3));
      break;
    case CallMove::kSink: e.jolt(0, q(1.8), 0); break;
    case CallMove::kShatter: e.jolt(0, q(1.4), 0); break;
    case CallMove::kShrug: e.jolt(0, q(-1.6), 0); break;
    // The whole turn's: a gulp at its end; a blink as all goes off.
    case CallMove::kGather: e.jolt(0, q(1.6), q(.6)); break;
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
         old.attention.more != c.more || old.attention.kind != c.attentionKind;
}

void GelFace::sync(const FaceSource& source, const FaceContext& context, uint32_t t) {
  advanceTo(t);
  pace_ = context.pace;
  alone_ = context.alone;
  // Bright as you first show up today: a stretch, up tall, as it wakes.
  if (context.energy == Energy::kBright && energy_ == Energy::kNormal && !context.attention) once(*clips_.stretch, t);
  energy_ = context.energy;
  engine_->energy = context.energy;
  pointer_ = context.pointer, pointerNear_ = context.pointerNear, pointerX_ = context.pointerX, pointerY_ = context.pointerY;
  // The invite: a new phase sounds its payoff afresh, and a pose takes the
  // body from the pastime playing.
  {
    const InviteShow& v = context.invite;
    if (v.phase != invite_.phase) inviteSounded_ = false;
    if (v.shows() && playing()) endPastime(t, true);
    invite_ = v, inviteAt_ = t - v.ms;
    showInvite(t);
  }
  Measure measure(gel::profile.sync);
  auto& e = *engine_;
  if (factsChanged(context)) {
    Facts f;
    f.base = context.base;
    f.act = context.act;
    f.attention = {context.attention, std::to_string(context.attentionId),
                   context.agent,     context.project,
                   context.thread,    context.more,
                   context.attentionKind};
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
  // while it plays. A low or cross mood keeps its own face through a
  // gesture.
  int borrowed = context.borrowed ? expressionFromName(moodName(source.mood)) : -1;
  hasOwnFace_ = borrowed >= 0;
  if (borrowed < 0 && source.anim == SceneState::kGesture &&
      !slime::kKeepsFaceThroughGestures[profileFor(context.mood)])
    borrowed = slime::kGestureFaces[std::min<int>(source.animVariant, slime::kGestureCount - 1)];
  if (borrowed < 0 && source.anim == SceneState::kNotice)
    borrowed = slime::kNoticeFaces[std::min<int>(source.animVariant, slime::kNoticeCount - 1)];
  // Leaning in, it wears a stroke's shut eyes, unless its mood keeps its own.
  if (borrowed < 0 && lean_ != Lean::kNone && !slime::kKeepsFaceThroughGestures[profileFor(context.mood)])
    borrowed = slime::kGestureFaces[int(Gesture::kStroke)];
  // An invite's pose and payoff their own, as a touch's, the same mood
  // keeping its own; but the back's side-eye is every mood's.
  const bool sideEye = context.invite.phase == InviteShow::kPose && context.invite.pose == InvitePose::kBack;
  if (borrowed < 0 && context.invite.shows() &&
      (sideEye || !slime::kKeepsFaceThroughGestures[profileFor(context.mood)]))
    borrowed = expressionFromName(inviteFace(context.invite));
  // Last, jamming to your music: a content face, unless its mood keeps its own.
  if (borrowed < 0 && source.anim == SceneState::kNone && whoHasWhat(truths(t)).face == FaceBy::kJam)
    borrowed = expressionFromName("pleased");
  bool next = source.anim != SceneState::kNone && (source.anim != source_.anim || source.at != source_.at);
  if (next) {
    // Behaviour times the reaction (its loops, its line), so the engine
    // holds it until the source moves on.
    Request r;
    r.anim = source.anim;
    r.loops = source.loops;
    r.outcome = source.outcome;
    r.variant = source.animVariant;
    r.expression = borrowed;
    e.play(r);
    restartCues();
    if (const rig::Clip* clip = rig::kRig.clip(stateName(source.anim))) play(*clip);
    // A face with a move of its own (a meme face's, face-<face>) plays it
    // once as the Moment comes, unless a reply brings a clip of its own.
    if (borrowed >= 0 && !context.reply[0] && !std::strncmp(slime::kIdleMoves[borrowed], "face-", 5))
      if (const rig::Clip* clip = rig::kRig.clip(slime::kIdleMoves[borrowed])) play(*clip);
  } else if (source.anim == SceneState::kNone && source_.anim != SceneState::kNone && !timeout) {
    e.clear();
    restartCues();
  }
  e.borrow(borrowed);
  // A reply to what you said: its clip over the face it came with, or the
  // pastime it asks for, once, as that face starts. A pack with none for
  // it plays the face alone.
  if (context.reply[0] && !(replied_ && context.replyAt == replyAt_)) {
    replied_ = true, replyAt_ = context.replyAt;
    reply(context.reply);
  }
  if (source.state() != source_.state()) {
    lookAt_ = t;
    restartCues();
  }
  source_ = source;
  showLayers(t);
}

// The engine's shuffle bag for the reaction, drawn from copies: a call
// refused after its pick (Device::refuse) leaves the bag and the engine's
// randomness as they were. started draws the same take for real.
uint8_t GelFace::pick(SceneState a, Mood mood, int, Outcome outcome, linkkit::Rng&, int loops, int turn) const {
  // A successful finish by its size: small deals Little Win's takes from
  // the bag, as every other row does.
  if (a == SceneState::kTaskComplete && outcome == Outcome::kSuccess) {
    const int canonical = slime::kProfile[profileFor(mood)].canonical;
    switch (finishSize(loops, turn, canonical)) {
      case FinishSize::kSmall: break;
      case FinishSize::kMedium: return uint8_t(finishVariant(Finish::kConfetti));
      case FinishSize::kBig: return uint8_t(finishVariant(Finish::kGoldRush));
    }
  }
  const int row = recipeState(a, outcome);
  auto bag = engine_->scenes.bags[slime::kProfile[profileFor(mood)].canonical][row];
  Random random = engine_->random;
  return uint8_t(bag.next(random, takes(row)));
}

void GelFace::started(SceneState a, Mood mood, uint8_t variant, Outcome outcome) {
  if (a == SceneState::kGesture) return;
  if (a == SceneState::kTaskComplete && isFinishVariant(variant)) return;
  const int row = recipeState(a, outcome);
  engine_->scenes.bags[slime::kProfile[profileFor(mood)].canonical][row].next(engine_->random, takes(row));
}

int GelFace::plays(SceneState a, uint8_t variant, int loops) const {
  return a == SceneState::kTaskComplete && isFinishVariant(variant) ? 1 : loops;
}

int GelFace::variants(Mood, SceneState s) const { return s == SceneState::kGesture ? slime::kGestureCount : kTakes; }

uint32_t GelFace::loopMs(Mood mood, SceneState state, int variant) const {
  return uint32_t(F(recipe(mood, state, variant, Outcome::kNone).duration).integer());
}

// A line over a reaction starts at its first result contact (the card or
// the alert), less the speaker's lead.
uint32_t GelFace::voiceMs(Mood mood, SceneState state, int variant) const {
  const slime::Recipe r = recipe(mood, state, variant, Outcome::kNone);
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
                   const char* caption, const SignShow& sign, const DoneShow& done, const Strip& strip, bool) {
  if (!native || !native->pixels) return false;
  const PastimeShow passing = pastimes(lastTick_);
  size_ = {native->width, native->height, native->corner};
  signHop_ = signHop(sign);
  // A sign held up fills its hands: from the next frame, no keys (owners.h).
  signUp_ = sign.text && !sign.low;
  cardDrawn_ = paintFrame(*native, *engine_, show.mouthOpen, show.dy, bubble, sign, strip, done, channels(), &layers_,
             lastTick_, stream_, t, &passing, drawer_, caption, &wish_, &card_);
  return true;
}

int GelFace::profile(char* out, size_t n, uint32_t frames) {
  auto& p = gel::profile;
  if (!frames) return 0;
  int written = std::snprintf(
      out, n,
      "gel_parts engine_us=%lu sync_us=%lu body_us=%lu art_us=%lu layers_us=%lu props_us=%lu clear_us=%lu "
      "lane_us=%lu stream_us=%lu behind_us=%lu front_us=%lu hands_us=%lu\n",
      (unsigned long)(p.engine / frames), (unsigned long)(p.sync / frames), (unsigned long)(p.body / frames),
      (unsigned long)(p.art / frames), (unsigned long)(p.layers / frames), (unsigned long)(p.props / frames),
      (unsigned long)(p.clear / frames), (unsigned long)(p.lane / frames), (unsigned long)(p.stream / frames),
      (unsigned long)(p.behind / frames), (unsigned long)(p.front / frames), (unsigned long)(p.hands / frames));
  p = Profile{};
  return written > 0 && size_t(written) < n ? written : 0;
}

}  // namespace render::gel
