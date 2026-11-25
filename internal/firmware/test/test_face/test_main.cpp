// The renderer's shared parts, with no face: easing, the palette, the
// names of moods, states and animations, the fonts and how text is cut.
#include <unity.h>

#include <string>
#include <vector>

#include "render/types.h"
#include "render/font.h"
#include "render/palette.h"
#include "render/maths.h"

using namespace render;

void setUp() {}
void tearDown() {}

namespace {
struct Buf {
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(kWidth) * kHeight, 0);
  Canvas c{px.data()};
  uint8_t at(int x, int y) const { return px[size_t(y) * kWidth + x]; }
  int count(uint8_t v) const {
    int n = 0;
    for (uint8_t p : px) n += p == v;
    return n;
  }
};

}  // namespace

static void test_ease_is_monotonic_from_0_to_1024() {
  TEST_ASSERT_EQUAL_INT(0, ease(0, 150));
  TEST_ASSERT_EQUAL_INT(512, ease(75, 150));
  TEST_ASSERT_EQUAL_INT(1024, ease(150, 150));
  int last = 0;
  for (int t = 0; t <= 150; ++t) {
    TEST_ASSERT_TRUE(ease(t, 150) >= last);
    last = ease(t, 150);
  }
}

static void test_palette_ramps_run_from_black_to_the_ink() {
  TEST_ASSERT_EQUAL_HEX16(rgb565(kEyeRgb), paletteAt(inkAt(kInkEye, kLevels)));
  TEST_ASSERT_EQUAL_HEX16(rgb565(kAmberRgb), paletteAt(inkAt(kInkAmber, kLevels)));
  TEST_ASSERT_EQUAL_INT(kBlack, inkAt(kInkEye, 0));
  TEST_ASSERT_EQUAL_HEX16(rgb565(255, 0, 0), paletteAt(kRed));  // the bring-up pattern's colours stay
}

// The animations, each by its design's state's name, and
// nothing else: the brain's finish (task_complete, reply_ready), wake_up
// and notice, the rules' reaction (starting), a tap's
// (poked, tap_spam), the board's own to a gesture (gesture) and listening.
// The older names ("cheer", "wiggle") are gone
// with the reaction message. Each plays its own design.
static void test_every_anim_has_a_name() {
  const char* names[] = {"task_complete", "reply_ready", "starting", "poked",  "tap_spam",
                         "wake_up",       "listening",   "gesture",  "notice"};
  int reactions = 0;
  for (int i = 0; i < int(SceneState::kCount); ++i) reactions += isMoment(SceneState(i));
  TEST_ASSERT_EQUAL_INT(9, reactions);
  for (const char* name : names) {
    const SceneState a = reactionFromName(name);
    TEST_ASSERT_TRUE_MESSAGE(isMoment(a), name);
    TEST_ASSERT_EQUAL_STRING(name, stateName(a));  // its own design
  }
  TEST_ASSERT_FALSE(isMoment(SceneState::kNone));
  TEST_ASSERT_EQUAL_STRING("none", stateName(SceneState::kNone));
  TEST_ASSERT_TRUE(reactionFromName("cheer") == SceneState::kNone);
  TEST_ASSERT_TRUE(reactionFromName("wiggle") == SceneState::kNone);
  TEST_ASSERT_TRUE(reactionFromName(nullptr) == SceneState::kNone);
  for (const char* gone : {"dance", "oops", "side_eye", "stretch", "yawn", "zip", "gobble", "rumble", "levelup",
                           "happy", "proud", "smug", "curious", "sleepy", "worried", "sulky", "love", "nod",
                           "thinking", "shrug", "idle", "working", "terminal", "needs_you", "no_app", "none"}) {
    TEST_ASSERT_TRUE_MESSAGE(reactionFromName(gone) == SceneState::kNone, gone);
  }
}

// characters/CHARACTER.md §9: the pack's moods, by the
// names the Mac sends; a missing or unknown one is the startup mood, happy.
static void test_every_mood_has_a_name() {
  TEST_ASSERT_EQUAL_INT(kMoodCount, int(Mood::kCount));
  for (int i = 0; i < int(Mood::kCount); ++i) TEST_ASSERT_TRUE(moodFromName(moodName(Mood(i))) == Mood(i));
  TEST_ASSERT_EQUAL_STRING("happy", moodName(render::kStartupMood));
  for (const char* other : {"cheerful", "no_such_mood", "", "Happy", "Calm"}) {
    TEST_ASSERT_TRUE_MESSAGE(moodFromName(other) == Mood::kHappy, other);
    Mood m = Mood::kSad;
    TEST_ASSERT_FALSE_MESSAGE(parseMood(other, m), other);
    TEST_ASSERT_TRUE(m == Mood::kSad);  // untouched
  }
  TEST_ASSERT_TRUE(moodFromName(nullptr) == Mood::kHappy);
}

// The designs' 22 states by name, in the wire's order, the
// first seven keeping their numbers; a missing or unknown one is idle.
static void test_every_state_has_a_name() {
  TEST_ASSERT_EQUAL_INT(22, int(SceneState::kCount));
  const char* names[] = {"idle",      "working",  "needs_you",  "task_complete", "asleep",      "no_app",
                         "listening", "starting", "planning",   "terminal",      "tool_use",    "searching",
                         "analyzing", "testing",  "delegating", "waiting",       "reply_ready", "poked",
                         "tap_spam",  "wake_up",  "gesture",    "notice"};
  for (int i = 0; i < int(sizeof names / sizeof names[0]); ++i) {
    TEST_ASSERT_EQUAL_STRING(names[i], stateName(SceneState(i)));
    TEST_ASSERT_TRUE(stateFromName(names[i]) == SceneState(i));
  }
  for (const char* other : {"cheer", "busy", "", "Idle"}) TEST_ASSERT_TRUE_MESSAGE(stateFromName(other) == SceneState::kIdle, other);
  TEST_ASSERT_TRUE(stateFromName(nullptr) == SceneState::kIdle);
}

static void test_fonts_are_monospaced_and_utf8_aware() {
  TEST_ASSERT_EQUAL_INT(3 * kSmall.w, stringWidth(kSmall, "abc"));
  TEST_ASSERT_EQUAL_INT(3 * kLarge.w, stringWidth(kLarge, "a\xC2\xB7" "b"));  // "·" is one glyph
  Buf b;
  int end = drawString(b.c, kSmall, 10, 10, "Hi", kInkAmber);
  TEST_ASSERT_EQUAL_INT(10 + 2 * kSmall.w, end);
  TEST_ASSERT_TRUE(b.count(inkAt(kInkAmber, kLevels)) > 10);
  Buf fit;
  int w = drawStringFit(fit.c, kSmall, 0, 0, "a-very-long-project-name", kInkAmber, 10 * kSmall.w);
  TEST_ASSERT_TRUE(w <= 10 * kSmall.w);
  // Accented letters show plain, anything else outside the font
  // as one "?" per character.
  Buf accented, plain, other, marks;
  TEST_ASSERT_EQUAL_INT(4 * kSmall.w, stringWidth(kSmall, "caf\xC3\xA9"));
  drawString(accented.c, kSmall, 0, 0, "caf\xC3\xA9 \xC3\x9C" "ber", kInkAmber);
  drawString(plain.c, kSmall, 0, 0, "cafe Uber", kInkAmber);
  TEST_ASSERT_TRUE(accented.px == plain.px);
  TEST_ASSERT_EQUAL_INT(2 * kSmall.w, stringWidth(kSmall, "\xED\x94\x84\xEB\xA1\x9C"));  // two Hangul syllables
  drawString(other.c, kSmall, 0, 0, "\xED\x94\x84\xEB\xA1\x9C", kInkAmber);
  drawString(marks.c, kSmall, 0, 0, "??", kInkAmber);
  TEST_ASSERT_TRUE(other.px == marks.px);
}

// Text that doesn't fit is cut by one rule on every face (cutAt): at the
// end of its last word within the room, after the last "·", when that
// keeps at least half the room, else mid-word; never ending on a space or
// a "·", and ".." after it.
void test_text_is_cut_at_a_word_where_one_fits() {
  TEST_ASSERT_EQUAL_INT(12, cutAt("still broken after all", 16));               // "still broken.."
  TEST_ASSERT_EQUAL_INT(13, cutAt("what does the turn do", 14));                // no space before ".."
  TEST_ASSERT_EQUAL_INT(16, cutAt("a supercalifragilistic", 16));               // "a" is under half: mid-word
  TEST_ASSERT_EQUAL_INT(16, cutAt("claude \xC2\xB7 a-very-long-project", 16));  // not "claude.."
  TEST_ASSERT_EQUAL_INT(17, cutAt("claude \xC2\xB7 Make the device answer", 17));
  TEST_ASSERT_EQUAL_INT(5, cutAt("hello \xC2\xB7 world", 7));  // not "hello ·.."
  TEST_ASSERT_EQUAL_INT(0, cutAt("anything", 0));
  // The canvas draws the cut as the rule has it.
  Buf cut, whole;
  drawStringFit(cut.c, kSmall, 0, 0, "still broken after all", kInkAmber, 16 * kSmall.w);
  drawString(whole.c, kSmall, 0, 0, "still broken..", kInkAmber);
  TEST_ASSERT_TRUE(cut.px == whole.px);
}

// A long thread or project wraps at spaces, and after a hyphen where a
// name has no space ("a-very-long-" then "project-name"), inside a word
// only when there's neither.
void test_text_wraps_at_spaces_and_hyphens() {
  char lines[3][48];
  TEST_ASSERT_EQUAL_INT(2, wrapText("Thread name on \"needs..", 16, 3, &lines[0][0], 48));
  TEST_ASSERT_EQUAL_STRING("Thread name on", lines[0]);
  TEST_ASSERT_EQUAL_STRING("\"needs..", lines[1]);
  TEST_ASSERT_EQUAL_INT(2, wrapText("a-very-long-project-n..", 16, 3, &lines[0][0], 48));
  TEST_ASSERT_EQUAL_STRING("a-very-long-", lines[0]);
  TEST_ASSERT_EQUAL_STRING("project-n..", lines[1]);
  TEST_ASSERT_EQUAL_INT(2, wrapText("fix a-very-long-project-name", 16, 3, &lines[0][0], 48));
  TEST_ASSERT_EQUAL_STRING("fix a-very-long-", lines[0]);
  TEST_ASSERT_EQUAL_STRING("project-name", lines[1]);
  TEST_ASSERT_EQUAL_INT(2, wrapText("one two three four five six", 10, 2, &lines[0][0], 48));
  TEST_ASSERT_EQUAL_STRING("one two", lines[0]);
  TEST_ASSERT_EQUAL_STRING("three..", lines[1]);  // the last line cut as cutAt cuts
  TEST_ASSERT_EQUAL_INT(1, wrapText("supercalifragilistic expialidocious", 10, 1, &lines[0][0], 48));
  TEST_ASSERT_EQUAL_STRING("supercal..", lines[0]);
  TEST_ASSERT_EQUAL_INT(1, wrapText("caf\xC3\xA9 \xC2\xB7 ok", 16, 3, &lines[0][0], 48));
  TEST_ASSERT_EQUAL_INT(9, glyphCount(lines[0]));
  TEST_ASSERT_EQUAL_INT(0, wrapText("   ", 16, 3, &lines[0][0], 48));
}

// A sign's words (foldText): as the fonts draw them, trimmed, and at most
// the glyphs asked for, cut as cutAt cuts them, with "..".
void test_text_folds_and_cuts_to_its_glyphs() {
  char out[40];
  TEST_ASSERT_EQUAL_INT(12, foldText("  bye bye code ", 18, out, sizeof out));
  TEST_ASSERT_EQUAL_STRING("bye bye code", out);
  TEST_ASSERT_EQUAL_INT(18, foldText("exactly eighteen!!", 18, out, sizeof out));
  TEST_ASSERT_EQUAL_STRING("exactly eighteen!!", out);
  TEST_ASSERT_EQUAL_INT(18, foldText("nineteen glyphs, ok", 18, out, sizeof out));
  TEST_ASSERT_EQUAL_STRING("nineteen glyphs,..", out);
  TEST_ASSERT_EQUAL_INT(14, foldText("still broken after", 15, out, sizeof out));  // no space before ".."
  TEST_ASSERT_EQUAL_STRING("still broken..", out);
  TEST_ASSERT_EQUAL_INT(14, foldText("still broken  aft\xC3\xA9r all", 18, out, sizeof out));
  TEST_ASSERT_EQUAL_STRING("still broken..", out);
  TEST_ASSERT_EQUAL_INT(7, foldText("hello \xC2\xB7 world", 9, out, sizeof out));
  TEST_ASSERT_EQUAL_STRING("hello..", out);
  TEST_ASSERT_EQUAL_INT(7, foldText("\xC3\xA9t\xC3\xA9\t\xC2\xB7 \xE2\x9C\x93", 18, out, sizeof out));
  TEST_ASSERT_EQUAL_STRING("ete \xC2\xB7 ?", out);
  std::string dots;  // "·" is two bytes: 18 of them still fit app::kSignBytes
  for (int i = 0; i < 18; ++i) dots += "\xC2\xB7";
  TEST_ASSERT_EQUAL_INT(18, foldText(dots.c_str(), 18, out, 37));
  TEST_ASSERT_EQUAL_STRING(dots.c_str(), out);
  TEST_ASSERT_EQUAL_INT(0, foldText("   ", 18, out, sizeof out));
  TEST_ASSERT_EQUAL_STRING("", out);
  TEST_ASSERT_EQUAL_INT(0, foldText(nullptr, 18, out, sizeof out));
  TEST_ASSERT_EQUAL_INT(4, foldText("abcdefgh", 18, out, 5));  // a short buffer holds what fits
  TEST_ASSERT_EQUAL_STRING("abcd", out);
  TEST_ASSERT_EQUAL_INT(4, foldText("ab cdefghijklmnopqrstu", 18, out, 6));  // and a cut, with its ".."
  TEST_ASSERT_EQUAL_STRING("ab..", out);
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_ease_is_monotonic_from_0_to_1024);
  RUN_TEST(test_palette_ramps_run_from_black_to_the_ink);
  RUN_TEST(test_every_anim_has_a_name);
  RUN_TEST(test_every_mood_has_a_name);
  RUN_TEST(test_every_state_has_a_name);
  RUN_TEST(test_fonts_are_monospaced_and_utf8_aware);
  RUN_TEST(test_text_is_cut_at_a_word_where_one_fits);
  RUN_TEST(test_text_wraps_at_spaces_and_hyphens);
  RUN_TEST(test_text_folds_and_cuts_to_its_glyphs);
  return UNITY_END();
}
