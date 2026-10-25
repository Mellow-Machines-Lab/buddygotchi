// The behaviour state machine: what the Mac last said,
// the reaction and the `say` playing, taps in a row, needs you, and
// the light and backlight they imply. Pure C++ and a function of the device
// clock: every time-based change happens at an exact millisecond, so a
// frozen clock gives the same frames on the board and in the simulator.
// Device owns the I/O, and LinkKit's queue decides when a reaction from the
// Mac plays (linkkit/SPEC.md §4): Behaviour says whether one may (admit) and
// plays it (play), and reports when the one playing has stopped.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstdio>

#include "linkkit/clock.h"
#include "linkkit/limits.h"
#include "render/face.h"
#include "render/drawer.h"
#include "render/stream.h"
#include "render/rig/rig.h"
#include "render/screens.h"
#include "voice/player.h"

namespace app {

using linkkit::Rng;

// Copies `src` into a buffer of `n` bytes, cut to fit; null copies as "".
inline void copyStr(char* dst, size_t n, const char* src) { std::snprintf(dst, n, "%s", src ? src : ""); }

// What the Mac last said, as the device parsed it.
struct Model {
  render::SceneState base = render::SceneState::kIdle;  // idle, working or asleep
  // What the agents are doing while working (`act`): that activity's
  // design shows in working's place. kWorking for none.
  render::SceneState act = render::SceneState::kWorking;
  render::Mood mood = render::kStartupMood;
  bool attn = false;
  char agent[12] = "";
  // Both show on the needs-you screen, three lines of 16.
  char project[48] = "";
  char name[48] = "";  // the thread's name; "" when the Mac sends none
  int more = 0;
  uint32_t attnId = 0;  // the needs-you shown's number; 0 when the Mac sends none
  int busy = 0;     // sessions working
  int idle = 0;     // sessions idle, waiting for your next prompt
  int helpers = 0;  // helpers working, over every session
  // The to-do list of the longest turn working that has one (`todo`),
  // done of total; 0 of 0 for none.
  int todoDone = 0, todoTotal = 0;
  int vol = 6;      // 0–10
  // The tags on now (`when`, render/tags.h): the part of the day, an
  // occasion, how busy the agents are. The face shows only the designs
  // whose tags are all on, and picks each look's variation itself.
  uint32_t when = 0;
  // The work stream's lanes (`calls`, render/stream.h), while the agents
  // work and nothing needs you.
  render::Stream::Lane lanes[render::Stream::kLanes];
  int laneCount = 0;
  // The agents' drawer's rows (`list`, render/drawer.h), which the Mac
  // sends while the board says it's open, and the sessions before them
  // (`skip`) and after (`unlisted`); `listed` when the state had a list at
  // all.
  render::Drawer::Row list[render::Drawer::kRows];
  int listCount = 0, listSkip = 0, unlisted = 0;
  bool listed = false;
  // The look while nothing needs you: what the agents are doing while
  // they work, else the base.
  render::SceneState look() const { return base == render::SceneState::kWorking ? act : base; }
};
// `base` by name: working or asleep, and idle for anything else.
render::SceneState baseFromName(const char* name);
// `act` by name: planning, terminal, tool_use, searching, analyzing,
// testing, delegating or waiting, and kWorking for anything else.
render::SceneState actFromName(const char* name);

// What cut a reaction short (`ended`): a tap (its poke, or push-to-talk's
// listening) or "needs you" starting. Each is the `why` of a `cut`. A
// newer reaction and dbg.reset need none here: the kit has already ended
// the one playing when it starts the next or resets its queue.
enum class CutBy : uint8_t { kNone, kTap, kNeedsYou };
const char* cutByName(CutBy c);  // null for kNone

// The reaction from the Mac that last played, once no part of it plays any
// more, for Device to hand to the kit: done, or cut by `by`. Every reaction
// plays as soon as the queue starts it, so it's the one the kit has
// playing, unless the kit has ended it already, and then the kit ignores it.
struct PlayedOut {
  uint32_t key = 0;
  CutBy by = CutBy::kNone;
};

// A reaction's sign (`sign`): at most kSignGlyphs glyphs of the board's
// fonts, cut with ".." past them (render::foldText), in kSignBytes.
constexpr int kSignGlyphs = 18;
constexpr size_t kSignBytes = 2 * kSignGlyphs + 1;

// A reaction from the Mac as Device parsed its args, already
// held in range: the do's name as an animation (none for `react`), a
// `say`, a face, a sign. With no anim, only the `say`, the face or the
// sign.
struct ReactionIn {
  render::SceneState anim = render::SceneState::kNone;  // a reaction's (render::isReaction)
  // It had a `say` field: the reply `listening` waits for, even with no
  // take. `stop_listening` is empty: it ends `listening` and does nothing
  // else.
  bool said = false;
  bool empty = false;
  int take = -1;  // the `say`: its first take's handle (voice/player.h), -1 for none
  int then = -1;  // and its second's, -1 for none
  // The expression: this mood's version of the look while the reaction
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
  // The kit's key for the reaction (linkkit::Do::key), 0 for none: its parts
  // carry it, and its end comes back as a PlayedOut with it.
  uint32_t key = 0;
  // The Mac's id for it, 0 for none: a tap on its finish names it.
  uint32_t id = 0;
  // The words the buddy holds up on a sign while it plays, "" for none.
  char sign[kSignBytes] = "";
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
  static constexpr int kMaxLoops = 6;  // a reaction's `loops`
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
  // A reaction's sign shows from its start for as long as any part of it
  // plays, and at least this long, to be read.
  static constexpr uint32_t kSignMinMs = 2500;
  // The brain's finish naming whose turn it was stays named in the strip
  // this long after it plays out, and a tap still opens its thread, unless
  // another animation or a needs-you takes the face first.
  static constexpr uint32_t kFinishLingerMs = 2000;

  void reset(uint32_t t, Rng& rng);
  // At power-on no Mac has spoken: "no app" from the start, until the
  // first state, rather than a face for kNoAppMs.
  void startWithNoApp() {
    change(modelT_, [&] { stale_ = true; });
  }

  // Messages from the Mac, at time t.
  void onState(const Model& m, uint32_t t);
  // Whether a reaction may play at t (the kit's refuse): null when some part
  // of it would, else why not: "no_app", "listening", "needs_you",
  // "not_listening" (stop_listening with nothing to stop) or "nothing". A
  // reply (a `say`, or stop_listening) ends listening first, whether or
  // not any of it then plays.
  const char* admit(const ReactionIn& m, uint32_t t);
  // Plays a reaction admitted at t. True when it carries a `say` that will
  // play: not while something needs you, or with no app.
  bool play(const ReactionIn& m, uint32_t t);
  // Which variation (from 0) of animation `a` to play in `mood`: `wanted`
  // (from 1, 0 for none) when it's one of those for the reaction's outcome
  // and context (render::fitting), else one of those at random, never the
  // one shown last. A finish's `loops` and `turn` may size it (the face's).
  uint8_t pick(render::SceneState a, render::Mood mood, int wanted, render::Outcome o, render::StartCtx c,
               Rng& rng, int loops = 1, int turn = render::kNoTurn) const;

  // Inputs, already recognised as gestures.
  void pressDown(uint32_t t);  // visible feedback at once
  void pressUp();
  // BOOT, or a touch anywhere: what it did, "poked" or "tap_spam", or
  // "dip" when it only dipped the face.
  const char* tap(uint32_t t, Rng& rng);
  // BOOT: while something needs you or an agent sits idle, it hands you
  // the next one on the Mac ("handoff"), and the board plays its hand-off
  // but over the needs-you screen, which stays; else it's a tap.
  const char* press(uint32_t t, Rng& rng);
  // The board's own reaction to a gesture: gesture's variation for it,
  // unless the face is held.
  void gesture(render::Gesture g, uint32_t t);
  // Laid face down: do not disturb. Every reaction but listening is
  // refused ("facedown") and the screen dims; needs you still shows.
  void setFaceDown(bool down, uint32_t t);
  bool faceDown() const { return faceDown_; }
  // No app, something needs you, or `listening` waits for the reply: a
  // tap or another animation doesn't take the face over, and a touch is a
  // tap, never a gesture.
  bool held(uint32_t t) const;
  // The id of the brain's finish showing whose turn it was at t, as it
  // plays or lingers after, which a tap opens on the Mac instead of
  // poking; 0 for none.
  uint32_t finishShown(uint32_t t) const;
  // Push-to-talk: BOOT held (talk_on) and let go, or capped (talk_off).
  void talkOn(uint32_t t, Rng& rng);
  void talkOff(uint32_t t);
  // dbg.light: holds the backlight until the next state.
  void overrideBacklight(uint8_t level) { blOverride_ = true, blSet_ = level; }

  // Moves to time t, handling every time-based change on the way at its
  // exact millisecond (a reaction or `say` ends, a blink, the no-app timeout).
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
  // The lane's strip at t, at its opacity: easing in over the rig's fade
  // (render::rig::Ramp) from when it came and out from when it went, still
  // showing what it last showed, so how often frames are drawn doesn't
  // change one. While it shows, what it shows changes at once.
  render::Strip strip(uint32_t t) const;
  // The `say`'s text in the bubble, or null: from the `say`'s start, which
  // can wait for its animation's voice window, to its bubble's end.
  const char* bubble(uint32_t t) const;
  // The sign a reaction holds up, while it shows, and for the rig's fade
  // after it goes (a reaction's end, a tap's, being put face down), fading
  // out: no text with no app or while something needs you, which take it
  // down at once.
  render::SignShow sign(uint32_t t) const;
  // Whether a sign is up, not fading.
  bool signUp(uint32_t t) const { return signOn(t) && !noApp(t) && !model_.attn; }
  // When the sign shown last goes.
  uint32_t signEnd() const { return sign_.at + sign_.ms; }
  // A `say` has arrived that waits for its animation's voice window:
  // it starts later, if nothing replaces it first.
  bool sayAhead(uint32_t t) const;
  // The animation playing (kNone for none) and ms left, and its variation.
  render::SceneState reaction(uint32_t t, uint32_t& left) const;
  uint8_t reactionVariant() const { return reaction_.variant; }
  bool speaking(uint32_t t) const;
  // The expression the face borrows while its reaction plays:
  // true, with its mood, until the reaction ends or another replaces it.
  bool expression(uint32_t t, render::Mood& mood) const;
  // The `say`'s takes, while it plays or waits to (-1 for none).
  int take() const { return say_.take; }
  int then() const { return say_.then; }
  // Counts reactions and `say`s started, local ones included, so a `say`
  // can tell it was replaced.
  uint32_t reactionSeq() const { return reactionSeq_; }
  // The reaction that last played, once no part of it plays any more,
  // exactly once; false when there's none. Device takes it after every
  // message, hook and tick.
  bool takePlayedOut(PlayedOut& p);
  // The first instant after `from`, at most `to`, at which a part ends
  // (an animation, a `say` with its bubble, a borrowed face, a sign); false
  // for none.
  bool nextEnd(uint32_t from, uint32_t to, uint32_t& at) const;
  // When the `say`'s bubble goes, from its start at its voice window.
  uint32_t sayEnd() const { return say_.at + say_.ms; }
  // A blink, Boop's idle life, is showing.
  bool blinking(uint32_t t) const { return face_->blinking(t); }
  // When needs you's performance, with its knocks and ding, last started
  // for a new needs-you; false before any.
  bool alerted(uint32_t& at) const {
    at = alertAt_;
    return alerted_;
  }
  const Model& model() const { return model_; }
  // The work stream (render/stream.h): the lanes each `state` says, and
  // the word a `call` brings forward, which plays at once while the
  // agents work and nothing needs you.
  const render::Stream& stream() const { return stream_; }
  bool callShows(uint32_t t) const { return stream_.accepts(t) && !model_.attn && !noApp(t); }
  void call(const char* word, uint8_t slot, render::CallGag gag, uint16_t count, uint32_t t) {
    stream_.startCall(word, slot, gag, count, t);
  }
  // The variation the look shows, from 0: the Mac's, until the variations
  // rotate.
  uint8_t lookVariant() const { return face_->lookVariant(); }
  // Taps in the run so far: 0 before any.
  int taps() const { return taps_; }

 private:
  // Each part of a reaction (the animation, the `say`, the expression)
  // carries its reaction's key, 0 for the device's own.
  struct Reaction {
    render::SceneState anim = render::SceneState::kNone;
    uint8_t variant = 0;
    uint32_t at = 0, ms = 0;
    // Its design's loops; held longer for its `say`, it rests on its last
    // frame.
    uint32_t playMs = 0;
    uint32_t key = 0;
    int loops = 1;
    render::Outcome requestedOutcome = render::Outcome::kNone;
    render::StartCtx ctx = render::StartCtx::kNone;
    uint32_t id = 0;  // the Mac's, which a tap on the finish names
    render::Outcome outcome = render::Outcome::kNone;  // what its design is for: a finish's result
    char agent[12] = "";  // the finish's `who`; empty for none
    char thread[24] = "";
  };
  // A `say`: its one or two takes, the bubble with their text, and the
  // mouth following their loudness. It plays over whatever face is showing,
  // from `at`, which with an animation is its design's voice window.
  struct Say {
    int take = -1;  // -1: no `say`
    int then = -1;
    char text[2 * voice::kTextMax] = "";  // the bubble's: the takes' words
    uint32_t at = 0, ms = 0;
    uint32_t speakMs = 0;  // the takes play this long, the gap included
    uint32_t key = 0;
  };
  // A sign: its words from `at` for `ms`, for its reaction (`key`).
  struct Sign {
    char text[kSignBytes] = "";
    uint32_t at = 0, ms = 0;
    uint32_t key = 0;
  };
  using Source = render::FaceSource;

  // An animation plays `loops` times in `mood`'s design (listening until
  // the reply), cutting the one playing, by `by`, but not the `say` or
  // expression; a finish for `outcome`, a start for `ctx`. kNone for a
  // newer reaction: the kit ended the one it replaces.
  void playAnim(render::SceneState a, uint32_t t, CutBy by, int loops, render::Mood mood, uint8_t variant,
                render::Outcome outcome = render::Outcome::kNone, render::StartCtx ctx = render::StartCtx::kNone);
  // The `say` and the expression end, the `say` cut short by `by`: a new
  // reaction's animation, or listening, replaces them; a tap's poke doesn't.
  // kNone for a newer reaction, as for playAnim.
  void endSay(uint32_t t, CutBy by);
  // How long a borrowed face in `mood` holds from t: `loops` loops of the
  // design it's drawn in, ending on a loop boundary of that design's clock.
  uint32_t holdMs(render::Mood mood, int loops, uint32_t t) const;
  // A `say` from `at`, which a reaction's animation can put after t.
  void startSay(const ReactionIn& in, uint32_t t, uint32_t at);
  // Every change goes through here: `f` changes the state at t, and if
  // what the face follows changed to another design, the eyes shut
  // briefly; a new look starts its design's clock. The backlight eases from
  // the level that was showing.
  template <class F>
  void change(uint32_t t, F f) {
    uint8_t lit = backlight(t);
    bool overridden = blOverride_;
    f();
    face_->sync(sourceAt(t), contextAt(t), t);
    followLane(t);
    uint8_t level = blTarget(t);
    if (!blOverride_ && (level != blLevel_ || overridden)) blFade_ = true, blFrom_ = lit, blAt_ = t;
    blLevel_ = level;
    modelT_ = t;
    sweep(t);
  }
  // The reaction that last played: it starts, a part of it is cut short while
  // it plays, and it's played out once no part of it plays at t.
  void cut(uint32_t key, CutBy by);
  void sweep(uint32_t t);
  bool holds(uint32_t key, uint32_t t) const;
  void resync(uint32_t t);
  bool reactionOn(uint32_t t) const;
  // A finish (task_complete or reply_ready) that names whose turn it was.
  static bool named(const Reaction& r);
  // The brain's finish naming whose turn it was, as it plays or lingers
  // after (the strip shows it); null for none.
  const Reaction* finishOn(uint32_t t) const;
  bool listening(uint32_t t) const;  // `listening` is playing
  uint8_t blTarget(uint32_t t) const;  // the level the state asks for at t
  bool sayOn(uint32_t t) const;        // the `say` plays, or its bubble shows
  bool sayDue(uint32_t t) const;       // the `say` plays, or waits to
  bool exprOn(uint32_t t) const;
  bool signOn(uint32_t t) const;
  Source sourceAt(uint32_t t) const;
  // What the strip shows: what the Mac last said, with no app or not, and
  // the brain's finish playing (null for none), whole.
  static render::Strip stripOf(const Model& m, bool noApp, const Reaction* finish);
  render::Strip stripAt(uint32_t t) const { return stripOf(model_, noApp(t), finishOn(t)); }
  // At every change: the strip kept while it shows, and its fade turned
  // when it comes or goes.
  void followLane(uint32_t t);
  // What the Mac last said, as the face may use it (render::FaceContext).
  render::FaceContext contextAt(uint32_t t) const;
  std::unique_ptr<render::Face> face_;

  Model model_;
  uint32_t lastState_ = 0;
  bool faceDown_ = false;
  // When the look (or needs you) last changed: the face's variations may
  // wait for it to have shown a while (`after`).
  uint32_t lookAt_ = 0;
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
  Reaction reaction_;
  // The finish that played out on its own, lingering from `at` for `ms`
  // (kFinishLingerMs); anim kNone for none.
  Reaction lingering_;
  Say say_;
  Sign sign_;
  // The sign that went last, fading out from goneAt_ (sign()).
  Sign gone_;
  uint32_t goneAt_ = 0;
  // The sign goes, at `at`: it fades out from then.
  void signGoes(uint32_t at);
  render::Stream stream_;
  // The reaction's expression: its mood from exprAt_ for exprMs_: as long
  // as the animation with it plays, or its loops; and at least as long as
  // the `say` with it.
  bool expr_ = false;
  render::Mood exprMood_ = render::kStartupMood;
  uint32_t exprAt_ = 0, exprMs_ = 0;
  uint32_t exprKey_ = 0;
  // The reaction that last played while a part of it plays, with what
  // first cut its animation or its `say` short; then, once it's played out,
  // its end until Device takes it. Key 0 for none.
  PlayedOut playing_, playedOut_;
  // The taps in the run, the last at lastTap_; 0 before the first.
  int taps_ = 0;
  uint32_t lastTap_ = 0;
  bool pressed_ = false;
  uint32_t pressAt_ = 0;
  bool alerted_ = false;
  uint32_t alertAt_ = 0;
  uint32_t modelT_ = 0;
  uint32_t reactionSeq_ = 0;
  // The lane: its opacity's ramp, and what the strip showed from at the
  // last change while it showed, copied, which it shows as it fades out.
  render::rig::Ramp lane_;
  Model laneModel_;
  Reaction laneFinish_;
  bool laneNoApp_ = false, laneFinishes_ = false;
};

}  // namespace app
