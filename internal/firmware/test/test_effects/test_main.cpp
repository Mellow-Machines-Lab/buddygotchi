// The sound effects' mixer (voice/effects.h) and the sound queue's rule
// (app::Sound), with the stub face's clips: the mixer never knows which
// face's bank it plays.
#include <unity.h>

#include <cstdlib>
#include <vector>

#include "app/sound.h"
#include "stub_face.h"  // internal/firmware/
#include "voice/effects.h"
#include "voice/player.h"

void setUp() {}
void tearDown() {}

namespace {

int peak(const std::vector<uint8_t>& v) {
  int m = 0;
  for (uint8_t s : v) m = std::abs(int(s) - 128) > m ? std::abs(int(s) - 128) : m;
  return m;
}

// The mixer's output for one effect, alone, from silence.
std::vector<uint8_t> mixed(voice::Effect e, bool duck = false, size_t n = 22050) {
  voice::Effects fx;
  fx.play(e);
  std::vector<uint8_t> out(n, 128);
  fx.mix(out.data(), out.size(), duck);
  return out;
}

size_t lastSounding(const std::vector<uint8_t>& v) {
  size_t last = 0;
  for (size_t i = 0; i < v.size(); ++i)
    if (v[i] != 128) last = i;
  return last;
}

voice::Effect effect(const char* name, uint8_t gain = 255, uint16_t pitch = 1000, uint8_t vol = 6) {
  voice::Effect e;
  e.clip = testface::clips().index(name);
  const voice::EffectClip clip = testface::clips().at(e.clip);
  e.samples = clip.samples, e.len = clip.len;
  e.gain = gain, e.pitch = pitch, e.vol = vol;
  return e;
}

}  // namespace

// A clip plays once, as loud as its gain and the volume say, and a higher
// pitch plays it faster.
void test_an_effect_plays_its_clip_once() {
  std::vector<uint8_t> full = mixed(effect("tick"));
  TEST_ASSERT_TRUE(peak(full) > 60);  // 255 at volume 6: as loud as the voice, about 0.6 of full
  TEST_ASSERT_TRUE(peak(full) <= 77);
  TEST_ASSERT_INT_WITHIN(2, peak(full) / 2, peak(mixed(effect("tick", 128))));
  TEST_ASSERT_EQUAL(0, peak(mixed(effect("tick", 255, 1000, 0))));  // muted
  size_t normal = lastSounding(mixed(effect("tone")));
  size_t fast = lastSounding(mixed(effect("tone", 255, 2000)));
  TEST_ASSERT_INT_WITHIN(int(normal / 50), int(normal / 2), int(fast));
}

// Under a `say`, effects are a quarter as loud, but those the face says a
// `say` never turns down (needs you's, the finish's, an error's): the
// event decides, not the clip.
void test_a_say_turns_effects_down_but_not_the_needs_you_cues() {
  TEST_ASSERT_INT_WITHIN(2, peak(mixed(effect("tick"))) / 4, peak(mixed(effect("tick"), true)));
  voice::Effect ding = effect("ding");
  ding.duck = false;
  TEST_ASSERT_EQUAL(peak(mixed(ding)), peak(mixed(ding, true)));
  TEST_ASSERT_INT_WITHIN(2, peak(mixed(effect("ding"))) / 4, peak(mixed(effect("ding"), true)));
}

// Four at once; a fifth replaces the oldest. Stopping fades out in 4 ms.
void test_voices_and_stopping() {
  voice::Effects fx;
  for (int i = 0; i < voice::Effects::kVoices + 1; ++i) fx.play(effect("tone", 40));
  std::vector<uint8_t> out(2205, 128);
  fx.mix(out.data(), out.size(), false);
  TEST_ASSERT_TRUE(fx.playing());
  fx.stop();
  std::vector<uint8_t> tail(200, 128);
  fx.mix(tail.data(), tail.size(), false);
  TEST_ASSERT_FALSE(fx.playing());
  TEST_ASSERT_TRUE(lastSounding(tail) < size_t(voice::kOutRate * 4 / 1000));
}

// Pins the sound queue's rule when it's full (app::Sound::toDrop): an
// effect goes first, the oldest waiting, or the new one if it's an effect;
// then the oldest `say`; a hush or a stop only when another of its kind
// waits after it or is the new one, so none is ever lost to effects.
static void test_a_full_sound_queue_never_drops_a_stop() {
  using Kind = app::Sound::Kind;
  auto cmd = [](Kind k) {
    app::Sound::Cmd c{};
    c.kind = k;
    return c;
  };
  const app::Sound::Cmd hush = cmd(Kind::kHush), stop = cmd(Kind::kStopEffects), fx = cmd(Kind::kEffect),
                        say = cmd(Kind::kSay);
  app::Sound::Cmd q[8] = {hush, fx, fx, say, fx, fx, fx, fx};
  TEST_ASSERT_EQUAL_INT(1, app::Sound::toDrop(q, 8, stop));  // the oldest effect, not the hush before it
  TEST_ASSERT_EQUAL_INT(1, app::Sound::toDrop(q, 8, fx));
  app::Sound::Cmd stops[8] = {hush, stop, say, hush, stop, say, hush, stop};
  TEST_ASSERT_EQUAL_INT(-1, app::Sound::toDrop(stops, 8, fx));   // the new effect
  TEST_ASSERT_EQUAL_INT(2, app::Sound::toDrop(stops, 8, hush));  // the oldest say
  app::Sound::Cmd only[8] = {hush, stop, hush, stop, hush, stop, hush, stop};
  TEST_ASSERT_EQUAL_INT(0, app::Sound::toDrop(only, 8, say));  // a hush another follows
  app::Sound::Cmd two[2] = {hush, stop};
  TEST_ASSERT_EQUAL_INT(1, app::Sound::toDrop(two, 2, stop));  // the stop the new one repeats
  TEST_ASSERT_EQUAL_INT(-1, app::Sound::toDrop(two, 2, say));  // nothing it may drop
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_a_full_sound_queue_never_drops_a_stop);
  RUN_TEST(test_an_effect_plays_its_clip_once);
  RUN_TEST(test_a_say_turns_effects_down_but_not_the_needs_you_cues);
  RUN_TEST(test_voices_and_stopping);
  return UNITY_END();
}
