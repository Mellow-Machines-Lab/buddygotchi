// A native face's frames reach the panel. Two surfaces are
// drawn in turn, each frame's push is planned from what either frame wrote
// and from the lane's canvas changes, and each band is turned a quarter
// into a panel window. A model panel takes every window the AMOLED would
// send, through the same code (render/push.h), and must equal the frame
// drawn after every frame.
#include <unity.h>

#include "pack_file.h"  // internal/firmware/

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <random>
#include <string>
#include <vector>

#include "app/device.h"
#include "linkkit/kit.h"
#include "render/canvas.h"
#include "render/push.h"
#include "render/screens.h"

void setUp() {}
void tearDown() {}

namespace {

using render::PanelWindow;
using render::PushPlan;
using render::Span;
using render::Surface;
using render::SurfacePair;

// The AMOLED's native surface (board/amoled206/config.h), which the
// simulator's Hal gives too.
constexpr int kW = 502, kH = 410;

// The CO5300 panel, as the AMOLED's display.cpp drives it: each band of a
// plan packed into a buffer, then written to its window.
struct ModelPanel {
  int w, h;  // panel pixels: the surface turned a quarter
  bool topOnLeft;
  std::vector<uint16_t> px;
  std::vector<uint16_t> buf = std::vector<uint16_t>(size_t(PushPlan::kRows) * kW);
  uint32_t sent = 0;
  ModelPanel(int surfaceW, int surfaceH, bool top) : w(surfaceH), h(surfaceW), topOnLeft(top) {
    px.assign(size_t(w) * h, 0x5aa5);  // not black: a missed pixel shows
  }
  void send(const Surface& s, const PushPlan& plan) {
    for (int b = 0; b < plan.bands; ++b) {
      if (plan.spans[b].empty()) continue;
      const PanelWindow win = render::packBand(s, b, plan.spans[b], topOnLeft, buf.data());
      // Windows only at even addresses with even sizes.
      TEST_ASSERT_EQUAL_INT(0, win.x % 2);
      TEST_ASSERT_EQUAL_INT(0, win.y % 2);
      TEST_ASSERT_EQUAL_INT(0, win.w % 2);
      TEST_ASSERT_EQUAL_INT(0, win.h % 2);
      TEST_ASSERT_TRUE(win.x >= 0 && win.y >= 0 && win.x + win.w <= w && win.y + win.h <= h);
      TEST_ASSERT_TRUE(win.w * win.h <= int(buf.size()));
      for (int r = 0; r < win.h; ++r)
        for (int c = 0; c < win.w; ++c) {
          const uint16_t v = buf[size_t(r) * win.w + c];  // high byte first, as it goes over SPI
          px[size_t(win.y + r) * w + win.x + c] = uint16_t((v << 8) | (v >> 8));
        }
      sent += uint32_t(win.w * win.h);
    }
  }
  // The first pixel of `s` the panel doesn't show turned a quarter, worked
  // out here rather than by packBand; empty when it shows all of them.
  std::string differs(const Surface& s) const {
    for (int y = 0; y < s.height; ++y)
      for (int x = 0; x < s.width; ++x) {
        const int pxX = topOnLeft ? y : w - 1 - y, pxY = topOnLeft ? h - 1 - x : x;
        if (px[size_t(pxY) * w + pxX] != s.pixels[size_t(y) * s.width + x])
          return "surface (" + std::to_string(x) + ", " + std::to_string(y) + ")";
      }
    return "";
  }
};

// Two surfaces' pixels and the pair over them.
struct Frames {
  std::vector<uint16_t> a = std::vector<uint16_t>(size_t(kW) * kH), b = a;
  std::vector<uint8_t> canvasPx = std::vector<uint8_t>(size_t(render::kWidth) * render::kHeight);
  render::Canvas canvas{canvasPx.data()};
  SurfacePair pair{kW, kH, a.data(), b.data()};
};

// A face's drawing, by its rules (render/surface.h): clear, then write only
// inside spans it touches, then the lane, blitted whole.
void drawRect(Surface& s, int x0, int y0, int x1, int y1, uint16_t ink) {
  s.touch(x0, y0, x1, y1);
  for (int y = std::max(0, y0); y < std::min(s.height, y1); ++y)
    for (int x = std::max(0, x0); x < std::min(s.width, x1); ++x) s.pixels[size_t(y) * s.width + x] = ink;
}
const int kLane = render::kLaneTop * kH / render::kHeight;  // where the gel blits the lane

}  // namespace

// The AMOLED's surface goes in 26 bands of 16 rows, the last
// 10, each turned a quarter into a window 16 panel columns wide; the first
// frame goes whole. Checked both ways up (kTopOnPanelLeft).
static void test_bands_turn_the_surface_a_quarter() {
  TEST_ASSERT_EQUAL_INT(16, PushPlan::kRows);
  for (bool top : {true, false}) {
    Frames f;
    for (int i = 0; i < kW * kH; ++i) f.a[size_t(i)] = uint16_t(i * 2654435761u >> 16);
    TEST_ASSERT_EQUAL_INT(0, f.pair.present(f.canvas).bands);  // nothing drawn yet: nothing to send
    f.pair.back().invalidate();
    f.pair.drew();
    const PushPlan& plan = f.pair.present(f.canvas);
    TEST_ASSERT_TRUE(plan.full);
    TEST_ASSERT_EQUAL_INT(26, plan.bands);
    TEST_ASSERT_EQUAL_INT(10, plan.rows(25));
    TEST_ASSERT_EQUAL_UINT32(uint32_t(kW) * kH, plan.pixels());
    ModelPanel panel(kW, kH, top);
    panel.send(f.pair.front(), plan);
    TEST_ASSERT_EQUAL_STRING("", panel.differs(f.pair.front()).c_str());
    TEST_ASSERT_EQUAL_UINT32(uint32_t(kW) * kH, panel.sent);
    // The surface's top-left pixel is the panel's bottom-left, or its top-right.
    TEST_ASSERT_EQUAL_HEX16(f.a[0], top ? panel.px[size_t(kW - 1) * panel.w] : panel.px[size_t(panel.w - 1)]);
  }
}

// After the first frame, a frame sends only what it or the
// frame on the panel wrote, rounded out to even columns, and the lane's
// columns whose canvas changed; a test pattern or another whole-surface
// write (on the panel or about to be), a frame without the lane, or the
// lane moving sends the whole surface.
static void test_a_frame_sends_what_either_frame_wrote() {
  Frames f;
  auto frame = [&](int x0, int y0, int x1, int y1, bool lane = true) {
    Surface& s = f.pair.back();
    s.clear();
    drawRect(s, x0, y0, x1, y1, 0xf800);
    if (lane) render::blit(f.canvas, s, kLane);
    f.pair.drew();
    return f.pair.present(f.canvas);
  };
  TEST_ASSERT_TRUE(frame(200, 0, 240, 20).full);  // the first frame
  PushPlan p = frame(101, 50, 121, 60);           // into the other surface
  TEST_ASSERT_FALSE(p.full);
  for (int b = 0; b < p.bands; ++b) {
    if (b == 3) {  // rows 48–63: this frame's rectangle, out to even columns
      TEST_ASSERT_EQUAL_INT(100, p.spans[b].x0);
      TEST_ASSERT_EQUAL_INT(122, p.spans[b].x1);
    } else if (b <= 1) {  // rows 0–31: the frame the panel shows wrote these, to be erased
      TEST_ASSERT_EQUAL_INT(200, p.spans[b].x0);
      TEST_ASSERT_EQUAL_INT(240, p.spans[b].x1);
    } else {
      TEST_ASSERT_TRUE(p.spans[b].empty());  // the lane didn't change
    }
  }
  p = frame(101, 50, 121, 60);  // the first surface again, its rectangle erased
  TEST_ASSERT_TRUE(p.spans[0].empty() && p.spans[1].empty());
  TEST_ASSERT_EQUAL_INT(100, p.spans[3].x0);
  TEST_ASSERT_EQUAL_UINT32(16 * 22, p.pixels());
  // The lane: canvas columns 32–63 of rows 200–205 change, in canvas bands
  // 33 and 34 (rows 198–209), which blit draws on surface rows 339–358
  // (bands 21 and 22) and columns 51–100.
  f.canvas.fillRect(40, 200, 8, 6, 7);
  p = frame(101, 50, 121, 60);
  TEST_ASSERT_FALSE(p.full);
  for (int b : {21, 22}) {
    TEST_ASSERT_EQUAL_INT(50, p.spans[b].x0);
    TEST_ASSERT_EQUAL_INT(102, p.spans[b].x1);
  }
  TEST_ASSERT_TRUE(p.spans[20].empty() && p.spans[23].empty());
  TEST_ASSERT_TRUE(frame(101, 50, 121, 60).spans[21].empty());  // and only once
  // A test pattern: the canvas, whole, past what drawing tracks.
  f.pair.back().invalidate();
  render::blit(f.canvas, f.pair.back(), 0);
  f.pair.drew();
  TEST_ASSERT_TRUE(f.pair.present(f.canvas).full);
  TEST_ASSERT_TRUE(frame(101, 50, 121, 60).full);         // the panel shows the pattern
  TEST_ASSERT_FALSE(frame(101, 50, 121, 60).full);        // the pattern's surface, cleared whole
  TEST_ASSERT_TRUE(frame(101, 50, 121, 60, false).full);  // no lane
  TEST_ASSERT_TRUE(frame(101, 50, 121, 60).full);         // the lane back
  TEST_ASSERT_FALSE(frame(101, 50, 121, 60).full);
  // A whole-surface write that keeps the lane where it was.
  f.pair.back().invalidate();
  std::fill(f.pair.back().pixels, f.pair.back().pixels + kW * kLane, uint16_t(0x07e0));
  render::blit(f.canvas, f.pair.back(), kLane);
  f.pair.drew();
  TEST_ASSERT_TRUE(f.pair.present(f.canvas).full);
  TEST_ASSERT_TRUE(frame(101, 50, 121, 60).full);  // the panel shows it
  TEST_ASSERT_FALSE(frame(101, 50, 121, 60).full);
  // A face with no lane at all: its first frame goes whole too.
  Frames bare;
  for (bool first : {true, false}) {
    Surface& s = bare.pair.back();
    s.clear();
    drawRect(s, 10, 10, 20, 20, 0x001f);
    bare.pair.drew();
    TEST_ASSERT_EQUAL(first, bare.pair.present(bare.canvas).full);
  }
}

// Whatever is drawn, in whatever order, the panel ends up
// showing every frame exactly: random rectangles in random inks, the
// lane's canvas changing, test patterns and other whole-surface writes,
// frames without the lane, two frames drawn before one is sent, and
// presents with nothing new.
static void test_random_frames_always_reach_the_panel() {
  std::mt19937 rng(20261005);
  auto pick = [&](int lo, int hi) { return int(rng() % uint32_t(hi - lo + 1)) + lo; };
  for (bool top : {true, false}) {
    Frames f;
    ModelPanel panel(kW, kH, top);
    bool laneless = false;  // a stretch of frames that skip the lane
    for (int n = 0; n < 1000; ++n) {
      if (pick(0, 24) == 0) laneless = !laneless;
      const int draws = pick(0, 9) == 0 ? 2 : pick(0, 19) == 0 ? 0 : 1;
      for (int d = 0; d < draws; ++d) {
        Surface& s = f.pair.back();
        if (pick(0, 29) == 0) {  // the test pattern
          f.canvas.fill(uint8_t(pick(0, 255)));
          s.invalidate();
          render::blit(f.canvas, s, 0);
        } else if (pick(0, 29) == 0) {  // another whole-surface write, the lane kept
          s.invalidate();
          std::fill(s.pixels, s.pixels + kW * kLane, uint16_t(rng()));
          render::blit(f.canvas, s, kLane);
        } else {
          s.clear();
          for (int r = pick(0, 6); r > 0; --r) {
            const int x = pick(-20, kW), y = pick(-20, kLane), w = pick(1, 160), h = pick(1, 120);
            drawRect(s, x, y, x + w, std::min(y + h, kLane), uint16_t(rng()));
          }
          if (pick(0, 3) == 0)
            f.canvas.fillRect(pick(0, 300), pick(150, 235), pick(1, 40), pick(1, 20), uint8_t(rng()));
          if (pick(0, 7) == 0) f.canvas.fill(uint8_t(rng()));
          if (!laneless) render::blit(f.canvas, s, kLane);
        }
        f.pair.drew();
      }
      const PushPlan plan = f.pair.present(f.canvas);
      panel.send(f.pair.front(), plan);
      const std::string miss = panel.differs(f.pair.front());
      if (!miss.empty()) TEST_FAIL_MESSAGE(("frame " + std::to_string(n) + ": the panel misses " + miss).c_str());
    }
  }
}

namespace {

struct FakeHal : app::Hal {
  uint32_t real = 0;
  uint32_t realMs() override { return real; }
  const char* fwVersion() override { return "t"; }
  const char* gitSha() override { return "abc"; }
};

struct Rig {
  FakeHal hal;
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(render::kWidth) * render::kHeight);
  app::Device dev{hal, px.data()};
  linkkit::Kit kit{hal, dev, true};
  Rig() { kit.tick(); }
  void line(const std::string& s) {
    kit.handleLine(s.c_str(), s.size(), linkkit::Link::kUsb);
    kit.tick();
  }
};

// A gel rig: Device makes the face BOOP_SIM_FACE names.
std::unique_ptr<Rig> gelRig() {
  setenv("BOOP_SIM_FACE", "gel", 1);
  auto r = std::make_unique<Rig>();
  unsetenv("BOOP_SIM_FACE");
  return r;
}

// Frames sent, and of those planned from changes, on average: the pixels
// that truly changed, the pixels sent, and what the tile hash this
// replaced would have sent (of each 16-row band, from its first changed
// 16-px tile to its last).
struct Tally {
  int frames = 0, partial = 0;
  uint64_t changed = 0, sent = 0, tiles = 0;
  void print(const char* name) const {
    const uint64_t n = partial ? uint64_t(partial) : 1;
    std::printf(
        "%s: %d frames, %d planned from changes; of those, a frame on average: %lu px changed, %lu px sent "
        "(%lu by the tile hash)\n",
        name, frames, partial, (unsigned long)(changed / n), (unsigned long)(sent / n), (unsigned long)(tiles / n));
  }
};

// Presents the rig's frame, if it drew one, as main.cpp does, sends it to
// the panel and checks the panel shows it. False if it drew none.
bool presentAndCheck(Rig& r, ModelPanel& panel, Tally& tally, const std::string& after) {
  if (!r.dev.takeFrame()) return false;
  const PushPlan plan = r.dev.frames()->present(r.dev.canvas());
  const Surface& shown = r.dev.frames()->front();
  TEST_ASSERT_EQUAL_PTR(r.dev.surface(), &shown);
  if (!plan.full) {
    for (int b = 0; b < plan.bands; ++b) {
      int x0 = kW, x1 = 0;
      for (int y = b * PushPlan::kRows; y < b * PushPlan::kRows + plan.rows(b); ++y)
        for (int x = 0; x < kW; ++x)
          if (panel.px[size_t(kW - 1 - x) * panel.w + y] != shown.pixels[size_t(y) * kW + x])
            ++tally.changed, x0 = std::min(x0, x), x1 = std::max(x1, x + 1);
      if (x1) tally.tiles += uint64_t(plan.rows(b)) * uint64_t(std::min(kW, (x1 + 15) / 16 * 16) - x0 / 16 * 16);
    }
    ++tally.partial;
    tally.sent += plan.pixels();
  }
  ++tally.frames;
  panel.send(shown, plan);
  const std::string miss = panel.differs(shown);
  if (!miss.empty()) TEST_FAIL_MESSAGE(("after \"" + after + "\": the panel misses " + miss).c_str());
  return true;
}

}  // namespace

// The gel through Device, as the board runs it. After every
// frame of a long random sequence (moods, states, moments and pokes, needs
// you, lane bubbles and the strip's count, test patterns and screenshots,
// uneven clock steps) the panel shows the frame drawn, and that frame is
// the one a single surface, cleared and drawn as before, would hold.
#if __has_include("render/gel/face.h")  // a pack with the gel face (Boop's)
static void test_gel_frames_always_reach_the_panel() {
  auto r = gelRig(), single = gelRig();
  TEST_ASSERT_NOT_NULL(r->dev.frames());
  TEST_ASSERT_EQUAL_INT(kW, r->dev.frames()->front().width);
  TEST_ASSERT_EQUAL_INT(kH, r->dev.frames()->front().height);
  ModelPanel panel(kW, kH, true);
  Tally tally;
  const char* bases[] = {"idle", "working", "asleep"};
  const char* acts[] = {"planning", "terminal", "tool_use", "searching", "testing", "delegating", "waiting"};
  const char* moods[] = {"happy", "excited", "grumpy", "sad", "calm", "frightened", "amused", "tired", "crying"};
  const char* takes[] = {"previous.go", "previous.dai", "new.d14"};
  std::mt19937 rng(5);
  auto pick = [&](int n) { return int(rng() % uint32_t(n)); };
  for (int n = 0; n < 700; ++n) {
    char msg[320];
    switch (pick(12)) {
      case 0:
      case 1:
        std::snprintf(msg, sizeof msg, "{\"t\":\"state\",\"base\":\"%s\",\"act\":\"%s\",\"mood\":\"%s\",\"busy\":%d}",
                      bases[pick(3)], acts[pick(7)], moods[pick(9)], pick(4));
        break;
      case 2:
        std::snprintf(msg, sizeof msg,
                      "{\"t\":\"state\",\"base\":\"working\",\"mood\":\"%s\",\"attn\":{\"agent\":\"claude\","
                      "\"project\":\"boop\",\"name\":\"Fix test %d\",\"id\":%d}}",
                      moods[pick(9)], pick(3), pick(3));
        break;
      case 3:
        std::snprintf(msg, sizeof msg,
                      "{\"t\":\"do\",\"name\":\"react\",\"play\":\"now\",\"args\":{\"say\":{\"take\":\"%s\"},"
                      "\"mood\":\"%s\"}}",
                      takes[pick(3)], moods[pick(9)]);
        break;
      case 4: {
        const char* names[] = {"task_complete", "starting",  "poked",         "error",
                               "helper_return", "listening", "stop_listening"};
        std::snprintf(msg, sizeof msg, "{\"t\":\"do\",\"name\":\"%s\",\"play\":\"now\",\"args\":{\"outcome\":\"%s\"}}",
                      names[pick(7)], pick(2) ? "success" : "failure");
        break;
      }
      case 5:
        std::snprintf(
            msg, sizeof msg,
            pick(2) ? "{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":%d}" : "{\"t\":\"dbg.press\",\"ms\":%d}",
            40 + pick(200));
        break;
      case 6:
        if (pick(4)) {
          std::snprintf(msg, sizeof msg, "{\"t\":\"dbg.shot\"}");  // a frame drawn afresh, before the loop's
        } else {
          const int kind = pick(3);
          std::snprintf(msg, sizeof msg,
                        kind == 0   ? "{\"t\":\"dbg.pattern\"}"
                        : kind == 1 ? "{\"t\":\"dbg.pattern\",\"fill\":%d}"
                                    : "{\"t\":\"dbg.pattern\",\"target\":[%d,90]}",
                        pick(256));
        }
        break;
      default:
        std::snprintf(msg, sizeof msg, "{\"t\":\"dbg.clock\",\"step\":%d}", 1 + pick(pick(4) ? 40 : 400));
        break;
    }
    for (Rig* x : {r.get(), single.get()}) x->line(msg);
    single->dev.takeFrame();  // never presented: one surface, drawn over and over
    if (!presentAndCheck(*r, panel, tally, msg)) continue;
    if (std::memcmp(r->dev.surface()->pixels, single->dev.surface()->pixels, r->dev.surface()->bytes()))
      TEST_FAIL_MESSAGE(("after \"" + std::string(msg) + "\": two surfaces drew another picture").c_str());
  }
  tally.print("random sequence");
  TEST_ASSERT_TRUE(tally.frames > 300);
  TEST_ASSERT_TRUE(tally.partial > tally.frames / 2);
}
#endif

#if __has_include("render/gel/face.h")
// Steady scenes, a frame every 33 ms (30 a second), as the
// board draws them in motion. The panel shows every frame, and every
// frame after the first is planned from changes; what each sends is
// printed for the record (at 40 MHz on four lines, a pixel is 0.1 µs).
static void test_steady_scenes_reach_the_panel() {
  const char* scenes[][2] = {
      {"working, happy", "{\"t\":\"state\",\"base\":\"working\",\"act\":\"terminal\",\"mood\":\"happy\",\"vol\":0}"},
      {"needs you",
       "{\"t\":\"state\",\"base\":\"working\",\"mood\":\"happy\",\"vol\":0,\"attn\":{\"agent\":\"claude\",\"project\":"
       "\"boop\",\"name\":\"Fix a test\",\"id\":1}}"},
      {"working, frightened",
       "{\"t\":\"state\",\"base\":\"working\",\"act\":\"testing\",\"mood\":\"frightened\",\"vol\":0}"},
      {"asleep", "{\"t\":\"state\",\"base\":\"asleep\",\"mood\":\"calm\",\"vol\":0}"},
  };
  for (const auto& scene : scenes) {
    auto r = gelRig();
    ModelPanel panel(kW, kH, true);
    Tally tally;
    r->line(scene[1]);
    presentAndCheck(*r, panel, tally, scene[1]);
    for (int i = 0; i < 90; ++i) {
      r->line("{\"t\":\"dbg.clock\",\"step\":33}");
      presentAndCheck(*r, panel, tally, scene[0]);
    }
    tally.print(scene[0]);
    TEST_ASSERT_EQUAL_INT(tally.frames - 1, tally.partial);
  }
}

// A lane the gel draws itself goes out only when it
// changes. In a steady needs-you scene, whose strip names who's asking,
// the bands wholly in the lane send nothing after the first frame: the
// other surface draws the same lane, which the panel already shows. A new
// name sends them again, once.
static void test_an_unchanged_lane_isnt_sent_again() {
  auto r = gelRig();
  ModelPanel panel(kW, kH, true);
  Tally tally;
  const int firstLaneBand = (kH * 4 / 5 + PushPlan::kRows - 1) / PushPlan::kRows;
  auto laneSent = [&](const std::string& after) {
    presentAndCheck(*r, panel, tally, after);
    const PushPlan& plan = r->dev.frames()->plan();
    int px = 0;
    for (int b = firstLaneBand; b < plan.bands; ++b) px += plan.spans[b].empty() ? 0 : 1;
    return px;
  };
  const std::string asking[] = {
      "{\"t\":\"state\",\"base\":\"working\",\"busy\":2,\"vol\":0,\"attn\":{\"agent\":\"claude\",\"name\":"
      "\"Fix a test\",\"id\":1}}",
      "{\"t\":\"state\",\"base\":\"working\",\"busy\":2,\"vol\":0,\"attn\":{\"agent\":\"claude\",\"name\":"
      "\"Fix another test\",\"id\":1}}"};
  for (const std::string& state : asking) {
    r->line(state);
    for (int i = 0; i < 8; ++i) {
      if (i) r->line("{\"t\":\"dbg.clock\",\"step\":33}");
      const int bands = laneSent(state);
      if (i == 0) TEST_ASSERT_TRUE_MESSAGE(bands > 0, "a new lane goes out");
      else TEST_ASSERT_EQUAL_INT_MESSAGE(0, bands, "an unchanged lane stays");
    }
  }
}
#endif

int main() {
  UNITY_BEGIN();
  if (!packfile::open()) std::printf("no voice pack: the chosen character pack has none\n");
  RUN_TEST(test_bands_turn_the_surface_a_quarter);
  RUN_TEST(test_a_frame_sends_what_either_frame_wrote);
  RUN_TEST(test_random_frames_always_reach_the_panel);
#if __has_include("render/gel/face.h")
  RUN_TEST(test_gel_frames_always_reach_the_panel);
#endif
#if __has_include("render/gel/face.h")
  RUN_TEST(test_steady_scenes_reach_the_panel);
  RUN_TEST(test_an_unchanged_lane_isnt_sent_again);
#endif
  return UNITY_END();
}
