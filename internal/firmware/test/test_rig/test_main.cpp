// The rig core (render/rig/): clips sampled with their eases, loops and
// cues; the mixer's springs, reaction weights, blending and style
// cross-fades; the ramp the fades ease on; and the staged pack's rig_tables.h.
#include <unity.h>

#include <algorithm>
#include <cstdlib>
#include <initializer_list>
#include <vector>

#include "render/maths.h"
#include "render/rig/layers.h"
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

constexpr Cue kTicks[] = {{0, "tick"}, {400, "tock"}};
constexpr Clip kTicking = {"ticking", 1000, true, true, {}, {kTicks, 2}};
constexpr Clip kOnce = {"once", 1000, false, true, {}, {kTicks, 2}};

// The ramp as another clip's move: a sway at its own size and pace, then
// at half its size over half its time, and at twice its size over twice.
constexpr Track kSwayTracks[] = {kRampTrack};
constexpr Clip kSway = {"sway", 200, false, true, {kSwayTracks, 1}, {kTicks, 1}};
constexpr Clip kSwaySmall = {"sway-small", 100, false, true, {kSwayTracks, 1}, {kTicks, 1}, 500, 200};
constexpr Clip kSwayBig = {"sway-big", 400, false, true, {kSwayTracks, 1}, {kTicks, 1}, 2000, 200};
constexpr Cue kHalfway[] = {{100, "top"}};
constexpr Clip kSwayTicking = {"sway-ticking", 1000, true, true, {kSwayTracks, 1}, {kHalfway, 1}, 1000, 200};

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

// A clip may be another's move at a size and a pace (a clip file's `of`):
// its values are that one's times size / 1000, its time runs over its own
// ms, and its cues come at their place in it. Its own, 1000 and its ms.
static void test_a_clip_plays_another_at_a_size_and_a_pace() {
  for (uint32_t t : {0u, 50u, 100u, 150u, 200u}) TEST_ASSERT_EQUAL_INT(sample(kRampTrack, t), kSway.value(kRampTrack, t));
  TEST_ASSERT_EQUAL_INT(500, kSwaySmall.value(kRampTrack, 50));  // the ramp's top, half as high, half as soon
  TEST_ASSERT_EQUAL_INT(250, kSwaySmall.value(kRampTrack, 25));
  TEST_ASSERT_EQUAL_INT(0, kSwaySmall.value(kRampTrack, 100));
  TEST_ASSERT_EQUAL_INT(2000, kSwayBig.value(kRampTrack, 200));
  TEST_ASSERT_EQUAL_INT(1000, kSwayBig.value(kRampTrack, 100));
  TEST_ASSERT_EQUAL_UINT32(100, kSwaySmall.local(900));  // held at its own end
  TEST_ASSERT_EQUAL_UINT32(100, kSwayBig.keyed(200));
  TEST_ASSERT_EQUAL_UINT32(200, kSwayBig.played(100));
  TEST_ASSERT_EQUAL_UINT32(4, kSwaySmall.played(7));  // 3.5: the first ms at or after
  // A cue at the end of a quicker move comes before its end, so it sounds.
  static constexpr Cue kLast[] = {{199, "last"}};
  static constexpr Clip kSwayEnding = {"sway-ending", 100, false, true, {kSwayTracks, 1}, {kLast, 1}, 500, 200};
  TEST_ASSERT_EQUAL_UINT32(99, kSwayEnding.played(199));
  const char* last[1];
  TEST_ASSERT_EQUAL_INT(1, crossed(kSwayEnding, 0, 100, last, 1));
  const char* out[4];
  TEST_ASSERT_EQUAL_INT(0, crossed(kSwayTicking, 0, 500, out, 4));  // its cue at 100 of 200 comes at 500 of 1000
  TEST_ASSERT_EQUAL_INT(1, crossed(kSwayTicking, 500, 501, out, 4));
  TEST_ASSERT_EQUAL_STRING("top", out[0]);
  TEST_ASSERT_EQUAL_INT(2, crossed(kSwayTicking, 400, 1600, out, 4));
  // On the mixer, at its size and pace: half the ramp's top, ten times
  // later.
  constexpr Clip kSwaySlow = {"sway-slow", 2000, false, true, {kSwayTracks, 1}, {}, 500, 200};
  Mixer m = still();
  m.play(kSwaySlow);
  m.advance(500);
  TEST_ASSERT_EQUAL_INT(250, m.channels()[Channel::kLean]);
  m.advance(500);
  TEST_ASSERT_EQUAL_INT(500, m.channels()[Channel::kLean]);
}

// ---- The mixer ---------------------------------------------------------------

// A reaction's weight eases in over kWeightMs as it starts and out as it
// ends: half way at 75 ms, whole at 150.
static void test_cues_crossed_on_every_loop() {
  const char* out[8];
  TEST_ASSERT_EQUAL_INT(1, crossed(kTicking, 0, 1, out, 8));
  TEST_ASSERT_EQUAL_STRING("tick", out[0]);
  TEST_ASSERT_EQUAL_INT(0, crossed(kTicking, 1, 400, out, 8));  // [from, to): 400 is the next one's
  TEST_ASSERT_EQUAL_INT(1, crossed(kTicking, 1, 401, out, 8));
  TEST_ASSERT_EQUAL_STRING("tock", out[0]);
  TEST_ASSERT_EQUAL_INT(0, crossed(kTicking, 400, 400, out, 8));
  // Across loops, in order: 1000, 1400, 2000.
  TEST_ASSERT_EQUAL_INT(3, crossed(kTicking, 900, 2100, out, 8));
  TEST_ASSERT_EQUAL_STRING("tick", out[0]);
  TEST_ASSERT_EQUAL_STRING("tock", out[1]);
  TEST_ASSERT_EQUAL_STRING("tick", out[2]);
  TEST_ASSERT_EQUAL_INT(2, crossed(kTicking, 900, 2100, out, 2));  // at most max
  // A clip that doesn't loop crosses its cues once.
  TEST_ASSERT_EQUAL_INT(2, crossed(kOnce, 0, 5000, out, 8));
  TEST_ASSERT_EQUAL_INT(0, crossed(kOnce, 900, 2100, out, 8));
}

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

// A reaction's clip stopped fades out over its weight's fade from where its
// weight is, as a look's old clip does; the look's own plays on, and a clip
// not playing stops nothing.
static void test_a_stopped_clip_fades_out() {
  Mixer m;
  m.reset(0, 0, &kLeanMore);
  m.play(kLean);
  m.advance(400);
  TEST_ASSERT_EQUAL_INT(700, m.channels()[Channel::kLean]);
  m.stop(kBlink);
  m.stop(kLeanMore);  // a look's clip stops only by setLook
  m.advance(0);
  TEST_ASSERT_EQUAL_INT(700, m.channels()[Channel::kLean]);
  m.stop(kLean);
  m.advance(75);
  TEST_ASSERT_EQUAL_INT(450, m.channels()[Channel::kLean]);
  m.advance(75);
  TEST_ASSERT_EQUAL_INT(200, m.channels()[Channel::kLean]);
  m.play(kLean);  // played again: a new play, fading in
  m.advance(150);
  TEST_ASSERT_EQUAL_INT(700, m.channels()[Channel::kLean]);
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

// A look that moves the whole body asks for a longer fade: both clips take
// it, the old out and the new in, half way at half of it; and a look names
// a base clip for an activity by its state, none for one it doesn't name.
static void test_a_look_fades_as_long_as_asked_and_names_its_activities() {
  Mixer m;
  m.reset(0, 0, &kLeanLoop);
  m.setLook(&kLeanBackLoop, 240);  // of these clips' 250 at most, a quarter of their second
  m.advance(120);
  TEST_ASSERT_INT_WITHIN(2, 100, m.channels()[Channel::kLean]);  // half of each: 250 - 150
  m.advance(Mixer::kWeightMs - 120);
  TEST_ASSERT_TRUE(m.channels()[Channel::kLean] > -300);  // where kWeightMs would have it
  const std::vector<int> v = record(m, Channel::kLean, 20);
  TEST_ASSERT_EQUAL_INT(-300, v.back());
  static constexpr ActClip kActs[] = {{&kLeanBackLoop, SceneState::kWaiting}};
  static constexpr Look kLook = {SceneState::kWorking, &kLeanLoop, {}, {kActs, 1}};
  TEST_ASSERT_EQUAL_PTR(&kLeanBackLoop, kLook.acted(SceneState::kWaiting));
  TEST_ASSERT_NULL(kLook.acted(SceneState::kTerminal));
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

// The glass and the hands are channels like the others: at rest the body
// is back from the glass with no patch and both hands are hidden in it
// (size 0), each hand's five channels in HandPart's order; a clip moves
// them, a palm pressed on the glass and held, and the mixer keeps each in
// its range however far a clip and an impulse carry it.
static void test_the_glass_and_the_hands_are_channels() {
  for (Channel c : {Channel::kGlass, Channel::kPatch, Channel::kHandLSize, Channel::kHandRSize, Channel::kHandLGlass,
                    Channel::kHandRGlass, Channel::kHandLShape, Channel::kHandRShape})
    TEST_ASSERT_EQUAL_INT(0, kRest[c]);
  TEST_ASSERT_EQUAL_INT(int(Channel::kHandLX), int(hand(0, HandPart::kX)));
  TEST_ASSERT_EQUAL_INT(int(Channel::kHandRY), int(hand(1, HandPart::kY)));
  TEST_ASSERT_EQUAL_INT(int(Channel::kTurn), int(hand(1, HandPart::kGlass)) + 1);  // the right hand's glass, then the turn
  TEST_ASSERT_EQUAL_STRING("handRShape", kChannelInfo[int(Channel::kHandRShape)].name);
  TEST_ASSERT_EQUAL_INT(-1000, kChannelInfo[int(Channel::kHandRShape)].lo);  // a fist
  TEST_ASSERT_EQUAL_INT(1000, kChannelInfo[int(Channel::kHandRShape)].hi);   // an open palm

  static constexpr Key kUp[] = {{0, 0, Ease::kLinear}, {100, 1000, Ease::kOut}};
  static constexpr Key kOut[] = {{0, 0, Ease::kLinear}, {100, 70, Ease::kOut}};
  static constexpr Key kFar[] = {{0, 0, Ease::kLinear}, {100, 3000, Ease::kOut}};
  static constexpr Track kPalmTracks[] = {{Channel::kHandRSize, {kUp, 2}},  {Channel::kHandRShape, {kUp, 2}},
                                          {Channel::kHandRGlass, {kUp, 2}}, {Channel::kHandRX, {kOut, 2}},
                                          {Channel::kGlass, {kUp, 2}},      {Channel::kHandLSize, {kFar, 2}}};
  static constexpr Clip kPalm = {"palm", 400, true, true, {kPalmTracks, 6}};
  Mixer m;
  m.reset(0, 0, nullptr);
  m.play(kPalm);
  m.advance(200);
  TEST_ASSERT_EQUAL_INT(1000, m.channels()[Channel::kHandRSize]);
  TEST_ASSERT_EQUAL_INT(1000, m.channels()[Channel::kHandRShape]);
  TEST_ASSERT_EQUAL_INT(1000, m.channels()[Channel::kHandRGlass]);
  TEST_ASSERT_EQUAL_INT(70, m.channels()[Channel::kHandRX]);
  TEST_ASSERT_EQUAL_INT(1000, m.channels()[Channel::kGlass]);
  TEST_ASSERT_EQUAL_INT(2000, m.channels()[Channel::kHandLSize]);  // held at its range's end
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kHandLX]);         // the other hand stays where it was
  m.impulse(Channel::kHandRGlass, 90000);
  m.advance(16);
  TEST_ASSERT_EQUAL_INT(1000, m.channels()[Channel::kHandRGlass]);
  m.stop(kPalm);
  m.advance(Mixer::kSettledMs);
  for (int c = 0; c < kChannelCount; ++c) TEST_ASSERT_EQUAL_INT(kRest.v[c], m.channels().v[c]);
}

// The turn is a channel like the others: at rest the body faces you (0);
// it reaches two whole turns either way, in thousandths of a turn, so a
// clip can spin all the way round (1000) and on, and the mixer holds it
// in that range however far a clip and an impulse carry it.
static void test_the_turn_is_a_channel() {
  TEST_ASSERT_EQUAL_INT(kChannelCount, int(Channel::kTurn) + 1);  // the last
  TEST_ASSERT_EQUAL_STRING("turn", kChannelInfo[int(Channel::kTurn)].name);
  TEST_ASSERT_EQUAL_INT(0, kRest[Channel::kTurn]);
  TEST_ASSERT_EQUAL_INT(-2000, kChannelInfo[int(Channel::kTurn)].lo);
  TEST_ASSERT_EQUAL_INT(2000, kChannelInfo[int(Channel::kTurn)].hi);
  TEST_ASSERT_FALSE(body(Channel::kTurn));
  static constexpr Key kRound[] = {{0, 0, Ease::kLinear}, {400, 1000, Ease::kOut}};
  static constexpr Key kFar[] = {{0, 0, Ease::kLinear}, {100, 3000, Ease::kOut}};
  static constexpr Track kSpinTracks[] = {{Channel::kTurn, {kRound, 2}}};
  static constexpr Track kFarTracks[] = {{Channel::kTurn, {kFar, 2}}};
  static constexpr Clip kSpin = {"spin", 800, true, true, {kSpinTracks, 1}};
  static constexpr Clip kTooFar = {"far", 200, true, true, {kFarTracks, 1}};
  Mixer m;
  m.reset(0, 0, nullptr);
  m.play(kSpin);
  m.advance(200);
  const int half = m.channels()[Channel::kTurn];
  TEST_ASSERT_TRUE(half > 500 && half < 1000);
  m.advance(300);
  TEST_ASSERT_EQUAL_INT(1000, m.channels()[Channel::kTurn]);  // all the way round
  m.stop(kSpin);
  m.play(kTooFar);
  m.advance(150);
  TEST_ASSERT_TRUE(m.channels()[Channel::kTurn] <= 2000);
  m.impulse(Channel::kTurn, -900000);
  m.advance(16);
  TEST_ASSERT_TRUE(m.channels()[Channel::kTurn] >= -2000 && m.channels()[Channel::kTurn] <= 2000);
  m.stop(kTooFar);
  m.advance(Mixer::kSettledMs);
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kTurn]);
}

// With kPlays playing, the oldest gives way but the look's own clip: a
// burst of reactions never stops the look, and the newest of them plays.
static void test_a_full_mixer_keeps_its_look() {
  Mixer m;
  m.reset(0, 0, &kLeanLoop);
  for (int i = 0; i < Mixer::kPlays * 2; ++i) {
    m.play(kWider);
    m.advance(10);
  }
  m.play(kShutLoop);
  m.advance(Mixer::kWeightMs);
  TEST_ASSERT_EQUAL_INT(500, m.channels()[Channel::kLean]);    // the look's, whole
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kEyeOpenL]);  // the newest, absolute, shuts it
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

// ---- The layer stack ----------------------------------------------------------

// A layer fades in over the rig's fade from when it's shown, on the ramp;
// a new content waits for the old to fade out, then fades in from the
// instant that ended, however often it's read; asked back mid-way, the
// old turns back up; and each layer is its own.
static void test_a_layer_fades_and_a_new_content_waits_its_turn() {
  Layers l;
  TEST_ASSERT_EQUAL_UINT32(0, l.content(Layer::kHat, 0));
  TEST_ASSERT_EQUAL_INT(0, l.opacity(Layer::kHat, 0));
  l.show(Layer::kHat, 3, 1000);
  TEST_ASSERT_EQUAL_UINT32(3, l.content(Layer::kHat, 1000));
  TEST_ASSERT_EQUAL_INT(500, l.opacity(Layer::kHat, 1100));
  TEST_ASSERT_EQUAL_INT(1000, l.opacity(Layer::kHat, 1200));
  TEST_ASSERT_EQUAL_INT(0, l.opacity(Layer::kAir, 1200));  // its own
  l.show(Layer::kHat, 3, 1300);                            // the same: no change
  TEST_ASSERT_EQUAL_INT(1000, l.opacity(Layer::kHat, 1300));
  l.show(Layer::kHat, 4, 2000);  // the old fades out first, then the new comes in
  for (uint32_t t = 2000; t < 2000 + kFadeMs; t += 10) {
    TEST_ASSERT_EQUAL_UINT32(3, l.content(Layer::kHat, t));
    TEST_ASSERT_EQUAL_INT(1000 - ease1000(int(t - 2000), int(kFadeMs)), l.opacity(Layer::kHat, t));
  }
  for (uint32_t t = 2200; t <= 2400 + 50; t += 10) {
    TEST_ASSERT_EQUAL_UINT32(4, l.content(Layer::kHat, t));
    TEST_ASSERT_EQUAL_INT(ease1000(int(t - 2200), int(kFadeMs)), l.opacity(Layer::kHat, t));
  }
  l.show(Layer::kHat, 5, 3000);
  l.show(Layer::kHat, 4, 3100);  // back mid-way: turns back up, no jump
  TEST_ASSERT_EQUAL_UINT32(4, l.content(Layer::kHat, 3100));
  TEST_ASSERT_EQUAL_INT(500, l.opacity(Layer::kHat, 3100));
  TEST_ASSERT_EQUAL_INT(1000, l.opacity(Layer::kHat, 3300));
  // Read once, after the fade out and in, it's as if read every frame.
  Layers once;
  once.show(Layer::kAir, 1, 0);
  once.show(Layer::kAir, 2, 500);
  TEST_ASSERT_EQUAL_UINT32(2, once.content(Layer::kAir, 800));
  TEST_ASSERT_EQUAL_INT(ease1000(100, int(kFadeMs)), once.opacity(Layer::kAir, 800));
  // Nothing again: it fades out, its content kept until it's gone.
  once.show(Layer::kAir, 0, 2000);
  TEST_ASSERT_EQUAL_UINT32(2, once.content(Layer::kAir, 2100));
  TEST_ASSERT_EQUAL_INT(500, once.opacity(Layer::kAir, 2100));
  TEST_ASSERT_EQUAL_UINT32(0, once.content(Layer::kAir, 2200));
  TEST_ASSERT_EQUAL_INT(0, once.opacity(Layer::kAir, 2200));
}

// ---- The pack's rig_tables.h ------------------------------------------------------

// Every row as charactergen.py checked it: keys in order within their clip,
// loops that close and looks' clips that loop.
static void test_the_staged_rig_is_whole() {
  for (const Clip& clip : kRig.clips) {
    TEST_ASSERT_EQUAL_PTR(&clip, kRig.clip(clip.id));
    for (const Track& t : clip.tracks) {
      for (int i = 1; i < t.keys.count; ++i) TEST_ASSERT_TRUE(t.keys[i].ms > t.keys[i - 1].ms);
      TEST_ASSERT_TRUE(t.keys[t.keys.count - 1].ms <= (clip.own ? clip.own : clip.ms));
      if (clip.loop) TEST_ASSERT_EQUAL_INT(clip.value(t, 0), clip.value(t, clip.ms));
    }
  }
  for (const Look& look : kRig.looks) {
    TEST_ASSERT_TRUE(!look.clip || look.clip->loop);
    TEST_ASSERT_EQUAL_PTR(&look, kRig.look(look.state));
  }
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_eases_run_from_0_to_1024_in_their_shapes);
  RUN_TEST(test_a_track_eases_between_its_keys_and_holds_its_ends);
  RUN_TEST(test_a_clip_loops_or_holds_its_end);
  RUN_TEST(test_cues_crossed_on_every_loop);
  RUN_TEST(test_a_clip_plays_another_at_a_size_and_a_pace);
  RUN_TEST(test_a_reactions_weight_eases_in_and_out);
  RUN_TEST(test_a_stopped_clip_fades_out);
  RUN_TEST(test_a_short_clip_fades_over_a_quarter_of_itself);
  RUN_TEST(test_additive_and_absolute_clips_blend_by_weight);
  RUN_TEST(test_a_new_look_fades_over_the_old_and_the_same_plays_on);
  RUN_TEST(test_a_look_fades_as_long_as_asked_and_names_its_activities);
  RUN_TEST(test_a_style_cross_fades_and_a_newer_one_waits_its_turn);
  RUN_TEST(test_an_impulse_kicks_a_spring_and_it_settles);
  RUN_TEST(test_a_spring_comes_to_rest_exactly);
  RUN_TEST(test_the_mixer_is_deterministic_and_bounded);
  RUN_TEST(test_a_full_mixer_keeps_its_look);
  RUN_TEST(test_the_glass_and_the_hands_are_channels);
  RUN_TEST(test_the_turn_is_a_channel);
  RUN_TEST(test_a_ramp_eases_over_200_ms_and_turns_back_smoothly);
  RUN_TEST(test_a_layer_fades_and_a_new_content_waits_its_turn);
  RUN_TEST(test_the_staged_rig_is_whole);
  return UNITY_END();
}
