#include "app/device.h"
#include "render/tags.h"

#include <ArduinoJson.h>

#include <cstdio>
#include <cstring>

#include "linkkit/codec.h"
#include "render/font.h"
#include "render/maths.h"
#include "render/palette.h"
#include "render/pattern.h"
#include "render/screens.h"

namespace app {

using render::after;

namespace {

using linkkit::Do;
using linkkit::How;
using linkkit::Link;

constexpr uint32_t kDefaultPressMs = 100;
// Motion redraws at most this often, in real ms: about 60 fps. Parts of
// the face that cross block lines a few ms apart show together.
constexpr uint32_t kFrameMs = 16;
// BOOT's cap on talking is where listening stops listening.
static_assert(ButtonGesture::kTalkCapMs == Behaviour::kListenMs, "the talk cap is listening's");
// dbg.shot sends the palette as it's laid out in memory: 256 RGB565
// entries, low byte first.
static_assert(sizeof(render::kPalette.c) == 512, "the palette is 256 entries");
static_assert(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__, "the palette goes out as it's stored");

// A repeated state keeps the link alive but doesn't invalidate the picture.
// Compare fields, not bytes: Model has padding and its strings are terminated.
bool sameModel(const Model& a, const Model& b) {
  return a.base == b.base && a.act == b.act && a.mood == b.mood && a.attn == b.attn && a.attnId == b.attnId &&
         a.more == b.more && a.busy == b.busy && a.idle == b.idle && a.helpers == b.helpers && a.vol == b.vol &&
         a.when == b.when && a.todoDone == b.todoDone && a.todoTotal == b.todoTotal && !std::strcmp(a.agent, b.agent) &&
         !std::strcmp(a.project, b.project) && !std::strcmp(a.name, b.name);
}

// Boop's do names, in hello.does's order, and the
// animation each plays: none for `react` (a `say`, a face) and for
// stop_listening. A tap's poked and tap_spam aren't among them: the device
// plays those itself.
enum DoIndex : uint8_t {
  kReact,
  kTaskComplete,
  kReplyReady,
  kStarting,
  kStopped,
  kError,
  kHelperReturn,
  kWakeUp,
  kListening,
  kStopListening,
  kNotice,
  kCall,
  kDoCount
};
constexpr const char* kDoNames[kDoCount] = {"react",         "task_complete", "reply_ready", "starting",
                                            "stopped",       "error",         "helper_return", "wake_up",
                                            "listening",     "stop_listening", "notice",      "call"};
constexpr render::SceneState kDoAnims[kDoCount] = {render::SceneState::kNone,         render::SceneState::kTaskComplete,
                                                   render::SceneState::kReplyReady,   render::SceneState::kStarting,
                                                   render::SceneState::kStopped,      render::SceneState::kError,
                                                   render::SceneState::kHelperReturn, render::SceneState::kWakeUp,
                                                   render::SceneState::kListening,    render::SceneState::kNone,
                                                   render::SceneState::kNotice,       render::SceneState::kNone};

// A number the device holds to lo–hi: any JSON number,
// one past either end (even too big for an int) as that end, and a
// fraction as its whole part. Missing or not a number reads as `missing`.
int heldTo(JsonVariantConst v, int lo, int hi, int missing) {
  if (!v.is<double>() || v.is<bool>()) return missing;
  double n = v.as<double>();
  return n >= hi ? hi : n > lo ? int(n) : lo;
}

// Copying a voice file onto the card over USB:
// `begin` (afresh, or `keep` to go on), then `put`s of base64 chunks at
// the end of what the card holds, each with its CRC-32, then `end` with the
// whole file's size and CRC-32. Every reply says what the card holds, so
// a chunk lost on the way is simply sent again. Writes the reply into
// `buf` and returns its length, 0 if it didn't fit. Not inlined, so its
// chunk isn't on every line's stack.
constexpr size_t kCardChunk = 360;  // bytes a `put` may carry
__attribute__((noinline)) size_t cardCopy(Hal& hal, JsonObjectConst doc, char* buf, size_t cap, bool& swapped) {
  const char* op = doc["op"] | "";
  uint32_t have = 0;
  const char* why = "";
  bool ok = false;
  swapped = false;
  int n;
  if (!std::strcmp(op, "begin")) {
    ok = hal.copyBegin(doc["keep"] | false, have, why);
  } else if (!std::strcmp(op, "put")) {
    uint8_t chunk[kCardChunk];  // on the stack: static, it'd hold 360 B of heap for good
    const char* d = doc["d"] | "";
    long got = linkkit::base64Decode(d, std::strlen(d), chunk, sizeof(chunk));
    hal.copyAppend(chunk, 0, have);  // how much the card holds
    if (got < 0) why = "not base64";
    else if (linkkit::crc32(chunk, size_t(got)) != (doc["c"] | 0u)) why = "wrong crc";
    else if ((doc["at"] | 0u) != have) why = "not where the card is";
    else if (!(ok = hal.copyAppend(chunk, size_t(got), have))) why = "can't write";
  } else if (!std::strcmp(op, "end")) {
    ok = swapped = hal.copyEnd(doc["size"] | 0u, doc["crc"] | 0u, why);
    n = std::snprintf(buf, cap, "{\"t\":\"dbg.card\",\"op\":\"end\",\"ok\":%s,\"voice\":\"%s\",\"why\":\"%s\"}",
                      ok ? "true" : "false", voice::assetsVersion(), ok ? "" : why);
    return n > 0 && size_t(n) < cap ? size_t(n) : 0;
  } else {
    why = "op is begin, put or end";
  }
  const char* name = ok || std::strcmp(why, "op is begin, put or end") ? op : "?";  // never echo junk
  n = std::snprintf(buf, cap, "{\"t\":\"dbg.card\",\"op\":\"%s\",\"ok\":%s,\"have\":%lu,\"why\":\"%s\"}", name,
                    ok ? "true" : "false", (unsigned long)have, ok ? "" : why);
  return n > 0 && size_t(n) < cap ? size_t(n) : 0;
}

}  // namespace

Device::Device(Hal& hal, uint8_t* pixels) : hal_(hal), canvas_(pixels) {
  const render::Size size = hal_.nativeSize();
  if (b_.face().drawsNative() && !size.empty()) {
    const size_t bytes = size_t(size.width) * size_t(size.height) * sizeof(uint16_t);
    auto* a = static_cast<uint16_t*>(hal_.allocateSurface(bytes));
    auto* b = static_cast<uint16_t*>(hal_.allocateSurface(bytes));
    native_ = std::make_unique<render::SurfacePair>(size.width, size.height, a, b);
  }
}
Device::~Device() {
  if (!native_) return;
  if (native_->back().pixels) hal_.releaseSurface(native_->back().pixels);
  if (native_->front().pixels) hal_.releaseSurface(native_->front().pixels);
}

int Device::does(const char* const*& names) const {
  names = kDoNames;
  return kDoCount;
}

// The voice file on the card, which the Mac checks before it sends takes.
void Device::hello(JsonObject extra) {
  extra["voice"] = voice::assetsVersion();
  extra["face"] = b_.face().name();
  extra["pack"] = render::kPackId;  // the character pack it was built with
  extra["pack_version"] = render::kPackVersion;
  extra["reset"] = hal_.resetReason();  // why it last restarted: the Mac logs a crash or a watchdog
  if (*hal_.boardName()) extra["board"] = hal_.boardName();  // which firmware the Mac updates it with
}

void Device::begin() {
  b_.reset(0, kit().rng());
  // A board seeds the kit's randomness from its boot id (linkkit/SPEC.md
  // §7); the simulator starts frozen and keeps the face's own seed.
  if (!kit().frozen()) b_.face().seed(kit().rng().next());
  b_.startWithNoApp();
  fpsSinceReal_ = hal_.realMs();
}

// Forgets everything the Mac said. The kit has frozen the clock at 0 and
// reseeded, so a scenario starts from the same place on the board and in
// the simulator.
void Device::reset() {
  b_.reset(0, kit().rng());
  drain();
  hush();
  hal_.stopEffects();
  live_ = {};
  dirty_ = true;
}

void Device::drain() {
  PlayedOut p;
  if (b_.takePlayedOut(p)) kit().ended(p.key, p.by == CutBy::kNone ? How::kDone : How::kCut, cutByName(p.by));
}

void Device::input(const char* k, uint32_t t, int x, int y) {
  live_.last = {k, t, x, y};
  dirty_ = true;
}

// ---- The Mac's messages ----------------------------------------------------

void Device::onState(JsonObjectConst doc, uint32_t at) {
  Model m;
  m.base = baseFromName(doc["base"]);          // idle if missing or unknown
  m.act = actFromName(doc["act"]);             // working's design if missing or unknown
  m.mood = render::moodFromName(doc["mood"]);  // the startup mood if missing or unknown
  JsonObjectConst attn = doc["attn"];
  if (attn) {
    m.attn = true;
    copyStr(m.agent, sizeof(m.agent), attn["agent"] | "");
    copyStr(m.project, sizeof(m.project), attn["project"] | "");
    copyStr(m.name, sizeof(m.name), attn["name"] | "");
    m.more = attn["more"] | 0;
    m.attnId = attn["id"] | 0u;
  }
  m.busy = doc["busy"] | 0;
  m.idle = doc["idle"] | 0;
  m.helpers = doc["helpers"] | 0;
  JsonObjectConst todo = doc["todo"];
  m.todoDone = todo["done"] | 0;
  m.todoTotal = todo["total"] | 0;
  m.vol = heldTo(doc["vol"], 0, 10, 6);
  // A tag the board doesn't know is left out.
  for (JsonVariantConst tag : doc["when"].as<JsonArrayConst>()) m.when |= render::tagBit(tag.as<const char*>());
  m.when |= render::busyTags(m.busy);
  // The work stream's lanes, `[slot, calls, word, project]`, their words
  // as the fonts draw them.
  for (JsonArrayConst lane : doc["calls"].as<JsonArrayConst>()) {
    if (m.laneCount >= render::Stream::kLanes) break;
    auto& l = m.lanes[m.laneCount++];
    l.slot = uint8_t(heldTo(lane[0], 0, render::Stream::kLanes - 1, 0));
    l.count = uint16_t(heldTo(lane[1], 0, 999, 0));
    render::foldText(lane[2].as<const char*>(), render::Stream::kWordBytes - 1, l.word, sizeof(l.word));
    render::foldText(lane[3].as<const char*>(), render::Stream::kLabelBytes - 1, l.label, sizeof(l.label));
  }
  if (!sameModel(m, b_.model()) || live_.pattern || b_.noApp(at))
    dirty_ = true, latency_.mark(Latency::kState, hal_.realMs());
  b_.onState(m, at);
  if (m.attn || m.vol == 0) hush();
  if (m.vol == 0) hal_.stopEffects();
  live_.pattern = false;
  drain();  // "needs you" cuts what plays
}

// A do's args, as a reaction's fields. The variation
// is picked here, as the reaction is about to play: the Mac's (from 1) when
// it's one of its design's, in the mood it's drawn in, for the finish's
// outcome or the start's context; else the device picks one of those,
// never the one it showed last.
ReactionIn Device::parse(const Do& c) {
  ReactionIn mo;
  mo.key = c.key;
  mo.id = c.id > 0 ? uint32_t(c.id) : 0;
  if (c.what == kStopListening) {
    mo.empty = true;
    return mo;
  }
  JsonObjectConst args = c.args;
  mo.anim = c.what < kDoCount ? kDoAnims[c.what] : render::SceneState::kNone;
  mo.expr = render::parseMood(args["mood"], mo.mood);  // unknown or missing: the state's mood
  mo.loops = heldTo(args["loops"], 1, Behaviour::kMaxLoops, 1);
  if (mo.anim != render::SceneState::kNone) {
    render::Outcome outcome = render::Outcome::kNone;
    render::StartCtx ctx = render::StartCtx::kNone;
    if (mo.anim == render::SceneState::kTaskComplete) outcome = render::outcomeFromName(args["outcome"]);
    if (mo.anim == render::SceneState::kStarting) ctx = render::ctxFromName(args["ctx"]);
    mo.outcome = outcome;
    mo.ctx = ctx;
    mo.variant = b_.pick(mo.anim, mo.expr ? mo.mood : b_.model().mood, heldTo(args["variant"], 0, 255, 0), outcome,
                         ctx, kit().rng());
  }
  mo.said = !args["say"].isNull();
  JsonObjectConst who = args["who"];  // copied by play, while the args live
  if (who) mo.whoAgent = who["agent"] | "", mo.whoThread = who["thread"] | "";
  // The `say`: a take by its id, and maybe a second, `then`, from the
  // card's voice file. `{}`, or an id the file doesn't have (or no card),
  // is still a `say` (the reply listening waits for) but plays nothing.
  mo.take = voice::takeIndex(args["say"]["take"].as<const char*>());
  mo.then = mo.take >= 0 ? voice::takeIndex(args["say"]["then"].as<const char*>()) : -1;
  // The words to hold up, as the fonts draw them, cut to kSignGlyphs.
  render::foldText(args["sign"].as<const char*>(), kSignGlyphs, mo.sign, sizeof(mo.sign));
  return mo;
}

// While something needs you, with no app, or while
// listening holds the face, a reaction none of which would play is skipped;
// so is stop_listening with nothing to stop. A reply ends listening either
// way.
const char* Device::refuse(const Do& c, uint32_t t) {
  // A word of the work stream shows only over the agents' work.
  if (c.what == kCall) return b_.callShows(t) ? nullptr : "hidden";
  live_.parsed = parse(c);
  const char* why = b_.admit(live_.parsed, t);
  drain();  // a listening reaction the reply ended
  if (why) live_.parsed = ReactionIn{};
  return why;
}

// The reaction starts playing: layered over what plays, and it says when
// it may be replaced: a
// `react` half a second after its `say` and bubble have played, or 1.7 s
// in for a face with no `say` (it ends sooner if nothing of it plays by
// then), and not before its sign comes down; a finish and the compacted
// start never, until they're over; the rules' other reactions, a poke and
// listening at once; stop_listening is over as it starts. The Mac's
// `listening` drops the reactions its own host has waiting in the queue.
void Device::onDo(const Do& c, uint32_t t) {
  latency_.mark(Latency::kDo, hal_.realMs());  // from when it plays, past its wait in the queue
  if (c.what == kCall) {
    // A word that comes forward: the face flies it and the body answers
    // as it lands. It holds nothing up.
    JsonObjectConst args = c.args;
    char word[render::Stream::kWordBytes];
    render::foldText(args["w"].as<const char*>(), render::Stream::kWordBytes - 1, word, sizeof(word));
    b_.call(word, uint8_t(heldTo(args["a"], 0, render::Stream::kLanes - 1, 0)),
            render::callGagFromName(args["as"].as<const char*>()), uint16_t(heldTo(args["n"], 0, 999, 0)), t);
    dirty_ = true;
    kit().rest(c.key);
    return;
  }
  const ReactionIn mo = live_.parsed.key == c.key ? live_.parsed : parse(c);
  live_.parsed = ReactionIn{};
  uint32_t seq = b_.reactionSeq();
  // A `say`'s sound goes with its bubble: now, or at its animation's voice
  // window. Any other reaction drops one still waiting.
  const bool say = b_.play(mo, t);
  if (!say) live_.saidSeq = b_.reactionSeq();
  if (!startSay(t) && b_.reactionSeq() != seq) hush();  // a new reaction replaces the `say`
  dirty_ = true;
  live_.restKey = 0;
  switch (c.what) {
    case kReact:
      live_.restKey = c.key;
      live_.restAt = (say ? b_.sayEnd() : t + Behaviour::kBubbleReadMs) + kReactGapMs;
      if (mo.sign[0] && b_.signUp(t) && after(b_.signEnd(), live_.restAt)) live_.restAt = b_.signEnd();
      break;
    case kTaskComplete:
    case kReplyReady:
    case kWakeUp:  // the brain's, like a finish: it plays through
    case kNotice:
      break;
    case kListening:
      kit().dropWaiting("mic_on", c.from);  // the mic went on: the reactions waiting would end it
      kit().rest(c.key);
      break;
    case kStopListening:
      kit().ended(c.key);
      break;
    case kStarting:
      // The compacted card is news to read: it holds, as a finish does,
      // until it has played. Any other start is over as it starts.
      if (mo.ctx != render::StartCtx::kCompacted) kit().rest(c.key);
      break;
    default:
      kit().rest(c.key);
      break;
  }
  drain();
}

void Device::advance(uint32_t t) {
  b_.advance(t, kit().rng());
  drain();
  if (live_.restKey && !after(live_.restAt, t)) kit().rest(live_.restKey), live_.restKey = 0;
}

bool Device::nextDue(uint32_t from, uint32_t to, uint32_t& at) {
  bool found = b_.nextEnd(from, to, at);
  if (live_.restKey && after(live_.restAt, from) && !after(live_.restAt, to) && (!found || after(at, live_.restAt))) {
    at = live_.restAt, found = true;
  }
  return found;
}

// ---- Debug messages --------------------------------------------------------

bool Device::debug(const char* type, JsonObjectConst doc, Link from) {
  char buf[160];
  if (!std::strcmp(type, "dbg.pattern")) {
    // With "fill", a solid screen of that palette index (webcam framing).
    // With "target": [x, y], a cross to tap on black (boopctl calibrate).
    live_.patternFill = doc["fill"] | -1;
    JsonArrayConst target = doc["target"];
    live_.targetX = target.size() == 2 ? render::clamp(target[0].as<int>(), 0, render::kWidth - 1) : -1;
    live_.targetY = target.size() == 2 ? render::clamp(target[1].as<int>(), 0, render::kHeight - 1) : -1;
    live_.pattern = true;
    dirty_ = true;
    kit().reply(from, "{\"t\":\"dbg.pattern\"}", 19);
  } else if (!std::strcmp(type, "dbg.look")) {
    // A look's variation, from 1, shown until it turns: for scenarios and
    // tools, since the face picks its own.
    b_.face().showLookVariant(uint8_t((doc["variant"] | 1) - 1));
    dirty_ = true;
    kit().reply(from, "{\"t\":\"dbg.look\"}", 16);
  } else if (!std::strcmp(type, "dbg.press")) {
    live_.injPress = true;
    live_.injPressUntil = kit().now() + (doc["ms"] | kDefaultPressMs);
    kit().reply(from, "{\"t\":\"dbg.press\"}", 17);
  } else if (!std::strcmp(type, "dbg.imu")) {
    // The motion sensor's reading, held until the next ("off" lets go).
    live_.injMotion = !(doc["off"] | false);
    live_.injAx = doc["ax"] | 0, live_.injAy = doc["ay"] | 0, live_.injAz = doc["az"] | 1000;
    kit().reply(from, "{\"t\":\"dbg.imu\"}", 15);
  } else if (!std::strcmp(type, "dbg.touch")) {
    live_.injTouch = true;
    live_.injX = doc["x"] | 0;
    live_.injY = doc["y"] | 0;
    live_.injToX = doc["to_x"] | live_.injX;  // a stroke: from x, y to these, over its ms
    live_.injToY = doc["to_y"] | live_.injY;
    live_.injTouchFrom = kit().now();
    live_.injTouchUntil = kit().now() + (doc["ms"] | kDefaultPressMs);
    kit().reply(from, "{\"t\":\"dbg.touch\"}", 17);
  } else if (!std::strcmp(type, "dbg.touchcal")) {
    // "set": [ax, bx, cx, ay, by, cy] in 1/65536 (TouchCal), or "clear".
    JsonArrayConst set = doc["set"];
    if (set.size() == 6) {
      TouchCal c;
      c.ax = set[0].as<int32_t>(), c.bx = set[1].as<int32_t>(), c.cx = set[2].as<int32_t>();
      c.ay = set[3].as<int32_t>(), c.by = set[4].as<int32_t>(), c.cy = set[5].as<int32_t>();
      c.valid = true;
      hal_.setTouchCal(c);
    } else if (doc["clear"] | false) {
      hal_.setTouchCal(TouchCal{});
    }
    TouchCal c = hal_.touchCal();
    int n = c.valid ? std::snprintf(buf, sizeof(buf), "{\"t\":\"dbg.touchcal\",\"cal\":[%ld,%ld,%ld,%ld,%ld,%ld]}",
                                    long(c.ax), long(c.bx), long(c.cx), long(c.ay), long(c.by), long(c.cy))
                    : std::snprintf(buf, sizeof(buf), "{\"t\":\"dbg.touchcal\",\"cal\":null}");
    if (n > 0 && size_t(n) < sizeof(buf)) kit().reply(from, buf, size_t(n));
  } else if (!std::strcmp(type, "dbg.card")) {
    // Nothing reads the old voice file while `end` swaps it, and a waiting `say` is dropped.
    if (!std::strcmp(doc["op"] | "", "end")) hush(), live_.saidSeq = b_.reactionSeq();
    bool swapped;
    size_t n = cardCopy(hal_, doc, buf, sizeof(buf), swapped);
    if (n) kit().reply(from, buf, n);
    if (swapped) kit().helloChanged();  // hello's `voice` names the new voice file
  } else if (!std::strcmp(type, "dbg.light")) {
    if (doc["bl"].is<int>()) b_.overrideBacklight(uint8_t(doc["bl"].as<int>()));
    kit().reply(from, "{\"t\":\"dbg.light\"}", 17);
  } else if (!std::strcmp(type, "dbg.latency")) {
    // Each kind's samples since the last clear, the p95 and max of the
    // latest Latency::kWindow, and the latest sample's two real times; with
    // "clear", forgotten once said.
    char out[512];
    int n = std::snprintf(out, sizeof(out), "{\"t\":\"dbg.latency\",\"now\":%lu", (unsigned long)hal_.realMs());
    for (int k = 0; k < Latency::kKinds && n > 0 && size_t(n) < sizeof(out); ++k) {
      const Latency::Stats s = latency_.stats(Latency::Kind(k));
      n += std::snprintf(out + n, sizeof(out) - size_t(n),
                         ",\"%s\":{\"n\":%lu,\"p95\":%lu,\"max\":%lu,\"at\":%lu,\"shown\":%lu}",
                         Latency::name(Latency::Kind(k)), (unsigned long)s.n, (unsigned long)s.p95,
                         (unsigned long)s.max, (unsigned long)s.at, (unsigned long)s.shown);
    }
    if (n > 0 && size_t(n) + 1 < sizeof(out)) {
      out[n++] = '}';
      kit().reply(from, out, size_t(n));
    }
    if (doc["clear"] | false) latency_.clear();
  } else {
    return false;
  }
  return true;
}

void Device::ping(JsonObject d) {
  d["sha"] = hal_.gitSha();
  d["reset"] = hal_.resetReason();
  d["heap"] = hal_.heapFree();
  d["heap_min"] = hal_.heapMin();
  d["fps"] = fps_;
  d["draw_us"] = drawUs_;
  d["push_us"] = pushUs_;
  d["voice"] = voice::assetsVersion();
  d["card"] = hal_.cardState();
  d["fx"] = b_.face().clips().version();
  d["w"] = render::kWidth;  // the screen as drawn, for boopctl calibrate
  d["h"] = render::kHeight;
}

const char* Device::screenName(uint32_t t) const {
  if (live_.pattern) return "pattern";
  switch (b_.look(t)) {
    case render::SceneState::kNoApp: return "no_app";
    case render::SceneState::kNeedsYou: return "needs_you";
    default: return "face";
  }
}

void Device::state(JsonObject d, uint32_t t) {
  const Model& m = b_.model();
  d["screen"] = screenName(t);
  d["base"] = render::stateName(m.base);
  if (m.act != render::SceneState::kWorking) d["act"] = render::stateName(m.act);
  else d["act"] = nullptr;
  d["mood"] = render::moodName(m.mood);
  d["look_variant"] = b_.lookVariant() + 1;
  // The motion sensor's reading now, in milli-g, for tuning its gestures;
  // null on a board with none.
  int ax = live_.injAx, ay = live_.injAy, az = live_.injAz;
  if (live_.injMotion || hal_.motion(ax, ay, az)) {
    JsonArray imu = d["imu"].to<JsonArray>();
    imu.add(ax), imu.add(ay), imu.add(az);
  } else {
    d["imu"] = nullptr;
  }
  d["face_down"] = b_.faceDown();
  d["idle"] = m.idle;
  d["helpers"] = m.helpers;
  JsonArray when = d["when"].to<JsonArray>();
  for (int i = 0; i < render::kTagCount; ++i)
    if (m.when >> i & 1) when.add(render::kTagNames[i]);
  if (m.todoTotal > 0) {
    d["todo"]["done"] = m.todoDone;
    d["todo"]["total"] = m.todoTotal;
  } else {
    d["todo"] = nullptr;
  }
  if (m.attn) {
    d["attn"]["agent"] = m.agent;
    d["attn"]["project"] = m.project;
    d["attn"]["name"] = m.name;
    d["attn"]["more"] = m.more;
    d["attn"]["id"] = m.attnId;
  } else {
    d["attn"] = nullptr;
  }
  uint32_t left;
  render::SceneState anim = b_.reaction(t, left);
  if (anim != render::SceneState::kNone) {
    d["moment"]["anim"] = render::stateName(anim);
    d["moment"]["left_ms"] = left;
    d["moment"]["variant"] = b_.reactionVariant() + 1;
  } else {
    d["moment"] = nullptr;
  }
  render::Mood expr;
  if (b_.expression(t, expr)) d["expr"] = render::moodName(expr);
  else d["expr"] = nullptr;
  if (b_.signUp(t)) d["sign"] = b_.sign(t).text;
  else d["sign"] = nullptr;
  // The work stream: how many lanes show, and the word forward's gag.
  const render::Stream& stream = b_.stream();
  d["calls"] = stream.on ? stream.laneCount : 0;
  if (stream.drawn(t) && stream.call.live) d["call"] = render::callGagName(stream.call.gag);
  else d["call"] = nullptr;
  if (b_.blinking(t)) d["life"] = "blink";
  else d["life"] = nullptr;
  d["vol"] = m.vol;
  char led[8];
  std::snprintf(led, sizeof(led), "#%06lX", (unsigned long)(b_.led(t) & 0xFFFFFF));
  d["led"] = led;
  d["audio"]["playing"] = b_.speaking(t);
  const char* take = b_.bubble(t) ? voice::takeId(b_.take()) : nullptr;
  if (take) d["audio"]["take"] = take;
  else d["audio"]["take"] = nullptr;
  AudioOut ao = hal_.audioOut();
  JsonObject out = d["audio"]["out"].to<JsonObject>();
  out["ready"] = ao.ready;
  out["playing"] = ao.playing;
  out["lines"] = ao.lines;
  if (voice::takeId(ao.take)) out["take"] = voice::takeId(ao.take);
  else out["take"] = nullptr;
  out["plan_ms"] = ao.planMs;
  out["out_ms"] = ao.outMs;
  out["wall_ms"] = ao.wallMs;
  out["cut"] = ao.cut;
  out["errors"] = ao.errors;
  JsonObject fx = d["audio"]["fx"].to<JsonObject>();
  fx["sent"] = fxSent_;
  if (fxLast_ >= 0) fx["last"] = b_.face().clips().at(fxLast_).name;
  else fx["last"] = nullptr;
  uint32_t alertAt;
  if (b_.alerted(alertAt)) d["alert"] = alertAt;
  else d["alert"] = nullptr;
  if (live_.last.k) {
    JsonObject li = d["last_input"].to<JsonObject>();
    li["k"] = live_.last.k;
    li["at"] = live_.last.at;
    if (live_.last.x >= 0) {
      li["x"] = live_.last.x;
      li["y"] = live_.last.y;
    }
  } else {
    d["last_input"] = nullptr;
  }
  // Bring-up extras (F1): raw hardware readings.
  d["boot"] = live_.boot.down();
  int rx, ry, rz;
  bool irq;
  hal_.touchRaw(rx, ry, rz, irq);
  JsonObject touch = d["touch"].to<JsonObject>();
  touch["down"] = live_.touchDown;
  touch["irq"] = irq;
  JsonArray raw = touch["raw"].to<JsonArray>();
  raw.add(rx), raw.add(ry), raw.add(rz);
  if (live_.lastTouchWas) {
    const TouchGesture::Path& p = live_.lastTouch;
    JsonObject last = touch["last"].to<JsonObject>();
    JsonArray from = last["from"].to<JsonArray>(), to = last["to"].to<JsonArray>();
    from.add(p.x0), from.add(p.y0), to.add(p.x), to.add(p.y);
    last["ms"] = p.ms;
    last["was"] = live_.lastTouchWas;
  } else {
    touch["last"] = nullptr;
  }
  d["amp"] = hal_.ampOn();
  d["bl"] = b_.backlight(t);
}

// 256 little-endian RGB565 palette entries, then one palette index per
// pixel, row by row, drawn afresh; a native face's frame as its RGB565
// pixels. Either is the frame the board sends next.
bool Device::shot(linkkit::Shot& s, uint32_t t) {
  noApp_ = !live_.pattern && b_.noApp(t);
  dirty_ = true;
  render(t);
  if (auto* native = surface()) {
    s.w = uint16_t(native->width);
    s.h = uint16_t(native->height);
    s.data[0] = reinterpret_cast<const uint8_t*>(native->pixels);
    s.size[0] = native->bytes();
    return true;
  }
  s.w = render::kWidth;
  s.h = render::kHeight;
  s.data[0] = reinterpret_cast<const uint8_t*>(render::kPalette.c);
  s.size[0] = sizeof(render::kPalette.c);
  s.data[1] = canvas_.pixels();
  s.size[1] = size_t(render::kWidth) * render::kHeight;
  return true;
}

// ---- Inputs ----------------------------------------------------------------

// A tap goes to the Mac as what the device did about it: the poke, or the
// press dip while the face is held or a finish names whose turn it was,
// with that finish's id, the thread the Mac opens.
void Device::tapped(uint32_t t, bool injected, bool button) {
  uint32_t finish = b_.finishShown(t);
  const char* did = button ? b_.press(t, kit().rng()) : b_.tap(t, kit().rng());
  input("tap", t);
  // Where it came from (`src`), and the finish it landed on, if any.
  char on[24] = "", data[48];
  if (finish) std::snprintf(on, sizeof(on), ",\"on\":%lu", (unsigned long)finish);
  std::snprintf(data, sizeof(data), "{\"src\":\"%s\"%s}", button ? "button" : "screen", on);
  kit().emit("tap", did, data, injected);
  drain();  // the poke cuts an animation
}

// BOOT and touch, turned into gestures. Every press and
// touch shows on screen at once, before the Mac hears about it.
void Device::readInputs(uint32_t t) {
  const uint32_t real = hal_.realMs();
  // When an injected press or touch let go, in real time: the clock runs
  // with real time, so as far back as the device clock is past its end.
  // A tool's input then times its release exactly (dbg.latency).
  auto letGo = [&](uint32_t until) { return kit().frozen() ? real : real - (t - until); };
  uint32_t pressGone = real, touchGone = real;
  if (live_.injPress && !after(live_.injPressUntil, t)) live_.injPress = false, pressGone = letGo(live_.injPressUntil);
  switch (live_.boot.update(hal_.bootDown() || live_.injPress, t)) {
    case ButtonGesture::kDown:
      live_.bootInjected = !hal_.bootDown();
      b_.pressDown(t);
      dirty_ = true;
      latency_.mark(Latency::kPress, real);
      break;
    case ButtonGesture::kTap:
      b_.pressUp();
      latency_.mark(Latency::kTap, live_.bootInjected ? pressGone : real);
      tapped(t, live_.bootInjected, true);
      break;
    case ButtonGesture::kHoldStart:  // push-to-talk: listening at once, before the Mac hears
      b_.pressUp();
      // The reactions waiting would end it: dropped for every Mac that
      // hears talk_on, which for a tool's dbg.press is only USB's.
      kit().dropWaiting("mic_on", live_.bootInjected ? Link::kUsb : Link::kNone);
      b_.talkOn(t, kit().rng());
      input("talk_on", t);
      kit().emit("talk_on", "listening", nullptr, live_.bootInjected);
      drain();  // listening cuts what played
      break;
    case ButtonGesture::kHoldEnd:  // let go, or the 30 s cap
      b_.talkOff(t);
      input("talk_off", t);
      kit().emit("talk_off", nullptr, nullptr, live_.bootInjected);
      break;
    default:
      break;
  }

  // A touch anywhere is a tap, sent on release however long it was held,
  // but for a finger held still on the needs-you screen (TouchGesture::held):
  // that's the gesture `dismiss`, sent as the hold completes with the
  // number of the request the screen showed as the finger went down, so the
  // Mac dismisses that one or none, never one that took the screen during
  // the hold. Its release does nothing, as a touch's on a screen that has
  // gone does. The press shows at once. The panel misses readings under a
  // light press, so its touch ends only after kTouchReleaseMs without
  // contact, in real time so that it ends while a tool has the clock
  // frozen; an injected one ends when it says. The debug pattern ignores
  // touches.
  if (live_.injTouch && !after(live_.injTouchUntil, t)) live_.injTouch = false, touchGone = letGo(live_.injTouchUntil);
  int x = 0, y = 0;
  bool contact = live_.injTouch ? (x = live_.injX, y = live_.injY, true) : hal_.touch(x, y);
  if (live_.injTouch && live_.injTouchUntil != live_.injTouchFrom) {  // a stroke's way along
    const int64_t along = int64_t(t - live_.injTouchFrom), ms = int64_t(live_.injTouchUntil - live_.injTouchFrom);
    x = live_.injX + int((live_.injToX - live_.injX) * along / ms),
    y = live_.injY + int((live_.injToY - live_.injY) * along / ms);
  }
  if (contact) live_.touchSeenReal = real, live_.touchInjected = live_.injTouch;
  bool touching = contact || (live_.touchDown && !live_.touchInjected && real - live_.touchSeenReal < kTouchReleaseMs);
  bool faced = !live_.pattern;
  if (touching && !live_.touchDown) {
    input("touch", t, x, y);
    live_.touchPath.down(x, y, t);
    // Only a touch that began on the screen holds it: a request that comes
    // up under a finger already down isn't dismissed by it.
    live_.touchOnNeedsYou = faced && needsYouShows(t);
    live_.touchAttnId = live_.touchOnNeedsYou ? b_.model().attnId : 0;
    live_.touchDismissed = false;
    if (faced) {
      b_.pressDown(t);
      b_.face().finger(true, x, y);
      latency_.mark(Latency::kPress, real);
    }
  } else if (touching && contact) {
    live_.touchPath.move(x, y, t);
    if (faced) b_.face().finger(true, x, y);
  }
  if (touching && live_.touchOnNeedsYou && !live_.touchDismissed && needsYouShows(t) && live_.touchPath.held(t)) {
    // Nothing plays: the screen goes when the Mac's next state says so.
    live_.touchDismissed = true;
    input("gesture", t);
    char data[24];
    std::snprintf(data, sizeof(data), "{\"attn\":%lu}", (unsigned long)live_.touchAttnId);
    kit().emit("gesture", kDismissGesture, live_.touchAttnId ? data : nullptr, live_.touchInjected);
  }
  if (!touching && live_.touchDown) {
    b_.pressUp();
    // The face may carry on the finger's motion as it lets go.
    int vx, vy;
    live_.touchPath.velocity(vx, vy);
    b_.face().letGo(vx, vy);
    render::Gesture g = render::Gesture::kHandoff;
    const TouchGesture::Kind kind = live_.touchPath.up(g);
    live_.lastTouch = live_.touchPath.path();
    live_.lastTouchWas = kind == TouchGesture::kGesture ? render::gestureName(g)
                         : kind == TouchGesture::kSwipe ? kSwipeGesture
                                                        : "tap";
    if (faced) {
      // The panel's touch let go when it was last in contact, so its tap
      // counts the kTouchReleaseMs the device waits to be sure. Its path
      // may make it a gesture: a stroke, a ruffle, a swipe, a tickle, a
      // boop on the nose; then the board reacts as one, but not while the
      // face is held, where a touch is a tap.
      // A touch that began on the needs-you screen was for it: it gives no tap
      // once its hold dismissed it, or once the screen has gone (its request
      // answered or dismissed on the Mac).
      if (!(live_.touchOnNeedsYou && (live_.touchDismissed || !needsYouShows(t)))) {
        latency_.mark(Latency::kTap, live_.touchInjected ? touchGone : live_.touchSeenReal);
        if (kind == TouchGesture::kTap || b_.held(t))
          tapped(t, live_.touchInjected, false);
        else
          gestured(g, t, live_.touchInjected, kind == TouchGesture::kSwipe);
      }
    }
  }
  if (touching != live_.touchDown) dirty_ = true;
  live_.touchDown = touching;
}

bool Device::needsYouShows(uint32_t t) const { return b_.look(t) == render::SceneState::kNeedsYou; }

void Device::gestured(render::Gesture g, uint32_t t, bool injected, bool swipe) {
  if (!swipe || b_.face().playsSwipe()) b_.gesture(g, t);
  input("gesture", t);
  kit().emit("gesture", swipe ? kSwipeGesture : render::gestureName(g), nullptr, injected);
  drain();  // the gesture cuts an animation, as a poke does
}

// The motion sensor, every kMotionMs: picked up, put down, shaken, a thump
// on the desk, laid face down (do not disturb) and turned back up.
void Device::readMotion(uint32_t t) {
  if (int32_t(t - live_.motionAt) < int32_t(kMotionMs)) return;
  live_.motionAt = t;
  int ax = live_.injAx, ay = live_.injAy, az = live_.injAz;
  if (!live_.injMotion && !hal_.motion(ax, ay, az)) return;
  switch (live_.motion.update(ax, ay, az, t)) {
    case MotionGesture::kPickup: gestured(render::Gesture::kPickup, t, live_.injMotion); break;
    case MotionGesture::kPutdown: gestured(render::Gesture::kPutdown, t, live_.injMotion); break;
    case MotionGesture::kShake: gestured(render::Gesture::kDizzy, t, live_.injMotion); break;
    case MotionGesture::kThump: gestured(render::Gesture::kStartle, t, live_.injMotion); break;
    case MotionGesture::kFaceDown:
      b_.setFaceDown(true, t);
      hush();
      kit().emit("gesture", "facedown", nullptr, live_.injMotion);
      dirty_ = true;
      break;
    case MotionGesture::kFaceUp:
      b_.setFaceDown(false, t);
      gestured(render::Gesture::kPeekaboo, t, live_.injMotion);
      break;
    default: break;
  }
}

void Device::tick(uint32_t t) {
  uint32_t real = hal_.realMs();
  if (real - fpsSinceReal_ >= 1000) fps_ = frames_ * 1000 / (real - fpsSinceReal_), frames_ = 0, fpsSinceReal_ = real;
  readInputs(t);
  readMotion(t);
  followSound(t);
  drain();

  uint32_t led = b_.led(t);
  if (led != led_) led_ = led, hal_.setLed(led);
  uint8_t bl = b_.backlight(t);
  if (bl != backlight_) backlight_ = bl, hal_.setBacklight(bl);

  const bool noApp = !live_.pattern && b_.noApp(t);
  if (noApp != noApp_) noApp_ = noApp, dirty_ = true;
  // The face may change without a message: its design moves on its own
  // clock (a breath, keys lighting, a blink), so on the face screens every
  // step is checked, and drawn only if its frame changed. A frozen clock
  // looks on every step, so scenario frames stay exact, and the press
  // squish on every pass, so the cap doesn't delay a press.
  bool due = kit().frozen() || b_.pressEasing(t) || hal_.realMs() - drawnReal_ >= kFrameMs;
  if (dirty_ || (!live_.pattern && t != live_.drawnT && due)) render(t);
}

// ---- Sound -----------------------------------------------------------------

void Device::hush() {
  if (saying_) hal_.hush();
  saying_ = false;
}

// The `say` that arrived starts its sound when its bubble shows, at the
// volume then; one replaced, or over, before it started is dropped. True
// when it starts now.
bool Device::startSay(uint32_t t) {
  if (b_.reactionSeq() == live_.saidSeq) return false;
  if (!b_.bubble(t)) {  // it waits for its animation's voice window, or it's gone
    if (!b_.sayAhead(t)) live_.saidSeq = b_.reactionSeq();
    return false;
  }
  live_.saidSeq = b_.reactionSeq();
  const Model& m = b_.model();
  if (m.vol <= 0) return false;
  hal_.say(voice::makeSay(b_.take(), b_.then(), uint8_t(m.vol)));
  saying_ = true;
  return true;
}

// Stops a `say` whose bubble ended or was replaced (by a newer reaction), and
// starts one that waited for its voice window, then plays the face's sound
// effects: its design's events as its clock reaches them,
// and silence for the last design's when it changes or starts over (needs
// you's, for a new needs-you).
void Device::followSound(uint32_t t) {
  if (saying_ && (b_.reactionSeq() != live_.saidSeq || !b_.bubble(t))) hush();
  startSay(t);
  const Model& m = b_.model();
  voice::FxEvent due[render::Face::kMaxCues];
  bool changed;
  int n = b_.face().cues(t, !live_.pattern, due, changed);
  if (changed) hal_.stopEffects();
  if (m.vol == 0) return;
  const voice::EffectClips& clips = b_.face().clips();
  for (int i = 0; i < n; ++i) {
    const voice::EffectClip clip = clips.at(due[i].clip);
    hal_.effect({due[i].clip, due[i].gain, due[i].pitch, uint8_t(m.vol), due[i].duck, clip.samples, clip.len});
    ++fxSent_;
    fxLast_ = due[i].clip;
  }
}

// ---- Drawing ---------------------------------------------------------------

// Draws the frame for t, unless nothing on it can have changed since the
// last one: no message or input since (dirty_), the face's
// design on the same steps with the same additions, and the bubble still
// up or still down. The designs step a few times a second, so most passes
// find the picture unchanged.
void Device::render(uint32_t t) {
  live_.drawnT = t;
  drawnReal_ = hal_.realMs();
  // A native face draws into the surface not being sent.
  render::SurfacePair* native = frames();
  if (live_.pattern) {  // drawn only when dirty: it doesn't move
    if (live_.targetX >= 0) {
      canvas_.fill(render::kBlack);
      canvas_.fillRect(live_.targetX - 10, live_.targetY - 1, 21, 3, render::kAmber);
      canvas_.fillRect(live_.targetX - 1, live_.targetY - 10, 3, 21, render::kAmber);
    } else if (live_.patternFill >= 0) {
      canvas_.fill(uint8_t(live_.patternFill));
    } else {
      render::drawPattern(canvas_);
    }
    if (native) {
      native->back().invalidate();  // written whole, past what drawing tracks
      render::blit(canvas_, native->back(), 0);
    }
  } else {
    b_.face().watch(&b_.stream());
    if (!b_.face().draw(canvas_, native ? &native->back() : nullptr, b_.show(t), t, b_.bubble(t), b_.sign(t),
                        b_.strip(t), dirty_))
      return;
  }
  if (native) native->drew();
  dirty_ = false;
  frame_ = true;
  latency_.drawn();
}

int Device::latencyFields(char* out, size_t n) const {
  int written = 0;
  for (int k = 0; k < Latency::kKinds; ++k) {
    const Latency::Stats s = latency_.stats(Latency::Kind(k));
    int w = std::snprintf(out + written, n - size_t(written), " %s_ms=%lu/%lu", Latency::name(Latency::Kind(k)),
                          (unsigned long)s.p95, (unsigned long)s.max);
    if (w < 0 || size_t(written + w) >= n) return written;
    written += w;
  }
  return written;
}

}  // namespace app
