// The production path: the `postgres` driver, as on Vercel with Neon, here
// against PGlite served over a socket. Migrations through the driver, as
// `npm run migrate` runs them, then one buddy's day through every route.

import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { PGlite } from "@electric-sql/pglite";
import { PGLiteSocketServer } from "@electric-sql/pglite-socket";
import { createApp } from "../src/app.js";
import { connectPostgres, migrate, type Db } from "../src/db.js";
import { ADMIN, CRON, fixture } from "./helpers.js";

let pg: PGlite;
let server: PGLiteSocketServer;
let db: Db;
let app: ReturnType<typeof createApp>;

before(async () => {
  pg = new PGlite();
  // One connection: PGlite runs one session, so the pool has one too.
  server = new PGLiteSocketServer({ db: pg, port: 0, maxConnections: 1 });
  await server.start();
  db = await connectPostgres(`postgres://postgres@${server.getServerConn()}/postgres?sslmode=disable`, { max: 1 });
  app = createApp(async () => db, { adminToken: () => ADMIN, cronSecret: () => CRON });
});

after(async () => {
  await db.close();
  await server.stop();
  await pg.close();
});

async function call(method: string, path: string, key?: string, body?: unknown) {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (key) headers.authorization = `Bearer ${key}`;
  const res = await app.request(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: res.status, body: (await res.json()) as any };
}

test("migrations apply through the driver, once", async () => {
  assert.deepEqual(await migrate(db), ["001_world.sql"]);
  assert.deepEqual(await migrate(db), []);
});

test("every route through the driver, with numbers as numbers", async () => {
  assert.deepEqual((await call("GET", "/v1/health")).body, { ok: true, db: true });
  const a = (await call("POST", "/v1/buddies", undefined, { name: "Mochi", country: "PT", tz: "Europe/Lisbon" })).body;
  const b = (await call("POST", "/v1/buddies", undefined, { name: "Bean", country: "JP", tz: "Asia/Tokyo" })).body;
  assert.equal((await call("PUT", "/v1/admin/goal", ADMIN, { title: "Two tests", metric: "tests_passed", target: 2, ends: "2099-12-31", reward_tag: "worldparty" })).status, 200);

  const sent = await call("PUT", "/v1/buddies/me", a.key, fixture("buddy-state.json"));
  assert.equal(sent.status, 200);
  assert.deepEqual(sent.body.counted, { xp: 82, turns: 3, tests_passed: 2, ships: 0, lines_changed: 140 });
  assert.equal(sent.body.goal_added, 2);
  assert.equal((await call("PUT", "/v1/buddies/me", a.key, fixture("buddy-state.json"))).body.duplicate, true);
  assert.equal((await call("PUT", "/v1/buddies/me", a.key, { ...fixture<Record<string, unknown>>("buddy-state.json"), seq: 419 })).status, 429);

  const world = (await call("GET", "/v1/world")).body;
  assert.equal(world.total, 2);
  assert.deepEqual(world.today, { turns: 3, tests_passed: 2, ships: 0, lines_changed: 140 });
  assert.equal(world.goal.progress, 2);
  assert.equal(world.goal.reached, true);
  assert.equal(world.rewards[0].tag, "worldparty");
  assert.deepEqual(world.countries, [{ country: "PT", awake: 1, today_turns: 3 }, { country: "JP", awake: 1, today_turns: 0 }]);
  assert.equal(world.buddies.find((x: any) => x.id === a.id).level, 12);

  assert.equal((await call("POST", "/v1/gestures", b.key, { to: a.id, kind: "boop" })).status, 201);
  const got = (await call("GET", "/v1/gestures", a.key)).body.gestures;
  assert.deepEqual(got.map((g: any) => [g.kind, g.from_country]), [["boop", "JP"]]);
  assert.deepEqual((await call("POST", "/v1/reports", b.key, { buddy: a.id })).body, { ok: true, hidden: false });
  assert.deepEqual((await call("GET", "/api/cron/expire", CRON)).body, { ok: true, buddies: 0, days: 0, gestures: 0 });
  assert.equal((await call("DELETE", "/v1/buddies/me", a.key)).status, 200);
  assert.equal((await call("GET", "/v1/world")).body.total, 1);
});
