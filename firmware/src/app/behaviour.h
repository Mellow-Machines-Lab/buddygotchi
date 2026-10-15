// The behaviour state machine: what the Mac last said,
// the moment and the line playing, taps in a row, needs you, and
// the light and backlight they imply. Pure C++ and a function of the device
// clock: every time-based change happens at an exact millisecond, so a
// frozen clock gives the same frames on the board and in the simulator.
// Device owns the I/O, and LinkKit decides when a call from the Mac plays
// (linkkit/SPEC.md §4): Behaviour says whether one may (admit) and plays it
// (play), and reports when the call holding the turn has stopped playing.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstdio>

#include "linkkit/clock.h"
#include "linkkit/limits.h"
#include "render/face.h"
#include "render/screens.h"
#include "voice/player.h"

namespace app {

using linkkit::Rng;

// Copies `src` into a buffer of `n` bytes, cut to fit; null copies as "".
inline void copyStr(char* dst, size_t n, const char* src) { std::snprintf(dst, n, "%s", src ? src : ""); }

// What the Mac last said, as the device parsed it.
struct Model {
  render::SceneState base = render::SceneState::kIdle;  // idle, working or asleep
  // What the agents are doing while working (`act`): that state's design
  // shows in working's place. kWorking for none.
  render::SceneState act = render::SceneState::kWorking;
  render::Mood mood = render::kStartupMood;
  // The variation of the visual the Mac shows (needs you's while something
  // does, else the look's), from 0: the wire's `variant` less one.
  uint8_t variant = 0;
  bool attn = false;
  char agent[12] = "";
  // Both show on the needs-you sign, three lines of 16.
  char project[48] = "";
  char name[48] = "";  // the thread's name; "" when the Mac sends none
  int more = 0;
  uint32_t attnId = 0;  // the request shown's number; 0 when the Mac sends none
  int busy = 0;
  int vol = 6;  // 0–10
  // The look while nothing needs you: what the agents are doing while
  // they work, else the base.
  render::SceneState look() const { return base == render::SceneState::kWorking ? act : base; }
};
// `base` by name: working or asleep, and idle for anything else.
render::SceneState baseFromName(const char* name);
// `act` by name: planning, terminal, tool_use, searching, analyzing,
// testing, delegating or waiting, and kWorking for anything else.
render::SceneState actFromName(const char* name);

// What cut a call short (`ended`): a tap (its poke, or push-to-talk's
// listening) or "needs you" starting. Each is the `why` of a `cut`. A
// newer call and dbg.reset need none here: the kit has already ended the
// call it held when it takes the next or resets its turn.
enum class CutBy : uint8_t { kNone, kTap, kNeedsYou };
const char* cutByName(CutBy c);  // null for kNone

// The call from the Mac that last played, once no part of it plays any
// more, for Device to hand to the kit: done, or cut by `by`. Every call
// plays as it takes the turn, so it's the kit's holder, unless the kit
// has ended it already, and then the kit ignores it.
struct PlayedOut {
  uint32_t call = 0;
  CutBy by = CutBy::kNone;
};

// A call from the Mac as Device parsed its args, already
// held in range: the do's name as an animation (none for `react`), a line,
// a face. With no anim, only the line, or only the face.
struct MomentIn {
  render::SceneState anim = render::SceneState::kNone;  // a moment's (render::isMoment)
  // It had a `say` field: the reply `listening` waits for, even with no
  // take. `stop_listening` is empty: it ends `listening` and does nothing
  // else.
  bool said = false;
  bool empty = false;
  int take = -1;  // the line: its first take's handle (voice/player.h), -1 for none
  int then = -1;  // and its second's, -1 for none
  // The expression: this mood's version of the look while the moment
  // plays. Only a known mood sets it.
  bool expr = false;
  render::Mood mood = render::kStartupMood;
  // The animation's variation, from 0, as Behaviour::pick chose it.
  uint8_t variant = 0;
  render::Outcome outcome = render::Outcome::kNone;
  render::StartCtx ctx = render::StartCtx::kNone;
  // 1–Behaviour::kMaxLoops: with an animation, how many
  // times its design plays; with an expression and no animation, how many
  // loops of the design it's drawn in the face holds.
  int loops = 1;
  // With the finish (task_complete or reply_ready), whose turn it is
  // (`who`): named in the strip while it plays. Null for none.
  const char* whoAgent = nullptr;
  const char* whoThread = nullptr;
  // The kit's key for the call (linkkit::Call::key), 0 for none: its parts
  // carry it, and its end comes back as a PlayedOut with it.
  uint32_t call = 0;
  // The Mac's id for it, 0 for none: a tap on its finish names it.
  uint32_t id = 0;
};

class Behaviour {
 public:
  Behaviour() : face_(render::makeFace()) {}
  explicit Behaviour(std::unique_ptr<render::Face> face) : face_(std::move(face)) {}
  render::Face& face() { return *face_; }
  const render::Face& face() const { return *face_; }
  // Timings. No app after the kit's host-gone window
  // (linkkit/SPEC.md §5) with no `state`, on the device clock, which a
  // tool can freeze and step.
  static constexpr uint32_t kNoAppMs = linkkit::kHostGoneMs;
  static constexpr uint32_t kBubbleReadMs = 1200;  // the text stays up after the take
  static constexpr uint32_t kPressEaseMs = 60;     // a press draws at once this long
  static constexpr int kPressPx = 2;                // a press dips the face this far
  static constexpr uint32_t kBacklightEaseMs = 150;
  static constexpr int kMaxLoops = 6;  // a call's `loops`
  // Push-to-talk: `listening` shows for at most kListenMs
  // of talking, then waits at most kReplyWaitMs for the reply; the
  // release shortens the wait to kReplyWaitMs from then.
  static constexpr uint32_t kListenMs = 30000;
  static constexpr uint32_t kReplyWaitMs = 8000;
  // Taps in a row: a tap within kTapRunMs of the last
  // one is another in the run, and from the kTapSpamFrom-th on each plays
  // tap_spam instead of poked. The Mac counts pokes by the same numbers,
  // TranscriptView.inARowMs (3000) and answersRunFrom (3): change them
  // together.
  static constexpr uint32_t kTapRunMs = 3000;
  static constexpr int kTapSpamFrom = 3;

  void reset(uint32_t t, Rng& rng);
  // At power-on no Mac has spoken: "no app" from the start, until the
  // first state, rather than a face for kNoAppMs.
  void startWithNoApp() { stale_ = true; }

  // Messages from the Mac, at time t.
  void onState(const Model& m, uint32_t t);
  // Whether a call may play at t (the kit's refuse): null when some part
  // of it would, else why not: "no_app", "listening", "needs_you",
  // "not_listening" (stop_listening with nothing to stop) or "nothing". A
  // reply (a `say`, or stop_listening) ends listening first, whether or
  // not any of it then plays.
  const char* admit(const MomentIn& m, uint32_t t);
  // Plays a call admitted at t. True when it carries a line that will
  // play: not while something needs you, or with no app.
  bool play(const MomentIn& m, uint32_t t);
  // Which variation (from 0) of animation `a` to play in `mood`: `wanted`
  // (from 1, 0 for none) when it's one of those for the moment's outcome
  // and context (render::fitting), else one of those at random, never the
  // one shown last.
  uint8_t pick(render::SceneState a, render::Mood mood, int wanted, render::Outcome o, render::StartCtx c,
               Rng& rng) const;

  // Inputs, already recognised as gestures.
  void pressDown(uint32_t t);  // visible feedback at once
  void pressUp();
  // BOOT, or a touch anywhere: what it did, "poked" or "tap_spam", or
  // "dip" when it only dipped the face.
  const char* tap(uint32_t t, Rng& rng);
  // The id of the brain's finish showing whose turn it was at t, which a
  // tap opens on the Mac instead of poking; 0 for none.
  uint32_t finishShown(uint32_t t) const;
  // Push-to-talk: BOOT held (talk_on) and let go, or capped (talk_off).
  void talkOn(uint32_t t, Rng& rng);
  void talkOff(uint32_t t);
  // dbg.light: holds the backlight until the next state.
  void overrideBacklight(uint8_t level) { blOverride_ = true, blSet_ = level; }

  // Moves to time t, handling every time-based change on the way at its
  // exact millisecond (a moment or line ends, a blink, the no-app timeout).
  void advance(uint32_t t, Rng& rng);

  // Queries at t (after advance).
  // The look: kNoApp, kNeedsYou, or what the Mac says (Model::look).
  render::SceneState look(uint32_t t) const;
  // The face at t: its design, the design's clock, and what the device
  // adds on top (render/face.h).
  render::SceneShow show(uint32_t t) const;
  // How long the face's design has been playing at t, counting on past its
  // loops: show()'s clock before it wraps an animation's or holds needs
  // you's pose. It starts over only with a new look or a new animation.
  uint32_t designMs(uint32_t t) const { return face_->designMs(t); }
  // A press has just come in: feedback the redraw cap mustn't hold back.
  bool pressEasing(uint32_t t) const;
  bool noApp(uint32_t t) const;
  uint32_t led(uint32_t t) const;
  uint8_t backlight(uint32_t t) const;
  render::Strip strip(uint32_t t) const;
  // The line's text in the bubble, or null: from its line's start, which
  // can wait for its animation's voice window, to its bubble's end.
  const char* bubble(uint32_t t) const;
  // A line has arrived that waits for its animation's voice window:
  // it starts later, if nothing replaces it first.
  bool lineAhead(uint32_t t) const;
  // The animation playing (kNone for none) and ms left, and its variation.
  render::SceneState moment(uint32_t t, uint32_t& left) const;
  uint8_t momentVariant() const { return moment_.variant; }
  bool speaking(uint32_t t) const;
  // The expression the face borrows while its call plays:
  // true, with its mood, until the call ends or another replaces it.
  bool expression(uint32_t t, render::Mood& mood) const;
  // The line's takes, while it plays or waits to (-1 for none).
  int take() const { return say_.take; }
  int then() const { return say_.then; }
  // Counts moments and lines started, local ones included, so a line can
  // tell it was replaced.
  uint32_t momentSeq() const { return momentSeq_; }
  // The call that last played, once no part of it plays any more, exactly
  // once; false when there's none. Device takes it after every line, hook
  // and tick.
  bool takePlayedOut(PlayedOut& p);
  // The first instant after `from`, at most `to`, at which a part ends
  // (an animation, a line with its bubble, a borrowed face); false for none.
  bool nextEnd(uint32_t from, uint32_t to, uint32_t& at) const;
  // When the line's bubble goes, from its start at its voice window.
  uint32_t sayEnd() const { return say_.at + say_.ms; }
  // A blink, Boop's idle life, is showing.
  bool blinking(uint32_t t) const { return face_->blinking(t); }
  // When needs you's performance, with its knocks and ding, last started
  // for a new request; false before any.
  bool alerted(uint32_t& at) const {
    at = alertAt_;
    return alerted_;
  }
  const Model& model() const { return model_; }
  // The variation the look shows, from 0: the Mac's, until the variations
  // take turns.
  uint8_t lookVariant() const { return face_->lookVariant(); }
  // Taps in the run so far: 0 before any.
  int taps() const { return taps_; }

 private:
  // Each part of a call (the animation, the line, the expression) carries
  // its call's key, 0 for the device's own.
  struct Moment {
    render::SceneState anim = render::SceneState::kNone;
    uint8_t variant = 0;
    uint32_t at = 0, ms = 0;
    // Its design's loops; held longer for its line, it rests on its last
    // frame.
    uint32_t playMs = 0;
    uint32_t call = 0;
    int loops = 1;
    render::Outcome requestedOutcome = render::Outcome::kNone;
    render::StartCtx ctx = render::StartCtx::kNone;
    uint32_t id = 0;  // the Mac's, which a tap on the finish names
    render::Outcome outcome = render::Outcome::kNone;  // what its design is for: a finish's result
    char agent[12] = "";  // the finish's `who`; empty for none
    char thread[24] = "";
  };
  // A line: its one or two takes, the bubble with their text, and the
  // mouth following their loudness. It plays over whatever face is showing,
  // from `at`, which with an animation is its design's voice window.
  struct Say {
    int take = -1;  // -1: no line
    int then = -1;
    char text[2 * voice::kTextMax] = "";  // the bubble's: the takes' words
    uint32_t at = 0, ms = 0;
    uint32_t speakMs = 0;  // the takes play this long, the gap included
    uint32_t call = 0;
  };
  using Source = render::FaceSource;

  // An animation plays `loops` times in `mood`'s design (listening until
  // the reply), cutting the one playing, by `by`, but not the line or
  // expression; a finish for `outcome`, a start for `ctx`. kNone for a
  // newer call: the kit ended the call it replaces.
  void playAnim(render::SceneState a, uint32_t t, CutBy by, int loops, render::Mood mood, uint8_t variant,
                render::Outcome outcome = render::Outcome::kNone, render::StartCtx ctx = render::StartCtx::kNone);
  // The line and the expression end, the line cut short by `by`: a new
  // moment's animation, or listening, replaces them; a tap's poke doesn't.
  // kNone for a newer call, as for playAnim.
  void endLine(uint32_t t, CutBy by);
  // How long a borrowed face in `mood` holds from t: `loops` loops of the
  // design it's drawn in, ending on a loop boundary of that design's clock.
  uint32_t holdMs(render::Mood mood, int loops, uint32_t t) const;
  // A line from `at`, which a moment's animation can put after t.
  void startSay(const MomentIn& in, uint32_t t, uint32_t at);
  // Every change goes through here: `f` changes the state at t, and if
  // what the face follows changed to another design, the eyes shut for a
  // moment; a new look starts its design's clock. The backlight eases from
  // the level that was showing.
  template <class F>
  void change(uint32_t t, F f) {
    uint8_t lit = backlight(t);
    bool overridden = blOverride_;
    f();
    face_->sync(sourceAt(t), contextAt(t), t);
    uint8_t level = blTarget(t);
    if (!blOverride_ && (level != blLevel_ || overridden)) blFade_ = true, blFrom_ = lit, blAt_ = t;
    blLevel_ = level;
    modelT_ = t;
    sweep(t);
  }
  // The call that last played: it starts, a part of it is cut short while
  // it plays, and it's played out once no part of it plays at t.
  void cut(uint32_t call, CutBy by);
  void sweep(uint32_t t);
  bool holds(uint32_t call, uint32_t t) const;
  void resync(uint32_t t);
  bool momentOn(uint32_t t) const;
  // The brain's finish plays, naming whose turn it was (the strip shows it).
  bool finishOn(uint32_t t) const;
  bool listening(uint32_t t) const;  // `listening` is playing
  // No app, something needs you, or `listening` waits
  // for the reply: a tap or another animation doesn't take
  // the face over.
  bool held(uint32_t t) const;
  uint8_t blTarget(uint32_t t) const;  // the level the state asks for at t
  bool sayOn(uint32_t t) const;   // the line plays, or its bubble shows
  bool sayDue(uint32_t t) const;  // the line plays, or waits to
  bool exprOn(uint32_t t) const;
  Source sourceAt(uint32_t t) const;
  // What the Mac last said, as the face may use it (render::FaceContext).
  render::FaceContext contextAt(uint32_t t) const;
  std::unique_ptr<render::Face> face_;

  Model model_;
  uint32_t lastState_ = 0;
  // Latched once the Mac has been silent kNoAppMs, so "no app" holds
  // however long the silence (the clock's differences wrap after 24 days).
  bool stale_ = false;
  bool blOverride_ = false;  // dbg.light, until the next state
  uint8_t blSet_ = 255;
  // The level the state asked for at the last change, like src_ for the
  // face, easing from blFrom_ since blAt_, over kBacklightEaseMs.
  uint8_t blLevel_ = 255;
  bool blFade_ = false;
  uint8_t blFrom_ = 255;
  uint32_t blAt_ = 0;
  Moment moment_;
  Say say_;
  // The moment's expression: its mood from exprAt_ for exprMs_: as long as
  // the animation with it plays, or its loops; and at least as long as the
  // line with it.
  bool expr_ = false;
  render::Mood exprMood_ = render::kStartupMood;
  uint32_t exprAt_ = 0, exprMs_ = 0;
  uint32_t exprCall_ = 0;
  // The call that last played while a part of it plays, with what first
  // cut its animation or its line short; then, once it's played out, its
  // end until Device takes it. Call 0 for none.
  PlayedOut playing_, playedOut_;
  // The taps in the run, the last at lastTap_; 0 before the first.
  int taps_ = 0;
  uint32_t lastTap_ = 0;
  bool pressed_ = false;
  uint32_t pressAt_ = 0;
  bool alerted_ = false;
  uint32_t alertAt_ = 0;
  uint32_t modelT_ = 0;
  uint32_t momentSeq_ = 0;
};

}  // namespace app
