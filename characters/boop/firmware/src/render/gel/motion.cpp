#include "render/gel/motion.h"
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
}
void SemanticFace::weigh(F s) {
  F sum = 0, slope;
  for (int i = 0; i < count; ++i) {
    auto& l = layers[i];
    hermite(l.from, l.tangent, l.to, s, l.weight, slope);
    sum += l.weight;
  }
  for (int i = 0; i < count; ++i) layers[i].weight = layers[i].weight / sum;
}
void SemanticFace::retarget(T ms) {
  const int art = targetSleeping ? slime::kTired : targetId;
  for (int i = 0; i < 8; ++i) target[i] = slime::kProfile[art].face[i];
  if (targetSleeping) {
    target[2] = kSleep[0];
    target[4] = kSleep[1];
    target[5] = kSleep[2];
    target[6] = target[7] = 0;
  }
  // Every layer starts again from its value and slope now, toward zero; the
  // new art, last, toward one (one still fading comes back from its value).
  const T next = ms / 1000;
  const F s = age / duration;
  int found = -1;
  for (int i = 0; i < count; ++i) {
    auto& l = layers[i];
    F slope;
    hermite(l.from, l.tangent, l.to, s, l.from, slope);
    l.tangent = slope * F(next) / F(duration);
    l.to = 0;
    if (l.art == art && l.sleeping == targetSleeping) found = i;
  }
  Layer top;
  if (found >= 0) {
    top = layers[found];
    for (int i = found; i + 1 < count; ++i) layers[i] = layers[i + 1];
    --count;
  } else {
    top.art = art, top.sleeping = targetSleeping, top.from = 0;
  }
  top.to = 1;
  // One at zero that can only stay there is gone; past kMaxLayers, the
  // faintest folds into the new art.
  int kept = 0;
  for (int i = 0; i < count; ++i)
    if (layers[i].from > F(0) || layers[i].tangent > F(0)) layers[kept++] = layers[i];
  count = kept;
  if (count == kMaxLayers) {
    int faintest = 0;
    for (int i = 1; i < count; ++i)
      if (layers[i].from < layers[faintest].from) faintest = i;
    top.from += layers[faintest].from;
    top.tangent += layers[faintest].tangent;
    for (int i = faintest; i + 1 < count; ++i) layers[i] = layers[i + 1];
    --count;
  }
  layers[count++] = top;
  age = 0;
  duration = next;
  weigh(0);
  updateRatios();
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
  if (count > 1) {
    age = min(duration, age + dt);
    elapsedMs = min(durationMs, age * 1000);
    if (age >= duration) {
      layers[0] = layers[count - 1];
      count = 1;
    }
    weigh(age / duration);
  }
  updateRatios();
}
// Each layer at the live control over its own size: the arts crossing over
// are drawn near one size while the controls move.
void SemanticFace::updateRatios() {
  for (int i = 0; i < count; ++i) {
    auto& l = layers[i];
    const auto& art = slime::kProfile[l.art].face;
    l.ratio = {softRatio(scaled[2] / ((l.sleeping ? kSleep[0] : art[2]) * kScale)),
               softRatio(scaled[4] / ((l.sleeping ? kSleep[1] : art[4]) * kScale)),
               softRatio(scaled[5] / ((l.sleeping ? kSleep[2] : art[5]) * kScale))};
  }
}
std::array<F, 3> drawnScale(const SemanticFace::Layer& l) {
  if (!l.sleeping) return l.ratio;
  const auto& tired = slime::kProfile[slime::kTired].face;
  return {l.ratio[0] * (kSleep[0] / tired[2]), l.ratio[1] * (kSleep[1] / tired[4]),
          l.ratio[2] * (kSleep[2] / tired[5])};
}
}  // namespace render::gel
