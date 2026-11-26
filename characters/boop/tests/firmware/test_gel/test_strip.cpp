// The strip's layouts (render/gel/lane.h's StripLayout), for the owner to
// choose between: the switch by name, and each one's rule for fitting the
// doing and the watched agent's name into the strip.
#include <unity.h>

#include <algorithm>
#include <vector>

#include "render/gel/face.h"
#include "render/gel/lane.h"

using namespace render;
using namespace render::gel;

namespace {

// The AMOLED's panel, its corners 110 px in radius.
struct Panel {
  std::vector<uint16_t> px = std::vector<uint16_t>(502 * 410);
  Surface s{502, 410, px.data()};
  Panel() { s.corner = 110; }
};

// WorkStream.maxDoingBytes: the longest doing the Mac sends; and the gap
// between the doing and the chip, the strip's marks' box.
constexpr int kLongestDoing = 24, kGap = 18;

}  // namespace

// dbg.strip's names set it, another leaves it, and a reset puts today's
// back.
void test_the_strips_layout_switches_by_name() {
  linkkit::Rng rng;
  GelFace face;
  face.reset(0, rng);
  TEST_ASSERT_TRUE(stripLayout() == StripLayout::kToday);
  const struct {
    const char* name;
    StripLayout layout;
  } names[] = {{"a", StripLayout::kDoingFirst},
               {"b", StripLayout::kFold},
               {"c", StripLayout::kRows},
               {"e", StripLayout::kOnLine},
               {"today", StripLayout::kToday}};
  for (const auto& n : names) {
    TEST_ASSERT_TRUE(face.stripLayout(n.name));
    TEST_ASSERT_TRUE(stripLayout() == n.layout);
  }
  TEST_ASSERT_TRUE(face.stripLayout("c"));
  TEST_ASSERT_FALSE(face.stripLayout("d"));
  TEST_ASSERT_FALSE(face.stripLayout(""));
  TEST_ASSERT_TRUE(stripLayout() == StripLayout::kRows);
  face.reset(0, rng);
  TEST_ASSERT_TRUE(stripLayout() == StripLayout::kToday);
}

// a: the doing first. Both whole when they fit; else the name cut to what
// the doing leaves, a few glyphs and a "…" at the least, else its initial;
// never past the row, and the doing never less than it needs while the
// least chip leaves it room.
void test_the_doing_first_split() {
  constexpr int kRoom = 374, kInitial = 13 + kNamePad;
  RowSplit s = splitRow(10, 5, kRoom);
  TEST_ASSERT_FALSE(s.cut);
  TEST_ASSERT_EQUAL_INT(5, s.glyphs);
  TEST_ASSERT_EQUAL_INT(5 * kLarge.w + kNamePad, s.chip);
  TEST_ASSERT_EQUAL_INT(kRoom - kGap - s.chip, s.doing);
  s = splitRow(14, 12, kRoom);  // "running the tests" and a long name: cut
  TEST_ASSERT_TRUE(s.cut && s.glyphs > kNameLeast && s.glyphs < 12);
  TEST_ASSERT_TRUE(s.doing >= 14 * kSign.w);
  s = splitRow(22, 12, kRoom);  // "editing WorkStream +12": the initial
  TEST_ASSERT_TRUE(s.cut);
  TEST_ASSERT_EQUAL_INT(1, s.glyphs);
  TEST_ASSERT_EQUAL_INT(kInitial, s.chip);
  s = splitRow(22, 0, kRoom);  // no name: the whole row
  TEST_ASSERT_EQUAL_INT(kRoom, s.doing);
  TEST_ASSERT_EQUAL_INT(0, s.chip);
  for (int room = 300; room <= 440; room += 7)
    for (int doing = 0; doing <= kLongestDoing; ++doing)
      for (int name = 1; name <= 12; ++name) {
        s = splitRow(doing, name, room);
        TEST_ASSERT_TRUE(s.doing + kGap + s.chip <= room);
        TEST_ASSERT_EQUAL_INT(s.glyphs * kLarge.w + kNamePad, s.chip);
        TEST_ASSERT_TRUE(s.doing >= std::min(doing * kSign.w, room - kGap - kInitial));
        if (s.cut)
          TEST_ASSERT_TRUE(s.glyphs == 1 || (s.glyphs > kNameLeast && s.glyphs < name));
        else
          TEST_ASSERT_EQUAL_INT(name, s.glyphs);
      }
}

// b: the name whole for kNameMs after the agent followed changes, then
// gone over kFoldMs, never coming back on its own.
void test_the_name_folds_away_after_it_shows() {
  TEST_ASSERT_EQUAL_INT(255, nameFold(0));
  TEST_ASSERT_EQUAL_INT(255, nameFold(kNameMs - 1));
  TEST_ASSERT_EQUAL_INT(255, nameFold(kNameMs));
  TEST_ASSERT_TRUE(nameFold(kNameMs + kFoldMs / 2) > 64 && nameFold(kNameMs + kFoldMs / 2) < 192);
  TEST_ASSERT_EQUAL_INT(0, nameFold(kNameMs + kFoldMs));
  TEST_ASSERT_EQUAL_INT(0, nameFold(60000));
  for (uint32_t t = 0; t < kNameMs + kFoldMs + 100; t += 10) TEST_ASSERT_TRUE(nameFold(t + 10) <= nameFold(t));
}

// The doing's whole row on the panel: today's and e's (the name on the
// line) hold 22 glyphs of the strip's font, short of the Mac's longest
// doing; c's top row, under its rule moved up, holds the longest whole.
void test_the_doings_room_by_layout() {
  Panel p;
  TEST_ASSERT_TRUE(setStripLayout("today"));
  const int today = doingRoom(p.s);
  TEST_ASSERT_EQUAL_INT(22, today / kSign.w);
  TEST_ASSERT_TRUE(setStripLayout("e"));
  TEST_ASSERT_EQUAL_INT(today, doingRoom(p.s));
  TEST_ASSERT_TRUE(setStripLayout("c"));
  TEST_ASSERT_TRUE(doingRoom(p.s) >= kLongestDoing * kSign.w);
  TEST_ASSERT_TRUE(setStripLayout("today"));
}
