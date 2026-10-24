#include "app/behaviour.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

#include "render/maths.h"
#include "render/tags.h"
#include "voice/effects.h"
#include "voice/player.h"

namespace app {

using render::after;
using render::within;

namespace {

constexpr uint32_t kAmberDim = 0x805800;  // needs you: amber at half

}  // namespace

const char* cutByName(CutBy c) {
  switch (c) {
    case CutBy::kTap: return "tap";
    case CutBy::kNeedsYou: return "needs_you";
    default: return nullptr;
  }
}

render::SceneState baseFromName(const char* name) {
  render::SceneState s = render::stateFromName(name);
  return s == render::SceneState::kWorking || s == render::SceneState::kAsleep ? s : render::SceneState::kIdle;
}

render::SceneState actFromName(const char* name) {
  using render::SceneState;
  SceneState s = render::stateFromName(name);
  switch (s) {
    case SceneState::kPlanning:
    case SceneState::kTerminal:
    case SceneState::kToolUse:
    case SceneState::kSearching:
    case SceneState::kAnalyzing:
    case SceneState::kTesting:
    case SceneState::kDelegating:
    case SceneState::kWaiting: return s;
    default: return SceneState::kWorking;
  }
}

// Forgets everything, what the Mac is owed included: the kit has already
// cut the reaction playing (dbg.reset resets its queue first).
void Behaviour::reset(uint32_t t, Rng& rng) {
  auto face = std::move(face_);
  *this = Behaviour(std::move(face));
  modelT_ = t;
  lastState_ = t;
  face_->reset(t, rng);
  change(t, [] {});
}

// ---- Time ------------------------------------------------------------------

bool Behaviour::noApp(uint32_t t) const { return stale_ || int32_t(t - lastState_) >= int32_t(kNoAppMs); }

bool Behaviour::reactionOn(uint32_t t) const {
  return reaction_.anim != render::SceneState::kNone && within(t, reaction_.at, reaction_.ms);
}

bool Behaviour::listening(uint32_t t) const {
  return reactionOn(t) && reaction_.anim == render::SceneState::kListening;
}

// What shows, first first: no app, listening, needs you,
// then a tap's poke and the reactions, then the look. So with no app, while
// something needs you and while listening waits for the reply, a tap only
// dips the face and a reaction's animation is skipped.
bool Behaviour::held(uint32_t t) const { return noApp(t) || model_.attn || listening(t); }

bool Behaviour::sayOn(uint32_t t) const { return say_.take >= 0 && within(t, say_.at, say_.ms); }

bool Behaviour::sayDue(uint32_t t) const {
  return say_.take >= 0 && int32_t(t - say_.at) < int32_t(say_.ms);
}

bool Behaviour::exprOn(uint32_t t) const { return expr_ && within(t, exprAt_, exprMs_); }

bool Behaviour::signOn(uint32_t t) const { return sign_.text[0] && within(t, sign_.at, sign_.ms); }

bool Behaviour::expression(uint32_t t, render::Mood& mood) const {
  if (!exprOn(t)) return false;
  mood = exprMood_;
  return true;
}

void Behaviour::advance(uint32_t t, Rng& rng) {
  if (after(modelT_, t)) {  // the clock went back: no history to replay
    modelT_ = t;
    face_->rewind(t, rng);
    resync(t);
    return;
  }
  for (;;) {
    bool found = false;
    uint32_t next = t;
    auto consider = [&](uint32_t c) {
      if (after(c, modelT_) && !after(c, t) && (!found || after(next, c))) next = c, found = true;
    };
    if (reaction_.anim != render::SceneState::kNone) consider(reaction_.at + reaction_.ms);
    if (say_.take >= 0) consider(say_.at + say_.ms);
    if (expr_) consider(exprAt_ + exprMs_);
    if (sign_.text[0]) consider(sign_.at + sign_.ms);
    consider(lastState_ + kNoAppMs);
    uint32_t faceAt;
    if (face_->nextDue(modelT_, t, faceAt)) consider(faceAt);
    if (!found) break;
    // Everything due at `next`, in a fixed order.
    resync(next);
    face_->step(next, rng);
    change(next, [] {});
  }
  resync(t);
}

// Time-based changes at t: a reaction or its expression that has ended, and
// the Mac's silence turning into "no app". First the timers that have run
// out are cleared, so none comes back when the clock's differences wrap
// after 2^31 ms (24.9 days); none of them is part of the source, so the
// face doesn't change.
void Behaviour::resync(uint32_t t) {
  if (say_.take >= 0 && !sayDue(t)) say_ = Say{};
  if (sign_.text[0] && !signOn(t)) sign_ = Sign{};
  if (blFade_ && !within(t, blAt_, kBacklightEaseMs)) blFade_ = false;
  change(t, [&] {
    if (reaction_.anim != render::SceneState::kNone && !within(t, reaction_.at, reaction_.ms)) {
      reaction_.anim = render::SceneState::kNone;
    }
    if (expr_ && !within(t, exprAt_, exprMs_)) expr_ = false;
    if (!stale_ && int32_t(t - lastState_) >= int32_t(kNoAppMs)) stale_ = true;
  });
}

// ---- The reaction playing: how it ended (`ended`) -----------------------

// A reaction is played out when none of its parts plays: the animation,
// the `say` and its bubble, the expression, the sign. It was cut if its
// animation or its `say` was stopped early. Its expression holds on after
// its `say`, and ending that early doesn't cut it: the reaction was seen
// and heard. Only
// the reaction that last played is followed: it's the one the kit has
// playing, and the kit ended any before it when the queue started this one.
bool Behaviour::holds(uint32_t key, uint32_t t) const {
  return (reactionOn(t) && reaction_.key == key) || (sayDue(t) && say_.key == key) ||
         (exprOn(t) && exprKey_ == key) || (signOn(t) && sign_.key == key);
}

// The first cut is the one reported.
void Behaviour::cut(uint32_t key, CutBy by) {
  if (playing_.key == key && playing_.by == CutBy::kNone) playing_.by = by;
}

void Behaviour::sweep(uint32_t t) {
  if (playing_.key && !holds(playing_.key, t)) playedOut_ = playing_, playing_ = PlayedOut{};
}

bool Behaviour::takePlayedOut(PlayedOut& p) {
  if (!playedOut_.key) return false;
  p = playedOut_;
  playedOut_ = PlayedOut{};
  return true;
}

bool Behaviour::nextEnd(uint32_t from, uint32_t to, uint32_t& at) const {
  bool found = false;
  auto consider = [&](uint32_t c) {
    if (after(c, from) && !after(c, to) && (!found || after(at, c))) at = c, found = true;
  };
  if (reaction_.anim != render::SceneState::kNone) consider(reaction_.at + reaction_.ms);
  if (say_.take >= 0) consider(say_.at + say_.ms);
  if (expr_) consider(exprAt_ + exprMs_);
  if (sign_.text[0]) consider(sign_.at + sign_.ms);
  return found;
}

// ---- Messages --------------------------------------------------------------

void Behaviour::onState(const Model& m, uint32_t t) {
  change(t, [&] {
    // A different needs-you shown: another number, or another agent or
    // project (all a Mac that sends no number says).
    bool had = model_.attn;
    bool fresh = m.attn && (!had || m.attnId != model_.attnId || std::strncmp(model_.agent, m.agent, sizeof(m.agent)) ||
                            std::strncmp(model_.project, m.project, sizeof(m.project)));
    // Another visual starts the looks' rotation over: the face picks its
    // first variation itself, from those that fit now.
    bool look = m.attn != model_.attn || m.look() != model_.look();
    model_ = m;
    if (look) lookAt_ = t, face_->newLook();
    lastState_ = t;
    stale_ = false;
    blOverride_ = false;
    if (fresh) {  // a new needs-you: its performance plays from the start, and it wins
      alerted_ = true, alertAt_ = t;
      face_->alert(t, had);
      // Listening is the one reaction that plays on, so
      // push-to-talk still works.
      if (reactionOn(t) && !listening(t))
        cut(reaction_.key, CutBy::kNeedsYou), reaction_.anim = render::SceneState::kNone;
      if (sayDue(t)) cut(say_.key, CutBy::kNeedsYou);
      say_ = Say{};  // no `say` or sign while something needs you
      sign_ = Sign{};
      expr_ = false;
    }
    // Answered on the Mac (`attn` leaves), or back after no app: the face
    // blinks into what the state says.
  });
}

// A reaction with an animation replaces the one playing, and its `say` too;
// the animation plays its loops of its design. A `say` on its own plays
// over whatever face is showing, replacing any `say`. With
// an animation, the `say` starts at its design's voice window,
// and the animation holds on until the `say` and its bubble are over
// rather than the `say` being hurried. A reaction with an expression draws
// the design showing in its mood for as long as its animation plays, or
// with none for its loops of the design it's drawn in, and at least as long
// as its `say` and bubble; a face on its own (no animation, no `say`) plays
// just that, leaving any `say` playing. A reaction's sign is held up from
// its start for as long as any of its other parts plays, and at least
// kSignMinMs; a newer reaction's animation or `say` takes it down with the
// `say`, and a sign on its own plays too. What outranks the reactions:
// no app, and while something needs you no animation
// takes the face over and no `say` or face on its own plays. A reaction
// that would play nothing isn't admitted: the kit skips it, with why.
//
// Listening plays even while something needs you, and holds
// until the reply: a reaction with a `say` is the reply, and ends it before
// playing as it would have; so does stop_listening, which does nothing
// else. Nothing else ends it or plays while it waits: not a rule's
// reaction, a finish or a face without a `say`. A listening reaction while
// listening carries on with the same design, its time starting over.
const char* Behaviour::admit(const ReactionIn& in, uint32_t t) {
  const bool listen = in.anim == render::SceneState::kListening;
  const bool wasListening = listening(t);
  if (wasListening && !listen && (in.said || in.empty)) change(t, [&] { reaction_.anim = render::SceneState::kNone; });
  if (in.empty) return wasListening ? nullptr : "not_listening";
  if (faceDown_ && !listen) return "facedown";  // do not disturb
  bool anim = in.anim != render::SceneState::kNone && (listen || !held(t));
  bool say = in.take >= 0 && !model_.attn && !noApp(t);
  bool face = in.expr && !held(t);  // listening, if it's still on, holds the face
  bool sign = in.sign[0] && !held(t);
  if (anim || say || face || sign) return nullptr;
  if (noApp(t)) return "no_app";
  if (listening(t)) return "listening";
  if (model_.attn) return "needs_you";
  return "nothing";
}

bool Behaviour::play(const ReactionIn& in, uint32_t t) {
  const bool listen = in.anim == render::SceneState::kListening;
  bool anim = in.anim != render::SceneState::kNone && (listen || !held(t));
  bool say = in.take >= 0 && !model_.attn && !noApp(t);
  bool face = in.expr && !held(t);
  bool sign = in.sign[0] && !held(t);
  if (!anim && !say && !face && !sign) return false;  // stop_listening: admit did it all
  change(t, [&] {
    const render::Mood mood = in.expr ? in.mood : model_.mood;  // the mood it's drawn in
    uint32_t voice = 0;  // when its `say` starts, from t
    if (anim && listen && listening(t)) {
      reaction_.ms = (t - reaction_.at) + kListenMs + kReplyWaitMs;
      reaction_.key = in.key;
      reaction_.id = in.id;
    } else if (anim) {
      endSay(t, CutBy::kNone);
      playAnim(in.anim, t, CutBy::kNone, in.loops, mood, in.variant, in.outcome, in.ctx);
      reaction_.key = in.key;
      reaction_.id = in.id;
      bool finish = in.anim == render::SceneState::kTaskComplete || in.anim == render::SceneState::kReplyReady;
      if (finish && in.whoAgent && in.whoAgent[0]) {
        copyStr(reaction_.agent, sizeof(reaction_.agent), in.whoAgent);
        copyStr(reaction_.thread, sizeof(reaction_.thread), in.whoThread);
      }
      if (!listen) voice = face_->voiceMs(mood, in.anim, in.variant);
    }
    if (say) {
      startSay(in, t, t + voice);
      say_.key = in.key;
      if (anim && !listen && voice + say_.ms > reaction_.ms) reaction_.ms = voice + say_.ms;
    }
    if (in.expr) {
      expr_ = true;
      exprMood_ = in.mood;
      exprAt_ = t;
      exprMs_ = anim ? reaction_.ms : holdMs(in.mood, in.loops, t);
      if (say && voice + say_.ms > exprMs_) exprMs_ = voice + say_.ms;
      exprKey_ = in.key;
    }
    if (sign) {  // as long as the rest of it plays, from now, and long enough to read
      copyStr(sign_.text, sizeof(sign_.text), in.sign);
      sign_.at = t;
      sign_.ms = kSignMinMs;
      if (anim && !listen) sign_.ms = std::max(sign_.ms, reaction_.ms);
      if (say) sign_.ms = std::max(sign_.ms, voice + say_.ms);
      if (in.expr) sign_.ms = std::max(sign_.ms, exprMs_);
      sign_.key = in.key;
    }
    if (in.key) playing_ = PlayedOut{in.key, CutBy::kNone};
  });
  return say;
}

uint8_t Behaviour::pick(render::SceneState a, render::Mood mood, int wanted, render::Outcome o, render::StartCtx c,
                        Rng& rng) const {
  return face_->pick(a, mood, wanted, o, c, rng);
}

// The animation playing is cut short, by `by`; the `say` and the
// expression play on (endSay ends them).
void Behaviour::playAnim(render::SceneState a, uint32_t t, CutBy by, int loops, render::Mood mood, uint8_t variant,
                         render::Outcome outcome, render::StartCtx ctx) {
  if (by != CutBy::kNone && reactionOn(t)) cut(reaction_.key, by);
  reaction_ = Reaction{};
  reaction_.anim = a;
  reaction_.variant = variant;
  reaction_.loops = loops;
  reaction_.at = t;
  reaction_.requestedOutcome = outcome;
  reaction_.ctx = ctx;
  if (a == render::SceneState::kListening) {
    reaction_.ms = kListenMs + kReplyWaitMs;
    reaction_.playMs = UINT32_MAX;  // its design loops on until the reply
  } else {
    reaction_.ms = reaction_.playMs = uint32_t(loops) * face_->loopMs(mood, a, variant);
  }
  reaction_.outcome = face_->outcome(mood, a, variant, outcome);
  face_->started(a, mood, variant, outcome, ctx);
}

// A new reaction replaces the `say` playing, cut short by `by`, and its
// expression and sign.
void Behaviour::endSay(uint32_t t, CutBy by) {
  if (by != CutBy::kNone && sayDue(t)) cut(say_.key, by);
  say_ = Say{};
  expr_ = false;
  sign_ = Sign{};
  ++reactionSeq_;
}

// The design is the animation's while one plays, on its clock, else the
// look's, on the look's; the first loop ends at its clock's next boundary
// after t, so it can be short. A later change of look or animation doesn't
// move the end.
uint32_t Behaviour::holdMs(render::Mood mood, int loops, uint32_t t) const {
  return face_->holdMs(mood, loops, t);
}

void Behaviour::startSay(const ReactionIn& in, uint32_t t, uint32_t at) {
  endSay(t, CutBy::kNone);  // a new `say` ends the last one and the last reaction's expression
  Say& s = say_;
  s.take = in.take;
  s.then = voice::takeText(in.then) ? in.then : -1;
  std::snprintf(s.text, sizeof(s.text), s.then >= 0 ? "%s %s" : "%s", voice::takeText(in.take), voice::takeText(s.then));
  s.speakMs = voice::sayMs(s.take, s.then);
  s.at = at;
  s.ms = s.speakMs + kBubbleReadMs;
}

// ---- Inputs ----------------------------------------------------------------

void Behaviour::pressDown(uint32_t t) {
  pressed_ = true;
  pressAt_ = t;
}

void Behaviour::pressUp() { pressed_ = false; }

// Every tap counts in the run, those that only dip the face too, as the
// Mac counts pokes; while the face is held, or while the brain's finish
// names whose turn it was (the Mac opens that thread), a tap shows the
// press dip only. Otherwise it plays poked in Boop's mood, or tap_spam from the run's
// third tap on, cutting the animation playing. A brain reaction's `say` and
// expression play on over it, so a barrage doesn't cut short the one
// answer it gets.
const char* Behaviour::tap(uint32_t t, Rng& rng) {
  bool inRun = taps_ > 0 && int32_t(t - lastTap_) < int32_t(kTapRunMs);
  taps_ = inRun ? std::min(taps_ + 1, 1000) : 1;
  lastTap_ = t;
  if (held(t) || finishShown(t)) return "dip";
  const render::SceneState a = taps_ >= kTapSpamFrom ? render::SceneState::kTapSpam : render::SceneState::kPoked;
  const uint8_t v = pick(a, model_.mood, 0, render::Outcome::kNone, render::StartCtx::kNone, rng);
  change(t, [&] { playAnim(a, t, CutBy::kTap, 1, model_.mood, v); });
  return render::stateName(a);
}

const char* Behaviour::press(uint32_t t, Rng& rng) {
  if (noApp(t) || !(model_.attn || model_.idle > 0)) return tap(t, rng);
  taps_ = 0;
  // While something needs you its sign stays up: the Mac opens it.
  gesture(render::Gesture::kHandoff, t);
  return "handoff";
}

void Behaviour::gesture(render::Gesture g, uint32_t t) {
  if (held(t)) return;
  const int n = face_->variants(model_.mood, render::SceneState::kGesture);
  const uint8_t v = uint8_t(int(g) < n ? int(g) : 0);
  change(t, [&] { playAnim(render::SceneState::kGesture, t, CutBy::kTap, 1, model_.mood, v); });
}

// BOOT held: listening at once, even while something needs you, cutting
// whatever else plays as a tap would. Already listening (the Mac's own
// mic), it carries on with the same design.
void Behaviour::talkOn(uint32_t t, Rng& rng) {
  change(t, [&] {
    if (listening(t)) {
      reaction_.ms = (t - reaction_.at) + kListenMs + kReplyWaitMs;
    } else {
      uint8_t v = pick(render::SceneState::kListening, model_.mood, 0, render::Outcome::kNone, render::StartCtx::kNone, rng);
      endSay(t, CutBy::kTap);
      playAnim(render::SceneState::kListening, t, CutBy::kTap, 1, model_.mood, v);
    }
  });
}

// Let go, or capped: listening carries on, with no new blend, and waits
// at most kReplyWaitMs for the reply. If it isn't playing any more (the
// Mac ended it), there's nothing to wait on.
void Behaviour::talkOff(uint32_t t) {
  change(t, [&] {
    if (listening(t) && reaction_.ms > (t - reaction_.at) + kReplyWaitMs)
      reaction_.ms = (t - reaction_.at) + kReplyWaitMs;
  });
}

// ---- What shows ------------------------------------------------------------

render::SceneState Behaviour::look(uint32_t t) const {
  if (noApp(t)) return render::SceneState::kNoApp;
  return model_.attn ? render::SceneState::kNeedsYou : model_.look();
}

// No app shows over everything; then an animation (listening only, while
// something needs you) over the look: needs you's, or what the agents are
// doing, idle, working or asleep.
Behaviour::Source Behaviour::sourceAt(uint32_t t) const {
  Source s;
  if (noApp(t)) {  // no Mac to pick a variation: the first
    s.look = render::SceneState::kNoApp;
    s.mood = model_.mood;
    return s;
  }
  s.mood = exprOn(t) ? exprMood_ : model_.mood;  // the reaction's expression, or the mood
  s.look = model_.attn ? render::SceneState::kNeedsYou : model_.look();
  s.lookVariant = face_->lookVariant();
  if (reactionOn(t)) {
    s.anim = reaction_.anim;
    s.at = reaction_.at;
    s.animVariant = reaction_.variant;
    s.loops = reaction_.loops;
    s.id = reaction_.id;
    s.outcome = reaction_.requestedOutcome;
    s.ctx = reaction_.ctx;
    s.playMs = reaction_.playMs;
  }
  return s;
}

render::FaceContext Behaviour::contextAt(uint32_t t) const {
  render::FaceContext c;
  c.mood = model_.mood;
  c.look = model_.look();
  c.working = model_.base == render::SceneState::kWorking;
  c.mayVary = !held(t) && !reactionOn(t) && !exprOn(t);
  c.base = model_.base;
  c.act = model_.act;
  c.attention = model_.attn;
  c.borrowed = exprOn(t);
  c.attentionId = model_.attnId;
  c.agent = model_.agent;
  c.project = model_.project;
  c.thread = model_.name;
  c.more = model_.more;
  c.when = model_.when;
  c.lookMs = t - lookAt_;
  c.pace = c.working && look(t) != render::SceneState::kNeedsYou ? render::workPace(model_.busy) : 100;
  return c;
}

// The design and its clock: an animation's from when it began, starting
// over each loop and resting on its last frame once its loops are over, a
// look's from when the look began. On top: a blink, or the blink that hides
// a change of design; the mouth an "o" while the take is loud;
// and the press's dip.
render::SceneShow Behaviour::show(uint32_t t) const {
  bool mouth = false;
  if (sayOn(t)) {
    uint32_t lt = t - say_.at;
    mouth = lt < say_.speakMs && voice::sayMouthOpen(say_.take, say_.then, lt);
  }
  return face_->show(t, mouth, pressed_ ? kPressPx : 0);
}

bool Behaviour::pressEasing(uint32_t t) const { return pressed_ && within(t, pressAt_, kPressEaseMs); }


// Amber at half while something needs you; otherwise off.
uint32_t Behaviour::led(uint32_t t) const {
  if (noApp(t)) return 0;
  return model_.attn ? kAmberDim : 0;
}

// Dims with the asleep look, eased over kBacklightEaseMs.
uint8_t Behaviour::backlight(uint32_t t) const {
  if (blOverride_) return blSet_;
  int target = blLevel_;
  if (!blFade_ || !within(t, blAt_, kBacklightEaseMs)) return uint8_t(target);
  return uint8_t(blFrom_ + (target - blFrom_) * render::ease(int(t - blAt_), int(kBacklightEaseMs)) / 1024);
}

void Behaviour::setFaceDown(bool down, uint32_t t) {
  change(t, [&] {
    faceDown_ = down;
    if (down && say_.take >= 0) endSay(t, CutBy::kNone);
    if (down) sign_ = Sign{};
  });
}

uint8_t Behaviour::blTarget(uint32_t t) const {
  if (noApp(t)) return 60;      // dimmed like asleep
  if (model_.attn) return 255;  // dimming never hides "needs you"
  if (faceDown_) return 20;     // face down: do not disturb
  if (model_.base == render::SceneState::kAsleep) return 60;
  return 255;
}

bool Behaviour::finishOn(uint32_t t) const {
  bool finish =
      reaction_.anim == render::SceneState::kTaskComplete || reaction_.anim == render::SceneState::kReplyReady;
  return reactionOn(t) && finish && reaction_.agent[0];
}

uint32_t Behaviour::finishShown(uint32_t t) const { return finishOn(t) ? reaction_.id : 0; }

// With no app the Mac's counts are stale, so only the unplugged
// icon shows. While the brain's finish plays, whose
// turn it was.
render::Strip Behaviour::stripOf(const Model& m, bool noApp, const Reaction* finish) {
  render::Strip s;
  s.noApp = noApp;
  if (s.noApp) return s;
  s.busy = m.busy;
  s.idle = m.idle;
  s.helpers = m.helpers;
  if (m.attn) s.agent = m.agent, s.project = m.project, s.name = m.name, s.more = m.more;
  if (finish) s.doneAgent = finish->agent, s.doneThread = finish->thread, s.doneOutcome = finish->outcome;
  return s;
}

// Every change goes through change(), so the strip comes and goes only at
// one, at the exact millisecond it did: a message's, or a time-based
// change's that advance stops at (no app, a finish ending).
void Behaviour::followLane(uint32_t t) {
  const bool shows = stripAt(t).shows();
  if (shows) laneModel_ = model_, laneFinish_ = reaction_, laneNoApp_ = noApp(t), laneFinishes_ = finishOn(t);
  lane_.retarget(shows ? 1000 : 0, t);
}

render::Strip Behaviour::strip(uint32_t t) const {
  render::Strip s;
  if (lane_.target())
    s = stripAt(t);
  else if (lane_.value(t))
    s = stripOf(laneModel_, laneNoApp_, laneFinishes_ ? &laneFinish_ : nullptr);
  s.opacity = lane_.value(t);
  return s;
}

// With no app, no `say` shows: it outranks the reactions.
const char* Behaviour::bubble(uint32_t t) const { return sayOn(t) && !noApp(t) ? say_.text : nullptr; }

render::SignShow Behaviour::sign(uint32_t t) const {
  render::SignShow s;
  if (signOn(t) && !noApp(t) && !model_.attn) s.text = sign_.text, s.ms = t - sign_.at;
  return s;
}

bool Behaviour::sayAhead(uint32_t t) const { return sayDue(t) && !sayOn(t); }

render::SceneState Behaviour::reaction(uint32_t t, uint32_t& left) const {
  if (!reactionOn(t)) {
    left = 0;
    return render::SceneState::kNone;
  }
  left = reaction_.at + reaction_.ms - t;
  return reaction_.anim;
}

bool Behaviour::speaking(uint32_t t) const { return sayOn(t) && within(t, say_.at, say_.speakMs); }

}  // namespace app
