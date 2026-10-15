// A platform and an app for testing the kit alone (test_turn, test_kit):
// nothing of any real app's. The app records what the kit asks of it, and the test
// scripts its answers.
#pragma once
#include <ArduinoJson.h>

#include <cstring>
#include <string>
#include <vector>

#include "linkkit/kit.h"

namespace kitfake {

struct Platform : linkkit::Platform {
  uint32_t real = 0;
  uint32_t realMs() override { return real; }
  const char* deviceId() override { return "dev-0001"; }
  const char* fwVersion() override { return "1.2.3"; }
  uint32_t boot = 0;  // 0: hello says none
  uint32_t bootId() override { return boot; }
};

struct Capture : linkkit::Out {
  std::string text;
  void write(const char* s, size_t n) override { text.append(s, n); }
};

// What onDo was handed.
struct Started {
  uint32_t key;
  int32_t id;
  std::string name;
  uint32_t t;
  std::string args;  // as JSON
  linkkit::Play play;
};

class App : public linkkit::App {
 public:
  // Its does: the first three a test may play; `names` for more.
  std::vector<const char*> names = {"say", "show", "beep"};

  // Scripted answers.
  const char* refuseWith = nullptr;          // refuse's answer for every call
  std::vector<std::string> refuseNames;       // or only for these names ("no")
  bool restAtStart = false;                   // rest each call as it starts
  bool endAtStart = false;                    // end each call as it starts
  bool endHolderInRefuse = false;             // refuse ends the holder, as Boop's reply ends listening
  // Timers the app keeps: rest or end `key` at `at`.
  struct Timer {
    uint32_t key, at;
    bool end;
  };
  std::vector<Timer> timers;

  // What it saw.
  std::vector<Started> started;
  std::vector<uint32_t> refused;  // keys refuse was asked about
  std::vector<uint32_t> advanced;
  int states = 0, ticks = 0, resets = 0, begun = 0;
  std::string lastState;

  linkkit::Kit& k() { return kit(); }

  const char* name() const override { return "fake"; }
  int does(const char* const*& n) const override {
    n = names.data();
    return int(names.size());
  }
  void hello(JsonObject extra) override { extra["x"] = 1; }
  void begin() override { ++begun; }
  void onState(JsonObjectConst s, uint32_t) override {
    ++states;
    lastState.clear();
    serializeJson(s, lastState);
  }
  const char* refuse(const linkkit::Call& c, uint32_t) override {
    refused.push_back(c.key);
    if (endHolderInRefuse) kit().ended(kit().turn().key);
    for (const std::string& n : refuseNames)
      if (n == c.name) return "no";
    return refuseWith;
  }
  void onDo(const linkkit::Call& c, uint32_t t) override {
    std::string args;
    serializeJson(c.args, args);
    started.push_back({c.key, c.id, c.name, t, args, c.play});
    if (restAtStart) kit().rest(c.key);
    if (endAtStart) kit().ended(c.key);
  }
  void advance(uint32_t t) override {
    advanced.push_back(t);
    for (size_t i = 0; i < timers.size();) {
      if (int32_t(t - timers[i].at) >= 0) {
        Timer x = timers[i];
        timers.erase(timers.begin() + long(i));
        if (x.end) kit().ended(x.key);
        else kit().rest(x.key);
      } else {
        ++i;
      }
    }
  }
  bool nextDue(uint32_t from, uint32_t to, uint32_t& at) override {
    bool found = false;
    for (const Timer& x : timers) {
      if (int32_t(x.at - from) > 0 && int32_t(x.at - to) <= 0 && (!found || int32_t(at - x.at) > 0)) at = x.at, found = true;
    }
    return found;
  }
  void tick(uint32_t) override { ++ticks; }
  bool debug(const char* type, JsonObjectConst, linkkit::Link from) override {
    if (std::strcmp(type, "dbg.fake")) return false;
    kit().reply(from, "{\"t\":\"dbg.fake\"}", 16);
    return true;
  }
  void ping(JsonObject r) override { r["vital"] = 7; }
  void state(JsonObject r, uint32_t) override { r["mine"] = true; }
  void reset() override { ++resets; }
  bool shot(linkkit::Shot& s, uint32_t) override {
    if (!frame) return false;
    s.w = 2, s.h = 1;
    s.data[0] = frame, s.size[0] = 2;
    return true;
  }
  const uint8_t* frame = nullptr;
};

// A kit with its links captured and the clock frozen at 0.
struct Rig {
  Platform platform;
  App app;
  Capture usb, ble;
  linkkit::Kit kit;
  explicit Rig(bool frozen = true) : kit(platform, app, frozen) {
    kit.setOut(linkkit::Link::kUsb, &usb);
    kit.setOut(linkkit::Link::kBle, &ble);
  }
  void usbLine(const std::string& s) {
    kit.handleLine(s.data(), s.size(), linkkit::Link::kUsb);
    kit.tick();
  }
  void bleLine(const std::string& s) {
    kit.handleLine(s.data(), s.size(), linkkit::Link::kBle);
    kit.tick();
  }
  // The frozen clock, moved to `t` by a tool.
  void clock(uint32_t t) { usbLine("{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(t) + "}"); }
  // A do from the host over USB.
  void doLine(int id, const char* name, const char* play, const char* more = "") {
    std::string s = "{\"t\":\"do\"";
    if (id) s += ",\"id\":" + std::to_string(id);
    s += std::string(",\"name\":\"") + name + "\"";
    if (play) s += std::string(",\"play\":\"") + play + "\"";
    s += more;
    s += "}";
    usbLine(s);
  }
};

inline bool has(const std::string& s, const std::string& needle) { return s.find(needle) != std::string::npos; }
inline int count(const std::string& s, const std::string& needle) {
  int n = 0;
  for (size_t at = s.find(needle); at != std::string::npos; at = s.find(needle, at + 1)) ++n;
  return n;
}
// The `ended` line for id, as the kit sends it.
inline std::string ended(int id, const char* how, const char* why = nullptr) {
  std::string s = "{\"t\":\"ev\",\"kind\":\"ended\",\"data\":{\"id\":" + std::to_string(id) + ",\"how\":\"" + how + "\"";
  if (why) s += std::string(",\"why\":\"") + why + "\"";
  return s + "}}\n";
}

}  // namespace kitfake
