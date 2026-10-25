// Complete integer engine, native surface bounds and face seam.
#include <unity.h>
#include <cmath>
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
#include "render/pixel/anim.h"
#include "app/behaviour.h"
#include "render/gel/sounds.h"
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
  e->setMood(slime::kFrightened);
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
// is 1025 × 513 texels, under a pixel each across the dome's middle, then
// half that for where they crowd under a pixel.
static void test_the_materials_copy_draws_the_same_body() {
  size_t bytes = 0;
  GelFace face;
  const void* texels = face.assets(bytes);
  TEST_ASSERT_EQUAL_UINT32((1025u * 513u + 513u * 257u) * 2u, bytes);
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
// A card revealed late, in its recipe's last 480 ms (no recipe's is yet),
// still shows: it rises whole over kCardRevealMs, then falls over the
// recovery, where it never rose at all.
static void test_a_card_revealed_late_rises_then_falls() {
  auto e = std::make_unique<Engine>();
  e->step(0);
  Request req;
  req.anim = SceneState::kTaskComplete;
  req.outcome = Outcome::kFailure;
  req.hold = true;
  e->oneShot(req);
  e->step(16);
  slime::Recipe& r = e->scenes.recipe;
  int moved = 0;
  for (int i = 0; i < r.count; ++i)
    if (r.contacts[i].kind == kFailure) r.contacts[i].at = r.duration - T(200), ++moved;
  TEST_ASSERT_EQUAL_INT(1, moved);
  const int end = F(r.duration + T(1000)).integer();
  F most = 0;
  for (int t = 32; t <= end; t += 16) {
    e->step(uint32_t(t));
    most = max(most, e->scenes.visible(Scenes::kResultProp, e->timeMs()));
  }
  TEST_ASSERT_TRUE(most > q(.99));
  TEST_ASSERT_TRUE(e->scenes.visible(Scenes::kResultProp, e->timeMs()) == F(0));
}
// A failure or a reply whose finish names whose turn it was shows no card:
// its ticket takes the card's place (render/gel/done.h).
static void test_a_named_finish_shows_no_card() {
  for (bool named : {false, true}) {
    auto e = std::make_unique<Engine>();
    e->step(0);
    e->scenes.cardless = named;
    Request req;
    req.anim = SceneState::kTaskComplete;
    req.outcome = Outcome::kFailure;
    req.hold = true;
    e->oneShot(req);
    F most = 0;
    for (int t = 16; t <= 6400; t += 16) {
      e->step(uint32_t(t));
      most = max(most, e->scenes.visible(Scenes::kResultProp, e->timeMs()));
    }
    TEST_ASSERT_TRUE(named ? most == F(0) : most > q(.99));
  }
}
// A finished turn's marks (render/gel/done.h). The glow comes over
// kGlowInMs to kGlowPeak at the panel's edge (a reply's to kGlowPeakFaint),
// holds while its reaction plays, and fades over the last kGlowOutMs; it
// reaches kGlowPx in, and nothing shows past the panel's rounded corners.
// The ticket drops in from above the top over kTicketDropMs and hangs in
// the middle, or left of a success's trophy, and goes back up over the last
// kTicketRiseMs.
static void test_a_finished_turn_glows_and_hangs_a_ticket() {
  static_assert(kGlowInMs == 300 && kGlowOutMs == 1000 && kGlowPx == 26, "the glow's timing and reach");
  static_assert(kGlowPeak == 200 && kGlowPeakFaint == 110, "the glow's strength at the edge");
  static_assert(kTicketDropMs == 700 && kTicketRiseMs == 400, "the ticket's drop and rise");
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

  // The ticket: above the top as it comes, then in, in the middle.
  d.ms = 0, d.leftMs = -1;
  fresh();
  paintTicket(s, d);
  TEST_ASSERT_EQUAL_INT(0, lit(0, 1, kW, kH));
  d.ms = kTicketDropMs + 3000;
  fresh();
  paintTicket(s, d);
  const int left = lit(0, 20, kW / 2, 70), right = lit(kW / 2, 20, kW, 70);
  TEST_ASSERT_TRUE(left > 300 && right > 300);
  TEST_ASSERT_INT_WITHIN((left + right) / 5, left, right);
  TEST_ASSERT_EQUAL_INT(0, lit(0, 80, kW, kH));
  // A success's hangs left of its trophy.
  d.outcome = Outcome::kSuccess;
  fresh();
  paintTicket(s, d);
  TEST_ASSERT_TRUE(lit(0, 20, kW * 420 / 1000, 70) > 300);
  TEST_ASSERT_EQUAL_INT(0, lit(kW * 420 / 1000 + 8, 0, kW, kH));
  // Gone back up.
  d.leftMs = 0;
  fresh();
  paintTicket(s, d);
  TEST_ASSERT_EQUAL_INT(0, lit(0, 1, kW, kH));
}
// Every result card has a mark over its label, none an empty top half: a
// cross for a failure or a tool error, a soft stop square when stopped,
// three dots for the other neutral ones (a finish with no outcome, a reply
// ready). A success shows its trophy and no card (render/gel/finish.h).
static void test_every_result_card_has_a_mark() {
  struct Card {
    SceneState anim;
    Outcome outcome;
    uint16_t fill;
  };
  const uint16_t bad = rgb565(62, 43, 56), neutral = rgb565(36, 56, 71);
  const Card cards[] = {{SceneState::kTaskComplete, Outcome::kFailure, bad},
                        {SceneState::kError, Outcome::kNone, bad},
                        {SceneState::kTaskComplete, Outcome::kNone, neutral},
                        {SceneState::kReplyReady, Outcome::kNone, neutral},
                        {SceneState::kStopped, Outcome::kNone, neutral}};
  constexpr int kW = 502, kH = 410;
  std::vector<uint16_t> px(kW * kH);
  Surface s{kW, kH, px.data()};
  for (const Card& card : cards) {
    auto e = std::make_unique<Engine>();
    e->step(0);
    Request req;
    req.anim = card.anim;
    req.outcome = card.outcome;
    req.hold = true;
    e->oneShot(req);
    for (int t = 16; t <= 2400; t += 16) e->step(uint32_t(t));
    s.invalidate(), s.clear();
    paint(s, *e);
    int marked = 0, filled = 0;  // between the card's sides, over its label
    for (int y = kH * 95 / 1000; y < kH * 180 / 1000; ++y)
      for (int x = kW * 440 / 1000; x < kW * 560 / 1000; ++x) {
        const uint16_t v = px[size_t(y) * kW + x];
        filled += v == card.fill, marked += v != card.fill;
      }
    TEST_ASSERT_TRUE_MESSAGE(filled > 1000, "the card shows");
    TEST_ASSERT_TRUE_MESSAGE(marked > 40, "with a mark over its label");
  }
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
// Across every directed edge the
// two arts cross over, their weights summing to one, each stepping no more
// than a slice of the shortest face window's ramp, the new one last; each
// drawn ratio stays inside (0.75, 4/3) and moves its drawn size no further
// than its control; a retarget keeps the controls' velocity, and a fifth art
// drops the faintest; and the alert
// sign ramps in and out with no step larger than a slice of its ramp.
static void test_face_and_props_move_without_jumps() {
  const F weightStep = q(.149), rampStep = q(.134);
  const int controls[] = {2, 4, 5};
  for (int i = 0; i < slime::kEdgeCount; ++i) {
    auto e = std::make_unique<Engine>();
    e->setMood(slime::kEdges[i].from);
    for (uint32_t t = 0; t <= 640; t += 16) e->step(t);
    e->setMood(slime::kEdges[i].to, i % 3);
    SemanticFace before = e->face;
    bool crossed = false;
    for (uint32_t t = 656; t <= 1280; t += 16) {
      e->step(t);
      const auto& f = e->face;
      TEST_ASSERT_EQUAL_INT(slime::kEdges[i].to, f.current().art);
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
  face.setMood(slime::kFrightened);
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
// fast, into a longer window (a bridge's 460 ms), dips below zero and comes
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
// happy to sad and calm to frightened never less than the fainter face).
static void test_the_face_never_fades_while_arts_cross_over() {
  std::vector<uint16_t> a(502 * 410), b(a.size());
  Surface drawn{502, 410, a.data()}, bare{502, 410, b.data()};
  struct Case {
    int from, to;
    SceneState base, then;
  } cases[] = {{slime::kCalm, slime::kHappy, SceneState::kIdle, SceneState::kIdle},
               {slime::kHappy, slime::kSad, SceneState::kIdle, SceneState::kIdle},
               // frightened's welling eyes: a pool over a bean, with a glint
               {slime::kCalm, slime::kFrightened, SceneState::kIdle, SceneState::kIdle},
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
        b.face().draw(c, &s, b.show(t), t, b.bubble(t), b.sign(t), b.done(t), b.strip(t), dirty);
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
  // Fourteen sketches, three takes each: comedy's sneeze and snore breath
  // too, and a big finish's cheer.
  TEST_ASSERT_EQUAL_INT(42, clips.count());
  TEST_ASSERT_EQUAL_STRING("gel-sketch-v1", clips.version());
  TEST_ASSERT_EQUAL_INT(clips.index("knock-2"), clipFor("knock", 2));
  TEST_ASSERT_EQUAL_INT(-1, clipFor("knock", 3));
  TEST_ASSERT_EQUAL_INT(-1, clipFor("knoc", 0));
  for (const char* recipe : {"sneeze", "breath", "bounce", "cheer"})
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
// At night the lids hang lower, and they go with the face falling asleep:
// as it squashes shut they ease out, gone by when it's a line (1 s), a
// sixteenth of their hang in a 16 ms frame at the most, where they went in
// one; and waking, they come back on the face's quick spring.
static void test_the_night_lids_ease_out_as_it_falls_asleep() {
  auto e = std::make_unique<Engine>();
  e->setOccasion(tagBit("night"), 0);
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
  // Two rows have a fourth take. A success's is its
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
// Idle's takes are an expression's three gestures,
// its own gags and the three idle gags, and its bag deals the gags from its
// second round. A yawn stretches up with its eyes squeezed; a doze droops
// the lids and sinks the dome, then snaps open with a blink; the zoomies
// slide it edge to edge and back; a sneeze is a contact a second in that
// may sound, lurching it forward, all off the heap; the long yawn ends
// heavy-lidded, then wakes. Asleep snores only after a round of still
// rests, and a lost link never.
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
  const auto yawn = play(slime::kCalm, 3, 3000);
  TEST_ASSERT_TRUE(at(yawn, 1.2)[3] > q(.04) && at(yawn, 1.2)[5] > q(.7));
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
  TEST_ASSERT_TRUE(at(play(slime::kCalm, 5, 2800), 1.15)[4] > q(.08));  // the sneeze lurches forward
  const auto longYawn = play(slime::kTired, 3, 5400);
  TEST_ASSERT_TRUE(at(longYawn, 3.2)[5] > q(.35) && at(longYawn, 5)[5] < q(.05));
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
// The gesture state has a take for each of
// render::Gesture, each its own gag under the face it borrows; the board
// names the take, and no bag deals it. Each plays held, under its face with
// its gag, the mood kept, each contact once, and gives the face back; each
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
// face starts: each of the twelve replies has one; a shake of the head
// swings the body side to side; the same reply still showing doesn't play
// it again, the next one does; and a reply with no clip plays nothing.
static void test_a_reply_plays_its_clip_once() {
  const char* replies[] = {"yes",    "no",   "dunno", "huh",  "hello",   "bye",
                           "thanks", "love", "ouch",  "hehe", "comfort", "status"};
  char name[24];
  for (const char* r : replies) {
    std::snprintf(name, sizeof(name), "reply-%s", r);
    TEST_ASSERT_NOT_NULL_MESSAGE(rig::kRig.clip(name), name);
  }
  linkkit::Rng rng;
  GelFace face;
  face.reset(0, rng);
  FaceSource s;
  FaceContext c;
  c.mood = s.mood = Mood::kCalm;
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
  c.reply = "dance", c.replyAt = 5000;
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
// family's with no card, timed to the clip and 200 ms more, with no gag or
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
  const int row = int(SceneState::kNotice);
  for (int v = 0; v < 3; ++v) {
    const auto& r = take(slime::kGrumpy, row, v);
    TEST_ASSERT_TRUE(r.gag < 0 && r.count == 0 && r.label == nullptr);
    TEST_ASSERT_EQUAL_INT(clip->ms + 200, F(r.duration).integer());
    TEST_ASSERT_TRUE(slime::kNoticeFaces[v] >= 0 && slime::kNoticeFaces[v] < slime::kProfiles);
  }
  for (int v = 0; v < 3; ++v) {
    GelFace face;
    face.reset(0, rng);
    FaceSource s;
    FaceContext c;
    c.mood = s.mood = Mood::kCalm;
    c.base = SceneState::kWorking, c.act = SceneState::kTerminal;
    s.look = SceneState::kTerminal;
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
      TEST_ASSERT_TRUE(e.acting.playing < 0);                                      // no gag: the clip moves it
      TEST_ASSERT_TRUE(e.scenes.visible(Scenes::kStartProp, e.timeMs()) == F(0));  // no card
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
    TEST_ASSERT_TRUE(e.scenes.route.state == SceneState::kTerminal);
    TEST_ASSERT_EQUAL_STRING("calm", slime::kProfile[e.expression].id);
    TEST_ASSERT_EQUAL_MEMORY(&rig::kRest, &face.mixer().channels(), sizeof rig::kRest);
  }
}
// A look's takes for tags and waits, dealt only
// while they fit, and only the one that fits. Idle drowses at night,
// stretches in the morning, bounces at a party and at New Year's (the
// party's own bounce), and nods off at idle's last tier, tier5, by that tag
// alone however long it has shown; with no tag on, or tags none needs, it
// plays none. Work types busier while busy and frantically while frantic,
// and plays nothing of its own at tier4 (the rig's stretch and the
// pastimes play there: test_a_rig_clip_plays_on_both_faces); asleep snores
// deeper at night and dreams after half an hour.
static void test_occasions_play_only_while_they_fit() {
  // The occasions idle played, by their gags.
  auto idle = [](uint32_t when, uint32_t lookMs) {
    auto e = std::make_unique<Engine>();
    e->setOccasion(when, lookMs);
    std::set<std::string> played;
    int last = -1;
    for (uint32_t t = 0; t <= 120000; t += 16) {
      e->step(t);
      if (e->acting.performance != last && e->acting.performance >= Acting::takes(e->emotion)) {
        const auto& o = slime::kIdleOccasions[e->acting.performance - Acting::takes(e->emotion)];
        TEST_ASSERT_TRUE(fits(o.when, o.after, when, lookMs));
        played.insert(slime::kGags[o.gag].gesture.type);
      }
      last = e->acting.performance;
    }
    return played;
  };
  using Played = std::set<std::string>;
  TEST_ASSERT_TRUE(idle(0, 0).empty());
  TEST_ASSERT_TRUE(idle(tagBit("day") | tagBit("weekend"), 0).empty());
  TEST_ASSERT_TRUE((idle(tagBit("night"), 0) == Played{"occasion:night-drowse"}));
  TEST_ASSERT_TRUE((idle(tagBit("morning"), 0) == Played{"occasion:morning-stretch"}));
  TEST_ASSERT_TRUE((idle(tagBit("party"), 0) == Played{"occasion:party-bounce"}));
  TEST_ASSERT_TRUE((idle(tagBit("newyear"), 0) == Played{"occasion:party-bounce"}));
  TEST_ASSERT_TRUE(idle(0, 7200000).empty());
  TEST_ASSERT_TRUE((idle(tagBit("tier5"), 0) == Played{"occasion:nod-off"}));
  // Work: an occasion's take is numbered after the row's own; the ones
  // played, as kLookOccasions numbers them.
  auto work = [](SceneState base, uint32_t when, uint32_t lookMs) {
    auto e = std::make_unique<Engine>();
    Facts facts;
    facts.base = base;
    e->setFacts(facts);
    e->setOccasion(when, lookMs);
    std::set<int> played;
    for (uint32_t t = 0; t <= 60000; t += 16) {
      e->step(t);
      if (e->scenes.variant >= takes(int(base))) {
        const int i = e->scenes.variant - takes(int(base));
        const auto& o = slime::kLookOccasions[i];
        TEST_ASSERT_EQUAL_INT(int(base), o.row);
        TEST_ASSERT_TRUE(fits(o.when, o.after, when, lookMs));
        played.insert(i);
      }
    }
    return played;
  };
  // Exactly one occasion played: the one that needs these tags and this
  // wait, with this gag (or none).
  auto only = [](const std::set<int>& played, uint32_t when, uint16_t after, const char* gag) {
    TEST_ASSERT_EQUAL_INT(1, int(played.size()));
    const auto& o = slime::kLookOccasions[*played.begin()];
    TEST_ASSERT_TRUE(o.when == when && o.after == after);
    if (gag)
      TEST_ASSERT_EQUAL_STRING(gag, slime::kGags[o.recipe.gag].gesture.type);
    else
      TEST_ASSERT_EQUAL_INT(-1, o.recipe.gag);
  };
  TEST_ASSERT_TRUE(work(SceneState::kWorking, 0, 0).empty());
  TEST_ASSERT_TRUE(busyTags(2) == tagBit("busy") && busyTags(5) == tagBit("frantic"));
  only(work(SceneState::kWorking, busyTags(2), 0), tagBit("busy"), 0, nullptr);
  only(work(SceneState::kWorking, busyTags(5), 0), tagBit("frantic"), 0, nullptr);
  TEST_ASSERT_TRUE(work(SceneState::kWorking, 0, 7200000).empty());
  TEST_ASSERT_TRUE(work(SceneState::kWorking, tagBit("tier4"), 0).empty());
  only(work(SceneState::kAsleep, tagBit("night"), 0), tagBit("night"), 0, nullptr);
  only(work(SceneState::kAsleep, 0, 1800000), 0, 1800, "occasion:dream");
  TEST_ASSERT_TRUE(work(SceneState::kAsleep, 0, 1799000).empty());
}
// A clip authored once in the pack's rig/clips/ plays on both of its faces:
// the look's occasion (rig/looks.json, working's stretch from tier4)
// through each face's mixer, the gel's laid over the engine's pose
// (applyRig) and Pixel's on its rig face: Pixel's at the end of a pass of
// the look's loop, render::rig::kOccasionPct of the chances, and the gel's
// dealt with its pastimes (test_pastimes_are_dealt_by_tier_after_a_rest).
// Without the tag neither face plays it; the gel's mixer stays at rest, so
// nothing it draws changes; and a reaction fades it out.
static void test_a_rig_clip_plays_on_both_faces() {
  const rig::Clip* stretch = rig::kRig.clip("stretch");
  TEST_ASSERT_NOT_NULL(stretch);
  const rig::Look* working = rig::kRig.look(SceneState::kWorking);
  TEST_ASSERT_EQUAL_INT(1, working->fitting(tagBit("tier4"), 0));
  TEST_ASSERT_EQUAL_PTR(stretch, working->fitting(tagBit("tier4") | tagBit("day"), 0, 0));
  TEST_ASSERT_EQUAL_INT(0, working->fitting(tagBit("tier3"), 0));
  // The tallest squash and the most shut eyes each face's mixer reaches at
  // work, over a minute, the gel's over two while no pastime of its own
  // plays (a look's occasion, then), and when the gel's first left rest.
  struct Seen {
    int squash = 0, open = 1000;
    uint32_t moved = 0;
  };
  auto play = [](bool gel, uint32_t when, uint32_t pokeAt = 0) {
    linkkit::Rng rng;
    std::unique_ptr<Face> face;
    if (gel)
      face = std::make_unique<GelFace>();
    else
      face = std::make_unique<pixel::PixelFace>();
    app::Behaviour b(std::move(face));
    b.reset(0, rng);
    app::Model m;
    m.base = SceneState::kWorking, m.act = SceneState::kTerminal, m.mood = Mood::kHappy, m.when = when;
    b.onState(m, 0);
    Seen seen;
    for (uint32_t t = 16; t <= (gel ? 120000u : 60000u); t += 16) {
      if (pokeAt && t == pokeAt) {
        app::ReactionIn in;
        in.anim = SceneState::kPoked;
        in.id = 7;
        in.variant = b.pick(in.anim, m.mood, 255, in.outcome, StartCtx::kNone, rng);
        b.play(in, t);
      }
      b.advance(t, rng);
      const rig::Mixer& mixer = gel ? static_cast<GelFace&>(b.face()).mixer()
                                    : static_cast<pixel::PixelFace&>(b.face()).rigFace().mixer();
      const rig::Channels& c = mixer.channels();
      if (!gel || static_cast<GelFace&>(b.face()).pastimes(t).playing == Pastime::kNone) {
        seen.squash = std::min<int>(seen.squash, c[rig::Channel::kSquash]);
        seen.open = std::min<int>(seen.open, std::min(c[rig::Channel::kEyeOpenL], c[rig::Channel::kEyeOpenR]));
      }
      if (gel && !seen.moved && std::memcmp(&c, &rig::kRest, sizeof c)) seen.moved = t;
      if (pokeAt && t >= pokeAt + 400) {
        // The poke's reaction faded the stretch, or the pastime, out.
        TEST_ASSERT_TRUE(c[rig::Channel::kSquash] >= -30);
        TEST_ASSERT_TRUE(c[rig::Channel::kEyeOpenL] > 900);
      }
      if (pokeAt && t >= pokeAt + 400) break;
    }
    return seen;
  };
  for (bool gel : {true, false}) {
    const Seen tier4 = play(gel, tagBit("tier4")), plain = play(gel, tagBit("day"));
    TEST_ASSERT_TRUE(tier4.squash <= -115);  // up tall: the stretch's -130 at its height
    TEST_ASSERT_TRUE(tier4.open <= 320);     // eyes squeezed: its -700 on 1000 (and Pixel blinks)
    TEST_ASSERT_TRUE(plain.squash >= -30);   // the look's own breathing at most (Pixel's)
    if (gel) {
      TEST_ASSERT_EQUAL_UINT32(0, plain.moved);  // the gel's mixer at rest throughout
      TEST_ASSERT_TRUE(tier4.moved > 0);
      play(gel, tagBit("tier4"), tier4.moved + 608);
    }
  }
  // On the gel the rig's channels move what the painter draws: taller, its
  // crown higher, and its lids down; at rest, nothing.
  auto e = std::make_unique<Engine>();
  for (uint32_t t = 0; t <= 1600; t += 16) e->step(t);
  PaintControls rest, moved;
  rest.squash = 100, rest.lean = -40, rest.lift = 20, rest.blink = 300;
  moved = rest;
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
void test_fixed_math_and_motion();
void test_software_clock_matches_binary64();
void test_a_divisor_divides_exactly();
// test_cells.cpp
void test_every_cell_plays_truthfully();
void test_ten_minutes_of_work();
void test_held_and_interrupted_contacts();
void test_card_reveal_trajectory();
void test_asleep_rests_still_but_for_a_snore();
// test_finish.cpp
void test_a_finish_is_sized_by_its_turn_or_else_its_hold();
void test_each_mood_takes_turns_between_its_big_finishes();
void test_the_face_picks_a_finish_and_plays_it_once();
void test_a_big_finish_cheers_once_and_bounces();
void test_a_takeover_puts_the_desk_away();
void test_every_finish_moves_smoothly_and_settles();
void test_gold_rush_floods_and_little_win_shows_its_trophy();
void test_only_what_draws_behind_erases_first();
// test_bridges.cpp
void test_every_edge_bridges_as_authored();
void test_a_bridge_follows_its_waveform();
void test_a_grab_defers_then_expires_the_bridge();
void test_a_quiet_or_alerting_body_holds_the_bridge();
void test_a_rapid_chain_settles_on_the_last();
void test_each_edge_deals_its_own_bag();
void test_the_semantic_face_numbers();
// test_motion.cpp
void test_the_motion_v1_numbers();
void test_the_finger_numbers();
void test_acting_timing_and_springs();
void test_setters_keep_springs_and_replay();
void test_the_scenes_formulas();
// test_pastimes.cpp
void test_every_pastime_has_its_clip_and_its_turn();
void test_each_pastime_draws_and_ends();
void test_pastimes_are_dealt_by_tier_after_a_rest();
void test_the_kit_follows_the_tiers();
void test_the_headphones_play_a_tune();
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
// The layers (render/gel/layers.h) sit on the anchors of the pose that drew
// the body: the crown over the brim's ring over the hands'; they move with
// the body. The outfit is the first that fits its tags, and a night's lids
// hang lower but asleep.
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
  TEST_ASSERT_EQUAL(int(Outfit::kNone), int(outfitFor(tags({"day", "friday"}))));
  TEST_ASSERT_EQUAL(int(Outfit::kNightcap), int(outfitFor(tags({"night", "winter"}))));
  TEST_ASSERT_EQUAL(int(Outfit::kBobble), int(outfitFor(tags({"morning", "winter"}))));
  TEST_ASSERT_EQUAL(int(Outfit::kPartyHat), int(outfitFor(tags({"night", "party"}))));
  TEST_ASSERT_EQUAL(int(Outfit::kPartyHat), int(outfitFor(tags({"day", "programmers"}))));
  TEST_ASSERT_EQUAL(int(Outfit::kWitchHat), int(outfitFor(tags({"night", "halloween", "party"}))));
  // Reading glasses while `reading` is on, over a Friday's shades; shades
  // only by day.
  TEST_ASSERT_EQUAL(int(Eyewear::kGlasses), int(eyewearFor(tags({"night", "reading"}))));
  TEST_ASSERT_EQUAL(int(Eyewear::kGlasses), int(eyewearFor(tags({"day", "friday", "reading"}))));
  TEST_ASSERT_EQUAL(int(Eyewear::kShades), int(eyewearFor(tags({"day", "friday"}))));
  TEST_ASSERT_EQUAL(int(Eyewear::kNone), int(eyewearFor(tags({"night", "friday"}))));
  // The pyjamas' rings: the lap's over the hem's, each from the left side to
  // the right, the hem's front the lowest, under the hands'.
  for (const auto* ring : {at.lap, at.hem}) {
    TEST_ASSERT_TRUE(ring[0].x < ring[8].x && ring[8].x < ring[16].x);
    TEST_ASSERT_TRUE(ring[0].y < ring[8].y && ring[16].y < ring[8].y);
  }
  TEST_ASSERT_TRUE(at.lap[8].y < at.handF.y && at.handF.y < at.hem[8].y);
  TEST_ASSERT_EQUAL_INT(0, sleepyLids(*e));
  e->setOccasion(tags({"night"}), 0);
  TEST_ASSERT_EQUAL_INT(kNightLids, sleepyLids(*e));
  // A nightcap covers the dome's top: the pixels just over the crown change.
  const std::vector<uint16_t> bare(px);
  paint(s, *e, false, 0, 0, &at);
  const size_t over = size_t(at.crown.y / 16 - 4) * 502 + size_t(at.crown.x / 16);
  TEST_ASSERT_NOT_EQUAL(bare[over], px[over]);
  // Every layer at once, asleep (a hat, shades, snow, confetti, hearts and
  // Zs), off the heap.
  e->setOccasion(tags({"night", "winter", "party", "valentines", "friday"}), 0);
  e->scenes.route.state = SceneState::kAsleep;
  allocCount = 0;
  allocCounting = true;
  for (int i = 0; i < 20; ++i) paintLayers(s, *e, at);
  allocCounting = false;
  TEST_ASSERT_EQUAL_INT(0, allocCount);
}

// What the gel wears, the air and the Zs come and go through the rig's
// layer stack (the face's), on the rig's 200 ms fade: a winter evening's
// bobble fades out at night and the nightcap in after it, the night sky
// and the pyjamas fading in with it; falling asleep, the Zs fade in while
// the sky, the hat, the pyjamas and the snow stay whole, each layer its
// own; a sign fades out at its opacity, as Behaviour gives
// it. Each is drawn at its layer's opacity.
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
  const uint32_t bobble = uint32_t(Outfit::kBobble), nightcap = uint32_t(Outfit::kNightcap);
  state(SceneState::kIdle, {"evening", "winter"}, 0);
  b.advance(1000, rng);
  TEST_ASSERT_EQUAL_UINT32(bobble, l.content(Layer::kHat, 1000));
  TEST_ASSERT_EQUAL_INT(1000, l.opacity(Layer::kHat, 1000));
  TEST_ASSERT_EQUAL_UINT32(kSnow, l.content(Layer::kAir, 1000));
  TEST_ASSERT_EQUAL_INT(0, l.opacity(Layer::kScene, 1000));
  TEST_ASSERT_EQUAL_INT(0, l.opacity(Layer::kWorn, 1000));
  state(SceneState::kIdle, {"night", "winter"}, 1008);
  for (uint32_t t = 1008; t <= 1500; t += 16) {
    b.advance(t, rng);
    const uint32_t into = t - 1008;
    const int in = ease1000(std::min(int(into), 200), 200);
    TEST_ASSERT_EQUAL_INT(in, l.opacity(Layer::kScene, t));  // the sky
    TEST_ASSERT_EQUAL_INT(in, l.opacity(Layer::kWorn, t));   // the pyjamas
    if (into < rig::kFadeMs) {
      TEST_ASSERT_EQUAL_UINT32(bobble, l.content(Layer::kHat, t));
      TEST_ASSERT_EQUAL_INT(1000 - ease1000(int(into), 200), l.opacity(Layer::kHat, t));
    } else {
      TEST_ASSERT_EQUAL_UINT32(nightcap, l.content(Layer::kHat, t));
      TEST_ASSERT_EQUAL_INT(ease1000(std::min(int(into) - 200, 200), 200), l.opacity(Layer::kHat, t));
    }
    TEST_ASSERT_EQUAL_INT(1000, l.opacity(Layer::kAir, t));  // the snow stays
  }
  state(SceneState::kAsleep, {"night", "winter"}, 2000);
  TEST_ASSERT_EQUAL_INT(0, l.opacity(Layer::kBeside, 2000));
  for (uint32_t t = 2016; t <= 2400; t += 16) {
    b.advance(t, rng);
    const int in = ease1000(std::min(int(t - 2000), 200), 200);
    TEST_ASSERT_EQUAL_INT(in, l.opacity(Layer::kBeside, t));  // the Zs
    TEST_ASSERT_EQUAL_INT(1000, l.opacity(Layer::kScene, t));
    TEST_ASSERT_EQUAL_INT(1000, l.opacity(Layer::kWorn, t));
    TEST_ASSERT_EQUAL_UINT32(nightcap, l.content(Layer::kHat, t));
    TEST_ASSERT_EQUAL_INT(1000, l.opacity(Layer::kHat, t));
    TEST_ASSERT_EQUAL_INT(1000, l.opacity(Layer::kAir, t));
  }
  TEST_ASSERT_TRUE(l.content(Layer::kWorn, 2400) != 0 && l.content(Layer::kBeside, 2400) == 1);
  // Drawn at the opacity: a hat half in is about half as bright as whole.
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  auto e = std::make_unique<Engine>();
  for (int t = 0; t <= 960; t += 16) e->step(t);
  e->setOccasion(tagBit("night"), 0);
  rig::Anchors at;
  paint(s, *e, false, 0, 0, &at);
  rig::Layers hat;
  hat.show(Layer::kHat, nightcap, 0);
  auto lit = [&](const rig::Layers& layers, uint32_t t) {
    std::fill(px.begin(), px.end(), 0);
    paintLayers(s, *e, at, &layers, t);
    long n = 0;
    for (uint16_t p : px) n += (p >> 11) + (p >> 5 & 63) / 2 + (p & 31);
    return n;
  };
  const long whole = lit(hat, 400), half = lit(hat, 100);
  TEST_ASSERT_TRUE(whole > 10000);
  TEST_ASSERT_INT_WITHIN(whole / 10, whole / 2, half);
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
}

// The pyjamas come with the nightcap, and with no other hat, but while it
// wears its reading glasses; the glasses are on its eyes but while it
// sleeps.
static void test_it_wears_pyjamas_at_night_and_reads_in_glasses() {
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  auto e = std::make_unique<Engine>();
  for (int t = 0; t <= 960; t += 16) e->step(t);
  rig::Anchors at;
  paint(s, *e, false, 0, 0, &at);
  auto layers = [&](std::initializer_list<const char*> names, SceneState state) {
    uint32_t when = 0;
    for (const char* n : names) when |= tagBit(n);
    e->setOccasion(when, 0);
    e->scenes.route.state = state;
    std::fill(px.begin(), px.end(), 0);
    paintLayers(s, *e, at);
  };
  // Inside the pyjamas, between the lap's front and the hem's; on the
  // glasses' left rim.
  const size_t pyjamas = size_t((at.lap[8].y + at.hem[8].y) / 32) * 502 + size_t(at.hem[8].x / 16);
  const size_t rim = size_t(at.eyeL.y / 16) * 502 + size_t((at.eyeL.x - (at.eyeR.x - at.eyeL.x) / 5) / 16);
  layers({"evening"}, SceneState::kIdle);
  TEST_ASSERT_EQUAL_HEX16(0, px[pyjamas]);
  layers({"night"}, SceneState::kIdle);
  TEST_ASSERT_NOT_EQUAL(0, px[pyjamas]);
  layers({"night"}, SceneState::kAsleep);
  TEST_ASSERT_NOT_EQUAL(0, px[pyjamas]);
  layers({"night", "winter"}, SceneState::kAsleep);  // night's cap over winter's bobble, and its pyjamas
  TEST_ASSERT_NOT_EQUAL(0, px[pyjamas]);
  layers({"night", "halloween"}, SceneState::kAsleep);  // Halloween's hat wins, and has no pyjamas
  TEST_ASSERT_EQUAL_HEX16(0, px[pyjamas]);
  layers({"day"}, SceneState::kAsleep);
  TEST_ASSERT_EQUAL_HEX16(0, px[pyjamas]);
  layers({"day", "reading"}, SceneState::kWorking);
  TEST_ASSERT_NOT_EQUAL(0, px[rim]);
  layers({"night", "reading"}, SceneState::kAsleep);  // the pyjamas, its eyes bare
  TEST_ASSERT_EQUAL_HEX16(0, px[rim]);
  TEST_ASSERT_NOT_EQUAL(0, px[pyjamas]);
  layers({"night", "reading"}, SceneState::kWorking);  // awake: the glasses, and no pyjamas
  TEST_ASSERT_NOT_EQUAL(0, px[rim]);
  TEST_ASSERT_EQUAL_HEX16(0, px[pyjamas]);
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
// and between pixels glides: a falling word's ink moves down in every
// frame, however little the frame, rather than a pixel at a time.
static void test_text_glides_between_pixels() {
  std::vector<uint16_t> a(502 * 410, 0), b(502 * 410, 0);
  Surface sa{502, 410, a.data()}, sb{502, 410, b.data()};
  Raster ra{sa}, rb{sb};
  ra.text("grep x", 200, 100, rgb565(140, 223, 203), kLarge);
  text16(rb, kLarge, (200 - 6 * kLarge.w / 2) * 16, (100 - kLarge.h / 2) * 16, "grep x", rgb565(140, 223, 203));
  TEST_ASSERT_EQUAL_MEMORY(a.data(), b.data(), a.size() * 2);
  // One lane's word, falling at 95 to 145 px a second: its ink's middle,
  // every 3 ms (under half a pixel), is lower each time.
  Stream stream;
  Stream::Lane lane;
  lane.slot = 0, lane.count = 1, std::strcpy(lane.word, "grep");
  stream.setLanes(&lane, 1, true, false, 0);
  double last = -1;
  for (uint32_t t = 600; t <= 660; t += 3) {
    std::fill(a.begin(), a.end(), 0);
    sa.invalidate();
    paintStreamBehind(sa, stream, t);
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

// The outfit is drawn into a recording and blended from it
// (OutfitLayer): while the body moves, a frame shows it as kept within
// kSlack (12 sixteenths) of where it is; once it's still (the same time,
// a frame over kMovingMs (100 ms) after the last, or anchors unmoved for
// kStillMs (200 ms)), it's drawn where it is, the same as afresh. The
// nightcap's swing steps every kSwingMs (400 ms).
static void test_the_outfit_is_kept_while_the_body_moves() {
  static_assert(OutfitLayer::kSlack == 12 && OutfitLayer::kMovingMs == 100 && OutfitLayer::kStillMs == 200 &&
                    OutfitLayer::kSwingMs == 400,
                "the rules this test pins");
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  auto e = std::make_unique<Engine>();
  for (int t = 0; t <= 960; t += 16) e->step(t);
  rig::Anchors home;
  paint(s, *e, false, 0, 0, &home);
  uint32_t night = tagBit("night");
  e->setOccasion(night, 0);
  // The nightcap alone, whole, at `at`, `ms` into the engine's clock.
  rig::Layers cap;
  cap.show(rig::Layer::kHat, uint32_t(Outfit::kNightcap), 0);
  auto frame = [&](const rig::Anchors& at, uint32_t ms) {
    std::fill(px.begin(), px.end(), 0);
    s.invalidate();
    e->elapsedMs = ms;
    paintLayers(s, *e, at, &cap, 1000);
    return px;
  };
  auto raised = [&](int crown) {  // the crown alone moved, the brim's front where it was
    rig::Anchors at = home;
    at.crown.y -= crown;
    return at;
  };
  const auto kept = frame(home, 1200);
  TEST_ASSERT_TRUE(kept == frame(home, 1599));  // the swing's step, by the time alone: the same
  TEST_ASSERT_TRUE(kept != frame(home, 1600));  // the next
  frame(home, 1200);
  TEST_ASSERT_TRUE(kept == frame(raised(12), 1230));  // moving, within kSlack: as kept
  TEST_ASSERT_TRUE(kept == frame(raised(12), 1330));  // still moving: it moved 100 ms ago
  const auto still = frame(raised(12), 1430);         // unmoved for kStillMs: drawn where it is
  TEST_ASSERT_TRUE(kept != still);
  TEST_ASSERT_TRUE(still == frame(raised(12), 1430));  // and kept so
  frame(home, 1200);
  TEST_ASSERT_TRUE(kept != frame(raised(13), 1230));  // past kSlack: drawn again
  frame(home, 1200);
  TEST_ASSERT_TRUE(still == frame(raised(12), 1200));  // the same time: as still
  frame(home, 1200);
  TEST_ASSERT_TRUE(still == frame(raised(12), 1301));  // a frame over kMovingMs after: the same
  // A whole number of pixels over, it's the kept one moved that far.
  frame(home, 1200);
  rig::Anchors down = home;
  for (rig::Point* p : {&down.crown, &down.brimL, &down.brimF, &down.brimR}) p->y += 3 * 16;
  const auto lower = frame(down, 1230);
  for (int y = 3; y < 410 * 4 / 5; ++y)
    TEST_ASSERT_EQUAL_MEMORY(kept.data() + (y - 3) * 502, lower.data() + y * 502, 502 * 2);
  // Moving half a pixel down, it's the kept one half a pixel down (Raster::
  // replay16): its ink's middle half a pixel lower, not where it was or a
  // pixel on.
  auto middle = [](const std::vector<uint16_t>& p) {
    double mass = 0, moment = 0;
    for (int y = 0; y < 410 * 4 / 5; ++y)
      for (int x = 0; x < 502; ++x)
        if (const int g = p[size_t(y) * 502 + x] >> 5 & 63) mass += g, moment += double(g) * y;
    return moment / mass;
  };
  frame(home, 1200);
  rig::Anchors half = home;
  for (rig::Point* p : {&half.crown, &half.brimL, &half.brimF, &half.brimR}) p->y += 8;
  const double glide = middle(frame(half, 1230)) - middle(kept);
  TEST_ASSERT_TRUE(glide > 0.4 && glide < 0.6);
}

// The sky (the stack's scene) is the night's at night and the sun in the
// morning, and none by day; behind everything: drawn only onto the
// background's black, so not a pixel of what's drawn changes, at its
// layer's opacity.
static void test_the_sky_is_behind_the_body() {
  using rig::Layer;
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  auto e = std::make_unique<Engine>();
  for (int t = 0; t <= 960; t += 16) e->step(t);
  rig::Anchors at;
  paint(s, *e, false, 0, 0, &at);
  const std::vector<uint16_t> body(px);
  long bare = 0;
  for (uint16_t p : body) bare += (p >> 11) + (p >> 5 & 63) / 2 + (p & 31);
  e->setOccasion(tagBit("day"), 0);
  TEST_ASSERT_EQUAL_UINT32(0, layerContents(*e).scene);
  e->setOccasion(tagBit("evening"), 0);
  TEST_ASSERT_EQUAL_UINT32(0, layerContents(*e).scene);
  for (const auto& [tag, scene] : {std::pair<const char*, uint32_t>{"night", kNightSky}, {"morning", kSun}}) {
    e->setOccasion(tagBit(tag), 0);
    TEST_ASSERT_EQUAL_UINT32(scene, layerContents(*e).scene);
    rig::Layers sky;
    sky.show(Layer::kScene, scene, 0);
    auto lit = [&](uint32_t t) {
      px = body;
      paintSky(s, *e, &sky, t);
      long n = 0;
      for (size_t i = 0; i < px.size(); ++i) {
        if (body[i]) TEST_ASSERT_EQUAL_HEX16(body[i], px[i]);
        n += (px[i] >> 11) + (px[i] >> 5 & 63) / 2 + (px[i] & 31);
      }
      return n;
    };
    const long whole = lit(400) - bare, half = lit(100) - bare;
    TEST_ASSERT_TRUE(whole > 20000);
    TEST_ASSERT_INT_WITHIN(whole / 10, whole / 2, half);
  }
}

// Its morning coffee is beside it while it's idle or at work in the
// morning, never asleep, in peekaboo or at another time of day, and the Zs
// only while it sleeps at night. Once every kSipMs (9 s) it lifts the mug
// to its mouth for the last 1.8 s: up over 500 ms, held 800, down over
// 500; the rest of the time it's held at its side.
static void test_it_has_its_coffee_in_the_morning() {
  static_assert(OutfitLayer::kSipMs == 9000, "the rule this test pins");
  std::vector<uint16_t> px(502 * 410);
  Surface s{502, 410, px.data()};
  auto e = std::make_unique<Engine>();
  for (int t = 0; t <= 960; t += 16) e->step(t);
  rig::Anchors at;
  paint(s, *e, false, 0, 0, &at);
  auto beside = [&](const char* tag, SceneState state, int variant = 0) {
    e->setOccasion(tagBit(tag), 0);
    e->scenes.route.state = state;
    e->scenes.variant = variant;
    return layerContents(*e).beside;
  };
  TEST_ASSERT_EQUAL_UINT32(kCoffeeMug, beside("morning", SceneState::kIdle));
  TEST_ASSERT_EQUAL_UINT32(kCoffeeMug, beside("morning", SceneState::kWorking));
  TEST_ASSERT_EQUAL_UINT32(0, beside("morning", SceneState::kAsleep));
  TEST_ASSERT_EQUAL_UINT32(0, beside("morning", SceneState::kGesture, int(Gesture::kPeekaboo)));
  TEST_ASSERT_EQUAL_UINT32(0, beside("day", SceneState::kIdle));
  TEST_ASSERT_EQUAL_UINT32(0, beside("night", SceneState::kIdle));
  TEST_ASSERT_EQUAL_UINT32(kZs, beside("night", SceneState::kAsleep));
  // The mug alone, `ms` into the engine's clock: over its mouth, just
  // right of the eyes' middle, only while it sips.
  beside("morning", SceneState::kIdle);
  rig::Layers mug;
  mug.show(rig::Layer::kBeside, kCoffeeMug, 0);
  const int mouthY = (at.eyeL.y + at.eyeR.y) / 32 + (at.eyeR.x - at.eyeL.x) * 32 / 1600;
  auto atMouth = [&](uint32_t ms) {
    std::fill(px.begin(), px.end(), 0);
    e->elapsedMs = ms;
    paintLayers(s, *e, at, &mug, 1000);
    const int mid = (at.eyeL.x + at.eyeR.x) / 32, d = (at.eyeR.x - at.eyeL.x) / 16;
    int n = 0;
    for (int x = mid; x < mid + d / 10; ++x) n += px[size_t(mouthY) * 502 + x] != 0;
    return n;
  };
  TEST_ASSERT_EQUAL_INT(0, atMouth(1000));
  TEST_ASSERT_EQUAL_INT(0, atMouth(7199));          // the last moment held at its side
  TEST_ASSERT_TRUE(atMouth(7200 + 900) > 5);         // sipping
  TEST_ASSERT_TRUE(atMouth(9000 + 7200 + 900) > 5);  // and again 9 s on
  TEST_ASSERT_EQUAL_INT(0, atMouth(9000 + 1000));
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
      "{\"t\":\"state\",\"base\":\"working\",\"act\":\"testing\",\"mood\":\"frightened\",\"busy\":2,\"vol\":0}",
      "{\"t\":\"state\",\"base\":\"asleep\",\"mood\":\"calm\",\"vol\":0}",
      // The pastimes and their kit.
      "{\"t\":\"state\",\"base\":\"working\",\"act\":\"terminal\",\"mood\":\"happy\",\"vol\":0,\"when\":[\"tier5\"]}",
      "{\"t\":\"state\",\"base\":\"idle\",\"mood\":\"happy\",\"vol\":0,\"when\":[\"tier5\"]}",
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
// longest take in its own font and a line of 34 in the large one.
static void test_the_lane_is_native_and_tracked() {
  constexpr int kW = 502, kH = 410, kLane = kH * 4 / 5;
  {
    Surface square{kW, kH, nullptr};
    TEST_ASSERT_TRUE(22 * kFontBubble.w <= bubbleRoom(square));
    TEST_ASSERT_TRUE(34 * kLarge.w <= bubbleRoom(square));
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
// The lane's text is cut by the rule every face's is (render::cutAt): a
// line too long for its room draws as the words cutAt keeps and "..". The
// working count's mark is a ring with its left half filled, which no digit
// reads as; a finished turn's tick is sage and its cross clay.
static void test_the_lane_cuts_and_marks_as_the_canvas_does() {
  constexpr int kW = 502, kH = 410;
  std::vector<uint16_t> a(kW * kH), b(a.size());
  Surface cut{kW, kH, a.data()}, whole{kW, kH, b.data()};
  Raster rc{cut}, rw{whole};
  rc.limit = rw.limit = kH;
  text(rc, kSign, 0, 0, "claude \xC2\xB7 what does the turn do", 0xffff, 24 * kSign.w);
  text(rw, kSign, 0, 0, "claude \xC2\xB7 what does the..", 0xffff);
  TEST_ASSERT_EQUAL_MEMORY(b.data(), a.data(), cut.bytes());
  // With no names, the counts start at the margin: the mark's middle 9 px in.
  Strip s;
  s.busy = 2;
  cut.invalidate(), cut.clear();
  paintLane(cut, nullptr, s);
  const int cy = kH * ((kStripTop + kHeight) / 2) / kHeight;
  TEST_ASSERT_EQUAL_HEX16(paletteAt(inkAt(kInkGrey, kLevels)), a[size_t(cy) * kW + 18 + 6]);
  TEST_ASSERT_EQUAL_HEX16(0, a[size_t(cy) * kW + 18 + 12]);
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
// What a frame keeps from its surface's last (a card's
// opaque inside, an unchanged lane) is exactly what clearing it whole and
// drawing afresh leaves. Two surfaces taking turns, as the board's do,
// through needs you rising and holding with its strip, a finish's card,
// the start card, a bubble coming and going, the strip's count changing
// and a finished turn's ticket and glow coming, holding and going (render/
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
  f.act = SceneState::kTerminal;
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
    // A finished turn from 150, its reaction played out at 230 and gone
    // by 330.
    DoneShow done;
    if (i >= 150 && i < 330) {
      done.agent = "claude", done.thread = "fix-nav", done.outcome = Outcome::kFailure;
      done.ms = uint32_t(i - 150) * 33;
      if (i >= 230) done.leftMs = (330 - i) * 33;
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
// The work stream on the gel: a lane's words drawn behind the body show
// only where it doesn't cover them; a word forward is drawn over it; the
// body answers a hit as it lands, knocked and its lids shut, opening again
// after the daze; and drawing it all takes nothing from the heap.
static void test_the_work_stream_falls_behind_and_hits_in_front() {
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
  // The words fall in their lanes' columns, a quarter and three quarters
  // across, and the body's middle covers whatever falls behind it.
  int left = 0, right = 0;
  for (int y = 30; y < 120; ++y)
    for (int x = 0; x < 502; ++x)
      if (px[size_t(y) * 502 + x] != bare[size_t(y) * 502 + x]) (x < 251 ? left : right) += 1;
  TEST_ASSERT_TRUE(left > 40 && right > 40);
  TEST_ASSERT_EQUAL_HEX16(bare[size_t(205) * 502 + 251], px[size_t(205) * 502 + 251]);
  // A failure flies at its face from the second lane, and lands.
  stream.startCall("make", 1, CallGag::kBonk, 0, 1000);
  TEST_ASSERT_EQUAL_UINT32(380, callFlightMs(CallGag::kBonk));
  TEST_ASSERT_EQUAL_INT(int(CallMove::kHit), int(callMove(CallGag::kBonk)));
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
  for (int g = 0; g < int(CallGag::kCount); ++g) {
    stream.startCall("x", 0, CallGag(g), 5, 4000);
    for (uint32_t t = 4000; t < 6500; t += 250)
      paintFrame(s, *e, false, 0, nullptr, none, strip, {}, rig::kRest, nullptr, 0, &stream, t);
  }
  allocCounting = false;
  TEST_ASSERT_EQUAL_INT(0, allocCount);
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_fixed_math_and_motion);
  RUN_TEST(test_the_work_stream_falls_behind_and_hits_in_front);
  RUN_TEST(test_software_clock_matches_binary64);
  RUN_TEST(test_a_divisor_divides_exactly);
  RUN_TEST(test_all_expressions_draw_inside_native_surface);
  RUN_TEST(test_frame_replay_is_byte_identical);
  RUN_TEST(test_a_helper_draws_the_same_body);
  RUN_TEST(test_one_face_vocabulary_and_latest_facts);
  RUN_TEST(test_request_identity_and_cache_bounds);
  RUN_TEST(test_grid_voice_lead_and_late_cues);
  RUN_TEST(test_external_source_holds_without_repeating_reveal);
  RUN_TEST(test_a_card_revealed_late_rises_then_falls);
  RUN_TEST(test_every_result_card_has_a_mark);
  RUN_TEST(test_interrupted_alert_signals_exactly_once);
  RUN_TEST(test_face_and_props_move_without_jumps);
  RUN_TEST(test_it_falls_asleep_squashing_shut);
  RUN_TEST(test_the_face_never_fades_while_arts_cross_over);
  RUN_TEST(test_the_lane_fades_whatever_the_draw_cadence);
  RUN_TEST(test_gel_clips_use_the_shared_mixer);
  RUN_TEST(test_each_cue_carries_its_own_duck);
  RUN_TEST(test_pick_is_pure_and_started_commits_it);
  RUN_TEST(test_a_power_on_seeds_the_engine_and_a_reset_restores_53);
  RUN_TEST(test_a_reset_lets_go_of_the_finger);
  RUN_TEST(test_a_finger_moves_the_dome_its_way);
  RUN_TEST(test_a_faded_art_never_comes_back);
  RUN_TEST(test_the_night_lids_ease_out_as_it_falls_asleep);
  RUN_TEST(test_timing_comes_from_the_recipe_table);
  RUN_TEST(test_comedy_plays_in_idle_and_asleep);
  RUN_TEST(test_each_gesture_plays_its_own_gag);
  RUN_TEST(test_a_notice_plays_its_rig_clip);
  RUN_TEST(test_a_reply_plays_its_clip_once);
  RUN_TEST(test_occasions_play_only_while_they_fit);
  RUN_TEST(test_a_rig_clip_plays_on_both_faces);
  RUN_TEST(test_every_pastime_has_its_clip_and_its_turn);
  RUN_TEST(test_each_pastime_draws_and_ends);
  RUN_TEST(test_pastimes_are_dealt_by_tier_after_a_rest);
  RUN_TEST(test_the_kit_follows_the_tiers);
  RUN_TEST(test_the_headphones_play_a_tune);
  RUN_TEST(test_the_layers_come_and_go_through_the_stack);
  RUN_TEST(test_gel_draws_natively);
  RUN_TEST(test_face_projection_and_pose_bounds);
  RUN_TEST(test_tracked_clear_matches_full_clear);
  RUN_TEST(test_histories_stay_off_the_heap);
  RUN_TEST(test_kept_cards_and_lanes_match_a_fresh_frame);
  RUN_TEST(test_a_named_finish_shows_no_card);
  RUN_TEST(test_a_finished_turn_glows_and_hangs_a_ticket);
  RUN_TEST(test_a_still_card_is_drawn_once_into_each_surface);
  RUN_TEST(test_steady_frames_allocate_nothing);
  RUN_TEST(test_the_lane_is_native_and_tracked);
  RUN_TEST(test_the_lane_clears_the_rounded_corners);
  RUN_TEST(test_the_strip_fades_as_one);
  RUN_TEST(test_the_lane_cuts_and_marks_as_the_canvas_does);
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
  RUN_TEST(test_it_wears_pyjamas_at_night_and_reads_in_glasses);
  RUN_TEST(test_the_sky_is_behind_the_body);
  RUN_TEST(test_it_has_its_coffee_in_the_morning);
  RUN_TEST(test_a_recording_replays_as_drawn);
  RUN_TEST(test_a_recording_replays_between_pixels);
  RUN_TEST(test_text_glides_between_pixels);
  RUN_TEST(test_the_outfit_is_kept_while_the_body_moves);
  // test_cells.cpp
  RUN_TEST(test_every_cell_plays_truthfully);
  RUN_TEST(test_ten_minutes_of_work);
  RUN_TEST(test_held_and_interrupted_contacts);
  RUN_TEST(test_card_reveal_trajectory);
  RUN_TEST(test_asleep_rests_still_but_for_a_snore);
  // test_finish.cpp
  RUN_TEST(test_a_finish_is_sized_by_its_turn_or_else_its_hold);
  RUN_TEST(test_each_mood_takes_turns_between_its_big_finishes);
  RUN_TEST(test_the_face_picks_a_finish_and_plays_it_once);
  RUN_TEST(test_a_big_finish_cheers_once_and_bounces);
  RUN_TEST(test_a_takeover_puts_the_desk_away);
  RUN_TEST(test_every_finish_moves_smoothly_and_settles);
  RUN_TEST(test_gold_rush_floods_and_little_win_shows_its_trophy);
  RUN_TEST(test_only_what_draws_behind_erases_first);
  // test_bridges.cpp
  RUN_TEST(test_every_edge_bridges_as_authored);
  RUN_TEST(test_a_bridge_follows_its_waveform);
  RUN_TEST(test_a_grab_defers_then_expires_the_bridge);
  RUN_TEST(test_a_quiet_or_alerting_body_holds_the_bridge);
  RUN_TEST(test_a_rapid_chain_settles_on_the_last);
  RUN_TEST(test_each_edge_deals_its_own_bag);
  RUN_TEST(test_the_semantic_face_numbers);
  // test_motion.cpp
  RUN_TEST(test_the_motion_v1_numbers);
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
