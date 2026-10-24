// The face's sound effects: the bank's clips and
// timelines as assets/sfx.h has them, the mixer, and when each event plays.
#include <unity.h>

#include <cstdlib>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

#include "render/pixel/anim.h"
#include "render/pixel/effect_track.h"
#include "render/pixel/sign.h"
#include "render/pixel/scene.h"
#include "render/pixel/sounds.h"
#include "voice/effects.h"
#include "voice/player.h"

void setUp() {}
void tearDown() {}

namespace {

using render::Mood;
using render::SceneState;

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
  e.clip = render::pixel::clips().index(name);
  const voice::EffectClip clip = render::pixel::clips().at(e.clip);
  e.samples = clip.samples, e.len = clip.len;
  e.gain = gain, e.pitch = pitch, e.vol = vol;
  return e;
}

render::SceneShow face(Mood m, SceneState s, uint8_t variant, uint32_t t) {
  render::SceneShow f;
  f.mood = m, f.state = s, f.variant = variant, f.t = t;
  return f;
}

// Follows one design from its start to `until` in 10 ms steps, noting when
// (on its clock) each event came out.
struct Heard {
  std::vector<uint32_t> at;
  std::vector<voice::FxEvent> ev;
  int changes = 0;
};
Heard follow(render::pixel::EffectTrack& track, Mood m, SceneState s, uint8_t variant, uint32_t from, uint32_t until) {
  Heard h;
  for (uint32_t t = from; t <= until; t += 10) {
    render::SceneShow f = face(m, s, variant, t);
    voice::FxEvent out[render::pixel::EffectTrack::kMaxOut];
    bool changed;
    int n = track.follow(&f, out, changed);
    h.changes += changed;
    for (int i = 0; i < n; ++i) h.at.push_back(t), h.ev.push_back(out[i]);
  }
  return h;
}

}  // namespace

// The events one loop of a design plays: list n % kLoops of
// a routine design's baked picks.
std::vector<voice::FxEvent> loopEvents(const render::pixel::Score& sc, uint32_t loop) {
  render::pixel::Events l = render::pixel::events(sc, loop);
  std::vector<voice::FxEvent> out;
  for (int i = 0; i < l.n; ++i) out.push_back(render::pixel::fxEvent(l.first + i));
  return out;
}

bool same(const std::vector<voice::FxEvent>& a, const std::vector<voice::FxEvent>& b) {
  if (a.size() != b.size()) return false;
  for (size_t i = 0; i < a.size(); ++i)
    if (a[i].atMs != b[i].atMs || a[i].clip != b[i].clip || a[i].gain != b[i].gain) return false;
  return true;
}

bool guarded(int s) {
  return s == int(SceneState::kNeedsYou) || s == int(SceneState::kTaskComplete) || s == int(SceneState::kError);
}

// The comedy designs (the bank's comedy-art.mjs) that break a quiet look's
// silence, by variation from 0: idle's yawn (3) once, as the face turns to
// it; its sneeze (5) every third loop; excited's zoomies (6) as routine work
// sounds; asleep's snore (3) every fourth loop. Nodding off (idle 4) and
// the rest stay silent.
render::pixel::Policy quietPolicy(SceneState s, int v, int& every, bool excited) {
  every = 1;
  if (s == SceneState::kIdle && v == 3) return render::pixel::Policy::kEntry;
  if (s == SceneState::kIdle && v == 5) return every = 3, render::pixel::Policy::kSparse;
  // Excited's zoomies; every other occasion (occasion-art.mjs) is silent.
  if (s == SceneState::kIdle && v == 6 && excited) return render::pixel::Policy::kLoop;
  if (s == SceneState::kAsleep && v == 3) return every = 4, render::pixel::Policy::kSparse;
  return render::pixel::Policy::kSilent;
}

int count(const std::vector<voice::FxEvent>& evs, const char* clip) {
  int n = 0;
  for (const voice::FxEvent& e : evs) n += e.clip == render::pixel::clips().index(clip);
  return n;
}

// Every design the device draws has a timeline, with clips it has: the
// bank's 46 that the timelines use, its 3 newer ones (brake,
// failedAttempt and the new moods' knock) and the comedy designs' 4 (yawn,
// sneeze, snore and hiccup).
void test_every_design_has_a_timeline() {
  TEST_ASSERT_EQUAL(53, render::pixel::clips().count());
  for (const char* name :
       {"brake", "failedAttempt", "knock", "alertDing", "trophyA", "yawn", "sneeze", "snore", "hiccup"}) {
    TEST_ASSERT_TRUE_MESSAGE(render::pixel::clips().index(name) >= 0, name);
  }
  // About 180 KB was budgeted.
  TEST_ASSERT_TRUE(render::pixel::clips().bytes() < 180u * 1024);
  for (int m = 0; m < render::pixelMoods(); ++m)
    for (int s = 0; s < int(SceneState::kCount); ++s)
      for (int v = 0; v < render::variants(render::pixelMood(m), SceneState(s)); ++v) {
        render::pixel::Score sc = render::pixel::score(m, s, v);
        TEST_ASSERT_TRUE(sc.lists == 1 || sc.lists == render::pixel::kLoops);
        uint32_t loop = render::loopMs(render::pixelMood(m), SceneState(s), v);
        TEST_ASSERT_TRUE(sc.voiceMs > 0 && sc.voiceMs < 8000);
        for (uint32_t n = 0; n < uint32_t(render::pixel::kLoops); ++n) {
          uint16_t prev = 0;
          for (const voice::FxEvent& e : loopEvents(sc, n)) {
            TEST_ASSERT_TRUE(e.clip < render::pixel::clips().count());
            TEST_ASSERT_TRUE(e.atMs >= prev);  // by time
            TEST_ASSERT_TRUE(e.atMs < loop);   // inside the design's loop
            TEST_ASSERT_TRUE(e.gain > 0);
            TEST_ASSERT_TRUE(e.pitch >= 900 && e.pitch <= 1150);
            prev = e.atMs;
          }
        }
      }
  // A variation out of range takes the first, as the screen does; a mood
  // the device doesn't know is silent.
  render::pixel::Score a = render::pixel::score(0, int(SceneState::kWorking), 0);
  render::pixel::Score b = render::pixel::score(0, int(SceneState::kWorking), 9);
  TEST_ASSERT_EQUAL(a.loop0, b.loop0);
  TEST_ASSERT_EQUAL(0, render::pixel::events(render::pixel::score(int(Mood::kCount), 0, 0), 0).n);
}

// The bank's voice-first mix, by state: the quiet states
// are silent but for the comedy's breaks (quietPolicy); needs you's knocks end in the ding, and it, the finish and
// an error play on their first loop only and never duck under a `say`;
// routine designs sound a few of their contacts, picked afresh each loop.
// Each design's voice window is where the bank puts it: a wake-up's once
// the creature is awake, late in its loop, so a hello never lands
// mid-yawn.
void test_each_state_sounds_as_the_bank_says() {
  int working = 0, varied = 0;
  for (int m = 0; m < render::pixelMoods(); ++m) {
    for (int s = 0; s < int(SceneState::kCount); ++s) {
      for (int v = 0; v < render::variants(render::pixelMood(m), SceneState(s)); ++v) {
        render::pixel::Score sc = render::pixel::score(m, s, v);
        TEST_ASSERT_EQUAL(!guarded(s), sc.duck);
        // The voice window opens 0.45 s in, or 0.12 s after a guarded
        // design's last cue has played out.
        std::vector<voice::FxEvent> first = loopEvents(sc, 0);
        if (SceneState(s) == SceneState::kWakeUp) {
          const uint32_t loop = render::loopMs(render::pixelMood(m), SceneState(s), v);
          TEST_ASSERT_TRUE(sc.voiceMs > loop / 2 && sc.voiceMs < loop);
        } else if (!guarded(s)) TEST_ASSERT_EQUAL_UINT16(450, sc.voiceMs);
        else TEST_ASSERT_TRUE(sc.voiceMs >= (first.empty() ? 0 : first.back().atMs) + 120);
        switch (SceneState(s)) {
          case SceneState::kIdle:
          case SceneState::kAsleep: {
            int every;
            TEST_ASSERT_TRUE(sc.policy == quietPolicy(SceneState(s), v, every, render::pixelMood(m) == Mood::kExcited));
            TEST_ASSERT_EQUAL(every, sc.every);
            break;
          }
          case SceneState::kNoApp:
          case SceneState::kListening:
          case SceneState::kWaiting:
            TEST_ASSERT_TRUE(sc.policy == render::pixel::Policy::kSilent);
            break;
          case SceneState::kNeedsYou: {
            TEST_ASSERT_TRUE(sc.policy == render::pixel::Policy::kEntry);
            bool ding = false;  // every needs-you performance ends in the ding
            for (const voice::FxEvent& e : loopEvents(sc, 0)) ding |= e.clip == render::pixel::clips().index("alertDing");
            TEST_ASSERT_TRUE(ding);
            break;
          }
          case SceneState::kTaskComplete:
          case SceneState::kError:
            TEST_ASSERT_TRUE(sc.policy == render::pixel::Policy::kEntry);
            TEST_ASSERT_TRUE(render::pixel::events(sc, 0).n > 0);
            // Trophy, then hiccups: the cheer's fanfare, then three clicks.
            if (count(first, "hiccup")) {
              TEST_ASSERT_EQUAL(3, count(first, "hiccup"));
              TEST_ASSERT_EQUAL(1, count(first, "trophyA") + count(first, "trophyB"));
            }
            break;
          case SceneState::kWorking: {
            TEST_ASSERT_TRUE(sc.policy == render::pixel::Policy::kLoop || sc.policy == render::pixel::Policy::kSparse);
            TEST_ASSERT_EQUAL(render::pixel::kLoops, sc.lists);
            ++working;
            bool differ = false;
            for (uint32_t n = 0; n < uint32_t(render::pixel::kLoops); ++n) {
              int k = render::pixel::events(sc, n).n;
              TEST_ASSERT_TRUE(k >= 1 && k <= 8);  // thinned: at most four gestures a loop
              differ |= !same(loopEvents(sc, n), loopEvents(sc, 0));
            }
            varied += differ;
            break;
          }
          default: break;
        }
      }
    }
  }
  TEST_ASSERT_EQUAL(working, varied);  // no working design sounds the same every loop
  // A failed finish never plays a trophy.
  for (int m = 0; m < render::pixelMoods(); ++m) {
    for (int v = 0; v < render::variants(render::pixelMood(m), SceneState::kTaskComplete); ++v) {
      if (render::variantOutcome(render::pixelMood(m), SceneState::kTaskComplete, v) != render::Outcome::kFailure) continue;
      for (const voice::FxEvent& e : loopEvents(render::pixel::score(m, int(SceneState::kTaskComplete), v), 0)) {
        TEST_ASSERT_FALSE(std::strncmp(render::pixel::clips().at(e.clip).name, "trophy", 6) == 0);
      }
    }
  }
}

// A clip plays once, as loud as its gain and the volume say, and a higher
// pitch plays it faster.
void test_an_effect_plays_its_clip_once() {
  std::vector<uint8_t> full = mixed(effect("key"));
  TEST_ASSERT_TRUE(peak(full) > 60);  // 255 at volume 6: as loud as the voice, about 0.6 of full
  TEST_ASSERT_TRUE(peak(full) <= 77);
  TEST_ASSERT_INT_WITHIN(2, peak(full) / 2, peak(mixed(effect("key", 128))));
  TEST_ASSERT_EQUAL(0, peak(mixed(effect("key", 255, 1000, 0))));  // muted
  size_t normal = lastSounding(mixed(effect("cloth")));
  size_t fast = lastSounding(mixed(effect("cloth", 255, 2000)));
  TEST_ASSERT_INT_WITHIN(int(normal / 50), int(normal / 2), int(fast));
}

// Under a `say`, effects are a quarter as loud, the bank's
// level, but needs you's, the finish's and an error's never are: the design
// decides, not the clip.
void test_a_say_turns_effects_down_but_not_the_needs_you_cues() {
  TEST_ASSERT_INT_WITHIN(2, peak(mixed(effect("key"))) / 4, peak(mixed(effect("key"), true)));
  voice::Effect ding = effect("alertDing");
  ding.duck = false;
  TEST_ASSERT_EQUAL(peak(mixed(ding)), peak(mixed(ding, true)));
  TEST_ASSERT_INT_WITHIN(2, peak(mixed(effect("alertDing"))) / 4, peak(mixed(effect("alertDing"), true)));
  // The track gives the rule of the design whose events it hands over.
  for (SceneState s : {SceneState::kNeedsYou, SceneState::kWorking}) {
    render::pixel::EffectTrack track;
    Heard h = follow(track, Mood::kCalm, s, 0, 0, 6000);
    TEST_ASSERT_TRUE(h.ev.size() > 0);
    TEST_ASSERT_EQUAL(s != SceneState::kNeedsYou, track.duck());
  }
}

// Four at once; a fifth replaces the oldest. Stopping fades out in 4 ms.
void test_voices_and_stopping() {
  voice::Effects fx;
  for (int i = 0; i < voice::Effects::kVoices + 1; ++i) fx.play(effect("victoryPodium", 40));
  std::vector<uint8_t> out(2205, 128);
  fx.mix(out.data(), out.size(), false);
  TEST_ASSERT_TRUE(fx.playing());
  fx.stop();
  std::vector<uint8_t> tail(200, 128);
  fx.mix(tail.data(), tail.size(), false);
  TEST_ASSERT_FALSE(fx.playing());
  TEST_ASSERT_TRUE(lastSounding(tail) < size_t(voice::kOutRate * 4 / 1000));
}

// A working design sounds every loop, each loop its own few contacts (the
// bank's picks for that loop), each kLeadMs ahead of its frame, and nothing
// is doubled; after kLoops loops the picks come round again.
void test_a_working_design_sounds_every_loop() {
  render::pixel::EffectTrack track;
  render::pixel::Score sc = render::pixel::score(render::pixelIndex(Mood::kHappy), int(SceneState::kWorking), 0);
  uint32_t loop = render::loopMs(Mood::kHappy, SceneState::kWorking, 0);
  const uint32_t loops = render::pixel::kLoops + 2;
  Heard h = follow(track, Mood::kHappy, SceneState::kWorking, 0, 0, loops * loop - render::pixel::EffectTrack::kLeadMs - 10);
  std::vector<uint32_t> due;
  for (uint32_t n = 0; n < loops; ++n) {
    for (const voice::FxEvent& e : loopEvents(sc, n)) due.push_back(n * loop + e.atMs);
  }
  TEST_ASSERT_EQUAL(int(due.size()), int(h.ev.size()));
  TEST_ASSERT_EQUAL(0, h.changes);
  for (size_t i = 0; i < h.ev.size(); ++i) {
    uint32_t sent = h.at[i] + render::pixel::EffectTrack::kLeadMs;
    if (h.at[i] == 0) TEST_ASSERT_TRUE(due[i] < sent);  // due before the lead: at once
    else TEST_ASSERT_TRUE(sent > due[i] && sent <= due[i] + 10);  // within one 10 ms step
  }
  TEST_ASSERT_TRUE(same(loopEvents(sc, render::pixel::kLoops), loopEvents(sc, 0)));
  TEST_ASSERT_FALSE(same(loopEvents(sc, 1), loopEvents(sc, 0)) && same(loopEvents(sc, 2), loopEvents(sc, 0)));
}

// The finish, needs you, an error and the rules' other reactions play their sounds
// on their first loop only.
void test_entry_designs_sound_once() {
  for (Mood m : {Mood::kProud, Mood::kWounded}) {
    for (SceneState s : {SceneState::kTaskComplete, SceneState::kNeedsYou, SceneState::kError, SceneState::kPoked}) {
      render::pixel::EffectTrack track;
      render::pixel::Score sc = render::pixel::score(render::pixelIndex(m), int(s), 1);
      TEST_ASSERT_TRUE(sc.policy == render::pixel::Policy::kEntry);
      uint32_t loop = render::loopMs(m, s, 1);
      Heard h = follow(track, m, s, 1, 0, 4 * loop);
      TEST_ASSERT_EQUAL(render::pixel::events(sc, 0).n, int(h.ev.size()));
    }
  }
}

// The needs-you arc's cues play over the design's, once each, at their
// times on the needs-you's clock and at their gain and pitch
// (render/pixel/sign.h, kArcCues): a swipe as the sway starts, knocks that
// grow with the picture (one as it sways, two mid-sway, three as it
// shakes, four at the height of it), each group louder and higher, the
// brake at the stare and the slide as the sign goes back up. A new needs-you
// plays them again.
void test_the_needs_you_arc_cues_once_each() {
  render::pixel::PixelFace face;
  const voice::EffectClips& clips = face.clips();
  std::vector<std::pair<int, int>> pitches;  // each heard cue's gain and pitch
  render::FaceContext context;
  auto look = [&](SceneState state, uint32_t t) {
    render::FaceSource source;
    source.mood = Mood::kCalm, source.look = state;
    face.sync(source, context, t);
  };
  // A needs-you at `from`: its clock starts there.
  auto heard = [&](uint32_t from, uint32_t to) {
    look(SceneState::kNeedsYou, from);
    face.alert(from, false);
    std::vector<std::pair<uint32_t, std::string>> out;
    for (uint32_t t = from; t < to; t += 16) {
      voice::FxEvent due[render::Face::kMaxCues];
      bool changed;
      int n = face.cues(t, true, due, changed);
      for (int i = 0; i < n; ++i) {
        std::string name = clips.at(due[i].clip).name;
        if (name == "swipe" || name == "alertKnock" || name == "brake" || name == "slide") {
          TEST_ASSERT_FALSE(due[i].duck);
          out.push_back({t - from, name});
          pitches.push_back({due[i].gain, due[i].pitch});
        }
      }
    }
    return out;
  };
  auto arc = heard(0, 30000);
  const auto& cues = render::kArcCues;
  // The design's own knocks may share the bank's clip; the arc's are the
  // ones at the arc's times.
  for (const render::ArcCue& c : cues) {
    TEST_ASSERT_TRUE_MESSAGE(clips.index(c.clip) >= 0, c.clip);
    int at = 0;
    for (const auto& e : arc)
      if (e.second == c.clip && e.first + render::pixel::EffectTrack::kLeadMs >= c.at && e.first <= c.at) ++at;
    TEST_ASSERT_EQUAL_INT_MESSAGE(1, at, c.clip);
  }
  // The arc's knocks, in groups by the gap before them: 1, 2, 3, 4, each
  // group louder and higher than the last.
  std::vector<int> groups, gains, tones;
  uint32_t last = 0;
  for (size_t i = 0; i < arc.size(); ++i) {
    if (arc[i].second != "alertKnock" || arc[i].first < render::Arc::kSwayAt) continue;  // not the design's own
    if (groups.empty() || arc[i].first - last > 1000) {
      groups.push_back(0), gains.push_back(pitches[i].first), tones.push_back(pitches[i].second);
    }
    ++groups.back();
    TEST_ASSERT_EQUAL_INT(gains.back(), pitches[i].first);
    TEST_ASSERT_EQUAL_INT(tones.back(), pitches[i].second);
    last = arc[i].first;
  }
  TEST_ASSERT_EQUAL_INT(4, int(groups.size()));
  for (int g = 0; g < 4; ++g) TEST_ASSERT_EQUAL_INT(g + 1, groups[g]);
  for (int g = 1; g < 4; ++g) TEST_ASSERT_TRUE(gains[g] > gains[g - 1] && tones[g] > tones[g - 1]);
  TEST_ASSERT_EQUAL_UINT32(render::Arc::kSwayAt, cues[0].at);
  TEST_ASSERT_EQUAL_STRING("swipe", cues[0].clip);
  TEST_ASSERT_EQUAL_UINT32(render::Arc::kShakeAt, cues[4].at);
  TEST_ASSERT_EQUAL_UINT32(render::Arc::kStareAt, cues[11].at);
  TEST_ASSERT_EQUAL_STRING("brake", cues[11].clip);
  TEST_ASSERT_EQUAL_UINT32(render::Arc::kGiveUpAt, cues[12].at);
  TEST_ASSERT_EQUAL_STRING("slide", cues[12].clip);
  // Another state stops the arc; the next needs-you starts it over.
  look(SceneState::kIdle, 35000);
  voice::FxEvent due[render::Face::kMaxCues];
  bool changed;
  face.cues(35000, true, due, changed);
  auto again = heard(40000, 46000);
  int swipes = 0;
  for (const auto& e : again) swipes += e.second == "swipe" && e.first <= 5000 && e.first + 100 >= 5000;
  TEST_ASSERT_EQUAL_INT(1, swipes);
}

// Listening is silent, so nothing competes with your voice.
void test_listening_is_silent() {
  for (int m = 0; m < render::pixelMoods(); ++m) {
    for (int v = 0; v < render::variants(render::pixelMood(m), SceneState::kListening); ++v) {
      render::pixel::EffectTrack track;
      TEST_ASSERT_TRUE(render::pixel::score(m, int(SceneState::kListening), v).policy == render::pixel::Policy::kSilent);
      Heard h = follow(track, render::pixelMood(m), SceneState::kListening, uint8_t(v), 0, 20000);
      TEST_ASSERT_EQUAL(0, int(h.ev.size()));
    }
  }
}

// A short busy loop sounds every other loop, counted in loops from the
// design's start as the bank's player counts them (score.mjs
// cycleHasSound), not by the clock; idle is silent.
void test_a_short_loop_sounds_every_other_loop() {
  render::pixel::EffectTrack track;
  render::pixel::Score sc = render::pixel::score(render::pixelIndex(Mood::kExcited), int(SceneState::kWorking), 0);
  uint32_t loop = render::loopMs(Mood::kExcited, SceneState::kWorking, 0);
  TEST_ASSERT_TRUE(sc.policy == render::pixel::Policy::kSparse);
  TEST_ASSERT_EQUAL(2, sc.every);
  TEST_ASSERT_TRUE(loop < 3500);
  Heard h = follow(track, Mood::kExcited, SceneState::kWorking, 0, 0, 12 * loop - render::pixel::EffectTrack::kLeadMs - 10);
  size_t k = 0;
  for (uint32_t n = 0; n < 12; ++n) {
    std::vector<voice::FxEvent> want = n % 2 ? std::vector<voice::FxEvent>{} : loopEvents(sc, n);
    for (const voice::FxEvent& e : want) {
      TEST_ASSERT_TRUE(k < h.ev.size());
      TEST_ASSERT_EQUAL(e.atMs, h.ev[k].atMs);
      TEST_ASSERT_EQUAL((h.at[k] + render::pixel::EffectTrack::kLeadMs) / loop, n);
      ++k;
    }
  }
  TEST_ASSERT_EQUAL(int(k), int(h.ev.size()));
  for (Mood m : {Mood::kHappy, Mood::kCalm}) {
    render::pixel::EffectTrack quiet;
    TEST_ASSERT_EQUAL(0, int(follow(quiet, m, SceneState::kIdle, 1, 0, 60000).ev.size()));
  }
}

// The comedy breaks the quiet now and then, counted in loops from the
// design's start as the bank's player counts them: a yawn on its first loop
// only, a sneeze on loops 0, 3, 6, a snore on 0, 4, 8, nodding off never;
// all soft, and a line turns them down. Each mood has the idle ones, and
// the snore is the same in every mood.
void test_the_quiet_breaks_now_and_then() {
  struct Case {
    Mood mood;
    SceneState state;
    uint8_t variant;
    const char* clip;
    int every, perLoop;  // every: 0 for the first loop only
  };
  const Case cases[] = {
      {Mood::kHappy, SceneState::kIdle, 3, "yawn", 0, 1},   {Mood::kWounded, SceneState::kIdle, 3, "yawn", 0, 1},
      {Mood::kHappy, SceneState::kIdle, 4, nullptr, 0, 0},  {Mood::kGrumpy, SceneState::kIdle, 5, "sneeze", 3, 1},
      {Mood::kCalm, SceneState::kIdle, 5, "sneeze", 3, 1},  {Mood::kHappy, SceneState::kAsleep, 3, "snore", 4, 2},
      {Mood::kWhiny, SceneState::kAsleep, 3, "snore", 4, 2}};
  for (const Case& c : cases) {
    render::pixel::EffectTrack track;
    const uint32_t loop = render::loopMs(c.mood, c.state, c.variant);
    const uint32_t loops = 9;
    Heard h = follow(track, c.mood, c.state, c.variant, 0, loops * loop - render::pixel::EffectTrack::kLeadMs - 10);
    std::vector<int> per(loops, 0);
    for (size_t i = 0; i < h.ev.size(); ++i) {
      if (c.clip && h.ev[i].clip == render::pixel::clips().index(c.clip)) {
        ++per[(h.at[i] + render::pixel::EffectTrack::kLeadMs) / loop];
        TEST_ASSERT_TRUE(h.ev[i].duck);
      }
    }
    for (uint32_t n = 0; n < loops; ++n) {
      const bool sounds = c.clip && (c.every ? n % c.every == 0 : n == 0);
      TEST_ASSERT_EQUAL_MESSAGE(sounds ? c.perLoop : 0, per[n], c.clip ? c.clip : "nodding off");
    }
    if (!c.clip) TEST_ASSERT_EQUAL(0, int(h.ev.size()));
    TEST_ASSERT_TRUE(track.duck());
  }
  // Soft: no quiet break is louder than a routine key press at its loudest.
  int keys = 0, breaks = 0;
  for (int m = 0; m < render::pixelMoods(); ++m) {
    for (int v = 0; v < render::variants(render::pixelMood(m), SceneState::kWorking); ++v) {
      render::pixel::Score sc = render::pixel::score(m, int(SceneState::kWorking), v);
      for (uint32_t n = 0; n < uint32_t(render::pixel::kLoops); ++n)
        for (const voice::FxEvent& e : loopEvents(sc, n)) keys = e.gain > keys ? e.gain : keys;
    }
    for (SceneState s : {SceneState::kIdle, SceneState::kAsleep}) {
      for (int v = 0; v < render::variants(render::pixelMood(m), s); ++v) {
        int every;
        if (quietPolicy(s, v, every, render::pixelMood(m) == Mood::kExcited) == render::pixel::Policy::kLoop)
          continue;  // zoomies: routine work's level
        for (const voice::FxEvent& e : loopEvents(render::pixel::score(m, int(s), v), 0))
          breaks = e.gain > breaks ? e.gain : breaks;
      }
    }
  }
  TEST_ASSERT_TRUE(breaks > 0 && breaks < keys);
  // The snore is the same in every mood, as asleep is.
  for (int m = 1; m < render::pixelMoods(); ++m) {
    TEST_ASSERT_TRUE(same(loopEvents(render::pixel::score(0, int(SceneState::kAsleep), 3), 0),
                          loopEvents(render::pixel::score(m, int(SceneState::kAsleep), 3), 0)));
  }
}

// A new design stops the last one's sounds; a mood changing mid-loop picks
// its timeline up where the clock is, without replaying the loop so far.
void test_a_change_of_design_starts_where_its_clock_is() {
  render::pixel::EffectTrack track;
  uint32_t loop = render::loopMs(Mood::kHappy, SceneState::kWorking, 0);
  follow(track, Mood::kHappy, SceneState::kWorking, 0, 0, loop / 2);
  Heard h = follow(track, Mood::kProud, SceneState::kWorking, 0, loop / 2 + 10, loop - 200);
  TEST_ASSERT_EQUAL(1, h.changes);
  render::pixel::Score g = render::pixel::score(render::pixelIndex(Mood::kProud), int(SceneState::kWorking), 0);
  uint32_t gl = render::loopMs(Mood::kProud, SceneState::kWorking, 0);
  int expect = 0;
  for (uint32_t start = 0, n = 0; start < loop; start += gl, ++n) {
    if (g.policy == render::pixel::Policy::kSparse && n % g.every) continue;
    for (const voice::FxEvent& e : loopEvents(g, n)) {
      uint32_t at = start + e.atMs;
      expect += at >= loop / 2 + 10 && at < loop - 200 + render::pixel::EffectTrack::kLeadMs + 10;
    }
  }
  TEST_ASSERT_TRUE(expect > 0);
  TEST_ASSERT_EQUAL(expect, int(h.ev.size()));
  // A test pattern silences it.
  voice::FxEvent out[render::pixel::EffectTrack::kMaxOut];
  bool changed;
  TEST_ASSERT_EQUAL(0, track.follow(nullptr, out, changed));
  TEST_ASSERT_TRUE(changed);
}

// A stalled loop drops what's more than kLateMs behind, not plays a burst.
void test_a_stall_drops_late_events() {
  render::pixel::EffectTrack track;
  uint32_t loop = render::loopMs(Mood::kExcited, SceneState::kWorking, 0);
  render::pixel::Score sc = render::pixel::score(render::pixelIndex(Mood::kExcited), int(SceneState::kWorking), 0);
  follow(track, Mood::kExcited, SceneState::kWorking, 0, 0, 0);
  render::SceneShow f = face(Mood::kExcited, SceneState::kWorking, 0, 2 * loop);
  voice::FxEvent out[render::pixel::EffectTrack::kMaxOut];
  bool changed;
  int n = track.follow(&f, out, changed);
  int window = 0;
  for (const voice::FxEvent& e : loopEvents(sc, 2)) window += e.atMs < render::pixel::EffectTrack::kLeadMs;
  TEST_ASSERT_EQUAL(window, n);
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_every_design_has_a_timeline);
  RUN_TEST(test_each_state_sounds_as_the_bank_says);
  RUN_TEST(test_an_effect_plays_its_clip_once);
  RUN_TEST(test_a_say_turns_effects_down_but_not_the_needs_you_cues);
  RUN_TEST(test_voices_and_stopping);
  RUN_TEST(test_a_working_design_sounds_every_loop);
  RUN_TEST(test_entry_designs_sound_once);
  RUN_TEST(test_listening_is_silent);
  RUN_TEST(test_the_needs_you_arc_cues_once_each);
  RUN_TEST(test_a_short_loop_sounds_every_other_loop);
  RUN_TEST(test_the_quiet_breaks_now_and_then);
  RUN_TEST(test_a_change_of_design_starts_where_its_clock_is);
  RUN_TEST(test_a_stall_drops_late_events);
  return UNITY_END();
}
