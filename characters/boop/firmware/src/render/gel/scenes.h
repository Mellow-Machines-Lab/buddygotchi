#pragma once
#include <cstring>
#include <vector>
#include "render/gel/acting.h"
#include "render/gel/router.h"
namespace render::gel {
// The recipe table's rows (slime::kRecipes): every state, then
// task_complete's success and failure, then starting's four contexts.
inline int recipeState(SceneState state, Outcome outcome, StartCtx ctx) {
  constexpr int kStates = int(SceneState::kCount);
  if (state == SceneState::kTaskComplete && outcome != Outcome::kNone) return kStates + int(outcome) - 1;
  if (state == SceneState::kStarting && ctx != StartCtx::kNone) return kStates + 2 + int(ctx) - 1;
  return int(state);
}
static_assert(int(SceneState::kCount) + 2 + 4 == slime::kRecipeStates, "recipe rows: states, outcomes, contexts");
enum ContactKind {
  kKey,
  kKnock,
  kBody,
  kAlert,
  kSuccess,
  kFailure,
  kResult,
  kStart,
  kHelper,
  kReply,
  kError,
  kStopped
};
// A contact as it fires. The reference's id for it is
// "requestId:generation:iteration:index", which nothing on the device
// reads, so only the trace check spells it out (gel-trace): building it on
// every contact cost the board's heap a few allocations each.
struct ContactEvent {
  std::string requestId;
  int generation = 0, iteration = 0, index = 0;
  uint8_t kind = 0;
  int side = 0;
  T timeMs;
  F strength;
};
// scenes/ramp.mjs: a prop's visibility over kPropRampMs. A cubic Hermite from
// the current value and slope: a smoothstep from rest, continuous in value and
// velocity on a reversal, exact at its end.
constexpr int kPropRampMs = 200;
struct Ramp {
  F from, to, tangent;
  T start;
  bool active = false;
  F value(T time) const;
  void retarget(F next, T time);
  void reset() { *this = Ramp{}; }

 private:
  void at(T time, F& value, F& slope) const;
};
struct Scenes {
  Spring activity[3], desk, quietMix;
  Route route;
  std::string requestId;
  int mood = slime::kCalm, expression = slime::kCalm, profileExpression = slime::kCalm;
  int generation = 0, iteration = 0, variant = 0, cursor = 0;
  T started, ageMs, revealAt;
  slime::Recipe recipe{};
  std::vector<ContactEvent> contacts;
  ContactEvent last;
  bool hasLast = false, resultRevealed = false, completed = false, quietRestored = false;
  const char* phase = "sustain";
  Bag bags[slime::kCanonical][slime::kRecipeStates];
  // The catalog is immutable. Keep its address and the jitter seed instead
  // of copying every contact into each of the two 64-entry histories. An
  // alert also keeps how far it got, so an interrupted one resumes there.
  struct Saved {
    uint64_t id;  // identityKey of the request
    int variant, profile;
    const slime::Recipe* recipe;
    uint32_t seed;
    T ageMs;
    int cursor = 0;
  };
  History<Saved, 64> alerts, moments;
  // Each prop keeps the content it last showed while its ramp fades it out
  // (CONTINUITY.md, Representative activity scenes).
  enum Prop { kAlertProp, kResultProp, kStartProp, kHelpersProp, kListeningProp, kTouchProp, kProps };
  struct Slot {
    bool on = false;
    std::string id;
    int iteration = 0;
    Ramp ramp;
  } slots[kProps];
  struct {
    std::string requestId, agent, project, name;
    int more = 0;
    bool known = false;
  } alertProp;
  struct {
    SceneState state = SceneState::kIdle;
    bool known = false;
    const char* label = "FINISHED";
    Outcome outcome = Outcome::kNone;
    F reveal;
  } resultProp;
  struct {
    const char* label = "START";
    StartCtx ctx = StartCtx::kNone;
    F reveal;
  } startProp;
  struct {
    bool returning = false, report = false;
    int count = 0, direction = 1;
    F progress, presence;
  } helpersProp;
  F listeningPulse = q(.5);
  SceneState touchKind = SceneState::kIdle;
  bool touchKnown = false;
  void setRoute(const Route&, T time, int expression, Random&);
  void pickRecipe(T time, Random&);
  std::string advance(T dt, T time, bool grab, bool reduced, Random&);
  F envelope(T time, int kind) const;
  F recovery() const {
    return !std::strcmp(phase, "recover")   ? smooth((recipe.duration - ageMs) / 480)
           : !std::strcmp(phase, "sustain") ? F(0)
                                             : F(1);
  }
  F entry() const { return smooth(ageMs / 240); }
  // A card rises over the prop ramp from its reveal contact and fades in recovery.
  F cardReveal() const { return resultRevealed ? smooth((ageMs - revealAt) / kPropRampMs) * recovery() : F(0); }
  F focus(bool reduced) const {
    return reduced ? q(.5) : q(.5) + q(.5) * sin(clamp(ageMs / recipe.duration, 0, 1) * pi * 2 * recipe.focus);
  }
  // A prop's drawn opacity: its ramp, times a card's reveal or the helpers' recovery.
  F visible(Prop prop, T time) const { return slots[prop].ramp.value(time) * drawnFactor(prop); }

 private:
  F drawnFactor(Prop prop) const {
    return prop == kResultProp    ? resultProp.reveal
           : prop == kStartProp   ? startProp.reveal
           : prop == kHelpersProp ? helpersProp.presence
                                  : F(1);
  }
  const char* phaseAt(T age) const;
  bool wants(Prop prop) const;
  void refresh(Prop prop, bool reduced);
  void updateProps(T time, bool reduced);
};
}  // namespace render::gel
