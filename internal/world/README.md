# The world server

Updated 2026-11-22.

Every buddy that joins the world talks to this server. A buddy sends its
state and counts each minute. Each Mac reads the world's snapshot: how many
buddies are awake, what they do, the day's and the year's totals, the goal
and a sample of buddies for the map; and the week's league, ranked by XP,
with each buddy's public profile. Buddies send each other boops, waves,
hearts and cheers. The design is in [plan/world.md](../../plan/world.md) §2
and, for the league, [plan/xp-league.md](../../plan/xp-league.md) §6.

It is a [Hono](https://hono.dev) app in TypeScript for Vercel Functions
(Node 24, Fluid Compute), on Postgres (Neon). It doesn't ship to devices,
so it lives in `internal/`. Nothing else in the repo depends on it, except
the Mac client's wire format, which `fixtures/` pins.

| Path | What it is |
| --- | --- |
| `src/app.ts` | The routes, and Vercel's entry: Vercel finds a Hono app by the default export of `src/app.ts`, so there are no rewrites |
| `src/db.ts` | Postgres from `DATABASE_URL`, or PGlite in memory when it's unset; the migrations runner |
| `src/limits.ts` | Every cap and rate limit, in one place |
| `src/names.ts` | The name filter |
| `src/world.ts` | The snapshot, and the goal: its progress, reached once, its reward |
| `src/league.ts` | The weekly league: the week's standings, a week closed once with its places and medals, a buddy's profile |
| `src/seeds.ts` | Made-up buddies for a small world: what each earned and does, from the time alone |
| `src/regions.ts` | The UTC offsets a buddy may send, and the regions they fall in: their boundaries, in one place |
| `src/auth.ts` | Buddy keys: 32 random bytes, base64url; the server keeps only their sha256. IP addresses' salted hashes, for the limit on joining |
| `db/migrations/` | Plain SQL, applied in name order, each once |
| `scripts/migrate.ts`, `scripts/dev.ts`, `scripts/seed.ts` | `npm run migrate`, `npm run dev` and `npm run seed` |
| `test/` | `node:test` against PGlite; `postgres.test.ts` goes through the `postgres` driver too, with PGlite over a socket |
| `fixtures/` | The wire's examples: what a buddy sends, the reply to it, the world's snapshot, the league and a buddy's profile. The Mac's tests decode them too |
| `vercel.json` | The daily cron that expires old rows |

## Run it

```sh
cd internal/world
npm ci
npm run dev        # http://localhost:8787, on PGlite in memory; PORT changes the port
```

The local server starts empty each time. Its admin token and cron secret
are `dev`, unless `ADMIN_TOKEN` or `CRON_SECRET` is set. Locally no caller
has an address, so they share one: 5 joins an hour. To point the Mac
app at it, set `BOOP_WORLD_URL=http://localhost:8787`. `SEEDS=20 npm run dev`
starts it with 20 made-up buddies.

To seed the deployed world, or take the seeds out again:

```sh
npm run seed -- 30         # 30 made-up buddies, with DATABASE_URL or .env.local's
npm run seed -- --remove   # every one, with its places and medals
```

A seed is a buddy row with `seed = true`. Nothing writes for it during the
day: its XP, counts and activity come from the time, by a pure function
(`src/seeds.ts`), so it counts in the league, the snapshot and the
numbers like any buddy. A gesture to a seed is taken and dropped. Seeds
never expire. Nothing marks a seed as one to other buddies.

## Test it

```sh
npm test           # every route, the limits, names, gestures, the goal, expiry
npm run typecheck
```

The tests need no database and no secret. CI runs both
(`.github/workflows/ci.yml`, the "World server tests" job).

## The API

All JSON. A buddy sends `Authorization: Bearer <key>`.

| Route | Who | Does |
| --- | --- | --- |
| `POST /v1/buddies` | Anyone | `{name, utc_offset}` → `{id, key, name, name_ok}`. The key is in this response only. At most 5 from one IP address in an hour; past it, 429 with `Retry-After` |
| `PUT /v1/buddies/me` | A buddy | Its state and what it added since its last send (`fixtures/buddy-state.json`). The reply (`fixtures/buddy-reply.json`) carries the gestures waiting for it and the current `rewards` |
| `DELETE /v1/buddies/me` | A buddy | Leaves the world: its row, days, reports and gestures go |
| `GET /v1/world` | Anyone | The snapshot (`fixtures/world.json`), cached 30 s at Vercel's edge |
| `GET /v1/league` | Anyone; a buddy's key adds `me` and `last_week` | The week's league (`fixtures/league.json`): the top 100 by the week's XP, a tie to the first joined; with a key, its place, the buddy just ahead and behind, its percent among those with XP, and last week's place |
| `GET /v1/buddies/:id` | Anyone; a buddy's key adds `between` | A buddy's public profile (`fixtures/buddy.json`): name, level, colour, region, what it does now, days in a row, medals, the week's XP and place, its best week, today's counts; with a key, the newest gesture each way and the last week this one beat it |
| `POST /v1/gestures` | A buddy | `{to, kind}`, with `kind` one of `boop`, `wave`, `heart`, `cheer` |
| `GET /v1/gestures` | A buddy | `{gestures: [{kind, from_region, from, at}]}`, `from` the sender's `{id, name}` as the world shows it (null once it's gone), so it can be answered, for a Mac that hasn't sent in a while. Each gesture is handed out once, here or in a send's reply |
| `POST /v1/reports` | A buddy | `{buddy}`: reports a name. Three buddies' reports hide it |
| `PUT /v1/admin/goal` | The owner, with `ADMIN_TOKEN` | Sets the goal. The newest goal is the current one |
| `GET /v1/health` | Anyone | `{ok, db}` |
| `GET /api/cron/expire` | Vercel Cron, with `CRON_SECRET` | The expiry below |

What the Mac must know about `PUT /v1/buddies/me`:

- **Only the keys in `fixtures/buddy-state.json` are taken.** Any other
  key is refused with 400, but for `stage`, which a Mac built before Boop
  was one size still sends: it's taken and ignored (`IGNORED_KEYS`).
- **`utc_offset` is the Mac's offset from UTC, in minutes** (60, -480,
  330), from -720 to 840 and a multiple of 15; any other is refused with
  400. Left out, the last one stays; `null` clears it. The server keeps no
  country and no time zone name.
- **`seq` must grow.** A send whose `seq` isn't above the last one counted
  gets `{ok: true, duplicate: true}` and counts nothing. So a resend after
  a timeout is safe.
- **At most one send each 10 s.** The Mac sends on change, and at least
  about every 10 minutes. A send that is too soon gets 429 with
  `Retry-After`, and counts nothing. Keep adding to `added` until a send
  gets 200.
- **`xp_today` is the Mac's day's total, with `day`.** The server counts
  only what's new since the last send for the same `day`, and at most 300
  XP in a UTC day.
- **`days_in_a_row` and `color`** (0 to 7) are what the buddy card shows.
  Left out, the last ones stay.
- **Counts are clamped** to what's plausible for the minutes since the last
  send. The response says what was counted (`counted`), what was clamped
  (`clamped`), how the name shows (`name`, `name_ok`, `name_reason`,
  `name_hidden`), and the buddy's part of the goal (`goal_added`).
- **The reply hands out what's waiting**: `gestures`, as
  `GET /v1/gestures` does and each once, and the world's current
  `rewards`, as in the snapshot. A resend's reply (`duplicate`) does too; a
  429 does not. So a Mac that sends on change rarely needs to poll. The
  send the Mac makes as it quits adds `?keep_gestures=1`: its reply hands
  out none, and they wait for the next launch's send or `GET`. It also
  carries `last_week`, the buddy's place in the week before, or null.

A buddy not seen for 15 minutes counts as asleep in the snapshot.
The snapshot's `regions` are always the three, in this order, from each
buddy's offset: `americas` (UTC-12 to -2), `europe_africa` (-1h45 to +3)
and `asia_oceania` (+3h15 to +14). A buddy with no offset is in none. The
server's days are UTC, and a league week runs from Monday 00:00 UTC. A week
that has ended is closed at the first league request, send or profile
after it, once: each buddy with XP gets its place, and the top three get
medals. The numbers here are in `src/limits.ts`.

## What it keeps, and for how long

| What | Kept | Gone |
| --- | --- | --- |
| A buddy: a random id, its key's hash, name, level, UTC offset, activity, when last seen | While it sends | 30 days after it was last seen, or at once when it leaves |
| What a buddy added each UTC day: XP, turns, tests passed, ships, lines changed | 400 days | Then summed with every other buddy's into one row a day (`totals_by_day`), with no buddy in it |
| Who joined lately: each join's IP address as an HMAC-SHA256 with `IP_SALT`, never the address | An hour | At the next join, or by the cron |
| Gestures, with the sender and its region | Until delivered | A day after delivery, or after two days unread |
| Name reports: who reported whom | While both buddies exist | When the name changes, or either buddy goes |
| Goals | Always | |
| A closed week's places: each buddy's place and XP | 12 weeks | Then deleted; or with the buddy |
| Medals | While the buddy exists | With the buddy |

It keeps no person, account, email, thread or project name, code or text.
It never logs a key. Vercel's request logs record each request's path and
IP address, as for any site.

## Deploy it

The owner's steps, once (plan/world.md §5).

1. In Vercel, **import the GitHub repository** as a new project. Set the
   **Root Directory** to `internal/world` and the production branch to the
   branch you deploy from (`main-v2`). Vercel detects Hono and Node 24 from
   `package.json`; leave the build settings empty. Or, from the Mac:
   `npx vercel login`, then `npx vercel --cwd internal/world`.
2. In the project's **Storage** tab, add **Neon Postgres** from the
   Marketplace, on the free plan. It sets `DATABASE_URL` in the project.
3. In **Settings → Environment Variables**, add `ADMIN_TOKEN`,
   `CRON_SECRET` and `IP_SALT`, each a long random string, for example from
   `openssl rand -base64 32`. With `IP_SALT` unset, each instance makes its
   own salt, and counts joins only on its own. Keep `ADMIN_TOKEN` somewhere safe: you need
   it to set a goal.
4. On the Mac, create the tables:

   ```sh
   cd internal/world
   npm ci
   npx vercel link
   npx vercel env pull .env.local --environment=production
   npm run migrate
   ```

   `npm run migrate` reads `DATABASE_URL` from `.env.local`, which git
   ignores. It applies only the migrations not yet applied, so it is safe
   to run again after a new one lands.
5. **Deploy**: push to the production branch, or `npx vercel --prod`. Then
   check that `https://<project>.vercel.app/v1/health` says
   `{"ok":true,"db":true}`.
6. Optional: add a domain, such as `world.adoptaboop.com`, in
   **Settings → Domains**.
7. Set the first goal:

   ```sh
   curl -X PUT https://<project>.vercel.app/v1/admin/goal \
     -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
     -d '{"title":"A million tests this month","metric":"tests_passed","target":1000000,
          "starts":"2026-12-01","ends":"2026-12-31","reward_tag":"worldparty","reward_days":3}'
   ```

   `metric` is one of `tests_passed`, `ships`, `turns`, `lines_changed` and
   `xp`. `starts` is today if you leave it out, and `reward_days` is 3.
8. If the domain isn't `https://world.adoptaboop.com`, point the Mac app at
   it with `BOOP_WORLD_URL`.

The cron runs once a day on production deployments only. Vercel sends
`CRON_SECRET` with it. To run it by hand:
`curl -H "Authorization: Bearer $CRON_SECRET" https://<project>.vercel.app/api/cron/expire`.

To unhide a reported name after you look at it, there's no route yet: in
Neon's SQL editor, `update buddies set reports = 0 where id = '…'` and
`delete from name_reports where buddy = '…'`.

### The deployment, as it is (2026-11-08)

- Project `boop-world` on the owner's Vercel account, production at
  `https://boop-world-michaeljxzhu.vercel.app`, Neon's free plan for Postgres.
  Deployed from a Mac with `npx vercel deploy --prod`, not from GitHub yet.
- Deployment Protection is off for this project: buddies' Macs can't log in, and
  every route that changes anything needs a buddy's key or the admin token.
- `vercel.json` names the framework (`"framework": "hono"`): a project made
  from the command line has none, and then nothing is built.
- TypeScript stays at 5.x: Vercel's build used TypeScript 7 from this package
  and then couldn't find Node's types.
- The admin token is in Vercel (sensitive, so it can't be read back) and in
  `~/.boopdev/world-admin-token` on the owner's Mac, readable only by them.
