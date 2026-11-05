#include "app/behaviour.h"

#include "app/touch_reason.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
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
    case CutBy::kMicOn: return "mic_on";
    case CutBy::kFaceDown: return "facedown";
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

// A Mac that goes to sleep is no news to a Boop already asleep: it sleeps on
// with no plug, until a touch shows why nothing answers. Its model is the
// last state, which nothing changes while the Mac is silent.
bool Behaviour::sleptThrough() const {
  return !touchedAlone_ && model_.base == render::SceneState::kAsleep && !model_.attn;
}

// Awake alone, Boop rests and the small plug says the Mac is gone. It falls
// asleep on the board's own clock, and that sleep has no plug either: a
// touch wakes it and shows it. So the plug is never on a sleeping Boop.
bool Behaviour::sleepsOn(uint32_t t) const { return noApp(t) && (aloneAsleep_ || sleptThrough()); }

bool Behaviour::reactionOn(uint32_t t) const {
  return reaction_.anim != render::SceneState::kNone && within(t, reaction_.at, reaction_.ms);
}

bool Behaviour::listening(uint32_t t) const {
  return reactionOn(t) && reaction_.anim == render::SceneState::kListening;
}

// What shows, first first: listening, needs you, then a tap's poke and the
// reactions, then the look. So while something needs you and while listening
// waits for the reply, a tap only dips the face. With no app a stale needs
// you holds nothing: a touch gets the board's own reaction.
bool Behaviour::held(uint32_t t) const { return (model_.attn && !noApp(t)) || listening(t); }

// Whether the face and sign of `in` are held at t: as held(t), but the
// reply to what you said shows over needs you, as listening does.
bool Behaviour::heldFrom(const ReactionIn& in, uint32_t t) const {
  const bool reply = in.expr && in.reply[0];
  return noApp(t) || (model_.attn && !reply) || listening(t);
}

bool Behaviour::sayOn(uint32_t t) const { return say_.take >= 0 && within(t, say_.at, say_.ms); }

bool Behaviour::sayDue(uint32_t t) const {
  return say_.take >= 0 && int32_t(t - say_.at) < int32_t(say_.ms);
}

bool Behaviour::exprOn(uint32_t t) const { return expr_ && within(t, exprAt_, exprMs_); }

bool Behaviour::signOn(uint32_t t) const { return sign_.text[0] && within(t, sign_.at, sign_.ms); }

bool Behaviour::signDue(uint32_t t) const { return sign_.text[0] && int32_t(t - sign_.at) < int32_t(sign_.ms); }

bool Behaviour::askOn(uint32_t t) const { return ask_.q[0] && within(t, ask_.at, kAskMs); }

bool Behaviour::expression(uint32_t t, render::Mood& mood) const {
  if (!exprOn(t)) return false;
  mood = exprMood_;
  return true;
}

void Behaviour::advance(uint32_t t, Rng& rng) {
  // The stream's words finish on their own; with no app, nothing works.
  if (noApp(t)) stream_.clear();
  stream_.prune(t);
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
    if (done_.agent[0] && done_.ending) consider(done_.endAt + done_.endMs);
    if (done_.agent[0] && !done_.signUp) consider(done_.at + kFinishSignByMs);
    if (say_.take >= 0) consider(say_.at + say_.ms);
    if (expr_) consider(exprAt_ + exprMs_);
    if (sign_.text[0]) consider(sign_.at + sign_.ms);
  if (reason_.text[0]) consider(reason_.at + reason_.ms);
    if (ask_.q[0]) consider(ask_.at + kAskMs);
    consider(lastState_ + kNoAppMs);
    if (stale_ && !aloneAsleep_) consider(aloneFrom_ + kAloneSleepMs);
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

// Time-based changes at t: a reaction or its expression that has ended, the
// finished turn it named lingering, then gone, and the Mac's silence
// turning into "no app". First the timers that have run out are cleared,
// so none comes back when the clock's differences wrap after 2^31 ms
// (24.9 days); none of them is part of the source, so the face doesn't
// change.
void Behaviour::resync(uint32_t t) {
  if (say_.take >= 0 && !sayDue(t)) say_ = Say{};
  if (sign_.text[0] && !signDue(t)) signGoes(signEnd());
  if (gone_.text[0] && !within(t, goneAt_, render::rig::kFadeMs)) gone_ = Sign{};
  if (blFade_ && !within(t, blAt_, kBacklightEaseMs)) blFade_ = false;
  bar_.sweep(t);
  change(t, [&] {
    if (reaction_.anim != render::SceneState::kNone && !within(t, reaction_.at, reaction_.ms))
      reaction_.anim = render::SceneState::kNone;
    if (expr_ && !within(t, exprAt_, exprMs_)) expr_ = false;
    if (ask_.q[0] && !askOn(t)) endAsk("ignored", ask_.at + kAskMs);
    // The finished turn lingers from the instant no part of its reaction
    // plays, then goes.
    if (done_.agent[0] && !done_.ending && !holds(done_.key, t))
      done_.ending = true, done_.endAt = t, done_.endMs = kFinishLingerMs;
    liftFinishSign(t);
    if (done_.agent[0] && done_.ending && !within(t, done_.endAt, done_.endMs)) done_ = Done{};
    if (greetKey_ && !holds(greetKey_, t)) greetKey_ = 0, followStream(t);
    if (!stale_ && int32_t(t - lastState_) >= int32_t(kNoAppMs)) stale_ = true, aloneFrom_ = t, lookAt_ = t;
    if (stale_ && !aloneAsleep_ && !within(t, aloneFrom_, kAloneSleepMs)) aloneAsleep_ = true, lookAt_ = t;
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
  return (reactionOn(t) && reaction_.key == key) || (sayDue(t) && say_.key == key) || (exprOn(t) && exprKey_ == key) ||
         (signDue(t) && sign_.key == key) || (askOn(t) && ask_.key == key);
}

// The first cut is the one reported.
void Behaviour::cut(uint32_t key, CutBy by) {
  if (playing_.key == key && playing_.by == CutBy::kNone) playing_.by = by;
}

// A greeting's sign is its point: one taken down before its time was cut, by
// this, whatever a touch reported before it, and the Mac tells it again.
void Behaviour::greetingSignCut(CutBy by, uint32_t t) {
  if (greetKey_ && signDue(t) && sign_.key == greetKey_ && playing_.key == greetKey_) playing_.by = by;
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
  if (ask_.q[0]) consider(ask_.at + kAskMs);
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
    const bool back = noApp(t);
    bool look = back || m.attn != model_.attn || m.look() != model_.look();
    if (m.wish != render::WishShow::kNone) lastWish_ = m.wish;
    bar_.heard(m.xp, render::growthStage(model_.when), render::growthStage(m.when), barHidden(m, back, t), t);
    model_ = m;
    if (look) lookAt_ = t, face_->newLook();
    lastState_ = t;
    stale_ = false;
    touchedAlone_ = aloneAsleep_ = false;
    blOverride_ = false;
    if (fresh) {  // a new needs-you: its performance plays from the start, and it wins
      alerted_ = true, alertAt_ = t, ++alerts_;
      face_->alert(t, had);
      // Listening is the one reaction that plays on, so
      // push-to-talk still works.
      if (reactionOn(t) && !listening(t))
        cut(reaction_.key, CutBy::kNeedsYou), reaction_.anim = render::SceneState::kNone;
      done_ = Done{};  // its own screen takes the face at once
      if (sayDue(t)) cut(say_.key, CutBy::kNeedsYou);
      greetingSignCut(CutBy::kNeedsYou, t);
      greetKey_ = 0;
      say_ = Say{};  // no `say`, sign or ask while something needs you
      if (ask_.q[0]) endAsk("ignored", t);
      sign_ = gone_ = reason_ = Sign{};
      expr_ = false;
    }
    // Answered on the Mac (`attn` leaves), or back after no app: the face
    // shows what the state says. The Mac's return gets a small hello of the
    // board's own, unless Boop has something else to show or is asleep. A
    // first state after power-on isn't a return.
    if (back && heard_ && !m.attn && m.base != render::SceneState::kAsleep && !faceDown_ && !listening(t))
      playAnim(render::SceneState::kNotice, t, CutBy::kNone, 1, m.mood, 0);
    heard_ = true;
  });
  followStream(t);
}

void Behaviour::followStream(uint32_t t) {
  const Model& m = model_;
  const bool greeting = greetingOn(t);
  // A greeting clears the words at once, and they fall again after it, on
  // the clock they'd have kept, as after a needs-you.
  const bool held = m.attn || greeting;  // each holds the screen
  stream_.setLanes(m.lanes, greeting ? 0 : m.laneCount, m.base == render::SceneState::kWorking && !held, held, t);
  stream_.setAct(greeting ? render::Stream::ActIn{} : m.workAct, held || listening(t), t);
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
// reaction, a finish or a face without a `say`; only a met wish's heart goes
// on over it. A listening reaction while listening carries on with the same
// design, its time starting over.
// The reply to what you said (`reply`, with a face) shows over needs you
// too, as listening did: its face, its clip and its sign, but no `say`;
// then the needs-you screen is back.
// Which parts of `in` play at t. With no app no reaction from the Mac does.
Behaviour::Parts Behaviour::partsOf(const ReactionIn& in, uint32_t t) const {
  Parts p;
  const bool listen = in.anim == render::SceneState::kListening;
  p.anim = in.anim != render::SceneState::kNone && (listen || !(noApp(t) || held(t)));
  p.say = in.take >= 0 && !model_.attn && !noApp(t);
  p.face = in.expr && !heldFrom(in, t);  // listening, if it's still on, holds the face
  p.sign = in.sign[0] && !heldFrom(in, t);
  return p;
}

const char* Behaviour::admit(const ReactionIn& in, uint32_t t) {
  const bool listen = in.anim == render::SceneState::kListening;
  const bool wasListening = listening(t);
  if (wasListening && !listen && (in.said || in.empty)) change(t, [&] { reaction_.anim = render::SceneState::kNone; });
  if (in.empty) return wasListening ? nullptr : "not_listening";
  if (faceDown_ && !listen) return "facedown";  // do not disturb
  if (partsOf(in, t).any()) return nullptr;
  if (noApp(t)) return "no_app";
  if (noteOnly(in)) return listening(t) ? "listening" : model_.attn ? "needs_you" : nullptr;
  // Push-to-talk met it, with listening still waiting for the reply: its heart
  // goes on, over the listening face.
  if (listening(t)) return in.wishMet ? nullptr : "listening";
  if (model_.attn) return "needs_you";
  return in.wishMet ? nullptr : "nothing";
}

bool Behaviour::play(const ReactionIn& in, uint32_t t) {
  const bool listen = in.anim == render::SceneState::kListening;
  const Parts parts = partsOf(in, t);
  const bool anim = parts.anim, say = parts.say, face = parts.face, sign = parts.sign;
  if (!parts.any()) return false;  // stop_listening: admit did it all
  // The Mac's words for the touch the board already said why of.
  const bool own = in.reason[0] && ownReason_[0] && within(t, ownReasonAt_, kOwnReasonMs) &&
                   !std::strcmp(in.reason, ownReason_);
  const Sign ownUp = own && within(t, reason_.at, reason_.ms) ? reason_ : Sign{};
  change(t, [&] {
    // A newer reaction ends the ask that's up, unanswered.
    if (ask_.q[0]) endAsk("ignored", t);
    // A reaction from the Mac takes the finished turn named down, unless
    // it names one itself: its animation a finish, or none.
    const bool finish = in.anim == render::SceneState::kTaskComplete || in.anim == render::SceneState::kReplyReady;
    const bool names = in.whoAgent && in.whoAgent[0] && (anim ? finish : in.anim == render::SceneState::kNone);
    if (!names) takeDown(t);
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
      copyStr(exprReply_, sizeof(exprReply_), in.reply[0] ? in.reply : in.clip);
      exprMs_ = anim ? reaction_.ms : holdMs(in.mood, in.loops, t);
      if (say && voice + say_.ms > exprMs_) exprMs_ = voice + say_.ms;
      exprKey_ = in.key;
    }
    if (sign) {  // as long as the rest of it plays, from now, and long enough to read
      copyStr(sign_.text, sizeof(sign_.text), in.sign);
      sign_.reply = in.expr && in.reply[0];
      sign_.low = in.low;
      sign_.at = t;
      sign_.ms = in.low ? kLowSignMinMs : kSignMinMs;
      if (anim && !listen) sign_.ms = std::max(sign_.ms, reaction_.ms);
      if (say) sign_.ms = std::max(sign_.ms, voice + say_.ms);
      if (in.expr) sign_.ms = std::max(sign_.ms, exprMs_);
      sign_.key = in.key;
      // A greeting's or a low one's waits until its words end, as a finish's
      // name does, and the face it came with holds while it's read.
      if ((in.greeting || in.low) && say) {
        sign_.at = say_.at + say_.speakMs;
        sign_.ms = in.low ? kLowSignMinMs : kSignMinMs;
        if (in.expr) exprMs_ = std::max(exprMs_, sign_.at + sign_.ms - exprAt_);
      }
    }
    // Why it plays, in the lane, as long as its sign would show; a newer
    // reaction with none takes the old one down.
    reason_ = Sign{};
    if (in.reason[0] && (anim || face || say || sign)) {
      copyStr(reason_.text, sizeof(reason_.text), in.reason);
      reason_.reply = in.expr && in.reply[0];
      reason_.at = t;
      reason_.ms = kSignMinMs;
      if (anim && !listen) reason_.ms = std::max(reason_.ms, reaction_.ms);
      if (say) reason_.ms = std::max(reason_.ms, voice + say_.ms);
      if (in.expr) reason_.ms = std::max(reason_.ms, exprMs_);
      reason_.key = in.key;
      if (own) {
        // One caption, on through this too; with it gone, not again.
        const uint32_t ms = reason_.ms;
        reason_ = ownUp;
        if (reason_.text[0]) reason_.ms = std::max(reason_.ms, (t - reason_.at) + ms);
      }
    }
    // An ask: its question stays up, and its answers fill the lane, until
    // a tap on one, a touch when it takes one, a newer reaction, or kAskMs.
    if (in.askQ[0] && sign) {
      ask_ = Ask{};
      copyStr(ask_.q, sizeof(ask_.q), in.askQ);
      copyStr(ask_.question, sizeof(ask_.question), in.sign);
      copyStr(ask_.a, sizeof(ask_.a), in.askA);
      copyStr(ask_.b, sizeof(ask_.b), in.askB);
      // The answers either side of the lane's middle: the shorter padded
      // to the longer, so the gap between them sits where a tap splits.
      const int la = int(std::strlen(ask_.a)), lb = int(std::strlen(ask_.b)), w = std::max(la, lb);
      std::snprintf(ask_.lane, sizeof(ask_.lane), "%*s    %-*s", w, ask_.a, w, ask_.b);
      ask_.touch = in.askTouch;
      ask_.at = t, ask_.key = in.key;
      sign_.ms = std::max(sign_.ms, kAskMs);
      reason_ = Sign{};
    }
    if (names) {
      done_ = Done{};
      copyStr(done_.agent, sizeof(done_.agent), in.whoAgent);
      copyStr(done_.thread, sizeof(done_.thread), in.whoThread);
      done_.outcome = anim ? reaction_.outcome : render::Outcome::kNone;
      done_.id = in.id, done_.key = in.key, done_.at = t;
      liftFinishSign(t);
    }
    if (in.key) playing_ = PlayedOut{in.key, CutBy::kNone};
    greetKey_ = in.greeting ? in.key : 0;
    followStream(t);
  });
  return say;
}

uint8_t Behaviour::pick(render::SceneState a, render::Mood mood, int wanted, render::Outcome o, render::StartCtx c,
                        Rng& rng, int loops, int turn) const {
  return face_->pick(a, mood, wanted, o, c, rng, loops, turn);
}

// The animation playing is cut short, by `by`; the `say` and the
// expression play on (endSay ends them).
void Behaviour::playAnim(render::SceneState a, uint32_t t, CutBy by, int loops, render::Mood mood, uint8_t variant,
                         render::Outcome outcome, render::StartCtx ctx) {
  if (by != CutBy::kNone && reactionOn(t)) cut(reaction_.key, by);
  reaction_ = Reaction{};
  takeDown(t);  // the face is taken
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
  if (signOn(t)) signGoes(t);
  sign_ = reason_ = Sign{};
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
  touchAlone(t);
}

void Behaviour::touchAlone(uint32_t t) {
  if (noApp(t)) change(t, [&] { touchedAlone_ = true, aloneAsleep_ = false, aloneFrom_ = t; });
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
  touchAlone(t);
  bool inRun = taps_ > 0 && int32_t(t - lastTap_) < int32_t(kTapRunMs);
  taps_ = inRun ? std::min(taps_ + 1, 1000) : 1;
  lastTap_ = t;
  if (held(t) || finishShown(t)) return "dip";
  const render::SceneState a = taps_ >= kTapSpamFrom ? render::SceneState::kTapSpam : render::SceneState::kPoked;
  const uint8_t v = pick(a, model_.mood, 0, render::Outcome::kNone, render::StartCtx::kNone, rng);
  change(t, [&] { playAnim(a, t, CutBy::kTap, 1, model_.mood, v); });
  if (face_->captionsTouches()) {
    char text[kSignBytes];
    pokeReason(taps_, model_.base == render::SceneState::kAsleep, buddyName(), kSignGlyphs, text, sizeof(text));
    showOwn(text, t);
  }
  return render::stateName(a);
}

const char* Behaviour::press(uint32_t t, Rng& rng) {
  if (noApp(t) || !(model_.attn || model_.idle > 0)) return tap(t, rng);
  taps_ = 0;
  // While something needs you its screen stays up: the Mac opens it.
  gesture(render::Gesture::kHandoff, t);
  return "handoff";
}

void Behaviour::gesture(render::Gesture g, uint32_t t) {
  touchAlone(t);
  if (held(t) || (g != render::Gesture::kHandoff && finishShown(t))) return;
  const int n = face_->variants(model_.mood, render::SceneState::kGesture);
  const uint8_t v = uint8_t(int(g) < n ? int(g) : 0);
  change(t, [&] { playAnim(render::SceneState::kGesture, t, CutBy::kTap, 1, model_.mood, v); });
  touchCaption(render::gestureName(g), t);
}

const char* Behaviour::buddyName() const { return model_.buddy[0] ? model_.buddy : render::kBuddyName; }

void Behaviour::touchCaption(const char* gesture, uint32_t t) {
  char text[kSignBytes];
  if (face_->captionsTouches() && touchReason(gesture, buddyName(), kSignGlyphs, text, sizeof(text))) showOwn(text, t);
}

// Long enough to read, and no more, since it has the strip's place in the lane;
// a say's bubble goes on above it.
void Behaviour::showOwn(const char* text, uint32_t t) {
  change(t, [&] {
    copyStr(ownReason_, sizeof(ownReason_), text);
    ownReasonAt_ = t;
    setReason(text, t);
  });
}

void Behaviour::setReason(const char* text, uint32_t t) {
  reason_ = Sign{};
  copyStr(reason_.text, sizeof(reason_.text), text);
  reason_.at = t;
  reason_.ms = kSignMinMs;
}

bool Behaviour::noteOnly(const ReactionIn& in) {
  return in.reason[0] && in.anim == render::SceneState::kNone && !in.expr && !in.said && !in.empty && !in.sign[0] &&
         !in.askQ[0] && !in.wishMet;
}

void Behaviour::note(const char* text, uint32_t t) {
  change(t, [&] {
    if (!(reason_.text[0] && within(t, reason_.at, reason_.ms))) setReason(text, t);
  });
}

// BOOT held: listening at once, even while something needs you, cutting
// whatever else plays as a tap would. Already listening (the Mac's own
// mic), it carries on with the same design.
void Behaviour::talkOn(uint32_t t, Rng& rng) {
  if (noApp(t)) return;  // nobody to hear it
  change(t, [&] {
    if (listening(t)) {
      reaction_.ms = (t - reaction_.at) + kListenMs + kReplyWaitMs;
    } else {
      uint8_t v = pick(render::SceneState::kListening, model_.mood, 0, render::Outcome::kNone, render::StartCtx::kNone, rng);
      if (ask_.q[0]) endAsk("ignored", t);
      greetingSignCut(CutBy::kMicOn, t);
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
  if (noApp(t)) return sleepsOn(t) ? render::SceneState::kAsleep : render::SceneState::kIdle;
  return model_.attn ? render::SceneState::kNeedsYou : model_.look();
}

// An animation (listening only, while something needs you) over the look:
// needs you's, or what the agents are doing, idle, working or asleep. With
// no app, the board's own touches over resting or asleep, in the last mood:
// what the Mac asked for is over.
Behaviour::Source Behaviour::sourceAt(uint32_t t) const {
  Source s;
  const bool alone = noApp(t);
  s.mood = !alone && exprOn(t) ? exprMood_ : model_.mood;  // the reaction's expression, or the mood
  s.look = look(t);
  s.lookVariant = alone ? 0 : face_->lookVariant();  // no Mac to pick a variation: the first
  const bool own = reaction_.anim == render::SceneState::kPoked || reaction_.anim == render::SceneState::kTapSpam ||
                   reaction_.anim == render::SceneState::kGesture;
  if (reactionOn(t) && (!alone || own)) {
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
  const bool alone = noApp(t);
  c.alone = alone;
  if (alone) {
    c.look = c.base = look(t);
    c.working = c.mayVary = c.attention = c.borrowed = false;
    c.act = render::FaceContext{}.act;
  }
  if (c.borrowed) c.reply = exprReply_, c.replyAt = exprAt_;
  c.attentionId = model_.attnId;
  c.agent = model_.agent;
  c.project = model_.project;
  c.thread = model_.name;
  c.more = model_.more;
  // With no app the Mac's tags are stale: a night's or a holiday's would
  // stay up all the next day. Its growth stage isn't: a Hatchling stays one.
  c.when = alone && !sleptThrough() ? model_.when & render::kGrowthTags : model_.when;
  c.lookMs = t - lookAt_;
  c.growthWaits = bar_.waits(t);
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
    if (down) greetingSignCut(CutBy::kFaceDown, t);
    if (down && say_.take >= 0) endSay(t, CutBy::kNone);
    if (down && signOn(t)) signGoes(t);
    if (down && ask_.q[0]) endAsk("ignored", t);
    if (down) sign_ = reason_ = Sign{};
  });
}

uint8_t Behaviour::blTarget(uint32_t t) const {
  if (noApp(t)) return faceDown_ ? 20 : sleepsOn(t) ? 60 : 255;  // dimmed as with the Mac
  if (model_.attn) return 255;  // dimming never hides "needs you"
  if (faceDown_) return 20;     // face down: do not disturb
  if (model_.base == render::SceneState::kAsleep) return 60;
  return 255;
}

const Behaviour::Done* Behaviour::finishOn(uint32_t t) const {
  if (!done_.agent[0] || !done_.named) return nullptr;
  return !done_.ending || within(t, done_.endAt, done_.endMs) ? &done_ : nullptr;
}

void Behaviour::takeDown(uint32_t t) {
  if (!done_.agent[0] || !done_.named) return;
  // One already lingering may go sooner than it would leave.
  const bool sooner = done_.ending && !after(done_.endAt + done_.endMs, t + kDoneLeaveMs);
  done_.named = false;
  if (!sooner) done_.ending = true, done_.endAt = t, done_.endMs = kDoneLeaveMs;
}

// As its reaction's words end, at once with none, or kFinishSignByMs in.
void Behaviour::liftFinishSign(uint32_t t) {
  if (!done_.agent[0] || done_.signUp) return;
  const bool talking = sayDue(t) && say_.key == done_.key;
  if (!talking || int32_t(t - done_.at) >= int32_t(kFinishSignByMs)) done_.signUp = true, done_.signAt = t;
}

const Behaviour::Done* Behaviour::stripFinish(uint32_t t) const {
  const Done* f = finishOn(t);
  return f && f->signUp && face_->holdsUpFinish() ? nullptr : f;
}

uint32_t Behaviour::finishShown(uint32_t t) const {
  const Done* f = finishOn(t);
  return f ? f->id : 0;
}

render::DoneShow Behaviour::done(uint32_t t) const {
  render::DoneShow d;
  if (!done_.agent[0] || noApp(t) || model_.attn) return d;
  if (done_.ending && !within(t, done_.endAt, done_.endMs)) return d;
  d.agent = done_.agent, d.thread = done_.thread, d.outcome = done_.outcome;
  d.ms = t - done_.at;
  d.leftMs = done_.ending ? int32_t(done_.endAt + done_.endMs - t) : -1;
  if (done_.signUp) d.signMs = int32_t(t - done_.signAt);
  return d;
}

// With no app the Mac's counts are stale, so only the unplugged
// icon shows. While the brain's reaction to a finished turn plays, and as
// it lingers, whose turn it was.
render::Strip Behaviour::stripOf(const Model& m, bool noApp, const Done* finish) {
  render::Strip s;
  s.noApp = noApp;
  if (s.noApp) return s;
  s.busy = m.busy;
  s.idle = m.idle;
  s.helpers = m.helpers;
  // The Mac sends a to-do list only while an agent works and nothing
  // needs you.
  s.todoDone = m.todoDone;
  s.todoTotal = m.todoTotal;
  static constexpr const char* kWishWords[] = {nullptr, "pet", "chat", "work"};
  s.wish = kWishWords[m.wish];
  if (m.attn) s.agent = m.agent, s.project = m.project, s.name = m.name, s.more = m.more;
  if (finish) s.doneAgent = finish->agent, s.doneThread = finish->thread, s.doneOutcome = finish->outcome;
  return s;
}

// Every change goes through change(), so the strip comes and goes only at
// one, at the exact millisecond it did: a message's, or a time-based
// change's that advance stops at (no app, a finish's linger ending).
void Behaviour::followLane(uint32_t t) {
  const bool shows = stripAt(t).shows();
  const Done* finish = stripFinish(t);
  if (shows) laneModel_ = model_, laneNoApp_ = plugShows(t), laneFinishes_ = finish != nullptr;
  if (shows && finish) laneFinish_ = *finish;
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

render::WishShow Behaviour::wishShow(uint32_t t) const {
  render::WishShow show;
  if (noApp(t)) return show;  // nothing waits on a Mac that isn't there
  if (wishPop_ != render::WishShow::kWaiting && t - wishPopAt_ < render::WishShow::kPopMs) {
    show.kind = lastWish_, show.pop = wishPop_, show.popAge = t - wishPopAt_;
    show.flies = wishPop_ == render::WishShow::kMet && bar_.heart();
  } else {
    show.kind = model_.wish;
    show.how = model_.wishHow;
    show.ms = t;
  }
  return show;
}

void Behaviour::wishPopped(bool met, uint32_t t) {
  if (lastWish_ == render::WishShow::kNone) return;
  wishPop_ = met ? render::WishShow::kMet : render::WishShow::kGone;
  wishPopAt_ = t;
  if (!met) return;
  bar_.heartComes(model_.xp, t);
}

bool Behaviour::barHidden(const Model& m, bool alone, uint32_t t) const {
  return alone || m.attn || m.base == render::SceneState::kAsleep || faceDown_;
}

render::GrowthShow Behaviour::growthShow(uint32_t t) const {
  return bar_.show(render::growthStage(model_.when), barHidden(model_, noApp(t), t), t);
}

// With no app, no `say` shows: it outranks the reactions.
const char* Behaviour::bubble(uint32_t t) const { return sayOn(t) && !noApp(t) ? say_.text : nullptr; }

const char* Behaviour::laneBubble(uint32_t t) const {
  if (const char* said = bubble(t)) return said;
  return asking(t) ? ask_.lane : nullptr;
}

const char* Behaviour::caption(uint32_t t) const {
  if (asking(t) || !reason_.text[0] || !within(t, reason_.at, reason_.ms) || noApp(t)) return nullptr;
  if (model_.attn && !reason_.reply) return nullptr;
  // A low sign and a finish's ticket have the lane's foot.
  if ((sign_.low && signOn(t)) || finishShown(t)) return nullptr;
  return reason_.text;
}

bool Behaviour::asking(uint32_t t) const { return askOn(t) && !noApp(t) && !model_.attn; }

bool Behaviour::answer(const char* pick, uint32_t t, bool injected) {
  if (!asking(t) || (!std::strcmp(pick, "touch") && !ask_.touch)) return false;
  change(t, [&] { endAsk(pick, t, injected); });
  return true;
}

void Behaviour::endAsk(const char* pick, uint32_t t, bool injected) {
  askEnd_ = AskEnd{};
  copyStr(askEnd_.q, sizeof(askEnd_.q), ask_.q);
  copyStr(askEnd_.question, sizeof(askEnd_.question), ask_.question);
  askEnd_.pick = pick;
  if (!std::strcmp(pick, "a") || !std::strcmp(pick, "touch")) copyStr(askEnd_.answer, sizeof(askEnd_.answer), ask_.a);
  if (!std::strcmp(pick, "b")) copyStr(askEnd_.answer, sizeof(askEnd_.answer), ask_.b);
  askEnd_.injected = injected;
  askEnded_ = true;
  // Its question comes down with it, unless a newer reaction's took its place.
  if (sign_.key == ask_.key && signOn(t)) {
    signGoes(t);
    sign_ = Sign{};
  }
  ask_ = Ask{};
}

void Behaviour::dropAsk(uint32_t t) {
  if (ask_.q[0]) change(t, [&] { endAsk("ignored", t); });
}

bool Behaviour::takeAskEnd(AskEnd& e) {
  if (!askEnded_) return false;
  e = askEnd_;
  askEnded_ = false;
  return true;
}

void Behaviour::signGoes(uint32_t at) {
  gone_ = sign_;
  goneAt_ = at;
}

render::SignShow Behaviour::sign(uint32_t t) const {
  render::SignShow s;
  if (noApp(t) || (model_.attn && !(signOn(t) ? sign_ : gone_).reply)) return s;
  if (signOn(t)) {
    s.text = sign_.text, s.ms = t - sign_.at, s.low = sign_.low;
    if (sign_.low) s.leftMs = int32_t(sign_.at + sign_.ms - t);
  } else if (gone_.text[0] && !gone_.low && within(t, goneAt_, render::rig::kFadeMs)) {  // a low one has fallen away
    s.text = gone_.text, s.ms = t - gone_.at;
    s.opacity = 1000 - render::ease1000(int(t - goneAt_), int(render::rig::kFadeMs));
  }
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
