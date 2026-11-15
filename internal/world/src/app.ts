// The world's routes. This file is the Vercel entry too: Vercel finds a Hono
// app by its default export in src/app.ts, so no rewrites are needed.
//
// A buddy authenticates with `Authorization: Bearer <key>`. A key is never
// logged or sent back, except once, when the buddy joins.

import { Hono, type Context } from "hono";
import { bodyLimit } from "hono/body-limit";
import { bearer, buddyFor, clientIp, ipHash, keyHash, matchesSecret, newKey } from "./auth.js";
import { defaultDb, type Db } from "./db.js";
import * as L from "./limits.js";
import { checkName, shownName } from "./names.js";
import { UTC_OFFSET_MAX, UTC_OFFSET_MIN, regionOf, validOffset } from "./regions.js";
import {
  ACTIVITIES, COUNTS, METRICS, TODAY, checkGoal, currentRewards, deliverGestures, goalAdded, snapshot, type Count,
} from "./world.js";

export const STAGES = ["hatchling", "sprout", "buddy", "chonk"] as const;
export const GESTURES = ["boop", "wave", "heart", "cheer"] as const;
/** Every key a buddy may send in PUT /v1/buddies/me. Any other is refused. */
export const STATE_KEYS = [
  "seq", "name", "level", "stage", "utc_offset", "activity", "day", "xp_today", "added",
] as const;

export interface Options {
  /** Read on each request, so tests can set them. Default: the environment. */
  adminToken?: () => string | undefined;
  cronSecret?: () => string | undefined;
  /** The salt for IP addresses' hashes. Unset: a random one for this instance. */
  ipSalt?: () => string | undefined;
}

type Env = { Variables: { db: Db; buddy: string } };

class BadRequest extends Error {}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const isInt = (v: unknown): v is number => Number.isSafeInteger(v);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const TAG = /^[a-z][a-z0-9]{0,23}$/;

/** A buddy's UTC offset, when it sent one: null clears it, a bad one is refused. */
function offset(v: unknown): number | null {
  if (v === undefined || v === null) return null;
  if (!validOffset(v)) {
    throw new BadRequest(`utc_offset must be minutes from ${UTC_OFFSET_MIN} to ${UTC_OFFSET_MAX}, a multiple of 15`);
  }
  return v;
}

function validDate(v: unknown): v is string {
  return typeof v === "string" && DATE.test(v) && !Number.isNaN(Date.parse(`${v}T00:00:00Z`));
}

async function json(c: Context): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    throw new BadRequest("the body must be JSON");
  }
  if (!isObject(body)) throw new BadRequest("the body must be a JSON object");
  return body;
}

const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));

export function createApp(getDb: () => Promise<Db> = defaultDb, options: Options = {}) {
  const adminToken = options.adminToken ?? (() => process.env.ADMIN_TOKEN);
  const cronSecret = options.cronSecret ?? (() => process.env.CRON_SECRET);
  const ipSalt = options.ipSalt ?? (() => process.env.IP_SALT);
  const app = new Hono<Env>();

  app.onError((err, c) => {
    if (err instanceof BadRequest) return c.json({ error: "bad_request", message: err.message }, 400);
    // The message only: never the request, whose headers hold a key.
    console.error(`${c.req.method} ${c.req.path}: ${err.message}`);
    return c.json({ error: "server_error" }, 500);
  });
  app.notFound((c) => c.json({ error: "not_found" }, 404));
  app.use(bodyLimit({ maxSize: 16 * 1024, onError: (c) => c.json({ error: "too_large" }, 413) }));

  // The health check opens the database itself, so it can say it's down.
  app.get("/v1/health", async (c) => {
    try {
      const db = await getDb();
      await db.query("select 1");
      return c.json({ ok: true, db: true });
    } catch (err) {
      console.error(`health: ${(err as Error).message}`);
      return c.json({ ok: false, db: false }, 503);
    }
  });

  app.use(async (c, next) => {
    c.set("db", await getDb());
    await next();
  });

  /** Only a buddy with its key gets past this. */
  const buddy = async (c: Context<Env>, next: () => Promise<void>) => {
    const id = await buddyFor(c.var.db, bearer(c.req.header("authorization")));
    if (!id) return c.json({ error: "unauthorized" }, 401);
    c.set("buddy", id);
    await next();
  };

  // Joins the world. The key is in this response and nowhere else.
  app.post("/v1/buddies", async (c) => {
    const body = await json(c);
    const name = checkName(body.name);
    const utcOffset = offset(body.utc_offset);

    // At most JOINS_PER_IP_PER_HOUR from one address, which is kept only as
    // its keyed hash, and only for the hour.
    const hash = ipHash(clientIp((h) => c.req.header(h)), ipSalt());
    const retryAfter = await c.var.db.transaction(async (tx) => {
      await tx.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", [hash]);
      await tx.query("delete from joins where at <= now() - interval '1 hour'");
      const [n] = await tx.query<{ n: number; wait: number | null }>(
        `select count(*)::int as n, extract(epoch from min(at) + interval '1 hour' - now())::float8 as wait
           from joins where ip_hash = decode($1, 'hex')`,
        [hash],
      );
      if (n.n >= L.JOINS_PER_IP_PER_HOUR) return Math.max(1, Math.ceil(n.wait ?? 3600));
      await tx.query("insert into joins (ip_hash) values (decode($1, 'hex'))", [hash]);
      return undefined;
    });
    if (retryAfter !== undefined) {
      c.header("Retry-After", String(retryAfter));
      return c.json({ error: "too_many", retry_after: retryAfter }, 429);
    }

    const id = crypto.randomUUID();
    const key = newKey();
    await c.var.db.query(
      `insert into buddies (id, key_hash, name, name_ok, utc_offset, activity, seen_at, created_at)
       values ($1, decode($2, 'hex'), $3, $4, $5, 'idle', now(), now())`,
      [id, keyHash(key), name.name, name.ok, utcOffset],
    );
    const shown = shownName({ name: name.name, name_ok: name.ok, reports: 0 });
    return c.json({ id, key, name: shown, name_ok: name.ok, ...(name.reason && { name_reason: name.reason }) }, 201);
  });

  // A buddy's state and what it added since its last send.
  app.put("/v1/buddies/me", buddy, async (c) => {
    const body = await json(c);
    const unknown = Object.keys(body).filter((k) => !(STATE_KEYS as readonly string[]).includes(k));
    if (unknown.length) throw new BadRequest(`unknown keys: ${unknown.join(", ")}`);
    const { seq, activity } = body;
    if (!isInt(seq) || seq < 1) throw new BadRequest("seq must be a positive integer");
    if (!(ACTIVITIES as readonly unknown[]).includes(activity)) throw new BadRequest(`activity must be one of ${ACTIVITIES.join(", ")}`);
    if (body.level !== undefined && (!isInt(body.level) || body.level < 1)) throw new BadRequest("level must be a positive integer");
    if (body.stage !== undefined && body.stage !== null && !(STAGES as readonly unknown[]).includes(body.stage)) throw new BadRequest(`stage must be one of ${STAGES.join(", ")}`);
    if (body.day !== undefined && !validDate(body.day)) throw new BadRequest("day must be YYYY-MM-DD");
    if (body.xp_today !== undefined && (!isInt(body.xp_today) || body.day === undefined)) throw new BadRequest("xp_today must be an integer, with day");
    const utcOffset = offset(body.utc_offset);
    const added = body.added ?? {};
    if (!isObject(added)) throw new BadRequest("added must be an object");
    for (const [k, v] of Object.entries(added)) {
      if (!(COUNTS as readonly string[]).includes(k)) throw new BadRequest(`unknown count: ${k}`);
      if (!isInt(v) || v < 0) throw new BadRequest(`${k} must be a non-negative integer`);
    }
    const id = c.var.buddy;

    type Row = { last_seq: number; since_ms: number | null; name: string; xp_day: string | null; xp_today: number };
    const result = await c.var.db.transaction(async (tx) => {
      const [row] = await tx.query<Row>(
        `select last_seq::float8 as last_seq, name, to_char(xp_day, 'YYYY-MM-DD') as xp_day, xp_today,
                (extract(epoch from now() - sent_at) * 1000)::float8 as since_ms
           from buddies where id = $1 for update`,
        [id],
      );
      if (seq <= row.last_seq) return { status: "duplicate" as const };
      if (row.since_ms !== null && row.since_ms < L.SEND_EVERY_MS) {
        return { status: "too_soon" as const, retryAfter: Math.ceil((L.SEND_EVERY_MS - row.since_ms) / 1000) };
      }

      // The counts, each within what's plausible for the minutes since the last send.
      const clamped: string[] = [];
      const minutes = row.since_ms === null ? 1 : clamp(row.since_ms / 60_000, 1, L.ADDED_MAX_MINUTES);
      const counts = {} as Record<Count, number>;
      for (const k of COUNTS) {
        const sent = (added[k] as number | undefined) ?? 0;
        const most = Math.floor(L.ADDED_PER_MINUTE[k] * minutes);
        counts[k] = Math.min(sent, most);
        if (sent > most) clamped.push(k);
      }

      // XP: only what's new since the last send of the same Mac day, and at
      // most XP_PER_DAY in a UTC day, so the ring's cap holds either way.
      let xp = 0;
      let xpDay = row.xp_day;
      let xpToday = row.xp_today;
      if (body.xp_today !== undefined) {
        const sent = body.xp_today as number;
        const today = clamp(sent, 0, L.XP_PER_DAY);
        if (today !== sent) clamped.push("xp_today");
        xp = body.day === row.xp_day ? Math.max(0, today - row.xp_today) : today;
        xpDay = body.day as string;
        xpToday = body.day === row.xp_day ? Math.max(today, row.xp_today) : today;
      }
      const [{ xp: before }] = await tx.query<{ xp: number }>(
        `select coalesce((select xp from buddy_days where buddy = $1 and day = ${TODAY}), 0) as xp`,
        [id],
      );
      const xpCounted = Math.min(xp, L.XP_PER_DAY - before);
      if (xpCounted < xp && !clamped.includes("xp_today")) clamped.push("xp_today");

      if (xpCounted > 0 || COUNTS.some((k) => counts[k] > 0)) {
        await tx.query(
          `insert into buddy_days (buddy, day, xp, turns, tests_passed, ships, lines_changed)
           values ($1, ${TODAY}, $2, $3, $4, $5, $6)
           on conflict (buddy, day) do update set
             xp = buddy_days.xp + excluded.xp, turns = buddy_days.turns + excluded.turns,
             tests_passed = buddy_days.tests_passed + excluded.tests_passed,
             ships = buddy_days.ships + excluded.ships, lines_changed = buddy_days.lines_changed + excluded.lines_changed`,
          [id, xpCounted, counts.turns, counts.tests_passed, counts.ships, counts.lines_changed],
        );
      }

      // A new name is checked again, and its reports start over.
      const renamed = body.name !== undefined && checkName(body.name);
      if (renamed && renamed.name !== row.name) {
        await tx.query("update buddies set name = $2, name_ok = $3, reports = 0 where id = $1", [id, renamed.name, renamed.ok]);
        await tx.query("delete from name_reports where buddy = $1", [id]);
      }
      await tx.query(
        `update buddies set last_seq = $2, sent_at = now(), seen_at = now(), activity = $3,
                level = coalesce($4, level), stage = case when $5::boolean then $6 else stage end,
                utc_offset = case when $7::boolean then $8::int else utc_offset end,
                xp_day = $9::date, xp_today = $10
          where id = $1`,
        [
          id, seq, activity,
          body.level === undefined ? null : Math.min(body.level as number, L.LEVEL_MAX),
          "stage" in body, body.stage ?? null,
          "utc_offset" in body, utcOffset,
          xpDay, xpToday,
        ],
      );
      if (clamped.length) console.warn(`buddy ${id}: clamped ${clamped.join(", ")}`);
      return { status: "ok" as const, counted: { xp: xpCounted, ...counts }, clamped };
    });

    if (result.status === "too_soon") {
      c.header("Retry-After", String(result.retryAfter));
      return c.json({ error: "too_soon", retry_after: result.retryAfter }, 429);
    }
    if (result.status === "ok") await checkGoal(c.var.db);
    const [me] = await c.var.db.query<{ name: string; name_ok: boolean; reports: number }>(
      "select name, name_ok, reports from buddies where id = $1",
      [id],
    );
    const name = checkName(me.name);
    return c.json({
      ok: true,
      ...(result.status === "duplicate" ? { duplicate: true } : { counted: result.counted, clamped: result.clamped }),
      name: shownName(me),
      name_ok: me.name_ok,
      ...(name.reason && { name_reason: name.reason }),
      name_hidden: me.reports >= L.REPORTS_TO_HIDE,
      goal_added: await goalAdded(c.var.db, id),
      // So a Mac that sends on change rarely needs to poll.
      rewards: await currentRewards(c.var.db),
      // The Mac's last send before it quits keeps them for its next launch:
      // a reply it may not live to read would lose them.
      gestures: c.req.query("keep_gestures") === "1" ? [] : await deliverGestures(c.var.db, id),
    });
  });

  // Leaves the world: the buddy, its days, its reports and every gesture to or from it.
  app.delete("/v1/buddies/me", buddy, async (c) => {
    await c.var.db.transaction(async (tx) => {
      await tx.query("delete from gestures where from_buddy = $1", [c.var.buddy]);
      await tx.query("delete from buddies where id = $1", [c.var.buddy]);
    });
    return c.json({ ok: true });
  });

  app.get("/v1/world", async (c) => {
    c.header("Cache-Control", `public, max-age=0, s-maxage=${L.SNAPSHOT_CACHE_SECONDS}`);
    return c.json(await snapshot(c.var.db));
  });

  app.post("/v1/gestures", buddy, async (c) => {
    const body = await json(c);
    const { to, kind } = body;
    if (typeof to !== "string" || !UUID.test(to)) throw new BadRequest("to must be a buddy's id");
    if (!(GESTURES as readonly unknown[]).includes(kind)) throw new BadRequest(`kind must be one of ${GESTURES.join(", ")}`);
    const from = c.var.buddy;
    if (to.toLowerCase() === from) throw new BadRequest("a buddy can't gesture to itself");
    const sent = await c.var.db.transaction(async (tx) => {
      const [me] = await tx.query<{ utc_offset: number | null }>("select utc_offset from buddies where id = $1 for update", [from]);
      const target = await tx.query("select 1 from buddies where id = $1", [to]);
      if (!target.length) return "not_found" as const;
      const [n] = await tx.query<{ total: number; one: number }>(
        `select count(*)::int as total, (count(*) filter (where to_buddy = $2))::int as one
           from gestures where from_buddy = $1 and created_at > now() - interval '1 hour'`,
        [from, to],
      );
      if (n.total >= L.GESTURES_SENT_PER_HOUR || n.one >= L.GESTURES_TO_ONE_PER_HOUR) return "too_many" as const;
      await tx.query("insert into gestures (to_buddy, from_buddy, kind, from_region) values ($1, $2, $3, $4)", [to, from, kind, regionOf(me.utc_offset)]);
      return "sent" as const;
    });
    if (sent === "not_found") return c.json({ error: "not_found" }, 404);
    if (sent === "too_many") return c.json({ error: "too_many" }, 429);
    return c.json({ ok: true }, 201);
  });

  // What's waiting for this buddy, for a Mac that hasn't sent in a while.
  // Each gesture is handed out once, here or in the PUT's reply.
  app.get("/v1/gestures", buddy, async (c) => {
    return c.json({ gestures: await deliverGestures(c.var.db, c.var.buddy) });
  });

  // Reports a name. Each buddy counts once; at REPORTS_TO_HIDE the name is hidden.
  app.post("/v1/reports", buddy, async (c) => {
    const body = await json(c);
    const target = body.buddy;
    if (typeof target !== "string" || !UUID.test(target)) throw new BadRequest("buddy must be a buddy's id");
    if (target.toLowerCase() === c.var.buddy) throw new BadRequest("a buddy can't report itself");
    const result = await c.var.db.transaction(async (tx) => {
      const found = await tx.query("select 1 from buddies where id = $1 for update", [target]);
      if (!found.length) return undefined;
      const added = await tx.query(
        "insert into name_reports (buddy, reporter) values ($1, $2) on conflict do nothing returning buddy",
        [target, c.var.buddy],
      );
      const [row] = await tx.query<{ reports: number }>(
        "update buddies set reports = reports + $2 where id = $1 returning reports",
        [target, added.length],
      );
      return row.reports;
    });
    if (result === undefined) return c.json({ error: "not_found" }, 404);
    return c.json({ ok: true, hidden: result >= L.REPORTS_TO_HIDE });
  });

  // Sets the world's goal. The newest goal is the current one.
  app.put("/v1/admin/goal", async (c) => {
    if (!matchesSecret(bearer(c.req.header("authorization")), adminToken())) return c.json({ error: "unauthorized" }, 401);
    const body = await json(c);
    const { title, metric, target, starts, ends, reward_tag, reward_days = 3 } = body;
    if (typeof title !== "string" || !title.trim() || title.length > 120) throw new BadRequest("title must be a short string");
    if (!(METRICS as readonly unknown[]).includes(metric)) throw new BadRequest(`metric must be one of ${METRICS.join(", ")}`);
    if (!isInt(target) || target < 1) throw new BadRequest("target must be a positive integer");
    if (starts !== undefined && !validDate(starts)) throw new BadRequest("starts must be YYYY-MM-DD");
    if (!validDate(ends)) throw new BadRequest("ends must be YYYY-MM-DD");
    if (typeof reward_tag !== "string" || !TAG.test(reward_tag)) throw new BadRequest("reward_tag must be a short lowercase tag");
    if (!isInt(reward_days) || reward_days < 1 || reward_days > L.REWARD_DAYS_MAX) throw new BadRequest(`reward_days must be 1 to ${L.REWARD_DAYS_MAX}`);
    await c.var.db.query(
      `insert into goals (title, metric, target, starts, ends, reward_tag, reward_days)
       values ($1, $2, $3, coalesce($4::date, ${TODAY}), $5::date, $6, $7)`,
      [title.trim(), metric, target, starts ?? null, ends, reward_tag, reward_days],
    );
    const { goal } = await checkGoal(c.var.db);
    return c.json({ ok: true, goal });
  });

  // The daily expiry, called by Vercel Cron with CRON_SECRET.
  app.get("/api/cron/expire", async (c) => {
    if (!matchesSecret(bearer(c.req.header("authorization")), cronSecret())) return c.json({ error: "unauthorized" }, 401);
    return c.json({ ok: true, ...(await expire(c.var.db)) });
  });

  return app;
}

/** What's kept and for how long: see the README. Returns how many rows went. */
export async function expire(db: Db) {
  return db.transaction(async (tx) => {
    const buddies = await tx.query(
      "delete from buddies where seen_at < now() - make_interval(days => $1) returning id",
      [L.BUDDY_EXPIRES_DAYS],
    );
    const old = `day < ${TODAY} - $1::int`;
    await tx.query(
      `insert into totals_by_day (day, xp, turns, tests_passed, ships, lines_changed)
       select day, sum(xp), sum(turns), sum(tests_passed), sum(ships), sum(lines_changed)
         from buddy_days where ${old} group by day
       on conflict (day) do update set
         xp = totals_by_day.xp + excluded.xp, turns = totals_by_day.turns + excluded.turns,
         tests_passed = totals_by_day.tests_passed + excluded.tests_passed,
         ships = totals_by_day.ships + excluded.ships, lines_changed = totals_by_day.lines_changed + excluded.lines_changed`,
      [L.DAYS_KEPT],
    );
    const days = await tx.query(`delete from buddy_days where ${old} returning day`, [L.DAYS_KEPT]);
    const gestures = await tx.query(
      `delete from gestures
        where delivered_at < now() - make_interval(days => $1)
           or (delivered_at is null and created_at < now() - make_interval(days => $2))
        returning id`,
      [L.GESTURE_DELIVERED_KEPT_DAYS, L.GESTURE_UNREAD_KEPT_DAYS],
    );
    const joins = await tx.query("delete from joins where at <= now() - interval '1 hour' returning at");
    return { buddies: buddies.length, days: days.length, gestures: gestures.length, joins: joins.length };
  });
}

export default createApp();
