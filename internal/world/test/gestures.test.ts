// Gestures (boop, wave, heart, cheer), delivered once, and name reports,
// which hide a name at three.

import assert from "node:assert/strict";
import { test } from "node:test";
import { GESTURES_SENT_PER_HOUR, GESTURES_TO_ONE_PER_HOUR, REPORTS_TO_HIDE } from "../src/limits.js";
import { world } from "./helpers.js";

const w = world();

test("a gesture is delivered once, with where it came from", async () => {
  const lisbon = await w.join("Ann", 0);
  const tokyo = await w.join("Bob", 540);
  for (const kind of ["boop", "heart"]) {
    const r = await w.json("POST", "/v1/gestures", { key: lisbon.key, body: { to: tokyo.id, kind } });
    assert.equal(r.status, 201);
  }
  const first = await w.json("GET", "/v1/gestures", { key: tokyo.key });
  assert.equal(first.status, 200);
  assert.deepEqual(first.body.gestures.map((g: any) => [g.kind, g.from_region]), [["boop", "europe_africa"], ["heart", "europe_africa"]]);
  assert.match(first.body.gestures[0].at, /Z$/);
  assert.deepEqual((await w.json("GET", "/v1/gestures", { key: tokyo.key })).body.gestures, [], "not again");
  assert.deepEqual((await w.json("GET", "/v1/gestures", { key: lisbon.key })).body.gestures, [], "only the receiver's");
});

test("a gesture needs a real buddy, not itself, and a known kind", async () => {
  const a = await w.join("Ann");
  const b = await w.join("Bob");
  assert.equal((await w.json("POST", "/v1/gestures", { key: a.key, body: { to: a.id, kind: "boop" } })).status, 400);
  assert.equal((await w.json("POST", "/v1/gestures", { key: a.key, body: { to: b.id, kind: "slap" } })).status, 400);
  assert.equal((await w.json("POST", "/v1/gestures", { key: a.key, body: { to: "nobody", kind: "boop" } })).status, 400);
  assert.equal((await w.json("POST", "/v1/gestures", { key: a.key, body: { to: crypto.randomUUID(), kind: "boop" } })).status, 404);
  for (const kind of ["boop", "wave", "heart"]) {
    assert.equal((await w.json("POST", "/v1/gestures", { key: a.key, body: { to: b.id, kind } })).status, 201, kind);
  }
});

test(`a buddy sends at most ${GESTURES_TO_ONE_PER_HOUR} an hour to one buddy, and ${GESTURES_SENT_PER_HOUR} in all`, async () => {
  const from = await w.join("Ann");
  const to = await w.join("Bob");
  for (let i = 0; i < GESTURES_TO_ONE_PER_HOUR; i++) {
    assert.equal((await w.json("POST", "/v1/gestures", { key: from.key, body: { to: to.id, kind: "cheer" } })).status, 201);
  }
  assert.equal((await w.json("POST", "/v1/gestures", { key: from.key, body: { to: to.id, kind: "cheer" } })).status, 429);
  await w.db.query("update gestures set created_at = now() - interval '61 minutes'");
  assert.equal((await w.json("POST", "/v1/gestures", { key: from.key, body: { to: to.id, kind: "cheer" } })).status, 201, "an hour later");

  await w.db.query("delete from gestures");
  const others = await Promise.all(Array.from({ length: GESTURES_SENT_PER_HOUR + 1 }, (_, i) => w.join(`B${i}`)));
  for (const [i, b] of others.entries()) {
    const status = (await w.json("POST", "/v1/gestures", { key: from.key, body: { to: b.id, kind: "wave" } })).status;
    assert.equal(status, i < GESTURES_SENT_PER_HOUR ? 201 : 429, `gesture ${i + 1}`);
  }
});

test(`${REPORTS_TO_HIDE} reports hide a name, and a buddy reports once`, async () => {
  const target = await w.join("Mochi");
  const reporters = await Promise.all([w.join("A"), w.join("B"), w.join("C")]);
  const report = (key: string) => w.json("POST", "/v1/reports", { key, body: { buddy: target.id } });
  assert.deepEqual((await report(reporters[0].key)).body, { ok: true, hidden: false });
  assert.deepEqual((await report(reporters[0].key)).body, { ok: true, hidden: false }, "the same reporter again");
  assert.deepEqual((await report(reporters[1].key)).body, { ok: true, hidden: false });
  assert.deepEqual((await report(reporters[2].key)).body, { ok: true, hidden: true });
  const world = (await w.json("GET", "/v1/world")).body;
  assert.equal(world.buddies.find((b: any) => b.id === target.id).name, "a buddy");
  assert.equal((await w.json("POST", "/v1/reports", { key: target.key, body: { buddy: target.id } })).status, 400, "not itself");
  assert.equal((await w.json("POST", "/v1/reports", { key: target.key, body: { buddy: crypto.randomUUID() } })).status, 404);
});
