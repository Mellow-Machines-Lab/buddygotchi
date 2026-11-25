// Boop's face boundary. The app owns priority, voice and
// LinkKit's queue. A face owns its presentation clock, variations, drawing,
// its sound clips and when they play. No display-library types cross this
// boundary, and nothing outside render/<face>/ knows which face is built:
// makeFace is the one place that chooses.
#pragma once
#include <cstddef>
#include <cstring>
#include <memory>
#include "linkkit/clock.h"
#include "render/types.h"
#include "render/drawer.h"
#include "render/surface.h"
#include "render/screens.h"
#include "render/stream.h"
#include "voice/clips.h"
#include "voice/effects.h"

namespace render {

// Boop's wish, as the board shows it: its kind while it waits (the Mac's
// `state.wish`), whether it shows how, its icon moving (`state.wish_how`), and for kPopMs after a wish_met or wish_gone Moment, how it
// went: the icon pops into a heart, or fades, the face slumping with it.
struct WishShow {
  enum Kind : uint8_t { kNone, kPet, kChat, kWork };
  enum Pop : uint8_t { kWaiting, kMet, kGone };
  static constexpr uint32_t kPopMs = 900;
  Kind kind = kNone;
  Pop pop = kWaiting;
  uint32_t popAge = 0;
  bool how = false;
  uint32_t ms = 0;  // the board's clock, for the icon's motion
};

// What the face follows (Behaviour::sourceAt): the reaction playing, if any,
// else the look, with the host facts a variation is chosen for.
struct FaceSource {
  SceneState anim = SceneState::kNone;  // the reaction's animation (isMoment), kNone for none
  uint32_t at = 0;
  SceneState look = SceneState::kIdle;
  uint8_t lookVariant = 0, animVariant = 0;
  Mood mood = kStartupMood;
  Outcome outcome = Outcome::kNone;
  StartCtx ctx = StartCtx::kNone;
  int loops = 1;
  // How long the animation's design plays its loops, from `at`; it rests
  // on its last frame after that, while the reaction holds on for its `say`.
  uint32_t playMs = 0;
  uint32_t id = 0;
  bool operator==(const FaceSource& o) const {
    return anim == o.anim && at == o.at && look == o.look && lookVariant == o.lookVariant &&
           animVariant == o.animVariant && mood == o.mood && playMs == o.playMs;
  }
  SceneState state() const { return anim != SceneState::kNone ? anim : look; }
  uint8_t variant() const { return anim != SceneState::kNone ? animVariant : lookVariant; }
};
// The sign a reaction holds up while it plays (its `sign`): the words, at
// most Behaviour::kSignGlyphs glyphs of the fonts, how long it has shown,
// and how much of it, 0 … 1000: whole while it's up, then fading out over
// the rig's fade once it goes (app/behaviour.h). No text for none.
struct SignShow {
  const char* text = nullptr;
  uint32_t ms = 0;
  int opacity = 1000;
  // Held low, in the lane, the face clear (a face that holdsUpFinish does),
  // and how long until it has gone.
  bool low = false;
  int32_t leftMs = -1;
  // A celebration's words, held low in gold with the rim glowing gold
  // (`gold`, "level 13!"), beside the sign or alone: how long since the
  // reaction began, and how long until it has gone. Null for none.
  const char* gold = nullptr;
  uint32_t goldMs = 0;
  int32_t goldLeftMs = -1;
  // What the gold's words have before them (`mark`): a star, a full ring
  // for today's ring, or a medal for a league's place.
  GoldMark goldMark = GoldMark::kStar;
  // The XP the low sign's moment earned (`xp`), shown on it as "+5 XP"; 0
  // for none.
  int xp = 0;
};
// The card an agent handed Boop to hold (the Mac's `state.card`,
// Behaviour::cardShow): one main thing, read from a chair, and at most one
// small line under it, both the Mac's words; whose it is, by its lane's
// slot (kNoSlot with no lane) and its agent's name (`claude`, `codex`, ""
// for none), which a face may show so the card reads as the agent's; whether a status's guess of the time has run
// out; a result's is what the turn made. `index` of `count` cards (from 1),
// for the dots. `on` only while nothing above
// Doing has the screen, and `ms` since it came or last changed.
struct CardShow {
  static constexpr int kTextBytes = 80, kSmallBytes = 48, kAgentBytes = 12, kNoSlot = -1;
  bool on = false, result = false, over = false;
  int slot = kNoSlot, index = 1, count = 1;
  const char* text = "";
  const char* small = "";
  const char* agent = "";
  uint32_t ms = 0;
  // A live picture of the work in place of words (the Mac's `pic`; the
  // engine's documentation/design/screen-guide.md, "Held pictures"): 'p'
  // the plan (a done of b, its step's words, `left` minutes left), 'c' the
  // changes (a row a file, its lines added and removed), 'h' the helpers
  // (a working, b done); 0 for none.
  static constexpr int kRows = 3, kNoLeft = -1000;
  char pic = 0;
  int a = 0, b = 0, left = kNoLeft, rows = 0;
  const char* step = "";
  const char* file[kRows] = {"", "", ""};
  int added[kRows] = {}, removed[kRows] = {};
  // A show (the Mac's `show`, pic 's'; the engine's documentation/design/
  // screen-guide.md, "The show"): the agent's headline over its picture,
  // kShowW by kShowH, run-length coded in kShowColours (render/show.h);
  // no picture until its bytes have come, and the headline alone.
  static constexpr int kShowW = 420, kShowH = 190, kHeadlineBytes = 40;
  const char* headline = "";
  const uint8_t* picture = nullptr;
  size_t pictureBytes = 0;
};
// The finished turn the brain's reaction is about (its `who`), while the
// reaction plays and lingers after (app/behaviour.h): whose turn, how it
// ended (kNone for a reply, or a face with no finish of its own), how long
// it has shown, and how long until it goes, -1 while its reaction still
// plays. A face may mark it on screen; the strip names it either way. No
// agent for none: with no app, or while something needs you, there's none.
struct DoneShow {
  const char* agent = nullptr;
  const char* thread = "";
  Outcome outcome = Outcome::kNone;
  uint32_t ms = 0;
  int32_t leftMs = -1;
  // How long the thread's name has been up, for a face that holds it up
  // (holdsUpFinish): -1 until the words end, or until a long cheer's
  // Behaviour::kFinishSignByMs.
  int32_t signMs = -1;
  // The XP its turn earned (`xp`), shown on its sign as "+5 XP"; 0 for none.
  int xp = 0;
  bool shows() const { return agent != nullptr; }
};
// How far a sign sits below its place `ms` after it went up, the same on
// every face: sliding up from `rise` px below, easing out, then lifting
// `bob` px now and then, a parabola.
constexpr uint32_t kSignRiseMs = 220, kSignBobEveryMs = 1400, kSignBobMs = 350;
inline int signLift(uint32_t ms, int rise, int bob) {
  if (ms < kSignRiseMs) {
    const int left = int(kSignRiseMs - ms);
    return rise * left * left / int(kSignRiseMs * kSignRiseMs);
  }
  const int n = int((ms - kSignRiseMs) % kSignBobEveryMs);
  return n < int(kSignBobMs) ? -4 * bob * n * (int(kSignBobMs) - n) / int(kSignBobMs * kSignBobMs) : 0;
}
// An invite (the `do`'s `invite`, app/behaviour.h): after a skit, Boop turns
// to you, comes up to the glass and holds a pose, the place to touch
// glowing, and waits for one touch; it pays off, or Boop shrugs and turns
// back. The pose, what it plays when the touch comes, and how far along it
// is. A face that draws none (drawsInvites) keeps every default and is never
// sent one.
enum class InvitePose : uint8_t { kNone, kPalm, kLean, kBack };
enum class InvitePayoff : uint8_t { kNone, kHighFive, kPurr, kSigh };
// By their names on the wire ("palm", "highfive"): kNone for one it doesn't know.
inline constexpr const char* kInvitePoseNames[] = {nullptr, "palm", "lean", "back"};
inline constexpr const char* kInvitePayoffNames[] = {nullptr, "highfive", "purr", "sigh"};
inline InvitePose invitePoseFromName(const char* name) {
  for (int i = 1; name && i < 4; ++i)
    if (!std::strcmp(name, kInvitePoseNames[i])) return InvitePose(i);
  return InvitePose::kNone;
}
inline InvitePayoff invitePayoffFromName(const char* name) {
  for (int i = 1; name && i < 4; ++i)
    if (!std::strcmp(name, kInvitePayoffNames[i])) return InvitePayoff(i);
  return InvitePayoff::kNone;
}
inline const char* invitePoseName(InvitePose p) { return kInvitePoseNames[int(p) < 4 ? int(p) : 0]; }
struct InviteShow {
  // kPose: it holds the pose and waits; kPayoff: the touch came; kShrug:
  // none came, and it turns back; kLate: one came after, and it turns
  // round, pleased (kTurnMs), into the payoff.
  enum Phase : uint8_t { kNone, kPose, kPayoff, kShrug, kLate };
  // How long each lasts, the same on every face: Behaviour times them.
  static constexpr uint32_t kPayoffMs = 2400, kShrugMs = 1200, kTurnMs = 600, kLateMs = kTurnMs + kPayoffMs;
  Phase phase = kNone;
  InvitePose pose = InvitePose::kNone;
  InvitePayoff payoff = InvitePayoff::kNone;
  const char* label = nullptr;  // the word by the glow (`label`); null for the glow alone
  int xp = 0;                   // what the touch earns, "+3 XP" in the payoff; 0 for none
  uint32_t ms = 0;              // since its phase began
  bool shows() const { return phase != kNone; }
};
// What the Mac last said, as far as a face may use it.
// Boop's energy, the Mac's rule (`state.energy`, documentation/design/
// screen-guide.md, "Energy"): a face draws it on its lids and in its tempo,
// never on the work or a reaction to you.
enum class Energy : uint8_t { kNormal, kBright, kTired };
// How much quicker a look at rest plays for it, in percent: 100 for normal.
constexpr int kBrightPace = 115, kTiredPace = 70;

struct FaceContext {
  bool alone = false;  // no Mac: the rest is the board's own, not what the Mac said
  Mood mood = kStartupMood;
  SceneState look = SceneState::kIdle;
  bool working = false;
  bool mayVary = false;
  SceneState base = SceneState::kIdle, act = SceneState::kWorking;
  bool attention = false, borrowed = false;
  // While it's borrowed, the Mac's reply to what you said that it came
  // with ("" for none) and when it started: a face may play a move for it,
  // once (the gel, its pack's `reply-<name>` clip).
  const char* reply = "";
  uint32_t replyAt = 0;
  uint32_t attentionId = 0;
  AttnKind attentionKind = AttnKind::kNone;
  const char* agent = "";
  const char* project = "";
  const char* thread = "";
  int more = 0;
  // The tags on (render/tags.h), how long the look (or needs you) has
  // shown, and the working looks' pace, in percent: quicker while the
  // agents are busy (render::workPace), 100 for any other look.
  uint32_t when = 0, lookMs = 0;
  int pace = 100;
  // The way to your pointer while it moves, from the Mac (`ptr`): each of
  // x (right) and y (down) in -10 … 10, and whether it's at the edge of the
  // screen nearest the board. Off with no Mac.
  bool pointer = false, pointerNear = false;
  int pointerX = 0, pointerY = 0;
  // Boop's energy; normal with no Mac.
  Energy energy = Energy::kNormal;
  // The invite showing, if any: a face that draws invites follows it.
  InviteShow invite;
};
class Face {
 public:
  static constexpr int kMaxCues = 16;
  virtual ~Face() = default;
  virtual const char* name() const = 0;  // hello's `face`
  // Draws into the board's native RGB565 surface (Device allocates it, at
  // the panel's size) rather than the 8-bit canvas alone.
  virtual bool drawsNative() const { return false; }
  // Read-only data it draws from often, which the board may copy where
  // it's quicker to read (Hal::quickerCopy) and hand back: the face then
  // reads the copy, the same bytes.
  virtual const void* assets(size_t& bytes) const { return bytes = 0, nullptr; }
  virtual void readAssetsFrom(const void* copy) { (void)copy; }
  // The clips its cues name (voice/clips.h).
  virtual const voice::EffectClips& clips() const = 0;

  // The presentation clock: reset at power-on and dbg.reset, rewound when
  // the device clock steps back (by default, reset again). Behaviour::advance
  // stops at every instant something changes, so each change happens at its
  // exact millisecond: nextDue gives the face's own next one after `from`,
  // at most `to`, and at each stop Behaviour syncs the face to the instant,
  // then steps it there. What's due at a stop is the face's to remember
  // from nextDue, since the sync can change it.
  virtual void reset(uint32_t t, linkkit::Rng& rng) = 0;
  // Power-on with the clock running: a seed from the board's randomness,
  // for a face that keeps randomness of its own (the gel's engine), so no
  // two boots replay the same choices. A tool's reset keeps the face's
  // fixed seed, so the board and the simulator still draw alike.
  virtual void seed(uint32_t s) { (void)s; }
  virtual void sync(const FaceSource& source, const FaceContext& context, uint32_t t) = 0;
  virtual void rewind(uint32_t t, linkkit::Rng& rng) { reset(t, rng); }
  virtual bool nextDue(uint32_t from, uint32_t to, uint32_t& at) = 0;
  virtual void step(uint32_t t, linkkit::Rng& rng) = 0;

  // Bookkeeping a face may ignore: a new needs-you, a new look. The face
  // picks each look's variation itself, from those whose tags are on
  // (FaceContext::when) and whose wait is over (lookMs); lookVariant is the
  // one showing.
  virtual void alert(uint32_t t, bool replacing) { (void)t, (void)replacing; }
  virtual uint8_t lookVariant() const = 0;
  virtual void newLook() {}
  // Shows the look's variation v (from 0) until it turns: dbg.look's, for
  // scenarios and tools. False for a face that picks by its own clock (the
  // gel's), which ignores it.
  virtual bool showLookVariant(uint8_t v) { return (void)v, false; }
  // Plays the pastime named `name` from t, whoever's turn it would be:
  // dbg.pastime's, for scenarios and tools. False for one the face hasn't
  // (a face with none has none).
  virtual bool playPastime(const char* name, uint32_t t) {
    (void)name, (void)t;
    return false;
  }
  // Plays the pack's rig clip `name` from t, over what's there: dbg.clip's,
  // for scenarios and the Character Studio, for a move nothing on the wire
  // names yet. False for one the pack hasn't, or a face that plays none.
  virtual bool playClip(const char* name, uint32_t t) {
    (void)name, (void)t;
    return false;
  }
  // The work stream to draw (render/stream.h), the device's, set before
  // each frame: a face that has no stream ignores it.
  virtual void watch(const Stream* stream) { (void)stream; }
  // The wish to show (WishShow), set before each frame: a face that draws
  // no thought bubble ignores it.
  virtual void wish(const WishShow& show) { (void)show; }
  // The buddy's colour, 0 to 7, set before each frame: 0 is the face's own,
  // and a face with one colour ignores it.
  virtual void color(int index) { (void)index; }
  // The card to hold (CardShow), set before each frame, and whether the
  // canvas's (x, y) is on it as last drawn: a touch that starts there is the
  // card's (a swipe to the next, a tap to open it). A face that holds no
  // card draws none and has none to touch.
  virtual void card(const CardShow& show) { (void)show; }
  virtual bool cardAt(int x, int y) const { return (void)x, (void)y, false; }
  // A finger on the screen (down, at x, y on the 320 × 240 canvas) or
  // let go: a face may follow it, as the gel's dome leans into a stroke.
  virtual void finger(bool down, int x, int y) { (void)down, (void)x, (void)y; }
  // The finger let go moving at vx, vy (canvas px a second, y down): a face
  // may carry the motion on, as the gel's dome does after a swipe.
  virtual void letGo(int vx, int vy) { (void)vx, (void)vy, finger(false, 0, 0); }
  // A finger kept still (app::TouchGesture): a face that can lean into it
  // at t says so, and hears how far along it is on every pass; one that
  // doesn't lean leaves the touch what it was, a tap on release.
  enum class Lean : uint8_t { kNone, kIn, kDoze };
  virtual bool leans(uint32_t t) const { return (void)t, false; }
  virtual void lean(Lean level, uint32_t t) { (void)level, (void)t; }
  // Whether the board's own touches say why themselves, in the caption, before
  // the Mac has heard of them (Behaviour::touchCaption).
  virtual bool captionsTouches() const { return false; }
  // Whether it draws invites (FaceContext::invite), which hello says
  // (`invites`): with none, the board plays a `do`'s invite not at all.
  virtual bool drawsInvites() const { return false; }
  // What it's doing to pass the time at t, by its name in the pack's
  // mac/passing.tsv, for the popover alone; null for nothing.
  virtual const char* passing(uint32_t t) const { return (void)t, nullptr; }
  // The board's steady tilt, in milli-g across the screen (app::Tilt), on
  // every reading of a board with a motion sensor: a face may slosh that way.
  virtual void tilt(int mg, uint32_t t) { (void)mg, (void)t; }
  // Whether a quick swipe plays the stroke (or the ruffle) it would be,
  // slower, as it does on a face that doesn't follow the finger; one that
  // carries it on as it lets go may only feel it go by.
  virtual bool playsSwipe() const { return true; }
  // Whether it holds up the finished turn's name itself (DoneShow::signMs):
  // from then on the strip doesn't repeat it.
  virtual bool holdsUpFinish() const { return false; }
  // How far below its usual place the nose is now, on the canvas: a face
  // that draws the body smaller, where it stands, has it lower.
  virtual int noseDrop() const { return 0; }
  // The agents' drawer (render/drawer.h): whether this face has one, the
  // device's, set before each frame as the stream is, how far a finger
  // pulls it from shut to open (canvas px), the session open under a
  // finger at x, y on the canvas, by its place in the list (-1 for none),
  // how far a list of `total` sessions scrolls (canvas px), the nearest
  // scroll to `scroll` that starts on a whole row, and the first and last
  // sessions any of whose rows show, scrolled as `drawer` is. A face with
  // none never opens one: a swipe up its strip is the swipe it was.
  virtual bool hasDrawer() const { return false; }
  virtual void drawer(const Drawer* drawer) { (void)drawer; }
  virtual int drawerTravel() const { return 0; }
  virtual int drawerRow(const Drawer& drawer, int x, int y) const { return (void)drawer, (void)x, (void)y, -1; }
  virtual int drawerScrollMax(int total) const { return (void)total, 0; }
  virtual int drawerSnap(int scroll) const { return scroll; }
  virtual void drawerShown(const Drawer& drawer, int& first, int& last) const { (void)drawer, first = 0, last = -1; }

  // A reaction's variation: pick chooses without changing anything (a
  // refused reaction leaves no trace); started is told what played. A
  // finish also says how long it's held (`loops`) and the tier its turn
  // reached (`turn`), which a face may size it by.
  virtual uint8_t pick(SceneState anim, Mood mood, int wanted, Outcome outcome, StartCtx ctx, linkkit::Rng& rng,
                       int loops = 1, int turn = kNoTurn) const = 0;
  virtual void started(SceneState anim, Mood mood, uint8_t variant, Outcome outcome, StartCtx ctx) = 0;
  // How many times variation `variant` of `anim` plays when it's asked to
  // play `loops` times: a design sized by them plays once.
  virtual int plays(SceneState anim, uint8_t variant, int loops) const { return (void)anim, (void)variant, loops; }

  // Its designs' timing, which Behaviour plays reactions and `say`s by.
  virtual int variants(Mood mood, SceneState state) const = 0;
  virtual uint32_t loopMs(Mood mood, SceneState state, int variant) const = 0;
  // The result a finish shows in the strip: its design's, or the one asked for.
  virtual Outcome outcome(Mood mood, SceneState state, int variant, Outcome requested) const = 0;
  virtual uint32_t voiceMs(Mood mood, SceneState state, int variant) const = 0;
  virtual uint32_t holdMs(Mood mood, int loops, uint32_t t) const = 0;
  virtual uint32_t designMs(uint32_t t) const = 0;
  virtual bool blinking(uint32_t t) const = 0;

  // What shows at t, with the device's additions: the mouth talking and
  // the press's dip.
  virtual SceneShow show(uint32_t t, bool mouthOpen, int dy) const = 0;
  // Draws the face, the sign it holds up, the finished turn its reaction
  // is about if it marks one, and the shared lane, with the bubble's words
  // and the caption under it, the reaction's reason (either may be null):
  // into the canvas, or into
  // `native` when it draws natively. `dirty` when something besides the
  // face's own clock changed since the last frame. Returns false when the
  // pixels have not changed.
  virtual bool draw(Canvas& canvas, Surface* native, const SceneShow& show, uint32_t t, const char* bubble,
                    const char* caption, const SignShow& sign, const DoneShow& done, const Strip& strip, bool dirty) = 0;
  // The sounds due at t, each with its own duck, and whether the last
  // ones should stop first; `shown` is false while the test pattern hides
  // the face.
  virtual int cues(uint32_t t, bool shown, voice::FxEvent* out, bool& changed) = 0;

  // BOOP_GEL_PROFILE builds: the face's own stage timings since the last
  // call, averaged over `frames`, as one line of text; 0 for none.
  virtual int profile(char* out, size_t n, uint32_t frames) {
    (void)out, (void)n, (void)frames;
    return 0;
  }
};
// The only build-time selection point: the staged pack's make_face.cpp.
std::unique_ptr<Face> makeFace();
}  // namespace render
