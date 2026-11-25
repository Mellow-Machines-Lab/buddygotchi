// The gel slime's engine: deterministic and integer, the same on the board,
// the simulator and the Mac's mirror of the board.
#pragma once
#include "render/face.h"
#include "render/gel/history.h"
#include "render/gel/scenes.h"
namespace render::gel {
int expressionFromName(const char* name);
struct SoundCue {
  ContactEvent contact;
  const char* recipe;
  int mood, variant;
  uint32_t seed;
  F pitch, gain;
  bool protectedCue;
};
class Engine {
 public:
  explicit Engine(uint32_t seed = 53) : random(seed), soundRandom(seed ^ 0xa511e9b3u) {
    postureWeights[slime::kCalm].x = 1;
    // A step's cues are its contacts, at most a recipe's and a bit's: room
    // for them now keeps every frame off the heap (test_gel).
    cues.reserve(std::size(slime::Recipe{}.contacts) + std::size(slime::Gag{}.contacts) + kClipCues);
    clipContacts_.reserve(kClipCues);
    sync();
  }
  // The most cues a rig clip sounds in one step.
  static constexpr int kClipCues = 4;
  // How far curious leans toward what it peers at.
  static constexpr F kCuriousLean = q(.045);
  Random random, soundRandom;
  Motion motion;
  SemanticFace face;
  Acting acting;
  Router router;
  Scenes scenes;
  int emotion = slime::kCalm, expression = slime::kCalm;
  bool grab = false;
  F point[2]{0, q(.2)}, target[3]{};
  Spring pull[3];
  // The mood posture's weights, critically damped outside the
  // locked blocks (Motion's weights still time those).
  MoodBeat moodBeat;
  Spring postureWeights[slime::kProfiles];
  std::vector<SoundCue> cues;
  uint32_t elapsedMs = 0;
  // Boop's energy, the Mac's (FaceContext::energy): the painter draws it on
  // the lids (sleepyLids) and the eyes' size.
  render::Energy energy = render::Energy::kNormal;
  // You're speaking (the face's with-you pose, `speaking`): the layers draw
  // its hand cupped at its ear and rings pulsing by it, on the side of the
  // Mac (`speakingSide`, -1 left, 1 right).
  bool speaking = false;
  int speakingSide = 1;
  // You're typing and it types along (GelFace::showAlong): the layers pop
  // a key's tick out beside the paw that taps, on its beat, in any pose,
  // so typing along reads as plainly as speaking does. `typingPhase` is
  // where the paws are in their beats (briskLift's), `typingFast` quicker.
  bool typingAlong = false, typingFast = false;
  int typingPhase = 0;
  // What it has on or beside it for you at the Mac (GelFace::showWithYou),
  // which the layers draw, each at its opacity (0–255), in any pose and at
  // the light size too: headphones while music plays, and notes rising from
  // them while it grooves (`notesMs` into the groove); a page beside it
  // while it reads along, its lines scrolled up `scroll` px; a small screen
  // beside it while it watches, its light on the body; and a muted mic by
  // its ear on a call. `side` is the Mac's: -1 left, 1 right, as speaking's.
  struct With {
    int headphones = 0, page = 0, screen = 0, muted = 0;
    bool notes = false;
    int side = 1, scroll = 0;
    uint32_t notesMs = 0;
  } with;
  // The invite showing (render/gel/invite.h), its time the board's as of the
  // last step: the face's to set, the painter's to draw.
  InviteShow invite;
  // How far the face trails the body (render/gel/lively.h's face rule), in
  // sixteenths of a canvas px, x right and y up: the face's to set, the
  // painter's to draw.
  int faceLagX16 = 0, faceLagY16 = 0;
  void sync();
  void step(uint32_t ms);
  void setMood(int id) {
    if (id >= 0 && id < slime::kProfiles && id != emotion) {
      emotion = id;
      sync();
    }
  }
  void setFacts(const Facts& value) {
    router.setFacts(value);
    sync();
  }
  // The tags on now (render/tags.h bits) and how long the look has shown,
  // which the face's pastimes fit by and its layers read.
  void setOccasion(uint32_t when, uint32_t lookMs) {
    scenes.when = when;
    scenes.lookMs = lookMs;
  }
  // A pastime's body the face dealt (render/gel/pastimes.h): a bit, which
  // acting plays in place of its next gesture, or a take, which the scene
  // plays as the look's next.
  void playBit(int gag) { acting.play(gag, motion.time); }
  void playTake(int take) {
    scenes.playTake(take, timeMs(), random);
    sync();
  }
  bool play(const Request& value) {
    bool ok = router.play(value, timeMs());
    sync();
    if (ok && (value.anim == SceneState::kPoked || value.anim == SceneState::kTapSpam))
      motion.impulse(value.anim == SceneState::kTapSpam);
    return ok;
  }
  void linkTimedOut(bool value) {
    router.timedOut = value;
    sync();
  }
  // The host's borrowed expression (-1 for none), over whatever shows,
  // until it says otherwise.
  void borrow(int id) {
    router.expression = id >= 0 && id < slime::kProfiles ? id : -1;
    sync();
  }
  void clear() {
    router.clear();
    sync();
  }
  // A finger's pull: held, it follows the finger;
  // let go, a softer spring settles it. Its target gives less and less past
  // kGrabKnee and never reaches kGrabReach; the body draws it as its lean
  // and squash (pose), and a finger let go while moving flings it on.
  // Each spring's frequency (its stiffness's root) and damping.
  static constexpr int kGrabHeld[2] = {16, 20}, kGrabReleased[2] = {10, 13};
  static constexpr F kGrabKnee = q(.32), kGrabReach = q(.64), kGrabLimit = q(.72);
  static constexpr F kGrabLean = 2, kGrabSquash = 1, kGrabFling = q(.3);
  static constexpr int kGrabVelocity = 6;
  void dragStart(F x, F y) {
    if (grab) return;
    grab = true;
    point[0] = clamp(x, -1, 1);
    point[1] = clamp(y, -1, 1);
    for (auto& v : target) v = 0;
    sync();
  }
  // The finger's displacement since it went down, in body units (y up).
  void dragMove(F x, F y, F z) {
    if (!grab) return;
    F len = sqrt(square(x) + square(y) + square(z)), gain = 1;
    if (len > kGrabKnee) {
      const F past = len - kGrabKnee, room = kGrabReach - kGrabKnee;
      gain = gain * (kGrabKnee + past * room / (past + room)) / len;
    }
    target[0] = x * gain;
    target[1] = y * gain;
    target[2] = z * gain;
  }
  // Let go, moving at (vx, vy, vz) body units a second; at rest, none.
  void dragEnd(F vx = 0, F vy = 0, F vz = 0) {
    if (!grab) return;
    const F velocity[3] = {vx, vy, vz}, gain = kGrabFling;
    for (int i = 0; i < 3; ++i) {
      const F add = clamp(velocity[i] * gain, -kGrabVelocity, kGrabVelocity);
      const bool outward = (add > F(0) && pull[i].x > F(0)) || (add < F(0) && pull[i].x < F(0));
      const F room = outward ? max(0, 1 - abs(pull[i].x) / kGrabLimit) : F(1);
      pull[i].v = clamp(pull[i].v + add * room, -kGrabVelocity, kGrabVelocity);
    }
    grab = false;
    leaning = kLeanNone, leanLids_ = false;
    for (auto& v : target) v = 0;
    acting.nextPerformance = max(acting.nextPerformance, motion.time + 3);
    sync();
  }
  // The eyes on a finger, in face units (y up), until lookAway; shut or
  // asleep, they don't follow it.
  void lookAt(F x, F y) {
    motion.following = true;
    const bool open = !scenes.route.quiet && !leaning;
    motion.gazeTarget = open ? x : F(0);
    motion.gazeUpTarget = open ? y : F(0);
  }
  void lookAway() {
    motion.following = false;
    motion.gazeTarget = motion.gazeUpTarget = 0;
  }
  // The eyes on something it looks at by itself (render/gel/gaze.h), in face
  // units (y up), until unattend; a finger has them first, and shut or
  // asleep they don't look.
  void attend(F x, F y) {
    motion.attending = !scenes.route.quiet && !leaning;
    motion.attendX = x, motion.attendUp = y;
  }
  void unattend() {
    if (!motion.attending) return;
    motion.attending = false;
    if (!motion.following) motion.gazeTarget = motion.gazeUpTarget = 0;
  }
  // A finger kept still: it leans in (kLeanIn) toward the spot, (x, y) across
  // the dome's half-width and half-height (-1 … 1, y up), or dozes on it
  // (kLeanDoze), its face going to sleep, until it's let go (kLeanNone).
  // `lids` shuts the eyes of a face that doesn't shut them itself. The dozing
  // is the sleeping face's; the spot's whichever size the body is.
  static constexpr int kLeanNone = 0, kLeanIn = 1, kLeanDoze = 2;
  static constexpr int kGrabLeaning[2] = {5, 10};
  // At a spot at the dome's edge the pull goes this far; it settles down by
  // the slump, comes forward, and breathes.
  static constexpr F kLeanReach = q(.2), kLeanSlump = q(.06), kDozeSlump = q(.13), kLeanForward = q(.35);
  // Eyes shut by lids, not their art's, stay a slit: all the way, they'd go.
  static constexpr F kLeanLids = q(.82);
  static constexpr F kLeanBreath = q(.012), kLeanBreathRate = q(2.6), kDozeBreathRate = q(1.6);
  int leaning = kLeanNone;
  void lean(int level, F x, F y, bool lids) {
    if (!grab) level = kLeanNone;
    leaning = level, leanX_ = x, leanY_ = y, leanLids_ = level != kLeanNone && lids;
    sync();
  }
  // The board's steady tilt (app::Tilt), in milli-g across the screen, right
  // side down positive: the body's lean goes that way on a spring of its own,
  // loose enough to slosh past and come back, and the eyes stay level, as a
  // lean shears the body and turns nothing. kTiltPerG of lean at 1 g, to
  // kTiltMost; the face says none while anything else moves the body.
  static constexpr F kTiltPerG = q(1.5), kTiltMost = q(.6);
  static constexpr int kTiltSpring[2] = {7, 5};
  void tilt(int mg) { tiltTarget_ = clamp(F(mg) * kTiltPerG / 1000, -kTiltMost, kTiltMost); }
  F tilted() const { return tilt_.x; }
  // Listening, it nods: two or three, a rest, again, off a clock of its own so
  // it never reads as a loop. On the pull's released spring; nothing else of
  // the listening look moves.
  static constexpr F kNodForward = q(.42), kNodSquash = q(.09);
  static constexpr F kNodRate = q(3.1), kNodBursts = q(.83);
  F nod() const;
  std::array<F, 4> pose() const;
  std::array<F, 3> life() const;
  // The mood posture's lean and squash, after the quiet blend.
  std::array<F, 2> posture() const;
  T timeMs() const { return motion.time * 1000; }
  // A contact a rig clip's cue names (slime::kContactKindNames), sounded at
  // the next step as the scene's are; a name it doesn't know, none.
  void contact(const char* kind);
  // How closed the eyes are drawn: the idle blink, a bit's lids, a hit's
  // daze or a lean's, whichever is most.
  F blink() const { return max(max(max(motion.blink(), acting.closure()), daze()), leanShut_); }
  // A word of the work stream landing (render/stream.h): a push on the
  // pull's springs, as a fling let go, in body units a second, and the
  // lids shut to `lids` for `dazeMs` of the engine's time, opening over
  // the last kDazeOpenMs of it. Nothing while a finger holds it.
  static constexpr uint32_t kDazeOpenMs = 300;
  void jolt(F lean, F squash, F forward, F lids = 0, uint32_t dazeMs = 0) {
    if (grab) return;
    const F push[3] = {lean, squash, forward};
    for (int i = 0; i < 3; ++i) pull[i].v = clamp(pull[i].v + push[i], -kGrabVelocity, kGrabVelocity);
    if (dazeMs) dazeLids_ = lids, dazeEnd_ = elapsedMs + dazeMs, dazed_ = true;
  }
  // The time left of it measured across the clock's wrap (a uint32_t of
  // milliseconds, which wraps after 49.7 days), and forgotten once it's
  // over (step), so an old one never comes back when the clock passes it
  // again.
  F daze() const {
    const int32_t left = int32_t(dazeEnd_ - elapsedMs);
    if (!dazed_ || left <= 0) return 0;
    return left >= int32_t(kDazeOpenMs) ? dazeLids_ : dazeLids_ * int(left) / int(kDazeOpenMs);
  }

 private:
  bool stamped_ = false, dazed_ = false;
  F dazeLids_ = 0;
  F leanX_ = 0, leanY_ = 0, leanShut_ = 0;
  Spring tilt_;
  F tiltTarget_ = 0;
  bool leanLids_ = false;
  uint32_t dazeEnd_ = 0;
  uint32_t previous_ = 0;
  std::vector<ContactEvent> clipContacts_;
  int cueGeneration_ = -1, cueIteration_ = -1, cueCount_ = 0;
  History<uint64_t, 64> revealed_;
  void consumeCues();
  // Whether a contact sounds: a bit's anywhere, at the routine chance; a
  // scene's never in a quiet state, a reveal once for what shows, a desk loop's
  // within its cycle's routine budget and any other's on its first loop.
  bool admits(const ContactEvent& c, SceneState state, bool quiet, bool protect);
};
}  // namespace render::gel
