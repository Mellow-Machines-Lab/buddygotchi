# A product review of Boop v1, and ideas to make it better

Updated 2026-11-09. A review of branch `v1-polish` (`270ee70c`) as a buyer would live with it, against the four pillars of [v1-buddy.md](v1-buddy.md) §1. It changes no code. The brief is [product-review-prompt.md](product-review-prompt.md). What is next to build stays in [TODO.md](TODO.md); ideas that are not decided stay in [product-ideas.md](product-ideas.md).

## 1. Summary

**What was done.** I ran the Mac's 286 snapshots, the simulator's 23 scenarios, a headless day with real hook events on a simulated board, and the world's end-to-end test. I tallied nine earlier Jev runs (6,363 passes) to see what the brain really picks. The real panel was not used: the owner's app was connected to it. No Jev request was spent.

**The scores.**

| Pillar | Score | Why |
| --- | --- | --- |
| 1 Status monitor | 4 of 5 | Needs you, the finish and the work acts are clear and fun. Three bugs break the promise |
| 2 Friend | 3 of 5 | A rich engine, thin content, and off for a buyer with no key |
| 3 A buddy that grows | 2 of 5 | The ring fills in the first hour; the level counts days |
| 4 A world | 2 of 5 | Built and working, with no goal and nobody in it yet |

**The chain between the pillars is mostly on paper.** Work fills the ring too fast to mean anything. Care cannot move it. XP goes up to the world and nothing comes back.

**The five findings that matter most.**

1. **A buyer cannot give Boop a brain.** The key's card links to API docs, with no sign-up and no price. With no key there is no mood, no emotion and no reply. Yet the brain's picks are close to a table: a long finish is proud 89% of the time, a turn's start is nothing 146 times in 146.
2. **The ring closes at about 10:43 on a typical day,** because every call earns 1 XP. Then growth is silent, and care counts for nothing.
3. **Pillar 1 has three real bugs** that no eval sees: a third finish in a row is dropped; failed checks never reach the brain; gestures that arrive together can all be lost.
4. **The model is larger than what a buyer can see.** 13 of 42 emotions were never picked in nine runs. Five moods hold 77% of the time. Eight activities differ by one small picture. The Words table grew from 79 to 95 words since the last simplifying audit.
5. **The content is thin where it fires most.** 163 sign lines; two asks, both once-only; one line for the most common lock. A buyer hears repeats on day 1.

**The biggest simplification.** Seven moods and eighteen emotions, by an alias table first and deletion after a week (§8.3). With four activities, three tiers, three sizes, nine kinds of moment, one buddy, one board and a one-page Studio, it removes about 9,000 lines, 30 evals and 40 words, and it makes a rules brain a third of the work.

**The top three ideas.**

1. **A brain in the box** (§9.1): a rules brain built from the recorded runs, so every Boop has its personality with no key. Jev becomes a switch.
2. **Make the ring mean a day** (ideas 3.1, 3.4): a call earns 0, a ship earns 10, and `today's done!` is one real moment in the afternoon.
3. **The content pass in one voice** (idea 2.1): about 170 lines in the pack, asks that come back, and the code's signs moved into the pack.

**What the review asks of the owner.** Nineteen decisions are in §13. The first three: whether a buyer needs a key, whether the XP amounts may change, and whether the calls of 2026-11-01 on moods' fades, several buddies and the CYD may be reopened with the new evidence.

**How to read the rest.** §2 is a buyer's life in eight scenes. §3 scores each pillar. §4 checks the fundamentals. §5 to §7 are 69 ideas. §8 is the simplification, with numbers. §9 is five fundamental changes. §10 to §13 decide. §14 lists the evidence.
## 2. The buyer's life

Each scene is built from what I could run: the Mac's snapshots, the simulator's frames, a headless runtime with a scripted brain on a simulated board, and nine earlier Jev runs. Nobody has watched the real panel for this review (§14). Each moment has a mark: **delight**, **fine**, **flat**, **confusing** or **broken**.

### 2.1 Unboxing and onboarding

| Minute | What the buyer sees and hears | Mark |
| --- | --- | --- |
| 0 | They plug the board in before anything else. A blue slime rests with a small plug icon. After 5 minutes it sleeps. Nothing says "get the app" | **flat** |
| 1 | The app opens: "Hi! I'm a Boop." A big face, one button, "Hi, Boop!" (`onboarding-1-hello-light.png`) | **delight** |
| 2 | "I keep an eye on your agents": a small terminal, three cards, and "I only watch. I never approve, deny or block anything for you." | **fine**, and it earns trust |
| 3 | "What should I be called?" They type Mochi. A bubble says "Mochi! I love it." Small print: the name is for keeps, and other buddies will see it | **delight**, then a small worry: for keeps? |
| 4 | "Let's find my body." macOS asks for Bluetooth. Rings pulse. "Tap my screen on your desk": the board holds up "Tap me!" | **delight**: the first touch joins the two |
| 5–7 | "Here's how we get along": four lessons, a legend of four moods, a rule about moods. Lesson 3 is "hold my button and talk". Boop answers: "I'll answer once I have a brain, in a couple of steps." | **confusing**: the first time they talk to it, it cannot answer |
| 7–9 | "Which agents should I watch?" Then they must leave the window, open a terminal, start a new agent session and type a prompt. Then a 4-step tour | **fine** for a developer, but long |
| 9–10 | "A few small things": open at login, the microphone, and "Give me a brain: a Jev API key lets TypeSafe's AI pick how I react." A link goes to API docs | **broken**: there is no way to get a key from here, and no price |
| 10–11 | "I live in a world of buddies." Two lists: others see, nobody sees. "Keep Mochi private" or "Sounds good" | **fine**: plain, and nothing was sent before it |
| 11 | "Mochi is all set!" with four more tips | **flat**: the third time the same touches are taught |

**Net:** a warm start with the best writing in the product, about 10 minutes long, with one hole in the middle. A buyer with no key leaves onboarding with a Boop that watches and never feels.

### 2.2 The first hour with one agent

Assume the buyer has a key.

| When | What happens | Mark |
| --- | --- | --- |
| The prompt | A "NEW TASK" card; the desk and monitor slide in; an emotion for the prompt. With "still broken" in it: determined, "retry", the sign `still broken?!` | **delight** |
| Calls | Words fall past Boop: file names, searches. A failed call bonks it | **delight**: this is "fun to watch" |
| The tests run | Boop straps on a crash helmet and rides a sled at a wall. `running tests`, then `PASS` or `FAIL` | **delight**: the best 5 seconds on the board |
| The tests fail three times | The act shows `FAIL` three times. Boop has no feeling about it: the brain is never asked (`runtime.md`, bug 1; `Harness.swift:604`, `TranscriptView.swift:334-336`). The steering's whole "a wince, then it climbs" ladder does not run | **broken** |
| Minute 5, 10 | A working check-in: determined, a word about the work. Determined is 69% of these | **fine**, then **flat** by the third |
| The agent asks permission | The amber card: NEEDS YOU. A knock. A touch opens the session on the Mac | **delight**: this is the reason to own it. But the card does not say what kind of thing waits |
| The finish | A green rim, a trophy, the low sign `✓ api`. For a long turn: proud, 89% of the time | **delight** the first ten times, then **fine** |
| About minute 25 | The bar slides in at the top: "100 today", gold, a sparkle. Then `Level 2!`. "Today's done!" does not show: when a level comes with the ring, only the level plays (`Core.swift:523-525`) | **confusing**: done? after 25 minutes? One turn with 77 reads gave 82 XP in the test run |
| The rest of the hour | XP shows nothing more today | **flat** |

### 2.3 A busy workday

| When | What happens | Mark |
| --- | --- | --- |
| 09:30 | Three agents start. Three "NEW TASK" cards in 3 seconds. The strip says `✳3` | **fine** |
| 10:15 | One agent pushes. A rocket: `git push`, lift-off, orbit, `shipped!` | **delight** |
| 10:40 | Two agents need you. The card names one; the strip says `+1`. The button hands you the next | **delight** |
| 11:05 | Three turns end within 2 seconds. Two finishes play. The third, a 46-minute turn, is dropped as "late" and never shows (`BoopDevice.swift:36`; `headless.log` 21:14:08) | **broken**: principle 8 says finishes are never hidden |
| 11:30 | A turn fails. An irritated emotion, maybe a swear, aloud | **delight** alone; **broken** in a meeting |
| 13:00 | Back from lunch. A glad hello, bigger for the longer gap, with a fact about what finished | **delight**, but they still open the Mac to see which sessions ended |
| 14:00–17:00 | Long turns. The drawer (a swipe up) lists every agent. Pastimes: headphones on, a sip, a stretch | **fine**; the drawer is **delight** once found |
| All day | A boop from the world arrives in a batch with two others. If the third is over the hour's limit, none plays (`runtime.md`, bug 4) | **broken**, silently |

**Net:** on a busy day pillar 1 carries everything, and it is good. The friend, the ring and the world are nearly absent after 10:00.

### 2.4 Stepping away

| When | What happens | Mark |
| --- | --- | --- |
| A short lock | A small wave in silence. Each lock and each unlock is one brain request | **fine** |
| A lock while an agent works | A real wave, a word, the sign `i got this`. It is the only line in its section, so it is `i got this` every time | **delight** on day 1, **flat** by day 3 |
| Lunch | Nothing plays to an empty chair. Good. But an hourly check-in still asks the brain every hour while the Mac is locked (`headless.log` 21:15:39) | **fine** for the buyer; a cost for whoever pays |
| The end of the day | A night lock: a wave, "night night", the caption "10 turns today" in small grey text, and Boop naps | **delight**, but the day's summary is the smallest text on the screen |

### 2.5 The next morning

| When | What happens | Mark |
| --- | --- | --- |
| The first unlock after 5:00 | Boop wakes and greets you. The dream is told: "Mochi dreamed about Monday and Tuesday: you poked it once; 10 turns on "api", 1 failed." | **delight** in shape. **Confusing** in detail: it was one evening, not two days, and the 10 turns were on three threads (`MemoryReader.swift:254`) |
| The board's caption | "day 1: 1 failed" | **flat**: a day of 10 turns is summed up by its one failure (`MemoryReader.swift:262-267`) |
| After the greeting | Doing goes back to asleep, because no agent has worked for an hour. Strokes and words each get a moment, then Boop sleeps again | **confusing**: I'm here, why is it asleep? |
| A remembered line, about once a day | The low sign: a note in Boop's voice. Narration: "Mochi remembers you stay up late on Fridays." | **delight** if the note is true. Unknown: no real week has run through the writer |

### 2.6 A week in

- **XP.** Level 5 or 6. On day 4 Boop grew to a Sprout: the stage ceremony is the one growth moment that feels earned. **Delight.**
- **The rings.** Seven circles on the Boop tab. Part-full ones are red (`boop-light.png`). The buyer learns that a ring is full on any day they used an agent for half an hour. **Flat.**
- **What Boop knows.** Three notes: "You work late most nights, and you say please to claude." If true, **delight**. If one is wrong, a cross forgets it; that is good design.
- **Repeats.** The two asks are long gone. They have seen `i got this` twenty times, proud at every long finish, and the same 17 pastimes about a hundred times a day each. **Flat.**
- **The world.** They opened the tab twice. It showed a few dots and "0 awake", because a buddy with no agent open counts as asleep (`Runtime+World.swift:44`). **Flat.**

### 2.7 A month in

- Level 20 to 25. One stage left, at 30. After it a level-up is `Level 31!` on the low sign for ever.
- 15 pastimes opened at level 15. The buyer may not notice: nothing says "new".
- The memory has perhaps 10 notes. This is the one part that can still surprise.
- The world has no goal, so nothing was reached together.
- **What keeps it on the desk:** needs you, the finish, the rocket. That is pillar 1, and it is enough reason to keep it plugged in. **What is missing:** any reason to look forward to tomorrow.

### 2.8 A quiet day with no agents

Five hours at the Mac with no agent open, run headless (`runtime.md`, scene f):

- Doing is asleep for all five hours. The rules make zero moments.
- The brain is asked six times: at 40 and 80 minutes, then hourly. In Jev's runs 58% of idle check-ins play nothing. So the buyer gets two or three small beats, or none.
- A stroke gets its answer, then Boop sleeps again.
- The world shows the buddy as asleep.

**Mark: flat.** On a day of meetings or writing, Boop is a sleeping slime. It does not earn its place. A clock on the hour, a musing every 45 minutes and an awake Doing while you are present would change that (ideas 2.5, 2.12).
## 3. The four pillars, scored

| Pillar | Score | In one sentence |
| --- | --- | --- |
| 1 Status monitor | **4 of 5** | Needs you, the finish and the work acts are clear and fun; three real bugs and an unreadable activity keep it from 5 |
| 2 Friend | **3 of 5** | A rich engine with thin content, shut off for any buyer without a key |
| 3 A buddy that grows | **2 of 5** | The ring fills in the first hour and the level counts days, so growth says "you used an agent" and nothing more |
| 4 A world | **2 of 5** | It is built and it works end to end, but it has no goal, shows an awake world as asleep, and reaches the board only if a stranger clicks your dot |

### 3.1 Pillar 1: status monitor — 4 of 5

**What delivers the promise.**

- Needs you cuts any moment at once, and a finish held under it plays after you answer (`headless.log` 21:10:08 to 21:10:20).
- A touch on a finish or on the needs-you card opens the session on the Mac (`open_thread (rule)`, 21:10:17).
- Doing, the activity, the to-do, the helpers and the tiers reach the board at once, by rule, with no brain (`runtime.md`, scenes a and c).
- The work acts (`sheets/gel-play.png`, row 4) and the work stream make watching fun. This is the product's best content.
- The drawer lists every agent (`sheets/gel-lane.png`, open).
- The Mac's Now tab is clear in every state, with needs you first (`sheets/now1.png`).

**Where it breaks, by how much a buyer feels it.**

1. **A third finish in a row is dropped.** A waiting moment lives 5 s and a finish plays about 5 s (`BoopDevice.swift:36`). With three agents this is weekly. It breaks principle 8.
2. **Failed checks get no feeling.** `tool_end` is passed over for the newer `act_end`, which is then held (`Harness.swift:604`, `TranscriptView.swift:334-336`). Eval `04-tests-fight-back` passes only because evals make no act events.
3. **The activity cannot be read** from a chair (§4.1).
4. **Needs you does not say what kind.**
5. **Working at night is 21 fps.**
6. **The strip's codes** need learning.
7. Small: a failed turn gets no word in the work stream; the word for `git push origin fix-nav` was "origin"; a stopped turn says "no tool calls" after one.

**The question the buyer can't answer:** "It needs me — for what? Is it a yes or no, or a page to read?"

**What we can't know without real use.**

| Question | Count that tells us | Exists? |
| --- | --- | --- |
| How fast do people answer when Boop knocks? | `answerMs`, in seconds | Yes, but printed in whole minutes ("0 min" for 44 s) |
| Do people open sessions from the board? | `threadsOpened`, split by finish and needs you | Partly |
| How many finishes are dropped? | finishes played against finishes sent | No |
| Are hooks silently broken? | days with you here and no hook event | No |
| How long does an agent wait on a person a day? | needs-you seconds a day | No |

### 3.2 Pillar 2: friend — 3 of 5

**What delivers the promise.**

- The morning: a greeting, the dream told once, the ring back at 0 (`headless.log` 21:15:49).
- Lock and unlock each get a moment with a plain reason; a night lock says the day's turns.
- A touch is answered on the board in 75 ms, in the mood; eyes follow a finger; a held finger makes it lean and doze.
- Every moment has narration; "X is calm" on the Mac explains the mood when a reason is kept.
- The memory is on the Mac, readable, with a pin and a cross on every note (`sheets/boop.png`).
- The owner's own proof: determined and "retry" at "this doesn't work".

**Where it breaks.**

1. **No key, no friend.** Mood, emotion and reply all need Jev, and a buyer cannot get a key (§4.6).
2. **Thin content.** 163 sign lines. Two asks, both once-only. One line for the lock you make most. 72 of 146 lines never showed in nine runs.
3. **Idle is silent.** 96 of 166 idle check-ins play nothing, and with no agent Boop is asleep while you sit there.
4. **Notices are faint and read as reports.** 13 of 17 were "claude sits idle". `stretch` and `rough` chose no sign and no emotion.
5. **One emotion per slot.** Proud at 89% of long finishes; 34 to 45% of emotions repeat the one before.
6. **The dream's sentence is wrong in two ways** (all turns on the top thread; two days for one evening), and the morning's caption picks the failure.
7. **Three registers** across signs, voice and the code's strings.
8. **Two narrations scold.**
9. **The memory writer has never seen a real week.**

**The question the buyer can't answer:** "Does it know me, or does it say that to everyone?"

**What we can't know without real use.**

| Question | Count | Exists? |
| --- | --- | --- |
| Do people talk to it after week 1? | push-to-talk uses a day | No |
| Do people touch it with no wish open? | `touchesNoWish` | Yes |
| Which touches? | touches by kind | No: a stroke and a shake both count 1 |
| Are wishes met or left? | `wishesMet`, `wishesGaveUp`, `wishWaitMs` | Yes |
| Is it too loud or too quiet? | `hushes`, `quiet`, `volume`; moments played by kind | Half |
| Do notes survive? | notes pinned and forgotten a week | No |
| Do asks get answered? | asks shown, answered, ignored | No |

### 3.3 Pillar 3: a buddy that grows — 2 of 5

**What delivers the promise.**

- The model is simple and pinned by tests: fixed XP, one cap, never down (`Growth.swift`, `GrowthTests.swift`). XP for each source matched the plan when measured live (`runtime.md`, scene e).
- The bar, the gold fill, the heart from a met wish and the stage ceremony are good on screen (`sheets/gel-v1.png`).
- A level-up and the ring wait while something needs you (`headless.log` 21:10:52 to 21:10:57).
- The Boop tab's words are warm: "82 today. Fill the ring and you're done for the day."

**Where it breaks.**

1. **The ring closes before lunch for anyone who uses agents.** A call earns 1 XP. A typical day (30 turns, 400 calls) offers 523 XP and closes the ring at about 10:43. A heavy day closes it at 09:30. 83% of XP is thrown away by the cap (`runtime.md` §2).
2. **Care does not count.** A devoted day of care is about 57 XP, but the ring is already full. Care changes the result only on days under about 8 turns. A met wish, the largest care reward, then shows nothing in growth.
3. **The level is a count of days.** A full ring is a level. So the level says how many days you used an agent. After level 30, about week 6, a level-up is a number.
4. **"Today's done!" never plays for the regular buyer.** When a level comes with the ring, only the level's moment plays (`Core.swift:523-525`). For a buyer who fills each ring, the 100th XP is always also a level.
5. **A level-up cut by needs you is gone.** It is marked as played when it starts (`GrowthStore.swift:118-131`; `care-live.log` 12:29:54).
6. **The level-up is sent twice** (`Runtime.swift:792-811`). Only timing hides the copy.
7. **Odd rules.** A shake and a wrong-way stroke earn 3 XP each; a poke earns 0 (`Touch.swift:24-28`, `Growth.swift:68`). 34 shakes close the ring in 2 minutes.
8. **Red rings** for part-full days, and "XP" in a UI whose rule bans game jargon.
9. **No demo and no eval** shows growth.

**Is the chain real?** Work feeds growth too well: any work at all fills it. Care does not feed growth in practice. So the first two links are, in turn, saturated and on paper.

**The question the buyer can't answer:** "What's the ring for? It's full by ten, whatever I do."

**What we can't know without real use.**

| Question | Count | Exists? |
| --- | --- | --- |
| When does the ring close? | hour of the day the ring closed | No |
| How much XP is work, how much care? | XP by source, and XP past the cap | No |
| Was the level-up seen? | level-ups played, cut | No |
| Does anyone open the Boop tab? | tab opens a week | No |

Only `level` is counted today.

### 3.4 Pillar 4: a world — 2 of 5

**What delivers the promise.**

- It works. `world_e2e.py` against the local server passes: two buddies join, see each other, boop, wave and leave, and nothing stays (`runtime/world_e2e.txt`).
- Privacy is designed in: the server refuses any key it does not know, nothing is sent before the world's screen, and off deletes the buddy.
- A boop on the board is charming: a bounce, `boop back!`, "Someone in Asia or Oceania booped Rex." (`world-recv.log` 12:21:59; `sheets/gel-v1.png`).
- Gestures wait under needs you and at night, and come back as one line.
- The World tab is calm and handles off, joining, stale and unreachable (`sheets/world.png`).

**Where it breaks.**

1. **There are no goals.** The promise is "together they reach goals". Goals were switched off on 2026-11-08. The tab has three numbers and a band of dots.
2. **An awake world reads as asleep.** A buddy with no agent open is "asleep" (`Runtime+World.swift:44`). Three buddies at their Macs showed `"awake":0`. A small world will say "0 awake" most of the time.
3. **The world reaches the board only when a stranger opens a tab and clicks your dot.** At launch that is nobody.
4. **Gestures in a batch can all be lost** when the last is over the limit; and two in one reply make one moment (`WorldGestures.swift:47-51`, `Harness.swift:604`).
5. **A cheer can hardly happen.** The button shows only while the push command runs, about 10 s, and the tab polls every 30 s (`WorldPane.swift:105`).
6. **A cheer needs no ship.** The board said `we shipped!` for a buddy that pushed nothing (`app.ts:285-309`).
7. **"While you were away"** is said for gestures held at night or under needs you, when the buyer was there.
8. **Abuse.** Three throwaway buddies can hide any name. The world's list is public with names and live activity. The level is self-reported up to 1,000,000. The name filter misses look-alike letters.
9. **The server is a personal hostname.**
10. **Your XP goes up and never comes back.** Nothing shows what you added.

**Does the world hold the other three together?** Not yet. It is a fourth tab. It shares the buddy's name and level with the others and takes nothing back into the day.

**Does status still outrank?** Yes. Gestures waited under needs you in every run, and a world moment is queued like any other. The risk is the other way: world moments are the first to be dropped.

**The question the buyer can't answer:** "Who are these dots, and what do we do together?"

**What we can't know without real use.** Nothing about the world is counted today. Needed: world on or off; World tab opens; gestures sent, received, played, held and dropped; cheers; the world's size at each open.

### 3.5 The seams

| Seam | Verdict | Evidence |
| --- | --- | --- |
| Work feeds growth | Real, and saturated. The ring cannot tell a good day from an hour | 523 XP offered on a typical day against a cap of 100 |
| Care feeds growth | On paper | The ring is full before care arrives; pokes earn 0, shakes 3 |
| Growth feeds the world | On paper | `xp_today` is sent; the World tab never shows your part; no goal uses it |
| The world feeds the friend | Weak | One sign section of 2 lines per gesture; nothing in the morning |
| Status outranks everything | Holds against the world and growth. Fails against itself: a third finish is dropped | `headless.log` 21:10:52, 21:14:08 |

**The chain in one line:** today it is 1 → (3, in an hour) and then nothing. Ideas 3.1, X2, 4.1 and 4.2 are the four changes that make each link real.
## 4. The fundamentals

### 4.1 Clarity at a glance

Judged on the simulator's frames at 320 × 240 (`/tmp/boop-review/sheets/`). The real panel was not used (§14).

| What | One second, arm's length? | Evidence |
| --- | --- | --- |
| Needs you | **Yes.** An amber card, the largest text on the board, and the session's name in the strip | `gel-states.png` (needs_you), `gel-lane.png` |
| A finish, done or failed | **Yes.** A green or red rim, a tick or a cross, the thread's name | `gel-lane.png` (finish-success, finish-failure) |
| Working or resting or asleep | **Yes.** The desk and monitor appear; eyes close | `gel-states.png` |
| Which activity | **No.** Eight activities differ by one small picture on the monitor | `gel-states.png` (testing, terminal, tool_use, searching) |
| How many agents | **Partly.** `✳2 ●●●● z1 3/7` is four codes in one line | `gel-lane.png` (working-counts, working-todo) |
| Why Boop did that | **No.** The narration's caption is small grey text on the last line | `gel-states.png` (poked: "you poked Boop"), `gel-v1.png` |
| The ring | **Partly.** The bar reads; "49 today" beside it is small; "Today's done!" is the caption size | `gel-v1.png` (ring-closed) |
| Boop's mood | **Partly.** Happy, cross, sad and asleep read. Most of the 42 emotions do not (§8.2) | `gel-moods.png` |
| A work act | **Yes, and it is the best thing on the board.** | `gel-play.png`, row 4 |

Two fixes carry most of this: four activities with body-size props (idea 1.2), and important words on a sign, never in the caption (ideas 3.4 and 2.4).

### 4.2 Feel

All numbers are from `plan/TODO.md` (2026-11-04), measured with the owner's Mac connected, so none is proven.

- **Frame rate.** Idle 41 fps. Working 34 by day against a budget of 30. Working at night 21: under budget for every evening session (idea 1.12). Short dips to 12 to 20 fps in the stage ceremony, the parade and the rocket's lift-off.
- **Touch latency.** The board's own press is 75 ms. That is good. The Mac's answer to a touch is a Jev request away, so the second half of a touch's answer comes 1 to 3 s late or not at all.
- **How long moments last.** A finish's sign lingers 5 s; a touch's caption 2.5 s; the bar "a few seconds". These feel right in the frames. Only the panel can say.
- **Repetition.** This is the weak point. A pastime is dealt every 11 s from 17 that a new buyer sees in a day, so each one shows about 100 times a day. In Jev's runs 34 to 45% of emotions repeat the one before. The busiest sign sections have one line (§3, pillar 2).

One passive reading from the real board during this session: `boopctl ping` gave `fps: 34`, `heap: 143528` while Doing was working with 5 helpers (my own research agents, seen through the owner's app).

### 4.3 Personality

- **Is the cheek consistent?** In the signs, yes: `still broken?!`, `so cute lol`, `i got this`. Across channels, no. The voice says "Jawohl", "Debrief" and "Tadaima"; the code's signs say "Level 12!" and "Happy Halloween!" (words report, §B6). Three writers are audible.
- **Does it repeat?** Yes, by day 1 for the sections that fire most (`[bye working]`, the tone templates, `[carry_on]`), and asks stop for good after two answers.
- **Too quiet or too loud?** Too quiet when idle: 96 of 166 idle check-ins played nothing. `personality.md:33` asks for exactly that ("mostly gets nothing"). Too flat at finishes: proud at 89% of long ones. And possibly too loud in one way: it can swear aloud with no warning.
- **Does it scold?** The steering says never. Two narrations do: "You've been here 3 hours and haven't touched it." (`Narration.swift:153`) and "Mochi wished for a chat, and you left it." (`Narration.swift:114`).

### 4.4 Words

The Mac's words are mostly warm and short. Onboarding's first-person voice is the best writing in the product ("Mochi! I love it.", "Feed me an update?"). The weak strings fall into four groups: the brain (Jev, TypeSafe, API key), the agents (hooks, sessions), the board (firmware, `voice.bin`, FAT32, simulator) and trouble notices. One thing has several names:

| Thing | Names a buyer reads |
| --- | --- |
| One conversation with an agent | Sessions, thread, agent |
| The hardware | my body, the board, Device, my Boop |
| The brain | brain, Jev, Jev API key, TypeSafe's AI, TypeSafe |
| Not working | idle, Resting, resting |
| Silence | Hush, Hushed, Quiet, Muted, Off |
| Growth | XP (which the UI's own rule calls game jargon), level, ring, today |

The full table of strings, with 25 rewrites by file and line, is in `/tmp/boop-review/words.md` (§A and §H). The best of them are in the quick wins (§11).

### 4.5 Trust

- **The world.** Nothing is sent before onboarding's world screen: true in code (`OnboardingModel.swift:404`, `Runtime+World.swift:104`). The screen says "Counts, like tests passed". The code sends five counts (turns, tests passed, ships, lines changed, today's XP), and also the stage and the local date (`WorldWire.swift:90-104`). Nothing sensitive is hidden, but "Nothing about you or your code" (`SettingsPane.swift:81`) is too strong: the activity and the offset say when you are at your desk. "Nobody sees: your name" is false if the buddy has your name, and the name cannot be changed.
- **The brain.** "Never your code" is true. Not said: up to 3 phrases of 18 characters copied from each prompt, project and thread names, and what Boop noticed about your habits also go to Jev (`PromptReading.swift:62`, `EventLine.swift:343`, `Notices.swift:114-139`).
- **Consent is plain enough** for the world, and one truthful sentence short for the brain. A rules brain (§9.1) removes the second problem.
- **The server's address** is a personal Vercel name (`WorldClient.swift:8`).

### 4.6 First-run risk: what could send it back in week one

Ranked by how likely and how bad.

1. **No brain.** The buyer cannot get a Jev key from the app. Boop then has no mood, no emotion and no reply. They bought "a personality of its own" and got a status light.
2. **Bluetooth.** Onboarding handles "off" and "refused" well. But a board that pairs once and then drops has no recovery story a buyer can follow; the Settings text talks of firmware and reconnect. Not measurable here.
3. **The voice card.** "No card" after a warm reset is a known fault (the owner's own note: unplug the board). The message sends the buyer to text about `voice/voice.bin` and FAT32.
4. **A swear in a meeting,** or any sound at all in a call (ideas 2.11, 1.8).
5. **Onboarding's length:** 9 acts, 8 to 12 minutes, one trip to a terminal.
6. **A flat day two.** The ring closed at 10:00, the two asks are used up, the same `i got this` at each lock, an empty world. Nothing is broken, and nothing is new.
7. **Agents the buyer does not use.** A buyer on Cursor or Copilot sees "Not found on this Mac" twice and has no product.
## 5. Ideas, by pillar

Each idea has the same fields. **Size:** S is under a day, M is a few days, L is a week or more. **Conf.** is my confidence that the idea is worth its size. "From the list" means the idea builds on `plan/product-ideas.md`. Sign texts are 18 characters or fewer.

### Pillar 1: status monitor

**1.1 Needs you says what kind** · S–M · conf. high · from the list (Maybe)
- **The moment:** an agent starts to wait for you.
- **Sees and hears:** the amber card's second line changes from "Continue on your Mac" to one of three: `say yes or no`, `a question`, `a plan to read`. The Mac's needs-you card gets the same three words. The voice does not change.
- **Why:** today the buyer cannot tell a 2-second approval from a 5-minute plan review. This is the most frequent "what do I do now?" in pillar 1.
- **Principles:** status outranks everything; nothing to teach; only the kind leaves the hook, never the command.
- **Where:** `agent-hooks` (the request's kind), `app/BoopKit/Core/Core.swift` and `StateSnapshot.swift` (`attn`), the gel's needs-you card (`render/gel/props.cpp`), `app/Boop/Views/OverviewPane.swift`.
- **Works if:** a demo step for each kind; a simulator golden; a new daily count, the median wait by kind.
- **Risk:** Codex may not give the kind. Fall back to today's line.

**1.2 An activity you can read from your chair** · M · conf. medium
- **The moment:** always, while Doing is working.
- **Sees and hears:** today the eight activities differ only by a 30-pixel picture on the small monitor (`/tmp/boop-review/sheets/gel-states.png`). Merge them to four on the board (§8.3) and give each a prop at body size: typing (keys only), testing (the crash helmet from the tests act, worn small), looking (a magnifier held up), waiting (chin on the desk). No words.
- **Why:** "at a glance" is the promise of pillar 1. Today a glance says "working", not how.
- **Principles:** the small screen stays clear (props replace, they do not add).
- **Where:** `firmware/src/render/types.h`, `render/gel/pastimes.cpp` (kit), `rig/looks.json`, `app/BoopKit/Core/Activity.swift`.
- **Works if:** the owner names each activity from 80 cm in a blind test of 8 frames, 7 of 8 right.
- **Risk:** frame cost of a prop while working (budget 30 fps; working is 34 by day).

**1.3 The long-turn clock** · S · conf. medium · from the list (Maybe)
- **The moment:** a turn passes 10 minutes (tier 5), then every 10 minutes.
- **Sees and hears:** the low sign shows `api · 14m` for 3 s. No voice, no emotion.
- **Why:** on a long turn the board looks the same at minute 11 and minute 40.
- **Principles:** shows, then goes. The thread's name already shows on the low sign at a finish.
- **Where:** `app/BoopKit/Core/Core.swift` (a rule moment), `render/gel/low_sign.cpp`.
- **Works if:** eval `18-long-grind` gets a visible beat; count: long turns a day.
- **Risk:** noise when four agents run long. Show only the longest turn.

**1.4 Stuck sense** · M · conf. medium · from the list (Maybe)
- **The moment:** the same check fails 3 times in a row in one turn.
- **Sees and hears:** an uneasy emotion, small; sign `stuck?`; the Mac's row gets a "stuck" chip. Once per turn.
- **Why:** this is the moment a person wants to step in. Boop becomes useful, not only cute.
- **Principles:** only reports; never blocks. The run counter exists in `TranscriptView`.
- **Where:** `app/BoopKit/Core/TranscriptView.swift` (runs of failing checks), `signs.md` (`[stuck]`), `OverviewPane.swift`.
- **Works if:** a scripted eval; count: stuck moments a week and whether a prompt followed within 2 minutes.
- **Risk:** false alarms on test-driven work. Start at 4 failures.

**1.5 Out of juice** · S–M · conf. low · from the list (Maybe)
- **The moment:** a turn fails with the usage-limit class.
- **Sees and hears:** Boop slumps (the wish's `slump` art), sign `out of juice`. Narration: "Claude hit its limit."
- **Why:** a silent stall is the worst status failure. The buyer finds it 20 minutes late.
- **Where:** `agent-hooks` (error class), `Core.swift`, `signs.md`.
- **Works if:** eval `03` extended; the owner confirms the class on a real limit (unconfirmed today).
- **Risk:** the class may not arrive. Do not build before one real sighting.

**1.6 The strip in words** · S · conf. medium
- **The moment:** the strip shows counts.
- **Sees and hears:** `✳2 ●●●● z1 3/7` becomes `2 working · 1 resting` when it fits, and the to-do stays `3/7`. Helpers show as small dots on the monitor, not in the strip.
- **Why:** four icon dialects in 300 pixels need teaching. The ground rule says nothing is taught.
- **Where:** the gel's strip (`render/gel/layers.cpp`, `firmware/src/app/behaviour.cpp`).
- **Works if:** a golden; the owner reads it at arm's length.
- **Risk:** width with 3 states. Fall back to chips over 22 characters.

**1.7 What happened while you were away** · M · conf. high
- **The moment:** you come back after 10 minutes or more, and 2 or more turns ended.
- **Sees and hears:** after the greeting, the low sign shows each finish for 2 s: `✓ api`, `✓ landing`, `✗ docs`. A touch on one opens that session. Failures come first. At most 4, then `+3 more`.
- **Why:** today coming back gives one greeting with a fact. The buyer still opens the Mac to learn what ended. This is pillar 1's best moment for a person who steps away.
- **Principles:** status first; uses the low sign and the finish's touch-to-open.
- **Where:** `Core.swift` (the rule at presence), `Notices.swift` (the fact exists), `render/gel/low_sign.cpp`, `done.cpp`.
- **Works if:** demo `back-from-lunch`; count: sessions opened from the board within 30 s of coming back.
- **Risk:** it delays the greeting's warmth. Keep the greeting first and short.

**1.8 Quiet on calls** · M · conf. high · from the list (Maybe)
- **The moment:** any app uses the Mac's microphone or camera.
- **Sees and hears:** the voice waits; needs you is the amber card only; a small phone-receiver mark in the strip. Voice comes back when the call ends.
- **Why:** a "Fuck" or a "Yay" in a client call is a return-the-product moment.
- **Principles:** Boop does not open the mic; it reads only "in use" from CoreAudio and CoreMediaIO.
- **Where:** a new `app/BoopKit/Presence/` source, `Core+Hush.swift` (a hush with a cause), `Tags.swift`.
- **Works if:** unit test with a fake source; count: calls a day, hushes made by hand during calls (should fall to zero).
- **Risk:** apps that hold the mic all day. Treat more than 3 hours as "not a call".

**1.9 Covers its eyes** · M · conf. medium · from the list (Wild)
- **The moment:** a call of a risky kind starts (`rm -rf`, a force push, `DROP TABLE`), sorted on the Mac.
- **Sees and hears:** Boop covers its eyes with both hands for the length of the call, peeks at the end. No sign, no voice.
- **Why:** fun to watch, and it carries real status: "something risky runs now".
- **Principles:** only the kind reaches the board and Jev. Never blocks.
- **Where:** `app/BoopKit/Core/WorkStream.swift` (a call style), `render/gel/stream.cpp`.
- **Works if:** a demo; count: risky calls a week.
- **Risk:** it could read as a warning Boop is responsible for. Narration says only "A risky command ran."

**1.10 A pull request is an act** · M · conf. medium
- **The moment:** `gh pr create` or a deploy command runs.
- **Sees and hears:** a third work act beside push, tests and build: Boop seals an envelope and posts it; low sign `PR sent!`.
- **Why:** work acts are the product's best content (`gel-play.png`, row 4). There are only three.
- **Where:** `Core/WorkStream.swift` (the act's rule), `render/gel/act.cpp`, `character.json` `acts`.
- **Works if:** a demo recording; 30 fps in the act.
- **Risk:** `act.cpp` is already 1,133 lines for 3 acts. Make an act a data file in the pack first.

**1.11 The board says what to do with no Mac** · S · conf. high
- **The moment:** Doing is no app for more than 30 s.
- **Sees and hears:** a sign once: `open Boop on Mac`. Then the small plug as now.
- **Why:** a buyer who plugs in before installing sees a resting slime and a plug icon. Nothing says what to do.
- **Where:** `firmware/src/app/behaviour.cpp`, the pack's no-app art.
- **Works if:** golden `alone/hello.png` with the sign.
- **Risk:** none.

**1.12 Working at night at 30 fps** · M · conf. high
- **The moment:** working with the `night` tag.
- **Sees and hears:** the nightcap stays; the pyjamas go while Doing is working.
- **Why:** measured 21 fps against 34 by day (`plan/TODO.md`, 2026-11-04). The outfit costs 15 to 18 ms a frame.
- **Where:** `firmware/src/render/tags.cpp` (dressing rules), `render/gel/layers.cpp`.
- **Works if:** `boopctl perf --scenes` with the Mac off.
- **Risk:** the look is a little less cosy.

**1.13 First-time hints on the board** · M · conf. high
- **The moment:** the first finish, the first needs you, the first time 3 agents are open.
- **Sees and hears:** one small sign each, once ever: `tap me to open`, `tap: go to it`, `swipe up: all`. The pack already does this for wishes (`wish_how`).
- **Why:** it lets onboarding lose act 5's lessons and act 6's tour (§8.6). The screen says what to do at the moment it matters.
- **Where:** `KeyValueStore` (done-once keys), `Core.swift`, `signs.md` (`[how …]`).
- **Works if:** count: touches on a finish in week 1, with and without the hint.
- **Risk:** a hint over a first big finish. Show it after the finish's sign.

**1.14 "Waited on you" as a number** · S · conf. medium · from the list (Maybe)
- **The moment:** the Now tab, any time.
- **Sees and hears:** one line under the sessions: "Your agents waited 14 min for you today."
- **Why:** it is the one number that proves pillar 1's value, to the buyer and to us.
- **Where:** `Memory/DailyCounts.swift` (new: needs-you seconds), `OverviewPane.swift`.
- **Risk:** it can read as a scold. Words stay neutral; never on the board.

### Pillar 2: friend

**2.1 The content pass: 170 more lines, one voice** · M · conf. high
- **The moment:** every sign, reply, ask, wish and dream.
- **Sees and hears:** more lines, all in the pack's lowercase, teasing register. `[bye working]` gets 6 lines, not 1. `[notice waiting]` changes from a report (`claude sits idle`) to cheek (`claude's all urs`). The code's Title-case signs (`Level 12!`, `Today's done!`, `Happy Halloween!`) move into the pack as `[level]`, `[ring]`, `[day …]`.
- **Why:** the pack has 163 sign lines. 72 of 146 never showed in 9 Jev runs, and the ones that fire most have 1 line each (words report, §B7). A buyer hears the first repeat on day 1.
- **Principles:** what Boop says stays data in the pack.
- **Where:** `characters/boop/steering/signs.md`, `replies.md`, `asks.md`, `dreams.md`; `app/BoopKit/Core/Core.swift:534-537`, `Days.swift:27-99`.
- **Works if:** `boopdev eval --only` on 8 scenarios (about 40 requests); a count across runs of distinct signs shown.
- **Risk:** more lines for Jev to read. Keep the offer to 6 lines by tag, as now.

**2.2 Asks that come back** · S–M · conf. high
- **The moment:** an idle check-in, at most 3 a day (the rule exists).
- **Sees and hears:** today there are 2 asks, both `keeps`, so asks end for good on day 1 or 2. Add 20: some once (`fav snack?`), some monthly (`tabs or spaces?`), some daily (`good day?` with `yep` / `meh`). The answer goes to the digest; a `meh` makes tomorrow's greeting softer.
- **Why:** an ask is the only two-way moment that needs no microphone. It also earns 5 XP, so care can matter.
- **Where:** `asks.md`, `app/BoopKit/Outputs/Asks.swift` (a `daily` and a `monthly` class beside `keeps`).
- **Works if:** count: asks shown and answered a day (exists: answered asks).
- **Risk:** nagging. An ask never needs a reply, and none on Quiet.

**2.3 Agent-isms** · S · conf. high · from the list (Wild)
- **The moment:** a finish whose reading is fawning, grovelling or over-cheerful.
- **Sees and hears:** "You're absolutely right!" gets a skeptical emotion and the sign `suuure`. "I apologize for the confusion" gets a pat (`there there`). "Perfect!" on a failed check gets a side-eye.
- **Why:** this is the one joke every buyer already knows. It makes Boop a coworker on your side. The reading exists (`personality.md` names fawning).
- **Where:** `signs.md` (`[fawning]`, `[sorry]`, `[overjoyed]`), `MessageReading`.
- **Works if:** 3 feel evals; count: these signs a day.
- **Risk:** repeats fast. 5 lines per kind, and at most one an hour.

**2.4 Notices you can see** · M · conf. high
- **The moment:** a notice plays (at most 2 a day).
- **Sees and hears:** each notice gets its own pose, not "a small look". `stretch`: Boop does its own stretch-break pastime, looks at you, sign `stretch w/ me?`. `rough`: it leans close, sign `*hug*`. `late`: a yawn and `still up?`. `waiting`: it points down at the low sign, which names the session.
- **Why:** the judge found `stretch` and `rough` with no sign and no emotion (`plan/TODO.md:103`). A notice nobody can see does not exist.
- **Where:** `Core/Notices.swift`, `MomentOutput.swift:141-154` (make the sign a rule, not Jev's choice), `rig/clips/`.
- **Works if:** evals 179 to 186 must show a sign; count: notices played, and for `waiting`, sessions opened within a minute.
- **Risk:** nagging. Keep the caps; never on Quiet.

**2.5 A floor under idle** · S · conf. medium
- **The moment:** you are at the Mac, no moment has played for 45 minutes.
- **Sees and hears:** the rules (not Jev) play one small own beat: a musing with a sign, or a pastime that looks at you.
- **Why:** 96 of 166 idle check-ins played nothing, and 56 more were a sign with no emotion. On a quiet day Boop is a screensaver.
- **Where:** `TranscriptView.swift` (check-ins), `Signs` (`musingEveryMs`), `signs.md` `[idle]` (needs 20 lines first, idea 2.1).
- **Works if:** scenario `173-a-workday` shows 8 to 12 own beats in 8.7 hours.
- **Risk:** the owner asked for less idle noise on 2026-11-04. This is a floor, not more talk.

**2.6 The evening card** · M · conf. high
- **The moment:** the first lock after 17:00 that follows 4 hours of presence.
- **Sees and hears:** on the board: a wave, the sign `12 turns, 3 ships`, then the nap. On the Mac next morning: a "Yesterday" card on the Boop tab with the ring, the day's top moment and one sentence.
- **Why:** the day has a start (the greeting) and no end. A ritual at both ends is what brings a person back (§9.3).
- **Where:** `MomentOutput.swift:400-450` (lock questions), `replies.md` `[bye night]`, `app/Boop/Views/BoopPane.swift`.
- **Works if:** evals `135` to `140` family; count: evening cards played a week.
- **Risk:** a lock at 17:05 for a coffee. The 4-hour rule and once a day.

**2.7 A name you can change, a birthday you can give** · S · conf. high
- **The moment:** Settings.
- **Sees and hears:** "Rename Mochi" (the world gets the new name), and "Your birthday" (optional).
- **Why:** the name is "for keeps" and public. A typo stays for ever unless the buyer goes private. Your birthday is on the Maybe list and gives one sure delight a year.
- **Where:** `SettingsPane.swift`, `OnboardingIntro.swift:311`, `Days.swift`, `WorldLink`.
- **Risk:** name abuse in the world. The server's filter runs on rename; one rename a week.

**2.8 Yes, that's me** · M · conf. medium
- **The moment:** Boop holds up a remembered line (about once a day).
- **Sees and hears:** a stroke on the board pins the note; a swipe away forgets it. The Boop tab marks the note "Mochi brought this up today."
- **Why:** memory is the riskiest part of pillar 2: a wrong note feels creepy. This gives the buyer a one-touch correction at the moment the note shows.
- **Where:** `Memory/Memory.swift` (`felt`), `MemoryStore` (pin, forget), `firmware/src/app/device.cpp` (touch on the low sign).
- **Works if:** counts: lines shown, pinned, forgotten.
- **Risk:** a touch for another reason forgets a note. Only a swipe forgets.

**2.9 A hidden quirk** · M · conf. medium · from the list (Wild)
- **The moment:** set once at naming, from a seed.
- **Sees and hears:** one of six quirks: afraid of deploys, a neat freak, a night owl, hates Mondays, a drama queen, a foodie. Each is 8 lines of steering and 5 signs.
- **Why:** every Boop is the same slime today. A quirk makes "my Boop" true, and it gives the world something to show on a buddy's card.
- **Where:** `steering/quirk/*.md`, the prompt's PERSONALITY section, `character.json`.
- **Works if:** 6 feel evals.
- **Risk:** more steering text. It replaces the per-mood exit lists cut in §8.

**2.10 The mood always has a because** · S · conf. high
- **The moment:** the Now tab's mood card.
- **Sees and hears:** "Mochi is determined, since the tests failed twice." Never the bare "Mochi is determined."
- **Why:** 6 of 8 snapshots show the bare line (`sheets/now1.png`). It is the place a buyer looks to answer "why did it do that?"
- **Where:** `Narration.swift`, `MoodOutput.swift` (keep the event that moved the mood), `OverviewPane.swift`.
- **Risk:** none.

**2.11 A swear switch** · S · conf. high
- **The moment:** onboarding's small things, and Settings.
- **Sees and hears:** "Mochi may swear when things break" as a switch, off by default.
- **Why:** the bank has "Fuck" and "Shit". No screen says so. Only Talk: Quiet stops it.
- **Where:** `SettingsPane.swift`, `ContextSection.swift` (the Talk row), `MomentOutput.swift` (`say` options).
- **Risk:** the cheek gets milder by default. That is the right default for a shared desk.

**2.12 The hour, held up** · S · conf. medium · from the list (Wild)
- **The moment:** on the hour, with no agent working and you present; at most 4 a day.
- **Sees and hears:** Boop holds up `3 o'clock` for 3 s, with a small sound.
- **Why:** on a day with no agents Boop has no job. A desk clock earns its space.
- **Where:** `Core.swift` (a rule moment), `signs.md` (`[hour]`).
- **Risk:** it is one more own beat. It counts against idea 2.5's floor.

**2.13 Superstitions** · S · conf. medium · from the list (Wild)
- **The moment:** the tests act starts; a push starts on a Friday afternoon.
- **Sees and hears:** crossed fingers during tests (a hand pose over the act); on Friday after 15:00, the sign `on a friday?!` with a frightened emotion.
- **Why:** both are steering and one clip. Both are jokes a developer tells a friend.
- **Where:** `personality.md`, `signs.md`, `rig/clips/`.

### Pillar 3: a buddy that grows

**3.1 Make the ring mean a day** · S · conf. high
- **The moment:** every XP event.
- **Sees and hears:** nothing new. The ring fills over the working day, not in the first hour.
- **The change:** a call earns 0 XP. A turn that ends done earns 5, a helper 2, a ship 10 (new), a check that passes after failing 5 (new). Care stays as it is.
- **Why:** a call earns 1 XP today (`Growth.swift:53`). A turn with 40 calls earns 45 XP, so two long turns close the ring. Then, by design, XP shows nothing for the rest of the day, and care can never matter (§3, pillar 3).
- **Principles:** still one cap, fixed amounts, no bonuses.
- **Where:** `app/BoopKit/Core/Growth.swift:53-74`, `GrowthTests.swift`.
- **Works if:** the daily count "time the ring closed" has a median between 14:00 and 18:00 in the owner's own week.
- **Risk:** light users never close it. Check with the owner's counts before you choose the numbers.

**3.2 The ring is never red** · S · conf. high
- **The moment:** the Boop tab.
- **Sees and hears:** a part-full ring is blue (Boop's colour), a full ring green. In "The last 7 days", a part-full day is a soft grey-blue arc.
- **Why:** red rings read as failures (`sheets/boop.png`). The plan says "no sad Boop for an unfilled ring".
- **Where:** `app/Boop/Views/BoopPane.swift`, `Theme.swift`.

**3.3 The ring's two colours** · S · conf. medium
- **The moment:** the Boop tab, and the board's bar.
- **Sees and hears:** one ring in two tints: work (blue) and care (pink). Text: "82 today: 61 from work, 21 from you two."
- **Why:** it answers "what's the ring for?" and makes care visible without a second cap.
- **Where:** `GrowthStore.swift` (keep two sums), `BoopPane.swift`, the gel's `paintGrowthBar`.
- **Risk:** one more number. The plan asks for few numbers; show the split only on hover or click.

**3.4 "Today's done" as a real moment** · S · conf. high
- **The moment:** the ring closes.
- **Sees and hears:** the words move from the small grey caption to a sign Boop holds (`today's done!`, with 5 variations from the pack), and the gold bar stays 2 s longer.
- **Why:** the day's biggest growth moment is the smallest text on the screen (`sheets/gel-v1.png`, `ring-closed.png`).
- **Where:** `Core.swift:519-537`, `signs.md` (`[ring]`).

**3.5 The shelf** · L · conf. medium
- **The moment:** a level-up, a shiny moment (3.6), a first (first ship, first all-green day, first cheer from the world).
- **Sees and hears:** on the Boop tab, "Mochi's shelf": small keepsakes with a date. On the board, a keepsake shows for 3 s when it is earned, and now and then as an idle pastime (Boop looks at one).
- **Why:** levels are a count of full days. Nothing is earned at level 31 that was not there at level 2. A shelf gives "a month in" something to look at, and gives the world's card something to show.
- **Principles:** whole from day one (looks only); nothing is lost.
- **Where:** a new `Memory/Keepsakes.swift` (a list in the key-value store), `BoopPane.swift`, `render/gel/pastimes.cpp` (one pastime), `signs.md`.
- **Works if:** count: Boop tab opens a week (new count).
- **Risk:** it is a new concept. It replaces "stage" in the buyer's head, so cut the stage names from the UI.

**3.6 Shiny moments** · M · conf. medium · from the list (Maybe)
- **The moment:** about 1 finish in 200 plays a rare variation (a golden Boop, a tiny top hat).
- **Sees and hears:** the finish, with gold; narration "A shiny one!"; it goes on the shelf.
- **Why:** rarity is the cheapest reason to keep watching, and to show a friend.
- **Where:** the board picks variations (`render/gel/finish.cpp`); it reports the pick in `ended`.

**3.7 Words it learns** · M · conf. medium
- **The moment:** every 5 levels.
- **Sees and hears:** Boop says a phrase it has not said before, with the sign `new word!`; the Boop tab lists "Words Mochi knows: 34".
- **Why:** 266 of the bank's 486 texts were never heard in 9 runs, and 168 of 202 phrases. The content exists and is hidden. Growth can reveal it.
- **Principles:** whole from day one holds: words are moments, not features.
- **Where:** `Voice/Take.swift` (a level on a phrase), `takes.tsv`, `BoopPane.swift`.
- **Risk:** the phrases' register (idea 2.1). Pick the 40 best; drop the rest.

**3.8 Levels past 30** · S–M · conf. medium
- **The moment:** levels 50, 100, 200, 365.
- **Sees and hears:** not a bigger body. A mark: a small glint at 50, a soft aura at 100, a tiny crown at 365. The day's greeting says it.
- **Why:** the last stage comes at level 30, about day 30 to 45. After that a level-up is the same low sign for ever.
- **Where:** `Growth.swift:38-40` (`stages`), `Tags.swift`, `render/gel/layers.cpp`.

**3.9 Swipe down for the ring** · S · conf. medium
- **The moment:** a swipe down from the top edge, any time nothing needs you.
- **Sees and hears:** the bar and "54 today · level 12" for 3 s.
- **Why:** after the ring's moment passes, the board cannot be asked. A swipe up opens the drawer; a swipe down is its twin.
- **Where:** `firmware/src/app/touch_gesture.cpp`, `growth_bar.cpp`.
- **Risk:** it must be found. Hint once (idea 1.13).

**3.10 Hatching** · M · conf. medium · from the list (Maybe)
- **The moment:** first power, before the app has named it.
- **Sees and hears:** an egg that wobbles when the Mac finds it, and hatches when you press "That's me".
- **Why:** the unboxing has no moment today: the board shows a resting Boop before you have met it.
- **Where:** `firmware/src/app/behaviour.cpp` (no app, never named), a gel clip, `OnboardingBoard.swift`.

**3.11 A week you can read** · M · conf. medium
- **The moment:** the Boop tab's "The last 7 days".
- **Sees and hears:** each day's ring with one small icon for its top moment (a rocket, a trophy, a heart). A click shows one line: "Thursday: 3 ships, and you fixed api."
- **Why:** seven circles say little. The digest already holds each day.
- **Where:** `BoopPane.swift`, `Memory/MemoryReader.swift` (the digest).

**3.12 Growth in the demos and the evals** · S · conf. high
- **The moment:** none for the buyer.
- **The change:** demos send `xp`; 5 scripted evals pin the ring, a level-up, a held level-up under needs you, and the stage ceremony.
- **Why:** growth has 0 evals and no demo (`plan/TODO.md:285`). A pillar with no demo breaks the ground rule.
- **Where:** `app/BoopKit/Demo/`, `characters/boop/evals/`, `characters/boop/demo/`.

**3.13 The bug jar** · M · conf. low · from the list (Wild)
- **The moment:** a check that failed passes.
- **Sees and hears:** a small bug drops in a jar beside Boop; the jar shows on the shelf with the week's count.
- **Why:** it turns failures into a collection.
- **Risk:** one more prop on a small screen. Only as a keepsake of the shelf.

### Pillar 4: a world

**4.1 Turn the world goal on** · M · conf. high
- **The moment:** a month's goal, set on the server. It is reached, or it is not.
- **Sees and hears:** the World tab: "This month: 10,000 tests passed together. 7,420 so far. Mochi added 340." When it is reached: one ceremony at the next quiet moment, a party hat for 3 days (the dressing exists), and a keepsake.
- **Why:** the pillar's promise is "together they reach goals". Goals were switched off on 2026-11-08 (`plan/world.md` §9). Without them the world is a scatter of dots.
- **Principles:** cooperative; no XP bonus; one goal at a time.
- **Where:** `internal/world/src/app.ts` (the routes exist), `World/WorldWire.swift`, `WorldPane.swift`, `Tags.swift`.
- **Works if:** the e2e script reaches a goal; count: World tab opens a week.
- **Risk:** a goal no small world can reach. Size it from last month's total.

**4.2 "Mochi added 82"** · S · conf. high
- **The moment:** the World tab.
- **Sees and hears:** one line under the numbers: "Mochi added 82 XP and 14 tests today."
- **Why:** the chain from pillar 3 to pillar 4 is on paper only. XP goes to the server and comes back nowhere.
- **Where:** `WorldPane.swift` (the counts are local).

**4.3 The world in the morning** · S–M · conf. high
- **The moment:** the day's greeting.
- **Sees and hears:** one fact for the telling: "214 buddies were up while you slept." or "The world passed 9,000 tests." Narration only, or a sign `world's busy!` once a week.
- **Why:** the world exists only while the World tab is open. This puts it in a moment the buyer already has.
- **Where:** `WorldLink.swift` (one fetch at the first unlock), `ContextSection.swift`.
- **Risk:** a fetch with the tab shut. One a day, and none with the world off.

**4.4 Boop back** · S–M · conf. high
- **The moment:** a boop from the world plays; Boop holds up `boop back!`.
- **Sees and hears:** a poke within 10 s sends a boop to the sender. The sign changes to `sent!`.
- **Why:** the sign already says "boop back!" (`v1/boop.png`), but the buyer must open the Mac, open the World tab and find a dot. The obvious touch should do the obvious thing.
- **Where:** `Runtime+World.swift`, `WorldGestures.swift` (the sender's id is in the event), `device.cpp`.
- **Risk:** a boop loop between two desks. The server's send limit holds it.

**4.5 An honest small world** · S · conf. high
- **The moment:** fewer than 30 buddies in the world.
- **Sees and hears:** "It's early. 6 buddies so far, and Mochi is one of the first." A "first 1,000" mark on those buddies' cards for good.
- **Why:** at launch the tiles will read "3 awake, 1 coding, 12 tests today". The fixture's "214 awake" hides this.
- **Where:** `WorldPane.swift`, `internal/world/src/world.ts` (a `founder` flag by join order).

**4.6 Who is shipping now** · S · conf. medium
- **The moment:** the World tab, when a buddy ships.
- **Sees and hears:** a row above the band: "Bean is shipping. Cheer?" with one button.
- **Why:** Cheer shows only on the card of a dot that is shipping. Nobody will find it.
- **Where:** `WorldPane.swift`, `WorldBand.swift`.

**4.7 A legend, or no colours** · S · conf. high
- **The moment:** the band.
- **Sees and hears:** five small words under the band in the dots' colours (coding, testing, shipping, waiting, resting), or all dots in one colour with only asleep dim.
- **Why:** seven colours with no key (`sheets/world.png`).
- **Where:** `WorldBand.swift`.

**4.8 A public page of the world** · M · conf. medium · from the plan (v1-buddy §10)
- **The moment:** a link, "See the world", on the World tab and the landing page.
- **Sees and hears:** the same band and numbers in a browser, read only.
- **Why:** it is marketing, and it gives the world a population the product alone will not have for months.
- **Where:** `landing/`, `internal/world` (`GET /world` is public already).

**4.9 A passing star** · M · conf. medium
- **The moment:** another buddy ships while yours rests; at most 2 a day.
- **Sees and hears:** a small star crosses behind Boop; Boop's eyes follow it. No sign. Narration on the Mac: "A buddy in Asia and Oceania just shipped."
- **Why:** presence without messages. The world is felt on the board with no one clicking a dot.
- **Principles:** it is a pastime, the lowest priority. Never while working or under needs you.
- **Where:** `WorldLink.swift` (from the reply to a send), `render/gel/pastimes.cpp`.

**4.10 Your buddy has a colour** · M · conf. medium
- **The moment:** naming, from the seed; shown on the dot, the card and a boop's sign.
- **Sees and hears:** a tint or a small hat. "A boop from a green buddy."
- **Why:** every buddy is a blue dot with a name. Identity makes a second boop from the same buddy a small story.
- **Where:** `World.State` (one more field; `WorldTests` pins the list), `WorldBand.swift`.
- **Risk:** it adds a shared field. It is random, so it says nothing about you.

**4.11 Boop waves by itself** · M · conf. low
- **The moment:** once a day at most, when a buddy near your offset reaches a level.
- **Sees and hears:** on the Mac: "Mochi waved at Bean, who reached level 20."
- **Why:** a world where nobody opens the tab stays silent. This seeds gestures.
- **Risk:** robot noise. If people learn that waves are automatic, a wave means nothing. Test with a mark: "Mochi waved (by itself)".

**4.12 Midnight goes round** · S–M · conf. medium · from the plan (later)
- **The moment:** New Year, and each Friday 17:00, by offset.
- **Sees and hears:** the band lights up region by region; your board plays its special-day look when your offset is reached; narration "It's Friday in Europe and Africa."
- **Where:** `WorldBand.swift`, `Days.swift`.

**4.13 The world has a home** · S · conf. high
- **The change:** move `boop-world-michaeljxzhu.vercel.app` (`WorldClient.swift:8`) to a product domain before anyone buys.
- **Why:** a personal hostname in a buyer's network log breaks trust at once.

## 6. Ideas across pillars

**X1. The day has a shape** · M · conf. high · pillars 1 to 4
- **The moment:** four fixed beats a day: the morning greeting, the first turn, the ring closing, the evening card.
- **Sees and hears:** morning: hello, the dream, one line from the world (4.3). Work: status. Mid-afternoon: `today's done!` (3.1, 3.4). Evening: the day in one sign, then the nap (2.6).
- **Why:** each pillar has moments, but they do not add up to a day. Rituals at fixed points are what a person misses when the board is unplugged.
- **Where:** `Core.swift` (the greeting and the collision rule exist), ideas 2.6, 3.1, 3.4, 4.3.
- **Works if:** counts for each of the four beats a day.

**X2. A ship is the hero event** · M · conf. high · pillars 1 to 4
- **The moment:** a push or a pull request.
- **Sees and hears:** the rocket act (1), Boop proud with a word (2), +10 XP with the bar (3), your dot lights up and cheers come back as one moment (4). The evening card counts ships.
- **Why:** it is the one event that runs through the whole chain, and three of the four parts are built. Only the XP is missing.
- **Where:** `Growth.swift`, `WorkStream.swift`, `WorldLink.swift`.

**X3. "What just happened"** · S–M · conf. high · pillars 1 and 2
- **The moment:** the Now tab.
- **Sees and hears:** under the sessions, the last 5 moments with their narration and time: "10:42 Mochi cheered: api finished after 14 min."
- **Why:** `plan/v1-buddy.md` §7 lists "today's notable moments" on Now. No snapshot shows them. The narration exists for every moment and is thrown away after it plays.
- **Where:** `OverviewPane.swift`, `Runtime+Status.swift`.

**X4. A rules brain as the default** · L · conf. high · all pillars. See §9.1.

**X5. Counts for each pillar, and "send my week"** · S–M · conf. high
- **The change:** new daily counts (§3 lists them per pillar), and a "Send this week's counts" button that copies `Boop --counts` to the clipboard.
- **Why:** nobody outside this Mac has used Boop. Every open question in this review ends in "we can't know without real use".
- **Where:** `Memory/DailyCounts.swift`, `SettingsPane.swift`.
- **Principles:** numbers only, sent by the buyer's own hand.

**X6. One character sheet** · S · conf. high
- **The change:** one page in the pack, `VOICE.md`: Boop's register, 10 lines it would say, 10 it would not. Signs, voice words and the code's strings follow it.
- **Why:** three registers today: "nite nite", "Jawohl", "Level 12!" (words report, §B6).

**X7. Boop on the Mac, before the board arrives** · M · conf. medium. See §9.4.

**X8. The board alone in its box** · M · conf. medium · pillars 1 and 2
- **The moment:** first power with no Mac ever paired.
- **Sees and hears:** the egg (3.10), then a 20-second loop: a wave, the rocket, a `tap me!`. A poke answers. A sign says `get the app` and the short address.
- **Why:** a gift is opened away from the Mac. Today the board rests, shows a plug, and sleeps after 5 minutes.
- **Where:** `firmware/src/app/behaviour.cpp`.

**X9. Mochi's week** · M · conf. medium · pillars 2, 3 and 4
- **The moment:** Monday's first greeting.
- **Sees and hears:** the Boop tab opens on a card: 7 rings, the week's top moment, one new note it learned, the world's week in one line. On the board: the sign `what a week!`.
- **Why:** a weekly beat between the daily ring and the monthly goal.

**X10. Rest days are real** · S · conf. medium · pillars 2 and 3
- **The moment:** a weekend, or a day with no agent.
- **Sees and hears:** the ring on such a day is drawn as a small moon, not an empty circle. Boop's greeting on Monday does not count the gap.
- **Why:** "no streaks to lose" is the rule, but seven circles with two empty ones still read as a broken streak.
- **Where:** `BoopPane.swift`.

## 7. Ideas that bend a rule

**B1. A desk-mate by code** · bends "install and go: no friends to add" and "the world is anonymous"
- Two buyers trade a 4-word code. Each sees the other's buddy pinned at the top of the World tab, and a boop between them says the name: "Bean booped Mochi."
- **The case:** a boop from "someone in Europe or Africa" is charming once. A boop from your teammate's Bean is a reason to boop every day. The rule protects first run; this is opt-in after it, and sends nothing new.
- **Size:** M (server: a pair table; client: the pin).

**B2. A sliver of the ring that stays** · bends "nothing new lives on the board all the time"
- A 2-pixel line along the top edge shows today's ring, dim. It turns gold when full.
- **The case:** the ring shows for a few seconds when XP comes in, then goes. A buyer cannot answer "how far today?" from the board. Two pixels cost no clarity. Idea 3.9 (swipe down) is the version that keeps the rule; build that first.

**B3. The ring wants both** · bends "no limits by source"
- Work can fill the ring to 80. The last 20 come only from care.
- **The case:** it is the only form in which care truly "counts". But it turns care into a chore and Boop into a scold by design. I do not recommend it. Idea 3.1 lets care matter with no second cap.

**B4. Agents can wink** · bends "Boop only watches" (the list's Wild)
- An MCP tool lets an agent pick one emotion on purpose: nervous before a migration. Multiple choice, no text.
- **The case:** it is the agent that speaks through Boop, so approvals stay untouched. It is a strong demo. The risk is that agents overuse it; cap it at once per turn.

**B5. Regions cheer each other** · bends "no ranking"
- No leaderboard. On Friday the World tab says "The Americas shipped 412 times this week. Europe and Africa: 388." in plain text.
- **The case:** a group number is not a personal rank. But it invites faking, and it changes the mood of the world from "together" to "against". Wait until the world has 1,000 buddies.

**B6. Boop answers in its own words** · bends "the brain answers multiple choice only" (the list's Later)
- For your words only, a small model writes one sign of 18 characters, checked by the same gates as a remembered line.
- **The case:** 437 reply takes are espeak placeholders and `replies.md` has 67 lines. Replies are where the fixed lines run out first. A sign is short enough to gate. Test it behind a switch with 20 prompts before you decide.
## 8. Simplify

The owner asked this question on 2026-11-01 and asks it again. The first audit removed code: one mood graph, one pastime table, 16 lasting moods in place of 42. It did not remove concepts. The Words table had 79 words then and has 95 now. Since then growth, wishes, notices, the world, work acts and the memory writer arrived. So this section counts concepts first, then asks what each one is worth with data that did not exist on 2026-11-01: nine Jev runs with 6,363 passes.

### 8.1 The inventory

Lines are `wc -l`, comments included. "Est." marks an estimate. The full tables and the commands are in `/tmp/boop-review/inventory.md`.

| Concept | Values today | Defined in | Cost |
| --- | --- | --- | --- |
| Doing | 5 (3 on the wire; the board adds listening and no app) | `Core.swift:623`, `StateSnapshot.swift:124` | Not separable; 334 Swift lines name it |
| Activity | 8 | `Core/Activity.swift:7` | 111 lines, 18 tests (469 lines); 8 of 28 recipe rows for each of 44 art profiles |
| Tier | 5 | `Core/Tags.swift:33` | About 35 lines; it drives 5 working clips and the pastime table |
| Pastime | 52 rows (19 working, 24 idle, 4 needs you, 5 asleep) | the pack's `render/gel/pastimes.cpp` | 1,613 lines, 12 tests (588 lines); a pastime is about 18 lines of drawing |
| Kit and dressing | 4 props, 13 designs | `pastimes.cpp`, `layers.cpp`, `tags.cpp` | About 150 and 600 lines (est.) |
| Lasting mood | 16 | `character.json`, `steering/mood/*.md` | 205 lines of steering; a graph of 119 edges; 606 lines of bridge tests |
| Emotion | 42, plus 2 variants | `Character/Moods.swift:9`, `expressions.json` | About 100 JSON lines each (6,582 in all); 44 × 28 × 3 recipe rows, generated |
| Size | 4, and a second scale of 4 for finishes | `MomentOutput.swift:486`, `Moment.swift:134` | About 25 lines; one of Jev's questions |
| Moment kinds | 17 (see §8.2) | mostly `MomentOutput.swift` (1,079 lines) | Work acts 1,201; finishes 932; work stream about 1,400; wish 230 + 349 of tests; notices 198 + 394; asks 153 + 165 |
| What Jev can say | 22 `say` options (4 feelings, 16 topics, swear, none) | `MomentOutput.swift:284-312` | 3,479 takes, 486 texts, 31.7 MB |
| Talk | 3 levels, and the hush | `Core/Talk.swift`, `Core+Hush.swift` | 119 lines |
| Touch | 14 | `Core/Touch.swift:8`, `firmware/src/app/touch_gesture.cpp`, `motion_gesture.cpp` | 510 firmware lines; 42 tests (1,237 lines) |
| Memory | 6 stores: transcript, daily counts, digests, written memory, remembered lines, dreams | `app/BoopKit/Memory/`, `Prompt/Memory*.swift` | About 3,200 lines, 89 tests (1,991 lines) |
| Growth | 8 XP amounts, the ring, levels, 4 stages | `Core/Growth.swift`, `Memory/GrowthStore.swift` | About 430 Swift and 350 firmware lines; 12 tests; 0 evals |
| The world | 4 gestures, 3 regions, 6 activities | `app/BoopKit/World/`, `internal/world/` | About 1,570 Swift lines and a 972-line server; 73 tests |
| Tags | 28 (23 reach the board) | `Core/Tags.swift:14` | Small; 5 are sent to no art |
| Special days | 10 calendar days, 5 kinds of Boop's own | `Core/Days.swift` | 277 lines, 16 tests |
| Wire | 4 messages, 20 `state` keys, 11 `do` names, 17 args | `linkkit/SPEC.md` | LinkKit is 7,565 lines |
| The Studio | 8 tabs, 16 views | `characters/studio/` | 2,990 hand-written lines; `packs.js` is 117,736 generated lines, not in git |
| `charactergen.py` | — | `characters/` | 1,397 lines; 563 serve only the Studio |
| A second character and board | Pixel, the CYD | `characters/pixel`, `firmware/src/board/cyd24` | About 8,500 hand-written lines (est.), 45,000 generated |
| Several buddies | — | `Buddies/`, `Runtime+Buddies.swift` | 500 to 600 lines in about 25 files; 1 demo, 0 evals |
| Evals | 148 scenarios | `characters/*/evals/` | A standard run is about 746 Jev requests |

Hand-written product code is about 57,600 lines. Tests and tools are about 66,000.

**The check on the Studio's size:** the claim holds. `packs.js` is 117,736 lines and 1.95 MB. It is generated in 0.05 s and is git-ignored. 86% of it is two pretty-printed copies of the voice table. The hand-written page is 2,990 lines.

### 8.2 What each concept is worth

The data is nine standard Jev runs: 6,363 passes and 5,138 Moments (`/tmp/boop-review/frequency.md`). Its limit: the scenarios choose the events, so a share means "what Jev picks when this happens", not "what a buyer sees in a day". The frames are the simulator's (`/tmp/boop-review/sheets/`).

**Moods: five do the work of sixteen.**

| Mood | Share of passes | Note |
| --- | --- | --- |
| calm | 43.6% | |
| happy 12.3%, annoyed 9.5%, sad 6.5%, grumpy 5.4% | 33.7% together | 7 scenarios start in grumpy; Jev rarely moves there |
| excited 5.3%, engaged 4.5%, determined 3.5%, irritated 2.4%, proud 2.2%, curious 1.4%, lonely 1.4% | 20.7% together | |
| wounded | 0.8% | only from your words |
| comfy | 0.6% | 22 moves in, 1 out: a dead end |
| surprised | 0.4% | its own file says it lasts 1 minute |
| lazy | 0.3% | 0 picks in the latest run; top probability 0.09 in 427 offers |

48 of the graph's 119 edges were never taken. The mood files repeat each other: about 70% of each file is the same six exit clauses, and comfy and lazy are near copies (words report, §B9). The files also disagree: the poke ladder and the waiting wish lead to different moods by file.

**Emotions: 13 of 42 were never picked, and many look alike.** Never picked in any run: shy, uncomfortable, angry, disappointed, crying, whiny, uneasy, scared, stunned, embarrassed, exhausted, overwhelmed, disgusted. Five emotions (determined, proud, calm, happy, annoyed) are 50% of Moments. Ten are 75%.

On the panel, at arm's length, these groups read as one face each (`sheets/gel-moods.png`):

| Group | Emotions in it | What differs |
| --- | --- | --- |
| Dots and a small mouth | calm, curious, hopeful, engaged, surprised, uneasy, confused | 1 to 3 pixels of mouth or brow |
| Flat eyes, small frown | annoyed, bored, irritated, grumpy, skeptical, disappointed | the angle of a 20-pixel line |
| Closed arcs, small smile | proud, pleased, lazy, comfy, affectionate, shy, embarrassed | blush, a wink |
| Closed arcs, tears | sad, crying, wounded, whiny | the size of the tear |
| Wide white eyes | scared, uncomfortable, frightened, stunned | pupils |
| Long closed lines | tired, exhausted, relieved, speechless | the mouth |

The clearly different ones are few: happy, excited, amused, angry, mischievous, determined, lonely, baffled, disgusted, overwhelmed.

**Each moment's slot has one emotion.** In the current build a long finish is proud 89% of the time. A working check-in is determined 69%. A prompt is calm 60%. A lock is calm 85%. A failed check is annoyed 57%. A turn's start gets no Moment in 146 of 146 passes, and each of those is a paid request. So the brain's choice among 42 is, in practice, a choice among 2 or 3 per slot.

**Sizes.** Small 44%, medium 45%, big 7%, huge 4%. The slot sets the size: every working check-in is medium. A finish has its own second scale by the turn's tier.

**The move.** 59% of Moments have none. Success is 18%, failure 5%, and both follow the turn's outcome. Dance played 4 times in 5,138.

**Voice.** 220 of 486 texts were heard. 34 of 202 phrases, because a phrase needs a big Moment. 8 of the 21 `say` kinds were never chosen in the latest run: waiting, looking, command, helper back, stopped, helpers, tool, planning. 437 takes are espeak placeholders. About 55 words are labels ("Verify", "Trial", "Probe", "Query").

**Signs.** 72 of 146 written lines never showed. Asks: both never showed in a Jev run, and both are `keeps`.

**Pastimes.** This is a model of the dealer, not a measurement. The board deals one about every 11 s. A new buyer knows 28 of 52 rows and sees about 17 on an ordinary day. 15 rows wait for level 15, which is day 14 at the earliest. Pastimes are cheap (18 lines each) and are the board's main life between Moments.

**Activities.** On the panel the eight differ by one 30-pixel picture on the small monitor (`sheets/gel-states.png`). At arm's length there is one activity: working.

**Touches.** 14 kinds, and the buyer was taught one (a poke). Ruffle, tickle, nose boop and thump each have a detector, a take and a test. None has a count from real use. Their detection code is small, so merging them saves concepts and tests, not many lines.

**Memory.** The buyer sees three things: a dream told in the morning, a remembered line about once a day, and three notes on the Boop tab. Behind them are six stores, about 3,200 lines and 89 tests. No real week has gone through the writer (`plan/TODO.md:253`). Its quality figures are hand-graded on made-up nights.

**Several buddies, Pixel, the CYD.** No new use since 2026-11-01. Several buddies still have 1 demo and 0 evals. The CYD has been frozen since 2026-10-24. Pixel keeps an older copy of the voice with 164 takes nothing plays. A third pack, Pixel Bro, was made without the Studio.

### 8.3 A simpler model

**The idea in one line:** the buyer should be able to say what Boop is doing and how it feels in two words, and the owner should be able to hold the whole model on one page.

| Today | Proposed | Verdict | Why |
| --- | --- | --- | --- |
| Doing: 5 | Doing: 4 (resting, working, asleep, no app). Listening becomes a Moment, as its priority already says | merge | It behaves as a Moment: it cuts everything and ends in seconds |
| Activity: 8 | Activity: 4 on the board (typing, testing, looking, waiting). The Mac's rows keep all 8 words | merge | One activity is readable today. Four with body-size props are (idea 1.2) |
| Tier: 5 | Tier: 3 (1 min, 5 min, 15 min) | merge | The buyer sees three things: fresh, settled, long. Finish sizes map one to one |
| Pastime: 52 | 52, and more | keep | Cheap, pure delight, already one table. Drop the stage lock on 24 of them (see below) |
| Kit, dressing | as now | keep | 13 designs, each with a reason on the Mac |
| Lasting mood: 16 | 7: calm, happy, focused, proud, cross, sad, lonely | merge | See the table below |
| Mood graph: 119 edges, jumps, fades in prose | No graph. Any mood may follow any; a fade is one number per mood, in `character.json`, run by code | cut, and make it data | 48 edges never used; fades in prose disagree by file. The owner said no to fades in code on 2026-11-01; the new evidence is the disagreement and the dead ends (comfy: 22 in, 1 out) |
| Emotion: 42 | 18 | merge | 13 never picked; the groups above. The other 24 names stay as aliases in `character.json`, so no eval breaks |
| Size: 4, and a second scale | 3 (small, medium, big), one scale | merge | Huge is 4%. A finish takes its size from the turn's tier only |
| Jev's questions: mood, emotion, move, size, say, sometimes sign | mood, emotion, say, sometimes sign | cut 2 | The move follows the outcome; the size follows the slot. The owner kept the move on 2026-11-01; the new evidence is 59% none and 23% fixed by outcome |
| A pass at every turn's start | none | cut | 146 of 146 chose nothing |
| `say`: 22 options | 12: none, swear, 4 feelings, 6 topics (hello, work, tests, done, retry, quiet) | merge | 8 kinds never chosen; their 76 texts never heard |
| Moment kinds: 17 | 9 (table below) | merge | |
| Talk: quiet, normal, chatty, hush; plus volume, muted, face down | Talk: quiet or normal; hush; volume | merge | Five ways to be silent. Chatty has 4 evals and changes one timer |
| Touch: 14 | 7: poke, stroke, hold, shake, pick-up, swipe, face down | merge | Ruffle is a stroke the wrong way; tickle and nose boop are pokes with a place; thump is a shake; put-down and peekaboo are the ends of pick-up and face down |
| Memory: 6 stores | 4: transcript, daily counts, digest, notes. The dream is the digest's sentence; a remembered line is a note's field | merge | The stores stay as files; the concepts fold |
| The dream's write with Apple Intelligence | Freeze. Run it on the owner's own days for 2 weeks, then keep or replace with counted notes | test | 917 lines, never run on a real week |
| Growth: XP, ring, level, 4 stages with names | XP, ring, level. Stages become "bigger at 5, 15, 30" with no names in the UI or the world | merge | "Hatchling" and "Chonk" are two more words for one idea: it got bigger |
| The world: 4 gestures | 2: a boop (wave and heart fold in), a cheer | merge | Three buttons that all make the other board bounce |
| Tags: 28 | 23: drop the 5 that reach no art (`weekend`, `friday13`, `piday`, `aprilfools`, `may4`) until the gel draws them | cut | |
| Variations | as now | keep | The board's own business |
| Several buddies | Cut | cut | 0 evals, 1 demo. The world is now where "other buddies" live. The owner kept it on 2026-11-01 for demos; a demo with two simulators can run two apps |
| Pixel and the CYD | Move to a `legacy` branch in their repositories; the engine keeps the pack contract, loses `cyd24` and the 8-bit canvas | cut | About 1,900 engine lines and half of every golden run. The owner kept them on 2026-11-01; the new facts are the AMOLED freeze and Pixel Bro drawing natively on the AMOLED |
| The Studio: 16 views | 1 contact sheet, plus `charactergen.py --check` | cut | §8.4 |
| Words table: 95 | About 55 | | It follows from the rows above |

**The seven moods.**

| New | Takes in | Share today | Shown by |
| --- | --- | --- | --- |
| calm | calm, comfy, lazy | 44.5% | Comfy and lazy become idle pastimes by tier, which they already are |
| happy | happy, excited | 17.6% | Excited is happy at size big |
| focused | engaged, determined, curious | 9.4% | The working face |
| proud | proud | 2.2% | Short: fades to happy in 5 min |
| cross | annoyed, irritated, grumpy | 17.3% | One mood with a level 1 to 3 that code counts (failures, pokes). The level picks the emotion |
| sad | sad, wounded | 7.3% | Wounded is sad caused by your words; the narration says so |
| lonely | lonely | 1.4% | Kept: it is the only mood about you |

Surprised becomes an emotion only. It was a mood for 1 minute.

**The eighteen emotions.** calm, happy, excited, amused, proud, affectionate, mischievous, curious, determined, hopeful, relieved, surprised, skeptical, annoyed, angry, sad, scared, tired. Lonely and focused are moods and draw as sad and determined variants. Each old name maps to one of these in `character.json`.

**The nine Moment kinds.**

| New | Takes in | Decided by |
| --- | --- | --- |
| A finish | finish, the low sign, level-up, the ring closing (all "something got done") | rules |
| A hello or a bye | greeting, wave, the day's greeting, the telling, the nap | rules for when; the brain for the emotion |
| A reply | reply, listening | the brain |
| A touch | the board's own answers | the board |
| A musing | musing, remembered line, notice, ask (a musing that is a question) | rules for which; the brain may say none |
| A wish | wish, wish met, wish gone | rules |
| A work act | push, tests, build | rules |
| The work stream | 16 call styles | rules |
| A boop from the world | boop, cheer | rules, with the brain's emotion |

**What this deletes (estimates).**

| Area | Today | After | Deleted |
| --- | --- | --- | --- |
| Mood steering | 16 files, 205 lines | 7 files, about 80 lines | 125 lines, and the six repeated clauses move once into `guide.md` |
| Mood graph | 119 edges in `character.json`, the board's `kEdges`, `MoodGraph.swift`, `test_bridges.cpp` (606) | 7 fades | About 800 lines, most of them tests |
| Emotion art | 6,582 JSON lines, 11,428 generated | about 2,900 and 5,000 | 3,700 hand-written JSON lines; flash space on the board |
| Recipe rows | 44 × 28 × 3 | 20 × 20 × 3 | Two thirds of `slime.h`'s recipe table |
| Jev's questions | 5 or 6 a pass, a pass at each turn's start | 3 or 4, none at a start | About 20% of requests, and about a third of the answer's tokens (est.) |
| `MomentOutput.swift` | 1,079 lines | about 750 | The move, the size, half of `say` |
| Voice | 486 texts, 3,479 takes | about 330 texts | The 76 unheard topic texts and about 55 label words; about 8 MB of `voice.bin` (est.) |
| Evals | 142 for the gel | about 110 | Scenarios that pin a merged mood or a cut `say` kind |
| Touch | 14 kinds, 42 tests | 7 kinds, about 28 tests | About 400 test lines |
| Several buddies | 500 to 600 lines, 178 of tests | 0 | About 750 lines in 25 files |
| CYD and the canvas | about 1,900 engine lines | 0 | 1,900 lines; half the simulator's golden time |
| The Studio | 2,990 lines, 563 in `charactergen.py` | about 1,050 | About 2,500 lines |
| **Total** | | | **About 9,000 hand-written lines, 4,000 lines of art data, 30 evals, 40 words** |

**What it risks.**

- **Feel.** A cross Boop that climbs annoyed, irritated, grumpy is a real joy when you see it. The level keeps the climb. But the board must still show three different faces for it, or the merge loses the joke. Check `129`, `17` and the shake ladder by eye.
- **The evals.** 76 of 148 scenarios mention a mood. With aliases most pass unchanged. I expect 20 to 30 to need new musts, and one standard run (about 750 requests) to re-baseline.
- **The packs.** SlimeBuddy needs the alias table, 9 fewer mood files and new voice lending. Pixel and Pixel Bro, if kept, need the same.
- **The owner's earlier calls.** Three rows above reopen decisions of 2026-11-01 (fades in code, the move in code, several buddies and the CYD). Each row names its new evidence. They are in the open questions (§13).

**One thing to add while cutting: unlock the pastimes.** 24 of 52 pastimes need stage 2 or 3. A new buyer sees 17 a day for two weeks. "Whole from day one" allows looks to grow, but this hides a third of the board's life in the weeks that decide whether the buyer keeps it. Keep 6 as stage rewards; open the rest.

### 8.4 The Character Studio

**What it is today.** 8 tabs and 16 views in 2,990 hand-written lines, plus 563 lines of `charactergen.py` that exist only to feed it. The full audit is in `/tmp/boop-review/studio.md`, with a screenshot of every view in `/tmp/boop-review/studio/`.

**Who uses it.** The owner, to look at every mood against every state. No one else: the playbook's 7 steps for a new character never use it, `CHARACTER.md` §14 calls the Studio entry optional, and the worker that made Pixel Bro wrote its own contact sheet.

**What it is worth, view by view.**

| View | What it does | Another tool does it? | Verdict |
| --- | --- | --- | --- |
| Matrix (136 lines) | Every mood × state cell, drawn | No | Keep: it is the contact sheet |
| Scene (about 190) | One cell large, with its layers | No | Keep as the sheet's detail |
| Personality, Moods, Signs, Dreams, Evals, Demos, Stills | Typeset the pack's files | Any editor | Cut |
| Voice | The take table, with playback | `boopctl takes` | Script |
| Brain | The prompt Jev reads | `boopdev prompts` | Script |
| Transitions, Rank | The mood graph's bridges | `boopctl sim` goldens | Cut with the graph (§8.3) |
| Overview's gap list | What the pack lacks | `charactergen.py --check` | Script: print the gaps |
| Behavior map | The engine's rules as a diagram | It is engine documentation | Move to `documentation/architecture.html`, or cut |
| References, Review | Notes on art | Used once each | Cut |

**It is broken today, and nobody noticed.** The landing view is blank for both packs: `character.js:151` reads `pack.uses`, which `charactergen.py` stopped writing on 2026-11-01. The default pack's board preview does not load: `charactergen.py:1132` writes `"staged": "character"`, so `board.js:107` asks for a file that is not there. `check.cjs` cannot pass: it asserts a deleted file. A tool that can be broken for eight days with no one seeing it is not in use.

**The smallest useful form.**

1. One page, the contact sheet: Matrix, with Scene as a cell's detail. About 1,050 lines.
2. `charactergen.py --check` prints the gap list.
3. `packs.js` is made on demand by the server or a `--studio` flag, not as a side effect of `--check`. Without the pretty-printed voice tables it is about 1,500 lines.
4. Better still, a static sheet: `boopctl sheet` writes one PNG per pack from the simulator, as `/tmp/boop-review/sheets/gel-moods.png` was made for this review with 20 lines of Python. Then the Studio needs no server and no JavaScript.

**It deletes** about 2,500 hand-written lines, 14 views, `behavior.json`, and the README's 387 lines of upkeep (changed in 21 of 33 Studio commits). **It risks** the in-browser playback of takes, the transitions scrubber, and the behaviour map's two code checks.

**With 18 emotions and 20 states** the sheet is 360 cells, not 924. It fits on one screen.

### 8.5 The cost of a new character

The contract asks for four things: `character.json` with 6 keys, `guide.md`, `personality.md` and a face. That is light. The real cost is the grid: each face answers 22 states × 42 moods, and a voice needs takes for every mood, about 3,500 rows and 32 MB. Pixel Bro was about 190 files in one commit and left the voice, the mirror, the goldens and the reply clips open.

With the simpler model a character is 18 emotions × 20 states, 7 mood files and about 330 voice texts. That is the difference between a week and a day for the art, and it makes a third character a real option in place of a demo.

### 8.6 Onboarding: 9 acts to 5

Onboarding is 9 acts, about 600 words and about 20 actions. A realistic time is 8 to 12 minutes; act 1 promises "a couple of minutes". Touches are taught three times (act 5, act 6's tour, the finale).

| Today | Proposed |
| --- | --- |
| 1 Hello, 2 What I do | 1 Hello (one screen; the three cards from act 2 below the face) |
| 3 Name | 2 Name |
| 4 Body | 3 Find me (the egg hatches here, idea 3.10) |
| 5 How we get along (4 lessons, a mood legend) | Cut. The board teaches each touch the first time it matters (idea 1.13) |
| 6 Agents, with a 4-step tour | 4 Agents: connect, then one live moment: "Say hi from your agent" |
| 7 Small things: login, mic, brain | Login moves to a default. Mic is asked at the first hold of the button. The brain is no longer asked (§9.1) |
| 8 World | 5 World, then done |
| 9 Finale (4 more tips) | Cut: the last screen is the world's, and Boop cheers |

The owner said no to "8 acts to 6" on 2026-11-01. The new evidence: the tour and the lessons now overlap, the brain card is where a buyer gets stuck, and first-time hints did not exist then.
## 9. Fundamental changes

Five changes to what Boop is. I recommend two now, two as one-week tests, and one as a decision to stop.

### 9.1 A brain in the box: rules first, Jev for the rare moment

**Thesis.** Boop should have its whole personality with no key, no account and no bill. A rules brain built from the eval runs picks the emotion, the mood and the word. Jev becomes an optional upgrade for your words and for big moments.

**Why now.** Three facts.

1. **A buyer cannot get a key.** Onboarding's card says "A Jev API key lets TypeSafe's AI pick how I react" and links to API docs. There is no sign-up, no price, and Settings has no link at all. With no key Boop has no mood, no emotion and no reply: the product's first sentence, "a personality of its own", is off. This is the largest first-week return risk in the product.
2. **Jev's choices are mostly a table already.** In the current build a long finish is proud 89% of the time, a working check-in determined 69%, a lock calm 85%, and a turn's start is nothing 146 times in 146. The slot sets the size. The move follows the outcome. Over 6,363 passes there are about 30 slots, and each has 1 to 3 real answers.
3. **The plan always said so.** `plan/product-ideas.md`: "The aim is to ship with a rules brain built from the evals, and grow into Jev for the richer things." `plan/v1-buddy.md` §12 asks the same question as decision 1.

**What it is.** A table in the pack, `brain.json`: for each slot (event kind × mood × a few facts such as the turn's tier, the run of failures, the time since the last Moment), a short list of weighted answers: emotion, `say` kind, sign section. A seeded pick with "not the last one" gives variety, which Jev lacks today (34 to 45% of emotions repeat the one before). The mood moves by rules: failures and pokes raise cross by a level, a win or kind words lower it, a long finish gives proud for 5 minutes, your rude words give sad, a wish left for an hour gives lonely, and each mood fades by its number. Replies to your words use word matching, as `Outputs/StatusReply.swift` already does for "how many" and "how long", extended to the 17 reply kinds; with no match Boop gives `huh?`.

**The buyer's day after it.** Unbox, name, plug in, work. Boop reacts from the first minute. It answers a touch or a finish in under 100 ms, not after a network call. Nothing about the buyer's work leaves the Mac except the world's counts. Settings has one optional line: "Give Mochi a bigger brain", for people who want replies to free speech.

**Deletes.** The brain card in onboarding, the no-brain, out-of-credit and "Jev isn't answering" notices, the daily request budget as a limit on development, and most of the cost of evals: a scenario's must becomes a table test that runs free in `make -C internal check`.
**Adds.** `brain.json` and its builder from trajectories, a rules brain beside the scripted one (`Boop --brain scripted` already runs the pipeline with no Jev), a mood rule file of about 150 lines.

**Effect on the pillars.** Pillar 1: none. Pillar 2: every buyer gets it, not only those with a key; replies to free speech get narrower. Pillar 3: none. Pillar 4: none. Trust: the privacy story becomes one sentence.

**Biggest risk.** Boop feels canned. Jev's rare, well-judged moment (the owner's own example: determined and "retry" at "this doesn't work") is what people remember.
**The cheapest test, one week.** Build the table from the 6,363 passes with a script. Run the 131 Jev scenarios with `--brain rules` and send the trajectories to the same judge (about 110 judge requests, no brain requests). The bar: musts 125 of 131 or better, and the judge's "reasonable" within 10 points of Jev's 99 of 110. Then the owner uses it for two days with no key.

**Recommendation: do it.** Start with the table for the non-speech slots (step 4 of the two-week plan). Keep Jev behind a switch, and keep `MomentOutput`'s code rules, which already sit between any brain and the board.

### 9.2 A smaller core: a status monitor with a soul

**Thesis.** Boop is one screen that says what your agents do and one creature that has seven feelings about it. Everything a buyer cannot tell apart on the panel goes.

**What it is.** §8.3: 4 Doings, 4 activities, 3 tiers, 7 moods, 18 emotions, 3 sizes, 9 Moment kinds, 7 touches, 2 Talk levels, one buddy, one board, one character, a one-page Studio.

**The buyer's day after it.** The same day, a little clearer. Cross is visibly cross. The buyer never sees an emotion they cannot name.

**Deletes.** About 9,000 hand-written lines, 4,000 lines of art data, about 30 evals and about 40 words of vocabulary. **Adds.** An alias table and a level on the cross mood.

**Effect on the pillars.** Pillar 1 gains (four readable activities). Pillar 2 is neutral to better (less repetition of near-equal faces; the content pass has fewer cells to fill). Pillars 3 and 4: none.

**Biggest risk.** A subtle loss of charm: the 24 emotions that go are someone's careful art. **The cheapest test:** the alias table alone is a one-day change with no deletion. Run the owner's desk for a week on 18 emotions and 7 moods. If nobody misses anything, delete.

**Recommendation: do it,** in the order aliases, then moods, then deletions. It makes 9.1 a third of the work, because the table has 7 × 30 cells, not 16 × 30.

### 9.3 A different loop: the day, not the level

**Thesis.** What brings a buyer back each day is a ritual with a start and an end, and a shelf that slowly fills. It is not a number that counts full days.

**Why.** The ring fills from calls in the first hour (§3, pillar 3), then says nothing. A level is 100 XP, so the level is the count of full days, and the only reward after level 30 is the same low sign. The world has no goal. So the loop today is: the morning greeting, then status until you go home.

**What it is.** Four fixed beats (idea X1): the morning (hello, the dream, one line from the world), the first ship of the day (the hero event, X2), the ring closing in the afternoon, and the evening card. Around it, the shelf (idea 3.5): keepsakes for firsts, shiny moments, level marks and world goals. XP stays as the ring's fuel, and the level stays as a quiet number on the Boop tab.

**The buyer's day after it.** They sit down: Boop tells its dream and that 40 buddies were up overnight. Their first push: the rocket, and a cheer from someone. About 15:30: `today's done!`. At the evening lock: `9 turns, 2 ships`, a wave, the nap. On Monday: the week's card.

**Deletes.** The stage names from the UI. **Adds.** The evening card, the shelf, the re-weighted XP.

**Effect on the pillars.** Pillar 2 gains two daily moments. Pillar 3 gets a reason past day 30. Pillar 4 gets a daily place to speak.

**Biggest risk.** The shelf becomes a grind or a new thing to teach. **The cheapest test:** ship 3.1 and 2.6 only (two small changes), and watch four counts for two weeks: when the ring closes, evening cards played, Boop tab opens, and days the board was connected.

**Recommendation: test it.** Build the two small pieces now. Build the shelf only if the Boop tab is opened at least 3 times a week.

### 9.4 A different surface: Boop on the Mac first

**Thesis.** The Mac's own Boop, in a small always-on-top window or beside the notch, is a whole product. The board is the upgrade that puts it on your desk.

**Why.** Everything hard is already on the Mac: the hooks, the rules, the memory, the world, and the board's own firmware compiled as the mirror and the simulator window. A buyer with no board today gets a small face in the popover's header and a window called "Simulator", a developer's word. Meanwhile the world needs hundreds of buddies to feel alive, and each one needs hardware that must be made, shipped and paired over Bluetooth.

**What it is.** The simulator window, made pretty and shipped: a 320 × 240 Boop that floats, with touch by mouse (click is a poke, drag is a stroke), sound from the Mac, and the same needs-you card. Onboarding's "No board? Use the simulator window" becomes "Start with me on your Mac". The board's onboarding act runs when one is first plugged in.

**The buyer's day after it.** Download, name, work. The world fills with Mac-only buddies. Those who love it order the board, and it arrives already named, with its level.

**Deletes.** Nothing. **Adds.** Polish for the window (it exists: Settings has a Simulator switch, `SettingsPane.swift:217`), mouse touches, and a decision about price.

**Effect on the pillars.** Pillar 1: weaker without the board (a window can be covered; the board cannot). Pillar 2: the same. Pillar 3: the same. Pillar 4: far stronger, since the world can grow at the speed of a download.

**Biggest risk.** It breaks a ground rule ("built for buyers of a ready-made Boop") and may weaken the reason to buy the board. A covered window is a worse status monitor than a second screen. **The cheapest test:** give the internal bundle with the window to 10 people for a week, with the daily counts on. Ask one question at the end: would you pay for the board?

**Recommendation: test it.** It is also the only way to learn anything from real use before hardware ships.

### 9.5 What to stop

**Thesis.** One buddy, one character, one board, one brain path, one page of tools.

| Stop | Why | It frees |
| --- | --- | --- |
| Several buddies | 0 evals, 1 demo, 25 files touched | About 750 lines; the header in every prompt |
| The CYD board and the 8-bit canvas | Frozen since 2026-10-24 | About 1,900 engine lines; half of the firmware test time |
| Pixel and Pixel Bro in the engine's CI | The gel is the product | The fetch of two packs' `main` on every CI run; a doubled golden set |
| 14 of the Studio's 16 views | §8.4 | About 2,500 lines |
| The dream's write by Apple Intelligence, until a real week has run | 917 lines with hand-graded quality | Nothing yet: it is a pause |
| World gestures as three buttons | Wave, boop and heart do the same thing | Two `[world …]` sections, one concept |
| The `chatty` Talk level | It changes a timer | A setting and 4 evals |
| The label words in the voice | "Verify", "Probe", "Query" | About 55 texts, and the register problem |

**What not to stop.** The world: it is cheap to run and it is the only pillar that can make owning a Boop social. The voice bank: sound is half of the charm on a desk. The work acts and the pastimes: they are the best content. The memory's digest and counts: they cost little and everything else reads them.

**Recommendation: do it,** after v1's panel checks, in one week of deletions. Each row is a separate commit.

### 9.6 Which relationship is the product?

The review brief asks: a coworker who comments on your work, a pet you care for, or a mirror of your day? The evidence points one way.

- **The coworker** has the strongest content: the rocket, the crash test, the work stream, `still broken?!`, the grudging proud face. It fires every few minutes. It needs no teaching.
- **The pet** has thin content and weak mechanics: one wish a day, two asks for ever, care that cannot move the ring, and 12 touches the buyer never learned.
- **The mirror** (notices, the dream, the written memory) is the least proven and the most likely to feel wrong when it errs.

So: **Boop is a coworker with a soft spot.** It is on your side against the agents and the work. Care is a spice: a stroke calms it, a wish is met by what you do anyway. The mirror stays small and correctable (idea 2.8). This sentence should decide every later trade-off: when an idea makes Boop a pet to keep alive, or a tracker of your habits, it is off the main road.
## 10. The Top 10

Ranked by the buyer's delight for each unit of effort. Three are simplifications (3, 6, 8) and one is the first step of a fundamental change (7).

**1. Status never drops: fix the three bugs in pillar 1.** (S to M; §11.2, bugs 1 to 4.)
A third finish in a row is lost, failed checks get no feeling, and gestures in a batch vanish. These are the product's first promise failing in ways the evals cannot see, because evals make no act events and never end three turns at once. It beats number 2 because a broken promise costs more than a weak one, and each fix is a few lines with a test.

**2. Make the ring mean a day.** (S; ideas 3.1, 3.2, 3.4.)
Drop the XP for a call, add XP for a ship, play one moment for the ring and the level together, hold `today's done!` up on a sign, and stop drawing part-full rings in red. It is a day of work and it turns pillar 3 from "full by ten" into a beat in the afternoon. It beats number 3 because the buyer sees it every day, and number 3 is invisible.

**3. Stop paying for nothing.** (S; simplification; §8.3.)
No brain pass at a turn's start (146 of 146 chose nothing), none for an unlock under a minute, none for hourly check-ins while you are away, and no `move` or `size` question. This is about a quarter of all requests (estimate) and it removes two concepts. It beats number 4 because it makes every later Jev run cheaper, the content pass included.

**4. The content pass, in one voice.** (M; ideas 2.1, 2.2, X6.)
About 170 new lines in the pack, 20 asks that come back, the code's signs moved into the pack, and one page that says how Boop talks. Pack-only work. It is the cheapest cure for "flat by day 3". It beats number 5 because repetition is felt many times a day, and a kind on the needs-you card a few times.

**5. Needs you says what kind, and the board says what happened while you were away.** (M; ideas 1.1, 1.7.)
Both make the status monitor more useful at the two moments a person looks at it: when it knocks, and when they sit back down. It beats number 6 because it adds use, and number 6 only removes confusion.

**6. Seven moods and eighteen emotions, by an alias table.** (M; simplification; §8.3.)
One day for the aliases, a week of the owner's own use, then the deletions. The buyer sees emotions they can name, cross becomes a visible ladder, and the owner holds the model in his head. It beats number 7 because it is its prerequisite: it cuts the rules brain's table from 16 moods to 7.

**7. A brain in the box, step one.** (L; fundamental; §9.1.)
Build the slot table from the 6,363 recorded passes, run the 131 scenarios on it for free, and send them to the same judge. If it holds, every buyer has a Boop with a personality and no key. This is the largest change in the list. It ranks seventh only because it is the largest piece of work; in value it is first. It beats number 8 because without it onboarding cannot lose its worst screen.

**8. Onboarding in five acts.** (M; simplification; §8.6, idea 1.13.)
Cut the lessons, the tour and the finale; let the board teach each touch once, when it matters. With number 7 the brain card goes too. Ten minutes become four. It beats number 9 because every buyer meets it, once, before anything else.

**9. The day has a shape.** (M; ideas X1, 2.6, 2.5, and "awake while you are here".)
An evening card, a floor under idle, and a Boop that is awake when you are at the Mac even with no agent. It gives a quiet day a pulse and the day an end. It beats number 10 because it needs no one else to be there.

**10. A world worth opening.** (M; ideas 4.1, 4.2, 4.4, 4.5, 4.7.)
Turn one goal on, show "Mochi added 82", say honestly when the world is small, count a buddy as awake when its person is there, and let a poke boop back. Last, because its value grows with the number of buddies, and that number is zero today.

**Just outside:** the Studio as a contact sheet (§8.4), quiet on calls (1.8), a swear switch (2.11), the shelf (3.5).

## 11. Quick wins

### 11.1 Polish that is ready now

Each is under a day. Strings first, then numbers, then small rules.

| # | Where | Change |
| --- | --- | --- |
| 1 | `app/Boop/Views/SettingsPane.swift:288` | "Allow \(model.name) in System Settings…" → "Allow Boop in System Settings, under General, Login Items." macOS lists the app's name |
| 2 | `characters/boop/steering/asks.md:17` | `hold BOOT, say hi?` → `hold button, hi?`. A buyer was never told "BOOT" |
| 3 | `characters/boop/steering/asks.md:2-3` | Remove `keeps` from one of the two asks, and add at least 8 more, so asks do not end on day 1 |
| 4 | `characters/boop/steering/replies.md:31` | `[bye working]` has one line, `i got this`. Add: `i'll watch em`, `go. i'm on it`, `leave it w/ me`, `they're mine now`, `holding the fort` |
| 5 | `characters/boop/steering/signs.md:38-40` | `{agent} sits idle` → `{agent}'s all urs`; `{agent}'s waiting` → `{agent} misses u` |
| 6 | `app/Boop/Views/BoopPane.swift`, `Theme.swift` | A part-full ring is blue, not red, in the big ring and in "The last 7 days" |
| 7 | `app/BoopKit/Core/Core.swift:523-537` | The ring's words go on a sign, not the caption; when a level comes with the ring, play one moment with both: the sign `today's done!` and the low sign `Level 13!` |
| 8 | `app/BoopKit/Core/Growth.swift:53` | `toolXP = 1` → `0`. Add `shipXP = 10`. Choose the final numbers after a week of the owner's own counts |
| 9 | `app/BoopKit/Core/Growth.swift:68` with `Touch.swift:24-28` | A shake and a wrong-way stroke earn no XP; a poke earns the same as other care, or none. Pin it in `GrowthTests` |
| 10 | `app/BoopKit/DeviceLink/BoopDevice.swift:36` | A finish (`task_complete`) waits 20 s, not 5; or two finishes that wait fold into one moment that names both threads |
| 11 | `app/BoopKit/Core/Narration.swift:153` | "You've been here \(hours) hours and haven't touched it." → "It's been \(hours) hours since you two said hi." |
| 12 | `app/BoopKit/Core/Narration.swift:114` | "\(name) wished for \(kind.words), and you left it." → "\(name)'s wish for \(kind.words) went by." |
| 13 | `app/BoopKit/Memory/MemoryReader.swift:254` | "10 turns on "api"" → "10 turns, most on "api"" when more than one thread |
| 14 | `app/BoopKit/Memory/MemoryReader.swift:262-267` | The morning caption picks turns before failures: "day 1: 10 turns" |
| 15 | `app/BoopKit/World/WorldGestures.swift` (the held line) | "While you were away" only after an away. After the night: "Overnight,". After needs you: "Just now," |
| 16 | `app/BoopKit/App/Runtime+World.swift:44` | With you at the Mac and no agent open, the world's activity is `idle`, not `asleep` |
| 17 | `app/Boop/Views/WorldPane.swift:42` | Under the band, a five-word legend in the dots' colours. Cut "Click one." when the card is open |
| 18 | `app/Boop/Views/SettingsPane.swift:81`, `Onboarding/OnboardingWorld.swift:19` | "counts like tests passed. Nothing about you or your code." → "today's counts: turns, tests, ships and lines changed. Nothing you write." |
| 19 | `app/Boop/Views/Onboarding/OnboardingBrainKey.swift:26, 34`, `SettingsPane.swift:357-382` | "Jev's docs" → "Get a key", to a sign-up page; add the same link in Settings; say the price |
| 20 | `app/Boop/Views/OverviewPane.swift:89, 74` | "Sessions" → "Your agents"; "Boop's hooks" uses the buddy's name or loses the word hooks |
| 21 | `app/BoopKit/World/WorldClient.swift:8` | A product domain in place of `boop-world-michaeljxzhu.vercel.app` |
| 22 | `app/BoopKit/Memory/DailyCounts.swift` (the summary) | Print the needs-you answer time in seconds under 2 minutes |
| 23 | `internal/world/src/app.ts:285-309`, `limits.ts` | A cheer needs a ship from that buddy in the last 30 minutes; `LEVEL_MAX` 1,000,000 → 5,000; reports count once for each address |
| 24 | `characters/studio/character.js:151`, `characters/charactergen.py:1132` | The two lines that leave the Studio's landing view blank and its board preview missing. Or skip, and cut the Studio (§8.4) |
| 25 | `characters/boop/steering/mood/*.md` | One poke ladder and one waiting-wish rule, said once in `guide.md`; delete the copies |
| 26 | `characters/boop/mac/passing.tsv:58-59` | "getting ready for the work act" → "getting into costume"; "coming back from the work act" → "packing its props away" |
| 27 | `firmware/src/render/tags.cpp` (dressing rules) | No pyjamas while Doing is working at night: 21 fps toward 30 |
| 28 | `app/BoopKit/Core/TranscriptView.swift` (what wakes the brain) | No pass for a turn's start; none for hourly check-ins while you are away |

### 11.2 Bugs found, not fixed

Nothing was changed in this session. Each bug has its log in `/tmp/boop-review/runtime.md`.

| # | Bug | Where | How it fails |
| --- | --- | --- | --- |
| 1 | Failed checks never ask the brain | `mellowharness/Sources/MellowHarness/Harness.swift:604-606`; `app/BoopKit/Core/TranscriptView.swift:334-336` | The `tool_end` is passed over for the newer `act_end`, and the `act_end` is held. Tests that fail 3 times, and tests that pass after failing, get no moment. `headless.log` 21:08:28 |
| 2 | A third finish in a row is dropped | `app/BoopKit/DeviceLink/BoopDevice.swift:36` | A finish plays about 5 s and a waiting moment lives 5 s. `do 618056319 ended skipped (late)`, 21:14:08 |
| 3 | The level-up `do` is sent twice | `app/BoopKit/App/Runtime.swift:792-811` | Two `do`s "Level 2!" 1 ms apart; the copy is skipped only because the first lasts 5.9 s. `ring.log` 12:31:01 |
| 4 | Gestures that arrive together can all be lost | `app/BoopKit/World/WorldGestures.swift:47-51` with `Harness.swift:604` | The harness keeps the newest event; if that one is over the hour's limit, the others never play. `world-recv.log` 12:22:09 |
| 5 | The ring's moment never plays with a level | `app/BoopKit/Core/Core.swift:523-525` | "One moment for them all: the last level's". For a buyer who fills each ring, that is every day |
| 6 | A level-up cut by needs you never comes back | `app/BoopKit/Memory/GrowthStore.swift:118-131` | It is marked played as it starts. `care-live.log` 12:29:54 |
| 7 | The dream puts every turn on the top thread | `app/BoopKit/Memory/MemoryReader.swift:254`; `Prompt/MemoryPipeline.swift:280` | "10 turns on "api"" for turns on three threads |
| 8 | Shakes earn care XP, pokes do not | `app/BoopKit/Core/Touch.swift:24-28`; `Growth.swift:68` | 3 shakes gave 9 XP; 7 pokes gave 0 |
| 9 | A cheer needs no ship | `internal/world/src/app.ts:285-309` | A board said `we shipped!` for a buddy that pushed nothing |
| 10 | A data-race warning on each gesture sent | `app/BoopKit/App/Runtime+World.swift:135` | "@MainActor function … was not called on the main thread". Seen headless only |
| 11 | Hourly check-ins ask the brain while you are away | `app/BoopKit/Core/TranscriptView.swift:320-350, 1095` | One request an hour for an empty chair; the debug line says `(no pass)` and is wrong |
| 12 | The Studio's landing view is blank | `characters/studio/character.js:151` | It reads `pack.uses`, gone since 2026-11-01 |
| 13 | The Studio's default board preview does not load | `characters/charactergen.py:1132`; `characters/studio/board.js:107` | `"staged": "character"` makes a path that is not there |
| 14 | Asks end for good after two answers | `characters/boop/steering/asks.md:2-3`; `app/BoopKit/Outputs/Asks.swift:31-33` | Both asks are `keeps` |
| 15 | Login Items names the buddy | `app/Boop/Views/SettingsPane.swift:288` | macOS lists "Boop" |
| 16 | Eval `04-tests-fight-back` passes on a path the runtime never takes | `characters/boop/evals/04-tests-fight-back.json` | Eval steps make no `act` events |

Oddities, true to the code but wrong to a reader: "Boop dreamed about Monday and Tuesday" for one evening; "While you were away" when you were not; a stopped turn "with no tool calls" after one; the work stream's word "origin" for a push; `spoken` counted at volume 0.

## 12. A two-week plan

Ten working days. The sizes add up to more than one person's ten days, so the plan has two tracks that do not touch the same files: **A** is the engine, **B** is the pack and the Mac's UI. Each step ships alone. Jev requests are estimates.

| Day | Track | Step | Ships as | Jev | The owner checks on the panel |
| --- | --- | --- | --- | --- | --- |
| 1 | A | **Top 1.** Finishes wait 20 s or fold; a failed check wakes the brain; the level-up goes once and comes back after a cut; batched gestures play as one | 4 commits, each with a test that fails first | `--only 04` and 2 more: about 15 | Three agents ending together: three names seen. Tests failing twice: a wince, then cross |
| 1 | B | Quick wins 1 to 6, 11 to 20, 26 | One commit of strings | 0 | Nothing: the Mac's snapshots |
| 2 | A | **Top 2.** XP weights, one moment for ring and level, the sign | One commit; `GrowthTests` | 0 | `today's done!` on a sign at arm's length; gold bar; the low sign under it |
| 2–3 | A | **Top 3.** No pass at a start, a short unlock, or while away; drop the `move` and `size` questions | Two commits | One standard run at the end of week 1 covers it | Nothing new should be seen. A finish still plays its size |
| 2–5 | B | **Top 4.** The content pass and the character sheet; asks that come back | Commits in SlimeBuddy, then the pin | `--only` on 8 scenarios: about 40 | Read 20 signs on the panel: do any clip at 18 characters? |
| 4–5 | A | **Top 5.** The kind on the needs-you card; the list after an away | Two commits, a demo step each | 0 | The card's second line from the chair. The list's pace: 2 s each |
| 5 | — | One standard run and the judge, on the week's tree | The report in `plan/TODO.md` | about 750 | — |
| 6 | A | **Top 6, part 1.** The alias table: 18 emotions, 7 moods, no deletion | One commit in SlimeBuddy and one here | `--only` on 10: about 50 | The cross ladder: three different faces. Does anything feel missing? |
| 6–9 | A | **Top 7.** The table from the recorded passes; `--brain rules`; the 131 scenarios; the judge | A new brain behind a switch | about 110, for the judge only | Two days with the key removed. Is it still Boop? |
| 6–8 | B | **Top 8.** Onboarding in five acts; first-time hints on the board | One commit; new snapshots | 0 | A full first run with a stopwatch. The three hints, once each |
| 8–9 | B | **Top 9.** The evening card; the floor under idle; awake while you are here | Three commits; evals for each | `--only` on 6: about 30 | An evening lock. A quiet hour: one small beat, not more |
| 9–10 | B | **Top 10.** The goal on (local server first); "Mochi added"; the small-world line; boop back | Server and client commits; `world_e2e.py` | 0 | A boop, then a poke within 10 s: `sent!` |
| 10 | A | **Top 6, part 2,** if the week on aliases felt whole: delete the 24 emotions, 9 mood files and the graph | One commit in each repository | One standard run: about 750 | The mirror on the Mac matches the board |
| 10 | — | The owed panel checks from `plan/TODO.md`, with the Mac off: `perf --scenes`, latency | Numbers in the report | 0 | Frame rate by eye at night |

About 1,750 Jev requests in two weeks, under the 2,500-a-day limit on any one day. After Top 7 lands, most later checks are free.

**Not in the two weeks:** stopping several buddies, the CYD and Pixel (§9.5), the Studio's cut (§8.4), the Mac-first test (§9.4), the shelf. Each is a week of its own.

## 13. Open questions for the owner

| # | The decision | My recommendation |
| --- | --- | --- |
| 1 | Does a buyer need a Jev key? (`plan/v1-buddy.md` §12, decision 1) | No. A rules brain in the box; Jev as a switch for those who want it (§9.1). Decide after the one-week test |
| 2 | May the XP amounts change, so the ring closes in the afternoon? | Yes. A call earns 0. Look at your own week of counts first: the hour the ring closed |
| 3 | Ring and level: two moments or one? | One, since for a regular buyer they are the same event. The level stays a number on the Boop tab |
| 4 | Seven moods and eighteen emotions? | Yes, by aliases first, deletion after a week on your desk |
| 5 | Fades as numbers in code, and no mood graph? You said no on 2026-11-01 | Yes now: the 16 files disagree with each other, 48 edges are unused, and a rules brain needs fades in code |
| 6 | Code picks the move and the size? You kept the move with Jev on 2026-11-01 | Yes now: 59% none, the rest follows the outcome |
| 7 | Stop several buddies, the CYD and Pixel in the engine? You kept all three on 2026-11-01 | Yes, after v1's panel checks. A two-buddy demo can run two apps |
| 8 | The Studio as one contact sheet? | Yes. It has been broken for 8 days unseen |
| 9 | World goals back on? | Yes, one a month, sized from last month's total, with no XP reward |
| 10 | Is a buddy "awake" when its person is at the Mac with no agent? | Yes, as `idle`. It already says `asleep` at a lock, so presence is shared today |
| 11 | Does the public `GET /v1/world` list names and live activity to anyone? | Give names only to joined buddies; the public page shows dots |
| 12 | Swearing: on or off by default? | Off, with a switch in onboarding |
| 13 | Can a buddy be renamed? | Yes, once a week |
| 14 | Onboarding in five acts? You said no to "8 to 6" on 2026-11-01 | Yes, once first-time hints exist |
| 15 | Is Boop a coworker, a pet or a mirror? | A coworker with a soft spot (§9.6). Write it at the top of `personality.md` |
| 16 | A Mac-only Boop for 10 testers? It bends "built for buyers of a board" | Yes, as a test. It is the only way to get real counts before hardware ships |
| 17 | The memory writer: keep building, or freeze? | Freeze. Run it on your own two weeks, read `memory.md`, then decide |
| 18 | The last stage is at level 30. What comes after? | Marks at 50, 100 and 365 (idea 3.8), and the shelf only if the Boop tab is opened |
| 19 | Who pays for the brain of a buyer who turns Jev on? | Out of scope here, but the screen must say the price |

## 14. Evidence index

No Jev request was made in this session (`boopdev eval --list`: "today: 0 of 2500 used"). No file in the repository was changed except this one. Nothing was pushed.

**The real board was not used.** `internal/tools/boopctl ping` showed `"ble": "conn"` (the owner's app was connected) and `boopctl state` showed `"face_down": true`. By the brief's rule I stopped there. The board's firmware is `838952c366`; `git diff --stat 838952c3 HEAD` shows no firmware change since, so no flash was due. Everything about the panel in this review is from the simulator's frames. What only a person at the panel can judge is in the two-week plan's last column.

**Commands run, from the `v1-polish` worktree.**

| Command | Result |
| --- | --- |
| `git status`, `git log --oneline -12`, `git log --oneline main-v2..v1-polish` | Clean; HEAD `270ee70c` |
| `make -C internal build` | Passed |
| `.build/debug/Boop --snapshots /tmp/boop-review/snaps` | 286 PNGs |
| `make -C internal sim` | 23 scenarios, 0 expect failures, 0 changed pictures; frames in `/tmp/boop-sim/v1-polish-d3b1e3/` |
| `internal/tools/boopctl board`, `ping`, `state` | Free; `ble: conn`; `face_down: true`; `fps: 34` |
| `.build/debug/Boop --headless --state-dir /tmp/br1 --link usb:/tmp/brb.sock --brain scripted --no-open --debug` | Scenes a to g, on the native simulator through `linkkit-bridge` |
| `.build/debug/Boop --counts --state-dir /tmp/br1` | `/tmp/boop-review/runtime/counts-live.txt` |
| `npm run dev` in `internal/world`, then `internal/tools/world_e2e.py http://localhost:8787` | PASS |
| `.build/debug/boopdev eval --list`, `--level standard --list`, `--scripted --timeline` | 142 scenarios; scripted 142 of 142 |
| `git show plan-simplify:plan/simplify-behavior.md` | The earlier audit, 571 lines |

**Reports written by this session's research** (each lists its own commands).

| File | Holds |
| --- | --- |
| `/tmp/boop-review/inventory.md` | Every concept: values, where defined, lines, tests (§8.1) |
| `/tmp/boop-review/frequency.md` and its `*-tables.md` | Nine Jev runs tallied: moods, emotions, sizes, voice, signs, the graph, pastimes (§8.2) |
| `/tmp/boop-review/studio.md`, `/tmp/boop-review/studio/*.png` | The Studio, view by view, with 32 screenshots (§8.4) |
| `/tmp/boop-review/runtime.md`, `/tmp/boop-review/runtime/` | The headless day: `headless.log`, `world-*.log`, `care-live.log`, `ring.log`, `world_e2e.txt` (§2, §3, §11.2) |
| `/tmp/boop-review/words.md` | Every string, sign, ask, reply and narration, with 25 rewrites and 35 inconsistencies (§4.4, §11.1) |

`/tmp` is cleared in time. The Jev trajectories the frequency report read are on the owner's Mac in `~/.boopdev/night-2026-11-01/`, `~/.boopdev/day2/`, `~/.boopdev/tonight/` and `/tmp/boop-eval/20261108-220953-81575.*` (the last is the only one with every option's probability, and `/tmp/boop-eval` is cleared after a day).

**Pictures looked at** (contact sheets made from the snapshots and the simulator's frames, in `/tmp/boop-review/sheets/`).

| Sheet | From |
| --- | --- |
| `now1.png`, `now3.png` | `snaps/overview-{working,needs-you,gel,crowded,celebrating,asleep,long-notices,needs-you-said,offline}-*.png` |
| `boop.png` | `snaps/boop-{light,first-day-light,ring-full-dark,long-light}.png` |
| `world.png` | `snaps/world-{light,card-light,off-light,arrivals-many-light}.png` |
| `onb1.png`, `onb2.png` | `snaps/onboarding-1…9-*-light.png` |
| `set.png` | `snaps/settings-{light,world-off-light}.png`, `overview-{no-key,quiet}-light.png` |
| `gel-moods.png` | `/tmp/boop-sim/v1-polish-d3b1e3/gel/moods/*.png` (all 42 emotions) |
| `gel-states.png` | `…/gel/states/*.png` (23 states) |
| `gel-v1.png` | `…/gel/v1/*.png`, `growbar/`, `wish/`, `notice/` |
| `gel-lane.png` | `…/gel/lane/*.png`, `drawer/open.png`, `drawer/scrolled.png` |
| `gel-play.png` | `…/gel/pastimes/`, `finish/`, `acts/`, `occasions/`, `reasons/` |

**Not done, and why.** The simulator's page in a browser (`make -C internal simulator`): the same firmware's frames were read from `make -C internal sim` instead. `boopctl run` and `boopctl shot` on the panel: the owner's app was connected. A met wish and a stage's level-up live: the scripted brain cannot offer a wish. Anything with Jev: no prompt changed, and the nine recorded runs answered the questions.

**What is a guess.** The line counts a change deletes (§8.3) are estimates from file sizes. The share of requests that Top 3 saves is an estimate. The pastime rates are a model of the dealer's code, not a measurement. The readings of faces "at arm's length" are from frames at 320 × 240 on a monitor, not from the AMOLED.
