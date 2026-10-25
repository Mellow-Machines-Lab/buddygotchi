// LinkKit's device side (linkkit/SPEC.md): reads the host's messages, keeps
// track of the links, sends hello, runs the queue (§4) and answers the
// kit's dbg.* messages (§7). What the device draws, plays and says is the
// app's: it plugs in as a linkkit::App, and the kit calls it.
//
// Pure C++17 and ArduinoJson 7. Single-threaded: the platform calls
// handleLine, tick and the link events from one loop, and the app calls
// the kit back only from inside its own hooks. Fixed-size tables, and no
// heap beyond one JsonDocument per line handled and per `do` started
// from the queue.
#pragma once
#include <ArduinoJson.h>

#include <cstddef>
#include <cstdint>

#include "linkkit/clock.h"
#include "linkkit/limits.h"

namespace linkkit {

// The two links a device has (§8). Both carry the same messages; dbg.*
// only
// works over USB.
enum class Link : uint8_t { kNone, kUsb, kBle };
const char* linkName(Link l);  // "usb", "ble" or "none"

// A do's `play` (§4).
enum class Play : uint8_t { kNow, kNext, kIfFree };
// How a `do` ended (§4), and the name `ended` gives it.
enum class How : uint8_t { kDone, kCut, kSkipped };
const char* howName(How h);

// Where messages go: USB serial, a Bluetooth link, a test's capture.
struct Out {
  virtual ~Out() = default;
  virtual void write(const char* s, size_t n) = 0;
};

// What the kit needs from the board or the simulator.
struct Platform {
  virtual ~Platform() = default;
  virtual uint32_t realMs() = 0;          // a millisecond counter; it may wrap
  virtual const char* deviceId() = 0;     // hello.id: the device's permanent id
  virtual const char* fwVersion() = 0;    // hello.fw
  // hello.boot: a number picked at random once per power-on, so a host can
  // tell the device restarted and stop waiting on what it had sent (§5).
  // 0 leaves it out.
  virtual uint32_t bootId() { return 0; }
  // Bluetooth, for dbg.ping: "off", "idle", "adv" or "conn", and the name
  // it advertises ("" for none).
  virtual const char* bleState() { return "off"; }
  virtual const char* bleName() { return ""; }
};

// A `do` as the app sees it (§3).
struct Do {
  uint32_t key = 0;        // unique since boot, never 0: what the app reports with
  int32_t id = 0;          // the host's id, 1..kMaxId; 0 when it had none (no `ended`)
  uint8_t what = 0;        // its name's index in the app's does()
  const char* name = "";   // its name: the app's own string
  Play play = Play::kNext;
  uint32_t ttl = kDefaultTtlMs;
  Link from = Link::kNone;  // where its `ended` goes
  JsonObjectConst args;     // the app's details (null reads as {}); valid only during the hook
};

// dbg.shot's picture (§7): its size and up to two runs of bytes, such as
// a palette and one index per pixel. The kit sends a header with their
// total length and CRC-32, then the bytes in base64 on one line. The runs
// must stay valid until the kit's next call.
struct Shot {
  uint16_t w = 0, h = 0;
  const uint8_t* data[2] = {nullptr, nullptr};
  size_t size[2] = {0, 0};
};

// What the queue looks like (dbg.state's `turn`, and for tests): the `do`
// playing at its head, then the ones waiting behind it.
struct QueueView {
  bool held = false;  // a `do` is playing
  uint32_t key = 0;
  int32_t id = 0;
  const char* name = "";
  bool resting = false;
  int waiting = 0;  // `do`s waiting, oldest first below
  struct Waiting {
    uint32_t key;
    int32_t id;
    const char* name;
    uint32_t leftMs;  // before it's `late`
  } wait[kMaxWaiting];
};

class Kit;

// The app: everything the device does with the host's messages. Only
// name, does, onState and onDo are required.
class App {
 public:
  virtual ~App() = default;

  // ---- hello (§3)
  virtual const char* name() const = 0;  // hello.app
  // hello.does: the do names it plays, at most kMaxDoes, as a static
  // array; the kit hands each `do` its index in it (Do::what).
  virtual int does(const char* const*& names) const = 0;
  // The app's own hello fields. The whole hello must fit in kMaxLine
  // bytes.
  virtual void hello(JsonObject extra) { (void)extra; }
  // The kit is attached (kit() works) and its clock is at 0.
  virtual void begin() {}

  // ---- the host's messages
  // A `state`: the app's whole map, sent every time (§3).
  virtual void onState(JsonObjectConst state, uint32_t t) = 0;
  // A `do` is about to start playing: a short lower-case reason ([a-z_],
  // §4) skips it (`skipped`, that reason) and leaves the one playing
  // alone; null lets it play. It may change the app's own state.
  virtual const char* refuse(const Do& c, uint32_t t) {
    (void)c, (void)t;
    return nullptr;
  }
  // The `do` starts playing, busy: play it. Report back with the kit's
  // rest, ended and cut, now or later.
  virtual void onDo(const Do& c, uint32_t t) = 0;

  // ---- time: always called in order of t (a tool may move the clock back)
  // Moves to t, handling the app's own timers.
  virtual void advance(uint32_t t) { (void)t; }
  // The first instant after `from`, at most `to`, at which the app will
  // rest or end the `do` playing by itself, so a `do` waiting starts at
  // that exact millisecond; false for none. Without it the queue moves at
  // the next tick.
  virtual bool nextDue(uint32_t from, uint32_t to, uint32_t& at) {
    (void)from, (void)to, (void)at;
    return false;
  }
  // Once per loop pass, after advance: read inputs, draw.
  virtual void tick(uint32_t t) { (void)t; }

  // ---- dbg.* over USB (§7)
  // A dbg.* type the kit doesn't handle: true if it's the app's, which
  // replies with Kit::reply. An unknown one gets no reply.
  virtual bool debug(const char* type, JsonObjectConst msg, Link from) {
    (void)type, (void)msg, (void)from;
    return false;
  }
  virtual void ping(JsonObject reply) { (void)reply; }             // dbg.ping's vitals
  virtual void state(JsonObject reply, uint32_t t) { (void)reply, (void)t; }  // dbg.state's fields
  // dbg.reset, after the queue's: forget the host's state (the clock is at 0).
  virtual void reset() {}
  // dbg.shot: the current frame; false when the app draws none.
  virtual bool shot(Shot& s, uint32_t t) {
    (void)s, (void)t;
    return false;
  }

 protected:
  Kit& kit() const { return *kit_; }

 private:
  friend class Kit;
  Kit* kit_ = nullptr;
};

class Kit {
 public:
  // The app must outlive the kit. The clock starts at 0, frozen (the
  // simulator and tests) or running (a board, whose randomness then starts
  // from the platform's bootId, §7).
  Kit(Platform& platform, App& app, bool frozenClock);
  Kit(const Kit&) = delete;
  Kit& operator=(const Kit&) = delete;

  // ---- the platform's side
  void setOut(Link link, Out* out);
  // One line from a link, without its newline. Returns true for a dbg.*
  // line: the caller ticks before the next line, since tools order their
  // input and clock steps against ticks.
  bool handleLine(const char* line, size_t n, Link from);
  // A host connected or disconnected over Bluetooth. USB has no such
  // event: a host is there while it has spoken in the last kHostGoneMs.
  void connected();
  void disconnected();
  // True when the Bluetooth host has sent no message for kHostGoneMs of real
  // time: let the link go so the device advertises again (§5). Then true
  // again only after another kHostGoneMs.
  bool shouldDrop();
  // Once per loop pass: hello's repeat, the clock's thaw, the queue's
  // timers, then the app's tick.
  void tick();

  // ---- the app's side
  uint32_t now() const { return clock_.now(platform_.realMs()); }
  bool frozen() const { return clock_.frozen(); }
  // Randomness reseeded when a tool freezes the clock, so frames repeat;
  // on a running board it starts from bootId, so each power-on differs.
  Rng& rng() { return rng_; }

  // The queue (§4). A report for a key that isn't playing is ignored.
  // A `why` is a short lower-case word ([a-z_]); the message escapes it anyway.
  void rest(uint32_t key);  // the `do` playing may be replaced now
  // The `do` playing is over: done, or cut (why says by what).
  void ended(uint32_t key, How how = How::kDone, const char* why = nullptr);
  void cut(const char* why);  // the app cuts the `do` playing
  // Every waiting `do` ends skipped, or only those that came in on
  // `only`: the host an input reached, when the input went to one link.
  void dropWaiting(const char* why, Link only = Link::kNone);
  QueueView queue() const;

  // Device → host. An `ev` of the app's `kind` (never "ended"), with what
  // the device already did about it and its details as a JSON object's
  // text (either may be null). `kind` and `did` are escaped as JSON
  // strings; `data` goes in the message as it is, so it must be an object's
  // JSON. A message longer than kMaxLine isn't sent. It goes on every live
  // link, or only over USB when a tool injected the input behind it (§3, §5).
  void emit(const char* kind, const char* did, const char* data, bool injected);
  // Something in hello changed: send it again on the host's link.
  void helloChanged();
  // The whole hello's length, the app's fields included (§3). One longer
  // than kMaxLine goes out with the kit's fields only, or not at all when
  // even those don't fit, and dbg.ping reports the length as `hello_long`.
  size_t helloLength();
  // One message to `to`, such as the reply to an app's dbg.* message.
  void reply(Link to, const char* text, size_t n);
  // Whether a link is live: for Bluetooth, connected; for USB, spoken on
  // in the last kHostGoneMs.
  bool live(Link l) const;

 private:
  struct LinkState {
    Out* out = nullptr;
    bool up = false;     // Bluetooth: connected
    bool heard = false;  // the host has spoken (since connecting, for Bluetooth)
    uint32_t heardReal = 0;  // real time it last did
    uint32_t quietReal = 0;  // Bluetooth: real time the quiet-link clock last started
    uint32_t helloReal = 0;  // real time hello last went out on it
  };
  struct Holder {
    uint32_t key = 0;
    int32_t id = 0;
    uint8_t what = 0;
    Link from = Link::kNone;
    bool resting = false;
  };
  struct Waiting {
    uint32_t key = 0;
    int32_t id = 0;
    uint8_t what = 0;
    Link from = Link::kNone;
    uint32_t at = 0, ttl = 0;  // arrived at, on the device clock
    uint8_t slot = 0;          // its args in args_
    uint16_t len = 0;
  };

  bool heard(Link from, uint32_t real);
  void fillHello(JsonDocument& d, bool kitOnly);
  void sendHello(Link to);
  void onDoLine(JsonObjectConst msg, Link from, uint32_t t);
  void offer(const Do& c, uint32_t t);
  void take(const Do& c, uint32_t t);
  void enqueue(const Do& c, uint32_t t);
  void pump(uint32_t t);
  void expire(uint32_t t);
  void advanceTo(uint32_t t);
  void step(uint32_t t);
  void forgetId(int32_t id);
  void removeWaiting(int i);
  void endHolder(How how, const char* why);
  void sendEnded(int32_t id, Link to, How how, const char* why);
  void sendPing(Link to);
  void sendState(Link to);
  void sendShot(Link to);
  void sendClock(Link to, JsonObjectConst msg, uint32_t real);
  void resetQueue();
  const char* nameOf(uint8_t what) const { return what < nDoes_ ? does_[what] : ""; }

  Platform& platform_;
  App& app_;
  Clock clock_;
  Rng rng_;
  LinkState links_[3];
  Link lastLink_ = Link::kNone;
  uint32_t dbgReal_ = 0;   // real time of the last dbg.* line
  bool toolFrozen_ = false;
  uint32_t rxState_ = 0, rxDo_ = 0;

  const char* const* does_ = nullptr;
  uint8_t nDoes_ = 0;

  uint32_t lastKey_ = 0;
  bool held_ = false;
  Holder holder_;
  Waiting waiting_[kMaxWaiting];
  int nWaiting_ = 0;
  char args_[kMaxWaiting][kMaxLine];  // waiting `do`s' args, as JSON
  uint8_t slotsUsed_ = 0;             // a bit per slot of args_
  uint32_t stepped_ = 0;              // the last instant the app was moved to
  bool pumping_ = false;
};

}  // namespace linkkit
