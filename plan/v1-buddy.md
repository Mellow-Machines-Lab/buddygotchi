# Boop v1: a status monitor, a friend, a buddy that grows, and a world

Updated 2026-11-08. The owner agreed the direction on 2026-11-08, with XP kept
simple; the world's build is in [world.md](world.md). Work goes on branch
`main-v2`; `main` stays as it is. It comes from the owner's talk of 2026-11-08 and builds on main
`b87a22c2`.

## 0. What this is

The owner's frame: at its core, Boop is four things. This plan says what each
one is, what Boop has of it today, what changes in behaviour, UI and
architecture, and in what order to build it.

**"A dumb buddy" for v1** is read here as: Boop as it is now, made whole on
these four things, with no new kind of intelligence. The brain stays Jev,
memory stays the on-device writer, and the voice stays the recorded bank. Who
pays for the brain, a voice architecture, talking freely, and leagues are out
of scope (§10). If "dumb" meant "no Jev at all", that changes §3 and §6 a lot;
say so, and this plan gets a section on a rules brain.

## 1. The four tenets

| | Tenet | The promise | How often you feel it |
| --- | --- | --- | --- |
| 1 | **Status monitor** | You always know what your agents are doing, at a glance, and it's fun to watch | Every few minutes |
| 2 | **Friend** | It greets you, notices you, and remembers small things | A few times a day |
| 3 | **A buddy that grows** | Your work and care earn XP; it closes a ring each day and climbs levels forever | Daily |
| 4 | **A world** | It lives among everyone's buddies, and together they reach goals | Daily to monthly |

Each tenet feeds the next: your work (1) and your care (2) earn XP (3), and
your XP adds to what the world achieves (4).

## 2. Principles

These bind every decision below.

1. **Whole from day one.** A buddy at level 1 does everything useful. XP and the
   world only add moments, never features.
2. **No grind.** A full day's ring is the most a day can give. More work adds
   nothing. No streaks to lose.
3. **Nothing is ever lost.** XP and levels never go down. (This removes the
   decay built on 2026-11-03.)
4. **The small screen stays clear.** Nothing new lives on the board's screen
   all the time. The ring, the level and the world appear only when they change
   or arrive, and the Mac holds the detail.
5. **The world is cooperative.** Buddies don't rank or beat each other in v1.
   Everyone contributes, and when the world reaches a goal, everyone shares it.
6. **Install and go.** No account, no friends to add, no setup beyond today's
   onboarding.
7. **Privacy stays plain.** What leaves the Mac is listed in one place,
   shown at onboarding, and can be turned off. Never code, words, thread names
   or memory.
8. **Status outranks everything.** Needs-you and finishes are never hidden by
   XP or world moments.

## 3. Tenet 1: the status monitor

**Today:** strong. Needs-you with its screen, the agents' drawer, tap anywhere on
a finish, the low sign with the thread's name, the work acts (push, tests,
build), the falling words, the working look and its tiers.

**For v1, no new features.** Finish what's owed:

- The real-board checks in `plan/TODO.md`: frame rate with the Mac off, the acts'
  look, the low sign at arm's length.
- Working at night's frame rate.
- The `to-work` transition being cut by `starting`.

**The one rule that changes:** with world moments arriving (§6), the order of
what may play becomes, highest first:

1. needs-you; 2. listening (push-to-talk); 3. a finish and its sign; 4. a work
act; 5. your own touch; 6. Boop's reactions (Jev's); 7. world arrivals (a boop,
a cheer, a world goal); 8. pastimes.

World arrivals wait in line like any reaction, and drop if they're stale (a
boop more than a few minutes old is just narrated on the Mac).

## 4. Tenet 2: the friend

**Today:** the morning sequence (greeting, day count, dream), lock and unlock,
wishes, notices (`waiting`, `stretch`, `rough`, `late`), facts on existing
moments ("While you were gone…"), the remembered line on the low sign, the
written memory and its pane, eyes that follow a finger, the lean, tilt, the
listening nod, and a plain reason for every reaction.

**For v1, tune, don't add:**

- **Notices may be too faint** (the judge, 2026-11-05): `stretch` and `rough`
  often play with no visible change. Make a notice's face clearly different from
  a quiet moment.
- **Idle may be too quiet:** 36 of 83 check-ins have a moment, 8 a real face.
  Find the middle with real use.
- **Bland words:** test labels like "Verify" and "Trial", and proud finishes
  nearly everywhere.
- **The daily counts** (built) are how we'll know: touches with no wish open,
  wishes met, hushes and Quiet.

**What the friend gains from tenets 3 and 4, at no extra concept:**

- Closing the ring is a friend's moment: Boop is glad, and the reason says so.
- A boop from someone in the world is a moment between you and Boop: "Someone in
  Lisbon booped Boop."
- World goals give the morning something to say: "The world passed a million
  tests overnight."

## 5. Tenet 3: a buddy that grows

### 5.1 The model

**XP** is the one number. It comes from the agents' work and from your care.

**The daily ring** is today's XP, from 0 to the day's goal, **100 XP**. When it's
full, it's full: nothing more counts today. It starts again at 5:00, Boop's
day.

**The level** comes from lifetime XP. It has no maximum, and never goes down.

### 5.2 Earning (kept simple, 2026-11-08)

The owner asked for simple rules and nothing clever, to build on later. So: a
fixed XP per thing, one daily cap, nothing else.

| What happens | XP |
| --- | --- |
| A turn that ends done | 5 |
| A tool call that ends without failing | 1 |
| A helper coming back | 2 |
| A touch that's care (stroke, lean, nose boop…) | 3 |
| A word to Boop | 3 |
| An answered ask | 5 |
| A met wish | 20 |
| Coming back to the Mac | 2 |

**The day's cap is the ring: 100 XP.** No limits by source, no bonuses, no
multipliers. What's earned past 100 in a day doesn't count.

### 5.3 Levels (kept simple)

**A level is 100 XP. Level = 1 + lifetime XP / 100.** So a full ring is a level:
your level says how many full days you've had together. No curve, no maximum,
never down.

### 5.4 The stages

The four stages (Hatchling, Sprout, Buddy, Chonk) and their art are built.
Two options:

- **A. Keep them as bigger level-ups** at levels 5, 15 and 30 (decided, 2026-11-08): Boop grows,
  with the existing ceremony. Not a concept to learn: just some level-ups that
  are bigger. *Recommended*: it's built, and it's a nice surprise.
- **B. Drop them.** One size of Boop. Simplest, and deletes the scaling code.

### 5.5 What the board shows

- **The ring:** the existing growth bar becomes today's ring. It shows only when
  XP comes in, for a few seconds, as now, and fills toward the day's goal.
  (A bar is clearer on this screen than a ring; "ring" is the idea's name.)
- **The heart** from a met wish still flies into it.
- **Closing the ring:** the bar fills, sparkles and goes; Boop's happy wiggle; the
  reason "Today's done. Nice work." Then, for the rest of the day, XP shows
  nothing on the board.
- **A level-up:** a short ceremony and a sign. At 5, 15 and 30 (option A), the
  growing ceremony.

### 5.6 What the Mac shows

- On the "Boop" tab (§7): the ring for today, the level, lifetime XP, and the next
  level's distance. A short history: the last 7 days' rings.
- "Today: 82 of 100", in plain words, no game jargon.

### 5.7 What changes in code

| Today | v1 |
| --- | --- |
| `Growth`: stages by XP, decay after 3 days, pools work 60, care 60, wish 40 | `Growth`: lifetime XP, today's XP, level = 1 + XP / 100, one daily cap of 100; no pools, no decay |
| `GrowthStore` keeps XP and stage | Keeps lifetime XP, today's XP and its day, and the level last celebrated |
| `state.xp` (percent through a stage) | `state.xp` becomes today's ring in percent; `state` gains the level only when it changes, as a tag or a field |
| `grew` events at a stage | `level` events at each level, a bigger one at 5, 15, 30 |
| Board: growth bar, the heart, stage scaling | The same bar as the ring; a ring-closed moment; level-up ceremony; stage scaling only under option A |
| CONTEXT's Boop row: stage, age | "Boop: level 12, 40 days old; today's ring 82 of 100" |
| Narration: grew | Level-ups, the ring closing |

**No migration:** Boop hasn't shipped, so XP starts from zero, and nothing old is kept (decided 2026-11-08).

## 6. Tenet 4: the world

### 6.1 What it is

Every buddy that's opted in appears in one shared world. You can see them all,
where they are (by time zone and country, never closer) and what they're doing,
and the world as a whole has goals that everyone's work counts toward.

### 6.2 What you see (the Mac's "World" tab, and later a web page)

- **The map:** a simple world map with day and night, from each buddy's time
  zone. Buddies on the night side sleep. Each buddy is a dot that shows, on
  hover or tap, its name, level, country and what it's doing.
- **What buddies do:** a few categories only: coding, testing, shipping, waiting
  on its person, idle, asleep.
- **Live numbers:** "214 buddies awake", "38 coding now", "12,400 tests passed
  today", by country too ("most active today: Brazil").
- **The world goal:** "1,000,000 tests passed this month: 742,000 so far", with
  a bar, and your own part: "You added 340."
- **Totals for the year:** "Together: 1.2 million lines changed in 2026."

### 6.3 How buddies interact

V1 keeps it to two gestures, both positive, both with no words:

- **Boop someone:** tap any buddy on the map. Their board plays a little bounce,
  and the reason says "Someone in Lisbon booped Boop." Fixed gestures only: a
  boop, a wave, a heart.
- **Cheer a ship:** when a buddy ships (the push act), it lights up on the map,
  and anyone can tap to cheer. The shipper's board plays confetti: "3 buddies
  cheered your ship!"

Limits: a few boops an hour sent from one buddy, a few received an hour shown on
the board (the rest are counted on the Mac: "and 12 more today"). Nobody can
boop you awake at night: at night, they wait for the morning sequence.

Later, not v1: **visits** (your buddy drops by another's desk at quiet times,
and a visitor peeks in on yours), a **leaderboard** of the week's XP, **world
moments** like New Year rolling across the map.

### 6.4 World goals and rewards

A goal is a total across everyone, over a period: tests passed this month,
ships this season, buddies awake at once. When the world reaches it,
**everyone gets the reward**, whether they helped or not.

Rewards that don't clutter the board:

- **A look for a few days.** World events become tags, like a holiday (`state.when`),
  so every board puts on a party hat or a crown, with the existing dressing
  system, and the reason says why.
- **A celebration moment:** a one-time ceremony on every board, at the next
  quiet moment, or in the morning sequence.
- **A line in memory:** "Boop was there when the world passed a million tests."

No XP bonus: it would break the ring's cap, and the reward is the shared moment.

One goal at a time, chosen by us on the server, so we can match the season.

### 6.5 What leaves the Mac

Sent only when the world is on:

| Field | Example | Why |
| --- | --- | --- |
| A random buddy id | `b_7f3a…` | To tell buddies apart. Made on first launch; not tied to you |
| Buddy name | `Mochi` | Shown on the map |
| Level | `12` | Shown on the map |
| Country | `PT` | From the Mac's region setting, for the map and country totals |
| Time zone | `Europe/Lisbon` | Day and night on the map |
| Activity | `testing` | One of six categories |
| Counts since the last send | `turns 3, tests_passed 2, ships 0, lines_changed 140` | The world's totals and goals |
| Today's XP | `82` | Your part of the goal; the server checks the daily cap |

**Never sent:** thread or project names, code, file names, commands, words you
said, prompts, agents' messages, memory, your name, your account, your IP beyond
what any web request reveals.

This changes two of Boop's ground rules, so they're named here for the owner's
decision:

- "Everything on the buddy. Nothing outside the desk." → the world needs a server
  and the Mac app's World tab.
- "Nothing leaves the Mac except Jev's request" → plus the table above, when
  the world is on.

### 6.6 Consent and names

- **Onboarding** gets one more step: "Join the world of buddies?", with the
  table above in plain words, and on by default. One tap to say no.
- **Settings:** a switch, and "What Boop shares" listing the table.
- **Off:** Boop works exactly as now; the World tab says it's off, and shows the
  world read-only (see below).
- **Names are public:** the server filters names (a word list, plus a check
  for links and numbers), falls back to "a buddy" if one fails, and has a
  report button on the map.

Open question: can someone with the world off still *see* the map, read-only?
Recommended: yes, since it's nice and costs nothing, but not be seen or
receive boops.

### 6.7 Cheating and fairness

XP and counts come from your own Mac, so they can be faked. In v1:

- The server rejects more than the daily cap of XP per buddy per day, and
  counts that are implausible (thousands of tests a minute).
- Rate limits on everything.
- No ranking in v1, so faking gains little. It matters only if a leaderboard comes.

## 7. The Mac app's UI

Today the popover has Overview, Memory and Settings. In v1 it becomes tabs, one
for each tenet that has something to show, with Settings apart:

| Tab | What it holds | From today |
| --- | --- | --- |
| **Now** | Needs-you first; the agents; Boop's mood and its reason; today's notable moments | Most of Overview |
| **Boop** | The ring and level; the last 7 days; what Boop knows about you; Boop's day (dream, notices) | Memory pane plus growth from Overview |
| **World** | The map; live numbers; the world goal and your part; boops and cheers you got | New |
| Settings | As now, plus the world switch and "What Boop shares" | Settings |

The popover's face of Boop (the mirror) stays at the top of every tab.

The menu bar icon stays as it is: needs-you shows, nothing about XP or the world.

## 8. The board's UI

Nothing new lives on the screen. What's added only appears:

| Moment | How it shows | Where |
| --- | --- | --- |
| XP comes in | The ring bar, a few seconds (as the growth bar now) | Bottom, the lane |
| The ring closes | The bar sparkles and goes; Boop wiggles; reason | Lane |
| A level-up | A short ceremony and a sign "Level 12!" | Low sign |
| A boop from the world | A bounce, the reason "someone in Lisbon booped you" | Face, lane |
| Cheers on your ship | Confetti, "3 buddies cheered your ship!" | After the push act ends |
| A world goal reached | The celebration, then the look (a hat) for some days | Whole screen once, then dressing |

The drawer, the strip, the needs-you screen and the finish don't change.

## 9. Architecture

### 9.1 Where the pieces go

The rules in `CLAUDE.md` still hold: decisions and effects stay apart, everything
goes through the transcript, the packages stay apart, and the brain is never on
the screen's path.

- **Growth** (`app/BoopKit/Core/Growth.swift`, `Memory/GrowthStore.swift`):
  rewritten for the ring and levels (§5.7). A pure model, tests pin the numbers.
- **The world client:** a new `app/BoopKit/World/`, Boop's own (it's about Boop's
  buddies, so it isn't a package). Three parts:
  - **`WorldPublisher`:** every minute while you're at the Mac, and at once on a
    change of activity, posts the §6.5 fields. It reads only the core's snapshot
    and the counts already kept (`DailyCounts`), so no new data is gathered.
  - **`WorldFeed`:** every minute, fetches the world's snapshot (the map, the
    numbers, the goal) for the World tab, and any gestures waiting for this
    buddy.
  - **Gestures and goals in:** each becomes a raw event in the transcript, a new
    kind `world` (`boop`, `cheer`, `goal`), so the view folds it into a line,
    Jev may react, and the reason says it. A goal reached sets a tag the core
    sends in `state.when`.
- **Off means off:** with the world off, neither runs; nothing is sent.
- **The board:** no new LinkKit message. Uses what exists: `state` (the ring's
  percent, the level when it changes, the world's tag), `do` reactions for the
  boop, the cheer and the celebration. LinkKit stays generic.
- **Jev:** CONTEXT's Boop row says the level and today's ring. A world line is like
  any event's. No world data in the prompt beyond those lines.

### 9.2 The server

A new, small service. It needs:

- `POST /buddy`: a buddy's state (§6.5), at most once a minute per buddy.
- `GET /world`: the map's buddies (a capped sample when there are many), the
  numbers, the goal. Cached for 30 s.
- `POST /gesture`: a boop or a cheer from one buddy to another.
- `GET /gestures`: what's waiting for this buddy.
- An admin way to set the current goal and its reward.

**Recommended stack:** the landing page is Next.js on Vercel, so the world API can
be Vercel Functions in the landing repository or a new one, with a managed
Redis (Upstash, from the Vercel Marketplace) for buddies' last state, counters
and gesture queues. No websockets in v1: polling every minute is enough for a
map and a boop.

**Repository:** a new `Mellow-Machines-Lab/BoopWorld`, or a folder in `landing/`.
Recommended: its own repository, so the engine's CI stays offline.

**Cost:** small at first. A buddy is about 2 requests a minute while its person
is at the Mac. At 1,000 buddies, about 1–2 million requests a month, within
Vercel's and Upstash's lower paid tiers. To check against current prices before
committing.

**Data kept:** buddies' last state, expiring after 30 days with no send; today's
and the period's totals; gesture queues, expiring after a day. No history per
buddy beyond today's.

### 9.3 Docs and rules to change

- `CLAUDE.md`: Words (XP, the ring, level, world, world goal, boop, cheer); the
  rule "no code, commands, tool output… to the brain" gets a sibling for the
  world; a row in the docs table for `app/BoopKit/World/`.
- `documentation/architecture.html`: the world client and server, what leaves
  the Mac.
- `README.md`, `SECURITY.md`: the world, opt-out, what's shared.
- `plan/product-ideas.md`: the ground rules that change.
- `characters/CHARACTER.md`: a pack's level-up and world lines in `signs.md`.

### 9.4 Testing

- **Unit:** the ring, the curve, the caps, migration; the publisher sends only
  the §6.5 fields (a test that fails on any new key); the feed's events.
- **A fake world server** for `Boop --headless` and the e2e scripts, so nothing in
  tests reaches the real one.
- **The server's own tests,** in its repository, including the cap and name
  filter.
- **Evals:** feel scenarios for a boop arriving, cheers, a goal reached, the ring
  closing, a level-up.
- **Simulator:** the new board moments as goldens.

## 10. Out of scope for v1

- Who pays for the brain, or a brain without Jev.
- A voice architecture: generated voices, free speech, Boop talking more as it
  levels.
- Leagues, leaderboards, rivalries, ranking of any kind.
- Visits, world moments beyond one goal at a time, a public web page of the
  world (a strong second step, since it's also marketing).
- Generations, keepsakes, chapters, a desk base, coins.
- New animations or acts beyond what's needed for the new moments.

## 11. Order of work

Each phase ships on its own.

| Phase | What | Needs a server | Size |
| --- | --- | --- | --- |
| **1. XP v1** | The ring, endless levels, no decay, the new caps, stages as big level-ups (or gone), the board's ring and level-up moments, the Mac's Boop tab | No | Medium |
| **2. The popover's tabs** | Now, Boop, World (empty or read-only), Settings | No | Small |
| **3. The world, read-only** | The server, `GET /world`, the World tab's map and numbers, with a seeded world | Yes | Medium |
| **4. Your buddy in the world** | The publisher, consent in onboarding and Settings, names and their filter, world goals and their reward tags | Yes | Medium |
| **5. Boops and cheers** | Gestures both ways, their board moments and reasons, limits | Yes | Medium |
| **6. Later** | Visits, a public web page, more world events, a weekly leaderboard | Yes | — |

Phases 1 and 2 can start now. Phase 3 needs the decisions in §12 first.

## 12. Decisions for the owner

1. **"Dumb buddy":** is this plan's reading right (no new intelligence, Jev
   stays), or should v1 run with no Jev?
2. **The ring:** 100 XP a day, one cap, no limits by source (decided: simple).
3. **Levels:** a level per 100 XP, so a full ring is a level (decided: simple).
4. **Stages:** big level-ups at 5, 15 and 30 (A), or gone (B)?
5. **The world's data:** the §6.5 table, and the two ground rules it changes.
6. **Consent:** on by default at onboarding, with one tap to say no?
7. **World off:** can you still see the map, read-only?
8. **The server:** Vercel Functions and Upstash Redis, in a new `BoopWorld`
   repository?
9. **Boops at night:** held for the morning?
10. **The first world goal**, and its reward.

## 13. Risks

- **A world needs people.** With few buddies, the map is empty and goals feel
  far away. Mitigation: show totals (they grow from day one), count the owner's
  own buddies, and pick the first goals to be reachable; a quiet world is still
  honest.
- **Privacy surprises.** Even coarse data surprises some people. Mitigation:
  the table, plain words, a switch, and nothing on by stealth.
- **Running a server** is new: uptime, cost, abuse, names. Mitigation: a small
  surface, read-mostly, rate limits, everything expiring.
- **Notification creep.** Boops and cheers could become noise. Mitigation: the
  board's limits, night holding, status first.
- **The ring could feel like a chore** if Boop guilts you. Mitigation: no streaks,
  no sad Boop for an unfilled ring, only a happy one for a full one.

The owner's decisions of 2026-11-08 after the sketches are in
[world.md](world.md) §9: they override this file where they differ (no country, joining
on by default, no world goals yet, XP from zero, the UI's words).
