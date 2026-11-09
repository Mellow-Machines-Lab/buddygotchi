# The world: architecture and build plan

Updated 2026-11-08. Built as `internal/world/` (§2); agreed with the owner on 2026-11-08, from
[v1-buddy.md](v1-buddy.md) §6 (what the world is) and §5 (XP, kept simple).
Work happens on branch `main-v2`, in feature branches off it; `main` stays as it
is for now.

## 1. The pieces

```
 Board  ◀── LinkKit (no new message) ──▶  Mac app (BoopKit)
                                             │
                                             │  app/BoopKit/World/  (new)
                                             │   WorldClient  ─ HTTPS ─▶  World server  (internal/world/, new)
                                             │   publishes state,             Vercel Functions, Node 24, TypeScript, Hono
                                             │   reads the world,             Postgres (Neon, from the Vercel Marketplace)
                                             │   gets gestures                 a cron to expire old rows
                                             ▼
                                         transcript: `world` events
                                         ▶ view ▶ Jev ▶ reactions, reasons
```

- **The server lives in `internal/world/`.** It doesn't ship to devices, so it's
  internal by the repo's rule. It depends on nothing else in the repo, and nothing
  in the repo depends on it, except the Mac client's wire format, which a shared
  fixture pins (§7).
- **The Mac client lives in `app/BoopKit/World/`.** It's Boop's own, so not a
  package. It only reads what the core and the daily counts already keep.
- **The board doesn't change protocol.** World moments arrive as reactions and
  tags, through what exists.
- **No secret is in the repo.** The server reads `DATABASE_URL` and `ADMIN_TOKEN`
  from Vercel's environment. Each buddy's key lives only on its Mac.

## 2. The server

### 2.1 Stack

| Choice | Why |
| --- | --- |
| **Vercel Functions on Fluid Compute, Node 24** | The current default runtime; reuses instances, so few cold starts. The landing page is on Vercel already |
| **Hono**, in TypeScript | Small, routes in one file, runs on Vercel with no config, and tests call it in memory (`app.request`) |
| **Postgres from Neon** (Vercel Marketplace, free tier) | The owner's choice. Vercel's own Postgres is no longer offered; Neon sets `DATABASE_URL` in the project |
| **`postgres`** (porsager) as the driver | Plain SQL with tagged templates, pools on Fluid Compute |
| **PGlite** for tests and local runs | Real Postgres in memory, so tests need no database and no secret |
| **Plain SQL migrations** in `db/migrations/` | Few tables; no ORM to learn |

### 2.2 Layout

```
internal/world/
  README.md            what it is, how to run, test and deploy it
  package.json         scripts: dev, test, migrate, typecheck
  tsconfig.json
  vercel.json          the cron, the function's settings
  .env.example         DATABASE_URL=, ADMIN_TOKEN=, CRON_SECRET=  (no values)
  src/
    app.ts             the routes; Vercel's entry, by its default export (no api/, no rewrites)
    db.ts              the pool, from DATABASE_URL; PGlite when it's unset
    names.ts           the name filter
    limits.ts          the caps and rate limits, in one place
    world.ts           the snapshot: buddies, numbers, the goal
    auth.ts            buddy keys
  db/migrations/001_world.sql
  scripts/migrate.ts   applies migrations to DATABASE_URL
  test/*.test.ts       node:test against PGlite
  fixtures/            the wire format's examples, shared with the Mac's tests
```

### 2.3 Data

```sql
-- One row per buddy in the world. No person, no account.
buddies (
  id          uuid primary key,
  key_hash    bytea not null,          -- sha256 of the buddy's secret key
  name        text not null,           -- filtered; "a buddy" if it fails
  name_ok     boolean not null,
  level       int  not null default 1,
  country     text,                    -- ISO 3166 alpha-2, from the Mac's region
  tz          text,                    -- IANA time zone
  activity    text not null,           -- coding | testing | shipping | waiting | idle | asleep
  stage       text,                    -- hatchling | sprout | buddy | chonk, if stages stay
  seen_at     timestamptz not null,
  created_at  timestamptz not null,
  reports     int not null default 0
)

-- What each buddy added each day: the world's totals and "you added".
buddy_days (
  buddy uuid references buddies on delete cascade,
  day   date,                            -- UTC
  xp    int default 0,                   -- capped at 100 by the server
  turns int default 0, tests_passed int default 0, ships int default 0, lines_changed int default 0,
  primary key (buddy, day)
)

-- The world goal: one at a time, set by the owner.
goals (
  id serial primary key,
  title text, metric text,               -- tests_passed | ships | turns | lines_changed | xp
  target bigint, starts date, ends date,
  reward_tag text,                       -- a tag every board wears when it's reached, e.g. "worldparty"
  reward_days int default 3,
  reached_at timestamptz
)

-- Boops and cheers waiting for a buddy.
gestures (
  id bigserial primary key,
  to_buddy uuid references buddies on delete cascade,
  from_buddy uuid references buddies on delete set null,
  kind text,                             -- boop | wave | heart | cheer
  from_country text,
  created_at timestamptz,
  delivered_at timestamptz
)
```

**Kept for how long:** a buddy not seen for 30 days is deleted, with its days.
`buddy_days` older than 400 days is summed into a `totals_by_day` row and deleted,
so the year's totals stay without per-buddy history. Gestures are deleted a day
after delivery, or after two days unread. A daily cron does all of this.

### 2.4 The API

All under `/v1`, JSON, HTTPS. A buddy authenticates with `Authorization: Bearer
<key>`.

| Method and path | Who | Does |
| --- | --- | --- |
| `POST /v1/buddies` | Anyone | Joins the world: `{name, country, tz}` → `{id, key}`. The key is shown once |
| `PUT /v1/buddies/me` | A buddy | Its state and what it added since the last send (§2.5) |
| `DELETE /v1/buddies/me` | A buddy | Leaves the world: its row, days and gestures go |
| `GET /v1/world` | Anyone | The snapshot (§2.6), cached 30 s at Vercel's edge |
| `POST /v1/gestures` | A buddy | `{to, kind}`: a boop, wave, heart or cheer |
| `GET /v1/gestures` | A buddy | What's waiting for it; marks them delivered |
| `POST /v1/reports` | A buddy | `{buddy}`: reports a name; at 3 reports the name is hidden |
| `PUT /v1/admin/goal` | The owner, with `ADMIN_TOKEN` | Sets the current goal |
| `GET /v1/health` | Anyone | `{ok, db}` |
| `GET /api/cron/expire` | Vercel Cron | The expiry above; checks `CRON_SECRET` |

### 2.5 What a buddy sends

```json
PUT /v1/buddies/me
{
  "seq": 418,
  "name": "Mochi",
  "level": 12,
  "stage": "buddy",
  "country": "PT",
  "tz": "Europe/Lisbon",
  "activity": "testing",
  "day": "2026-11-08",
  "xp_today": 82,
  "added": { "turns": 3, "tests_passed": 2, "ships": 0, "lines_changed": 140 }
}
```

- `seq` grows by one each send, so a resend after a timeout isn't counted twice.
- `added` is what changed since the last send. The server adds it to today's
  `buddy_days`.
- **The server holds the limits** (`limits.ts`): XP at most 100 a day, at most
  one send each 30 s, and `added` within plausible bounds a minute (turns 20,
  tests 50, ships 5, lines 20,000). Past them, it clamps and logs.
- **A test on the Mac fails if any other key is ever sent** (§7).

### 2.6 What the world returns

```json
GET /v1/world
{
  "at": "2026-11-08T17:02:00Z",
  "awake": 214, "total": 1302,
  "doing": {"coding": 38, "testing": 12, "shipping": 2, "waiting": 9, "idle": 153, "asleep": 1088},
  "today": {"turns": 9120, "tests_passed": 12400, "ships": 310, "lines_changed": 812000},
  "year":  {"turns": 1.2e6, "tests_passed": 2.1e6, "ships": 41000, "lines_changed": 1.2e8},
  "countries": [{"country": "BR", "awake": 31, "today_turns": 1200}, …],
  "goal": {"title": "A million tests this month", "metric": "tests_passed",
           "target": 1000000, "progress": 742000, "ends": "2026-11-30", "reached": false},
  "rewards": [{"tag": "worldparty", "until": "2026-11-11"}],
  "buddies": [{"id": "…", "name": "Bean", "level": 7, "stage": "buddy",
               "country": "JP", "tz": "Asia/Tokyo", "activity": "asleep"}, …]
}
```

- `buddies` is a sample of at most 500, the awake first, so the response stays
  small however big the world gets.
- A buddy whose name was hidden shows as "a buddy".
- `rewards` is what every board wears now: the Mac turns it into a tag.

### 2.7 Names

- At most 16 characters, letters, digits, spaces and a few marks.
- Refused: a word list (kept in `names.ts`), anything that looks like a link, a
  handle or a phone number. A refused name is stored but shown as "a buddy",
  and the Mac is told, so its Settings can say so.
- Three reports hide a name until the owner looks.

### 2.8 Cost, at a guess

A buddy sends once a minute while you're at the Mac, and reads the world once a
minute while the World tab is open, or every 5 minutes otherwise. At 1,000
buddies, that's about 1–2 million function calls a month and a small database:
within Vercel's Hobby or Pro limits, and Neon's free tier at first. To check
against current prices when the world grows.

## 3. The Mac client

### 3.1 `app/BoopKit/World/`

| Part | Does |
| --- | --- |
| `WorldSettings` | On or off, the server's URL (`https://world.adoptaboop.com` by default, or `BOOP_WORLD_URL`), and the buddy's id and key, kept in the state folder, readable only by you |
| `WorldClient` | The HTTP calls of §2.4, with timeouts and backoff. Never blocks the core |
| `WorldPublisher` | Every 60 s while you're at the Mac, and at once on a change of activity: builds §2.5 from the core's snapshot, the growth store and the daily counts, and sends it. Nothing new is gathered |
| `WorldFeed` | Reads `/v1/world` for the World tab, and `/v1/gestures` every 60 s; turns gestures and reached goals into events |

- **Off means off:** neither the publisher nor the feed runs, and nothing is sent.
- **The activity's six categories** come from the core's look: working with a
  `tests` check running is `testing`, a push act is `shipping`, needs-you is
  `waiting`, asleep is `asleep`, else `coding` or `idle`.
- **Country** is from the Mac's region setting (`Locale.current.region`), and the
  time zone from `TimeZone.current`.

### 3.2 Events

A new event kind, `world`, from a new source, `world`:

| `specific_type` | When | Line Jev reads | Reason |
| --- | --- | --- | --- |
| `boop`, `wave`, `heart` | A gesture arrives | "Someone in Lisbon booped Boop." | The same |
| `cheer` | Cheers for your ship (counted together) | "3 buddies cheered your ship." | The same |
| `goal` | The world's goal is reached | "The world passed a million tests!" | The same, and the reward |

- They go through the transcript like any event; the view folds them into lines;
  Jev may react; the narration says why.
- **At night they wait** for the morning sequence, which tells them in one line.
- **A reward** becomes a tag in `state.when` (`worldparty`) until its date, so the
  board's dressing shows it, as a holiday does.
- **Limits on the board:** at most a few gestures an hour play. The rest are
  counted for the World tab.

### 3.3 XP

`Growth` changes as `v1-buddy.md` §5 says, kept simple: fixed XP per thing, a
daily cap of 100, level = 1 + XP / 100, no decay. The board's growth bar becomes
today's ring. The world reads the same numbers.

### 3.4 The UI

- **Popover tabs:** Now, Boop, World, and Settings (`v1-buddy.md` §7).
- **The World tab:** a world map (an equirectangular image with the night side
  shaded from the time), buddies as dots by time zone and country, a buddy's card
  on tap with buttons to boop, wave or heart; the live numbers; the goal's bar
  and your part; the gestures you got today.
- **Onboarding:** one more step, "Join the world of buddies?", with what's shared
  in plain words; on by default.
- **Settings:** the switch, "What Boop shares", your buddy's name as the world
  shows it, and "Leave the world" (deletes your buddy on the server).

### 3.5 The board

Nothing new on the wire. The ring is `state.xp` as today's percent; a level-up and
the ring closing are rule reactions; a gesture is a reaction from Jev or, without
one, a rule's small bounce; a reward is a tag. The pack gains lines in `signs.md`
and maybe one celebration design.

## 4. Privacy, in one place

| Leaves the Mac, when the world is on | Never |
| --- | --- |
| A random buddy id and its key | Your name, account or email |
| The buddy's name, level and stage | Thread or project names |
| Country and time zone | Code, files, commands, tool output |
| One of six activities | Prompts, what you said, agents' messages |
| Counts: turns, tests passed, ships, lines changed; today's XP | Memory, notes, the dream |
| Gestures you send | Anything when the world is off |

This list is written once, in the code (`WorldPublisher`'s fields), and the
onboarding, Settings, README and `SECURITY.md` say it in words. It changes two of
Boop's ground rules (see `v1-buddy.md` §6.5).

## 5. Deploying it

What's done in the repo, and the owner's steps after.

**In the repo (this work):** the server, its tests, `vercel.json`, `.env.example`,
the migration, the README with these steps, and a CI job that runs its tests with
no secrets.

**The owner's steps:**

1. In Vercel, **import the GitHub repository** as a new project, with **Root
   Directory `internal/world`** and production branch `main-v2`. (Or deploy from
   the Mac with `npx vercel --cwd internal/world`, after `npx vercel login`.)
2. In the project's **Storage** tab, add **Neon Postgres** from the Marketplace,
   free plan. It sets `DATABASE_URL` for the project.
3. In **Settings → Environment Variables**, add `ADMIN_TOKEN` (any long random
   string) and `CRON_SECRET`.
4. On the Mac: `cd internal/world && npx vercel link && npx vercel env pull .env.local
   && npm run migrate`. This creates the tables. (`.env.local` is ignored by git.)
5. **Deploy** (push to `main-v2`, or `npx vercel --prod`), then check
   `https://<project>.vercel.app/v1/health` says `{"ok":true,"db":true}`.
6. Optional: a domain such as `world.adoptaboop.com` in **Settings → Domains**.
7. Set the first goal:
   `curl -X PUT …/v1/admin/goal -H "Authorization: Bearer $ADMIN_TOKEN" -d '{…}'`.
8. Point the Mac app at it, if the domain differs: `BOOP_WORLD_URL`.

## 6. Order of work

| Step | What | Where | Needs the owner |
| --- | --- | --- | --- |
| **1** | The server: routes, schema, limits, names, cron, tests, README, CI job | `internal/world/` | No |
| **2** | Deploy | Vercel | Yes: §5 steps 1–5 |
| **3** | XP kept simple: the ring, levels, no decay; the board's ring and level-up | Engine, pack | No |
| **4** | The popover's tabs, with the Boop tab | Mac app | No |
| **5** | The Mac client: settings, client, publisher, feed, the `world` events, privacy test, a fake server for tests | `app/BoopKit/World/` | No |
| **6** | The World tab and onboarding's step; gestures both ways; the goal's reward tag | Mac app, pack | No |
| **7** | End to end against the deployed server, from two state folders | All | The server running |

Steps 1, 3 and 4 can run side by side. 5 needs 1. 7 needs 2.

## 7. Testing

- **Server:** `npm test` in `internal/world/`, with PGlite: every route, the
  limits, the name filter, `seq` against double counting, expiry, the admin
  token, and the goal reached exactly once.
- **The wire format:** `internal/world/fixtures/*.json` are the examples of §2.5
  and §2.6. The server's tests check them, and the Mac's tests decode them, so the
  two can't drift.
- **Privacy:** a Mac test fails if `WorldPublisher` would send any key not in §2.5.
- **The Mac without a network:** a fake server in tests and `Boop --headless`
  (`BOOP_WORLD_URL` pointing at `npm run dev`, which uses PGlite).
- **Evals:** feel scenarios for a boop, cheers, a goal reached, the ring closing,
  a level-up.
- **CI:** a job running `npm ci && npm test` in `internal/world/`, with no secrets.

## 8. Decisions taken here (say if any is wrong)

- Hono and the `postgres` driver; plain SQL; PGlite in tests.
- One goal at a time, set by the owner with the admin token; no admin page yet.
- A buddy's key in the Mac's state folder, not the Keychain, since an agent shell
  must never read the Keychain and the key protects only a buddy's world row.
- A sample of 500 buddies in the snapshot, awake first.
- Gestures by polling every minute, not websockets.
- Days on the server are UTC; Boop's own 5:00 day stays on the Mac for the ring.
