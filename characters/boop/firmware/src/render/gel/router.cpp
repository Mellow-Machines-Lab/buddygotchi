#include "render/gel/router.h"
namespace render::gel {
bool isDesk(SceneState s) {
  switch (s) {
    case SceneState::kWorking:
    case SceneState::kPlanning:
    case SceneState::kTerminal:
    case SceneState::kToolUse:
    case SceneState::kSearching:
    case SceneState::kAnalyzing:
    case SceneState::kTesting:
    case SceneState::kDelegating:
    case SceneState::kWaiting: return true;
    default: return false;
  }
}
Activity activityOf(SceneState s) {
  switch (s) {
    case SceneState::kAnalyzing:
    case SceneState::kSearching: return Activity::kLooking;
    case SceneState::kTerminal:
    case SceneState::kTesting:
    case SceneState::kDelegating: return Activity::kRunning;
    case SceneState::kWaiting: return Activity::kWaiting;
    default: return Activity::kTyping;
  }
}
SceneState deskStateOf(Activity a) {
  switch (a) {
    case Activity::kLooking: return SceneState::kAnalyzing;
    case Activity::kRunning: return SceneState::kTerminal;
    case Activity::kWaiting: return SceneState::kWaiting;
    default: return SceneState::kWorking;
  }
}
Family family(SceneState s) {
  switch (s) {
    case SceneState::kAsleep:
    case SceneState::kNoApp: return Family::kRest;
    case SceneState::kIdle: return Family::kIdle;
    case SceneState::kListening: return Family::kListen;
    case SceneState::kWakeUp:
    case SceneState::kNotice: return Family::kStart;
    case SceneState::kNeedsYou: return Family::kAlert;
    case SceneState::kTaskComplete:
    case SceneState::kReplyReady: return Family::kResult;
    case SceneState::kPoked:
    case SceneState::kTapSpam:
    case SceneState::kGesture: return Family::kTouch;
    default: return Family::kDesk;
  }
}
// A needs-you is new when it comes on, or asks for another request.
void Router::setFacts(const Facts& value) {
  const auto& a = value.attention;
  const auto& previous = facts.attention;
  if (a.on && (!previous.on || a.id != previous.id || a.agent != previous.agent || a.project != previous.project))
    ++alerts;
  facts = value;
  if (a.on) {
    reacting = false;
    expression = -1;
  }
}
bool Router::play(const Request& in, T time) {
  listening = false;
  if (timedOut || in.anim == SceneState::kNone) return false;
  if (in.anim == SceneState::kListening) {
    reacting = false;
    expression = -1;
    listening = true;
    ++reactions;
    return true;
  }
  if (facts.attention.on) return false;
  reacting = true;
  reaction = in;
  reaction.loops = in.loops < 1 ? 1 : in.loops;  // the device holds it to its most
  reactionAt = time;
  expression = in.expression;
  ++reactions;
  return true;
}
Route Router::resolve() const {
  Route r;
  r.baseState = facts.look();
  r.state = timedOut             ? SceneState::kNoApp
            : listening          ? SceneState::kListening
            : facts.attention.on ? SceneState::kNeedsYou
            : reacting           ? reaction.anim
                                 : r.baseState;
  r.group = family(r.state);
  r.quiet = r.state == SceneState::kAsleep || r.state == SceneState::kNoApp;
  r.key = timedOut             ? showKey(Shows::kLostLink, 0)
          : listening          ? showKey(Shows::kListening, reactions)
          : facts.attention.on ? showKey(Shows::kNeedsYou, alerts)
          : reacting           ? showKey(Shows::kReaction, reactions)
                               : showKey(Shows::kLook, uint32_t(r.baseState));
  r.attention = facts.attention.on ? &facts.attention : nullptr;
  r.expression = expression;
  if (reacting) {
    r.reaction = &reaction;
    r.reactionAt = reactionAt;
    r.outcome = reaction.outcome;
    r.loops = reaction.loops;
  }
  return r;
}
}  // namespace render::gel
