# Fun audit: where Boop is dull, repetitive or boxed in, in this repository (2026-10-21)

The owner's brief, the same as last night's in the personal repository:
a buddy that is fun and interactive in daily use, a bit obtuse at times,
loud rather than quiet for now; reliable where it must be ("needs you")
and surprising elsewhere (cussing at a failed prompt); words and sounds
that feel lifelike with a pet's vocabulary. Plus the dumb-pet list:
hearing about 20 words, getting them wrong on purpose, bodily comedy
(hiccups, sneezes, nodding off, forgetting, a gift), a startle at a loud
noise, and reacting to tone. The mic is in scope; audio never leaves the
Mac, and what's heard goes in as an event.

This audit is of **this** repository (Mellow-Machines-Lab/buddygotchi, at
`4c9157b`) and both of its character packs: Boop, the gel slime on the
AMOLED with Pixel's face on the CYD, and Pixel, the pixel face. The
prior art is the personal repository's audit, plan and overnight
iteration of 2026-10-20/21 (`buddygotchi_old`, branch
`worktree-bridge-cse_01SXrgC1Lay6ULSx1kvnPobs`, `plan/evidence/`). What
fits is reused; everything is checked against this engine, which differs
in most of the places that matter (§2). The plan that follows from it is
[PLAN.md](PLAN.md).

## 1. What ran

| Check | Result |
| --- | --- |
| `python3 characters/charactergen.py --stage && swift build --product boopdev` | Builds (30.6 s) |
| `.build/debug/boopdev check` | `boop: ok`, `pixel: ok`, charactergen passes both |
| `.build/debug/boopdev eval --list` | 62 scenarios: 660 requests at the default runs (`make eval`), 388 at `--runs 1`, 165 for the 27 `always` scenarios at `--runs 1` |
| Jev | **Nothing.** `BOOP_JEV_KEY` was not set in this session and no key came with the brief, so no eval case ran. Every claim below about what Jev answers is either read off the steering text (which pins the answer) or carried over from the personal repository's runs of 2026-10-20/21, and is marked so |

No tests, firmware or simulator checks ran: nothing was changed.

## 2. Where Boop stands here

This engine is further along than the one audited last night. Much of
that plan is already done here, in a different shape:

| Last night's item | Here |
| --- | --- |
| R5 sweet or cheeky as a section | **Done.** `steering/nature/{sweet,cheeky}.md` in both packs, placed after PERSONALITY (`Runtime+Buddies.brain`). Not exercised by any eval (§5) |
| R7 idle life by re-picking a look's variation | **Done, on the device.** The pixel face turns a look's variation at the end of each loop, 67% of the time, once the look has shown 5 s (`PixelFace::kTurnPct`, `kTurnMinMs`); the gel plays one of three authored performances per mood every 7–15 s (`Acting::perform`). What's missing is content: nothing it turns to is funny or audible (§3 A4) |
| R12's privacy shape for ears | **Half done.** Push-to-talk already runs on-device speech recognition (`SpeechListener`, `requiresOnDeviceRecognition`) and sends only the words. But it needs the button held, and it sends the free text to Jev, cut to 300 characters |
| The wake-up | **Done.** `wake_up` animation, a presence detector, `63`–`65` |
| Needs you that asks harder | **Done.** The pixel sign's five stages, the gel's knocks and ding, on the request's own clock |
| The context wall | **Half done.** The COMPACTED card plays by rule; the brain never hears of it (§3 C5) |
| A failure with a body | **Done.** `task_complete` has failure designs ("The task fell apart"; the gel's "FAILED" card), so the cuss already has art. What it lacks is a required word and a hold |

**What it can do.** 42 moods on the mood graph, each a face on both
boards (the pixel face draws 13 and lends them to the other 29;
the gel draws all 42). 23 states, 13 of them looks and 10 reactions.
A recorded voice of 2,722 takes: three feelings (glad, upset, tickled),
16 topics, four kinds (word, sound, phrase, swear), a `say` of up to two
takes within 2.8 s, and the last say's words are avoided next time. Jev
answers six questions per pass (face, animation, hold, feeling, topic,
kind) plus the mood. Reactions are mood-tinted looks, four finish
animations, and the rules' starting, stopped, error and helper return.
Two buddies can share a desk and react to each other. Demos script
seven hero clips. Growth XP and stages exist and drive nothing.

**What works, keep it.** "Needs you" is a plain core rule, the device
holds it over everything, and nothing but what you say wakes the brain
while it shows: every recommendation in the plan leaves that alone. The
mood graph with its ordinary and dramatic moves, pinned by `47`–`53`.
The device's queue (`play: next`, 5 s ttl) and the "in progress" line in
HISTORY. Variation picking never-the-last on both sides. The voice's own
variety (eight ways to say "done"). The eval runner on a virtual clock
with a scripted brain, which prices a change without a key.

**What it feels like today** (from the steering, the device code and
the pack content, not from a Jev run). Working: an engaged face held
twice with a work grunt every 1.5–3 minutes, the same line each time.
A finish: a happy face held once over one of four trophy designs, with
"Done" or "Finished". A failed turn: an irritated face, a cross, maybe
"Ugh", once. Idle with sessions open: blinks, the three idle designs
taking turns, no sound at all, and the brain hears nothing for an hour.
Asleep: silent, dimmed. A tap: one poke design, "Boop" or "Whoa" from
Jev, every time. There is no comedy in either face, nothing happens on
its own that you'd hear, and Boop never once does the wrong thing.

## 3. Findings

### A. Not joyful, fun or interactive enough

| # | Finding | Evidence |
| --- | --- | --- |
| A1 | **The 29 moods only the slime draws are dead letters to Jev.** Boop's `character.json` takes their `meaning` from the slime design's `emotion-graph.json`, so Jev reads "Comically reluctant and low-effort in presentation, while still performing the real task correctly" (lazy) or "display label Hurt, stable legacy ID wounded" (wounded); 29 have no `face` text; and their `steering/mood/*.md` are one generic boilerplate ("React only to what NOW establishes; never invent danger…"). Those are exactly the fun moods: lazy, bored, mischievous, amused, surprised, stunned, baffled, disgusted, embarrassed, tired. Pixel's pack has plain meanings and faces for all 42, but mood files of three lines | `characters/boop/character.json`; `steering/mood/lazy.md`, `bored.md`, `hopeful.md`; `slimegen` README ("the slime design's emotion-graph.json is the source for Boop's moods… it keeps any key a mood has that the design doesn't set, such as `face`") |
| A2 | **Routine work is one face.** The personality pins it: a short finish → `happy, success, done in a word, once`; a long one the same with "glad"; "work still going gets a face held twice" every check-in. The design and the word vary (never-the-last, `lastWords`); the face mood and the hold never do. Last night's runs on the same brain: Jev answers the same line the same way at 0.9+ | `steering/personality/boop.md` Examples; `ReactOutput.run` (`lastVariant`, `lastWords`); personal repo passes.txt |
| A3 | **Interaction is a tap and a held button.** A tap is `poked`, or `tap_spam` from the third; Jev answers each run once (`answersRunFrom`), so a barrage is one face. There's no poke while asleep, no second barrage ("again"), no double tap, stroke or shake; the hardware is a touch panel and BOOT. Push-to-talk needs the button held 400 ms; the words then go to Jev as free text. There is no hands-free hearing, no level meter, no tone | `firmware/src/app/gesture.h`; `TranscriptView.poke`; `app/Boop/Talk.swift` |
| A4 | **Idle and asleep are silent on both faces.** Pixel's idle designs ("Quiet blink", "Small look-around", "Tiny resting stretch") and asleep designs ("Even sleep", "Small dream twitch", "Sleepy resettle") all carry the `silent` sound policy; the gel's `state-plan.json` marks idle, asleep, no_app, listening and waiting `silent`. No yawn, snore, sigh or sneeze exists in either bank. The device's variation turns and the gel's performances have nothing comic to turn to | `sfxgen` scores (`policy: silent` on every idle and asleep design); `state-plan.json` `audioPolicy` |
| A5 | **The brain is deaf between events.** With sessions open and nothing working it hears "Nothing has happened for 1 hour" once an hour and never sooner; it never hears that you answered a request (the `needs_you` end is recorded, not lined); it never hears a compaction (the COMPACTED card plays by rule, `sessionStart` lines are nil); the working check-in's line has no topic (its facts do). So there's nothing to react to when you're around but not running agents, and the one moment you and Boop look at the same thing (you approve, amber clears) gets nothing | `TranscriptView.heartbeat(at:)` (`heartbeatMs` = 1 h), `needs(_:)` (start only), `agentEvent` `.sessionStart: return nil`, `EventLine.working` |
| A6 | **The cuss is a one-hold grumble.** `03` accepts `feeling: upset\|none` with no word and no hold; the swear is kept for `60` (a stinging failure, already grumpy). A failed turn after a failed check in the same turn has no Example. "Loud is better" has two levers, the hold (`react.loops`) and the kind (`say.kind`), and the steering pulls neither at a plain failure | `03-turn-failed.json`; `boop.md` ("irritated, failure, upset in a swear, once") |
| A7 | **Nothing is ever wrong on purpose.** `react` reads each answer's top `choice`; the only randomness between Jev and the device is which take and which variation. Jev's full probability table arrives with every answer and nothing reads it | `ReactOutput.run`; `MellowHarness.Answer.probabilities` |
| A8 | **Sweet or cheeky changes the prompt and nothing checks it.** The evals build the harness with `nature: nil`, so every scenario runs a prompt the app never shows (the app always has a nature from setup). Boop's Examples don't differ by nature; the nature files are prose with no Examples | `Eval.run` → `Runtime.harness(... nature:)` default nil; `steering/nature/*.md` |
| A9 | **The pet's vocabulary is the brain's, not the person's.** Boop can say hundreds of words; the person can say nothing to it without holding the button. "Good boy" works today through push-to-talk (`35`), which is the right privacy shape and the wrong ergonomics for a dog | `35-talk-gets-an-answer.json`; `Core.Talk` |

### B. Too repetitive

| # | Finding | Evidence |
| --- | --- | --- |
| B1 | **The working heartbeat is the same line, face and hold, 8 times in a 20-minute turn.** `claude is still working on "api", a very long turn.` every 90–180 s; the Example says engaged, work, twice. Only the grunt varies (8 work sounds, 9 words) | `EventLine.working`; `boop.md`; last night's `21` timeline (12 identical check-ins) |
| B2 | **Finishes repeat their face and hold** (A2). With four success designs and eight "done" takes the picture and the word already vary more than they did last night; the mood face and `once` don't | `ReactOutput.run` |
| B3 | **The evals say sameness is fine.** `max_same_in_a_row` and `min_variety` are implemented in `Eval.judge` and used by no scenario; `19`'s case reads "The same face every time is fine; staying quiet isn't"; the working day prints the longest identical run "with no limit: repeats are fine" | `grep -l max_same_in_a_row characters/boop/evals/` is empty; `19-same-win-again.json`; `workday.py` `LIMITS` (six limits, none on repeats or words) |
| B4 | **A barrage is one face by design (good), and so is every barrage.** `23` pins one reaction per barrage; `16` pins grumpy or irritated for each of three. A second barrage reads to Jev as a fresh one (last night: "It can't read back through HISTORY… the fix was a named modifier") | `23-poke-barrage-one-face.json`; personal repo iteration notes |

### C. Architectural gaps

| # | Gap | Why it blocks the brief | Where |
| --- | --- | --- | --- |
| C1 | **Everything expressive but the device's reflexes and four rule reactions waits on a paid network call.** Without a key "Boop still shows what your agents are doing… but doesn't react or celebrate". The device-side life that exists (blinks, variation turns, gel performances) is the right place for the free, small stuff, and it has no comic content to play | README "A Jev key"; `Core.play` (starting, stopped, error, helper_return) |
| C2 | **`react` reads only the top choice**, though every `Answer` carries Jev's probabilities. A repeat guard, a second-best swap or a die fits in that one file with no harness change | `ReactOutput.run`, `Contracts.swift` `Answer` |
| C3 | **A new reaction animation is an engine change; a new variation is pack content.** The 23 states are "fixed by the engine": `SceneState`, `charactergen --check`'s table, `faces.json`'s `states`, `FaceLoops`, `ReactOutput.animations` and `scenes`, `DeviceReaction.anims`, the gel's families and `kRecipeStates`, the studio's `states.json`. Variations of an existing state need only the pack's generators (`facegen`/`sfxgen`, `slimegen`), and both faces pick among them on their own. So comedy should land as variations first | CHARACTER.md §9; `render/types.h`; `slime.h` `static_assert(kRecipeStates)` |
| C4 | **No ears.** `SpeechListener` taps the input only while push-to-talk is on; there's no level or pitch path; `talk` lines quote free text. A hands-free listener needs its own component, a fixed vocabulary and a new event kind; the pipeline (`Pipeline.said` → `talk`) is the model to copy | `app/Boop/Talk.swift`; `Event.Kind` |
| C5 | **Five things the view doesn't say** (A5): compaction, the answered request, the check-in's topic, idle under an hour, a poke while asleep or a barrage again. Each is a line and facts in `TranscriptView`, a wake, and Examples; none touches the core, the harness or the device | `TranscriptView`; `EventLine` |
| C6 | **The steering is full.** Guide 300/300 tokens, `boop.md` 729/750, `engaged.md` 175/175 (`Steering.Budget`, about four bytes a token). Every Example the plan adds means cutting one first | `Steering.Budget`; `overBudget()` is pinned by `RuntimeTests` and `CharacterPackTests` |
| C7 | **The say is capped at two takes and 2.8 s, and a phrase plays alone.** "Loud" tops out at a 2.6 s phrase; a four-times hold has the same words as a once | `Voice.say`, `maxSayMs`, `DeviceReaction.Say` (`prefix(2)`) |
| C8 | **The eval runner lacks the steps the fun needs.** Steps: turn started/finished/failed, command, poke, pokes (four), said, away, back, wait. No `needs you`/`answered`, no `compact`, no Codex, no poke count or asleep, no heard, no `nature`, no buddies. And nothing in Pixel's pack: the evals and the working day are Boop's | `Scenario.events`; `characters/pixel/` has no `evals/` |
| C9 | **Growth does nothing.** XP and six stages (Hatchling to Legend) are counted and shown; "nothing Boop does depends on them yet". Not a gap for this brief, but the cheapest hook for "a pet that learns tricks" later | `Growth.swift` |

### D. Do the evals cover the fun?

**Covered well** (62 scenarios, 27 of them `always`): the mood ladder
and the graph (`04`, `13`, `47`–`53`, `55`, `68`, `69`); the hero
moments as decisions (`02` the cheer, `03`/`60` the cuss, `05`/`16`/`23`
pokes, `63`–`65` the wake-up); talk, apologies and sad news (`35`–`40`,
`54`, `56`–`59`); never the wrong face (`17`); liveliness windows (`18`,
`21`, `22`); finishes judged by their words (`41`–`46`). Pass/fail is
strict, one scenario costs 1–29 requests, and the scripted brain prices
a run for free.

**Not covered:**

| Gap | Detail |
| --- | --- |
| Variety | No scenario uses `max_same_in_a_row` or `min_variety`; `19` allows the same face five times |
| Words at the hero moments | `said` is required in 4 steps (`29`, `60`, `62`); `03`, `05`, `08`, `16` accept nothing said; `kind` is checked in 9 steps, `loops` in 6 |
| Nature | None: every run has no NATURE section |
| Needs you answered, compaction, idle under an hour, a poke while asleep | No step, no line |
| Codex | Every scenario is Claude's |
| The other pack | Pixel has no evals; the runner takes `--scenarios` and `--steering`, and `CHARACTER=pixel` picks its pack |
| Hero clips 1 and 2 | The cheer and the cuss have no standalone demo; `landing` has both inside a longer story |
| Sound and holds | Nothing checks that a bigger moment holds longer or says more than a small one in one run |
| The working day | `LIMITS` has no repeat limit and no words-said limit |
| Buddies | A demo (`not-my-turn`) and unit tests; no eval |

## 4. What the plan does about it

[PLAN.md](PLAN.md) has ten recommendations, each a brief a subagent can
take alone, in the order the owner's rule prefers: pack content and the
device's own timelines first, then steering, then new lines for the
brain, then `react` reading its own answers, and one new component
(ears) last. The core, the harness, the protocol and the device's queue
change nowhere; one optional item (R10) says what a genuinely new
animation would cost, for when a variation can't carry it.

| | Fixes | Jev passes |
| --- | --- | --- |
| R1 Room in the steering, and real words for the 29 slime moods | A1, C6 | ~0 |
| R2 The cuss, and a ladder of failure | A6 | ~20 |
| R3 Nature in the evals and the Examples | A8 | ~10 |
| R4 Variety inside `react`: the echo rule, the off die, the kind bump | A2, A7, B1, B2, C2 | ~40 |
| R5 Five new lines for the brain | A5, B1, B4, C5 | ~30 |
| R6 Idle and asleep life in both packs | A4, C1 | 0 |
| R7 Comedy on the finish, and bigger says for big holds | A4, C7 | 0 |
| R8 Ears | A3, A9, C4 | ~10, plus the owner |
| R9 Evals and the working day hold the fun | B3, C8, D | ~20 |
| R10 (only if needed) One new animation state | C3 | ~10 |

Everything above keeps "needs you" exactly as it is: a core rule, held
by the device over every reaction, with nothing but your words waking
the brain while it shows. Idle check-ins, heard words and the answered
line are gated by it like every other event.
