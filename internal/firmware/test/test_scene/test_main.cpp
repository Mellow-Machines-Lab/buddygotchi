// The animation bank's player (render/pixel/scene.h) against facegen's own
// drawing of the designs, which facegen --check holds to Chrome's drawing
// of the SVGs (internal/VERIFICATION.md L0).
#include <unity.h>

#include "pack_file.h"  // internal/firmware/

#include <cstdio>
#include <vector>

#include "linkkit/codec.h"
#include "frames.h"
#include "render/palette.h"
#include "render/pixel/scene.h"

using namespace render;

void setUp() {}
void tearDown() {}

namespace {

struct Buf {
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(kWidth) * kHeight, 0);
  Canvas c{px.data()};
  // Draws the show on black, as facegen does.
  Buf& draw(const SceneShow& s) {
    c.fill(kBlack);
    drawScene(c, s);
    return *this;
  }
  uint8_t at(int x, int y) const { return px[size_t(y) * kWidth + x]; }
};

SceneShow show(Mood m, SceneState s, uint32_t t = 0, int variant = 0) {
  SceneShow v;
  v.mood = m, v.state = s, v.t = t, v.variant = uint8_t(variant);
  return v;
}

// Where two drawings differ: the box around every pixel that does, or none.
struct Box {
  int x0 = kWidth, y0 = kHeight, x1 = -1, y1 = -1;
  bool empty() const { return x1 < 0; }
};
Box differ(const Buf& a, const Buf& b) {
  Box d;
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      if (a.at(x, y) == b.at(x, y)) continue;
      if (x < d.x0) d.x0 = x;
      if (y < d.y0) d.y0 = y;
      if (x > d.x1) d.x1 = x;
      if (y > d.y1) d.y1 = y;
    }
  }
  return d;
}

}  // namespace

// Every sampled moment of every design, every variation, draws facegen's
// pixels exactly: the same palette index everywhere.
static void test_every_scene_matches_facegen() {
  Buf b;
  int failed = 0;
  for (const FacegenFrame& f : kFacegenFrames) {
    b.draw(show(pixelMood(f.mood), SceneState(f.state), f.t, f.variant));
    uint32_t crc = linkkit::crc32(b.px.data(), b.px.size());
    if (crc != f.crc) {
      char msg[64];
      std::snprintf(msg, sizeof msg, "mood %d state %d variant %d at %u ms", f.mood, f.state, f.variant + 1,
                    unsigned(f.t));
      TEST_MESSAGE(msg);
      ++failed;
    }
  }
  TEST_ASSERT_EQUAL_INT(0, failed);
  TEST_ASSERT_TRUE(sizeof(kFacegenFrames) / sizeof(kFacegenFrames[0]) > 1000);
}

// Each mood has its own variations of each state, each a
// design of its own; one out of range draws the first. The older seven moods
// have the first pack's (three a state, working five) and one or two of each
// newer state; the six new ones three of each, nine starts (three a context)
// and six finishes (three a result). Asleep and with no app, Boop looks the
// same in every older mood, and in every new one.
static void test_variations_and_shared_designs() {
  const int older[] = {3, 5, 3, 5, 3, 3, 3, 3, 1, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 1, 1};
  const int newer[] = {3, 5, 3, 6, 3, 3, 3, 9, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3};
  for (int m = 0; m < pixelMoods(); ++m) {
    for (int s = 0; s < int(SceneState::kCount); ++s) {
      int n = variants(render::pixelMood(m), SceneState(s));
      TEST_ASSERT_EQUAL_INT(m < pixelIndex(Mood::kCalm) ? older[s] : newer[s], n);
      TEST_ASSERT_TRUE(n >= 1 && n <= kMaxVariants);
      for (int v = 1; v < n; ++v) {
        TEST_ASSERT_NOT_EQUAL(sceneOf(render::pixelMood(m), SceneState(s), 0), sceneOf(render::pixelMood(m), SceneState(s), v));
      }
      TEST_ASSERT_EQUAL_INT(sceneOf(render::pixelMood(m), SceneState(s), 0), sceneOf(render::pixelMood(m), SceneState(s), 9));
      TEST_ASSERT_EQUAL_INT(sceneOf(render::pixelMood(m), SceneState(s), 0), sceneOf(render::pixelMood(m), SceneState(s), -1));
    }
    Mood family = m < pixelIndex(Mood::kCalm) ? Mood::kHappy : Mood::kCalm;
    for (int v = 0; v < 3; ++v) {
      TEST_ASSERT_EQUAL_INT(sceneOf(family, SceneState::kAsleep, v), sceneOf(render::pixelMood(m), SceneState::kAsleep, v));
      TEST_ASSERT_EQUAL_INT(sceneOf(family, SceneState::kNoApp, v), sceneOf(render::pixelMood(m), SceneState::kNoApp, v));
    }
    if (m) TEST_ASSERT_NOT_EQUAL(sceneOf(Mood::kHappy, SceneState::kIdle), sceneOf(render::pixelMood(m), SceneState::kIdle));
  }
  // A mood or state the device doesn't know draws happy's, and idle's.
  TEST_ASSERT_EQUAL_INT(sceneOf(Mood::kHappy, SceneState::kWorking), sceneOf(Mood::kCount, SceneState::kWorking));
  TEST_ASSERT_EQUAL_INT(sceneOf(Mood::kSad, SceneState::kIdle), sceneOf(Mood::kSad, SceneState::kCount));
}

// A finish's variations are each for a result, and a start's
// for a context; the filters pick among those that fit, and every variation
// when none does, as the Mac's FaceLoops.variants does.
static void test_variations_for_a_result_or_a_context() {
  uint8_t out[kMaxVariants];
  for (int m = 0; m < pixelMoods(); ++m) {
    Mood mood = render::pixelMood(m);
    int done = variants(mood, SceneState::kTaskComplete);
    int wins = 0, fails = 0;
    for (int v = 0; v < done; ++v) {
      Outcome o = variantOutcome(mood, SceneState::kTaskComplete, v);
      TEST_ASSERT_TRUE(o == Outcome::kSuccess || o == Outcome::kFailure);
      TEST_ASSERT_TRUE(variantCtx(mood, SceneState::kTaskComplete, v) == StartCtx::kNone);
      (o == Outcome::kSuccess ? wins : fails)++;
    }
    TEST_ASSERT_EQUAL_INT(m < pixelIndex(Mood::kCalm) ? 4 : 3, wins);  // the first pack's three successes, and the newer ones
    TEST_ASSERT_EQUAL_INT(m < pixelIndex(Mood::kCalm) ? 1 : 3, fails);
    for (Outcome o : {Outcome::kSuccess, Outcome::kFailure}) {
      int n = fitting(mood, SceneState::kTaskComplete, o, StartCtx::kNone, out);
      TEST_ASSERT_EQUAL_INT(o == Outcome::kSuccess ? wins : fails, n);
      for (int i = 0; i < n; ++i) {
        TEST_ASSERT_TRUE(variantOutcome(mood, SceneState::kTaskComplete, out[i]) == o);
        if (i) TEST_ASSERT_TRUE(out[i] > out[i - 1]);
      }
    }
    TEST_ASSERT_EQUAL_INT(done, fitting(mood, SceneState::kTaskComplete, Outcome::kNone, StartCtx::kNone, out));
    int starts = variants(mood, SceneState::kStarting);
    for (StartCtx c : {StartCtx::kNewTask, StartCtx::kSession, StartCtx::kContinuation}) {
      int n = fitting(mood, SceneState::kStarting, Outcome::kNone, c, out);
      TEST_ASSERT_EQUAL_INT(starts / 3, n);
      for (int i = 0; i < n; ++i) TEST_ASSERT_TRUE(variantCtx(mood, SceneState::kStarting, out[i]) == c);
    }
    // A fact no variation is for, or one that doesn't apply, takes them all.
    TEST_ASSERT_EQUAL_INT(starts, fitting(mood, SceneState::kStarting, Outcome::kSuccess, StartCtx::kNone, out));
    TEST_ASSERT_EQUAL_INT(variants(mood, SceneState::kWorking),
                          fitting(mood, SceneState::kWorking, Outcome::kFailure, StartCtx::kSession, out));
    for (int s = 0; s < int(SceneState::kCount); ++s) {
      if (s == int(SceneState::kTaskComplete) || s == int(SceneState::kStarting)) continue;
      for (int v = 0; v < variants(mood, SceneState(s)); ++v) {
        TEST_ASSERT_TRUE(variantOutcome(mood, SceneState(s), v) == Outcome::kNone);
        TEST_ASSERT_TRUE(variantCtx(mood, SceneState(s), v) == StartCtx::kNone);
      }
    }
  }
  TEST_ASSERT_TRUE(outcomeFromName("failure") == Outcome::kFailure);
  TEST_ASSERT_TRUE(outcomeFromName("win") == Outcome::kNone);
  TEST_ASSERT_TRUE(outcomeFromName(nullptr) == Outcome::kNone);
  TEST_ASSERT_TRUE(ctxFromName("continuation") == StartCtx::kContinuation);
  TEST_ASSERT_TRUE(ctxFromName("resume") == StartCtx::kNone);
}

// Shut eyes, a blink's or the one that hides a change of design, show the
// design's closed eyes: only the face changes. The first pack's designs
// shut their eyes; a new mood's flip-book shows the face of its own blink
// step in place of the step showing.
static void test_a_blink_shows_the_closed_eyes() {
  for (int m = 0; m < pixelMoods(); ++m) {
    for (SceneState st : {SceneState::kIdle, SceneState::kWorking, SceneState::kPoked, SceneState::kTaskComplete}) {
      if (st == SceneState::kTaskComplete && m < pixelIndex(Mood::kCalm)) continue;  // the first pack's successes, colour to the edges
      Buf open, shut;
      open.draw(show(render::pixelMood(m), st, 300));
      SceneShow s = show(render::pixelMood(m), st, 300);
      TEST_ASSERT_FALSE(eyesClosed(s));
      s.eyesShut = true;
      TEST_ASSERT_TRUE(eyesClosed(s));
      TEST_ASSERT_EQUAL(m >= pixelIndex(Mood::kCalm), blinksItself(render::pixelMood(m), st, 0));
      shut.draw(s);
      Box d = differ(open, shut);
      TEST_ASSERT_FALSE(d.empty());
      TEST_ASSERT_TRUE(d.y0 >= 40 && d.y1 < 150);  // the face
    }
  }
}

// Talking, the mouth is a small "o" where it was, in its colour: the
// first pack's where it always sat.
static void test_the_mouth_opens_to_talk() {
  Buf closed, talking;
  closed.draw(show(Mood::kHappy, SceneState::kIdle));
  SceneShow s = show(Mood::kHappy, SceneState::kIdle);
  s.mouthOpen = true;
  talking.draw(s);
  Box d = differ(closed, talking);
  TEST_ASSERT_FALSE(d.empty());
  TEST_ASSERT_TRUE(d.x0 >= 145 && d.x1 < 175 && d.y0 >= 125 && d.y1 < 142);
  TEST_ASSERT_EQUAL(sceneInk(1), talking.at(154, 129));  // the o's ring, at (153, 128)
  TEST_ASSERT_EQUAL(sceneInk(1), talking.at(153, 128));
  TEST_ASSERT_EQUAL(kBlack, talking.at(160, 134));       // its hole
  // The first pack's success draws its face dark on gold: the o is dark too.
  Buf cheer;
  SceneShow c = show(Mood::kHappy, SceneState::kTaskComplete, 300);
  c.mouthOpen = true;
  cheer.draw(c);
  Buf shut;
  c.mouthOpen = false;
  shut.draw(c);
  Box o = differ(shut, cheer);
  TEST_ASSERT_FALSE(o.empty());
  TEST_ASSERT_EQUAL(cheer.at(o.x0 + 1, o.y0 + 1), cheer.at(o.x0 + 1, o.y1));  // one colour, all round
  TEST_ASSERT_NOT_EQUAL(sceneInk(1), cheer.at(o.x0 + 1, o.y0 + 1));
}

// A flip-book has a face, with its mouth, in each step: talking opens the
// mouth of the face that shows, wherever that step has put it, on the mouth
// it draws, and only the mouth changes.
static void test_a_flip_book_talks_with_the_face_that_shows() {
  // Calm's mouth at rest is 22 × 4 px at (149, 123): the o sits on it.
  Buf rest, open;
  rest.draw(show(Mood::kCalm, SceneState::kIdle));
  SceneShow t = show(Mood::kCalm, SceneState::kIdle);
  t.mouthOpen = true;
  open.draw(t);
  Box o = differ(rest, open);
  TEST_ASSERT_TRUE(o.y0 <= 123 && o.y1 >= 126);  // over the lips, not below them
  TEST_ASSERT_TRUE(o.x0 >= 149 && o.x1 <= 170);
  for (Mood m : {Mood::kCalm, Mood::kIrritated, Mood::kWhiny}) {
    uint32_t loop = loopMs(m, SceneState::kWorking);
    int moved = 0;
    Box first;
    for (uint32_t t = 0; t < loop; t += loop / 9) {
      Buf closed, talking;
      closed.draw(show(m, SceneState::kWorking, t));
      SceneShow s = show(m, SceneState::kWorking, t);
      s.mouthOpen = true;
      talking.draw(s);
      Box d = differ(closed, talking);
      TEST_ASSERT_FALSE(d.empty());
      TEST_ASSERT_TRUE(d.x0 >= 135 && d.x1 < 185 && d.y0 >= 110 && d.y1 < 155);  // about the mouth
      if (first.empty()) first = d;
      moved += d.x0 != first.x0 || d.y0 != first.y0;
    }
    TEST_ASSERT_TRUE(moved > 0);  // with the step's face, not in one place
  }
}

// A press moves the whole face; the props stay.
static void test_the_face_moves_as_one() {
  Buf still, moved, back;
  still.draw(show(Mood::kHappy, SceneState::kWorking));
  SceneShow s = show(Mood::kHappy, SceneState::kWorking);
  s.dy = 2;
  moved.draw(s);
  int same = 0, face = 0;
  for (int y = 40; y < 140; ++y) {
    for (int x = 40; x < 290; ++x) {
      if (still.at(x, y) == kBlack) continue;
      ++face;
      same += moved.at(x, y + 2) == still.at(x, y);
    }
  }
  TEST_ASSERT_TRUE(face > 100);
  TEST_ASSERT_TRUE(same * 10 >= face * 9);  // the face, shifted
  for (int y = 180; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) TEST_ASSERT_EQUAL(still.at(x, y), moved.at(x, y));  // the props, not
  }
}

// A flip-book's face moves as one too: the face of the step that shows.
static void test_a_flip_book_face_moves_as_one() {
  for (uint32_t t : {0u, 900u, 2300u}) {
    Buf still, moved;
    still.draw(show(Mood::kEngaged, SceneState::kIdle, t));
    SceneShow s = show(Mood::kEngaged, SceneState::kIdle, t);
    s.dy = 2;
    moved.draw(s);
    int same = 0, face = 0;
    for (int y = 40; y < 140; ++y) {
      for (int x = 40; x < 290; ++x) {
        if (still.at(x, y) == kBlack) continue;
        ++face;
        same += moved.at(x, y + 2) == still.at(x, y);
      }
    }
    TEST_ASSERT_TRUE(face > 100);
    TEST_ASSERT_TRUE(same * 10 >= face * 9);
  }
}

// Needs you's art stays above y 192: the bottom 48 px are the strip's.
static void test_needs_you_leaves_the_bottom_lane() {
  for (int m = 0; m < pixelMoods(); ++m) {
    for (int v = 0; v < variants(render::pixelMood(m), SceneState::kNeedsYou); ++v) {
      for (uint32_t t : {0u, 700u, 1500u, 3000u}) {
        Buf b;
        b.draw(show(render::pixelMood(m), SceneState::kNeedsYou, t, v));
        for (int y = 192; y < kHeight; ++y) {
          for (int x = 0; x < kWidth; ++x) TEST_ASSERT_EQUAL(kBlack, b.at(x, y));
        }
      }
    }
  }
}

// A frame changes when a step or an addition does, and only then.
static void test_frames_change_only_when_the_picture_can() {
  SceneShow a = show(Mood::kExcited, SceneState::kWorking, 1000);
  SceneShow b = a;
  b.t = 1001;
  TEST_ASSERT_TRUE(sceneFrame(a) == sceneFrame(b));
  bool changed = false;
  for (uint32_t t = 1000; t < 3000 && !changed; t += 10) b.t = t, changed = sceneFrame(a) != sceneFrame(b);
  TEST_ASSERT_TRUE(changed);
  b = a;
  b.eyesShut = true;
  TEST_ASSERT_TRUE(sceneFrame(a) != sceneFrame(b));
  b = a;
  b.mood = Mood::kSad;
  TEST_ASSERT_TRUE(sceneFrame(a) != sceneFrame(b));
  b = a;
  b.variant = 1;
  TEST_ASSERT_TRUE(sceneFrame(a) != sceneFrame(b));
  b = a;
  b.dy = 1;
  TEST_ASSERT_TRUE(sceneFrame(a) != sceneFrame(b));
}

// The gold fades of the first pack's successes show in the frame: the
// colour steps count as changes.
static void test_a_fade_changes_the_frame() {
  bool changed = false;
  SceneShow a = show(Mood::kHappy, SceneState::kTaskComplete, 0);
  for (uint32_t t = 0; t < 6400 && !changed; t += 20) {
    SceneShow b = a;
    b.t = t;
    SceneFrame fa = sceneFrame(a), fb = sceneFrame(b);
    for (int i = 0; i < SceneFrame::kMaxGroups; ++i) changed = changed || fa.fill[i] != fb.fill[i];
  }
  TEST_ASSERT_TRUE(changed);
}

int main(int, char**) {
  UNITY_BEGIN();
  if (!packfile::open()) std::printf("no voice pack: the chosen character pack has none\n");
  RUN_TEST(test_every_scene_matches_facegen);
  RUN_TEST(test_variations_and_shared_designs);
  RUN_TEST(test_variations_for_a_result_or_a_context);
  RUN_TEST(test_a_blink_shows_the_closed_eyes);
  RUN_TEST(test_the_mouth_opens_to_talk);
  RUN_TEST(test_a_flip_book_talks_with_the_face_that_shows);
  RUN_TEST(test_the_face_moves_as_one);
  RUN_TEST(test_a_flip_book_face_moves_as_one);
  RUN_TEST(test_needs_you_leaves_the_bottom_lane);
  RUN_TEST(test_frames_change_only_when_the_picture_can);
  RUN_TEST(test_a_fade_changes_the_frame);
  return UNITY_END();
}
