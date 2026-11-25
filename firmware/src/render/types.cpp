#include "render/types.h"
#include <cstring>
namespace render {
namespace {
constexpr const char* kStateNames[] = {
    "idle",     "working",     "needs_you", "task_complete", "asleep",    "no_app",  "listening",
    "planning", "terminal",    "tool_use",  "searching",     "analyzing", "testing", "delegating",
    "waiting",  "reply_ready", "poked",     "tap_spam",      "wake_up",   "gesture", "notice"};
constexpr const char* kGestureNames[] = {"handoff", "stroke", "ruffle",  "nose",    "tickle",
                                         "dizzy",   "pickup", "putdown", "startle", "peekaboo"};
static_assert(sizeof kGestureNames / sizeof kGestureNames[0] == int(Gesture::kCount), "a name for every gesture");
static_assert(sizeof kStateNames / sizeof kStateNames[0] == int(SceneState::kCount), "a name for every state");
const char* const kOutcomes[] = {"", "success", "failure"};
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

bool isMoment(SceneState s) {
  switch (s) {
    case SceneState::kTaskComplete:
    case SceneState::kReplyReady:
    case SceneState::kWakeUp:
    case SceneState::kNotice:
    case SceneState::kPoked:
    case SceneState::kTapSpam:
    case SceneState::kGesture:
    case SceneState::kListening: return true;
    default: return false;
  }
}

SceneState reactionFromName(const char* name) {
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

GoldMark goldMarkFromName(const char* name) {
  static constexpr const char* kMarks[] = {"star", "ring", "gold", "silver", "bronze"};
  for (int i = 1; name && i < int(sizeof(kMarks) / sizeof(kMarks[0])); ++i) {
    if (!std::strcmp(name, kMarks[i])) return GoldMark(i);
  }
  return GoldMark::kStar;
}

namespace {
constexpr const char* kAttnKinds[] = {nullptr, "approve", "question", "plan"};
}

AttnKind attnKindFromName(const char* name) {
  for (int i = 1; name && i < int(sizeof(kAttnKinds) / sizeof(kAttnKinds[0])); ++i) {
    if (!std::strcmp(name, kAttnKinds[i])) return AttnKind(i);
  }
  return AttnKind::kNone;
}

const char* attnKindName(AttnKind k) { return kAttnKinds[int(k) < 4 ? int(k) : 0]; }

}  // namespace render
