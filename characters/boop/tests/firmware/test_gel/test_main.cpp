// Complete integer engine, native surface bounds and face seam.
#include <unity.h>
#include <cmath>
#include <vector>
#include <memory>
#include <cstring>
#include <cstdlib>
#include "render/gel/painter.h"
#include "render/gel/geometry.h"
#include "render/gel/face.h"
#include "render/pixel/anim.h"
#include "app/behaviour.h"
#include "render/gel/sounds.h"
#include "app/device.h"
#include "linkkit/kit.h"
#include <new>
#include "render/gel/lane.h"
#include "render/tags.h"
#include "fonts_gel.h"
using namespace render;
using namespace render::gel;
// Heap allocations while `allocCounting` is on (test_steady_frames_allocate_nothing),
// and the bytes held at any moment (test_histories_stay_off_the_heap): each
// block carries its size in a 16-byte header.
static bool allocCounting = false;
static long allocCount = 0, allocLive = 0;
void* operator new(size_t n) {
  if (allocCounting) ++allocCount;
  auto* p = static_cast<unsigned char*>(std::malloc(n + 16));
  if (!p) throw std::bad_alloc();
  *reinterpret_cast<size_t*>(p) = n;
  allocLive += long(n);
  return p + 16;
}
void operator delete(void* p) noexcept {
  if (!p) return;
  auto* block = static_cast<unsigned char*>(p) - 16;
  allocLive -= long(*reinterpret_cast<size_t*>(block));
  std::free(block);
}
void operator delete(void* p, size_t) noexcept { operator delete(p); }
static_assert(sizeof(Scenes::Saved) < sizeof(slime::Recipe),
              "history stores a catalog reference, not a full recipe copy");
static void test_all_expressions_draw_inside_native_surface() {
  std::vector<uint16_t> px(502 * 410 + 2, 0xA55A);
  Surface s{502, 410, px.data() + 1};
  TEST_ASSERT_EQUAL_UINT32(411640, s.bytes());
  for (int mood = 0; mood < slime::kProfiles; ++mood) {
    auto e = std::make_unique<Engine>();
    e->setMood(mood);
    for (int t = 0; t <= 960; t += 16) e->step(t);
    paint(s, *e);
    TEST_ASSERT_EQUAL_HEX16(0xA55A, px.front());
    TEST_ASSERT_EQUAL_HEX16(0xA55A, px.back());
    TEST_ASSERT_EQUAL_HEX16(0, s.pixels[0]);
    TEST_ASSERT_NOT_EQUAL(0, s.pixels[205 * 502 + 251]);
  }
}
static void test_frame_replay_is_byte_identical() {
  std::vector<uint16_t> a(502 * 410), b(a.size());
  Surface sa{502, 410, a.data()}, sb{502, 410, b.data()};
  auto e = std::make_unique<Engine>();
  e->setMood(slime::kFrightened);
  e->motion.impulse(false, false);
  for (int t = 0; t <= 640; t += 16) e->step(t);
  paint(sa, *e);
  paint(sb, *e);
  TEST_ASSERT_EQUAL_MEMORY(a.data(), b.data(), sa.bytes());
  e->face.bridgeBlink = 1;
  paint(sb, *e);
  TEST_ASSERT_NOT_EQUAL(0, std::memcmp(a.data(), b.data(), sa.bytes()));
}
static void test_one_face_vocabulary_and_latest_facts() {
  linkkit::Rng rng;
  app::Behaviour b(std::make_unique<GelFace>());
  b.reset(0, rng);
  TEST_ASSERT_EQUAL_STRING("gel", b.face().name());
  // Every face draws every mood: the pixel face's frightened wears wounded's designs.
  TEST_ASSERT_EQUAL_INT(render::pixelIndex(Mood::kWounded), render::pixelIndex(Mood::kFrightened));
  app::Model m;
  m.mood = Mood::kFrightened;
  m.base = SceneState::kWorking;
  m.act = SceneState::kTerminal;
  b.onState(m, 0);
  app::ReactionIn in;
  in.anim = SceneState::kTaskComplete;
  in.outcome = Outcome::kFailure;
  in.id = 42;
  in.variant = b.pick(in.anim, m.mood, 255, in.outcome, StartCtx::kNone, rng);
  b.play(in, 0);
  b.advance(1504, rng);
  auto& e = static_cast<GelFace&>(b.face()).engine();
  TEST_ASSERT_TRUE(e.scenes.route.state == SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(e.scenes.route.outcome == Outcome::kFailure);
  m.act = SceneState::kTesting;
  b.onState(m, 1600);
  b.advance(5008, rng);
  TEST_ASSERT_TRUE(e.scenes.route.state == SceneState::kTesting);
  TEST_ASSERT_EQUAL_INT(slime::kFrightened, e.emotion);
}
static void test_request_identity_and_cache_bounds() {
  auto e = std::make_unique<Engine>();
  e->step(0);
  int dings = 0;
  for (int request = 0; request < 80; ++request) {
    Facts f;
    f.base = SceneState::kWorking;
    f.attention.on = true;
    f.attention.id = std::to_string(request);
    e->setFacts(f);
    for (int i = 1; i <= 300; ++i) {
      e->step(uint32_t(request * 4800 + i * 16));
      for (const auto& cue : e->cues)
        if (cue.contact.kind == kAlert) ++dings;
    }
  }
  TEST_ASSERT_EQUAL_INT(80, dings);
  TEST_ASSERT_EQUAL_INT(64, e->scenes.alerts.size());
}
// The bounded histories (moments seen, saved alerts and
// moments, cue identities) keep their 64 entries as keys in fixed tables
// inside the engine. A hundred distinct needs-you requests with long names
// and a hundred moments, each remembered, leave the heap where it was; as
// strings they held about 25 KB of the board's internal RAM.
static void test_histories_stay_off_the_heap() {
  auto e = std::make_unique<Engine>();
  e->step(0);
  const long before = allocLive;
  uint32_t t = 0;
  for (int i = 0; i < 100; ++i) {
    Facts f;
    f.base = SceneState::kWorking;
    f.attention = {true, std::to_string(1000 + i), "claude", "a-very-long-project-name",
                   "A thread with a long name, number " + std::to_string(i), i % 3};
    e->setFacts(f);
    for (int k = 0; k < 40; ++k) e->step(t += 16);
    e->setFacts(Facts{});
    Request r;
    r.anim = i % 2 ? SceneState::kPoked : SceneState::kTaskComplete, r.hasId = true, r.id = "moment-" + std::to_string(i);
    r.outcome = Outcome::kSuccess, r.hold = true;
    e->oneShot(r);
    for (int k = 0; k < 40; ++k) e->step(t += 16);
    e->clearTransient();
  }
  TEST_ASSERT_EQUAL_INT(64, e->scenes.alerts.size());
  TEST_ASSERT_EQUAL_INT(64, e->scenes.moments.size());
  TEST_ASSERT_TRUE_MESSAGE(allocLive - before < 2048, std::to_string(allocLive - before).c_str());
}
static void test_grid_voice_lead_and_late_cues() {
  linkkit::Rng rng;
  GelFace f;
  f.reset(0, rng);
  uint32_t at = 0;
  TEST_ASSERT_TRUE(f.nextDue(3, 20, at));
  TEST_ASSERT_EQUAL_UINT32(16, at);
  TEST_ASSERT_FALSE(f.nextDue(3, 15, at));
  TEST_ASSERT_EQUAL_UINT32(3200, f.loopMs(Mood::kHappy, SceneState::kTaskComplete, 0));
  TEST_ASSERT_EQUAL_UINT32(4200, f.loopMs(Mood::kHappy, SceneState::kTaskComplete, 2));
  TEST_ASSERT_EQUAL_UINT32(750, f.voiceMs(Mood::kHappy, SceneState::kTaskComplete, 0));
  FaceSource s;
  s.look = SceneState::kNeedsYou;
  FaceContext c;
  c.attention = true;
  c.attentionId = 9;
  f.sync(s, c, 0);
  for (uint32_t t = 16; t <= 4800; t += 16) f.step(t, rng);
  voice::FxEvent cues[Face::kMaxCues];
  bool changed = false;
  TEST_ASSERT_EQUAL_INT(0, f.cues(4800, false, cues, changed));
}
static void test_external_source_holds_without_repeating_reveal() {
  auto e = std::make_unique<Engine>();
  Facts f;
  f.base = SceneState::kWorking;
  f.act = SceneState::kTesting;
  e->setFacts(f);
  e->step(0);
  Request req;
  req.anim = SceneState::kTaskComplete;
  req.outcome = Outcome::kSuccess;
  req.hasId = true;
  req.id = "held";
  req.hold = true;
  req.variant = 0;
  e->oneShot(req);
  int reveals = 0;
  for (int t = 16; t <= 6400; t += 16) {
    e->step(t);
    for (auto& cue : e->cues)
      if (cue.contact.kind == kSuccess) ++reveals;
  }
  TEST_ASSERT_EQUAL_INT(1, reveals);
  TEST_ASSERT_TRUE(e->scenes.route.state == SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(e->scenes.visible(Scenes::kResultProp, e->timeMs()) == F(0));
  e->clearTransient();
  TEST_ASSERT_TRUE(e->scenes.route.state == SceneState::kTesting);
}
// CONTINUITY.md, Alerts, taps and interruption: an alert interrupted before
// its knocks and ding resumes where it stopped, so each plays exactly once;
// one interrupted after them returns to its silent hold.
static void test_interrupted_alert_signals_exactly_once() {
  for (int after : {0, 160, 320, 640, 2000}) {
    for (bool timeout : {false, true}) {
      auto e = std::make_unique<Engine>();
      e->step(0);
      Facts f;
      f.base = SceneState::kWorking;
      f.attention.on = true;
      f.attention.id = std::to_string(after);
      e->setFacts(f);
      int knocks = 0, reveals = 0, dings = 0, variant = e->scenes.variant;
      uint32_t t = 0;
      auto run = [&](int ms) {
        for (int i = 0; i < ms; i += 16) {
          e->step(t += 16);
          for (const auto& c : e->scenes.contacts) {
            knocks += c.kind == kKnock;
            reveals += c.kind == kAlert;
          }
          for (const auto& cue : e->cues) dings += std::strcmp(cue.recipe, "ding") == 0;
        }
      };
      run(after);
      Request mic;
      mic.anim = SceneState::kListening;
      mic.hasId = true;
      mic.id = "mic";
      if (timeout)
        e->linkTimedOut(true);
      else
        e->oneShot(mic);
      run(640);
      mic.stop = true;
      if (timeout)
        e->linkTimedOut(false);
      else
        e->oneShot(mic);
      TEST_ASSERT_TRUE(e->scenes.route.state == SceneState::kNeedsYou);
      TEST_ASSERT_TRUE(e->scenes.quietRestored);
      run(4800);
      TEST_ASSERT_EQUAL_INT(variant + 1, knocks);
      TEST_ASSERT_EQUAL_INT(1, reveals);
      TEST_ASSERT_EQUAL_INT(1, dings);
    }
  }
}
// CONTINUITY.md, Continuity of what is drawn: across every directed edge the
// drawn ratios stay inside (0.75, 4/3) and never jump, the mouth dots only
// at the swap, a retarget keeps the controls' velocity, and the alert sign
// ramps in and out with no step larger than a slice of its ramp.
static void test_face_and_props_move_without_jumps() {
  const F ratioStep = q(.163), rampStep = q(.134);
  for (int i = 0; i < slime::kEdgeCount; ++i) {
    auto e = std::make_unique<Engine>();
    e->setMood(slime::kEdges[i].from);
    for (uint32_t t = 0; t <= 640; t += 16) e->step(t);
    e->setMood(slime::kEdges[i].to, i % 3);
    auto previous = e->face.render;
    for (uint32_t t = 656; t <= 1280; t += 16) {
      e->step(t);
      const auto& r = e->face.render;
      for (int k = 0; k < 3; ++k) {
        TEST_ASSERT_TRUE(r[k] > q(.75) - q(.0001) && r[k] < q(4.0 / 3) + q(.0001));
        TEST_ASSERT_TRUE(abs(r[k] - previous[k]) <= ratioStep);
      }
      TEST_ASSERT_TRUE(abs(r[SemanticFace::kMouthDot] - (1 - q(.8) * e->face.bridgeBlink)) <= q(.0001));
      previous = r;
    }
  }
  SemanticFace face;
  face.setMood(slime::kFrightened);
  for (int i = 0; i < 3; ++i) face.advance(T::ratio(16, 1000), false);
  const F moving = face.velocity[2];
  TEST_ASSERT_TRUE(abs(moving) > q(.01));
  face.setMood(slime::kHappy);
  TEST_ASSERT_TRUE(face.velocity[2] == moving);
  auto e = std::make_unique<Engine>();
  e->step(0);
  Facts f;
  f.base = SceneState::kWorking;
  f.attention.on = true;
  e->setFacts(f);
  F last = 0;
  bool seen = false;
  for (uint32_t t = 16; t <= 3200; t += 16) {
    if (t == 160 || t == 1600) {
      Request mic;
      mic.anim = SceneState::kListening;
      mic.hasId = true;
      mic.id = "mic" + std::to_string(t);
      mic.stop = t == 1600;
      e->oneShot(mic);
    }
    e->step(t);
    F now = e->scenes.visible(Scenes::kAlertProp, e->timeMs());
    TEST_ASSERT_TRUE(abs(now - last) <= rampStep);
    seen |= now > q(.99);
    last = now;
  }
  TEST_ASSERT_TRUE(seen);
}
// The face brings its own clips; the shared mixer plays
// whatever samples it's handed, whichever face is built.
static void test_gel_clips_use_the_shared_mixer() {
  GelFace face;
  const voice::EffectClips& clips = face.clips();
  // Thirteen sketches, three takes each: comedy's sneeze and snore breath too.
  TEST_ASSERT_EQUAL_INT(39, clips.count());
  TEST_ASSERT_EQUAL_STRING("gel-sketch-v1", clips.version());
  TEST_ASSERT_EQUAL_INT(clips.index("knock-2"), clipFor("knock", 2));
  TEST_ASSERT_EQUAL_INT(-1, clipFor("knock", 3));
  TEST_ASSERT_EQUAL_INT(-1, clipFor("knoc", 0));
  for (const char* recipe : {"sneeze", "breath", "bounce"})
    for (int take = 0; take < 3; ++take) TEST_ASSERT_TRUE(clipFor(recipe, take) >= 0);
  for (int i = 0; i < clips.count(); ++i) {
    const voice::EffectClip clip = clips.at(i);
    voice::Effects fx;
    fx.play({i, 255, 1000, 6, true, clip.samples, clip.len});
    std::vector<uint8_t> out(4096, 128);
    fx.mix(out.data(), out.size(), false);
    bool audible = false;
    for (auto v : out) audible |= v != 128;
    TEST_ASSERT_TRUE(audible);
  }
}
// Each sound carries its own duck. A needs-you alert's
// knocks and ding stay up under a line; routine typing turns down.
static void test_each_cue_carries_its_own_duck() {
  linkkit::Rng rng;
  GelFace f;
  f.reset(0, rng);
  FaceSource s;
  FaceContext c;
  c.base = SceneState::kWorking;
  c.act = SceneState::kTerminal;
  s.look = SceneState::kTerminal;
  f.sync(s, c, 0);
  int routine = 0, alert = 0;
  voice::FxEvent cues[Face::kMaxCues];
  bool changed = false;
  for (uint32_t t = 16; t <= 16000; t += 16) {
    if (t == 9600) {
      c.attention = true;
      c.attentionId = 7;
      s.look = SceneState::kNeedsYou;
      f.sync(s, c, t);
    }
    f.step(t, rng);
    int n = f.cues(t, true, cues, changed);
    for (int i = 0; i < n; ++i) {
      if (t < 9600) {
        TEST_ASSERT_TRUE(cues[i].duck);
        ++routine;
      } else {
        TEST_ASSERT_FALSE(cues[i].duck);
        ++alert;
      }
    }
  }
  TEST_ASSERT_TRUE(routine > 0);
  TEST_ASSERT_TRUE(alert > 0);
}
// A pick changes nothing (a refused call leaves no trace);
// started then draws the same take for real.
static void test_pick_is_pure_and_started_commits_it() {
  linkkit::Rng rng;
  GelFace f;
  f.reset(0, rng);
  const uint32_t before = f.engine().random.state;
  const uint8_t first = f.pick(SceneState::kTaskComplete, Mood::kGrumpy, 0, Outcome::kSuccess, StartCtx::kNone, rng);
  TEST_ASSERT_EQUAL_UINT8(first,
                          f.pick(SceneState::kTaskComplete, Mood::kGrumpy, 0, Outcome::kSuccess, StartCtx::kNone, rng));
  TEST_ASSERT_EQUAL_UINT32(before, f.engine().random.state);
  f.started(SceneState::kTaskComplete, Mood::kGrumpy, first, Outcome::kSuccess, StartCtx::kNone);
  TEST_ASSERT_TRUE(f.engine().random.state != before);
  // The shuffle bag never repeats a take straight away.
  TEST_ASSERT_TRUE(first != f.pick(SceneState::kTaskComplete, Mood::kGrumpy, 0, Outcome::kSuccess, StartCtx::kNone, rng));
}
// After a reset the engine draws from the reference traces'
// seed, so the board and the simulator choose alike; a board's power-on
// seeds it from the kit's randomness instead, and the next reset goes back.
static void test_a_power_on_seeds_the_engine_and_a_reset_restores_53() {
  linkkit::Rng rng;
  GelFace f;
  f.reset(0, rng);
  Engine fresh(53), seeded(0xab12);
  fresh.step(0);
  seeded.step(0);
  TEST_ASSERT_EQUAL_UINT32(fresh.random.state, f.engine().random.state);
  f.seed(0xab12);
  TEST_ASSERT_EQUAL_UINT32(seeded.random.state, f.engine().random.state);
  TEST_ASSERT_TRUE(seeded.random.state != fresh.random.state);
  f.reset(0, rng);
  TEST_ASSERT_EQUAL_UINT32(fresh.random.state, f.engine().random.state);
}
// The timing Behaviour plays by is the recipe table's. The
// outcome and context rows time like their state's own row, which is what
// loopMs and voiceMs read.
static void test_timing_comes_from_the_recipe_table() {
  GelFace f;
  constexpr int kStates = int(SceneState::kCount);
  for (int p = 0; p < slime::kProfiles; ++p)
    for (int v = 0; v < 3; ++v) {
      const auto& done = slime::kRecipes[p][int(SceneState::kTaskComplete)][v];
      const auto& start = slime::kRecipes[p][int(SceneState::kStarting)][v];
      for (int row : {kStates, kStates + 1}) TEST_ASSERT_TRUE(slime::kRecipes[p][row][v].duration == done.duration);
      for (int row = kStates + 2; row < kStates + 6; ++row)
        TEST_ASSERT_TRUE(slime::kRecipes[p][row][v].duration == start.duration);
      // wake_up stretches in the start family's timing, with no card.
      const auto& wake = slime::kRecipes[p][int(SceneState::kWakeUp)][v];
      TEST_ASSERT_TRUE(wake.duration == start.duration);
      TEST_ASSERT_NULL(wake.label);
      TEST_ASSERT_EQUAL_UINT8(kStart, wake.contacts[0].kind);
    }
  TEST_ASSERT_EQUAL_INT(kStates, recipeState(SceneState::kTaskComplete, Outcome::kSuccess, StartCtx::kNone));
  TEST_ASSERT_EQUAL_INT(kStates + 1, recipeState(SceneState::kTaskComplete, Outcome::kFailure, StartCtx::kNone));
  TEST_ASSERT_EQUAL_INT(kStates + 2, recipeState(SceneState::kStarting, Outcome::kNone, StartCtx::kNewTask));
  TEST_ASSERT_EQUAL_INT(kStates + 4, recipeState(SceneState::kStarting, Outcome::kNone, StartCtx::kContinuation));
  TEST_ASSERT_EQUAL_INT(kStates + 5, recipeState(SceneState::kStarting, Outcome::kNone, StartCtx::kCompacted));
  TEST_ASSERT_EQUAL_INT(int(Family::kStart), int(family(SceneState::kWakeUp)));
  // Looks rest on one 3.2 s loop whatever the take.
  TEST_ASSERT_EQUAL_UINT32(3200, f.loopMs(Mood::kHappy, SceneState::kIdle, 2));
  // CONTINUITY.md, Comedy: two rows have a fourth take. A success's is its
  // hiccups: the first take's card at 680 ms, then three little contacts in a
  // 3.7 s take; a finish timed without its outcome finds it too.
  for (int row = 0; row < slime::kRecipeStates; ++row)
    TEST_ASSERT_EQUAL_INT(row == int(SceneState::kGesture)                    ? 10
                          : row == int(SceneState::kAsleep) || row == kStates ? 4
                                                                              : 3,
                          takes(row));
  const auto& hiccups = take(slime::kHappy, kStates, 3);
  TEST_ASSERT_EQUAL_UINT8(4, hiccups.count);
  TEST_ASSERT_EQUAL_UINT8(kSuccess, hiccups.contacts[0].kind);
  const int hics[] = {1640, 2060, 2480};
  for (int i = 0; i < 3; ++i) {
    TEST_ASSERT_EQUAL_UINT8(kBody, hiccups.contacts[i + 1].kind);
    TEST_ASSERT_TRUE(hiccups.contacts[i + 1].at == T(hics[i]));
    TEST_ASSERT_TRUE(hiccups.contacts[i + 1].strength == q(.45));
  }
  TEST_ASSERT_EQUAL_UINT32(3700, f.loopMs(Mood::kHappy, SceneState::kTaskComplete, 3));
  TEST_ASSERT_EQUAL_UINT32(750, f.voiceMs(Mood::kHappy, SceneState::kTaskComplete, 3));
  // Asleep's is a snore: two breaths in 4.8 s; its other takes are still.
  const auto& snore = take(slime::kCalm, int(SceneState::kAsleep), 3);
  TEST_ASSERT_TRUE(snore.duration == T(4800));
  TEST_ASSERT_EQUAL_UINT8(2, snore.count);
  for (int i = 0; i < 2; ++i) TEST_ASSERT_EQUAL_UINT8(kBreath, snore.contacts[i].kind);
  TEST_ASSERT_TRUE(snore.contacts[0].at == T(600) && snore.contacts[1].at == T(2600));
  for (int v = 0; v < 3; ++v) TEST_ASSERT_EQUAL_UINT8(0, take(slime::kCalm, int(SceneState::kAsleep), v).count);
  // The gift: proud's lifted success alone shows a bug beside its card.
  int gifts = 0;
  for (int p = 0; p < slime::kProfiles; ++p)
    for (int row = 0; row < slime::kRecipeStates; ++row)
      for (int v = 0; v < takes(row); ++v) gifts += take(p, row, v).gift;
  TEST_ASSERT_EQUAL_INT(1, gifts);
  TEST_ASSERT_TRUE(take(slime::kProud, kStates, 1).gift);
  // A finish's result reaches the strip (screens.cpp's tick or cross).
  TEST_ASSERT_TRUE(f.outcome(Mood::kSad, SceneState::kTaskComplete, 1, Outcome::kFailure) == Outcome::kFailure);
}
// CONTINUITY.md, Comedy: idle's takes are an expression's three gestures,
// its own gags and the three idle gags, and its bag deals the gags from its
// second round. A doze droops the lids and sinks the dome, the zoomies slide
// it edge to edge, a sneeze is a contact that may sound, all off the heap;
// asleep snores only after a round of still rests, and a lost link never.
static void test_comedy_plays_in_idle_and_asleep() {
  TEST_ASSERT_EQUAL_INT(7, slime::kMaxGestures);
  TEST_ASSERT_EQUAL_INT(6, Acting::takes(slime::kCalm));
  for (int p : {slime::kBored, slime::kTired, slime::kLazy, slime::kComfy, slime::kExcited})
    TEST_ASSERT_EQUAL_INT(7, Acting::takes(p));
  TEST_ASSERT_NULL(Acting::gag(slime::kCalm, 2));
  const char* calm[] = {"yawn-and-settle", "doze-and-snap", "sneeze-and-shake"};
  for (int i = 0; i < 3; ++i) TEST_ASSERT_EQUAL_STRING(calm[i], Acting::gesture(slime::kCalm, 3 + i).type);
  TEST_ASSERT_EQUAL_STRING("long-yawn", Acting::gesture(slime::kTired, 3).type);
  TEST_ASSERT_EQUAL_STRING("zoomies", Acting::gesture(slime::kExcited, 3).type);
  TEST_ASSERT_EQUAL_STRING("sneeze-and-shake", Acting::gesture(slime::kExcited, 6).type);
  // The bag: its first round the three gestures, then every take, never the last again.
  Bag<slime::kMaxGestures> bag;
  Random random(53);
  int dealt[15], seen[2][6]{};
  for (int& d : dealt) d = bag.next(random, 6);
  for (int i = 0; i < 15; ++i) {
    if (i < 3) TEST_ASSERT_TRUE(dealt[i] < 3);
    if (i >= 3) ++seen[(i - 3) / 6][dealt[i]];
    if (i) TEST_ASSERT_TRUE(dealt[i] != dealt[i - 1]);
  }
  for (const auto& round : seen)
    for (int n : round) TEST_ASSERT_EQUAL_INT(1, n);
  auto play = [](int profile, int take, uint32_t ms) {
    auto e = std::make_unique<Engine>();
    e->setMood(profile);
    e->step(0);
    e->step(16);
    e->acting.perform(e->motion.time, e->random, take);
    std::vector<std::array<F, 3>> frames;  // closure, slide, squash
    for (uint32_t t = 32; t <= 32 + ms; t += 16) {
      e->step(t);
      frames.push_back({e->acting.closure(), e->acting.slide.x, e->pose()[1]});
    }
    return frames;
  };
  const auto doze = play(slime::kCalm, 4, 3600);
  for (int at : {75, 100, 125, 150}) TEST_ASSERT_TRUE(doze[at][0] > q(.55));  // 1.2 to 2.4 s
  TEST_ASSERT_TRUE(doze[112][2] < doze[0][2] - q(.03));                       // it sinks
  F snap = 0;
  for (int at = 160; at < 180; ++at) snap = max(snap, doze[at][0]);
  TEST_ASSERT_TRUE(snap > q(.7) && doze[200][0] < q(.05));  // a blink, then open
  const auto zoom = play(slime::kExcited, 3, 3600);
  F most = 0, least = 0;
  for (const auto& f : zoom) most = max(most, f[1]), least = min(least, f[1]);
  TEST_ASSERT_TRUE(most > q(.45) && least < q(-.45) && abs(zoom.back()[1]) < q(.02));
  // A sneeze is one contact, a second in, and allocates nothing.
  auto e = std::make_unique<Engine>();
  e->step(0);
  e->acting.perform(e->motion.time, e->random, 5);
  int sneezes = 0;
  allocCount = 0;
  allocCounting = true;
  for (uint32_t t = 16; t <= 2800; t += 16) {
    e->step(t);
    for (const auto& c : e->acting.contacts) {
      TEST_ASSERT_EQUAL_UINT8(kSneeze, c.kind);
      TEST_ASSERT_TRUE(c.timeMs >= T(1000) && c.timeMs < T(1032));
      ++sneezes;
    }
  }
  allocCounting = false;
  TEST_ASSERT_EQUAL_INT(1, sneezes);
  TEST_ASSERT_EQUAL_INT(0, allocCount);
  // Asleep: the first rest and the bag's first round are still; then a snore
  // now and then, two breaths, each a slight swell. A lost link never snores.
  for (bool lost : {false, true}) {
    auto sleepy = std::make_unique<Engine>();
    Facts f;
    f.base = SceneState::kAsleep;
    sleepy->setFacts(f);
    sleepy->linkTimedOut(lost);
    int breaths = 0, firstSnore = -1;
    F swell = 0;
    for (uint32_t t = 0; t <= 60000; t += 16) {
      sleepy->step(t);
      if (sleepy->scenes.variant == 3 && firstSnore < 0) firstSnore = int(t);
      for (const auto& c : sleepy->scenes.contacts) breaths += c.kind == kBreath;
      swell = max(swell, sleepy->scenes.activity[1].x);
    }
    if (lost) {
      TEST_ASSERT_EQUAL_INT(-1, firstSnore);
      TEST_ASSERT_EQUAL_INT(0, breaths);
    } else {
      TEST_ASSERT_TRUE(firstSnore >= 12800);
      TEST_ASSERT_TRUE(breaths >= 2 && breaths % 2 == 0);
      TEST_ASSERT_TRUE(swell > q(.01) && swell < q(.03));
    }
  }
}
// CONTINUITY.md, Gestures: the gesture state has a take for each of
// render::Gesture, each its own gag under the face it borrows; the board
// names the take, and no bag deals it. A shake wobbles the dome both ways
// under baffled eyes, then the mood's face comes back.
static void test_each_gesture_plays_its_own_gag() {
  linkkit::Rng rng;
  GelFace f;
  f.reset(0, rng);
  TEST_ASSERT_EQUAL_INT(int(Gesture::kCount), f.variants(Mood::kHappy, SceneState::kGesture));
  TEST_ASSERT_EQUAL_INT(3, f.variants(Mood::kHappy, SceneState::kPoked));
  const int row = int(SceneState::kGesture);
  for (int g = 0; g < int(Gesture::kCount); ++g) {
    const auto& r = take(slime::kGrumpy, row, g);
    TEST_ASSERT_TRUE(&r == &take(slime::kCalm, row, g));  // the same in every mood
    TEST_ASSERT_TRUE(r.gag >= 0 && r.count > 0);
    char type[32];
    std::snprintf(type, sizeof type, "gesture:%s", gestureName(Gesture(g)));
    TEST_ASSERT_EQUAL_STRING(type, slime::kGags[r.gag].gesture.type);
    TEST_ASSERT_TRUE(slime::kGestureFaces[g] >= 0 && slime::kGestureFaces[g] < slime::kProfiles);
    TEST_ASSERT_EQUAL_UINT8(g, f.pick(SceneState::kGesture, Mood::kHappy, g + 1, Outcome::kNone, StartCtx::kNone, rng));
    TEST_ASSERT_EQUAL_UINT32(uint32_t(F(r.duration).integer()), f.loopMs(Mood::kHappy, SceneState::kGesture, g));
  }
  const uint32_t random = f.engine().random.state;
  f.started(SceneState::kGesture, Mood::kHappy, 5, Outcome::kNone, StartCtx::kNone);
  TEST_ASSERT_EQUAL_UINT32(random, f.engine().random.state);
  FaceSource s;
  FaceContext c;
  c.mood = s.mood = Mood::kHappy;
  f.sync(s, c, 0);
  for (uint32_t t = 16; t <= 480; t += 16) f.step(t, rng);
  s.anim = SceneState::kGesture;
  s.animVariant = uint8_t(Gesture::kDizzy);
  s.at = 496;
  f.sync(s, c, 496);
  const auto& e = f.engine();
  TEST_ASSERT_EQUAL_STRING("baffled", slime::kProfile[e.expression].id);
  TEST_ASSERT_EQUAL_INT(int(Gesture::kDizzy), e.scenes.variant);
  TEST_ASSERT_EQUAL_STRING("gesture:dizzy", slime::kGags[e.acting.playing].gesture.type);
  F most = 0, least = 0;
  for (uint32_t t = 512; t <= 496 + 3400; t += 16) {
    f.sync(s, c, t);
    f.step(t, rng);
    most = max(most, e.acting.slide.x), least = min(least, e.acting.slide.x);
  }
  TEST_ASSERT_TRUE(most > q(.05) && least < q(-.05));
  s.anim = SceneState::kNone;
  f.sync(s, c, 4000);
  f.step(4000, rng);
  TEST_ASSERT_EQUAL_STRING("happy", slime::kProfile[e.expression].id);
  TEST_ASSERT_FALSE(e.acting.holding);
}
// CONTINUITY.md, Occasions: a look's takes for tags and waits, dealt only
// while they fit. Idle at night drowses; with no tag on it never plays an
// occasion; frantic work types frantically; twenty idle minutes nod off.
static void test_occasions_play_only_while_they_fit() {
  auto idle = [](uint32_t when, uint32_t lookMs) {
    auto e = std::make_unique<Engine>();
    e->setOccasion(when, lookMs);
    int occasions = 0, last = -1;
    for (uint32_t t = 0; t <= 120000; t += 16) {
      e->step(t);
      if (e->acting.performance != last && e->acting.performance >= Acting::takes(e->emotion)) {
        const auto& o = slime::kIdleOccasions[e->acting.performance - Acting::takes(e->emotion)];
        TEST_ASSERT_TRUE(fits(o.when, o.after, when, lookMs));
        ++occasions;
      }
      last = e->acting.performance;
    }
    return occasions;
  };
  TEST_ASSERT_EQUAL_INT(0, idle(0, 0));
  TEST_ASSERT_EQUAL_INT(0, idle(tagBit("day") | tagBit("weekend"), 0));
  TEST_ASSERT_TRUE(idle(tagBit("night"), 0) > 0);
  TEST_ASSERT_TRUE(idle(tagBit("party"), 0) > 0);
  TEST_ASSERT_EQUAL_INT(0, idle(0, 1199000));
  TEST_ASSERT_TRUE(idle(0, 1200000) > 0);
  // Work: an occasion's take is numbered after the row's three.
  auto work = [](SceneState base, uint32_t when, uint32_t lookMs) {
    auto e = std::make_unique<Engine>();
    Facts facts;
    facts.base = base;
    e->setFacts(facts);
    e->setOccasion(when, lookMs);
    int occasions = 0;
    for (uint32_t t = 0; t <= 60000; t += 16) {
      e->step(t);
      if (e->scenes.variant >= takes(int(base))) {
        const auto& o = slime::kLookOccasions[e->scenes.variant - takes(int(base))];
        TEST_ASSERT_EQUAL_INT(int(base), o.row);
        TEST_ASSERT_TRUE(fits(o.when, o.after, when, lookMs));
        ++occasions;
      }
    }
    return occasions;
  };
  TEST_ASSERT_EQUAL_INT(0, work(SceneState::kWorking, 0, 0));
  TEST_ASSERT_TRUE(work(SceneState::kWorking, busyTags(5), 0) > 0);
  TEST_ASSERT_TRUE(work(SceneState::kWorking, busyTags(2), 0) > 0);
  TEST_ASSERT_TRUE(work(SceneState::kAsleep, tagBit("night"), 0) > 0);
  TEST_ASSERT_TRUE(work(SceneState::kAsleep, 0, 1800000) > 0);
  TEST_ASSERT_EQUAL_INT(0, work(SceneState::kAsleep, 0, 1799000));
}
void test_fixed_math_and_motion();
void test_software_clock_matches_binary64();
static void test_gel_draws_natively() {
  // Full-panel RGB565. The gel asks for native surfaces;
  // Device allocates them at the board's size, which the simulator's Hal
  // gives as the AMOLED's (what reaches the panel: test_push).
  GelFace face;
  TEST_ASSERT_TRUE(face.drawsNative());
  Surface native{502, 410, nullptr};
  TEST_ASSERT_EQUAL_UINT32(411640, native.bytes());
}
static void test_reference_face_projection_and_pose_bounds() {
  // Compare authored face anchors to camera.mjs + dome equations,
  // at the 95% scene viewport. A 2 px tolerance covers integer/mesh approximation.
  for (uint64_t value = 0; value <= 0xffffffffu; value += 104729) {
    uint64_t r = root(uint32_t(value));
    TEST_ASSERT_TRUE(r * r <= value);
    TEST_ASSERT_TRUE((r + 1) * (r + 1) > value);
  }
  TEST_ASSERT_EQUAL_INT(65535, root(0xffffffffu));
  Surface s{502, 410, nullptr};
  PaintControls c;
  Projector camera(s, c);
  auto left = camera.face(-1229, 258), right = camera.face(1229, 258), mouth = camera.face(0, -414);
  TEST_ASSERT_INT_WITHIN(32, 2852, left.x);
  TEST_ASSERT_INT_WITHIN(32, 5174, right.x);
  TEST_ASSERT_INT_WITHIN(32, 3750, left.y);
  TEST_ASSERT_INT_WITHIN(32, 4327, mouth.y);
  std::vector<uint16_t> pixels(502 * 410 + 2, 0xa55a);
  s.pixels = pixels.data() + 1;
  for (int sign : {-1, 1}) {
    c.lean = sign * 5120;
    c.squash = sign * 5407;
    c.ripple = sign * 4669;
    c.dent = 2949;
    c.roll = sign * 492;
    c.lift = 983;
    c.forward = sign * 942;
    c.slide = sign * 2867;  // a gag's slide at its bound, 0.7
    paint(s, c);
    TEST_ASSERT_EQUAL_HEX16(0xa55a, pixels.front());
    TEST_ASSERT_EQUAL_HEX16(0xa55a, pixels.back());
    for (int y = 328; y < 410; ++y)
      for (int x = 0; x < 502; ++x) TEST_ASSERT_EQUAL_HEX16(0, s.pixels[y * 502 + x]);
  }
}
static void test_tracked_clear_matches_full_clear() {
  // Retained row spans must erase everything from the previous
  // pose/props, and a diagnostic write must invalidate all 410 tracked rows.
  std::vector<uint16_t> a(502 * 410, 0xffff), b(a.size(), 0xffff);
  Surface tracked{502, 410, a.data()}, full{502, 410, b.data()};
  auto e = std::make_unique<Engine>();
  for (int state = 0; state < int(SceneState::kCount); ++state) {
    e->clearTransient();
    e->linkTimedOut(SceneState(state) == SceneState::kNoApp);
    Facts f;
    f.base = SceneState(state) == SceneState::kAsleep ? SceneState::kAsleep
             : SceneState(state) == SceneState::kIdle ? SceneState::kIdle
                                                      : SceneState::kWorking;
    f.act = SceneState(state);
    f.attention.on = SceneState(state) == SceneState::kNeedsYou;
    e->setFacts(f);
    Request r;
    r.anim = reactionFromName(stateName(SceneState(state)));
    r.hasId = true;
    r.id = std::to_string(state);
    if (r.anim != SceneState::kNone) e->oneShot(r);
    e->setMood(state % slime::kProfiles);
    e->step(state * 1600 + 1504);
    full.invalidate();
    paint(tracked, *e);
    paint(full, *e);
    TEST_ASSERT_EQUAL_MEMORY(a.data(), b.data(), tracked.bytes());
  }
  std::fill(a.begin(), a.end(), 0xffff);
  tracked.invalidate();
  full.invalidate();
  PaintControls c;
  paint(tracked, c);
  paint(full, c);
  TEST_ASSERT_EQUAL_MEMORY(a.data(), b.data(), tracked.bytes());
  // Arbitrary taller surfaces safely fall back to a full clear.
  constexpr int kTall = Surface::kTrackedRows + 1;
  std::vector<uint16_t> tall(2 * kTall, 0xffff);
  Surface extra{2, kTall, tall.data()};
  extra.clear();
  extra.touch(0, kTall - 1, 2, kTall);
  tall.back() = 1;
  extra.clear();
  TEST_ASSERT_EQUAL_HEX16(0, tall.back());
}
// A steady scene runs on the board's heap without touching
// it. Through Device, as the board runs it (inputs, sound cues, the
// engine and drawing), 300 frames of working, needs you, the
// frightened face and asleep allocate nothing; only messages and events
// do, into bounded histories. (ArduinoJson's documents use malloc, so a
// line's parsing isn't counted here.)
static void test_steady_frames_allocate_nothing() {
  struct Hal : app::Hal {
    uint32_t realMs() override { return 0; }
    const char* fwVersion() override { return "t"; }
    const char* gitSha() override { return "t"; }
  };
  const char* scenes[] = {
      "{\"t\":\"state\",\"base\":\"working\",\"act\":\"terminal\",\"mood\":\"happy\",\"busy\":1,\"vol\":0}",
      "{\"t\":\"state\",\"base\":\"working\",\"mood\":\"happy\",\"vol\":0,\"attn\":{\"agent\":\"claude\",\"project\":"
      "\"boop\",\"name\":\"Fix a very long test name\",\"id\":7}}",
      "{\"t\":\"state\",\"base\":\"working\",\"act\":\"testing\",\"mood\":\"frightened\",\"busy\":2,\"vol\":0}",
      "{\"t\":\"state\",\"base\":\"asleep\",\"mood\":\"calm\",\"vol\":0}",
  };
  setenv("BOOP_SIM_FACE", "gel", 1);
  Hal hal;
  std::vector<uint8_t> px(size_t(kWidth) * kHeight);
  app::Device dev(hal, px.data());
  linkkit::Kit kit(hal, dev, true);
  unsetenv("BOOP_SIM_FACE");
  auto line = [&](const char* text) {
    kit.handleLine(text, std::strlen(text), linkkit::Link::kUsb);
    kit.tick();
    if (dev.takeFrame()) dev.frames()->present(dev.canvas());
  };
  const char* step = "{\"t\":\"dbg.clock\",\"step\":33}";
  for (const char* scene : scenes) {
    line("{\"t\":\"dbg.reset\"}");
    line(scene);
    for (int i = 0; i < 60; ++i) line(step);  // into the scene's loop
    allocCount = 0;
    allocCounting = true;
    for (int i = 0; i < 300; ++i) line(step);
    allocCounting = false;
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, allocCount, scene);
  }
}
// The host's lane is drawn at the panel's size into the
// bottom fifth only, where the face and its props never draw, and the
// double buffer's tracking clears it as it clears the rest: frame after
// frame of the strip, the bubble and neither, a tracked clear leaves the
// surface as a full one does. The bubble holds the longest take in its own
// font and a line of 34 in the large one.
static void test_the_lane_is_native_and_tracked() {
  constexpr int kW = 502, kH = 410, kLane = kH * 4 / 5;
  TEST_ASSERT_TRUE(22 * kFontBubble.w <= bubbleRoom(kW));
  TEST_ASSERT_TRUE(34 * kLarge.w <= bubbleRoom(kW));
  std::vector<uint16_t> a(kW * kH, 0xffff), b(a.size(), 0xffff), lane(a.size(), 0);
  Surface tracked{kW, kH, a.data()}, full{kW, kH, b.data()}, alone{kW, kH, lane.data()};
  Strip needsYou, working, none;
  needsYou.agent = "claude", needsYou.name = "Make the device answer every touch at once", needsYou.more = 2,
  needsYou.busy = 2;
  working.busy = 3, working.noApp = true;
  const char* lines[] = {nullptr, "Go", "Technical difficulties", nullptr, "Tsk... Validate", nullptr};
  const Strip* strips[] = {&needsYou, &needsYou, &working, &none, &none, &working};
  auto e = std::make_unique<Engine>();
  for (int i = 0; i < 12; ++i) {
    e->step(1504 + i * 400);
    full.invalidate();
    for (Surface* s : {&tracked, &full}) {
      paint(*s, *e);
      paintLane(*s, lines[i % 6], *strips[i % 6]);
    }
    TEST_ASSERT_EQUAL_MEMORY(a.data(), b.data(), tracked.bytes());
    std::fill(lane.begin(), lane.end(), 0);
    alone.invalidate();
    alone.clear();
    paintLane(alone, lines[i % 6], *strips[i % 6]);
    for (int y = 0; y < kLane; ++y)
      for (int x = 0; x < kW; ++x) TEST_ASSERT_EQUAL_HEX16(0, lane[size_t(y) * kW + x]);
  }
  // And the face stops above it: a frame with no lane leaves its rows black.
  tracked.invalidate();
  paint(tracked, *e);
  for (int y = kLane; y < kH; ++y)
    for (int x = 0; x < kW; ++x) TEST_ASSERT_EQUAL_HEX16(0, a[size_t(y) * kW + x]);
}
// What a frame keeps from its surface's last (a card's
// opaque inside, an unchanged lane) is exactly what clearing it whole and
// drawing afresh leaves. Two surfaces taking turns, as the board's do,
// through needs you rising and holding with its strip, a finish's card,
// the start card, a bubble coming and going and the strip's count
// changing, equal a third cleared whole before every frame; and the keeps
// happened.
static void test_kept_cards_and_lanes_match_a_fresh_frame() {
  constexpr int kW = 502, kH = 410;
  std::vector<uint16_t> pa(kW * kH, 0x1234), pb(pa.size(), 0x5678), pf(pa.size());
  Surface turns[2] = {{kW, kH, pa.data()}, {kW, kH, pb.data()}}, fresh{kW, kH, pf.data()};
  auto e = std::make_unique<Engine>();
  Facts f;
  f.base = SceneState::kWorking;
  f.act = SceneState::kTerminal;
  e->setFacts(f);
  Strip asking, working;
  asking.agent = "claude", asking.name = "Fix a test", asking.more = 1, asking.busy = 2;
  working.busy = 1;
  int cardFrames = 0, laneKeeps = 0, cardKeeps = 0, knockKeeps = 0;
  uint32_t t = 0;
  for (int i = 0; i < 400; ++i) {
    if (i == 20) {  // needs you
      f.attention = {true, "7", "claude", "boop", "Fix a test", 1};
      e->setFacts(f);
    } else if (i == 140) {  // answered; a finish with its card
      f.attention = {};
      e->setFacts(f);
      Request r;
      r.anim = SceneState::kTaskComplete, r.hasId = true, r.id = "9", r.outcome = Outcome::kSuccess, r.hold = true;
      e->oneShot(r);
    } else if (i == 260) {
      e->clearTransient();
      Request r;
      r.anim = SceneState::kStarting, r.hasId = true, r.id = "10", r.hold = true;
      e->oneShot(r);
    }
    e->step(t += 33);
    const char* bubble = i >= 300 && i < 330 ? "Technical difficulties" : nullptr;
    const Strip& strip = f.attention.on ? asking : i % 50 < 25 ? working : Strip{};
    Surface& s = turns[i % 2];
    Box boxes[Surface::kMaxKeep];
    cardFrames += opaqueCards(s, *e, boxes) > 0;
    laneKeeps += s.laneKey && s.laneKey == laneKey(bubble, strip);
    const uint32_t cardKey = s.cardKey;
    paintFrame(s, *e, false, 0, bubble, {}, strip);
    cardKeeps += cardKey && s.cardKey == cardKey;
    knockKeeps += cardKey && s.cardKey == cardKey && e->scenes.envelope(e->timeMs(), kKnock) > 0;
    fresh.invalidate();
    paintFrame(fresh, *e, false, 0, bubble, {}, strip);
    if (std::memcmp(s.pixels, fresh.pixels, s.bytes()))
      TEST_FAIL_MESSAGE(("kept frame differs from a fresh one at " + std::to_string(i)).c_str());
  }
  TEST_ASSERT_TRUE(cardFrames > 100);
  TEST_ASSERT_TRUE(laneKeeps > 100);
  TEST_ASSERT_TRUE(cardKeeps > 100);
  TEST_ASSERT_TRUE(knockKeeps > 0);
}
// A still card a surface already shows isn't drawn again;
// its inside is what the surface kept. A surface that lost its pixels
// draws it whole.
static void test_a_still_card_is_drawn_once_into_each_surface() {
  constexpr int kW = 502, kH = 410;
  std::vector<uint16_t> pa(kW * kH), pb(pa.size());
  Surface turns[2] = {{kW, kH, pa.data()}, {kW, kH, pb.data()}};
  auto e = std::make_unique<Engine>();
  Facts f;
  f.base = SceneState::kWorking;
  f.attention = {true, "7", "claude", "boop", "Fix a test", 1};
  e->setFacts(f);
  uint32_t t = 0;
  int i = 0;
  // Until the card's faded in and its knocks are over: both surfaces show it.
  for (; i < 600 && !(turns[0].cardKey && turns[0].cardKey == turns[1].cardKey); ++i) {
    e->step(t += 33);
    paint(turns[i % 2], *e);
  }
  TEST_ASSERT_TRUE(turns[0].cardKey && turns[0].cardKey == turns[1].cardKey);
  // A pixel inside the card, under no label (its kept middle, left side).
  Box boxes[Surface::kMaxKeep];
  TEST_ASSERT_EQUAL(3, opaqueCards(turns[0], *e, boxes));
  const int x = boxes[1].x0 + 4, y = boxes[1].y0 + 2;
  Surface& s = turns[i % 2];
  const uint16_t card = s.pixels[y * kW + x];
  s.pixels[y * kW + x] = 0x1234;
  for (int n = 0; n < 2; ++n, ++i) {
    e->step(t += 33);
    paint(turns[i % 2], *e);
  }
  TEST_ASSERT_EQUAL_HEX16(0x1234, s.pixels[y * kW + x]);
  s.invalidate();
  for (int n = 0; n < 2; ++n, ++i) {
    e->step(t += 33);
    paint(turns[i % 2], *e);
  }
  TEST_ASSERT_EQUAL_HEX16(card, s.pixels[y * kW + x]);
}
// Shapes are drawn by coverage. The ink a shape leaves is its
// area, wherever it sits between pixels, so moving it a sixteenth of a pixel
// never makes it swell or shrink.
static double ink(const std::vector<uint16_t>& px) {
  double sum = 0;
  for (uint16_t v : px) sum += ((v >> 5) & 63) / 63.0;
  return sum;
}
static void test_polygons_cover_their_area_wherever_they_sit() {
  std::vector<uint16_t> px(502 * 410);
  double least = 1e9, most = 0;
  for (int offset = 0; offset < 32; ++offset) {
    std::fill(px.begin(), px.end(), 0);
    Surface s{502, 410, px.data()};
    Raster r{s};
    // A 40 × 30 pixel diamond: 600 pixels of area, its edges at every slope.
    const int x = 200 * 16 + offset, y = 150 * 16 + offset / 2;
    Point diamond[] = {{x, y - 15 * 16}, {x + 20 * 16, y}, {x, y + 15 * 16}, {x - 20 * 16, y}};
    r.polygon16(diamond, 4, 0xffff);
    const double area = ink(px);
    least = std::min(least, area), most = std::max(most, area);
  }
  TEST_ASSERT_TRUE(std::fabs((least) - (600)) <= 6);
  TEST_ASSERT_TRUE(std::fabs((most) - (600)) <= 6);
}
static void test_strokes_keep_their_width_and_blend_once() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  Raster r{s};
  // 40 pixels long, 3 wide: 120 pixels, plus two round caps of 1.5 pixels.
  for (int offset : {0, 5, 11}) {
    std::fill(px.begin(), px.end(), 0);
    Point line[] = {{100 * 16 + offset, 100 * 16 + offset}, {140 * 16 + offset, 100 * 16 + offset}};
    r.stroke16(line, 2, 3 * 16, 0xffff);
    TEST_ASSERT_TRUE(std::fabs((ink(px)) - (120 + 3.14159 * 1.5 * 1.5)) <= 4);
  }
  // A translucent stroke whose points crowd together still lays each pixel
  // down once: no pixel darker than the stroke's own opacity.
  std::fill(px.begin(), px.end(), 0);
  Point dense[64];
  for (int i = 0; i < 64; ++i) dense[i] = {200 * 16 + i * 4, 200 * 16 + (i % 3) * 2};
  r.alpha = 128;
  r.stroke16(dense, 64, 4 * 16, 0xffff);
  int most = 0;
  for (uint16_t v : px) most = std::max(most, int((v >> 5) & 63));
  TEST_ASSERT_TRUE(most <= 63 * 128 / 255 + 1);
}
// The body's outline is soft (its pixels take their share of
// the edge against the black), and nothing inside is: an outline edge
// wrongly found inside would show as a dark seam.
static void test_the_body_outline_is_soft_without_seams() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  PaintControls c;
  paint(s, c);
  auto lum = [&](int x, int y) { return int((px[y * 502 + x] >> 5) & 63); };
  int rows = 0, soft = 0;
  for (int y = 120; y < 300; ++y) {
    int first = -1;
    for (int x = 0; x < 502 && first < 0; ++x)
      if (px[y * 502 + x]) first = x;
    if (first < 0 || first + 4 >= 502) continue;
    ++rows;
    if (lum(first, y) < lum(first + 3, y) * 9 / 10) ++soft;
  }
  TEST_ASSERT_TRUE(rows > 100);
  TEST_ASSERT_TRUE(soft * 10 >= rows * 6);
  for (int y = 1; y < 327; ++y)
    for (int x = 1; x < 501; ++x) {
      int around = 0, inside = 1;
      for (int dy = -1; dy <= 1; ++dy)
        for (int dx = -1; dx <= 1; ++dx) {
          if (!px[(y + dy) * 502 + x + dx]) inside = 0;
          if (dx || dy) around += lum(x + dx, y + dy);
        }
      // Deep inside the body (its whole neighbourhood drawn and not the
      // outline's dim edge), a pixel is never under half its neighbours'.
      if (inside && around > 8 * 12) TEST_ASSERT_TRUE_MESSAGE(lum(x, y) * 8 * 2 >= around, "a seam inside the body");
    }
}
static void test_rgb565_opacity_rounds_to_nearest() {
  // Exact nearest rounding in RGB565 makes alpha 0..2 and
  // 253..255 identical to the endpoints even for the maximum channel delta.
  TEST_ASSERT_EQUAL_HEX16(0, mix565(0, 0xffff, 2));
  TEST_ASSERT_EQUAL_HEX16(0x0020, mix565(0, 0xffff, 3));
  TEST_ASSERT_EQUAL_HEX16(0xffdf, mix565(0, 0xffff, 252));
  TEST_ASSERT_EQUAL_HEX16(0xffff, mix565(0, 0xffff, 253));
  TEST_ASSERT_EQUAL_HEX16(0xffff, mix565(0xffff, 0, 2));
  TEST_ASSERT_EQUAL_HEX16(0, mix565(0xffff, 0, 253));
  TEST_ASSERT_EQUAL_HEX16(0x8410, mix565(0, 0xffff, 128));
  TEST_ASSERT_EQUAL_HEX16(0, mix565(0, 0xffff, -1));
  TEST_ASSERT_EQUAL_HEX16(0xffff, mix565(0, 0xffff, 256));
  // Independent scalar reference checks both packed lanes and every green
  // value/opacity; division by 255 is intentionally absent from the renderer.
  for (int from = 0; from < 64; ++from)
    for (int to = 0; to < 64; ++to)
      for (int a = 0; a < 256; ++a) {
        uint16_t old = ((from & 31) << 11) | (from << 5) | ((63 - from) & 31),
                 ink = ((to & 31) << 11) | (to << 5) | ((63 - to) & 31);
        auto channel = [&](int shift, int mask) {
          return ((((old >> shift) & mask) * (255 - a) + ((ink >> shift) & mask) * a + 127) / 255) << shift;
        };
        TEST_ASSERT_EQUAL_HEX16(channel(11, 31) | channel(5, 63) | channel(0, 31), mix565(old, ink, a));
      }
}
int main() {
  UNITY_BEGIN();
  RUN_TEST(test_fixed_math_and_motion);
  RUN_TEST(test_software_clock_matches_binary64);
  RUN_TEST(test_all_expressions_draw_inside_native_surface);
  RUN_TEST(test_frame_replay_is_byte_identical);
  RUN_TEST(test_one_face_vocabulary_and_latest_facts);
  RUN_TEST(test_request_identity_and_cache_bounds);
  RUN_TEST(test_grid_voice_lead_and_late_cues);
  RUN_TEST(test_external_source_holds_without_repeating_reveal);
  RUN_TEST(test_interrupted_alert_signals_exactly_once);
  RUN_TEST(test_face_and_props_move_without_jumps);
  RUN_TEST(test_gel_clips_use_the_shared_mixer);
  RUN_TEST(test_each_cue_carries_its_own_duck);
  RUN_TEST(test_pick_is_pure_and_started_commits_it);
  RUN_TEST(test_a_power_on_seeds_the_engine_and_a_reset_restores_53);
  RUN_TEST(test_timing_comes_from_the_recipe_table);
  RUN_TEST(test_comedy_plays_in_idle_and_asleep);
  RUN_TEST(test_each_gesture_plays_its_own_gag);
  RUN_TEST(test_occasions_play_only_while_they_fit);
  RUN_TEST(test_gel_draws_natively);
  RUN_TEST(test_reference_face_projection_and_pose_bounds);
  RUN_TEST(test_tracked_clear_matches_full_clear);
  RUN_TEST(test_histories_stay_off_the_heap);
  RUN_TEST(test_kept_cards_and_lanes_match_a_fresh_frame);
  RUN_TEST(test_a_still_card_is_drawn_once_into_each_surface);
  RUN_TEST(test_steady_frames_allocate_nothing);
  RUN_TEST(test_the_lane_is_native_and_tracked);
  RUN_TEST(test_rgb565_opacity_rounds_to_nearest);
  RUN_TEST(test_polygons_cover_their_area_wherever_they_sit);
  RUN_TEST(test_strokes_keep_their_width_and_blend_once);
  RUN_TEST(test_the_body_outline_is_soft_without_seams);
  return UNITY_END();
}
