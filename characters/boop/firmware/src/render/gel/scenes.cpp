#include "render/gel/scenes.h"
namespace render::gel {
namespace {
int recipeState(const Route& r) { return gel::recipeState(r.state, r.outcome, r.ctx); }
Scenes::Saved* find(History<Scenes::Saved, 64>& cache, const std::string& id) {
  const uint64_t key = identityKey(id);
  return cache.find([&](const Scenes::Saved& s) { return s.id == key; });
}
void save(History<Scenes::Saved, 64>& cache, const Scenes::Saved& s) { cache.add(s); }
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
  return realize(*saved.recipe, random);
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
    case kResultProp:
      // A successful finish shows its trophy instead of a card, and one
      // that names whose turn it was its ticket.
      return route.group == Family::kResult && !cardless &&
             !(route.state == SceneState::kTaskComplete && route.outcome == Outcome::kSuccess);
    case kStartProp:
      return route.state == SceneState::kStarting;
    case kListeningProp:
      return route.state == SceneState::kListening;
    default:
      return route.group == Family::kTouch;
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
      copy(alertProp.requestId, requestId);
      copy(alertProp.agent, a ? a->agent : none);
      copy(alertProp.project, a ? a->project : none);
      copy(alertProp.name, a ? a->name : none);
      alertProp.more = a ? a->more : 0;
      alertProp.known = true;
      break;
    }
    case kResultProp:
      resultProp.state = route.state;
      resultProp.known = true;
      resultProp.gift = recipe.gift;
      resultProp.outcome = route.outcome;
      resultProp.label = recipe.label                         ? recipe.label
                         : route.outcome == Outcome::kSuccess ? "COMPLETE"
                         : route.outcome == Outcome::kFailure ? "FAILED"
                                                              : "FINISHED";
      break;
    case kStartProp:
      startProp.label = recipe.label;
      break;
    case kListeningProp:
      listeningPulse = focus();
      break;
    default:
      touchKind = route.state;
  }
}
// A card's reveal is its slot's own ramp: up over kCardRevealMs from its
// reveal contact, down over the recovery, each from its time on the route's
// clock, but not down before it's up: revealed late in the recipe, it rises
// whole, then falls. Once the route ends, nothing retargets it, so it
// carries on as it was going while the slot's ramp fades the card out.
void Scenes::cardReveal(Ramp& reveal) const {
  if (!resultRevealed) {
    reveal.reset();
    return;
  }
  const T down = max(recipe.duration - T(480), revealAt + T(kCardRevealMs));
  if (ageMs >= down)
    reveal.retarget(0, started + down, 480);
  else
    reveal.retarget(1, started + revealAt, kCardRevealMs);
}
// A prop whose route ends fades out with its last content (a card's reveal
// going on as it was), so it never stops dead. New content (a new
// request) waits until nothing of the old is drawn, then fades in from
// zero.
void Scenes::updateProps(T time) {
  for (int p = 0; p < kProps; ++p) {
    const Prop prop = Prop(p);
    auto& slot = slots[p];
    const bool want = wants(prop);
    bool same = slot.on == want && (!want || prop == kAlertProp || slot.id == requestId);
    if (!same && visible(prop, time).raw == 0) {
      slot.on = want;
      if (want && slot.id != requestId) slot.id = requestId;
      slot.ramp.reset();
      slot.reveal.reset();
      same = true;
    }
    if (want && same) {
      refresh(prop);
      slot.ramp.retarget(1, time);
      if (card(prop)) cardReveal(slot.reveal);
    } else {
      slot.ramp.retarget(0, time);
    }
  }
}
void Scenes::pickRecipe(T time, Random& random) {
  started = time;
  ageMs = 0;
  cursor = 0;
  completed = false;
  hasLast = false;
  resultRevealed = false;
  if (route.moment)
    if (const auto* old = find(moments, requestId)) {
      variant = old->variant;
      recipe = restore(*old);
      profileExpression = old->profile;
      phase = "enter";
      return;
    }
  // The host's take if its state has it; the first rest is always the still
  // one, and asleep deals from its bag after that. A look deals an
  // occasion's take instead, while one fits, kOccasionShare of the time
  // (numbered after the row's own); a gesture's take is the board's, or
  // the first.
  const int row = recipeState(route), count = takes(row), asked = route.moment ? route.moment->value.variant : -1;
  const bool ask = asked >= 0 && (asked < count || (row == kSuccessRow && isFinishVariant(asked)));
  const bool deal =
      !ask && route.state != SceneState::kGesture &&
      ((!route.quiet && route.state != SceneState::kIdle) || (route.state == SceneState::kAsleep && iteration));
  int look = -1;
  if (deal && !route.moment) {
    int fit[slime::kLookOccasionCount], k = 0;
    for (int i = 0; i < slime::kLookOccasionCount; ++i) {
      const auto& o = slime::kLookOccasions[i];
      if (o.row == row && fits(o.when, o.after, when, lookMs)) fit[k++] = i;
    }
    if (k && random.unit() < slime::kOccasionShare) look = fit[random.index(k)];
  }
  variant = ask ? asked : look >= 0 ? count + look : deal ? bags[mood][row].next(random, count) : 0;
  profileExpression = expression;
  const auto* base = look >= 0 ? &slime::kLookOccasions[look].recipe : &take(expression, row, variant);
  uint32_t seed = random.state;
  recipe = realize(*base, random);
  Saved saved{identityKey(requestId), variant, profileExpression, base, seed};
  if (route.state == SceneState::kNeedsYou) save(alerts, saved);
  if (route.moment) save(moments, saved);
  phase = "enter";
}
void Scenes::setRoute(const Route& next, T time, int nextExpression, Random& random) {
  expression = nextExpression;
  mood = slime::kProfile[expression].canonical;
  bool same = generation && route.state == next.state && requestId == *next.requestId;
  // An alert left before its knocks and ding finished keeps its place, so
  // each request signals exactly once however it is interrupted.
  if (!same && generation && route.state == SceneState::kNeedsYou)
    if (auto* left = find(alerts, requestId)) {
      left->ageMs = ageMs;
      left->cursor = cursor;
    }
  route = next;
  if (same) return;
  requestId = *next.requestId;
  ++generation;
  iteration = 0;
  contacts.clear();
  resultRevealed = false;
  const Saved* old = route.state == SceneState::kNeedsYou ? find(alerts, requestId) : nullptr;
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
    bool returning = route.moment && find(moments, requestId);
    pickRecipe(time, random);
    if (returning) {
      iteration = ((time - route.moment->startedAt) / recipe.duration).floor();
      started = route.moment->startedAt + recipe.duration * iteration;
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
std::string Scenes::advance(T dt, T time, bool grab, Random& random) {
  contacts.clear();
  if (!generation) return {};
  if (completed) {
    if (route.moment) {
      if (iteration + 1 >= route.loops) {
        if (!route.moment->value.hold) return requestId;
      } else {
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
    if ((route.moment || route.state == SceneState::kAsleep) && ageMs >= recipe.duration) completed = true;
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
    last = {
        requestId,
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
  F strength = hasLast ? last.strength : F(1),
    contact = active ? max(max(envelope(time, kKey), envelope(time, kKnock)), envelope(time, kBody)) * strength : F(0);
  F reveal = active ? max(envelope(time, kSuccess), envelope(time, kFailure)) * strength : F(0), present = 0;
  if (active)
    for (int kind : {kStart, kHelper, kReply, kError, kStopped}) present = max(present, envelope(time, kind));
  present *= strength;
  bool success = route.state == SceneState::kTaskComplete && route.outcome == Outcome::kSuccess,
       failure = route.state == SceneState::kTaskComplete && route.outcome == Outcome::kFailure;
  F recoveryPose[3]{};
  const auto& profile = slime::kProfile[profileExpression];
  // A fourth take (the hiccups) has no gesture of its own to recover with,
  // and a recipe with a gag of its own recovers with that.
  if (active && !std::strcmp(phase, "recover") && !profile.representative && variant < kGestures && recipe.gag < 0) {
    const auto& perf = profile.performances[variant];
    T pt = F(1 - (recipe.duration - ageMs) / 480) * F(perf.duration);
    for (int i = 0; i < perf.count; ++i) {
      const auto& c = perf.cues[i];
      int channel = c.channel == 4 ? 0 : c.channel == 3 ? 1 : c.channel == 2 ? 2 : c.channel == 5 ? 2 : c.channel;
      T age = pt - c.at;
      if (channel > 2 || age < 0 || age > q(.48)) continue;
      const F gain[] = {q(.025), q(.018), q(.015)};
      recoveryPose[channel] += c.velocity * gain[channel] * square(sin(pi * age / q(.48)));
    }
  }
  F wave = (route.state == SceneState::kWaiting || route.state == SceneState::kListening)
               ? q(.65) + q(.35) * sin(ageMs / recipe.duration * pi * 2 * recipe.focus)
               : F(1);
  F target[] = {
      recipe.lean * entry() * recovery() * wave + (hasLast ? last.side : 0) * contact * q(.024) + recoveryPose[0],
      -contact * q(.052) +
          (success   ? q(.036)
           : failure ? q(-.048)
                     : F(0)) *
              reveal +
          present * q(.018) + recoveryPose[1],
      contact * q(.045) +
          (success   ? q(.025)
           : failure ? q(-.035)
                     : F(0)) *
              reveal +
          present * (route.state == SceneState::kError ? q(-.025) : q(.018)) + recoveryPose[2]};
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
  updateProps(time);
  return {};
}
}  // namespace render::gel
