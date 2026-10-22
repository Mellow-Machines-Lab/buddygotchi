#include "render/types.h"
#include <cstring>
namespace render {
namespace {
constexpr const char* kStateNames[] = {
    "idle",     "working",     "needs_you", "task_complete", "asleep",    "no_app",   "listening",  "starting",
    "planning", "terminal",    "tool_use",  "searching",     "analyzing", "testing",  "delegating", "helper_return",
    "waiting",  "reply_ready", "error",     "stopped",       "poked",     "tap_spam", "wake_up",    "gesture"};
constexpr const char* kGestureNames[] = {"handoff", "stroke",  "ruffle", "nose",    "tickle",
                                         "dizzy",   "pickup",  "putdown", "startle", "peekaboo"};
static_assert(sizeof kGestureNames / sizeof kGestureNames[0] == int(Gesture::kCount), "a name for every gesture");
static_assert(sizeof kStateNames / sizeof kStateNames[0] == int(SceneState::kCount), "a name for every state");
const char* const kOutcomes[] = {"", "success", "failure"};
const char* const kCtxs[] = {"", "new_task", "session", "continuation", "compacted"};
}  // namespace
Mood moodFromName(const char* name) {
  Mood m = kStartupMood;
  parseMood(name, m);
  return m;
}

bool parseMood(const char* name, Mood& out) {
  if (!name) return false;
  for (int i = 0; i < int(Mood::kCount); ++i) {
    if (!std::strcmp(name, kMoodNames[i])) return out = Mood(i), true;
  }
  return false;
}

const char* moodName(Mood m) { return kMoodNames[int(m) < kMoodCount ? int(m) : int(kStartupMood)]; }

const char* stateName(SceneState s) {
  if (s == SceneState::kNone) return "none";
  return kStateNames[int(s) < int(SceneState::kCount) ? int(s) : 0];
}

const char* gestureName(Gesture g) { return int(g) < int(Gesture::kCount) ? kGestureNames[int(g)] : "handoff"; }

bool isReaction(SceneState s) {
  switch (s) {
    case SceneState::kTaskComplete:
    case SceneState::kReplyReady:
    case SceneState::kWakeUp:
    case SceneState::kStarting:
    case SceneState::kStopped:
    case SceneState::kError:
    case SceneState::kHelperReturn:
    case SceneState::kPoked:
    case SceneState::kTapSpam:
    case SceneState::kGesture:
    case SceneState::kListening: return true;
    default: return false;
  }
}

SceneState reactionFromName(const char* name) {
  const SceneState s = stateFromName(name);
  return name && isReaction(s) ? s : SceneState::kNone;
}

SceneState stateFromName(const char* name) {
  if (!name) return SceneState::kIdle;
  for (int i = 0; i < int(SceneState::kCount); ++i) {
    if (!std::strcmp(name, kStateNames[i])) return SceneState(i);
  }
  return SceneState::kIdle;
}

Outcome outcomeFromName(const char* name) {
  for (int i = 1; name && i < int(sizeof(kOutcomes) / sizeof(kOutcomes[0])); ++i) {
    if (!std::strcmp(name, kOutcomes[i])) return Outcome(i);
  }
  return Outcome::kNone;
}

StartCtx ctxFromName(const char* name) {
  for (int i = 1; name && i < int(sizeof(kCtxs) / sizeof(kCtxs[0])); ++i) {
    if (!std::strcmp(name, kCtxs[i])) return StartCtx(i);
  }
  return StartCtx::kNone;
}

}  // namespace render
