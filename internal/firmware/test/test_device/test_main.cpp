// Boop on LinkKit, line in and line out: its vocabulary,
// its rules for the turn, the debug channel and inputs, through the same
// Hal the simulator uses.
#include <unity.h>

#include "pack_file.h"  // internal/firmware/

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "app/device.h"
#include "linkkit/kit.h"
#include "linkkit/line_reader.h"
#include "render/palette.h"
#include "render/pixel/scene.h"
#include "render/pixel/effect_track.h"
#include "render/pixel/sounds.h"

void setUp() {}
void tearDown() {}

namespace {

struct FakeHal : app::Hal {
  uint32_t real = 0;
  bool boot = false;
  uint32_t led = 0;
  uint8_t bl = 255;
  uint32_t realMs() override { return real; }
  void setBacklight(uint8_t level) override { bl = level; }
  bool bootDown() override { return boot; }
  void setLed(uint32_t rgb) override { led = rgb; }
  const char* fwVersion() override { return "t"; }
  const char* gitSha() override { return "abc"; }
  std::vector<voice::Line> said;
  int hushes = 0;
  void say(const voice::Line& l) override { said.push_back(l); }
  void hush() override { ++hushes; }
  std::vector<voice::Effect> effects;
  int effectStops = 0;
  void effect(const voice::Effect& e) override { effects.push_back(e); }
  void stopEffects() override { ++effectStops; }
  bool touching = false;  // the panel, at the middle of the face
  bool touch(int& x, int& y) override {
    if (touching) x = 160, y = 100;
    return touching;
  }
  app::TouchCal cal;
  void setTouchCal(const app::TouchCal& c) override { cal = c; }
  app::TouchCal touchCal() override { return cal; }
  bool packOk = false;  // dbg.card's `end` swaps a pack in
  bool packEnd(uint32_t, uint32_t, const char*& why) override { return why = "no card", packOk; }
};

struct Capture : linkkit::Out {
  std::string text;
  void write(const char* s, size_t n) override { text.append(s, n); }
};

struct Rig {
  FakeHal hal;
  Capture usb, ble;
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(render::kWidth) * render::kHeight);
  app::Device dev{hal, px.data()};
  linkkit::Kit kit{hal, dev, true};
  Rig() {
    kit.setOut(linkkit::Link::kUsb, &usb);
    kit.setOut(linkkit::Link::kBle, &ble);
    kit.tick();
  }
  void usbLine(const char* s) {
    kit.handleLine(s, std::strlen(s), linkkit::Link::kUsb);
    kit.tick();
  }
  void bleLine(const char* s) { kit.handleLine(s, std::strlen(s), linkkit::Link::kBle); }
  // A pixel of the frame the board would push.
  uint8_t at(int x, int y) const { return px[size_t(y) * render::kWidth + x]; }
  // What's on the screen, as dbg.state says.
  std::string screen() {
    usbLine("{\"t\":\"dbg.state\"}");
    size_t i = usb.text.rfind("\"screen\":\"") + 10;
    return usb.text.substr(i, usb.text.find('"', i) - i);
  }
};

bool has(const std::string& s, const char* needle) { return s.find(needle) != std::string::npos; }
bool has(const std::string& s, const std::string& needle) { return s.find(needle) != std::string::npos; }

// Runs the frozen clock from `from` to `to` in 10 ms steps, ticking each.
void runClock(Rig& r, uint32_t from, uint32_t to) {
  for (uint32_t t = from; t <= to; t += 10) {
    char step[64];
    std::snprintf(step, sizeof(step), "{\"t\":\"dbg.clock\",\"freeze\":%u}", unsigned(t));
    r.usbLine(step);
  }
}

bool played(const FakeHal& h, const char* clip) {
  for (const voice::Effect& e : h.effects)
    if (e.clip == render::pixel::clips().index(clip)) return true;
  return false;
}

}  // namespace

static void test_ping_reports_version_and_link() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"sha\":\"abc\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"link\":\"none\""));  // dbg.* doesn't count as the Mac
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"link\":\"usb\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"w\":320,\"h\":240"));  // the screen, for boopctl calibrate
}

static void test_touch_calibration_maps_raw_to_screen() {
  // Raw y runs 250 → 3750 across the width, raw x 3800 → 300 down the height.
  app::TouchCal c;
  c.bx = int32_t(320.0 / 3500 * 65536), c.cx = int32_t(-250 * 320.0 / 3500 * 65536);
  c.ay = int32_t(-240.0 / 3500 * 65536), c.cy = int32_t(3800 * 240.0 / 3500 * 65536);
  int x, y;
  c.map(3800, 250, x, y);
  TEST_ASSERT_INT_WITHIN(1, 0, x);
  TEST_ASSERT_INT_WITHIN(1, 0, y);
  c.map(2050, 2000, x, y);
  TEST_ASSERT_INT_WITHIN(1, 160, x);
  TEST_ASSERT_INT_WITHIN(1, 120, y);
  c.map(0, 4095, x, y);  // past the edge: clamped to the screen
  TEST_ASSERT_EQUAL(319, x);
  TEST_ASSERT_EQUAL(239, y);
}

// The default map turns with the picture. Raw (x_min, y_min) is the panel's
// own top-left pixel (portrait, USB-C at the bottom), and raw y runs down
// the panel's 320 px side, towards USB-C.
static void test_default_touch_map_follows_the_rotation() {
  const int lo = app::kTouchRawMin, hi = app::kTouchRawMax;
  int x, y;
  // Rotation 1, USB-C on the right (a quarter turn anticlockwise from
  // portrait): the panel's top-left is the screen's bottom-left, and the
  // USB-C end is the right edge.
  app::TouchCal r1 = app::defaultTouchCal(1);
  TEST_ASSERT_TRUE(r1.valid);
  r1.map(lo, lo, x, y);
  TEST_ASSERT_INT_WITHIN(1, 0, x);
  TEST_ASSERT_INT_WITHIN(1, 239, y);
  r1.map(hi, lo, x, y);  // the panel's top-right: the screen's top-left
  TEST_ASSERT_INT_WITHIN(1, 0, x);
  TEST_ASSERT_INT_WITHIN(1, 0, y);
  r1.map(lo, hi, x, y);  // the panel's bottom-left, by USB-C: the bottom-right
  TEST_ASSERT_INT_WITHIN(1, 319, x);
  TEST_ASSERT_INT_WITHIN(1, 239, y);
  r1.map((lo + hi) / 2, (lo + hi) / 2, x, y);
  TEST_ASSERT_INT_WITHIN(1, 160, x);
  TEST_ASSERT_INT_WITHIN(1, 120, y);
  // Rotation 3, USB-C on the left (a quarter turn clockwise): the panel's
  // top-left is the screen's top-right.
  app::TouchCal r3 = app::defaultTouchCal(3);
  r3.map(lo, lo, x, y);
  TEST_ASSERT_INT_WITHIN(1, 319, x);
  TEST_ASSERT_INT_WITHIN(1, 0, y);
  r3.map(lo, hi, x, y);
  TEST_ASSERT_INT_WITHIN(1, 0, x);
  TEST_ASSERT_INT_WITHIN(1, 0, y);
  r3.map(hi, hi, x, y);
  TEST_ASSERT_INT_WITHIN(1, 0, x);
  TEST_ASSERT_INT_WITHIN(1, 239, y);
}

// A calibration is kept with the screen it was fitted on; one fitted on
// another screen (the portrait build's) or another rotation is ignored.
static void test_saved_touch_calibration_must_match_the_screen() {
  app::TouchCal c;
  c.ax = 11, c.bx = 22, c.cx = 33, c.ay = 44, c.by = 55, c.cy = 66, c.valid = true;
  app::SavedTouchCal saved = app::saveTouchCal(c, 1);
  TEST_ASSERT_EQUAL(320, saved.w);
  TEST_ASSERT_EQUAL(240, saved.h);
  app::TouchCal out;
  TEST_ASSERT_TRUE(app::loadTouchCal(&saved, sizeof(saved), 1, out));
  TEST_ASSERT_EQUAL(11, out.ax);
  TEST_ASSERT_EQUAL(66, out.cy);
  TEST_ASSERT_TRUE(out.valid);

  app::TouchCal none;
  TEST_ASSERT_FALSE(app::loadTouchCal(&saved, sizeof(saved), 3, none));  // kRotation flipped since
  TEST_ASSERT_FALSE(none.valid);
  app::SavedTouchCal portrait = saved;
  portrait.w = 240, portrait.h = 320, portrait.rotation = 0;
  TEST_ASSERT_FALSE(app::loadTouchCal(&portrait, sizeof(portrait), 1, none));
  // The portrait build stored the bare map, with no screen: a different size.
  TEST_ASSERT_FALSE(app::loadTouchCal(&c, sizeof(c), 1, none));
  TEST_ASSERT_FALSE(app::loadTouchCal(&saved, 0, 1, none));
  TEST_ASSERT_FALSE(app::loadTouchCal(nullptr, sizeof(saved), 1, none));
  app::SavedTouchCal cleared = app::saveTouchCal(app::TouchCal{}, 1);
  TEST_ASSERT_FALSE(app::loadTouchCal(&cleared, sizeof(cleared), 1, none));
  TEST_ASSERT_FALSE(none.valid);
}

static void test_touchcal_sets_reads_and_clears() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.touchcal\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"cal\":null"));
  r.usbLine("{\"t\":\"dbg.touchcal\",\"set\":[-4494,0,15630336,0,5991,-1497965]}");
  TEST_ASSERT_TRUE(r.hal.cal.valid);
  TEST_ASSERT_EQUAL(-4494, r.hal.cal.ax);
  TEST_ASSERT_EQUAL(-1497965, r.hal.cal.cy);
  TEST_ASSERT_TRUE(has(r.usb.text, "\"cal\":[-4494,0,15630336,0,5991,-1497965]"));
  r.usbLine("{\"t\":\"dbg.touchcal\",\"clear\":true}");
  TEST_ASSERT_FALSE(r.hal.cal.valid);
}

static void test_pattern_target_draws_a_cross() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.pattern\",\"target\":[20,220]}");  // bottom left, as boopctl calibrate puts it
  TEST_ASSERT_EQUAL(render::kAmber, r.at(20, 220));
  TEST_ASSERT_EQUAL(render::kAmber, r.at(29, 220));
  TEST_ASSERT_EQUAL(render::kAmber, r.at(20, 211));
  TEST_ASSERT_EQUAL(render::kAmber, r.at(20, 229));
  TEST_ASSERT_EQUAL(render::kBlack, r.at(40, 200));
  TEST_ASSERT_EQUAL(render::kBlack, r.at(160, 120));
  r.usbLine("{\"t\":\"dbg.pattern\",\"target\":[300,20]}");  // top right
  TEST_ASSERT_EQUAL(render::kAmber, r.at(300, 20));
  TEST_ASSERT_EQUAL(render::kAmber, r.at(310, 20));
  TEST_ASSERT_EQUAL(render::kBlack, r.at(20, 220));
  r.usbLine("{\"t\":\"dbg.pattern\",\"target\":[2147483647,-9]}");  // off the screen: kept on it
  TEST_ASSERT_EQUAL(render::kAmber, r.at(319, 0));
}

static void test_debug_is_ignored_over_ble() {
  Rig r;
  r.kit.handleLine("{\"t\":\"dbg.ping\"}", 16, linkkit::Link::kBle);
  TEST_ASSERT_TRUE(r.ble.text.empty());
}

static int count(const std::string& s, const char* needle) {
  int n = 0;
  for (size_t at = s.find(needle); at != std::string::npos; at = s.find(needle, at + 1)) ++n;
  return n;
}

// linkkit/SPEC.md §3, §5: Boop's hello, sent in answer
// to the Mac's first line on a link, not at connect, then every 60 s on
// the Mac's link. It names the voice pack on its card, which the Mac
// checks, and fits in one line.
static void test_hello_on_the_first_line_and_every_minute() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.hal.real = 1000;
  r.kit.connected();
  TEST_ASSERT_FALSE(has(r.ble.text, "\"hello\""));  // nothing at connect
  r.bleLine("{\"t\":\"state\",\"base\":\"idle\"}");
  std::string hello = std::string(
                          "{\"t\":\"hello\",\"kit\":1,\"app\":\"boop\",\"id\":\"b00p-0000\",\"fw\":\"t\",\"does\":["
                          "\"react\",\"task_complete\",\"reply_ready\",\"starting\",\"stopped\",\"error\",\"helper_return\","
                          "\"listening\",\"stop_listening\",\"poked\",\"tap_spam\"],\"voice\":\"") +
                      voice::assetsVersion() + "\",\"face\":\"pixel\"}\n";
  TEST_ASSERT_EQUAL(12, int(std::strlen(voice::assetsVersion())));
  TEST_ASSERT_EQUAL_STRING(hello.c_str(), r.ble.text.c_str());
  TEST_ASSERT_TRUE(hello.size() - 1 <= linkkit::kMaxLine);
  TEST_ASSERT_EQUAL(int(hello.size() - 1), int(r.kit.helloLength()));  // so it goes whole
  r.hal.real = 60999;
  r.kit.tick();
  TEST_ASSERT_EQUAL_INT(1, count(r.ble.text, "\"hello\""));
  r.hal.real = 61000;
  r.kit.tick();
  TEST_ASSERT_EQUAL_INT(2, count(r.ble.text, "\"hello\""));
  // Input goes to the Mac on Bluetooth; nothing leaks onto USB.
  r.hal.boot = true;
  r.kit.tick();
  r.hal.boot = false;
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":100}");
  TEST_ASSERT_TRUE(has(r.ble.text, "{\"t\":\"ev\",\"kind\":\"tap\",\"did\":\"poked\"}\n"));
  TEST_ASSERT_FALSE(has(r.usb.text, "\"kind\":\"tap\""));
  TEST_ASSERT_FALSE(has(r.usb.text, "\"hello\""));
  r.kit.disconnected();
  r.hal.real = 200000;
  r.kit.tick();
  TEST_ASSERT_EQUAL_INT(2, count(r.ble.text, "\"hello\""));
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"link\":\"none\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"ble\":\"off\""));
}

// A new voice pack on the card changes hello's `voice`,
// so hello goes again, on the Mac's link.
static void test_hello_again_when_the_pack_changes() {
  Rig r;
  r.hal.packOk = true;
  r.kit.connected();
  r.bleLine("{\"t\":\"state\",\"base\":\"idle\"}");
  TEST_ASSERT_EQUAL_INT(1, count(r.ble.text, "\"hello\""));
  r.usbLine("{\"t\":\"dbg.card\",\"op\":\"end\",\"size\":0,\"crc\":0}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"dbg.card\",\"op\":\"end\",\"ok\":true,"));
  TEST_ASSERT_EQUAL_INT(2, count(r.ble.text, "\"hello\""));
  TEST_ASSERT_FALSE(has(r.usb.text, "\"hello\""));  // the tool isn't the Mac
}

// A real press goes to every live Mac link. A tool's
// do over USB while the app is on Bluetooth (boopctl takes) doesn't
// take the taps away from the app; USB gets a copy while
// the Mac spoke there in the last 30 s.
static void test_input_reaches_every_live_link() {
  Rig r;
  auto step = [&](int ms) {
    std::string s = "{\"t\":\"dbg.clock\",\"step\":" + std::to_string(ms) + "}";
    r.usbLine(s.c_str());
  };
  auto press = [&](int ms, int every) {  // BOOT, held for `ms`
    step(50);  // past BOOT's debounce
    r.hal.boot = true;
    r.kit.tick();
    for (int at = every; at <= ms; at += every) step(every);
    r.hal.boot = false;
    step(every);
  };
  const char* tap = "{\"t\":\"ev\",\"kind\":\"tap\",";  // with what it did
  const char* talkOn = "{\"t\":\"ev\",\"kind\":\"talk_on\",\"did\":\"listening\"}\n";
  const char* talkOff = "{\"t\":\"ev\",\"kind\":\"talk_off\"}\n";
  r.kit.connected();
  r.bleLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.hal.real = 1000;
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}");
  press(100, 100);  // a tap
  press(800, 500);  // a hold: push-to-talk, and no tap
  for (const std::string* out : {&r.ble.text, &r.usb.text}) {
    TEST_ASSERT_EQUAL_INT(1, count(*out, tap));
    TEST_ASSERT_EQUAL_INT(1, count(*out, "{\"t\":\"ev\",\"kind\":\"tap\",\"did\":\"poked\"}\n"));
    TEST_ASSERT_EQUAL_INT(1, count(*out, talkOn));
    TEST_ASSERT_EQUAL_INT(1, count(*out, talkOff));
  }
  // 30 s after the tool's last word, only Bluetooth hears.
  r.hal.real = 31000;
  press(100, 100);
  TEST_ASSERT_EQUAL_INT(2, count(r.ble.text, tap));
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, tap));
  // Listening still waits for the reply, so that tap only dipped the face.
  TEST_ASSERT_TRUE(has(r.ble.text, "{\"t\":\"ev\",\"kind\":\"tap\",\"did\":\"dip\"}\n"));
  // Disconnected, Bluetooth hears nothing more.
  r.kit.disconnected();
  press(100, 100);
  TEST_ASSERT_EQUAL_INT(2, count(r.ble.text, tap));
}

// Input a tool injects (dbg.press, dbg.touch) goes back
// only over USB, where the tool is, even while the everyday app is on
// Bluetooth, so a test run never reaches the everyday app, or its mic: a
// held dbg.press is push-to-talk on USB alone.
static void test_injected_input_stays_on_usb() {
  Rig r;
  const char* tap = "{\"t\":\"ev\",\"kind\":\"tap\",";
  r.kit.connected();
  r.bleLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.reset\"}");
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":800}");
  for (int ms = 0; ms <= 900; ms += 10) r.usbLine("{\"t\":\"dbg.clock\",\"step\":10}");
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, "{\"t\":\"ev\",\"kind\":\"talk_on\",\"did\":\"listening\"}\n"));
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, "{\"t\":\"ev\",\"kind\":\"talk_off\"}\n"));
  r.usbLine("{\"t\":\"do\",\"name\":\"stop_listening\",\"play\":\"now\"}");  // the tool's reply
  r.usbLine("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100}");
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":200}");
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, tap));
  TEST_ASSERT_FALSE(has(r.ble.text, "\"kind\":\"t"));  // no tap, talk_on or talk_off
  // With only dbg.* traffic from the tool, too.
  r.hal.real = 60000;
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":100}");
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":200}");
  TEST_ASSERT_EQUAL_INT(2, count(r.usb.text, tap));
  TEST_ASSERT_FALSE(has(r.ble.text, "\"kind\":\"t"));
}

// linkkit/SPEC.md §5: USB has no connect event: the Mac's first word, or
// its first after 30 s of silence, gets a hello; and so does the Mac's own
// hello, which it sends first on every connect, so a Mac relaunched within
// the 30 s hears one too.
static void test_usb_hello_when_the_mac_first_speaks() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_FALSE(has(r.usb.text, "\"hello\""));  // tools don't count
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, "\"hello\""));
  r.hal.real = 20000;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, "\"hello\""));
  r.hal.real = 50000;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  TEST_ASSERT_EQUAL_INT(2, count(r.usb.text, "\"hello\""));
  r.hal.real = 55000;  // the app relaunched: hello, then its state
  r.usbLine("{\"t\":\"hello\"}");
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  TEST_ASSERT_EQUAL_INT(3, count(r.usb.text, "{\"t\":\"hello\",\"kit\":1,\"app\":\"boop\","));
}

// Reconnecting: a Bluetooth link with no line from the
// Mac for 30 s is dropped, and if that didn't take, dropped again 30 s
// later. USB has no connection to let go, so only Bluetooth is checked.
static void test_a_quiet_link_is_dropped_after_30_s() {
  TEST_ASSERT_EQUAL_UINT32(30000, linkkit::kHostGoneMs);
  Rig r;
  TEST_ASSERT_FALSE(r.kit.shouldDrop());  // not connected
  r.hal.real = 1000;
  r.kit.connected();
  r.hal.real = 30999;
  TEST_ASSERT_FALSE(r.kit.shouldDrop());
  r.hal.real = 20000;
  r.bleLine("{\"t\":\"state\",\"base\":\"idle\"}");  // the Mac's 10 s keepalive
  r.hal.real = 49999;
  TEST_ASSERT_FALSE(r.kit.shouldDrop());
  r.hal.real = 50000;
  TEST_ASSERT_TRUE(r.kit.shouldDrop());
  r.hal.real = 50001;
  TEST_ASSERT_FALSE(r.kit.shouldDrop());
  r.hal.real = 80000;
  TEST_ASSERT_TRUE(r.kit.shouldDrop());
  r.kit.disconnected();
  r.hal.real = 200000;
  TEST_ASSERT_FALSE(r.kit.shouldDrop());
  r.hal.real = 0xFFFFF000u;  // millis() wraps
  r.kit.connected();
  r.hal.real = 0x00001000u;
  TEST_ASSERT_FALSE(r.kit.shouldDrop());
  r.hal.real = 0xFFFFF000u + 30000;
  TEST_ASSERT_TRUE(r.kit.shouldDrop());
}

static void test_pattern_until_next_state() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.pattern\"}");
  TEST_ASSERT_EQUAL_STRING("pattern", r.screen().c_str());
  TEST_ASSERT_TRUE(r.dev.takeFrame());
  r.usbLine("{\"t\":\"state\",\"base\":\"working\"}");
  TEST_ASSERT_EQUAL_STRING("face", r.screen().c_str());
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"working\""));
}

// `state` carries the mood, and like every field it's a
// snapshot: a state without one, or with one the device doesn't know, is
// happy again.
static void test_state_carries_the_mood() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"mood\":\"happy\""));
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"mood\":\"determined\"}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"working\",\"act\":null,\"mood\":\"determined\""));
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"mood\":\"sulky\"}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"mood\":\"happy\""));
  r.usbLine("{\"t\":\"state\",\"mood\":\"sad\"}");
  r.usbLine("{\"t\":\"state\",\"base\":\"napping\"}");  // a base it doesn't know is idle
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"idle\",\"act\":null,\"mood\":\"happy\""));
}

static void test_injected_tap_reaches_the_mac() {
  Rig r;
  r.usbLine("{\"t\":\"state\"}");  // the Mac is on USB
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":100}");
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":100}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"tap\",\"did\":\"poked\"}\n"));
}

// A tap while the brain's finish names whose turn it was
// only dips the face and carries that call's id, the thread the Mac
// opens; the finish plays on.
static void test_a_tap_on_a_named_finish_carries_its_id() {
  Rig r;
  r.usbLine("{\"t\":\"state\"}");
  r.usbLine("{\"t\":\"do\",\"id\":42,\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\","
            "\"who\":{\"agent\":\"claude\",\"thread\":\"fix-nav\"}}}");
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":100}");
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":100}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"tap\",\"did\":\"dip\",\"data\":{\"on\":42}}\n"));
  TEST_ASSERT_FALSE(has(r.usb.text, "\"kind\":\"ended\""));  // not cut
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"anim\":\"task_complete\""));
}

// The resistive panel misses readings under a light press, so a
// panel touch ends only after 50 ms without contact. A press that flickers
// is one tap; a new press after a real lift is another.
static void test_a_flickering_touch_is_one_tap() {
  TEST_ASSERT_EQUAL_UINT32(50, app::Device::kTouchReleaseMs);
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
  const char* tap = "{\"t\":\"ev\",\"kind\":\"tap\",";
  for (uint32_t ms = 0; ms < 300; ms += 2) {  // 10 ms in contact, 10 ms not; last contact at 288
    r.hal.real = ms;
    r.hal.touching = ms / 10 % 2 == 0;
    r.kit.tick();
  }
  r.hal.touching = false;
  r.hal.real = 337;
  r.kit.tick();
  TEST_ASSERT_EQUAL_INT(0, count(r.usb.text, tap));
  r.hal.real = 338;
  r.kit.tick();
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, tap));
  r.hal.real = 400;
  r.hal.touching = true;
  r.kit.tick();
  r.hal.real = 450;
  r.hal.touching = false;
  r.kit.tick();
  r.hal.real = 500;
  r.kit.tick();
  TEST_ASSERT_EQUAL_INT(2, count(r.usb.text, tap));
}

// The 50 ms runs on real time, so a panel touch still ends, and
// taps at once, while a tool has the clock frozen.
static void test_a_touch_ends_while_the_clock_is_frozen() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1000}");
  const char* tap = "{\"t\":\"ev\",\"kind\":\"tap\",";
  for (uint32_t ms = 200; ms <= 400; ms += 5) {
    r.hal.real = ms;
    r.hal.touching = ms < 300;  // last contact at 295
    r.kit.tick();
    if (ms == 340) {
      TEST_ASSERT_EQUAL_INT(0, count(r.usb.text, tap));
      r.usbLine("{\"t\":\"dbg.state\"}");
      TEST_ASSERT_TRUE(has(r.usb.text, "\"touch\":{\"down\":true"));
    }
  }
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, tap));
  TEST_ASSERT_EQUAL_UINT32(1000, r.kit.now());  // still frozen
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"touch\":{\"down\":false"));
}

// BOOT held is push-to-talk: talk_on once it has been down
// 400 ms, with listening on screen at once, and talk_off on release, with
// no tap. Listening then waits for the reply.
static void test_a_physical_hold_is_push_to_talk() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.usbLine("{\"t\":\"state\"}");
  r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
  r.hal.boot = true;
  r.kit.tick();
  r.hal.real = 399;
  r.kit.tick();
  TEST_ASSERT_FALSE(has(r.usb.text, "\"t\":\"ev\""));
  r.hal.real = 400;
  r.kit.tick();
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, "\"t\":\"ev\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"talk_on\",\"did\":\"listening\"}\n"));
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":{\"anim\":\"listening\""));
  r.hal.real = 2000;
  r.kit.tick();
  r.hal.boot = false;
  r.hal.real = 2100;
  r.kit.tick();
  TEST_ASSERT_EQUAL_INT(2, count(r.usb.text, "\"t\":\"ev\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"talk_off\"}\n"));
  TEST_ASSERT_FALSE(has(r.usb.text, "\"kind\":\"tap\""));
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":{\"anim\":\"listening\",\"left_ms\":8000,"));
  // The reply, a line, ends it and plays.
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"},\"mood\":\"proud\"}}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"take\":\"previous.go\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"expr\":\"proud\""));
}

// The Mac's own `listening` shows the design it names, or
// one the device picks when it names none it has, never the last one;
// stop_listening ends it.
static void test_the_macs_listening_and_the_empty_moment() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"do\",\"name\":\"listening\",\"play\":\"now\",\"args\":{\"variant\":3}}");
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":{\"anim\":\"listening\",\"left_ms\":38000,\"variant\":3}"));
  r.usbLine("{\"t\":\"do\",\"name\":\"stop_listening\",\"play\":\"now\"}");
  r.usbLine("{\"t\":\"do\",\"name\":\"listening\",\"play\":\"now\",\"args\":{\"variant\":9}}");  // happy has three: not the last
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":{\"anim\":\"listening\",\"left_ms\":38000,\"variant\":"));
  TEST_ASSERT_FALSE(has(r.usb.text, "\"variant\":3}"));
  r.usbLine("{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\"}}");  // refused while listening
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"anim\":\"listening\""));
  r.usbLine("{\"t\":\"do\",\"name\":\"stop_listening\",\"play\":\"now\"}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
}

// A clock a tool froze runs again after 60 s with no
// dbg.* message, from where it stopped, so a tool that dies mid-run can't
// leave the board still: no-app, blinks and BOOT all need a moving clock.
// Traffic from the Mac doesn't count; the simulator's own start stays frozen.
static void test_a_frozen_clock_runs_again_after_60s_without_debug() {
  Rig r;
  r.hal.real = 100000;
  r.kit.tick();
  TEST_ASSERT_EQUAL_UINT32(0, r.kit.now());  // started frozen: not a tool's doing
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":5000}");
  r.hal.real = 130000;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.hal.real = 159999;
  r.kit.tick();
  TEST_ASSERT_EQUAL_UINT32(5000, r.kit.now());
  r.hal.real = 160000;
  r.kit.tick();
  r.hal.real = 160250;
  TEST_ASSERT_EQUAL_UINT32(5250, r.kit.now());
  // dbg.reset freezes it too, and any dbg.* message holds it another 60 s.
  r.usbLine("{\"t\":\"dbg.reset\"}");
  r.hal.real = 200000;
  r.usbLine("{\"t\":\"dbg.state\"}");
  r.hal.real = 259999;
  r.kit.tick();
  TEST_ASSERT_EQUAL_UINT32(0, r.kit.now());
  r.hal.real = 260000;
  r.kit.tick();
  r.hal.real = 261000;
  TEST_ASSERT_EQUAL_UINT32(1000, r.kit.now());
}

static void test_shot_is_header_then_base64() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.shot\"}");
  size_t nl = r.usb.text.find('\n');
  TEST_ASSERT_TRUE(has(r.usb.text.substr(0, nl), "\"bytes\":77312"));
  std::string body = r.usb.text.substr(nl + 1);
  TEST_ASSERT_EQUAL_UINT32(77312 / 3 * 4 + 4 + 1, body.size());  // padded, plus the newline
}

// dbg.light holds the backlight until the next state.
// dbg.clock may move a frozen clock back, even while an animation plays:
// the device carries on at once (it used to spin in the sound effects),
// and the face is the look again.
static void test_the_clock_can_go_back_mid_animation() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":9001}");
  r.usbLine("{\"t\":\"do\",\"name\":\"helper_return\",\"play\":\"now\",\"args\":{\"loops\":2}}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":4201}");
  for (uint32_t t = 4251; t <= 9000; t += 50) {
    char step[64];
    std::snprintf(step, sizeof(step), "{\"t\":\"dbg.clock\",\"freeze\":%u}", unsigned(t));
    r.usbLine(step);
  }
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"clock\":{\"now\":8951,"));
}

static void test_light_holds_the_backlight_until_the_next_state() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.light\",\"bl\":40}");
  TEST_ASSERT_EQUAL(40, r.hal.bl);
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"bl\":40"));
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1000}");  // eased back over the blend
  TEST_ASSERT_EQUAL(255, r.hal.bl);
}

// With the clock running, motion redraws at most every
// 16 ms of real time, however fast the loop runs. A frozen clock checks
// on every step, so scenario frames stay exact. The excited working
// design's sparks and keys step 3 ms apart (810 and 813 ms), so uncapped
// its picture changes faster.
static void test_motion_redraws_at_most_every_16ms() {
  for (bool running : {true, false}) {
    Rig r;
    r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"mood\":\"excited\"}");
    if (running) r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
    r.dev.takeFrame();
    int frames = 0, last = 0, gap = 1000;
    for (int ms = 1; ms <= 2000; ++ms) {
      if (running) ++r.hal.real, r.kit.tick();
      else r.usbLine("{\"t\":\"dbg.clock\",\"step\":1}");
      if (!r.dev.takeFrame()) continue;
      ++frames;
      if (ms - last < gap) gap = ms - last;
      last = ms;
    }
    TEST_ASSERT_TRUE(frames > 10);
    if (running) TEST_ASSERT_GREATER_OR_EQUAL(16, gap);
    else TEST_ASSERT_LESS_THAN(16, gap);
  }
}

// A frame is drawn only when the picture changes. The
// designs step a few times a second, so with the clock running every frame
// drawn is a new picture, fewer than one a second asleep. And the screen always
// shows what drawing afresh would: stepping a frozen clock, which checks
// on every step, it matches a second rig that takes a dbg.shot (which
// draws afresh) after every step, pixel for pixel.
static void test_a_still_picture_isnt_redrawn() {
  struct Case {
    const char* base;
    const char* moment;
    int ms;
    int most;  // frames in 3 s; 3000 / 16 = 187 without the check
  };
  const Case cases[] = {
      {"{\"t\":\"state\",\"base\":\"asleep\"}", nullptr, 2400, 20},
      {"{\"t\":\"state\",\"base\":\"working\",\"busy\":3}", nullptr, 1200, 40},
      {"{\"t\":\"state\",\"base\":\"working\"}", "{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\"}}", 1200, 90},
  };
  for (const Case& c : cases) {
    const std::string name = std::string(c.base) + (c.moment ? c.moment : "");
    Rig r, fresh;
    for (Rig* x : {&r, &fresh}) {
      x->usbLine(c.base);
      if (c.moment) x->usbLine(c.moment);
    }
    for (int ms = 2; ms <= c.ms + 2; ms += 2) {
      r.usbLine("{\"t\":\"dbg.clock\",\"step\":2}");
      fresh.usbLine("{\"t\":\"dbg.clock\",\"step\":2}");
      fresh.usb.text.clear();
      fresh.usbLine("{\"t\":\"dbg.shot\"}");
      if (r.px != fresh.px) TEST_FAIL_MESSAGE(("stale frame at " + std::to_string(ms) + " ms: " + name).c_str());
    }
    if (c.moment) r.usbLine(c.moment);  // from the start again, with the clock running
    r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
    r.dev.takeFrame();
    std::vector<uint8_t> last = r.px;
    int frames = 0, pictures = 0;
    for (int ms = 0; ms < 3000; ++ms) {
      ++r.hal.real;
      r.kit.tick();
      if (!r.dev.takeFrame()) continue;
      ++frames;
      if (r.px != last) ++pictures, last = r.px;
    }
    TEST_ASSERT_EQUAL_MESSAGE(pictures, frames, name.c_str());
    TEST_ASSERT_TRUE_MESSAGE(frames > 0 && frames <= c.most, name.c_str());
  }
}

// Repeated state heartbeats refresh liveness without drawing
// an unchanged canvas. Changed status text and recovery still draw at once,
// even when the frozen clock has not advanced.
static void test_repeated_states_dont_redraw_the_picture() {
  const char* states[] = {
      "{\"t\":\"state\",\"base\":\"asleep\"}",
      "{\"t\":\"state\",\"base\":\"working\",\"busy\":2}",
      "{\"t\":\"state\",\"attn\":{\"agent\":\"claude\",\"project\":\"boop\",\"name\":\"Fix a test\",\"id\":1}}",
  };
  for (const char* state : states) {
    Rig r;
    r.usbLine(state);
    r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1000}");
    const std::vector<uint8_t> before = r.px;
    r.dev.takeFrame();
    for (int i = 0; i < 20; ++i) {
      r.usbLine(state);
      TEST_ASSERT_FALSE_MESSAGE(r.dev.takeFrame(), state);
      TEST_ASSERT_TRUE(r.px == before);
    }
    // The identical state still replaces the debug pattern immediately.
    r.usbLine("{\"t\":\"dbg.pattern\",\"fill\":3}");
    r.dev.takeFrame();
    r.usbLine(state);
    TEST_ASSERT_TRUE(r.dev.takeFrame());
    TEST_ASSERT_TRUE(r.px == before);
    // And after no app it still reconnects, even with the same model.
    r.usbLine("{\"t\":\"dbg.clock\",\"step\":30000}");
    TEST_ASSERT_TRUE(r.screen() == "no_app");
    r.dev.takeFrame();
    r.usbLine(state);
    TEST_ASSERT_TRUE(r.dev.takeFrame());
    TEST_ASSERT_TRUE(r.screen() != "no_app");
  }

  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"busy\":1}");
  r.dev.takeFrame();
  const std::vector<uint8_t> before = r.px;
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"busy\":2}");
  TEST_ASSERT_TRUE(r.dev.takeFrame());
  TEST_ASSERT_TRUE(r.px != before);
  r.usbLine(states[2]);
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1000}");
  r.dev.takeFrame();
  const std::vector<uint8_t> sign = r.px;
  r.usbLine("{\"t\":\"state\",\"attn\":{\"agent\":\"claude\",\"project\":\"boop\",\"name\":\"Fix another test\",\"id\":1}}");
  TEST_ASSERT_TRUE(r.dev.takeFrame());
  TEST_ASSERT_TRUE(r.px != sign);
}

// internal/VERIFICATION.md §8: a press draws at once, and the 16 ms
// redraw cap doesn't hold it back. With the clock running and a
// loop pass every ms, the first frame that differs from the unpressed face
// after a BOOT press comes on the same ms as with a frozen clock, which
// draws every step.
static void test_the_redraw_cap_doesnt_delay_a_press() {
  const int n = int(app::Behaviour::kPressEaseMs);
  for (const char* base : {"idle", "working"}) {
    // Frames from ms 0 to n after a press at t = 500 (or none), each
    // checked against `ref`; returns them, or the first ms that differs.
    auto run = [&](bool press, bool running, const std::vector<std::vector<uint8_t>>* ref, int& first) {
      std::vector<std::vector<uint8_t>> frames;
      Rig r;
      std::string state = std::string("{\"t\":\"state\",\"base\":\"") + base + "\"}";
      r.usbLine(state.c_str());
      r.usbLine("{\"t\":\"dbg.clock\",\"step\":500}");
      if (running) r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
      r.hal.boot = press;
      first = -1;
      for (int ms = 0; ms < n; ++ms) {
        if (ms == 0 || running) {
          r.kit.tick();
        } else {
          r.usbLine("{\"t\":\"dbg.clock\",\"step\":1}");
        }
        if (r.dev.takeFrame() && ref && first < 0 && r.px != (*ref)[size_t(ms)]) first = ms;
        frames.push_back(r.px);
        ++r.hal.real;
      }
      return frames;
    };
    int frozen = -1, running = -1;
    std::vector<std::vector<uint8_t>> still = run(false, false, nullptr, frozen);
    run(true, false, &still, frozen);
    run(true, true, &still, running);
    TEST_ASSERT_TRUE_MESSAGE(frozen >= 0, base);  // the dip shows on the press's own ms
    TEST_ASSERT_EQUAL_INT_MESSAGE(frozen, running, base);
  }
}

// dbg.state's `alert`: when needs you's performance last started for a
// new request, or null.
static std::string alertOf(Rig& r) {
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  size_t i = r.usb.text.find("\"alert\":");
  if (i == std::string::npos) return "missing";
  size_t j = r.usb.text.find_first_of(",}", i);
  return r.usb.text.substr(i + 8, j - i - 8);
}

// The performance, knocks and ding, once per request,
// amber at half, nothing more while it waits; a different request plays it
// again.
static void test_attention_shows_needs_you_and_alerts_once() {
  Rig r;
  TEST_ASSERT_EQUAL_STRING("null", alertOf(r).c_str());
  const char* landing = "{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"landing\"}}";
  r.usbLine(landing);
  TEST_ASSERT_EQUAL_STRING("needs_you", r.screen().c_str());
  TEST_ASSERT_EQUAL_UINT32(0x805800, r.hal.led);
  TEST_ASSERT_EQUAL_STRING("0", alertOf(r).c_str());
  for (uint32_t t : {20000u, 40000u, 60000u, 80000u, 100000u, 120000u, 140000u}) {
    char step[64];
    std::snprintf(step, sizeof(step), "{\"t\":\"dbg.clock\",\"freeze\":%u}", unsigned(t));
    r.usbLine(step);
    r.usbLine(landing);
  }
  TEST_ASSERT_EQUAL_STRING("0", alertOf(r).c_str());
  TEST_ASSERT_EQUAL_UINT32(0x805800, r.hal.led);
  // A different project alerts again, and so does a different request
  // with the same names: the Mac numbers each one in `attn.id`.
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"site\",\"id\":4}}");
  TEST_ASSERT_EQUAL_STRING("140000", alertOf(r).c_str());
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"site\",\"more\":1,\"id\":4}}");
  TEST_ASSERT_EQUAL_STRING("140000", alertOf(r).c_str());
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":150000}");
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"site\",\"id\":5}}");
  TEST_ASSERT_EQUAL_STRING("150000", alertOf(r).c_str());
  TEST_ASSERT_TRUE(has(r.usb.text, "\"attn\":{\"agent\":\"codex\",\"project\":\"site\",\"name\":\"\",\"more\":0,\"id\":5}"));
  // The thread's name, when the Mac sends one, is read and shown back; a
  // new name alone is the same request, and doesn't alert again.
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"site\",\"name\":\"Fix the hero\",\"id\":5}}");
  TEST_ASSERT_EQUAL_STRING("150000", alertOf(r).c_str());
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"project\":\"site\",\"name\":\"Fix the hero\""));
  r.usbLine("{\"t\":\"state\",\"base\":\"working\"}");
  TEST_ASSERT_EQUAL_STRING("face", r.screen().c_str());
  TEST_ASSERT_EQUAL_UINT32(0, r.hal.led);
  // Muted, nothing sounds.
  Rig m;
  m.usbLine("{\"t\":\"state\",\"base\":\"working\",\"vol\":0,\"attn\":{\"agent\":\"codex\",\"project\":\"landing\"}}");
  runClock(m, 0, 8000);
  TEST_ASSERT_EQUAL(0, int(m.hal.effects.size()));
}

// At power-on no Mac has spoken, so the board shows no
// app from the start, not a face for the first 30 s; the first state ends
// it. dbg.reset, which every scenario starts with, still starts on the face.
static void test_power_on_shows_no_app_until_a_state() {
  Rig r;
  TEST_ASSERT_EQUAL_STRING("no_app", r.screen().c_str());
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  TEST_ASSERT_EQUAL_STRING("face", r.screen().c_str());
  r.usbLine("{\"t\":\"dbg.reset\"}");
  TEST_ASSERT_EQUAL_STRING("face", r.screen().c_str());
}

// No app after 30 s of silence. dbg.state still says
// "no_app", the backlight dims to 60 and the face is asleep.
static void test_no_app_after_30s_of_silence() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":29999}");
  TEST_ASSERT_EQUAL_STRING("face", r.screen().c_str());
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":30000}");
  TEST_ASSERT_EQUAL_STRING("no_app", r.screen().c_str());
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":30150}");  // dimmed over the blend
  TEST_ASSERT_EQUAL(60, r.hal.bl);
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"screen\":\"no_app\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"bl\":60"));
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  TEST_ASSERT_EQUAL_STRING("face", r.screen().c_str());
}

// An animation plays its loops, then ends; a newer one
// replaces it.
static void test_moment_plays_then_ends_and_a_new_one_replaces_it() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"do\",\"name\":\"poked\",\"play\":\"now\"}");  // the dashboard's: the poke
  r.usbLine("{\"t\":\"dbg.state\"}");
  const uint32_t poke = render::loopMs(render::Mood::kHappy, render::SceneState::kPoked);
  TEST_ASSERT_TRUE(has(r.usb.text, ("\"moment\":{\"anim\":\"poked\",\"left_ms\":" + std::to_string(poke) + ",").c_str()));
  r.usbLine("{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\",\"variant\":1,\"size\":3,\"ttl\":5}}");  // args it doesn't know are ignored
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  // One loop of happy's first task-complete design.
  const uint32_t loop = render::loopMs(render::Mood::kHappy, render::SceneState::kTaskComplete);
  auto left = [](uint32_t ms) { return "\"anim\":\"task_complete\",\"left_ms\":" + std::to_string(ms) + ","; };
  TEST_ASSERT_TRUE(has(r.usb.text, left(loop).c_str()));
  // `loops` says how many, held to 1–6: missing, 0 or
  // not a number reads as 1, one too big for an int as 6, and a fraction
  // as its whole loops.
  const struct {
    const char* loops;
    uint32_t times;
  } cases[] = {{"3", 3}, {"9", 6}, {"0", 1}, {"-2", 1}, {"\"many\"", 1}, {"true", 1}, {"99999999999", 6},
               {"1e10", 6}, {"-1e10", 1}, {"2.5", 2}, {"6.9", 6}, {"0.5", 1}};
  for (const auto& c : cases) {
    r.usbLine((std::string("{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\","
                           "\"variant\":1,\"loops\":") + c.loops + "}}").c_str());
    r.usb.text.clear();
    r.usbLine("{\"t\":\"dbg.state\"}");
    TEST_ASSERT_TRUE_MESSAGE(has(r.usb.text, left(c.times * loop).c_str()), c.loops);
  }
  r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(loop) + "}").c_str());  // the last, one loop, is over
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
  // Names it doesn't have, the removed animations and the old `cheer`
  // and `wiggle` among them, are skipped `unknown` (linkkit/SPEC.md §3),
  // with any line they carried.
  for (const char* gone : {"moonwalk", "oops", "happy", "levelup", "yawn", "nod", "thinking", "shrug", "idle", "terminal",
                           "cheer", "wiggle"}) {
    std::string line = std::string("{\"t\":\"do\",\"id\":8,\"name\":\"") + gone +
                       "\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}";
    r.usb.text.clear();
    r.usbLine(line.c_str());
    TEST_ASSERT_TRUE_MESSAGE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"ended\",\"data\":{\"id\":8,\"how\":\"skipped\","
                                             "\"why\":\"unknown\"}}\n"), gone);
    r.usbLine("{\"t\":\"dbg.state\"}");
    TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
  }
  TEST_ASSERT_EQUAL(0, int(r.hal.said.size()));
  // A reaction's line plays on its own.
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}");
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
}

// stop_listening with nothing to stop, or a name the
// device doesn't have, is skipped: whatever is playing carries on.
static void test_a_moment_with_nothing_to_play_is_ignored() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\"}}");
  r.usbLine("{\"t\":\"do\",\"name\":\"stop_listening\",\"play\":\"now\"}");
  r.usbLine("{\"t\":\"do\",\"name\":\"shrug\",\"play\":\"now\"}");  // removed: ignored
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":{\"anim\":\"task_complete\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"rx\":{\"state\":1,\"do\":3}"));
  TEST_ASSERT_EQUAL(0, r.hal.hushes);
}

// The strip is part of the screen; a touch on it is a tap.
static void test_a_strip_touch_is_a_tap() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.touch\",\"x\":160,\"y\":222,\"ms\":100}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":200}");
  TEST_ASSERT_EQUAL_STRING("face", r.screen().c_str());
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"tap\",\"did\":\"poked\"}\n"));
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"anim\":\"poked\""));
}

static void test_reset_forgets_the_mac_and_freezes_at_0() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"x\"}}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":5000}");
  r.usbLine("{\"t\":\"dbg.reset\"}");
  TEST_ASSERT_EQUAL(0u, r.kit.now());
  TEST_ASSERT_EQUAL_STRING("face", r.screen().c_str());
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"idle\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"attn\":null"));
}

// A call's `say` names a take by id, which reaches the
// player with the volume; dbg.state reports it. `{}`, an id the
// device doesn't have and the old syllable fields are still a `say`, but
// play nothing.
static void test_say_reaches_the_player() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"vol\":7}");
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"new.d14\"}}}");
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  const voice::Line& l = r.hal.said[0];
  TEST_ASSERT_EQUAL(voice::takeIndex("new.d14"), l.take);
  TEST_ASSERT_EQUAL(7, l.vol);
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":true,\"take\":\"new.d14\",\"out\":{"));
  // A tap's poke plays, and the line plays on under it.
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":50}");
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":100}");
  TEST_ASSERT_EQUAL(0, r.hal.hushes);
  for (const char* none : {"{}", "{\"take\":\"banana\"}", "{\"take\":7}", "{\"syl\":\"ba po\",\"word\":\"done\"}"}) {
    Rig q;
    q.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
    q.usbLine("{\"t\":\"do\",\"name\":\"listening\",\"play\":\"now\"}");
    q.usbLine((std::string("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":") + none + "}}").c_str());
    TEST_ASSERT_EQUAL_MESSAGE(0, int(q.hal.said.size()), none);
    q.usb.text.clear();
    q.usbLine("{\"t\":\"dbg.state\"}");
    TEST_ASSERT_TRUE_MESSAGE(has(q.usb.text, "\"moment\":null"), none);  // the reply: it ends listening
    TEST_ASSERT_TRUE_MESSAGE(has(q.usb.text, "\"audio\":{\"playing\":false,\"take\":null,"), none);
  }
}

// A face on its own (a `mood`, no `anim`, no line) plays
// that face for its `loops` and is answered `done` when it's over.
static void test_a_face_on_its_own_plays_and_ends() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":0}");
  r.usbLine("{\"t\":\"state\",\"base\":\"working\"}");
  r.usbLine("{\"t\":\"do\",\"id\":4,\"name\":\"react\",\"play\":\"now\",\"args\":{\"mood\":\"grumpy\",\"loops\":2}}");
  TEST_ASSERT_EQUAL(0, int(r.hal.said.size()));
  const uint32_t loop = render::loopMs(render::Mood::kGrumpy, render::SceneState::kWorking);
  r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(2 * loop - 1) + "}").c_str());
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"expr\":\"grumpy\""));
  TEST_ASSERT_FALSE(has(r.usb.text, "\"kind\":\"ended\""));
  r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(2 * loop) + "}").c_str());
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"ended\",\"data\":{\"id\":4,\"how\":\"done\"}}\n"));
}

// A react with only `say` plays the line, bubble and
// voice, over the face showing; no animation starts. The line stops when
// the bubble goes.
// A call's `mood` is its expression, which
// dbg.state reports as `expr` while it plays; an unknown one is ignored,
// and the line plays as usual.
static void test_a_moment_carries_its_expression() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":0}");
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"mood\":\"happy\"}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"expr\":null"));
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.dai\"},\"mood\":\"grumpy\"}}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"mood\":\"happy\""));  // the state's mood is kept
  TEST_ASSERT_TRUE(has(r.usb.text, "\"expr\":\"grumpy\""));
  // The line (Dai, 460 ms) is over at 1660 ms; the face holds a loop of
  // the working design in grumpy, whose clock started with the state at 0.
  const uint32_t loop = render::loopMs(render::Mood::kGrumpy, render::SceneState::kWorking);
  auto exprAt = [&](uint32_t t) {
    r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(t) + "}").c_str());
    r.usb.text.clear();
    r.usbLine("{\"t\":\"dbg.state\"}");
    return has(r.usb.text, "\"expr\":\"grumpy\"");
  };
  TEST_ASSERT_TRUE(460 + app::Behaviour::kBubbleReadMs < loop);
  TEST_ASSERT_TRUE(exprAt(1400));
  TEST_ASSERT_TRUE(exprAt(loop - 1));
  TEST_ASSERT_FALSE(exprAt(loop));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"expr\":null"));
  // `loops`: two, from a boundary, end at the second one after it; over
  // 6 holds 6.
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"},\"mood\":\"grumpy\",\"loops\":2}}");
  TEST_ASSERT_TRUE(exprAt(3 * loop - 1));
  TEST_ASSERT_FALSE(exprAt(3 * loop));
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"mood\":\"happy\"}");  // no "no app" meanwhile
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"},\"mood\":\"grumpy\",\"loops\":9}}");
  TEST_ASSERT_TRUE(exprAt(9 * loop - 1));
  TEST_ASSERT_FALSE(exprAt(9 * loop));
  // Unknown: no expression, and the line still plays.
  size_t said = r.hal.said.size();
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"},\"mood\":\"cheerful\"}}");
  TEST_ASSERT_EQUAL(int(said + 1), int(r.hal.said.size()));
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"expr\":null"));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":true"));
}

static void test_a_say_on_its_own_plays_the_line() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"working\"}");
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}");
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":true,\"take\":\"previous.go\""));
  // "Go"'s 638 ms + 1.2 s: the bubble goes, and the line with it.
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1837}");
  TEST_ASSERT_EQUAL(0, r.hal.hushes);
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1838}");
  TEST_ASSERT_EQUAL(1, r.hal.hushes);
  // With no line and no animation, nothing happens.
  r.usbLine("{\"t\":\"do\",\"name\":\"stop_listening\",\"play\":\"now\"}");
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  // A line of two takes: both play, one after the other,
  // and the status names the first.
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.tsk\",\"then\":\"phase1.word.test.test__annoyed__contained\"}}}");
  TEST_ASSERT_EQUAL(2, int(r.hal.said.size()));
  TEST_ASSERT_TRUE(r.hal.said.back().then >= 0);
  TEST_ASSERT_TRUE(r.hal.said.back().b.len > 0);
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":true,\"take\":\"previous.tsk\""));
}

static void test_mute_and_needs_you_keep_it_silent() {
  NEEDS_VOICE_PACK();
  const char* states[] = {
      "{\"t\":\"state\",\"base\":\"idle\",\"vol\":0}",
      "{\"t\":\"state\",\"base\":\"idle\",\"attn\":{\"agent\":\"claude\",\"project\":\"x\"}}",
  };
  for (const char* st : states) {
    for (const char* mo : {"{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\",\"say\":{\"take\":\"previous.go\"}}}",
                           "{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}"}) {
      Rig r;
      r.usbLine(st);
      r.usbLine(mo);
      TEST_ASSERT_EQUAL(0, int(r.hal.said.size()));
    }
  }
  // Muted, the mouth still moves, at its voice window: only the sound goes.
  Rig r;
  r.usbLine(states[0]);
  r.usbLine("{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\",\"variant\":1,\"say\":{\"take\":\"previous.go\"}}}");
  const uint32_t voice = render::pixel::score(render::pixelIndex(render::Mood::kHappy), int(render::SceneState::kTaskComplete), 0).voiceMs;
  r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(voice) + "}").c_str());
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":true,\"take\":\"previous.go\""));
  TEST_ASSERT_EQUAL(0, int(r.hal.said.size()));
  // A line stops when mute arrives mid-line.
  Rig q;
  q.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  q.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}");
  TEST_ASSERT_EQUAL(1, int(q.hal.said.size()));
  q.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"vol\":0}");
  TEST_ASSERT_EQUAL(1, q.hal.hushes);
}

// A line playing when something starts needing you is
// hushed, and needs you's own sounds, all alerts, play in its place.
static void test_needs_you_hushes_a_line_for_its_alert() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}");
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":100}");
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"attn\":{\"agent\":\"claude\",\"project\":\"x\"}}");
  TEST_ASSERT_EQUAL(1, r.hal.hushes);
  r.hal.effects.clear();
  runClock(r, 110, 8000);
  TEST_ASSERT_TRUE(played(r.hal, "alertDing"));
  for (const voice::Effect& e : r.hal.effects) TEST_ASSERT_FALSE(e.duck);  // no line turns it down
}

// A call with an `id` gets one `ended` once all of it
// is over, on the link it came in on, saying how: done, cut and why, or
// skipped and why. Muting doesn't stop it. A call with no `id` gets none.
static void test_a_moment_with_an_id_is_answered_when_it_ends() {
  NEEDS_VOICE_PACK();
  Rig r;
  // Idle's second variation, a long loop (`variant`).
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"variant\":2}");
  r.usbLine("{\"t\":\"do\",\"id\":5,\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"},\"mood\":\"proud\"}}");
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"variant\":2,\"vol\":0}");  // hushed, but it plays on
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1840}");  // the line is over: 640 ms + 1.2 s
  // The face holds a loop of the idle design in proud.
  const uint32_t loop = render::loopMs(render::Mood::kProud, render::SceneState::kIdle, 1);
  r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(loop - 1) + "}").c_str());
  TEST_ASSERT_FALSE(has(r.usb.text, "\"kind\":\"ended\""));
  r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(loop) + "}").c_str());
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"ended\",\"data\":{\"id\":5,\"how\":\"done\"}}\n"));
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"do\",\"id\":6,\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}");
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":50}");  // a tap's poke doesn't cut it
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":100}");
  TEST_ASSERT_FALSE(has(r.usb.text, "\"id\":6,"));
  r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(loop + 3000) + "}").c_str());
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"ended\",\"data\":{\"id\":6,\"how\":\"done\"}}\n"));
  r.usbLine("{\"t\":\"do\",\"id\":7,\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}");
  r.usbLine("{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\"}}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"ended\",\"data\":{\"id\":7,\"how\":\"cut\",\"why\":\"now\"}}\n"));
  r.usbLine("{\"t\":\"do\",\"id\":8,\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}");
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"attn\":{\"agent\":\"claude\",\"project\":\"x\"}}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"ended\",\"data\":{\"id\":8,\"how\":\"cut\",\"why\":\"needs_you\"}}\n"));
  r.usbLine("{\"t\":\"do\",\"id\":9,\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"ended\",\"data\":{\"id\":9,\"how\":\"skipped\",\"why\":\"needs_you\"}}\n"));
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}");
  r.usbLine("{\"t\":\"do\",\"id\":10,\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}");
  r.usbLine("{\"t\":\"dbg.reset\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"ended\",\"data\":{\"id\":10,\"how\":\"cut\",\"why\":\"reset\"}}\n"));
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":60000}");
  TEST_ASSERT_EQUAL_INT(6, count(r.usb.text, "\"kind\":\"ended\""));  // one each, and none without an id

  // Over Bluetooth: back over Bluetooth, and not on USB.
  Rig b;
  b.kit.connected();
  const char* state = "{\"t\":\"state\",\"base\":\"idle\"}";
  const char* moment = "{\"t\":\"do\",\"id\":3,\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}";
  b.kit.handleLine(state, std::strlen(state), linkkit::Link::kBle);
  b.kit.handleLine(moment, std::strlen(moment), linkkit::Link::kBle);
  b.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1840}");
  TEST_ASSERT_TRUE(has(b.ble.text, "{\"t\":\"ev\",\"kind\":\"ended\",\"data\":{\"id\":3,\"how\":\"done\"}}\n"));
  TEST_ASSERT_FALSE(has(b.usb.text, "\"kind\":\"ended\""));
}

// A line is at most 512 bytes. The board and boop-sim both
// read their lines through LineReader, so a longer one is dropped whole on
// both, and the next line is read as usual.
static void test_lines_over_512_bytes_are_dropped() {
  auto state = [](const char* base, size_t bytes) {
    std::string s = std::string("{\"t\":\"state\",\"base\":\"") + base + "\",\"pad\":\"";
    s += std::string(bytes - s.size() - 2, 'x') + "\"}";
    return s;
  };
  Rig r;
  linkkit::LineReader reader;
  auto feed = [&](const std::string& line) {
    TEST_ASSERT_TRUE(line.size() <= 520);
    for (char c : line + "\n") {
      if (reader.feed(c)) r.kit.handleLine(reader.line(), reader.length(), linkkit::Link::kUsb);
    }
    r.kit.tick();
  };
  std::string at512 = state("working", 512), at513 = state("asleep", 513);
  TEST_ASSERT_EQUAL(512, int(at512.size()));
  TEST_ASSERT_EQUAL(513, int(at513.size()));
  feed(at512);
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"working\""));
  r.usb.text.clear();
  feed(at513);
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"working\""));  // dropped
  r.usb.text.clear();
  feed(state("asleep", 100));
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"asleep\""));
}

// `vol` is held to 0–10 once, as it arrives, and a line
// plays at it. However far out (past an int's range too), and a fraction
// as its whole part; anything but a number reads as the default.
static void test_volume_is_held_in_range() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"vol\":15}");
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"vol\":10,"));
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}");
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  TEST_ASSERT_EQUAL(10, r.hal.said[0].vol);
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"vol\":-3}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"vol\":0,"));
  const struct {
    const char* vol;
    const char* reads;
  } vols[] = {{"99999999999", "\"vol\":10,"}, {"-1e10", "\"vol\":0,"}, {"9.9", "\"vol\":9,"}, {"\"3\"", "\"vol\":6,"}};
  for (const auto& v : vols) {
    r.usbLine((std::string("{\"t\":\"state\",\"base\":\"idle\",\"vol\":") + v.vol + "}").c_str());
    r.usb.text.clear();
    r.usbLine("{\"t\":\"dbg.state\"}");
    TEST_ASSERT_TRUE_MESSAGE(has(r.usb.text, v.reads), v.vol);
  }
}

// The face's design plays its sounds as its clock runs, at
// the state's volume, and dbg.state and dbg.ping say so.
static void test_the_face_plays_its_designs_sounds() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"mood\":\"happy\",\"vol\":4}");
  uint32_t loop = render::loopMs(render::Mood::kHappy, render::SceneState::kWorking, 0);
  render::pixel::Score sc = render::pixel::score(render::pixelIndex(render::Mood::kHappy), int(render::SceneState::kWorking), 0);
  runClock(r, 0, 2 * loop - render::pixel::EffectTrack::kLeadMs - 10);
  int two = render::pixel::events(sc, 0).n + render::pixel::events(sc, 1).n;  // each loop its own picks
  TEST_ASSERT_EQUAL(two, int(r.hal.effects.size()));
  TEST_ASSERT_EQUAL(4, int(r.hal.effects[0].vol));
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  char fx[64];
  std::snprintf(fx, sizeof(fx), "\"fx\":{\"sent\":%d,\"last\":\"%s\"}", two,
                render::pixel::clips().at(r.hal.effects.back().clip).name);
  TEST_ASSERT_TRUE(has(r.usb.text, fx));
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"fx\":\""));
  // Muted: the sounds stop and no more are sent.
  int stops = r.hal.effectStops;
  size_t sent = r.hal.effects.size();
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"mood\":\"happy\",\"vol\":0}");
  TEST_ASSERT_TRUE(r.hal.effectStops > stops);
  runClock(r, 2 * loop, 3 * loop);
  TEST_ASSERT_EQUAL(int(sent), int(r.hal.effects.size()));
}

// When the look's variations take turns,
// the sounds follow: the last one's stop, and only the new one's play,
// from its own start. dbg.state's `look_variant` says which shows.
static void test_the_sounds_follow_the_looks_turns() {
  Rig r;
  const char* state = "{\"t\":\"state\",\"base\":\"working\",\"mood\":\"happy\",\"variant\":1}";
  r.usbLine(state);
  for (uint32_t t = 10; t <= 300000; t += 10) {
    if (t % 10000 == 0) r.usbLine(state);  // the Mac, saying the same
    int stops = r.hal.effectStops;
    r.hal.effects.clear();
    char step[64];
    std::snprintf(step, sizeof(step), "{\"t\":\"dbg.clock\",\"freeze\":%u}", unsigned(t));
    r.usbLine(step);
    r.usb.text.clear();
    r.usbLine("{\"t\":\"dbg.state\"}");
    if (has(r.usb.text, "\"look_variant\":1,")) continue;
    TEST_ASSERT_TRUE(r.hal.effectStops > stops);
    int now = 0;
    for (int v = 2; v <= 5; ++v) {
      char want[32];
      std::snprintf(want, sizeof(want), "\"look_variant\":%d,", v);
      if (has(r.usb.text, want)) now = v - 1;
    }
    TEST_ASSERT_TRUE(now > 0);
    render::pixel::Score sc = render::pixel::score(render::pixelIndex(render::Mood::kHappy), int(render::SceneState::kWorking), now);
    for (const voice::Effect& e : r.hal.effects) {
      bool ours = false;
      for (uint32_t loop = 0; loop < uint32_t(render::pixel::kLoops); ++loop) {
        render::pixel::Events l = render::pixel::events(sc, loop);
        for (int i = 0; i < l.n; ++i) ours |= render::pixel::fxEvent(l.first + i).clip == e.clip;
      }
      TEST_ASSERT_TRUE(ours);
    }
    return;
  }
  TEST_FAIL_MESSAGE("no turn in 300 s");
}

// Needs you stops the last design's sounds and plays its own, ending in
// the ding; asleep is silent.
static void test_needs_you_plays_its_ding_and_asleep_is_quiet() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"working\"}");
  runClock(r, 0, 500);
  int stops = r.hal.effectStops;
  r.hal.effects.clear();
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"landing\"}}");
  TEST_ASSERT_TRUE(r.hal.effectStops > stops);
  runClock(r, 510, 8000);
  TEST_ASSERT_TRUE(played(r.hal, "alertDing"));
  for (const voice::Effect& e : r.hal.effects) TEST_ASSERT_FALSE(e.duck);  // no line turns it down
  Rig a;
  a.usbLine("{\"t\":\"state\",\"base\":\"asleep\"}");
  runClock(a, 0, 20000);
  TEST_ASSERT_EQUAL(0, int(a.hal.effects.size()));
}

// A test pattern is silent: dbg.pattern stops the face's sounds.
static void test_a_test_pattern_is_silent() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"working\"}");
  runClock(r, 0, 300);
  int stops = r.hal.effectStops;
  r.usbLine("{\"t\":\"dbg.pattern\"}");
  TEST_ASSERT_TRUE(r.hal.effectStops > stops);
  size_t sent = r.hal.effects.size();
  runClock(r, 310, 6000);
  TEST_ASSERT_EQUAL(int(sent), int(r.hal.effects.size()));
}

// `state`'s `act` says what the agents are doing while
// working, which dbg.state reports (null for none, or one the device
// doesn't know); `variant` is then the act's, held to its variations.
static void test_a_state_carries_what_the_agents_do() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"act\":\"terminal\",\"mood\":\"calm\",\"variant\":3}");
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"working\",\"act\":\"terminal\",\"mood\":\"calm\",\"variant\":3,"));
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"act\":\"terminal\",\"mood\":\"happy\",\"variant\":3}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"variant\":1,"));  // happy has one terminal design
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"act\":\"juggling\"}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"act\":null,"));
}

// A do names its design by `name`, its variation by
// `variant` when it's one for the call's facts (`outcome`, `ctx`), else
// the device picks one of those; dbg.state says which plays.
static void test_moments_read_their_facts() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  const struct {
    const char* moment;
    const char* reads;
  } cases[] = {
      {"{\"t\":\"do\",\"name\":\"starting\",\"play\":\"now\",\"args\":{\"ctx\":\"session\"}}", "\"anim\":\"starting\",\"left_ms\":3800,\"variant\":2}"},
      {"{\"t\":\"do\",\"name\":\"starting\",\"play\":\"now\",\"args\":{\"variant\":1,\"ctx\":\"continuation\"}}", "\"variant\":3}"},
      {"{\"t\":\"do\",\"name\":\"starting\",\"play\":\"now\",\"args\":{\"variant\":1}}", "\"variant\":1}"},
      {"{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"failure\"}}", "\"anim\":\"task_complete\",\"left_ms\":5200,\"variant\":5}"},
      {"{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"variant\":2,\"outcome\":\"success\"}}", "\"variant\":2}"},
      {"{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"variant\":5}}", "\"variant\":5}"},
      {"{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\",\"variant\":3}}", "\"anim\":\"task_complete\",\"left_ms\":6400,\"variant\":3}"},
      {"{\"t\":\"do\",\"name\":\"reply_ready\",\"play\":\"now\"}", "\"anim\":\"reply_ready\",\"left_ms\":4200,\"variant\":1}"},
      {"{\"t\":\"do\",\"name\":\"stopped\",\"play\":\"now\"}", "\"anim\":\"stopped\",\"left_ms\":4200,\"variant\":1}"},
      {"{\"t\":\"do\",\"name\":\"error\",\"play\":\"now\",\"args\":{\"variant\":1}}", "\"anim\":\"error\",\"left_ms\":3800,\"variant\":1}"},
      {"{\"t\":\"do\",\"name\":\"helper_return\",\"play\":\"now\",\"args\":{\"variant\":2}}", "\"anim\":\"helper_return\",\"left_ms\":4800,\"variant\":2}"},
      {"{\"t\":\"do\",\"name\":\"poked\",\"play\":\"now\"}", "\"anim\":\"poked\",\"left_ms\":2800,\"variant\":1}"},
      {"{\"t\":\"do\",\"name\":\"tap_spam\",\"play\":\"now\"}", "\"anim\":\"tap_spam\",\"left_ms\":3800,\"variant\":1}"},
  };
  for (const auto& c : cases) {
    r.usbLine(c.moment);
    r.usb.text.clear();
    r.usbLine("{\"t\":\"dbg.state\"}");
    TEST_ASSERT_TRUE_MESSAGE(has(r.usb.text, c.reads), c.moment);
  }
  // A success: happy's failure isn't one it plays.
  for (int i = 0; i < 20; ++i) {
    r.usbLine("{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\",\"variant\":5}}");
    r.usb.text.clear();
    r.usbLine("{\"t\":\"dbg.state\"}");
    TEST_ASSERT_TRUE(has(r.usb.text, "\"anim\":\"task_complete\""));
    TEST_ASSERT_FALSE(has(r.usb.text, "\"variant\":5}"));
  }
}

// While listening waits, a rule's one-shot, the brain's
// finish without a line, a face on its own and a name the device
// doesn't know leave it be; a `say`, or stop_listening, ends it.
static void test_only_the_reply_ends_the_macs_listening() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"do\",\"name\":\"listening\",\"play\":\"now\"}");
  for (const char* other : {"{\"t\":\"do\",\"name\":\"starting\",\"play\":\"now\",\"args\":{\"ctx\":\"new_task\"}}",
                            "{\"t\":\"do\",\"name\":\"stopped\",\"play\":\"now\"}", "{\"t\":\"do\",\"name\":\"error\",\"play\":\"now\"}",
                            "{\"t\":\"do\",\"name\":\"helper_return\",\"play\":\"now\"}",
                            "{\"t\":\"do\",\"id\":4,\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\"}}",
                            "{\"t\":\"do\",\"name\":\"reply_ready\",\"play\":\"now\"}", "{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"mood\":\"proud\"}}",
                            "{\"t\":\"do\",\"name\":\"oops\",\"play\":\"now\"}"}) {
    r.usbLine(other);
    r.usb.text.clear();
    r.usbLine("{\"t\":\"dbg.state\"}");
    TEST_ASSERT_TRUE_MESSAGE(has(r.usb.text, "\"moment\":{\"anim\":\"listening\""), other);
  }
  TEST_ASSERT_TRUE(has(r.usb.text, "\"expr\":null"));
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"},\"mood\":\"proud\"}}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"expr\":\"proud\""));
}

// A line that comes with an animation reaches the player at
// its design's voice window, at the volume then, with its bubble; one a tap
// or "needs you" stops first never plays, and the line playing when it
// arrives stops at once.
static void test_a_finishs_line_starts_at_its_voice_window() {
  NEEDS_VOICE_PACK();
  const uint32_t voice = render::pixel::score(render::pixelIndex(render::Mood::kHappy), int(render::SceneState::kTaskComplete), 0).voiceMs;
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"vol\":5}");
  r.usbLine("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}");  // a line playing
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  r.usbLine("{\"t\":\"do\",\"id\":3,\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\","
            "\"variant\":1,\"say\":{\"take\":\"new.d14\"}}}");
  TEST_ASSERT_EQUAL(1, r.hal.hushes);  // it replaces the line playing
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":false,\"take\":null,"));
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"vol\":7}");
  runClock(r, 10, voice - 10);
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(voice) + "}").c_str());
  TEST_ASSERT_EQUAL(2, int(r.hal.said.size()));
  TEST_ASSERT_EQUAL(voice::takeIndex("new.d14"), r.hal.said[1].take);
  TEST_ASSERT_EQUAL(7, r.hal.said[1].vol);  // the volume when it starts
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":true,\"take\":\"new.d14\","));
  // Tapped before its window, the line still plays over the poke; cut by
  // needs you, it never plays.
  for (const char* stop : {"tap", "needs"}) {
    Rig q;
    q.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
    q.usbLine("{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"outcome\":\"success\",\"variant\":1,\"say\":{\"take\":\"previous.go\"}}}");
    const bool tap = !std::strcmp(stop, "tap");
    if (tap) {
      q.usbLine("{\"t\":\"dbg.press\",\"ms\":50}");
    } else {
      q.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"attn\":{\"agent\":\"claude\",\"project\":\"x\"}}");
    }
    runClock(q, 100, voice + 500);
    TEST_ASSERT_EQUAL_MESSAGE(tap ? 1 : 0, int(q.hal.said.size()), stop);
  }
}

// Taps in a row, counted by the device: the first two
// poke, the third spams, and 3 s after the last a new run pokes again.
static void test_taps_in_a_row_poke_then_spam() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  const char* expect[] = {"poked", "poked", "tap_spam", "tap_spam"};
  uint32_t t = 0;
  for (const char* anim : expect) {
    r.usbLine("{\"t\":\"dbg.press\",\"ms\":50}");
    t += 100;
    r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(t) + "}").c_str());
    r.usb.text.clear();
    r.usbLine("{\"t\":\"dbg.state\"}");
    TEST_ASSERT_TRUE_MESSAGE(has(r.usb.text, (std::string("\"moment\":{\"anim\":\"") + anim).c_str()), anim);
    t += 900;
    r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(t) + "}").c_str());
  }
  t += app::Behaviour::kTapRunMs;
  r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(t) + "}").c_str());
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":50}");
  r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(t + 100) + "}").c_str());
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":{\"anim\":\"poked\""));
}

// The sounds follow the design drawn: what the agents are
// doing, and each animation, from its own start. Those that play once
// (a finish, a one-shot, a poke) sound in their first loop only, however
// many loops the finish plays.
static void test_the_sounds_follow_every_design() {
  using render::Mood;
  using render::SceneState;
  auto only = [](const std::vector<voice::Effect>& fx, const render::pixel::Score& sc, uint32_t loops) {
    for (const voice::Effect& e : fx) {
      bool ours = false;
      for (uint32_t n = 0; n < loops; ++n) {
        render::pixel::Events l = render::pixel::events(sc, n);
        for (int i = 0; i < l.n; ++i) ours |= render::pixel::fxEvent(l.first + i).clip == e.clip;
      }
      if (!ours) return false;
    }
    return true;
  };
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"act\":\"terminal\",\"mood\":\"engaged\"}");
  render::pixel::Score term = render::pixel::score(render::pixelIndex(Mood::kEngaged), int(SceneState::kTerminal), 0);
  uint32_t loop = render::loopMs(Mood::kEngaged, SceneState::kTerminal, 0);
  runClock(r, 0, 2 * loop);
  TEST_ASSERT_TRUE(r.hal.effects.size() > 0);
  TEST_ASSERT_TRUE(only(r.hal.effects, term, uint32_t(render::pixel::kLoops)));
  // A finish of three loops: its whole timeline, once.
  uint32_t at = 2 * loop + 10;
  r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(at) + "}").c_str());
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"act\":\"terminal\",\"mood\":\"engaged\"}");
  r.hal.effects.clear();
  r.usbLine("{\"t\":\"do\",\"name\":\"task_complete\",\"play\":\"now\",\"args\":{\"variant\":1,\"loops\":3}}");
  render::pixel::Score done = render::pixel::score(render::pixelIndex(Mood::kEngaged), int(SceneState::kTaskComplete), 0);
  uint32_t doneLoop = render::loopMs(Mood::kEngaged, SceneState::kTaskComplete, 0);
  TEST_ASSERT_TRUE(done.policy == render::pixel::Policy::kEntry && !done.duck);
  for (uint32_t t = at + 10; t <= at + 3 * doneLoop - 20; t += 10) {
    if ((t - at) % 9000 < 10) r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"act\":\"terminal\",\"mood\":\"engaged\"}");
    r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(t) + "}").c_str());
  }
  TEST_ASSERT_EQUAL(render::pixel::events(done, 0).n, int(r.hal.effects.size()));
  TEST_ASSERT_TRUE(only(r.hal.effects, done, 1));
  // A one-shot, and a tap's poke: their own, once each.
  for (const char* line : {"{\"t\":\"do\",\"name\":\"error\",\"play\":\"now\",\"args\":{\"variant\":1}}", "poke"}) {
    Rig q;
    q.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"mood\":\"calm\"}");
    SceneState s = SceneState::kError;
    if (!std::strcmp(line, "poke")) {
      q.usbLine("{\"t\":\"dbg.press\",\"ms\":50}");
      q.usbLine("{\"t\":\"dbg.clock\",\"freeze\":60}");
      s = SceneState::kPoked;
    } else {
      q.usbLine(line);
    }
    q.usb.text.clear();
    q.usbLine("{\"t\":\"dbg.state\"}");
    int v = 0;
    for (int k = 1; k <= 3; ++k) {
      if (has(q.usb.text, (",\"variant\":" + std::to_string(k) + "},").c_str())) v = k - 1;
    }
    render::pixel::Score sc = render::pixel::score(render::pixelIndex(Mood::kCalm), int(s), v);
    uint32_t l = render::loopMs(Mood::kCalm, s, v);
    q.hal.effects.clear();
    runClock(q, 70, l - 20);
    TEST_ASSERT_TRUE_MESSAGE(only(q.hal.effects, sc, 1), line);
    TEST_ASSERT_TRUE_MESSAGE(int(q.hal.effects.size()) <= render::pixel::events(sc, 0).n, line);
  }
}

// ---- The turn: Boop's rules on LinkKit -------------------------------------

// Sends a do over USB: its id (0 for none), name, play and args.
static void doLine(Rig& r, int id, const char* name, const char* play, const char* args = nullptr) {
  std::string s = "{\"t\":\"do\"";
  if (id) s += ",\"id\":" + std::to_string(id);
  s += std::string(",\"name\":\"") + name + "\",\"play\":\"" + play + "\"";
  if (args) s += std::string(",\"args\":") + args;
  r.usbLine((s + "}").c_str());
}
static void clockAt(Rig& r, uint32_t t) { r.usbLine(("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(t) + "}").c_str()); }
static std::string endedLine(int id, const char* how, const char* why = nullptr) {
  std::string s = "{\"t\":\"ev\",\"kind\":\"ended\",\"data\":{\"id\":" + std::to_string(id) + ",\"how\":\"" + how + "\"";
  if (why) s += std::string(",\"why\":\"") + why + "\"";
  return s + "}}\n";
}
static std::string stateOf(Rig& r) {
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  return r.usb.text;
}
static const char* kGo = "{\"say\":{\"take\":\"previous.go\"}}";  // 638 ms, then 1.2 s of bubble

// A reaction with nothing left to play once its line and
// bubble have played (the take, then 1.2 s) ends done then, and the
// brain's next one, waiting its turn, starts at that millisecond, however
// the clock steps. One whose face holds on rests half a second after its
// bubble, then the face may be replaced.
static void test_a_reaction_waits_for_the_line_before_it() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"variant\":2}");  // a long loop for the face to hold
  doLine(r, 1, "react", "next", kGo);
  clockAt(r, 100);
  doLine(r, 2, "react", "next", "{\"say\":{\"take\":\"previous.go\"},\"mood\":\"proud\",\"loops\":3}");
  TEST_ASSERT_TRUE(has(stateOf(r), "\"turn\":{\"holder\":{\"id\":1,\"name\":\"react\",\"resting\":false},"
                                   "\"waiting\":[{\"id\":2,\"name\":\"react\",\"left_ms\":5000}]}"));
  clockAt(r, 1837);
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  clockAt(r, 3000);  // a jump: it started at 1838 all the same
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(1, "done")));
  TEST_ASSERT_EQUAL(2, int(r.hal.said.size()));
  std::string st = stateOf(r);
  TEST_ASSERT_TRUE(has(st, "\"audio\":{\"playing\":false,\"take\":\"previous.go\""));  // its take played 1838–2476
  TEST_ASSERT_TRUE(has(st, "\"expr\":\"proud\""));
  TEST_ASSERT_TRUE(has(st, "\"holder\":{\"id\":2,\"name\":\"react\",\"resting\":false}"));
  clockAt(r, 4175);
  TEST_ASSERT_TRUE(has(stateOf(r), "\"resting\":false"));
  clockAt(r, 4176);  // 1838 + 1838 + 500: it rests, its face holding its loops
  TEST_ASSERT_TRUE(has(stateOf(r), "\"holder\":{\"id\":2,\"name\":\"react\",\"resting\":true}"));
  // A face with no line rests 1.2 s in, and the half second.
  Rig f;
  f.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"variant\":2}");  // a long loop
  doLine(f, 3, "react", "next", "{\"mood\":\"grumpy\",\"loops\":3}");
  clockAt(f, 1699);
  TEST_ASSERT_TRUE(has(stateOf(f), "\"resting\":false"));
  clockAt(f, 1700);
  TEST_ASSERT_TRUE(has(stateOf(f), "\"resting\":true"));
}

// A reaction whose face holds on after its line rests
// half a second after its bubble goes (Device::kReactGapMs, the pause the
// Mac left before LinkKit), so the next reaction takes over then, and not
// at the bubble's last millisecond.
static void test_the_next_reaction_waits_half_a_second_after_a_bubble() {
  NEEDS_VOICE_PACK();
  TEST_ASSERT_EQUAL_UINT32(500, app::Device::kReactGapMs);
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"variant\":2}");  // a long loop for the face to hold
  doLine(r, 1, "react", "next", "{\"say\":{\"take\":\"previous.go\"},\"mood\":\"proud\",\"loops\":3}");
  clockAt(r, 100);
  doLine(r, 2, "react", "next", kGo);
  clockAt(r, 1838);  // the bubble goes
  TEST_ASSERT_TRUE(has(stateOf(r), "\"holder\":{\"id\":1,\"name\":\"react\",\"resting\":false}"));
  clockAt(r, 2337);
  TEST_ASSERT_TRUE(has(stateOf(r), "\"waiting\":[{\"id\":2,"));
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  clockAt(r, 2338);
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(1, "done")));
  TEST_ASSERT_TRUE(has(stateOf(r), "\"holder\":{\"id\":2,\"name\":\"react\",\"resting\":false}"));
  TEST_ASSERT_EQUAL(2, int(r.hal.said.size()));
}

// The brain's finish never rests: the next reaction waits
// until it's over, and one that has waited longer than its ttl is late.
static void test_a_finish_holds_the_turn_until_it_ends() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  doLine(r, 1, "task_complete", "next", "{\"outcome\":\"success\",\"variant\":1}");
  const uint32_t loop = render::loopMs(render::Mood::kHappy, render::SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(loop > 5100);
  clockAt(r, 100);
  doLine(r, 2, "react", "next", kGo);
  clockAt(r, 5100);
  TEST_ASSERT_FALSE(has(r.usb.text, "\"id\":2,"));
  clockAt(r, 5101);
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(2, "skipped", "late")));
  r.usbLine("{\"t\":\"do\",\"id\":3,\"name\":\"react\",\"ttl\":9000,\"args\":{\"say\":{\"take\":\"previous.go\"}}}");
  clockAt(r, 20000);
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(1, "done")));
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  TEST_ASSERT_TRUE(has(stateOf(r), "\"holder\":null"));  // 3 played from `loop` and is over
  TEST_ASSERT_TRUE(has(r.usb.text, "\"rx\":{\"state\":1,\"do\":3}"));
}

// A rule's one-shot (if_free) never cuts a reaction's
// line, nor the half second after its bubble: it's skipped busy. Over the
// face held after that it plays, and that reaction is done; it rests at
// once, so the brain's next line plays over it.
static void test_a_one_shot_never_cuts_a_line() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"variant\":2}");  // a long loop for the face to hold
  doLine(r, 1, "react", "next", "{\"say\":{\"take\":\"previous.go\"},\"mood\":\"proud\",\"loops\":2}");
  clockAt(r, 100);
  doLine(r, 2, "starting", "if_free", "{\"ctx\":\"new_task\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(2, "skipped", "busy")));
  TEST_ASSERT_TRUE(has(stateOf(r), "\"moment\":null"));
  clockAt(r, 2000);  // the bubble went at 1838; the reaction rests at 2338
  doLine(r, 5, "stopped", "if_free");
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(5, "skipped", "busy")));
  clockAt(r, 2338);
  doLine(r, 3, "starting", "if_free", "{\"ctx\":\"new_task\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(1, "done")));
  std::string st = stateOf(r);
  TEST_ASSERT_TRUE(has(st, "\"moment\":{\"anim\":\"starting\""));
  TEST_ASSERT_TRUE(has(st, "\"holder\":{\"id\":3,\"name\":\"starting\",\"resting\":true}"));
  doLine(r, 4, "react", "next", kGo);
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(3, "done")));
  st = stateOf(r);
  TEST_ASSERT_TRUE(has(st, "\"moment\":{\"anim\":\"starting\""));  // the line plays over it
  TEST_ASSERT_TRUE(has(st, "\"audio\":{\"playing\":true,\"take\":\"previous.go\""));
}

// Why a call is skipped: something needs you, no app,
// listening holds the face (a reply excepted), stop_listening with
// nothing to stop, or nothing of it that would play.
static void test_refused_calls_say_why() {
  Rig n;  // at power-on, no app
  doLine(n, 1, "react", "next", "{\"mood\":\"proud\"}");
  TEST_ASSERT_TRUE(has(n.usb.text, endedLine(1, "skipped", "no_app")));
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"attn\":{\"agent\":\"claude\",\"project\":\"x\"}}");
  doLine(r, 2, "react", "next", kGo);
  doLine(r, 3, "error", "if_free");
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(2, "skipped", "needs_you")));
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(3, "skipped", "needs_you")));
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  doLine(r, 4, "listening", "now");
  doLine(r, 5, "starting", "if_free");
  doLine(r, 6, "task_complete", "next", "{\"outcome\":\"success\"}");  // a finish with no `say` is no reply
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(5, "skipped", "listening")));
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(6, "skipped", "listening")));
  TEST_ASSERT_TRUE(has(stateOf(r), "\"moment\":{\"anim\":\"listening\""));
  doLine(r, 7, "stop_listening", "if_free");
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(4, "done")));
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(7, "done")));
  TEST_ASSERT_TRUE(has(stateOf(r), "\"moment\":null"));
  doLine(r, 8, "stop_listening", "if_free");
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(8, "skipped", "not_listening")));
  doLine(r, 9, "react", "next", "{\"say\":{}}");
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(9, "skipped", "nothing")));
  // A reply ends listening even when nothing of it can then play.
  doLine(r, 10, "listening", "now");
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"attn\":{\"agent\":\"claude\",\"project\":\"x\"}}");
  TEST_ASSERT_TRUE(has(stateOf(r), "\"moment\":{\"anim\":\"listening\""));  // it plays over needs you
  doLine(r, 11, "react", "next", kGo);
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(10, "done")));
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(11, "skipped", "needs_you")));
  TEST_ASSERT_TRUE(has(stateOf(r), "\"moment\":null"));
}

// Push-to-talk, BOOT's or the Mac's `listening`, drops
// the reactions waiting (they'd end it) with why `mic_on`; BOOT's also
// cuts the holder, as a tap does, and the Mac's replaces it.
static void test_the_mic_drops_the_reactions_waiting() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  doLine(r, 1, "react", "next", kGo);
  doLine(r, 2, "react", "next", kGo);
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":800}");
  for (uint32_t t = 10; t <= 500; t += 10) clockAt(r, t);
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"talk_on\",\"did\":\"listening\"}\n"));
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(2, "skipped", "mic_on")));
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(1, "cut", "tap")));
  Rig m;
  m.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  doLine(m, 3, "react", "next", kGo);
  doLine(m, 4, "react", "next", kGo);
  doLine(m, 5, "listening", "now");
  TEST_ASSERT_TRUE(has(m.usb.text, endedLine(3, "cut", "now")));
  TEST_ASSERT_TRUE(has(m.usb.text, endedLine(4, "skipped", "mic_on")));
  TEST_ASSERT_TRUE(has(stateOf(m), "\"holder\":{\"id\":5,\"name\":\"listening\",\"resting\":true}"));
}

// A tool's dbg.press over USB is push-to-talk for USB
// alone, so it drops only the calls USB has waiting. The everyday app on
// Bluetooth never hears that talk_on, so its reaction waiting is left
// alone: it takes the turn once the press cuts the one playing and, a
// reply, ends the listening, as the app's own queued reply did before.
static void test_a_tools_press_drops_only_usbs_waiting_calls() {
  NEEDS_VOICE_PACK();
  Rig r;
  const char* react = "{\"t\":\"do\",\"id\":%d,\"name\":\"react\",\"play\":\"next\",\"args\":{\"say\":{\"take\":\"previous.go\"}}}";
  char line[160];
  r.kit.connected();
  r.bleLine("{\"t\":\"state\",\"base\":\"idle\"}");
  for (int id : {1, 2}) {
    std::snprintf(line, sizeof(line), react, id);
    r.bleLine(line);
  }
  doLine(r, 3, "react", "next", kGo);  // a tool's, over USB
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":800}");
  for (uint32_t t = 10; t <= 500; t += 10) clockAt(r, t);
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"talk_on\",\"did\":\"listening\"}\n"));
  TEST_ASSERT_FALSE(has(r.ble.text, "talk_on"));
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(3, "skipped", "mic_on")));
  TEST_ASSERT_TRUE(has(r.ble.text, endedLine(1, "cut", "tap")));
  TEST_ASSERT_FALSE(has(r.ble.text, "\"id\":2,"));
  std::string st = stateOf(r);
  TEST_ASSERT_TRUE(has(st, "\"holder\":{\"id\":2,\"name\":\"react\",\"resting\":false}"));
  TEST_ASSERT_TRUE(has(st, "\"moment\":null"));  // the reply ended listening
}

// A tap's poke that cuts the holder's animation ends
// it `cut`, `tap`, once nothing of it plays; the next reaction waiting then
// plays.
static void test_a_tap_cuts_the_holders_animation() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  doLine(r, 1, "task_complete", "next", "{\"outcome\":\"success\",\"variant\":1}");
  doLine(r, 2, "react", "next", kGo);
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":50}");
  clockAt(r, 100);
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ev\",\"kind\":\"tap\",\"did\":\"poked\"}\n"));
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(1, "cut", "tap")));
  std::string st = stateOf(r);
  TEST_ASSERT_TRUE(has(st, "\"moment\":{\"anim\":\"poked\""));  // the line plays over the poke
  TEST_ASSERT_TRUE(has(st, "\"holder\":{\"id\":2,"));
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
}

// linkkit/SPEC.md §4 (same id again): each launch of the Mac app starts its
// ids at a random number, so a call after a restart can, rarely, reuse an
// id the device still holds from the launch before. That launch is gone:
// its call is forgotten, unanswered, and the new one's end is its own.
static void test_a_new_launchs_call_is_its_own() {
  NEEDS_VOICE_PACK();
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");  // the idle design's clock from 0
  clockAt(r, 1000);
  doLine(r, 1, "react", "next", "{\"say\":{\"take\":\"previous.go\"},\"mood\":\"proud\",\"loops\":4}");
  clockAt(r, 4000);
  doLine(r, 1, "react", "next", "{\"say\":{\"take\":\"previous.go\"},\"mood\":\"proud\"}");  // the new launch's first
  // Its face holds to the idle design's next boundary, or while its line
  // plays, whichever is later.
  const uint32_t idle = render::loopMs(render::Mood::kProud, render::SceneState::kIdle);
  uint32_t end = (4000 / idle + 1) * idle;
  if (end < 4000 + 1838) end = 4000 + 1838;
  clockAt(r, end - 1);
  TEST_ASSERT_FALSE(has(r.usb.text, "\"kind\":\"ended\""));
  clockAt(r, end);
  TEST_ASSERT_TRUE(has(r.usb.text, endedLine(1, "done")));
  clockAt(r, end + 4 * idle);
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, "\"kind\":\"ended\""));  // once, and nothing of the old launch's
}

// ---- Latency (dbg.latency) -------------------------------------------------

// Each kind's samples go to the frame that showed them, in the order the
// frames were handed over; p95 is the nearest rank of the latest 32
//, and a burst of one kind before its frame counts from the
// first.
static void test_latency_follows_each_event_to_its_frame() {
  app::Latency l;
  l.mark(app::Latency::kState, 100);
  l.mark(app::Latency::kState, 104);  // the same frame shows both: the first counts
  l.drawn();
  l.handed();
  l.mark(app::Latency::kDo, 110);
  l.drawn();
  l.handed();  // two in flight
  l.shown(130);
  l.shown(150);
  TEST_ASSERT_EQUAL_UINT32(1, l.stats(app::Latency::kState).n);
  TEST_ASSERT_EQUAL_UINT32(30, l.stats(app::Latency::kState).max);
  TEST_ASSERT_EQUAL_UINT32(40, l.stats(app::Latency::kDo).max);
  TEST_ASSERT_EQUAL_UINT32(110, l.stats(app::Latency::kDo).at);
  TEST_ASSERT_EQUAL_UINT32(150, l.stats(app::Latency::kDo).shown);
  TEST_ASSERT_EQUAL_UINT32(20, l.stats(app::Latency::kFrame).max);  // between the two frames shown

  // Frames drawn twice before they're handed over go as one.
  l.mark(app::Latency::kPress, 200);
  l.drawn();
  l.mark(app::Latency::kTap, 205);
  l.drawn();
  l.handed();
  l.shown(220);
  TEST_ASSERT_EQUAL_UINT32(20, l.stats(app::Latency::kPress).max);
  TEST_ASSERT_EQUAL_UINT32(15, l.stats(app::Latency::kTap).max);

  // A third frame in flight drops the oldest's events, uncounted.
  l.clear();
  for (uint32_t t : {300u, 310u, 320u}) {
    l.mark(app::Latency::kPress, t);
    l.drawn();
    l.handed();
  }
  l.shown(330);
  l.shown(340);
  TEST_ASSERT_EQUAL_UINT32(2, l.stats(app::Latency::kPress).n);
  TEST_ASSERT_EQUAL_UINT32(20, l.stats(app::Latency::kPress).max);

  // 100 samples of 1..100 ms: the window holds 69..100, whose nearest-rank
  // p95 is its 31st smallest.
  l.clear();
  for (uint32_t ms = 1; ms <= 100; ++ms) {
    l.mark(app::Latency::kDo, 1000 * ms);
    l.drawn();
    l.handed();
    l.shown(1000 * ms + ms);
  }
  static_assert(app::Latency::kWindow == 32, "the window the p95 below is for");
  TEST_ASSERT_EQUAL_UINT32(100, l.stats(app::Latency::kDo).n);
  TEST_ASSERT_EQUAL_UINT32(99, l.stats(app::Latency::kDo).p95);
  TEST_ASSERT_EQUAL_UINT32(100, l.stats(app::Latency::kDo).max);
}

namespace {
// The frame drawn last, on the panel at real time `at`, if there is one.
void showFrame(Rig& r, uint32_t at) {
  if (r.dev.takeFrame()) r.dev.shown(at);
}
// dbg.latency's reply, as JSON.
JsonDocument latencyOf(Rig& r, bool clear = false) {
  r.usb.text.clear();
  r.usbLine(clear ? "{\"t\":\"dbg.latency\",\"clear\":true}" : "{\"t\":\"dbg.latency\"}");
  JsonDocument d;
  deserializeJson(d, r.usb.text);
  return d;
}
}  // namespace

// With the clock running, each input and message counts from when the
// device knew of it to the frame shown after it: a touch from its press,
// its tap from the injected release (past the pass that saw it), a state
// that changes the picture, a do as it starts. A repeated state changes
// nothing and counts nothing.
static void test_dbg_latency_times_inputs_and_messages() {
  Rig r;
  r.hal.real = 1000;
  r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"busy\":1}");
  showFrame(r, 1007);
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"busy\":1}");
  showFrame(r, 1009);
  JsonDocument d = latencyOf(r);
  TEST_ASSERT_EQUAL_STRING("dbg.latency", d["t"]);
  TEST_ASSERT_EQUAL_UINT32(1000, d["now"].as<uint32_t>());
  TEST_ASSERT_EQUAL_UINT32(1, d["state"]["n"].as<uint32_t>());
  TEST_ASSERT_EQUAL_UINT32(7, d["state"]["max"].as<uint32_t>());
  TEST_ASSERT_EQUAL_UINT32(1000, d["state"]["at"].as<uint32_t>());
  TEST_ASSERT_EQUAL_UINT32(1007, d["state"]["shown"].as<uint32_t>());

  r.hal.real = 2000;
  r.usbLine("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":100}");
  showFrame(r, 2012);
  r.hal.real = 2095;
  r.kit.tick();
  showFrame(r, 2095);
  r.hal.real = 2107;  // the pass that sees the release is 7 ms past it
  r.kit.tick();
  showFrame(r, 2120);
  r.hal.real = 3000;
  r.usbLine("{\"t\":\"do\",\"name\":\"poked\",\"play\":\"now\"}");
  showFrame(r, 3004);
  d = latencyOf(r, true);
  TEST_ASSERT_EQUAL_UINT32(12, d["press"]["max"].as<uint32_t>());
  TEST_ASSERT_EQUAL_UINT32(2100, d["tap"]["at"].as<uint32_t>());
  TEST_ASSERT_EQUAL_UINT32(20, d["tap"]["max"].as<uint32_t>());
  TEST_ASSERT_EQUAL_UINT32(4, d["do"]["max"].as<uint32_t>());
  TEST_ASSERT_TRUE(d["frame"]["n"].as<uint32_t>() >= 3);  // between the four frames above, at least
  d = latencyOf(r);  // cleared once said
  for (const char* k : {"press", "tap", "state", "do", "frame"}) TEST_ASSERT_EQUAL_UINT32(0, d[k]["n"].as<uint32_t>());
}

int main() {
  UNITY_BEGIN();
  if (!packfile::open()) std::printf("no voice pack: the chosen character pack has none\n");
  RUN_TEST(test_the_face_plays_its_designs_sounds);
  RUN_TEST(test_the_sounds_follow_every_design);
  RUN_TEST(test_a_state_carries_what_the_agents_do);
  RUN_TEST(test_moments_read_their_facts);
  RUN_TEST(test_only_the_reply_ends_the_macs_listening);
  RUN_TEST(test_a_finishs_line_starts_at_its_voice_window);
  RUN_TEST(test_taps_in_a_row_poke_then_spam);
  RUN_TEST(test_the_sounds_follow_the_looks_turns);
  RUN_TEST(test_needs_you_plays_its_ding_and_asleep_is_quiet);
  RUN_TEST(test_a_test_pattern_is_silent);
  RUN_TEST(test_ping_reports_version_and_link);
  RUN_TEST(test_debug_is_ignored_over_ble);
  RUN_TEST(test_touch_calibration_maps_raw_to_screen);
  RUN_TEST(test_default_touch_map_follows_the_rotation);
  RUN_TEST(test_saved_touch_calibration_must_match_the_screen);
  RUN_TEST(test_touchcal_sets_reads_and_clears);
  RUN_TEST(test_pattern_target_draws_a_cross);
  RUN_TEST(test_hello_on_the_first_line_and_every_minute);
  RUN_TEST(test_hello_again_when_the_pack_changes);
  RUN_TEST(test_usb_hello_when_the_mac_first_speaks);
  RUN_TEST(test_a_quiet_link_is_dropped_after_30_s);
  RUN_TEST(test_input_reaches_every_live_link);
  RUN_TEST(test_injected_input_stays_on_usb);
  RUN_TEST(test_pattern_until_next_state);
  RUN_TEST(test_injected_tap_reaches_the_mac);
  RUN_TEST(test_a_physical_hold_is_push_to_talk);
  RUN_TEST(test_the_macs_listening_and_the_empty_moment);
  RUN_TEST(test_a_flickering_touch_is_one_tap);
  RUN_TEST(test_a_tap_on_a_named_finish_carries_its_id);
  RUN_TEST(test_a_moment_carries_its_expression);
  RUN_TEST(test_a_touch_ends_while_the_clock_is_frozen);
  RUN_TEST(test_a_frozen_clock_runs_again_after_60s_without_debug);
  RUN_TEST(test_shot_is_header_then_base64);
  RUN_TEST(test_the_clock_can_go_back_mid_animation);
  RUN_TEST(test_light_holds_the_backlight_until_the_next_state);
  RUN_TEST(test_motion_redraws_at_most_every_16ms);
  RUN_TEST(test_a_still_picture_isnt_redrawn);
  RUN_TEST(test_repeated_states_dont_redraw_the_picture);
  RUN_TEST(test_the_redraw_cap_doesnt_delay_a_press);
  RUN_TEST(test_attention_shows_needs_you_and_alerts_once);
  RUN_TEST(test_no_app_after_30s_of_silence);
  RUN_TEST(test_power_on_shows_no_app_until_a_state);
  RUN_TEST(test_moment_plays_then_ends_and_a_new_one_replaces_it);
  RUN_TEST(test_a_moment_with_nothing_to_play_is_ignored);
  RUN_TEST(test_a_strip_touch_is_a_tap);
  RUN_TEST(test_reset_forgets_the_mac_and_freezes_at_0);
  RUN_TEST(test_say_reaches_the_player);
  RUN_TEST(test_a_say_on_its_own_plays_the_line);
  RUN_TEST(test_a_face_on_its_own_plays_and_ends);
  RUN_TEST(test_mute_and_needs_you_keep_it_silent);
  RUN_TEST(test_needs_you_hushes_a_line_for_its_alert);
  RUN_TEST(test_state_carries_the_mood);
  RUN_TEST(test_lines_over_512_bytes_are_dropped);
  RUN_TEST(test_volume_is_held_in_range);
  RUN_TEST(test_a_moment_with_an_id_is_answered_when_it_ends);
  RUN_TEST(test_a_reaction_waits_for_the_line_before_it);
  RUN_TEST(test_the_next_reaction_waits_half_a_second_after_a_bubble);
  RUN_TEST(test_a_finish_holds_the_turn_until_it_ends);
  RUN_TEST(test_a_one_shot_never_cuts_a_line);
  RUN_TEST(test_refused_calls_say_why);
  RUN_TEST(test_the_mic_drops_the_reactions_waiting);
  RUN_TEST(test_a_tools_press_drops_only_usbs_waiting_calls);
  RUN_TEST(test_a_tap_cuts_the_holders_animation);
  RUN_TEST(test_a_new_launchs_call_is_its_own);
  RUN_TEST(test_latency_follows_each_event_to_its_frame);
  RUN_TEST(test_dbg_latency_times_inputs_and_messages);
  return UNITY_END();
}
