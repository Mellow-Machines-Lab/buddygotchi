#include "render/gel/acting.h"
namespace render::gel {
namespace {
// The channels a cue or a key names (slimegen's): the six gestures', then a
// gag's slide and lids.
constexpr int kSlide = 6, kLids = 7, kChannels = 8;
}  // namespace
F keyed(const slime::Gag& gag, int channel, T age) {
  T from = 0;
  F value = 0;
  for (int i = 0; i < gag.keyCount; ++i) {
    const auto& key = gag.keys[i];
    if (key.channel != channel) continue;
    if (age < key.at) return value + (key.value - value) * smooth((age - from) / (key.at - from));
    from = key.at;
    value = key.value;
  }
  return value;
}
bool Acting::perform(T time, Random& random, int index) {
  if (suppressed) return false;
  const int n = takes(emotion);
  int selected;
  if (index < 0 && chosen < 0) {
    // While an idle occasion fits, its gag kOccasionShare of the time.
    int fit[slime::kIdleOccasionCount], k = 0;
    for (int i = 0; i < slime::kIdleOccasionCount; ++i)
      if (fits(slime::kIdleOccasions[i].when, slime::kIdleOccasions[i].after, when, lookMs)) fit[k++] = i;
    if (k && random.unit() < slime::kOccasionShare)
      selected = n + fit[random.index(k)];
    else
      selected = bags[emotion].next(random, n);
  } else
    selected = std::max(0, std::min(n - 1, index < 0 ? chosen : index));
  performance = selected;
  playing = -1;
  expression = emotion;
  start = time;
  cursor = contactCursor = 0;
  ++count;
  nextPerformance = time + gesture(emotion, selected).duration + 7 + random.unit() * 8;
  return true;
}
void Acting::hold(int g, int generation, int iteration, T time) {
  if (g < 0) {
    holding = false;
    return;
  }
  if (holding && heldGeneration == generation && heldIteration == iteration) return;
  holding = true;
  heldGeneration = generation;
  heldIteration = iteration;
  performance = -1;
  playing = g;
  expression = emotion;
  start = time;
  cursor = contactCursor = 0;
  ++count;
  nextPerformance = max(nextPerformance, time + slime::kGags[g].gesture.duration + 3);
}
void Acting::advance(T dt, T time, bool grab, Random& random) {
  contacts.clear();
  if (!suppressed && !grab && !holding && time >= nextPerformance) perform(time, random);
  F target[kChannels]{};
  if (!suppressed && (performance >= 0 || playing >= 0) && expression == emotion) {
    const auto* g = current();
    const auto& p = g ? g->gesture : slime::kProfile[emotion].performances[performance];
    T age = time - start;
    while (cursor < p.count && age >= p.cues[cursor].at) {
      const auto& cue = p.cues[cursor++];
      (cue.channel == kSlide ? slide : channels[cue.channel]).v += cue.velocity;
    }
    if (g) {
      // A gag's keys set its channels' targets.
      for (int c = 0; c < kChannels; ++c) target[c] = keyed(*g, c, age);
      // Its contacts are its sounds; they move nothing themselves.
      while (contactCursor < g->contactCount && age >= g->contacts[contactCursor].at) {
        const int index = contactCursor++;
        const auto& c = g->contacts[index];
        contacts.push_back({"gag", count, 0, index, c.kind, 0, time * 1000, c.strength});
      }
    }
  }
  for (int i = 0; i < 6; ++i) {
    F limit = i == 3 ? q(.24) : i == 4 ? q(.12) : i == 5 ? q(.18) : q(.42);
    integrate(channels[i], dt, target[i], i == 3 ? 11 : i == 4 ? 10 : 9, q(6.4), limit, 5);
  }
  integrate(slide, dt, target[kSlide], 10, 9, q(.7), 5);
  integrate(lids, dt, target[kLids], 24, 48, 1, 20);
}
T Bridge::retarget(int source, int target, T time, Random& random, int forced) {
  from = source;
  to = target;
  edge = -1;
  const auto& a = slime::kProfile[source];
  const auto& b = slime::kProfile[target];
  for (int i = 0; i < slime::kEdgeCount; ++i)
    if (slime::kEdges[i].from == a.canonical && slime::kEdges[i].to == b.canonical) {
      edge = i;
      break;
    }
  category = edge < 0 ? 2 : slime::kEdges[edge].dramatic ? 1 : 0;
  variant = edge < 0 ? 0 : forced >= 0 ? forced : bags[edge].next(random);
  primitive = variant == 2    ? Primitive::kBlink
              : category == 1 ? Primitive::kRecoil
              : variant == 1  ? Primitive::kGather
                              : Primitive::kSoft;
  F score = (b.traits[3] - a.traits[3]) + (b.traits[2] - a.traits[2]) * q(.025) + (a.traits[0] - b.traits[0]) / 10000 +
            (b.face[2] - a.face[2]) * q(.01) + (b.face[4] - a.face[4]) * q(.005);
  direction = score > F(0) ? 1 : score < F(0) ? -1 : 0;
  amplitude = clamp(q(.8) + abs(score) * 4, q(.8), q(1.2));
  // Each channel's bound over the primitive's
  // largest coefficient on it, so no target leaves its bound.
  constexpr F limits[] = {
      q(std::min({.06 / .009, .05 / .004, .04 / .003})),  // soft retarget
      q(std::min({.06 / .026, .05 / .032, .04 / .012})),  // gather/settle
      q(std::min({.06 / .006, .05 / .014, .04 / .004})),  // ordinary blink retarget
      q(std::min({.06 / .026, .05 / .035, .04 / .014})),  // dramatic blink retarget
      q(std::min({.06 / .045, .05 / .038, .04 / .032})),  // dramatic recoil
      q(std::min({.06 / .022, .05 / .048, .04 / .026}))   // dramatic compression
  };
  const int shape = primitive == Primitive::kSoft     ? 0
                    : primitive == Primitive::kGather ? 1
                    : primitive == Primitive::kBlink  ? (category == 1 ? 3 : 2)
                                                      : (variant == 0 ? 4 : 5);
  amplitude = min(amplitude, limits[shape]);
  constexpr int durations[2][3] = {{420, 680, 360}, {760, 920, 560}}, faces[2][3] = {{320, 360, 460}, {240, 280, 340}};
  active = true;
  elapsedMs = 0;
  durationMs = durations[category == 1 ? 1 : 0][variant];
  deferredMs = 0;
  expired = false;
  suppressed = quiet || attention;
  return faces[category == 1 ? 1 : 0][variant];
}
void Bridge::advance(T dt) {
  F target[3]{};
  if (active) {
    if (grab && elapsedMs < durationMs && !suppressed && !expired) {
      deferredMs += dt * 1000;
      if (deferredMs >= F(320)) expired = suppressed = true;
    } else
      elapsedMs = min(durationMs, elapsedMs + dt * 1000);
    if (!grab && !suppressed && !expired && elapsedMs < durationMs) {
      F p = clamp(elapsedMs / durationMs, 0, 1), pulse = square(sin(pi * p));
      if (primitive == Primitive::kSoft) {
        target[0] = q(.009) * direction * pulse;
        target[1] = q(.004) * pulse;
        target[2] = q(.003) * pulse;
      } else if (primitive == Primitive::kGather) {
        target[0] = q(.026) * direction * pulse;
        target[1] = q(-.032) * pulse;
        target[2] = q(.012) * sin(pi * 2 * p) * pulse;
      } else if (primitive == Primitive::kBlink) {
        F held = p < q(.25) ? F(0) : square(sin(pi * (p - q(.25)) / q(.75)));
        bool dramatic = category == 1;
        target[0] = (dramatic ? q(.026) : q(.006)) * direction * held;
        target[1] = (dramatic ? q(-.035) : q(-.014)) * held;
        target[2] = (dramatic ? q(-.014) : q(-.004)) * held;
      } else if (variant == 0) {
        target[0] = q(-.045) * direction * sin(pi * 2 * p) * pulse;
        target[1] = q(-.038) * pulse;
        target[2] = q(-.032) * pulse;
      } else {
        target[0] = q(.022) * direction * pulse;
        target[1] = q(-.048) * pulse;
        target[2] = q(.026) * sin(pi * 2 * p) * pulse;
      }
      for (auto& v : target) v *= amplitude;
    }
  }
  constexpr F bounds[] = {q(.06), q(.05), q(.04)};
  for (int i = 0; i < 3; ++i) integrate(channels[i], dt, target[i], 14, 12, bounds[i], 1);
}
}  // namespace render::gel
