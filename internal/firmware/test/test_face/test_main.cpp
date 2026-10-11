// The renderer: integer maths, the rasterizer, the names of the
// animations and moods, the strip and the bubble, fonts and the palette ramps (the v1 build plan's F2, L0).
#include <unity.h>

#include <cstring>
#include <utility>
#include <vector>

#include "render/types.h"
#include "render/font.h"
#include "render/palette.h"
#include "render/maths.h"
#include "render/pixel/scene.h"
#include "render/screens.h"
#include "render/pixel/sign.h"
#include "voice/player.h"
#include "pack_file.h"  // internal/firmware/

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
  TEST_ASSERT_TRUE(kPaletteUsed <= 256);
  TEST_ASSERT_EQUAL_HEX16(rgb565(255, 0, 0), paletteAt(kRed));  // the bring-up pattern's colours stay
}

// The animations, each by its design's state's name, and
// nothing else: the brain's finish (task_complete, reply_ready), the rules'
// one-shots (starting, stopped, error, helper_return), a tap's (poked,
// tap_spam) and listening. The older names ("cheer", "wiggle") are gone
// with the moment message. Each plays its own design, and every design
// has a loop.
static void test_every_anim_has_a_name_and_ends() {
  TEST_ASSERT_EQUAL_INT(10, int(Anim::kCount));  // with kNone
  const char* names[] = {"task_complete", "reply_ready", "starting", "stopped", "error",
                         "helper_return", "poked",       "tap_spam", "listening"};
  for (int i = 1; i < int(Anim::kCount); ++i) {
    Anim a = Anim(i);
    TEST_ASSERT_EQUAL_STRING(names[i - 1], animName(a));
    TEST_ASSERT_TRUE(animFromName(animName(a)) == a);
    TEST_ASSERT_EQUAL_STRING(animName(a), stateName(animState(a)));  // its own design
  }
  TEST_ASSERT_TRUE(animFromName("cheer") == Anim::kNone);
  TEST_ASSERT_TRUE(animFromName("wiggle") == Anim::kNone);
  for (int m = 0; m < render::pixelMoods(); ++m) {
    for (int s = 0; s < int(SceneState::kCount); ++s) TEST_ASSERT_TRUE(loopMs(render::pixelMood(m), SceneState(s)) > 0);
  }
  for (const char* gone : {"dance", "oops", "side_eye", "stretch", "yawn", "zip", "gobble", "rumble", "levelup",
                           "happy", "proud", "smug", "curious", "sleepy", "worried", "sulky", "love", "nod",
                           "thinking", "shrug", "idle", "working", "terminal", "needs_you", "no_app", "none"}) {
    TEST_ASSERT_TRUE_MESSAGE(animFromName(gone) == Anim::kNone, gone);
  }
}

// characters/CHARACTER.md §9: the pack's 42 moods, by the
// names the Mac sends; the pixel designs draw thirteen, by name, in faces.h's
// order; a missing or unknown one is the startup mood, happy.
static void test_every_mood_has_a_name() {
  TEST_ASSERT_EQUAL_INT(kMoodCount, int(Mood::kCount));
  for (int i = 0; i < int(Mood::kCount); ++i) TEST_ASSERT_TRUE(moodFromName(moodName(Mood(i))) == Mood(i));
  const char* names[] = {"happy", "excited", "proud",     "curious", "determined", "grumpy", "sad",
                         "calm",  "engaged", "annoyed", "irritated", "whiny",      "wounded"};
  TEST_ASSERT_EQUAL_INT(13, render::pixelMoods());
  for (int i = 0; i < 13; ++i) TEST_ASSERT_EQUAL_STRING(names[i], moodName(render::pixelMood(i)));
  TEST_ASSERT_EQUAL_STRING("happy", moodName(render::kStartupMood));
  for (const char* other : {"cheerful", "sleepy", "", "Happy", "Calm"}) {
    TEST_ASSERT_TRUE_MESSAGE(moodFromName(other) == Mood::kHappy, other);
    Mood m = Mood::kSad;
    TEST_ASSERT_FALSE_MESSAGE(parseMood(other, m), other);
    TEST_ASSERT_TRUE(m == Mood::kSad);  // untouched
  }
  TEST_ASSERT_TRUE(moodFromName(nullptr) == Mood::kHappy);
}

// The designs' 22 states by name, in faces.h's order, the
// first seven keeping their numbers; a missing or unknown one is idle.
static void test_every_state_has_a_name() {
  TEST_ASSERT_EQUAL_INT(22, int(SceneState::kCount));
  const char* names[] = {"idle",      "working",   "needs_you",  "task_complete", "asleep",  "no_app",
                         "listening", "starting",  "planning",   "terminal",      "tool_use", "searching",
                         "analyzing", "testing",   "delegating", "helper_return", "waiting", "reply_ready",
                         "error",     "stopped",   "poked",      "tap_spam"};
  for (int i = 0; i < 22; ++i) {
    TEST_ASSERT_EQUAL_STRING(names[i], stateName(SceneState(i)));
    TEST_ASSERT_TRUE(stateFromName(names[i]) == SceneState(i));
  }
  for (const char* other : {"cheer", "busy", "", "Idle"}) TEST_ASSERT_TRUE_MESSAGE(stateFromName(other) == SceneState::kIdle, other);
  TEST_ASSERT_TRUE(stateFromName(nullptr) == SceneState::kIdle);
}

// The strip's divider is drawn only over bare glass, so it
// doesn't cut through the props an older mood's working look draws into
// the lane.
static void test_the_divider_leaves_the_design_alone() {
  Buf b;
  b.c.fillRect(100, kStripTop - 4, 30, 10, 7);  // a prop across the divider's row
  Strip busy;
  busy.busy = 1;
  drawStrip(b.c, busy);
  for (int x = 100; x < 130; ++x) TEST_ASSERT_EQUAL_INT(7, b.at(x, kStripTop));
  TEST_ASSERT_EQUAL_INT(inkAt(kInkDim, kLevels), b.at(60, kStripTop));
  TEST_ASSERT_EQUAL_INT(inkAt(kInkDim, kLevels), b.at(200, kStripTop));
}

static void test_an_empty_strip_is_bare_glass() {
  // With nothing to count or flag, the strip shows nothing, not even its
  // divider; with anything, the divider is there.
  auto lit = [](const Strip& s) {
    Buf b;
    drawStrip(b.c, s);
    int n = 0;
    for (uint8_t v : b.px) n += v != kBlack;
    return n;
  };
  TEST_ASSERT_EQUAL_INT(0, lit(Strip{}));
  Strip busy, noApp, needsYou;
  busy.busy = 1, noApp.noApp = true, needsYou.agent = "codex";
  for (const Strip& s : {busy, noApp, needsYou}) {
    Buf b;
    drawStrip(b.c, s);
    TEST_ASSERT_EQUAL_INT(inkAt(kInkDim, kLevels), b.at(kWidth / 2, kStripTop));
  }
}

// While something needs you, the strip says who in amber, cut to
// leave room for "+N" and the working count, which stay whole.
static void test_the_strip_says_who_needs_you() {
  auto amberCols = [](const Strip& s, int& last) {
    Buf b;
    drawStrip(b.c, s);
    int n = 0;
    last = -1;
    for (int x = 0; x < kWidth; ++x) {
      bool lit = false;
      for (int y = kStripTop + 1; y < kHeight; ++y) lit = lit || b.at(x, y) == inkAt(kInkAmber, kLevels);
      if (lit) ++n, last = x;
    }
    return n;
  };
  Strip who, longWho;
  who.agent = "codex", who.project = "landing", who.more = 1, who.busy = 1;
  longWho = who, longWho.project = "a-really-long-project..";
  int lastWho, lastLong;
  TEST_ASSERT_TRUE(amberCols(who, lastWho) > 0);
  amberCols(longWho, lastLong);
  TEST_ASSERT_TRUE(lastLong > lastWho);  // "codex · a-really-lo.." takes the room there is
  Buf b;
  drawStrip(b.c, longWho);
  bool grey = false;  // the working count still shows, in grey, at the right of the cut name
  for (int x = lastLong + 1; x < kWidth - 12; ++x) {
    for (int y = kStripTop + 1; y < kHeight; ++y) grey = grey || b.at(x, y) == inkAt(kInkGrey, kLevels);
  }
  TEST_ASSERT_TRUE(grey);
  TEST_ASSERT_TRUE(lastLong < kWidth - 12);
  // The thread's name shows in the project's place: "codex · a-really-lo.."
  // drawn as a name is the same pixels as drawn as a project.
  Strip named = who;
  named.name = longWho.project;
  Buf asName, asProject;
  drawStrip(asName.c, named);
  drawStrip(asProject.c, longWho);
  TEST_ASSERT_EQUAL_MEMORY(asProject.c.pixels(), asName.c.pixels(), kWidth * kHeight);
}

// The bubble shows the take's text, in amber, centred;
// every take's text in the card's pack fits whole inside the margins, in
// the large font or else the small one ("Technical difficulties" is the
// widest), and only text too long for the bubble ends "..".
static void test_the_bubble_fits_every_take() {
  NEEDS_VOICE_PACK();
  auto draw = [](const char* text, int& left, int& right) {
    Buf b;
    drawFaceScreen(b.c, SceneShow{}, text, Strip{});
    int n = 0;
    left = kWidth, right = -1;
    for (int y = kLaneTop; y < kHeight; ++y) {
      for (int x = 0; x < kWidth; ++x) {
        bool amber = false;  // at any of the ink's anti-aliased levels
        for (int l = 1; l <= kLevels; ++l) amber = amber || b.at(x, y) == inkAt(kInkAmber, l);
        if (!amber) continue;
        ++n;
        if (x < left) left = x;
        if (x > right) right = x;
      }
      for (int x : {0, 11, kWidth - 12, kWidth - 1}) TEST_ASSERT_EQUAL_INT(kBlack, b.at(x, y));
    }
    return n;
  };
  if (!packfile::open()) TEST_FAIL_MESSAGE("no voice pack: the chosen character pack has none");
  // Each take's text from the pack's index: a 64-byte header with the count
  // at 24 and the index at 32, then 128-byte records, the text at 72.
  uint8_t h[64];
  TEST_ASSERT_TRUE(packfile::source().read(0, h, sizeof(h)));
  auto u32 = [](const uint8_t* p) { return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24; };
  const uint32_t count = u32(h + 24), indexAt = u32(h + 32);
  TEST_ASSERT_EQUAL_UINT32(2722, count);
  const int room = kWidth - 2 * 12 - 2 * (10 + 2);  // the margins, the padding and the outline
  for (uint32_t i = 0; i < count; ++i) {
    char text[37] = {};
    TEST_ASSERT_TRUE(packfile::source().read(indexAt + i * 128 + 72, text, 36));
    // Whole: it fits the room in one font or the other, so nothing cuts it.
    const Font& f = stringWidth(kLarge, text) <= room ? kLarge : kSmall;
    TEST_ASSERT_TRUE_MESSAGE(stringWidth(f, text) <= room, text);
    int left, right;
    TEST_ASSERT_TRUE(draw(text, left, right) > 0);
    TEST_ASSERT_INT_WITHIN_MESSAGE(f.w, kWidth - 1 - right, left, text);  // centred
  }
  int left, right;
  draw("a very long line that cannot fit", left, right);  // cut, but inside the margins
}

// The bubble sits in the bottom lane, below
// y 192, which the animation bank's designs leave for text: it takes the
// strip's place while it shows and leaves the design above untouched. Over
// a design that draws to the bottom (the first pack's success), it blanks the
// lane first.
static void test_the_bubble_takes_the_lane() {
  const char* m = "Yay";
  Strip s;
  s.busy = 2, s.doneAgent = "codex", s.doneThread = "landing", s.doneOutcome = Outcome::kSuccess;
  for (SceneState st : {SceneState::kIdle, SceneState::kTaskComplete}) {
    SceneShow face;
    face.state = st;
    Buf with, without, face0;
    drawFaceScreen(with.c, face, m, s);
    drawFaceScreen(without.c, face, nullptr, s);
    drawFaceScreen(face0.c, face, nullptr, Strip{});
    for (int y = 0; y < kLaneTop; ++y) {  // the design, as it was
      for (int x = 0; x < kWidth; ++x) TEST_ASSERT_EQUAL(face0.at(x, y), with.at(x, y));
    }
    int amber = 0, eye = 0;
    for (int y = kLaneTop; y < kHeight; ++y) {
      for (int x = 0; x < kWidth; ++x) {
        uint8_t v = with.at(x, y);
        amber += v == inkAt(kInkAmber, kLevels);
        eye += v == inkAt(kInkEye, kLevels);
        TEST_ASSERT_TRUE(v < faces::kSceneBase);  // the design's colours are gone from the lane
      }
    }
    TEST_ASSERT_TRUE(amber > 20);   // the word
    TEST_ASSERT_EQUAL_INT(0, eye);  // not the strip's names, which show without it
    int names = 0;
    for (int y = kStripTop; y < kHeight; ++y) {
      for (int x = 0; x < kWidth; ++x) names += without.at(x, y) == inkAt(kInkEye, kLevels);
    }
    TEST_ASSERT_TRUE(names > 20);
  }
}

// While the brain's finish plays, the strip names whose
// turn it was after a mark for its result: a tick for a success, a cross
// for a failure, three dots for a reply; each draws differently.
static void test_the_strip_marks_the_finish() {
  auto mark = [](Outcome o) {
    Strip s;
    s.doneAgent = "codex", s.doneThread = "landing", s.doneOutcome = o;
    Buf b;
    drawStrip(b.c, s);
    std::vector<uint8_t> icon;
    for (int y = kStripTop + 1; y < kHeight; ++y) {
      for (int x = 0; x < 28; ++x) icon.push_back(b.at(x, y));
    }
    return icon;
  };
  auto tick = mark(Outcome::kSuccess), cross = mark(Outcome::kFailure), dots = mark(Outcome::kNone);
  TEST_ASSERT_TRUE(tick != cross && cross != dots && tick != dots);
  for (const auto& icon : {tick, cross, dots}) {
    int lit = 0;
    for (uint8_t v : icon) lit += v == inkAt(kInkEye, kLevels);
    TEST_ASSERT_TRUE(lit > 0);
  }
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

// The needs-you sign: the whole face for kHoldMs, then the
// sign rises over kRiseMs, bouncing past its place, as the head shrinks
// behind it to peek over its top edge.
void test_the_sign_rises_then_peeks() {
  SignPose p = signPose(0);
  TEST_ASSERT_TRUE(p.signY >= kHeight);
  TEST_ASSERT_TRUE(p.whole);
  TEST_ASSERT_FALSE(p.hands);
  TEST_ASSERT_EQUAL_INT(64, p.scale);
  TEST_ASSERT_EQUAL_INT(kWidth / 2, p.headX);
  TEST_ASSERT_TRUE(signPose(Sign::kHoldMs).signY >= kHeight);
  bool past = false;
  for (uint32_t ms = Sign::kHoldMs; ms < Sign::kHoldMs + Sign::kRiseMs; ms += 10) past |= signPose(ms).signY < Sign::kTop;
  TEST_ASSERT_TRUE(past);
  p = signPose(Sign::kHoldMs + Sign::kRiseMs);
  TEST_ASSERT_EQUAL_INT(Sign::kTop, p.signY);
  TEST_ASSERT_EQUAL_INT(Sign::kHeadScale, p.scale);
  TEST_ASSERT_EQUAL_INT(Sign::kHeadY, p.headY);
  TEST_ASSERT_EQUAL_INT(Sign::kSpotX[0], p.headX);
  TEST_ASSERT_FALSE(p.whole);
  TEST_ASSERT_TRUE(p.hands);
  TEST_ASSERT_EQUAL_INT(1, p.glance);  // toward the sign's middle
  // The press dips the sign and the head together.
  SignPose dipped = signPose(Sign::kHoldMs + Sign::kRiseMs, false, 2);
  TEST_ASSERT_EQUAL_INT(p.signY + 2, dipped.signY);
  TEST_ASSERT_EQUAL_INT(p.headY + 2, dipped.headY);
}

// Settled, the head spends kHopMs at each spot, left, right, the middle and
// round again, ducking kDuckMs before it moves; the sign bumps up kNudgePx
// every kNudgeEveryMs.
void test_the_head_plays_peekaboo() {
  const uint32_t at = Sign::kSettledMs + Sign::kPopMs + 100;
  const int spots[] = {Sign::kSpotX[0], Sign::kSpotX[1], Sign::kSpotX[2], Sign::kSpotX[0]};
  for (int i = 0; i < 4; ++i) {
    SignPose p = signPose(at + i * Sign::kHopMs);
    TEST_ASSERT_EQUAL_INT(spots[i], p.headX);
    TEST_ASSERT_EQUAL_INT(spots[i], p.handX);
  }
  TEST_ASSERT_EQUAL_INT(-1, signPose(at + Sign::kHopMs).glance);  // right, looking left
  TEST_ASSERT_EQUAL_INT(64, Sign::kSpotX[0]);
  TEST_ASSERT_EQUAL_INT(256, Sign::kSpotX[1]);
  TEST_ASSERT_EQUAL_INT(160, Sign::kSpotX[2]);
  // Ducking: all the way behind the sign at the end of a spot.
  SignPose duck = signPose(Sign::kSettledMs + Sign::kHopMs - 1);
  TEST_ASSERT_TRUE(duck.headY - 26 * Sign::kHeadScale / 64 > duck.signY);
  TEST_ASSERT_TRUE(signPose(Sign::kSettledMs + Sign::kHopMs - Sign::kDuckMs - 1).headY <= Sign::kHeadY);
  // The nudge, at its top halfway through.
  TEST_ASSERT_EQUAL_INT(Sign::kTop - Sign::kNudgePx, signPose(Sign::kSettledMs + Sign::kNudgeMs / 2).signY);
  TEST_ASSERT_EQUAL_INT(Sign::kTop, signPose(Sign::kSettledMs + Sign::kNudgeMs + 1).signY);
  TEST_ASSERT_EQUAL_INT(Sign::kTop - Sign::kNudgePx,
                        signPose(Sign::kSettledMs + Sign::kNudgeEveryMs + Sign::kNudgeMs / 2).signY);
  TEST_ASSERT_EQUAL_UINT32(3600, Sign::kNudgeEveryMs);
  TEST_ASSERT_EQUAL_UINT32(4200, Sign::kHopMs);
}

// The sign: amber, with who's asking in black, the thread in the sign's
// font, 16 columns wide.
void test_the_sign_is_black_on_amber() {
  TEST_ASSERT_EQUAL_UINT8(kAmber, textAt(kInkOnAmber, 0));
  TEST_ASSERT_EQUAL_UINT16(0, paletteAt(textAt(kInkOnAmber, kLevels)));
  TEST_ASSERT_EQUAL_UINT16(rgb565(kAmberRgb), paletteAt(kAmber));
  TEST_ASSERT_EQUAL_INT(16, (Sign::kWidth - 2 * Sign::kPad) / kSign.w);
  Buf b;
  Strip s;
  s.agent = "claude", s.project = "boop", s.name = "Fix the login test";
  drawSignScreen(b.c, signPose(Sign::kSettledMs + Sign::kPopMs + 100), s);
  TEST_ASSERT_TRUE(b.count(kAmber) > kWidth * kHeight / 2);
  TEST_ASSERT_TRUE(b.count(textAt(kInkOnAmber, kLevels)) > 500);
  TEST_ASSERT_TRUE(b.count(sceneInk(1)) > 100);  // the head and the mitts
}

void test_text_wraps_at_spaces() {
  char lines[3][48];
  TEST_ASSERT_EQUAL_INT(2, wrapText("Thread name on \"needs..", 16, 3, &lines[0][0], 48));
  TEST_ASSERT_EQUAL_STRING("Thread name on", lines[0]);
  TEST_ASSERT_EQUAL_STRING("\"needs..", lines[1]);
  TEST_ASSERT_EQUAL_INT(2, wrapText("a-very-long-project-n..", 16, 3, &lines[0][0], 48));
  TEST_ASSERT_EQUAL_STRING("a-very-long-proj", lines[0]);
  TEST_ASSERT_EQUAL_STRING("ect-n..", lines[1]);
  TEST_ASSERT_EQUAL_INT(2, wrapText("one two three four five six", 10, 2, &lines[0][0], 48));
  TEST_ASSERT_EQUAL_STRING("one two", lines[0]);
  TEST_ASSERT_EQUAL_STRING("three fo..", lines[1]);
  TEST_ASSERT_EQUAL_INT(1, wrapText("caf\xC3\xA9 \xC2\xB7 ok", 16, 3, &lines[0][0], 48));
  TEST_ASSERT_EQUAL_INT(9, glyphCount(lines[0]));
  TEST_ASSERT_EQUAL_INT(0, wrapText("   ", 16, 3, &lines[0][0], 48));
}

int main(int, char**) {
  UNITY_BEGIN();
    RUN_TEST(test_ease_is_monotonic_from_0_to_1024);
  RUN_TEST(test_palette_ramps_run_from_black_to_the_ink);
  RUN_TEST(test_every_anim_has_a_name_and_ends);
  RUN_TEST(test_every_mood_has_a_name);
  RUN_TEST(test_every_state_has_a_name);
  RUN_TEST(test_an_empty_strip_is_bare_glass);
  RUN_TEST(test_the_divider_leaves_the_design_alone);
  RUN_TEST(test_the_strip_says_who_needs_you);
  RUN_TEST(test_the_bubble_fits_every_take);
  RUN_TEST(test_the_bubble_takes_the_lane);
  RUN_TEST(test_the_strip_marks_the_finish);
  RUN_TEST(test_fonts_are_monospaced_and_utf8_aware);
  RUN_TEST(test_the_sign_rises_then_peeks);
  RUN_TEST(test_the_head_plays_peekaboo);
  RUN_TEST(test_the_sign_is_black_on_amber);
  RUN_TEST(test_text_wraps_at_spaces);
  return UNITY_END();
}
