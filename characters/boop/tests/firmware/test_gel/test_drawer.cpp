// The agents' drawer on the gel (render/drawer.h, render/gel/drawer.h,
// app::Device): what a finger on the strip and on the rows tells the Mac,
// when it shuts itself, where its rows are, and that its frames allocate
// nothing.
#include <unity.h>

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "app/device.h"
#include "linkkit/kit.h"
#include "render/gel/drawer.h"
#include "render/gel/painter.h"

using namespace render;
using namespace render::gel;

extern long allocCount;
extern bool allocCounting;

namespace {

struct Hal : app::Hal {
  uint32_t realMs() override { return 0; }
  const char* fwVersion() override { return "t"; }
  const char* gitSha() override { return "t"; }
};

struct Capture : linkkit::Out {
  std::string text;
  void write(const char* s, size_t n) override { text.append(s, n); }
};

// A gel board on USB, its clock frozen, with sessions to list.
struct Board {
  Hal hal;
  Capture usb;
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(kWidth) * kHeight);
  std::unique_ptr<app::Device> dev;
  std::unique_ptr<linkkit::Kit> kit;
  uint32_t t = 0;
  Board() {
    setenv("BOOP_SIM_FACE", "gel", 1);
    dev = std::make_unique<app::Device>(hal, px.data());
    kit = std::make_unique<linkkit::Kit>(hal, *dev, true);
    unsetenv("BOOP_SIM_FACE");
    kit->setOut(linkkit::Link::kUsb, &usb);
    line("{\"t\":\"dbg.clock\",\"freeze\":0}");
    line(kState);
  }
  static constexpr const char* kState =
      "{\"t\":\"state\",\"base\":\"working\",\"busy\":2,\"idle\":1,\"vol\":0}";
  static constexpr const char* kListed =
      "{\"t\":\"state\",\"base\":\"working\",\"busy\":2,\"idle\":1,\"vol\":0,\"list\":[[11,\"n\",-1,\"codex\",\"Hero "
      "copy\",\"landing\"],[12,\"w\",0,\"claude\",\"Fix the lane colours\",\"buddygotchi\"],[14,\"i\",-1,"
      "\"claude\",\"harness\",\"\"]]}";
  void line(const char* s) {
    kit->handleLine(s, std::strlen(s), linkkit::Link::kUsb);
    kit->tick();
    if (dev->takeFrame()) dev->frames()->present(dev->canvas());
  }
  // The clock on by `ms`, a tick every 20.
  void run(uint32_t ms) {
    for (uint32_t done = 0; done < ms; done += 20) {
      char step[64];
      std::snprintf(step, sizeof(step), "{\"t\":\"dbg.clock\",\"freeze\":%lu}", (unsigned long)(t += 20));
      line(step);
    }
  }
  void touch(int x, int y, int toX, int toY, int ms) {
    char s[128];
    std::snprintf(s, sizeof(s), "{\"t\":\"dbg.touch\",\"x\":%d,\"y\":%d,\"to_x\":%d,\"to_y\":%d,\"ms\":%d}", x, y,
                  toX, toY, ms);
    line(s);
  }
  int open() {
    usb.text.clear();
    line("{\"t\":\"dbg.state\"}");
    const size_t i = usb.text.find("\"drawer\":{\"open\":");
    return i == std::string::npos ? -9999 : std::atoi(usb.text.c_str() + i + 17);
  }
  int count(const char* needle) const {
    int n = 0;
    for (size_t at = usb.text.find(needle); at != std::string::npos; at = usb.text.find(needle, at + 1)) ++n;
    return n;
  }
};

constexpr const char* kOpen = "{\"t\":\"ev\",\"kind\":\"drawer\",\"did\":\"open\"}";
constexpr const char* kClosed = "{\"t\":\"ev\",\"kind\":\"drawer\",\"did\":\"closed\"}";

// Pulled up from the strip, let go open, and the Mac's rows in.
void pullOpen(Board& b) {
  b.touch(160, 232, 160, 40, 320);
  b.run(400);
  b.line(Board::kListed);
  b.run(app::Device::kDrawerMs + 100);
}

}  // namespace

// A finger up from the strip pulls the drawer: the Mac hears "open" as it
// starts, and nothing else of the touch (no tap, no swipe); let go high, it
// springs open, past its end and back (kDrawerMs).
void test_a_pull_up_the_strip_opens_the_drawer() {
  Board b;
  b.usb.text.clear();
  b.touch(160, 232, 160, 40, 320);
  b.run(100);
  TEST_ASSERT_EQUAL_INT(1, b.count(kOpen));
  b.run(300);
  TEST_ASSERT_EQUAL_INT(0, b.count("\"kind\":\"tap\""));
  TEST_ASSERT_EQUAL_INT(0, b.count("\"kind\":\"gesture\""));
  b.run(app::Device::kDrawerMs / 2);
  TEST_ASSERT_TRUE(b.open() > 1000);  // springing past its end
  b.run(app::Device::kDrawerMs);
  TEST_ASSERT_EQUAL_INT(1000, b.open());
}

// A swipe up that starts on the face, above the strip, is the face's, as
// it was: the dome flung, the Mac told `swipe`, and no drawer.
void test_a_swipe_up_the_face_isnt_the_drawers() {
  Board b;
  b.usb.text.clear();
  b.touch(160, 200, 160, 60, 160);
  b.run(400);
  TEST_ASSERT_EQUAL_INT(0, b.count(kOpen));
  TEST_ASSERT_EQUAL_INT(1, b.count("{\"t\":\"ev\",\"kind\":\"gesture\",\"did\":\"swipe\""));
  TEST_ASSERT_EQUAL_INT(0, b.open());
}

// A short pull, let go low and slow, springs back shut, and the Mac hears
// it closed again.
void test_a_short_pull_springs_back_shut() {
  Board b;
  b.usb.text.clear();
  b.touch(160, 232, 160, 200, 600);
  b.run(700 + app::Device::kDrawerMs);
  TEST_ASSERT_EQUAL_INT(1, b.count(kOpen));
  TEST_ASSERT_EQUAL_INT(1, b.count(kClosed));
  TEST_ASSERT_EQUAL_INT(0, b.open());
}

// A tap on a row sends that row's id, the Mac's number for the session
// (`pick`), and shuts the drawer (closed) as Boop hands it over; a tap
// beside the rows only shuts it.
void test_a_tap_on_a_row_picks_it() {
  Board b;
  pullOpen(b);
  b.usb.text.clear();
  b.touch(160, 112, 160, 112, 60);  // the second row, as the panel reads it
  b.run(100);
  TEST_ASSERT_EQUAL_INT(1, b.count("{\"t\":\"ev\",\"kind\":\"drawer\",\"did\":\"pick\",\"data\":{\"id\":12}}"));
  TEST_ASSERT_EQUAL_INT(1, b.count(kClosed));
  b.run(app::Device::kDrawerMs);
  TEST_ASSERT_EQUAL_INT(0, b.open());

  pullOpen(b);
  b.usb.text.clear();
  b.touch(160, 230, 160, 230, 60);  // under the last row
  b.run(100 + app::Device::kDrawerMs);
  TEST_ASSERT_EQUAL_INT(0, b.count("\"did\":\"pick\""));
  TEST_ASSERT_EQUAL_INT(1, b.count(kClosed));
  TEST_ASSERT_EQUAL_INT(0, b.open());
}

// Open and untouched, it shuts itself kDrawerShutMs after the last touch;
// until then it says "open" again every kDrawerSayMs, and every
// kDrawerAskMs while no rows have come, so a Mac that started since hears.
void test_it_shuts_itself_and_says_its_open_till_then() {
  Board b;
  b.touch(160, 232, 160, 40, 320);
  b.run(400);  // let go at 320; the Mac sends no rows
  b.usb.text.clear();
  b.run(app::Device::kDrawerAskMs + 100);
  TEST_ASSERT_EQUAL_INT(1, b.count(kOpen));
  b.line(Board::kListed);  // at 2500, the last "open" at about 2040
  b.usb.text.clear();
  b.run(app::Device::kDrawerSayMs - 700);
  TEST_ASSERT_EQUAL_INT(0, b.count(kOpen));
  b.run(400);
  TEST_ASSERT_EQUAL_INT(1, b.count(kOpen));
  TEST_ASSERT_EQUAL_INT(1000, b.open());
  b.run(app::Device::kDrawerShutMs - b.t - 200);  // let go at about 340
  TEST_ASSERT_EQUAL_INT(1000, b.open());
  b.usb.text.clear();
  b.run(800);
  TEST_ASSERT_EQUAL_INT(1, b.count(kClosed));
}

// BOOT pressed while it's open shuts it, and does what BOOT does.
void test_boot_shuts_it() {
  Board b;
  pullOpen(b);
  b.usb.text.clear();
  b.line("{\"t\":\"dbg.press\",\"ms\":100}");
  b.run(200 + app::Device::kDrawerMs);
  TEST_ASSERT_EQUAL_INT(1, b.count(kClosed));
  TEST_ASSERT_EQUAL_INT(1, b.count("\"kind\":\"tap\""));
  TEST_ASSERT_EQUAL_INT(0, b.open());
}

// Its rows on the AMOLED: five, each whole inside the panel's rounded
// corners, the second where the panel reads a finger at canvas (160, 112),
// and none under one beside them; the sheet shut is the strip's rule.
void test_the_drawers_rows_on_the_panel() {
  const DrawerLayout l(502, 410, 110);
  TEST_ASSERT_EQUAL_INT(410 * kStripTop / kHeight, l.top(0));
  TEST_ASSERT_EQUAL_INT(66, l.top(1000));
  const int last = l.rowTop(1000, Drawer::kRows - 1);
  TEST_ASSERT_TRUE(last + l.rowH() <= 410 - 4);
  TEST_ASSERT_TRUE(l.margin() >= Surface::insetOf(502, 410, 110, last, last + l.rowH(), 10));
  Drawer d;
  d.count = 3;
  TEST_ASSERT_EQUAL_INT(1, l.rowAt(d, 160, 112));
  TEST_ASSERT_EQUAL_INT(0, l.rowAt(d, 160, 78));
  TEST_ASSERT_EQUAL_INT(-1, l.rowAt(d, 160, 230));
  TEST_ASSERT_EQUAL_INT(-1, l.rowAt(d, 2, 112));
  d.count = Drawer::kRows, d.unlisted = 2;  // the last row's place says how many more
  TEST_ASSERT_EQUAL_INT(-1, l.rowAt(d, 160, l.rowTop(1000, Drawer::kRows - 1) * 2 / 3 - 8));
}

// Pressed flat under it, the body fills the rows above the sheet's edge
// and squeezes its eyes shut past six tenths flat; shut, it's at rest.
void test_the_body_under_the_drawer() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  s.corner = 110;
  Drawer d;
  d.open = 0;
  DrawerPose rest = drawerPose(s, d);
  TEST_ASSERT_EQUAL_INT(restBodyTop(410), rest.top);
  TEST_ASSERT_EQUAL_INT(restBodyBottom(410), rest.bottom);
  TEST_ASSERT_FALSE(rest.squint);
  d.open = 1000;
  DrawerPose open = drawerPose(s, d);
  TEST_ASSERT_TRUE(open.top >= 0 && open.top < 10);
  TEST_ASSERT_EQUAL_INT(DrawerLayout(502, 410, 110).top(1000) + 6, open.bottom);
  TEST_ASSERT_TRUE(open.squint);
  TEST_ASSERT_TRUE(open.widen > 4096 && open.widen < 4096 * 11 / 10);
}

// Its frames, open and springing shut, allocate nothing.
void test_drawer_frames_allocate_nothing() {
  Board b;
  b.run(3000);  // into the look's loop, as test_steady_frames_allocate_nothing
  pullOpen(b);
  allocCount = 0;
  allocCounting = true;
  b.run(1000);
  allocCounting = false;
  TEST_ASSERT_EQUAL_INT(0, int(allocCount));
  b.touch(160, 232, 160, 232, 60);  // shutting, beside the rows
  b.run(40);
  allocCount = 0;
  allocCounting = true;
  b.run(app::Device::kDrawerMs);
  allocCounting = false;
  TEST_ASSERT_EQUAL_INT(0, int(allocCount));
}
