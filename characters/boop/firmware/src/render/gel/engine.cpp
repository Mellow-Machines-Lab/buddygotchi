#include "render/gel/engine.h"
#include <cstring>
namespace render::gel {
int expressionFromName(const char* name) {
  if (name)
    for (int i = 0; i < slime::kProfiles; ++i)
      if (!std::strcmp(name, slime::kProfile[i].id)) return i;
  return -1;
}
void Engine::contact(const char* kind) {
  for (int i = 0; i < slime::kContactKinds; ++i)
    if (!std::strcmp(kind, slime::kContactKindNames[i]) && int(clipContacts_.size()) < kClipCues) {
      ContactEvent c;
      c.kind = uint8_t(i);
      c.timeMs = timeMs();
      c.strength = q(.4);
      clipContacts_.push_back(c);
      return;
    }
}
void Engine::sync() {
  const Route route = router.resolve();
  int next = route.expression < 0 ? emotion : route.expression;
  moodBeat.context(route.quiet, grab, route.state == SceneState::kNeedsYou);
  if (next != expression) {
    T ms = moodBeat.retarget(expression, next, random);
    expression = next;
    motion.emotion = next;
    acting.setMood(next, motion.time);
    face.setMood(next, ms);
  }
  face.setSleeping(route.quiet || leaning == kLeanDoze);
  scenes.setRoute(route, timeMs(), expression, random);
  // Acting plays in idle, and wherever the scene's recipe carries a bit.
  const int gag = scenes.gag();
  acting.setSuppressed((route.state != SceneState::kIdle && gag < 0) || grab, motion.time);
  acting.hold(gag, scenes.generation, scenes.iteration, motion.time);
}
void Engine::step(uint32_t ms) {
  uint32_t delta = stamped_ ? std::min(uint32_t(ms - previous_), uint32_t(45)) : 0;
  previous_ = ms;
  stamped_ = true;
  cues.clear();
  elapsedMs += delta;
  if (dazed_ && int32_t(dazeEnd_ - elapsedMs) <= 0) dazed_ = false;
  T dt = T::ratio(delta, 1000);
  motion.advance(dt, motion.time + dt, random);
  sync();
  moodBeat.advance(dt);
  scenes.advance(dt, timeMs(), grab, random);
  acting.advance(dt, motion.time, grab, random);
  // Held, the pull follows the finger quickly; let go, it settles back on a
  // softer spring, a wobble rather than a snap.
  if (leaning) {
    const bool dozing = leaning == kLeanDoze;
    const F breath = sin(motion.time * (dozing ? kDozeBreathRate : kLeanBreathRate)) * kLeanBreath;
    target[0] = kLeanReach * leanX_;
    target[1] = kLeanReach * leanY_ / 2 - (dozing ? kDozeSlump : kLeanSlump) + breath;
    target[2] = kLeanForward;
  } else if (!grab) {
    const F nodding = nod();
    target[0] = 0, target[1] = -kNodSquash * nodding, target[2] = kNodForward * nodding;
  }
  const F shutGoal = leanLids_ ? kLeanLids : F(0);
  if (leanShut_.raw != shutGoal.raw) leanShut_ += (shutGoal - leanShut_) * (F(1) - exp(-dt * 7));
  const int* spring = leaning ? kGrabLeaning : grab ? kGrabHeld : kGrabReleased;
  for (int i = 0; i < 3; ++i) integrate(pull[i], dt, target[i], spring[0], spring[1], kGrabLimit, kGrabVelocity);
  integrate(tilt_, dt, tiltTarget_, kTiltSpring[0], kTiltSpring[1], q(.72), kGrabVelocity);
  face.advance(dt);
  const F w = 10;
  for (int i = 0; i < slime::kProfiles; ++i) {
    auto& m = postureWeights[i];
    const F goal = i == expression ? 1 : 0;
    if (!m.x.raw && !m.v.raw && !goal.raw) continue;
    for (F left = dt; left > F(0);) {
      F h = min(left, q(1.0 / 240));
      m.v += (w * w * (goal - m.x) - 2 * w * m.v) * h;
      m.x += m.v * h;
      left -= h;
    }
  }
  consumeCues();
  clipContacts_.clear();
}
std::array<F, 4> Engine::pose() const {
  auto out = motion.pose();
  const auto mood = posture();
  out[0] += acting.channels[0].x + mood[0] + scenes.activity[0].x + moodBeat.channels[0].x;
  out[1] += acting.channels[1].x + mood[1] + scenes.activity[1].x + moodBeat.channels[1].x;
  out[2] += acting.channels[2].x;
  // The pull leans and squashes the whole body, inside its bounds.
  out[0] += kGrabLean * pull[0].x;
  out[1] += kGrabSquash * pull[1].x;
  out[0] += tilt_.x;
  const F limits[] = {q(1.25), q(1.32), q(1.14), q(.72)};
  for (int i = 0; i < 4; ++i) out[i] = clamp(out[i], -limits[i], limits[i]);
  return out;
}
F Engine::nod() const {
  if (scenes.route.state != SceneState::kListening) return 0;
  const F t = motion.time, beat = max(0, sin(t * kNodRate));
  return square(beat) * clamp(q(.5) + q(.7) * sin(t * kNodBursts + 1), 0, 1);
}
std::array<F, 2> Engine::posture() const {
  F lean = 0, squash = 0;
  for (int i = 0; i < slime::kProfiles; ++i) {
    F w = postureWeights[i].x;
    int m = slime::kProfile[i].canonical;
    F s = 0;
    switch (m) {
      case slime::kSad:
      case slime::kWounded: s = q(-.055); break;
      case slime::kProud: s = q(.05); break;
      case slime::kDetermined: s = q(.022); break;
      case slime::kFocused: s = q(.012); break;
      case slime::kCurious: s = q(.03); break;
    }
    squash += w * s;
    // Curious leans toward what it peers at, the side of its bigger eye.
    if (m == slime::kCurious) lean += w * kCuriousLean;
    F t = motion.time;
    if (m == slime::kExcited) squash += w * q(.012) * sin(t * q(4.3));
  }
  return {lean * (1 - scenes.quietMix.x), squash * (1 - scenes.quietMix.x)};
}
std::array<F, 3> Engine::life() const {
  return {clamp(max(0, acting.channels[3].x), q(-.24), q(.24)), clamp(acting.channels[4].x, q(-.12), q(.12)),
          clamp(acting.channels[5].x + scenes.activity[2].x + moodBeat.channels[2].x, q(-.23), q(.23))};
}
bool Engine::admits(const ContactEvent& c, SceneState state, bool quiet, bool protect) {
  // Comedy sounds even in a quiet state, with the routine chance.
  if (comedy(c.kind)) return soundRandom.unit() < slime::kRoutineProbability;
  if (quiet) return false;
  if (protect && reveals(c.kind)) {
    // What showed and the contact's kind, as one key.
    const uint64_t identity = c.key ^ uint64_t(c.kind) << 56;
    if (revealed_.find([&](uint64_t k) { return k == identity; })) return false;
    revealed_.add(identity);
  }
  if (isDesk(state)) {
    if (scenes.recipe.duration < slime::kShortLoopMs && scenes.iteration % slime::kShortLoopEvery) return false;
    if (cueCount_ >= slime::kMaxRoutine || soundRandom.unit() >= slime::kRoutineProbability) return false;
    ++cueCount_;
    return true;
  }
  return !scenes.iteration;
}
void Engine::consumeCues() {
  auto state = scenes.route.state;
  if (cueGeneration_ != scenes.generation || cueIteration_ != scenes.iteration) {
    cueGeneration_ = scenes.generation;
    cueIteration_ = scenes.iteration;
    cueCount_ = 0;
  }
  const bool quiet = state == SceneState::kIdle || state == SceneState::kAsleep || state == SceneState::kNoApp ||
                     state == SceneState::kListening || state == SceneState::kWaiting;
  const bool protect = state == SceneState::kNeedsYou || state == SceneState::kTaskComplete;
  // A key's contact sounds none: the keys clicking at every word were too
  // much, and the paws on the keyboard show it.
  static const char* recipes[] = {nullptr, "knock",  "squish", "ding",   "complete", "failed",
                                  nullptr, "squish", "squish", "sneeze", "breath",   "bounce"};
  static_assert(std::size(recipes) == slime::kContactKinds, "a recipe, or none, for every contact kind");
  // The scene's contacts, then a bit's, then a rig clip's cues'.
  for (const auto* list : {&scenes.contacts, &acting.contacts, &clipContacts_})
    for (const auto& c : *list) {
      const char* recipe = recipes[c.kind];
      // A finish a size above small cheers at its reveal and bounces as it lands.
      if (state == SceneState::kTaskComplete && isFinishVariant(scenes.variant) && list == &scenes.contacts)
        recipe = c.kind == kSuccess ? "cheer" : c.kind == kBody ? "bounce" : recipe;
      if (!recipe || !admits(c, state, quiet, protect)) continue;
      int mood = slime::kProfile[emotion].canonical;
      const auto& p = slime::kProfile[mood];
      SoundCue cue{c, recipe, mood, 0, 53, 1, q(.45), protect};
      if (c.kind != kAlert) {
        cue.variant = soundRandom.index(3);
        cue.seed = soundRandom.next();
        cue.pitch = p.pitch * (slime::kPitchLo + soundRandom.unit() * (slime::kPitchHi - slime::kPitchLo));
        cue.gain =
            min(q(.8), p.gain * c.strength * (slime::kGainLo + soundRandom.unit() * (slime::kGainHi - slime::kGainLo)));
      }
      cues.push_back(cue);
    }
}
}  // namespace render::gel
