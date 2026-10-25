#pragma once
#include <cstring>
#include <vector>
#include "render/gel/acting.h"
#include "render/gel/finish.h"
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
// A row's takes: three, and a fourth for two rows, asleep's snore and a
// successful finish's hiccups. The fourths are a
// table of their own, so the other rows stay three.
static_assert(slime::kMaxTakes == 4 && slime::kFourthRows == 2, "two rows have a fourth take");
static_assert(slime::kRecipeTakes[int(SceneState::kAsleep)] == 4 && slime::kRecipeTakes[int(SceneState::kCount)] == 4 &&
                  slime::kRecipeTakes[int(SceneState::kCount) + 1] == 3 &&
                  slime::kRecipeTakes[int(SceneState::kNoApp)] == 3,
              "asleep and a success have a fourth take; a failure and a lost link don't");
inline int takes(int row) { return slime::kRecipeTakes[row]; }
static_assert(int(std::size(slime::kRecipes[0][0])) == kGestures, "a row's first takes, one for each gesture");
// The gesture state's takes are render::Gesture's, one for each, the same in
// every mood (kGestureTakes); the board names one, and no bag deals them.
static_assert(slime::kGestureCount == int(Gesture::kCount), "a take for each of render::Gesture");
static_assert(slime::kRecipeTakes[int(SceneState::kGesture)] == slime::kGestureCount, "the gesture row's takes");
// A successful finish's row, whose variations go on past its takes with
// the finishes a size above small (render/gel/finish.h).
constexpr int kSuccessRow = int(SceneState::kCount);
inline const slime::Recipe& take(int profile, int row, int variant) {
  if (row == int(SceneState::kGesture)) return slime::kGestureTakes[variant < slime::kGestureCount ? variant : 0];
  if (row == kSuccessRow && isFinishVariant(variant)) return finishRecipe(finishOf(variant));
  return variant < kGestures ? slime::kRecipes[profile][row][variant]
                             : slime::kFourthTakes[profile][slime::kFourthRow[row]];
}
// Idle's takes: an expression's three gestures, its own gags, then the idle
// gags (acting.h Acting::takes), at most this many.
static_assert(slime::kMaxGestures == 7, "three gestures, an own gag and three idle gags");
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
  kStopped,
  // Comedy's: a gag's sneeze and zoomies, a snore's breath.
  kSneeze,
  kBreath,
  kZoom
};
static_assert(kZoom + 1 == slime::kContactKinds, "contact kinds as slimegen numbers them");
// A reveal: the alert's, or a card's or a start's.
constexpr bool reveals(int kind) { return kind >= kAlert && kind <= kStopped; }
// Comedy's contacts sound even in a quiet state, with the routine chance.
constexpr bool comedy(int kind) { return kind >= kSneeze; }
// A prop's visibility over kPropRampMs: a cubic Hermite from
// the current value and slope: a smoothstep from rest, continuous in value and
// velocity on a reversal, exact at its end.
constexpr int kPropRampMs = 200;
// A card's reveal, from its reveal contact.
constexpr int kCardRevealMs = 400;
struct Ramp {
  F from, to, tangent;
  T start;
  int windowMs = kPropRampMs;
  bool active = false;
  F value(T time) const;
  // Toward next from time, over `overMs`; the slope it has carries over into
  // the new window.
  void retarget(F next, T time, int overMs = kPropRampMs);
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
  Bag<slime::kMaxTakes> bags[slime::kCanonical][slime::kRecipeStates];
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
  // Each prop keeps the content it last showed while its ramp fades it out.
  enum Prop { kAlertProp, kResultProp, kStartProp, kListeningProp, kTouchProp, kProps };
  struct Slot {
    bool on = false;
    std::string id;
    Ramp ramp;
    Ramp reveal;  // a card's (cardReveal)
  } slots[kProps];
  struct {
    std::string requestId, agent, project, name;
    int more = 0;
    bool known = false;
  } alertProp;
  struct {
    SceneState state = SceneState::kIdle;
    bool known = false, gift = false;  // a gift: proud's bug beside its card
    const char* label = "FINISHED";
    Outcome outcome = Outcome::kNone;
  } resultProp;
  struct {
    const char* label = "START";
  } startProp;
  F listeningPulse = q(.5);
  // The finish playing names whose turn it was, which the face marks
  // itself (render/gel/done.h): it shows no result card of its own.
  bool cardless = false;
  SceneState touchKind = SceneState::kIdle;
  // The tags on and how long the look has shown (Engine::setOccasion): a
  // look's occasion (kLookOccasions) is dealt by them, numbered after the
  // row's takes.
  uint32_t when = 0, lookMs = 0;
  // The gag the recipe playing carries for acting (a gesture's, an
  // occasion's), as kGags numbers it, or -1.
  int gag() const { return generation ? recipe.gag : -1; }
  // The successful finish playing: its variation's, from its reveal.
  FinishShow finishShow() const;
  void setRoute(const Route&, T time, int expression, Random&);
  void pickRecipe(T time, Random&);
  std::string advance(T dt, T time, bool grab, Random&);
  F envelope(T time, int kind) const;
  F recovery() const {
    return !std::strcmp(phase, "recover")   ? smooth((recipe.duration - ageMs) / 480)
           : !std::strcmp(phase, "sustain") ? F(0)
                                             : F(1);
  }
  F entry() const { return smooth(ageMs / 240); }
  F focus() const { return q(.5) + q(.5) * sin(clamp(ageMs / recipe.duration, 0, 1) * pi * 2 * recipe.focus); }
  // A prop's drawn opacity: its ramp, times a card's reveal.
  F visible(Prop prop, T time) const {
    const auto& slot = slots[prop];
    return slot.ramp.value(time) * (card(prop) ? slot.reveal.value(time) : F(1));
  }
  static bool card(Prop prop) { return prop == kResultProp || prop == kStartProp; }

 private:
  const char* phaseAt(T age) const;
  void cardReveal(Ramp& reveal) const;
  bool wants(Prop prop) const;
  void refresh(Prop prop);
  void updateProps(T time);
};
}  // namespace render::gel
