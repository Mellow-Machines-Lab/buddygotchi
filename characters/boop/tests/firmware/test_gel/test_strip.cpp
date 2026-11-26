// The strip with several agents (render/gel/lane.h): the name of the one
// the screen follows in its pip on the line, as much as fits and cut with
// "…"; the lane kept while only the spinner's step changes; and the counts
// on the line, for the owner to see, off until asked.
#include <unity.h>

#include <cstring>
#include <vector>

#include "render/gel/face.h"
#include "render/gel/lane.h"

using namespace render;
using namespace render::gel;

namespace {

// The AMOLED's panel, its corners 110 px in radius, and its line: the
// strip's rule, from one end to the other.
struct Panel {
  static constexpr int kW = 502, kH = 410;
  std::vector<uint16_t> px = std::vector<uint16_t>(kW * kH);
  Surface s{kW, kH, px.data()};
  Panel() { s.corner = 110; }
  int rule() const { return kH * kStripTop / render::kHeight; }
  int margin() const { return std::max(18, s.inset(rule(), rule() + 2) + 4); }
  int line() const { return kW - 2 * margin(); }
};

// Core.maxWatchNameBytes: the longest name the Mac sends for the line.
constexpr int kLongestName = 28;

Strip several(int pips, const char* who) {
  Strip s;
  s.busy = pips - 1, s.idle = 1, s.pipCount = pips, s.watch = 1, s.who = who;
  for (int i = 0; i < pips; ++i) s.pipKind[i] = i + 1 < pips ? 'w' : 'i', s.pipSlot[i] = int8_t(i);
  return s;
}

}  // namespace

// The name on the line: whole when it fits beside the other pips with some
// line at each end; else cut as text() cuts it, its "…" a cell of the
// pill; never past the line, whatever the name and however many agents.
void test_the_name_on_the_line_fits() {
  const int line = Panel().line();
  const char* longest = "internal-tools-marketing-sui";  // 28
  TEST_ASSERT_EQUAL_INT(kLongestName, glyphCount(longest));
  for (int pips = 2; pips <= Strip::kPips; ++pips) {
    const PipsFit whole = fitPips(pips, true, "boop-voice-fw", line);
    TEST_ASSERT_FALSE(whole.cut);
    TEST_ASSERT_EQUAL_INT(13, whole.glyphs);
    TEST_ASSERT_EQUAL_INT(13 * kLarge.w + 2 * kPillPad, whole.pill);
    for (const char* name : {"a", "web", "the landing page and its\xE2\x80\xA6", longest}) {
      const PipsFit f = fitPips(pips, true, name, line);
      TEST_ASSERT_TRUE(f.width + 2 * (kPipRuleGap + kLineLeast) <= line);
      TEST_ASSERT_EQUAL_INT(f.glyphs * kLarge.w + 2 * kPillPad, f.pill);
      TEST_ASSERT_TRUE(f.glyphs * kLarge.w <= f.room);
      if (f.cut)
        TEST_ASSERT_TRUE(f.glyphs < glyphCount(name));
      else
        TEST_ASSERT_EQUAL_INT(glyphCount(name), f.glyphs);
    }
  }
  // Up to four agents, a name of 24 shows whole; six cut the longest.
  TEST_ASSERT_FALSE(fitPips(4, true, "the landing page and its", line).cut);
  TEST_ASSERT_TRUE(fitPips(6, true, longest, line).cut);
  // No name, or no agent watched: the long pip, or only dots.
  TEST_ASSERT_EQUAL_INT(kPipLong, fitPips(3, true, "", line).pill);
  const PipsFit none = fitPips(3, false, "web", line);
  TEST_ASSERT_EQUAL_INT(0, none.pill);
  TEST_ASSERT_EQUAL_INT(3 * 2 * kPipDot + 2 * kPipGap, none.width);
}

// Drawn, the line keeps a little of its rule at each end, the pill stays
// on it and clear of the doing's row, and a cut name ends in "…".
void test_the_line_holds_the_name() {
  Panel p;
  const Strip s = several(6, "internal-tools-marketing-sui");
  paintLane(p.s, nullptr, s);
  const int y = p.rule(), margin = p.margin();
  for (int x : {margin + 2, Panel::kW - margin - 3}) TEST_ASSERT_NOT_EQUAL(0, p.px[size_t(y) * Panel::kW + x]);
  // Nothing of the line between its rows and the doing's.
  const int top = y + 1 - kPillTall / 2, bottom = y + 1 + kPillTall / 2;
  for (int x = 0; x < Panel::kW; ++x) {
    TEST_ASSERT_EQUAL_HEX16(0, p.px[size_t(top - 2) * Panel::kW + x]);
    TEST_ASSERT_EQUAL_HEX16(0, p.px[size_t(bottom + 2) * Panel::kW + x]);
  }
  const PipsFit f = fitPips(6, true, s.who, p.line());
  TEST_ASSERT_TRUE(f.cut);
  TEST_ASSERT_TRUE(kLarge.h >= 14 && kPillTall >= 14);
}

// With several agents the strip draws no spinner, so its key, the name on
// the line and all, holds through the spinner's steps; with one at work it
// turns with them.
void test_the_line_is_kept_through_the_spinner() {
  const Strip s = several(3, "web");
  for (int spin = 1; spin < kSpinSteps; ++spin)
    TEST_ASSERT_EQUAL_UINT32(laneKey(nullptr, s), laneKey(nullptr, s, spin));
  Strip one;
  one.busy = 1;
  TEST_ASSERT_NOT_EQUAL(laneKey(nullptr, one), laneKey(nullptr, one, 1));
  Strip asking = s;
  asking.agent = "claude";  // needs you's marks have a spinner
  TEST_ASSERT_NOT_EQUAL(laneKey(nullptr, asking), laneKey(nullptr, asking, 1));
}

// The counts on the line: off as the board starts, on by dbg.counts, and
// off again after a reset; on, the lane's key says so.
void test_the_counts_on_the_line_switch() {
  linkkit::Rng rng;
  GelFace face;
  face.reset(0, rng);
  TEST_ASSERT_FALSE(countsOnLine());
  Strip one;
  one.busy = 1;
  const uint32_t row = laneKey(nullptr, one);
  TEST_ASSERT_TRUE(face.countsOnLine(true));
  TEST_ASSERT_TRUE(countsOnLine());
  TEST_ASSERT_NOT_EQUAL(row, laneKey(nullptr, one));
  face.reset(0, rng);
  TEST_ASSERT_FALSE(countsOnLine());
  TEST_ASSERT_EQUAL_UINT32(row, laneKey(nullptr, one));
}
