# XP and the league: the design and the build plan

Updated 2026-11-22. Agreed with the owner on 2026-11-22, from the mockups at
<https://claude.ai/artifact/PSuUVzy5m38YMTXeDpeHsz> ("Boop XP and World").
Nothing here is built. It replaces [v1-buddy.md](v1-buddy.md) §5 (XP) and the
World tab of [world.md](world.md) §3.4, and it reopens three of that plan's
rules on purpose (§2). It follows
[documentation/design/](../documentation/design/README.md): XP speaks on the
board only in places that already exist.

Tick a step in the commit that finishes it, and say there what checked it.

## 1. Why

The owner's words: XP and the world "feel a little flat". The code says why.

| Problem | Where |
| --- | --- |
| Eight things earn XP and the board never says which one did | `Growth.xp(for:)`; the bar shows only a number |
| Each call earns 1 XP, so the ring is full at about 10:43 on a typical day, and 83% of XP is thrown away | `Growth.toolXP`; [product-review.md](product-review.md) §3.3 |
| Care can never move the ring, because work fills it first | The same |
| A full ring is a level, so the level counts days | `Growth.perLevel == perDay` |
| The World tab is dots with nothing to do and nothing at stake | `WorldPane.swift`, `WorldBand.swift` |

The fix gives XP one meaning at each of three time scales.

| Scale | Question | Answer |
| --- | --- | --- |
| Today | Was it a good day? | The ring, filled by finished work, and by care on a quiet day |
| Tomorrow | How long have we kept it up? | Days in a row with a full ring |
| Everyone | How do I stack up? | A weekly league, ranked by the week's XP |

## 2. What changes from the earlier plans

These override `v1-buddy.md` and `world.md` where they differ. Update those
files in the commits that build each part.

| Earlier rule | Now |
| --- | --- |
| "A full day's ring is the most a day can give" (`v1-buddy.md` §2.2) | The ring is a goal at 100. XP counts past it, to at most 300 a day |
| "No streaks to lose" (§2.2, §13) | Days in a row, with two days of grace. Boop is never sad about a missed day |
| "No ranking in v1" (§6.7, §10) | One weekly league for everyone |
| A level is 100 XP | A level is 500 XP |
| The board's bar shows when XP comes in (§5.5) | No bar. Three signs (§5) |
| The World tab is a time-zone band (`world.md` §9) | The World tab is the league. The band goes |
| A gesture is anonymous (`world.md` §3.2) | A gesture names its sender, so you can answer it (§8, step 7) |

Not changed: XP and levels never go down. Nothing is locked behind a level.
Boop is one size. No world goals yet. The privacy rules of `world.md` §4
hold, with the new shared facts listed in §9.

## 3. XP

### 3.1 What earns

Four things earn XP. Each is an event the board already shows.

| What happens | XP | Whose | The event today |
| --- | --- | --- | --- |
| An agent finishes a turn, done, and the finish plays as a success | 5 | Work | A `turn` end with `outcome == "done"` that `MomentRule.finish` reads as `.success` |
| A ship: a push that passed | 10 | Work | An `act` end, `specificType == "push"`, `passed == true` (as `WorldLink.heard` counts `ships`) |
| Tests pass after they failed | 5 | Work | An `act` end for a check with `passed == true` and a failed run of the same check before it in the turn (`TranscriptView`'s `failedBefore > 0`) |
| Time with Boop: a care touch that is not rough, your words to Boop, a met wish | 3 each, at most 30 a day | You | As today: `Touch.isCare && !isRough`, `.said`, a `wish` end that is met |

These earn nothing now: a call, a helper, coming back to the Mac, an
answered ask, a failed or stopped turn, a chat turn. Delete their constants
(`toolXP`, `helperXP`, `backXP`, `answerXP`, `wishXP`).

Rules:

- **A chat turn earns nothing.** A turn earns XP only when its finish is a
  success, so "+5 XP" always has a sign to ride on. Count the turn's XP
  from the same facts that pick the finish, so the two cannot disagree.
- **XP counts even when the sign cannot play** (something needs you, face
  down, on a call). The sign is the usual case, not the condition.
- **`Growth.xp(for:)` reads one raw event today.** "Tests fixed" and "a
  success finish" need facts the raw event does not carry. Choose the
  smallest change: either the core stamps the fact on the event it logs,
  or the growth count moves to where the facts exist. Keep `Growth` a
  pure model that tests pin.
- **The day's limit is 300 XP,** work and care together. Care also has its
  own limit of 30. Past a limit, an event earns 0 and writes nothing, as
  `GrowthStore.count` does today for the ring.
- The amounts are first guesses. See §10.

### 3.2 The ring, the level and days in a row

| Thing | Rule |
| --- | --- |
| The ring | Today's XP against 100. `ringClosed` at 100, as now. `today` may go to 300 |
| The level | `1 + xp / 500`. No maximum, never down. A level-up keeps its moment: `level 8!` in gold on the low sign |
| Days in a row | A Boop day counts when its ring closes. The count goes up by one at that moment. It starts again at 1 when more than two Boop days with no full ring lie between two full ones. So a weekend never breaks it |

Days in a row, exactly: keep `count` and `lastDay` (the last Boop day with a
full ring). When the ring closes on day `d`: if `d - lastDay <= 3` then
`count += 1`, else `count = 1`; then `lastDay = d`. The count to show on day
`t` is `count` if `t - lastDay <= 3`, else 0. Use `LocalTime.dayNumber` for
the difference. Pin both rules in a test.

The word is "days in a row", never "streak" (CLAUDE.md's Words).

### 3.3 What the Mac keeps

`GrowthStore` gains, as `xp.` keys in the same store:

- Today's XP by source, with its count: turns, ships, fixes, care. For
  example `xp.today_by = "turns 8 40,ships 1 10,fixes 1 5,care 3 9"`. It
  starts again with the day, as `xp.today` does.
- Days in a row: `xp.row = "<count> <lastDay>"`.
- The kept days stay at 7. A day's row keeps its total only.

`Growth` gains `work` and `care` (today's two parts), and `today` may be up
to 300. `percent` goes with the bar (§5.4).

## 4. The Boop tab: your buddy's profile

Every buddy has one profile. The Boop tab is your buddy's whole profile. A
buddy card in the World tab is the public part of another buddy's (§7).
Build both from the same views where the content is the same.

From the top (`app/Boop/Views/BoopPane.swift`):

1. **Who.** Boop's face in its colour, its name, "Level 7 · 12 days in a
   row", and its medals as three small counts (gold, silver, bronze). No
   medals row before the first medal. No days text at 0.
2. **Mood, and why.** One card: "**Happy.** api finished after 14
   minutes." Use the Now tab's own line and view. The Now tab keeps it.
3. **Today.** The ring, with today's XP and "XP" in it. Two tints in one
   ring: blue for work, pink for you. Past 100 the ring stays full and
   the number goes on. Beside it, the list of what filled it, from §3.3:
   "8 turns finished 40", "1 ship 10", "Tests fixed once 5", "Time with
   Mochi 9". A row shows only when it has XP.
4. **The hint.** One line under it:
   - Nothing yet: "Nothing yet today. Work with your agents, or give
     Mochi a pet." (as now)
   - Under 100: "36 to go. A few more turns will do it, or go and say hi
     to Mochi."
   - Full: "Today's ring is full. Nice work."
5. **The last 7 days.** As now, with these changes: a full day is green, a
   part-full day is blue, and a day with nothing is a dotted hollow ring.
   Never red.
6. **What Mochi knows about you.** As now: up to three notes and "See
   everything". The owner put any redesign of this aside; do not change it.

Words follow CLAUDE.md's "The UI's words". "XP" is the unit's name and may
be shown; change that section's "No game jargon" to say so.

## 5. The board

The design rule (`screen-guide.md`, "Before you add something"): a thing you
can ignore gets no rise. So XP gets no element of its own. It rides on three
moments that are already for you. Everything else is in the app.

### 5.1 "+5 XP" on a result

- A success finish's low sign names the thread, as now, and carries a chip
  at its right end: `+5 XP`. The chip is a filled pill in the sign's own
  green, with dark text, 17 px bold.
- A ship's result and a fixed check's result show the same chip, `+10 XP`
  and `+5 XP`, beside the result's words (`pushed`, `tests passed`),
  wherever the gel draws those words.
- The Mac decides. `Moment` gains `xp: Int?`, sent in the `do`'s args as
  `xp`. The board draws the chip when it is there and never works it out.
  Send it only when the event really earned (not past a limit).
- If the thread's name and the chip do not both fit, shorten the name.
- Care shows no chip. Boop's face answers care, as the theory says.

### 5.2 The ring is full

- Once a Boop day, when the ring closes: a gold low sign with a small full
  ring at its left and `100 XP today · day 12`. With a count of 1 it says
  `100 XP today`. It replaces `today's done!` (`Core.ringSign`), which the
  owner found unclear.
- The face and the wiggle stay as they are. It still waits while something
  needs you or Boop listens (`Core.recordGrowth`). It also waits until no
  turn runs: Boop starts things only when idle.
- A level no longer comes with the ring, so the "one moment for both" rule
  becomes rare. Keep it correct, and keep the bug fixes the review asked
  for: a moment cut by needs you is due again (`GrowthStore.missed`).

### 5.3 Monday's moment

- In the first hello of the Boop day after a league week ends, if this
  buddy was in last week's league: a gold low sign with a small medal or
  place at its left and `2nd · 512 XP last week`.
- For the top three: Boop's biggest cheer (the finish at its big size) and
  the medal in its metal. For any other place: a small hello, the same
  sign, no cheer.
- It is one of the hello's extras (`MomentRule.hello`: "at most one
  extra"). Its place in that order is first, on the one day it applies.
- Tell it once: keep the told week on the Mac. At night it waits for the
  morning, as gestures do.
- Built more simply: it plays at the first send's reply that carries last
  week's place while you're there and nothing needs you (not quiet), which
  is soon after you come back. A medal plays proud at the big size with the
  gold sign; there is no finish animation for it.

### 5.4 What goes

- The bar at the top: `firmware/src/app/growth_bar.{h,cpp}`,
  `render::GrowthShow`, the gel's drawing of it, `Behaviour`'s use, and
  `state.xp` if nothing else reads it. The top of the screen is the
  band's, for things you must act on.
- A met wish's heart no longer flies into the bar. It plays at Boop and
  fades.
- The goldens that show the bar (`ring-filling`, `ring-sparkle`,
  `ring-closed`, `ring-and-level*`, `level-up*` in SlimeBuddy's
  `golden-gel/v1`) are recorded again or removed.
- No idle ring, and no daily "3rd this week" line. The owner cut both.

Add the XP chip, the ring sign and the league sign to the screen guide's
"Each element" table as forms of the low sign, in the commit that builds
them.

## 6. The league

### 6.1 Rules

- **One league for everyone** to start. Keep the code ready for several:
  give a week's results a `league` number that is always 1.
- **A week** is Monday 00:00 UTC to the next Monday 00:00 UTC. The server's
  days are UTC already. The app shows time left from the server's `ends_at`
  ("ends in 2 days"), never a weekday, because the end is not local.
- **The score** is the week's XP: the sum of `buddy_days.xp` for the week.
- **A tie** goes to the buddy that joined first (`created_at`).
- **Who is in it:** every buddy in the world. A private buddy is in no
  league and sees the list with no row of its own.
- **Medals:** gold, silver and bronze for places 1 to 3 when the week
  closes. A medal stays for ever.
- **No other prize.** No XP for a win: it would make next week's winner the
  same buddy.
- **Later, not now:** leagues that move (top five up, bottom five down)
  once the world has a few hundred buddies.

### 6.2 The server (`internal/world/`)

Limits (`limits.ts`): `XP_PER_DAY` becomes 300. Add `LEAGUE_ROWS = 100`,
`RESULTS_KEPT_WEEKS = 12`.

A new migration:

```sql
alter table buddies add column color int not null default 0;       -- §8
alter table buddies add column days_in_a_row int not null default 0;
alter table buddies add column seed boolean not null default false; -- §6.4
alter table buddies add column seed_strength int;                   -- 100 to 700: a seed's usual week

-- One row a buddy a closed week: the Monday line and "best week".
create table league_results (
  week   date not null,          -- the week's Monday, UTC
  league int  not null default 1,
  buddy  uuid not null references buddies on delete cascade,
  place  int  not null,
  xp     int  not null,
  primary key (week, league, buddy)
);
-- Medals stay when old results go.
create table medals (
  buddy uuid not null references buddies on delete cascade,
  week  date not null,
  place int  not null check (place between 1 and 3),
  primary key (buddy, week)
);
create table league_weeks (week date primary key, closed_at timestamptz not null);
```

What a buddy sends (`PUT /v1/buddies/me`, `STATE_KEYS`): two new keys,
`days_in_a_row` (0 to 100,000) and `color` (0 to 7). `xp_today` may now be
up to 300. The fixture `buddy-state.json` gains both.

Closing a week: the daily cron (`/api/cron/expire`) closes every week that
has ended and has no `league_weeks` row. For each: write `league_results`
for every buddy with XP that week, write `medals` for places 1 to 3, then
the `league_weeks` row, in one transaction. A second run does nothing. Also
close a week lazily on the first `GET /v1/league` after it ends, with the
same function, so the Monday line never waits for the cron. Delete results
older than `RESULTS_KEPT_WEEKS`.

New routes:

| Method and path | Who | Does |
| --- | --- | --- |
| `GET /v1/league` | Anyone; a buddy's key adds `me` | The current week's list |
| `GET /v1/buddies/:id` | Anyone; a buddy's key adds `between` | One buddy's public profile |

```json
GET /v1/league
{
  "week": "2026-11-23", "ends_at": "2026-11-30T00:00:00Z",
  "total": 1302, "awake": 214,
  "rows": [
    { "place": 1, "id": "…", "name": "Bean", "level": 9, "color": 3,
      "activity": "shipping", "xp_week": 512 }
  ],
  "me": { "place": 3, "xp_week": 431, "top_percent": 18,
          "ahead": { "id": "…", "name": "Nori", "by": 37 } },
  "last_week": { "week": "2026-11-16", "place": 2, "xp": 512, "of": 1280 }
}
```

- `rows` is the top `LEAGUE_ROWS`. If `me` is below them, the Mac shows the
  top rows, a gap, and its own row from `me`.
- `ahead` is the buddy one place above. None at place 1.
- `top_percent` is `ceil(place * 100 / buddies with XP this week)`.
- `last_week` is there until the next week closes. `me` and `last_week`
  need the buddy's key, so cache the list at the edge without them and add
  them per request, or serve the keyed form uncached. Decide by cost.
- Names go through `shownName`, as in the snapshot.

```json
GET /v1/buddies/:id
{
  "id": "…", "name": "Bean", "level": 9, "color": 3, "region": "asia_oceania",
  "utc_offset": 540, "activity": "shipping", "days_in_a_row": 21,
  "medals": { "gold": 3, "silver": 1, "bronze": 0 },
  "week": { "xp": 512, "place": 1 }, "best_week": 640,
  "today": { "turns": 11, "ships": 2, "tests_passed": 4 },
  "between": { "from_them": { "kind": "wave", "at": "…" },
               "from_you": null, "you_beat_them": "2026-11-09" }
}
```

- `between` is step 7. `from_them` and `from_you` are the newest gesture
  each way that the server still has. `you_beat_them` is the newest closed
  week where your place was better, from `league_results`.

Tests, with PGlite as now: the score sums the week only; the tie rule; a
week closes once and medals are written once; the lazy close and the cron
agree; a private or deleted buddy leaves no row; `XP_PER_DAY` clamps at
300; `top_percent` and `ahead` at the edges (place 1, last place, alone);
the fixtures `league.json` and `buddy.json`, which the Mac's tests decode.

### 6.3 The Mac (`app/BoopKit/World/`, `app/Boop/Views/WorldPane.swift`)

The World tab, from the top:

1. **"This week's league · ends in 2 days".** The list. Each row: place, a
   dot for what the buddy does now, its name in bold, the activity word, a
   small bar for its XP against the leader's, the XP, and a chevron. Your
   row is tinted and says "you". The whole row opens the buddy card.
2. **The rival line.** One card under the list: "**37 XP behind Nori.**
   Two ships would pass it." The second sentence turns `by` into the
   fewest ships or turns that pass it (ships of 10 first, then turns of
   5). At place 1: "**First, 44 XP ahead of Nori.**"
3. **One line:** "Top 18% of 1,302 buddies this week. 214 are awake now."
   Leave out the percent while fewer than 50 buddies have XP this week.
4. **"For Mochi today":** the gestures that came, as now.

Remove the band (`WorldBand.swift`), "Around the world" and the three
numbers. Keep every state the tab handles now: off, private, joining,
stale, unreachable.

Fetch `/v1/league` only while the World tab is open, about every 30 s, as
the snapshot is today. `last_week` must also reach the Mac with no tab
open, for Monday's moment: add it to the reply of `PUT /v1/buddies/me`
(the `buddy-reply.json` fixture), which every buddy gets within 10
minutes.

`WorldLink` sends the two new facts with the state. `WorldTests` pins the
keys a buddy sends: add `days_in_a_row` and `color` there and nowhere else.

### 6.4 Seeded buddies

The owner will seed the world with made-up buddies until real ones come.

- A seed is a row in `buddies` with `seed = true`, a name from a list in
  the repo, a level, a UTC offset, a colour and a `seed_strength` (its
  usual week's XP, 100 to 700, so a real buddy that works most days can
  reach the top three).
- **No process writes for seeds during the day.** A pure function in
  `src/seeds.ts`, `seedNow(id, strength, utc_offset, now)`, gives a seed's
  XP today, its counts and its activity from the time alone: it works its
  local weekday hours, rests some days, and its XP for a day grows through
  that day. It is random by a hash of `(id, day)`, so it is the same for
  every request. The league, the buddy card and the snapshot add seeds'
  values from this function.
- Built differently: nothing writes a seed's days. The league sums a
  seed's week from the same function, so a week closes with seeds in it
  and no cron job is needed for them.
- A gesture to a seed is taken and dropped. A seed sends none.
- `scripts/seed.ts N` makes N seeds; `scripts/seed.ts --remove` deletes
  every one (`delete from buddies where seed`), with their days, results
  and medals.
- Seeds count in `total` and `awake`.
- Tests: `seedNow` is stable for one time and never goes down within a
  day; a seed's week stays within its strength's range; removal leaves
  nothing.

One thing to decide before real buyers join: whether a seed is marked as
one. This plan does not mark them. The `seed` flag makes either choice a
small change.

## 7. The buddy card

Opened from a league row, in the World tab, with "‹ League" to go back.

1. **Who:** the face in its colour, the name, "Level 9 · 21 days in a
   row", the medals.
2. **Now:** "**Shipping now.** Asia and Oceania, 16:05 there." The time is
   from the UTC offset.
3. **Numbers:** "This week 512 XP · 1st", "Today 11 turns · 2 ships",
   "Best week 640 XP".
4. **Buttons:** Boop, Wave, Heart, and "Cheer the ship" while the buddy
   ships. These are today's gestures and limits (`GESTURES_TO_ONE_PER_HOUR`).
   Keep today's sent and failed states.
5. **"You two"** (step 7): "Bean waved at Mochi yesterday." with "Wave
   back", and "You beat Bean two weeks ago." Leave the section out when
   it is empty.
6. **One line of trust:** "Others see the same of Mochi: its name, level,
   days, medals and counts. Never its mood, your projects, or what it
   knows."

Your own row opens the same card with no buttons and "This is Mochi, as
other buddies see it."

For "You two", a gesture names its sender: `gestures` handed to a buddy
gain `from: { id, name }`, and the arrival's words become "Bean booped
Mochi" where they said "Someone in Asia or Oceania". On the board the sign
stays as it is.

## 8. The buddy's colour

Everyone can pick their buddy's colour, at any level. It is a setting, not
a reward.

- **Eight fixed colours,** `color` 0 to 7, with 0 the blue of today. Pick
  them in the gel's own art so each looks as good as the blue. Keep all of
  them away from amber (needs you), from the outcome colours, and from the
  agents' lane colours.
- **Settings:** a row of eight swatches under the buddy's name. Onboarding's
  naming screen may show it too.
- **The board:** the Mac sends the colour in `state`. The gel draws its
  body, its highlights and its signs' knobs from a palette for that
  colour. This is the largest art change in this plan: the gel's blue is
  in many places. Do it last, and re-record the goldens once.
- **The Mac:** the mirror, the Boop tab's face and the menu bar follow.
- **The world:** `color` is shared (§6.2) and draws each buddy's face in
  the league and on its card.

## 9. Privacy

The rule in CLAUDE.md stays: the world gets only `World.State`'s fields,
and `WorldTests` pins them. This plan adds two fields a buddy sends, and
changes what the server shows others.

| New | Who sees it |
| --- | --- |
| `days_in_a_row`, `color` (sent) | Anyone who opens the buddy's card |
| The week's XP, the place, the best week, medals (the server's sums) | Anyone, in the league and on the card |
| Today's turns, ships and tests passed (already sent, now shown for one buddy) | Anyone who opens the card |
| A gesture's sender, by name | The buddy that gets it |

Never, as before: mood, what Boop knows, threads, projects, code, words.

Change in the same commits: onboarding's world screen ("Others see…"),
Settings' "What Boop shares", `README.md`, `SECURITY.md`, `world.md` §4,
`internal/world/README.md`, and CLAUDE.md's architecture rule on the world.

Cheating: a buddy reports its own XP. The server clamps a day at 300 and
the counts per minute. That is enough for medals. Do not add any prize
with real value on these numbers.

## 10. The numbers to tune

Before step 1 ships, read the owner's own `daily-counts.jsonl`
(`Boop --counts`) and work out, for the last two weeks, when the ring would
have closed with §3.1's amounts.

- Aim: the ring closes between 14:00 and 18:00 on a usual working day, and
  a day of meetings reaches 60 to 80 from work, so care can close it.
- If it closes too early, lower the turn's 5 first.
- Add to the daily counts, numbers only: the hour the ring closed, XP by
  source, and XP that a limit refused.

## 11. The steps

Each step can ship alone. Steps 1 to 3 need no server. Do one step, run
its checks, show the owner the pictures, and commit. The rules of
[design-build.md](design-build.md) "Before you start" apply: the gel's
drawing is in SlimeBuddy and lands there first; only the owner pushes or
flashes; a change to what the gel draws rebuilds the mirror; new words go
in CLAUDE.md's table in the commit that builds them.

Checks for every step: `make -C internal check`; for the server, `npm test`
in `internal/world/`; for the board, the gel's scenarios and new ones for
what the step adds.

### 1. XP's rules on the Mac (built)

- `Growth.swift`: §3.1's amounts and limits, §3.2's level. Delete the old
  constants. `GrowthStore.swift`: today by source, days in a row (§3.3).
- Where the turn's and the fixed check's XP is counted (§3.1's third rule).
- `Runtime+Status.swift`: the status carries the parts, the by-source list,
  the days in a row.
- Daily counts: §10's three numbers.
- Tests: `GrowthTests` pins every row of §3.1, both limits, the level and
  the days-in-a-row rule with a weekend and with a three-day gap.
- Docs: CLAUDE.md's Words (XP, the ring, level; add days in a row),
  `v1-buddy.md` §2 and §5, `architecture.html` where it describes growth.

Done when: a headless day with real hook events gives the XP that §3.1
says, by hand count.

### 2. The board's signs, and the bar goes (built)

- `Moment.xp` and the `do`'s `xp`; the chip on the finish's low sign and
  on a ship's and a fixed check's result (§5.1).
- The ring sign's new words and its ring mark (§5.2).
- Remove the bar and everything only it used (§5.4).
- SlimeBuddy first (`render/gel/low_sign.{h,cpp}` and where results draw),
  then here, then the mirror and the engine pin.
- New scenarios: a finish with the chip, a long thread name with the chip,
  a ship, a fixed check, the ring full with and without a count, the ring
  held under needs you and played after.
- Docs: the screen guide's element table and "How a turn ends"; CLAUDE.md's
  Words (the ring, low sign); SlimeBuddy's `CONTINUITY.md`.

Done when: on the simulator, no bar ever shows, and each of the three
results shows its chip.

### 3. The Boop tab (built)

- `BoopPane.swift` as §4, with the Now tab's mood view shared.
- Snapshots (`Boop --snapshots`): nothing yet, part-full with both tints,
  full, past 100, no medals, a week with a rest day, dark.
- Medals and the face's colour come later; lay the header out so they fit.

Done when: the owner reads the tab and can say what earned today's XP.

### 4. The league on the server (built)

- §6.2: the migration, the limits, the two new state keys, closing a week,
  `GET /v1/league`, `GET /v1/buddies/:id` without `between`, `last_week`
  in the send's reply.
- §6.4: seeds.
- Fixtures and `internal/world/README.md`.

Done when: `npm test` passes, and a local run (`npm run dev`) with 20
seeds and two real state folders shows a list that changes through a day.

### 5. The World tab (built)

- §6.3: the client's calls and types (`WorldWire.swift`, `WorldClient.swift`,
  `WorldLink.swift`), the list, the rival line, the percent line. Remove
  the band.
- §7's card, items 1 to 4 and 6.
- Snapshots: first place, a middle place, below the top rows, alone in the
  league, private, stale, unreachable, a card for a buddy that ships.
- Privacy docs and screens (§9) for the two new sent fields.

Done when: the end-to-end script (`internal/tools/world_e2e.py`) joins two buddies, each
sees the other in the league in order, and one opens the other's card and
sends a wave that arrives.

### 6. Medals and Monday's moment (built)

- Medals on the Boop tab's header and on the card.
- §5.3: the `world` event for a closed week, the hello's extra, the gold
  low sign, the big cheer for the top three, told once.
- Scenarios: first, third, tenth, told once, held at night, held under
  needs you, a private buddy gets none.

Done when: with the server's clock moved past a Monday, the board plays
the result once at the next hello.

### 7. "You two" (built)

- A gesture names its sender (§7, §9). `between` on the buddy's profile.
  "Wave back" on the card and on an arrival's row.

Done when: buddy A waves, buddy B sees "A waved at B" and waves back from
that row.

### 8. The colour

- §8, in this order: the setting and the shared field; the Mac's faces;
  the gel's palettes and the goldens.

Done when: each of the eight colours passes the gel's scenarios, and none
can be mistaken for needs you at arm's length on the real board.

## 12. Open questions for the owner

1. **The day's limit of 300.** The owner agreed that XP counts past the
   ring, and asked for simple. A hard limit is the simple form. Say if no
   limit, or another number, is wanted.
2. **Two days of grace** for days in a row. Shown in the mockups, never
   confirmed in words.
3. **Seeds are not marked.** Fine for a test world. Decide again before
   buyers join.
4. **Eight fixed colours,** not a free picker, so every colour is drawn
   well and none collides with amber or a lane colour.
5. **A gesture names its sender.** It makes "wave back" possible, and it
   ends anonymous gestures.
