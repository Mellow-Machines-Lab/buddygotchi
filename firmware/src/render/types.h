// Boop animation, mood and factual-state vocabulary.
// Shared by face implementations; no generated pixel asset dependency.
#pragma once
#include <cstdint>

#include "moods.h"  // the character pack's (characters/CHARACTER.md §9)

namespace render {

// The character's mood, which picks the set of designs every look and
// animation is drawn in. The list is the character pack's,
// in its order, from its generated moods.h (characters/CHARACTER.md §9):
// a face looks a mood up by its name, never by its number.
Mood moodFromName(const char* name);          // kStartupMood if missing or unknown
bool parseMood(const char* name, Mood& out);  // false, and `out` untouched, if missing or unknown
const char* moodName(Mood m);

// The designs' states, in faces.h's order: the first
// seven keep the numbers they had before the rest came. Idle, working,
// asleep, needs you, no app and what the agents are doing (planning to
// waiting) are looks, what the face shows when no reaction plays; the rest
// are the reactions' animations (isReaction), each playing its own state's
// design.
// kNone, past the designs, is no animation.
enum class SceneState : uint8_t {
  kIdle,
  kWorking,
  kNeedsYou,
  kTaskComplete,
  kAsleep,
  kNoApp,
  kListening,
  kStarting,
  kPlanning,
  kTerminal,
  kToolUse,
  kSearching,
  kAnalyzing,
  kTesting,
  kDelegating,
  kHelperReturn,
  kWaiting,
  kReplyReady,
  kError,
  kStopped,
  kPoked,
  kTapSpam,
  kCount,
  kNone = 0xFF
};
// The state's name, faces.h's kStateNames ("idle", "needs_you", ...);
// "none" for kNone.
const char* stateName(SceneState s);
SceneState stateFromName(const char* name);  // kIdle if missing or unknown
// The reactions' animations: the brain's finish (task_complete, a turn done
// or failed; reply_ready, an answer or a question back), the rules'
// reactions (starting, stopped, error, helper_return), a tap's (poked, and
// tap_spam from the third in a row) and push-to-talk's listening, until
// the reply.
bool isReaction(SceneState s);
SceneState reactionFromName(const char* name);  // kNone for any other name

// The host fact a variation is for, when it's for one: task_complete's
// outcome and starting's context. kNone on a design
// is for any; as a filter, it takes any.
enum class Outcome : uint8_t { kNone, kSuccess, kFailure };
enum class StartCtx : uint8_t { kNone, kNewTask, kSession, kContinuation, kCompacted };
Outcome outcomeFromName(const char* name);  // "success" or "failure"; kNone otherwise
StartCtx ctxFromName(const char* name);     // "new_task", "session", "continuation" or "compacted"; kNone otherwise

struct SceneShow {
  Mood mood = kStartupMood;
  SceneState state = SceneState::kIdle;
  uint8_t variant = 0;  // from 0; one out of range draws the first
  uint32_t t = 0;       // ms since the scene started
  // A blink, or the blink that hides a change of design: the first pack's
  // closed eyes instead of its open ones, and a flip-book's own blink step
  // in place of the step showing.
  bool eyesShut = false;
  bool mouthOpen = false;  // talking: a small "o" on the mouth, instead of it
  int16_t dy = 0;          // the face pressed down
};

}  // namespace render
