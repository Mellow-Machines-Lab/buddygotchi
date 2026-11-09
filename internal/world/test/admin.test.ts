// The owner's routes and the cron: the admin token, the goal's checks, the
// expiry (plan/world.md §2.3, "Kept for how long"), health and migrations.

import assert from "node:assert/strict";
import { test } from "node:test";
import { createApp } from "../src/app.js";
import { migrate } from "../src/db.js";
import { BUDDY_EXPIRES_DAYS, DAYS_KEPT } from "../src/limits.js";
import { ADMIN, CRON, state, world } from "./helpers.js";

const w = world();
const goal = { title: "A million tests", metric: "tests_passed", target: 1_000_000, ends: "2099-12-31", reward_tag: "worldparty" };

test("health says the database is up", async () => {
  assert.deepEqual((await w.json("GET", "/v1/health")).body, { ok: true, db: true });
  const down = createApp(async () => {
    throw new Error("no database");
  });
  const saved = console.error;
  console.error = () => {};
  try {
    const res = await down.request("/v1/health");
    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), { ok: false, db: false });
  } finally {
    console.error = saved;
  }
});

test("an unknown path is a JSON 404", async () => {
  const r = await w.json("GET", "/v1/nothing");
  assert.deepEqual([r.status, r.body], [404, { error: "not_found" }]);
});

test("setting the goal needs the admin token", async () => {
  assert.equal((await w.json("PUT", "/v1/admin/goal", { body: goal })).status, 401);
  assert.equal((await w.json("PUT", "/v1/admin/goal", { key: "wrong", body: goal })).status, 401);
  const b = await w.join();
  assert.equal((await w.json("PUT", "/v1/admin/goal", { key: b.key, body: goal })).status, 401, "a buddy's key isn't the token");
  const unset = createApp(async () => w.db, { adminToken: () => undefined });
  assert.equal((await unset.request("/v1/admin/goal", { method: "PUT", headers: { authorization: "Bearer " }, body: JSON.stringify(goal) })).status, 401, "an unset token lets nobody in");
  const r = await w.json("PUT", "/v1/admin/goal", { key: ADMIN, body: goal });
  assert.equal(r.status, 200);
  assert.equal(r.body.goal.title, "A million tests");
});

test("a bad goal is refused, and the newest goal is the current one", async () => {
  for (const bad of [{ ...goal, metric: "prompts" }, { ...goal, target: 0 }, { ...goal, ends: "soon" }, { ...goal, reward_tag: "World Party" }, { ...goal, reward_days: 99 }, { ...goal, title: "" }]) {
    assert.equal((await w.json("PUT", "/v1/admin/goal", { key: ADMIN, body: bad })).status, 400, JSON.stringify(bad));
  }
  await w.json("PUT", "/v1/admin/goal", { key: ADMIN, body: goal });
  await w.json("PUT", "/v1/admin/goal", { key: ADMIN, body: { ...goal, title: "Ships", metric: "ships", target: 50 } });
  assert.equal((await w.json("GET", "/v1/world")).body.goal.title, "Ships");
});

test("the cron needs CRON_SECRET", async () => {
  assert.equal((await w.json("GET", "/api/cron/expire")).status, 401);
  assert.equal((await w.json("GET", "/api/cron/expire", { key: ADMIN })).status, 401);
  assert.equal((await w.json("GET", "/api/cron/expire", { key: CRON })).status, 200);
});

test("expiry: old buddies, old days into totals_by_day, and gestures", async () => {
  const old = await w.join("Old");
  const kept = await w.join("Kept");
  const other = await w.join("Other");
  await w.send(kept, state({ added: { turns: 1 } }));
  await w.db.query(`update buddies set seen_at = now() - make_interval(days => $1) - interval '1 hour' where id = $2`, [BUDDY_EXPIRES_DAYS, old.id]);
  await w.db.query(`update buddies set seen_at = now() - make_interval(days => $1) + interval '1 hour' where id = $2`, [BUDDY_EXPIRES_DAYS, kept.id]);
  await w.db.query(
    `insert into buddy_days (buddy, day, xp, turns, ships) values
       ($1, (now() at time zone 'utc')::date - $3::int - 1, 50, 7, 1),
       ($2, (now() at time zone 'utc')::date - $3::int - 1, 20, 3, 0),
       ($1, (now() at time zone 'utc')::date - $3::int + 1, 10, 5, 0)`,
    [kept.id, other.id, DAYS_KEPT],
  );
  await w.db.query(
    `insert into gestures (to_buddy, from_buddy, kind, created_at, delivered_at) values
       ($1, $2, 'boop', now() - interval '3 days', now() - interval '25 hours'),
       ($1, $2, 'wave', now() - interval '3 days', null),
       ($1, $2, 'heart', now() - interval '2 hours', now() - interval '1 hour'),
       ($1, $2, 'cheer', now() - interval '47 hours', null)`,
    [kept.id, other.id],
  );

  const r = await w.json("GET", "/api/cron/expire", { key: CRON });
  assert.deepEqual(r.body, { ok: true, buddies: 1, days: 2, gestures: 2 });
  assert.equal((await w.db.query("select 1 from buddies where id = $1", [old.id])).length, 0);
  assert.equal((await w.db.query("select 1 from buddies where id = $1", [kept.id])).length, 1);
  const totals = await w.db.query("select xp::int, turns::int, ships::int from totals_by_day");
  assert.deepEqual(totals, [{ xp: 70, turns: 10, ships: 1 }], "summed over every buddy");
  assert.equal((await w.db.query("select 1 from buddy_days")).length, 2, "the recent days stay");
  assert.deepEqual((await w.db.query<{ kind: string }>("select kind from gestures order by kind")).map((g) => g.kind), ["cheer", "heart"]);

  const again = await w.json("GET", "/api/cron/expire", { key: CRON });
  assert.deepEqual(again.body, { ok: true, buddies: 0, days: 0, gestures: 0 });
  assert.deepEqual(await w.db.query("select xp::int, turns::int, ships::int from totals_by_day"), [{ xp: 70, turns: 10, ships: 1 }], "nothing summed twice");
});

test("migrations run once", async () => {
  assert.deepEqual(await migrate(w.db), [], "already applied");
  const rows = await w.db.query<{ name: string }>("select name from schema_migrations");
  assert.deepEqual(rows.map((r) => r.name), ["001_world.sql", "002_utc_offset.sql"]);
});
