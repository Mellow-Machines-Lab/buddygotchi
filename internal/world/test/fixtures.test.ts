// The wire format's examples in fixtures/, which the Mac's tests decode too,
// so the two sides can't drift: the state the server takes, and the world's
// shape, key for key and type for type, against a real snapshot.

import assert from "node:assert/strict";
import { test } from "node:test";
import { GESTURES, STATE_KEYS } from "../src/app.js";
import { REGIONS, validOffset } from "../src/regions.js";
import { ACTIVITIES, COUNTS, METRICS } from "../src/world.js";
import { ADMIN, fixture, world } from "./helpers.js";

const w = world();

test("buddy-state.json is every key a buddy may send, and the server takes it", async () => {
  const sent = fixture("buddy-state.json");
  assert.deepEqual(Object.keys(sent).sort(), [...STATE_KEYS].sort());
  assert.deepEqual(Object.keys(sent.added as object).sort(), [...COUNTS].sort());
  assert.ok(ACTIVITIES.includes(sent.activity as never));
  const b = await w.join();
  const r = await w.send(b, sent);
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.counted, { xp: 82, turns: 3, tests_passed: 2, ships: 0, lines_changed: 140 });
});

test("buddy-reply.json has the shape of a real send's reply", async () => {
  const example = fixture<any>("buddy-reply.json");
  const a = await w.join("Mochi", 60);
  const b = await w.join("Bean", 540);
  await w.json("PUT", "/v1/admin/goal", { key: ADMIN, body: { title: "Two tests", metric: "tests_passed", target: 2, ends: "2099-12-31", reward_tag: "worldparty" } });
  await w.json("POST", "/v1/gestures", { key: b.key, body: { to: a.id, kind: "boop" } });
  const real = (await w.send(a, fixture("buddy-state.json"))).body;
  assert.deepEqual(shape(real), shape(example));
  assert.deepEqual(real.counted, example.counted);
  assert.equal(real.gestures[0].from_region, example.gestures[0].from_region);
  assert.ok(GESTURES.includes(example.gestures[0].kind));
});

/** A value's shape: its keys and their types, arrays by their first item. */
function shape(v: unknown): unknown {
  if (Array.isArray(v)) return [v.length ? shape(v[0]) : "empty"];
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, shape(x)]).sort());
  return typeof v;
}

test("world.json has the shape of a real snapshot", async () => {
  const example = fixture<any>("world.json");
  const a = await w.join("Bean", 540);
  await w.send(a, { seq: 1, activity: "coding", level: 7, added: { tests_passed: 4 } });
  await w.json("POST", "/v1/buddies", { body: { name: "boop.com" } });
  await w.json("PUT", "/v1/admin/goal", { key: ADMIN, body: { title: "Four tests", metric: "tests_passed", target: 4, ends: "2099-12-31", reward_tag: "worldparty" } });
  const real = (await w.json("GET", "/v1/world")).body;

  // A buddy with no offset has a null there.
  const nullable = example.buddies[1];
  assert.equal(nullable.utc_offset, null);
  const realNoOffset = real.buddies.find((b: any) => b.utc_offset === null);
  assert.ok(realNoOffset);
  assert.deepEqual(shape(realNoOffset), shape(nullable));

  example.buddies = example.buddies.slice(0, 1);
  real.buddies = real.buddies.filter((b: any) => b.utc_offset !== null);
  assert.deepEqual(shape(real), shape(example));

  assert.deepEqual(Object.keys(example.doing).sort(), [...ACTIVITIES].sort());
  assert.deepEqual(Object.keys(example.today).sort(), [...COUNTS].sort());
  assert.ok(METRICS.includes(example.goal.metric));
  assert.deepEqual(example.regions.map((r: any) => r.region), REGIONS.map((r) => r.region), "every region, in order");
  assert.ok(validOffset(example.buddies[0].utc_offset));
  assert.ok(ACTIVITIES.includes(example.buddies[0].activity));
  assert.equal(example.awake, example.total - example.doing.asleep);
  assert.ok(GESTURES.length === 4);
});
