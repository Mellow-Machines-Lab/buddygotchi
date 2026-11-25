// What the gel engine plays for what it's told, and what it sounds: which
// request wins, what a request keeps as it changes, and how sparsely and
// how often its contacts sound.
#include <unity.h>

#include <cstring>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

#include "render/gel/engine.h"
#include "render/gel/pastimes.h"

using namespace render;
using namespace render::gel;

namespace {

Facts look(SceneState base, SceneState act = SceneState::kWorking) {
  Facts f;
  f.base = base;
  f.act = act;
  return f;
}

Facts asking(const char* id, const char* agent = "codex", const char* project = "slime", const char* name = "",
             int more = 0) {
  Facts f = look(SceneState::kWorking);
  f.attention = {true, id, agent, project, name, more};
  return f;
}

Request ask(SceneState anim, Outcome outcome = Outcome::kNone, int loops = 1) {
  Request r;
  r.anim = anim;
  r.outcome = outcome;
  r.loops = loops;
  return r;
}

// A fresh engine, stepped once, on the facts given.
std::unique_ptr<Engine> engine(const Facts& facts = Facts{}) {
  auto e = std::make_unique<Engine>();
  e->step(0);
  e->setFacts(facts);
  return e;
}

SceneState state(const Engine& e) { return e.scenes.route.state; }
uint64_t request(const Engine& e) { return e.scenes.route.key; }

// Steps `ms` on the 16 ms grid from `t`, calling each() after every step.
template <class Each>
void run(Engine& e, uint32_t& t, int ms, Each each) {
  for (int i = 0; i < ms; i += 16) {
    e.step(t += 16);
    each();
  }
}
void run(Engine& e, uint32_t& t, int ms) {
  run(e, t, ms, [] {});
}

bool sameCues(const Engine& a, const Engine& b) {
  if (a.cues.size() != b.cues.size()) return false;
  for (size_t i = 0; i < a.cues.size(); ++i) {
    const auto &x = a.cues[i], &y = b.cues[i];
    if (std::strcmp(x.recipe, y.recipe) || x.variant != y.variant || x.seed != y.seed || x.pitch != y.pitch ||
        x.gain != y.gain || x.contact.kind != y.contact.kind)
      return false;
  }
  return true;
}

int count(const std::vector<SoundCue>& cues, const char* recipe) {
  int n = 0;
  for (const auto& c : cues) n += !std::strcmp(c.recipe, recipe);
  return n;
}

}  // namespace

// Which request plays: a lost link over listening, listening over needs
// you, needs you over a reaction, a reaction over the look; an act only
// while working. Every one of the board's states is reachable from what
// the engine is told. Listening asked again starts anew, has no time of
// its own, and ends when it's cleared or a reaction comes, even one refused
// because needs you shows. A borrowed face plays over a reaction without
// replacing it; loops are one or more (the device holds them to its most),
// each a pass of the same take with one reveal, and the last held until
// it's cleared, onto the latest facts; held through a lost link, a reaction
// comes back with its take; facts can't clear a lost link, and getting the
// link back plays the latest. A take its state hasn't got is dealt instead;
// a gesture asked for no take plays the first, and its bit plays at work
// too; a notice asked for none is dealt one.
void test_requests_route_by_priority() {
  std::set<SceneState> reached;
  auto e = engine();
  auto expect = [&](const Engine& on, SceneState want) {
    TEST_ASSERT_EQUAL_INT(int(want), int(state(on)));
    reached.insert(want);
  };
  for (SceneState base : {SceneState::kAsleep, SceneState::kIdle, SceneState::kWorking}) {
    e->setFacts(look(base));
    expect(*e, base);
  }
  for (SceneState act : {SceneState::kTesting, SceneState::kDelegating, SceneState::kTerminal, SceneState::kSearching,
                         SceneState::kAnalyzing, SceneState::kToolUse, SceneState::kWaiting, SceneState::kPlanning}) {
    // Each act shows as its activity's one state.
    e->setFacts(look(SceneState::kWorking, act));
    expect(*e, deskStateOf(activityOf(act)));
  }
  e->setFacts(look(SceneState::kIdle, SceneState::kTesting));
  expect(*e, SceneState::kIdle);
  e->setFacts(asking("1"));
  expect(*e, SceneState::kNeedsYou);
  TEST_ASSERT_TRUE(e->play(ask(SceneState::kListening)));
  expect(*e, SceneState::kListening);
  const uint64_t listening = request(*e);
  const int generation = e->scenes.generation;
  TEST_ASSERT_TRUE(e->play(ask(SceneState::kListening)));
  TEST_ASSERT_TRUE(request(*e) != listening && e->scenes.generation == generation + 1);
  TEST_ASSERT_TRUE(state(*e) == SceneState::kListening);
  e->linkTimedOut(true);
  expect(*e, SceneState::kNoApp);
  e->linkTimedOut(false);
  expect(*e, SceneState::kListening);
  uint32_t t = 0;
  run(*e, t, 30000);  // listening has no time of its own
  TEST_ASSERT_TRUE(state(*e) == SceneState::kListening);
  TEST_ASSERT_FALSE(e->play(ask(SceneState::kTaskComplete, Outcome::kSuccess)));
  TEST_ASSERT_TRUE(state(*e) == SceneState::kNeedsYou);
  e->setFacts(look(SceneState::kWorking));
  TEST_ASSERT_TRUE(state(*e) == SceneState::kWorking);
  TEST_ASSERT_TRUE(e->play(ask(SceneState::kListening)));
  e->clear();
  TEST_ASSERT_TRUE(state(*e) == SceneState::kWorking);
  for (SceneState anim : {SceneState::kReplyReady, SceneState::kTaskComplete, SceneState::kPoked, SceneState::kTapSpam,
                          SceneState::kWakeUp, SceneState::kGesture, SceneState::kNotice}) {
    auto single = engine(look(SceneState::kWorking));
    TEST_ASSERT_TRUE(single->play(ask(anim, Outcome::kFailure)));
    expect(*single, anim);
  }
  // Every state but the five acts the gel shows as another's (planning,
  // tool_use, searching, testing, delegating).
  TEST_ASSERT_EQUAL_INT(int(SceneState::kCount) - 5, int(reached.size()));
  // A borrowed face over a finish: the finish, its outcome and its pass
  // stay; the lasting mood stays; a bare reaction has nothing to play.
  auto finish = engine(look(SceneState::kWorking));
  finish->play(ask(SceneState::kTaskComplete, Outcome::kFailure));
  const uint64_t finishing = request(*finish);
  const int pass = finish->scenes.generation;
  finish->borrow(slime::kSad);
  TEST_ASSERT_TRUE(state(*finish) == SceneState::kTaskComplete && finish->scenes.route.outcome == Outcome::kFailure);
  TEST_ASSERT_EQUAL_INT(slime::kCalm, finish->emotion);
  TEST_ASSERT_EQUAL_INT(slime::kSad, finish->expression);
  TEST_ASSERT_TRUE(request(*finish) == finishing && finish->scenes.generation == pass);
  TEST_ASSERT_FALSE(finish->play(Request{}));
  // Loops, one or more.
  const int asked[] = {-2, 0, 1, 4, 6}, kept[] = {1, 1, 1, 4, 6};
  for (int i = 0; i < 5; ++i) {
    auto single = engine();
    single->play(ask(SceneState::kTaskComplete, Outcome::kFailure, asked[i]));
    TEST_ASSERT_EQUAL_INT(kept[i], single->scenes.route.loops);
  }
  // Three loops: one take three times over, each pass revealing once.
  auto looped = engine(look(SceneState::kWorking));
  looped->play(ask(SceneState::kTaskComplete, Outcome::kFailure, 3));
  std::set<int> takes, passes;
  int failures = 0;
  t = 0;
  run(*looped, t, 14400, [&] {
    if (state(*looped) != SceneState::kTaskComplete) return;
    takes.insert(looped->scenes.variant), passes.insert(looped->scenes.iteration);
    for (const auto& c : looped->scenes.contacts) failures += c.kind == kFailure;
  });
  TEST_ASSERT_EQUAL_INT(1, int(takes.size()));
  TEST_ASSERT_TRUE((passes == std::set<int>{0, 1, 2}));
  TEST_ASSERT_EQUAL_INT(3, failures);
  TEST_ASSERT_TRUE(state(*looped) == SceneState::kTaskComplete && looped->scenes.iteration == 2);
  // A wake-up holds its last until it's cleared, then shows the latest facts.
  auto start = engine(look(SceneState::kWorking));
  start->play(ask(SceneState::kWakeUp));
  TEST_ASSERT_TRUE(state(*start) == SceneState::kWakeUp);
  start->setFacts(look(SceneState::kWorking, SceneState::kTerminal));
  t = 0;
  run(*start, t, 16000);
  TEST_ASSERT_TRUE(state(*start) == SceneState::kWakeUp);
  start->clear();
  TEST_ASSERT_TRUE(state(*start) == SceneState::kTerminal);
  // A lost link: facts don't clear it, the link coming back plays the latest.
  auto lost = engine(look(SceneState::kWorking));
  lost->linkTimedOut(true);
  lost->setFacts(look(SceneState::kWorking, SceneState::kTerminal));
  t = 0;
  run(*lost, t, 320, [&] { TEST_ASSERT_TRUE(state(*lost) == SceneState::kNoApp); });
  lost->linkTimedOut(false);
  TEST_ASSERT_TRUE(state(*lost) == SceneState::kTerminal);
  // A reaction held through a lost link comes back with its take.
  auto held = engine(look(SceneState::kWorking));
  held->play(ask(SceneState::kTaskComplete, Outcome::kSuccess));
  TEST_ASSERT_TRUE(state(*held) == SceneState::kTaskComplete);
  const int take = held->scenes.variant;
  held->linkTimedOut(true);
  t = 0;
  run(*held, t, 1600);
  held->linkTimedOut(false);
  TEST_ASSERT_TRUE(state(*held) == SceneState::kTaskComplete && held->scenes.variant == take);
  // A fourth take where the state has three: one of the three, dealt.
  auto fourth = engine(look(SceneState::kWorking));
  Request reply = ask(SceneState::kReplyReady);
  reply.variant = 3;
  fourth->play(reply);
  TEST_ASSERT_TRUE(state(*fourth) == SceneState::kReplyReady && fourth->scenes.variant < 3);
  // A gesture with no take is the first; at work its bit plays, and stops with
  // it.
  auto plain = engine();
  plain->play(ask(SceneState::kGesture));
  TEST_ASSERT_TRUE(state(*plain) == SceneState::kGesture);
  TEST_ASSERT_EQUAL_INT(0, plain->scenes.variant);
  auto work = engine(look(SceneState::kWorking, SceneState::kTerminal));
  Request dizzy = ask(SceneState::kGesture);
  dizzy.variant = 5;
  work->play(dizzy);
  t = 0;
  run(*work, t, 1600, [&] { TEST_ASSERT_FALSE(work->acting.suppressed); });
  TEST_ASSERT_TRUE(work->acting.playing >= 0);
  work->clear();
  TEST_ASSERT_TRUE(state(*work) == SceneState::kTerminal && work->acting.suppressed);
  // A notice with no take asked is dealt one of its three.
  auto notice = engine();
  notice->play(ask(SceneState::kNotice));
  TEST_ASSERT_TRUE(state(*notice) == SceneState::kNotice && notice->scenes.variant < 3);
}

// A needs-you request is its id, its agent and its project, in that
// activation: a new name, more waiting or a mood change keep it, with no
// new entry and no sound; a new id, the same id after it cleared, or
// another agent or project is a new request. Needs you stops the desk's
// keys at once.
void test_a_request_keeps_its_identity() {
  auto e = engine(look(SceneState::kWorking));
  uint32_t t = 0;
  run(*e, t, 2000);
  e->setFacts(asking("777"));
  TEST_ASSERT_TRUE(state(*e) == SceneState::kNeedsYou);
  const uint64_t id = request(*e);
  run(*e, t, 4000, [&] {
    for (const auto& c : e->scenes.contacts) TEST_ASSERT_TRUE(c.kind != kKey);
  });
  const int pass = e->scenes.iteration, generation = e->scenes.generation;
  for (int mood : {slime::kHappy, slime::kGrumpy, slime::kSad}) {
    e->setMood(mood);
    const std::string name = std::string("Renamed ") + slime::kProfile[mood].id;
    e->setFacts(asking("777", "codex", "slime", name.c_str(), 3));
    run(*e, t, 800, [&] {
      TEST_ASSERT_TRUE(request(*e) == id);
      TEST_ASSERT_TRUE(e->scenes.iteration == pass && e->scenes.generation == generation);
      TEST_ASSERT_EQUAL_INT(0, int(e->scenes.contacts.size()));
      TEST_ASSERT_EQUAL_INT(0, int(e->cues.size()));
    });
  }
  e->setFacts(asking("778"));
  const uint64_t next = request(*e);
  TEST_ASSERT_TRUE(next != id);
  e->setFacts(look(SceneState::kWorking));
  TEST_ASSERT_TRUE(state(*e) == SceneState::kWorking);
  e->setFacts(asking("778"));
  TEST_ASSERT_TRUE(request(*e) != next);
  uint64_t previous = request(*e);
  for (const char* project : {"slime", "other"}) {
    e->setFacts(asking("778", "claude", project));
    TEST_ASSERT_TRUE(request(*e) != previous);
    previous = request(*e);
  }
}

// Sound stays sparse and quiet. At work its keys sound none: the paws on
// the keys show the typing, and a click at every word was too much. Were
// they to, a pass of a loop would sound at most four of its contacts, and a
// loop shorter than 3.5 s every other pass; stepping to the same time again
// sounds nothing. Idle sounds only its comedy's sneeze (the
// face's to deal: here every 20 s) and sleep
// only its snore's breaths, each fewer than half its contacts, ducked under
// a line like any routine sound; waiting and listening sound nothing. A
// finish's hiccups sound as three little squishes after its fanfare.
void test_cues_stay_sparse_and_quiet() {
  static_assert(slime::kMaxRoutine == 4 && slime::kShortLoopMs == 3500 && slime::kShortLoopEvery == 2,
                "four sounds a pass, a short loop's every other pass");
  auto e = engine(look(SceneState::kWorking));
  std::map<std::pair<int, int>, int> perPass;
  int contacts = 0, cues = 0;
  for (uint32_t at = 16; at <= 600000; at += 16) {
    e->step(at);
    contacts += int(e->scenes.contacts.size() + e->acting.contacts.size());
    cues += int(e->cues.size());
    TEST_ASSERT_TRUE((perPass[{e->scenes.generation, e->scenes.iteration}] += int(e->cues.size())) <= 4);
    if (e->scenes.recipe.duration < T(3500) && e->scenes.iteration % 2) TEST_ASSERT_EQUAL_INT(0, int(e->cues.size()));
    e->step(at);
    TEST_ASSERT_EQUAL_INT(0, int(e->cues.size()));
  }
  TEST_ASSERT_TRUE(contacts > 0);
  TEST_ASSERT_EQUAL_INT(0, cues);
  struct Quiet {
    SceneState base;
    const char* recipe;
    uint32_t ms;
  } quiet[] = {{SceneState::kIdle, "sneeze", 20 * 60000},
               {SceneState::kAsleep, "breath", 5 * 60000},
               {SceneState::kWaiting, nullptr, 60000},
               {SceneState::kListening, nullptr, 60000}};
  for (const auto& q : quiet) {
    auto s = engine(q.base == SceneState::kWaiting ? look(SceneState::kWorking, SceneState::kWaiting) : look(q.base));
    if (q.base == SceneState::kListening) s->play(ask(SceneState::kListening));
    int comedyContacts = 0, sounded = 0;
    for (uint32_t at = 16; at <= q.ms; at += 16) {
      if (q.base == SceneState::kIdle && at % 20000 == 0) s->playBit(bitOf(info(Pastime::kSneeze)));
      s->step(at);
      for (const auto& c : s->acting.contacts) comedyContacts += comedy(c.kind);
      for (const auto& c : s->scenes.contacts) comedyContacts += comedy(c.kind);
      for (const auto& cue : s->cues) {
        TEST_ASSERT_NOT_NULL(q.recipe);
        TEST_ASSERT_EQUAL_STRING(q.recipe, cue.recipe);
        TEST_ASSERT_TRUE(comedy(cue.contact.kind) && !cue.protectedCue);
        ++sounded;
      }
    }
    if (q.recipe) TEST_ASSERT_TRUE(comedyContacts > 0 && sounded > 0 && sounded * 2 < comedyContacts);
  }
  auto hiccups = engine();
  Request success = ask(SceneState::kTaskComplete, Outcome::kSuccess);
  success.variant = 3;
  hiccups->setMood(slime::kHappy);
  hiccups->play(success);
  std::vector<SoundCue> heard;
  uint32_t t = 0;
  run(*hiccups, t, 3700, [&] { heard.insert(heard.end(), hiccups->cues.begin(), hiccups->cues.end()); });
  TEST_ASSERT_EQUAL_INT(3, hiccups->scenes.variant + 0);
  TEST_ASSERT_EQUAL_INT(1, count(heard, "complete"));
  TEST_ASSERT_EQUAL_INT(3, count(heard, "squish"));
}

// A request sounds once, whatever changes while it shows: a minute of
// needs you through a mood change, a new name and more waiting, and a lost
// link coming back is one ding; a new request is one more. A ding is the
// alert's own sound, the same every time (its first take, seed 53, pitch 1,
// gain .45). A finish's fanfare or failure sounds once however many times
// it loops.
void test_a_request_sounds_once_whatever_changes() {
  auto e = engine();
  std::vector<SoundCue> dings;
  uint32_t t = 0;
  auto listen = [&] {
    for (const auto& c : e->cues)
      if (!std::strcmp(c.recipe, "ding")) dings.push_back(c);
  };
  e->setFacts(asking("7", "codex", "a"));
  run(*e, t, 2400, listen);
  e->setMood(slime::kSad);
  e->setFacts(asking("7", "codex", "a", "Renamed", 3));
  run(*e, t, 4800, listen);
  e->linkTimedOut(true);
  run(*e, t, 160, listen);
  e->linkTimedOut(false);
  run(*e, t, 2400, listen);
  TEST_ASSERT_EQUAL_INT(1, int(dings.size()));
  e->setFacts(asking("8", "codex", "a"));
  run(*e, t, 2400, listen);
  TEST_ASSERT_EQUAL_INT(2, int(dings.size()));
  for (const auto& d : dings)
    TEST_ASSERT_TRUE(d.variant == 0 && d.seed == 53 && d.pitch == F(1) && d.gain == q(.45) && d.protectedCue);
  for (Outcome outcome : {Outcome::kSuccess, Outcome::kFailure}) {
    auto finish = engine();
    finish->play(ask(SceneState::kTaskComplete, outcome, 6));
    std::vector<SoundCue> heard;
    t = 0;
    run(*finish, t, 26000, [&] { heard.insert(heard.end(), finish->cues.begin(), finish->cues.end()); });
    TEST_ASSERT_EQUAL_INT(1, count(heard, outcome == Outcome::kSuccess ? "complete" : "failed"));
  }
}

// Sound has randomness of its own: two engines told the same things sound
// alike, cue for cue, and one whose sound draws differ moves and draws
// exactly as the others do.
void test_sound_draws_change_nothing_drawn() {
  auto a = std::make_unique<Engine>(), b = std::make_unique<Engine>(), c = std::make_unique<Engine>();
  c->soundRandom = Random(1);
  bool differed = false;
  for (uint32_t t = 0; t <= 60000; t += 16) {
    for (Engine* e : {a.get(), b.get(), c.get()}) {
      if (t == 0) e->setFacts(look(SceneState::kWorking, SceneState::kTerminal));
      if (t == 10000) e->setFacts(asking("1"));
      if (t == 16000) e->setFacts(look(SceneState::kIdle));
      if (t == 40000) e->play(ask(SceneState::kTaskComplete, Outcome::kSuccess));
      if (t == 50000) e->setFacts(look(SceneState::kAsleep));
      e->step(t);
    }
    TEST_ASSERT_TRUE(sameCues(*a, *b));
    differed |= !sameCues(*a, *c);
    TEST_ASSERT_TRUE(a->pose() == c->pose() && a->life() == c->life());
    TEST_ASSERT_TRUE(a->face.controls == c->face.controls && a->blink() == c->blink());
    for (int i = 0; i < 4; ++i) TEST_ASSERT_TRUE(a->motion.modes[i].x == c->motion.modes[i].x);
    TEST_ASSERT_EQUAL_INT(int(a->scenes.contacts.size()), int(c->scenes.contacts.size()));
    for (size_t i = 0; i < a->scenes.contacts.size(); ++i)
      TEST_ASSERT_TRUE(a->scenes.contacts[i].kind == c->scenes.contacts[i].kind &&
                       a->scenes.contacts[i].index == c->scenes.contacts[i].index &&
                       a->scenes.contacts[i].timeMs == c->scenes.contacts[i].timeMs);
    for (int p = 0; p < Scenes::kProps; ++p)
      TEST_ASSERT_TRUE(a->scenes.visible(Scenes::Prop(p), a->timeMs()) ==
                       c->scenes.visible(Scenes::Prop(p), c->timeMs()));
  }
  TEST_ASSERT_TRUE(differed);
}
