// The rig core (render/rig/): clips sampled with their eases, loops and
// cues; the mixer's springs, reaction weights, blending and style
// cross-fades; the layers' fades; and the staged pack's rig_tables.h.
#include <unity.h>

#include <algorithm>
#include <cstdlib>
#include <initializer_list>
#include <utility>
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
constexpr Clip kLean = {"lean", 1000, false, true, {kLeanInTracks, 1}, {}};
constexpr Clip kLeanLoop = {"lean-loop", 1000, true, true, {kLeanInTracks, 1}, {}};
constexpr Key kLeanBack[] = {{0, -300, Ease::kLinear}, {1000, -300, Ease::kLinear}};
constexpr Track kLeanBackTracks[] = {{Channel::kLean, {kLeanBack, 2}}};
constexpr Clip kLeanBackLoop = {"lean-back", 1000, true, true, {kLeanBackTracks, 1}, {}};

constexpr Key kPlus[] = {{0, 200, Ease::kLinear}, {1000, 200, Ease::kLinear}};
constexpr Key kMinus[] = {{0, -600, Ease::kLinear}, {1000, -600, Ease::kLinear}};
constexpr Track kPlusTracks[] = {{Channel::kMouthCurve, {kPlus, 2}}};
constexpr Track kMinusTracks[] = {{Channel::kMouthCurve, {kMinus, 2}}};
constexpr Clip kSmileMore = {"smile-more", 1000, true, true, {kPlusTracks, 1}, {}};
constexpr Clip kFrownNow = {"frown-now", 1000, true, false, {kMinusTracks, 1}, {}};
constexpr Key kShut[] = {{0, 0, Ease::kLinear}, {1000, 0, Ease::kLinear}};
constexpr Key kOpen[] = {{0, 300, Ease::kLinear}, {1000, 300, Ease::kLinear}};
constexpr Track kShutTracks[] = {{Channel::kEyeOpenL, {kShut, 2}}};
constexpr Track kWiderTracks[] = {{Channel::kEyeOpenL, {kOpen, 2}}};
constexpr Clip kShutLoop = {"shut", 1000, true, false, {kShutTracks, 1}, {}};
constexpr Clip kWider = {"wider", 1000, true, true, {kWiderTracks, 1}, {}};

constexpr Key kDip[] = {
    {0, 0, Ease::kLinear}, {60, -1000, Ease::kIn}, {100, -1000, Ease::kLinear}, {180, 0, Ease::kOut}};
constexpr Track kDipTracks[] = {{Channel::kEyeOpenL, {kDip, 4}}};
constexpr Clip kBlink = {"blink", 180, false, true, {kDipTracks, 1}, {}};

constexpr Cue kTicks[] = {{0, "tick"}, {400, "tock"}};
constexpr Clip kTicking = {"ticking", 1000, true, true, {}, {kTicks, 2}};
constexpr Clip kOnce = {"once", 1000, false, true, {}, {kTicks, 2}};

// Expressions: rest, with these channels set.
Expression pose(std::initializer_list<std::pair<Channel, int>> values, uint8_t eyes = 0, uint8_t mouth = 0) {
  Expression e{"test", kRest, eyes, mouth};
  for (const auto& [c, v] : values) e.values[c] = int16_t(v);
  return e;
}

// A channel's value each frame of `frames` frames, `ms` apart.
std::vector<int> record(Mixer& m, Channel c, int frames, uint32_t ms = 16) {
  std::vector<int> out;
  for (int i = 0; i < frames; ++i) {
    m.advance(ms);
    out.push_back(m.channels()[c]);
  }
  return out;
}
// The largest change from one frame to the next, and in that change.
int steepest(const std::vector<int>& v) {
  int most = 0;
  for (size_t i = 1; i < v.size(); ++i) most = std::max(most, std::abs(v[i] - v[i - 1]));
  return most;
}
int sharpest(const std::vector<int>& v) {
  int most = 0;
  for (size_t i = 2; i < v.size(); ++i) most = std::max(most, std::abs(v[i] - 2 * v[i - 1] + v[i - 2]));
  return most;
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

// ---- The mixer ---------------------------------------------------------------

static void test_springs_settle_on_the_moods_targets_without_overshoot() {
  const Expression calm = pose({}), glad = pose({{Channel::kLean, 400}, {Channel::kMouthCurve, 800}});
  Mixer m;
  m.reset(calm, nullptr);
  TEST_ASSERT_EQUAL_INT16(0, m.channels()[Channel::kMouthCurve]);
  m.setMood(glad);
  const std::vector<int> mouth = record(m, Channel::kMouthCurve, 9);
  const int lean = m.channels()[Channel::kLean];
  // The face moves quicker than the body (kFaceRate, kBodyRate).
  TEST_ASSERT_TRUE(mouth.back() * 400 > lean * 800);
  for (int v : record(m, Channel::kMouthCurve, 120)) TEST_ASSERT_TRUE(v <= 800);  // critically damped
  for (int c = 0; c < kChannelCount; ++c) TEST_ASSERT_EQUAL_INT16(glad.values.v[c], m.channels().v[c]);
}

// A new mood mid-way moves the targets and keeps the velocity: the channel
// never jumps, and its velocity never changes by more than its spring can
// in a frame (rate² · change · dt²: 400 · 1600 · 0.016² ≈ 164).
static void test_a_retarget_mid_way_keeps_the_channel_continuous() {
  const Expression frown = pose({{Channel::kMouthCurve, -800}}), smile = pose({{Channel::kMouthCurve, 800}});
  Mixer m;
  m.reset(frown, nullptr);
  m.setMood(smile);
  std::vector<int> v = record(m, Channel::kMouthCurve, 6);
  m.setMood(frown);
  for (int x : record(m, Channel::kMouthCurve, 60)) v.push_back(x);
  TEST_ASSERT_TRUE(v[5] > -800 && v[5] < 800);  // turned back mid-way
  TEST_ASSERT_TRUE(steepest(v) <= 200);
  TEST_ASSERT_TRUE(sharpest(v) <= 170);
  TEST_ASSERT_EQUAL_INT(-800, v.back());
}

// A reaction's weight eases in over kFadeMs as it starts and out as it
// ends: half way at 75 ms, whole at 150.
static void test_a_reactions_weight_eases_in_and_out() {
  Mixer m;
  m.reset(pose({}), nullptr);
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
  Mixer m;
  m.reset(pose({}), nullptr);
  m.play(kBlink);
  m.advance(60);
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kEyeOpenL]);  // whole by 45 ms
  m.advance(40);
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kEyeOpenL]);
  m.advance(80);
  TEST_ASSERT_EQUAL_INT(1000, m.channels()[Channel::kEyeOpenL]);
  // A clip of four fades or more fades over kFadeMs: half way at 75 ms.
  m.play(kLean);
  m.advance(75);
  TEST_ASSERT_EQUAL_INT(250, m.channels()[Channel::kLean]);
}

static void test_a_cut_reaction_eases_out_from_where_it_was() {
  Mixer m;
  m.reset(pose({}), nullptr);
  m.play(kLeanLoop);
  m.advance(300);
  TEST_ASSERT_EQUAL_INT(500, m.channels()[Channel::kLean]);
  m.cut();
  m.advance(75);
  TEST_ASSERT_EQUAL_INT(250, m.channels()[Channel::kLean]);
  m.advance(75);
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kLean]);
  // Cut while it eases in, it eases out from there: no jump up first.
  m.play(kLeanLoop);
  m.advance(50);
  const int at = m.channels()[Channel::kLean];
  m.cut();
  m.advance(16);
  TEST_ASSERT_TRUE(m.channels()[Channel::kLean] <= at);
}

// Additive clips add, absolute ones blend toward their values by weight, in
// the order they started; the look's clip is under every reaction.
static void test_additive_and_absolute_clips_blend_by_weight() {
  Mixer m;
  m.reset(pose({{Channel::kMouthCurve, 400}}), nullptr);
  m.play(kSmileMore);
  m.advance(200);
  TEST_ASSERT_EQUAL_INT(600, m.channels()[Channel::kMouthCurve]);
  m.play(kFrownNow);
  m.advance(75);  // half way in: half way from 600 to -600
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kMouthCurve]);
  m.advance(75);
  TEST_ASSERT_EQUAL_INT(-600, m.channels()[Channel::kMouthCurve]);

  m.reset(pose({}), &kShutLoop);  // a look with its eyes shut
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kEyeOpenL]);
  TEST_ASSERT_EQUAL_INT(1000, m.channels()[Channel::kEyeOpenR]);
  m.play(kWider);
  m.advance(200);
  TEST_ASSERT_EQUAL_INT(300, m.channels()[Channel::kEyeOpenL]);  // over the look's, not under it
}

static void test_a_new_look_fades_over_the_old_and_the_same_plays_on() {
  Mixer m;
  m.reset(pose({}), &kLeanLoop);
  TEST_ASSERT_EQUAL_INT(500, m.channels()[Channel::kLean]);
  m.setLook(&kLeanBackLoop);
  const std::vector<int> v = record(m, Channel::kLean, 20);
  TEST_ASSERT_TRUE(steepest(v) <= 200);
  TEST_ASSERT_EQUAL_INT(-300, v.back());
  // The same look again doesn't start it over.
  m.reset(pose({}), &kTicking);
  m.advance(300);
  m.setLook(&kTicking);
  m.advance(200);  // 300 to 500: past its tock at 400, not its tick at 0
  TEST_ASSERT_EQUAL_INT(1, m.cueCount());
  TEST_ASSERT_EQUAL_STRING("tock", m.cue(0));
  // No look: the old one fades out.
  m.reset(pose({}), &kLeanLoop);
  m.setLook(nullptr);
  m.advance(Mixer::kFadeMs / 2);
  TEST_ASSERT_EQUAL_INT(250, m.channels()[Channel::kLean]);
  m.advance(Mixer::kFadeMs / 2);
  TEST_ASSERT_EQUAL_INT(0, m.channels()[Channel::kLean]);
}

static void test_the_mixer_reports_the_cues_its_clips_cross() {
  Mixer m;
  m.reset(pose({}), nullptr);
  m.play(kOnce);
  m.advance(16);
  TEST_ASSERT_EQUAL_INT(1, m.cueCount());
  TEST_ASSERT_EQUAL_STRING("tick", m.cue(0));
  m.advance(16);
  TEST_ASSERT_EQUAL_INT(0, m.cueCount());
  m.cut();  // a cut clip makes no more sounds
  m.advance(400);
  TEST_ASSERT_EQUAL_INT(0, m.cueCount());
}

static void test_a_style_cross_fades_and_a_newer_one_waits_its_turn() {
  Mixer m;
  m.reset(pose({}, 0, 1), nullptr);
  TEST_ASSERT_EQUAL_INT(1, m.mouth().index);
  TEST_ASSERT_EQUAL_INT(1, m.mouth().next);
  m.setMood(pose({}, 0, 0));
  m.advance(100);
  TEST_ASSERT_EQUAL_INT(1, m.mouth().index);
  TEST_ASSERT_EQUAL_INT(0, m.mouth().next);
  TEST_ASSERT_EQUAL_INT(500, m.mouth().mix);
  m.setMood(pose({}, 0, 2));  // mid-way: it finishes this fade first
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

static void test_an_impulse_kicks_a_spring_and_it_settles() {
  Mixer m;
  m.reset(pose({}), nullptr);
  m.impulse(Channel::kSquash, 6000);
  const std::vector<int> v = record(m, Channel::kSquash, 100);
  int most = 0;
  for (int x : v) {
    TEST_ASSERT_TRUE(x >= 0);
    most = std::max(most, x);
  }
  TEST_ASSERT_TRUE(most > 150);
  TEST_ASSERT_EQUAL_INT(0, v.back());
}

static void test_the_mixer_is_deterministic_and_bounded() {
  const Expression a = pose({{Channel::kSquash, 300}, {Channel::kEyeCurve, 900}}, 1, 1),
                   b = pose({{Channel::kGazeX, -700}});
  Mixer one, two;
  for (Mixer* m : {&one, &two}) m->reset(a, &kLeanLoop);
  for (int f = 0; f < 400; ++f) {
    for (Mixer* m : {&one, &two}) {
      if (f % 50 == 10) m->setMood(f % 100 == 10 ? b : a);
      if (f % 7 == 3) m->play(f % 2 ? kLean : kFrownNow);  // more than kPlays at once
      if (f % 31 == 5) m->impulse(Channel::kLift, 90000);
      if (f % 61 == 9) m->cut();
      if (f % 120 == 60) m->setLook(f % 240 == 60 ? &kLeanBackLoop : &kShutLoop);
      m->advance(uint32_t(5 + f % 23));
    }
    TEST_ASSERT_EQUAL_MEMORY(one.channels().v, two.channels().v, sizeof one.channels().v);
    for (int c = 0; c < kChannelCount; ++c) {
      TEST_ASSERT_TRUE(one.channels().v[c] >= kChannelInfo[c].lo && one.channels().v[c] <= kChannelInfo[c].hi);
    }
  }
}

// ---- Layers ------------------------------------------------------------------

static void test_a_layer_fades_in_and_out_over_200_ms() {
  Layers l;
  TEST_ASSERT_EQUAL_INT(0, l.opacity(Layer::kLane));
  l.show(Layer::kLane, 1);
  std::vector<int> v;
  for (int t = 0; t < 10; ++t) l.advance(20), v.push_back(l.opacity(Layer::kLane));
  TEST_ASSERT_EQUAL_INT(500, v[4]);  // a smoothstep from rest: half way at 100 ms
  TEST_ASSERT_EQUAL_INT(1000, v[9]);
  for (size_t i = 1; i < v.size(); ++i) TEST_ASSERT_TRUE(v[i] >= v[i - 1]);
  // Turned off half way back up, it turns back smoothly: no jump.
  l.show(Layer::kLane, 0);
  l.advance(100);
  l.show(Layer::kLane, 1);
  std::vector<int> back;
  for (int t = 0; t < 12; ++t) l.advance(20), back.push_back(l.opacity(Layer::kLane));
  TEST_ASSERT_TRUE(steepest(back) <= 160);
  TEST_ASSERT_EQUAL_INT(1000, back.back());
}

static void test_a_new_content_waits_for_the_old_to_fade_out() {
  Layers l;
  l.show(Layer::kScene, 1);
  l.finish();
  TEST_ASSERT_EQUAL_INT(1000, l.opacity(Layer::kScene));
  l.show(Layer::kScene, 2);
  l.advance(100);
  TEST_ASSERT_EQUAL_INT(1, l.content(Layer::kScene));  // the desk fading out
  TEST_ASSERT_EQUAL_INT(500, l.opacity(Layer::kScene));
  l.advance(100);
  TEST_ASSERT_EQUAL_INT(2, l.content(Layer::kScene));  // then the next fading in
  TEST_ASSERT_EQUAL_INT(0, l.opacity(Layer::kScene));
  l.advance(200);
  TEST_ASSERT_EQUAL_INT(1000, l.opacity(Layer::kScene));
}

// What the tags call for is render::outfitFor's and render::airFor's.
static void test_a_look_that_dresses_wears_the_tags_outfit() {
  const uint32_t night = tagBit("night") | tagBit("winter");
  Layers l;
  l.dress(night, true);
  l.finish();
  TEST_ASSERT_EQUAL_INT(int(Outfit::kNightcap), l.content(Layer::kAccessories));
  TEST_ASSERT_EQUAL_INT(kSnow, l.content(Layer::kAir));
  l.dress(night, false);  // a look that doesn't dress: no hat, still snow
  l.advance(kLayerFadeMs);
  TEST_ASSERT_EQUAL_INT(0, l.opacity(Layer::kAccessories));
  TEST_ASSERT_EQUAL_INT(1000, l.opacity(Layer::kAir));
}

// ---- The pack's rig_tables.h ------------------------------------------------------

// Every row as charactergen.py checked it: values in range, styles named,
// keys in order within their clip, loops that close, cues before the end
// and looks' clips that loop.
static void test_the_staged_rig_is_whole() {
  for (const Expression& e : kRig.expressions) {
    TEST_ASSERT_TRUE(e.eyes < kRig.eyeStyles.count && e.mouth < kRig.mouthStyles.count);
    for (int c = 0; c < kChannelCount; ++c)
      TEST_ASSERT_TRUE(e.values.v[c] >= kChannelInfo[c].lo && e.values.v[c] <= kChannelInfo[c].hi);
    TEST_ASSERT_EQUAL_PTR(&e, kRig.expression(e.mood));
  }
  for (const Clip& clip : kRig.clips) {
    TEST_ASSERT_EQUAL_PTR(&clip, kRig.clip(clip.id));
    for (const Track& t : clip.tracks) {
      for (int i = 1; i < t.keys.count; ++i) TEST_ASSERT_TRUE(t.keys[i].ms > t.keys[i - 1].ms);
      TEST_ASSERT_TRUE(t.keys[t.keys.count - 1].ms <= clip.ms);
      if (clip.loop) TEST_ASSERT_EQUAL_INT(sample(t, 0), sample(t, clip.ms));
    }
    for (const Cue& cue : clip.cues) TEST_ASSERT_TRUE(cue.ms < clip.ms);
  }
  for (const Look& look : kRig.looks) {
    TEST_ASSERT_TRUE(!look.clip || look.clip->loop);
    TEST_ASSERT_TRUE(look.scene <= kRig.scenes.count);
    TEST_ASSERT_EQUAL_PTR(&look, kRig.look(look.state));
  }
}

// Boop's rig/ files, as the table holds them.
static void test_the_staged_rig_is_the_packs_files() {
  if (!kRig.expressions.count) TEST_IGNORE_MESSAGE("the staged pack has no rig/");
  const Expression* happy = kRig.expression("happy");
  const Expression* sad = kRig.expression("sad");
  TEST_ASSERT_NOT_NULL(happy);
  TEST_ASSERT_NOT_NULL(sad);
  TEST_ASSERT_EQUAL_INT16(800, happy->values[Channel::kMouthCurve]);
  TEST_ASSERT_EQUAL_INT16(-700, sad->values[Channel::kEyeCurve]);
  TEST_ASSERT_EQUAL_INT16(1000, sad->values[Channel::kEyeSize]);  // at rest: its file doesn't say
  TEST_ASSERT_EQUAL_STRING("calm", kRig.mouthStyles[kRig.expression("calm")->mouth]);
  TEST_ASSERT_NULL(kRig.expression("comfy"));  // not drawn yet
  const Look* idle = kRig.look(SceneState::kIdle);
  TEST_ASSERT_NOT_NULL(idle);
  TEST_ASSERT_EQUAL_STRING("breathe", idle->clip->id);
  TEST_ASSERT_TRUE(idle->dresses);
  const Look* working = kRig.look(SceneState::kWorking);
  TEST_ASSERT_EQUAL_STRING("desk", kRig.scenes[working->scene - 1]);
  TEST_ASSERT_NULL(kRig.look(SceneState::kTesting));
  const Clip* cheer = kRig.clip("cheer");
  TEST_ASSERT_NOT_NULL(cheer);
  TEST_ASSERT_FALSE(cheer->loop);
  TEST_ASSERT_TRUE(cheer->additive);
  TEST_ASSERT_EQUAL_INT(1400, cheer->ms);
  TEST_ASSERT_EQUAL_STRING("pop", cheer->cues[0].name);
  TEST_ASSERT_EQUAL_INT(300, cheer->cues[0].ms);
  TEST_ASSERT_FALSE(kRig.clip("doze")->additive);
  TEST_ASSERT_EQUAL(int(Anchor::kBrim), int(kRig.accessory(Outfit::kNightcap)->anchor));
  TEST_ASSERT_NULL(kRig.accessory(Outfit::kNone));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_eases_run_from_0_to_1024_in_their_shapes);
  RUN_TEST(test_a_track_eases_between_its_keys_and_holds_its_ends);
  RUN_TEST(test_a_clip_loops_or_holds_its_end);
  RUN_TEST(test_cues_crossed_on_every_loop);
  RUN_TEST(test_springs_settle_on_the_moods_targets_without_overshoot);
  RUN_TEST(test_a_retarget_mid_way_keeps_the_channel_continuous);
  RUN_TEST(test_a_reactions_weight_eases_in_and_out);
  RUN_TEST(test_a_short_clip_fades_over_a_quarter_of_itself);
  RUN_TEST(test_a_cut_reaction_eases_out_from_where_it_was);
  RUN_TEST(test_additive_and_absolute_clips_blend_by_weight);
  RUN_TEST(test_a_new_look_fades_over_the_old_and_the_same_plays_on);
  RUN_TEST(test_the_mixer_reports_the_cues_its_clips_cross);
  RUN_TEST(test_a_style_cross_fades_and_a_newer_one_waits_its_turn);
  RUN_TEST(test_an_impulse_kicks_a_spring_and_it_settles);
  RUN_TEST(test_the_mixer_is_deterministic_and_bounded);
  RUN_TEST(test_a_layer_fades_in_and_out_over_200_ms);
  RUN_TEST(test_a_new_content_waits_for_the_old_to_fade_out);
  RUN_TEST(test_a_look_that_dresses_wears_the_tags_outfit);
  RUN_TEST(test_the_staged_rig_is_whole);
  RUN_TEST(test_the_staged_rig_is_the_packs_files);
  return UNITY_END();
}
