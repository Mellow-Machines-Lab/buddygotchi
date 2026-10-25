// The gel slime's engine: deterministic and integer, the same on the board,
// the simulator and the Mac's mirror of the board.
#pragma once
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
    // A step's cues are its contacts, at most a recipe's and a gag's: room
    // for them now keeps every frame off the heap (test_gel).
    cues.reserve(std::size(slime::Recipe{}.contacts) + std::size(slime::Gag{}.contacts));
    sync();
  }
  Random random, soundRandom;
  Motion motion;
  SemanticFace face;
  Acting acting;
  Bridge bridge;
  Router router;
  Scenes scenes;
  int emotion = slime::kCalm, expression = slime::kCalm;
  bool grab = false;
  F point[2]{0, q(.2)}, target[3]{};
  Spring pull[3];
  // The mood posture's weights, critically damped outside the
  // locked blocks (Motion's weights still time those).
  Spring postureWeights[slime::kProfiles];
  std::vector<SoundCue> cues;
  uint32_t elapsedMs = 0;
  void sync(int forcedBridge = -1);
  void step(uint32_t ms);
  void setMood(int id, int forced = -1) {
    if (id >= 0 && id < slime::kProfiles && id != emotion) {
      emotion = id;
      sync(forced);
    }
  }
  void setFacts(const Facts& value) {
    router.setFacts(value);
    sync();
  }
  // The tags on now (render/tags.h bits) and how long the look has shown:
  // an occasion's take fits by them at its next pick.
  void setOccasion(uint32_t when, uint32_t lookMs) {
    acting.when = scenes.when = when;
    acting.lookMs = scenes.lookMs = lookMs;
  }
  bool oneShot(const Request& value) {
    bool ok = router.oneShot(value, timeMs());
    sync();
    if (ok && (value.anim == SceneState::kPoked || value.anim == SceneState::kTapSpam))
      motion.impulse(value.anim == SceneState::kTapSpam);
    return ok;
  }
  void linkTimedOut(bool value) {
    router.timedOut = value;
    sync();
  }
  void holdExpression(int id) {
    router.holdExpression(id >= 0 && id < slime::kProfiles ? id : -1);
    sync();
  }
  void clearTransient() {
    router.clearTransient();
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
    for (auto& v : target) v = 0;
    acting.nextPerformance = max(acting.nextPerformance, motion.time + 3);
    sync();
  }
  std::array<F, 4> pose() const;
  std::array<F, 3> life() const;
  // The mood posture's lean and squash, after the quiet blend.
  std::array<F, 2> posture() const;
  T timeMs() const { return motion.time * 1000; }
  // How closed the eyes are drawn: the idle blink or a gag's lids, whichever
  // is more.
  F blink() const { return max(motion.blink(), acting.closure()); }

 private:
  bool stamped_ = false;
  uint32_t previous_ = 0;
  int cueGeneration_ = -1, cueIteration_ = -1, cueCount_ = 0;
  History<uint64_t, 64> revealed_;
  void consumeCues();
  // Whether a contact sounds: a gag's anywhere, at the routine chance; a
  // scene's never in a quiet state, a reveal once per request, a desk loop's
  // within its cycle's routine budget and any other's on its first loop.
  bool admits(const ContactEvent& c, SceneState state, bool quiet, bool protect);
};
}  // namespace render::gel
