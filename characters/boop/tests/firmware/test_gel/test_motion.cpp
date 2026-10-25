// The gel engine's motion against its numbers: the body's springs, pokes,
// blink and gaze and the clock (the accepted motion: changing it means
// changing this file), the finger, acting's takes and springs, every
// setter leaving the springs where they are, and the scenes' activity.
#include <unity.h>

#include <cmath>
#include <cstring>
#include <memory>

#include "frames.h"
#include "render/gel/engine.h"
#include "render/tags.h"

using namespace render;
using namespace render::gel;

namespace {

double num(F f) { return double(f.raw) / F::scale; }
double num(T t) { return num(F(t)); }
const T kFrame = T::ratio(16, 1000);
bool near(F a, double b, double tolerance) { return std::abs(num(a) - b) <= tolerance; }

// A spring as the engine integrates one, in doubles: 1/240 s substeps of
// stiffness k and damping c, then its position and velocity limits.
struct Ref {
  double x = 0, v = 0;
};
void spring(Ref& s, double dt, double target, double k, double c, double xl = 1e9, double vl = 1e9) {
  for (double left = dt; left > 1e-12;) {
    const double h = std::min(left, 1.0 / 240);
    s.v += (k * (target - s.x) - c * s.v) * h;
    s.x += s.v * h;
    left -= h;
  }
  s.x = std::clamp(s.x, -xl, xl);
  s.v = std::clamp(s.v, -vl, vl);
}
Ref ref(const Spring& s) { return {num(s.x), num(s.v)}; }
// The body's modes, copied.
std::array<Spring, 4> modes(const Motion& m) { return {m.modes[0], m.modes[1], m.modes[2], m.modes[3]}; }
bool near(const Spring& s, const Ref& r, double x, double v) { return near(s.x, r.x, x) && near(s.v, r.v, v); }
bool same(const Spring& a, const Spring& b) { return a.x == b.x && a.v == b.v; }

// The body's four modes: lean, squash, ripple and dent, each a frequency
// and a damping (stiffness the frequency's square).
constexpr double kModeFrequency[] = {11, 13, 18, 16}, kModeDamping[] = {4.6, 4.5, 5.3, 6};

Request request(SceneState anim, const char* id) {
  Request r;
  r.anim = anim;
  r.hasId = true;
  r.id = id;
  return r;
}

}  // namespace

// The body's four modes are springs, lean 11 and 4.6, squash 13 and 4.5,
// ripple 18 and 5.3, dent 16 and 6 (frequency and damping), in 1/240 s
// substeps, held within ±0.72 at ±9 a second, and nothing else moves them
// between frames. A poke adds velocity to each, never position: the lean
// 2.6 away from where it's poked, the squash -3.5, the ripple 3.5, the dent
// 4.8; a shake 4.5, -2.6, 5 and 0; each mode within ±8 however many come.
// The body breathes, its squash 0.011 sin(1.65 t). It blinks, sin² over
// 0.24 s, first just past 2.8 s, then 3 to 7 s on, and glances at most
// 0.014 either way, first just past 4.5 s, then 3.2 to 7.2 s on, its gaze
// easing there at rate 3. The engine's clock starts at its first step,
// takes at most 45 ms from any step, stands still for a repeated time, and
// wraps with the board's milliseconds.
void test_the_motion_v1_numbers() {
  for (int i = 0; i < 4; ++i) {
    Motion m;
    Random random(53);
    m.modes[i].v = 1;
    Ref s{0, 1};
    T now;
    for (int frame = 1; frame <= 120; ++frame) {
      m.advance(kFrame, now += kFrame, random);
      spring(s, .016, 0, kModeFrequency[i] * kModeFrequency[i], kModeDamping[i], .72, 9);
      TEST_ASSERT_TRUE(near(m.modes[i], s, 2e-4, 5e-4));
      for (int j = 0; j < 4; ++j)
        if (j != i) TEST_ASSERT_TRUE(m.modes[j].x == F(0) && m.modes[j].v == F(0));
    }
  }
  {
    Motion m;
    Random random(53);
    m.modes[0].x = 5;
    m.modes[1].v = 100;
    m.modes[2].v = -100;
    m.advance(T(), T(), random);  // no time passes: only the limits apply
    TEST_ASSERT_TRUE(m.modes[0].x == q(.72) && m.modes[1].v == F(9) && m.modes[2].v == F(-9));
  }
  struct Kick {
    bool shake;
    F x;
    double dv[4];
  } kicks[] = {{false, q(-.4), {2.6, -3.5, 3.5, 4.8}},
               {false, q(.4), {-2.6, -3.5, 3.5, 4.8}},
               {false, F(0), {-2.6, -3.5, 3.5, 4.8}},
               {true, F(0), {4.5, -2.6, 5, 0}}};
  for (const auto& kick : kicks) {
    Motion m;
    for (int i = 0; i < 4; ++i) m.modes[i] = {q(.1) * (i + 1), q(.5)};
    const auto before = modes(m);
    m.impulse(kick.shake, kick.x);
    for (int i = 0; i < 4; ++i) {
      TEST_ASSERT_TRUE(m.modes[i].x == before[i].x);
      TEST_ASSERT_TRUE(m.modes[i].v == before[i].v + q(kick.dv[i]));
    }
  }
  {
    Motion m;
    for (int i = 0; i < 100; ++i) m.impulse(false, q(-.5));
    TEST_ASSERT_TRUE(m.modes[0].v == F(8) && m.modes[1].v == F(-8) && m.modes[2].v == F(8) && m.modes[3].v == F(8));
    for (int i = 0; i < 100; ++i) m.impulse(true);
    for (const auto& mode : m.modes) TEST_ASSERT_TRUE(abs(mode.v) <= F(8));
  }
  {
    Motion m;
    for (int i = 0; i <= 100; ++i) {
      m.time = T::literal(i * .173);
      TEST_ASSERT_TRUE(near(m.pose()[1] - m.modes[1].x, .011 * std::sin(1.65 * i * .173), 2e-6));
    }
  }
  {
    Motion m;
    Random random(53);
    T blinkAt = m.blinkAt;
    int blinks = 0, looks = 0;
    T now;
    for (int frame = 1; frame <= 7500; ++frame) {
      now += kFrame;
      const T look = m.nextLook;
      const F gaze = m.gaze;
      m.advance(kFrame, now, random);
      if (m.blinkAt != blinkAt) {
        blinkAt = m.blinkAt;
        if (!blinks++) TEST_ASSERT_TRUE(num(blinkAt) >= 2.8 - 1e-6 && num(blinkAt) < 2.8 + .016 + 1e-6);
        const double gap = num(m.nextBlink) - num(blinkAt);
        TEST_ASSERT_TRUE(gap >= 3 - 1e-6 && gap < 7 + 1e-6);
        Motion probe = m;
        const double at[] = {-.01, 0, .06, .12, .18, .24, .3}, want[] = {0, 0, .5, 1, .5, 0, 0};
        for (int k = 0; k < 7; ++k) {
          probe.time = blinkAt + T::literal(at[k]);
          TEST_ASSERT_TRUE(near(probe.blink(), want[k], 1e-4));
        }
      }
      if (m.nextLook != look) {
        if (!looks++) TEST_ASSERT_TRUE(num(now) >= 4.5 - 1e-6 && num(now) < 4.5 + .016 + 1e-6);
        TEST_ASSERT_TRUE(abs(m.gazeTarget) <= q(.014));
        const double gap = num(m.nextLook) - num(now);
        TEST_ASSERT_TRUE(gap >= 3.2 - 1e-6 && gap < 7.2 + 1e-6);
      }
      TEST_ASSERT_TRUE(near(m.gaze, num(gaze) + (num(m.gazeTarget) - num(gaze)) * (1 - std::exp(-3 * .016)), 1e-6));
    }
    TEST_ASSERT_TRUE(blinks >= 120 / 7 && looks >= 120 / 8);
  }
  {
    // In the engine, between frames only the modes' own springs move them,
    // and a poke changes their velocity alone.
    auto e = std::make_unique<Engine>();
    e->step(0);
    for (uint32_t t = 16; t <= 8000; t += 16) {
      if (t == 3008 || t == 3200) {
        const auto before = modes(e->motion);
        TEST_ASSERT_TRUE(
            e->oneShot(request(t == 3008 ? SceneState::kPoked : SceneState::kTapSpam, t == 3008 ? "p" : "s")));
        const double dv[2][4] = {{-2.6, -3.5, 3.5, 4.8}, {4.5, -2.6, 5, 0}};
        for (int i = 0; i < 4; ++i) {
          TEST_ASSERT_TRUE(e->motion.modes[i].x == before[i].x);
          TEST_ASSERT_TRUE(e->motion.modes[i].v == clamp(before[i].v + q(dv[t == 3200][i]), -8, 8));
        }
      }
      auto want = modes(e->motion);
      for (int i = 0; i < 4; ++i) integrate(want[i], kFrame, 0, q(kModeFrequency[i]), q(kModeDamping[i]), q(.72), 9);
      e->step(t);
      for (int i = 0; i < 4; ++i) TEST_ASSERT_TRUE(same(e->motion.modes[i], want[i]));
    }
  }
  auto e = std::make_unique<Engine>();
  const uint32_t steps[] = {1000, 1016, 2016, 2016, 0xFFFFFFF0u, 0x10u};
  const uint32_t elapsed[] = {0, 16, 61, 61, 106, 138};
  for (int i = 0; i < 6; ++i) {
    e->step(steps[i]);
    TEST_ASSERT_EQUAL_UINT32(elapsed[i], e->elapsedMs);
    TEST_ASSERT_TRUE(near(F(e->motion.time), elapsed[i] / 1000.0, 1e-6));
  }
}

// The finger: down, it holds the dome where it touched, within ±1 either
// way, and a second finger changes nothing; moved, the pull's target is the
// finger's displacement up to 0.32, then gives less and less (slope one at
// 0.32), rising toward 0.64 and never reaching it. Held, the pull follows it
// on a spring of stiffness 256 and damping 20; let go, on 100 and 13, within
// ±0.72 at ±6 a second. The body leans twice the pull's x and squashes its
// y. Let go moving, it's flung on: 0.3 of the finger's velocity, at most 6,
// and outward only as far as the room left before 0.72; at rest, let go
// changes nothing that moves but the target, and acting waits 3 s.
void test_the_finger_numbers() {
  static_assert(Engine::kGrabHeld[0] == 16 && Engine::kGrabHeld[1] == 20 && Engine::kGrabReleased[0] == 10 &&
                    Engine::kGrabReleased[1] == 13,
                "the pull's springs, held and let go: frequency and damping");
  static_assert(Engine::kGrabKnee == q(.32) && Engine::kGrabReach == q(.64) && Engine::kGrabLimit == q(.72) &&
                    Engine::kGrabVelocity == 6 && Engine::kGrabLean == F(2) && Engine::kGrabSquash == F(1) &&
                    Engine::kGrabFling == q(.3),
                "the finger's knee and reach, the pull's limits, the body's "
                "lean and squash, the fling");
  {
    auto e = std::make_unique<Engine>();
    e->step(0);
    e->dragStart(2, -2);
    TEST_ASSERT_TRUE(e->grab && e->point[0] == F(1) && e->point[1] == F(-1));
    e->dragStart(q(.1), q(.1));
    TEST_ASSERT_TRUE(e->point[0] == F(1) && e->point[1] == F(-1));
    const auto reach = [](double len) { return len <= .32 ? len : .32 + (len - .32) * .32 / (len - .32 + .32); };
    double last = 0;
    for (int i = 1; i <= 400; ++i) {
      const double len = i * .01;
      e->dragMove(q(len * .6), q(len * .8), 0);  // its length is len
      const double x = num(e->target[0]), y = num(e->target[1]), got = std::hypot(x, y);
      TEST_ASSERT_TRUE(std::abs(got - reach(len)) <= 2e-5 && got < .64 && got > last);
      TEST_ASSERT_TRUE(std::abs(x * .8 - y * .6) <= 2e-6 && e->target[2] == F(0));  // the finger's way
      last = got;
    }
    e->dragMove(q(.32), 0, 0);
    const F knee = e->target[0];
    e->dragMove(q(.3201), 0, 0);
    TEST_ASSERT_TRUE(std::abs(num(e->target[0] - knee) / .0001 - 1) <= .01);
  }
  {
    auto e = std::make_unique<Engine>();
    e->step(0);
    e->dragStart(0, q(.2));
    e->dragMove(q(.2), 0, 0);
    Ref s;
    uint32_t t = 0;
    for (int frame = 0; frame < 30; ++frame) {
      e->step(t += 16);
      spring(s, .016, .2, 256, 20, .72, 6);
      TEST_ASSERT_TRUE(near(e->pull[0], s, 2e-5, 1e-4));
    }
    e->dragEnd();
    for (int frame = 0; frame < 30; ++frame) {
      e->step(t += 16);
      spring(s, .016, 0, 100, 13, .72, 6);
      TEST_ASSERT_TRUE(near(e->pull[0], s, 2e-5, 1e-4));
    }
  }
  {
    auto e = std::make_unique<Engine>();
    e->step(0);
    e->dragStart(0, q(.2));
    e->dragMove(q(.2), q(-.3), 0);
    uint32_t t = 0;
    for (; t < 480; t += 16) e->step(t + 16);
    const auto pose = e->pose();
    TEST_ASSERT_TRUE(e->pull[0].x > q(.15) && e->pull[1].x < q(-.2));
    TEST_ASSERT_TRUE(abs(pose[0] - e->pull[0].x * 2) <= q(.02) && abs(pose[1] - e->pull[1].x) <= q(.02));
    // At rest, let go: nothing that moves is touched but the target.
    const auto kept = modes(e->motion);
    const auto acting = e->acting;
    const auto bridge = e->bridge;
    Spring activity[3], pull[3];
    for (int i = 0; i < 3; ++i) activity[i] = e->scenes.activity[i], pull[i] = e->pull[i];
    e->dragEnd();
    TEST_ASSERT_FALSE(e->grab);
    for (int i = 0; i < 4; ++i) TEST_ASSERT_TRUE(same(e->motion.modes[i], kept[i]));
    for (int i = 0; i < 6; ++i) TEST_ASSERT_TRUE(same(e->acting.channels[i], acting.channels[i]));
    TEST_ASSERT_TRUE(same(e->acting.slide, acting.slide) && same(e->acting.lids, acting.lids));
    for (int i = 0; i < 3; ++i) {
      TEST_ASSERT_TRUE(same(e->scenes.activity[i], activity[i]) && same(e->pull[i], pull[i]));
      TEST_ASSERT_TRUE(same(e->bridge.channels[i], bridge.channels[i]) && e->target[i] == F(0));
    }
    TEST_ASSERT_TRUE(e->pose() == pose);
    TEST_ASSERT_TRUE(e->acting.nextPerformance >= e->motion.time + T(3));
  }
  // Flung from rest: 0.3 of the finger's speed, at most 6.
  for (const double speed : {-10.0, -100.0, 10.0}) {
    auto e = std::make_unique<Engine>();
    e->step(0);
    e->dragStart(0, q(.2));
    e->dragEnd(0, q(speed), 0);
    TEST_ASSERT_TRUE(near(e->pull[1].v, std::clamp(speed * .3, -6.0, 6.0), 1e-6));
    TEST_ASSERT_TRUE(e->pull[0].v == F(0) && e->pull[2].v == F(0));
  }
  // Flung from where it's pulled: outward by the room left, inward whole.
  for (const double speed : {-10.0, 10.0}) {
    auto e = std::make_unique<Engine>();
    e->step(0);
    e->dragStart(0, q(.2));
    e->dragMove(0, -3, 0);
    for (uint32_t t = 16; t <= 800; t += 16) e->step(t);
    const double x = num(e->pull[1].x), v = num(e->pull[1].v);
    TEST_ASSERT_TRUE(x < -.55);
    e->dragEnd(0, q(speed), 0);
    const double add = speed * .3 * (speed < 0 ? 1 - std::abs(x) / .72 : 1);
    TEST_ASSERT_TRUE(near(e->pull[1].v, std::clamp(v + add, -6.0, 6.0), 1e-5));
  }
  // However hard it's pulled and flung, the pull stays inside its limits.
  auto e = std::make_unique<Engine>();
  e->step(0);
  e->dragStart(0, q(.2));
  e->dragMove(5, 5, 5);
  uint32_t t = 0;
  frames::Frame before = frames::capture(*e);
  for (int frame = 0; frame < 190; ++frame) {
    if (frame == 40) e->dragEnd(100, -100, 100);
    e->step(t += 16);
    frames::check(*e, &before);
    before = frames::capture(*e);
  }
}

// Acting's takes: the first plays 1 s in; each next one after the take's
// own length and 7 to 15 s more, never the take just played; a new mood
// puts the next off 0.4 s from then. A take's impulses add their velocity
// at their times. The gesture springs are the lean's, squash's, ripple's and
// forward's 9, the lift's 11 and the roll's 10, damped 6.4 and held within
// 0.42, the lift's 0.24, the roll's 0.12 and the forward's 0.18, at 5 a
// second; a gag's slide is 10 and 9 within 0.7 at 5, its lids 24 and 48
// (critically damped) within 1 at 20. The mood's posture follows the mood
// on a critically damped spring of 10, proud's squash 0.05.
void test_acting_timing_and_springs() {
  {
    auto e = std::make_unique<Engine>();
    e->step(0);
    TEST_ASSERT_TRUE(e->acting.nextPerformance == T(1));
    int count = 0, last = -1;
    for (uint32_t t = 16; t <= 600000; t += 16) {
      const int before = e->acting.count;
      e->step(t);
      if (e->acting.count == before) continue;
      const double start = num(e->acting.start);
      if (!count) TEST_ASSERT_TRUE(start >= 1 && start < 1.016 + 1e-6);
      const double gap = num(e->acting.nextPerformance) - start -
                         num(Acting::gesture(e->acting.emotion, e->acting.performance).duration);
      TEST_ASSERT_TRUE(gap >= 7 - 1e-5 && gap < 15 + 1e-5);
      TEST_ASSERT_TRUE(e->acting.performance != last);
      last = e->acting.performance;
      ++count;
    }
    TEST_ASSERT_TRUE(count > 30);
    e->setMood(slime::kHappy);
    TEST_ASSERT_TRUE(e->acting.performance == -1 && e->acting.nextPerformance == e->motion.time + T::literal(.4));
  }
  {
    const double frequency[] = {9, 9, 9, 11, 10, 9}, limit[] = {.42, .42, .42, .24, .12, .18};
    Acting a;
    Random random(53);
    Ref s[6], slide{0, 1}, lids{0, 1};
    for (int i = 0; i < 6; ++i) a.channels[i].v = 1, s[i] = {0, 1};
    a.slide.v = a.lids.v = 1;
    for (int frame = 0; frame < 60; ++frame) {
      a.advance(kFrame, T(), false,
                random);  // its clock held before its first take: nothing plays
      for (int i = 0; i < 6; ++i) {
        spring(s[i], .016, 0, frequency[i] * frequency[i], 6.4, limit[i], 5);
        TEST_ASSERT_TRUE(near(a.channels[i], s[i], 1e-4, 5e-4));
      }
      spring(slide, .016, 0, 100, 9, .7, 5);
      spring(lids, .016, 0, 576, 48, 1, 20);
      TEST_ASSERT_TRUE(near(a.slide, slide, 1e-4, 5e-4) && near(a.lids, lids, 1e-4, 5e-4));
    }
    for (int i = 0; i < 6; ++i) a.channels[i] = {F(5), F(100)};
    a.slide = a.lids = {F(5), F(-100)};
    a.advance(T(), T(), false, random);
    for (int i = 0; i < 6; ++i) TEST_ASSERT_TRUE(a.channels[i].x == q(limit[i]) && a.channels[i].v == F(5));
    TEST_ASSERT_TRUE(a.slide.x == q(.7) && a.slide.v == F(-5) && a.lids.x == F(1) && a.lids.v == F(-20));
  }
  {
    Acting a;
    Random random(53);
    TEST_ASSERT_TRUE(a.perform(T(), random, 0));
    const auto& p = slime::kProfile[slime::kCalm].performances[0];
    TEST_ASSERT_TRUE(p.count > 0);
    for (int k = 0; k < p.count;) {
      const T at = p.cues[k].at;
      double want[7];
      for (int c = 0; c < 6; ++c) want[c] = num(a.channels[c].v);
      want[6] = num(a.slide.v);
      for (; k < p.count && p.cues[k].at == at; ++k) want[p.cues[k].channel] += num(p.cues[k].velocity);
      a.advance(T(), at, false, random);
      for (int c = 0; c < 6; ++c) TEST_ASSERT_TRUE(near(a.channels[c].v, std::clamp(want[c], -5.0, 5.0), 1e-6));
      TEST_ASSERT_TRUE(near(a.slide.v, std::clamp(want[6], -5.0, 5.0), 1e-6));
    }
  }
  auto e = std::make_unique<Engine>();
  uint32_t t = 0;
  for (; t < 2000; t += 16) e->step(t);
  e->step(t);  // the last before the mood
  e->setMood(slime::kProud);
  Ref proud = ref(e->postureWeights[slime::kProud]), calm = ref(e->postureWeights[slime::kCalm]);
  for (int frame = 0; frame < 60; ++frame) {
    e->step(t += 16);
    spring(proud, .016, 1, 100, 20);
    spring(calm, .016, 0, 100, 20);
    TEST_ASSERT_TRUE(near(e->postureWeights[slime::kProud], proud, 1e-5, 1e-4));
    TEST_ASSERT_TRUE(near(e->postureWeights[slime::kCalm], calm, 1e-5, 1e-4));
    TEST_ASSERT_TRUE(near(e->posture()[1], .05 * proud.x, 1e-5));
  }
}

namespace {

// Every spring in the engine, and what its face eases.
struct Springs {
  std::array<Spring, 4> modes;
  Spring acting[6], slide, lids, activity[3], bridge[3], pull[3], desk, quietMix;
  Spring posture[slime::kProfiles];
  std::array<F, 8> controls, velocity;
  T time;
};
Springs springs(const Engine& e) {
  Springs s;
  s.modes = modes(e.motion);
  for (int i = 0; i < 6; ++i) s.acting[i] = e.acting.channels[i];
  s.slide = e.acting.slide;
  s.lids = e.acting.lids;
  for (int i = 0; i < 3; ++i)
    s.activity[i] = e.scenes.activity[i], s.bridge[i] = e.bridge.channels[i], s.pull[i] = e.pull[i];
  s.desk = e.scenes.desk;
  s.quietMix = e.scenes.quietMix;
  for (int i = 0; i < slime::kProfiles; ++i) s.posture[i] = e.postureWeights[i];
  s.controls = e.face.controls;
  s.velocity = e.face.velocity;
  s.time = e.motion.time;
  return s;
}
// The same, but for the modes' velocities when `kicked` (a poke's or a
// shake's), which then only stay within ±8.
bool same(const Springs& a, const Springs& b, bool kicked = false) {
  bool ok = a.time == b.time && same(a.slide, b.slide) && same(a.lids, b.lids) && same(a.desk, b.desk) &&
            same(a.quietMix, b.quietMix) && a.controls == b.controls && a.velocity == b.velocity;
  for (int i = 0; i < 4; ++i)
    ok &= a.modes[i].x == b.modes[i].x && (kicked ? abs(b.modes[i].v) <= F(8) : a.modes[i].v == b.modes[i].v);
  for (int i = 0; i < 6; ++i) ok &= same(a.acting[i], b.acting[i]);
  for (int i = 0; i < 3; ++i)
    ok &= same(a.activity[i], b.activity[i]) && same(a.bridge[i], b.bridge[i]) && same(a.pull[i], b.pull[i]);
  for (int i = 0; i < slime::kProfiles; ++i) ok &= same(a.posture[i], b.posture[i]);
  return ok;
}
// Two engines draw the same: every spring, the face's arts and the body's
// pose, the contacts and the sounds.
bool alike(const Engine& a, const Engine& b) {
  bool ok = same(springs(a), springs(b)) && a.pose() == b.pose() && a.life() == b.life() && a.blink() == b.blink() &&
            a.face.count == b.face.count && a.scenes.contacts.size() == b.scenes.contacts.size() &&
            a.cues.size() == b.cues.size() && a.scenes.route.state == b.scenes.route.state;
  for (int i = 0; ok && i < a.face.count; ++i)
    ok = a.face.layers[i].art == b.face.layers[i].art && a.face.layers[i].weight == b.face.layers[i].weight;
  for (size_t i = 0; ok && i < a.scenes.contacts.size(); ++i)
    ok = a.scenes.contacts[i].kind == b.scenes.contacts[i].kind &&
         a.scenes.contacts[i].index == b.scenes.contacts[i].index;
  for (size_t i = 0; ok && i < a.cues.size(); ++i) {
    const auto &x = a.cues[i], &y = b.cues[i];
    ok = !std::strcmp(x.recipe, y.recipe) && x.variant == y.variant && x.seed == y.seed && x.pitch == y.pitch &&
         x.gain == y.gain;
  }
  return ok;
}

Facts facts(SceneState base, SceneState act = SceneState::kWorking, const char* attention = nullptr) {
  Facts f;
  f.base = base;
  f.act = act;
  if (attention) f.attention = {true, attention, "claude", "boop", "", 0};
  return f;
}

}  // namespace

// Every setter (a mood, facts, a reaction, a borrowed face, a lost link, the
// tags, the finger) changes what the engine aims for and never where a
// spring is or how fast it moves, nor the clock; a poke or a shake adds to
// the body's velocity alone. A reaction already had, and a touch while an
// agent needs you, are refused and kick nothing. Two engines with one seed
// fed the same draw the same, frame for frame, however another engine is
// driven meanwhile, and another seed draws otherwise. Every frame keeps its
// bounds.
void test_setters_keep_springs_and_replay() {
  auto a = std::make_unique<Engine>(53), b = std::make_unique<Engine>(53), c = std::make_unique<Engine>(8128),
       d = std::make_unique<Engine>(54);
  enum Kind {
    kHappy,
    kGrumpy,
    kSad,
    kWorking,
    kTesting,
    kWaiting,
    kNeedsYou,
    kIdle,
    kAsleep,
    kPoke,
    kTapSpam,
    kNight,
    kFinish,
    kBorrow,
    kLetGo,
    kGesture,
    kClear,
    kLost,
    kFound,
    kDown,
    kMove,
    kUp,
    kListen,
    kStop
  };
  struct Call {
    uint32_t at;
    Kind kind;
    const char* id = "";
    bool refused = false, kicks = false;
  };
  const Call calls[] = {{1000, kHappy},
                        {2000, kWorking},
                        {3000, kTesting},
                        {4000, kPoke, "p1", false, true},
                        {4100, kPoke, "p1", true},  // a reaction already had
                        {5000, kTapSpam, "t1", false, true},
                        {6000, kGrumpy},
                        {7000, kNight},
                        {8000, kNeedsYou},
                        {9000, kPoke, "p2", true},  // a touch while an agent needs you
                        {12000, kIdle},
                        {13000, kFinish, "done"},
                        {14000, kBorrow},
                        {15000, kLetGo},
                        {17000, kGesture, "g1"},
                        {19000, kClear},
                        {20000, kLost},
                        {22000, kFound},
                        {23000, kDown},
                        {23100, kMove},
                        {24000, kUp},
                        {25000, kAsleep},
                        {30000, kSad},
                        {33000, kIdle},
                        {35000, kListen, "mic"},
                        {37000, kStop},
                        {40000, kWaiting}};
  // Makes the call; false when the engine refuses it.
  auto call = [](Engine& e, const Call& k) {
    Request r;
    switch (k.kind) {
      case kHappy: e.setMood(slime::kHappy); break;
      case kGrumpy: e.setMood(slime::kGrumpy, 1); break;
      case kSad: e.setMood(slime::kSad); break;
      case kWorking: e.setFacts(facts(SceneState::kWorking)); break;
      case kTesting: e.setFacts(facts(SceneState::kWorking, SceneState::kTesting)); break;
      case kWaiting: e.setFacts(facts(SceneState::kWorking, SceneState::kWaiting)); break;
      case kNeedsYou: e.setFacts(facts(SceneState::kWorking, SceneState::kWorking, "9")); break;
      case kIdle: e.setFacts(facts(SceneState::kIdle)); break;
      case kAsleep: e.setFacts(facts(SceneState::kAsleep)); break;
      case kPoke: return e.oneShot(request(SceneState::kPoked, k.id));
      case kTapSpam: return e.oneShot(request(SceneState::kTapSpam, k.id));
      case kNight: e.setOccasion(tagBit("night"), 5000); break;
      case kFinish:
        r = request(SceneState::kTaskComplete, k.id);
        r.outcome = Outcome::kSuccess;
        return e.oneShot(r);
      case kBorrow: e.holdExpression(slime::kProud); break;
      case kLetGo: e.holdExpression(-1); break;
      case kGesture:
        r = request(SceneState::kGesture, k.id);
        r.variant = 5;
        r.hold = true;
        return e.oneShot(r);
      case kClear: e.clearTransient(); break;
      case kLost: e.linkTimedOut(true); break;
      case kFound: e.linkTimedOut(false); break;
      case kDown: e.dragStart(q(.3), q(.2)); break;
      case kMove: e.dragMove(q(.25), q(-.15), 0); break;
      case kUp: e.dragEnd(); break;
      case kListen: return e.oneShot(request(SceneState::kListening, k.id));
      case kStop: r.stop = true; return e.oneShot(r);
    }
    return true;
  };
  for (Engine* e : {a.get(), b.get(), c.get(), d.get()}) e->step(0);
  frames::Frame before = frames::capture(*a);
  bool differs = false;
  size_t next = 0;
  for (uint32_t t = 16; t <= 60000; t += 16) {
    for (; next < std::size(calls) && calls[next].at <= t; ++next) {
      const Call& k = calls[next];
      const Springs was = springs(*a);
      TEST_ASSERT_TRUE(call(*a, k) != k.refused);
      TEST_ASSERT_TRUE(same(was, springs(*a), k.kicks));
      if (k.kicks) TEST_ASSERT_FALSE(same(was, springs(*a)));  // and it did kick
      call(*b, k);
      call(*d, k);
    }
    // Another engine, fed otherwise, meanwhile.
    if (t % 2400 == 0) c->setMood((t / 2400) % slime::kProfiles);
    if (t % 3100 == 0) c->oneShot(request(SceneState::kPoked, std::to_string(t).c_str()));
    if (t == 9000) c->setFacts(facts(SceneState::kWorking, SceneState::kSearching));
    for (Engine* e : {a.get(), c.get(), b.get(), d.get()}) e->step(t);
    frames::check(*a, &before);
    before = frames::capture(*a);
    TEST_ASSERT_TRUE(alike(*a, *b));
    differs |= !alike(*a, *d);
  }
  TEST_ASSERT_TRUE(differs);
}

namespace {

// What a scene aims its activity at in a frame, worked out afresh from
// where the scene is: its recipe's lean, eased in over its first 240 ms and
// out over its last 480 (and, waiting or listening, waving between 0.3 and
// 1 of itself, focus times a recipe); the last contact's kick, a cos² over
// 120 ms (a key's, a knock's or the body's: leaning 0.024 its way, squashing
// 0.052 and pushing forward 0.045; a success's card lifting 0.036 and
// forward 0.025, a failure's sagging 0.048 and back 0.035; a start's, a
// helper's, a reply's or a stop's 0.018 up and forward, an error's 0.018 up
// and 0.025 back), at its strength; a mood's own gesture echoing as it
// recovers (lean 0.025, squash 0.018, forward 0.015 a unit of velocity,
// each cue a sin² over 0.48 s of the gesture played over the recovery); and
// asleep, a snore's breath swelling it.
std::array<double, 3> aim(const Engine& e) {
  const Scenes& s = e.scenes;
  const double now = num(e.timeMs()), age = num(s.ageMs), duration = num(s.recipe.duration);
  const bool active = !e.grab && !s.route.quiet;
  const double strength = s.hasLast ? num(s.last.strength) : 1;
  auto kick = [&](int kind) {
    if (!s.hasLast || s.last.kind != kind) return 0.0;
    const double since = now - num(s.last.timeMs);
    return since >= 0 && since < 120 ? std::pow(std::cos(since / 120 * M_PI / 2), 2) : 0.0;
  };
  const double contact = active ? std::max({kick(kKey), kick(kKnock), kick(kBody)}) * strength : 0;
  const double reveal = active ? std::max(kick(kSuccess), kick(kFailure)) * strength : 0;
  double present = 0;
  if (active)
    for (int kind : {kStart, kHelper, kReply, kError, kStopped}) present = std::max(present, kick(kind));
  present *= strength;
  const bool finish = s.route.state == SceneState::kTaskComplete;
  const bool success = finish && s.route.outcome == Outcome::kSuccess,
             failure = finish && s.route.outcome == Outcome::kFailure;
  const auto smoothstep = [](double x) {
    x = std::clamp(x, 0.0, 1.0);
    return x * x * (3 - 2 * x);
  };
  const bool recovering = !std::strcmp(s.phase, "recover");
  const double entry = smoothstep(age / 240), recovery = recovering ? smoothstep((duration - age) / 480)
                                                         : !std::strcmp(s.phase, "sustain") ? 0
                                                                                            : 1;
  double echo[3] = {};
  const auto& profile = slime::kProfile[s.profileExpression];
  if (active && recovering && !profile.representative && s.variant < kGestures && s.recipe.gag < 0) {
    const auto& p = profile.performances[s.variant];
    const double at = (1 - (duration - age) / 480) * num(p.duration);
    const int onto[] = {0, 1, 2, 1, 0, 2};  // lean, squash, ripple, lift, roll, forward:
                                            // onto lean, squash, forward
    const double gain[] = {.025, .018, .015};
    for (int i = 0; i < p.count; ++i) {
      const double since = at - num(p.cues[i].at);
      if (p.cues[i].channel > 5 || since < 0 || since > .48) continue;
      const int to = onto[p.cues[i].channel];
      echo[to] += num(p.cues[i].velocity) * gain[to] * std::pow(std::sin(M_PI * since / .48), 2);
    }
  }
  const bool waves = s.route.state == SceneState::kWaiting || s.route.state == SceneState::kListening;
  const double wave = waves ? .65 + .35 * std::sin(age / duration * M_PI * 2 * s.recipe.focus) : 1;
  if (!active) {
    double swell = 0;
    if (s.route.quiet && s.hasLast && s.last.kind == kBreath && now - num(s.last.timeMs) < slime::kSnoreSwellMs)
      swell = std::pow(std::sin((now - num(s.last.timeMs)) / slime::kSnoreSwellMs * M_PI), 2) * strength *
              num(slime::kSnoreSwell);
    return {0, swell, 0};
  }
  const double side = s.hasLast ? s.last.side : 0;
  return {num(s.recipe.lean) * entry * recovery * wave + side * contact * .024 + echo[0],
          -contact * .052 +
              (success   ? .036
               : failure ? -.048
                         : 0) *
                  reveal +
              present * .018 + echo[1],
          contact * .045 +
              (success   ? .025
               : failure ? -.035
                         : 0) *
                  reveal +
              present * (s.route.state == SceneState::kError ? -.025 : .018) + echo[2]};
}

}  // namespace

// A scene's activity is a spring (12 and 10, within lean 0.08, squash 0.06
// and forward 0.05, at 1.2 a second) toward what the scene aims at in that
// frame (aim, above), across the looks, the reactions and a mood's own
// recovery. A desk's contacts play up to 40 ms either side of their time,
// at 0.9 to 1.1 of their strength, and other recipes' as written. A gag's
// keys ease from rest, a smoothstep to each, then hold the last, each
// channel's keys in order and the last at rest; a channel with none stays
// at rest.
void test_the_scenes_formulas() {
  struct Run {
    int mood;
    Facts facts;
    SceneState anim;
    Outcome outcome;
    uint32_t ms;
  } runs[] = {
      {slime::kHappy, facts(SceneState::kWorking, SceneState::kWaiting), SceneState::kNone, Outcome::kNone, 20000},
      {slime::kHappy, facts(SceneState::kIdle), SceneState::kListening, Outcome::kNone, 10000},
      {slime::kCalm, facts(SceneState::kWorking), SceneState::kNone, Outcome::kNone, 40000},
      {slime::kCurious, facts(SceneState::kWorking, SceneState::kTerminal), SceneState::kNone, Outcome::kNone, 30000},
      {slime::kHappy, facts(SceneState::kWorking), SceneState::kReplyReady, Outcome::kNone, 6000},
      {slime::kCalm, facts(SceneState::kWorking), SceneState::kError, Outcome::kNone, 6000},
      {slime::kHappy, facts(SceneState::kWorking), SceneState::kTaskComplete, Outcome::kSuccess, 6000},
      {slime::kCalm, facts(SceneState::kWorking), SceneState::kTaskComplete, Outcome::kFailure, 6000},
      {slime::kCalm, facts(SceneState::kWorking, SceneState::kDelegating), SceneState::kNone, Outcome::kNone, 20000},
      {slime::kCalm, facts(SceneState::kWorking), SceneState::kStarting, Outcome::kNone, 6000},
      {slime::kCalm, facts(SceneState::kAsleep), SceneState::kNone, Outcome::kNone, 90000},
  };
  const double limit[] = {.08, .06, .05};
  int checked = 0, jittered = 0, picks = 0;
  for (const auto& run : runs) {
    auto e = std::make_unique<Engine>();
    e->step(0);
    e->setMood(run.mood);
    e->setFacts(run.facts);
    if (run.anim != SceneState::kNone) {
      Request r = request(run.anim, "r");
      r.outcome = run.outcome;
      r.hold = true;
      TEST_ASSERT_TRUE(e->oneShot(r));
    }
    int generation = -1, iteration = -1;
    for (uint32_t t = 16; t <= run.ms; t += 16) {
      Ref want[3];
      for (int i = 0; i < 3; ++i) want[i] = ref(e->scenes.activity[i]);
      const int was = e->scenes.generation;
      e->step(t);
      const Scenes& s = e->scenes;
      if (s.generation == was) {
        const auto target = aim(*e);
        for (int i = 0; i < 3; ++i) {
          spring(want[i], .016, target[i], 144, 10, limit[i], 1.2);
          TEST_ASSERT_TRUE(near(s.activity[i], want[i], 2e-6, 2e-5));
        }
        ++checked;
      }
      // Each pick of a recipe: as written, or a desk's jittered within its
      // bounds.
      if (s.generation != generation || s.iteration != iteration) {
        generation = s.generation, iteration = s.iteration;
        const int row = recipeState(s.route.state, s.route.outcome, s.route.ctx);
        if (s.variant >= takes(row) && s.route.state != SceneState::kGesture) continue;  // an occasion's
        const auto& base = take(s.profileExpression, row, s.variant);
        TEST_ASSERT_EQUAL_INT(base.count, s.recipe.count);
        for (int i = 0; i < base.count; ++i) {
          const auto &was = base.contacts[i], &is = s.recipe.contacts[i];
          TEST_ASSERT_TRUE(was.kind == is.kind && was.side == is.side);
          if (!base.jitter) {
            TEST_ASSERT_TRUE(was.at == is.at && was.strength == is.strength);
            continue;
          }
          const double shift = num(is.at) - num(was.at), scale = num(is.strength) / num(was.strength);
          TEST_ASSERT_TRUE(std::abs(shift) <= 40 + 1e-6 && scale >= .9 - 1e-6 && scale <= 1.1 + 1e-6);
          jittered += shift != 0;
        }
        ++picks;
      }
    }
  }
  TEST_ASSERT_TRUE(checked > 10000 && jittered > 0 && picks > 20);
  // Every gag keys its channels inside their bounds (the gestures' lean,
  // squash and ripple .42, lift .24, roll .12, forward .18, the slide .7 and
  // the lids 1), which the springs would otherwise clamp, and times its
  // impulses in order within its length.
  const F caps[] = {q(.42), q(.42), q(.42), q(.24), q(.12), q(.18), q(.7), F(1)};
  for (const auto& gag : slime::kGags) {
    for (int i = 0; i < gag.gesture.count; ++i) {
      const auto& cue = gag.gesture.cues[i];
      TEST_ASSERT_TRUE(cue.at <= gag.gesture.duration && (!i || cue.at >= gag.gesture.cues[i - 1].at));
    }
    for (int c = 0; c < 8; ++c) {
      double value = 0, from = 0;
      int keys = 0;
      for (int i = 0; i < gag.keyCount; ++i) {
        const auto& key = gag.keys[i];
        if (key.channel != c) continue;
        TEST_ASSERT_TRUE(abs(key.value) <= caps[c]);
        const double at = num(key.at), to = num(key.value);
        TEST_ASSERT_TRUE(at > from || !keys);
        TEST_ASSERT_TRUE(near(keyed(gag, c, T::literal((from + at) / 2)), (value + to) / 2, 1e-5));
        TEST_ASSERT_TRUE(near(keyed(gag, c, T::literal(from + (at - from) / 4)), value + (to - value) * .15625, 1e-5));
        TEST_ASSERT_TRUE(keyed(gag, c, key.at) == key.value);
        value = to, from = at, ++keys;
      }
      TEST_ASSERT_TRUE(value == 0);  // each channel's keys come back to rest
      for (const double at : {0.0, .5, 1.5, 4.0, 9.0})
        if (!keys || at > from) TEST_ASSERT_TRUE(keyed(gag, c, T::literal(at)) == q(value));
    }
  }
}
