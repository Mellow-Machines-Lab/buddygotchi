// What moves slowly moves in sixteenths of a pixel, as the body does: its
// drawn ink's middle goes on in a straight line with the time, not a whole
// pixel at a time. At 30-45 fps a thing moving 100 px a second steps 2-3
// px a frame, and a whole-pixel position makes each step half a pixel more
// or less than the last; the eye reads that as a stutter beside the body.
#include <unity.h>

#include <cmath>
#include <cstring>
#include <memory>
#include <vector>

#include "render/gel/engine.h"
#include "render/gel/layers.h"
#include "render/gel/painter.h"
#include "render/gel/raster.h"
#include "render/palette.h"
#include "render/gel/stream.h"
#include "render/tags.h"

using namespace render;
using namespace render::gel;

namespace {

// The ink's middle in a box: each pixel weighted by how far its channels
// are from `base`'s.
struct Middle {
  double x = 0, y = 0, weight = 0;
};
Middle middle(const std::vector<uint16_t>& px, const std::vector<uint16_t>& base, int width, Box b) {
  Middle m;
  for (int y = b.y0; y < b.y1; ++y)
    for (int x = b.x0; x < b.x1; ++x) {
      const uint16_t v = px[size_t(y) * width + x], o = base[size_t(y) * width + x];
      const double d = std::abs(int(v >> 11) - int(o >> 11)) / 31.0 +
                       std::abs(int(v >> 5 & 63) - int(o >> 5 & 63)) / 63.0 +
                       std::abs(int(v & 31) - int(o & 31)) / 31.0;
      m.x += d * x, m.y += d * y, m.weight += d;
    }
  if (m.weight > 0) m.x /= m.weight, m.y /= m.weight;
  return m;
}

// The most any of the values is off the straight line through them all
// (least squares) by its time.
double offLine(const std::vector<double>& at, const std::vector<double>& v) {
  const double n = double(at.size());
  double st = 0, sv = 0, stt = 0, stv = 0;
  for (size_t i = 0; i < at.size(); ++i) st += at[i], sv += v[i], stt += at[i] * at[i], stv += at[i] * v[i];
  const double slope = (n * stv - st * sv) / (n * stt - st * st), cut = (sv - slope * st) / n;
  double most = 0;
  for (size_t i = 0; i < at.size(); ++i) most = std::max(most, std::abs(v[i] - (cut + slope * at[i])));
  return most;
}

}  // namespace

// A lane's word falls behind the body a sixteenth at a time
// (render/gel/stream.cpp's `behind`): over the 1.6 s it's fully shown, its
// ink's middle is never more than 0.1 px off the straight line of its fall
// at its speed (whole pixels were up to half a pixel off), and on a whole
// pixel it's the glyph as drawn.
void test_a_falling_word_falls_in_sixteenths() {
  std::vector<uint16_t> px(502 * 410), black(502 * 410, 0);
  Surface s{502, 410, px.data()};
  Stream stream;
  Stream::Lane lane;
  lane.slot = 0, lane.count = 1, std::strcpy(lane.word, "grep");
  stream.setLanes(&lane, 1, true, false, 0);
  int live = 0;
  for (auto& w : stream.words) {
    if (!w.live) continue;
    ++live;
    w.speed = 117, w.born = 0;  // a speed no whole number of px a frame
  }
  TEST_ASSERT_EQUAL_INT(1, live);
  std::vector<double> at, ys;
  for (uint32_t t = 300; t <= 1900; t += 7) {
    std::fill(px.begin(), px.end(), 0);
    paintStreamBehind(s, stream, t);
    const Middle m = middle(px, black, 502, {0, 0, 502, 328});
    TEST_ASSERT_TRUE(m.weight > 20);
    at.push_back(t), ys.push_back(m.y);
  }
  // It falls at its speed, in a straight line.
  TEST_ASSERT_TRUE(std::abs(ys.back() - ys.front() - 117 * 1.6) < 1.5);
  TEST_ASSERT_TRUE(offLine(at, ys) < 0.1);
  // On a whole pixel it's the glyph's own coverage: the frame a sixteenth
  // later has ink in the row under it that this one hasn't.
  int whole = -1;
  for (uint32_t t = 300; t < 900 && whole < 0; ++t)
    if (int64_t(t) * 117 * 16 / 1000 % 16 == 0) whole = int(t);
  TEST_ASSERT_TRUE(whole > 0);
  auto lowest = [&](uint32_t t) {
    std::fill(px.begin(), px.end(), 0);
    paintStreamBehind(s, stream, t);
    int last = -1;
    for (int y = 0; y < 328; ++y)
      for (int x = 0; x < 502; ++x)
        if (px[size_t(y) * 502 + x]) last = y;
    return last;
  };
  TEST_ASSERT_EQUAL_INT(lowest(uint32_t(whole)) + 1, lowest(uint32_t(whole) + 1));
}

// A recording replayed between rows (Raster::replay16) is what its shapes
// drew there, near enough: at every sixteenth of two pixels down, its
// ink's middle within 0.03 px of theirs and its ink within 1% of theirs,
// and on a whole row exactly theirs.
void test_a_recording_replays_between_rows() {
  std::vector<uint16_t> px(502 * 410), black(502 * 410, 0);
  Surface s{502, 410, px.data()};
  static uint8_t room[16 * 1024];
  Recording kept{room, int(sizeof room)};
  kept.clear();
  // A disk and a stroke over it, as a hat's shapes overlap.
  auto shapes = [](Raster& r, int dy16) {
    r.disk16(200 * 16 + 5, 150 * 16 + 3 + dy16, 30 * 16 + 7, rgb565(240, 80, 40));
    const Point v[] = {{170 * 16, 140 * 16 + dy16}, {230 * 16 + 9, 160 * 16 + 4 + dy16}};
    r.stroke16(v, 2, 6 * 16, rgb565(40, 200, 120));
  };
  Raster record{s};
  record.recording = &kept;
  shapes(record, 0);
  TEST_ASSERT_FALSE(kept.full);
  Raster r{s};
  const Box all{0, 0, 502, 328};
  for (int dy16 = 0; dy16 <= 32; ++dy16) {
    std::fill(px.begin(), px.end(), 0);
    shapes(r, dy16);
    const std::vector<uint16_t> fresh(px);
    std::fill(px.begin(), px.end(), 0);
    r.replay16(kept, 0, dy16);
    const Middle a = middle(px, black, 502, all), b = middle(fresh, black, 502, all);
    TEST_ASSERT_TRUE(std::abs(a.y - b.y) < 0.03 && std::abs(a.x - b.x) < 0.03);
    TEST_ASSERT_TRUE(std::abs(a.weight - b.weight) < b.weight / 100);
    if (dy16 % 16 == 0) TEST_ASSERT_TRUE(px == fresh);
  }
}

// The hat, kept (OutfitLayer), follows the body down in sixteenths while
// it moves: brought down a sixteenth every 10 ms, its ink's middle goes
// down with it in a straight line, never 0.1 px off it (a whole pixel at a
// time it was up to half a pixel off).
void test_the_hat_follows_the_body_in_sixteenths() {
  std::vector<uint16_t> px(502 * 410), black(502 * 410, 0);
  Surface s{502, 410, px.data()};
  auto e = std::make_unique<Engine>();
  for (int t = 0; t <= 960; t += 16) e->step(t);
  rig::Anchors home;
  paint(s, *e, false, 0, 0, &home);
  e->setOccasion(tagBit("night"), 0);
  rig::Layers cap;
  cap.show(rig::Layer::kHat, uint32_t(Outfit::kNightcap), 0);
  std::vector<double> at, ys;
  // Within one step of the cap's swing (OutfitLayer::kSwingMs).
  for (int i = 0; i < 40; ++i) {
    rig::Anchors down = home;
    for (rig::Point* p : {&down.crown, &down.brimL, &down.brimF, &down.brimR}) p->y += i;
    std::fill(px.begin(), px.end(), 0);
    s.invalidate();
    e->elapsedMs = 1200 + 10 * i;
    paintLayers(s, *e, down, &cap, 1000);
    const Middle m = middle(px, black, 502, {0, 0, 502, 328});
    TEST_ASSERT_TRUE(m.weight > 100);
    at.push_back(i), ys.push_back(m.y);
  }
  TEST_ASSERT_TRUE(std::abs(ys.back() - ys.front() - 39 / 16.0) < 0.1);
  TEST_ASSERT_TRUE(offLine(at, ys) < 0.1);
}
