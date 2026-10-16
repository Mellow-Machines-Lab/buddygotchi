// LinkKit alone, around the queue (linkkit/SPEC.md §2, §3, §5, §7, §9):
// messages, hello, the links, `ev`, the kit's dbg.* messages, and the lamp
// example the README walks through. A fake app; nothing of any real app's.
#include <unity.h>

#include <string>

#include "../../examples/lamp/lamp.h"
#include "../kit_fakes.h"
#include "linkkit/line_reader.h"

using kitfake::count;
using kitfake::ended;
using kitfake::has;
using kitfake::Rig;
using linkkit::Link;

void setUp() {}
void tearDown() {}

// §9: the numbers the kit keeps.
static void test_the_limits() {
  TEST_ASSERT_EQUAL(1, linkkit::kVersion);
  TEST_ASSERT_EQUAL(512, int(linkkit::kMaxLine));
  TEST_ASSERT_EQUAL(512, int(linkkit::LineReader::kMax));
  TEST_ASSERT_EQUAL(32, linkkit::kMaxDoes);
  TEST_ASSERT_EQUAL(4, linkkit::kMaxWaiting);
  TEST_ASSERT_EQUAL_UINT32(5000, linkkit::kDefaultTtlMs);
  TEST_ASSERT_EQUAL_UINT32(60000, linkkit::kMaxTtlMs);
  TEST_ASSERT_EQUAL_UINT32(30000, linkkit::kHostGoneMs);
  TEST_ASSERT_EQUAL_UINT32(60000, linkkit::kHelloMs);
  TEST_ASSERT_EQUAL_UINT32(60000, linkkit::kThawMs);
}

// §2: a message that isn't a JSON object with a `t`, or of a type the device
// doesn't know, is ignored, and unknown fields too; `state` is the app's
// whole map, untouched.
static void test_lines_the_kit_ignores() {
  Rig r;
  for (const char* junk : {"", "{", "not json", "[1,2]", "{\"type\":\"state\"}", "{\"t\":7}", "{\"t\":\"moment\"}",
                           "{\"t\":\"status\"}", "{\"t\":\"ev\",\"kind\":\"tap\"}"}) {
    r.usbLine(junk);
  }
  TEST_ASSERT_EQUAL(0, r.app.states);
  TEST_ASSERT_EQUAL(0, int(r.app.started.size()));
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"extra\":{\"deep\":[1]}}");
  TEST_ASSERT_EQUAL(1, r.app.states);
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"state\",\"base\":\"idle\",\"extra\":{\"deep\":[1]}}", r.app.lastState.c_str());
  r.usbLine("{\"t\":\"do\",\"name\":\"say\",\"play\":\"now\",\"future\":true}");
  TEST_ASSERT_EQUAL(1, int(r.app.started.size()));
}

// §3, §5: hello answers a host's first message on a link (any type but
// dbg.*): its kit fields, then the app's. Over Bluetooth, the first
// message since connecting; not the connect itself.
static void test_hello_answers_the_hosts_first_line() {
  Rig r;
  const std::string hello = "{\"t\":\"hello\",\"kit\":1,\"app\":\"fake\",\"id\":\"dev-0001\",\"fw\":\"1.2.3\",\"does\":[\"say\",\"show\",\"beep\"],\"x\":1}\n";
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_FALSE(has(r.usb.text, "\"hello\""));
  r.usbLine("{\"t\":\"whatever\"}");  // a type it doesn't know still counts as the host
  TEST_ASSERT_TRUE(has(r.usb.text, hello));
  r.usbLine("{\"t\":\"state\"}");
  TEST_ASSERT_EQUAL(1, count(r.usb.text, "\"hello\""));
  r.kit.connected();
  TEST_ASSERT_TRUE(r.ble.text.empty());
  r.bleLine("{\"t\":\"state\"}");
  TEST_ASSERT_EQUAL_STRING(hello.c_str(), r.ble.text.c_str());
  r.bleLine("{\"t\":\"state\"}");
  TEST_ASSERT_EQUAL(1, count(r.ble.text, "\"hello\""));
  r.kit.disconnected();
  r.kit.connected();  // a new connection: hello again on its first message
  r.bleLine("{\"t\":\"state\"}");
  TEST_ASSERT_EQUAL(2, count(r.ble.text, "\"hello\""));
}

// §3, §5: hello carries the platform's boot id, picked once per power-on,
// as 8 hex digits after fw; a platform that gives 0 has none.
static void test_hello_says_its_boot() {
  Rig r;
  r.platform.boot = 0xab12;
  r.usbLine("{\"t\":\"state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"fw\":\"1.2.3\",\"boot\":\"0000ab12\",\"does\""));
  Rig none;
  none.usbLine("{\"t\":\"state\"}");
  TEST_ASSERT_FALSE(has(none.usb.text, "\"boot\""));
}

// §5: USB is live while the host has spoken there in the last 30 s; its
// first message after 30 s of silence gets a hello again.
static void test_usb_hello_again_after_30_s_of_silence() {
  Rig r;
  r.usbLine("{\"t\":\"state\"}");
  r.platform.real = 29999;
  r.usbLine("{\"t\":\"state\"}");
  TEST_ASSERT_EQUAL(1, count(r.usb.text, "\"hello\""));
  TEST_ASSERT_TRUE(r.kit.live(Link::kUsb));
  r.platform.real = 29999 + 30000;
  TEST_ASSERT_FALSE(r.kit.live(Link::kUsb));
  r.usbLine("{\"t\":\"state\"}");
  TEST_ASSERT_EQUAL(2, count(r.usb.text, "\"hello\""));
}

// §3, §5: a host's own hello asks for the device's, on that link, even
// while the device still counts the link as live: a host relaunched
// within 30 s over USB, or one taking over a Bluetooth link the system
// kept up, which the device never saw drop. As a first message it gets one
// hello, not two.
static void test_a_hosts_hello_asks_for_one() {
  Rig r;
  r.usbLine("{\"t\":\"hello\"}");
  TEST_ASSERT_EQUAL(1, count(r.usb.text, "\"hello\""));
  TEST_ASSERT_TRUE(r.kit.live(Link::kUsb));
  r.platform.real = 5000;  // the host relaunches within 30 s
  r.usbLine("{\"t\":\"hello\"}");
  TEST_ASSERT_EQUAL(2, count(r.usb.text, "\"hello\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"hello\",\"kit\":1,\"app\":\"fake\","));
  r.usbLine("{\"t\":\"state\"}");  // then its state: no more
  TEST_ASSERT_EQUAL(2, count(r.usb.text, "\"hello\""));
  r.kit.connected();
  r.bleLine("{\"t\":\"state\"}");
  TEST_ASSERT_EQUAL(1, count(r.ble.text, "\"hello\""));
  r.platform.real = 9000;  // a new app on the same Bluetooth link: no reconnect
  r.bleLine("{\"t\":\"hello\"}");
  r.bleLine("{\"t\":\"state\"}");
  TEST_ASSERT_EQUAL(2, count(r.ble.text, "\"hello\""));
  TEST_ASSERT_EQUAL(2, count(r.usb.text, "\"hello\""));  // each on its own link
  r.usbLine("{\"t\":\"dbg.hello\"}");  // not a tool's
  TEST_ASSERT_EQUAL(2, count(r.usb.text, "\"hello\""));
}

// §3, §2: a hello longer than 512 bytes would be dropped whole on the
// way, so the host would never hear it. The app's fields are left out,
// or, when even the kit's don't fit, none goes; dbg.ping says how long
// the whole one is.
static void test_a_hello_too_long_goes_short_or_not_at_all() {
  kitfake::Platform p;
  kitfake::App app;
  static std::string names[32];
  app.names.clear();
  for (int i = 0; i < 32; ++i) names[i] = "n" + std::to_string(10 + i), app.names.push_back(names[i].c_str());
  linkkit::Kit kit(p, app, true);
  kitfake::Capture usb;
  kit.setOut(Link::kUsb, &usb);
  TEST_ASSERT_TRUE(kit.helloLength() <= linkkit::kMaxLine);  // 32 short names: it fits
  // The app's own field takes it over.
  struct Wordy : kitfake::App {
    void hello(JsonObject extra) override { extra["pad"] = std::string(300, 'x'); }
  } wordy;
  wordy.names = app.names;
  linkkit::Kit kit2(p, wordy, true);
  kitfake::Capture usb2;
  kit2.setOut(Link::kUsb, &usb2);
  TEST_ASSERT_TRUE(kit2.helloLength() > linkkit::kMaxLine);
  kit2.handleLine("{\"t\":\"state\"}", 13, Link::kUsb);
  TEST_ASSERT_TRUE(has(usb2.text, "{\"t\":\"hello\",\"kit\":1,\"app\":\"fake\","));
  TEST_ASSERT_TRUE(has(usb2.text, "\"n41\"]}\n"));  // the kit's fields only
  TEST_ASSERT_FALSE(has(usb2.text, "\"pad\""));
  TEST_ASSERT_TRUE(usb2.text.size() - 1 <= linkkit::kMaxLine);
  usb2.text.clear();
  kit2.handleLine("{\"t\":\"dbg.ping\"}", 16, Link::kUsb);
  TEST_ASSERT_TRUE(has(usb2.text, "\"hello_long\":" + std::to_string(kit2.helloLength()) + ","));
  // Names too long even for the kit's fields: no hello at all.
  static std::string longNames[32];
  wordy.names.clear();
  for (int i = 0; i < 32; ++i) longNames[i] = std::string(20, char('a' + i % 26)), wordy.names.push_back(longNames[i].c_str());
  linkkit::Kit kit3(p, wordy, true);
  kitfake::Capture usb3;
  kit3.setOut(Link::kUsb, &usb3);
  kit3.handleLine("{\"t\":\"state\"}", 13, Link::kUsb);
  TEST_ASSERT_FALSE(has(usb3.text, "\"hello\""));
  kit3.handleLine("{\"t\":\"dbg.ping\"}", 16, Link::kUsb);
  TEST_ASSERT_TRUE(has(usb3.text, "\"hello_long\":"));
  // One that fits says nothing of it.
  kit.handleLine("{\"t\":\"dbg.ping\"}", 16, Link::kUsb);
  TEST_ASSERT_FALSE(has(usb.text, "hello_long"));
}

// §5: hello goes again every 60 s, on the link the host last spoke on,
// while that link is live, and when the app says something in it changed.
static void test_hello_every_60_s_on_the_hosts_link() {
  Rig r;
  r.kit.connected();
  r.bleLine("{\"t\":\"state\"}");  // hello at 0
  r.platform.real = 20000;
  r.usbLine("{\"t\":\"state\"}");  // hello on USB at 20000; the host's link is USB now
  r.platform.real = 20000 + 59999;
  r.kit.tick();
  TEST_ASSERT_EQUAL(1, count(r.ble.text, "\"hello\""));
  TEST_ASSERT_EQUAL(1, count(r.usb.text, "\"hello\""));
  r.bleLine("{\"t\":\"state\"}");  // back on Bluetooth
  r.platform.real = 80000;
  r.kit.tick();
  TEST_ASSERT_EQUAL(2, count(r.ble.text, "\"hello\""));
  TEST_ASSERT_EQUAL(1, count(r.usb.text, "\"hello\""));
  r.app.k().helloChanged();
  TEST_ASSERT_EQUAL(3, count(r.ble.text, "\"hello\""));
  r.kit.disconnected();  // not live: no repeat, no change
  r.platform.real = 300000;
  r.kit.tick();
  r.app.k().helloChanged();
  TEST_ASSERT_EQUAL(3, count(r.ble.text, "\"hello\""));
}

// §3, §9: hello.does has at most 32 names.
static void test_does_is_capped_at_32() {
  kitfake::Platform p;
  kitfake::App app;
  static std::string names[40];
  app.names.clear();
  for (int i = 0; i < 40; ++i) names[i] = "n" + std::to_string(i), app.names.push_back(names[i].c_str());
  linkkit::Kit kit(p, app, true);
  kitfake::Capture usb;
  kit.setOut(Link::kUsb, &usb);
  kit.handleLine("{\"t\":\"state\"}", 13, Link::kUsb);
  TEST_ASSERT_TRUE(has(usb.text, "\"n31\"]"));
  TEST_ASSERT_FALSE(has(usb.text, "\"n32\""));
  kit.handleLine("{\"t\":\"do\",\"id\":1,\"name\":\"n35\"}", 30, Link::kUsb);
  TEST_ASSERT_TRUE(has(usb.text, ended(1, "skipped", "unknown")));
}

// §5: 30 s with no message from the host: it's gone. A Bluetooth link is to
// be dropped (and again 30 s later if that didn't take), and USB is no
// longer live.
static void test_the_host_is_gone_after_30_s() {
  Rig r;
  r.platform.real = 1000;
  r.kit.connected();
  TEST_ASSERT_FALSE(r.kit.shouldDrop());
  r.bleLine("{\"t\":\"state\"}");
  r.platform.real = 1000 + 29999;
  TEST_ASSERT_FALSE(r.kit.shouldDrop());
  r.platform.real = 1000 + 30000;
  TEST_ASSERT_TRUE(r.kit.shouldDrop());
  TEST_ASSERT_FALSE(r.kit.shouldDrop());
  r.platform.real = 1000 + 60000;
  TEST_ASSERT_TRUE(r.kit.shouldDrop());
  r.kit.disconnected();
  TEST_ASSERT_FALSE(r.kit.shouldDrop());
  r.usbLine("{\"t\":\"dbg.ping\"}");  // a tool isn't the host
  TEST_ASSERT_FALSE(r.kit.live(Link::kUsb));
  r.usbLine("{\"t\":\"state\"}");
  r.platform.real = 1000 + 60000 + 29999;
  TEST_ASSERT_TRUE(r.kit.live(Link::kUsb));
  r.platform.real = 1000 + 60000 + 30000;
  TEST_ASSERT_FALSE(r.kit.live(Link::kUsb));
}

// §3, §5: an app's ev goes on every live link; one from input a tool
// injected goes only over USB, live or not. `ended` is the kit's (§4).
static void test_ev_goes_on_every_live_link() {
  Rig r;
  r.app.k().emit("tap", "poked", nullptr, false);
  TEST_ASSERT_TRUE(r.usb.text.empty() && r.ble.text.empty());  // no host
  r.kit.connected();
  r.app.k().emit("tap", "poked", nullptr, false);
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"ev\",\"kind\":\"tap\",\"did\":\"poked\"}\n", r.ble.text.c_str());
  TEST_ASSERT_TRUE(r.usb.text.empty());
  r.usbLine("{\"t\":\"state\"}");
  r.usb.text.clear(), r.ble.text.clear();
  r.app.k().emit("tap", nullptr, "{\"on\":42}", false);
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"ev\",\"kind\":\"tap\",\"data\":{\"on\":42}}\n", r.ble.text.c_str());
  TEST_ASSERT_EQUAL_STRING(r.ble.text.c_str(), r.usb.text.c_str());
  r.usb.text.clear(), r.ble.text.clear();
  r.app.k().emit("hold", nullptr, nullptr, true);
  TEST_ASSERT_TRUE(r.ble.text.empty());
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"ev\",\"kind\":\"hold\"}\n", r.usb.text.c_str());
  // §2: a message never goes out longer than 512 bytes.
  std::string big = "{\"pad\":\"" + std::string(500, 'x') + "\"}";
  r.usb.text.clear();
  r.app.k().emit("big", nullptr, big.c_str(), true);
  TEST_ASSERT_TRUE(r.usb.text.empty());
}

// §2, §4: the app's words go in the message as JSON strings, so a quote, a
// backslash or a control character in an `ev`'s kind or did, or in a
// refusal's why, can't break it; an `ev`'s data goes as it is.
static void test_the_apps_words_are_escaped() {
  Rig r;
  r.usbLine("{\"t\":\"state\"}");
  r.usb.text.clear();
  r.app.k().emit("say \"hi\"", "a\\b\n", "{\"n\":1}", false);
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"ev\",\"kind\":\"say \\\"hi\\\"\",\"did\":\"a\\\\b\\u000a\",\"data\":{\"n\":1}}\n",
                           r.usb.text.c_str());
  JsonDocument d;
  TEST_ASSERT_TRUE(deserializeJson(d, r.usb.text) == DeserializationError::Ok);
  TEST_ASSERT_EQUAL_STRING("say \"hi\"", d["kind"].as<const char*>());
  TEST_ASSERT_EQUAL_STRING("a\\b\n", d["did"].as<const char*>());
  r.usb.text.clear();
  r.app.refuseWith = "not \"now\"";
  r.doLine(7, "say", "now");
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"ev\",\"kind\":\"ended\",\"data\":{\"id\":7,\"how\":\"skipped\",\"why\":\"not \\\"now\\\"\"}}\n",
                           r.usb.text.c_str());
  TEST_ASSERT_TRUE(deserializeJson(d, r.usb.text) == DeserializationError::Ok);
  TEST_ASSERT_EQUAL_STRING("not \"now\"", d["data"]["why"].as<const char*>());
}

// §7: dbg.* works only over USB, and never counts as the host speaking.
static void test_debug_is_usb_only() {
  Rig r;
  r.kit.connected();
  TEST_ASSERT_FALSE(r.kit.handleLine("{\"t\":\"dbg.ping\"}", 16, Link::kBle));
  TEST_ASSERT_TRUE(r.ble.text.empty());
  TEST_ASSERT_TRUE(r.kit.handleLine("{\"t\":\"dbg.ping\"}", 16, Link::kUsb));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"link\":\"none\""));
  TEST_ASSERT_FALSE(r.kit.handleLine("{\"t\":\"state\"}", 13, Link::kUsb));
}

// §7: dbg.ping: the kit's fields, then the app's vitals.
static void test_ping() {
  Rig r;
  r.platform.real = 4321;
  r.usbLine("{\"t\":\"state\"}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"dbg.ping\",\"kit\":1,\"fw\":\"1.2.3\",\"up\":4321,\"link\":\"usb\",\"ble\":\"off\",\"vital\":7}\n",
                           r.usb.text.c_str());
}

// §7: dbg.clock freezes (reseeding the randomness from T), steps and runs
// the clock; a frozen clock runs again by itself after 60 s with no dbg.*.
// The simulator's own start, frozen, stays frozen.
static void test_clock_freezes_steps_runs_and_thaws() {
  Rig r;
  r.platform.real = 100000;
  r.kit.tick();
  TEST_ASSERT_EQUAL_UINT32(0, r.kit.now());  // started frozen: not a tool's doing
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":5000}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"dbg.clock\",\"now\":5000,\"frozen\":true}\n"));
  linkkit::Rng seeded;
  seeded.seed(5000);
  TEST_ASSERT_EQUAL_UINT32(seeded.next(), r.kit.rng().next());
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":250}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"dbg.clock\",\"now\":5250,\"frozen\":true}\n"));
  r.platform.real = 130000;
  r.usbLine("{\"t\":\"state\"}");  // the host doesn't hold it
  r.platform.real = 159999;
  r.kit.tick();
  TEST_ASSERT_EQUAL_UINT32(5250, r.kit.now());
  r.platform.real = 160000;
  r.kit.tick();
  r.platform.real = 160100;
  TEST_ASSERT_EQUAL_UINT32(5350, r.kit.now());
  TEST_ASSERT_FALSE(r.kit.frozen());
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":10}");
  r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"dbg.clock\",\"now\":10,\"frozen\":false}\n"));
  r.platform.real = 160600;
  TEST_ASSERT_EQUAL_UINT32(510, r.kit.now());
}

// §7: dbg.reset freezes the clock at 0, reseeds from 0, and resets the app.
static void test_reset_freezes_at_0() {
  Rig r(false);
  r.platform.real = 7000;
  TEST_ASSERT_EQUAL_UINT32(7000, r.kit.now());
  r.usbLine("{\"t\":\"dbg.reset\"}");
  TEST_ASSERT_EQUAL_UINT32(0, r.kit.now());
  TEST_ASSERT_TRUE(r.kit.frozen());
  TEST_ASSERT_EQUAL(1, r.app.resets);
  linkkit::Rng seeded;
  seeded.seed(0);
  TEST_ASSERT_EQUAL_UINT32(seeded.next(), r.kit.rng().next());
}

// §7: a running device's randomness starts from its boot id, so each
// power-on differs; a frozen one (the simulator, tests) starts where every
// dbg.reset leaves it.
static void test_a_running_device_seeds_from_its_boot() {
  kitfake::Platform p;
  p.boot = 0xab12;
  kitfake::App onBoard, onSim;
  linkkit::Kit board(p, onBoard, false), sim(p, onSim, true);
  linkkit::Rng boot, reset;
  boot.seed(0xab12);
  reset.seed(0);
  TEST_ASSERT_EQUAL_UINT32(boot.next(), board.rng().next());
  TEST_ASSERT_EQUAL_UINT32(reset.next(), sim.rng().next());
}

// §7: dbg.shot: a header with the app's frame's size, byte count and
// CRC-32, then its bytes in base64; an app with no frame sends none.
static void test_shot() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.shot\"}");
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"dbg.shot\",\"w\":0,\"h\":0,\"bytes\":0,\"crc\":0}\n\n", r.usb.text.c_str());
  const uint8_t px[2] = {'h', 'i'};
  r.app.frame = px;
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.shot\"}");
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"dbg.shot\",\"w\":2,\"h\":1,\"bytes\":2,\"crc\":3633523372}\naGk=\n", r.usb.text.c_str());
}

// §7: dbg.state: the app's fields, then the kit's clock, rx and queue.
static void test_dbg_state() {
  Rig r;
  r.usbLine("{\"t\":\"state\"}");
  r.doLine(0, "say", "now");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"dbg.state\",\"mine\":true,\"clock\":{\"now\":0,\"frozen\":true},\"rx\":{\"state\":1,\"do\":1},"
                           "\"turn\":{\"holder\":{\"id\":null,\"name\":\"say\",\"resting\":false},\"waiting\":[]}}\n",
                           r.usb.text.c_str());
}

// §7: an unknown dbg.* gets no reply; the app answers its own.
static void test_the_apps_debug_messages() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.nope\"}");
  TEST_ASSERT_TRUE(r.usb.text.empty());
  r.usbLine("{\"t\":\"dbg.fake\"}");
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"dbg.fake\"}\n", r.usb.text.c_str());
}

// The app is attached and begun before the kit's first message, and
// ticked after the queue's timers on every pass.
static void test_the_app_is_begun_and_ticked() {
  Rig r;
  TEST_ASSERT_EQUAL(1, r.app.begun);
  r.kit.tick();
  r.kit.tick();
  TEST_ASSERT_EQUAL(2, r.app.ticks);
  TEST_ASSERT_EQUAL_UINT32(0, r.app.advanced.back());
}

// linkkit/device/README.md's lamp: its state, a blink that plays through,
// one that waits in the queue, and its own button cutting one.
static void test_the_lamp_example() {
  kitfake::Platform p;
  lamp::Lamp app;
  linkkit::Kit kit(p, app, true);
  kitfake::Capture usb;
  kit.setOut(Link::kUsb, &usb);
  auto line = [&](const std::string& s) {
    kit.handleLine(s.data(), s.size(), Link::kUsb);
    kit.tick();
  };
  line("{\"t\":\"state\",\"level\":40}");
  TEST_ASSERT_TRUE(has(usb.text, "{\"t\":\"hello\",\"kit\":1,\"app\":\"lamp\",\"id\":\"dev-0001\",\"fw\":\"1.2.3\",\"does\":[\"blink\"]}\n"));
  TEST_ASSERT_EQUAL(40, app.light());
  line("{\"t\":\"do\",\"id\":1,\"name\":\"blink\",\"args\":{\"times\":2}}");
  TEST_ASSERT_EQUAL(255, app.light());
  line("{\"t\":\"do\",\"id\":2,\"name\":\"blink\"}");  // waits for the first
  line("{\"t\":\"dbg.clock\",\"freeze\":100}");
  TEST_ASSERT_EQUAL(40, app.light());
  line("{\"t\":\"dbg.clock\",\"freeze\":1000}");
  TEST_ASSERT_TRUE(has(usb.text, ended(1, "done")));
  TEST_ASSERT_TRUE(has(usb.text, ended(2, "done")));  // started at 400, over at 600
  line("{\"t\":\"do\",\"id\":3,\"name\":\"blink\",\"args\":{\"times\":10}}");
  app.press();
  TEST_ASSERT_TRUE(has(usb.text, ended(3, "cut", "button")));
  TEST_ASSERT_TRUE(has(usb.text, "{\"t\":\"ev\",\"kind\":\"press\",\"did\":\"stopped\"}\n"));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_the_limits);
  RUN_TEST(test_lines_the_kit_ignores);
  RUN_TEST(test_hello_answers_the_hosts_first_line);
  RUN_TEST(test_hello_says_its_boot);
  RUN_TEST(test_usb_hello_again_after_30_s_of_silence);
  RUN_TEST(test_a_hosts_hello_asks_for_one);
  RUN_TEST(test_a_hello_too_long_goes_short_or_not_at_all);
  RUN_TEST(test_hello_every_60_s_on_the_hosts_link);
  RUN_TEST(test_does_is_capped_at_32);
  RUN_TEST(test_the_host_is_gone_after_30_s);
  RUN_TEST(test_ev_goes_on_every_live_link);
  RUN_TEST(test_the_apps_words_are_escaped);
  RUN_TEST(test_debug_is_usb_only);
  RUN_TEST(test_ping);
  RUN_TEST(test_clock_freezes_steps_runs_and_thaws);
  RUN_TEST(test_reset_freezes_at_0);
  RUN_TEST(test_a_running_device_seeds_from_its_boot);
  RUN_TEST(test_shot);
  RUN_TEST(test_dbg_state);
  RUN_TEST(test_the_apps_debug_messages);
  RUN_TEST(test_the_app_is_begun_and_ticked);
  RUN_TEST(test_the_lamp_example);
  return UNITY_END();
}
