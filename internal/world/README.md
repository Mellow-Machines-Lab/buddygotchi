# The world server

Updated 2026-11-08.

Every buddy that joins the world talks to this server. A buddy sends its
state and counts each minute. Each Mac reads the world's snapshot: how many
buddies are awake, what they do, the day's and the year's totals, the goal
and a sample of buddies for the map. Buddies send each other boops, waves,
hearts and cheers. The design is in [plan/world.md](../../plan/world.md) §2.

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
| `src/regions.ts` | The UTC offsets a buddy may send, and the regions they fall in: their boundaries, in one place |
| `src/auth.ts` | Buddy keys: 32 random bytes, base64url; the server keeps only their sha256 |
| `db/migrations/` | Plain SQL, applied in name order, each once |
| `scripts/migrate.ts`, `scripts/dev.ts` | `npm run migrate` and `npm run dev` |
| `test/` | `node:test` against PGlite; `postgres.test.ts` goes through the `postgres` driver too, with PGlite over a socket |
| `fixtures/` | The wire's examples: what a buddy sends, and what the world returns. The Mac's tests decode them too |
| `vercel.json` | The daily cron that expires old rows |

## Run it

```sh
cd internal/world
npm ci
npm run dev        # http://localhost:8787, on PGlite in memory; PORT changes the port
```

The local server starts empty each time. Its admin token and cron secret
are `dev`, unless `ADMIN_TOKEN` or `CRON_SECRET` is set. To point the Mac
app at it, set `BOOP_WORLD_URL=http://localhost:8787`.

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
| `POST /v1/buddies` | Anyone | `{name, utc_offset}` → `{id, key, name, name_ok}`. The key is in this response only |
| `PUT /v1/buddies/me` | A buddy | Its state and what it added since its last send (`fixtures/buddy-state.json`) |
| `DELETE /v1/buddies/me` | A buddy | Leaves the world: its row, days, reports and gestures go |
| `GET /v1/world` | Anyone | The snapshot (`fixtures/world.json`), cached 30 s at Vercel's edge |
| `POST /v1/gestures` | A buddy | `{to, kind}`, with `kind` one of `boop`, `wave`, `heart`, `cheer` |
| `GET /v1/gestures` | A buddy | `{gestures: [{kind, from_region, at}]}`, each handed out once |
| `POST /v1/reports` | A buddy | `{buddy}`: reports a name. Three buddies' reports hide it |
| `PUT /v1/admin/goal` | The owner, with `ADMIN_TOKEN` | Sets the goal. The newest goal is the current one |
| `GET /v1/health` | Anyone | `{ok, db}` |
| `GET /api/cron/expire` | Vercel Cron, with `CRON_SECRET` | The expiry below |

What the Mac must know about `PUT /v1/buddies/me`:

- **Only the keys in `fixtures/buddy-state.json` are taken.** Any other
  key is refused with 400.
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
  only what's new since the last send for the same `day`, and at most 100
  XP in a UTC day.
- **Counts are clamped** to what's plausible for the minutes since the last
  send. The response says what was counted (`counted`), what was clamped
  (`clamped`), how the name shows (`name`, `name_ok`, `name_reason`,
  `name_hidden`), and the buddy's part of the goal (`goal_added`).

A buddy not seen for 15 minutes counts as asleep in the snapshot.
The snapshot's `regions` are always the three, in this order, from each
buddy's offset: `americas` (UTC-12 to -2), `europe_africa` (-1h45 to +3)
and `asia_oceania` (+3h15 to +14). A buddy with no offset is in none. The
server's days are UTC. The numbers here are in `src/limits.ts`.

## What it keeps, and for how long

| What | Kept | Gone |
| --- | --- | --- |
| A buddy: a random id, its key's hash, name, level, stage, UTC offset, activity, when last seen | While it sends | 30 days after it was last seen, or at once when it leaves |
| What a buddy added each UTC day: XP, turns, tests passed, ships, lines changed | 400 days | Then summed with every other buddy's into one row a day (`totals_by_day`), with no buddy in it |
| Gestures, with the sender's region | Until delivered | A day after delivery, or after two days unread |
| Name reports: who reported whom | While both buddies exist | When the name changes, or either buddy goes |
| Goals | Always | |

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
3. In **Settings → Environment Variables**, add `ADMIN_TOKEN` and
   `CRON_SECRET`, each a long random string, for example from
   `openssl rand -base64 32`. Keep `ADMIN_TOKEN` somewhere safe: you need
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
