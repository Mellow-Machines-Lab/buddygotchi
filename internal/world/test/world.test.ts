// The snapshot (plan/world.md §2.6) and the goal: its progress, reached
// exactly once, and its reward in `rewards`.

import assert from "node:assert/strict";
import { test } from "node:test";
import { AWAKE_WITHIN_MS, SNAPSHOT_BUDDIES, SNAPSHOT_CACHE_SECONDS } from "../src/limits.js";
import { REGIONS, UTC_OFFSET_MAX, UTC_OFFSET_MIN, regionOf } from "../src/regions.js";
import { ADMIN, state, world } from "./helpers.js";

const w = world();
const utcToday = () => new Date().toISOString().slice(0, 10);
const addDays = (day: string, n: number) => new Date(Date.parse(`${day}T00:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10);

async function snapshot() {
  const res = await w.call("GET", "/v1/world");
  assert.equal(res.status, 200);
  return { res, body: (await res.json()) as any };
}

function setGoal(goal: Record<string, unknown>) {
  return w.json("PUT", "/v1/admin/goal", { key: ADMIN, body: goal });
}

test("an empty world", async () => {
  const { res, body } = await snapshot();
  assert.equal(res.headers.get("cache-control"), `public, max-age=0, s-maxage=${SNAPSHOT_CACHE_SECONDS}`);
  assert.equal(body.total, 0);
  assert.equal(body.awake, 0);
  assert.deepEqual(body.doing, { coding: 0, testing: 0, shipping: 0, waiting: 0, idle: 0, asleep: 0 });
  assert.deepEqual(body.today, { turns: 0, tests_passed: 0, ships: 0, lines_changed: 0 });
  assert.deepEqual([body.goal, body.rewards, body.buddies], [null, [], []]);
  assert.deepEqual(body.regions, REGIONS.map(({ region }) => ({ region, awake: 0, today_turns: 0 })), "every region, with zeros");
  assert.match(body.at, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
});

test("numbers, regions and the buddies, the awake first", async () => {
  const pt = await w.join("Mochi", 0);
  const br = await w.join("Bean", -180);
  const br2 = await w.join("Pip", -180);
  const gone = await w.join("Old", 540);
  await w.join("Nowhere", null);
  await w.send(pt, state({ activity: "testing", level: 12, stage: "buddy", added: { turns: 3, tests_passed: 2, lines_changed: 140 } }));
  await w.send(br, state({ activity: "coding", added: { turns: 5 } }));
  await w.send(br2, state({ activity: "asleep" }));
  await w.send(gone, state({ activity: "coding", added: { turns: 1 } }));
  // Not seen for longer than AWAKE_WITHIN_MS: asleep, whatever it said.
  await w.db.query("update buddies set seen_at = now() - make_interval(secs => $2) where id = $1", [gone.id, AWAKE_WITHIN_MS / 1000 + 1]);

  const { body } = await snapshot();
  assert.equal(body.total, 5);
  assert.equal(body.awake, 3);
  assert.deepEqual(body.doing, { coding: 1, testing: 1, shipping: 0, waiting: 0, idle: 1, asleep: 2 });
  assert.deepEqual(body.today, { turns: 9, tests_passed: 2, ships: 0, lines_changed: 140 });
  assert.deepEqual(body.year, body.today);
  assert.deepEqual(body.regions, [
    { region: "americas", awake: 1, today_turns: 5 },
    { region: "europe_africa", awake: 1, today_turns: 3 },
    { region: "asia_oceania", awake: 0, today_turns: 1 },
  ], "a buddy with no offset is in no region");
  assert.deepEqual(body.buddies.slice(0, 3).map((b: any) => b.activity).sort(), ["coding", "idle", "testing"], "the awake first");
  const mochi = body.buddies.find((b: any) => b.id === pt.id);
  assert.deepEqual(mochi, { id: pt.id, name: "Mochi", level: 12, stage: "buddy", utc_offset: 0, activity: "testing" });
  assert.equal(body.buddies.find((b: any) => b.id === gone.id).activity, "asleep");
});

test(`a buddy is awake for ${AWAKE_WITHIN_MS / 60_000} minutes after it was seen, then asleep`, async () => {
  assert.equal(AWAKE_WITHIN_MS, 15 * 60_000, "a heartbeat about every 10 minutes, and room for one late");
  const b = await w.join();
  await w.send(b, state({ activity: "coding" }));
  const seenAgo = (secs: number) => w.db.query("update buddies set seen_at = now() - make_interval(secs => $2) where id = $1", [b.id, secs]);
  await seenAgo(AWAKE_WITHIN_MS / 1000 - 5);
  let { body } = await snapshot();
  assert.deepEqual([body.awake, body.buddies[0].activity, body.regions[1].awake], [1, "coding", 1], "just under: awake");
  await seenAgo(AWAKE_WITHIN_MS / 1000 + 5);
  ({ body } = await snapshot());
  assert.deepEqual([body.awake, body.buddies[0].activity, body.regions[1].awake], [0, "asleep", 0], "just over: asleep");
});

test("the regions cover every offset, with no gap and no overlap", () => {
  for (let o = UTC_OFFSET_MIN; o <= UTC_OFFSET_MAX; o += 15) {
    const inside = REGIONS.filter((r) => o >= r.from && o <= r.to);
    assert.equal(inside.length, 1, `offset ${o}`);
  }
  const cases: [number, string][] = [
    [-600, "americas"], [-480, "americas"], [-180, "americas"], [-120, "americas"],
    [-60, "europe_africa"], [0, "europe_africa"], [60, "europe_africa"], [180, "europe_africa"],
    [210, "asia_oceania"], [330, "asia_oceania"], [540, "asia_oceania"], [840, "asia_oceania"],
  ];
  for (const [o, region] of cases) assert.equal(regionOf(o), region, `offset ${o}`);
  assert.equal(regionOf(null), null);
});

test("the year adds the days summed into totals_by_day", async () => {
  const b = await w.join();
  await w.send(b, state({ added: { turns: 2 } }));
  await w.db.query(`insert into totals_by_day (day, turns) values (date_trunc('year', now() at time zone 'utc')::date, 40), ('1999-01-01', 1000)`);
  const { body } = await snapshot();
  assert.equal(body.today.turns, 2);
  assert.equal(body.year.turns, 42, "this year's only");
});

test(`the snapshot's buddies are a sample of at most ${SNAPSHOT_BUDDIES}, and a hidden name shows as a buddy`, async () => {
  await w.db.query(
    `insert into buddies (id, key_hash, name, name_ok, activity, seen_at, created_at)
     select gen_random_uuid(), sha256(i::text::bytea), 'B' || i, true, 'idle', now() - interval '1 hour', now()
       from generate_series(1, $1) as i`,
    [SNAPSHOT_BUDDIES + 5],
  );
  const hidden = await w.join("Rude");
  await w.db.query("update buddies set reports = 3 where id = $1", [hidden.id]);
  const awake = await w.join("Fresh");
  await w.send(awake, state({ activity: "coding" }));
  const { body } = await snapshot();
  assert.equal(body.total, SNAPSHOT_BUDDIES + 7);
  assert.equal(body.buddies.length, SNAPSHOT_BUDDIES);
  assert.equal(body.buddies[0].id, awake.id, "the awake first, the latest seen first");
  assert.equal(body.buddies[1].id, hidden.id);
  assert.equal(body.buddies.find((b: any) => b.id === hidden.id)?.name, "a buddy");
});

test("the goal's progress, and your part of it", async () => {
  const a = await w.join("Ann");
  const b = await w.join("Bob");
  const r = await setGoal({ title: "Ten tests", metric: "tests_passed", target: 10, ends: addDays(utcToday(), 7), reward_tag: "worldparty" });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.goal, { title: "Ten tests", metric: "tests_passed", target: 10, progress: 0, starts: utcToday(), ends: addDays(utcToday(), 7), reached: false });
  await w.send(a, state({ added: { tests_passed: 3 } }));
  const sent = await w.send(b, state({ added: { tests_passed: 4 } }));
  assert.equal(sent.body.goal_added, 4, "you added 4");
  assert.deepEqual(sent.body.rewards, [], "none until it's reached");
  const { body } = await snapshot();
  assert.equal(body.goal.progress, 7);
  assert.equal(body.goal.reached, false);
  assert.deepEqual(body.rewards, []);
});

test("the goal is reached exactly once, and its reward is in rewards", async () => {
  const a = await w.join("Ann");
  const b = await w.join("Bob");
  await setGoal({ title: "Ten tests", metric: "tests_passed", target: 10, ends: addDays(utcToday(), 7), reward_tag: "worldparty", reward_days: 3 });
  await w.send(a, state({ added: { tests_passed: 6 } }));
  await w.send(b, state({ added: { tests_passed: 6 } }));
  const [first] = await w.db.query<{ at: string }>("select reached_at::text as at from goals");
  assert.ok(first.at, "reached");

  // More work, more snapshots: still the one reaching.
  await w.rewind(a);
  await w.send(a, state({ seq: 2, added: { tests_passed: 6 } }));
  await snapshot();
  const [again] = await w.db.query<{ at: string }>("select reached_at::text as at from goals");
  assert.equal(again.at, first.at);

  const { body } = await snapshot();
  assert.equal(body.goal.reached, true);
  assert.equal(body.goal.progress, 18);
  assert.deepEqual(body.rewards, [{ tag: "worldparty", until: addDays(utcToday(), 3) }]);
  await w.rewind(b);
  const sent = await w.send(b, state({ seq: 2 }));
  assert.deepEqual(sent.body.rewards, body.rewards, "a send's reply carries the rewards too");
});

test("a reward lasts its days, and a goal past its end isn't reached", async () => {
  await w.db.query(
    `insert into goals (title, metric, target, starts, ends, reward_tag, reward_days, reached_at) values
       ('Old', 'ships', 1, '2026-01-01', '2026-01-31', 'oldparty', 3, now() - interval '4 days'),
       ('Late', 'ships', 1, '2026-01-01', '2026-01-31', 'lateparty', 3, null)`,
  );
  const b = await w.join();
  await w.send(b, state({ added: { ships: 5 } }));
  const { body } = await snapshot();
  assert.deepEqual(body.rewards, [], "the old reward is over");
  assert.equal(body.goal, null, "the late goal ended unreached and isn't shown");
  const [late] = await w.db.query<{ reached: boolean }>("select reached_at is not null as reached from goals where title = 'Late'");
  assert.equal(late.reached, false);
});
