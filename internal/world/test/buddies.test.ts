// Joining, sending state and leaving (plan/world.md §2.4, §2.5): the keys,
// seq against double counts, and the limits the server holds.

import assert from "node:assert/strict";
import { test } from "node:test";
import { createHmac } from "node:crypto";
import { ipHash } from "../src/auth.js";
import { ADDED_PER_MINUTE, JOINS_PER_IP_PER_HOUR, SEND_EVERY_MS, XP_PER_DAY } from "../src/limits.js";
import { UTC_OFFSET_MAX, UTC_OFFSET_MIN } from "../src/regions.js";
import { IP_SALT, state, world } from "./helpers.js";

const w = world();

async function today(id: string) {
  const [row] = await w.db.query<Record<string, number>>(
    "select xp, turns, tests_passed, ships, lines_changed from buddy_days where buddy = $1",
    [id],
  );
  return row;
}

test("joining gives an id and a key, and the server keeps only the key's hash", async () => {
  const b = await w.join("Mochi", 330);
  assert.match(b.id, /^[0-9a-f-]{36}$/);
  assert.match(b.key, /^[A-Za-z0-9_-]{43}$/, "32 random bytes, base64url");
  assert.equal(b.name, "Mochi");
  assert.equal(b.name_ok, true);
  const [row] = await w.db.query<{ hash: string; utc_offset: number }>(
    "select encode(key_hash, 'hex') as hash, utc_offset from buddies where id = $1",
    [b.id],
  );
  assert.equal(row.hash.length, 64, "a sha256");
  assert.equal(row.utc_offset, 330);
  const anywhere = await w.db.query("select 1 from buddies where name = $1 or encode(key_hash, 'escape') like $2", [b.key, `%${b.key}%`]);
  assert.equal(anywhere.length, 0, "the key itself is stored nowhere");
});

test("a refused name is kept but shown as a buddy, and the offset may be left out", async () => {
  const b = await w.join("boop.com", null);
  assert.equal(b.name, "a buddy");
  assert.equal(b.name_ok, false);
  assert.equal(b.name_reason, "link");
  const [row] = await w.db.query<{ name: string; utc_offset: number | null }>(
    "select name, utc_offset from buddies where id = $1",
    [b.id],
  );
  assert.deepEqual(row, { name: "boop.com", utc_offset: null });
});

test(`utc_offset: minutes from ${UTC_OFFSET_MIN} to ${UTC_OFFSET_MAX}, in quarter hours`, async () => {
  for (const ok of [UTC_OFFSET_MIN, -480, 0, 60, 330, 345, 765, UTC_OFFSET_MAX]) {
    const r = await w.json("POST", "/v1/buddies", { body: { name: "Mochi", utc_offset: ok }, ip: `192.0.2.${ok & 255}` });
    assert.equal(r.status, 201, `${ok}`);
  }
  for (const bad of [UTC_OFFSET_MIN - 15, UTC_OFFSET_MAX + 15, 61, 1.5, "60", "Europe/Lisbon", true]) {
    const r = await w.json("POST", "/v1/buddies", { body: { name: "Mochi", utc_offset: bad } });
    assert.equal(r.status, 400, `join with ${JSON.stringify(bad)}`);
  }
  const b = await w.join("Mochi", 0);
  assert.equal((await w.send(b, state({ seq: 1, utc_offset: 900 }))).status, 400);
  assert.equal((await w.send(b, state({ seq: 1, country: "PT" }))).status, 400, "no country any more");
  assert.equal((await w.send(b, state({ seq: 1, tz: "Europe/Lisbon" }))).status, 400, "no time zone any more");
  const offsetOf = async () => (await w.db.query<{ o: number | null }>("select utc_offset as o from buddies where id = $1", [b.id]))[0].o;
  assert.equal((await w.send(b, state({ seq: 1, utc_offset: -480 }))).status, 200);
  assert.equal(await offsetOf(), -480);
  await w.rewind(b);
  await w.send(b, state({ seq: 2 }));
  assert.equal(await offsetOf(), -480, "left out: kept");
  await w.rewind(b);
  await w.send(b, state({ seq: 3, utc_offset: null }));
  assert.equal(await offsetOf(), null, "null: cleared");
});

test("joining needs a JSON object", async () => {
  const res = await w.app.request("/v1/buddies", { method: "POST", body: "not json" });
  assert.equal(res.status, 400);
});

test("a buddy's routes need its key", async () => {
  const b = await w.join();
  for (const [method, path] of [["PUT", "/v1/buddies/me"], ["DELETE", "/v1/buddies/me"], ["GET", "/v1/gestures"], ["POST", "/v1/gestures"], ["POST", "/v1/reports"]]) {
    assert.equal((await w.call(method, path, { body: {} })).status, 401, `${method} ${path} with no key`);
    assert.equal((await w.call(method, path, { key: "wrong", body: {} })).status, 401, `${method} ${path} with a wrong key`);
  }
  assert.equal((await w.send(b, state())).status, 200);
});

test("a send updates the buddy and adds its counts to today", async () => {
  const b = await w.join();
  const { status, body } = await w.send(b, state({
    name: "Mochi", level: 12, stage: "buddy", utc_offset: 60, activity: "testing",
    xp_today: 82, added: { turns: 3, tests_passed: 2, ships: 0, lines_changed: 140 },
  }));
  assert.equal(status, 200);
  assert.deepEqual(body.counted, { xp: 82, turns: 3, tests_passed: 2, ships: 0, lines_changed: 140 });
  assert.deepEqual(body.clamped, []);
  assert.equal(body.name, "Mochi");
  assert.equal(body.goal_added, null, "no goal yet");
  const [row] = await w.db.query("select level, stage, activity, last_seq::int as seq from buddies where id = $1", [b.id]);
  assert.deepEqual(row, { level: 12, stage: "buddy", activity: "testing", seq: 1 });
  assert.deepEqual(await today(b.id), { xp: 82, turns: 3, tests_passed: 2, ships: 0, lines_changed: 140 });
});

test("an unknown key or a bad value is refused", async () => {
  const b = await w.join();
  const cases: Record<string, unknown>[] = [
    state({ email: "me@example.com" }),
    state({ added: { turns: 1, prompts: 4 } }),
    state({ seq: 0 }),
    state({ seq: "1" }),
    state({ activity: "dancing" }),
    state({ stage: "giant" }),
    state({ day: "08/11/2026" }),
    state({ added: { turns: -1 } }),
    state({ level: 1.5 }),
  ];
  for (const s of cases) assert.equal((await w.send(b, s)).status, 400, JSON.stringify(s));
});

test("seq: a resend isn't counted twice", async () => {
  const b = await w.join();
  const first = state({ seq: 7, xp_today: 10, added: { turns: 2 } });
  assert.equal((await w.send(b, first)).status, 200);
  await w.rewind(b);
  const again = await w.send(b, first);
  assert.equal(again.status, 200);
  assert.equal(again.body.duplicate, true);
  const older = await w.send(b, state({ seq: 6, added: { turns: 5 } }));
  assert.equal(older.body.duplicate, true);
  assert.equal((await today(b.id)).turns, 2);
  assert.equal((await w.send(b, state({ seq: 8, xp_today: 10, added: { turns: 1 } }))).body.counted.turns, 1);
  assert.equal((await today(b.id)).turns, 3);
});

test(`a buddy sends at most once every ${SEND_EVERY_MS / 1000} s`, async () => {
  const b = await w.join();
  assert.equal((await w.send(b, state({ seq: 1 }))).status, 200);
  const res = await w.call("PUT", "/v1/buddies/me", { key: b.key, body: state({ seq: 2, added: { turns: 1 } }) });
  assert.equal(res.status, 429);
  const retry = Number(res.headers.get("retry-after"));
  assert.ok(retry > 0 && retry <= SEND_EVERY_MS / 1000, `Retry-After ${retry}`);
  assert.equal((await today(b.id)), undefined, "nothing counted");
  await w.rewind(b, SEND_EVERY_MS / 1000 - 1);
  assert.equal((await w.send(b, state({ seq: 2 }))).status, 429, "a second short is too soon");
  await w.rewind(b, 2);
  assert.equal((await w.send(b, state({ seq: 2, added: { turns: 1 } }))).status, 200, "a second past is fine");
});

test(`XP counts at most ${XP_PER_DAY} a day`, async () => {
  const b = await w.join();
  let r = await w.send(b, state({ seq: 1, day: "2026-11-08", xp_today: 82 }));
  assert.equal(r.body.counted.xp, 82);
  await w.rewind(b);
  r = await w.send(b, state({ seq: 2, day: "2026-11-08", xp_today: 82 }));
  assert.equal(r.body.counted.xp, 0, "the same XP again adds nothing");
  await w.rewind(b);
  r = await w.send(b, state({ seq: 3, day: "2026-11-08", xp_today: 150 }));
  assert.equal(r.body.counted.xp, 18, "past the ring, clamped");
  assert.deepEqual(r.body.clamped, ["xp_today"]);
  assert.equal((await today(b.id)).xp, XP_PER_DAY);
  await w.rewind(b);
  r = await w.send(b, state({ seq: 4, day: "2026-11-09", xp_today: 40 }));
  assert.equal(r.body.counted.xp, 0, "a new Mac day in the same UTC day: the UTC day is full");
  assert.equal((await today(b.id)).xp, XP_PER_DAY);
});

test("added is clamped to what's plausible since the last send", async () => {
  const b = await w.join();
  let r = await w.send(b, state({ seq: 1, added: { turns: 1000, tests_passed: 50, ships: 99, lines_changed: 5_000_000 } }));
  assert.deepEqual(r.body.counted, { xp: 0, turns: ADDED_PER_MINUTE.turns, tests_passed: 50, ships: ADDED_PER_MINUTE.ships, lines_changed: ADDED_PER_MINUTE.lines_changed });
  assert.deepEqual(r.body.clamped, ["turns", "ships", "lines_changed"]);
  await w.rewind(b, 5 * 60);
  r = await w.send(b, state({ seq: 2, added: { turns: 1000 } }));
  assert.equal(r.body.counted.turns, 5 * ADDED_PER_MINUTE.turns, "five minutes since the last send");
  await w.rewind(b, 24 * 3600);
  r = await w.send(b, state({ seq: 3, added: { turns: 100_000 } }));
  assert.equal(r.body.counted.turns, 60 * ADDED_PER_MINUTE.turns, "an hour at most");
});

test("a new name is checked again, and its reports start over", async () => {
  const b = await w.join("Mochi");
  await w.db.query("update buddies set reports = 3 where id = $1", [b.id]);
  let r = await w.send(b, state({ seq: 1, name: "Mochi" }));
  assert.equal(r.body.name, "a buddy");
  assert.equal(r.body.name_hidden, true);
  await w.rewind(b);
  r = await w.send(b, state({ seq: 2, name: "fuck" }));
  assert.deepEqual([r.body.name, r.body.name_ok, r.body.name_reason, r.body.name_hidden], ["a buddy", false, "word", false]);
  await w.rewind(b);
  r = await w.send(b, state({ seq: 3, name: "Bean" }));
  assert.deepEqual([r.body.name, r.body.name_ok, r.body.name_hidden], ["Bean", true, false]);
});

test("leaving deletes the buddy, its days, its reports and its gestures both ways", async () => {
  const a = await w.join("Ann");
  const b = await w.join("Bob");
  await w.send(a, state({ added: { turns: 1 } }));
  await w.json("POST", "/v1/gestures", { key: a.key, body: { to: b.id, kind: "boop" } });
  await w.json("POST", "/v1/gestures", { key: b.key, body: { to: a.id, kind: "wave" } });
  await w.json("POST", "/v1/reports", { key: a.key, body: { buddy: b.id } });
  await w.json("POST", "/v1/reports", { key: b.key, body: { buddy: a.id } });
  const { status } = await w.json("DELETE", "/v1/buddies/me", { key: a.key });
  assert.equal(status, 200);
  for (const [table, where] of [["buddies", "id = $1"], ["buddy_days", "buddy = $1"], ["gestures", "to_buddy = $1 or from_buddy = $1 or from_buddy is null"], ["name_reports", "buddy = $1 or reporter = $1"]]) {
    assert.equal((await w.db.query(`select 1 from ${table} where ${where}`, [a.id])).length, 0, table);
  }
  assert.equal((await w.send(a, state({ seq: 2 }))).status, 401, "the key no longer works");
  assert.equal((await w.db.query("select 1 from buddies where id = $1", [b.id])).length, 1, "the other buddy stays");
});

test("a key is never logged", async () => {
  const lines: string[] = [];
  const saved = { log: console.log, warn: console.warn, error: console.error };
  for (const k of ["log", "warn", "error"] as const) console[k] = (...args: unknown[]) => void lines.push(args.join(" "));
  try {
    const b = await w.join();
    await w.send(b, state({ seq: 1, xp_today: 500, added: { turns: 9999 } }));
    await w.send(b, state({ seq: 2 }));
    await w.send(b, state({ seq: 3, bogus: 1 }));
    await w.json("DELETE", "/v1/buddies/me", { key: b.key });
    assert.ok(lines.length > 0, "the clamp was logged");
    assert.ok(lines.every((l) => !l.includes(b.key)), lines.join("\n"));
  } finally {
    Object.assign(console, saved);
  }
});

test(`at most ${JOINS_PER_IP_PER_HOUR} new buddies from one address in an hour, kept only as a salted hash`, async () => {
  const join = (ip: string) => w.call("POST", "/v1/buddies", { body: { name: "Mochi", utc_offset: 0 }, ip });
  for (let i = 0; i < JOINS_PER_IP_PER_HOUR; i++) assert.equal((await join("203.0.113.7")).status, 201, `join ${i + 1}`);
  const refused = await join("203.0.113.7, 10.0.0.1");
  assert.equal(refused.status, 429, "the first address in x-forwarded-for is the caller's");
  const retry = Number(refused.headers.get("retry-after"));
  assert.ok(retry > 3500 && retry <= 3600, `Retry-After ${retry}`);
  assert.equal((await w.db.query("select 1 from buddies")).length, JOINS_PER_IP_PER_HOUR, "no buddy made");
  assert.equal((await join("198.51.100.2")).status, 201, "another address");

  // The table holds the address's HMAC with the salt, never the address.
  const rows = await w.db.query<{ h: string }>("select encode(ip_hash, 'hex') as h from joins");
  assert.equal(rows.length, JOINS_PER_IP_PER_HOUR + 1);
  const salted = createHmac("sha256", IP_SALT).update("203.0.113.7").digest("hex");
  assert.equal(rows.filter((r) => r.h === salted).length, JOINS_PER_IP_PER_HOUR);
  assert.ok(rows.every((r) => !Buffer.from(r.h, "hex").toString("latin1").includes("203.0.113")), "no address in plain text");
  assert.notEqual(ipHash("203.0.113.7", undefined), salted, "with IP_SALT unset, a random salt");
  assert.equal(ipHash("203.0.113.7", undefined), ipHash("203.0.113.7", ""), "the same one each time");

  // An hour on, the address may join again, and the old hashes go.
  await w.db.query("update joins set at = at - interval '1 hour'");
  assert.equal((await join("203.0.113.7")).status, 201, "an hour later");
  assert.equal((await w.db.query("select 1 from joins")).length, 1, "only this hour's hashes are kept");
});

test("a refused join doesn't count against the address", async () => {
  for (let i = 0; i < JOINS_PER_IP_PER_HOUR + 2; i++) {
    const r = await w.call("POST", "/v1/buddies", { body: { name: "Mochi", utc_offset: 1000 }, ip: "203.0.113.9" });
    assert.equal(r.status, 400);
  }
  assert.equal((await w.call("POST", "/v1/buddies", { body: { name: "Mochi" }, ip: "203.0.113.9" })).status, 201);
});
