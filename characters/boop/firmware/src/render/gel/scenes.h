#pragma once
#include <cstring>
#include <vector>
#include "render/gel/acting.h"
#include "render/gel/finish.h"
#include "render/gel/router.h"
namespace render::gel {
// The recipe table's rows (slime::kRecipes): each state's, which a state
// the Mac no longer sends shares with the one that stands in for it
// (slime::kRecipeRow), then task_complete's success and failure.
static_assert(int(SceneState::kCount) == slime::kStates, "a row for every state");
static_assert(slime::kStateRows + 2 == slime::kRecipeStates, "recipe rows: states, outcomes");
inline int recipeState(SceneState state, Outcome outcome) {
  if (state == SceneState::kTaskComplete && outcome != Outcome::kNone) return slime::kStateRows + int(outcome) - 1;
  return slime::kRecipeRow[int(state)];
}
constexpr int rowOf(SceneState state) { return slime::kRecipeRow[int(state)]; }
// A row's takes: three, and a fourth for two rows, asleep's snore and a
// successful finish's hiccups. The fourths are a
// table of their own, so the other rows stay three.
static_assert(slime::kMaxTakes == 4 && slime::kFourthRows == 2, "two rows have a fourth take");
static_assert(slime::kRecipeTakes[rowOf(SceneState::kAsleep)] == 4 && slime::kRecipeTakes[slime::kStateRows] == 4 &&
                  slime::kRecipeTakes[slime::kStateRows + 1] == 3 &&
                  slime::kRecipeTakes[rowOf(SceneState::kNoApp)] == 3,
              "asleep and a success have a fourth take; a failure and a lost link don't");
inline int takes(int row) { return slime::kRecipeTakes[row]; }
static_assert(int(std::size(slime::kRecipes[0])) == kFirstTakes, "a row's first takes");
// The gesture state's takes are render::Gesture's, one for each, the same in
// every mood (kGestureTakes); the board names one, and no bag deals them.
static_assert(slime::kGestureCount == int(Gesture::kCount), "a take for each of render::Gesture");
static_assert(slime::kRecipeTakes[rowOf(SceneState::kGesture)] == slime::kGestureCount, "the gesture row's takes");
// A successful finish's row, whose variations go on past its takes with
// the finishes a size above small (render/gel/finish.h).
constexpr int kSuccessRow = slime::kStateRows;
// A take in a profile's mood. A moody recipe (a desk's, a result's, a
// start's, a wake's) takes the profile's timing traits: each contact at
// first + delay + (at - first) * spacing, from the first contact's time,
// its strength times the gain, and the lean added. The lifted success's
// gift is proud's alone. Any other recipe is the same in every mood.
inline slime::Recipe inMood(const slime::Recipe& base, int profile) {
  if (!base.moody) return base;
  slime::Recipe r = base;
  const F* traits = slime::kProfile[profile].traits;  // delay, spacing, gain, lean
  const T first = r.count ? base.contacts[0].at : T(0);
  for (int i = 0; i < r.count; ++i) {
    r.contacts[i].at = first + T(traits[0]) + T((base.contacts[i].at - first) * traits[1]);
    r.contacts[i].strength = base.contacts[i].strength * traits[2];
  }
  r.lean = base.lean + traits[3];
  r.gift = base.gift && profile == slime::kProud;
  return r;
}
inline slime::Recipe take(int profile, int row, int variant) {
  if (row == rowOf(SceneState::kGesture)) return slime::kGestureTakes[variant < slime::kGestureCount ? variant : 0];
  if (row == kSuccessRow && isFinishVariant(variant)) return finishRecipe(finishOf(variant));
  return inMood(variant < kFirstTakes ? slime::kRecipes[row][variant] : slime::kFourthTakes[slime::kFourthRow[row]],
                profile);
}
// Idle's takes: its mood's move, then its own bits (acting.h
// Acting::takes), at most this many.
static_assert(slime::kIdleTakes == 2, "the mood's move and an own gag");
enum ContactKind {
  kKey,
  kKnock,
  kBody,
  kAlert,
  kSuccess,
  kFailure,
  kResult,
  kStart,
  kReply,
  // Comedy's: a bit's sneeze and zoomies, a snore's breath.
  kSneeze,
  kBreath,
  kZoom
};
static_assert(kZoom + 1 == slime::kContactKinds, "contact kinds as slimegen numbers them");
// A reveal: the alert's, or a card's or a start's.
constexpr bool reveals(int kind) { return kind >= kAlert && kind <= kReply; }
// Comedy's contacts sound even in a quiet state, with the routine chance.
constexpr bool comedy(int kind) { return kind >= kSneeze; }
// A prop's visibility over kPropRampMs: a cubic Hermite from
// the current value and slope: a smoothstep from rest, continuous in value and
// velocity on a reversal, exact at its end.
constexpr int kPropRampMs = 200;
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
  // How far the desk shows each activity (router.h's Activity), 0 … 1,
  // typing's what the others leave: the paws ease from one pose to the next
  // by them (paintProps).
  Spring pose[kActivities];
  F posed(Activity a) const { return pose[int(a)].x; }
  Route route;
  uint64_t key = 0;  // what shows (Route::key)
  int mood = slime::kCalm, expression = slime::kCalm, profileExpression = slime::kCalm;
  int generation = 0, iteration = 0, variant = 0, cursor = 0;
  T started, ageMs, revealAt;
  slime::Recipe recipe{};
  std::vector<ContactEvent> contacts;
  ContactEvent last;
  bool hasLast = false, resultRevealed = false, completed = false, quietRestored = false;
  const char* phase = "sustain";
  Bag<slime::kMaxTakes> bags[slime::kCanonical][slime::kRecipeStates];
  // A take kept: the catalog is immutable, so where it is (its row, take
  // and profile, which take() builds it from) and its jitter's seed, not
  // its contacts. The needs-you showing and the reaction held
  // each keep theirs, and an alert how far it got, so one interrupted
  // resumes there.
  struct Saved {
    uint64_t key = 0;  // what it showed (Route::key)
    int variant, profile, row;
    uint32_t seed;
    T ageMs;
    int cursor = 0;
  };
  Saved alert, held;
  // Each prop keeps the content it last showed while its ramp fades it out.
  enum Prop { kAlertProp, kListeningProp, kProps };
  struct Slot {
    bool on = false;
    uint64_t key = 0;
    Ramp ramp;
  } slots[kProps];
  struct {
    std::string agent, project, name;
    int more = 0;
    bool known = false;
  } alertProp;
  F listeningPulse = q(.5);
  // The tags on and how long the look has shown (Engine::setOccasion).
  uint32_t when = 0, lookMs = 0;
  // The bit the recipe playing carries for acting (a gesture's, a
  // pastime's), as kGags numbers it, or -1.
  int gag() const { return generation ? recipe.gag : -1; }
  // The successful finish playing: its variation's, from its reveal.
  FinishShow finishShow() const;
  void setRoute(const Route&, T time, int expression, Random&);
  void pickRecipe(T time, Random&);
  // A pastime's take (slime::kPastimeTakes) the face dealt: the look's next
  // take, from now, numbered after its row's own.
  void playTake(int take, T time, Random&);
  // A take starts over from `time`: its age, contacts and reveal.
  void restartTake(T time);
  void advance(T dt, T time, bool grab, Random&);
  F envelope(T time, int kind) const;
  F recovery() const {
    return !std::strcmp(phase, "recover")   ? smooth((recipe.duration - ageMs) / 480)
           : !std::strcmp(phase, "sustain") ? F(0)
                                             : F(1);
  }
  F entry() const { return smooth(ageMs / 240); }
  F focus() const { return q(.5) + q(.5) * sin(clamp(ageMs / recipe.duration, 0, 1) * pi * 2 * recipe.focus); }
  // A prop's drawn opacity: its ramp.
  F visible(Prop prop, T time) const { return slots[prop].ramp.value(time); }

 private:
  const char* phaseAt(T age) const;
  bool wants(Prop prop) const;
  void refresh(Prop prop);
  void updateProps(T time);
};
}  // namespace render::gel
