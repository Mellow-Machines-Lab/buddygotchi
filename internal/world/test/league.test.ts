// The weekly league (plan/xp-league.md §6): the week's XP, its order, the
// week closing once with its medals, a buddy's profile, and seeds.

import assert from "node:assert/strict";
import { test } from "node:test";
import { XP_PER_DAY } from "../src/limits.js";
import { addSeeds, closeWeek, dayOf, removeSeeds, standings, weekOf } from "../src/league.js";
import { SEED_NAMES, seedDay, seedXp } from "../src/seeds.js";
import { fixture, state, world } from "./helpers.js";

const w = world();

/** A buddy's XP on UTC day `day`, written as the server would. */
async function earned(id: string, day: string, xp: number) {
  await w.db.query(
    `insert into buddy_days (buddy, day, xp) values ($1, $2::date, $3)
     on conflict (buddy, day) do update set xp = excluded.xp`,
    [id, day, xp],
  );
}

const MONDAY = "2026-11-23";
const NOW = Date.parse("2026-11-25T12:00:00Z"); // a Wednesday

test("a week runs Monday to Sunday, UTC", () => {
  assert.equal(weekOf("2026-11-23"), MONDAY);
  assert.equal(weekOf("2026-11-29"), MONDAY);
  assert.equal(weekOf("2026-11-30"), "2026-11-30");
  assert.equal(weekOf("2026-11-22"), "2026-11-16");
});

test("the league ranks by the week's XP only, a tie to the first joined", async () => {
  const a = await w.join("Ann", 0);
  const b = await w.join("Bob", 0);
  const c = await w.join("Cat", 0);
  await earned(a.id, "2026-11-23", 100);
  await earned(a.id, "2026-11-22", 300); // last week's: not counted
  await earned(b.id, "2026-11-24", 60);
  await earned(b.id, "2026-11-25", 40);
  await earned(c.id, "2026-11-25", 150);
  const order = (await standings(w.db, MONDAY, NOW)).map((s) => [s.name, s.xp_week]);
  assert.deepEqual(order, [["Cat", 150], ["Ann", 100], ["Bob", 100]], "Ann joined before Bob");
});

test("GET /v1/league: the rows, and with a key, my place, who's ahead and behind, the percent", async () => {
  const a = await w.join("Ann", 0);
  const b = await w.join("Bob", 0);
  const c = await w.join("Cat", 0);
  await earned(a.id, dayOf(Date.now()), 50);
  await earned(b.id, dayOf(Date.now()), 80);
  await earned(c.id, dayOf(Date.now()), 20);
  const anyone = (await w.json("GET", "/v1/league")).body;
  assert.deepEqual(anyone.rows.map((r: any) => r.name), ["Bob", "Ann", "Cat"]);
  assert.equal(anyone.me, undefined);
  const mine = (await w.json("GET", "/v1/league", { key: a.key })).body;
  assert.deepEqual(mine.me, {
    place: 2, xp_week: 50, top_percent: 67,
    ahead: { id: b.id, name: "Bob", by: 30 }, behind: { id: c.id, name: "Cat", by: 30 },
  });
  const first = (await w.json("GET", "/v1/league", { key: b.key })).body.me;
  assert.equal(first.ahead, null, "none ahead of the first");
  assert.equal((await w.json("GET", "/v1/league", { key: c.key })).body.me.behind, null, "none behind the last");
  const fresh = await w.join("Dot", 0);
  assert.equal((await w.json("GET", "/v1/league", { key: fresh.key })).body.me.top_percent, null, "no XP, no percent");
});

test("a week closes once: places for those with XP, medals for the top three", async () => {
  const names = ["Ann", "Bob", "Cat", "Dot", "Eve"];
  const bs = [];
  for (const n of names) bs.push(await w.join(n, 0));
  for (const [i, b] of bs.entries()) if (i < 4) await earned(b.id, "2026-11-18", 400 - i * 50);
  const monday = Date.parse("2026-11-23T00:30:00Z");
  assert.equal(await closeWeek(w.db, monday), true);
  assert.equal(await closeWeek(w.db, monday + 60_000), false, "once");
  const results = await w.db.query<{ name: string; place: number; xp: number }>(
    "select b.name, r.place, r.xp from league_results r join buddies b on b.id = r.buddy order by r.place",
  );
  assert.deepEqual(results.map((r) => [r.name, r.place, r.xp]), [["Ann", 1, 400], ["Bob", 2, 350], ["Cat", 3, 300], ["Dot", 4, 250]]);
  const medals = await w.db.query<{ name: string; place: number }>(
    "select b.name, m.place from medals m join buddies b on b.id = m.buddy order by m.place",
  );
  assert.deepEqual(medals.map((m) => [m.name, m.place]), [["Ann", 1], ["Bob", 2], ["Cat", 3]]);
});

test("a send's reply carries last week's place, for Monday's moment", async () => {
  const a = await w.join("Ann", 0);
  const lastMonday = weekOf(dayOf(Date.now() - 7 * 86_400_000));
  await earned(a.id, lastMonday, 120);
  const r = await w.send(a, state());
  assert.deepEqual(r.body.last_week, { week: lastMonday, place: 1, xp: 120, of: 1 });
  const example = fixture<any>("buddy-reply.json");
  assert.deepEqual(Object.keys(r.body.last_week).sort(), Object.keys(example.last_week).sort());
});

test(`a day counts at most ${XP_PER_DAY} XP, past the ring of 100`, async () => {
  const a = await w.join("Ann", 0);
  let r = await w.send(a, state({ xp_today: 240 }));
  assert.equal(r.body.counted.xp, 240);
  await w.rewind(a);
  r = await w.send(a, state({ seq: 2, xp_today: 400 }));
  assert.equal(r.body.counted.xp, XP_PER_DAY - 240);
});

test("a buddy sends its days in a row and its colour; a bad one is refused", async () => {
  const a = await w.join("Ann", 0);
  assert.equal((await w.send(a, state({ days_in_a_row: 12, color: 3 }))).status, 200);
  const p = (await w.json("GET", `/v1/buddies/${a.id}`)).body;
  assert.equal(p.days_in_a_row, 12);
  assert.equal(p.color, 3);
  await w.rewind(a);
  assert.equal((await w.send(a, state({ seq: 2, color: 8 }))).status, 400);
});

test("GET /v1/buddies/:id: the public profile, and between two buddies with a key", async () => {
  const a = await w.join("Ann", 540);
  const b = await w.join("Bob", 0);
  await earned(a.id, dayOf(Date.now()), 90);
  await w.db.query("insert into medals (buddy, week, place) values ($1, '2026-11-09', 1), ($1, '2026-11-02', 1)", [a.id]);
  await w.db.query(
    "insert into league_results (week, buddy, place, xp) values ('2026-11-09', $1, 2, 300), ('2026-11-09', $2, 1, 400)",
    [a.id, b.id],
  );
  await w.json("POST", "/v1/gestures", { key: a.key, body: { to: b.id, kind: "wave" } });
  const p = (await w.json("GET", `/v1/buddies/${a.id}`, { key: b.key })).body;
  assert.equal(p.name, "Ann");
  assert.equal(p.region, "asia_oceania");
  assert.deepEqual(p.medals, { gold: 2, silver: 0, bronze: 0 });
  assert.deepEqual(p.week, { xp: 90, place: 1 });
  assert.equal(p.best_week, 300);
  assert.equal(p.between.from_them.kind, "wave");
  assert.equal(p.between.from_you, null);
  assert.equal(p.between.you_beat_them, "2026-11-09", "Bob beat Ann that week");
  const anyone = (await w.json("GET", `/v1/buddies/${a.id}`)).body;
  assert.equal(anyone.between, undefined);
  const example = fixture<any>("buddy.json");
  assert.deepEqual(Object.keys(p).sort(), Object.keys(example).sort());
  assert.equal((await w.json("GET", "/v1/buddies/0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f")).status, 404);
});

test("a buddy that leaves leaves no row", async () => {
  const a = await w.join("Ann", 0);
  await earned(a.id, dayOf(Date.now()), 50);
  await w.json("DELETE", "/v1/buddies/me", { key: a.key });
  assert.equal((await w.json("GET", "/v1/league")).body.rows.length, 0);
});

test("a seed's day is the same for one time and never goes down within it", () => {
  const id = "3f8c2a10-6b1e-4d6f-9a51-2c7e8b0d4f11";
  let last = 0;
  for (let h = 0; h <= 24; h++) {
    const t = Date.parse("2026-11-24T00:00:00Z") + h * 3_600_000;
    const d = seedDay(id, 500, 0, "2026-11-24", t);
    assert.deepEqual(seedDay(id, 500, 0, "2026-11-24", t), d);
    assert.ok(d.xp >= last);
    last = d.xp;
  }
});

test("a seed's week stays near its strength", () => {
  for (let i = 0; i < 40; i++) {
    const id = `seed-${i}`;
    const xp = seedXp(id, 400, 0, "2026-11-23", "2026-11-29", Date.parse("2026-12-01T00:00:00Z"));
    assert.ok(xp >= 0 && xp <= 400 * 1.6 + 1, `${xp}`);
  }
});

test("seeds join the league and the world, take gestures and drop them, and go in one call", async () => {
  const a = await w.join("Ann", 0);
  const ids = await addSeeds(w.db, 5, SEED_NAMES);
  const league = (await w.json("GET", "/v1/league")).body;
  assert.equal(league.total, 6);
  assert.equal((await w.json("GET", "/v1/world")).body.total, 6);
  const sent = await w.json("POST", "/v1/gestures", { key: a.key, body: { to: ids[0], kind: "boop" } });
  assert.equal(sent.status, 201);
  assert.equal((await w.db.query("select 1 from gestures")).length, 0, "dropped");
  assert.equal(await removeSeeds(w.db), 5);
  assert.equal((await w.json("GET", "/v1/league")).body.total, 1);
});

test("league.json has the shape of a real league", async () => {
  const example = fixture<any>("league.json");
  const a = await w.join("Ann", 0);
  const b = await w.join("Bob", 0);
  const c = await w.join("Cat", 0);
  for (const [b2, xp] of [[a, 50], [b, 80], [c, 20]] as const) await earned(b2.id, dayOf(Date.now()), xp);
  const lastMonday = weekOf(dayOf(Date.now() - 7 * 86_400_000));
  await earned(a.id, lastMonday, 10);
  const real = (await w.json("GET", "/v1/league", { key: a.key })).body;
  const keys = (o: any) => Object.keys(o).sort();
  assert.deepEqual(keys(real), keys(example));
  assert.deepEqual(keys(real.rows[0]), keys(example.rows[0]));
  assert.deepEqual(keys(real.me), keys(example.me));
  assert.deepEqual(keys(real.me.ahead), keys(example.me.ahead));
  assert.deepEqual(keys(real.last_week), keys(example.last_week));
});

test("a gesture names its sender, so it can be answered; a sender that left is nobody", async () => {
  const a = await w.join("Ann", 0);
  const b = await w.join("Bob", 0);
  await w.json("POST", "/v1/gestures", { key: a.key, body: { to: b.id, kind: "wave" } });
  const got = (await w.json("GET", "/v1/gestures", { key: b.key })).body.gestures;
  assert.deepEqual(got[0].from, { id: a.id, name: "Ann" });
  await w.json("POST", "/v1/gestures", { key: a.key, body: { to: b.id, kind: "heart" } });
  await w.db.query("update gestures set from_buddy = null");
  assert.equal((await w.json("GET", "/v1/gestures", { key: b.key })).body.gestures[0].from, null);
});
