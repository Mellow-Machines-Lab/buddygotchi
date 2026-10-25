#include "render/gel/motion.h"
namespace render::gel {
void Motion::advance(T dt, T now, Random& random) {
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
}
void Motion::impulse(bool shake, F x) {
  modes[0].v = clamp(modes[0].v + (shake ? q(4.5) : x >= F(0) ? q(-2.6) : q(2.6)), -8, 8);
  modes[1].v = clamp(modes[1].v - (shake ? q(2.6) : q(3.5)), -8, 8);
  modes[2].v = clamp(modes[2].v + (shake ? F(5) : q(3.5)), -8, 8);
  modes[3].v = clamp(modes[3].v + (shake ? F(0) : q(4.8)), -8, 8);
}
F Motion::blink() const {
  T age = time - blinkAt;
  return age >= F(0) && age < T::literal(.24) ? square(sin(pi * age / T::literal(.24))) : F(0);
}
std::array<F, 4> Motion::pose() const {
  return {modes[0].x, modes[1].x + sin(time * q(1.65)) * q(.011), modes[2].x, modes[3].x};
}
namespace {
// The controls a layer's ratios follow (the eye's openness, the mouth's
// width and its curve), and the shared sleeping face's sizes of them.
constexpr int kSized[3] = {2, 4, 5};
constexpr F kSleep[3] = {q(.004), q(.018), q(.008)};
// a / b as `/` gives it, for positive a and b, at compile time.
constexpr F quotient(F a, F b) { return F::fromRaw(a.raw * F::scale / b.raw); }
// The sleeping face's size over the tired art's, which it is drawn from.
constexpr F kSleepScale[3] = {quotient(kSleep[0], slime::kProfile[slime::kTired].face[2]),
                              quotient(kSleep[1], slime::kProfile[slime::kTired].face[4]),
                              quotient(kSleep[2], slime::kProfile[slime::kTired].face[5])};
// A Divisor is exact for divisors from 1/2 and dividends under 128: every
// size a ratio is over is at least 1/2 at kScale, and the controls there,
// under 35, are far inside.
constexpr bool sizesDivide() {
  for (const F size : kSleep)
    if (size * SemanticFace::kScale < q(.5)) return false;
  for (const auto& profile : slime::kProfile)
    for (const int c : kSized)
      if (profile.face[c] * SemanticFace::kScale < q(.5)) return false;
  return true;
}
static_assert(sizesDivide(), "every art's size is at least 1/2 at kScale");
// A layer of an art, sized: its weight's Hermite is the caller's.
SemanticFace::Layer layer(int art, bool sleeping) {
  SemanticFace::Layer l;
  l.art = art;
  l.sleeping = sleeping;
  for (int k = 0; k < 3; ++k)
    l.size[k] = Divisor((sleeping ? kSleep[k] : slime::kProfile[art].face[kSized[k]]) * SemanticFace::kScale);
  return l;
}
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
  layers[0] = layer(targetId, false);
}
void SemanticFace::drop(int i) {
  std::copy(layers.begin() + i + 1, layers.begin() + count, layers.begin() + i);
  --count;
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
void SemanticFace::aim() {
  const int art = targetSleeping ? slime::kTired : targetId;
  for (int i = 0; i < 8; ++i) target[i] = slime::kProfile[art].face[i];
  if (targetSleeping) {
    target[2] = kSleep[0];
    target[4] = kSleep[1];
    target[5] = kSleep[2];
    target[6] = target[7] = 0;
  }
  from = controls;
  to = target;
}
void SemanticFace::retarget(T ms) {
  aim();
  const int art = targetSleeping ? slime::kTired : targetId;
  // Every layer starts again from its value and slope now, toward zero; the
  // new art, last, toward one (one still fading comes back from its value).
  const F s = elapsedMs / durationMs;
  int found = -1;
  for (int i = 0; i < count; ++i) {
    auto& l = layers[i];
    F slope;
    hermite(l.from, l.tangent, l.to, s, l.from, slope);
    l.tangent = slope * F(ms) / F(durationMs);
    l.to = 0;
    if (l.art == art && l.sleeping == targetSleeping) found = i;
  }
  Layer top;
  if (found >= 0) {
    top = layers[found];
    drop(found);
  } else {
    top = layer(art, targetSleeping);
    top.from = 0;
  }
  top.to = 1;
  // One at zero that can only stay there is gone; past kMaxLayers, so is
  // the faintest, the others' shares growing to fill what it leaves.
  const auto end = std::remove_if(layers.begin(), layers.begin() + count,
                                  [](const Layer& l) { return l.from <= F(0) && l.tangent <= F(0); });
  count = int(end - layers.begin());
  if (count == kMaxLayers)
    drop(int(std::min_element(layers.begin(), end, [](const Layer& a, const Layer& b) { return a.from < b.from; }) -
             layers.begin()));
  layers[count++] = top;
  weigh(0);
  elapsedMs = 0;
  durationMs = ms;
}
void SemanticFace::setMood(int id, T ms) {
  if (id == targetId) return;
  targetId = id;
  if (!targetSleeping) retarget(ms);
}
// Falling asleep squashes the awake face shut first (advance swaps in the
// sleeping face once it's a line); waking crosses to the mood's art, unless
// the awake one is still drawn, which then opens again.
void SemanticFace::setSleeping(bool value) {
  if (value == targetSleeping) return;
  targetSleeping = value;
  if (!value && (current().sleeping || current().art != targetId))
    retarget(kFaceMs);
  else
    aim();
}
void SemanticFace::advance(T dt) {
  // The controls' spring: the face's, or sleep's while it sleeps.
  const F w = targetSleeping ? F(kSleepFrequency) : F(kFaceFrequency);
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
  integrate(shut, dt, targetSleeping ? 1 : 0, w, 2 * w, 1, 100);
  shut.x = max(shut.x, 0);
  if (count > 1) {
    elapsedMs = min(durationMs, elapsedMs + dt * 1000);
    if (elapsedMs >= durationMs) {
      layers[0] = layers[count - 1];
      count = 1;
    }
    weigh(elapsedMs / durationMs);
  }
  if (targetSleeping && !current().sleeping && shut.x >= kShutLine) retarget(kSwapMs);
}
// Each layer at the live control over its own size: the arts crossing over
// are drawn near one size while the controls move. An awake art smaller
// than its own is drawn as far toward the control itself as the face is
// shut, its eyes no thinner than a line as thick as the sleeping face's
// lids (kLineHalf, half their pen, over the eye's own half height).
std::array<F, 3> SemanticFace::ratios(const Layer& l) const {
  std::array<F, 3> out;
  for (int k = 0; k < 3; ++k) {
    const F r = l.size[k].divide(scaled[kSized[k]]), soft = softRatio(r);
    if (l.sleeping || r >= F(1)) {
      out[k] = soft;
      continue;
    }
    const F shut_to = k ? r : max(r, min(1, kLineHalf / slime::kProfile[l.art].face[2]));
    out[k] = soft - (soft - shut_to) * shut.x;
  }
  return out;
}
std::array<F, 3> drawnScale(const SemanticFace& face, const SemanticFace::Layer& l) {
  auto out = face.ratios(l);
  if (l.sleeping)
    for (int k = 0; k < 3; ++k) out[k] = out[k] * kSleepScale[k];
  return out;
}
}  // namespace render::gel
