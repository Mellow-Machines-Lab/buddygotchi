#include "render/gel/motion.h"
#include <cstring>
namespace render::gel {
void Motion::advance(T dt, T now, Random& random, bool reduced) {
  time = now;
  constexpr F frequency[] = {q(11), q(13), q(18), q(16)}, damping[] = {q(4.6), q(4.5), q(5.3), q(6)};
  for (int i = 0; i < 4; ++i) integrate(modes[i], dt, 0, frequency[i], damping[i], q(.72), 9);
  if (time > nextBlink) {
    blinkAt = time;
    nextBlink = time + 3 + random.unit() * 4;
  }
  if (time > nextLook) {
    gazeTarget = (random.unit() - q(.5)) * q(.028);
    nextLook = time + q(3.2) + random.unit() * 4;
  }
  gaze += (gazeTarget - gaze) * (F(1) - exp(-dt * 3));
  F smoothing = F(1) - exp(-dt * (reduced ? 35 : 14));
  for (int i = 0; i < slime::kProfiles; ++i) weights[i] += (F(i == emotion ? 1 : 0) - weights[i]) * smoothing;
}
void Motion::impulse(bool shake, bool reduced, F x, F y) {
  contactX = clamp(x, q(-.85), q(.85));
  contactY = clamp(y, q(-.25), q(.65));
  F strength = reduced ? q(.25) : F(1);
  modes[0].v = clamp(modes[0].v + (shake ? q(4.5) : x >= F(0) ? q(-2.6) : q(2.6)) * strength, -8, 8);
  modes[1].v = clamp(modes[1].v - (shake ? q(2.6) : q(3.5)) * strength, -8, 8);
  modes[2].v = clamp(modes[2].v + (shake ? F(5) : q(3.5)) * strength, -8, 8);
  modes[3].v = clamp(modes[3].v + (shake ? F(0) : q(4.8)) * strength, -8, 8);
}
F Motion::blink() const {
  T age = time - blinkAt;
  return age >= F(0) && age < T::literal(.24) ? square(sin(pi * age / T::literal(.24))) : F(0);
}
std::array<F, 4> Motion::pose(bool reduced) const {
  return {modes[0].x, modes[1].x + (reduced ? F(0) : sin(time * q(1.65)) * q(.011)), modes[2].x, modes[3].x};
}
namespace {
// The shared sleeping face's eye openness, mouth width and curve.
constexpr F kSleep[3] = {q(.004), q(.018), q(.008)};
}  // namespace
F softRatio(F value) {
  F x = value - 1, room = x < F(0) ? q(.25) : q(4.0 / 3 - 1);
  return 1 + x * room / (room + abs(x));
}
SemanticFace::SemanticFace() {
  for (int i = 0; i < 8; ++i) {
    controls[i] = target[i] = from[i] = to[i] = slime::kProfile[targetId].face[i];
    scaled[i] = controls[i] * kScale;
  }
  render = {1, 1, 1, 1, controls[6], controls[7]};
}
void SemanticFace::retarget(T ms) {
  const int next = targetSleeping ? slime::kTired : targetId;
  for (int i = 0; i < 8; ++i) target[i] = slime::kProfile[next].face[i];
  if (targetSleeping) {
    target[2] = kSleep[0];
    target[4] = kSleep[1];
    target[5] = kSleep[2];
    target[6] = target[7] = 0;
  }
  // A mid-bridge retarget starts from what is drawn now; a cheek or tear
  // style that changes dips to zero at the swap.
  for (int i = 0; i < 3; ++i) start[i] = render[i];
  start[3] = mix[0];
  start[4] = mix[1];
  const auto &a = slime::kProfile[artId], &b = slime::kProfile[next];
  swap[0] = std::strcmp(a.cheeks, b.cheeks) ? 0 : 1;
  swap[1] = std::strcmp(a.tears, b.tears) ? 0 : 1;
  active = true;
  age = 0;
  duration = ms / 1000;
  startClosure = bridgeBlink;
  switched = false;
  from = controls;
  to = target;
  elapsedMs = 0;
  durationMs = ms;
}
void SemanticFace::setMood(int id, T ms) {
  if (id == targetId) return;
  targetId = id;
  if (!targetSleeping) retarget(ms);
}
void SemanticFace::setSleeping(bool value) {
  if (value == targetSleeping) return;
  targetSleeping = value;
  retarget();
}
void SemanticFace::advance(T dt, bool reduced) {
  const F w = reduced ? 30 : 20;
  for (int i = 0; i < 8; ++i) {
    F x = scaled[i], v = velocity[i], goal = target[i] * kScale;
    for (F left = dt; left > F(0);) {
      F h = min(left, q(1.0 / 240));
      v += (w * w * (goal - x) - 2 * w * v) * h;
      x += v * h;
      left -= h;
    }
    scaled[i] = i >= 6 ? clamp(x, 0, kScale) : x;
    velocity[i] = v;
    controls[i] = scaled[i] / kScale;
  }
  if (active) bridge(dt);
  updateRender();
}
void SemanticFace::bridge(T dt) {
  age += dt;
  elapsedMs = min(durationMs, age * 1000);
  T half = duration / 2;
  if (age < half)
    bridgeBlink = startClosure + (F(1) - startClosure) * square(sin(age / half * pi / 2));
  else if (!switched) {
    artId = targetSleeping ? slime::kTired : targetId;
    sleeping = targetSleeping;
    switched = true;
    bridgeBlink = 1;
  } else if (age < duration)
    bridgeBlink = square(cos((age - half) / half * pi / 2));
  else {
    active = false;
    bridgeBlink = 0;
    artId = targetSleeping ? slime::kTired : targetId;
    sleeping = targetSleeping;
  }
}
// Before the swap the old art eases from the ratio it was drawn at to its own
// size; after it the new art eases from its own size to the live ratio.
void SemanticFace::updateRender() {
  const auto& art = slime::kProfile[artId].face;
  const F live[3] = {softRatio(scaled[2] / ((sleeping ? kSleep[0] : art[2]) * kScale)),
                     softRatio(scaled[4] / ((sleeping ? kSleep[1] : art[4]) * kScale)),
                     softRatio(scaled[5] / ((sleeping ? kSleep[2] : art[5]) * kScale))};
  if (!active) {
    for (int i = 0; i < 3; ++i) render[i] = live[i];
    mix[0] = mix[1] = 1;
  } else if (!switched) {
    F e = square(sin(age / (duration / 2) * pi / 2));
    for (int i = 0; i < 3; ++i) render[i] = start[i] + (1 - start[i]) * e;
    for (int i = 0; i < 2; ++i) mix[i] = start[3 + i] + (swap[i] - start[3 + i]) * e;
  } else {
    F e = 1 - bridgeBlink;
    for (int i = 0; i < 3; ++i) render[i] = 1 + (live[i] - 1) * e;
    for (int i = 0; i < 2; ++i) mix[i] = swap[i] + (1 - swap[i]) * e;
  }
  render[kMouthDot] = 1 - q(.8) * bridgeBlink;
  render[kCheek] = clamp(controls[6] * mix[0], 0, 1);
  render[kTear] = clamp(controls[7] * mix[1], 0, 1);
}
F SemanticFace::eyeScale() const {
  return sleeping ? render[kEye] * (kSleep[0] / slime::kProfile[slime::kTired].face[2]) : render[kEye];
}
F SemanticFace::mouthScaleX() const {
  F s = render[kMouthWidth] * render[kMouthDot];
  return sleeping ? s * (kSleep[1] / slime::kProfile[slime::kTired].face[4]) : s;
}
F SemanticFace::mouthScaleY() const {
  F s = render[kMouthHeight] * render[kMouthDot];
  return sleeping ? s * (kSleep[2] / slime::kProfile[slime::kTired].face[5]) : s;
}
}  // namespace render::gel
