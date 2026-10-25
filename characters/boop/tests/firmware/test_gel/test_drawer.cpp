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
    if (dev->takeFrame()) dev->frames()->present();
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
  // How far its rows are scrolled (dbg.state's drawer.scroll), leaving
  // what the board said before.
  int scroll() {
    const size_t from = usb.text.size();
    line("{\"t\":\"dbg.state\"}");
    const size_t i = usb.text.find("\"scroll\":", usb.text.find("\"drawer\":{", from));
    const int at = i == std::string::npos ? -9999 : std::atoi(usb.text.c_str() + i + 9);
    usb.text.resize(from);
    return at;
  }
  // The Mac's state listing `total` sessions, numbered 100 on, from the
  // `skip`th: as many as the board takes.
  void list(int skip, int total) {
    std::string s = "{\"t\":\"state\",\"base\":\"working\",\"busy\":2,\"vol\":0,\"list\":[";
    const int rows = std::min(Drawer::kRows, total - skip);
    for (int i = skip; i < skip + rows; ++i) {
      char row[64];
      std::snprintf(row, sizeof(row), "%s[%d,\"w\",-1,\"claude\",\"Thread %d\",\"p\"]", i > skip ? "," : "", 100 + i, i);
      s += row;
    }
    s += "],\"skip\":" + std::to_string(skip) + ",\"unlisted\":" + std::to_string(total - skip - rows) + "}";
    line(s.c_str());
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

// A reaction that asks for the drawer (`show`, a reply about every agent)
// opens it kShowDrawerMs in, once its sign has been read, tells the Mac
// as a pull does, and shuts itself kDrawerShutMs on.
constexpr const char* kShowDo =
    "{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"sign\":\"2 working, 1 "
    "idle\",\"reply\":\"status\",\"show\":\"drawer\",\"say\":{},\"mood\":\"engaged\",\"loops\":1}}";

void test_a_reaction_shows_the_drawer_once_its_sign_is_read() {
  Board b;
  b.usb.text.clear();
  b.line(kShowDo);
  b.run(app::Device::kShowDrawerMs - 100);
  TEST_ASSERT_EQUAL_INT(0, b.count(kOpen));
  TEST_ASSERT_EQUAL_INT(0, b.open());
  b.usb.text.clear();
  b.run(200);
  TEST_ASSERT_EQUAL_INT(1, b.count(kOpen));
  b.line(Board::kListed);
  b.run(app::Device::kDrawerMs + 100);
  TEST_ASSERT_EQUAL_INT(1000, b.open());
  b.usb.text.clear();
  b.run(app::Device::kDrawerShutMs - app::Device::kDrawerMs - 500);
  TEST_ASSERT_EQUAL_INT(0, b.count(kClosed));
  b.run(800);
  TEST_ASSERT_EQUAL_INT(1, b.count(kClosed));
}

// A finger on the face, or BOOT, before it opens keeps it shut, and so
// do a request that comes up meanwhile and a later reaction, listening
// included; a reaction that doesn't ask never opens it.
void test_a_finger_or_a_request_first_keeps_it_shut() {
  Board b;
  b.line(kShowDo);
  b.touch(160, 100, 160, 100, 60);
  b.run(app::Device::kShowDrawerMs + app::Device::kDrawerMs);
  TEST_ASSERT_EQUAL_INT(0, b.open());

  Board pressed;
  pressed.line(kShowDo);
  pressed.line("{\"t\":\"dbg.press\",\"ms\":100}");
  pressed.run(app::Device::kShowDrawerMs + app::Device::kDrawerMs);
  TEST_ASSERT_EQUAL_INT(0, pressed.open());

  Board asked;
  asked.line(kShowDo);
  asked.run(500);
  asked.line(
      "{\"t\":\"state\",\"base\":\"working\",\"busy\":2,\"vol\":0,\"attn\":{\"agent\":\"codex\",\"project\":"
      "\"landing\",\"name\":\"Hero copy\",\"more\":0,\"id\":7}}");
  asked.run(app::Device::kShowDrawerMs + app::Device::kDrawerMs);
  TEST_ASSERT_EQUAL_INT(0, asked.open());

  Board plain;
  plain.line("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"sign\":\"claude: done!\",\"reply\":"
             "\"status\",\"say\":{},\"mood\":\"engaged\",\"loops\":1}}");
  plain.run(app::Device::kShowDrawerMs + app::Device::kDrawerMs);
  TEST_ASSERT_EQUAL_INT(0, plain.open());

  // The Mac's Talk pressed again before it opens: listening takes its
  // place, and so does any later reaction.
  Board talked;
  talked.line(kShowDo);
  talked.run(500);
  talked.line("{\"t\":\"do\",\"name\":\"listening\",\"play\":\"now\"}");
  talked.run(app::Device::kShowDrawerMs + app::Device::kDrawerMs);
  TEST_ASSERT_EQUAL_INT(0, talked.open());

  Board next;
  next.line(kShowDo);
  next.run(500);
  next.line("{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{},\"mood\":\"happy\",\"loops\":1}}");
  next.run(app::Device::kShowDrawerMs + app::Device::kDrawerMs);
  TEST_ASSERT_EQUAL_INT(0, next.open());
}

// BOOT held to talk while it's open shuts it, and so does the Mac's
// `listening` (its Talk button): Boop's face listens.
void test_holding_boot_to_talk_shuts_it() {
  Board b;
  pullOpen(b);
  b.usb.text.clear();
  b.line("{\"t\":\"dbg.press\",\"ms\":900}");
  b.run(600 + app::Device::kDrawerMs);
  TEST_ASSERT_EQUAL_INT(1, b.count(kClosed));
  TEST_ASSERT_EQUAL_INT(1, b.count("\"kind\":\"talk_on\""));
  TEST_ASSERT_EQUAL_INT(0, b.open());

  Board mac;
  pullOpen(mac);
  mac.usb.text.clear();
  mac.line("{\"t\":\"do\",\"name\":\"listening\",\"play\":\"now\"}");
  mac.run(app::Device::kDrawerMs + 100);
  TEST_ASSERT_EQUAL_INT(1, mac.count(kClosed));
  TEST_ASSERT_EQUAL_INT(0, mac.open());
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

// Its rows on the AMOLED: a screenful of five, each whole inside the
// panel's rounded corners, and the Mac's six, the sixth peeking under
// them; the second where the panel reads a finger at canvas (160, 112),
// and none under one beside them; the sheet shut is the strip's rule.
void test_the_drawers_rows_on_the_panel() {
  const DrawerLayout l(502, 410, 110);
  TEST_ASSERT_EQUAL_INT(410 * kStripTop / kHeight, l.top(0));
  TEST_ASSERT_EQUAL_INT(66, l.top(1000));
  TEST_ASSERT_EQUAL_INT(5, l.fits());
  TEST_ASSERT_EQUAL_INT(l.fits() + 1, Drawer::kRows);
  const int last = l.rowTop(1000, l.fits() - 1);
  TEST_ASSERT_TRUE(last + l.rowH() <= 410 - 4);
  TEST_ASSERT_TRUE(l.rowTop(1000, l.fits()) < 410);
  TEST_ASSERT_TRUE(l.margin() >= Surface::insetOf(502, 410, 110, last, last + l.rowH(), 10));
  Drawer d;
  d.open = 1000, d.count = 3;
  TEST_ASSERT_EQUAL_INT(1, l.rowAt(d, 160, 112));
  TEST_ASSERT_EQUAL_INT(0, l.rowAt(d, 160, 78));
  TEST_ASSERT_EQUAL_INT(-1, l.rowAt(d, 160, 230));
  TEST_ASSERT_EQUAL_INT(-1, l.rowAt(d, 2, 112));
  int first, shown;
  l.shown(d, first, shown);
  TEST_ASSERT_EQUAL_INT(0, first);
  TEST_ASSERT_EQUAL_INT(2, shown);
}

// With more sessions than a screenful, its rows scroll till the last is
// in the screenful's last place; scrolled, the rows under the lid are cut
// off, a finger finds the session under it by its place in the whole list,
// whether or not its row has come, and none over the lid.
void test_a_long_drawers_rows_scroll() {
  const DrawerLayout l(502, 410, 110);
  TEST_ASSERT_EQUAL_INT(0, l.scrollMax(5));
  TEST_ASSERT_EQUAL_INT(7 * l.pitch() * 2 / 3, l.scrollMax(12));
  TEST_ASSERT_EQUAL_INT(l.scrolledBy(3), l.snap(l.scrolledBy(3) + l.pitch() / 3 - 1));
  TEST_ASSERT_EQUAL_INT(l.scrolledBy(4), l.snap(l.scrolledBy(3) + l.pitch() / 3 + 1));
  Drawer d;
  d.open = 1000, d.count = 6, d.unlisted = 6;
  int first, last;
  l.shown(d, first, last);
  TEST_ASSERT_EQUAL_INT(0, first);
  TEST_ASSERT_EQUAL_INT(5, last);
  d.scroll = l.pitch() * 2 / 3 * 3;  // three rows up, near enough
  l.shown(d, first, last);
  TEST_ASSERT_EQUAL_INT(3, first);
  TEST_ASSERT_EQUAL_INT(8, last);
  TEST_ASSERT_NULL(d.at(8));
  TEST_ASSERT_EQUAL_INT(3, l.rowAt(d, 160, 82));
  TEST_ASSERT_EQUAL_INT(-1, l.rowAt(d, 160, 60));
  d.scroll = l.scrollMax(12);
  l.shown(d, first, last);
  TEST_ASSERT_EQUAL_INT(11, last);
}

// A finger up a long open drawer scrolls its rows, not the drawer, and
// the board asks the Mac for the rows from the first that shows; let go,
// they come to rest on a whole row, a screenful the Mac's rows fill, and
// once they've come it asks no more. Let go quickly, they glide on
// (kDrawerGlideMs) to the last; pushed past it, they spring back. A finger
// down a glide stops it on the nearest whole row and picks nothing; a tap
// on a scrolled row picks that session; flung back to the top, a finger
// down pulls the drawer shut.
void test_a_finger_scrolls_a_long_drawer() {
  TEST_ASSERT_EQUAL_UINT32(600, app::Device::kDrawerGlideMs);
  TEST_ASSERT_EQUAL_UINT32(1000, app::Device::kDrawerReaskMs);
  Board b;
  b.touch(160, 232, 160, 40, 320);
  b.run(400);
  b.list(0, 12);
  b.run(app::Device::kDrawerMs + 100);
  const int most = DrawerLayout(502, 410, 110).scrollMax(12);
  b.usb.text.clear();
  b.touch(160, 200, 160, 100, 400);  // slowly, 250 px/s
  b.run(400 + app::Device::kDrawerGlideMs + 100);
  const DrawerLayout l(502, 410, 110);
  const int slow = b.scroll();
  TEST_ASSERT_TRUE(slow > 100 && slow < most);
  TEST_ASSERT_EQUAL_INT(l.snap(slow), slow);
  TEST_ASSERT_EQUAL_INT(0, b.count(kClosed));
  TEST_ASSERT_EQUAL_INT(0, b.count("\"did\":\"pick\""));
  TEST_ASSERT_EQUAL_INT(0, b.count("\"kind\":\"tap\""));
  Drawer d;
  d.open = 1000, d.count = 12, d.scroll = slow;
  int first, last;
  l.shown(d, first, last);
  TEST_ASSERT_EQUAL_INT(Drawer::kRows - 1, last - first);
  char asked[64];
  std::snprintf(asked, sizeof(asked), "\"did\":\"open\",\"data\":{\"from\":%d}", first);
  TEST_ASSERT_EQUAL_INT(1, b.count(asked));
  b.list(first, 12);
  b.usb.text.clear();
  b.run(app::Device::kDrawerReaskMs + 200);
  TEST_ASSERT_EQUAL_INT(0, b.count("\"did\":\"open\""));
  TEST_ASSERT_EQUAL_INT(1000, b.open());

  b.touch(160, 200, 160, 40, 100);  // flung, 1600 px/s
  b.run(100 + app::Device::kDrawerGlideMs + 100);
  TEST_ASSERT_EQUAL_INT(most, b.scroll());
  b.touch(160, 200, 160, 120, 200);  // pushed past the end
  b.run(180);
  TEST_ASSERT_TRUE(b.scroll() > most);
  b.run(app::Device::kDrawerGlideMs + 100);
  TEST_ASSERT_EQUAL_INT(most, b.scroll());

  b.list(6, 12);
  b.touch(160, 80, 160, 220, 100);  // flung down, then caught
  b.run(200);
  const int caught = b.scroll();
  TEST_ASSERT_TRUE(caught > 0 && caught < most);
  b.usb.text.clear();
  b.touch(160, 150, 160, 150, 60);
  b.run(100);
  TEST_ASSERT_EQUAL_INT(0, b.count("\"did\":\"pick\""));
  b.run(app::Device::kDrawerGlideMs);
  const int stopped = b.scroll();
  TEST_ASSERT_EQUAL_INT(1000, b.open());
  TEST_ASSERT_TRUE(stopped > 0 && stopped < most);
  TEST_ASSERT_EQUAL_INT(l.snap(stopped), stopped);

  d.scroll = stopped;
  DrawerLayout(502, 410, 110).shown(d, first, last);
  b.list(first, 12);
  b.run(40);
  d.scroll = stopped;
  const int row = DrawerLayout(502, 410, 110).rowAt(d, 160, 150);
  TEST_ASSERT_TRUE(row >= first && row < first + Drawer::kRows);
  b.usb.text.clear();
  b.touch(160, 150, 160, 150, 60);
  b.run(100);
  char picked[64];
  std::snprintf(picked, sizeof(picked), "\"did\":\"pick\",\"data\":{\"id\":%d}", 100 + row);
  TEST_ASSERT_EQUAL_INT(1, b.count(picked));
  TEST_ASSERT_EQUAL_INT(1, b.count(kClosed));
  b.run(app::Device::kDrawerMs);

  b.touch(160, 232, 160, 40, 320);  // open again: at the top
  b.run(400);
  b.list(0, 12);
  b.run(app::Device::kDrawerMs + 100);
  TEST_ASSERT_EQUAL_INT(0, b.scroll());
  b.usb.text.clear();
  b.touch(160, 100, 160, 220, 200);
  b.run(200 + app::Device::kDrawerMs + 100);
  TEST_ASSERT_EQUAL_INT(1, b.count(kClosed));
  TEST_ASSERT_EQUAL_INT(0, b.open());
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
