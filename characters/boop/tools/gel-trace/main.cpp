// Native-only JSON adapter. The shipped engine contains no JSON or float math.
#include <ArduinoJson.h>
#include <fstream>
#include <iostream>
#include <memory>
#include "render/gel/engine.h"
using namespace render;
using namespace render::gel;
static double number(F x) { return double(x.raw) / F::scale; }
static const char* controls[] = {"eyeX",       "eyeY",  "eyeOpen",    "mouthY",
                                 "mouthWidth", "curve", "cheekAlpha", "tearAmount"};
static const char* modeNames[] = {"lean", "squash", "ripple", "dent"};
static const char* actingNames[] = {"lean", "squash", "ripple", "lift", "roll", "forward"};
static const char* activityNames[] = {"lean", "squash", "forward"};
static const char* outcomes[] = {nullptr, "success", "failure"};
static const char* contexts[] = {nullptr, "new_task", "session", "continuation", "compacted"};
static void springs(JsonObject o, const Spring* springs, const char** names, int n) {
  for (int i = 0; i < n; ++i) {
    o[names[i]]["x"] = number(springs[i].x);
    o[names[i]]["v"] = number(springs[i].v);
  }
}
// The reference's id for a contact, which the device doesn't keep.
static std::string contactId(const ContactEvent& c) {
  return c.requestId + ":" + std::to_string(c.generation) + ":" + std::to_string(c.iteration) + ":" +
         std::to_string(c.index);
}
static void contact(JsonObject o, const ContactEvent& c) {
  o["id"] = contactId(c);
  o["kind"] = slime::kContactNames[c.kind];
  o["requestId"] = c.requestId;
  o["generation"] = c.generation;
  o["iteration"] = c.iteration;
  o["index"] = c.index;
  o["timeMs"] = number(c.timeMs);
  o["side"] = c.side;
  o["strength"] = number(c.strength);
}
static void inspect(JsonObject o, Engine& e) {
  auto& s = e.scenes;
  auto& b = e.bridge;
  auto& f = e.face;
  auto& a = e.acting;
  const auto& r = s.route;
  o["time"] = number(e.motion.time);
  o["gaze"] = number(e.motion.gaze);
  o["blink"] = number(e.motion.blink());
  o["contact"]["x"] = number(e.motion.contactX);
  o["contact"]["y"] = number(e.motion.contactY);
  springs(o["modes"].to<JsonObject>(), e.motion.modes, modeNames, 4);
  auto actor = o["actorChannels"].to<JsonObject>();
  springs(actor, a.channels, actingNames, 6);
  // A gag's own channels join once one has played (acting.mjs inspect).
  if (a.gagged) {
    actor["slide"]["x"] = number(a.slide.x);
    actor["slide"]["v"] = number(a.slide.v);
    actor["lids"]["x"] = number(a.lids.x);
    actor["lids"]["v"] = number(a.lids.v);
    o["slide"] = number(a.slide.x);
  }
  springs(o["activityChannels"].to<JsonObject>(), s.activity, activityNames, 3);
  springs(o["bridgeChannels"].to<JsonObject>(), b.channels, activityNames, 3);
  o["mood"] = slime::kProfile[slime::kProfile[e.emotion].canonical].id;
  o["expression"] = slime::kProfile[e.expression].id;
  o["reducedMotion"] = e.reduced;
  auto pose = o["pose"].to<JsonArray>();
  for (auto v : e.pose()) pose.add(number(v));
  auto life = o["life"].to<JsonArray>();
  for (auto v : e.life()) life.add(number(v));
  auto posture = o["posture"].to<JsonArray>();
  for (auto v : e.posture()) posture.add(number(v));
  o["performanceCount"] = a.count;
  o["nextPerformance"] = number(a.nextPerformance);
  o["actingSuppressed"] = a.suppressed;
  if (a.performance < 0)
    o["performance"] = nullptr;
  else {
    auto p = o["performance"].to<JsonObject>();
    auto& perf = Acting::gesture(a.expression, a.performance);
    p["type"] = perf.type;
    p["index"] = a.performance;
    p["expression"] = slime::kProfile[a.expression].id;
    p["age"] = number(e.motion.time - a.start);
    p["duration"] = number(perf.duration);
  }
  auto face = o["face"].to<JsonObject>();
  for (int i = 0; i < 8; ++i) {
    face[controls[i]] = number(f.controls[i]);
    face["transition"]["from"][controls[i]] = number(f.from[i]);
    face["transition"]["to"][controls[i]] = number(f.to[i]);
  }
  static const char* renders[] = {"eye", "mouthWidth", "mouthHeight", "mouth", "cheek", "tear"};
  for (int i = 0; i < 6; ++i) face["render"][renders[i]] = number(f.render[i]);
  face["artId"] = slime::kProfile[f.artId].id;
  face["sleeping"] = f.sleeping;
  face["bridgeBlink"] = number(f.bridgeBlink);
  face["blink"] = number(max(max(f.bridgeBlink, e.motion.blink()), a.closure()));
  face["transition"]["elapsedMs"] = number(f.elapsedMs);
  face["transition"]["durationMs"] = number(f.durationMs);
  face["transition"]["active"] = f.active;
  auto bridge = o["bridge"].to<JsonObject>();
  bridge["from"] = b.active ? slime::kProfile[b.from].id : nullptr;
  bridge["to"] = b.active ? slime::kProfile[b.to].id : nullptr;
  if (b.edge >= 0)
    bridge["edgeId"] = std::string(slime::kProfile[slime::kEdges[b.edge].from].id) + "->" +
                       slime::kProfile[slime::kEdges[b.edge].to].id;
  else
    bridge["edgeId"] = nullptr;
  const char *cats[] = {"ordinary", "dramatic", "direct"},
             *prims[] = {"soft-retarget", "gather-settle", "blink-retarget", "recoil-compress"};
  bridge["category"] = b.active ? cats[b.category] : nullptr;
  bridge["primitive"] = b.active ? prims[int(b.primitive)] : nullptr;
  if (b.active)
    bridge["variant"] = b.variant;
  else
    bridge["variant"] = nullptr;
  bridge["elapsedMs"] = number(b.elapsedMs);
  bridge["durationMs"] = number(b.durationMs);
  bridge["startedAtMs"] = number(b.startedAtMs);
  bridge["deferredMs"] = number(b.deferredMs);
  bridge["expired"] = b.expired;
  bridge["suppressed"] = b.suppressed;
  bridge["direction"] = b.direction;
  bridge["amplitude"] = number(b.amplitude);
  bridge["progress"] = number(b.progress());
  bridge["phase"] = b.phase();
  bridge["deferred"] = b.deferred();
  auto scene = o["scene"].to<JsonObject>();
  scene["state"] = stateName(r.state);
  scene["family"] = familyName(r.group);
  scene["implemented"] = true;
  scene["quiet"] = r.quiet;
  scene["phase"] = s.phase;
  scene["variant"] = s.variant;
  scene["iteration"] = s.iteration;
  scene["generation"] = s.generation;
  scene["ageMs"] = number(s.ageMs);
  scene["requestId"] = s.requestId;
  scene["outcome"] = outcomes[int(r.outcome)];
  scene["ctx"] = contexts[int(r.ctx)];
  scene["intent"] = s.recipe.intent;
  scene["loops"] = r.loops;
  scene["restored"] = s.quietRestored;
  scene["loopDurationMs"] = number(s.recipe.duration);
  scene["quietMix"] = number(s.quietMix.x);
  scene["profile"]["expression"] = slime::kProfile[s.profileExpression].id;
  if (s.variant < 3)
    scene["profile"]["performanceType"] = slime::kProfile[s.profileExpression].performances[s.variant].type;
  else
    scene["profile"]["performanceType"] = nullptr;  // a fourth take has no gesture of its own
  scene["profile"]["recoveryGesture"] = !r.quiet && !slime::kProfile[s.profileExpression].representative;
  auto props = o["props"].to<JsonObject>();
  auto desk = props["desk"].to<JsonObject>();
  desk["id"] = "desk-1";
  desk["visible"] = number(s.desk.x);
  desk["x"] = .5;
  desk["y"] = .64;
  desk["screen"] = stateName(isDesk(r.state) ? r.state : isDesk(r.baseState) ? r.baseState : SceneState::kWorking);
  desk["contact"] = number(s.envelope(e.timeMs(), kKey));
  desk["side"] = s.hasLast && s.last.kind == kKey ? s.last.side : 1;
  desk["focus"] = number(s.focus(e.reduced));
  desk["progress"] = number(clamp(s.ageMs / s.recipe.duration, 0, 1));
  desk["status"] = r.state == SceneState::kWaiting     ? "waiting"
                   : r.state == SceneState::kPlanning  ? "planning"
                   : r.state == SceneState::kSearching ? "searching"
                   : r.state == SceneState::kTesting   ? "testing"
                   : r.state == SceneState::kAnalyzing ? "inspecting"
                   : r.state == SceneState::kToolUse   ? "invoking"
                                                       : "neutral";
  // Each prop's visible is its drawn opacity; its content is what it last showed.
  const T now = e.timeMs();
  auto alert = props["alert"].to<JsonObject>();
  bool isAlert = r.state == SceneState::kNeedsYou;
  F alertVisible = s.visible(Scenes::kAlertProp, now);
  alert["visible"] = number(alertVisible);
  alert["reveal"] = number(alertVisible);
  if (s.alertProp.known)
    alert["requestId"] = s.alertProp.requestId;
  else
    alert["requestId"] = nullptr;
  alert["label"] = "NEEDS YOU";
  alert["agent"] = s.alertProp.agent;
  alert["project"] = s.alertProp.project;
  alert["name"] = s.alertProp.name;
  alert["more"] = s.alertProp.more;
  alert["knock"] = number(isAlert ? s.envelope(now, kKnock) : F(0));
  alert["confirmation"] = number(isAlert ? s.envelope(now, kAlert) : F(0));
  const auto& card = s.resultProp;
  F resultVisible = s.visible(Scenes::kResultProp, now);
  auto result = props["result"].to<JsonObject>();
  result["visible"] = number(resultVisible);
  result["reveal"] = number(card.reveal);
  if (card.known)
    result["state"] = stateName(card.state);
  else
    result["state"] = nullptr;
  result["label"] = card.label;
  result["outcome"] = outcomes[int(card.outcome)];
  result["trophy"] = resultVisible > F(0) && card.outcome == Outcome::kSuccess;
  if (card.gift) result["gift"] = true;
  props["start"]["visible"] = number(s.visible(Scenes::kStartProp, now));
  props["start"]["reveal"] = number(s.startProp.reveal);
  props["start"]["label"] = s.startProp.label;
  props["start"]["ctx"] = contexts[int(s.startProp.ctx)];
  const auto& helpers = s.helpersProp;
  props["helpers"]["visible"] = number(s.visible(Scenes::kHelpersProp, now));
  props["helpers"]["mode"] = helpers.returning ? "return" : "dispatch";
  props["helpers"]["count"] = helpers.count;
  props["helpers"]["progress"] = number(helpers.progress);
  props["helpers"]["report"] = helpers.report;
  props["helpers"]["direction"] = helpers.direction;
  props["listening"]["visible"] = number(s.visible(Scenes::kListeningProp, now));
  props["listening"]["pulse"] = number(s.listeningPulse);
  props["listening"]["lean"] = number(s.activity[0].x);
  props["touch"]["visible"] = number(s.visible(Scenes::kTouchProp, now));
  if (s.touchKnown)
    props["touch"]["kind"] = stateName(s.touchKind);
  else
    props["touch"]["kind"] = nullptr;
  props["touch"]["pulse"] = number(s.envelope(now, kBody));
  props["lane"]["top"] = .8;
  auto contacts = o["contacts"].to<JsonArray>();
  for (const auto& c : s.contacts) contact(contacts.add<JsonObject>(), c);
  for (const auto& c : a.contacts) contact(contacts.add<JsonObject>(), c);
  o["grab"]["active"] = e.grab;
  for (int i = 0; i < 2; ++i) o["grab"]["point"][i] = number(e.point[i]);
  for (int i = 0; i < 3; ++i) {
    o["grab"]["target"][i] = number(e.target[i]);
    o["grab"]["pull"][i] = number(e.pull[i].x);
  }
}
static F readF(JsonVariantConst v, F fallback = 0) { return v.isNull() ? fallback : F::decimal(v.as<double>()); }
static std::string scalar(JsonVariantConst v) {
  if (v.is<const char*>()) return v.as<std::string>();
  std::string out;
  serializeJson(v, out);
  return out;
}
static void event(Engine& e, JsonVariantConst v) {
  std::string type = v["type"].as<std::string>();
  if (type == "mood")
    e.setMood(expressionFromName(v["mood"]), v["bridgeVariant"] | -1);
  else if (type == "facts") {
    auto j = v["facts"];
    Facts f;
    f.base = stateFromName(j["base"]);
    f.act = stateFromName(j["act"] | "working");
    auto a = j["attn"];
    if (!a.isNull()) {
      f.attention.on = true;
      serializeJson(a["id"], f.attention.id = "");
      f.attention.agent = a["agent"] | "";
      f.attention.project = a["project"] | "";
      f.attention.name = a["name"] | "";
      f.attention.more = a["more"] | 0;
    }
    e.setFacts(f);
  } else if (type == "oneShot") {
    auto j = v["moment"];
    std::string name = j["name"] | "";
    Request r;
    r.hasId = !j["id"].isNull();
    r.id = scalar(j["id"]);
    r.stop = name == "stop_listening";
    r.say = !j["args"]["say"].isNull();
    r.anim = reactionFromName(name.c_str());
    auto args = j["args"];
    r.expression = expressionFromName(args["mood"]);
    r.loops = args["loops"] | 1;
    r.outcome = r.anim == SceneState::kTaskComplete ? outcomeFromName(args["outcome"]) : Outcome::kNone;
    r.ctx = r.anim == SceneState::kStarting ? ctxFromName(args["ctx"]) : StartCtx::kNone;
    r.hold = j["hold"] | false;
    int variant = args["variant"] | -1;
    r.variant = variant >= 0 && variant < slime::kMaxTakes ? variant : -1;
    e.oneShot(r);
  } else if (type == "linkTimedOut")
    e.linkTimedOut(v["value"]);
  else if (type == "clearTransient")
    e.clearTransient();
  else if (type == "holdExpression")
    e.holdExpression(expressionFromName(v["mood"]));
  else if (type == "poke")
    e.motion.impulse(false, e.reduced, readF(v["x"]), readF(v["y"], q(.2)));
  else if (type == "shake")
    e.motion.impulse(true, e.reduced);
  else if (type == "perform")
    e.acting.perform(e.motion.time, e.random, v["index"] | -1);
  else if (type == "dragStart")
    e.dragStart(readF(v["point"][0]), readF(v["point"][1], q(.2)));
  else if (type == "dragMove")
    e.dragMove(readF(v["delta"][0]), readF(v["delta"][1]), readF(v["delta"][2]));
  else if (type == "dragEnd")
    e.dragEnd();
}
int main(int argc, char** argv) {
  if (argc != 2) return 2;
  std::ifstream in(argv[1]);
  std::vector<JsonDocument> events;
  std::string line;
  uint32_t end = 0;
  while (std::getline(in, line)) {
    if (line.empty()) continue;
    JsonDocument j;
    if (deserializeJson(j, line)) return 3;
    end = j["at"];
    events.push_back(std::move(j));
  }
  if (events.empty()) return 4;
  auto e = std::make_unique<Engine>();
  size_t cursor = 0;
  for (uint32_t at = 0; at <= end; at += 16) {
    while (cursor < events.size() && events[cursor]["at"].as<uint32_t>() <= at) event(*e, events[cursor++]);
    e->step(at);
    JsonDocument out;
    out["at"] = at;
    inspect(out["channels"].to<JsonObject>(), *e);
    auto cues = out["cues"].to<JsonArray>();
    for (const auto& c : e->cues) {
      auto o = cues.add<JsonObject>();
      contact(o, c.contact);
      o["id"] = "sound:" + contactId(c.contact);
      o["contactId"] = contactId(c.contact);
      o["recipe"] = c.recipe;
      o["mood"] = slime::kProfile[c.mood].id;
      o["protected"] = c.protectedCue;
      o["variant"] = c.variant;
      o["seed"] = c.seed;
      o["pitch"] = number(c.pitch);
      o["gain"] = number(c.gain);
    }
    serializeJson(out, std::cout);
    std::cout << '\n';
  }
}
