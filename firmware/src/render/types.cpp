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
Anim animFromName(const char* name) {
  if (!name) return Anim::kNone;
  for (int i = 1; i < int(Anim::kCount); ++i) {
    if (!std::strcmp(name, animName(Anim(i)))) return Anim(i);
  }
  return Anim::kNone;
}

const char* animName(Anim a) {
  return a != Anim::kNone && int(a) < int(Anim::kCount) ? stateName(animState(a)) : "none";
}

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

const char* stateName(SceneState s) { return kStateNames[int(s) < int(SceneState::kCount) ? int(s) : 0]; }

SceneState animState(Anim a) {
  switch (a) {
    case Anim::kTaskComplete: return SceneState::kTaskComplete;
    case Anim::kReplyReady: return SceneState::kReplyReady;
    case Anim::kStarting: return SceneState::kStarting;
    case Anim::kStopped: return SceneState::kStopped;
    case Anim::kError: return SceneState::kError;
    case Anim::kHelperReturn: return SceneState::kHelperReturn;
    case Anim::kPoked: return SceneState::kPoked;
    case Anim::kTapSpam: return SceneState::kTapSpam;
    case Anim::kListening: return SceneState::kListening;
    default: return SceneState::kIdle;
  }
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
