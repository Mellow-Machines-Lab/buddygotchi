// The rig core (render/rig/): clips sampled with their eases and loops; the
// mixer's springs, reaction weights, blending and style cross-fades; the
// ramp the fades ease on; and the staged pack's rig_tables.h.
#include <unity.h>

#include <algorithm>
#include <cstdlib>
#include <initializer_list>
#include <vector>

#include "render/maths.h"
#include "render/rig/mixer.h"
#include "rig_tables.h"  // the staged pack's (characters/charactergen.py)

using namespace render;
using namespace render::rig;

void setUp() {}
void tearDown() {}

namespace {
// Clips for the tests, each a track or two held or ramped.
constexpr Key kRamp[] = {{0, 0, Ease::kLinear}, {100, 1000, Ease::kLinear}, {200, 0, Ease::kIn}};
constexpr Track kRampTrack = {Channel::kLean, {kRamp, 3}};
constexpr Key kLater[] = {{50, 300, Ease::kLinear}, {150, 600, Ease::kOut}};
constexpr Track kLaterTrack = {Channel::kLean, {kLater, 2}};

constexpr Key kLeanIn[] = {{0, 500, Ease::kLinear}, {1000, 500, Ease::kLinear}};
constexpr Track kLeanInTracks[] = {{Channel::kLean, {kLeanIn, 2}}};
constexpr Clip kLean = {"lean", 1000, false, true, {kLeanInTracks, 1}};
constexpr Clip kLeanLoop = {"lean-loop", 1000, true, true, {kLeanInTracks, 1}};
constexpr Key kLeanBack[] = {{0, -300, Ease::kLinear}, {1000, -300, Ease::kLinear}};
constexpr Track kLeanBackTracks[] = {{Channel::kLean, {kLeanBack, 2}}};
constexpr Clip kLeanBackLoop = {"lean-back", 1000, true, true, {kLeanBackTracks, 1}};
constexpr Clip kLeanBackNow = {"lean-back-now", 1000, true, false, {kLeanBackTracks, 1}};

constexpr Key kPlus[] = {{0, 200, Ease::kLinear}, {1000, 200, Ease::kLinear}};
constexpr Track kPlusTracks[] = {{Channel::kLean, {kPlus, 2}}};
constexpr Clip kLeanMore = {"lean-more", 1000, true, true, {kPlusTracks, 1}};
constexpr Key kShut[] = {{0, 0, Ease::kLinear}, {1000, 0, Ease::kLinear}};
constexpr Key kOpen[] = {{0, 300, Ease::kLinear}, {1000, 300, Ease::kLinear}};
constexpr Track kShutTracks[] = {{Channel::kEyeOpenL, {kShut, 2}}};
constexpr Track kWiderTracks[] = {{Channel::kEyeOpenL, {kOpen, 2}}};
constexpr Clip kShutLoop = {"shut", 1000, true, false, {kShutTracks, 1}};
constexpr Clip kWider = {"wider", 1000, true, true, {kWiderTracks, 1}};

constexpr Key kDip[] = {
    {0, 0, Ease::kLinear}, {60, -1000, Ease::kIn}, {100, -1000, Ease::kLinear}, {180, 0, Ease::kOut}};
constexpr Track kDipTracks[] = {{Channel::kEyeOpenL, {kDip, 4}}};
constexpr Clip kBlink = {"blink", 180, false, true, {kDipTracks, 1}};

// A channel's value each frame of `frames` frames, `ms` apart.
std::vector<int> record(Mixer& m, Channel c, int frames, uint32_t ms = 16) {
  std::vector<int> out;
  for (int i = 0; i < frames; ++i) {
    m.advance(ms);
    out.push_back(m.channels()[c]);
  }
  return out;
}
// The largest change from one frame to the next.
int steepest(const std::vector<int>& v) {
  int most = 0;
  for (size_t i = 1; i < v.size(); ++i) most = std::max(most, std::abs(v[i] - v[i - 1]));
  return most;
}
// At rest in styles 0, with nothing playing.
Mixer still() {
  Mixer m;
  m.reset(0, 0, nullptr);
  return m;
}
}  // namespace

// ---- Clips -------------------------------------------------------------------

static void test_eases_run_from_0_to_1024_in_their_shapes() {
  TEST_ASSERT_EQUAL_INT(512, eased(Ease::kLinear, 50, 100));
  TEST_ASSERT_EQUAL_INT(256, eased(Ease::kIn, 50, 100));
  TEST_ASSERT_EQUAL_INT(768, eased(Ease::kOut, 50, 100));
  TEST_ASSERT_EQUAL_INT(ease(30, 100), eased(Ease::kInOut, 30, 100));  // render::ease's smoothstep
  for (Ease e : {Ease::kLinear, Ease::kIn, Ease::kOut, Ease::kInOut}) {
    TEST_ASSERT_EQUAL_INT(0, eased(e, 0, 100));
    TEST_ASSERT_EQUAL_INT(1024, eased(e, 100, 100));
    for (int t = 1, last = 0; t <= 100; last = eased(e, t, 100), ++t) TEST_ASSERT_TRUE(eased(e, t, 100) >= last);
  }
}

static void test_a_track_eases_between_its_keys_and_holds_its_ends() {
  TEST_ASSERT_EQUAL_INT(0, sample(kRampTrack, 0));
  TEST_ASSERT_EQUAL_INT(500, sample(kRampTrack, 50));
  TEST_ASSERT_EQUAL_INT(1000, sample(kRampTrack, 100));
  TEST_ASSERT_EQUAL_INT(1000 - 1000 * 256 / 1024, sample(kRampTrack, 150));  // in: slow from the key before
  TEST_ASSERT_EQUAL_INT(0, sample(kRampTrack, 200));
  TEST_ASSERT_EQUAL_INT(0, sample(kRampTrack, 900));
  TEST_ASSERT_EQUAL_INT(300, sample(kLaterTrack, 0));  // before its first key, the first key's
  TEST_ASSERT_EQUAL_INT(300 + 300 * 768 / 1024, sample(kLaterTrack, 100));
  TEST_ASSERT_EQUAL_INT(600, sample(kLaterTrack, 151));
}

static void test_a_clip_loops_or_holds_its_end() {
  TEST_ASSERT_EQUAL_UINT32(500, kLeanLoop.local(2500));
  TEST_ASSERT_EQUAL_UINT32(0, kLeanLoop.local(3000));
  TEST_ASSERT_EQUAL_UINT32(1000, kLean.local(2500));
  TEST_ASSERT_EQUAL_UINT32(250, kLean.local(250));
}

// ---- The mixer ---------------------------------------------------------------

// A reaction's weight eases in over kWeightMs as it starts and out as it
// ends: half way at 75 ms, whole at 150.
static void test_a_reactions_weight_eases_in_and_out() {
  static_assert(Mixer::kWeightMs == 150, "a clip's weight eases over 150 ms");
  Mixer m = still();
  m.play(kLean);
  m.advance(75);
  TEST_ASSERT_EQUAL_INT(250, m.channels()[Channel::kLean]);
  m.advance(75);
  TEST_ASSERT_EQUAL_INT(500, m.channels()[Channel::kLean]);
  m.advance(700);
  TEST_ASSERT_EQUAL_INT(500, m.channels()[Channel::kLean]);
  m.advance(75);  // 75 ms before its end
  TEST_ASSERT_EQUAL_INT(250, m.channels()[Channel::kLean]);
  m.advance(75);
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kLean]);
  m.advance(16);
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kLean]);
}

// A clip shorter than four fades eases in and out over a quarter of itself,
// so a 180 ms blink still shuts whole for its held keys.
static void test_a_short_clip_fades_over_a_quarter_of_itself() {
  Mixer m = still();
  m.play(kBlink);
  m.advance(60);
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kEyeOpenL]);  // whole by 45 ms
  m.advance(40);
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kEyeOpenL]);
  m.advance(80);
  TEST_ASSERT_EQUAL_INT(1000, m.channels()[Channel::kEyeOpenL]);
  // A clip of four fades or more fades over kWeightMs: half way at 75 ms.
  m.play(kLean);
  m.advance(75);
  TEST_ASSERT_EQUAL_INT(250, m.channels()[Channel::kLean]);
}

// Additive clips add, absolute ones blend toward their values by weight, in
// the order they started; the look's clip is under every reaction.
static void test_additive_and_absolute_clips_blend_by_weight() {
  Mixer m;
  m.reset(0, 0, &kLeanLoop);  // a look leaning 500
  m.play(kLeanMore);
  m.advance(200);
  TEST_ASSERT_EQUAL_INT(700, m.channels()[Channel::kLean]);
  m.play(kLeanBackNow);
  m.advance(75);  // half way in: half way from 700 to -300
  TEST_ASSERT_EQUAL_INT(200, m.channels()[Channel::kLean]);
  m.advance(75);
  TEST_ASSERT_EQUAL_INT(-300, m.channels()[Channel::kLean]);

  m.reset(0, 0, &kShutLoop);  // a look with its eyes shut
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kEyeOpenL]);
  TEST_ASSERT_EQUAL_INT(1000, m.channels()[Channel::kEyeOpenR]);
  m.play(kWider);
  m.advance(200);
  TEST_ASSERT_EQUAL_INT(300, m.channels()[Channel::kEyeOpenL]);  // over the look's, not under it
}

// A new look fades in over the old, which fades out from where it was; the
// same look again plays on; no look lets the old one go.
static void test_a_new_look_fades_over_the_old_and_the_same_plays_on() {
  Mixer m;
  m.reset(0, 0, &kLeanLoop);
  TEST_ASSERT_EQUAL_INT(500, m.channels()[Channel::kLean]);
  m.setLook(&kLeanBackLoop);
  const std::vector<int> v = record(m, Channel::kLean, 20);
  TEST_ASSERT_TRUE(steepest(v) <= 200);
  TEST_ASSERT_EQUAL_INT(-300, v.back());
  m.setLook(&kLeanBackLoop);
  m.advance(16);
  TEST_ASSERT_EQUAL_INT(-300, m.channels()[Channel::kLean]);
  m.setLook(nullptr);
  m.advance(Mixer::kWeightMs / 2);
  TEST_ASSERT_EQUAL_INT(-150, m.channels()[Channel::kLean]);
  m.advance(Mixer::kWeightMs / 2);
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kLean]);
}

// A style cross-fades over kFadeMs, eased: half way at 100 ms; one asked for
// mid-way waits for that fade to finish.
static void test_a_style_cross_fades_and_a_newer_one_waits_its_turn() {
  static_assert(kFadeMs == 200, "a style cross-fades over the rig's 200 ms fade");
  Mixer m;
  m.reset(0, 1, nullptr);
  TEST_ASSERT_EQUAL_INT(1, m.mouth().index);
  TEST_ASSERT_EQUAL_INT(1, m.mouth().next);
  m.setStyles(0, 0);
  m.advance(100);
  TEST_ASSERT_EQUAL_INT(1, m.mouth().index);
  TEST_ASSERT_EQUAL_INT(0, m.mouth().next);
  TEST_ASSERT_EQUAL_INT(500, m.mouth().mix);
  m.setStyles(0, 2);  // mid-way: it finishes this fade first
  m.advance(100);
  TEST_ASSERT_EQUAL_INT(0, m.mouth().index);
  TEST_ASSERT_EQUAL_INT(0, m.mouth().mix);
  m.advance(100);
  TEST_ASSERT_EQUAL_INT(2, m.mouth().next);
  TEST_ASSERT_EQUAL_INT(500, m.mouth().mix);
  m.advance(100);
  TEST_ASSERT_EQUAL_INT(2, m.mouth().index);
  TEST_ASSERT_EQUAL_INT(2, m.mouth().next);
  TEST_ASSERT_EQUAL_INT(0, m.eyes().index);  // the eyes never changed
  TEST_ASSERT_EQUAL_INT(0, m.eyes().mix);
}

// An impulse kicks a spring, which settles back to rest without overshoot,
// the face's quicker than the body's (kFaceRate, kBodyRate).
static void test_an_impulse_kicks_a_spring_and_it_settles() {
  Mixer m = still();
  m.impulse(Channel::kSquash, 6000);
  m.impulse(Channel::kGazeX, 6000);
  std::vector<int> squash, gaze;
  for (int i = 0; i < 100; ++i) {
    m.advance(16);
    squash.push_back(m.channels()[Channel::kSquash]);
    gaze.push_back(m.channels()[Channel::kGazeX]);
  }
  for (size_t i = 0; i < squash.size(); ++i) TEST_ASSERT_TRUE(squash[i] >= 0 && gaze[i] >= 0);
  TEST_ASSERT_TRUE(*std::max_element(squash.begin(), squash.end()) > 150);
  TEST_ASSERT_TRUE(gaze[30] < squash[30]);  // back sooner
  TEST_ASSERT_EQUAL_INT(0, squash.back());
}

// At rest a spring is exactly at rest: once within half a unit of it and
// all but still (under half a unit a second), it stops there, so a still
// face's channels never creep. A step of kSettledMs or more sets every
// spring at rest at once rather than stepping through it.
static void test_a_spring_comes_to_rest_exactly() {
  static_assert(Mixer::kSettledMs == 1000, "a step of a second or more settles the springs");
  Mixer m = still();
  m.impulse(Channel::kLean, 3000);
  m.advance(16);
  TEST_ASSERT_TRUE(m.channels()[Channel::kLean] > 0);
  m.advance(Mixer::kSettledMs);
  for (int c = 0; c < kChannelCount; ++c) TEST_ASSERT_EQUAL_INT16(kRest.v[c], m.channels().v[c]);
  Mixer stepped = still(), once = still();
  for (Mixer* x : {&stepped, &once}) x->impulse(Channel::kLift, 4000);
  for (int i = 0; i < 60; ++i) stepped.advance(16);
  once.advance(960);
  TEST_ASSERT_EQUAL_INT(kRest[Channel::kLift], stepped.channels()[Channel::kLift]);  // settled by stepping too
  TEST_ASSERT_EQUAL_MEMORY(once.channels().v, stepped.channels().v, sizeof once.channels().v);
  for (int i = 0; i < 100; ++i) stepped.advance(16);
  TEST_ASSERT_EQUAL_MEMORY(kRest.v, stepped.channels().v, sizeof kRest.v);
}

static void test_the_mixer_is_deterministic_and_bounded() {
  Mixer one, two;
  for (Mixer* m : {&one, &two}) m->reset(1, 1, &kLeanLoop);
  for (int f = 0; f < 400; ++f) {
    for (Mixer* m : {&one, &two}) {
      if (f % 50 == 10) m->setStyles(uint8_t(f % 3), uint8_t(f % 5));
      if (f % 7 == 3) m->play(f % 2 ? kLean : kLeanBackNow);  // more than kPlays at once
      if (f % 31 == 5) m->impulse(Channel::kLift, 90000);
      if (f % 120 == 60) m->setLook(f % 240 == 60 ? &kLeanBackLoop : &kShutLoop);
      m->advance(uint32_t(5 + f % 23));
    }
    TEST_ASSERT_EQUAL_MEMORY(one.channels().v, two.channels().v, sizeof one.channels().v);
    for (int c = 0; c < kChannelCount; ++c) {
      TEST_ASSERT_TRUE(one.channels().v[c] >= kChannelInfo[c].lo && one.channels().v[c] <= kChannelInfo[c].hi);
    }
  }
}

// ---- The ramp ----------------------------------------------------------------

// The fades' ramp: from rest, render::ease's smoothstep over kFadeMs (half
// way at 100 ms), from the moment it was retargeted, whenever it's read.
// Turned back half way, it turns back smoothly: no jump.
static void test_a_ramp_eases_over_200_ms_and_turns_back_smoothly() {
  Ramp r;
  TEST_ASSERT_EQUAL_INT(0, r.value(0));
  r.retarget(1000, 1000);
  for (uint32_t t = 0; t <= kFadeMs; t += 10) TEST_ASSERT_EQUAL_INT(ease1000(int(t), int(kFadeMs)), r.value(1000 + t));
  TEST_ASSERT_EQUAL_INT(500, r.value(1100));
  TEST_ASSERT_EQUAL_INT(1000, r.value(5000));
  TEST_ASSERT_EQUAL_INT(1000, r.target());
  r.retarget(0, 6000);
  r.retarget(1000, 6100);  // half way back down
  std::vector<int> back;
  for (uint32_t t = 6100; t <= 6340; t += 20) back.push_back(r.value(t));
  TEST_ASSERT_TRUE(steepest(back) <= 160);
  TEST_ASSERT_EQUAL_INT(1000, back.back());
}

// ---- The pack's rig_tables.h ------------------------------------------------------

// Every row as charactergen.py checked it: keys in order within their clip,
// loops that close and looks' clips that loop.
static void test_the_staged_rig_is_whole() {
  for (const Expression& e : kRig.expressions) {
    TEST_ASSERT_TRUE(e.eyes[0] && e.mouth[0]);
    TEST_ASSERT_EQUAL_PTR(&e, kRig.expression(e.mood));
  }
  for (const Clip& clip : kRig.clips) {
    TEST_ASSERT_EQUAL_PTR(&clip, kRig.clip(clip.id));
    for (const Track& t : clip.tracks) {
      for (int i = 1; i < t.keys.count; ++i) TEST_ASSERT_TRUE(t.keys[i].ms > t.keys[i - 1].ms);
      TEST_ASSERT_TRUE(t.keys[t.keys.count - 1].ms <= clip.ms);
      if (clip.loop) TEST_ASSERT_EQUAL_INT(sample(t, 0), sample(t, clip.ms));
    }
  }
  for (const Look& look : kRig.looks) {
    TEST_ASSERT_TRUE(!look.clip || look.clip->loop);
    TEST_ASSERT_EQUAL_PTR(&look, kRig.look(look.state));
  }
}

// Boop's rig/ files, as the table holds them.
static void test_the_staged_rig_is_the_packs_files() {
  if (!kRig.expressions.count) TEST_IGNORE_MESSAGE("the staged pack has no rig/");
  const Expression* calm = kRig.expression("calm");
  TEST_ASSERT_NOT_NULL(calm);
  TEST_ASSERT_EQUAL_STRING("calm", calm->eyes);
  TEST_ASSERT_EQUAL_STRING("calm", calm->mouth);
  TEST_ASSERT_NULL(kRig.expression("comfy"));  // not drawn yet
  const Look* idle = kRig.look(SceneState::kIdle);
  TEST_ASSERT_NOT_NULL(idle);
  TEST_ASSERT_EQUAL_STRING("breathe", idle->clip->id);
  TEST_ASSERT_EQUAL_STRING("work", kRig.look(SceneState::kWorking)->clip->id);
  TEST_ASSERT_NULL(kRig.look(SceneState::kTesting));
  const Clip* blink = kRig.clip("blink");
  TEST_ASSERT_NOT_NULL(blink);
  TEST_ASSERT_FALSE(blink->loop);
  TEST_ASSERT_TRUE(blink->additive);
  TEST_ASSERT_EQUAL_INT(180, blink->ms);
  TEST_ASSERT_EQUAL(int(Channel::kEyeOpenL), int(blink->tracks[0].channel));  // eyeOpen sets both eyes
  TEST_ASSERT_EQUAL(int(Channel::kEyeOpenR), int(blink->tracks[1].channel));
  TEST_ASSERT_FALSE(kRig.clip("doze")->additive);
  TEST_ASSERT_NULL(kRig.clip("cheer"));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_eases_run_from_0_to_1024_in_their_shapes);
  RUN_TEST(test_a_track_eases_between_its_keys_and_holds_its_ends);
  RUN_TEST(test_a_clip_loops_or_holds_its_end);
  RUN_TEST(test_a_reactions_weight_eases_in_and_out);
  RUN_TEST(test_a_short_clip_fades_over_a_quarter_of_itself);
  RUN_TEST(test_additive_and_absolute_clips_blend_by_weight);
  RUN_TEST(test_a_new_look_fades_over_the_old_and_the_same_plays_on);
  RUN_TEST(test_a_style_cross_fades_and_a_newer_one_waits_its_turn);
  RUN_TEST(test_an_impulse_kicks_a_spring_and_it_settles);
  RUN_TEST(test_a_spring_comes_to_rest_exactly);
  RUN_TEST(test_the_mixer_is_deterministic_and_bounded);
  RUN_TEST(test_a_ramp_eases_over_200_ms_and_turns_back_smoothly);
  RUN_TEST(test_the_staged_rig_is_whole);
  RUN_TEST(test_the_staged_rig_is_the_packs_files);
  return UNITY_END();
}
