# Boop runtime review: a buyer's day, headless

Date: 2026-11-09. Worktree: `/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish` (branch `v1-polish`, HEAD `270ee70c`). Nothing in the repo was changed (`git status` is clean).

## 0. How I ran it

- Runtime: `.build/debug/Boop --headless --state-dir /tmp/br1 --link usb:/tmp/brb.sock --brain scripted --no-open --debug`.
- Board: the native simulator (`firmware/.pio/build/native/program --live`, gel face) behind `linkkit-bridge --port /tmp/brsim.port --socket /tmp/brb.sock`. No Bluetooth, no USB board, no Jev, no Keychain.
- Agents: real hook payloads through `.build/debug/agent-hook claude|codex --keep-text`, with `HOME=/tmp/brhome` and `AGENT_HOOKS_SOCKET` set to the run's socket. One long-lived parent process for each session, because agent-hooks takes the hook's parent for the agent's process.
- You: touches through the board's `dbg.touch` and `dbg.imu`; words, presence and the clock through `{"dev":…}` lines.
- World: `npm run dev` in `internal/world` (port 8787), three more headless Boops (`/tmp/br2`…`/tmp/br5`).
- All processes I started are stopped. Two processes were there before me and I left them: the owner's `Boop --debug --state-dir …/Boop-dev` (pid 99222) and a `native/program` started at 20:52 (pid 99904).

Evidence files, all under `/tmp/boop-review/runtime/`:

| File | Holds |
| --- | --- |
| `headless.log` | Scenes A–F (the full debug log; prompt lines start with `│`) |
| `marks.txt`, `lg.py` | Scene marks by wall time; `python3 lg.py A3 A4` prints a scene without prompts |
| `board.log` | What the board said (`ev ended`…) in scenes A–B |
| `world-recv.log`, `world-night.log`, `world-s1.log`, `world-s2.log` | World scenes G |
| `care-live.log`, `ring.log`, `care.log` | Ask, ring and level-up reruns; the demo run |
| `world_e2e.txt`, `counts-live.txt`, `snaps/` | The e2e output, `--counts` output, popover snapshots |
| `/tmp/br1` | The state folder of scenes A–F (`debug.jsonl`, `transcript/`, `daily-counts.jsonl`) |

Limits of this run. Read every finding with them in mind.

- The scripted brain answers every pass with "excited, small, say start". So I can say **which events ask the brain** and **what the rules send**. I cannot say what Jev picks.
- The Mac's clock was advanced with `{"dev":"advance"}`. The simulated board runs in real time. So after a jump, lines like `no ended for do … gave up` are my harness, not Boop.
- The run started at 21:06 local, so scenes A–C are "evening" and D crosses a night.

## 1. The scenes

### a. One agent: prompt, calls, tests, finish, failed turn, stopped turn

What the board was told, in order (`headless.log`, 21:08:20–21:09:40):

```
21:08:20.317 link rules → {"t":"do",…,"name":"starting","play":"if_free","args":{"ctx":"session","reason":"new claude thread"}}
21:08:20.826 link rules → {"t":"state","base":"working","mood":"calm","busy":1,…,"xp":0}
21:08:20.831 link brain → {"t":"do",…,"name":"react","play":"next","ttl":5000,"args":{"reason":"you asked claude","say":{…},"mood":"excited","loops":1}}
21:08:23.334 link rules → {"t":"state","base":"working","act":"analyzing",…,"calls":[[0,1,"read"]]}
21:08:24.878 ▸ 15 act start: claude is running tests on "api". Boop has strapped itself to a sled facing a wall, by itself, and is holding its breath.
21:08:24.878 link rules → {"t":"state",…,"act":"testing",…,"wact":["tests","running tests",1]}
21:08:25.039 link rules → {"t":"state",…,"wact":["tests","PASS",1,"p"]}
21:08:42.903 link rules → {"t":"do",…,"name":"call","play":"next","ttl":1500,"args":{"a":0,"w":"done","as":"gather"}}
21:08:42.907 link brain → {"t":"do",…,"name":"task_complete",…,"args":{"outcome":"success","turn":2,"who":{"agent":"claude","thread":"api"},…}}
```

- Working look, activity, work stream and the tests act all arrive at once from the rules. Good.
- XP in `state.xp`: read +1, edit +1, test pass +1, failed tests +0, turn done +5. Matches §5.2.
- **Three failed test runs in a row made no moment at all.** The brain was never asked:

```
21:08:28.205 harness: tool_end passed over for a newer act_end
21:08:28.205 harness: act_end held: the small version of the act has no voice
21:08:35.545 ▸ 39 tool end: claude's tests failed again on "api", 3 times in a row.
21:08:35.545 ▸ 40 act end (no pass): claude's tests failed on "api". Boop has hit the wall and slid down it, by itself.
```

  The buyer sees only the low sign `FAIL` three times. The same happened for "tests passed after failing" (21:08:39.891) and for a failed deploy in a full act (`act_end held: the check's failure is its own line`, 21:09:23.652, but that line was already passed over). The eval `04-tests-fight-back` passes with `--scripted` because the eval makes no `act` events (0 `act_start`/`act_end` in `/tmp/boop-eval/20261109-213202-20893.jsonl`). So the eval says Boop gets determined at failing tests, and the real runtime stays silent. See bug 1.
- Failed turn (`StopFailure`): `task_complete` with `"outcome":"failure"`. No `call` word for it (a done turn gets "done", a stopped one "stopped").
- Stopped turn (Esc, `PostToolUseFailure` with `is_interrupt`): `call` word "stopped", then Jev's `react`. The line says `a very short turn, no tool calls` though one call had started.
- No finish or stopped-turn `do` carries a `reason`. The thread's name (`who`) stands in for it.

### b. Needs-you

Needs-you while another agent finishes (21:10:07–21:10:25):

```
21:10:08.056   … needs_you (rule): Boop showed that claude needs you.
21:10:08.057 link rules → {"t":"state","base":"working","mood":"calm","attn":{"agent":"claude","project":"api","more":0,"id":1658002613},"busy":1,…}
21:10:08.058 device: do 618056289 ended cut (needs_you)
21:10:10.901 harness: last_message held: something needs you
21:10:17.982   ✓ open_thread (rule): Boop opened the thread that needs you on the Mac.
21:10:20.432 ▸ 116 needs_you end: claude finished turn 1 on "web": done, a long turn, 1 tool call.
    It finished while another agent needed you; nothing needs you now.
21:10:20.437 link brain → {"t":"do",…,"name":"task_complete",…"who":{"agent":"claude","thread":"web"}…}
```

- Needs-you cut the playing moment at once. The other agent's finish waited and played after the answer. A tap opened the thread. This is right, and status outranked everything.

Ring close under needs-you (21:10:51–21:11:05):

```
21:10:52.856 link rules → {"t":"state",…"attn":{…},…,"xp":100}          ← ring closes, nothing plays
21:10:57.064   · needs_you (rule) ended
21:10:57.066 ▸ 305 level (no pass): Boop reached level 2.
21:10:57.066 ▸ 306 ring (no pass): Today's ring is full: Boop's done for the day.
21:10:57.066 link rules → {"t":"do",…,"name":"react","play":"next","ttl":5000,"args":{"sign":"Level 2!","reason":"level 2!","low":true,"mood":"proud","loops":2}}
21:11:02.073   ✗ react (309) didn't happen: waited too long
```

- The ring and level waited for the answer. Correct by principle 8.
- **The ring-closed moment ("Today's done!") did not play.** One moment plays for both, and the level wins (`Core.swift:523-530`). On day 1, and on every day for a buyer who filled every earlier ring, the 100th XP is also a level. So that buyer never sees "Today's done!" on the board.
- The level-up took 8.4 s. Jev's reaction to "You answered claude" waited 5 s behind it and dropped.

Needs-you 0.6 s after the level-up starts (`care-live.log`, 12:29:54):

```
12:29:54.277 link rules → {"t":"do","id":405603354,"name":"react",…"sign":"Level 2!"…}
12:29:54.278 link rules → {"t":"do","id":405603355,"name":"react",…"sign":"Level 2!"…}
12:29:54.911 link rules → {"t":"state",…"attn":{"agent":"claude","project":"api",…},…,"xp":100}
12:29:54.911 device: do 405603354 ended done
12:29:54.912 device: do 405603355 ended skipped (needs_you)
```

- Needs-you won again. But the level-up was on screen for 0.6 s and never came back after the answer (it is marked celebrated as it starts). A greeting cut this way tells its dream again; a level-up does not. The buyer loses the day's one growth moment.
- The level-up `do` is sent twice. See bug 2.

### c. Three agents, a push, a helper, a long turn

- Three session starts gave three `starting` cards and three prompt reactions in 3 s. The helper's word (`"w":"helper"`) was `skipped (late)` behind them. Fine.
- Helper: `state` got `"helpers":1`, the word "helper", then "back" on `SubagentStop`. No brain pass for a helper coming back.
- To-do: `"todo":{"done":1,"total":3}` at once.
- Tiers: `tier1` at 35 s, `tier2` at 1 min, `tier3` at 2, `tier4` at 5, `tier5` at 10. A rest under 30 s keeps the stretch, so a new turn can start at `tier2` or `tier3`. By design (`Tags.stretchRestMs`).
- Working check-ins asked the brain at 5, 10, 16 and 36 min (`reason":"working 5 min"`), about the longest turn only.
- Full push act after 30 min: `"wact":["push","git push",1]`, then `["push","shipped!",1,"p"]`, with brain passes at start and end. A `vercel --prod` also plays the push rocket ("claude is pushing").
- **Three finishes within 2 s: the third was never shown.**

```
21:14:01.264 link brain → {"t":"do","id":618056316,"name":"task_complete",…"who":{"agent":"claude","thread":"api"}…}
21:14:02.281 link brain → {"t":"do","id":618056318,"name":"task_complete",…"who":{"agent":"claude","thread":"web"}…}
21:14:03.296 link brain → {"t":"do","id":618056319,"name":"task_complete",…"who":{"agent":"codex","thread":"infra"}…}
21:14:08.304   ✗ react (437) didn't happen: waited too long
21:14:08.304 device: do 618056319 ended skipped (late)
```

  Each finish plays about 5 s and a waiting moment lives 5 s. So with three agents that end close together, one finish and its thread name are lost. The strip's idle count is the only trace. This breaks "finishes are never hidden" in practice, by other finishes. Bug 3.
- Note on my harness: in this scene the act looked stuck on "delegating". That was my mistake (I never ended the `Task` call), not Boop's.

### d. Lock, unlock, away, night, morning

```
21:14:54.721 ▸ 441 lock start: You locked the Mac, first time in a while.
21:14:54.723 link brain → {…"args":{"reason":"you locked the Mac",…}}
21:14:59.741 ▸ 445 lock end: You unlocked the Mac after under a minute.
21:14:59.746 link brain → {…"args":{"reason":"you unlocked it",…}}
```

- Every lock and unlock asks the brain, each with a plain reason. A 20 s lock/unlock pair costs two Jev requests.
- An away needs a 10 min lock or 30 min with no input (`PresenceDetector.swift:15-19`). 15 min idle with no lock is nothing, as designed.
- Night lock (22:35): the caption was the day's turns: `"reason":"10 turns today"`. Good.
- At night with idle agents, Boop fell asleep after 10 quiet minutes: `{"t":"do",…"args":{"reason":"quiet for 10 min"}}`.
- **While I was away and locked for 9 hours, a check-in asked the brain every hour**, and each answer went to the board:

```
21:15:39.202 ▸ 476 heartbeat (no pass): Nothing has happened for 3 hours.
21:15:39.206 link brain → {"t":"do","id":618056329,"name":"react","play":"next","ttl":5000,"args":{"say":{…},"mood":"excited","loops":1}}
```

  `debug.jsonl` confirms a real pass for each (`PASS for 476 held None`). With Jev that is about one paid request an hour for an empty chair, on every Mac that stays awake. Jev may answer "none", but the request is still made. The `(no pass)` label on those lines is wrong (oddity 12).
- The dream came 2.5 h into the sleep:

```
21:15:38.598 memory: dreaming (asleep, and no agent works) about Monday and Tuesday
21:15:38.600 memory: dreamed about Monday and Tuesday (2026-11-10): you poked it once; 10 turns on "api", 1 failed
```

  Two things are wrong for a buyer. All the work was on Monday evening, and the dream ran at about 01:25 on Tuesday, yet it says "Monday and Tuesday". And the 10 turns were on three threads (api 6, web 3, infra 1), but the sentence puts all 10 on "api" (bug 5).
- Morning (07:40, first showing up after 5:00):

```
21:15:49.400 ▸ 508 presence end: You came back to the Mac after 9 hours away.
    Boop dreamed about Monday and Tuesday: you poked it once; 10 turns on "api", 1 failed.
21:15:49.401 link rules → {"t":"state","base":"asleep",…"when":["morning","tier5","hatchling"],"xp":2}
21:15:49.408 link brain → {…"name":"react",…"args":{"reason":"day 1: 1 failed","greeting":true,…}}
```

  The dream is told once, and the ring is back at 0 (+2 for coming back). But the board's caption for the first hello of the day is **"day 1: 1 failed"**. `MemoryReader.fact` picks strokes, then talks, then failures, then turns. A day of 10 turns with one failure is summed up by its failure (oddity 6).
- After the greeting the board stayed `"base":"asleep"`, because all three agents had rested over an hour.

### e. Care and XP

Measured on the live runtime (`headless.log` 21:18, `care-live.log`, `ring.log`):

| What I did | XP added | §5.2 says | Note |
| --- | --- | --- | --- |
| Tool call that didn't fail | 1 | 1 | |
| Tool call that failed | 0 | 0 | |
| Turn done | 5 | 5 | Failed or stopped: 0 |
| Coming back after an away | 2 | 2 | A short unlock gives 0 |
| Stroke | 3 | 3 | Three strokes in 9 s gave 9 |
| Lean (finger held 2.5 s) | 3 | 3 | |
| Poke ×7 | 0 | not listed | `Touch.poke.isCare` is true, but `Growth.xp` counts only `.gesture` events. A test pins "a poke nothing" |
| Ruffle (wrong-way stroke) | 3 | not listed | A rough touch earns care XP |
| Shake ×3 | 9 | not listed | A shake earns care XP each time |
| Word to Boop ×2 | 6 | 3 each | |
| Answered ask ("fav snack?", tap on "cookie") | 5 | 5 | Forced with the dashboard's pass |
| Helper back | 2 | 2 | From `GrowthTests.testXPComesFromTheAgentsWorkByRule`; in my live run the ring was already full |
| Met wish | 20 | 20 | From `GrowthTests.testCareEarnsXP` only. I could not make a wish headless: a wish is offered only on a real event's pass (`MomentOutput.swift:122-125`), the scripted brain always answers sign "none", and `{"dev":"answer"}` has no event (`harness: forced answers left out: ["react.sign"]`) |

- The ring caps at 100: `state.xp` stayed 100 through 3 more calls and 2 done turns. `--counts` and the status show `today_xp 100`.
- Past 100 the buyer sees nothing new on the board: no bar, no moment. The Mac's Boop tab says "Today's ring is full. Nice work." (`snaps/boop-ring-full-light.png`).
- At 5:00 the ring is 0 again and the tab keeps the week's rings.
- Care has no limit by time or by source. 34 strokes, or 34 shakes, close the ring in about 2 minutes with no agent.
- Through all of this care the board's Doing stayed `"base":"asleep"`, at 8 in the morning with the buyer stroking and talking to it, because no agent had worked for an hour. Each touch got its moment, then Boop was asleep again.
- A demo never counts XP (`state` has no `xp` in `care.log`). By design.

### f. A quiet day with no agents

Five hours at the Mac, no agent open, clock stepped by 5 minutes (21:19:35–21:20:04):

```
21:19:38.493 ▸ 585 heartbeat: Nothing has happened for 40 min; no agents are open.
21:19:42.089 ▸ 589 heartbeat: Nothing has happened for 80 min; no agents are open.
21:19:42.092 link brain → {…"args":{"reason":"no touch in 1 h",…}}
21:19:45.700 ▸ 593 heartbeat (no pass): Nothing has happened for 2 hours.
21:19:51.146 ▸ 597 heartbeat (no pass): Nothing has happened for 3 hours.
```

- Six brain passes in five hours: idle check-ins at 40 and 80 min (the gap is doubled with no agent), then one an hour. After two hours with no Boop event, the buyer at the Mac gets the same hourly check-in as an empty chair.
- Rules made zero moments in those five hours. The board was `asleep` the whole time. Everything else (a musing, an ask, a wish, a notice) is Jev's pick at one of those six passes. The limits in code are: a musing at most once an hour, 3 asks a day, about one wish a day, 2 notices a day. The plan's own number is that 36 of 83 check-ins get a moment. So a quiet five hours gives about two or three small moments, maybe none.
- "Nothing has happened" means no event for Boop. Typing on the Mac all day without an agent is "nothing".
- The first check-in's `do` has no reason; the second says "no touch in 1 h".

### g. World gestures

Local world, receiver "Rex" at midday (`world-recv.log`), senders "Sol" and "Tam":

```
12:21:59.000 ▸ 2 world: Someone in Asia or Oceania booped Rex.
12:21:59.005 link brain → {…"args":{"sign":"boop back!","reason":"someone booped Rex",…}}
```

- Idle: a boop plays, with a sign and a plain reason. Good. It arrived at the receiver's next check, up to 10 minutes after it was sent.
- **Three gestures arriving together played nothing:**

```
12:22:09.013 harness: world passed over for a newer world
12:22:09.013 harness: world passed over for a newer world
12:22:09.014 harness: world held: past the hour's world moments: the World tab counts it
12:22:09.015 ▸ 6 world: Someone in Asia or Oceania waved at Rex.
12:22:09.016 ▸ 7 world: Someone in Asia or Oceania sent Rex a heart.
12:22:09.016 ▸ 8 world (no pass): Someone in Asia or Oceania booped Rex.
```

  The wave and the heart were inside the 3-an-hour limit. They were passed over for the newest event, and the newest was the one over the limit. Gestures always arrive in batches (a reply every 10 minutes), so this is the normal case, not a corner. Bug 4.
- The 3-an-hour limit itself holds: the 4th of the hour is logged with `plays:false`. A gesture released after waiting plays even past the limit.
- Sender's side: the server stops a 4th gesture to one buddy in an hour: `12:22:24.012 dev: the boop didn't go`.
- A cheer with no ship: the server took it, and the board said `"sign":"we shipped!","reason":"a cheer for you!"` under the line "Someone in Asia or Oceania cheered your ship." Rex had pushed nothing.
- While something needs you: the heart waited, and came back after the answer:

```
12:22:52.782 ▸ 34 world: While you were away, someone in Asia or Oceania sent Rex a heart.
```

  It waited correctly. The words are wrong: the buyer was not away, they were answering an agent.
- At night (`world-night.log`, receiver "Nox" at 02:30): a boop and a heart went to `world-waiting.json` and nothing played. They came back as one line at the first tick after 05:00: `While you were away, someone booped Nox and one sent Nox a heart.` with the sign "boop back!". The same "away" words, with the buyer at the Mac. A night owl working from 22:00 to 05:00 gets no world moment at all in those hours.
- Server restart: a sender whose key the server no longer knew joined again by itself at its next heartbeat.
- Offline: `world: sent a wave` then `dev: the wave didn't go`. No other sign in the log.

## 2. XP for realistic days

Rules confirmed in `app/BoopKit/Core/Growth.swift:53-80`, `app/BoopKit/Memory/GrowthStore.swift:92-106` and `internal/app/Tests/GrowthTests.swift:30-63, 92, 122`. Work spread evenly over 09:00–18:00, 5% of calls failing, 90% of turns done:

| Day | Work XP offered | Times the ring | Ring closes | Turns to close |
| --- | --- | --- | --- | --- |
| Light: 5 turns, 40 calls | 60 | 0.6× | never by work alone | 8.3 |
| Modest: 10 turns, 120 calls | 161 | 1.6× | 14:35 | 6.2 |
| Typical: 30 turns, 400 calls | 523 | 5.2× | 10:43 | 5.7 |
| Heavy: 80 turns, 1,500 calls, 20 helpers | 1,825 | 18× | 09:30 | 4.4 |
| 3 agents in parallel: 150 turns, 4,000 calls | 4,595 | 46× | 09:12 | 3.3 |

- In my own run one turn with 77 reads gave 82 XP.
- Care in a devoted day: 4 comings back (8) + 5 strokes (15) + 3 words (9) + 1 ask (5) + 1 wish (20) = 57 XP. On a typical day that is 11% of what work offers, and 83% of all XP earned is thrown away by the cap.
- **Does care matter? Only for the light user.** For anyone who uses agents for an hour or two, calls at 1 XP each close the ring before lunch whatever they do to Boop. After that a wish met (the biggest care reward, 20 XP) shows nothing in growth. Care only changes the outcome on days under about 8 turns.
- The reverse also holds: with no agents, 34 strokes or shakes close the ring in 2 minutes.
- Level = days with a full ring. Sprout at day 4, Buddy at day 14, Chonk at day 29 at the soonest. A daily agent user has seen every size in about 6 working weeks; after that a level-up is a number.
- Because the ring closes at the same XP for everyone who uses agents, the ring does not tell a good day from a normal one. It reads as "you used an agent today".

## 3. Daily counts

`Boop --counts --state-dir /tmp/br1` after scenes A–F (`counts-live.txt`):

```
days touched: 2 of 2
touches: 16, 16 with no wish open
wishes: 0 made, 0 met, 0 given up, waiting - on average
threads opened from the board: 1
needs you: 2, 2 answered, in 0 min on average
spoken: 11.9 an hour at the Mac (66 in 333 min)
hushes: 0; days on Quiet: 0; volume: 0
face down: 0
unplugged: 0 min, on 0 day(s); disconnects: 0
failures: 5
level: 2
```

Every count kept (`app/BoopKit/Memory/DailyCounts.swift:9-28`): `day`, `touches`, `touchesNoWish`, `wishesMade`, `wishesMet`, `wishesGaveUp`, `wishWaitMs`, `threadsOpened`, `needsYou`, `answered`, `answerMs`, `spoken`, `hereMinutes`, `hushes`, `faceDown`, `disconnects`, `unpluggedMinutes`, `failures`, `quiet`, `volume`, `level`.

| Pillar | Counts that measure it | What is missing to know it works |
| --- | --- | --- |
| 1 Status monitor | `needsYou`, `answered`, `answerMs`, `threadsOpened`, `failures`, `disconnects`, `unpluggedMinutes`, `hereMinutes` | Turns and finishes a day; finishes played against finishes dropped (late, skipped); answer time in seconds (the summary prints "0 min" for a 44 s average); taps on a finish apart from taps on needs-you; days with you here but no hook at all (hooks broken) |
| 2 Friend | `touches`, `touchesNoWish`, the wish counts, `spoken` per hour, `hushes`, `quiet`, `volume`, `faceDown` | Words to Boop (push-to-talk uses); asks asked, answered, ignored; greetings and dreams told; notices played; moments played by kind and moments skipped; which touches (a stroke and a shake both count 1) |
| 3 A buddy that grows | `level` only | Today's XP; whether the ring closed and at what hour; XP by source (work against care); XP past the cap; whether the level-up was seen or cut; Boop-tab opens |
| 4 A world | none | World on or off; gestures sent, received, played, held, over the limit; World-tab opens; cheers; time from a gesture sent to seen |

Oddities in the counts: `spoken` counted 66 moments with volume 0, so it is "moments with a take", not "heard". `failures` adds failed turns and failed acts into one number.

## 4. The world

`internal/tools/world_e2e.py http://localhost:8787`: **PASS**, exit 0.

```
world e2e: http://localhost:8787, {'ok': True, 'db': True}
world e2e: joined, Mochi 14d981b0…, Bean f3e011d6…
world e2e: each sees the other in the world
world e2e: Bean got {'count': 1, 'from_region': 'asia_oceania', 'held': True, 'specific_type': 'boop'}, Mochi got {'count': 1, 'from_region': 'asia_oceania', 'specific_type': 'wave'}
world e2e: PASS, both left and nothing stays
```

`npm run dev` needed no install and no env vars (Node 26 against `engines` 24.x, it ran).

**What is sent** (`app/BoopKit/World/WorldWire.swift:90-104`, `internal/world/fixtures/buddy-state.json`):

- Join: `name`, `utc_offset`. The reply gives `id` and `key`, kept in `world.json` in the state folder.
- Each send: `seq`, `name`, `level`, `stage`, `utc_offset` (minutes, to the quarter hour), `activity` (coding, testing, shipping, waiting, idle, asleep), `day`, `xp_today`, `added` {`turns`, `tests_passed`, `ships`, `lines_changed`}. The server refuses any other key. No country, no time zone name, no thread or project.
- A gesture: `to`, `kind`. The receiver gets `kind`, `from_region` (one of three), `at`.

**Cadence** (`WorldLink.swift:13-25`): a send at once on a change of activity, level, ring or name, at least 10 s apart; counts wait up to 3 min; a heartbeat every 10 min; "asleep" at once on a lock or a quit. Gestures come in a send's reply, at an unlock or a coming back. The snapshot is fetched only while the World tab is open, every 30 s. After a failure it backs off from 30 s to 15 min.

**An empty world.** With three buddies and no agent working, the snapshot was `"awake":0,"total":3`, every buddy `"activity":"asleep"`. A Boop with no agent open is asleep, and asleep is what the world sees (`Runtime+World.swift:44`). So a buyer who opens the World tab in a world of 0–5 buddies sees tiles "0 awake · 0 coding · 0 tests today", a band with their own dot and a few grey ones, and "all asleep" for each region, even while all of them sit at their Macs. There is no goal and no total for the year on the tab (the tiles are awake, coding, tests today). Nothing invites a second look.

**Cheers can hardly happen.** The Cheer button shows only while a buddy's activity is `shipping` (`app/Boop/Views/WorldPane.swift:105`). That is true only while the push command runs with no result (`Runtime+World.swift:47`). The world sees it for 10 s or a little more, and a viewer's tab polls every 30 s. In a small world nobody will catch a ship.

**Offline.** The tab says "The world can't be reached just now. Boop will keep trying." or, with an old snapshot, "The world isn't answering, so this may be out of date." A gesture fails without a retry. Counts not yet sent are dropped at quit ("Counts aren't kept across a quit", `WorldLink.swift:437-440`), so work done offline never reaches the totals.

**Limits.** Server: 20 gestures an hour from one buddy, 3 an hour to the same buddy, 5 joins an hour from one IP, one send each 10 s, 100 XP a UTC day, counts clamped by the minute (`internal/world/src/limits.ts`). Mac: 3 boops, waves or hearts play an hour, one cheer moment each 30 min, and all wait at night, away or under needs-you (`WorldGestures.swift:14-18`).

**What could be abused, or feels off:**

1. **Three throwaway buddies can hide anyone's name.** Three reports hide a name (`REPORTS_TO_HIDE = 3`), each buddy may report any number of buddies, and one IP may join 5 an hour. One person can turn every name in the world into "a buddy".
2. `GET /v1/world` is public and lists up to 500 buddies with `id`, `name`, `level`, `utc_offset` and `activity`. Anyone can watch when a named buddy's person is coding, waiting or asleep, minute by minute. People name buddies after themselves.
3. `level` is whatever the Mac says, up to 1,000,000 (`LEVEL_MAX`). A card can show "level 999999".
4. A cheer needs no ship on the server. Any buddy can make another's board say "we shipped!" (seen in scene g).
5. Goal counts can be faked up to 50 tests a minute for each buddy: 72,000 a day, 360,000 with five buddies from one IP. A "million tests this month" goal falls to one person in three days.
6. The name filter folds only Latin letters and digits (`names.ts:42-49`). A banned word written with Cyrillic look-alikes passes `ALLOWED` and the word lists.
7. The Mac's Boop day runs 05:00 to 05:00 local, the server's XP cap is by UTC day. In a zone far from UTC two full local rings can land in one UTC day, and the server counts 100 of the 200.
8. A buyer in the 22:00–05:00 hours never gets a world moment live, and the held line says "While you were away" when they were not.

## 5. Bugs and oddities

Bugs (I am confident of these; each has a log above):

1. **Failed checks never ask the brain in the real runtime.** `mellowharness/Sources/MellowHarness/Harness.swift:604-606` passes a `tool_end` over for any newer waking event; the work act's `act_end` is always newer; `app/BoopKit/Core/TranscriptView.swift:334-336` then holds that `act_end` ("the small version of the act has no voice", or "the check's failure is its own line"). So tests failing 1, 2, 3 times, and passing after failing, get no moment. The eval `characters/boop/evals/04-tests-fight-back.json` does not catch it, because eval steps make no act events.
2. **The level-up `do` is sent twice.** `app/BoopKit/App/Runtime.swift:792-811` (`grow` → `playGrowthDue` inside a pipeline step). `ring.log` 12:31:01.956 and .957: two `do`s "Level 2!", and the `level` and `ring` lines printed twice with the same ids. The second is `skipped (late)` only because the first lasts 5.9 s against a 5 s wait. A shorter first one would show "Level 2!" twice.
3. **A third finish in a row is dropped.** `app/BoopKit/DeviceLink/BoopDevice.swift:36` `reactionTTL` (5 s) against finishes of about 5 s. `headless.log` 21:14:08.304. The finish of a 46-minute codex turn was never shown.
4. **Gestures that arrive together are all lost when the last one is over the hour's limit.** `app/BoopKit/World/WorldGestures.swift:47-51` logs one event for each gesture; the harness keeps only the newest (`Harness.swift:604`); `TranscriptView.swift:339` holds it. Also, without the limit, two gestures in one reply give one moment for the last only.
5. **The dream puts every turn on the top thread.** `app/BoopKit/Memory/MemoryReader.swift:254`: `"\(t.turns) turns on \"\(t.thread)\""`. Ten turns on three threads read as `10 turns on "api"`. `MemoryPipeline.swift:280` writes the same shape into memory.
6. **The ring's own moment never plays when a level comes with it.** `app/BoopKit/Core/Core.swift:523-530`. For a buyer who fills each ring, that is every day.
7. **A level-up cut by needs-you is gone for good.** `GrowthStore.played` (`GrowthStore.swift:118-131`) marks it as it starts; `care-live.log` 12:29:54–12:30:02 shows no second try.
8. **Shakes and wrong-way strokes earn care XP; pokes do not.** `app/BoopKit/Core/Touch.swift:24-28` (`isCare` has `.ruffle`, `.dizzy`, `.poke`) with `app/BoopKit/Core/Growth.swift:68` (only `.gesture`). Measured: 3 shakes = 9 XP, 7 pokes = 0. No test pins ruffle or shake.
9. **A cheer needs no ship.** `internal/world/src/app.ts:285-309` checks only the kind and the limits.
10. **Runtime warning in the world's sender:** `warning: data race detected: @MainActor function at BoopKit/Runtime+World.swift:135 was not called on the main thread`, on every gesture sent (`world-s1.log`). Seen headless; I did not check the app.

Oddities (true to the code, but they read wrong to a buyer or a reader):

11. Hourly check-ins ask the brain all night while you are away (`TranscriptView.swift:1095-1096`; no hold for away in `hold`, lines 320-350). Cost, and with a brain that answers, a voice at 3 am.
12. `debug` prints `heartbeat (no pass)` for hourly check-ins that did get a pass (`Pipeline.swift:111-113` writes the view with `wakes: false`; `DebugLog.swift:336`).
13. The morning caption "day 1: 1 failed" (`MemoryReader.swift:262-267`, `Narration.swift:31-35`).
14. "Boop dreamed about Monday and Tuesday" at 01:25 on Tuesday, for a Monday evening.
15. "While you were away" for gestures held by night or by needs-you (`world-recv.log` 12:22:52, `world-night.log` 02:24:43).
16. A stopped turn says "no tool calls" after one interrupted call (21:09:37.193).
17. The work stream's word for `git push origin fix-nav` was "origin" (`"calls":[[0,8,"origin"],…]`, 21:13:49.219).
18. A failed turn gets no `call` word; done and stopped turns do.
19. Boop's Doing stays `asleep` through strokes, words and the morning greeting when no agent has worked for an hour. And the world then shows the buddy "asleep".
20. `--counts` prints the needs-you answer time in whole minutes ("in 0 min on average" for 44 s), and counts "spoken" at volume 0.
21. In a demo on a board, `{"you":"answer"}` logs "You answered" and then, when the board's ask times out, "You didn't answer Boop's 'fav snack?'" (`care.log` 21:25:29).
22. HISTORY was empty in the prompt of an idle check-in 35 minutes after ten turns (`headless.log`, the pass at 21:15:28). I did not chase why.

Not checked: a met wish and a stage level-up (5, 15, 30) live; Codex needs-you; a world goal; the real app's World tab (only snapshots); anything with Jev.
