#include "render/gel/scenes.h"
namespace render::gel {
namespace {
int recipeState(const Route& r) { return gel::recipeState(r.state, r.outcome); }
Scenes::Saved* find(Scenes::Saved& saved, uint64_t key) { return saved.key == key ? &saved : nullptr; }
slime::Recipe realize(const slime::Recipe& source, Random& random) {
  auto recipe = source;
  if (recipe.jitter)
    for (int i = 0; i < recipe.count; ++i) {
      recipe.contacts[i].at += (random.unit() * 2 - 1) * 40;
      recipe.contacts[i].strength *= 1 + (random.unit() * 2 - 1) * q(.1);
    }
  return recipe;
}
slime::Recipe restore(const Scenes::Saved& saved) {
  Random random(saved.seed);
  return realize(take(saved.profile, saved.row, saved.variant), random);
}
void prop(Spring& s, F dt, F target, int frequency, int damping) {
  while (dt > 0) {
    F h = min(dt, F::ratio(1, 240));
    s.v += (frequency * frequency * (target - s.x) - damping * s.v) * h;
    s.x += s.v * h;
    dt -= h;
  }
  s.x = clamp(s.x, 0, 1);
}
}  // namespace
void Ramp::at(T time, F& value, F& slope) const {
  T elapsed = time - start;
  if (!active || elapsed >= T(windowMs)) {
    value = to;
    slope = 0;
    return;
  }
  hermite(from, tangent, to, elapsed / windowMs, value, slope);
}
F Ramp::value(T time) const {
  F v, slope;
  at(time, v, slope);
  return v;
}
void Ramp::retarget(F next, T time, int overMs) {
  if (next == to) return;
  F value, slope;
  at(time, value, slope);
  from = value;
  tangent = slope * (F(overMs) / F(windowMs));
  to = next;
  start = time;
  windowMs = overMs;
  active = true;
}
const char* Scenes::phaseAt(T age) const {
  return age < T(240)                     ? "enter"
         : age < recipe.duration - T(480) ? "act"
         : age < recipe.duration          ? "recover"
                                          : "sustain";
}
bool Scenes::wants(Prop prop) const {
  switch (prop) {
    case kAlertProp:
      return route.state == SceneState::kNeedsYou;
    default:
      return route.state == SceneState::kListening;
  }
}
void Scenes::refresh(Prop prop) {
  auto copy = [](std::string& to, const std::string& from) {
    if (to != from) to = from;
  };
  switch (prop) {
    case kAlertProp: {
      static const std::string none;
      const Attention* a = route.attention;
      copy(alertProp.agent, a ? a->agent : none);
      copy(alertProp.project, a ? a->project : none);
      copy(alertProp.name, a ? a->name : none);
      alertProp.more = a ? a->more : 0;
      alertProp.known = true;
      break;
    }
    default:
      listeningPulse = focus();
  }
}
// A prop whose route ends fades out with its last content, so it never
// stops dead. New content (a new
// request) waits until nothing of the old is drawn, then fades in from
// zero.
void Scenes::updateProps(T time) {
  for (int p = 0; p < kProps; ++p) {
    const Prop prop = Prop(p);
    auto& slot = slots[p];
    const bool want = wants(prop);
    bool same = slot.on == want && (!want || prop == kAlertProp || slot.key == key);
    if (!same && visible(prop, time).raw == 0) {
      slot.on = want;
      if (want) slot.key = key;
      slot.ramp.reset();
      same = true;
    }
    if (want && same) {
      refresh(prop);
      slot.ramp.retarget(1, time);
    } else {
      slot.ramp.retarget(0, time);
    }
  }
}
void Scenes::restartTake(T time) {
  started = time;
  ageMs = 0;
  cursor = 0;
  completed = false;
  hasLast = false;
  resultRevealed = false;
}
void Scenes::pickRecipe(T time, Random& random) {
  restartTake(time);
  if (route.reaction)
    if (const auto* old = find(held, key)) {
      variant = old->variant;
      recipe = restore(*old);
      profileExpression = old->profile;
      phase = "enter";
      return;
    }
  // The host's take if its state has it; the first rest is always the still
  // one, and asleep deals from its bag after that; a gesture's take is the
  // board's, or the first.
  const int row = recipeState(route), count = takes(row), asked = route.reaction ? route.reaction->variant : -1;
  const bool ask = asked >= 0 && (asked < count || (row == kSuccessRow && isFinishVariant(asked)));
  const bool deal =
      !ask && route.state != SceneState::kGesture &&
      ((!route.quiet && route.state != SceneState::kIdle) || (route.state == SceneState::kAsleep && iteration));
  variant = ask ? asked : deal ? bags[mood][row].next(random, count) : 0;
  profileExpression = expression;
  const slime::Recipe base = take(expression, row, variant);
  uint32_t seed = random.state;
  recipe = realize(base, random);
  Saved saved{key, variant, profileExpression, row, seed};
  if (route.state == SceneState::kNeedsYou) alert = saved;
  if (route.reaction && shows(key) == Shows::kReaction) held = saved;
  phase = "enter";
}
void Scenes::playTake(int index, T time, Random& random) {
  if (index < 0 || index >= slime::kPastimeTakeCount || !generation || route.reaction) return;
  ++iteration;
  restartTake(time);
  variant = takes(recipeState(route)) + index;
  profileExpression = expression;
  recipe = realize(slime::kPastimeTakes[index].recipe, random);
  phase = "enter";
}
void Scenes::setRoute(const Route& next, T time, int nextExpression, Random& random) {
  expression = nextExpression;
  mood = slime::kProfile[expression].canonical;
  bool same = generation && route.state == next.state && key == next.key;
  // An alert left before its knocks and ding finished keeps its place, so
  // each request signals exactly once however it is interrupted.
  if (!same && generation && route.state == SceneState::kNeedsYou)
    if (auto* left = find(alert, key)) {
      left->ageMs = ageMs;
      left->cursor = cursor;
    }
  route = next;
  if (same) return;
  key = next.key;
  ++generation;
  iteration = 0;
  contacts.clear();
  resultRevealed = false;
  const Saved* old = route.state == SceneState::kNeedsYou ? find(alert, key) : nullptr;
  quietRestored = old;
  if (old) {
    variant = old->variant;
    recipe = restore(*old);
    profileExpression = old->profile;
    hasLast = false;
    if (old->cursor >= recipe.count) {
      started = time - recipe.duration;
      ageMs = recipe.duration;
      cursor = recipe.count;
      completed = true;
      phase = "sustain";
    } else {
      started = time - old->ageMs;
      ageMs = old->ageMs;
      cursor = old->cursor;
      completed = false;
      phase = phaseAt(ageMs);
    }
  } else {
    bool returning = route.reaction && find(held, key);
    pickRecipe(time, random);
    if (returning) {
      iteration = ((time - route.reactionAt) / recipe.duration).floor();
      started = route.reactionAt + recipe.duration * iteration;
      ageMs = time - started;
      while (cursor < recipe.count && recipe.contacts[cursor].at <= ageMs) {
        if (reveals(recipe.contacts[cursor].kind)) {
          resultRevealed = true;
          revealAt = recipe.contacts[cursor].at;
        }
        ++cursor;
      }
    }
  }
}
FinishShow Scenes::finishShow() const {
  if (!generation || route.state != SceneState::kTaskComplete || route.outcome != Outcome::kSuccess) return {};
  FinishShow show;
  show.on = true;
  show.finish = finishOf(variant);
  show.ageMs = F(ageMs).integer();
  for (int i = 0; i < recipe.count; ++i)
    if (recipe.contacts[i].kind == kSuccess) {
      show.revealMs = F(recipe.contacts[i].at).integer();
      break;
    }
  show.gift = recipe.gift;
  return show;
}
F Scenes::envelope(T time, int kind) const {
  if (!hasLast || last.kind != kind) return 0;
  T age = time - last.timeMs;
  return age >= 0 && age < 120 ? square(cos(age / 120 * pi / 2)) : F(0);
}
void Scenes::advance(T dt, T time, bool grab, Random& random) {
  contacts.clear();
  if (!generation) return;
  if (completed) {
    // A reaction plays its loops, then holds its last until it's cleared.
    if (route.reaction) {
      if (iteration + 1 < route.loops) {
        ++iteration;
        pickRecipe(time, random);
      }
    } else if (isDesk(route.state) || route.state == SceneState::kListening || route.state == SceneState::kAsleep) {
      // Asleep picks again after each take, as routine work does, so it can snore.
      ++iteration;
      pickRecipe(time, random);
    }
  }
  ageMs = max(0, time - started);
  if (route.quiet || route.state == SceneState::kIdle) {
    phase = ageMs < 240 ? "enter" : "sustain";
    if ((route.reaction || route.state == SceneState::kAsleep) && ageMs >= recipe.duration) completed = true;
  } else if (ageMs < 240)
    phase = "enter";
  else if (ageMs < recipe.duration - 480)
    phase = "act";
  else if (ageMs < recipe.duration)
    phase = "recover";
  else {
    phase = "sustain";
    completed = true;
  }
  // Quiet rest has no contacts but a snore's breaths.
  while (cursor < recipe.count && ageMs >= recipe.contacts[cursor].at) {
    int index = cursor++;
    const auto& c = recipe.contacts[index];
    if ((route.quiet && c.kind != kBreath) || (grab && !reveals(c.kind))) continue;
    // Keys are pressed only while it types.
    if (c.kind == kKey && activityOf(route.state) != Activity::kTyping) continue;
    last = {
        key,
        generation,
        iteration,
        index,
        c.kind,
        c.side,
        time,
        c.strength};
    contacts.push_back(last);
    hasLast = true;
    if (reveals(c.kind) && c.kind != kAlert) {
      resultRevealed = true;
      revealAt = c.at;
    }
  }
  bool active = !grab && !route.quiet;
  // A key's or the body's contact dips the body; a knock's is a hand's on
  // the glass (the knock's rig clip, render/gel/moves.h), so the body stays.
  F strength = hasLast ? last.strength : F(1),
    contact = active ? max(envelope(time, kKey), envelope(time, kBody)) * strength : F(0);
  F reveal = active ? max(envelope(time, kSuccess), envelope(time, kFailure)) * strength : F(0), present = 0;
  if (active)
    for (int kind : {kStart, kReply}) present = max(present, envelope(time, kind));
  present *= strength;
  bool success = route.state == SceneState::kTaskComplete && route.outcome == Outcome::kSuccess,
       failure = route.state == SceneState::kTaskComplete && route.outcome == Outcome::kFailure;
  F wave = route.state == SceneState::kListening
               ? q(.65) + q(.35) * sin(ageMs / recipe.duration * pi * 2 * recipe.focus)
               : F(1);
  F target[] = {
      recipe.lean * entry() * recovery() * wave + (hasLast ? last.side : 0) * contact * q(.024),
      -contact * q(.052) +
          (success   ? q(.036)
           : failure ? q(-.048)
                     : F(0)) *
              reveal +
          present * q(.018),
      contact * q(.045) +
          (success   ? q(.025)
           : failure ? q(-.035)
                     : F(0)) *
              reveal +
          present * q(.018)};
  // A snore's breath swells the sleeping body a little, rising and falling.
  F swell = 0;
  if (route.quiet && hasLast && last.kind == kBreath && time - last.timeMs < T(slime::kSnoreSwellMs))
    swell = square(sin((time - last.timeMs) / slime::kSnoreSwellMs * pi)) * last.strength * slime::kSnoreSwell;
  const F limits[] = {q(.08), q(.06), q(.05)};
  for (int i = 0; i < 3; ++i) integrate(activity[i], dt, active ? target[i] : i == 1 ? swell : F(0), 12, 10, limits[i], q(1.2));
  const FinishShow finish = finishShow();
  const bool party = finish.on && takesOver(finish.finish);
  prop(desk, dt, (isDesk(route.state) || isDesk(route.baseState)) && !party ? 1 : 0, 10, 14);
  prop(quietMix, dt, route.quiet ? 1 : 0, 12, 10);
  const SceneState deskState = isDesk(route.state) ? route.state : route.baseState;
  for (int a = 0; a < kActivities; ++a)
    prop(pose[a], dt, isDesk(deskState) && activityOf(deskState) == Activity(a) ? 1 : 0, 9, 18);
  updateProps(time);
}
}  // namespace render::gel
