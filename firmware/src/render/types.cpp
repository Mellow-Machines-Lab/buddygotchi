#include "render/types.h"
#include <cstring>
namespace render {
namespace {
constexpr const char* kStateNames[22] = {
    "idle",     "working",     "needs_you", "task_complete", "asleep",    "no_app",  "listening",  "starting",
    "planning", "terminal",    "tool_use",  "searching",     "analyzing", "testing", "delegating", "helper_return",
    "waiting",  "reply_ready", "error",     "stopped",       "poked",     "tap_spam"};
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

bool isMoment(SceneState s) {
  switch (s) {
    case SceneState::kTaskComplete:
    case SceneState::kReplyReady:
    case SceneState::kStarting:
    case SceneState::kStopped:
    case SceneState::kError:
    case SceneState::kHelperReturn:
    case SceneState::kPoked:
    case SceneState::kTapSpam:
    case SceneState::kListening: return true;
    default: return false;
  }
}

SceneState momentFromName(const char* name) {
  const SceneState s = stateFromName(name);
  return name && isMoment(s) ? s : SceneState::kNone;
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
