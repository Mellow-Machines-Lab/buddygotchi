// The renderer: integer maths, the rasterizer, the names of the
// animations and moods, the strip and the bubble, fonts and the palette ramps (the v1 build plan's F2, L0).
#include <unity.h>

#include <cstring>
#include <string>
#include <utility>
#include <vector>

#include "render/types.h"
#include "render/font.h"
#include "render/palette.h"
#include "render/maths.h"
#include "render/pixel/scene.h"
#include "render/screens.h"
#include "render/pixel/needs_you.h"
#include "voice/player.h"
#include "voice_file.h"  // internal/firmware/

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

// A design's screen, as the pixel face draws one: on black, with the
// bubble, else the strip.
void drawFaceScreen(Canvas& c, const SceneShow& face, const char* bubble, const Strip& s) {
  c.fill(kBlack);
  drawScene(c, face);
  drawLane(c, bubble, s);
}

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
// nothing else: the brain's finish (task_complete, reply_ready), wake_up
// and notice, the rules' reactions (starting, stopped, error, helper_return), a tap's
// (poked, tap_spam), the board's own to a gesture (gesture) and listening.
// The older names ("cheer", "wiggle") are gone
// with the reaction message. Each plays its own design, and every design
// has a loop.
static void test_every_anim_has_a_name_and_ends() {
  const char* names[] = {"task_complete", "reply_ready", "starting",  "stopped", "error",
                         "helper_return", "poked",       "tap_spam",  "wake_up", "listening", "gesture",
                         "notice"};
  int reactions = 0;
  for (int i = 0; i < int(SceneState::kCount); ++i) reactions += isReaction(SceneState(i));
  TEST_ASSERT_EQUAL_INT(12, reactions);
  for (const char* name : names) {
    const SceneState a = reactionFromName(name);
    TEST_ASSERT_TRUE_MESSAGE(isReaction(a), name);
    TEST_ASSERT_EQUAL_STRING(name, stateName(a));  // its own design
  }
  TEST_ASSERT_FALSE(isReaction(SceneState::kNone));
  TEST_ASSERT_EQUAL_STRING("none", stateName(SceneState::kNone));
  TEST_ASSERT_TRUE(reactionFromName("cheer") == SceneState::kNone);
  TEST_ASSERT_TRUE(reactionFromName("wiggle") == SceneState::kNone);
  TEST_ASSERT_TRUE(reactionFromName(nullptr) == SceneState::kNone);
  for (int m = 0; m < render::pixelMoods(); ++m) {
    for (int s = 0; s < int(SceneState::kCount); ++s) TEST_ASSERT_TRUE(loopMs(render::pixelMood(m), SceneState(s)) > 0);
  }
  for (const char* gone : {"dance", "oops", "side_eye", "stretch", "yawn", "zip", "gobble", "rumble", "levelup",
                           "happy", "proud", "smug", "curious", "sleepy", "worried", "sulky", "love", "nod",
                           "thinking", "shrug", "idle", "working", "terminal", "needs_you", "no_app", "none"}) {
    TEST_ASSERT_TRUE_MESSAGE(reactionFromName(gone) == SceneState::kNone, gone);
  }
}

// characters/CHARACTER.md §9: the pack's moods, by the
// names the Mac sends; the pixel designs draw thirteen, by name, in faces.h's
// order; a missing or unknown one is the startup mood, happy.
static void test_every_mood_has_a_name() {
  TEST_ASSERT_EQUAL_INT(kMoodCount, int(Mood::kCount));
  for (int i = 0; i < int(Mood::kCount); ++i) TEST_ASSERT_TRUE(moodFromName(moodName(Mood(i))) == Mood(i));
  const char* names[] = {"happy", "excited", "proud",     "curious", "determined", "grumpy", "sad",
                         "calm",  "engaged", "annoyed", "irritated", "whiny",      "wounded"};
  TEST_ASSERT_EQUAL_INT(13, render::pixelMoods());
  for (int i = 0; i < 13; ++i) TEST_ASSERT_EQUAL_STRING(names[i], moodName(render::pixelMood(i)));
  // Every mood is drawn: the others wear one of the thirteen (faces.h's kWears).
  for (int i = 0; i < int(Mood::kCount); ++i) TEST_ASSERT_TRUE_MESSAGE(render::pixelIndex(Mood(i)) >= 0, moodName(Mood(i)));
  TEST_ASSERT_EQUAL_INT(render::pixelIndex(Mood::kCalm), render::pixelIndex(Mood::kComfy));
  TEST_ASSERT_EQUAL_INT(render::pixelIndex(Mood::kWounded), render::pixelIndex(Mood::kFrightened));
  TEST_ASSERT_EQUAL_STRING("happy", moodName(render::kStartupMood));
  for (const char* other : {"cheerful", "no_such_mood", "", "Happy", "Calm"}) {
    TEST_ASSERT_TRUE_MESSAGE(moodFromName(other) == Mood::kHappy, other);
    Mood m = Mood::kSad;
    TEST_ASSERT_FALSE_MESSAGE(parseMood(other, m), other);
    TEST_ASSERT_TRUE(m == Mood::kSad);  // untouched
  }
  TEST_ASSERT_TRUE(moodFromName(nullptr) == Mood::kHappy);
}

// The designs' 25 states by name, in faces.h's order, the
// first seven keeping their numbers; a missing or unknown one is idle.
static void test_every_state_has_a_name() {
  TEST_ASSERT_EQUAL_INT(25, int(SceneState::kCount));
  const char* names[] = {"idle",      "working",   "needs_you",  "task_complete", "asleep",  "no_app",
                         "listening", "starting",  "planning",   "terminal",      "tool_use", "searching",
                         "analyzing", "testing",   "delegating", "helper_return", "waiting", "reply_ready",
                         "error",     "stopped",   "poked",      "tap_spam",      "wake_up", "gesture",
                         "notice"};
  for (int i = 0; i < int(sizeof names / sizeof names[0]); ++i) {
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

// A cut name leaves the counts after it the room they're drawn in: the
// working count, the helpers (minis, and "+N" past kMinis) and the idle
// count all end inside the strip's 12 px margin.
static void test_a_cut_name_leaves_the_counts_their_room() {
  for (int helpers : {2, kMinis, kMinis + 3}) {
    Strip s;
    s.agent = "codex", s.project = "a-really-long-project-name-that-is-cut";
    s.busy = 3, s.helpers = helpers, s.idle = 12;
    Buf b;
    drawStrip(b.c, s);
    int last = -1;
    for (int x = 0; x < kWidth; ++x)
      for (int y = kStripTop + 1; y < kHeight; ++y)
        if (b.at(x, y) != kBlack) last = x;
    TEST_ASSERT_TRUE_MESSAGE(last >= 0 && last < kWidth - 12, "the counts run into the margin");
  }
}

// The bubble shows the take's text, in amber, centred;
// every take's text in the card's voice file fits whole inside the margins, in
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
  if (!voicefile::open()) TEST_FAIL_MESSAGE("no voice file: the chosen character pack has none");
  // Each take's text from the voice file's index: a 64-byte header with the count
  // at 24 and the index at 32, then 128-byte records, the text at 72.
  uint8_t h[64];
  TEST_ASSERT_TRUE(voicefile::source().read(0, h, sizeof(h)));
  auto u32 = [](const uint8_t* p) { return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24; };
  const uint32_t count = u32(h + 24), indexAt = u32(h + 32);
  TEST_ASSERT_EQUAL_UINT32(2722, count);
  const int room = kWidth - 2 * 12 - 2 * (10 + 2);  // the margins, the padding and the outline
  for (uint32_t i = 0; i < count; ++i) {
    char text[37] = {};
    TEST_ASSERT_TRUE(voicefile::source().read(indexAt + i * 128 + 72, text, 36));
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

// The working count's mark is a ring with its left half filled, which no
// digit reads as: inside it, the left of its middle is lit and the right
// is bare glass.
static void test_the_working_mark_is_half_filled() {
  Strip s;
  s.busy = 2;
  Buf b;
  drawStrip(b.c, s);
  const int left = 12, top = (kStripTop + kHeight) / 2 - 5;  // its 10 × 10 box
  TEST_ASSERT_EQUAL_UINT8(inkAt(kInkGrey, kLevels), b.at(left + 3, top + 5));
  TEST_ASSERT_EQUAL_UINT8(kBlack, b.at(left + 6, top + 5));
}

// While the brain's finish plays, the strip names whose
// turn it was after a mark for its result: a tick for a success in sage, a
// cross for a failure in clay, three dots for a reply in the names' white;
// each draws differently.
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
  const std::pair<const std::vector<uint8_t>*, uint8_t> inks[] = {
      {&tick, kSage}, {&cross, kClay}, {&dots, inkAt(kInkEye, kLevels)}};
  for (const auto& [icon, ink] : inks) {
    int lit = 0;
    for (uint8_t v : *icon) lit += v == ink;
    TEST_ASSERT_TRUE(lit > 0);
  }
  TEST_ASSERT_EQUAL_HEX16(rgb565(kSageRgb), paletteAt(kSage));
  TEST_ASSERT_EQUAL_HEX16(rgb565(kClayRgb), paletteAt(kClay));
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

// The needs-you screen: the whole face for kHoldMs, then the
// placard rises over kRiseMs, bouncing past its place, as the head shrinks
// behind it to peek over its top edge.
void test_the_placard_rises_then_peeks() {
  NeedsYouPose p = needsYouPose(0);
  TEST_ASSERT_TRUE(p.placardY >= kHeight);
  TEST_ASSERT_TRUE(p.whole);
  TEST_ASSERT_FALSE(p.hands);
  TEST_ASSERT_EQUAL_INT(64, p.scale);
  TEST_ASSERT_EQUAL_INT(kWidth / 2, p.headX);
  TEST_ASSERT_TRUE(needsYouPose(NeedsYou::kHoldMs).placardY >= kHeight);
  bool past = false;
  for (uint32_t ms = NeedsYou::kHoldMs; ms < NeedsYou::kHoldMs + NeedsYou::kRiseMs; ms += 10)
    past |= needsYouPose(ms).placardY < NeedsYou::kTop;
  TEST_ASSERT_TRUE(past);
  p = needsYouPose(NeedsYou::kHoldMs + NeedsYou::kRiseMs);
  TEST_ASSERT_EQUAL_INT(NeedsYou::kTop, p.placardY);
  TEST_ASSERT_EQUAL_INT(NeedsYou::kHeadScale, p.scale);
  TEST_ASSERT_EQUAL_INT(NeedsYou::kHeadY, p.headY);
  TEST_ASSERT_EQUAL_INT(NeedsYou::kSpotX[0], p.headX);
  TEST_ASSERT_FALSE(p.whole);
  TEST_ASSERT_TRUE(p.hands);
  TEST_ASSERT_EQUAL_INT(1, p.glance);  // toward the placard's middle
  // The press dips the placard and the head together.
  NeedsYouPose dipped = needsYouPose(NeedsYou::kHoldMs + NeedsYou::kRiseMs, false, 2);
  TEST_ASSERT_EQUAL_INT(p.placardY + 2, dipped.placardY);
  TEST_ASSERT_EQUAL_INT(p.headY + 2, dipped.headY);
}

// Calm (settled until the sway, and for good once it gives up), the head
// spends kHopMs at each spot, left, right, the middle and round again,
// ducking kDuckMs before it moves; the placard bumps up kNudgePx every
// kNudgeEveryMs.
void test_the_head_plays_peekaboo() {
  const uint32_t at = Arc::kGiveUpAt + NeedsYou::kPopMs + 100;
  const int spots[] = {NeedsYou::kSpotX[0], NeedsYou::kSpotX[1], NeedsYou::kSpotX[2], NeedsYou::kSpotX[0]};
  for (int i = 0; i < 4; ++i) {
    NeedsYouPose p = needsYouPose(at + i * NeedsYou::kHopMs);
    TEST_ASSERT_EQUAL_INT(spots[i], p.headX);
    TEST_ASSERT_EQUAL_INT(spots[i], p.handX);
  }
  TEST_ASSERT_EQUAL_INT(-1, needsYouPose(at + NeedsYou::kHopMs).glance);  // right, looking left
  TEST_ASSERT_EQUAL_INT(64, NeedsYou::kSpotX[0]);
  TEST_ASSERT_EQUAL_INT(256, NeedsYou::kSpotX[1]);
  TEST_ASSERT_EQUAL_INT(160, NeedsYou::kSpotX[2]);
  // Ducking: all the way behind the placard at the end of a spot.
  NeedsYouPose duck = needsYouPose(Arc::kGiveUpAt + NeedsYou::kHopMs - 1);
  TEST_ASSERT_TRUE(duck.headY - 26 * NeedsYou::kHeadScale / 64 > duck.placardY);
  TEST_ASSERT_TRUE(needsYouPose(Arc::kGiveUpAt + NeedsYou::kHopMs - NeedsYou::kDuckMs - 1).headY <= NeedsYou::kHeadY);
  // The nudge, at its top halfway through.
  TEST_ASSERT_EQUAL_INT(NeedsYou::kTop - NeedsYou::kNudgePx,
                        needsYouPose(NeedsYou::kSettledMs + NeedsYou::kNudgeMs / 2).placardY);
  TEST_ASSERT_EQUAL_INT(NeedsYou::kTop, needsYouPose(NeedsYou::kSettledMs + NeedsYou::kNudgeMs + 1).placardY);
  TEST_ASSERT_EQUAL_INT(NeedsYou::kTop - NeedsYou::kNudgePx,
                        needsYouPose(NeedsYou::kSettledMs + NeedsYou::kNudgeEveryMs + NeedsYou::kNudgeMs / 2).placardY);
  TEST_ASSERT_EQUAL_UINT32(3600, NeedsYou::kNudgeEveryMs);
  TEST_ASSERT_EQUAL_UINT32(4200, NeedsYou::kHopMs);
}

// How far a pose's placard sways and bobs over a stretch, at most.
static void most(uint32_t from, uint32_t to, int& sway, int& bob) {
  sway = 0, bob = 0;
  for (uint32_t ms = from; ms < to; ms += 10) {
    NeedsYouPose q = needsYouPose(ms);
    if (q.placardX > sway) sway = q.placardX;
    if (NeedsYou::kTop - q.placardY > bob) bob = NeedsYou::kTop - q.placardY;
  }
}

// The longer it waits, the harder it asks: calm until kSwayAt (5 s), then
// it sways the placard until kShakeAt (12 s), then shakes it and waves a mitt
// until kStareAt (17 s), then lowers it and stares, its whole face up close,
// flat-mouthed and unblinking, until kGiveUpAt (22 s), when it goes back up
// and it's calm for good. The placard, and who's asking, shows throughout.
void test_it_asks_harder_the_longer_it_waits() {
  TEST_ASSERT_EQUAL_UINT32(5000, Arc::kSwayAt);
  TEST_ASSERT_EQUAL_UINT32(12000, Arc::kShakeAt);
  TEST_ASSERT_EQUAL_UINT32(17000, Arc::kStareAt);
  TEST_ASSERT_EQUAL_UINT32(22000, Arc::kGiveUpAt);
  int calmSway, calmBob, swaySway, swayBob, shakeSway, shakeBob, laterSway, laterBob;
  most(NeedsYou::kSettledMs, Arc::kSwayAt, calmSway, calmBob);
  most(Arc::kSwayAt, Arc::kShakeAt, swaySway, swayBob);
  most(Arc::kShakeAt, Arc::kStareAt, shakeSway, shakeBob);
  most(Arc::kGiveUpAt + Arc::kLowerMs, Arc::kGiveUpAt + 30000, laterSway, laterBob);
  TEST_ASSERT_EQUAL_INT(0, calmSway);
  TEST_ASSERT_EQUAL_INT(Arc::kSway, swaySway);
  TEST_ASSERT_EQUAL_INT(Arc::kShake, shakeSway);
  TEST_ASSERT_TRUE(shakeBob > swayBob && swayBob > calmBob);  // the nudge, calm
  TEST_ASSERT_EQUAL_INT(0, laterSway);
  TEST_ASSERT_EQUAL_INT(calmBob, laterBob);
  // Swaying it waves one mitt and shaking both, back and forth over the
  // placard's edge, the knuckles tilting with the wave, well clear of the
  // head; calm or staring, none.
  for (uint32_t ms : {3000u, 19000u, 25000u}) TEST_ASSERT_EQUAL_INT(0, needsYouPose(ms).waving);
  auto waves = [](uint32_t from, uint32_t to, int count, int reach) {
    int lo = 1000, hi = -1000, tilts = 0;
    for (uint32_t ms = from; ms < to; ms += 5) {
      NeedsYouPose q = needsYouPose(ms);
      TEST_ASSERT_EQUAL_INT(count, q.waving);
      TEST_ASSERT_EQUAL_INT(q.placardY - Arc::kMittUp, q.waveY);
      for (int x : {int(q.waveX), count == 2 ? int(q.waveX2) : int(q.waveX)}) {
        TEST_ASSERT_TRUE(x - q.headX > 70 || x - q.headX < -70);
        TEST_ASSERT_TRUE(x - 13 >= 0 && x + 13 < kWidth);
      }
      const int off = q.waveX - q.handX - (q.waveX > q.handX ? Arc::kMittOut : -Arc::kMittOut);
      lo = off < lo ? off : lo, hi = off > hi ? off : hi;
      tilts |= q.tilt < 0 ? 1 : q.tilt > 0 ? 2 : 0;
    }
    TEST_ASSERT_EQUAL_INT(-reach, lo);
    TEST_ASSERT_EQUAL_INT(reach, hi);
    TEST_ASSERT_EQUAL_INT(3, tilts);  // both ways
  };
  waves(Arc::kSwayAt, Arc::kShakeAt, 1, Arc::kSwayWave);
  waves(Arc::kShakeAt, Arc::kStareAt, 2, Arc::kShakeWave);
  TEST_ASSERT_TRUE(Arc::kShakeWaveMs < Arc::kSwayWaveMs);
  // The stare.
  NeedsYouPose p = needsYouPose(Arc::kStareAt + Arc::kLowerMs, true);
  TEST_ASSERT_EQUAL_INT(Arc::kStareTop, p.placardY);
  TEST_ASSERT_EQUAL_INT(Arc::kStareScale, p.scale);
  TEST_ASSERT_EQUAL_INT(Arc::kStareY, p.headY);
  TEST_ASSERT_EQUAL_INT(kWidth / 2, p.headX);
  TEST_ASSERT_TRUE(p.whole && p.flat);
  TEST_ASSERT_FALSE(p.eyesShut);
  TEST_ASSERT_EQUAL_INT(0, p.glance);
  TEST_ASSERT_TRUE(needsYouPose(8000, true).eyesShut);  // swaying, it blinks
  // Back up when it gives up.
  p = needsYouPose(Arc::kGiveUpAt + Arc::kLowerMs);
  TEST_ASSERT_EQUAL_INT(NeedsYou::kTop, p.placardY);
  TEST_ASSERT_EQUAL_INT(NeedsYou::kHeadScale, p.scale);
  TEST_ASSERT_FALSE(p.whole);
  // Every stage draws the placard over most of the screen, with the head.
  Strip s;
  s.agent = "claude", s.project = "boop", s.name = "Deploy the docs";
  for (uint32_t ms : {2000u, 8000u, 14000u, 19500u, 25000u}) {
    Buf b;
    drawNeedsYouScreen(b.c, needsYouPose(ms), s);
    TEST_ASSERT_TRUE(b.count(kAmber) > kWidth * kHeight / 3);
    TEST_ASSERT_TRUE(b.count(textAt(kInkOnAmber, kLevels)) > 300);
    TEST_ASSERT_TRUE(b.count(sceneInk(1)) > 100);
  }
}

// The placard: amber, with who's asking in black, the thread in kSign,
// 16 columns wide.
void test_the_placard_is_black_on_amber() {
  TEST_ASSERT_EQUAL_UINT8(kAmber, textAt(kInkOnAmber, 0));
  TEST_ASSERT_EQUAL_UINT16(0, paletteAt(textAt(kInkOnAmber, kLevels)));
  TEST_ASSERT_EQUAL_UINT16(rgb565(kAmberRgb), paletteAt(kAmber));
  TEST_ASSERT_EQUAL_INT(16, (NeedsYou::kWidth - 2 * NeedsYou::kPad) / kSign.w);
  Buf b;
  Strip s;
  s.agent = "claude", s.project = "boop", s.name = "Fix the login test";
  drawNeedsYouScreen(b.c, needsYouPose(NeedsYou::kSettledMs + NeedsYou::kPopMs + 100), s);
  TEST_ASSERT_TRUE(b.count(kAmber) > kWidth * kHeight / 2);
  TEST_ASSERT_TRUE(b.count(textAt(kInkOnAmber, kLevels)) > 500);
  TEST_ASSERT_TRUE(b.count(sceneInk(1)) > 100);  // the head and the mitts
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
  RUN_TEST(test_every_anim_has_a_name_and_ends);
  RUN_TEST(test_every_mood_has_a_name);
  RUN_TEST(test_every_state_has_a_name);
  RUN_TEST(test_an_empty_strip_is_bare_glass);
  RUN_TEST(test_the_divider_leaves_the_design_alone);
  RUN_TEST(test_the_strip_says_who_needs_you);
  RUN_TEST(test_a_cut_name_leaves_the_counts_their_room);
  RUN_TEST(test_the_bubble_fits_every_take);
  RUN_TEST(test_the_bubble_takes_the_lane);
  RUN_TEST(test_the_working_mark_is_half_filled);
  RUN_TEST(test_the_strip_marks_the_finish);
  RUN_TEST(test_fonts_are_monospaced_and_utf8_aware);
  RUN_TEST(test_the_placard_rises_then_peeks);
  RUN_TEST(test_the_head_plays_peekaboo);
  RUN_TEST(test_it_asks_harder_the_longer_it_waits);
  RUN_TEST(test_the_placard_is_black_on_amber);
  RUN_TEST(test_text_is_cut_at_a_word_where_one_fits);
  RUN_TEST(test_text_wraps_at_spaces_and_hyphens);
  RUN_TEST(test_text_folds_and_cuts_to_its_glyphs);
  return UNITY_END();
}
