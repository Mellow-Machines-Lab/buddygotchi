#pragma once
#include <array>
#include <string>
#include "render/types.h"
#include "render/gel/history.h"
#include "render/gel/time.h"
namespace render::gel {
enum class Family { kRest, kIdle, kListen, kStart, kDesk, kHelpers, kAlert, kResult, kTouch };
Family family(SceneState state);
bool isDesk(SceneState state);
struct Attention {
  bool on = false;
  std::string id = "0", agent, project, name;  // id is a JSON scalar, for stable identity
  int more = 0;
};
struct Facts {
  SceneState base = SceneState::kIdle, act = SceneState::kWorking;
  Attention attention;
  SceneState look() const { return base == SceneState::kWorking ? act : base; }
};
struct Request {
  std::string id;
  bool hasId = false, stop = false, say = false;
  SceneState anim = SceneState::kNone;  // the moment's animation (isReaction); kNone for a face alone
  int expression = -1, loops = 1, variant = -1;
  bool hold = false;  // the host times it: held until cleared
  Outcome outcome = Outcome::kNone;
  StartCtx ctx = StartCtx::kNone;
};
struct Moment {
  Request value;
  std::string requestId;
  T startedAt, expiresAt;
};
struct Route {
  SceneState state = SceneState::kIdle, baseState = SceneState::kIdle;
  Family group = Family::kIdle;
  bool quiet = false, linkTimedOut = false;
  const std::string* requestId = nullptr;
  const Attention* attention = nullptr;
  const Moment* moment = nullptr;
  int expression = -1, loops = 1;
  Outcome outcome = Outcome::kNone;
  StartCtx ctx = StartCtx::kNone;
};
class Router {
 public:
  Facts facts;
  bool timedOut = false, listening = false, hasMoment = false, hasOverlay = false;
  Moment moment;
  int overlayExpression = -1;
  T overlayUntil;
  bool overlayHeld = false;  // the host's borrowed expression: no expiry
  Router() = default;
  void setFacts(const Facts& value);
  bool oneShot(const Request& value, T time, T overlayLoopMs = 3200);
  void clearTransient() { listening = hasMoment = hasOverlay = false; }
  // The host's borrowed expression (-1 for none), held until it says
  // otherwise: on the moment playing, else over the look.
  void holdExpression(int expression) {
    if (hasMoment) moment.value.expression = expression;
    hasOverlay = expression >= 0 && !hasMoment;
    overlayHeld = true;
    overlayExpression = expression;
  }
  void advance(T time) {
    if (hasOverlay && !overlayHeld && time >= overlayUntil) hasOverlay = false;
    if (hasMoment && !moment.value.hold && time >= moment.expiresAt) hasMoment = false;
  }
  void duration(const std::string& id, T ms) {
    if (hasMoment && moment.requestId == id) moment.expiresAt = moment.startedAt + ms * moment.value.loops;
  }
  void finish(const std::string& id) {
    if (hasMoment && moment.requestId == id) hasMoment = false;
  }
  Route resolve() const;

 private:
  // The protocol already deduplicates calls. This bounded extra history protects
  // direct/local input without allowing long-running firmware memory growth.
  static constexpr int kRecent = 64;
  History<uint64_t, kRecent> recent_;
  unsigned activation_ = 0, sequence_ = 0;
  std::string attentionKey_, listeningKey_, baseKey_ = "base:idle", timeoutKey_ = "link-timeout";
};
}  // namespace render::gel
