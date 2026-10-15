#include "app/device.h"

#include <ArduinoJson.h>

#include <cstdio>
#include <cstring>

#include "linkkit/codec.h"
#include "render/maths.h"
#include "render/palette.h"
#include "render/pattern.h"
#include "render/screens.h"

namespace app {

namespace {

using linkkit::Call;
using linkkit::How;
using linkkit::Link;

constexpr uint32_t kDefaultPressMs = 100;
// Motion redraws at most this often, in real ms: about 60 fps. Parts of
// the face that cross block lines a few ms apart show together.
constexpr uint32_t kFrameMs = 16;
// BOOT's cap on talking is where listening stops listening.
static_assert(ButtonGesture::kTalkCapMs == Behaviour::kListenMs, "the talk cap is listening's");
// The face's no-app look and the kit's host-gone window are the same 30 s
// (linkkit/SPEC.md §5), on the device clock and in real
// time.
static_assert(Behaviour::kNoAppMs == linkkit::kHostGoneMs, "no app is when the host is gone");
// dbg.shot sends the palette as it's laid out in memory: 256 RGB565
// entries, low byte first.
static_assert(sizeof(render::kPalette.c) == 512, "the palette is 256 entries");
static_assert(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__, "the palette goes out as it's stored");

bool after(uint32_t a, uint32_t b) { return int32_t(a - b) > 0; }  // a later than b

// A repeated state keeps the link alive but doesn't invalidate the picture.
// Compare fields, not bytes: Model has padding and its strings are terminated.
bool sameModel(const Model& a, const Model& b) {
  return a.base == b.base && a.act == b.act && a.mood == b.mood && a.variant == b.variant &&
         a.attn == b.attn && a.attnId == b.attnId && a.more == b.more && a.busy == b.busy && a.vol == b.vol &&
         !std::strcmp(a.agent, b.agent) && !std::strcmp(a.project, b.project) && !std::strcmp(a.name, b.name);
}

// Boop's do names, in hello.does's order, and the
// animation each plays: none for a reaction (a line, a face) and for
// stop_listening. A tap's poked and tap_spam aren't among them: the device
// plays those itself.
enum Do : uint8_t {
  kReact,
  kTaskComplete,
  kReplyReady,
  kStarting,
  kStopped,
  kError,
  kHelperReturn,
  kListening,
  kStopListening,
  kDoCount
};
constexpr const char* kDoNames[kDoCount] = {"react", "task_complete", "reply_ready", "starting",      "stopped",
                                            "error", "helper_return", "listening",   "stop_listening"};
constexpr render::Anim kDoAnims[kDoCount] = {
    render::Anim::kNone,         render::Anim::kTaskComplete, render::Anim::kReplyReady,
    render::Anim::kStarting,     render::Anim::kStopped,      render::Anim::kError,
    render::Anim::kHelperReturn, render::Anim::kListening,    render::Anim::kNone};

// A number the device holds to lo–hi: any JSON number,
// one past either end (even too big for an int) as that end, and a
// fraction as its whole part. Missing or not a number reads as `missing`.
int heldTo(JsonVariantConst v, int lo, int hi, int missing) {
  if (!v.is<double>() || v.is<bool>()) return missing;
  double n = v.as<double>();
  return n >= hi ? hi : n > lo ? int(n) : lo;
}

// Copying a voice pack onto the card over USB:
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
    ok = hal.packBegin(doc["keep"] | false, have, why);
  } else if (!std::strcmp(op, "put")) {
    uint8_t chunk[kCardChunk];  // on the stack: static, it'd hold 360 B of heap for good
    const char* d = doc["d"] | "";
    long got = linkkit::base64Decode(d, std::strlen(d), chunk, sizeof(chunk));
    hal.packAppend(chunk, 0, have);  // how much the card holds
    if (got < 0) why = "not base64";
    else if (linkkit::crc32(chunk, size_t(got)) != (doc["c"] | 0u)) why = "wrong crc";
    else if ((doc["at"] | 0u) != have) why = "not where the card is";
    else if (!(ok = hal.packAppend(chunk, size_t(got), have))) why = "can't write";
  } else if (!std::strcmp(op, "end")) {
    ok = swapped = hal.packEnd(doc["size"] | 0u, doc["crc"] | 0u, why);
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

// The voice pack on the card, which the Mac checks before it sends takes.
void Device::hello(JsonObject extra) {
  extra["voice"] = voice::assetsVersion();
  extra["face"] = b_.face().name();
  extra["pack"] = render::kPackId;  // the character pack it was built with
  extra["pack_version"] = render::kPackVersion;
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
  parsed_ = Parsed{};
  restKey_ = 0;
  hush();
  saidSeq_ = 0;
  hal_.stopEffects();
  pattern_ = false;
  patternFill_ = -1;
  targetX_ = targetY_ = -1;
  injPress_ = injTouch_ = bootInjected_ = touchDown_ = touchInjected_ = false;
  boot_ = ButtonGesture{};
  last_ = LastInput{};
  drawnT_ = 0;
  dirty_ = true;
}

void Device::drain() {
  Ended e;
  while (b_.takeEnded(e)) kit().ended(e.call, e.by == CutBy::kNone ? How::kDone : How::kCut, cutByName(e.by));
}

void Device::input(const char* k, uint32_t t, int x, int y) {
  last_ = {k, t, x, y};
  dirty_ = true;
}

// ---- The Mac's messages ----------------------------------------------------

void Device::onState(JsonObjectConst doc, uint32_t at) {
  Model m;
  m.base = baseFromName(doc["base"]);          // idle if missing or unknown
  m.act = actFromName(doc["act"]);             // working's design if missing or unknown
  m.mood = render::moodFromName(doc["mood"]);
  if (!b_.face().supportsMood(m.mood)) m.mood = render::kStartupMood;  // the startup mood if missing or unknown
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
  m.vol = heldTo(doc["vol"], 0, 10, 6);
  // The visual's variation, from 1: missing reads as 1, and one out of range is held to it.
  m.variant = uint8_t(
      heldTo(doc["variant"], 1, b_.face().variants(m.mood, m.attn ? render::SceneState::kNeedsYou : m.look()), 1) - 1);
  if (!sameModel(m, b_.model()) || pattern_ || b_.noApp(at)) dirty_ = true, latency_.mark(Latency::kState, hal_.realMs());
  b_.onState(m, at);
  if (m.attn || m.vol == 0) hush();
  if (m.vol == 0) hal_.stopEffects();
  pattern_ = false;
  drain();  // "needs you" cuts what plays
}

// A do's args, as today's moment fields. The variation
// is picked here, as the call is about to play: the Mac's (from 1) when
// it's one of its design's, in the mood it's drawn in, for the finish's
// outcome or the start's context; else the device picks one of those,
// never the one it showed last.
MomentIn Device::parse(const Call& c) {
  MomentIn mo;
  mo.call = c.key;
  mo.id = c.id > 0 ? uint32_t(c.id) : 0;
  if (c.what == kStopListening) {
    mo.empty = true;
    return mo;
  }
  JsonObjectConst args = c.args;
  mo.anim = c.what < kDoCount ? kDoAnims[c.what] : render::Anim::kNone;
  mo.expr = render::parseMood(args["mood"], mo.mood) && b_.face().supportsMood(mo.mood);  // unknown or missing: the state's mood
  mo.loops = heldTo(args["loops"], 1, Behaviour::kMaxLoops, 1);
  if (mo.anim != render::Anim::kNone) {
    render::Outcome outcome = render::Outcome::kNone;
    render::StartCtx ctx = render::StartCtx::kNone;
    if (mo.anim == render::Anim::kTaskComplete) outcome = render::outcomeFromName(args["outcome"]);
    if (mo.anim == render::Anim::kStarting) ctx = render::ctxFromName(args["ctx"]);
    mo.outcome = outcome;
    mo.ctx = ctx;
    mo.variant = b_.pick(mo.anim, mo.expr ? mo.mood : b_.model().mood, heldTo(args["variant"], 0, 255, 0), outcome,
                         ctx, kit().rng());
  }
  mo.said = !args["say"].isNull();
  JsonObjectConst who = args["who"];  // copied by play, while the args live
  if (who) mo.whoAgent = who["agent"] | "", mo.whoThread = who["thread"] | "";
  // The line: a take by its id, and maybe a second, `then`, from the
  // card's voice pack. `{}`, or an id the pack doesn't have (or no card),
  // is still a `say` (the reply listening waits for) but plays nothing.
  mo.take = voice::takeIndex(args["say"]["take"].as<const char*>());
  mo.then = mo.take >= 0 ? voice::takeIndex(args["say"]["then"].as<const char*>()) : -1;
  return mo;
}

// While something needs you, with no app, or while
// listening holds the face, a call none of which would play is skipped;
// so is stop_listening with nothing to stop. A reply ends listening either
// way.
const char* Device::refuse(const Call& c, uint32_t t) {
  parsed_ = Parsed{c.key, parse(c)};
  const char* why = b_.admit(parsed_.in, t);
  drain();  // a listening call the reply ended
  if (why) parsed_ = Parsed{};
  return why;
}

// The call holds the turn: it plays as a moment always has, layered over
// what plays, and says when it may be replaced: a
// reaction half a second after its line and bubble have played, or 1.7 s
// in for a face with no line (it ends sooner if nothing of it plays by
// then); a finish never, until it's over; the one-shots, a poke and
// listening at once; stop_listening is over as it starts. The Mac's
// `listening` drops the calls its own host has waiting, as the Mac once
// dropped its own queue.
void Device::onDo(const Call& c, uint32_t t) {
  latency_.mark(Latency::kDo, hal_.realMs());  // from when it plays, past its wait for the turn
  const MomentIn mo = parsed_.key == c.key ? parsed_.in : parse(c);
  parsed_ = Parsed{};
  uint32_t seq = b_.momentSeq();
  // A line's sound goes with its bubble: now, or at its animation's voice
  // window. Any other call drops one still waiting.
  const bool line = b_.play(mo, t);
  if (!line) saidSeq_ = b_.momentSeq();
  if (!startLine(t) && b_.momentSeq() != seq) hush();  // a new moment replaces the line
  dirty_ = true;
  restKey_ = 0;
  switch (c.what) {
    case kReact:
      restKey_ = c.key;
      restAt_ = (line ? b_.sayEnd() : t + Behaviour::kBubbleReadMs) + kReactGapMs;
      break;
    case kTaskComplete:
    case kReplyReady:
      break;
    case kListening:
      kit().dropWaiting("mic_on", c.from);  // the mic went on: the reactions waiting would end it
      kit().rest(c.key);
      break;
    case kStopListening:
      kit().ended(c.key);
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
  if (restKey_ && !after(restAt_, t)) kit().rest(restKey_), restKey_ = 0;
}

bool Device::nextDue(uint32_t from, uint32_t to, uint32_t& at) {
  bool found = b_.nextEnd(from, to, at);
  if (restKey_ && after(restAt_, from) && !after(restAt_, to) && (!found || after(at, restAt_))) {
    at = restAt_, found = true;
  }
  return found;
}

// ---- Debug messages --------------------------------------------------------

bool Device::debug(const char* type, JsonObjectConst doc, Link from) {
  char buf[160];
  if (!std::strcmp(type, "dbg.pattern")) {
    // With "fill", a solid screen of that palette index (webcam framing).
    // With "target": [x, y], a cross to tap on black (boopctl calibrate).
    patternFill_ = doc["fill"] | -1;
    JsonArrayConst target = doc["target"];
    targetX_ = target.size() == 2 ? render::clamp(target[0].as<int>(), 0, render::kWidth - 1) : -1;
    targetY_ = target.size() == 2 ? render::clamp(target[1].as<int>(), 0, render::kHeight - 1) : -1;
    pattern_ = true;
    dirty_ = true;
    kit().reply(from, "{\"t\":\"dbg.pattern\"}", 19);
  } else if (!std::strcmp(type, "dbg.press")) {
    injPress_ = true;
    injPressUntil_ = kit().now() + (doc["ms"] | kDefaultPressMs);
    kit().reply(from, "{\"t\":\"dbg.press\"}", 17);
  } else if (!std::strcmp(type, "dbg.touch")) {
    injTouch_ = true;
    injX_ = doc["x"] | 0;
    injY_ = doc["y"] | 0;
    injTouchUntil_ = kit().now() + (doc["ms"] | kDefaultPressMs);
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
    // Nothing reads the old pack while `end` swaps it, and a waiting line is dropped.
    if (!std::strcmp(doc["op"] | "", "end")) hush(), saidSeq_ = b_.momentSeq();
    bool swapped;
    size_t n = cardCopy(hal_, doc, buf, sizeof(buf), swapped);
    if (n) kit().reply(from, buf, n);
    if (swapped) kit().helloChanged();  // hello's `voice` names the new pack
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

void Device::state(JsonObject d, uint32_t t) {
  const Model& m = b_.model();
  d["screen"] = screenName(screenAt(t));
  d["base"] = render::stateName(m.base);
  if (m.act != render::SceneState::kWorking) d["act"] = render::stateName(m.act);
  else d["act"] = nullptr;
  d["mood"] = render::moodName(m.mood);
  d["variant"] = m.variant + 1;
  d["look_variant"] = b_.lookVariant() + 1;
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
  render::Anim anim = b_.moment(t, left);
  if (anim != render::Anim::kNone) {
    d["moment"]["anim"] = render::animName(anim);
    d["moment"]["left_ms"] = left;
    d["moment"]["variant"] = b_.momentVariant() + 1;
  } else {
    d["moment"] = nullptr;
  }
  render::Mood expr;
  if (b_.expression(t, expr)) d["expr"] = render::moodName(expr);
  else d["expr"] = nullptr;
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
  if (last_.k) {
    JsonObject li = d["last_input"].to<JsonObject>();
    li["k"] = last_.k;
    li["at"] = last_.at;
    if (last_.x >= 0) {
      li["x"] = last_.x;
      li["y"] = last_.y;
    }
  } else {
    d["last_input"] = nullptr;
  }
  // Bring-up extras (F1): raw hardware readings.
  d["boot"] = boot_.down();
  int rx, ry, rz;
  bool irq;
  hal_.touchRaw(rx, ry, rz, irq);
  JsonObject touch = d["touch"].to<JsonObject>();
  touch["down"] = touchDown_;
  touch["irq"] = irq;
  JsonArray raw = touch["raw"].to<JsonArray>();
  raw.add(rx), raw.add(ry), raw.add(rz);
  d["amp"] = hal_.ampOn();
  d["bl"] = b_.backlight(t);
}

// 256 little-endian RGB565 palette entries, then one palette index per
// pixel, row by row, drawn afresh; a native face's frame as its RGB565
// pixels. Either is the frame the board sends next.
bool Device::shot(linkkit::Shot& s, uint32_t t) {
  screen_ = screenAt(t);
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
void Device::tapped(uint32_t t, bool injected) {
  uint32_t finish = b_.finishShown(t);
  const char* did = b_.tap(t, kit().rng());
  input("tap", t);
  char data[32];
  bool on = finish && std::snprintf(data, sizeof(data), "{\"on\":%lu}", (unsigned long)finish) > 0;
  kit().emit("tap", did, on ? data : nullptr, injected);
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
  if (injPress_ && int32_t(t - injPressUntil_) >= 0) injPress_ = false, pressGone = letGo(injPressUntil_);
  switch (boot_.update(hal_.bootDown() || injPress_, t)) {
    case ButtonGesture::kDown:
      bootInjected_ = !hal_.bootDown();
      b_.pressDown(t);
      dirty_ = true;
      latency_.mark(Latency::kPress, real);
      break;
    case ButtonGesture::kTap:
      b_.pressUp();
      latency_.mark(Latency::kTap, bootInjected_ ? pressGone : real);
      tapped(t, bootInjected_);
      break;
    case ButtonGesture::kHoldStart:  // push-to-talk: listening at once, before the Mac hears
      b_.pressUp();
      // The reactions waiting would end it: dropped for every Mac that
      // hears talk_on, which for a tool's dbg.press is only USB's.
      kit().dropWaiting("mic_on", bootInjected_ ? Link::kUsb : Link::kNone);
      b_.talkOn(t, kit().rng());
      input("talk_on", t);
      kit().emit("talk_on", "listening", nullptr, bootInjected_);
      drain();  // listening cuts what played
      break;
    case ButtonGesture::kHoldEnd:  // let go, or the 30 s cap
      b_.talkOff(t);
      input("talk_off", t);
      kit().emit("talk_off", nullptr, nullptr, bootInjected_);
      break;
    default:
      break;
  }

  // A touch anywhere is a tap, sent on release however long it was held.
  // The press shows at once. The panel misses readings under a light
  // press, so its touch ends only after kTouchReleaseMs without contact,
  // in real time so that it ends while a tool has the clock frozen; an
  // injected one ends when it says. The debug pattern ignores touches.
  if (injTouch_ && int32_t(t - injTouchUntil_) >= 0) injTouch_ = false, touchGone = letGo(injTouchUntil_);
  int x = 0, y = 0;
  bool contact = injTouch_ ? (x = injX_, y = injY_, true) : hal_.touch(x, y);
  if (contact) touchSeenReal_ = real, touchInjected_ = injTouch_;
  bool touching = contact || (touchDown_ && !touchInjected_ && real - touchSeenReal_ < kTouchReleaseMs);
  bool faced = screenAt(t) != Screen::kPattern;
  if (touching && !touchDown_) {
    input("touch", t, x, y);
    if (faced) {
      b_.pressDown(t);
      latency_.mark(Latency::kPress, real);
    }
  }
  if (!touching && touchDown_) {
    b_.pressUp();
    if (faced) {
      // The panel's touch let go when it was last in contact, so its tap
      // counts the kTouchReleaseMs the device waits to be sure.
      latency_.mark(Latency::kTap, touchInjected_ ? touchGone : touchSeenReal_);
      tapped(t, touchInjected_);
    }
  }
  if (touching != touchDown_) dirty_ = true;
  touchDown_ = touching;
}

void Device::tick(uint32_t t) {
  uint32_t real = hal_.realMs();
  if (real - fpsSinceReal_ >= 1000) fps_ = frames_ * 1000 / (real - fpsSinceReal_), frames_ = 0, fpsSinceReal_ = real;
  readInputs(t);
  followSound(t);
  drain();

  uint32_t led = b_.led(t);
  if (led != led_) led_ = led, hal_.setLed(led);
  uint8_t bl = b_.backlight(t);
  if (bl != backlight_) backlight_ = bl, hal_.setBacklight(bl);

  Screen screen = screenAt(t);
  if (screen != screen_) screen_ = screen, dirty_ = true;
  // The face may change without a message: its design moves on its own
  // clock (a breath, keys lighting, a blink), so on the face screens every
  // step is checked, and drawn only if its frame changed. A frozen clock
  // looks on every step, so scenario frames stay exact, and the press
  // squish on every pass, so the cap doesn't delay a press.
  bool due = kit().frozen() || b_.pressEasing(t) || hal_.realMs() - drawnReal_ >= kFrameMs;
  if (dirty_ || (screen_ != Screen::kPattern && t != drawnT_ && due)) render(t);
}

// ---- Sound -----------------------------------------------------------------

void Device::hush() {
  if (saying_) hal_.hush();
  saying_ = false;
}

// The line that arrived starts its sound when its bubble shows, at the
// volume then; one replaced, or over, before it started is dropped. True
// when it starts now.
bool Device::startLine(uint32_t t) {
  if (b_.momentSeq() == saidSeq_) return false;
  if (!b_.bubble(t)) {  // it waits for its animation's voice window, or it's gone
    if (!b_.lineAhead(t)) saidSeq_ = b_.momentSeq();
    return false;
  }
  saidSeq_ = b_.momentSeq();
  const Model& m = b_.model();
  if (m.vol <= 0) return false;
  hal_.say(voice::makeLine(b_.take(), b_.then(), uint8_t(m.vol)));
  saying_ = true;
  return true;
}

// Stops a line whose bubble ended or was replaced (a newer moment, say), and
// starts one that waited for its voice window, then plays the face's sound
// effects: its design's events as its clock reaches them,
// and silence for the last design's when it changes or starts over (needs
// you's, for a new request).
void Device::followSound(uint32_t t) {
  if (saying_ && (b_.momentSeq() != saidSeq_ || !b_.bubble(t))) hush();
  startLine(t);
  const Model& m = b_.model();
  render::SceneShow show = b_.show(t);
  show.t = b_.designMs(t);
  voice::FxEvent due[render::Face::kMaxCues];
  bool changed;
  int n = b_.face().cues(screenAt(t) == Screen::kPattern ? nullptr : &show, due, changed);
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
  drawnT_ = t;
  drawnReal_ = hal_.realMs();
  // A native face draws into the surface not being sent.
  render::SurfacePair* native = frames();
  if (screen_ == Screen::kPattern) {  // drawn only when dirty: it doesn't move
    if (targetX_ >= 0) {
      canvas_.fill(render::kBlack);
      canvas_.fillRect(targetX_ - 10, targetY_ - 1, 21, 3, render::kAmber);
      canvas_.fillRect(targetX_ - 1, targetY_ - 10, 3, 21, render::kAmber);
    } else if (patternFill_ >= 0) {
      canvas_.fill(uint8_t(patternFill_));
    } else {
      render::drawPattern(canvas_);
    }
    if (native) {
      native->back().invalidate();  // written whole, past what drawing tracks
      render::blit(canvas_, native->back(), 0);
    }
  } else {
    if (!b_.face().draw(canvas_, native ? &native->back() : nullptr, b_.show(t), t, b_.bubble(t), b_.strip(t),
                        dirty_))
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
