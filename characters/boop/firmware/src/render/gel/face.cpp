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
                   kMusicTag = bitOf("music"), kVideoTag = bitOf("video"), kFastTag = bitOf("typingfast"),
                   kTypingTag = bitOf("typing"), kMacLeftTag = bitOf("macleft"),
                   kMacRightTag = bitOf("macright"), kMacUpTag = bitOf("macup"),
                   kSpeakingTag = bitOf("speaking");

}  // namespace

const voice::EffectClips& GelFace::clips() const { return gel::clips(); }

// By WithYou's order: none, music, video, reading, speaking, on a call.
const GelFace::Clips GelFace::clips_ = {
    {nullptr, &clipNamed("groove"), &clipNamed("video"), &clipNamed("read-along"), &clipNamed("speak-along"),
     &clipNamed("on-call")},
    &clipNamed("read-along-settled"),
    &clipNamed("type-along"),
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
  fast_ = typingTag_ = thought_ = false, typingFrom_ = thinkAt_ = 0;
  with_ = wanted_ = WithYou::kNone, withClip_ = nullptr;
  scrolled_ = music_ = called_ = settled_ = false, scrolledAt_ = readFrom_ = musicFrom_ = 0;
  for (auto& m : marks_) m = rig::Ramp{};
  scrolledMs_ = 0, withAt_ = t;
  pawPhaseQ_ = 0, fastSeen_ = 0;
  pointer_ = pointerNear_ = false, pointerX_ = pointerY_ = 0;
  for (int i = 0; i < kFollows; ++i) followTo_[i] = followBy_[i] = 0;
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
  engine_->typingAlong = tapping_, engine_->typingFast = fast_, engine_->typingPhase = int(pawPhaseQ_ / 1000);
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
    holdGestures(*clip);
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
  // Nor one over its keyboard, out to type along with you.
  // Nor while it's on a call with you, holding a copy, reading along,
  // watching or in a groove (showWithYou).
  const bool busy = finger_ || card_.on || along_.target() || wanted_ != WithYou::kNone ||
                    (stream_ && stream_->drawn(t) && stream_->call.live);
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
  // At work, only a stretch but while it types: a take is typing, the done
  // beat is a paw on Enter, and a melt from another pose would leave the
  // screen.
  const SceneState desk = e.scenes.route.state;
  const bool types = isDesk(desk) && activityOf(desk) == Activity::kTyping;
  // Tired, idle: a yawn now and then, whatever the tier, and the newest.
  const bool tired = e.energy == Energy::kTired && look == SceneState::kIdle;
  for (const auto& p : kPastimes) {
    const bool yawn = tired && p.id == Pastime::kYawn;
    if (p.look != look || !(fits(p, when, lookMs) || yawn) || (p.move && moveWaits) || !hasBody(p)) continue;
    if ((look == SceneState::kWorking && !types && p.id != Pastime::kStretch))
      continue;
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
    holdGestures(*clip);
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

void GelFace::holdGestures(const rig::Clip& clip) {
  auto& acting = engine_->acting;
  acting.nextPerformance = max(acting.nextPerformance, engine_->motion.time + int(clip.ms / 1000) + 2);
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
  for (const PastimeInfo& p : kPastimes)
    if (!std::strcmp(p.name, name)) {
      advanceTo(t);
      playPastime(p.id, t);
      return true;
    }
  return false;
}

// Whether the working look's pose is typing's: no activity's own clip
// (looking, running, waiting) has the body and the eyes.
bool GelFace::typingPose() const {
  const rig::Look* l = rig::kRig.look(SceneState::kWorking);
  return !(l && l->acted(engine_->router.facts.look()));
}

// Whether it's free for you at the Mac (typing along, and the poses of
// showWithYou): it shows its own look, idle or at work in any pose, a card
// in its hands or not (going with you is a layer over the pose, the
// engine's documentation/design/theory.md, "One body, three channels"),
// and nothing else has it: no finger, no Mac gone, no transition and no
// pastime. `look` is the look.
bool GelFace::freeForYou(uint32_t t, SceneState& look) const {
  const bool shows = showsLook(source_.anim, look);
  const bool place = look == SceneState::kIdle || look == SceneState::kWorking;
  return shows && place && !finger_ && !alone_ && !transition(t) && !playing();
}

// Whether going with you is at its light size: at work, or holding a card.
// The pose is the work's then, so only the rhythm and the gaze ride on it:
// the paws stay where the pose puts them, and the poses that move the whole
// body (reading, a video, music) give way to the eyes alone.
bool GelFace::light(SceneState look) const {
  return card_.on || (look == SceneState::kWorking && !typingPose());
}

// Typing along with you (face.h): while your hands are busy and it's free
// for you, its paws type briskly with you. Idle, its keyboard comes out
// for it, and stays a little longer after you stop, its paws at rest, so a
// pause in your typing doesn't put the keyboard away and bring it back; at
// work the desk is out already, and its paws go back to the agents' soft
// typing. Not while it holds a card: its hands are full. Not on a call.
void GelFace::showAlong(uint32_t t) {
  const Engine& e = *engine_;
  SceneState look;
  const bool free = freeForYou(t, look);
  const bool idle = free && look == SceneState::kIdle, working = free && look == SceneState::kWorking;
  const uint32_t when = e.scenes.when;
  const bool typing = when & kTypingTag;
  const bool was = tapping_;
  // Speaking wins over typing: one rhythm at a time.
  tapping_ = (idle || working) && typing && !(when & kCallTag) && !(when & kSpeakingTag);
  // Its body keeps time with you: a small sway over the keys (the rig's
  // `type-along`); the paws carry the typing.
  if (tapping_ != was) tapping_ ? mixer_.play(*clips_.along) : mixer_.stop(*clips_.along);
  // Fast, its eyes open wider and it hunches in, and its paws tap quicker
  // (pawPhase). A flicker off shorter than kFastLingerMs doesn't stop it.
  const bool fastNow = tapping_ && (when & kFastTag);
  if (fastNow) fastSeen_ = t;
  const bool fast = fastNow || (fast_ && tapping_ && within(t, fastSeen_, kFastLingerMs));
  if (fast != fast_) fast ? mixer_.play(*clips_.fast) : mixer_.stop(*clips_.fast);
  fast_ = fast;
  // A long stretch of typing along that you stop: it looks up at you, as
  // if thinking it over with you (render/gel/gaze.h).
  if (typing && !typingTag_) typingFrom_ = t;
  if (!typing && typingTag_ && was && t - typingFrom_ >= Gaze::kThinkAfterMs) thought_ = true, thinkAt_ = t;
  typingTag_ = typing;
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

// With you at the Mac besides typing along (face.h): the one that fits now,
// its pose's clip on the mixer, the lean it follows, and a move once as a
// call or the music ends.
void GelFace::showWithYou(uint32_t t) {
  const Engine& e = *engine_;
  const uint32_t when = e.scenes.when;
  SceneState look;
  const bool free = freeForYou(t, look) && !tapping_ && !e.acting.current() && !e.router.listening;
  const bool call = when & kCallTag;
  if (when & kScrollingTag) {
    if (!scrolled_ || t - scrolledAt_ >= kReadGapMs) readFrom_ = t;
    scrolled_ = true, scrolledAt_ = t;
  }
  const bool reading = scrolled_ && within(t, scrolledAt_, kReadLingerMs) && !light(look);
  const bool music = when & kMusicTag;
  if (music && !music_) musicFrom_ = t;
  const bool musicStopped = music_ && !music;
  music_ = music;
  const bool grooving = music && (t - musicFrom_) % (kGrooveMs + kGrooveRestMs) < kGrooveMs && !light(look);
  wanted_ = call       ? WithYou::kCall
            : (when & kSpeakingTag) ? WithYou::kSpeaking
            : reading  ? WithYou::kReading
            : (when & kVideoTag) && !light(look) ? WithYou::kVideo
            : grooving ? WithYou::kMusic
                       : WithYou::kNone;
  const WithYou now = free ? wanted_ : WithYou::kNone;
  // As each ends: a stretch back up after a call, a look round as the
  // music stops. Not over anything else.
  if (called_ && !call) once(*clips_.stretch, t);
  else if (musicStopped && !call) once(*clips_.lookAround, t);
  called_ = call;
  settled_ = now == WithYou::kReading && t - readFrom_ >= kSettleMs;
  const rig::Clip* clip = now == WithYou::kReading && settled_ ? clips_.settled : clips_.with[int(now)];
  if (clip != withClip_) {
    if (withClip_) mixer_.stop(*withClip_);
    if (clip) mixer_.play(*clip, kWithFadeMs);
    withClip_ = clip;
  }
  // The engine's own idle gestures wait while it's with you.
  if (clip) holdGestures(*clip);
  with_ = now;
  engine_->speaking = now == WithYou::kSpeaking;
  engine_->speakingSide = when & kMacLeftTag ? -1 : 1;
  const int mac = (when & kMacLeftTag) ? -1 : (when & kMacRightTag) ? 1 : 0;
  // What it has on or beside it (Engine::With), so each reads at a glance
  // where a pose alone is too small to see: at the light size too, and
  // the headphones while it types along. Not over a Moment, a finger or
  // listening, nor a pastime but the headphones; a call has only its muted
  // mic, and speaking's hand is at its ear, so no headphones then. The page
  // and the screen stand beside it, so neither while its paws are busy or a
  // card is held.
  {
    SceneState place;
    const bool open = freeForYou(t, place) && !e.acting.current() && !e.router.listening;
    const bool speaks = when & kSpeakingTag, read = scrolled_ && within(t, scrolledAt_, kReadLingerMs);
    const bool beside = open && !call && !speaks && !tapping_ && !card_.on;
    const bool page = beside && read, screen = beside && !read && (when & kVideoTag);
    // Headphones stay on through a pastime (a bit or a take of the engine's
    // too) or a transition, so they don't come and go between grooves.
    SceneState shown;
    const bool worn = showsLook(source_.anim, shown) && (shown == SceneState::kIdle || shown == SceneState::kWorking) &&
                      !finger_ && !alone_ && !e.router.listening;
    const bool phones = worn && music && !call && !speaks;
    const bool on[kMarks] = {phones, page, screen, open && call};
    for (int i = 0; i < kMarks; ++i) marks_[i].retarget(on[i] ? 1000 : 0, t);
    if (page && (when & kScrollingTag)) scrolledMs_ += std::min<uint32_t>(t - withAt_, 100);
    withAt_ = t;
    Engine::With& w = engine_->with;
    auto opacity = [&](Mark m) { return (marks_[m].value(t) * 255 + 500) / 1000; };
    w.headphones = opacity(kHeadphones), w.page = opacity(kPage), w.screen = opacity(kScreen), w.muted = opacity(kMuted);
    w.side = mac ? mac : 1;
    w.scroll = int(scrolledMs_ * kPageScroll / 1000);
    w.notes = phones && !page && !screen && !tapping_ && (t - musicFrom_) % (kGrooveMs + kGrooveRestMs) < kGrooveMs;
    w.notesMs = t - musicFrom_;
  }
  // Turned to the screen, reading or watching: to the Mac's side, or up at
  // it; to the pointer while it moves, and further at the edge nearest the
  // board, reaching toward it. Never on a call.
  const bool up = !mac && (when & kMacUpTag);
  int* to = followTo_;
  for (int i = 0; i < kFollows; ++i) to[i] = 0;
  if (now == WithYou::kReading) {
    to[kFollowLean] = mac * kReadLean, to[kFollowX] = mac * kReadSlide, to[kFollowGazeX] = mac * kScreenGaze;
    to[kFollowGazeY] = up ? -kScreenGazeUp : kPageGaze;
    if (up) to[kFollowSquash] = -kUpStretch;
  } else if (now == WithYou::kVideo) {
    to[kFollowLean] = mac * kLeanReach, to[kFollowX] = mac * kScreenSlide, to[kFollowGazeX] = mac * kScreenGaze;
    if (up) to[kFollowGazeY] = -kScreenGazeUp, to[kFollowSquash] = -kUpStretch;
  }
  if (free && now != WithYou::kCall && pointer_) {
    const int side = pointerX_ > 0 ? 1 : pointerX_ < 0 ? -1 : mac;
    if (pointerNear_) {
      to[kFollowLean] = side * kLeanReach, to[kFollowSquash] = -kNearStretch;
      to[kFollowX] = side * Gaze::kPointerReach * kPointerSlide, to[kFollowGazeX] = side * Gaze::kPointerReach * kPointerGaze;
      if (!side && up) to[kFollowGazeY] = -kScreenGazeUp;
    } else {
      to[kFollowLean] = pointerX_ * kPointerLean, to[kFollowSquash] = pointerY_ < 0 ? pointerY_ * kPointerStretch : 0;
      to[kFollowX] = pointerX_ * kPointerSlide;
      to[kFollowGazeX] = pointerX_ * kPointerGaze, to[kFollowGazeY] = pointerY_ * kPointerGazeUp;
    }
  }
}

void GelFace::once(const rig::Clip& clip, uint32_t t) {
  SceneState look;
  const Engine& e = *engine_;
  if (!freeForYou(t, look) || tapping_ || e.acting.current() || e.router.listening) return;
  play(clip);
  holdGestures(clip);
  // No pastime straight after it.
  if (after(t + clip.ms + kRestMinMs, restUntil_)) restUntil_ = t + clip.ms + kRestMinMs;
}

// The lean and the stretch ease to where they're going, over about kLeanMs.
void GelFace::followLean(uint32_t dt) {
  auto follow = [&](int& by, int to) {
    const int64_t goal = int64_t(to) * 256;
    by = int(by + (goal - by) * int64_t(dt) / int64_t(dt + kLeanMs));
  };
  for (int i = 0; i < kFollows; ++i) follow(followBy_[i], followTo_[i]);
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
  const bool desk = e.scenes.desk.x > q(.5) || along_.value(t) > 500;
  lively_.advance(dt, clipChannels(), e.life()[0] * unit, e.acting.slide.x * unit, desk);
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
  // A move (an invite's, the knock): its clip at its time, over the rest.
  addMove(c, currentMove(*engine_), false);
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
  const bool shows = showsLook(source_.anim, look);
  const uint32_t when = e.scenes.when;
  f.free = shows && !finger_ && !alone_ && !playing() && !transition(t) && !e.acting.current() && !e.router.listening &&
           !(stream_ && stream_->call.live);
  f.needsYou = look == SceneState::kNeedsYou;
  f.lookMs = e.scenes.lookMs;
  f.mac = (when & kMacLeftTag) ? -1 : (when & kMacRightTag) ? 1 : 0;
  f.up = !f.mac && (when & kMacUpTag);
  f.along = tapping_ && !light(look);
  f.posed = look == SceneState::kWorking && !typingPose();
  f.thinking = thought_ && within(t, thinkAt_, Gaze::kThinkMs), f.thinkMs = t - thinkAt_;
  if (!f.thinking) thought_ = false;
  f.with = with_;
  // The pointer only where it's free for you: never asleep or dozing.
  SceneState place;
  f.pointer = pointer_ && freeForYou(t, place) && !tapping_;
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
  if (tapping_) return "along";
  if (playing()) return info(pastime_).name;
  switch (with_) {
    case WithYou::kCall: return "oncall";
    case WithYou::kSpeaking: return "speaking";
    case WithYou::kReading: return "reading";
    case WithYou::kVideo: return "video";
    case WithYou::kMusic: return "music";
    case WithYou::kNone: break;
  }
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
  // In a groove with your music, a content face, unless its mood keeps its own.
  if (borrowed < 0 && with_ == WithYou::kMusic && !slime::kKeepsFaceThroughGestures[profileFor(context.mood)])
    borrowed = expressionFromName("pleased");
  // Leaning in, it wears a stroke's shut eyes, unless its mood keeps its own.
  if (borrowed < 0 && lean_ != Lean::kNone && !slime::kKeepsFaceThroughGestures[profileFor(context.mood)])
    borrowed = slime::kGestureFaces[int(Gesture::kStroke)];
  // An invite's pose and payoff their own, as a touch's, the same mood
  // keeping its own; but the back's side-eye is every mood's.
  const bool sideEye = context.invite.phase == InviteShow::kPose && context.invite.pose == InvitePose::kBack;
  if (borrowed < 0 && context.invite.shows() &&
      (sideEye || !slime::kKeepsFaceThroughGestures[profileFor(context.mood)]))
    borrowed = expressionFromName(inviteFace(context.invite));
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
  // A sign held up fills its hands: no key's ticks under it.
  if (sign.text && !sign.low) engine_->typingAlong = false;
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
      "lane_us=%lu stream_us=%lu behind_us=%lu front_us=%lu\n",
      (unsigned long)(p.engine / frames), (unsigned long)(p.sync / frames), (unsigned long)(p.body / frames),
      (unsigned long)(p.art / frames), (unsigned long)(p.layers / frames), (unsigned long)(p.props / frames),
      (unsigned long)(p.clear / frames), (unsigned long)(p.lane / frames), (unsigned long)(p.stream / frames),
      (unsigned long)(p.behind / frames), (unsigned long)(p.front / frames));
  p = Profile{};
  return written > 0 && size_t(written) < n ? written : 0;
}

}  // namespace render::gel
