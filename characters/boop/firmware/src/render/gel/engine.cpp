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
void Engine::sync(int forced) {
  const Route route = router.resolve();
  int next = route.expression < 0 ? emotion : route.expression;
  bridge.context(route.quiet, grab, route.state == SceneState::kNeedsYou);
  if (next != expression) {
    T ms = bridge.retarget(expression, next, timeMs(), random, forced);
    expression = next;
    motion.emotion = next;
    acting.setMood(next, motion.time);
    face.setMood(next, ms);
  }
  face.setSleeping(route.quiet);
  scenes.setRoute(route, timeMs(), expression, random);
  // Acting plays in idle, and wherever the scene's recipe carries a gag.
  const int gag = scenes.gag();
  acting.setSuppressed((route.state != SceneState::kIdle && gag < 0) || grab, motion.time);
  acting.hold(gag, scenes.generation, scenes.iteration, motion.time);
  if (route.moment) router.duration(*route.requestId, scenes.recipe.duration);
}
void Engine::step(uint32_t ms) {
  uint32_t delta = stamped_ ? std::min(uint32_t(ms - previous_), uint32_t(45)) : 0;
  previous_ = ms;
  stamped_ = true;
  cues.clear();
  elapsedMs += delta;
  T dt = T::ratio(delta, 1000);
  motion.advance(dt, motion.time + dt, random);
  router.advance(timeMs());
  sync();
  bridge.advance(dt);
  auto ended = scenes.advance(dt, timeMs(), grab, random);
  if (!ended.empty()) {
    router.finish(ended);
    sync();
  }
  acting.advance(dt, motion.time, grab, random);
  // Held, the pull follows the finger quickly; let go, it settles back on a
  // softer spring, a wobble rather than a snap.
  const int* spring = grab ? kGrabHeld : kGrabReleased;
  for (int i = 0; i < 3; ++i) integrate(pull[i], dt, target[i], spring[0], spring[1], kGrabLimit, kGrabVelocity);
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
  out[0] += acting.channels[0].x + mood[0] + scenes.activity[0].x + bridge.channels[0].x;
  out[1] += acting.channels[1].x + mood[1] + scenes.activity[1].x + bridge.channels[1].x;
  out[2] += acting.channels[2].x;
  // The pull leans and squashes the whole body, inside its bounds.
  out[0] += kGrabLean * pull[0].x;
  out[1] += kGrabSquash * pull[1].x;
  const F limits[] = {q(1.25), q(1.32), q(1.14), q(.72)};
  for (int i = 0; i < 4; ++i) out[i] = clamp(out[i], -limits[i], limits[i]);
  return out;
}
std::array<F, 2> Engine::posture() const {
  F lean = 0, squash = 0;
  for (int i = 0; i < slime::kProfiles; ++i) {
    F w = postureWeights[i].x;
    int m = slime::kProfile[i].canonical;
    F s = 0;
    switch (m) {
      case slime::kLazy: s = q(-.04); break;
      case slime::kBored: s = q(-.022); break;
      case slime::kTired: s = q(-.032); break;
      case slime::kExhausted: s = q(-.1); break;
      case slime::kDisappointed: s = q(-.035); break;
      case slime::kSad:
      case slime::kWounded: s = q(-.055); break;
      case slime::kCrying:
      case slime::kFrightened: s = q(-.045); break;
      case slime::kShy: s = q(-.025); break;
      case slime::kComfy: s = q(-.02); break;
      case slime::kProud: s = q(.05); break;
      case slime::kDetermined: s = q(.022); break;
      case slime::kHopeful: s = q(.025); break;
      case slime::kEngaged: s = q(.012); break;
    }
    squash += w * s;
    F t = motion.time;
    if (m == slime::kExcited) squash += w * q(.012) * sin(t * q(4.3));
    if (m == slime::kScared || m == slime::kFrightened)
      lean += w * (m == slime::kScared ? q(.014) : q(.026)) * sin(t * 13) * (q(.35) + q(.65) * square(sin(t * q(.75))));
    if (m == slime::kCrying) squash += w * q(.01) * sin(t * q(3.1));
    if (m == slime::kIrritated) lean += w * q(.008) * sin(t * q(6.1)) * square(square(max(0, sin(t * q(.7)))));
  }
  return {lean * (1 - scenes.quietMix.x), squash * (1 - scenes.quietMix.x)};
}
std::array<F, 3> Engine::life() const {
  return {clamp(max(0, acting.channels[3].x), q(-.24), q(.24)), clamp(acting.channels[4].x, q(-.12), q(.12)),
          clamp(acting.channels[5].x + scenes.activity[2].x + bridge.channels[2].x, q(-.23), q(.23))};
}
bool Engine::admits(const ContactEvent& c, SceneState state, bool quiet, bool protect) {
  // Comedy sounds even in a quiet state, with the routine chance.
  if (comedy(c.kind)) return soundRandom.unit() < slime::kRoutineProbability;
  if (quiet) return false;
  if (protect && reveals(c.kind)) {
    // The request and the contact's kind, as its key.
    const uint64_t identity = identityKey(":" + std::to_string(c.kind), identityKey(c.requestId));
    if (revealed_.find([&](uint64_t k) { return k == identity; })) return false;
    revealed_.add(identity);
  }
  if (isDesk(state) && state != SceneState::kDelegating) {
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
  const bool protect =
      state == SceneState::kNeedsYou || state == SceneState::kTaskComplete || state == SceneState::kError;
  static const char* recipes[] = {"keyboard", "knock",  "squish", "ding",   "complete", "failed", nullptr, "squish",
                                  "squish",   "squish", "failed", "squish", "sneeze",   "breath", "bounce"};
  static_assert(std::size(recipes) == slime::kContactKinds, "a recipe, or none, for every contact kind");
  // The scene's contacts, then a gag's, then a rig clip's cues'.
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
