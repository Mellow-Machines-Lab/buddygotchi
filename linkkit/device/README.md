# LinkKit: the device library

Updated 2026-10-15. The C++ half of LinkKit, for the small device a host
app drives: it reads the host's messages, keeps track of the links, sends
`hello`, decides when each `do` plays (the queue), routes `ev` and answers
the kit's `dbg.*` messages, all as [../SPEC.md](../SPEC.md) says. What the
device draws, plays and says is yours: you write an app that plugs into
it. Boop's firmware is one; a lamp that fits on a page is below.

C++17 and ArduinoJson 7, single-threaded, fixed-size tables. The portable
part has no Arduino headers and runs on a Mac for tests and simulators;
the Bluetooth transport is built only on an ESP32 with NimBLE-Arduino.
It never includes an app's headers: its build fails if it does
(`tools/check_includes.py`, run as the library's `extraScript`).

## What's in it

| File (`src/linkkit/`) | What |
| --- | --- |
| `kit.h`, `kit.cpp` | `Kit`, `App`, `Platform`, `Do`: the protocol and the queue |
| `limits.h` | The spec's numbers (§9): 512-byte messages, 4 waiting, `ttl` 5000 and 1–60000, 60 s `hello`, 30 s host gone |
| `line_reader.h`, `packets.h` | Lines out of a byte stream, and lines into Bluetooth packets |
| `clock.h` | The device clock tools freeze and step (`dbg.clock`), and randomness reseeded with it (from the boot id on a running device's power-on) |
| `codec.h`, `codec.cpp` | CRC-32 and base64, for `dbg.shot` and an app's own debug messages |
| `ble.h`, `ble.cpp` | The Nordic UART peripheral (§8), `<Prefix>-XXXX`; empty off the ESP32 |

## How an app plugs in

The board (or a simulator) owns three things: a `Platform` (a millisecond
counter, the device's id and firmware version), your `App`, and a `Kit`
made from both. It feeds the kit every line from each link and calls
`tick()` once per loop pass; the kit calls your app back. `handleLine`
returns true for a `dbg.*` message: tick before the next line, since tools
time their input and clock steps against ticks.

| Your app's hook | When the kit calls it |
| --- | --- |
| `name()`, `does(names)`, `hello(extra)` | For `hello`: `app`, the `do` names you play, your own fields |
| `begin()` | Once, attached, with the clock at 0 |
| `onState(state, t)` | Every `state`: your whole map |
| `refuse(d, t)` | A `do` is about to start playing: return a short reason to skip it, or null |
| `onDo(d, t)` | The `do` starts playing, busy: play it. `d.args` is yours, `d.key` is what you report with |
| `advance(t)`, `nextDue(from, to, at)` | Time moves on (in order). `nextDue` says when you'll rest or end the `do` playing by yourself, so a `do` waiting starts at that exact millisecond |
| `tick(t)` | Once per pass, after `advance`: read inputs, draw |
| `debug(type, msg, from)`, `ping(obj)`, `state(obj, t)`, `reset()`, `shot(s, t)` | Your `dbg.*` types, your vitals and `dbg.state` fields, `dbg.reset`, and the frame `dbg.shot` sends |

And what your app calls on `kit()`, from inside any hook: `rest(key)`
(the `do` playing may be replaced now), `ended(key, how, why)` (it's over),
`cut(why)` (you cut the `do` playing: a button, a tap), `dropWaiting(why, only)`
(every `do` waiting, or only those from link `only`),
`emit(kind, did, data, injected)` (an `ev` to every live link, or only to
USB for a tool's injected input), `helloChanged()`, `reply(link, text, n)`
for your `dbg.*` replies, and `now()`, `rng()`, `frozen()`. A report for
a key that isn't playing is ignored, so each `do` gets exactly
one `ended` however your layers overlap.

### A lamp

`examples/lamp/lamp.h`, without its opening comment; the unit tests run it
(`test/test_kit`):

```cpp
namespace lamp {

class Lamp : public linkkit::App {
 public:
  static constexpr uint32_t kBlinkMs = 200;

  const char* name() const override { return "lamp"; }
  int does(const char* const*& names) const override {
    static const char* const kDoes[] = {"blink"};
    names = kDoes;
    return 1;
  }

  void onState(JsonObjectConst state, uint32_t) override { level_ = state["level"] | 0; }

  // Busy while it blinks: a `next` blink waits in the queue, a `now` one cuts it.
  void onDo(const linkkit::Do& c, uint32_t t) override {
    int times = c.args["times"] | 1;
    times = times < 1 ? 1 : times > 10 ? 10 : times;
    blinking_ = c.key;
    until_ = t + kBlinkMs * uint32_t(times);
    at_ = t;
  }
  void advance(uint32_t t) override {
    if (blinking_ && int32_t(t - until_) >= 0) kit().ended(blinking_), blinking_ = 0;
  }
  // So a blink waiting starts the millisecond this one ends.
  bool nextDue(uint32_t from, uint32_t to, uint32_t& at) override {
    if (!blinking_ || int32_t(until_ - from) <= 0 || int32_t(until_ - to) > 0) return false;
    at = until_;
    return true;
  }
  void tick(uint32_t t) override {
    light_ = blinking_ && (t - at_) / (kBlinkMs / 2) % 2 == 0 ? 255 : level_;
  }

  // The lamp's own button: the device does this itself, so it doesn't
  // go through the queue; it cuts the blink and tells the host.
  void press() {
    if (blinking_) kit().cut("button"), blinking_ = 0;
    kit().emit("press", "stopped", nullptr, false);
  }
  uint8_t light() const { return light_; }

 private:
  uint8_t level_ = 0, light_ = 0;
  uint32_t blinking_ = 0;  // the `do` blinking, 0 for none
  uint32_t until_ = 0, at_ = 0;
};

}  // namespace lamp
```

On an ESP32 (Arduino), the loop around it:

```cpp
linkkit::Ble ble;
struct SerialOut : linkkit::Out {
  void write(const char* s, size_t n) override { Serial.write((const uint8_t*)s, n); }
};
struct Board : linkkit::Platform {
  uint32_t realMs() override { return millis(); }
  const char* deviceId() override { return ble.id(); }
  const char* fwVersion() override { return "1.0.0"; }
  uint32_t bootId() override {  // once per power-on, never 0
    static const uint32_t id = esp_random() | 1;
    return id;
  }
};

Board board;
lamp::Lamp app;
linkkit::Kit kit(board, app, /*frozenClock=*/false);
SerialOut usb;
linkkit::LineReader line;

void setup() {
  Serial.begin(460800);
  kit.setOut(linkkit::Link::kUsb, &usb);
  if (ble.begin("Lamp", "lamp")) kit.setOut(linkkit::Link::kBle, &ble);  // Lamp-XXXX
}
void loop() {
  while (Serial.available())  // every message waiting, until a dbg.* one
    if (line.feed(char(Serial.read())) && kit.handleLine(line.line(), line.length(), linkkit::Link::kUsb)) break;
  ble.poll(kit);  // connects, drops a quiet link, and one message from Bluetooth
  kit.tick();
}
```

A host sends `{"t":"state","level":40}`, the lamp answers `hello`, and
`{"t":"do","id":1,"name":"blink","args":{"times":2}}` blinks it twice,
then `{"t":"ev","kind":"ended","data":{"id":1,"how":"done"}}`. A second
`blink` sent meanwhile waits and starts the millisecond the first ends.

## The queue, from the app's side

A `do` plays from `onDo` until you `ended` it (or the kit ends it: a
`now` one cuts it while busy, `dbg.reset`). Call `rest(key)` when the
part that matters is over: from then anything may replace it, and it
ends `done`. Things the device does on its own (a tap's reflex, a held
button) don't go through the queue; cut the `do` playing only when you
actually cut it. `refuse` is asked right before a `do` would start
playing, so it can look at what's on screen then; it may change your own
state (Boop's reply ends listening even when it's refused). `do`s
waiting keep their own copy of `args` (512 bytes each, 2 KB in all),
parsed again when they start.

## Building and testing

Add it to a PlatformIO env with ArduinoJson 7 (and NimBLE-Arduino on the
board, for `Ble`):

```ini
lib_deps =
    symlink://../linkkit/device
    bblanchon/ArduinoJson @ ^7.0.0
```

Boop's firmware does that in both its envs, the board's and the Mac's
(its unit tests and simulator).

The library tests on its own, on the Mac, from its own PlatformIO
project (`platformio.ini` here, which apps don't use): `test/test_queue`
(every rule of §4), `test/test_kit` (messages, `hello`, links, `ev`, the
app's words escaped, `dbg.*`, the lamp) and `test/test_helpers` (lines
out of bytes and into Bluetooth packets, CRC-32 and base64, the clock),
with a fake platform and app (`test/kit_fakes.h`):

```sh
pio test -d linkkit/device -e native          # the kit's own tests
python3 linkkit/device/tools/check_includes.py   # the include check, by itself
```

In Boop's checkout, `make -C internal fw-test` runs these after Boop's
own suites, with the PlatformIO that keeps its packages in the checkout.
To run only the kit's tests that way, give `firmware/tools/pio.sh` an
absolute path, since it runs from `firmware/`:

```sh
firmware/tools/pio.sh test -d "$PWD/linkkit/device" -e native
```
