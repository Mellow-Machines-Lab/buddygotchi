// The rig face (render/pixel/rig_face.h): each drawn mood at rest on its own
// art, as its idle design draws it; its parts chosen and placed by the
// channels (an eye shut below a third open, the body's squash and lean, the
// gaze); a style change's morph and dither; the "o" while it talks; the
// anchors that what it wears rides; and the designs it draws a face in, as
// they're drawn.
#include <unity.h>

#include <algorithm>
#include <cstdio>
#include <vector>

#include "faces.h"
#include "render/palette.h"
#include "render/pixel/rig_face.h"
#include "render/pixel/scene.h"

using namespace render;
using namespace render::pixel;

void setUp() {}
void tearDown() {}

namespace {

struct Buf {
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(kWidth) * kHeight, 0);
  Canvas c{px.data()};
  int count(uint8_t color) const {
    int n = 0;
    for (uint8_t p : px) n += p == color;
    return n;
  }
};

// At rest in mood m from 0, at t: idle's clip playing, nothing else.
RigFace at(Mood m, uint32_t t = 0) {
  RigFace f;
  f.reset(m, SceneState::kIdle, 0);
  f.advanceTo(t);
  return f;
}
// Where the body is now.
rig::Anchors anchors(const RigFace& f) {
  rig::Anchors a;
  f.frame(0, false, {}, {}, &a);
  return a;
}
// The part of a frame of this kind, or nullptr.
const Placed* find(const RigFrame& f, int kind, int nth = 0) {
  for (int i = 0; i < f.count; ++i)
    if (f.parts[i].kind == kind && nth-- == 0) return &f.parts[i];
  return nullptr;
}

}  // namespace

// At rest in each drawn mood, the rig face draws that mood's own parts where
// its art has them, whole: in its first idle's place at its start, with that
// design's decorations over it, the design as drawn, pixel for pixel.
static void test_each_mood_rests_on_its_own_art() {
  for (int d = 0; d < faces::kMoodCount; ++d) {
    const Mood m = pixelMood(d);
    TEST_ASSERT_NOT_NULL(RigFace::pose(m));
    const RigFrame f = at(m).frame(0, false);
    TEST_ASSERT_EQUAL_INT(4, f.count);  // two eyes, the cheeks, the mouth
    for (int i = 0; i < f.count; ++i) {
      const Placed& p = f.parts[i];
      const faces::Part& art = faces::kParts[d][p.kind];
      TEST_ASSERT_EQUAL_INT(d, p.style);
      TEST_ASSERT_TRUE(p.kind != faces::kPartShutL && p.kind != faces::kPartShutR);
      TEST_ASSERT_EQUAL_INT(art.x, p.x);
      TEST_ASSERT_EQUAL_INT(art.y, p.y);
      TEST_ASSERT_EQUAL_INT(1024, p.sx);
      TEST_ASSERT_EQUAL_INT(1024, p.sy);
      TEST_ASSERT_TRUE(p.dither.all());
    }
    Buf rig, baked;
    SceneShow s;
    s.mood = m, s.state = SceneState::kIdle;
    drawRig(rig.c, f, sceneFrame(s, true));
    drawScene(baked.c, s);
    TEST_ASSERT_EQUAL_MEMORY_MESSAGE(baked.px.data(), rig.px.data(), baked.px.size(), faces::kMoodNames[d]);
  }
}

// A blink closes each eye onto the line it shuts on: squashed about its
// pivot while it's a third open or more, its shut art below that.
static void test_an_eye_closes_onto_its_pivot_then_shows_shut() {
  RigFace f = at(Mood::kCalm);
  f.blink();
  f.advanceTo(30);
  const RigFrame closing = f.frame(0, false);
  const Placed* eye = find(closing, faces::kPartEyeL);
  TEST_ASSERT_NOT_NULL(eye);
  const faces::Part& art = faces::kParts[pixelIndex(Mood::kCalm)][faces::kPartEyeL];
  TEST_ASSERT_TRUE(eye->sy < 1024 && eye->sy >= 1024 / 3);
  TEST_ASSERT_EQUAL_INT(1024, eye->sx);
  TEST_ASSERT_EQUAL_INT(art.y, eye->y);  // it closes onto its pivot
  f.advanceTo(80);
  const RigFrame shut = f.frame(0, false);
  TEST_ASSERT_NULL(find(shut, faces::kPartEyeL));
  TEST_ASSERT_NOT_NULL(find(shut, faces::kPartShutL));
  TEST_ASSERT_NOT_NULL(find(shut, faces::kPartShutR));
  f.advanceTo(400);
  TEST_ASSERT_TRUE(f.frame(0, false) == at(Mood::kCalm, 400).frame(0, false));  // open again, at rest
}

// A new mood cross-fades its styles over the mixer's style mix: half way,
// both moods' parts, the old one's thresholds the rest of the new one's,
// each box between the two; then the new mood's alone.
static void test_a_mood_change_morphs_and_dissolves() {
  RigFace f = at(Mood::kHappy);
  f.setMood(Mood::kExcited);
  f.advanceTo(100);
  const RigFrame mid = f.frame(0, false);
  TEST_ASSERT_EQUAL_INT(8, mid.count);
  const Placed *out = find(mid, faces::kPartMouth), *in = find(mid, faces::kPartMouth, 1);
  TEST_ASSERT_NOT_NULL(in);
  TEST_ASSERT_EQUAL_INT(pixelIndex(Mood::kHappy), out->style);
  TEST_ASSERT_EQUAL_INT(pixelIndex(Mood::kExcited), in->style);
  TEST_ASSERT_TRUE(out->dither.lo == in->dither.hi && out->dither.hi == 16 && in->dither.lo == 0);
  TEST_ASSERT_TRUE(in->dither.hi > 0 && in->dither.hi < 16);
  // Happy's small mouth grows toward excited's wide one, which starts small.
  TEST_ASSERT_TRUE(out->sx > 1024 && in->sx < 1024);
  f.advanceTo(1000);
  const RigFrame after = f.frame(0, false);
  TEST_ASSERT_EQUAL_INT(4, after.count);
  TEST_ASSERT_TRUE(after == at(Mood::kExcited, 1000).frame(0, false));
}

// A press squashes the face onto its ground, wider and shorter; a stroke
// leans it the way the finger goes. Both settle back to rest.
static void test_a_press_squashes_and_a_stroke_leans() {
  RigFace f = at(Mood::kCalm);
  const Placed rest = *find(f.frame(0, false), faces::kPartEyeL);
  f.finger(true, 100, 120);
  f.advanceTo(60);
  const Placed pressed = *find(f.frame(0, false), faces::kPartEyeL);
  TEST_ASSERT_TRUE(pressed.sx > 1024 && pressed.sy < 1024);
  TEST_ASSERT_TRUE(pressed.y > rest.y);  // down toward the ground
  for (int x = 110; x <= 200; x += 10) f.finger(true, x, 120);
  f.finger(false, 0, 0);
  f.advanceTo(160);
  TEST_ASSERT_TRUE(anchors(f).crown.x > anchors(at(Mood::kCalm)).crown.x);  // its top leans right
  f.advanceTo(3000);
  TEST_ASSERT_TRUE(f.frame(0, false) == at(Mood::kCalm, 3000).frame(0, false));
}

// While it talks, the "o" takes the mouth's place, at its middle, in its ink.
static void test_talking_shows_the_o_in_the_mouths_place() {
  const RigFrame f = at(Mood::kCalm).frame(0, true);
  TEST_ASSERT_NULL(find(f, faces::kPartMouth));
  const faces::Part& mouth = faces::kParts[pixelIndex(Mood::kCalm)][faces::kPartMouth];
  TEST_ASSERT_EQUAL_INT(mouth.x + (mouth.x0 + mouth.x1) / 2 - kTalkW / 2, f.talkX);
  TEST_ASSERT_EQUAL_INT(sceneInk(1), f.talkInk);
}

// The anchors at rest are the mood's pose's; a press moves them with the
// face.
static void test_the_anchors_ride_the_face() {
  RigFace f = at(Mood::kHappy);
  const RigFace::Pose& rest = *RigFace::pose(Mood::kHappy);
  TEST_ASSERT_EQUAL_INT(rest.brim.y, anchors(f).brimF.y);
  TEST_ASSERT_EQUAL_INT(rest.hand.y, anchors(f).handF.y);
  const faces::Part& eye = faces::kParts[pixelIndex(Mood::kHappy)][faces::kPartEyeL];
  TEST_ASSERT_EQUAL_INT(eye.y + eye.y0, rest.brim.y);  // the top of its eyes
  f.finger(true, 160, 120);                            // a press: the face squashes down, and its brim with it
  f.advanceTo(60);
  TEST_ASSERT_TRUE(anchors(f).brimF.y > rest.brim.y);
}

// Every step of a design's loop: each time one of its tracks, the face's
// included, takes its next key.
static std::vector<uint32_t> steps(const SceneShow& show) {
  const faces::Scene& sc = faces::kScenes[sceneOf(show.mood, show.state, show.variant)];
  std::vector<uint32_t> out = {0};
  auto keys = [&](uint16_t track) {
    if (track == 0xFFFF) return;
    const faces::Track& tr = faces::kTracks[track];
    for (uint32_t r = 0; r < sc.loopMs / tr.dur; ++r)
      for (int k = 0; k < tr.n; ++k) out.push_back(r * tr.dur + faces::kKeys[tr.key0 + k]);
  };
  keys(sc.face);
  for (int i = 0; i < sc.groups; ++i) {
    const faces::Group& g = faces::kGroups[faces::kSceneGroups[sc.group0 + i]];
    for (uint16_t track : {g.move, g.show, g.fill}) keys(track);
  }
  std::sort(out.begin(), out.end());
  out.erase(std::unique(out.begin(), out.end()), out.end());
  return out;
}

// A design whose face is its mood's resting face (facegen's rig_face), at
// every step of its loop: drawn with the rig face at rest in its place,
// moved and shut as the design has it, it's the design as drawn, pixel for
// pixel, its desk and its decorations included, shut eyes, a mouth that
// moves on its own (sad's trembling lip) and all. The design without its
// face draws none of the face's eyes. And a design that shuts its face
// blinks on its own, so the device's blinks leave it be.
static void test_a_design_with_the_resting_face_draws_as_drawn() {
  int designs = 0, shut = 0, trembles = 0, frames = 0;
  for (int d = 0; d < faces::kMoodCount; ++d) {
    const Mood m = pixelMood(d);
    for (int s = 0; s < int(SceneState::kCount); ++s) {
      for (int v = 0; v < variants(m, SceneState(s)); ++v) {
        if (!rigFaced(m, SceneState(s), v)) continue;
        SceneShow show;
        show.mood = m, show.state = SceneState(s), show.variant = uint8_t(v);
        bool shuts = false, mouth = false;
        for (const uint32_t t : steps(show)) {
          show.t = t;
          Buf rig, baked;
          const FaceMove move = faceMove(show);
          drawRig(rig.c, at(m).frame(0, false, {}, move), sceneFrame(show, true));
          drawScene(baked.c, show);
          char why[96];
          std::snprintf(why, sizeof why, "%s %s %d at %u ms", faces::kMoodNames[d], faces::kStateNames[s], v + 1,
                        unsigned(t));
          TEST_ASSERT_EQUAL_MEMORY_MESSAGE(baked.px.data(), rig.px.data(), baked.px.size(), why);
          shuts = shuts || move.shut;
          mouth = mouth || move.mx || move.my;
          ++frames;
        }
        if (shuts) TEST_ASSERT_TRUE(blinksItself(m, show.state, v));
        shut += shuts, trembles += mouth;
        show.t = 0;
        Buf baked, around;
        const FaceMove move = faceMove(show);
        drawScene(baked.c, show);
        drawScene(around.c, sceneFrame(show, true));
        const faces::Part& eye = faces::kParts[d][faces::kPartEyeL];
        const faces::Rect& ink = faces::kPartRects[eye.rect0];  // a pixel of its art, unless a prop covers it
        const size_t px = size_t(eye.y + ink.y + move.dy + move.ey) * kWidth + eye.x + ink.x + move.dx + move.ex;
        if (!move.shut && baked.px[px] == sceneInk(ink.color)) TEST_ASSERT_EQUAL(kBlack, around.px[px]);
        ++designs;
      }
    }
  }
  TEST_ASSERT_TRUE(designs > 500);
  TEST_ASSERT_TRUE(shut > 400);  // most of them blink, or squeeze their eyes shut, on their own
  TEST_ASSERT_TRUE(trembles > 0);
  TEST_ASSERT_TRUE(frames > designs * 4);
}

// The rig face sits where its design moves the face: calm's perk lifts it
// to look up at you, and the rig face drawn there is the design as drawn.
static void test_the_rig_face_moves_as_its_design_moves_it() {
  SceneShow show;
  show.mood = moodFromName("calm"), show.state = SceneState::kNotice;
  TEST_ASSERT_TRUE(rigFaced(show.mood, show.state, 0));
  show.t = loopMs(show.mood, show.state) * 4 / 10;  // its second step up
  const FaceMove move = faceMove(show);
  TEST_ASSERT_TRUE(move.dy < -5);
  Buf rig, baked;
  drawRig(rig.c, at(show.mood).frame(0, false, {}, move), sceneFrame(show, true));
  drawScene(baked.c, show);
  TEST_ASSERT_EQUAL_MEMORY(baked.px.data(), rig.px.data(), baked.px.size());
}

// A cross-fade's two pictures share the pixels: each threshold is one's.
static void test_a_dither_shares_the_pixels() {
  for (int mix = 0; mix <= 1000; mix += 125) {
    const Dither in = Dither::fade(mix, true), out = Dither::fade(mix, false);
    Buf a, b;
    a.c.fillRect(0, 0, kWidth, kHeight, 1, in);
    b.c.fillRect(0, 0, kWidth, kHeight, 1, out);
    TEST_ASSERT_EQUAL_INT(kWidth * kHeight, a.count(1) + b.count(1));
    TEST_ASSERT_EQUAL_INT(kWidth * kHeight * in.hi / 16, a.count(1));
  }
  // Within another: a quarter of a half.
  const Dither d = Dither{0, 4}.within(Dither::fade(500, false));
  TEST_ASSERT_EQUAL_INT(8, d.lo);
  TEST_ASSERT_EQUAL_INT(10, d.hi);
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_each_mood_rests_on_its_own_art);
  RUN_TEST(test_an_eye_closes_onto_its_pivot_then_shows_shut);
  RUN_TEST(test_a_mood_change_morphs_and_dissolves);
  RUN_TEST(test_a_press_squashes_and_a_stroke_leans);
  RUN_TEST(test_talking_shows_the_o_in_the_mouths_place);
  RUN_TEST(test_the_anchors_ride_the_face);
  RUN_TEST(test_a_design_with_the_resting_face_draws_as_drawn);
  RUN_TEST(test_the_rig_face_moves_as_its_design_moves_it);
  RUN_TEST(test_a_dither_shares_the_pixels);
  return UNITY_END();
}
