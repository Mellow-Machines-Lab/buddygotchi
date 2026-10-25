#include "render/gel/router.h"
namespace render::gel {
namespace {
std::string quoted(const std::string& value) {
  static const char hex[] = "0123456789abcdef";
  std::string out = "\"";
  for (unsigned char c : value) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      case '\b': out += "\\b"; break;
      case '\f': out += "\\f"; break;
      default:
        if (c < 32) {
          out += "\\u00";
          out += hex[c >> 4];
          out += hex[c & 15];
        } else
          out += char(c);
    }
  }
  return out + '"';
}
}  // namespace
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
Family family(SceneState s) {
  switch (s) {
    case SceneState::kAsleep:
    case SceneState::kNoApp: return Family::kRest;
    case SceneState::kIdle: return Family::kIdle;
    case SceneState::kListening: return Family::kListen;
    case SceneState::kStarting:
    case SceneState::kWakeUp:
    case SceneState::kNotice: return Family::kStart;
    case SceneState::kDelegating:
    case SceneState::kHelperReturn: return Family::kHelpers;
    case SceneState::kNeedsYou: return Family::kAlert;
    case SceneState::kTaskComplete:
    case SceneState::kReplyReady:
    case SceneState::kError:
    case SceneState::kStopped: return Family::kResult;
    case SceneState::kPoked:
    case SceneState::kTapSpam:
    case SceneState::kGesture: return Family::kTouch;
    default: return Family::kDesk;
  }
}
void Router::setFacts(const Facts& value) {
  const auto& a = value.attention;
  const auto& previous = facts.attention;
  if (a.on && (!previous.on || a.id != previous.id || a.agent != previous.agent || a.project != previous.project))
    attentionKey_ = "attention:" + std::to_string(++activation_) + ":[" + a.id + "," + quoted(a.agent) + "," +
                    quoted(a.project) + "]";
  if (!a.on) attentionKey_.clear();
  facts = value;
  baseKey_ = "base:" + std::string(stateName(facts.look()));
  if (a.on) hasMoment = hasOverlay = false;
}
bool Router::oneShot(const Request& in, T time, T loopMs) {
  if (in.say) listening = false;
  if (in.stop) {
    bool accepted = listening;
    listening = false;
    return accepted;
  }
  if (timedOut) return false;
  if (in.anim == SceneState::kListening) {
    if (listening) return true;
    hasMoment = hasOverlay = false;
    listening = true;
    listeningKey_ = "listening:" + (in.hasId ? in.id : std::to_string(++sequence_));
    return true;
  }
  if (listening || facts.attention.on) return false;
  const std::string id = in.hasId ? in.id : "local-" + std::to_string(++sequence_);
  const std::string key = "moment:" + std::string(in.anim == SceneState::kNone ? "react" : stateName(in.anim)) + ":" + id;
  const uint64_t seen = identityKey(key);
  if (recent_.find([&](uint64_t k) { return k == seen; })) return false;
  recent_.add(seen);
  int loops = std::max(1, std::min(6, in.loops));
  if (in.anim == SceneState::kNone) {
    if (in.expression < 0) return false;
    hasOverlay = true;
    overlayHeld = false;
    overlayExpression = in.expression;
    overlayUntil = time + loopMs * loops;
    return true;
  }
  hasOverlay = false;
  hasMoment = true;
  moment.value = in;
  moment.value.id = id;
  moment.value.loops = loops;
  moment.requestId = key;
  moment.startedAt = time;
  moment.expiresAt = time + loopMs * loops;
  return true;
}
Route Router::resolve() const {
  Route r;
  r.baseState = facts.look();
  r.linkTimedOut = timedOut;
  r.state = timedOut             ? SceneState::kNoApp
            : listening          ? SceneState::kListening
            : facts.attention.on ? SceneState::kNeedsYou
            : hasMoment          ? moment.value.anim
                                 : r.baseState;
  r.group = family(r.state);
  r.quiet = r.state == SceneState::kAsleep || r.state == SceneState::kNoApp;
  r.requestId = timedOut             ? &timeoutKey_
                : listening          ? &listeningKey_
                : facts.attention.on ? &attentionKey_
                : hasMoment          ? &moment.requestId
                                     : &baseKey_;
  r.attention = facts.attention.on ? &facts.attention : nullptr;
  r.moment = hasMoment ? &moment : nullptr;
  r.expression = hasOverlay ? overlayExpression : hasMoment ? moment.value.expression : -1;
  if (hasMoment) {
    r.outcome = moment.value.outcome;
    r.ctx = moment.value.ctx;
    r.loops = moment.value.loops;
  }
  return r;
}
}  // namespace render::gel
