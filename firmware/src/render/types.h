// Boop animation, mood and factual-state vocabulary.
// Shared by face implementations; no generated asset dependency.
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
// waiting) are looks: Doing, what the face shows when no Moment plays;
// the rest are the Moments' animations (isMoment), each playing its own
// state's design.
// kNone, past the designs, is no animation.
enum class SceneState : uint8_t {
  kIdle,
  kWorking,
  kNeedsYou,
  kTaskComplete,
  kAsleep,
  kNoApp,
  kListening,
  kPlanning,
  kTerminal,
  kToolUse,
  kSearching,
  kAnalyzing,
  kTesting,
  kDelegating,
  kWaiting,
  kReplyReady,
  kPoked,
  kTapSpam,
  kWakeUp,
  kGesture,
  kNotice,
  kCount,
  kNone = 0xFF
};
// The state's name, faces.h's kStateNames ("idle", "needs_you", ...);
// "none" for kNone.
const char* stateName(SceneState s);
SceneState stateFromName(const char* name);  // kIdle if missing or unknown
// The Moments' animations: the brain's finish (task_complete, a turn done
// or failed; reply_ready, an answer or a question back) and its wake_up
// (you back at the Mac after a long break) and its notice (you named it in
// your prompt: it looks up at you), a tap's (poked, and
// tap_spam from the third in a row), the board's own to a gesture
// (gesture) and push-to-talk's listening, until the reply.
bool isMoment(SceneState s);

// What a gesture is, for the board's own reaction to it (SceneState::
// kGesture): its variations are these, in this order, and a face with
// fewer draws its first. A BOOT press that hands you an agent; a stroke,
// one the wrong way, a boop on the nose, a tickle (touch); a shake, a
// pick-up, a put-down, a thump on the desk, turned face up again (motion).
enum class Gesture : uint8_t {
  kHandoff,
  kStroke,
  kRuffle,
  kNose,
  kTickle,
  kDizzy,
  kPickup,
  kPutdown,
  kStartle,
  kPeekaboo,
  kCount
};
const char* gestureName(Gesture g);  // "handoff", "stroke", ...
SceneState reactionFromName(const char* name);  // kNone for any other name

// The host fact a variation is for, when it's for one: task_complete's
// outcome. kNone on a design is for any; as a filter, it takes any.
enum class Outcome : uint8_t { kNone, kSuccess, kFailure };
Outcome outcomeFromName(const char* name);  // "success" or "failure"; kNone otherwise

// What a celebration's gold has before its words (a `do`'s `mark`): a star,
// a full ring for today's ring, or a medal for a league's place.
enum class GoldMark : uint8_t { kStar, kRing, kGold, kSilver, kBronze };
GoldMark goldMarkFromName(const char* name);  // "ring", "gold", "silver", "bronze"; kStar otherwise
// What the needs-you request asks of you (`attn.kind`): a yes or no to a
// call, a question to answer, or a plan to read; kNone when the Mac doesn't
// say (an older app, or practice).
enum class AttnKind : uint8_t { kNone, kApprove, kQuestion, kPlan };
AttnKind attnKindFromName(const char* name);  // "approve", "question" or "plan"; kNone otherwise
const char* attnKindName(AttnKind k);         // the wire's name; null for kNone
// The tier the turn a finish is for reached (its `turn`), as the tags count
// them (render/tags.h): 0 short of the first, then 1 to kTurnTiers for tier1
// to tier5 (the Mac sends up to 3); kNoTurn when the Mac doesn't say.
constexpr int kNoTurn = -1, kTurnTiers = 5;

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
