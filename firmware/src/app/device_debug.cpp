#include "app/device.h"

#include <ArduinoJson.h>

#include <cstdio>
#include <cstring>

#include "linkkit/codec.h"
#include "render/maths.h"
#include "render/palette.h"
#include "render/tags.h"

namespace app {

namespace {

using linkkit::Link;

constexpr uint32_t kDefaultPressMs = 100;
// dbg.shot sends the palette as it's laid out in memory: 256 RGB565
// entries, low byte first.
static_assert(sizeof(render::kPalette.c) == 512, "the palette is 256 entries");
static_assert(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__, "the palette goes out as it's stored");

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
  // The agents' drawer: how far open, and the rows the Mac sent.
  d["drawer"]["open"] = drawerOpen(t);
  d["drawer"]["rows"] = m.listCount;
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
  touch["lifts"] = hal_.touchLifts();
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

}  // namespace app
