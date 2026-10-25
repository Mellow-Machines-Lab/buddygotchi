// Every mood in every state, each take, driven as the board drives it, and
// held to what each must show; a long working stretch; contacts a finger or
// an alert interrupts; a card's reveal; and asleep's stillness.
#include <unity.h>

#include <cstring>
#include <memory>
#include <set>
#include <string>
#include <tuple>
#include <vector>

#include "frames.h"

using namespace render;
using namespace render::gel;

namespace {

constexpr int kStates = int(SceneState::kCount);

// The states whose cues may only be comedy's: the engine's quiet ones.
bool quietSounds(SceneState s) {
  return s == SceneState::kIdle || s == SceneState::kAsleep || s == SceneState::kNoApp || s == SceneState::kListening ||
         s == SceneState::kWaiting;
}
// The factual reveals: each activation of these shows exactly one.
bool revealsOnce(SceneState s) {
  switch (s) {
    case SceneState::kNeedsYou:
    case SceneState::kTaskComplete:
    case SceneState::kReplyReady:
    case SceneState::kError:
    case SceneState::kStopped:
    case SceneState::kStarting:
    case SceneState::kHelperReturn: return true;
    default: return false;
  }
}
bool result(SceneState s) { return family(s) == Family::kResult; }

// One engine driven frame by frame, every frame checked (frames.h), with
// what the frames showed: its contacts (each once), its reveals, how far
// its body moved, how much of each prop showed, and what the result card
// said while it showed.
// The jolt rule's statistics over every run of the matrix.
frames::Jolts jolts;
struct Run {
  std::unique_ptr<Engine> e = std::make_unique<Engine>();
  frames::Frame before;
  frames::Track track{&jolts};
  uint32_t t = 0;
  int mood;
  std::set<std::tuple<std::string, int, int, int>> ids;
  int reveals = 0, keys = 0, contacts = 0;
  F moved = 0, props[Scenes::kProps]{}, desk = 0;
  bool success = false, gift = false;
  explicit Run(int m, const Facts& facts = Facts{}) : mood(m) {
    e->setMood(m);
    e->setFacts(facts);
    e->step(0);
    before = frames::capture(*e);
  }
  void clear() {
    reveals = keys = contacts = 0;
    moved = desk = 0;
    for (auto& p : props) p = 0;
    success = gift = false;
  }
  void step() {
    const bool event = track.heard(*e);
    e->step(t += 16);
    frames::check(*e, &before);
    before = frames::capture(*e);
    track.add(*e, event);
    // The mood the host gave is kept whatever plays.
    TEST_ASSERT_EQUAL_INT(mood, e->emotion);
    const SceneState state = e->scenes.route.state;
    for (const auto& c : e->scenes.contacts) {
      TEST_ASSERT_TRUE(ids.insert({c.requestId, c.generation, c.iteration, c.index}).second);
      reveals += gel::reveals(c.kind), keys += c.kind == kKey, ++contacts;
    }
    // A gag's contacts come only while its gag plays.
    if (!e->acting.contacts.empty()) TEST_ASSERT_NOT_NULL(e->acting.current());
    for (const auto& c : e->acting.contacts)
      TEST_ASSERT_TRUE(ids.insert({c.requestId, c.generation, c.iteration, c.index}).second);
    // Quiet states sound only comedy's contacts, and those duck under a line.
    if (quietSounds(state))
      for (const auto& cue : e->cues) TEST_ASSERT_TRUE(comedy(cue.contact.kind) && !cue.protectedCue);
    for (int i = 0; i < 3; ++i) moved = max(moved, abs(e->scenes.activity[i].x));
    for (const auto& c : e->acting.channels) moved = max(moved, abs(c.x));
    moved = max(moved, abs(e->acting.slide.x));
    for (const auto& m : e->motion.modes) moved = max(moved, abs(m.x));
    for (int p = 0; p < Scenes::kProps; ++p) props[p] = max(props[p], e->scenes.visible(Scenes::Prop(p), e->timeMs()));
    desk = max(desk, e->scenes.desk.x);
    if (e->scenes.visible(Scenes::kResultProp, e->timeMs()) > F(0)) {
      success |= e->scenes.resultProp.outcome == Outcome::kSuccess;
      gift |= e->scenes.resultProp.gift;
    }
    // A successful finish shows its trophy, not a card, from its reveal.
    const FinishShow finish = e->scenes.finishShow();
    if (finish.on && finish.ageMs >= finish.revealMs) success = true, gift |= finish.gift;
  }
  void run(int ms) {
    for (int i = 0; i < ms; i += 16) step();
  }
};

// The prop each state must show, peaking above half: the alert, a card
// (but for a successful finish, which shows its trophy instead),
// listening's, a touch's; the desk for desk states, whole.
void showsItsProp(const Run& r, SceneState state, Outcome outcome = Outcome::kNone) {
  if (state == SceneState::kNeedsYou) TEST_ASSERT_TRUE(r.props[Scenes::kAlertProp] > q(.5));
  const bool trophy = state == SceneState::kTaskComplete && outcome == Outcome::kSuccess;
  if (result(state)) TEST_ASSERT_TRUE(trophy ? r.props[Scenes::kResultProp] == F(0) : r.props[Scenes::kResultProp] > q(.5));
  if (state == SceneState::kStarting) TEST_ASSERT_TRUE(r.props[Scenes::kStartProp] > q(.5));
  // Waking and noticing are the start family's body without its card.
  if (state == SceneState::kWakeUp || state == SceneState::kNotice)
    TEST_ASSERT_TRUE(r.props[Scenes::kStartProp] == F(0));
  if (state == SceneState::kListening) TEST_ASSERT_TRUE(r.props[Scenes::kListeningProp] > q(.5));
  if (family(state) == Family::kTouch) TEST_ASSERT_TRUE(r.props[Scenes::kTouchProp] > q(.5));
  if (isDesk(state)) TEST_ASSERT_TRUE(r.desk > q(.9));
}

// A reaction, held as the board holds every one (Behaviour times it), over
// the look the board plays it on: working, or idle for waking and a gesture.
// It plays one pass of its take, then the host clears it. Its signature is
// the body's lean and squash at 24 points through the take.
std::vector<F> play(int mood, int row, SceneState state, Outcome outcome, StartCtx ctx, int take, int id) {
  Facts facts;
  facts.base = state == SceneState::kWakeUp || state == SceneState::kGesture ? SceneState::kIdle : SceneState::kWorking;
  Run r(mood, facts);
  r.run(64);  // a few frames first, so the request's own frame is measured against them
  r.clear();
  Request req;
  req.anim = state;
  req.hasId = true;
  req.id = std::to_string(id);
  req.hold = true;
  req.variant = take;
  req.outcome = outcome;
  req.ctx = ctx;
  // A gesture's and a notice's own faces, which the board borrows for them.
  if (state == SceneState::kGesture) req.expression = slime::kGestureFaces[take];
  if (state == SceneState::kNotice) req.expression = slime::kNoticeFaces[take];
  TEST_ASSERT_TRUE(r.e->oneShot(req));
  TEST_ASSERT_TRUE(r.e->scenes.route.state == state);
  TEST_ASSERT_EQUAL_INT(take, r.e->scenes.variant);
  const slime::Recipe recipe = r.e->scenes.recipe;
  int recipeReveals = 0;
  for (int i = 0; i < recipe.count; ++i) recipeReveals += reveals(recipe.contacts[i].kind);
  const int ms = F(recipe.duration).integer();
  std::vector<F> signature;
  for (int at = 16; at <= ms + 16; at += 16) {
    r.step();
    TEST_ASSERT_TRUE(r.e->scenes.route.state == state);
    if (signature.size() < 48 && at >= int(signature.size() / 2) * ms / 24) {
      const auto pose = r.e->pose();
      signature.push_back(pose[0]), signature.push_back(pose[1] + r.e->life()[2]);
    }
  }
  // Every reveal of the take shows, once; a factual one is exactly one.
  TEST_ASSERT_EQUAL_INT(recipeReveals, r.reveals);
  if (revealsOnce(state)) TEST_ASSERT_EQUAL_INT(1, r.reveals);
  TEST_ASSERT_TRUE(r.moved > q(.0001));
  showsItsProp(r, state, outcome);
  // Only a successful finish shows the trophy, and only proud's lifted one
  // a gift beside it.
  if (result(state)) {
    TEST_ASSERT_EQUAL(state == SceneState::kTaskComplete && outcome == Outcome::kSuccess, r.success);
    TEST_ASSERT_EQUAL(
        mood == slime::kProud && state == SceneState::kTaskComplete && outcome == Outcome::kSuccess && take == 1,
        r.gift);
  }
  // Cleared, it goes back to the latest facts, and what it showed fades out.
  r.e->clearTransient();
  r.run(208);
  TEST_ASSERT_TRUE(r.e->scenes.route.state == facts.look());
  return signature;
}

bool sameRecipe(const slime::Recipe& a, const slime::Recipe& b) {
  if (a.duration != b.duration || a.lean != b.lean || a.count != b.count || a.gag != b.gag || a.gift != b.gift)
    return false;
  for (int i = 0; i < a.count; ++i)
    if (a.contacts[i].at != b.contacts[i].at || a.contacts[i].kind != b.contacts[i].kind ||
        a.contacts[i].strength != b.contacts[i].strength || a.contacts[i].side != b.contacts[i].side)
      return false;
  return true;
}

// A look the board shows by its facts, run until its bag has dealt each of
// its takes: the takes it dealt, and what the frames showed.
std::set<int> look(Run& r, int row, int ms) {
  std::set<int> dealt;
  const int count = takes(row);
  for (int at = 0; at < ms && int(dealt.size()) < count; at += 16) {
    r.step();
    TEST_ASSERT_EQUAL_INT(row, int(r.e->scenes.route.state));
    TEST_ASSERT_TRUE(r.e->scenes.variant < count);
    dealt.insert(r.e->scenes.variant);
  }
  return dealt;
}

}  // namespace

// Every mood plays every state, each of its takes, as the board asks for it:
// the mood it was given held; one reveal for each of a request's; the prop
// it needs shown; only a successful finish's trophy; quiet states silent
// but for comedy and still but for a snore; and every frame inside its
// bounds, nothing drawn jumping.
void test_every_cell_plays_truthfully() {
  // The takes of a row differ, but for the rests and idle, whose scene is
  // one still rest (idle's takes are its acting's, which differ too), and
  // notice, whose takes are one rig clip, each under its own face.
  for (int a = 0; a < slime::kNoticeCount; ++a)
    for (int b = a + 1; b < slime::kNoticeCount; ++b)
      TEST_ASSERT_TRUE(slime::kNoticeFaces[a] != slime::kNoticeFaces[b]);
  for (int p = 0; p < slime::kCanonical; ++p) {
    for (int row = 0; row < slime::kRecipeStates; ++row) {
      if (row == int(SceneState::kIdle) || row == int(SceneState::kNoApp) || row == int(SceneState::kNotice)) continue;
      for (int a = 0; a < takes(row); ++a)
        for (int b = a + 1; b < takes(row); ++b) {
          if (row == int(SceneState::kAsleep) && b < 3) continue;  // its still rests, then the snore
          TEST_ASSERT_FALSE(sameRecipe(take(p, row, a), take(p, row, b)));
        }
    }
    for (int a = 0; a < Acting::takes(p); ++a)
      for (int b = a + 1; b < Acting::takes(p); ++b)
        TEST_ASSERT_TRUE(std::strcmp(Acting::gesture(p, a).type, Acting::gesture(p, b).type) != 0);
    // Waiting and listening make no contacts.
    for (int v = 0; v < 3; ++v) {
      TEST_ASSERT_EQUAL_UINT8(0, take(p, int(SceneState::kWaiting), v).count);
      TEST_ASSERT_EQUAL_UINT8(0, take(p, int(SceneState::kListening), v).count);
    }
  }
  int id = 0, cells = 0;
  for (int mood = 0; mood < slime::kCanonical; ++mood) {
    for (int row = 0; row < slime::kRecipeStates; ++row) {
      const SceneState state = row < kStates       ? SceneState(row)
                               : row < kStates + 2 ? SceneState::kTaskComplete
                                                   : SceneState::kStarting;
      const Outcome outcome = row == kStates       ? Outcome::kSuccess
                              : row == kStates + 1 ? Outcome::kFailure
                                                   : Outcome::kNone;
      const StartCtx ctx = row >= kStates + 2 ? StartCtx(row - kStates - 1) : StartCtx::kNone;
      ++cells;
      if (isReaction(state) && state != SceneState::kListening) {
        std::vector<std::vector<F>> played;
        for (int v = 0; v < takes(row); ++v) played.push_back(play(mood, row, state, outcome, ctx, v, ++id));
        // Each take moves the body its own way, but notice's, its one clip's.
        if (state == SceneState::kNotice) continue;
        for (size_t a = 0; a < played.size(); ++a)
          for (size_t b = a + 1; b < played.size(); ++b) {
            F most = 0;
            for (size_t i = 0; i < played[a].size() && i < played[b].size(); ++i)
              most = max(most, abs(played[a][i] - played[b][i]));
            TEST_ASSERT_TRUE(most > q(.0001));
          }
        continue;
      }
      Facts facts;
      if (state == SceneState::kIdle) {
        // Idle's takes are its acting's: its gestures, then its comedy.
        for (int v = 0; v < Acting::takes(mood); ++v) {
          Run r(mood);
          r.step();
          TEST_ASSERT_TRUE(r.e->acting.perform(r.e->motion.time, r.e->random, v));
          r.run(F(Acting::gesture(mood, v).duration * 1000).integer() + 160);
          TEST_ASSERT_TRUE(r.e->scenes.route.state == SceneState::kIdle);
          TEST_ASSERT_TRUE(r.moved > q(.0001));
          TEST_ASSERT_EQUAL_INT(0, r.reveals);
        }
      } else if (state == SceneState::kAsleep) {
        // Asleep: no performance and no contact but a snore's breaths, its
        // face the sleeping one; it snores in time; and woken, the mood it
        // kept comes back.
        facts.base = SceneState::kAsleep;
        Run r(mood, facts);
        std::set<int> dealt;
        for (int at = 0; at < 90000 && !dealt.count(3); at += 16) {
          r.step();
          TEST_ASSERT_TRUE(r.e->scenes.route.quiet && r.e->acting.performance < 0);
          for (const auto& c : r.e->scenes.contacts) TEST_ASSERT_EQUAL_UINT8(kBreath, c.kind);
          if (at >= 3000) TEST_ASSERT_TRUE(r.e->face.current().sleeping);
          dealt.insert(r.e->scenes.variant);
        }
        TEST_ASSERT_EQUAL_INT(4, int(dealt.size()));
        facts.base = SceneState::kIdle;
        r.e->setFacts(facts);
        r.run(1000);
        TEST_ASSERT_EQUAL_INT(mood, r.e->expression);
        TEST_ASSERT_TRUE(!r.e->face.current().sleeping && r.e->face.current().art == mood);
      } else if (state == SceneState::kNoApp) {
        // A lost link rests as asleep does, silent and still, keeping the
        // facts and the mood for when it's back.
        facts.base = SceneState::kWorking;
        Run r(mood, facts);
        r.run(320);
        r.e->linkTimedOut(true);
        r.clear();
        for (int at = 0; at < 4000; at += 16) {
          r.step();
          TEST_ASSERT_TRUE(r.e->scenes.route.state == SceneState::kNoApp && r.e->acting.performance < 0);
          if (at >= 3000) TEST_ASSERT_TRUE(r.e->face.current().sleeping);
        }
        TEST_ASSERT_EQUAL_INT(0, r.contacts);
        r.e->linkTimedOut(false);
        r.run(1000);
        TEST_ASSERT_TRUE(r.e->scenes.route.state == SceneState::kWorking);
        TEST_ASSERT_TRUE(!r.e->face.current().sleeping && r.e->face.current().art == mood);
      } else if (state == SceneState::kNeedsYou) {
        // Three requests in a row: each its own take, one alert reveal each.
        facts.base = SceneState::kWorking;
        Run r(mood, facts);
        r.run(320);
        std::set<int> dealt;
        for (int k = 0; k < 3; ++k) {
          facts.attention = {true, std::to_string(++id), "claude", "Studio", "", 0};
          r.e->setFacts(facts);
          r.clear();
          const int ms = F(r.e->scenes.recipe.duration).integer();
          dealt.insert(r.e->scenes.variant);
          for (int at = 0; at <= ms + 320; at += 16) {
            r.step();
            TEST_ASSERT_TRUE(r.e->scenes.route.state == SceneState::kNeedsYou);
          }
          TEST_ASSERT_EQUAL_INT(1, r.reveals);
          showsItsProp(r, state);
          facts.attention = {};
          r.e->setFacts(facts);
          r.run(480);
        }
        TEST_ASSERT_EQUAL_INT(3, int(dealt.size()));
      } else if (state == SceneState::kListening) {
        // Listening holds its looping takes until the host says stop.
        facts.base = SceneState::kWorking;
        Run r(mood, facts);
        r.run(320);
        Request mic;
        mic.anim = SceneState::kListening;
        mic.hasId = true;
        mic.id = "mic" + std::to_string(++id);
        r.e->oneShot(mic);
        r.clear();
        TEST_ASSERT_EQUAL_INT(3, int(look(r, row, 30000).size()));
        r.run(4200);
        TEST_ASSERT_TRUE(r.e->scenes.route.state == SceneState::kListening);
        TEST_ASSERT_EQUAL_INT(0, r.contacts);
        TEST_ASSERT_TRUE(r.moved > q(.0001));
        showsItsProp(r, state);
        mic.stop = true;
        r.e->oneShot(mic);
        r.run(400);
        TEST_ASSERT_TRUE(r.e->scenes.route.state == SceneState::kWorking);
      } else {
        // The desk's looks: working, and what the agents do at it.
        facts.base = SceneState::kWorking;
        facts.act = state;
        Run r(mood, facts);
        TEST_ASSERT_EQUAL_INT(3, int(look(r, row, 40000).size()));
        TEST_ASSERT_TRUE(r.moved > q(.0001));
        if (state != SceneState::kWaiting && state != SceneState::kDelegating) TEST_ASSERT_TRUE(r.keys > 0);
        if (state == SceneState::kWaiting) TEST_ASSERT_EQUAL_INT(0, r.contacts);
        showsItsProp(r, state);
      }
    }
  }
  TEST_ASSERT_EQUAL_INT(slime::kCanonical * slime::kRecipeStates, cells);
  jolts.finish();
}

// Ten minutes at work, the agents changing what they do: the desk and the
// mood stay, each take is one the row has, a pick never deals the take its
// row dealt last, no contact comes twice, and nothing drawn jumps.
void test_ten_minutes_of_work() {
  const SceneState acts[] = {SceneState::kWorking,   SceneState::kTerminal, SceneState::kPlanning,
                             SceneState::kSearching, SceneState::kTesting,  SceneState::kToolUse,
                             SceneState::kAnalyzing, SceneState::kWaiting,  SceneState::kDelegating};
  Facts facts;
  facts.base = SceneState::kWorking;
  Run r(slime::kDetermined, facts);
  int last[kStates], iterations = 0, generation = 0, iteration = 0;
  for (int& l : last) l = -1;
  // A pick, at a new act's route or the next pass of a take's.
  auto picked = [&] {
    const auto& s = r.e->scenes;
    if (s.generation == generation && s.iteration == iteration) return;
    generation = s.generation, iteration = s.iteration;
    const int row = int(s.route.state);
    TEST_ASSERT_TRUE(s.variant < takes(row) && s.variant != last[row]);
    last[row] = s.variant;
    iterations += s.iteration > 3;
  };
  picked();
  for (int second = 0; second < 600; ++second) {
    if (second % 30 == 0) {
      facts.act = acts[second / 30 % 9];
      r.e->setFacts(facts);
      picked();
    }
    for (int i = 0; i < 1000; i += 16) {
      r.step();
      TEST_ASSERT_TRUE(r.e->scenes.route.state == facts.act);
      if (second >= 1) TEST_ASSERT_TRUE(r.e->scenes.desk.x > q(.99));
      picked();
    }
  }
  TEST_ASSERT_TRUE(iterations > 0);
}

// What a finger or an alert interrupts plays no more: a held finger keeps
// the desk's keys from sounding and letting go replays none; needs you
// cancels the keys still to come at once; it ends a finish before its
// trophy, which never comes; and a finish held under a finger reveals its
// trophy once, as asked, and replays nothing it skipped.
void test_held_and_interrupted_contacts() {
  Facts working;
  working.base = SceneState::kWorking;
  {
    Run r(slime::kCalm, working);
    r.run(1600);
    r.e->dragStart(q(.2), q(.3));
    r.clear();
    r.run(2400);
    TEST_ASSERT_EQUAL_INT(0, r.contacts);
    // Let go: the keys it held back stay unplayed, the rest come on time.
    r.e->dragEnd();
    const int generation = r.e->scenes.generation, iteration = r.e->scenes.iteration;
    const T released = r.e->scenes.ageMs;
    for (int i = 0; i < 300; ++i) {
      r.step();
      for (const auto& c : r.e->scenes.contacts)
        if (c.generation == generation && c.iteration == iteration)
          TEST_ASSERT_TRUE(r.e->scenes.recipe.contacts[c.index].at >= released);
    }
  }
  {
    Run r(slime::kCalm, working);
    r.run(1600);
    Facts asked = working;
    asked.attention = {true, "7", "claude", "Studio", "", 0};
    r.e->setFacts(asked);
    r.clear();
    r.run(3200);
    TEST_ASSERT_EQUAL_INT(0, r.keys);
  }
  {
    Run r(slime::kHappy, working);
    r.run(320);
    Request done;
    done.anim = SceneState::kTaskComplete, done.outcome = Outcome::kSuccess, done.hasId = true, done.id = "done";
    done.hold = true, done.variant = 0;
    r.e->oneShot(done);
    r.clear();
    r.run(160);
    Facts asked = working;
    asked.attention = {true, "8", "claude", "Studio", "", 0};
    r.e->setFacts(asked);
    r.run(4800);
    r.e->setFacts(working);
    r.run(4800);
    int successes = 0;
    for (const auto& id : r.ids) successes += std::get<0>(id).find("task_complete") != std::string::npos;
    TEST_ASSERT_EQUAL_INT(0, successes);
    TEST_ASSERT_TRUE(r.props[Scenes::kResultProp] == F(0) && !r.success);
    TEST_ASSERT_TRUE(r.e->scenes.route.state == SceneState::kWorking);
  }
  {
    Run r(slime::kHappy, working);
    r.run(320);
    Request done;
    done.anim = SceneState::kTaskComplete, done.outcome = Outcome::kSuccess, done.hasId = true, done.id = "hiccups";
    done.hold = true, done.variant = 3;
    r.e->oneShot(done);
    r.clear();
    r.run(1500);
    r.e->dragStart(q(-.2), q(.3));
    r.run(1500);
    r.e->dragEnd();
    r.run(1200);
    // Its trophy, once, and no card; its hiccups, under the finger, never.
    TEST_ASSERT_EQUAL_INT(1, r.reveals);
    TEST_ASSERT_EQUAL_INT(1, r.contacts);
    TEST_ASSERT_TRUE(r.success && r.props[Scenes::kResultProp] == F(0));
  }
}

// A card's reveal (a failed finish's): from its reveal contact it rises on
// a smoothstep over 400 ms, and falls on one over the take's last 480 ms. A
// card whose reaction ends while it rises or falls carries on as it was
// going while the card fades out over the props' 200 ms ramp, and is drawn
// a dozen frames more, then gone.
void test_card_reveal_trajectory() {
  Facts working;
  working.base = SceneState::kWorking;
  auto start = [&](Run& r) {
    r.run(320);
    Request done;
    done.anim = SceneState::kTaskComplete, done.outcome = Outcome::kFailure, done.hasId = true, done.id = "card";
    done.hold = true, done.variant = 0;
    r.e->oneShot(done);
  };
  {
    Run r(slime::kHappy, working);
    start(r);
    const T began = r.e->scenes.started, duration = r.e->scenes.recipe.duration;
    T reveal = -1;
    for (int i = 0; i < r.e->scenes.recipe.count; ++i)
      if (r.e->scenes.recipe.contacts[i].kind == kFailure) reveal = r.e->scenes.recipe.contacts[i].at;
    TEST_ASSERT_TRUE(reveal == T(680));
    const T down = duration - T(480);
    for (int at = 16; at <= F(duration).integer(); at += 16) {
      r.step();
      const T age = r.e->timeMs() - began;
      const F got = r.e->scenes.slots[Scenes::kResultProp].reveal.value(r.e->timeMs());
      const F want = age < reveal ? F(0)
                     : age < down ? smooth((age - reveal) / kCardRevealMs)
                                  : F(1) - smooth((age - down) / 480);
      TEST_ASSERT_TRUE(abs(got - want) <= q(.002));
    }
  }
  for (bool rising : {true, false}) {
    Run r(slime::kHappy, working);
    start(r);
    const int until = rising ? 680 + 160 : 3200 - 320;
    r.run(until);
    const F before = r.e->scenes.slots[Scenes::kResultProp].reveal.value(r.e->timeMs());
    r.e->clearTransient();
    int shown = 0;
    F last = before;
    for (int i = 0; i < 40; ++i) {
      r.step();
      const F reveal = r.e->scenes.slots[Scenes::kResultProp].reveal.value(r.e->timeMs());
      if (r.e->scenes.visible(Scenes::kResultProp, r.e->timeMs()) == F(0)) continue;  // gone, the card lets it go
      TEST_ASSERT_TRUE(rising ? reveal >= last : reveal <= last);                     // it carries on its way
      last = reveal;
      ++shown;
    }
    TEST_ASSERT_TRUE(shown >= 10 && shown <= 14);
    TEST_ASSERT_TRUE(r.e->scenes.visible(Scenes::kResultProp, r.e->timeMs()) == F(0));
  }
}

// Asleep plays no gesture of its own and rests still: no performance, its
// acting springs at rest, and its body moving only by a snore's swell.
void test_asleep_rests_still_but_for_a_snore() {
  Facts asleep;
  asleep.base = SceneState::kAsleep;
  Run r(slime::kExcited, asleep);
  bool snored = false;
  for (int at = 0; at < 60000; at += 16) {
    r.step();
    TEST_ASSERT_TRUE(r.e->acting.performance < 0 && r.e->acting.playing < 0);
    if (at < 2000) continue;
    for (const auto& c : r.e->acting.channels) TEST_ASSERT_TRUE(abs(c.x) < q(.001));
    TEST_ASSERT_TRUE(abs(r.e->scenes.activity[0].x) < q(.0001) && abs(r.e->scenes.activity[2].x) < q(.0001));
    TEST_ASSERT_TRUE(abs(r.e->scenes.activity[1].x) < q(.03));
    snored |= r.e->scenes.variant == 3;
  }
  TEST_ASSERT_TRUE(snored);
}
