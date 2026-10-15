#include "app/behaviour.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

#include "render/maths.h"
#include "voice/effects.h"
#include "voice/player.h"

namespace app {

namespace {

constexpr uint32_t kAmberDim = 0x805800;  // needs you: amber at half

bool after(uint32_t a, uint32_t b) { return int32_t(a - b) > 0; }  // a later than b
bool within(uint32_t t, uint32_t from, uint32_t ms) { return int32_t(t - from) >= 0 && int32_t(t - from) < int32_t(ms); }

}  // namespace

const char* screenName(Screen s) {
  switch (s) {
    case Screen::kFace: return "face";
    case Screen::kNeedsYou: return "needs_you";
    case Screen::kNoApp: return "no_app";
    case Screen::kPattern: return "pattern";
  }
  return "face";
}

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
// cut the call it held (dbg.reset resets its turn first).
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

bool Behaviour::momentOn(uint32_t t) const {
  return moment_.anim != render::Anim::kNone && within(t, moment_.at, moment_.ms);
}

bool Behaviour::listening(uint32_t t) const { return momentOn(t) && moment_.anim == render::Anim::kListening; }

// What shows, first first: no app, listening, needs you,
// then a tap's poke and the moments, then the look. So with no app, while
// something needs you and while listening waits for the reply, a tap only
// dips the face and a moment's animation is skipped.
bool Behaviour::held(uint32_t t) const { return noApp(t) || model_.attn || listening(t); }

bool Behaviour::sayOn(uint32_t t) const { return say_.take >= 0 && within(t, say_.at, say_.ms); }

bool Behaviour::sayDue(uint32_t t) const {
  return say_.take >= 0 && int32_t(t - say_.at) < int32_t(say_.ms);
}

bool Behaviour::exprOn(uint32_t t) const { return expr_ && within(t, exprAt_, exprMs_); }

bool Behaviour::expression(uint32_t t, render::Mood& mood) const {
  if (!exprOn(t)) return false;
  mood = exprMood_;
  return true;
}

void Behaviour::advance(uint32_t t, Rng& rng) {
  if (int32_t(t - modelT_) < 0) {  // the clock went back: no history to replay
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
    if (moment_.anim != render::Anim::kNone) consider(moment_.at + moment_.ms);
    if (say_.take >= 0) consider(say_.at + say_.ms);
    if (expr_) consider(exprAt_ + exprMs_);
    consider(lastState_ + kNoAppMs);
    uint32_t faceAt;
    if (face_->nextDue(modelT_, t, faceAt)) consider(faceAt);
    if (!found) break;
    // Everything due at `next`, in a fixed order.
    unsigned due = face_->dueAt(next);
    resync(next);
    face_->step(next, rng, due);
    change(next, [] {});
  }
  resync(t);
  face_->step(t, rng, 0);
}

// Time-based changes at t: a moment or its expression that has ended, and
// the Mac's silence turning into "no app". First the timers that have run
// out are cleared, so none comes back when the clock's differences wrap
// after 2^31 ms (24.9 days); none of them is part of the source, so the
// face doesn't change.
void Behaviour::resync(uint32_t t) {
  if (say_.take >= 0 && !sayDue(t)) say_ = Say{};
  if (blFade_ && !within(t, blAt_, kBacklightEaseMs)) blFade_ = false;
  change(t, [&] {
    if (moment_.anim != render::Anim::kNone && !within(t, moment_.at, moment_.ms)) moment_.anim = render::Anim::kNone;
    if (expr_ && !within(t, exprAt_, exprMs_)) expr_ = false;
    if (!stale_ && int32_t(t - lastState_) >= int32_t(kNoAppMs)) stale_ = true;
  });
}

// ---- Calls from the Mac: how each ended (`ended`) -----------------------

// A call is over when none of its parts plays: the animation, the line
// and its bubble, the expression. It was cut if its animation or its line
// was stopped early. Its expression holds on after its line, and ending
// that early doesn't cut it: the reaction was seen and heard. The kit
// passes on only the holder's end; a call it replaced was answered then.
bool Behaviour::holds(uint32_t call, uint32_t t) const {
  return (momentOn(t) && moment_.call == call) || (sayDue(t) && say_.call == call) ||
         (exprOn(t) && exprCall_ == call);
}

void Behaviour::wait(uint32_t call) {
  // Can't overflow: each part holds one call, and those with none left
  // were ended at the last change.
  if (owed_.nWaiting < Owed::kWaiting) owed_.waiting[owed_.nWaiting++] = Waiting{call, CutBy::kNone};
}

// The first cut is the one reported.
void Behaviour::cut(uint32_t call, CutBy by) {
  for (int i = 0; i < owed_.nWaiting; ++i) {
    Waiting& w = owed_.waiting[i];
    if (w.call == call && w.cut == CutBy::kNone) w.cut = by;
  }
}

void Behaviour::sweep(uint32_t t) {
  int kept = 0;
  for (int i = 0; i < owed_.nWaiting; ++i) {
    const Waiting w = owed_.waiting[i];
    if (holds(w.call, t)) {
      owed_.waiting[kept++] = w;
    } else {
      report(Ended{w.call, w.cut});
    }
  }
  owed_.nWaiting = kept;
}

// Device takes the ends after every line and tick, so a few are enough.
void Behaviour::report(const Ended& e) {
  if (owed_.nEnded < Owed::kEnded) owed_.ended[owed_.nEnded++] = e;
}

bool Behaviour::takeEnded(Ended& e) {
  if (owed_.nEnded == 0) return false;
  e = owed_.ended[0];
  for (int i = 1; i < owed_.nEnded; ++i) owed_.ended[i - 1] = owed_.ended[i];
  --owed_.nEnded;
  return true;
}

bool Behaviour::nextEnd(uint32_t from, uint32_t to, uint32_t& at) const {
  bool found = false;
  auto consider = [&](uint32_t c) {
    if (after(c, from) && !after(c, to) && (!found || after(at, c))) at = c, found = true;
  };
  if (moment_.anim != render::Anim::kNone) consider(moment_.at + moment_.ms);
  if (say_.take >= 0) consider(say_.at + say_.ms);
  if (expr_) consider(exprAt_ + exprMs_);
  return found;
}

// ---- Messages --------------------------------------------------------------

void Behaviour::onState(const Model& m, uint32_t t) {
  change(t, [&] {
    // A different request shown: another number, or another agent or
    // project (all a Mac that sends no number says).
    bool had = model_.attn;
    bool fresh = m.attn && (!had || m.attnId != model_.attnId || std::strncmp(model_.agent, m.agent, sizeof(m.agent)) ||
                            std::strncmp(model_.project, m.project, sizeof(m.project)));
    // Another visual, or another variation of it from the Mac, starts the
    // looks' turns over from the Mac's; the same one again leaves them.
    bool look = m.attn != model_.attn || m.look() != model_.look() || m.variant != model_.variant;
    model_ = m;
    if (look) face_->setLookVariant(m.variant);
    lastState_ = t;
    stale_ = false;
    blOverride_ = false;
    if (fresh) {  // a new request: its performance plays from the start, and attention wins
      alerted_ = true, alertAt_ = t;
      face_->alert(t, had);
      // Listening is the one moment that plays on, so
      // push-to-talk still works.
      if (momentOn(t) && !listening(t)) cut(moment_.call, CutBy::kNeedsYou), moment_.anim = render::Anim::kNone;
      if (sayDue(t)) cut(say_.call, CutBy::kNeedsYou);
      say_ = Say{};  // no lines while something needs you
      expr_ = false;
    }
    // Answered on the Mac (`attn` leaves), or back after no app: the face
    // blinks into what the state says.
  });
}

// A moment with an animation replaces the one playing, and its line too;
// the animation plays its loops of its design. A line on its own plays
// over whatever face is showing, replacing any line. With
// an animation, the line starts at its design's voice window,
// and the animation holds on until the line and its bubble are over
// rather than the line being hurried. A moment with an expression draws
// the design showing in its mood for as long as its animation plays, or
// with none for its loops of the design it's drawn in, and at least as long
// as its line and bubble; a face on its own (no animation, no line) plays
// just that, leaving any line playing. What outranks the moments:
// no app, and while something needs you no animation
// takes the face over and no line or face on its own plays. A call that
// would play nothing isn't admitted: the kit skips it, with why.
//
// Listening plays even while something needs you, and holds
// until the reply: a call with a `say` is the reply, and ends it before
// playing as it would have; so does stop_listening, which does nothing
// else. Nothing else ends it or plays while it waits: not a one-shot, a
// finish or a face without a `say`. A listening call while listening
// carries on with the same design, its time starting over.
const char* Behaviour::admit(const MomentIn& in, uint32_t t) {
  const bool listen = in.anim == render::Anim::kListening;
  const bool wasListening = listening(t);
  if (wasListening && !listen && (in.said || in.empty)) change(t, [&] { moment_.anim = render::Anim::kNone; });
  if (in.empty) return wasListening ? nullptr : "not_listening";
  bool anim = in.anim != render::Anim::kNone && (listen || !held(t));
  bool line = in.take >= 0 && !model_.attn && !noApp(t);
  bool face = in.expr && !held(t);  // listening, if it's still on, holds the face
  if (anim || line || face) return nullptr;
  if (noApp(t)) return "no_app";
  if (listening(t)) return "listening";
  if (model_.attn) return "needs_you";
  return "nothing";
}

bool Behaviour::play(const MomentIn& in, uint32_t t) {
  const bool listen = in.anim == render::Anim::kListening;
  bool anim = in.anim != render::Anim::kNone && (listen || !held(t));
  bool line = in.take >= 0 && !model_.attn && !noApp(t);
  bool face = in.expr && !held(t);
  if (!anim && !line && !face) return false;  // stop_listening: admit did it all
  change(t, [&] {
    const render::Mood mood = in.expr ? in.mood : model_.mood;  // the mood it's drawn in
    uint32_t voice = 0;  // when its line starts, from t
    if (anim && listen && listening(t)) {
      moment_.ms = (t - moment_.at) + kListenMs + kReplyWaitMs;
      moment_.call = in.call;
      moment_.id = in.id;
    } else if (anim) {
      endLine(t, CutBy::kNone);
      playAnim(in.anim, t, CutBy::kNone, in.loops, mood, in.variant, in.outcome, in.ctx);
      moment_.call = in.call;
      moment_.id = in.id;
      bool finish = in.anim == render::Anim::kTaskComplete || in.anim == render::Anim::kReplyReady;
      if (finish && in.whoAgent && in.whoAgent[0]) {
        copyStr(moment_.agent, sizeof(moment_.agent), in.whoAgent);
        copyStr(moment_.thread, sizeof(moment_.thread), in.whoThread);
      }
      if (!listen) voice = face_->voiceMs(mood, render::animState(in.anim), in.variant);
    }
    if (line) {
      startSay(in, t, t + voice);
      say_.call = in.call;
      if (anim && !listen && voice + say_.ms > moment_.ms) moment_.ms = voice + say_.ms;
    }
    if (in.expr) {
      expr_ = true;
      exprMood_ = in.mood;
      exprAt_ = t;
      exprMs_ = anim ? moment_.ms : holdMs(in.mood, in.loops, t);
      if (line && voice + say_.ms > exprMs_) exprMs_ = voice + say_.ms;
      exprCall_ = in.call;
    }
    if (in.call) wait(in.call);
  });
  return line;
}

uint8_t Behaviour::pick(render::Anim a, render::Mood mood, int wanted, render::Outcome o, render::StartCtx c,
                        Rng& rng) const {
  return face_->pick(a, mood, wanted, o, c, rng);
}

// The animation playing is cut short, by `by`; the line and the
// expression play on (endLine ends them).
void Behaviour::playAnim(render::Anim a, uint32_t t, CutBy by, int loops, render::Mood mood, uint8_t variant,
                         render::Outcome outcome, render::StartCtx ctx) {
  if (by != CutBy::kNone && momentOn(t)) cut(moment_.call, by);
  moment_ = Moment{};
  moment_.anim = a;
  moment_.variant = variant;
  moment_.loops = loops;
  moment_.at = t;
  moment_.requestedOutcome = outcome;
  moment_.ctx = ctx;
  const render::SceneState s = render::animState(a);
  if (a == render::Anim::kListening) {
    moment_.ms = kListenMs + kReplyWaitMs;
    moment_.playMs = UINT32_MAX;  // its design loops on until the reply
  } else {
    moment_.ms = moment_.playMs = uint32_t(loops) * face_->loopMs(mood, s, variant);
  }
  moment_.outcome = face_->outcome(mood, s, variant, outcome);
  face_->started(a, mood, variant, outcome, ctx);
}

// A new moment replaces the line playing, cut short by `by`, and its
// expression.
void Behaviour::endLine(uint32_t t, CutBy by) {
  if (by != CutBy::kNone && sayDue(t)) cut(say_.call, by);
  say_ = Say{};
  expr_ = false;
  ++momentSeq_;
}

// The design is the animation's while one plays, on its clock, else the
// look's, on the look's; the first loop ends at its clock's next boundary
// after t, so it can be short. A later change of look or animation doesn't
// move the end.
uint32_t Behaviour::holdMs(render::Mood mood, int loops, uint32_t t) const {
  return face_->holdMs(mood, loops, t);
}

void Behaviour::startSay(const MomentIn& in, uint32_t t, uint32_t at) {
  endLine(t, CutBy::kNone);  // a new line ends the last one and the last moment's expression
  Say& s = say_;
  s.take = in.take;
  s.then = voice::takeText(in.then) ? in.then : -1;
  std::snprintf(s.text, sizeof(s.text), s.then >= 0 ? "%s %s" : "%s", voice::takeText(in.take), voice::takeText(s.then));
  s.speakMs = voice::lineMs(s.take, s.then);
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
// third tap on, cutting the animation playing. A brain reaction's line and
// expression play on over it, so a barrage doesn't cut short the one
// answer it gets.
const char* Behaviour::tap(uint32_t t, Rng& rng) {
  bool inRun = taps_ > 0 && int32_t(t - lastTap_) < int32_t(kTapRunMs);
  taps_ = inRun ? std::min(taps_ + 1, 1000) : 1;
  lastTap_ = t;
  if (held(t) || finishShown(t)) return "dip";
  const render::Anim a = taps_ >= kTapSpamFrom ? render::Anim::kTapSpam : render::Anim::kPoked;
  const uint8_t v = pick(a, model_.mood, 0, render::Outcome::kNone, render::StartCtx::kNone, rng);
  change(t, [&] { playAnim(a, t, CutBy::kTap, 1, model_.mood, v); });
  return render::animName(a);
}

// BOOT held: listening at once, even while something needs you, cutting
// whatever else plays as a tap would. Already listening (the Mac's own
// mic), it carries on with the same design.
void Behaviour::talkOn(uint32_t t, Rng& rng) {
  change(t, [&] {
    if (listening(t)) {
      moment_.ms = (t - moment_.at) + kListenMs + kReplyWaitMs;
    } else {
      uint8_t v = pick(render::Anim::kListening, model_.mood, 0, render::Outcome::kNone, render::StartCtx::kNone, rng);
      endLine(t, CutBy::kTap);
      playAnim(render::Anim::kListening, t, CutBy::kTap, 1, model_.mood, v);
    }
  });
}

// Let go, or capped: listening carries on, with no new blend, and waits
// at most kReplyWaitMs for the reply. If it isn't playing any more (the
// Mac ended it), there's nothing to wait on.
void Behaviour::talkOff(uint32_t t) {
  change(t, [&] {
    if (listening(t) && moment_.ms > (t - moment_.at) + kReplyWaitMs) moment_.ms = (t - moment_.at) + kReplyWaitMs;
  });
}

// ---- What shows ------------------------------------------------------------

Screen Behaviour::screen(uint32_t t) const {
  if (noApp(t)) return Screen::kNoApp;
  return model_.attn ? Screen::kNeedsYou : Screen::kFace;
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
  s.mood = exprOn(t) ? exprMood_ : model_.mood;  // the moment's expression, or the mood
  if (model_.attn) {
    s.look = render::SceneState::kNeedsYou;
    s.lookVariant = model_.variant;
  } else {
    s.look = model_.look();
    s.lookVariant = face_->lookVariant();
  }
  if (momentOn(t)) {
    s.anim = moment_.anim;
    s.at = moment_.at;
    s.animVariant = moment_.variant;
    s.loops = moment_.loops;
    s.id = moment_.id;
    s.outcome = moment_.requestedOutcome;
    s.ctx = moment_.ctx;
  }
  return s;
}

render::FaceContext Behaviour::contextAt(uint32_t t) const {
  render::FaceContext c;
  c.mood = model_.mood;
  c.look = model_.look();
  c.working = model_.base == render::SceneState::kWorking;
  c.mayVary = !held(t) && !momentOn(t) && !exprOn(t);
  c.base = model_.base;
  c.act = model_.act;
  c.attention = model_.attn;
  c.borrowed = exprOn(t);
  c.attentionId = model_.attnId;
  c.agent = model_.agent;
  c.project = model_.project;
  c.thread = model_.name;
  c.more = model_.more;
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
    mouth = lt < say_.speakMs && voice::lineMouthOpen(say_.take, say_.then, lt);
  }
  return face_->show(t, moment_.playMs, mouth, pressed_ ? kPressPx : 0);
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

uint8_t Behaviour::blTarget(uint32_t t) const {
  if (noApp(t)) return 60;      // dimmed like asleep
  if (model_.attn) return 255;  // dimming never hides "needs you"
  if (model_.base == render::SceneState::kAsleep) return 60;
  return 255;
}

bool Behaviour::finishOn(uint32_t t) const {
  bool finish = moment_.anim == render::Anim::kTaskComplete || moment_.anim == render::Anim::kReplyReady;
  return momentOn(t) && finish && moment_.agent[0];
}

uint32_t Behaviour::finishShown(uint32_t t) const { return finishOn(t) ? moment_.id : 0; }

// With no app the Mac's counts are stale, so only the unplugged
// icon shows. While the brain's finish plays, whose
// turn it was.
render::Strip Behaviour::strip(uint32_t t) const {
  render::Strip s;
  s.noApp = noApp(t);
  if (s.noApp) return s;
  s.busy = model_.busy;
  if (model_.attn) s.agent = model_.agent, s.project = model_.project, s.name = model_.name, s.more = model_.more;
  if (finishOn(t)) {
    s.doneAgent = moment_.agent, s.doneThread = moment_.thread, s.doneOutcome = moment_.outcome;
  }
  return s;
}

// With no app, no line shows: it outranks the moments.
const char* Behaviour::bubble(uint32_t t) const { return sayOn(t) && !noApp(t) ? say_.text : nullptr; }

bool Behaviour::lineAhead(uint32_t t) const { return sayDue(t) && !sayOn(t); }

render::Anim Behaviour::moment(uint32_t t, uint32_t& left) const {
  if (!momentOn(t)) {
    left = 0;
    return render::Anim::kNone;
  }
  left = moment_.at + moment_.ms - t;
  return moment_.anim;
}

bool Behaviour::speaking(uint32_t t) const { return sayOn(t) && within(t, say_.at, say_.speakMs); }

}  // namespace app
