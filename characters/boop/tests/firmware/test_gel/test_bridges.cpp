// The directed mood bridges and the semantic face: what a mood change does
// to the body and the face, edge by edge, frame by frame.
#include <unity.h>

#include <algorithm>
#include <cmath>
#include <memory>
#include <string>
#include <vector>

#include "frames.h"

using namespace render;
using namespace render::gel;

namespace {

const T kFrame = T::ratio(16, 1000);
constexpr int kOrdinaryMs[3] = {420, 680, 360}, kDramaticMs[3] = {760, 920, 560};
constexpr int kOrdinaryFaceMs[3] = {320, 360, 460}, kDramaticFaceMs[3] = {240, 280, 340};
const F kBounds[3] = {q(.06), q(.05), q(.04)};
// The one primitive whose own coefficients need its amplitude cut: the
// dramatic compression, whose squash peaks at .048 of it.
const F kCompressionLimit = q(.05 / .048);

double number(F f) { return double(f.raw) / F::scale; }
// Unity here has no doubles: within `tolerance` of `want`.
#define TEST_NEAR(tolerance, want, got) TEST_ASSERT_TRUE(std::abs(double(want) - double(got)) <= (tolerance))

// What a retarget must leave as it was: every live spring, the face's
// controls and their velocities, the composed pose and the clock.
struct Physical {
  std::vector<int64_t> raw;
  static Physical of(const Engine& e) {
    Physical p;
    auto add = [&](F f) { p.raw.push_back(f.raw); };
    auto spring = [&](const Spring& s) { add(s.x), add(s.v); };
    for (const auto& s : e.motion.modes) spring(s);
    for (const auto& s : e.acting.channels) spring(s);
    spring(e.acting.slide);
    spring(e.acting.lids);
    for (const auto& s : e.bridge.channels) spring(s);
    for (const auto& s : e.scenes.activity) spring(s);
    for (const auto& s : e.pull) spring(s);
    for (const auto& s : e.postureWeights) spring(s);
    for (const F f : e.pose()) add(f);
    for (const F f : e.life()) add(f);
    for (const F f : e.face.controls) add(f);
    for (const F f : e.face.velocity) add(f);
    add(e.motion.time);
    p.raw.push_back(e.elapsedMs);
    return p;
  }
  bool operator==(const Physical& o) const { return raw == o.raw; }
};

// An engine in `from`, idle, 512 ms into its authored gesture `gesture`:
// where every edge's bridge starts from.
// A track, if given, follows its last frames.
std::unique_ptr<Engine> prepared(int from, int gesture, uint32_t& t, frames::Track* track = nullptr) {
  auto e = std::make_unique<Engine>();
  e->step(t = 0);
  e->setMood(from);
  for (t = 16; t <= 1600; t += 16) e->step(t);
  e->acting.perform(e->motion.time, e->random, gesture);
  for (; t <= 2112; t += 16) {
    e->step(t);
    if (track && t >= 2048) track->add(*e, false);
  }
  t -= 16;
  TEST_ASSERT_EQUAL_INT(gesture, e->acting.performance);
  return e;
}

// One frame of the bridge's own spring toward nothing, as a suppressed,
// deferred or expired bridge integrates.
void settles(Spring (&springs)[3]) {
  for (int i = 0; i < 3; ++i) integrate(springs[i], kFrame, 0, 14, 12, kBounds[i], 1);
}
void expectSettling(const Engine& e, Spring (&was)[3]) {
  settles(was);
  for (int i = 0; i < 3; ++i) {
    TEST_ASSERT_TRUE(e.bridge.channels[i].x == was[i].x);
    TEST_ASSERT_TRUE(e.bridge.channels[i].v == was[i].v);
  }
}
void copy(Spring (&to)[3], const Spring (&from)[3]) { std::copy(from, from + 3, to); }

// The authored waveform of each primitive, at its progress p, for direction
// and amplitude: what the bridge's spring is pulled toward.
enum Shape { kSoftShape, kGatherShape, kOrdinaryBlink, kDramaticBlink, kRecoilShape, kCompressionShape };
std::array<double, 3> waveform(Shape shape, double p, int direction, double amplitude) {
  if (p <= 0 || p >= 1) return {0, 0, 0};
  const double pulse = std::pow(std::sin(M_PI * p), 2), wave = std::sin(2 * M_PI * p);
  const double held = p < .25 ? 0 : std::pow(std::sin(M_PI * (p - .25) / .75), 2);
  std::array<double, 3> t;
  switch (shape) {
    case kSoftShape: t = {.009 * direction * pulse, .004 * pulse, .003 * pulse}; break;
    case kGatherShape: t = {.026 * direction * pulse, -.032 * pulse, .012 * wave * pulse}; break;
    case kOrdinaryBlink: t = {.006 * direction * held, -.014 * held, -.004 * held}; break;
    case kDramaticBlink: t = {.026 * direction * held, -.035 * held, -.014 * held}; break;
    case kRecoilShape: t = {-.045 * direction * wave * pulse, -.038 * pulse, -.032 * pulse}; break;
    default: t = {.022 * direction * pulse, -.048 * pulse, .026 * wave * pulse};
  }
  for (auto& v : t) v *= amplitude;
  return t;
}
Shape shapeOf(const Bridge& b) {
  switch (b.primitive) {
    case Primitive::kSoft: return kSoftShape;
    case Primitive::kGather: return kGatherShape;
    case Primitive::kBlink: return b.category == 1 ? kDramaticBlink : kOrdinaryBlink;
    default: return b.variant == 0 ? kRecoilShape : kCompressionShape;
  }
}
// The amplitude a primitive may have: its channels' bounds over its largest
// coefficients on them.
double limitOf(Shape shape) {
  const double peaks[6][3] = {{.009, .004, .003}, {.026, .032, .012}, {.006, .014, .004},
                              {.026, .035, .014}, {.045, .038, .032}, {.022, .048, .026}};
  return std::min({.06 / peaks[shape][0], .05 / peaks[shape][1], .04 / peaks[shape][2]});
}

// The first edge from `from` to `to`, or -1.
int edgeOf(int from, int to) {
  for (int i = 0; i < slime::kEdgeCount; ++i)
    if (slime::kEdges[i].from == from && slime::kEdges[i].to == to) return i;
  return -1;
}

}  // namespace

// Every directed edge, in each of its three variants, from an authored
// gesture under way: the retarget itself changes no spring, control, pose
// or clock, and every art is drawn as it was, the destination's coming in
// at nothing; the bridge plays its edge's primitive (ordinary: soft, gather,
// blink; dramatic: recoil, compression, blink) over its authored
// body and face windows, at an amplitude in [0.8, 1.2] that keeps every
// target inside its bound, its direction reversing with the edge; every
// frame keeps the engine's bounds and each face control between where it
// started and where it's going; the bridge passes through every sixteenth
// of its window, the three variants moving differently; and the face
// arrives at the destination's art, alone, with the mood unchanged.
void test_every_edge_bridges_as_authored() {
  int crossed = 0;
  frames::Jolts jolts;
  for (int i = 0; i < slime::kEdgeCount; ++i) {
    const auto& edge = slime::kEdges[i];
    const bool dramatic = edge.dramatic;
    std::vector<int64_t> signatures[3];
    for (int v = 0; v < 3; ++v) {
      uint32_t t;
      frames::Track track(&jolts);
      auto e = prepared(edge.from, v, t, &track);
      const Physical before = Physical::of(*e);
      const SemanticFace settled = e->face;
      const std::array<F, 8> start = e->face.controls;
      e->setMood(edge.to, v);
      TEST_ASSERT_TRUE(Physical::of(*e) == before);
      // What's drawn: every art as it was, at its weight and its ratios, the
      // destination's coming in at nothing.
      TEST_ASSERT_EQUAL_INT(settled.count + 1, e->face.count);
      for (int k = 0; k < settled.count; ++k) {
        const auto &now = e->face.layers[k], &was = settled.layers[k];
        TEST_ASSERT_TRUE(now.art == was.art && now.sleeping == was.sleeping && now.weight == was.weight);
        TEST_ASSERT_TRUE(e->face.ratios(now) == settled.ratios(was));
      }
      TEST_ASSERT_TRUE(e->face.current().weight == F(0));
      const Bridge& b = e->bridge;
      TEST_ASSERT_EQUAL_INT(i, b.edge);
      TEST_ASSERT_EQUAL_INT(v, b.variant);
      TEST_ASSERT_EQUAL_INT(dramatic ? 1 : 0, b.category);
      const Primitive family[2][3] = {{Primitive::kSoft, Primitive::kGather, Primitive::kBlink},
                                      {Primitive::kRecoil, Primitive::kRecoil, Primitive::kBlink}};
      TEST_ASSERT_TRUE(b.primitive == family[dramatic][v]);
      TEST_ASSERT_TRUE(b.durationMs == T((dramatic ? kDramaticMs : kOrdinaryMs)[v]));
      TEST_ASSERT_TRUE(e->face.durationMs == T((dramatic ? kDramaticFaceMs : kOrdinaryFaceMs)[v]));
      TEST_ASSERT_TRUE(b.amplitude >= q(.8) && b.amplitude <= q(1.2));
      TEST_ASSERT_TRUE(number(b.amplitude) <= limitOf(shapeOf(b)) + 1e-6);
      // The same bridge the other way: the opposite direction, the same
      // amplitude (but where the compression's limit cuts one).
      Bridge back;
      Random r(53);
      back.retarget(edge.to, edge.from, 0, r, v);
      TEST_ASSERT_EQUAL_INT(-b.direction, back.direction);
      TEST_ASSERT_TRUE(min(b.amplitude, kCompressionLimit) == min(back.amplitude, kCompressionLimit));
      // Every frame, through the bridge and 320 ms beyond.
      std::array<F, 8> lo, hi;
      for (int k = 0; k < 8; ++k)
        lo[k] = min(start[k], e->face.to[k]) - q(.000001), hi[k] = max(start[k], e->face.to[k]) + q(.000001);
      frames::Frame last = frames::capture(*e);
      bool bins[16] = {};
      const int end = int(t) + (dramatic ? kDramaticMs : kOrdinaryMs)[v] + 320;
      for (t += 16; int(t) <= end; t += 16) {
        const bool event = track.heard(*e);
        e->step(t);
        frames::check(*e, &last);
        last = frames::capture(*e);
        track.add(*e, event);
        TEST_ASSERT_EQUAL_INT(edge.to, e->face.current().art);
        TEST_ASSERT_FALSE(e->face.current().sleeping);
        for (int k = 0; k < 8; ++k) TEST_ASSERT_TRUE(e->face.controls[k] >= lo[k] && e->face.controls[k] <= hi[k]);
        crossed = std::max(crossed, e->face.count);
        const int bin = std::min(15, (b.elapsedMs / b.durationMs * 16).floor());
        if (!bins[bin]) {
          bins[bin] = true;
          for (const auto& s : b.channels) signatures[v].push_back(s.x.raw);
          for (const F c : e->face.controls) signatures[v].push_back(c.raw);
        }
      }
      for (const bool hit : bins) TEST_ASSERT_TRUE(hit);
      TEST_ASSERT_EQUAL_INT(edge.to, e->emotion);
      TEST_ASSERT_EQUAL_INT(1, e->face.count);
    }
    TEST_ASSERT_TRUE(signatures[0] != signatures[1] && signatures[1] != signatures[2] &&
                     signatures[0] != signatures[2]);
  }
  TEST_ASSERT_EQUAL_INT(2, crossed);
  jolts.finish();
  // The direction and amplitude come from the two moods' posture, energy,
  // delay and face sizes: happy to sad leans back, at 0.8 and four times
  // its score; a mood to itself has no direction and the least amplitude.
  Bridge b;
  Random r(53);
  b.retarget(slime::kHappy, slime::kSad, 0, r, 0);
  const double score =
      (-.016 - .014) + (.62 - 1.05) * .025 + (0 - 160) / 10000.0 + (.077 - .046) * .01 + (.035 - .076) * .005;
  TEST_ASSERT_EQUAL_INT(-1, b.direction);
  TEST_NEAR(1e-4, .8 + std::abs(score) * 4, number(b.amplitude));
  b.retarget(slime::kCalm, slime::kCalm, 0, r, 0);
  TEST_ASSERT_EQUAL_INT(0, b.direction);
  TEST_ASSERT_TRUE(b.amplitude == q(.8));
}

// Each primitive pulls the bridge's spring (frequency 14, damping 12, in
// 1/240 s steps) toward its authored waveform, every target inside its
// channel's bound (lean .06, squash .05, forward .04) at the largest
// amplitude it may take, and nothing before it starts or after it ends;
// the spring is held inside the bounds, at most 1 a second; and a dramatic
// compression squashes the body more than a fifth again as far as an
// ordinary gather does.
void test_a_bridge_follows_its_waveform() {
  // The waveform's own numbers, as authored, at a few points.
  struct Point {
    Shape shape;
    double p, lean, squash, forward;
  } points[] = {{kSoftShape, .5, .009, .004, .003},         {kGatherShape, .5, .026, -.032, 0},
                {kGatherShape, .25, .013, -.016, .006},     {kOrdinaryBlink, .25, 0, 0, 0},
                {kOrdinaryBlink, .625, .006, -.014, -.004}, {kDramaticBlink, .625, .026, -.035, -.014},
                {kRecoilShape, .25, -.0225, -.019, -.016},  {kCompressionShape, .25, .011, -.024, .013}};
  for (const auto& point : points)
    for (const double amplitude : {.8, 1.0, 1.2}) {
      const auto t = waveform(point.shape, point.p, 1, amplitude);
      TEST_NEAR(1e-9, point.lean * amplitude, t[0]);
      TEST_NEAR(1e-9, point.squash * amplitude, t[1]);
      TEST_NEAR(1e-9, point.forward * amplitude, t[2]);
    }
  for (int shape = 0; shape < 6; ++shape) {
    const double amplitude = std::min(1.2, limitOf(Shape(shape)));
    for (int k = 0; k <= 512; ++k)
      for (const int direction : {-1, 1}) {
        const auto t = waveform(Shape(shape), k / 512.0, direction, amplitude);
        for (int c = 0; c < 3; ++c) TEST_ASSERT_TRUE(std::abs(t[c]) <= number(kBounds[c]) + 1e-12);
      }
  }
  TEST_NEAR(1e-9, .05 / .048, limitOf(kCompressionShape));
  TEST_ASSERT_TRUE(limitOf(kRecoilShape) > 1.2);
  // The bridge itself follows the waveform, frame by frame, for each of the
  // six shapes: from calm along an ordinary edge and a dramatic one.
  const int ordinary = edgeOf(slime::kCalm, slime::kCurious), dramatic = edgeOf(slime::kCalm, slime::kSurprised);
  TEST_ASSERT_TRUE(ordinary >= 0 && !slime::kEdges[ordinary].dramatic);
  TEST_ASSERT_TRUE(dramatic >= 0 && slime::kEdges[dramatic].dramatic);
  double peaks[2] = {};
  for (const int to : {slime::kCurious, slime::kSurprised})
    for (int v = 0; v < 3; ++v) {
      Bridge b;
      Random r(53);
      b.context(false, false, false);
      b.retarget(slime::kCalm, to, 0, r, v);
      const Shape shape = shapeOf(b);
      TEST_ASSERT_EQUAL_INT(to == slime::kSurprised ? (v == 2   ? kDramaticBlink
                                                       : v == 0 ? kRecoilShape
                                                                : kCompressionShape)
                                                    : v,
                            shape);
      double x[3] = {}, vel[3] = {};
      for (int frame = 1; frame * 16 <= int(F(b.durationMs).integer()) + 320; ++frame) {
        b.advance(kFrame);
        const double p = std::min(1.0, frame * 16 / double(F(b.durationMs).integer()));
        const auto target = waveform(shape, p, b.direction, number(b.amplitude));
        for (int c = 0; c < 3; ++c) {
          for (double left = .016; left > 1e-12;) {
            const double h = std::min(left, 1.0 / 240);
            vel[c] += (196 * (target[c] - x[c]) - 12 * vel[c]) * h;
            x[c] += vel[c] * h;
            left -= h;
          }
          TEST_NEAR(2e-5, x[c], number(b.channels[c].x));
          TEST_NEAR(2e-4, vel[c], number(b.channels[c].v));
        }
        if (v == 1) {
          double& peak = peaks[to == slime::kSurprised];
          peak = std::max(peak, std::abs(number(b.channels[1].x)));
        }
      }
    }
  TEST_ASSERT_TRUE(peaks[1] > peaks[0] * 1.2);
  // Pushed past them, the spring is held to its bounds after it moves.
  Bridge pushed;
  for (auto& s : pushed.channels) s.v = 100;
  pushed.advance(kFrame);
  for (int c = 0; c < 3; ++c) {
    TEST_ASSERT_TRUE(pushed.channels[c].x == kBounds[c]);
    TEST_ASSERT_TRUE(pushed.channels[c].v == F(1));
  }
}

// A bridge that begins under a finger waits for it, its progress frozen,
// for 320 ms of holding in all, across separate grabs, and then expires,
// letting go with nothing owed; a bridge already played out stays played
// out, however long a finger then holds.
void test_a_grab_defers_then_expires_the_bridge() {
  Random r(53);
  Bridge held;
  held.context(false, true, false);
  held.retarget(slime::kCalm, slime::kSurprised, 0, r, 1);
  for (int frame = 0; frame < 19; ++frame) held.advance(kFrame);
  TEST_ASSERT_FALSE(held.expired);
  TEST_ASSERT_TRUE(held.elapsedMs == T(0));
  held.advance(kFrame);
  TEST_ASSERT_TRUE(held.expired && held.suppressed);
  held.context(false, false, false);
  held.advance(kFrame);
  for (const auto& s : held.channels) TEST_ASSERT_TRUE(s.x == F(0) && s.v == F(0));

  Bridge early;
  early.context(false, true, false);
  early.retarget(slime::kCalm, slime::kSurprised, 0, r, 1);
  for (int frame = 0; frame < 10; ++frame) early.advance(kFrame);
  early.context(false, false, false);
  early.advance(kFrame);
  TEST_NEAR(1e-6, 16, number(early.elapsedMs));
  TEST_ASSERT_FALSE(early.expired);
  early.context(false, true, false);
  for (int frame = 0; frame < 9; ++frame) early.advance(kFrame);
  TEST_ASSERT_FALSE(early.expired);
  early.advance(kFrame);
  TEST_ASSERT_TRUE(early.expired);

  Bridge played;
  played.retarget(slime::kCalm, slime::kCurious, 0, r, 1);
  for (int frame = 0; frame < 63; ++frame) played.advance(kFrame);
  TEST_ASSERT_TRUE(played.progress() == F(1));
  played.context(false, true, false);
  for (int frame = 0; frame < 24; ++frame) played.advance(kFrame);
  TEST_ASSERT_FALSE(played.expired || played.suppressed);
  TEST_ASSERT_TRUE(played.deferredMs == T(0) && played.elapsedMs == played.durationMs);
}

// While the body rests, a finger holds it or something needs you, a mood
// change plays no bridge: its spring only settles, frame by frame; the
// request on screen keeps its identity, a needs-you's knocks and its one
// ding coming exactly as they would have with no mood change; the face
// keeps its sleeping target while it sleeps; and the mood asked for is
// kept for afterwards. On every third edge, each in one of its variants,
// to keep the run short.
void test_a_quiet_or_alerting_body_holds_the_bridge() {
  for (int i = 0; i < slime::kEdgeCount; i += 3) {
    const auto& edge = slime::kEdges[i];
    const int v = i % 3;
    for (const bool asleep : {true, false}) {
      uint32_t t;
      auto e = prepared(edge.from, 0, t);
      Facts f;
      if (asleep) {
        f.base = SceneState::kAsleep;
        e->setFacts(f);
      } else {
        e->dragStart(q(.2), q(.3));
        e->dragMove(q(.15), q(.1), 0);
      }
      for (const uint32_t end = t + 320; t < end;) e->step(t += 16);
      e->setMood(edge.to, v);
      const std::string identity = e->scenes.requestId;
      Spring was[3];
      copy(was, e->bridge.channels);
      for (const uint32_t end = t + 1280; t < end;) {
        e->step(t += 16);
        expectSettling(*e, was);
        TEST_ASSERT_EQUAL_STRING(identity.c_str(), e->scenes.requestId.c_str());
      }
      if (asleep) {
        TEST_ASSERT_TRUE(e->face.targetSleeping);
        TEST_ASSERT_EQUAL_INT(edge.to, e->face.targetId);
        f.base = SceneState::kIdle;
        e->setFacts(f);
      } else {
        TEST_ASSERT_TRUE(e->bridge.expired);
        e->dragEnd();
      }
      for (const uint32_t end = t + 480; t < end;) {
        e->step(t += 16);
        expectSettling(*e, was);
      }
      TEST_ASSERT_EQUAL_INT(edge.to, e->emotion);
    }
    // Needs you: against an engine with no mood change, the same contacts
    // every frame, and one ding in 4.8 s.
    uint32_t t, u;
    auto subject = prepared(edge.from, 0, t), baseline = prepared(edge.from, 0, u);
    Facts f;
    f.base = SceneState::kWorking;
    f.attention = {true, "99", "codex", "bridge", "", 0};
    for (auto* e : {subject.get(), baseline.get()}) {
      e->setFacts(f);
      for (uint32_t s = t + 16; s <= t + 96; s += 16) e->step(s);
    }
    t += 96;
    const std::string identity = subject->scenes.requestId;
    subject->setMood(edge.to, v);
    Spring was[3];
    copy(was, subject->bridge.channels);
    int dings = 0;
    for (const uint32_t end = t + 4800; t < end;) {
      t += 16;
      subject->step(t);
      baseline->step(t);
      expectSettling(*subject, was);
      TEST_ASSERT_EQUAL_STRING(identity.c_str(), subject->scenes.requestId.c_str());
      const auto &a = subject->scenes.contacts, &b = baseline->scenes.contacts;
      TEST_ASSERT_EQUAL_INT(int(b.size()), int(a.size()));
      for (size_t k = 0; k < a.size(); ++k) {
        TEST_ASSERT_TRUE(a[k].kind == b[k].kind && a[k].index == b[k].index && a[k].timeMs == b[k].timeMs &&
                         a[k].strength == b[k].strength && a[k].requestId == b[k].requestId);
        dings += a[k].kind == kAlert;
      }
    }
    TEST_ASSERT_EQUAL_INT(1, dings);
    f = {};
    subject->setFacts(f);
    for (const uint32_t end = t + 480; t < end;) {
      subject->step(t += 16);
      expectSettling(*subject, was);
    }
    TEST_ASSERT_EQUAL_INT(edge.to, subject->emotion);
  }
}

// Seven moods asked for 48 ms apart: each retarget starts the face from its
// controls as they are; the controls stay within the span of everything
// they started from or were asked for; four arts cross over at once at the
// most; and the face settles on the last, alone, within a second.
void test_a_rapid_chain_settles_on_the_last() {
  auto e = std::make_unique<Engine>();
  uint32_t t = 0;
  e->step(t);
  frames::Frame last = frames::capture(*e);
  std::array<F, 8> lo = e->face.controls, hi = e->face.controls;
  int crowded = 0;
  const int chain[] = {slime::kCurious, slime::kSurprised, slime::kFrightened, slime::kSad,
                       slime::kHappy,   slime::kWounded,   slime::kAngry};
  auto frame = [&] {
    e->step(t += 16);
    frames::check(*e, &last);
    last = frames::capture(*e);
    for (int k = 0; k < 8; ++k)
      TEST_ASSERT_TRUE(e->face.controls[k] >= lo[k] - q(.000001) && e->face.controls[k] <= hi[k] + q(.000001));
    crowded = std::max(crowded, e->face.count);
  };
  for (int i = 0; i < 7; ++i) {
    const auto before = e->face.controls;
    e->setMood(chain[i], i % 3);
    TEST_ASSERT_TRUE(e->face.from == before);
    for (int k = 0; k < 8; ++k) lo[k] = min(lo[k], e->face.to[k]), hi[k] = max(hi[k], e->face.to[k]);
    for (int k = 0; k < 3; ++k) frame();
  }
  for (const uint32_t end = t + 1024; t < end;) frame();
  TEST_ASSERT_EQUAL_INT(4, crowded);
  TEST_ASSERT_EQUAL_INT(1, e->face.count);
  TEST_ASSERT_EQUAL_INT(slime::kAngry, e->face.current().art);
}

// Each directed edge deals its three variants from a bag of its own: every
// three of its retargets play each once, and never the same twice running,
// across bags too.
void test_each_edge_deals_its_own_bag() {
  Bridge b;
  Random r(53);
  std::vector<int> picks[slime::kEdgeCount];
  for (int round = 0; round < 6; ++round)
    for (int i = 0; i < slime::kEdgeCount; ++i) {
      b.retarget(slime::kEdges[i].from, slime::kEdges[i].to, round * 1000, r);
      TEST_ASSERT_EQUAL_INT(i, b.edge);
      picks[i].push_back(b.variant);
    }
  for (const auto& p : picks) {
    for (int at = 0; at < 6; at += 3) {
      std::vector<int> bag(p.begin() + at, p.begin() + at + 3);
      std::sort(bag.begin(), bag.end());
      TEST_ASSERT_TRUE(bag == (std::vector<int>{0, 1, 2}));
    }
    for (size_t k = 1; k < p.size(); ++k) TEST_ASSERT_NOT_EQUAL(p[k - 1], p[k]);
  }
}

// The face's controls each follow a critically damped spring at frequency
// 20, which keeps its velocity across a retarget and never overshoots from
// rest; a mood change draws nothing different at once, then crosses its
// arts over in the face's 180 ms, the new one's weight a smoothstep, the
// newest drawn last; waking takes the same window and spring; and an art is
// drawn at a ratio of its own size that is one at one, rises with slope one
// there and saturates inside (3/4, 4/3).
void test_the_semantic_face_numbers() {
  static_assert(SemanticFace::kFaceMs == 180 && SemanticFace::kFaceFrequency == 20, "the face's window and spring");
  // One frame of the spring, from where the controls are and as fast as
  // they're going, toward the target, at kScale.
  auto spring = [](double x, double v, double goal, double w, double& outV) {
    x *= SemanticFace::kScale, v *= 1, goal *= SemanticFace::kScale;
    for (double left = .016; left > 1e-12;) {
      const double h = std::min(left, 1.0 / 240);
      v += (w * w * (goal - x) - 2 * w * v) * h;
      x += v * h;
      left -= h;
    }
    outV = v;
    return x / SemanticFace::kScale;
  };
  for (int id = 0; id + 1 < slime::kProfiles; ++id) {
    SemanticFace f;
    f.setMood(id);
    for (int frame = 0; frame < 60; ++frame) f.advance(kFrame);
    TEST_ASSERT_EQUAL_INT(1, f.count);
    const SemanticFace settled = f;
    f.setMood(id + 1);
    TEST_ASSERT_EQUAL_INT(2, f.count);
    TEST_ASSERT_TRUE(f.controls == settled.controls && f.velocity == settled.velocity);
    TEST_ASSERT_TRUE(f.layers[0].weight == F(1) && f.layers[1].weight == F(0));
    TEST_ASSERT_TRUE(f.ratios(f.layers[0]) == settled.ratios(settled.layers[0]));
    const auto start = f.controls, goal = f.to;
    for (int frame = 1; frame <= 12; ++frame) {
      const auto was = f.controls;
      const auto speed = f.velocity;
      f.advance(kFrame);
      for (int k = 0; k < 6; ++k) {
        double v;
        const double x = spring(number(was[k]), number(speed[k]), number(goal[k]), 20, v);
        TEST_NEAR(2e-6, x, number(f.controls[k]));
        TEST_ASSERT_TRUE(f.controls[k] >= min(start[k], goal[k]) && f.controls[k] <= max(start[k], goal[k]));
      }
      if (frame < 12) {
        TEST_ASSERT_EQUAL_INT(2, f.count);
        TEST_ASSERT_EQUAL_INT(id + 1, f.current().art);
        const double s = frame * 16 / 180.0;
        TEST_NEAR(1e-4, s * s * (3 - 2 * s), number(f.layers[1].weight));
      } else {
        TEST_ASSERT_EQUAL_INT(1, f.count);
      }
    }
  }
  // A retarget mid-window keeps every control's velocity, the next frame
  // carrying on from it toward the new target, and draws the newest last.
  SemanticFace f;
  f.setMood(slime::kFrightened);
  f.advance(kFrame);
  f.advance(kFrame);
  const auto moving = f.velocity;
  const auto at = f.controls;
  f.setMood(slime::kHappy);
  TEST_ASSERT_TRUE(f.velocity == moving);
  TEST_ASSERT_EQUAL_INT(3, f.count);
  TEST_ASSERT_EQUAL_INT(slime::kCalm, f.layers[0].art);
  TEST_ASSERT_EQUAL_INT(slime::kFrightened, f.layers[1].art);
  TEST_ASSERT_EQUAL_INT(slime::kHappy, f.layers[2].art);
  f.advance(kFrame);
  for (int k = 0; k < 6; ++k) {
    double v;
    TEST_NEAR(2e-6, spring(number(at[k]), number(moving[k]), number(f.to[k]), 20, v), number(f.controls[k]));
  }
  // Waking from a settled sleeping face: the face's window, and its spring.
  SemanticFace sleeper;
  sleeper.setSleeping(true);
  for (int frame = 0; frame < 300; ++frame) sleeper.advance(kFrame);
  TEST_ASSERT_TRUE(sleeper.current().sleeping);
  sleeper.setMood(slime::kHappy);
  const auto asleep = sleeper.controls;
  sleeper.setSleeping(false);
  TEST_ASSERT_TRUE(sleeper.durationMs == T(SemanticFace::kFaceMs));
  sleeper.advance(kFrame);
  double v;
  TEST_NEAR(2e-6, spring(number(asleep[2]), 0, number(slime::kProfile[slime::kHappy].face[2]), 20, v),
            number(sleeper.controls[2]));
  for (int frame = 1; frame < 12; ++frame) sleeper.advance(kFrame);
  TEST_ASSERT_EQUAL_INT(1, sleeper.count);
  TEST_ASSERT_EQUAL_INT(slime::kHappy, sleeper.current().art);
  TEST_ASSERT_FALSE(sleeper.current().sleeping);
  // The drawn ratio of an art's own size.
  TEST_ASSERT_TRUE(softRatio(F(1)) == F(1));
  TEST_NEAR(5e-3, 1, (number(softRatio(q(1.001))) - number(softRatio(q(.999)))) / .002);
  F last = softRatio(F(0));
  TEST_ASSERT_TRUE(last > q(.75));
  for (int k = 1; k <= 1200; ++k) {
    const F now = softRatio(F::ratio(k, 100));
    TEST_ASSERT_TRUE(now > last && now > q(.75) && now < q(4.0 / 3));
    last = now;
  }
}
