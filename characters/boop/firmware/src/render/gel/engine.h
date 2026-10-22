// Deterministic integer engine shared by the board and native trace checks.
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
  bool reduced = false, paused = false, hidden = false, grab = false;
  F point[2]{0, q(.2)}, target[3]{};
  Spring pull[3];
  // compose.mjs: the mood posture's weights, critically damped outside the
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
  bool oneShot(const Request& value) {
    bool ok = router.oneShot(value, timeMs());
    sync();
    if (ok && (value.anim == SceneState::kPoked || value.anim == SceneState::kTapSpam))
      motion.impulse(value.anim == SceneState::kTapSpam, reduced);
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
  void dragStart(F x, F y) {
    if (grab) return;
    grab = true;
    point[0] = clamp(x, -1, 1);
    point[1] = clamp(y, -1, 1);
    for (auto& v : target) v = 0;
    sync();
  }
  void dragMove(F x, F y, F z) {
    if (!grab) return;
    F len = sqrt(square(x) + square(y) + square(z)),
      gain = (len > q(.64) ? q(.64) / len : F(1)) * (reduced ? q(.35) : F(1));
    target[0] = x * gain;
    target[1] = y * gain;
    target[2] = z * gain;
  }
  void dragEnd() {
    if (!grab) return;
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
  // How closed the eyes are drawn: a bridge's blink, the idle blink, or a
  // gag's lids, whichever is most.
  F blink() const { return max(max(face.bridgeBlink, motion.blink()), acting.closure()); }

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
