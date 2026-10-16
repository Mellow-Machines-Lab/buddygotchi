#include "linkkit/kit.h"

#include <cstdio>
#include <cstring>

#include "linkkit/codec.h"

namespace linkkit {

namespace {

bool after(uint32_t a, uint32_t b) { return int32_t(a - b) > 0; }  // a later than b

// A number field that must be an integer in lo..hi (§2): anything else,
// a fraction or a bool included, reads as missing (0).
int64_t intIn(JsonVariantConst v, int64_t lo, int64_t hi) {
  if (!v.is<int64_t>()) return 0;
  int64_t n = v.as<int64_t>();
  return n >= lo && n <= hi ? n : 0;
}

Play playFrom(const char* s) {
  if (s && !std::strcmp(s, "now")) return Play::kNow;
  if (s && !std::strcmp(s, "if_free")) return Play::kIfFree;
  return Play::kNext;  // missing or unknown (§3)
}

// Builds one message of at most kMaxLine bytes, escaping the app's strings
// as JSON, so a quote or a backslash in an `ev`'s kind, its did or a `why`
// can't break it. A message that wouldn't fit is never sent: len() is 0.
class LineOut {
 public:
  LineOut& raw(const char* s) {
    while (*s) put(*s++);
    return *this;
  }
  LineOut& str(const char* s) {
    put('"');
    for (; *s; ++s) {
      const unsigned char c = static_cast<unsigned char>(*s);
      if (c == '"' || c == '\\') {
        put('\\'), put(char(c));
      } else if (c < 0x20) {
        char esc[7];
        std::snprintf(esc, sizeof(esc), "\\u%04x", unsigned(c));
        raw(esc);
      } else {
        put(char(c));
      }
    }
    put('"');
    return *this;
  }
  LineOut& num(long n) {
    char digits[24];
    std::snprintf(digits, sizeof(digits), "%ld", n);
    return raw(digits);
  }
  const char* text() const { return buf_; }
  size_t len() const { return ok_ ? n_ : 0; }

 private:
  void put(char c) {
    if (n_ < kMaxLine) buf_[n_++] = c;
    else ok_ = false;
  }
  char buf_[kMaxLine];
  size_t n_ = 0;
  bool ok_ = true;
};

// Streams ArduinoJson's output to an Out a few bytes at a time, so a long
// dbg.* reply needs no buffer of its own size.
class OutWriter {
 public:
  explicit OutWriter(Out* out) : out_(out) {}
  ~OutWriter() { flush(); }
  size_t write(uint8_t c) {
    if (n_ == sizeof(buf_)) flush();
    buf_[n_++] = char(c);
    return 1;
  }
  size_t write(const uint8_t* s, size_t n) {
    for (size_t i = 0; i < n; ++i) write(s[i]);
    return n;
  }
  void flush() {
    if (n_ && out_) out_->write(buf_, n_);
    n_ = 0;
  }

 private:
  Out* out_;
  char buf_[64];
  size_t n_ = 0;
};

void sinkToOut(void* ctx, const char* text, size_t n) { static_cast<Out*>(ctx)->write(text, n); }

}  // namespace

const char* linkName(Link l) {
  switch (l) {
    case Link::kUsb: return "usb";
    case Link::kBle: return "ble";
    default: return "none";
  }
}

const char* howName(How h) {
  switch (h) {
    case How::kCut: return "cut";
    case How::kSkipped: return "skipped";
    default: return "done";
  }
}

Kit::Kit(Platform& platform, App& app, bool frozenClock) : platform_(platform), app_(app) {
  clock_.start(frozenClock, platform_.realMs());
  // §7: a running device's randomness differs each power-on; a frozen one
  // (the simulator, tests) starts where every dbg.reset does.
  if (!frozenClock) rng_.seed(platform_.bootId());
  const char* const* names = nullptr;
  int n = app_.does(names);
  does_ = names;
  nDoes_ = uint8_t(names && n > 0 ? (n < kMaxDoes ? n : kMaxDoes) : 0);
  app_.kit_ = this;
  app_.begin();
}

void Kit::setOut(Link link, Out* out) { links_[int(link)].out = out; }

void Kit::reply(Link to, const char* text, size_t n) {
  Out* out = links_[int(to)].out;
  if (!out) return;
  out->write(text, n);
  out->write("\n", 1);
}

bool Kit::live(Link l) const {
  const LinkState& s = links_[int(l)];
  if (l == Link::kBle) return s.up;
  return l == Link::kUsb && s.heard && platform_.realMs() - s.heardReal < kHostGoneMs;
}

// ---- Lines ----------------------------------------------------------------

bool Kit::handleLine(const char* line, size_t n, Link from) {
  JsonDocument doc;
  if (deserializeJson(doc, line, n) != DeserializationError::Ok) return false;
  const char* t = doc["t"];
  if (!t) return false;
  const bool debug = std::strncmp(t, "dbg.", 4) == 0;
  if (debug && from != Link::kUsb) return false;  // §7: USB only
  const uint32_t real = platform_.realMs();
  bool greeted = false;  // heard() has just sent hello
  if (debug) dbgReal_ = real;
  else greeted = heard(from, real);
  const uint32_t at = now();
  advanceTo(at);
  JsonObjectConst msg = doc.as<JsonObjectConst>();

  if (!std::strcmp(t, "state")) {
    ++rxState_;
    app_.onState(msg, at);
  } else if (!std::strcmp(t, "do")) {
    onDoLine(msg, from, at);
  } else if (!std::strcmp(t, "hello")) {
    if (!greeted) sendHello(from);  // §3: the host asks who the device is
  } else if (!std::strcmp(t, "dbg.ping")) {
    sendPing(from);
  } else if (!std::strcmp(t, "dbg.state")) {
    sendState(from);
  } else if (!std::strcmp(t, "dbg.shot")) {
    sendShot(from);
  } else if (!std::strcmp(t, "dbg.clock")) {
    sendClock(from, msg, real);
  } else if (!std::strcmp(t, "dbg.reset")) {
    resetQueue();
    clock_.freeze(0);
    toolFrozen_ = true;
    rng_.seed(0);
    stepped_ = 0;
    app_.reset();
    reply(from, "{\"t\":\"dbg.reset\"}", 17);
  } else if (debug) {
    app_.debug(t, msg, from);
  }
  pump(stepped_);
  return debug;
}

// §5: the host's first message on a link it wasn't live on (for Bluetooth,
// its first since connecting) gets a hello, on that link. Returns true
// when it sent one. A host the device still counts as live (relaunched
// within 30 s, or taking over a link) asks with its own hello instead.
bool Kit::heard(Link from, uint32_t real) {
  LinkState& l = links_[int(from)];
  bool wasLive = from == Link::kBle ? l.heard : l.heard && real - l.heardReal < kHostGoneMs;
  l.heard = true;
  l.heardReal = l.quietReal = real;
  lastLink_ = from;
  if (!wasLive) sendHello(from);
  return !wasLive;
}

void Kit::connected() {
  LinkState& l = links_[int(Link::kBle)];
  l.up = true;
  l.heard = false;
  l.quietReal = platform_.realMs();  // the quiet-link clock starts now
}

void Kit::disconnected() {
  LinkState& l = links_[int(Link::kBle)];
  l.up = l.heard = false;
  if (lastLink_ == Link::kBle) lastLink_ = Link::kNone;
}

bool Kit::shouldDrop() {
  LinkState& l = links_[int(Link::kBle)];
  uint32_t real = platform_.realMs();
  if (!l.up || real - l.quietReal < kHostGoneMs) return false;
  l.quietReal = real;
  return true;
}

void Kit::tick() {
  const uint32_t real = platform_.realMs();
  if (lastLink_ != Link::kNone && live(lastLink_) && real - links_[int(lastLink_)].helloReal >= kHelloMs) {
    sendHello(lastLink_);
  }
  if (toolFrozen_ && real - dbgReal_ >= kThawMs) clock_.run(real), toolFrozen_ = false;
  const uint32_t t = now();
  advanceTo(t);
  app_.tick(t);
  pump(t);
}

// The hello (§3): the kit's fields, then the app's unless kitOnly.
void Kit::fillHello(JsonDocument& d, bool kitOnly) {
  d.clear();
  d["t"] = "hello";
  d["kit"] = kVersion;
  d["app"] = app_.name();
  d["id"] = platform_.deviceId();
  d["fw"] = platform_.fwVersion();
  if (uint32_t boot = platform_.bootId()) {
    char hex[9];
    std::snprintf(hex, sizeof(hex), "%08x", unsigned(boot));
    d["boot"] = hex;
  }
  JsonArray does = d["does"].to<JsonArray>();
  for (int i = 0; i < nDoes_; ++i) does.add(does_[i]);
  if (!kitOnly) app_.hello(d.as<JsonObject>());
}

size_t Kit::helloLength() {
  JsonDocument d;
  fillHello(d, false);
  return measureJson(d);
}

// A hello longer than kMaxLine would be dropped whole on the way (§2),
// so the host would never hear it: the app's fields are left out, and
// when even the kit's don't fit, none goes. dbg.ping says `hello_long`.
void Kit::sendHello(Link to) {
  links_[int(to)].helloReal = platform_.realMs();
  JsonDocument d;
  fillHello(d, false);
  if (measureJson(d) > kMaxLine) {
    fillHello(d, true);
    if (measureJson(d) > kMaxLine) return;
  }
  Out* out = links_[int(to)].out;
  if (!out) return;
  {
    OutWriter w(out);
    serializeJson(d, w);
  }
  out->write("\n", 1);
}

void Kit::helloChanged() {
  if (lastLink_ != Link::kNone && live(lastLink_)) sendHello(lastLink_);
}

void Kit::emit(const char* kind, const char* did, const char* data, bool injected) {
  LineOut line;
  line.raw("{\"t\":\"ev\",\"kind\":").str(kind ? kind : "");
  if (did) line.raw(",\"did\":").str(did);
  if (data) line.raw(",\"data\":").raw(data);
  line.raw("}");
  const size_t n = line.len();
  if (!n) return;
  if (injected) return reply(Link::kUsb, line.text(), n);
  if (live(Link::kBle)) reply(Link::kBle, line.text(), n);
  if (live(Link::kUsb)) reply(Link::kUsb, line.text(), n);
}

// ---- The queue (§4) ------------------------------------------------------

void Kit::onDoLine(JsonObjectConst msg, Link from, uint32_t t) {
  ++rxDo_;
  Do c;
  c.key = ++lastKey_ ? lastKey_ : ++lastKey_;  // never 0, even after it wraps
  c.id = int32_t(intIn(msg["id"], 1, kMaxId));
  c.play = playFrom(msg["play"]);
  int64_t ttl = intIn(msg["ttl"], 1, kMaxTtlMs);
  c.ttl = ttl ? uint32_t(ttl) : kDefaultTtlMs;
  c.from = from;
  c.args = msg["args"].as<JsonObjectConst>();
  // Same id again: a later launch of the host's. The old `do` is
  // forgotten without an `ended`.
  if (c.id) forgetId(c.id);
  const char* name = msg["name"] | "";
  int what = -1;
  for (int i = 0; i < nDoes_ && what < 0; ++i) {
    if (!std::strcmp(name, does_[i])) what = i;
  }
  if (what < 0) return sendEnded(c.id, from, How::kSkipped, "unknown");
  c.what = uint8_t(what);
  c.name = does_[what];
  offer(c, t);
}

void Kit::offer(const Do& c, uint32_t t) {
  const bool free = (!held_ || holder_.resting) && nWaiting_ == 0;
  switch (c.play) {
    case Play::kNow: return take(c, t);
    case Play::kNext: return free ? take(c, t) : enqueue(c, t);
    case Play::kIfFree: return free ? take(c, t) : sendEnded(c.id, c.from, How::kSkipped, "busy");
  }
}

// First the app may refuse it; otherwise it replaces the `do` playing (a
// resting one is done, a busy one cut by it) and plays.
void Kit::take(const Do& c, uint32_t t) {
  if (const char* why = app_.refuse(c, t)) return sendEnded(c.id, c.from, How::kSkipped, why);
  if (held_) endHolder(holder_.resting ? How::kDone : How::kCut, holder_.resting ? nullptr : "now");
  held_ = true;
  holder_ = Holder{c.key, c.id, c.what, c.from, false};
  app_.onDo(c, t);
}

void Kit::enqueue(const Do& c, uint32_t t) {
  // Args too long to keep (only numbers can grow, written again, past the
  // message they came in on) leave no room to wait.
  if (measureJson(c.args) >= kMaxLine) return sendEnded(c.id, c.from, How::kSkipped, "full");
  if (nWaiting_ == kMaxWaiting) {  // the oldest makes room
    sendEnded(waiting_[0].id, waiting_[0].from, How::kSkipped, "full");
    removeWaiting(0);
  }
  int slot = 0;
  while (slotsUsed_ & (1u << slot)) ++slot;
  size_t len = serializeJson(c.args, args_[slot], kMaxLine);
  slotsUsed_ |= uint8_t(1u << slot);
  waiting_[nWaiting_++] = Waiting{c.key, c.id, c.what, c.from, t, c.ttl, uint8_t(slot), uint16_t(len)};
}

void Kit::removeWaiting(int i) {
  slotsUsed_ &= uint8_t(~(1u << waiting_[i].slot));
  for (int k = i + 1; k < nWaiting_; ++k) waiting_[k - 1] = waiting_[k];
  --nWaiting_;
}

void Kit::forgetId(int32_t id) {
  if (held_ && holder_.id == id) held_ = false;
  for (int i = nWaiting_ - 1; i >= 0; --i) {
    if (waiting_[i].id == id) removeWaiting(i);
  }
}

// The queue moves whenever the `do` playing rests or ends: the oldest
// waiting `do` still inside its ttl tries to start.
void Kit::pump(uint32_t t) {
  if (pumping_) return;  // a hook reported: the loop below carries on
  pumping_ = true;
  while ((!held_ || holder_.resting) && nWaiting_ > 0) {
    const Waiting w = waiting_[0];
    if (int32_t(t - w.at) > int32_t(w.ttl)) {
      sendEnded(w.id, w.from, How::kSkipped, "late");
      removeWaiting(0);
      continue;
    }
    JsonDocument doc;  // owns the args while the hooks run
    deserializeJson(doc, args_[w.slot], w.len);
    removeWaiting(0);
    Do c;
    c.key = w.key, c.id = w.id, c.what = w.what, c.name = nameOf(w.what);
    c.play = Play::kNext, c.ttl = w.ttl, c.from = w.from;
    c.args = doc.as<JsonObjectConst>();
    take(c, t);
  }
  pumping_ = false;
}

void Kit::expire(uint32_t t) {
  for (int i = 0; i < nWaiting_;) {
    if (int32_t(t - waiting_[i].at) > int32_t(waiting_[i].ttl)) {
      sendEnded(waiting_[i].id, waiting_[i].from, How::kSkipped, "late");
      removeWaiting(i);
    } else {
      ++i;
    }
  }
}

// Moves the app, and the queue with it, to t. While `do`s wait, it stops
// at every instant one would be late or the app will rest or end the one
// playing, so the queue moves at its exact millisecond, whatever steps the
// clock takes.
void Kit::advanceTo(uint32_t t) {
  if (after(stepped_, t)) stepped_ = t;  // the clock went back: no history to replay
  for (int guard = 0; nWaiting_ > 0 && guard < 64; ++guard) {
    bool found = false;
    uint32_t next = t;
    auto consider = [&](uint32_t c) {
      if (after(c, stepped_) && !after(c, t) && (!found || after(next, c))) next = c, found = true;
    };
    for (int i = 0; i < nWaiting_; ++i) consider(waiting_[i].at + waiting_[i].ttl + 1);
    uint32_t due;
    if (app_.nextDue(stepped_, t, due)) consider(due);
    if (!found) break;
    step(next);
  }
  step(t);
}

void Kit::step(uint32_t t) {
  app_.advance(t);
  stepped_ = t;
  expire(t);
  pump(t);
}

void Kit::rest(uint32_t key) {
  if (held_ && holder_.key == key) holder_.resting = true;
}

void Kit::ended(uint32_t key, How how, const char* why) {
  if (held_ && holder_.key == key) endHolder(how, why);
}

void Kit::cut(const char* why) {
  if (held_) endHolder(How::kCut, why);
}

void Kit::dropWaiting(const char* why, Link only) {
  for (int i = 0; i < nWaiting_;) {
    if (only != Link::kNone && waiting_[i].from != only) {
      ++i;
      continue;
    }
    sendEnded(waiting_[i].id, waiting_[i].from, How::kSkipped, why);
    removeWaiting(i);
  }
}

void Kit::endHolder(How how, const char* why) {
  held_ = false;
  sendEnded(holder_.id, holder_.from, how, how == How::kDone ? nullptr : why);
}

// Exactly one per `do` with an id, on the link it came in on.
void Kit::sendEnded(int32_t id, Link to, How how, const char* why) {
  if (id <= 0) return;
  LineOut line;
  line.raw("{\"t\":\"ev\",\"kind\":\"ended\",\"data\":{\"id\":").num(long(id)).raw(",\"how\":").str(howName(how));
  if (why && *why) line.raw(",\"why\":").str(why);
  line.raw("}}");
  if (line.len()) reply(to, line.text(), line.len());
}

void Kit::resetQueue() {
  if (held_) endHolder(How::kCut, "reset");
  dropWaiting("reset");
}

QueueView Kit::queue() const {
  QueueView v;
  v.held = held_;
  if (held_) v.key = holder_.key, v.id = holder_.id, v.name = nameOf(holder_.what), v.resting = holder_.resting;
  const uint32_t t = now();
  v.waiting = nWaiting_;
  for (int i = 0; i < nWaiting_; ++i) {
    const Waiting& w = waiting_[i];
    int32_t left = int32_t(w.at + w.ttl - t);
    v.wait[i] = QueueView::Waiting{w.key, w.id, nameOf(w.what), left > 0 ? uint32_t(left) : 0};
  }
  return v;
}

// ---- dbg.* (§7) ------------------------------------------------------------

void Kit::sendPing(Link to) {
  JsonDocument d;
  d["t"] = "dbg.ping";
  d["kit"] = kVersion;
  d["fw"] = platform_.fwVersion();
  d["up"] = platform_.realMs();
  d["link"] = linkName(lastLink_);
  d["ble"] = platform_.bleState();
  if (platform_.bleName()[0]) d["name"] = platform_.bleName();
  const size_t hello = helloLength();
  if (hello > kMaxLine) d["hello_long"] = hello;  // §3: it didn't fit, so went short or not at all
  app_.ping(d.as<JsonObject>());
  Out* out = links_[int(to)].out;
  if (!out) return;
  {
    OutWriter w(out);
    serializeJson(d, w);
  }
  out->write("\n", 1);
}

void Kit::sendState(Link to) {
  JsonDocument d;
  d["t"] = "dbg.state";
  const uint32_t t = now();
  app_.state(d.as<JsonObject>(), t);
  d["clock"]["now"] = t;
  d["clock"]["frozen"] = clock_.frozen();
  d["rx"]["state"] = rxState_;
  d["rx"]["do"] = rxDo_;
  const QueueView v = queue();
  JsonObject turn = d["turn"].to<JsonObject>();  // the queue, under its old key
  if (v.held) {
    JsonObject h = turn["holder"].to<JsonObject>();
    if (v.id) h["id"] = v.id;
    else h["id"] = nullptr;
    h["name"] = v.name;
    h["resting"] = v.resting;
  } else {
    turn["holder"] = nullptr;
  }
  JsonArray wait = turn["waiting"].to<JsonArray>();
  for (int i = 0; i < v.waiting; ++i) {
    JsonObject w = wait.add<JsonObject>();
    if (v.wait[i].id) w["id"] = v.wait[i].id;
    else w["id"] = nullptr;
    w["name"] = v.wait[i].name;
    w["left_ms"] = v.wait[i].leftMs;
  }
  Out* out = links_[int(to)].out;
  if (!out) return;
  {
    OutWriter w(out);
    serializeJson(d, w);
  }
  out->write("\n", 1);
}

// A header message, then one base64 line of the app's bytes.
void Kit::sendShot(Link to) {
  Out* out = links_[int(to)].out;
  if (!out) return;
  Shot s;
  if (!app_.shot(s, now())) s = Shot{};
  uint32_t crc = 0;
  size_t bytes = 0;
  for (int i = 0; i < 2; ++i) {
    if (!s.data[i]) continue;
    crc = crc32(s.data[i], s.size[i], crc);
    bytes += s.size[i];
  }
  char head[128];
  int n = std::snprintf(head, sizeof(head), "{\"t\":\"dbg.shot\",\"w\":%u,\"h\":%u,\"bytes\":%lu,\"crc\":%lu}",
                        unsigned(s.w), unsigned(s.h), (unsigned long)bytes, (unsigned long)crc);
  if (n <= 0 || size_t(n) >= sizeof(head)) return;
  reply(to, head, size_t(n));
  Base64Writer b64(sinkToOut, out);
  for (int i = 0; i < 2; ++i) {
    if (s.data[i]) b64.write(s.data[i], s.size[i]);
  }
  b64.finish();
  out->write("\n", 1);
}

// Freeze at T (reseeding the randomness from T), step MS, or run.
void Kit::sendClock(Link to, JsonObjectConst msg, uint32_t real) {
  if (msg["freeze"].is<uint32_t>()) {
    uint32_t t = msg["freeze"];
    clock_.freeze(t);
    rng_.seed(t);
    toolFrozen_ = true;
  } else if (msg["step"].is<uint32_t>()) {
    clock_.step(msg["step"].as<uint32_t>(), real);
    toolFrozen_ = true;
  } else if (msg["run"].as<bool>()) {
    clock_.run(real);
    toolFrozen_ = false;
  }
  char buf[80];
  int n = std::snprintf(buf, sizeof(buf), "{\"t\":\"dbg.clock\",\"now\":%lu,\"frozen\":%s}", (unsigned long)now(),
                        clock_.frozen() ? "true" : "false");
  if (n > 0 && size_t(n) < sizeof(buf)) reply(to, buf, size_t(n));
}

}  // namespace linkkit
