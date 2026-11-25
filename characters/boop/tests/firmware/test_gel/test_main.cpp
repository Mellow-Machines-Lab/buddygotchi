// Complete integer engine, native surface bounds and face seam.
#include <unity.h>
#include <cmath>
#include <functional>
#include <vector>
#include <memory>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <set>
#include <string>
#include "render/gel/painter.h"
#include "render/helper.h"
#include "render/gel/geometry.h"
#include "render/gel/face.h"
#include "render/gel/hands.h"
#include "render/gel/invite.h"
#include "render/gel/moves.h"
#include "app/behaviour.h"
#include "render/gel/sounds.h"
#include "slime_mesh.h"
#include "app/device.h"
#include "linkkit/kit.h"
#include <new>
#include "render/gel/done.h"
#include "render/gel/lane.h"
#include "render/gel/layers.h"
#include "render/gel/raster.h"
#include "render/gel/stream.h"
#include "render/tags.h"
#include "fonts_gel.h"
#include "rig_tables.h"  // the staged pack's (characters/charactergen.py)
using namespace render;
using namespace render::gel;
// Heap allocations while `allocCounting` is on (test_steady_frames_allocate_nothing),
// and the bytes held at any moment (test_histories_stay_off_the_heap): each
// block carries its size in a 16-byte header.
bool allocCounting = false;  // test_drawer.cpp counts too
long allocCount = 0;
static long allocLive = 0;
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
              "history stores where a take is, not a full recipe copy");
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
  e->setMood(slime::kWounded);
  e->motion.impulse(false);
  for (int t = 0; t <= 640; t += 16) e->step(t);
  paint(sa, *e);
  paint(sb, *e);
  TEST_ASSERT_EQUAL_MEMORY(a.data(), b.data(), sa.bytes());
  e->face.scaled[2] = e->face.scaled[2] * q(.8);  // the eyes drawn less open
  paint(sb, *e);
  TEST_ASSERT_NOT_EQUAL(0, std::memcmp(a.data(), b.data(), sa.bytes()));
}
// The AMOLED's other core draws the body's lower rows (render/helper.h):
// however the rows are shared out, the frame is the same pixels as one
// core's. The stand-in runs each job at once, on a clock that makes the
// share move every frame.
static uint32_t helperClock = 0;
static void test_a_helper_draws_the_same_body() {
  std::vector<uint16_t> a(502 * 410), b(a.size());
  Surface sa{502, 410, a.data()}, sb{502, 410, b.data()};
  auto e = std::make_unique<Engine>();
  e->setMood(slime::kWounded);
  e->motion.impulse(false);
  {
    PaintControls c;
    c.lean = 900;
    render::helper = {};
    paint(sa, c);
    render::helper = {[](void (*job)(void*), void* arg) { job(arg); }, [] {},
                      [] { return helperClock += helperClock % 3 ? 7 : 1; }};
    paint(sb, c);
    render::helper = {};
    int diffs = 0, first = -1;
    for (size_t i = 0; i < a.size(); ++i)
      if (a[i] != b[i]) first = first < 0 ? int(i) : first, ++diffs;
    char msg[96];
    snprintf(msg, sizeof msg, "body-only diffs=%d first=(%d,%d)", diffs, first % 502, first / 502);
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, diffs, msg);
  }
  for (int t = 0; t <= 640; t += 16) {
    e->step(t);
    render::helper = {};
    paint(sa, *e);
    render::helper = {[](void (*job)(void*), void* arg) { job(arg); }, [] {},
                      [] { return helperClock += helperClock % 3 ? 7 : 1; }};
    paint(sb, *e);
    TEST_ASSERT_EQUAL_MEMORY(a.data(), b.data(), sa.bytes());
  }
  render::helper = {};
}
// The AMOLED reads the body's material from a copy in PSRAM
// (GelFace::readAssetsFrom): the same texels, the same frame. The material
// is 1025 × 513 texels over the sphere, under a pixel each across the
// dome's middle, then half that for where they crowd under a pixel; each
// kept down to ring 18 of 24, the lowest the camera sees: 385 and 193 rows.
static void test_the_materials_copy_draws_the_same_body() {
  static_assert(slime::kMaterialRings == 18 && slime::kMeshRings == 24, "the rings this test pins");
  size_t bytes = 0;
  GelFace face;
  const void* texels = face.assets(bytes);
  TEST_ASSERT_EQUAL_UINT32((1025u * 385u + 513u * 193u) * 2u, bytes);
  std::vector<uint16_t> copy(bytes / 2), a(502 * 410), b(a.size());
  std::memcpy(copy.data(), texels, bytes);
  Surface sa{502, 410, a.data()}, sb{502, 410, b.data()};
  PaintControls c;
  c.lean = 700;
  paint(sa, c);
  face.readAssetsFrom(copy.data());
  paint(sb, c);
  face.readAssetsFrom(nullptr);
  TEST_ASSERT_EQUAL_MEMORY(a.data(), b.data(), sa.bytes());
}
static void test_one_face_vocabulary_and_latest_facts() {
  linkkit::Rng rng;
  app::Behaviour b(std::make_unique<GelFace>());
  b.reset(0, rng);
  TEST_ASSERT_EQUAL_STRING("gel", b.face().name());
  app::Model m;
  m.mood = Mood::kWounded;
  m.base = SceneState::kWorking;
  m.act = SceneState::kWorking;
  b.onState(m, 0);
  app::ReactionIn in;
  in.anim = SceneState::kTaskComplete;
  in.outcome = Outcome::kFailure;
  in.id = 42;
  in.variant = b.pick(in.anim, m.mood, 255, in.outcome, rng);
  b.play(in, 0);
  b.advance(1504, rng);
  auto& e = static_cast<GelFace&>(b.face()).engine();
  TEST_ASSERT_TRUE(e.scenes.route.state == SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(e.scenes.route.outcome == Outcome::kFailure);
  m.act = SceneState::kTerminal;
  b.onState(m, 1600);
  b.advance(5008, rng);
  TEST_ASSERT_TRUE(e.scenes.route.state == SceneState::kTerminal);
  TEST_ASSERT_EQUAL_INT(slime::kWounded, e.emotion);
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
  TEST_ASSERT_TRUE(e->scenes.alert.key == showKey(Shows::kNeedsYou, 80));
}
// What the engine keeps of what showed (the alert and the reaction held,
// and the reveals' bounded history) is numbers inside the engine. A hundred
// distinct needs-you requests with long names and a hundred reactions leave
// the heap where it was; as strings they held about 25 KB of the board's
// internal RAM.
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
    r.anim = i % 2 ? SceneState::kPoked : SceneState::kTaskComplete;
    r.outcome = Outcome::kSuccess;
    e->play(r);
    for (int k = 0; k < 40; ++k) e->step(t += 16);
    e->clear();
  }
  TEST_ASSERT_TRUE(shows(e->scenes.alert.key) == Shows::kNeedsYou && shows(e->scenes.held.key) == Shows::kReaction);
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
  f.act = SceneState::kTerminal;
  e->setFacts(f);
  e->step(0);
  Request req;
  req.anim = SceneState::kTaskComplete;
  req.outcome = Outcome::kSuccess;
  req.variant = 0;
  e->play(req);
  int reveals = 0;
  for (int t = 16; t <= 6400; t += 16) {
    e->step(t);
    for (auto& cue : e->cues)
      if (cue.contact.kind == kSuccess) ++reveals;
  }
  TEST_ASSERT_EQUAL_INT(1, reveals);
  TEST_ASSERT_TRUE(e->scenes.route.state == SceneState::kTaskComplete);
  e->clear();
  TEST_ASSERT_TRUE(e->scenes.route.state == SceneState::kTerminal);
}
// A finished turn's marks (render/gel/done.h). The glow comes over
// kGlowInMs to kGlowPeak at the panel's edge (a reply's to kGlowPeakFaint),
// holds while its reaction plays, and fades over the last kGlowOutMs; it
// reaches kGlowPx in, and nothing shows past the panel's rounded corners.
static void test_a_finished_turn_glows() {
  static_assert(kGlowInMs == 300 && kGlowOutMs == 1000 && kGlowPx == 26, "the glow's timing and reach");
  static_assert(kGlowPeak == 200 && kGlowPeakFaint == 110, "the glow's strength at the edge");
  DoneShow d;
  d.agent = "claude", d.thread = "fix-nav", d.outcome = Outcome::kFailure;
  TEST_ASSERT_EQUAL_INT(0, doneGlow(d));  // just come
  d.ms = kGlowInMs;
  TEST_ASSERT_EQUAL_INT(kGlowPeak, doneGlow(d));
  d.ms = 9000;
  TEST_ASSERT_EQUAL_INT(kGlowPeak, doneGlow(d));  // holding while it plays
  d.leftMs = kGlowOutMs;
  TEST_ASSERT_EQUAL_INT(kGlowPeak, doneGlow(d));
  d.leftMs = kGlowOutMs / 2;
  TEST_ASSERT_INT_WITHIN(2, kGlowPeak / 2, doneGlow(d));
  d.leftMs = 0;
  TEST_ASSERT_EQUAL_INT(0, doneGlow(d));
  d.leftMs = -1, d.outcome = Outcome::kNone;
  TEST_ASSERT_EQUAL_INT(kGlowPeakFaint, doneGlow(d));
  TEST_ASSERT_EQUAL_INT(0, doneGlow(DoneShow{}));

  constexpr int kW = 502, kH = 410;
  std::vector<uint16_t> px(kW * kH);
  Surface s{kW, kH, px.data()};
  s.corner = 110;
  auto at = [&](int x, int y) { return px[size_t(y) * kW + x]; };
  auto lit = [&](int x0, int y0, int x1, int y1) {
    int n = 0;
    for (int y = y0; y < y1; ++y)
      for (int x = x0; x < x1; ++x) n += at(x, y) != 0;
    return n;
  };
  auto fresh = [&] { std::fill(px.begin(), px.end(), 0), s.invalidate(), s.clear(); };
  d.outcome = Outcome::kFailure;
  fresh();
  paintGlow(s, d, 0, kH);
  TEST_ASSERT_TRUE(at(kW / 2, 0) != 0 && at(0, kH / 2) != 0 && at(kW - 1, kH / 2) != 0 && at(kW / 2, kH - 1) != 0);
  // Nothing further in from the straight edges.
  TEST_ASSERT_EQUAL_INT(0, lit(kGlowPx, 110, kW - kGlowPx, kH - 110));
  TEST_ASSERT_EQUAL_INT(0, lit(110, kGlowPx + 1, kW - 110, kH - kGlowPx - 1));
  TEST_ASSERT_EQUAL_INT(0, at(0, 0) | at(kW - 1, 0) | at(0, kH - 1) | at(kW - 1, kH - 1));  // past the corners
  TEST_ASSERT_TRUE(at(40, 40) != 0);  // round the corner's arc
  // Only the rows asked for.
  fresh();
  paintGlow(s, d, 0, 300);
  TEST_ASSERT_EQUAL_INT(0, lit(0, 300, kW, kH));
}
// An alert interrupted before
// its knocks and ding resumes where it stopped, so each plays exactly once;
// one interrupted after them returns to its silent hold. Interrupted by
// listening or by a lost link, at any point from its start to well after.
static void test_interrupted_alert_signals_exactly_once() {
  for (int after : {0, 160, 320, 480, 640, 800, 1200, 2000}) {
    for (bool timeout : {false, true}) {
      auto e = std::make_unique<Engine>();
      e->step(0);
      Facts f;
      f.base = SceneState::kWorking;
      f.attention.on = true;
      f.attention.id = std::to_string(after);
      e->setFacts(f);
      int knocks = 0, reveals = 0, dings = 0;
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
      if (timeout)
        e->linkTimedOut(true);
      else
        e->play(mic);
      run(640);
      if (timeout)
        e->linkTimedOut(false);
      else
        e->clear();
      TEST_ASSERT_TRUE(e->scenes.route.state == SceneState::kNeedsYou);
      TEST_ASSERT_TRUE(e->scenes.quietRestored);
      run(4800);
      TEST_ASSERT_EQUAL_INT(e->scenes.recipe.count - 1, knocks);  // the knock's, then its ding
      TEST_ASSERT_EQUAL_INT(1, reveals);
      TEST_ASSERT_EQUAL_INT(1, dings);
    }
  }
}
// From every face to every other (the 24: the Mac's 18 and the six
// meme faces) the two arts cross over, their weights summing to one, each stepping no more
// than a slice of the shortest face window's ramp, the new one last; each
// drawn ratio stays inside (0.75, 4/3) and moves its drawn size no further
// than its control; a retarget keeps the controls' velocity, and a fifth art
// drops the faintest; and the alert
// sign ramps in and out with no step larger than a slice of its ramp.
static void test_face_and_props_move_without_jumps() {
  const F weightStep = q(.149), rampStep = q(.134);
  const int controls[] = {2, 4, 5};
  TEST_ASSERT_EQUAL_INT(24, slime::kCanonical);
  for (int i = 0; i < slime::kCanonical * slime::kCanonical; ++i) {
    const int from = i / slime::kCanonical, to = i % slime::kCanonical;
    if (from == to) continue;
    auto e = std::make_unique<Engine>();
    e->setMood(from);
    for (uint32_t t = 0; t <= 640; t += 16) e->step(t);
    e->setMood(to);
    SemanticFace before = e->face;
    bool crossed = false;
    for (uint32_t t = 656; t <= 1280; t += 16) {
      e->step(t);
      const auto& f = e->face;
      TEST_ASSERT_EQUAL_INT(to, f.current().art);
      crossed |= f.count == 2;
      F sum = 0;
      for (int k = 0; k < f.count; ++k) {
        const auto& l = f.layers[k];
        sum += l.weight;
        const auto ratio = f.ratios(l);
        for (const F r : ratio) TEST_ASSERT_TRUE(r > q(.75) - q(.0001) && r < q(4.0 / 3) + q(.0001));
        for (int j = 0; j < before.count; ++j) {
          const auto& was = before.layers[j];
          if (was.art != l.art) continue;
          TEST_ASSERT_TRUE(abs(l.weight - was.weight) <= weightStep);
          const auto wasRatio = before.ratios(was);
          for (int r = 0; r < 3; ++r) {
            const int c = controls[r];
            TEST_ASSERT_TRUE(abs(ratio[r] - wasRatio[r]) * slime::kProfile[l.art].face[c] <=
                             abs(f.controls[c] - before.controls[c]) + q(.00001));
          }
        }
      }
      TEST_ASSERT_TRUE(abs(sum - 1) <= q(.0001));
      before = f;
    }
    TEST_ASSERT_TRUE(crossed);
    TEST_ASSERT_EQUAL_INT(1, e->face.count);
  }
  SemanticFace face;
  face.setMood(slime::kWounded);
  for (int i = 0; i < 3; ++i) face.advance(T::ratio(16, 1000));
  const F moving = face.velocity[2];
  TEST_ASSERT_TRUE(abs(moving) > q(.01));
  face.setMood(slime::kHappy);
  TEST_ASSERT_TRUE(face.velocity[2] == moving);
  // A fifth art within one window drops the faintest of the four; the
  // others keep their order, and their shares grow to fill what it leaves.
  face.advance(T::ratio(16, 1000));
  face.setMood(slime::kSad);
  face.advance(T::ratio(16, 1000));
  TEST_ASSERT_EQUAL_INT(SemanticFace::kMaxLayers, face.count);
  const SemanticFace four = face;
  int faintest = 0;
  for (int i = 1; i < four.count; ++i)
    if (four.layers[i].weight < four.layers[faintest].weight) faintest = i;
  face.setMood(slime::kAngry);
  TEST_ASSERT_EQUAL_INT(SemanticFace::kMaxLayers, face.count);
  TEST_ASSERT_EQUAL_INT(slime::kAngry, face.current().art);
  for (int i = 0, k = 0; i < four.count; ++i) {
    if (i == faintest) continue;
    TEST_ASSERT_EQUAL_INT(four.layers[i].art, face.layers[k].art);
    TEST_ASSERT_TRUE(abs(face.layers[k++].weight - four.layers[i].weight / (F(1) - four.layers[faintest].weight)) <=
                     q(.0001));
  }
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
      if (t == 1600)
        e->clear();
      else
        e->play(mic);
    }
    e->step(t);
    F now = e->scenes.visible(Scenes::kAlertProp, e->timeMs());
    TEST_ASSERT_TRUE(abs(now - last) <= rampStep);
    seen |= now > q(.99);
    last = now;
  }
  TEST_ASSERT_TRUE(seen);
}
// Falling asleep, the awake face squashes shut on sleep's slow spring
// (frequency 4): its eyes to lines and its mouth to the sleeping one's
// size, the same art, no other drawn; once it's 0.9 shut, about a second
// on, the sleeping face crosses in over 360 ms, and it's alone by 1.35 s.
// The controls keep sleep's spring until it wakes, a mood changing
// meanwhile changing nothing drawn. Waking is quick: the face's own window
// and spring (180 ms, frequency 20), its eyes opening from lines, to the
// mood it has then; woken before it's a line, the same art opens again.
static void test_it_falls_asleep_squashing_shut() {
  static_assert(SemanticFace::kFaceMs == 180 && SemanticFace::kFaceFrequency == 20, "the face's window and spring");
  static_assert(SemanticFace::kSleepFrequency == 4 && SemanticFace::kSwapMs == 360, "falling asleep's spring and swap");
  static_assert(SemanticFace::kShutLine == q(.9), "the sleeping face comes in once it's a line");
  const T frame = T::ratio(16, 1000);
  SemanticFace f;
  f.setMood(slime::kHappy);
  for (int i = 0; i < 30; ++i) f.advance(frame);
  TEST_ASSERT_EQUAL_INT(1, f.count);
  f.setSleeping(true);
  TEST_ASSERT_EQUAL_INT(1, f.count);  // nothing drawn changes at once
  double x = 0, v = 0;                // the shut spring, in doubles
  F lastEye = 1, lastMouth = 1;
  SemanticFace still;
  int swapped = -1, alone = -1;
  for (int i = 1; i <= 160; ++i) {
    f.advance(frame);
    for (double left = .016; left > 1e-12;) {
      const double h = std::min(left, 1.0 / 240);
      v += (16 * (1 - x) - 8 * v) * h;
      x += v * h;
      left -= h;
    }
    TEST_ASSERT_TRUE(std::abs(x - double(f.shut.x.raw) / F::scale) < 1e-4);
    if (swapped < 0 && f.current().sleeping) swapped = i;
    if (swapped < 0) {
      // Still the happy art alone, squashing: each frame no larger than the last.
      TEST_ASSERT_TRUE(f.count == 1 && f.current().art == slime::kHappy);
      const auto r = f.ratios(f.current());
      TEST_ASSERT_TRUE(r[0] <= lastEye && r[1] <= lastMouth && r[2] <= q(1));
      lastEye = r[0], lastMouth = r[1];
    }
    if (alone < 0 && swapped > 0 && f.count == 1) alone = i;
    if (i > 15) {
      still.advance(frame);
      TEST_ASSERT_TRUE(still.controls == f.controls && still.velocity == f.velocity && still.shut.x == f.shut.x);
    }
    if (i == 15) {  // 240 ms in, a mood changing changes nothing drawn
      still = f;
      f.setMood(slime::kSad);
    }
  }
  // The line by 0.95 to 1 s: the eyes no thinner than the sleeping lids'
  // pen and near it, the mouth under two fifths of its size and going to the
  // sleeping one's; the sleeping face alone 360 ms on.
  TEST_ASSERT_TRUE(swapped * 16 >= 950 && swapped * 16 <= 1000);
  const F line = SemanticFace::kLineHalf / slime::kProfile[slime::kHappy].face[2];
  TEST_ASSERT_TRUE(lastEye >= line && lastEye < line + q(.06) && lastMouth < q(.4));
  TEST_ASSERT_TRUE(alone - swapped >= 360 / 16 && alone - swapped <= 360 / 16 + 1);
  TEST_ASSERT_TRUE(f.current().sleeping);
  f.setSleeping(false);
  TEST_ASSERT_TRUE(f.durationMs == T(SemanticFace::kFaceMs));
  TEST_ASSERT_EQUAL_INT(slime::kSad, f.current().art);
  const auto opening = f.ratios(f.current());
  // Its eyes come in as lines, and open within a quarter of a second.
  TEST_ASSERT_TRUE(opening[0] < SemanticFace::kLineHalf / slime::kProfile[slime::kSad].face[2] + q(.01));
  for (int i = 0; i < 16; ++i) f.advance(frame);
  TEST_ASSERT_TRUE(f.count == 1 && !f.current().sleeping && f.shut.x < q(.05));
  // Woken before it's a line, the same art opens again, nothing crossing.
  SemanticFace early;
  for (int i = 0; i < 30; ++i) early.advance(frame);
  early.setSleeping(true);
  for (int i = 0; i < 40; ++i) early.advance(frame);
  TEST_ASSERT_TRUE(early.count == 1 && !early.current().sleeping);
  early.setSleeping(false);
  for (int i = 0; i < 30; ++i) {
    early.advance(frame);
    TEST_ASSERT_TRUE(early.count == 1 && early.current().art == slime::kCalm);
  }
  TEST_ASSERT_TRUE(early.shut.x < q(.01));
}
// A weight held at zero is flat there (the Hermite's): an art going out
// fast, into a longer window (460 ms), dips below zero and comes
// back up toward it, and a retarget then doesn't bring it back.
static void test_a_faded_art_never_comes_back() {
  const T frame = T::ratio(16, 1000);
  SemanticFace f;
  f.setMood(slime::kHappy);
  for (int i = 0; i < 6; ++i) f.advance(frame);
  f.setMood(slime::kSad, 460);
  for (int i = 0; i < 24; ++i) f.advance(frame);
  auto calm = [&] {
    for (int i = 0; i < f.count; ++i)
      if (f.layers[i].art == slime::kCalm && !f.layers[i].sleeping) return &f.layers[i];
    return static_cast<SemanticFace::Layer*>(nullptr);
  };
  TEST_ASSERT_NOT_NULL(calm());
  TEST_ASSERT_TRUE(calm()->weight == F(0));
  f.setMood(slime::kAngry);
  for (int i = 0; i < 12; ++i) {
    f.advance(frame);
    TEST_ASSERT_NULL(calm());
  }
}
// The face's visible ink in a frame: the pixels its art takes at least a
// quarter of the way from the body's luminance to the ink's, against the
// same frame with no art drawn. Fainter than that, a fading art's ghost
// and the antialiased edges don't count; the paler features (a water eye's
// fill, the cheeks, the tears) are lighter than the body and never do.
static int faceInk(const Engine& e, Surface& drawn, Surface& bare) {
  auto lum = [](uint16_t p) {
    const int r = ((p >> 11) & 31) * 255 / 31, g = ((p >> 5) & 63) * 255 / 63, b = (p & 31) * 255 / 31;
    return (77 * r + 150 * g + 29 * b) >> 8;
  };
  const int ink = lum(rgb565(13, 43, 72));
  paint(drawn, e);
  auto none = std::make_unique<Engine>(e);
  for (int i = 0; i < none->face.count; ++i) none->face.layers[i].weight = 0;
  paint(bare, *none);
  int count = 0;
  for (int i = 0; i < drawn.width * drawn.height; ++i) {
    const int body = lum(bare.pixels[i]), room = body - ink;
    if (room > 0 && (body - lum(drawn.pixels[i])) * 4 >= room) ++count;
  }
  return count;
}
// The face never fades. Through a cross-fade between differently shaped
// arts, in frames 40 ms apart, the eyes and the mouth keep at least 90% of
// the visible ink of the fainter of the two faces settled; falling asleep,
// that's its swap from the lines the awake face squashed to into the
// sleeping face's lids. Each look is laid over the body alone and the two
// blended (CrossFade), so where both ink a pixel none of the body shows
// through: the least now is 92%, waking (falling asleep 97%; calm to happy,
// happy to sad and calm to wounded never less than the fainter face).
static void test_the_face_never_fades_while_arts_cross_over() {
  std::vector<uint16_t> a(502 * 410), b(a.size());
  Surface drawn{502, 410, a.data()}, bare{502, 410, b.data()};
  struct Case {
    int from, to;
    SceneState base, then;
  } cases[] = {{slime::kCalm, slime::kHappy, SceneState::kIdle, SceneState::kIdle},
               {slime::kHappy, slime::kSad, SceneState::kIdle, SceneState::kIdle},
               // wounded's thin tears
               {slime::kCalm, slime::kWounded, SceneState::kIdle, SceneState::kIdle},
               // falling asleep, and waking
               {slime::kCalm, slime::kCalm, SceneState::kIdle, SceneState::kAsleep},
               {slime::kCalm, slime::kCalm, SceneState::kAsleep, SceneState::kIdle}};
  for (const auto& c : cases) {
    auto e = std::make_unique<Engine>();
    Facts f;
    f.base = c.base;
    e->setFacts(f);
    e->setMood(c.from);
    // Asleep settles once its face is the sleeping one, alone.
    uint32_t t = 0;
    for (; t <= (c.base == SceneState::kAsleep ? 2000u : 640u); t += 40) e->step(t);
    int start = faceInk(*e, drawn, bare);
    f.base = c.then;
    e->setFacts(f);
    e->setMood(c.to);
    int least = 1 << 30;
    bool crossed = false;
    for (int frame = 0; frame < 60 && !(crossed && e->face.count == 1); ++frame) {
      e->step(t += 40);
      if (e->face.count == 1) {
        if (!crossed) start = faceInk(*e, drawn, bare);  // the face it crosses from: the line, falling asleep
        continue;
      }
      TEST_ASSERT_TRUE(e->blink() == F(0));  // the eyes open throughout: no blink comes before 2.8 s
      least = std::min(least, faceInk(*e, drawn, bare)), crossed = true;
    }
    TEST_ASSERT_TRUE(crossed);
    TEST_ASSERT_EQUAL_INT(1, e->face.count);
    const int fainter = std::min(start, faceInk(*e, drawn, bare));
    TEST_ASSERT_TRUE(fainter > 200);  // the line, falling asleep; else over 400
    TEST_ASSERT_TRUE(least * 100 >= fainter * 90);
  }
}
// Nothing on the face flickers as moods cross over: a face that comes in
// at weight zero draws nothing, and moves nothing it shares with the faces
// already there to its own turn in the draw order. Pins changes like those
// where it once did, for a frame (32 to 630 pixels of the mouth and
// tears), and two that never did.
static void test_a_face_coming_in_moves_nothing() {
  std::vector<uint16_t> a(502 * 410), b(a.size());
  Surface with{502, 410, a.data()}, without{502, 410, b.data()};
  const int changes[][2] = {{slime::kPleased, slime::kAffectionate}, {slime::kSad, slime::kWounded},
                            {slime::kWounded, slime::kSad},          {slime::kLonely, slime::kWounded},
                            {slime::kCalm, slime::kHappy},           {slime::kHappy, slime::kSad}};
  std::string report;
  int worst = 0;
  for (const auto& change : changes) {
    auto e = std::make_unique<Engine>();
    e->setMood(change[0]);
    uint32_t t = 0;
    for (; t <= 1200; t += 40) e->step(t);
    const int before = e->face.count;
    e->setMood(change[1]);
    // The face coming in, as it's added: its weight all but nothing.
    while (e->face.count == before && t < 3000) e->step(t += 1);
    TEST_ASSERT_TRUE(e->face.count > before);
    paint(with, *e);
    auto gone = std::make_unique<Engine>(*e);
    gone->face.count -= 1;  // as it was, the new face not yet added
    paint(without, *gone);
    int differ = 0;
    for (int i = 0; i < 502 * 410; ++i) differ += a[i] != b[i];
    // And as the face it crossed from goes, at its weight's last: the frame
    // is the one without it, to within that last bit of weight.
    std::unique_ptr<Engine> last;
    for (int count = e->face.count; e->face.count >= count && t < 6000;) {
      last = std::make_unique<Engine>(*e);
      count = e->face.count;
      e->step(t += 1);
    }
    paint(with, *last);
    auto left = std::make_unique<Engine>(*last);
    for (int i = 1; i < left->face.count; ++i) left->face.layers[i - 1] = left->face.layers[i];
    left->face.count -= 1;
    paint(without, *left);
    int leaving = 0;
    for (int i = 0; i < 502 * 410; ++i)
      leaving += std::abs(int(a[i] >> 11) - int(b[i] >> 11)) > 1 ||
                 std::abs(int(a[i] >> 5 & 63) - int(b[i] >> 5 & 63)) > 2 || std::abs(int(a[i] & 31) - int(b[i] & 31)) > 1;
    report += std::to_string(change[0]) + "->" + std::to_string(change[1]) + ":" + std::to_string(differ) + "/" +
              std::to_string(leaving) + " ";
    worst = std::max({worst, differ, leaving});
  }
  TEST_ASSERT_EQUAL_INT_MESSAGE(0, worst, report.c_str());
}
// No prop pops: the lane's strip eases in as it comes and out
// as it goes, at the opacity Behaviour gives it on the rig's ramp, which is
// the props' (app/behaviour.h, pinned in test_behaviour), and the same
// whatever the draw cadence: a board drawing every 16 ms and one drawing
// every 200 ms show the same lane wherever both draw, mid-fade and settled,
// its strip coming and going between their frames.
static void test_the_lane_fades_whatever_the_draw_cadence() {
  static_assert(rig::kFadeMs == uint32_t(kPropRampMs), "the lane fades on the props' ramp");
  constexpr int kW = 502, kH = 410, kLane = kH * 4 / 5;
  struct Run {
    linkkit::Rng rng;
    app::Behaviour b{std::make_unique<GelFace>()};
    std::vector<uint8_t> canvas = std::vector<uint8_t>(size_t(kWidth) * kHeight);
    std::vector<uint16_t> px = std::vector<uint16_t>(size_t(kW) * kH);
    Surface s{kW, kH, px.data()};
    std::vector<std::vector<uint16_t>> lanes;
    void play(uint32_t every) {
      b.reset(0, rng);
      Canvas c{canvas.data()};
      const uint32_t messages[] = {1100, 2300}, shots[] = {1200, 1600, 2400, 2800};
      int next = 0;
      bool dirty = true;
      for (uint32_t t = 0; t <= 2800; t += every) {
        for (; next < 2 && messages[next] <= t; ++next) {
          app::Model m;
          m.busy = next == 0 ? 2 : 0;
          b.advance(messages[next], rng);
          b.onState(m, messages[next]);
          dirty = true;
        }
        b.advance(t, rng);
        b.face().draw(c, &s, b.show(t), t, b.bubble(t), b.caption(t), b.sign(t), b.done(t), b.strip(t), dirty);
        dirty = false;
        for (uint32_t shot : shots)
          if (shot == t) lanes.emplace_back(px.begin() + kLane * kW, px.end());
      }
    }
  };
  auto lit = [](const std::vector<uint16_t>& lane) {
    long n = 0;
    for (uint16_t p : lane) n += (p >> 11) + (p >> 5 & 63) / 2 + (p & 31);
    return n;
  };
  auto often = std::make_unique<Run>(), seldom = std::make_unique<Run>();
  often->play(16);
  seldom->play(200);
  TEST_ASSERT_EQUAL(4, int(often->lanes.size()));
  for (int i = 0; i < 4; ++i) TEST_ASSERT_TRUE(often->lanes[i] == seldom->lanes[i]);
  const long whole = lit(often->lanes[1]);
  TEST_ASSERT_TRUE(whole > 1000);
  TEST_ASSERT_INT_WITHIN(whole / 10, whole / 2, lit(often->lanes[0]));  // fading in
  TEST_ASSERT_INT_WITHIN(whole / 10, whole / 2, lit(often->lanes[2]));  // fading out
  TEST_ASSERT_EQUAL(0, lit(often->lanes[3]));
}
// The face brings its own clips; the shared mixer plays
// whatever samples it's handed, whichever face is built.
static void test_gel_clips_use_the_shared_mixer() {
  GelFace face;
  const voice::EffectClips& clips = face.clips();
  // The nine sketches the board names, three takes each: the contacts',
  // comedy's sneeze and snore breath, and a big finish's cheer; the rest of
  // the design's sketches aren't baked.
  TEST_ASSERT_EQUAL_INT(27, clips.count());
  TEST_ASSERT_EQUAL_STRING("gel-sketch-v1", clips.version());
  TEST_ASSERT_EQUAL_INT(clips.index("knock-2"), clipFor("knock", 2));
  TEST_ASSERT_EQUAL_INT(-1, clipFor("knock", 3));
  TEST_ASSERT_EQUAL_INT(-1, clipFor("knoc", 0));
  for (const char* recipe : {"knock", "squish", "ding", "complete", "failed", "sneeze", "breath", "bounce", "cheer"})
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
// The invite (render/gel/invite.h): the gel draws them; every pose and
// payoff is the pack's clip (render/gel/moves.h), nothing in code: the
// palm and the lean each up at the glass whole as it waits, the palm the
// right hand open and flat on it, the lean's cheek a patch on it; the back
// turned half way round, away from the glass. The high five spins all the
// way round and the sigh comes round from the back; a late one's payoff
// waits for its turn round; the XP shows low only while a payoff that
// earns plays.
static void test_the_gel_draws_invites() {
  using rig::Channel;
  GelFace f;
  TEST_ASSERT_TRUE(f.drawsInvites());
  TEST_ASSERT_FALSE(inviteMove(InviteShow{}).on());
  for (InvitePose p : {InvitePose::kPalm, InvitePose::kLean, InvitePose::kBack}) {
    InviteShow v;
    v.phase = InviteShow::kPose, v.pose = p, v.ms = 2000;
    const MoveShow m = inviteMove(v);
    TEST_ASSERT_TRUE(m.on());
    rig::Channels ch = rig::kRest;
    addMove(ch, m);
    PaintControls held;
    applyRig(held, ch);
    TEST_ASSERT_EQUAL_INT(p == InvitePose::kBack ? 0 : 4096, held.glass);
    TEST_ASSERT_EQUAL_INT(p == InvitePose::kBack ? -2048 : 0, held.turn);  // its back to you: half a turn, to its left
    TEST_ASSERT_EQUAL_INT(p == InvitePose::kLean, held.patch > 0);
    TEST_ASSERT_EQUAL_INT(p == InvitePose::kPalm ? 1000 : 0, ch[Channel::kHandRGlass]);
    TEST_ASSERT_EQUAL_INT(p == InvitePose::kPalm ? 1000 : 0, ch[Channel::kHandRShape]);
    TEST_ASSERT_FALSE(inviteSign(v).shows());
  }
  // Waiting with its back to you, it looks over its shoulder, its face
  // part way back round, and turns its back again.
  InviteShow back;
  back.phase = InviteShow::kPose, back.pose = InvitePose::kBack;
  const uint32_t in = inviteMove(back).clip->ms;
  int nearest = -1000;
  for (uint32_t ms = in; ms < in + 4000; ms += 50) {
    back.ms = ms;
    rig::Channels ch = rig::kRest;
    addMove(ch, inviteMove(back));
    nearest = std::max(nearest, int(ch[Channel::kTurn]));
  }
  TEST_ASSERT_TRUE(nearest < -200 && nearest > -300);
  // The miss and the payoffs have clips of their own.
  InviteShow v;
  v.pose = InvitePose::kPalm, v.payoff = InvitePayoff::kHighFive, v.phase = InviteShow::kShrug;
  TEST_ASSERT_EQUAL_STRING("invite-palm-miss", inviteMove(v).clip->id);
  v.phase = InviteShow::kPayoff;
  TEST_ASSERT_EQUAL_STRING("invite-highfive", inviteMove(v).clip->id);
  TEST_ASSERT_EQUAL_INT(0, sinceHit(inviteMove(v)));  // the clap hits the glass as it starts
  v.ms = InviteShow::kPayoffMs;
  rig::Channels spun = rig::kRest;
  addMove(spun, inviteMove(v));
  TEST_ASSERT_EQUAL_INT(1000, spun[Channel::kTurn]);  // the spin: all the way round
  v.pose = InvitePose::kBack, v.payoff = InvitePayoff::kSigh, v.ms = 0;
  TEST_ASSERT_EQUAL_STRING("invite-sigh", inviteMove(v).clip->id);
  v.phase = InviteShow::kShrug;
  TEST_ASSERT_EQUAL_STRING("invite-back-miss", inviteMove(v).clip->id);
  for (InviteShow::Phase phase : {InviteShow::kPayoff, InviteShow::kShrug}) {
    v.phase = phase, v.ms = phase == InviteShow::kPayoff ? InviteShow::kPayoffMs : InviteShow::kShrugMs;
    rig::Channels round = rig::kRest;
    addMove(round, inviteMove(v));
    TEST_ASSERT_EQUAL_INT(-1000, round[Channel::kTurn]);  // round to you, on the way it turned
  }
  InviteShow late;
  late.phase = InviteShow::kLate, late.pose = InvitePose::kPalm, late.payoff = InvitePayoff::kHighFive, late.xp = 3,
  late.ms = InviteShow::kTurnMs - 1;
  TEST_ASSERT_EQUAL_STRING("invite-palm-late", inviteMove(late).clip->id);
  TEST_ASSERT_EQUAL_INT(-1, payoffAge(late));
  TEST_ASSERT_FALSE(inviteSign(late).shows());
  late.ms = InviteShow::kTurnMs + 100;
  TEST_ASSERT_EQUAL_STRING("invite-highfive", inviteMove(late).clip->id);
  TEST_ASSERT_EQUAL_INT(100, payoffAge(late));
  TEST_ASSERT_EQUAL_INT(3, inviteSign(late).xp);
  late.xp = 0;
  TEST_ASSERT_FALSE(inviteSign(late).shows());
  late.pose = InvitePose::kBack, late.payoff = InvitePayoff::kSigh, late.ms = 0;
  TEST_ASSERT_EQUAL_STRING("invite-back-late", inviteMove(late).clip->id);
}

// The glass (render/gel/painter.h): the rig's glass brings the body up to
// it, 1.15 its size at the whole and never more, about where it stands,
// over a finish's own scale; with none, it's its own size.
static void test_the_glass_scales_the_body_to_115_at_most() {
  const Surface s{502, 410, nullptr, 110};
  PaintControls c;
  applyGlass(c, s);
  TEST_ASSERT_EQUAL_INT(4096, c.scale);
  rig::Channels ch = rig::kRest;
  ch[rig::Channel::kGlass] = 1000;
  applyRig(c, ch);
  applyGlass(c, s);
  TEST_ASSERT_EQUAL_INT(4096 + kGlassScale, c.scale);
  TEST_ASSERT_TRUE(c.scale * 100 <= 4096 * 115);  // 1.15 at most
  TEST_ASSERT_EQUAL_INT(finishAnchor(s).y, c.anchorY);
  PaintControls finish;
  finish.scale = 3440, finish.anchorX = 7, finish.anchorY = 9, finish.glass = 2048;
  applyGlass(finish, s);
  TEST_ASSERT_EQUAL_INT(3440 * (4096 + kGlassScale / 2) / 4096, finish.scale);
  TEST_ASSERT_EQUAL_INT(9, finish.anchorY);  // a finish's own anchor kept
}

// The one pair of hands (render/gel/hands.h): a hand at size 0 draws
// nothing; a hand is a disk of its radius (its shadow a little past it),
// on the glass kHandGlassGrow bigger, a palm about 85 px across at the
// body's glass scale; the rig's hand sits from the body's front, at its
// scale; and each frame's plan lets only the part that has a hand draw it.
static void test_one_pair_of_hands() {
  static uint16_t px[502 * 410];
  Surface s{502, 410, px, 110};
  auto drawn = [&](const Hand& h) {
    std::fill(std::begin(px), std::end(px), 0);
    Raster r{s};
    paintHand(r, h);
    int x0 = 1 << 30, x1 = -1;
    for (int y = 0; y < 410; ++y)
      for (int x = 0; x < 502; ++x)
        if (px[y * 502 + x]) x0 = std::min(x0, x), x1 = std::max(x1, x);
    return x1 < 0 ? 0 : x1 - x0 + 1;
  };
  Hand none;
  TEST_ASSERT_EQUAL_INT(0, drawn(none));
  Hand ball;
  ball.x16 = 200 * 16, ball.y16 = 150 * 16, ball.radius16 = kHandPx * 16;
  const int across = drawn(ball);
  TEST_ASSERT_TRUE(across >= 2 * kHandPx && across <= 2 * kHandPx + 6);
  Hand palm = ball;
  palm.shape = 4096, palm.glass = 4096;
  palm.radius16 = kHandPx * 16 * 870 / 1000 * (4096 + kGlassScale) / 4096;
  TEST_ASSERT_EQUAL_INT(palm.radius16 * 5 / 2, palm.drawn16());
  const int wide = drawn(palm);
  TEST_ASSERT_TRUE(wide >= 80 && wide <= 96);  // about 85 px across
  rig::Anchors at;
  at.handF = {251 * 16, 300 * 16};
  rig::Channels ch = rig::kRest;
  TEST_ASSERT_FALSE(fromRig(ch, at, 1, 4096).shown());  // hidden in the body at rest
  ch[rig::Channel::kHandRSize] = 1000, ch[rig::Channel::kHandRX] = 85, ch[rig::Channel::kHandRY] = 85;
  const Hand right = fromRig(ch, at, 1, 4096);
  TEST_ASSERT_EQUAL_INT((251 + 128) * 16, right.x16);  // a body unit right and up
  TEST_ASSERT_EQUAL_INT((300 - 128) * 16, right.y16);
  TEST_ASSERT_EQUAL_INT(kHandPx * 16, right.radius16);
  TEST_ASSERT_FALSE(fromRig(ch, at, 0, 4096).shown());
  HandsPlan plan;
  TEST_ASSERT_TRUE(plan.has(-1, HandsAt::kSign) && plan.has(1, HandsAt::kDesk));  // alone, each draws its own
  plan.at[0] = HandsAt::kMove, plan.at[1] = HandsAt::kDesk;
  TEST_ASSERT_FALSE(plan.has(-1, HandsAt::kDesk));
  TEST_ASSERT_TRUE(plan.has(-1, HandsAt::kMove) && plan.has(1, HandsAt::kDesk));
  TEST_ASSERT_FALSE(plan.has(1, HandsAt::kSign));
}

// The knock (render/gel/moves.h, slimegen's scenes.mjs `knock`): one move
// for every mood and take, its knocks the clip's cues and the ding after
// them; it climbs at slime::kKnockClimbAtMs, after the knock ('follows')
// or at its end ('replaces'), and the needs-you scene lasts until the
// climb is over, so a needs-you come back to never climbs twice.
static void test_the_knock_is_one_move_that_climbs() {
  const rig::Clip* knock = rig::kRig.clip("knock");
  const rig::Clip* climb = rig::kRig.clip("knock-climb");
  TEST_ASSERT_NOT_NULL(knock);
  TEST_ASSERT_NOT_NULL(climb);
  TEST_ASSERT_TRUE(slime::kKnockClimbAtMs >= knock->ms);
  const int row = rowOf(SceneState::kNeedsYou);
  const slime::Recipe first = take(0, row, 0);
  for (int p = 0; p < slime::kProfiles; ++p)
    for (int v = 0; v < 3; ++v) {
      const slime::Recipe r = take(p, row, v);
      TEST_ASSERT_EQUAL_INT(F(first.duration).integer(), F(r.duration).integer());
      TEST_ASSERT_EQUAL_INT(first.count, r.count);
      for (int i = 0; i < r.count; ++i) TEST_ASSERT_EQUAL_INT(F(first.contacts[i].at).integer(), F(r.contacts[i].at).integer());
    }
  TEST_ASSERT_EQUAL_INT(int(slime::kKnockClimbAtMs + climb->ms), F(first.duration).integer());
  int knocks = 0;
  for (int i = 0; i < first.count; ++i)
    if (first.contacts[i].kind == kKnock) {
      TEST_ASSERT_EQUAL_INT(int(knock->cues[knocks].ms), F(first.contacts[i].at).integer());
      ++knocks;
    }
  TEST_ASSERT_EQUAL_INT(knock->cues.count, knocks);
  TEST_ASSERT_EQUAL_INT(kAlert, first.contacts[first.count - 1].kind);

  auto e = std::make_unique<Engine>(1);
  Facts f;
  f.base = SceneState::kWorking;
  f.attention = {true, "4", "claude", "boop", "", 0, AttnKind::kApprove};
  e->setFacts(f);
  uint32_t now = 0;
  auto at = [&](uint32_t ms) {
    while (now < ms) e->step(now = std::min(ms, now + 16));
    return currentMove(*e);
  };
  TEST_ASSERT_EQUAL_STRING("knock", at(1000).clip->id);
  TEST_ASSERT_FALSE(at(1000).sounds);  // its scene sounds the knock
  TEST_ASSERT_FALSE(at(slime::kKnockClimbAtMs - 100).on() && slime::kKnockClimbAtMs > knock->ms + 100);
  const MoveShow climbing = at(slime::kKnockClimbAtMs + 600);
  TEST_ASSERT_EQUAL_STRING("knock-climb", climbing.clip->id);
  TEST_ASSERT_TRUE(climbing.sounds);  // the face sounds the climb
  rig::Channels ch = rig::kRest;
  addMove(ch, at(slime::kKnockClimbAtMs + 3000));
  TEST_ASSERT_TRUE(ch[rig::Channel::kHandLSize] > 0 && ch[rig::Channel::kHandRSize] > 0);  // both fists
  TEST_ASSERT_TRUE(ch[rig::Channel::kHandLShape] < 0 && ch[rig::Channel::kHandRShape] < 0);
  ch = rig::kRest;
  addMove(ch, at(slime::kKnockClimbAtMs + 6000));
  TEST_ASSERT_TRUE(ch[rig::Channel::kPatch] > 0 && ch[rig::Channel::kPatchY] > 500);  // its forehead on the glass
  TEST_ASSERT_FALSE(at(slime::kKnockClimbAtMs + climb->ms + 100).on());
}

// The flop (the pack's clip `flop`) plays on the face by its id
// (dbg.clip's): its palms both on the glass with the body; an id the pack
// hasn't plays nothing.
static void test_the_flop_plays_by_its_id() {
  GelFace f;
  linkkit::Rng rng;
  f.reset(0, rng);
  TEST_ASSERT_FALSE(f.playClip("no-such-clip", 16));
  TEST_ASSERT_TRUE(f.playClip("flop", 16));
  for (uint32_t t = 32; t <= 2500; t += 16) f.step(t, rng);
  const rig::Channels c = f.channels();
  TEST_ASSERT_EQUAL_INT(1000, c[rig::Channel::kGlass]);
  TEST_ASSERT_EQUAL_INT(1000, c[rig::Channel::kHandLGlass]);
  TEST_ASSERT_EQUAL_INT(1000, c[rig::Channel::kHandRGlass]);
  TEST_ASSERT_TRUE(c[rig::Channel::kPatch] > 0);
}

// A Moment's clip (the `do`'s `clip`, the fix skit's flop) plays by its own
// name when the pack has no reply-<clip>: a fix's Moment, a face with the
// low sign and `clip: flop`, brings the body and both palms to the glass.
static void test_a_moments_clip_plays_by_its_own_name() {
  linkkit::Rng rng;
  app::Behaviour b(std::make_unique<GelFace>());
  b.reset(0, rng);
  app::Model m;
  m.base = SceneState::kIdle, m.mood = Mood::kCalm;
  b.onState(m, 0);
  TEST_ASSERT_NULL(rig::kRig.clip("reply-flop"));
  app::ReactionIn in;
  in.expr = true, in.mood = Mood::kPleased, in.low = true;
  std::snprintf(in.sign, sizeof(in.sign), "%s", "tests fixed");
  std::snprintf(in.clip, sizeof(in.clip), "%s", "flop");
  b.play(in, 1008);
  int glass = 0, palms = 0;
  for (uint32_t t = 1008; t < 4000; t += 16) {
    b.advance(t + 16, rng);
    const rig::Channels c = static_cast<GelFace&>(b.face()).channels();
    glass = std::max(glass, int(c[rig::Channel::kGlass]));
    palms = std::max(palms, int(std::min(c[rig::Channel::kHandLGlass], c[rig::Channel::kHandRGlass])));
  }
  TEST_ASSERT_TRUE(glass > 900);
  TEST_ASSERT_TRUE(palms > 900);
}

// Turning round (the rig's `turn`, render/gel/geometry.h's Projector::face): each
// point of the face goes round the dome on its own, so the eye nearer the
// rim narrows by itself while the other keeps its width, and one gone round
// behind faces 0, which paintArt fades out whole (shownFacing); at its back
// every feature is behind, and a whole turn draws as none.
static void test_the_turn_narrows_each_eye_on_its_own() {
  const Surface s{502, 410, nullptr, 110};
  const auto& calm = slime::kProfile[slime::kCalm].face;
  const int eyeX = scalar(calm[0]), eyeY = scalar(calm[1]), mouthY = scalar(calm[3]), half = 4096 * 4 / 100;
  struct Eye {
    int width, facing;
  };
  auto eye = [&](int turn, int side) {
    PaintControls c;
    c.turn = turn;
    const Projector p(s, c);
    int a = 0, b = 0, facing = 0;
    const Point l = p.face(side * eyeX - half, eyeY, &a), r = p.face(side * eyeX + half, eyeY, &b);
    p.face(side * eyeX, eyeY, &facing);
    return Eye{std::abs(r.x - l.x), facing};
  };
  const Eye left = eye(0, -1), right = eye(0, 1);
  TEST_ASSERT_INT_WITHIN(16, left.width, right.width);  // at rest, as drawn
  TEST_ASSERT_TRUE(left.facing > 3500 && left.facing == right.facing);
  // A sixth of a turn to its right: the right eye nears the rim, narrower
  // by far (about an eighth of its width), the left, past the middle now,
  // three quarters as wide.
  const Eye nearL = eye(4096 / 6, -1), nearR = eye(4096 / 6, 1);
  TEST_ASSERT_TRUE(nearR.width * 2 < nearL.width);
  TEST_ASSERT_TRUE(nearL.width * 10 > left.width * 7);
  TEST_ASSERT_TRUE(nearR.facing < nearL.facing && nearR.facing > kFacingGone);
  // A quarter: the right eye has gone round behind, the left still shows.
  TEST_ASSERT_EQUAL_INT(0, shownFacing(eye(1024, 1).facing));
  TEST_ASSERT_EQUAL_INT(4096, shownFacing(eye(1024, -1).facing));
  // Its back: nothing of the face shows.
  PaintControls back;
  back.turn = 2048;
  const Projector p(s, back);
  for (const int x : {-eyeX, 0, eyeX}) {
    int facing = -1;
    p.face(x, x ? eyeY : mouthY, &facing);
    TEST_ASSERT_EQUAL_INT(0, shownFacing(facing));
  }
  // A whole turn is where it began.
  PaintControls rest, whole;
  whole.turn = 4096;
  const Point a = Projector(s, rest).face(eyeX, eyeY), b = Projector(s, whole).face(eyeX, eyeY);
  TEST_ASSERT_INT_WITHIN(16, a.x, b.x);
  TEST_ASSERT_INT_WITHIN(16, a.y, b.y);
  TEST_ASSERT_EQUAL_INT(0, shownFacing(kFacingGone));
  TEST_ASSERT_EQUAL_INT(4096, shownFacing(kFacingShown));
}

// The meme faces (character.json's board_faces): six faces past the
// pack's 18, each by its name on the wire, each with its own move,
// face-<face>, a rig clip dbg.clip plays, idle's first take and played
// once as a Moment shows the face. The silent scream's palms come up to
// its cheeks; a face of the 18 plays no face move.
static void test_the_meme_faces_and_their_moves() {
  TEST_ASSERT_EQUAL_INT(24, slime::kCanonical);
  TEST_ASSERT_EQUAL_INT(24, kMoodCount);
  const char* faces[] = {"deadpan", "side_eye", "squint", "smug", "silent_scream", "faint"};
  const char* moves[] = {"face-deadpan", "face-side-eye",      "face-squint",
                         "face-smug",    "face-silent-scream", "face-faint"};
  GelFace f;
  linkkit::Rng rng;
  f.reset(0, rng);
  for (int i = 0; i < 6; ++i) {
    Mood m;
    TEST_ASSERT_TRUE_MESSAGE(parseMood(faces[i], m), faces[i]);
    TEST_ASSERT_TRUE(int(m) >= 18);  // after the Mac's 18
    const int p = expressionFromName(faces[i]);
    TEST_ASSERT_TRUE(p >= 0 && p < slime::kCanonical);
    TEST_ASSERT_EQUAL_STRING(moves[i], slime::kIdleMoves[p]);
    TEST_ASSERT_NOT_NULL(rig::kRig.clip(moves[i]));
    TEST_ASSERT_TRUE(f.playClip(moves[i], 16));
  }
  for (int p = 0; p < 18; ++p) TEST_ASSERT_EQUAL_INT(0, std::strncmp(slime::kIdleMoves[p], "idle-", 5));
  // A Moment with the face: its move, once.
  auto hands = [&](Mood mood) {
    GelFace g;
    g.reset(0, rng);
    FaceSource src;
    FaceContext c;
    g.sync(src, c, 0);
    src.anim = SceneState::kPoked, src.at = 100, src.mood = mood, c.borrowed = true;
    int most = 0;
    for (uint32_t t = 100; t <= 2000; t += 16) {
      g.sync(src, c, t);
      g.step(t, rng);
      most = std::max(most, int(g.channels()[rig::Channel::kHandLSize]));
    }
    return most;
  };
  TEST_ASSERT_TRUE(hands(Mood::kSilentScream) > 600);
  TEST_ASSERT_EQUAL_INT(0, hands(Mood::kSurprised));
}

// Each sound carries its own duck. A needs-you alert's
// knocks and ding stay up under a line; a poke's squish, routine, turns down.
static void test_each_cue_carries_its_own_duck() {
  linkkit::Rng rng;
  GelFace f;
  f.reset(0, rng);
  FaceSource s;
  FaceContext c;
  c.base = SceneState::kWorking;
  c.act = SceneState::kWorking;
  s.look = SceneState::kWorking;
  f.sync(s, c, 0);
  int routine = 0, alert = 0;
  voice::FxEvent cues[Face::kMaxCues];
  bool changed = false;
  for (uint32_t t = 16; t <= 16000; t += 16) {
    if (t == 16 || t == 3200) {  // a poke, over the work, and gone
      s.anim = t == 16 ? SceneState::kPoked : SceneState::kNone;
      s.at = 16;
      f.sync(s, c, t);
    }
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
  const uint8_t first = f.pick(SceneState::kTaskComplete, Mood::kGrumpy, 0, Outcome::kSuccess, rng);
  TEST_ASSERT_EQUAL_UINT8(first, f.pick(SceneState::kTaskComplete, Mood::kGrumpy, 0, Outcome::kSuccess, rng));
  TEST_ASSERT_EQUAL_UINT32(before, f.engine().random.state);
  f.started(SceneState::kTaskComplete, Mood::kGrumpy, first, Outcome::kSuccess);
  TEST_ASSERT_TRUE(f.engine().random.state != before);
  // The shuffle bag never repeats a take straight away.
  TEST_ASSERT_TRUE(first != f.pick(SceneState::kTaskComplete, Mood::kGrumpy, 0, Outcome::kSuccess, rng));
}
// After a reset the engine draws from one seed, 53, so the board and the simulator choose alike; a board's power-on
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
// Tired (the Mac's energy: at night, or after a long stretch of work) the
// lids hang lower, and they go with the face falling asleep:
// as it squashes shut they ease out, gone by when it's a line (1 s), a
// sixteenth of their hang in a 16 ms frame at the most, where they went in
// one; and waking, they come back on the face's quick spring.
static void test_the_night_lids_ease_out_as_it_falls_asleep() {
  auto e = std::make_unique<Engine>();
  e->setOccasion(tagBit("night"), 0);
  TEST_ASSERT_EQUAL_INT(0, sleepyLids(*e));  // the night alone isn't energy: the Mac's rule says
  e->energy = Energy::kTired;
  Facts f;
  f.base = SceneState::kIdle;
  e->setFacts(f);
  uint32_t t = 0;
  for (; t <= 640; t += 16) e->step(t);
  TEST_ASSERT_EQUAL_INT(kNightLids, sleepyLids(*e));
  for (const SceneState then : {SceneState::kAsleep, SceneState::kIdle}) {
    int last = sleepyLids(*e), steepest = 0;
    f.base = then;
    e->setFacts(f);
    for (int frame = 0; frame < (then == SceneState::kAsleep ? 100 : 40); ++frame) {
      e->step(t += 16);
      const int now = sleepyLids(*e);
      TEST_ASSERT_TRUE(then == SceneState::kAsleep ? now <= last : now >= last);
      steepest = std::max(steepest, std::abs(now - last));
      last = now;
    }
    TEST_ASSERT_EQUAL_INT(then == SceneState::kAsleep ? 0 : kNightLids, last);
    TEST_ASSERT_TRUE(steepest * (then == SceneState::kAsleep ? 16 : 4) <= kNightLids);
  }
}
// A reset lets go of the finger with the engine: a finger still down
// through it grabs the new engine at its next touch.
static void test_a_reset_lets_go_of_the_finger() {
  linkkit::Rng rng;
  GelFace f;
  f.reset(0, rng);
  f.finger(true, 100, 100);
  TEST_ASSERT_TRUE(f.engine().grab);
  f.reset(0, rng);
  TEST_ASSERT_FALSE(f.engine().grab);
  f.finger(true, 120, 100);
  TEST_ASSERT_TRUE(f.engine().grab);
}
// A finger moves the dome its own way (GelFace::finger), the canvas's y
// down as the screen's is: a swipe down brings the crown down and squashes
// the body while its base stays on the floor, up stretches it, across leans it that
// way. Let go moving, the dome carries on its way a little, then settles
// back where it stood without bouncing past it by much.
static void test_a_finger_moves_the_dome_its_way() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  linkkit::Rng rng;
  auto anchors = [&](const GelFace& f) {
    rig::Anchors a;
    paint(s, f.engine(), false, 0, 0, &a);
    return a;
  };
  auto base = [&] {  // the lowest row the body last drew, above the lane
    for (int y = 410 * 4 / 5 - 1; y > 0; --y)
      for (int x = 0; x < 502; ++x)
        if (px[size_t(y) * 502 + size_t(x)]) return y;
    return 0;
  };
  struct Swipe {
    int x0, y0, x1, y1;
  };
  for (const Swipe w : {Swipe{160, 60, 160, 200}, Swipe{160, 200, 160, 60}, Swipe{70, 130, 250, 130}}) {
    GelFace f;
    f.reset(0, rng);
    for (uint32_t t = 16; t <= 960; t += 16) f.step(t, rng);
    const rig::Anchors rest = anchors(f);
    const int restBase = base();
    // 160 ms there, a reading every 16 ms, then let go at its speed.
    for (uint32_t t = 976; t <= 1120; t += 16) {
      const int along = int(t - 960);
      f.finger(true, w.x0 + (w.x1 - w.x0) * along / 160, w.y0 + (w.y1 - w.y0) * along / 160);
      f.step(t, rng);
    }
    const rig::Anchors held = anchors(f);
    const auto pose = f.engine().pose();
    if (w.y1 > w.y0) {
      TEST_ASSERT_TRUE(held.crown.y > rest.crown.y + 16 * 30);  // down: the crown comes down 30 px and more
      TEST_ASSERT_TRUE(pose[1] < q(-.2));
    } else if (w.y1 < w.y0) {
      TEST_ASSERT_TRUE(held.crown.y < rest.crown.y - 16 * 30);  // up: it rises
      TEST_ASSERT_TRUE(pose[1] > q(.2));
    } else {
      TEST_ASSERT_TRUE(held.crown.x > rest.crown.x + 16 * 30);  // across: it leans that way
      TEST_ASSERT_TRUE(pose[0] > q(.4));
    }
    // The base stays on the floor: its edge moves only as its footprint
    // spreads or narrows toward the camera.
    TEST_ASSERT_INT_WITHIN(12, restBase, base());
    const int vx = (w.x1 - w.x0) * 1000 / 160, vy = (w.y1 - w.y0) * 1000 / 160;
    const rig::Point before = held.crown;
    f.letGo(vx, vy);
    TEST_ASSERT_FALSE(f.engine().grab);
    f.step(1136, rng);
    const rig::Point after = anchors(f).crown;
    // Carried on its way for a frame after letting go.
    TEST_ASSERT_TRUE(vy ? (after.y - before.y) * vy > 0 : (after.x - before.x) * vx > 0);
    int past = 0;  // the furthest the crown goes back past where it stood, in px
    for (uint32_t t = 1152; t <= 3000; t += 16) {
      f.step(t, rng);
      const rig::Point c = anchors(f).crown;
      past = std::max(past, vy ? (rest.crown.y - c.y) * (vy > 0 ? 1 : -1) / 16 : (rest.crown.x - c.x) / 16);
    }
    const rig::Point settled = anchors(f).crown;
    TEST_ASSERT_TRUE(std::abs(settled.x - rest.crown.x) < 16 * 2 && std::abs(settled.y - rest.crown.y) < 16 * 3);
    TEST_ASSERT_TRUE(past <= 10);
  }
}
// The timing Behaviour plays by is the recipe table's. The outcome rows
// time like their state's own row, which is what loopMs and voiceMs read.
// One set of takes for each state: the table has no mood, and the
// activities the desk shows as another's (the four the Mac no longer sends,
// and tool_use, which it shows as working) play that one's row.
static void test_timing_comes_from_the_recipe_table() {
  GelFace f;
  constexpr int kRows = slime::kStateRows;
  for (int v = 0; v < 3; ++v) {
    const auto& done = slime::kRecipes[rowOf(SceneState::kTaskComplete)][v];
    for (int row : {kRows, kRows + 1}) TEST_ASSERT_TRUE(slime::kRecipes[row][v].duration == done.duration);
    // wake_up stretches in a take's usual length, a finish's.
    const auto& wake = slime::kRecipes[rowOf(SceneState::kWakeUp)][v];
    TEST_ASSERT_TRUE(wake.duration == done.duration);
    TEST_ASSERT_EQUAL_UINT8(kStart, wake.contacts[0].kind);
  }
  TEST_ASSERT_EQUAL_INT(int(SceneState::kCount) - 5, kRows);
  TEST_ASSERT_EQUAL_INT(kRows + 2, slime::kRecipeStates);
  TEST_ASSERT_EQUAL_INT(kRows, recipeState(SceneState::kTaskComplete, Outcome::kSuccess));
  TEST_ASSERT_EQUAL_INT(kRows + 1, recipeState(SceneState::kTaskComplete, Outcome::kFailure));
  TEST_ASSERT_EQUAL_INT(rowOf(SceneState::kWakeUp), recipeState(SceneState::kWakeUp, Outcome::kNone));
  TEST_ASSERT_EQUAL_INT(rowOf(SceneState::kWorking), rowOf(SceneState::kPlanning));
  TEST_ASSERT_EQUAL_INT(rowOf(SceneState::kAnalyzing), rowOf(SceneState::kSearching));
  TEST_ASSERT_EQUAL_INT(rowOf(SceneState::kTerminal), rowOf(SceneState::kTesting));
  TEST_ASSERT_EQUAL_INT(rowOf(SceneState::kTerminal), rowOf(SceneState::kDelegating));
  TEST_ASSERT_EQUAL_INT(rowOf(SceneState::kWorking), rowOf(SceneState::kToolUse));
  TEST_ASSERT_EQUAL_INT(int(Family::kStart), int(family(SceneState::kWakeUp)));
  // A moody take in a mood (scenes.h's inMood): each contact at first +
  // delay + (at - first) * spacing, its strength times the gain, the lean
  // added. Sad's (160 ms late, 1.18 apart, a gain of .62) over the desk's
  // second take, keys at 560, 760, 1680 and 1880 ms: 720, 956, 2041.6 and
  // 2277.6. Waiting's and a touch's are the same in every mood.
  const slime::Recipe& desk = slime::kRecipes[rowOf(SceneState::kWorking)][1];
  const slime::Recipe sad = take(slime::kSad, rowOf(SceneState::kWorking), 1);
  TEST_ASSERT_TRUE(desk.moody && sad.count == 4 && desk.count == 4);
  TEST_ASSERT_TRUE(sad.lean == desk.lean + q(-.016));
  const int keys[] = {720, 956, 2041, 2277};
  for (int i = 0; i < 4; ++i) {
    TEST_ASSERT_EQUAL_INT(keys[i], F(sad.contacts[i].at).integer());
    TEST_ASSERT_TRUE(sad.contacts[i].strength == desk.contacts[i].strength * q(.62));
  }
  for (SceneState still : {SceneState::kWaiting, SceneState::kPoked, SceneState::kNeedsYou, SceneState::kListening})
    TEST_ASSERT_FALSE(slime::kRecipes[rowOf(still)][0].moody);
  // Looks rest on one 3.2 s loop whatever the take.
  TEST_ASSERT_EQUAL_UINT32(3200, f.loopMs(Mood::kHappy, SceneState::kIdle, 2));
  // Two rows have a fourth take. A success's is its
  // hiccups: the first take's card at 680 ms, then three little contacts in a
  // 3.7 s take; a finish timed without its outcome finds it too.
  for (int row = 0; row < slime::kRecipeStates; ++row)
    TEST_ASSERT_EQUAL_INT(row == rowOf(SceneState::kGesture)                  ? 10
                          : row == rowOf(SceneState::kAsleep) || row == kRows ? 4
                                                                              : 3,
                          takes(row));
  // Happy's timing traits move nothing (no delay, a spacing of 1).
  const slime::Recipe hiccups = take(slime::kHappy, kRows, 3);
  TEST_ASSERT_EQUAL_UINT8(4, hiccups.count);
  TEST_ASSERT_EQUAL_UINT8(kSuccess, hiccups.contacts[0].kind);
  const int hics[] = {1640, 2060, 2480};
  for (int i = 0; i < 3; ++i) {
    TEST_ASSERT_EQUAL_UINT8(kBody, hiccups.contacts[i + 1].kind);
    TEST_ASSERT_TRUE(hiccups.contacts[i + 1].at == T(hics[i]));
    TEST_ASSERT_TRUE(hiccups.contacts[i + 1].strength == q(.45) * slime::kProfile[slime::kHappy].traits[2]);
  }
  TEST_ASSERT_EQUAL_UINT32(3700, f.loopMs(Mood::kHappy, SceneState::kTaskComplete, 3));
  TEST_ASSERT_EQUAL_UINT32(750, f.voiceMs(Mood::kHappy, SceneState::kTaskComplete, 3));
  // Asleep's is a snore: two breaths in 4.8 s; its other takes are still.
  const slime::Recipe snore = take(slime::kCalm, rowOf(SceneState::kAsleep), 3);
  TEST_ASSERT_TRUE(snore.duration == T(4800));
  TEST_ASSERT_EQUAL_UINT8(2, snore.count);
  for (int i = 0; i < 2; ++i) TEST_ASSERT_EQUAL_UINT8(kBreath, snore.contacts[i].kind);
  TEST_ASSERT_TRUE(snore.contacts[0].at == T(600) && snore.contacts[1].at == T(2600));
  for (int v = 0; v < 3; ++v) TEST_ASSERT_EQUAL_UINT8(0, take(slime::kCalm, rowOf(SceneState::kAsleep), v).count);
  // The gift: proud's lifted success alone shows a bug beside its card.
  int gifts = 0;
  for (int p = 0; p < slime::kProfiles; ++p)
    for (int row = 0; row < slime::kRecipeStates; ++row)
      for (int v = 0; v < takes(row); ++v) gifts += take(p, row, v).gift;
  TEST_ASSERT_EQUAL_INT(1, gifts);
  TEST_ASSERT_TRUE(take(slime::kProud, kRows, 1).gift);
  // A finish's result reaches the strip (screens.cpp's tick or cross).
  TEST_ASSERT_TRUE(f.outcome(Mood::kSad, SceneState::kTaskComplete, 1, Outcome::kFailure) == Outcome::kFailure);
}
// Idle's takes are its mood's one move (a rig clip, idle-<mood>) and the
// expression's own bits, and its bag deals the bits from its second round;
// the comedy every mood shares, the yawn and the sneeze, is the face's to
// deal, as pastimes. A yawn stretches up with its eyes squeezed; the
// zoomies slide it edge to edge and back; a sneeze is a contact a second in
// that may sound, lurching it forward, all off the heap. Asleep snores only
// after a round of still rests, and a lost link never.
static void test_comedy_plays_in_idle_and_asleep() {
  TEST_ASSERT_EQUAL_INT(2, slime::kIdleTakes);
  TEST_ASSERT_EQUAL_INT(1, Acting::takes(slime::kCalm));
  TEST_ASSERT_EQUAL_INT(2, Acting::takes(slime::kExcited));
  TEST_ASSERT_NULL(Acting::gag(slime::kCalm, 0));
  const int yawning = bitOf(info(Pastime::kYawn)), sneezing = bitOf(info(Pastime::kSneeze));
  TEST_ASSERT_EQUAL_STRING("yawn-and-settle", slime::kGags[yawning].gesture.type);
  TEST_ASSERT_EQUAL_STRING("sneeze-and-shake", slime::kGags[sneezing].gesture.type);
  TEST_ASSERT_EQUAL_STRING("zoomies", Acting::gag(slime::kExcited, 1)->gesture.type);
  // A bag: its first round its first three, then every take, never the last again.
  Bag<4> bag;
  Random random(53);
  int dealt[11], seen[2][4]{};
  for (int& d : dealt) d = bag.next(random, 4);
  for (int i = 0; i < 11; ++i) {
    if (i < 3) TEST_ASSERT_TRUE(dealt[i] < 3);
    if (i >= 3) ++seen[(i - 3) / 4][dealt[i]];
    if (i) TEST_ASSERT_TRUE(dealt[i] != dealt[i - 1]);
  }
  for (const auto& round : seen)
    for (int n : round) TEST_ASSERT_EQUAL_INT(1, n);
  // A take of its own, or with `bit`, that bit as the face deals it.
  auto play = [](int profile, int take, uint32_t ms, int gag = -1) {
    auto e = std::make_unique<Engine>();
    e->setMood(profile);
    e->step(0);
    e->step(16);
    if (gag >= 0)
      e->playBit(gag);
    else
      e->acting.perform(e->motion.time, e->random, take);
    std::vector<std::array<F, 6>> frames;  // closure, slide, squash, lift, forward, the eyes' closing
    for (uint32_t t = 32; t <= 32 + ms; t += 16) {
      e->step(t);
      const auto life = e->life();
      frames.push_back({e->acting.closure(), e->acting.slide.x, e->pose()[1], life[0], life[2], e->blink()});
    }
    return frames;
  };
  // A frame `s` seconds after the take began.
  auto at = [](const std::vector<std::array<F, 6>>& frames, double s) {
    return frames[size_t(std::lround(s * 1000 / 16)) - 1];
  };
  const auto yawn = play(slime::kCalm, 0, 3000, yawning);
  TEST_ASSERT_TRUE(at(yawn, 1.2)[3] > q(.04) && at(yawn, 1.2)[5] > q(.7));
  const auto zoom = play(slime::kExcited, 3, 3600);
  F most = 0, least = 0;
  for (const auto& f : zoom) most = max(most, f[1]), least = min(least, f[1]);
  TEST_ASSERT_TRUE(most > q(.45) && least < q(-.45) && abs(zoom.back()[1]) < q(.02));
  TEST_ASSERT_TRUE(at(play(slime::kCalm, 0, 2800, sneezing), 1.15)[4] > q(.08));  // the sneeze lurches forward
  // A sneeze is one contact, a second in, and allocates nothing.
  auto e = std::make_unique<Engine>();
  e->step(0);
  e->playBit(sneezing);
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
// A low or cross mood keeps its own face through a gesture, so a touch
// never cheers it on the screen on its own; any other mood borrows the
// gesture's face while it plays.
static void test_a_low_or_cross_mood_keeps_its_face_through_a_gesture() {
  TEST_ASSERT_FALSE(slime::kKeepsFaceThroughGestures[slime::kCalm]);
  TEST_ASSERT_FALSE(slime::kKeepsFaceThroughGestures[slime::kHappy]);
  TEST_ASSERT_TRUE(slime::kKeepsFaceThroughGestures[slime::kSad]);
  TEST_ASSERT_TRUE(slime::kKeepsFaceThroughGestures[slime::kAnnoyed]);
  TEST_ASSERT_TRUE(slime::kKeepsFaceThroughGestures[slime::kWounded]);
  TEST_ASSERT_TRUE(slime::kKeepsFaceThroughGestures[slime::kGrumpy]);
  linkkit::Rng rng;
  // The face showing a frame into gesture g, played from idle in a mood.
  auto shown = [&](Mood mood, Gesture g) {
    GelFace face;
    face.reset(0, rng);
    FaceSource s;
    FaceContext c;
    c.mood = s.mood = mood;
    face.sync(s, c, 0);
    for (uint32_t t = 16; t <= 480; t += 16) face.step(t, rng);
    s.anim = SceneState::kGesture;
    s.animVariant = uint8_t(g);
    s.at = 496;
    face.sync(s, c, 496);
    face.step(512, rng);
    return face.engine().expression;
  };
  for (Gesture g : {Gesture::kStroke, Gesture::kNose, Gesture::kTickle, Gesture::kPeekaboo}) {
    TEST_ASSERT_EQUAL_INT(slime::kGestureFaces[int(g)], shown(Mood::kCalm, g));
    TEST_ASSERT_EQUAL_INT(slime::kSad, shown(Mood::kSad, g));
    TEST_ASSERT_EQUAL_INT(slime::kAngry, shown(Mood::kAngry, g));
  }
}

// The gesture state has a take for each of
// render::Gesture, each its own bit under the face it borrows; the board
// names the take, and no bag deals it. Each plays held, under its face with
// its bit, the mood kept, each contact once, and gives the face back; each
// does what it says (a hand-off lifts and leans in, a stroke melts with its
// eyes shut, a ruffle bristles, a boop on the nose squishes, a tickle
// jiggles both ways, dizzy wobbles side to side, a pick-up stretches up, a
// put-down lands squashed, a startle jumps, peekaboo rises from below), and
// every one comes back to the middle.
static void test_each_gesture_plays_its_own_gag() {
  linkkit::Rng rng;
  GelFace f;
  f.reset(0, rng);
  TEST_ASSERT_EQUAL_INT(int(Gesture::kCount), f.variants(Mood::kHappy, SceneState::kGesture));
  TEST_ASSERT_EQUAL_INT(3, f.variants(Mood::kHappy, SceneState::kPoked));
  const int row = rowOf(SceneState::kGesture);
  for (int g = 0; g < int(Gesture::kCount); ++g) {
    const slime::Recipe r = take(slime::kGrumpy, row, g);
    TEST_ASSERT_FALSE(r.moody);  // the same in every mood
    TEST_ASSERT_TRUE(r.duration == take(slime::kCalm, row, g).duration);
    TEST_ASSERT_TRUE(r.gag >= 0 && r.count > 0);
    char type[32];
    std::snprintf(type, sizeof type, "gesture:%s", gestureName(Gesture(g)));
    TEST_ASSERT_EQUAL_STRING(type, slime::kGags[r.gag].gesture.type);
    TEST_ASSERT_TRUE(slime::kGestureFaces[g] >= 0 && slime::kGestureFaces[g] < slime::kProfiles);
    TEST_ASSERT_EQUAL_UINT32(uint32_t(F(r.duration).integer()), f.loopMs(Mood::kHappy, SceneState::kGesture, g));
  }
  const uint32_t random = f.engine().random.state;
  f.started(SceneState::kGesture, Mood::kHappy, 5, Outcome::kNone);
  TEST_ASSERT_EQUAL_UINT32(random, f.engine().random.state);
  struct Shot {
    std::array<F, 4> pose;
    std::array<F, 3> life;
    F blink, slide, squash, ripple;  // the eyes' closing, a gag's slide, the gesture springs' squash and ripple
  };
  // A gesture played from calm idle as the board plays it, a frame every 16
  // ms from its start; then let go.
  auto play = [&](int g) {
    GelFace face;
    face.reset(0, rng);
    FaceSource s;
    FaceContext c;
    c.mood = s.mood = Mood::kCalm;
    face.sync(s, c, 0);
    for (uint32_t t = 16; t <= 480; t += 16) face.step(t, rng);
    s.anim = SceneState::kGesture;
    s.animVariant = uint8_t(g);
    s.at = 496;
    face.sync(s, c, 496);
    const auto& e = face.engine();
    const auto& r = take(slime::kCalm, row, g);
    std::vector<Shot> shots;
    int contacts = 0;
    uint32_t t = 496;
    for (; t < 496 + uint32_t(F(r.duration).integer()); t += 16) {
      face.sync(s, c, t + 16);
      face.step(t + 16, rng);
      TEST_ASSERT_TRUE(e.scenes.route.state == SceneState::kGesture && e.scenes.variant == g);
      TEST_ASSERT_EQUAL_INT(slime::kGestureFaces[g], e.expression);
      TEST_ASSERT_EQUAL_INT(slime::kCalm, e.emotion);
      TEST_ASSERT_EQUAL_INT(r.gag, e.acting.playing);
      contacts += int(e.scenes.contacts.size());
      shots.push_back(
          {e.pose(), e.life(), e.blink(), e.acting.slide.x, e.acting.channels[1].x, e.acting.channels[2].x});
    }
    TEST_ASSERT_EQUAL_INT(r.count, contacts);
    s.anim = SceneState::kNone;
    face.sync(s, c, t += 16);
    face.step(t, rng);
    TEST_ASSERT_EQUAL_INT(slime::kCalm, e.expression);
    TEST_ASSERT_FALSE(e.acting.holding);
    TEST_ASSERT_TRUE(abs(shots.back().slide) < q(.02));  // back in the middle
    return shots;
  };
  std::vector<std::vector<Shot>> played;
  for (int g = 0; g < int(Gesture::kCount); ++g) played.push_back(play(g));
  auto at = [&](Gesture g, double s) { return played[int(g)][size_t(std::lround(s * 1000 / 16)) - 1]; };
  auto most = [&](Gesture g, int frames, auto read) {
    F m = read(played[int(g)][0]);
    for (int i = 0; i < std::min<int>(frames, int(played[int(g)].size())); ++i) m = max(m, read(played[int(g)][i]));
    return m;
  };
  const int all = 1 << 20;
  TEST_ASSERT_TRUE(at(Gesture::kHandoff, 1).life[0] > q(.04) && at(Gesture::kHandoff, 1).life[2] > q(.08));
  TEST_ASSERT_TRUE(at(Gesture::kStroke, 1.5).blink > q(.8) &&
                   at(Gesture::kStroke, 1.5).pose[1] < at(Gesture::kHandoff, .1).pose[1]);
  TEST_ASSERT_TRUE(most(Gesture::kRuffle, 40, [](const Shot& s) { return abs(s.ripple); }) > q(.05));
  TEST_ASSERT_TRUE(at(Gesture::kNose, .2).squash < q(-.05));
  TEST_ASSERT_TRUE(most(Gesture::kTickle, all, [](const Shot& s) { return s.pose[0]; }) > q(.05) &&
                   most(Gesture::kTickle, all, [](const Shot& s) { return -s.pose[0]; }) > q(.05));
  TEST_ASSERT_TRUE(most(Gesture::kDizzy, all, [](const Shot& s) { return s.slide; }) > q(.05) &&
                   most(Gesture::kDizzy, all, [](const Shot& s) { return -s.slide; }) > q(.05));
  TEST_ASSERT_TRUE(at(Gesture::kPickup, .8).life[0] > q(.12));
  TEST_ASSERT_TRUE(at(Gesture::kPutdown, .2).squash < q(-.06));
  TEST_ASSERT_TRUE(most(Gesture::kStartle, 40, [](const Shot& s) { return s.life[0]; }) > q(.1));
  TEST_ASSERT_TRUE(at(Gesture::kPeekaboo, .4).squash < q(-.12) && at(Gesture::kPeekaboo, 1.1).life[0] > q(.08));
}
// A reply to what you said (FaceContext::reply, the Mac's `reply`) plays
// its pack's clip, reply-<name>, over the face it came with, once, as that
// face starts: each of the replies has one (the Mac's eleven, and dunno, a huh to a question), and fits the board's
// buffer for it; a shake of the head swings the body side to side; the
// same reply still showing doesn't play it again, the next one does; and a
// reply with no clip plays nothing.
static void test_a_reply_plays_its_clip_once() {
  const char* replies[] = {"yes",    "no",   "dunno", "huh",     "hello",  "bye",
                           "thanks", "ouch", "hehe",  "comfort", "status", "hush"};
  char name[24];
  for (const char* r : replies) {
    std::snprintf(name, sizeof(name), "reply-%s", r);
    TEST_ASSERT_NOT_NULL_MESSAGE(rig::kRig.clip(name), name);
    TEST_ASSERT_TRUE_MESSAGE(std::strlen(r) < app::kReplyBytes, r);
    TEST_ASSERT_TRUE_MESSAGE(rig::kRig.clip(name)->ms >= 1000 && rig::kRig.clip(name)->ms <= 1800, name);
  }
  linkkit::Rng rng;
  GelFace face;
  face.reset(0, rng);
  FaceSource s;
  FaceContext c;
  // Happy: its idle move (idle-happy, a hop) leans nothing.
  c.mood = s.mood = Mood::kHappy;
  face.sync(s, c, 0);
  // The most the body leans while `ms` go by from `from`.
  auto lean = [&](uint32_t from, uint32_t ms) {
    int most = 0;
    for (uint32_t t = from; t < from + ms; t += 16) {
      face.sync(s, c, t + 16);
      face.step(t + 16, rng);
      most = std::max(most, std::abs(int(face.mixer().channels()[rig::Channel::kLean])));
    }
    return most;
  };
  const int still = lean(0, 1000);
  c.borrowed = true, c.reply = "no", c.replyAt = 1000;
  TEST_ASSERT_TRUE(lean(1000, 1300) > still + 80);
  TEST_ASSERT_TRUE(lean(2300, 1300) <= still + 10);  // still showing: once
  c.replyAt = 3600;
  TEST_ASSERT_TRUE(lean(3600, 1300) > still + 80);
  c.reply = "meow", c.replyAt = 5000;
  TEST_ASSERT_TRUE(lean(5000, 1300) <= still + 10);

  // The reaction it rides on, as the device plays a `do`: the reply goes
  // with its face, and only a face carries one.
  app::Behaviour b(std::make_unique<GelFace>());
  b.reset(0, rng);
  app::Model m;
  m.base = SceneState::kIdle, m.mood = Mood::kCalm;
  b.onState(m, 0);
  auto leaned = [&](uint32_t from, uint32_t ms) {
    int most = 0;
    for (uint32_t t = from; t < from + ms; t += 16) {
      b.advance(t + 16, rng);
      most = std::max(most, std::abs(int(static_cast<GelFace&>(b.face()).mixer().channels()[rig::Channel::kLean])));
    }
    return most;
  };
  const int resting = leaned(0, 1000);
  app::ReactionIn in;
  in.expr = true, in.mood = Mood::kHappy, in.said = true;
  std::snprintf(in.reply, sizeof(in.reply), "%s", "no");
  b.play(in, 1008);
  TEST_ASSERT_TRUE(leaned(1008, 1300) > resting + 80);
}

// The notice state's three takes play the pack's rig clip for it
// (rig/clips/notice.json) on the face's mixer, each under a face it
// borrows (kNoticeFaces), dealt by its bag; its scene is the start
// family's, timed to the clip and 200 ms more, with no bit or
// contact of its own. Heard at work, the clip moves what the painter
// draws: it perks up tall, hops off the ground and lands flat; its eyes go
// wide and up, then squeeze shut, and its mouth opens; its two cues sound
// a body contact each, and it goes back to the work, the mood's face
// again, the mixer at rest.
static void test_a_notice_plays_its_rig_clip() {
  linkkit::Rng rng;
  GelFace f;
  f.reset(0, rng);
  const rig::Clip* clip = rig::kRig.clip("notice");
  TEST_ASSERT_NOT_NULL(clip);
  TEST_ASSERT_EQUAL_INT(3, f.variants(Mood::kHappy, SceneState::kNotice));
  TEST_ASSERT_EQUAL_INT(3, slime::kNoticeCount);
  TEST_ASSERT_TRUE(family(SceneState::kNotice) == Family::kStart);
  const int row = rowOf(SceneState::kNotice);
  for (int v = 0; v < 3; ++v) {
    const auto& r = take(slime::kGrumpy, row, v);
    TEST_ASSERT_TRUE(r.gag < 0 && r.count == 0);
    TEST_ASSERT_EQUAL_INT(clip->ms + 200, F(r.duration).integer());
    TEST_ASSERT_TRUE(slime::kNoticeFaces[v] >= 0 && slime::kNoticeFaces[v] < slime::kProfiles);
  }
  for (int v = 0; v < 3; ++v) {
    GelFace face;
    face.reset(0, rng);
    FaceSource s;
    FaceContext c;
    c.mood = s.mood = Mood::kCalm;
    c.base = SceneState::kWorking, c.act = SceneState::kWorking;
    s.look = SceneState::kWorking;
    face.sync(s, c, 0);
    for (uint32_t t = 16; t <= 480; t += 16) face.step(t, rng);
    s.anim = SceneState::kNotice;
    s.animVariant = uint8_t(v);
    s.at = 496;
    face.sync(s, c, 496);
    const auto& e = face.engine();
    TEST_ASSERT_EQUAL_INT(slime::kNoticeFaces[v], e.expression);
    const auto& r = take(slime::kCalm, row, v);
    // What the painter draws of the clip: its controls from rest.
    int tallest = 0, flattest = 0, lift = 0, eyes = 0, up = 0, shut = 0, mouth = 0;
    std::vector<uint32_t> sounded;
    uint32_t t = 496;
    for (; t < 496 + uint32_t(F(r.duration).integer()); t += 16) {
      face.sync(s, c, t + 16);
      face.step(t + 16, rng);
      TEST_ASSERT_TRUE(e.scenes.route.state == SceneState::kNotice && e.scenes.variant == v);
      TEST_ASSERT_TRUE(e.acting.playing < 0);  // no gag: the clip moves it
      PaintControls p;
      applyRig(p, face.mixer().channels());
      tallest = std::max(tallest, p.squash), flattest = std::min(flattest, p.squash);
      lift = std::max(lift, p.lift), eyes = std::max(eyes, p.eyeSize), up = std::max(up, p.gazeUp);
      shut = std::max(shut, p.blink);
      mouth = std::max<int>(mouth, face.mixer().channels()[rig::Channel::kMouthOpen]);
      for (const auto& cue : e.cues) {
        TEST_ASSERT_EQUAL_STRING("squish", cue.recipe);
        sounded.push_back(t + 16 - 496);
      }
    }
    TEST_ASSERT_TRUE(tallest > 4096 * 8 / 100 && flattest < -4096 / 10);  // Q12 of the dome's squash
    TEST_ASSERT_TRUE(lift > 4096 * 17 / kPxPerUnit);                      // most of its 20 px off the ground
    TEST_ASSERT_TRUE(eyes > 4096 * 6 / 5 && up > kRigGaze / 2 && shut > 4096 * 3 / 5 && mouth >= kRigMouthOpen);
    // Its cues, each in the step that crosses it: take-off and landing.
    TEST_ASSERT_EQUAL_INT(2, int(sounded.size()));
    TEST_ASSERT_TRUE(sounded[0] > 460 && sounded[0] <= 476 && sounded[1] > 760 && sounded[1] <= 776);
    s.anim = SceneState::kNone;
    face.sync(s, c, t += 16);
    face.step(t, rng);
    TEST_ASSERT_TRUE(e.scenes.route.state == SceneState::kWorking);
    TEST_ASSERT_EQUAL_STRING("calm", slime::kProfile[e.expression].id);
    TEST_ASSERT_EQUAL_MEMORY(&rig::kRest, &face.mixer().channels(), sizeof rig::kRest);
  }
}
// A clip authored once in the pack's rig/clips/ plays on the gel: work's
// stretch from tier2, a row of its pastimes (kStretch), through its mixer,
// laid over the engine's pose (applyRig). Without the tier it doesn't play; the mixer stays at rest, so nothing it draws changes;
// and a reaction fades it out.
static void test_a_rig_clip_plays_on_the_gel() {
  const rig::Clip* stretch = rig::kRig.clip("stretch");
  TEST_ASSERT_NOT_NULL(stretch);
  TEST_ASSERT_EQUAL_PTR(stretch, clipOf(info(Pastime::kStretch)));
  TEST_ASSERT_EQUAL_INT(2, info(Pastime::kStretch).tier);
  // The tallest squash and the most shut eyes the gel's mixer reaches at
  // work, over five minutes while the stretch plays, and when it first
  // left rest. The Mac's state comes every 10 s, as it does, so the link
  // stays up.
  struct Seen {
    int squash = 0, open = 1000;
    uint32_t moved = 0;
  };
  auto play = [](uint32_t when, uint32_t pokeAt = 0) {
    linkkit::Rng rng;
    app::Behaviour b(std::make_unique<GelFace>());
    b.reset(0, rng);
    app::Model m;
    m.base = SceneState::kWorking, m.act = SceneState::kWorking, m.mood = Mood::kHappy, m.when = when;
    b.onState(m, 0);
    Seen seen;
    for (uint32_t t = 16; t <= 300000u; t += 16) {
      if (t % 10000 < 16) b.onState(m, t);
      if (pokeAt && t == pokeAt) {
        app::ReactionIn in;
        in.anim = SceneState::kPoked;
        in.id = 7;
        in.variant = b.pick(in.anim, m.mood, 255, in.outcome, rng);
        b.play(in, t);
      }
      b.advance(t, rng);
      const rig::Channels& c = static_cast<GelFace&>(b.face()).mixer().channels();
      if (static_cast<GelFace&>(b.face()).pastimes(t).playing == Pastime::kStretch) {
        seen.squash = std::min<int>(seen.squash, c[rig::Channel::kSquash]);
        seen.open = std::min<int>(seen.open, std::min(c[rig::Channel::kEyeOpenL], c[rig::Channel::kEyeOpenR]));
      }
      if (!seen.moved && std::memcmp(&c, &rig::kRest, sizeof c)) seen.moved = t;
      if (pokeAt && t >= pokeAt + 400) {
        // The poke's reaction faded the stretch, or the pastime, out.
        TEST_ASSERT_TRUE(c[rig::Channel::kSquash] >= -30);
        TEST_ASSERT_TRUE(c[rig::Channel::kEyeOpenL] > 900);
      }
      if (pokeAt && t >= pokeAt + 400) break;
    }
    return seen;
  };
  const Seen tier2 = play(reached(tagBit("tier2"))), plain = play(tagBit("day"));
  TEST_ASSERT_TRUE(tier2.squash <= -115);    // up tall: the stretch's -130 at its height
  TEST_ASSERT_TRUE(tier2.open <= 320);       // eyes squeezed: its -700 on 1000
  TEST_ASSERT_TRUE(plain.squash >= -30);     // the look's own breathing at most
  TEST_ASSERT_EQUAL_UINT32(0, plain.moved);  // the mixer at rest throughout
  TEST_ASSERT_TRUE(tier2.moved > 0);
  play(reached(tagBit("tier2")), tier2.moved + 608);
  // On the gel the rig's channels move what the painter draws: taller, its
  // crown higher, and its lids down; at rest, nothing.
  auto e = std::make_unique<Engine>();
  for (uint32_t t = 0; t <= 1600; t += 16) e->step(t);
  // Its padding zeroed, which the comparison reads too, and its members
  // their defaults, which only they are written with.
  alignas(PaintControls) unsigned char room[sizeof(PaintControls)] = {};
  PaintControls& rest = *new (room) PaintControls;
  PaintControls moved;
  rest.squash = 100, rest.lean = -40, rest.lift = 20, rest.blink = 300;
  std::memcpy(&moved, &rest, sizeof rest);
  applyRig(rest, rig::kRest);
  TEST_ASSERT_EQUAL_MEMORY(&moved, &rest, sizeof rest);
  rig::Mixer m;
  m.reset(0, 0, nullptr);
  m.play(*stretch);
  m.advance(1000);
  applyRig(moved, m.channels());
  TEST_ASSERT_TRUE(moved.squash > rest.squash + 400 && moved.lift > rest.lift + 250 && moved.blink > 2500);
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  rig::Anchors still, stretched;
  paint(s, *e, false, 0, 0, &still);
  paint(s, *e, false, 0, 0, &stretched, m.channels());
  TEST_ASSERT_TRUE(stretched.crown.y < still.crown.y - 16 * 8);
}
// Pins the rig's x, reach and melt on the gel (applyRig, geometry.h's
// kReachOut, kReachIn, kMeltDrop and kMeltSpread): x carries the whole body
// sideways, 100 canvas px about 150 of the panel's and 400 off its edge;
// a full reach carries its right side out over 30 px low on its side,
// where it reaches for the desk, and pinches its left in; a full melt brings its crown down most of the way
// to the desk and spreads its base wider, its base where it was.
static void test_the_rig_carries_reaches_and_melts_the_gel() {
  auto e = std::make_unique<Engine>();
  for (uint32_t t = 0; t <= 1600; t += 16) e->step(t);
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  auto anchors = [&](rig::Channel ch, int value) {
    rig::Channels c = rig::kRest;
    c[ch] = int16_t(value);
    rig::Anchors at;
    paint(s, *e, false, 0, 0, &at, c);
    return at;
  };
  constexpr int kEnd = rig::Anchors::kRingPoints - 1;
  const rig::Anchors still = anchors(rig::Channel::kX, 0);
  const rig::Anchors right = anchors(rig::Channel::kX, 100), away = anchors(rig::Channel::kX, 400);
  const int moved = (right.crown.x - still.crown.x) / 16;
  TEST_ASSERT_TRUE(moved > 120 && moved < 180);
  TEST_ASSERT_INT_WITHIN(16, still.crown.y, right.crown.y);
  TEST_ASSERT_TRUE(away.brimL.x / 16 > 502 && away.hem[0].x / 16 > 502);
  const rig::Anchors reach = anchors(rig::Channel::kReach, 1000), back = anchors(rig::Channel::kReach, -1000);
  TEST_ASSERT_TRUE(reach.lap[kEnd].x - still.lap[kEnd].x > 30 * 16);
  TEST_ASSERT_TRUE(reach.lap[0].x > still.lap[0].x);
  TEST_ASSERT_TRUE(still.lap[0].x - back.lap[0].x > 30 * 16);
  const rig::Anchors melt = anchors(rig::Channel::kMelt, 1000), half = anchors(rig::Channel::kMelt, 500);
  const int height = (still.hem[kEnd / 2].y - still.crown.y) / 16, low = (melt.hem[kEnd / 2].y - melt.crown.y) / 16;
  TEST_ASSERT_TRUE(low < height / 2 && low > height / 4);
  TEST_ASSERT_TRUE(half.crown.y > still.crown.y && half.crown.y < melt.crown.y);
  TEST_ASSERT_INT_WITHIN(2 * 16, still.hem[kEnd / 2].y, melt.hem[kEnd / 2].y);
  TEST_ASSERT_TRUE((melt.hem[kEnd].x - melt.hem[0].x) * 4 > (still.hem[kEnd].x - still.hem[0].x) * 5);
}
void test_fixed_math_and_motion();
void test_software_clock_matches_binary64();
void test_a_divisor_divides_exactly();
// test_cells.cpp
void test_every_cell_plays_truthfully();
void test_ten_minutes_of_work();
void test_held_and_interrupted_contacts();
void test_asleep_rests_still_but_for_a_snore();
// test_finish.cpp
void test_a_finish_is_sized_by_its_turn_or_else_its_hold();
void test_the_face_picks_a_finish_and_plays_it_once();
void test_a_big_finish_cheers_once_and_bounces();
void test_a_takeover_puts_the_desk_away();
void test_every_finish_moves_smoothly_and_settles();
void test_gold_rush_floods_and_little_win_shows_its_trophy();
void test_only_what_draws_behind_erases_first();
void test_a_rapid_chain_settles_on_the_last();
void test_the_semantic_face_numbers();
// test_motion.cpp
void test_the_motion_v1_numbers();
void test_the_motion_v2_numbers();
void test_each_motion_rule_off_gives_back_the_motion_before();
void test_the_motion_layer_comes_to_rest();
void test_hands_follow_and_change_owner_without_a_jump();
void test_the_seven_idle_moves();
void test_a_spin_never_unwinds();
void test_half_a_turn_off_still_turns();
void test_the_turn_comes_round_within_its_limits();
void test_the_finger_numbers();
void test_acting_timing_and_springs();
void test_setters_keep_springs_and_replay();
void test_the_scenes_formulas();
// test_pastimes.cpp
void test_every_pastime_has_its_clip_and_its_turn();
void test_each_pastime_draws_and_ends();
void test_pastimes_are_dealt_by_tier_after_a_rest();
void test_transitions_play_between_doings_and_anything_urgent_cuts_through();
void test_a_tagged_pastime_plays_only_while_its_tag_is_on();
void test_the_eyes_rest_unless_theres_a_reason();
void test_a_look_is_a_turn_not_a_dart();
void test_it_types_along_with_you();
// test_with_you.cpp
void test_the_eyes_with_you_in_order();
void test_the_eyes_follow_your_pointer();
void test_it_reads_along_while_you_scroll();
void test_it_grooves_to_your_music_and_watches_with_you();
void test_a_call_keeps_it_still();
void test_speaking_wins_over_typing();
void test_what_it_wears_and_has_beside_it();
void test_typing_fast_is_quicker_not_higher();
void test_nothing_with_you_without_the_facts();
void test_work_settles_by_tier();
void test_the_paws_type_on_the_keys();
void test_each_activity_is_a_pose();
// test_hand.cpp
void test_the_eyes_follow_a_finger();
void test_a_finger_leaves_the_dice_alone();
void test_a_lean_goes_where_the_finger_is();
void test_a_finger_at_rest_leans_then_dozes_and_lifting_wakes();
void test_lifting_a_doze_wakes_it_with_a_start();
void test_a_short_hold_stays_a_tap();
void test_a_stroke_and_a_tickle_stay_theirs();
void test_a_hold_on_the_needs_you_screen_only_dismisses();
void test_a_needs_you_under_a_lean_ends_it();
void test_a_finish_keeps_its_touches();
void test_listening_takes_the_face_from_a_lean();
void test_a_hold_on_the_strip_is_the_drawers();
void test_an_asks_lane_keeps_its_held_tap();
void test_a_moment_cuts_a_lean();
void test_a_drag_starts_where_the_finger_is_on_the_dome();
void test_a_leans_breath_minds_the_volume();
void test_a_lean_allocates_nothing();
void test_a_tilt_sloshes_and_settles();
void test_a_tilt_gives_way();
void test_a_tilt_allocates_nothing();
void test_listening_nods();
void test_a_touch_says_why_itself();
void test_the_macs_reason_doesnt_double_a_touchs();
void test_a_reason_alone();
// test_drawer.cpp
void test_a_pull_up_the_strip_opens_the_drawer();
void test_a_swipe_up_the_face_isnt_the_drawers();
void test_a_short_pull_springs_back_shut();
void test_a_tap_on_a_row_picks_it();
void test_it_shuts_itself_and_says_its_open_till_then();
void test_boot_shuts_it();
void test_the_drawers_rows_on_the_panel();
void test_a_long_drawers_rows_scroll();
void test_a_finger_scrolls_a_long_drawer();
void test_the_body_under_the_drawer();
void test_a_reaction_shows_the_drawer_once_its_sign_is_read();
void test_a_finger_or_a_request_first_keeps_it_shut();
void test_holding_boot_to_talk_shuts_it();
void test_drawer_frames_allocate_nothing();
// test_requests.cpp
void test_requests_route_by_priority();
void test_a_request_keeps_its_identity();
void test_cues_stay_sparse_and_quiet();
void test_a_request_sounds_once_whatever_changes();
void test_sound_draws_change_nothing_drawn();
static void test_gel_draws_natively() {
  // Full-panel RGB565. The gel asks for native surfaces;
  // Device allocates them at the board's size, which the simulator's Hal
  // gives as the AMOLED's (what reaches the panel: test_push).
  GelFace face;
  TEST_ASSERT_TRUE(face.drawsNative());
  Surface native{502, 410, nullptr};
  TEST_ASSERT_EQUAL_UINT32(411640, native.bytes());
}
static void test_face_projection_and_pose_bounds() {
  // The face's anchors where the camera and the dome put them,
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
    e->clear();
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
    if (r.anim != SceneState::kNone) e->play(r);
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
// wounded face and asleep allocate nothing; only messages and events
// do, into bounded histories. (ArduinoJson's documents use malloc, so a
// line's parsing isn't counted here.)
// The layers (render/gel/layers.h) sit on the anchors of the pose that drew
// the body: the crown over the brim's ring over the hands'; they move with
// the body. It wears nothing for any tag, the night's included: a night
// shows on its lids, which hang lower but asleep.
static void test_layers_follow_the_bodys_anchors() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  auto e = std::make_unique<Engine>();
  for (int t = 0; t <= 960; t += 16) e->step(t);
  rig::Anchors at;
  paint(s, *e, false, 0, 0, &at);
  TEST_ASSERT_TRUE(at.crown.y < at.brimF.y && at.brimF.y < at.handF.y);
  TEST_ASSERT_TRUE(at.brimL.x < at.crown.x && at.crown.x < at.brimR.x);
  TEST_ASSERT_TRUE(at.eyeL.x < at.eyeR.x && at.brimF.y < at.eyeL.y && at.eyeL.y < at.handF.y + 16 * 40);
  TEST_ASSERT_TRUE(at.crown.y > 0 && at.handF.y / 16 < 410 * 4 / 5);
  rig::Anchors pressed;
  paint(s, *e, false, 2, 0, &pressed);  // the press dips the body, and the layers with it
  TEST_ASSERT_EQUAL_INT(at.crown.y + 32, pressed.crown.y);
  TEST_ASSERT_EQUAL_INT(at.handF.y + 32, pressed.handF.y);
  auto tags = [](std::initializer_list<const char*> names) {
    uint32_t when = 0;
    for (const char* n : names) when |= tagBit(n);
    return when;
  };
  {
    // Nothing is worn for a special day, a season, a Friday or the night:
    // only the Zs, beside it, and only asleep.
    auto dressed = std::make_unique<Engine>();
    Facts idle;
    idle.base = SceneState::kIdle;
    dressed->setFacts(idle);
    for (const char* tag : {"friday", "winter", "party", "newyear", "lunar", "programmers", "halloween", "valentines"}) {
      dressed->setOccasion(tags({"day", tag}), 0);
      dressed->step(500);
      TEST_ASSERT_EQUAL_UINT32_MESSAGE(0, layerContents(*dressed).beside, tag);
      dressed->setOccasion(tags({"night", tag}), 0);
      TEST_ASSERT_EQUAL_UINT32_MESSAGE(0, layerContents(*dressed).beside, tag);
    }
  }
  // The body's lower rings: the lap's over the hem's, each from the left side to
  // the right, the hem's front the lowest, under the hands'.
  for (const auto* ring : {at.lap, at.hem}) {
    TEST_ASSERT_TRUE(ring[0].x < ring[8].x && ring[8].x < ring[16].x);
    TEST_ASSERT_TRUE(ring[0].y < ring[8].y && ring[16].y < ring[8].y);
  }
  TEST_ASSERT_TRUE(at.lap[8].y < at.handF.y && at.handF.y < at.hem[8].y);
  TEST_ASSERT_EQUAL_INT(0, sleepyLids(*e));
  e->setOccasion(tags({"night"}), 0);
  e->energy = Energy::kTired;
  TEST_ASSERT_EQUAL_INT(kNightLids, sleepyLids(*e));
  e->energy = Energy::kNormal;
  // Every layer at once, asleep (the Zs), off the heap.
  e->setOccasion(tags({"night", "winter", "party", "valentines", "friday"}), 0);
  e->scenes.route.state = SceneState::kAsleep;
  allocCount = 0;
  allocCounting = true;
  for (int i = 0; i < 20; ++i) paintLayers(s, *e, at);
  allocCounting = false;
  TEST_ASSERT_EQUAL_INT(0, allocCount);
}

// The Zs come and go through the rig's layer stack (the face's), on the
// rig's 200 ms fade: a winter night awake wears nothing; falling asleep,
// the Zs fade in, each layer its own; a sign fades out at its opacity, as
// Behaviour gives it. Each is drawn at its layer's opacity.
static void test_the_layers_come_and_go_through_the_stack() {
  using rig::Layer;
  static_assert(rig::kFadeMs == 200, "a layer fades over the rig's 200 ms");
  linkkit::Rng rng;
  app::Behaviour b(std::make_unique<GelFace>());
  b.reset(0, rng);
  const auto& face = static_cast<GelFace&>(b.face());
  const rig::Layers& l = face.layers();
  auto state = [&](SceneState base, std::initializer_list<const char*> names, uint32_t t) {
    app::Model m;
    m.base = base, m.mood = Mood::kCalm;
    for (const char* n : names) m.when |= tagBit(n);
    b.advance(t, rng);
    b.onState(m, t);
    b.advance(t, rng);
  };
  state(SceneState::kIdle, {"night", "winter", "party", "friday"}, 0);
  b.advance(1000, rng);
  TEST_ASSERT_EQUAL_UINT32(0, l.content(Layer::kHat, 1000));  // no nightcap
  TEST_ASSERT_EQUAL_INT(0, l.opacity(Layer::kWorn, 1000));
  TEST_ASSERT_EQUAL_INT(0, l.opacity(Layer::kBeside, 1000));
  state(SceneState::kAsleep, {"night", "winter"}, 2000);
  TEST_ASSERT_EQUAL_INT(0, l.opacity(Layer::kBeside, 2000));
  for (uint32_t t = 2016; t <= 2400; t += 16) {
    b.advance(t, rng);
    const int in = ease1000(std::min(int(t - 2000), 200), 200);
    TEST_ASSERT_EQUAL_INT(in, l.opacity(Layer::kBeside, t));  // the Zs
    TEST_ASSERT_EQUAL_INT(0, l.opacity(Layer::kWorn, t));
    TEST_ASSERT_EQUAL_UINT32(0, l.content(Layer::kHat, t));
  }
  TEST_ASSERT_TRUE(l.content(Layer::kWorn, 2400) == 0 && l.content(Layer::kBeside, 2400) == 1);
  // Drawn at the opacity: the Zs half in are about half as bright as whole.
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  auto e = std::make_unique<Engine>();
  for (int t = 0; t <= 960; t += 16) e->step(t);
  e->setOccasion(tagBit("night"), 0);
  rig::Anchors at;
  paint(s, *e, false, 0, 0, &at);
  rig::Layers zs;
  zs.show(Layer::kBeside, kZs, 0);
  auto lit = [&](const rig::Layers& layers, uint32_t t) {
    std::fill(px.begin(), px.end(), 0);
    paintLayers(s, *e, at, &layers, t);
    long n = 0;
    for (uint16_t p : px) n += (p >> 11) + (p >> 5 & 63) / 2 + (p & 31);
    return n;
  };
  const long whole = lit(zs, 400), half = lit(zs, 100);
  TEST_ASSERT_TRUE(whole > 300);
  TEST_ASSERT_INT_WITHIN(whole / 5, whole / 2, half);
  TEST_ASSERT_EQUAL_INT(0, lit(rig::Layers{}, 400));
  // The sign, at its opacity.
  auto sign = [&](int opacity) {
    std::fill(px.begin(), px.end(), 0);
    paintSign(s, {"bye bye code", 1000, opacity}, at);
    long n = 0;
    for (uint16_t p : px) n += (p >> 11) + (p >> 5 & 63) / 2 + (p & 31);
    return n;
  };
  const long up = sign(1000);
  TEST_ASSERT_TRUE(up > 10000);
  TEST_ASSERT_INT_WITHIN(up / 10, up / 2, sign(500));
  TEST_ASSERT_EQUAL_INT(0, sign(0));
  // The longest sign, its hands carried far to either side, stays
  // SignLayer::kEdge in from the panel's sides, hands and all; one that
  // would have stayed on it is held where its hands are.
  const char* longest = "Eighteen glyphs ok";
  TEST_ASSERT_EQUAL_INT(18, glyphCount(longest));
  for (int side : {-1, 1}) {
    rig::Anchors carried = at;
    carried.handF.x = at.handF.x + side * 200 * 16;
    std::fill(px.begin(), px.end(), 0);
    paintSign(s, {longest, 1000, 1000}, carried);
    int x0 = s.width, x1 = -1;
    for (int y = 0; y < s.height; ++y)
      for (int x = 0; x < s.width; ++x)
        if (px[size_t(y) * s.width + x]) x0 = std::min(x0, x), x1 = std::max(x1, x);
    TEST_ASSERT_TRUE(x1 >= 0);
    TEST_ASSERT_TRUE(x0 >= SignLayer::kEdge);
    TEST_ASSERT_TRUE(x1 <= s.width - 1 - SignLayer::kEdge);
    TEST_ASSERT_TRUE(side < 0 ? x0 <= SignLayer::kEdge + 1 : x1 >= s.width - 2 - SignLayer::kEdge);
  }
  rig::Anchors nudged = at;
  nudged.handF.x = at.handF.x + 20 * 16;
  std::fill(px.begin(), px.end(), 0);
  paintSign(s, {"bye bye code", 1000, 1000}, nudged);
  const std::vector<uint16_t> moved(px);
  std::fill(px.begin(), px.end(), 0);
  paintSign(s, {"bye bye code", 1000, 1000}, at);
  for (int y = 0; y < s.height; ++y)
    for (int x = 0; x + 20 < s.width; ++x)
      TEST_ASSERT_EQUAL_HEX16(px[size_t(y) * s.width + x], moved[size_t(y) * s.width + x + 20]);
}

// A recording (render/gel/raster.h) blends again exactly what its shapes
// would have drawn, and as they'd have drawn a whole number of pixels
// over: the pixels and the rows marked changed, over the body and black,
// cut at the surface's edges.
static void test_a_recording_replays_as_drawn() {
  constexpr int kW = 120, kH = 100;
  std::vector<uint16_t> a(kW * kH), b(kW * kH);
  auto shapes = [](Raster& r, int dx, int dy) {
    const Point cap[] = {{dx + 200, dy + 900}, {dx + 1500, dy + 260}, {dx + 1700, dy + 1300}, {dx + 400, dy + 1500}};
    r.polygon16(cap, 4, rgb565(58, 62, 150));
    const Point band[] = {{dx + 100, dy + 1200}, {dx + 900, dy + 1450}, {dx + 1800, dy + 1150}};
    r.stroke16(band, 3, 150, rgb565(246, 240, 226));
    r.alpha = 140;
    r.disk16(dx + 1650, dy + 300, 120, rgb565(246, 240, 226));
    r.alpha = 255;
  };
  for (const auto& shift : {std::array<int, 2>{0, 0}, {3, 2}, {-2, -14}, {40, 30}}) {
    for (int i = 0; i < kW * kH; ++i) a[i] = b[i] = i % 7 ? rgb565(89, 169, 224) : 0;  // the body, and black
    Surface sa{kW, kH, a.data()}, sb{kW, kH, b.data()};
    Raster direct{sa};
    shapes(direct, shift[0] * 16, shift[1] * 16);
    static uint8_t bytes[8 * 1024];
    Recording kept{bytes, int(sizeof bytes)};
    kept.clear();
    Surface frame{512, 400, nullptr};
    Raster record{frame};
    record.limit = frame.height;
    record.recording = &kept;
    shapes(record, 200 * 16, 150 * 16);  // kept 200, 150 px over: on no pixels, and uncut
    TEST_ASSERT_FALSE(kept.full);
    TEST_ASSERT_TRUE(kept.box.x0 > 195 && kept.box.y0 > 150 && kept.box.x1 < 320 && kept.box.y1 < 250);
    Raster replayed{sb};
    replayed.replay(kept, shift[0] - 200, shift[1] - 150);
    TEST_ASSERT_EQUAL_MEMORY(a.data(), b.data(), a.size() * 2);
    for (int y = 0; y < kH; ++y) {
      TEST_ASSERT_EQUAL_INT(sa.written[y].first, sb.written[y].first);
      TEST_ASSERT_EQUAL_INT(sa.written[y].last, sb.written[y].last);
    }
  }
  // Past its room it keeps nothing more, and says so.
  static uint8_t room[2000];
  Recording small{room, int(sizeof room)};
  small.clear();
  Surface frame{512, 400, nullptr};
  Raster record{frame};
  record.limit = frame.height;
  record.recording = &small;
  for (int i = 0; i < 1000 && !small.full; ++i) record.round(0, i % 38 * 10, 500, 10, 0, rgb565(1, 2, 3));
  TEST_ASSERT_TRUE(small.full);
  TEST_ASSERT_TRUE(small.used <= small.room);
}

// A recording replayed between pixels (Raster::replay16) is, for one shape
// over black, the mean of it replayed on the four whole pixels around, to
// within rounding; on a whole pixel it's replay() exactly.
static void test_a_recording_replays_between_pixels() {
  constexpr int kW = 120, kH = 100;
  const uint16_t ink = rgb565(246, 240, 226);
  static uint8_t bytes[4 * 1024];
  Recording kept{bytes, int(sizeof bytes)};
  kept.clear();
  Surface frame{kW, kH, nullptr};
  Raster record{frame};
  record.limit = kH;
  record.recording = &kept;
  const Point cap[] = {{600, 900}, {1500, 260}, {1700, 1300}, {400, 1500}};
  record.polygon16(cap, 4, ink);
  std::vector<uint16_t> whole[4], between(kW * kH, 0);
  for (int i = 0; i < 4; ++i) {
    whole[i].assign(kW * kH, 0);
    Surface s{kW, kH, whole[i].data()};
    Raster r{s};
    r.replay(kept, 10 + i % 2, 6 + i / 2);
  }
  Surface s{kW, kH, between.data()};
  Raster r{s};
  r.replay16(kept, 10 * 16 + 8, 6 * 16 + 8);
  for (int p = 0; p < kW * kH; ++p) {
    int mean = 0;
    for (const auto& w : whole) mean += w[p] >> 5 & 63;
    TEST_ASSERT_INT_WITHIN(2, mean / 4, between[p] >> 5 & 63);
  }
  std::vector<uint16_t> again(kW * kH, 0);
  Surface sa{kW, kH, again.data()};
  Raster ra{sa};
  ra.replay16(kept, 10 * 16, 6 * 16);
  TEST_ASSERT_EQUAL_MEMORY(whole[0].data(), again.data(), again.size() * 2);
}

// Text placed in sixteenths (text16) is Raster::text's on a whole pixel,
// and between pixels glides: a word forward's ink moves in every frame,
// however little the frame, rather than a pixel at a time.
static void test_text_glides_between_pixels() {
  std::vector<uint16_t> a(502 * 410, 0), b(502 * 410, 0);
  Surface sa{502, 410, a.data()}, sb{502, 410, b.data()};
  Raster ra{sa}, rb{sb};
  ra.text("grep x", 200, 100, rgb565(140, 223, 203), kLarge);
  text16(rb, kLarge, (200 - 6 * kLarge.w / 2) * 16, (100 - kLarge.h / 2) * 16, "grep x", rgb565(140, 223, 203));
  TEST_ASSERT_EQUAL_MEMORY(a.data(), b.data(), a.size() * 2);
  // Moved down 7 sixteenths at a time (under half a pixel): its ink's
  // middle is lower each time.
  double last = -1;
  for (int k = 0; k < 20; ++k) {
    std::fill(a.begin(), a.end(), 0);
    sa.invalidate();
    Raster rk{sa};
    text16(rk, kLarge, 180 * 16, 80 * 16 + k * 7, "grep", rgb565(140, 223, 203));
    double mass = 0, moment = 0;
    for (int y = 0; y < 300; ++y)
      for (int x = 0; x < 502; ++x)
        if (const int g = a[size_t(y) * 502 + x] >> 5 & 63) mass += g, moment += double(g) * y;
    TEST_ASSERT_TRUE(mass > 0);
    const double middle = moment / mass;
    TEST_ASSERT_TRUE(middle > last);
    if (last >= 0) TEST_ASSERT_TRUE(middle - last < 0.6);
    last = middle;
  }
}

// The screen's rule, part one (render/gel/layers.h): nothing hangs behind
// the body or drifts round it for a time of day, a season or a holiday,
// and it wears nothing for one. A morning, a winter's day, a party, New
// Year's, a Friday, Halloween, a Valentine's Day and a night awake draw
// nothing at all over the body. The Zs are the one thing beside it, only
// while it sleeps at night.
static void test_nothing_hangs_in_the_sky_or_the_air() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  auto e = std::make_unique<Engine>();
  for (int t = 0; t <= 960; t += 16) e->step(t);
  rig::Anchors at;
  paint(s, *e, false, 0, 0, &at);
  auto tags = [](std::initializer_list<const char*> names) {
    uint32_t when = 0;
    for (const char* n : names) when |= tagBit(n);
    return when;
  };
  // What the layers draw for `when` in `state`: how many pixels in all, and
  // how many clear of the body's sides by 60 px or more.
  struct Drawn {
    int all = 0, far = 0;
  };
  auto drawn = [&](uint32_t when, SceneState state) {
    e->setOccasion(when, 0);
    e->scenes.route.state = state;
    std::fill(px.begin(), px.end(), 0);
    paintLayers(s, *e, at);
    Drawn d;
    const int left = at.brimL.x / 16 - 60, right = at.brimR.x / 16 + 60;
    for (int y = 0; y < s.height; ++y)
      for (int x = 0; x < s.width; ++x)
        if (px[size_t(y) * s.width + x]) ++d.all, d.far += x < left || x > right;
    return d;
  };
  for (SceneState state : {SceneState::kIdle, SceneState::kWorking, SceneState::kAsleep}) {
    TEST_ASSERT_EQUAL_INT(0, drawn(tags({"morning"}), state).all);
    TEST_ASSERT_EQUAL_INT(0, drawn(tags({"day"}), state).all);
    for (const char* day : {"valentines", "winter", "party", "newyear", "lunar", "programmers", "halloween", "friday"}) {
      TEST_ASSERT_EQUAL_INT_MESSAGE(0, drawn(tags({"day", day}), state).all, day);
      TEST_ASSERT_EQUAL_INT_MESSAGE(0, drawn(tags({"evening", day}), state).all, day);
    }
    for (uint32_t when : {tags({"night"}), tags({"night", "party", "winter", "halloween"})}) {
      const Drawn d = drawn(when, state);
      if (state != SceneState::kAsleep) TEST_ASSERT_EQUAL_INT(0, d.all);  // no nightcap
      else TEST_ASSERT_TRUE(d.all > 0);                                   // the Zs
    }
  }
  auto beside = [&](const char* tag, SceneState state) {
    e->setOccasion(tagBit(tag), 0);
    e->scenes.route.state = state;
    return layerContents(*e).beside;
  };
  TEST_ASSERT_EQUAL_UINT32(0, beside("morning", SceneState::kIdle));
  TEST_ASSERT_EQUAL_UINT32(0, beside("morning", SceneState::kWorking));
  TEST_ASSERT_EQUAL_UINT32(0, beside("night", SceneState::kIdle));
  TEST_ASSERT_EQUAL_UINT32(0, beside("day", SceneState::kAsleep));
  TEST_ASSERT_EQUAL_UINT32(kZs, beside("night", SceneState::kAsleep));
}

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
      "{\"t\":\"state\",\"base\":\"working\",\"act\":\"terminal\",\"mood\":\"wounded\",\"busy\":2,\"vol\":0}",
      "{\"t\":\"state\",\"base\":\"asleep\",\"mood\":\"calm\",\"vol\":0}",
      // The pastimes and their kit.
      "{\"t\":\"state\",\"base\":\"working\",\"act\":\"terminal\",\"mood\":\"happy\",\"vol\":0,\"when\":[\"tier3\"]}",
      "{\"t\":\"state\",\"base\":\"idle\",\"mood\":\"happy\",\"vol\":0,\"when\":[\"tier3\"]}",
  };
  Hal hal;
  std::vector<uint8_t> px(size_t(kWidth) * kHeight);
  app::Device dev(hal, px.data());
  linkkit::Kit kit(hal, dev, true);
  auto line = [&](const char* text) {
    kit.handleLine(text, std::strlen(text), linkkit::Link::kUsb);
    kit.tick();
    if (dev.takeFrame()) dev.frames()->present();
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
// surface as a full one does. On a square panel the bubble holds the
// longest take in the sign's font.
static void test_the_lane_is_native_and_tracked() {
  constexpr int kW = 502, kH = 410, kLane = kH * 4 / 5;
  {
    Surface square{kW, kH, nullptr};
    TEST_ASSERT_TRUE(22 * kSign.w <= bubbleRoom(square));
  }
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
// The AMOLED's panel has corners 110 px in radius that show nothing
// (board/amoled206/config.h's kNativeCorner), so the strip and the bubble
// stand clear of them, whatever they hold: there the bubble holds the
// longest take in the sign's font, and a line of 34 in the small one.
static void test_the_lane_clears_the_rounded_corners() {
  constexpr int kW = 502, kH = 410;
  std::vector<uint16_t> px(kW * kH);
  Surface s{kW, kH, px.data()};
  s.corner = 110;
  TEST_ASSERT_EQUAL_INT(100, s.inset(0, 1));  // the top row loses 100 px a side
  TEST_ASSERT_EQUAL_INT(s.inset(0, 1), s.inset(kH - 1, kH));
  TEST_ASSERT_EQUAL_INT(0, s.inset(110, kH - 110));
  TEST_ASSERT_TRUE(s.inset(0, 20, 14) < s.inset(0, 20));  // a box with round corners stands nearer
  TEST_ASSERT_TRUE(22 * kSign.w <= bubbleRoom(s));
  TEST_ASSERT_TRUE(34 * kSmall.w <= bubbleRoom(s));
  auto clearOfCorners = [&](const char* what) {
    for (int y = 0; y < kH; ++y)
      for (int cut = s.inset(y, y + 1), x = 0; x < cut; ++x) {
        TEST_ASSERT_EQUAL_HEX16_MESSAGE(0, px[size_t(y) * kW + x], what);
        TEST_ASSERT_EQUAL_HEX16_MESSAGE(0, px[size_t(y) * kW + kW - 1 - x], what);
      }
  };
  Strip needsYou, done;
  needsYou.agent = "claude", needsYou.name = "Make the device answer every touch at once", needsYou.more = 2;
  needsYou.busy = 2, needsYou.helpers = 3, needsYou.idle = 2, needsYou.todoDone = 3, needsYou.todoTotal = 7;
  needsYou.noApp = true;
  done.doneAgent = "codex", done.doneThread = "Ship it", done.doneOutcome = Outcome::kFailure, done.busy = 12;
  for (const Strip* strip : {&needsYou, &done}) {
    s.invalidate(), s.clear();
    paintLane(s, nullptr, *strip);
    clearOfCorners("the strip");
  }
  for (const char* line : {"Go", "Technical difficulties", "Tsk... Validate it all, then ship it"}) {
    s.invalidate(), s.clear();
    paintLane(s, line, needsYou);
    clearOfCorners(line);
  }
}
// The strip fades as one: at any opacity each pixel is the whole strip's,
// blended once over the lane's black, so its holes (the working mark's open
// half, the minis' eyes) stay holes, and where its marks meet blends once.
static void test_the_strip_fades_as_one() {
  constexpr int kW = 502, kH = 410;
  std::vector<uint16_t> a(kW * kH), b(a.size());
  Surface whole{kW, kH, a.data()}, faded{kW, kH, b.data()};
  Strip s;
  s.doneAgent = "claude", s.doneThread = "Ship it", s.doneOutcome = Outcome::kSuccess;
  s.busy = 2, s.helpers = 3, s.idle = 1;
  for (int opacity : {0, 1, 250, 500, 999}) {
    Strip partial = s;
    partial.opacity = opacity;
    for (Surface* x : {&whole, &faded}) x->invalidate(), x->clear();
    paintLane(whole, nullptr, s);
    paintLane(faded, nullptr, partial);
    const int alpha = (opacity * 255 + 500) / 1000;
    for (size_t i = 0; i < a.size(); ++i) TEST_ASSERT_EQUAL_HEX16(mix565(0, a[i], alpha), b[i]);
  }
}
// Text inside a raster's bounds draws only what's in them, and marks only
// those rows written: as a kept card draws its corners again, pixel for
// pixel what the whole text leaves there, at the cost of the corner alone.
static void test_text_draws_only_inside_its_bounds() {
  constexpr int kW = 200, kH = 100;
  std::vector<uint16_t> a(kW * kH), b(a.size());
  Surface whole{kW, kH, a.data()}, part{kW, kH, b.data()};
  Raster rw{whole}, rp{part};
  rw.limit = rp.limit = kH;
  const Box box{20, 10, 41, 22};
  rp.bounds = box;
  text(rw, kSign, 5, 0, "NEEDS YOU", 0xffff);
  text(rp, kSign, 5, 0, "NEEDS YOU", 0xffff);
  for (int y = 0; y < kH; ++y)
    for (int x = 0; x < kW; ++x) {
      const bool in = x >= box.x0 && x < box.x1 && y >= box.y0 && y < box.y1;
      TEST_ASSERT_EQUAL_HEX16(in ? a[size_t(y) * kW + x] : 0, b[size_t(y) * kW + x]);
    }
  for (int y = 0; y < kH; ++y)
    if (y < box.y0 || y >= box.y1) TEST_ASSERT_EQUAL_INT(0, part.written[y].last);
}
// The lane's text is cut by the rule every face's is (render::cutAt): a
// line too long for its room draws as the words cutAt keeps and one cell's
// "…". With room, the counts are words, from the margin: "2 working", the
// number in warm white and the word in grey; a needs-you name leaves the
// working count only its mark, a spinner in warm white; a finished turn's
// tick is sage and its cross clay.
static void test_the_lane_cuts_and_marks_as_the_canvas_does() {
  constexpr int kW = 502, kH = 410;
  std::vector<uint16_t> a(kW * kH), b(a.size());
  Surface cut{kW, kH, a.data()}, whole{kW, kH, b.data()};
  Raster rc{cut}, rw{whole};
  rc.limit = rw.limit = kH;
  text(rc, kSign, 0, 0, "claude \xC2\xB7 what does the turn do", 0xffff, 24 * kSign.w);
  text(rw, kSign, 0, 0, "claude \xC2\xB7 what does the\xE2\x80\xA6", 0xffff);
  TEST_ASSERT_EQUAL_MEMORY(b.data(), a.data(), cut.bytes());
  const int cy = kH * ((kStripTop + kHeight) / 2) / kHeight, ty = cy - kSign.h / 2;
  auto inked = [&](int x0, int x1, uint16_t ink) {
    int n = 0;
    for (int y = ty; y < ty + kSign.h; ++y)
      for (int x = x0; x < x1; ++x) n += a[size_t(y) * kW + x] == ink;
    return n;
  };
  Strip s;
  s.busy = 2;
  cut.invalidate(), cut.clear();
  paintLane(cut, nullptr, s);
  TEST_ASSERT_TRUE(inked(18, 18 + kSign.w, rgb565(kEyeRgb)) > 10);                         // "2"
  TEST_ASSERT_TRUE(inked(18 + 2 * kSign.w, 18 + 9 * kSign.w, rgb565(kNarrationRgb)) > 40);  // "working"
  Strip asks = s;
  asks.agent = "claude", asks.name = "fix-nav";
  cut.invalidate(), cut.clear();
  paintLane(cut, nullptr, asks);
  int spokes = 0;
  for (int y = cy - 9; y <= cy + 9; ++y)
    for (int x = kW / 2; x < kW; ++x) spokes += a[size_t(y) * kW + x] == kWorkingInk;
  TEST_ASSERT_TRUE(spokes > 4);
  for (auto [outcome, ink] :
       {std::pair{Outcome::kSuccess, rgb565(kSageRgb)}, std::pair{Outcome::kFailure, rgb565(kClayRgb)}}) {
    Strip done;
    done.doneAgent = "claude", done.doneThread = "fix-nav", done.doneOutcome = outcome;
    cut.invalidate(), cut.clear();
    paintLane(cut, nullptr, done);
    int lit = 0;
    for (int y = cy - 8; y <= cy + 8; ++y)
      for (int x = 18; x < 18 + 18; ++x) lit += a[size_t(y) * kW + x] == ink;
    TEST_ASSERT_TRUE(lit > 10);
  }
}
// The low sign takes the lane's rows and no others, so a
// lane kept keeps it (Surface::laneKeyFrom); a short name in the sign's size;
// names to about 50 characters on two lines, whole, on the AMOLED's rounded
// panel; a longer one cut; and rising, it moves from the panel's foot.
static void test_the_low_sign_stays_in_the_lane_and_holds_a_long_name() {
  static_assert(kLowSignMostGlyphs == 50 && kLowSignRiseMs == 280 && kLowSignFallMs == 400, "the low sign's room and pace");
  constexpr int kW = 502, kH = 410, kCorner = 110, kLane = kH * kLaneTop / kHeight;
  std::vector<uint16_t> px(kW * kH);
  Surface s{kW, kH, px.data()};
  s.corner = kCorner;
  LowSign sign;
  sign.mark = LowSign::Mark::kTick, sign.ink = rgb565(kSageRgb), sign.ms = 1000;
  auto draw = [&] {
    std::fill(px.begin(), px.end(), 0), s.invalidate(), s.clear();
    paintLowSign(s, sign);
    int above = 0;
    for (int y = 0; y < kLane; ++y)
      for (int x = 0; x < kW; ++x) above += px[size_t(y) * kW + x] != 0;
    return above;
  };
  auto layout = [&](const char* text) { return lowSignLayout(kW, kH, kCorner, text, true); };
  const LowSignLayout one = layout("fix-nav");
  TEST_ASSERT_TRUE(one.large);
  TEST_ASSERT_EQUAL_INT(1, one.lines);
  const char* const names[] = {"Rework the onboarding tour for the AMOLED board",  // 47
                               "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwx",  // 50 with nowhere to break
                               "aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjj k"};  // 50 of short words
  for (const char* name : names) {
    const LowSignLayout two = layout(name);
    TEST_ASSERT_FALSE(two.large);
    TEST_ASSERT_EQUAL_INT(2, two.lines);
    // All of it shown: no cut, however it wrapped.
    TEST_ASSERT_EQUAL_INT(int(std::strlen(name)) - (std::strchr(name, ' ') ? 1 : 0),
                          glyphCount(two.line[0]) + glyphCount(two.line[1]));
    // Clear of the panel's corners, down to its last row.
    TEST_ASSERT_TRUE(two.x >= s.inset(two.y, two.y + two.h, 16));
    TEST_ASSERT_TRUE(two.y + two.h < kH);
    sign.text = name;
    TEST_ASSERT_EQUAL_INT(0, draw());
  }
  // Past what it holds, cut as everything is, with "..".
  const LowSignLayout cut = layout("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghij");
  TEST_ASSERT_TRUE(std::strstr(cut.line[1], "..") != nullptr);
  sign.text = "fix-nav";
  TEST_ASSERT_EQUAL_INT(0, draw());
  // Risen, it doesn't move, so its key doesn't change; moving, it does.
  const uint32_t rest = lowSignKey(sign);
  TEST_ASSERT_EQUAL_INT(0, lowSignDrop(sign, kH));
  sign.ms = 9000;
  TEST_ASSERT_EQUAL_UINT32(rest, lowSignKey(sign));
  sign.ms = 100;
  TEST_ASSERT_TRUE(lowSignDrop(sign, kH) > 0);
  TEST_ASSERT_TRUE(lowSignKey(sign) != rest);
  // The strip under it is gone by the time it's half way up, so its words
  // never show through the rising sign.
  const int most = lowSignDrop(LowSign{"x", LowSign::Mark::kNone, 0, 0}, kH);
  for (uint32_t ms = 0; ms <= uint32_t(kLowSignRiseMs); ms += 4) {
    sign.ms = ms;
    const int drop = lowSignDrop(sign, kH), strip = lowSignStripAlpha(sign, kH);
    if (ms == 0) TEST_ASSERT_EQUAL_INT(255, strip);
    if (drop * 2 <= most) TEST_ASSERT_EQUAL_INT(0, strip);
  }
  sign.ms = 100;
  sign.ms = 0;
  TEST_ASSERT_EQUAL_INT(0, draw());
  sign.ms = 1000, sign.leftMs = 5;
  TEST_ASSERT_TRUE(lowSignDrop(sign, kH) > 0);
  sign.leftMs = kLowSignFallMs;
  TEST_ASSERT_EQUAL_INT(0, lowSignDrop(sign, kH));
}

// On the gel the strip names a finished turn only until its sign is up, and
// the sign takes the lane: not over a newer reaction's words.
static void test_the_strip_gives_way_to_the_finishs_sign() {
  linkkit::Rng rng;
  app::Behaviour b{std::make_unique<GelFace>()};
  b.reset(0, rng);
  b.onState(app::Model{}, 0);
  app::ReactionIn in;
  in.anim = SceneState::kTaskComplete;
  in.whoAgent = "claude", in.whoThread = "fix-nav";
  in.key = 7;
  TEST_ASSERT_NULL(b.admit(in, 100));
  b.play(in, 100);
  b.advance(100, rng);
  TEST_ASSERT_TRUE(b.done(100).signMs == 0);  // no words: at once
  TEST_ASSERT_NULL(b.strip(100).doneAgent);
  TEST_ASSERT_EQUAL_STRING("fix-nav", finishSign(b.done(100)).text);
  DoneShow agentOnly;
  agentOnly.agent = "codex", agentOnly.signMs = 10;
  TEST_ASSERT_EQUAL_STRING("codex", finishSign(agentOnly).text);
  agentOnly.signMs = -1;
  TEST_ASSERT_NULL(finishSign(agentOnly).text);
}

// The working mark's spinner turns clockwise a spoke every kSpinStepMs,
// kSpinSteps spokes, a turn a second, the one it's on lit and the one it
// left a step dimmer. The lane's key follows the step only while sessions
// work, so a strip with none working is kept, not drawn again.
static void test_the_working_spinner_turns_once_a_second() {
  TEST_ASSERT_EQUAL_INT(1000, kSpinSteps * kSpinStepMs);
  TEST_ASSERT_EQUAL_INT(0, spinStep(0));
  TEST_ASSERT_EQUAL_INT(0, spinStep(kSpinStepMs - 1));
  TEST_ASSERT_EQUAL_INT(1, spinStep(kSpinStepMs));
  TEST_ASSERT_EQUAL_INT(kSpinSteps - 1, spinStep(999));
  TEST_ASSERT_EQUAL_INT(0, spinStep(1000));
  constexpr int kW = 502, kH = 410;
  std::vector<uint16_t> a(kW * kH);
  Surface lane{kW, kH, a.data()};
  Strip working, resting;
  working.busy = 1;
  resting.idle = 2;
  const int cy = 200, mx = 18 + 9;
  auto at = [&](int spin, int x, int y) {
    lane.invalidate(), lane.clear();
    Raster r{lane};
    r.limit = kH;
    paintStatusMark(r, StatusMark::kWorking, 18, cy, spin);
    return a[size_t(y) * kW + x];
  };
  TEST_ASSERT_EQUAL_HEX16(kWorkingInk, at(0, mx, cy - 6));  // twelve o'clock
  TEST_ASSERT_EQUAL_HEX16(kWorkingInk, at(2, mx + 6, cy));  // three o'clock, two steps on
  const uint16_t left = at(1, mx, cy - 6);                  // twelve, a step behind
  TEST_ASSERT_TRUE(left != 0 && left != kWorkingInk);
  TEST_ASSERT_TRUE((left & 0x1f) < (kWorkingInk & 0x1f));
  TEST_ASSERT_TRUE(laneKey(nullptr, working, 0) != laneKey(nullptr, working, 1));
  TEST_ASSERT_EQUAL_UINT32(laneKey(nullptr, resting, 0), laneKey(nullptr, resting, 5));
}
// What a frame keeps from its surface's last (a card's
// opaque inside, an unchanged lane) is exactly what clearing it whole and
// drawing afresh leaves. Two surfaces taking turns, as the board's do,
// through needs you rising and holding with its strip, a finish, a bubble
// coming and going, the strip's count changing
// and a finished turn's low sign and glow coming, holding and going (render/
// gel/done.h), on the AMOLED's rounded panel, equal a third cleared whole
// before every frame; and the keeps happened.
static void test_kept_cards_and_lanes_match_a_fresh_frame() {
  constexpr int kW = 502, kH = 410;
  std::vector<uint16_t> pa(kW * kH, 0x1234), pb(pa.size(), 0x5678), pf(pa.size());
  Surface turns[2] = {{kW, kH, pa.data()}, {kW, kH, pb.data()}}, fresh{kW, kH, pf.data()};
  for (Surface* s : {&turns[0], &turns[1], &fresh}) s->corner = 110;
  auto e = std::make_unique<Engine>();
  Facts f;
  f.base = SceneState::kWorking;
  f.act = SceneState::kWorking;
  e->setFacts(f);
  Strip asking, working;
  asking.agent = "claude", asking.name = "Fix a test", asking.more = 1, asking.busy = 2;
  working.busy = 1;
  int cardFrames = 0, laneKeeps = 0, cardKeeps = 0, knockKeeps = 0, doneFrames = 0, glowKeeps = 0;
  uint32_t t = 0;
  for (int i = 0; i < 400; ++i) {
    if (i == 20) {  // needs you
      f.attention = {true, "7", "claude", "boop", "Fix a test", 1};
      e->setFacts(f);
    } else if (i == 140) {  // answered; a finish
      f.attention = {};
      e->setFacts(f);
      Request r;
      r.anim = SceneState::kTaskComplete, r.outcome = Outcome::kSuccess;
      e->play(r);
    } else if (i == 260) {
      e->clear();
    }
    e->step(t += 33);
    const char* bubble = i >= 300 && i < 330 ? "Technical difficulties" : nullptr;
    const Strip& strip = f.attention.on ? asking : i % 50 < 25 ? working : Strip{};
    // A finished turn from 150, its reaction played out at 230 and gone
    // by 330.
    DoneShow done;
    if (i >= 150 && i < 330) {
      done.agent = "claude", done.thread = "fix-nav", done.outcome = Outcome::kFailure;
      done.ms = uint32_t(i - 150) * 33;
      if (i >= 230) done.leftMs = (330 - i) * 33;
      if (i >= 190) done.signMs = (i - 190) * 33;
      doneFrames += doneGlow(done) > 0;
    }
    Surface& s = turns[i % 2];
    Box boxes[Surface::kMaxKeep];
    cardFrames += opaqueCards(s, *e, boxes) > 0;
    laneKeeps += s.laneKey && s.laneKey == laneKey(bubble, strip);
    const uint32_t cardKey = s.cardKey, kept = s.laneKey;
    paintFrame(s, *e, false, 0, bubble, {}, strip, done);
    glowKeeps += done.shows() && kept && s.laneKey == kept;
    cardKeeps += cardKey && s.cardKey == cardKey;
    knockKeeps += cardKey && s.cardKey == cardKey && e->scenes.envelope(e->timeMs(), kKnock) > 0;
    fresh.invalidate();
    paintFrame(fresh, *e, false, 0, bubble, {}, strip, done);
    if (std::memcmp(s.pixels, fresh.pixels, s.bytes())) {
      size_t at = 0;
      while (s.pixels[at] == fresh.pixels[at]) ++at;
      TEST_FAIL_MESSAGE(("kept frame differs from a fresh one at " + std::to_string(i) + ", first at (" +
                         std::to_string(at % kW) + ", " + std::to_string(at / kW) + ")")
                            .c_str());
    }
  }
  TEST_ASSERT_TRUE(cardFrames > 100);
  TEST_ASSERT_TRUE(laneKeeps > 100);
  TEST_ASSERT_TRUE(cardKeeps > 100);
  TEST_ASSERT_TRUE(knockKeeps > 0);
  TEST_ASSERT_TRUE(doneFrames > 150);
  TEST_ASSERT_TRUE(glowKeeps > 20);  // a lane under a steady glow is kept, glow and all
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
  TEST_ASSERT_TRUE(std::fabs((least) - (600)) <= 1);
  TEST_ASSERT_TRUE(std::fabs((most) - (600)) <= 1);
}
// A polygon's coverage is its exact area in each pixel, not four sub-rows'
// worth: a lid 3/16 of a pixel thin keeps its ink wherever it sits, and a
// near-level edge moved down a sixteenth adds a sixteenth of a pixel's ink
// to each pixel it crosses, every time, never four sixteenths at once.
static void test_polygon_edges_move_a_sixteenth_at_a_time() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  double least = 1e9, most = 0, stepLeast = 1e9, stepMost = 0, last = -1;
  for (int offset = 0; offset < 32; ++offset) {
    std::fill(px.begin(), px.end(), 0);
    Raster r{s};
    // 40 pixels wide, 3/16 tall, a little aslant: 7.5 pixels of ink.
    const int y = 150 * 16 + offset;
    Point lid[] = {{100 * 16, y}, {140 * 16, y + 2}, {140 * 16, y + 5}, {100 * 16, y + 3}};
    r.polygon16(lid, 4, 0xffff);
    const double area = ink(px);
    least = std::min(least, area), most = std::max(most, area);
    // A 40 × 10 box whose bottom edge, at a slope of 1 in 40, comes down a
    // sixteenth a step: 2.5 pixels more ink each time.
    std::fill(px.begin(), px.end(), 0);
    Point box[] = {{200 * 16, 100 * 16}, {240 * 16, 100 * 16}, {240 * 16, 110 * 16 + offset + 16}, {200 * 16, 110 * 16 + offset}};
    r.polygon16(box, 4, 0xffff);
    const double grown = ink(px);
    if (last >= 0) stepLeast = std::min(stepLeast, grown - last), stepMost = std::max(stepMost, grown - last);
    last = grown;
  }
  TEST_ASSERT_TRUE(least >= 7.5 - 0.5 && most <= 7.5 + 0.5);
  TEST_ASSERT_TRUE(stepLeast >= 2.5 - 0.5 && stepMost <= 2.5 + 0.5);
}
// A sleeper's z (Raster::zee) grows and drifts by sixteenths of a pixel:
// from 7 to 16 px tall, a sixteenth taller never takes ink away and adds
// at most 5 px of it (its pen a sixteenth wider along its 50 px), where
// the font's z it replaces jumped from one size to the next, 40-47 px more
// at once; and a sixteenth over leaves its ink as it was.
static void test_a_z_grows_and_drifts_by_sixteenths() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  Raster r{s};
  double last = -1, grew = 0, shrank = 0, least = 1e9, most = 0;
  for (int h16 = 7 * 16; h16 <= 16 * 16; ++h16) {
    std::fill(px.begin(), px.end(), 0);
    r.zee(200 * 16, 200 * 16, h16, 0xffff);
    const double now = ink(px);
    if (last >= 0) grew = std::max(grew, now - last), shrank = std::max(shrank, last - now);
    last = now;
  }
  TEST_ASSERT_TRUE(grew <= 5 && shrank <= 0.25);
  for (int dx = 0; dx < 16; ++dx) {
    std::fill(px.begin(), px.end(), 0);
    r.zee(200 * 16 + dx, 200 * 16 + dx / 2, 12 * 16, 0xffff);
    least = std::min(least, ink(px)), most = std::max(most, ink(px));
  }
  TEST_ASSERT_TRUE(most - least <= 0.5);
}
// Cut to a clip, a polygon covers what lies inside both: inside a bigger
// clip, all of itself; under a clip over its left half, half of itself.
static void test_a_clipped_polygon_covers_what_lies_in_both() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  Raster r{s};
  Point square[] = {{100 * 16 + 5, 100 * 16 + 3}, {120 * 16 + 5, 100 * 16 + 3}, {120 * 16 + 5, 120 * 16 + 3},
                    {100 * 16 + 5, 120 * 16 + 3}};
  Point big[] = {{90 * 16, 90 * 16}, {130 * 16, 90 * 16}, {130 * 16, 130 * 16}, {90 * 16, 130 * 16}};
  r.polygon16(square, 4, 0xffff, big, 4);
  TEST_ASSERT_TRUE(std::fabs(ink(px) - 400) <= 1);
  std::fill(px.begin(), px.end(), 0);
  Point left[] = {{90 * 16, 90 * 16}, {110 * 16 + 5, 90 * 16}, {110 * 16 + 5, 130 * 16}, {90 * 16, 130 * 16}};
  r.polygon16(square, 4, 0xffff, left, 4);
  TEST_ASSERT_TRUE(std::fabs(ink(px) - 200) <= 1);
}
// Two looks cross-fading (CrossFade) each laid over what's under them
// alone, then blended by weight: half and half of the same ink is that
// ink, with nothing of the black under it showing through, where drawn
// one over the other at half each it'd be three quarters of it.
static void test_a_cross_fade_never_shows_through() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  static uint8_t bytes[4096];
  CrossFade fade{bytes, sizeof bytes};
  Raster r{s};
  auto square = [&](int x) {
    Point v[] = {{x * 16, 100 * 16}, {(x + 20) * 16, 100 * 16}, {(x + 20) * 16, 120 * 16}, {x * 16, 120 * 16}};
    r.polygon16(v, 4, 0xffff);
  };
  fade.look(2048);
  r.recording = fade.next();
  square(100);
  fade.look(2048);
  r.recording = fade.next();
  square(110);  // half of it over the first
  r.recording = nullptr;
  TEST_ASSERT_TRUE(fade.kept());
  r.blend(fade);
  auto green = [&](int x, int y) { return (px[y * 502 + x] >> 5) & 63; };
  TEST_ASSERT_EQUAL_INT(63, green(115, 110));  // both: all ink
  TEST_ASSERT_EQUAL_INT(32, green(105, 110));  // one: half
  TEST_ASSERT_EQUAL_INT(32, green(125, 110));
  TEST_ASSERT_EQUAL_INT(0, green(135, 110));  // neither
}
// Every two arts' cross-fade keeps its groups' looks in half the room it
// has (kCrossingBytes), so they're blended, not drawn one over the other.
static void test_every_cross_fade_fits_its_room() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  crossingPeak = 0;
  const int arts = int(sizeof(slime::kProfile) / sizeof(slime::kProfile[0]));
  for (int from = 0; from < arts; ++from)
    for (int to = 0; to < arts; ++to) {
      if (from == to) continue;
      SemanticFace f;
      f.setMood(from);
      const T frame = T::ratio(16, 1000);
      for (int i = 0; i < 40; ++i) f.advance(frame);
      f.setMood(to);
      for (int i = 0; i < 60 && !(f.count == 2 && f.layers[1].weight >= q(.5)); ++i) f.advance(frame);
      auto e = std::make_unique<Engine>();
      e->face = f;
      PaintControls c;
      paintArt(s, *e, c, false);
    }
  TEST_ASSERT_TRUE(crossingPeak > 0);
  TEST_ASSERT_TRUE(crossingPeak * 2 <= kCrossingBytes);
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
// The outline's soft fringe goes over the crown too, where the pole's
// triangles meet (painter.cpp's `across`), and the outline doesn't jump as
// the mesh turns: leaned or squashed from one end to the other in steps of
// 16 (Q12), each row's edge, from its pixels' coverage, moves evenly, its
// second difference never a pixel and a quarter (it was 1.6 when a
// triangle's edges went soft or hard as it turned).
static void test_the_outline_holds_still_as_the_mesh_turns() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  auto green = [&](int x, int y) { return int((px[y * 502 + x] >> 5) & 63); };
  {
    PaintControls c;
    paint(s, c);
    int soft = 0, columns = 0;
    for (int x = 221; x <= 281; ++x, ++columns) {
      int top = 0;
      while (!px[top * 502 + x]) ++top;
      if (green(x, top) * 10 < green(x, top + 3) * 9) ++soft;
    }
    TEST_ASSERT_TRUE(soft * 10 >= columns * 6);
  }
  for (bool squash : {false, true}) {
    std::vector<double> edges[3];
    double worst = 0;
    for (int v = -4096; v <= 4096; v += 16) {
      PaintControls c;
      (squash ? c.squash : c.lean) = v;
      paint(s, c);
      // Each row's edge from either side, as the share of four pixels the
      // body covers, the fifth taken as whole.
      std::vector<double> now(2 * 410, NAN);
      for (int y = 0; y < 410; ++y)
        for (int side = 0; side < 2; ++side) {
          auto at = [&](int i) { return green(side ? 501 - i : i, y); };
          int first = 0;
          while (first + 4 < 502 && !px[y * 502 + (side ? 501 - first : first)]) ++first;
          if (first + 4 >= 502 || at(first + 4) < 8) continue;
          double covered = 0;
          for (int i = first; i < first + 4; ++i) covered += std::min(1.0, double(at(i)) / at(first + 4));
          now[side * 410 + y] = first + 4 - covered;
        }
      edges[0] = edges[1], edges[1] = edges[2], edges[2] = now;
      if (edges[0].empty()) continue;
      // Rows where the outline is steep, in all three frames.
      for (int i = 1; i + 1 < 2 * 410; ++i) {
        bool steep = i % 410 != 0 && i % 410 != 409;
        for (const auto& e : edges)
          steep = steep && !std::isnan(e[i - 1]) && !std::isnan(e[i]) && !std::isnan(e[i + 1]) &&
                  std::fabs(e[i + 1] - e[i - 1]) < 3;
        if (steep) worst = std::max(worst, std::fabs(edges[2][i] - 2 * edges[1][i] + edges[0][i]));
      }
    }
    char msg[64];
    snprintf(msg, sizeof msg, "%s: the outline jumped %.2f px", squash ? "squash" : "lean", worst);
    TEST_ASSERT_TRUE_MESSAGE(worst < 1.25, msg);
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
// A work act is the work's, never a card: what's running, then how it
// ended, for kActResultMs, on the monitor (a flask, a tick or a cross) and
// as the strip's term. It runs on its state; a result that comes before
// kActLeadMs waits for it; a needs-you leaves it to come back where it got
// to; and no frame of it takes from the heap.
static void test_a_work_act_shows_on_the_monitor_and_the_strip() {
  static_assert(kActLeadMs == 900 && kActResultMs == 2600, "the times this test pins, the Mac's too (WorkStream)");
  Stream stream;
  Stream::ActIn in;
  in.kind = ActKind::kPush;
  std::strcpy(in.text, "git push");
  stream.setAct(in, false, 1000);
  Stream::ActNow now = stream.actNow(1500);
  TEST_ASSERT_TRUE(now.shows());
  TEST_ASSERT_EQUAL_INT(500, now.ageMs);
  // Running: its words, with dots.
  TEST_ASSERT_EQUAL_STRING("git push", now.text);
  TEST_ASSERT_TRUE(now.result == ActResult::kRunning);
  TEST_ASSERT_EQUAL_INT(-1, now.leftMs);
  // Held away, it runs on unseen; back, where it got to.
  Stream::ActIn none;
  stream.setAct(none, true, 1600);
  TEST_ASSERT_FALSE(stream.actNow(1600).shows());
  stream.setAct(in, false, 1700);
  TEST_ASSERT_EQUAL_INT(700, stream.actNow(1700).ageMs);
  // The command ends early: its result waits for kActLeadMs.
  in.result = ActResult::kPass;
  std::strcpy(in.text, "shipped!");
  stream.setAct(in, false, 1750);
  TEST_ASSERT_EQUAL_INT(int(ActResult::kRunning), int(stream.actNow(1750).result));
  TEST_ASSERT_EQUAL_STRING("git push", stream.actNow(1750).text);
  const uint32_t begins = 1000 + kActLeadMs;
  now = stream.actNow(begins);
  TEST_ASSERT_EQUAL_INT(int(ActResult::kPass), int(now.result));
  TEST_ASSERT_EQUAL_STRING("shipped!", now.text);
  TEST_ASSERT_EQUAL_INT(int(kActResultMs), now.leftMs);
  TEST_ASSERT_FALSE(stream.actNow(begins + kActResultMs).shows());
  // A failure's sign has a cross.
  Stream failing;
  in.result = ActResult::kFail;
  std::strcpy(in.text, "fail");
  failing.setAct(in, false, 0);
  TEST_ASSERT_TRUE(failing.actNow(kActLeadMs).result == ActResult::kFail);
  TEST_ASSERT_EQUAL_STRING("fail", failing.actNow(kActLeadMs).text);
  // The state gone and nothing else holding the screen: it's over.
  stream.setAct(none, false, begins + 100);
  TEST_ASSERT_FALSE(stream.actNow(begins + 100).shows());

  auto e = std::make_unique<Engine>();
  Facts working;
  working.base = SceneState::kWorking, working.act = SceneState::kWorking;
  e->setFacts(working);
  for (int t = 0; t <= 960; t += 16) e->step(t);
  const SignShow sign;
  const Strip strip;
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  // An act is the work's, never a card: the monitor's flask, and with an
  // agent at work, the strip's term ("running tests" for "make"). Above the
  // monitor all is drawn as with none.
  {
    Stream plain, acting;
    Stream::Lane lane;
    lane.slot = 0, lane.count = 1, std::strcpy(lane.word, "make");
    plain.setLanes(&lane, 1, true, false, 0);
    acting.setLanes(&lane, 1, true, false, 0);
    Stream::ActIn tests;
    tests.kind = ActKind::kTests;
    std::strcpy(tests.text, "running tests");
    acting.setAct(tests, false, 0);
    s.invalidate();
    paintFrame(s, *e, false, 0, nullptr, sign, strip, {}, rig::kRest, nullptr, 0, &plain, 600);
    const std::vector<uint16_t> bare(px);
    s.invalidate();
    paintFrame(s, *e, false, 0, nullptr, sign, strip, {}, rig::kRest, nullptr, 0, &acting, 600);
    const size_t lane0 = size_t(502) * (410 * kLaneTop / kHeight), monitor0 = size_t(502) * (410 * 600 / 1000);
    TEST_ASSERT_EQUAL_MEMORY(bare.data(), px.data(), monitor0 * 2);
    TEST_ASSERT_TRUE(std::memcmp(bare.data() + monitor0, px.data() + monitor0, (lane0 - monitor0) * 2) != 0);
    TEST_ASSERT_EQUAL_MEMORY(bare.data() + lane0, px.data() + lane0, (px.size() - lane0) * 2);
    Strip busy;
    busy.busy = 1;
    s.invalidate();
    paintFrame(s, *e, false, 0, nullptr, sign, busy, {}, rig::kRest, nullptr, 0, &plain, 600);
    const std::vector<uint16_t> made(px);
    s.invalidate();
    paintFrame(s, *e, false, 0, nullptr, sign, busy, {}, rig::kRest, nullptr, 0, &acting, 600);
    TEST_ASSERT_TRUE(std::memcmp(made.data() + lane0, px.data() + lane0, (px.size() - lane0) * 2) != 0);
  }
  // Every beat of every result, off the heap.
  allocCount = 0;
  allocCounting = true;
  for (const ActKind kind : {ActKind::kTests, ActKind::kPush, ActKind::kBuild})
    for (const ActResult result : {ActResult::kRunning, ActResult::kPass, ActResult::kFail}) {
      Stream run;
      Stream::ActIn start;
      start.kind = kind;
      std::strcpy(start.text, "git push");
      run.setAct(start, false, 0);
      start.result = result;
      if (result != ActResult::kRunning) run.setAct(start, false, 4000);
      for (uint32_t t = 0; t < 8000; t += 137)
        paintFrame(s, *e, false, 0, nullptr, sign, strip, {}, rig::kRest, nullptr, 0, &run, t);
    }
  allocCounting = false;
  TEST_ASSERT_EQUAL_INT(0, allocCount);
}

// The body answers a work act's result once, as its sign changes
// (GelFace::answerAct): a pleased hop up at a pass, a flinch down at a
// fail, and then it settles while the result still shows.
static void test_the_body_answers_an_acts_result_once() {
  // How squashed the body is (the pull's second axis) `after` ms into the
  // result, with the act ended as `result`.
  auto squash = [](ActResult result, uint32_t after) {
    linkkit::Rng rng;
    app::Behaviour b(std::make_unique<GelFace>());
    b.reset(0, rng);
    b.face().watch(&b.stream());  // as Device does before it draws
    app::Model m;
    m.base = SceneState::kWorking, m.act = SceneState::kWorking, m.mood = Mood::kCalm;
    b.onState(m, 0);
    uint32_t t = 0;
    auto to = [&](uint32_t until) {
      while (t + 16 <= until) b.advance(t += 16, rng);
    };
    to(2000);
    m.workAct.kind = ActKind::kTests;
    std::strcpy(m.workAct.text, "running tests");
    b.onState(m, t);
    to(4000);
    if (result != ActResult::kRunning) {
      m.workAct.result = result;
      std::strcpy(m.workAct.text, result == ActResult::kPass ? "pass" : "fail");
      b.onState(m, t);
    }
    to(4000 + after);
    return static_cast<GelFace&>(b.face()).engine().pull[1].x;
  };
  const F running = squash(ActResult::kRunning, 112), pass = squash(ActResult::kPass, 112),
          fail = squash(ActResult::kFail, 112);
  TEST_ASSERT_TRUE(pass < running - q(.01));  // up
  TEST_ASSERT_TRUE(fail > running + q(.01));  // down
  // Still showing its result (kActResultMs), and at rest again: once.
  static_assert(kActResultMs > 2000, "the result outlasts the jolt");
  const F later = squash(ActResult::kRunning, 2000);
  TEST_ASSERT_TRUE(abs(squash(ActResult::kPass, 2000) - later) < q(.01));
  TEST_ASSERT_TRUE(abs(squash(ActResult::kFail, 2000) - later) < q(.01));
}

// A running act's sign holds the lane, but what Boop says takes it, as it does
// from any other low sign: talking to it during a long test shows the words.
static void test_words_take_the_lane_from_a_running_act() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  auto e = std::make_unique<Engine>();
  for (int t = 0; t <= 960; t += 16) e->step(t);
  const SignShow none;
  const Strip strip;
  Stream stream;
  Stream::ActIn start;
  start.kind = ActKind::kTests;
  std::strcpy(start.text, "running tests");
  stream.setAct(start, false, 0);
  const uint32_t t = 2500;
  paintFrame(s, *e, false, 0, nullptr, none, strip, {}, rig::kRest, nullptr, 0, &stream, t);
  const std::vector<uint16_t> sign(px);
  paintFrame(s, *e, false, 0, "hello there", none, strip, {}, rig::kRest, nullptr, 0, &stream, t);
  TEST_ASSERT_TRUE(px != sign);
  const std::vector<uint16_t> said(px);
  // And back to the sign once they're over.
  paintFrame(s, *e, false, 0, nullptr, none, strip, {}, rig::kRest, nullptr, 0, &stream, t);
  TEST_ASSERT_TRUE(px == sign);
  TEST_ASSERT_TRUE(px != said);
}

// The work stream on the gel: nothing falls behind the body, its lanes
// alone draw nothing above the lane; a word forward flies from the monitor
// and is drawn over the body; the body answers a hit as it lands, knocked
// and its lids shut, opening again after the daze; and drawing it all
// takes nothing from the heap.
static void test_the_work_stream_hits_from_the_monitor() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  auto e = std::make_unique<Engine>();
  for (int t = 0; t <= 960; t += 16) e->step(t);
  Stream stream;
  Stream::Lane lanes[2];
  lanes[0].slot = 0, lanes[0].count = 1, std::strcpy(lanes[0].word, "grep");
  lanes[1].slot = 1, lanes[1].count = 1, std::strcpy(lanes[1].word, "sed");
  stream.setLanes(lanes, 2, true, false, 0);
  const SignShow none;
  const Strip strip;
  paintFrame(s, *e, false, 0, nullptr, none, strip);
  const std::vector<uint16_t> bare(px);
  paintFrame(s, *e, false, 0, nullptr, none, strip, {}, rig::kRest, nullptr, 0, &stream, 600);
  // No words fall: above the lane, the frame is as with no stream.
  const size_t lane0 = size_t(502) * (410 * kLaneTop / kHeight);
  TEST_ASSERT_EQUAL_MEMORY(bare.data(), px.data(), lane0 * 2);
  // A failure flies at its face from the monitor, and lands; in flight,
  // it's drawn between the monitor and the face.
  stream.startCall("make", 1, CallStyle::kBonk, 1000);
  paintFrame(s, *e, false, 0, nullptr, none, strip, {}, rig::kRest, nullptr, 0, &stream, 1100);
  int changed = 0;
  for (int y = 180; y < 280; ++y)
    for (int x = 80; x < 260; ++x) changed += px[size_t(y) * 502 + x] != bare[size_t(y) * 502 + x];
  TEST_ASSERT_TRUE(changed > 40);
  TEST_ASSERT_EQUAL_UINT32(380, callFlightMs(CallStyle::kBonk));
  TEST_ASSERT_EQUAL_INT(int(CallMove::kHit), int(callMove(CallStyle::kBonk)));
  const F open = e->blink();
  e->jolt(q(1.2), q(3.2), q(-3), q(.75), 900);
  TEST_ASSERT_TRUE(e->blink() >= q(.75));
  for (int t = 976; t <= 976 + 112; t += 16) e->step(t);
  TEST_ASSERT_TRUE(abs(e->pull[1].x) > q(.01));  // squashed by the knock
  for (int t = 1104; t <= 976 + 544; t += 16) e->step(t);
  TEST_ASSERT_TRUE(e->blink() >= q(.75));  // still dazed, until the last kDazeOpenMs of its 0.9 s
  for (int t = 1536; t <= 1536 + 800; t += 16) e->step(t);
  TEST_ASSERT_TRUE(e->blink() <= max(open, q(.2)));  // and open again after it
  // Every part of it, over and over, off the heap.
  allocCount = 0;
  allocCounting = true;
  for (uint32_t t = 1000; t < 3500; t += 100)
    paintFrame(s, *e, false, 0, nullptr, none, strip, {}, rig::kRest, nullptr, 0, &stream, t);
  for (int g = 0; g < int(CallStyle::kCount); ++g) {
    stream.startCall("x", 0, CallStyle(g), 4000);
    for (uint32_t t = 4000; t < 6500; t += 250)
      paintFrame(s, *e, false, 0, nullptr, none, strip, {}, rig::kRest, nullptr, 0, &stream, t);
  }
  allocCounting = false;
  TEST_ASSERT_EQUAL_INT(0, allocCount);
}

// A hit's daze across the engine clock's wrap (a uint32_t of milliseconds,
// 49.7 days): it lasts its time, and once over it's forgotten, so the
// clock coming round past its end again leaves the eyes open.
static void test_a_daze_ends_across_the_clock_wrap() {
  auto e = std::make_unique<Engine>();
  for (int t = 0; t <= 480; t += 16) e->step(t);
  e->elapsedMs = 0xFFFFFFFFu - 400;
  e->jolt(0, 0, 0, q(.75), 900);
  TEST_ASSERT_TRUE(e->daze() >= q(.75));
  uint32_t t = 496;
  for (; e->elapsedMs > 1000; t += 16) e->step(t);  // past the wrap, 400 ms in
  TEST_ASSERT_TRUE(e->elapsedMs < 100);
  TEST_ASSERT_TRUE(e->daze() >= q(.75));  // still dazed, until the last kDazeOpenMs of its 0.9 s
  for (const uint32_t end = t + 600; t <= end; t += 16) e->step(t);
  TEST_ASSERT_TRUE(e->daze() == F(0));  // and open after it
  // The clock round again, before where the daze ended: still open.
  e->elapsedMs = 100;
  TEST_ASSERT_TRUE(e->daze() == F(0));
  e->step(t);
  TEST_ASSERT_TRUE(e->daze() == F(0));
}

// It stands up on its sign, or the card would cover its mouth, easing with
// the card; not for a low sign.
static void test_it_rises_for_its_sign() {
  const SignShow up{"<3", kSignRiseMs, 1000};
  TEST_ASSERT_EQUAL_INT(14, SignLayer::kHopPx);
  TEST_ASSERT_EQUAL_INT(SignLayer::kHopPx, signHop(up));
  TEST_ASSERT_EQUAL_INT(0, signHop({"<3", 0, 1000}));
  TEST_ASSERT_EQUAL_INT(0, signHop({"<3", 2000, 0}));
  SignShow low = up;
  low.low = true;
  TEST_ASSERT_EQUAL_INT(0, signHop(low));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_fixed_math_and_motion);
  RUN_TEST(test_words_take_the_lane_from_a_running_act);
  RUN_TEST(test_the_work_stream_hits_from_the_monitor);
  RUN_TEST(test_a_work_act_shows_on_the_monitor_and_the_strip);
  RUN_TEST(test_the_body_answers_an_acts_result_once);
  RUN_TEST(test_a_daze_ends_across_the_clock_wrap);
  RUN_TEST(test_it_rises_for_its_sign);
  RUN_TEST(test_software_clock_matches_binary64);
  RUN_TEST(test_a_divisor_divides_exactly);
  RUN_TEST(test_all_expressions_draw_inside_native_surface);
  RUN_TEST(test_frame_replay_is_byte_identical);
  RUN_TEST(test_a_helper_draws_the_same_body);
  RUN_TEST(test_one_face_vocabulary_and_latest_facts);
  RUN_TEST(test_request_identity_and_cache_bounds);
  RUN_TEST(test_grid_voice_lead_and_late_cues);
  RUN_TEST(test_external_source_holds_without_repeating_reveal);
  RUN_TEST(test_interrupted_alert_signals_exactly_once);
  RUN_TEST(test_face_and_props_move_without_jumps);
  RUN_TEST(test_it_falls_asleep_squashing_shut);
  RUN_TEST(test_the_face_never_fades_while_arts_cross_over);
  RUN_TEST(test_a_face_coming_in_moves_nothing);
  RUN_TEST(test_the_lane_fades_whatever_the_draw_cadence);
  RUN_TEST(test_gel_clips_use_the_shared_mixer);
  RUN_TEST(test_each_cue_carries_its_own_duck);
  RUN_TEST(test_the_gel_draws_invites);
  RUN_TEST(test_the_glass_scales_the_body_to_115_at_most);
  RUN_TEST(test_one_pair_of_hands);
  RUN_TEST(test_the_knock_is_one_move_that_climbs);
  RUN_TEST(test_the_flop_plays_by_its_id);
  RUN_TEST(test_a_moments_clip_plays_by_its_own_name);
  RUN_TEST(test_the_turn_narrows_each_eye_on_its_own);
  RUN_TEST(test_the_meme_faces_and_their_moves);
  RUN_TEST(test_pick_is_pure_and_started_commits_it);
  RUN_TEST(test_a_power_on_seeds_the_engine_and_a_reset_restores_53);
  RUN_TEST(test_a_reset_lets_go_of_the_finger);
  RUN_TEST(test_a_finger_moves_the_dome_its_way);
  RUN_TEST(test_a_faded_art_never_comes_back);
  RUN_TEST(test_the_night_lids_ease_out_as_it_falls_asleep);
  RUN_TEST(test_timing_comes_from_the_recipe_table);
  RUN_TEST(test_comedy_plays_in_idle_and_asleep);
  RUN_TEST(test_each_gesture_plays_its_own_gag);
  RUN_TEST(test_a_low_or_cross_mood_keeps_its_face_through_a_gesture);
  RUN_TEST(test_a_notice_plays_its_rig_clip);
  RUN_TEST(test_a_reply_plays_its_clip_once);
  RUN_TEST(test_a_rig_clip_plays_on_the_gel);
  RUN_TEST(test_the_rig_carries_reaches_and_melts_the_gel);
  RUN_TEST(test_every_pastime_has_its_clip_and_its_turn);
  RUN_TEST(test_each_pastime_draws_and_ends);
  RUN_TEST(test_pastimes_are_dealt_by_tier_after_a_rest);
  RUN_TEST(test_transitions_play_between_doings_and_anything_urgent_cuts_through);
  RUN_TEST(test_a_tagged_pastime_plays_only_while_its_tag_is_on);
  RUN_TEST(test_the_eyes_rest_unless_theres_a_reason);
  RUN_TEST(test_a_look_is_a_turn_not_a_dart);
  RUN_TEST(test_it_types_along_with_you);
  RUN_TEST(test_the_eyes_with_you_in_order);
  RUN_TEST(test_the_eyes_follow_your_pointer);
  RUN_TEST(test_it_reads_along_while_you_scroll);
  RUN_TEST(test_it_grooves_to_your_music_and_watches_with_you);
  RUN_TEST(test_a_call_keeps_it_still);
  RUN_TEST(test_speaking_wins_over_typing);
  RUN_TEST(test_what_it_wears_and_has_beside_it);
  RUN_TEST(test_typing_fast_is_quicker_not_higher);
  RUN_TEST(test_nothing_with_you_without_the_facts);
  RUN_TEST(test_work_settles_by_tier);
  RUN_TEST(test_the_paws_type_on_the_keys);
  RUN_TEST(test_each_activity_is_a_pose);
  RUN_TEST(test_the_layers_come_and_go_through_the_stack);
  RUN_TEST(test_gel_draws_natively);
  RUN_TEST(test_face_projection_and_pose_bounds);
  RUN_TEST(test_tracked_clear_matches_full_clear);
  RUN_TEST(test_histories_stay_off_the_heap);
  RUN_TEST(test_kept_cards_and_lanes_match_a_fresh_frame);
  RUN_TEST(test_a_finished_turn_glows);
  RUN_TEST(test_the_low_sign_stays_in_the_lane_and_holds_a_long_name);
  RUN_TEST(test_the_strip_gives_way_to_the_finishs_sign);
  RUN_TEST(test_a_still_card_is_drawn_once_into_each_surface);
  RUN_TEST(test_steady_frames_allocate_nothing);
  RUN_TEST(test_text_draws_only_inside_its_bounds);
  RUN_TEST(test_the_lane_is_native_and_tracked);
  RUN_TEST(test_the_lane_clears_the_rounded_corners);
  RUN_TEST(test_the_strip_fades_as_one);
  RUN_TEST(test_the_lane_cuts_and_marks_as_the_canvas_does);
  RUN_TEST(test_the_working_spinner_turns_once_a_second);
  RUN_TEST(test_rgb565_opacity_rounds_to_nearest);
  RUN_TEST(test_polygons_cover_their_area_wherever_they_sit);
  RUN_TEST(test_polygon_edges_move_a_sixteenth_at_a_time);
  RUN_TEST(test_a_z_grows_and_drifts_by_sixteenths);
  RUN_TEST(test_a_clipped_polygon_covers_what_lies_in_both);
  RUN_TEST(test_a_cross_fade_never_shows_through);
  RUN_TEST(test_every_cross_fade_fits_its_room);
  RUN_TEST(test_strokes_keep_their_width_and_blend_once);
  RUN_TEST(test_the_body_outline_is_soft_without_seams);
  RUN_TEST(test_the_outline_holds_still_as_the_mesh_turns);
  RUN_TEST(test_the_materials_copy_draws_the_same_body);
  RUN_TEST(test_layers_follow_the_bodys_anchors);
  RUN_TEST(test_nothing_hangs_in_the_sky_or_the_air);
  RUN_TEST(test_a_recording_replays_as_drawn);
  RUN_TEST(test_a_recording_replays_between_pixels);
  RUN_TEST(test_text_glides_between_pixels);
  // test_cells.cpp
  RUN_TEST(test_every_cell_plays_truthfully);
  RUN_TEST(test_ten_minutes_of_work);
  RUN_TEST(test_held_and_interrupted_contacts);
  RUN_TEST(test_asleep_rests_still_but_for_a_snore);
  // test_finish.cpp
  RUN_TEST(test_a_finish_is_sized_by_its_turn_or_else_its_hold);
  RUN_TEST(test_the_face_picks_a_finish_and_plays_it_once);
  RUN_TEST(test_a_big_finish_cheers_once_and_bounces);
  RUN_TEST(test_a_takeover_puts_the_desk_away);
  RUN_TEST(test_every_finish_moves_smoothly_and_settles);
  RUN_TEST(test_gold_rush_floods_and_little_win_shows_its_trophy);
  RUN_TEST(test_only_what_draws_behind_erases_first);
  RUN_TEST(test_a_rapid_chain_settles_on_the_last);
  RUN_TEST(test_the_semantic_face_numbers);
  // test_motion.cpp
  RUN_TEST(test_the_motion_v1_numbers);
  RUN_TEST(test_the_motion_v2_numbers);
  RUN_TEST(test_each_motion_rule_off_gives_back_the_motion_before);
  RUN_TEST(test_the_motion_layer_comes_to_rest);
  RUN_TEST(test_hands_follow_and_change_owner_without_a_jump);
  RUN_TEST(test_the_seven_idle_moves);
  RUN_TEST(test_a_spin_never_unwinds);
  RUN_TEST(test_half_a_turn_off_still_turns);
  RUN_TEST(test_the_turn_comes_round_within_its_limits);
  RUN_TEST(test_the_finger_numbers);
  RUN_TEST(test_acting_timing_and_springs);
  RUN_TEST(test_setters_keep_springs_and_replay);
  RUN_TEST(test_the_scenes_formulas);
  // test_requests.cpp
  RUN_TEST(test_requests_route_by_priority);
  RUN_TEST(test_a_request_keeps_its_identity);
  RUN_TEST(test_cues_stay_sparse_and_quiet);
  RUN_TEST(test_a_request_sounds_once_whatever_changes);
  RUN_TEST(test_sound_draws_change_nothing_drawn);
  // test_hand.cpp
  RUN_TEST(test_the_eyes_follow_a_finger);
  RUN_TEST(test_a_finger_leaves_the_dice_alone);
  RUN_TEST(test_a_lean_goes_where_the_finger_is);
  RUN_TEST(test_a_finger_at_rest_leans_then_dozes_and_lifting_wakes);
  RUN_TEST(test_lifting_a_doze_wakes_it_with_a_start);
  RUN_TEST(test_a_short_hold_stays_a_tap);
  RUN_TEST(test_a_stroke_and_a_tickle_stay_theirs);
  RUN_TEST(test_a_hold_on_the_needs_you_screen_only_dismisses);
  RUN_TEST(test_a_needs_you_under_a_lean_ends_it);
  RUN_TEST(test_a_finish_keeps_its_touches);
  RUN_TEST(test_listening_takes_the_face_from_a_lean);
  RUN_TEST(test_a_hold_on_the_strip_is_the_drawers);
  RUN_TEST(test_an_asks_lane_keeps_its_held_tap);
  RUN_TEST(test_a_moment_cuts_a_lean);
  RUN_TEST(test_a_drag_starts_where_the_finger_is_on_the_dome);
  RUN_TEST(test_a_leans_breath_minds_the_volume);
  RUN_TEST(test_a_lean_allocates_nothing);
  RUN_TEST(test_a_tilt_sloshes_and_settles);
  RUN_TEST(test_a_tilt_gives_way);
  RUN_TEST(test_a_tilt_allocates_nothing);
  RUN_TEST(test_listening_nods);
  RUN_TEST(test_a_touch_says_why_itself);
  RUN_TEST(test_the_macs_reason_doesnt_double_a_touchs);
  RUN_TEST(test_a_reason_alone);
  // test_drawer.cpp
  RUN_TEST(test_a_pull_up_the_strip_opens_the_drawer);
  RUN_TEST(test_a_swipe_up_the_face_isnt_the_drawers);
  RUN_TEST(test_a_short_pull_springs_back_shut);
  RUN_TEST(test_a_tap_on_a_row_picks_it);
  RUN_TEST(test_it_shuts_itself_and_says_its_open_till_then);
  RUN_TEST(test_boot_shuts_it);
  RUN_TEST(test_the_drawers_rows_on_the_panel);
  RUN_TEST(test_a_long_drawers_rows_scroll);
  RUN_TEST(test_a_finger_scrolls_a_long_drawer);
  RUN_TEST(test_the_body_under_the_drawer);
  RUN_TEST(test_a_reaction_shows_the_drawer_once_its_sign_is_read);
  RUN_TEST(test_a_finger_or_a_request_first_keeps_it_shut);
  RUN_TEST(test_holding_boot_to_talk_shuts_it);
  RUN_TEST(test_drawer_frames_allocate_nothing);
  return UNITY_END();
}
