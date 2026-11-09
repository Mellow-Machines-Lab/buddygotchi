// The snapshot every Mac reads (GET /v1/world), and the goal: its progress,
// reaching it once, and the rewards every board wears after.
//
// The server's days are UTC. A buddy not seen for AWAKE_WITHIN_MS counts as
// asleep, whatever it last said, since its Mac has gone quiet.

import type { Db } from "./db.js";
import { AWAKE_WITHIN_MS, SNAPSHOT_BUDDIES } from "./limits.js";
import { shownName } from "./names.js";
import { REGIONS, regionSql, type Region } from "./regions.js";

export const ACTIVITIES = ["coding", "testing", "shipping", "waiting", "idle", "asleep"] as const;
export type Activity = (typeof ACTIVITIES)[number];
export const COUNTS = ["turns", "tests_passed", "ships", "lines_changed"] as const;
export type Count = (typeof COUNTS)[number];
export const METRICS = [...COUNTS, "xp"] as const;
export type Metric = (typeof METRICS)[number];

/** Today in UTC, in SQL. */
export const TODAY = "(now() at time zone 'utc')::date";
/** A buddy's activity as the world sees it; $1 is AWAKE_WITHIN_MS / 1000. */
const SEEN_ACTIVITY = "case when seen_at >= now() - make_interval(secs => $1) then activity else 'asleep' end";
const iso = (col: string) => `to_char(${col} at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')`;
const date = (col: string) => `to_char(${col}, 'YYYY-MM-DD')`;

export type Totals = Record<Count, number>;

export interface Goal {
  title: string;
  metric: Metric;
  target: number;
  progress: number;
  starts: string;
  ends: string;
  reached: boolean;
}

export interface Snapshot {
  at: string;
  awake: number;
  total: number;
  doing: Record<Activity, number>;
  today: Totals;
  year: Totals;
  regions: { region: Region; awake: number; today_turns: number }[];
  goal: Goal | null;
  rewards: { tag: string; until: string }[];
  buddies: {
    id: string;
    name: string;
    level: number;
    stage: string | null;
    utc_offset: number | null;
    activity: Activity;
  }[];
}

const sums = (cols: readonly string[]) => cols.map((c) => `coalesce(sum(${c}), 0)::float8 as ${c}`).join(", ");

async function totalsSince(db: Db, fromSql: string, toSql: string): Promise<Totals> {
  const where = `day >= ${fromSql} and day <= ${toSql}`;
  const [days] = await db.query<Totals>(`select ${sums(COUNTS)} from buddy_days where ${where}`);
  const [old] = await db.query<Totals>(`select ${sums(COUNTS)} from totals_by_day where ${where}`);
  return Object.fromEntries(COUNTS.map((c) => [c, days[c] + old[c]])) as Totals;
}

interface GoalRow {
  id: number;
  title: string;
  metric: Metric;
  target: number;
  starts: string;
  ends: string;
  reached: boolean;
  showing: boolean;
}

/** The current goal: the newest, while it runs or its reward does. */
async function currentGoal(db: Db): Promise<GoalRow | undefined> {
  const [row] = await db.query<GoalRow>(
    `select id, title, metric, target::float8 as target, ${date("starts")} as starts, ${date("ends")} as ends,
            reached_at is not null as reached,
            (ends >= ${TODAY} or (reached_at is not null
              and (reached_at at time zone 'utc')::date + reward_days > ${TODAY})) as showing
       from goals order by id desc limit 1`,
  );
  return row;
}

/** The goal's progress: its metric summed over its days, every buddy's. */
async function progress(db: Db, goal: Pick<GoalRow, "metric" | "starts" | "ends">, buddy?: string): Promise<number> {
  if (!METRICS.includes(goal.metric)) return 0;
  const params: unknown[] = [goal.starts, goal.ends];
  let where = "day >= $1::date and day <= $2::date";
  if (buddy) {
    params.push(buddy);
    where += " and buddy = $3";
  }
  const col = goal.metric;
  const [a] = await db.query<{ n: number }>(`select coalesce(sum(${col}), 0)::float8 as n from buddy_days where ${where}`, params);
  if (buddy) return a.n;
  const [b] = await db.query<{ n: number }>(
    `select coalesce(sum(${col}), 0)::float8 as n from totals_by_day where ${where}`,
    params.slice(0, 2),
  );
  return a.n + b.n;
}

/**
 * Checks the current goal, and marks it reached the first time its progress
 * meets the target before it ends. Returns the goal as the world shows it,
 * and whether this call was the one that reached it.
 */
export async function checkGoal(db: Db): Promise<{ goal: Goal | null; reachedNow: boolean }> {
  const row = await currentGoal(db);
  if (!row || !row.showing) return { goal: null, reachedNow: false };
  const done = await progress(db, row);
  let reached = row.reached;
  let reachedNow = false;
  if (!reached && done >= row.target) {
    const marked = await db.query(
      `update goals set reached_at = now() where id = $1 and reached_at is null and ends >= ${TODAY} returning id`,
      [row.id],
    );
    reachedNow = marked.length > 0;
    reached = reachedNow;
  }
  const { title, metric, target, starts, ends } = row;
  return { goal: { title, metric, target, progress: done, starts, ends, reached }, reachedNow };
}

/** What a buddy added to the current goal: "You added 340." */
export async function goalAdded(db: Db, buddy: string): Promise<number | null> {
  const row = await currentGoal(db);
  return row?.showing ? progress(db, row, buddy) : null;
}

export async function snapshot(db: Db): Promise<Snapshot> {
  const awakeSecs = AWAKE_WITHIN_MS / 1000;
  const [{ at }] = await db.query<{ at: string }>(`select ${iso("now()")} as at`);

  const doing = Object.fromEntries(ACTIVITIES.map((a) => [a, 0])) as Record<Activity, number>;
  const counted = await db.query<{ a: Activity; n: number }>(
    `select ${SEEN_ACTIVITY} as a, count(*)::int as n from buddies group by 1`,
    [awakeSecs],
  );
  for (const { a, n } of counted) if (a in doing) doing[a] += n;
  const total = Object.values(doing).reduce((s, n) => s + n, 0);

  const today = await totalsSince(db, TODAY, TODAY);
  const year = await totalsSince(db, `date_trunc('year', ${TODAY})::date`, TODAY);

  // Every region, in REGIONS' order, with zeros where no buddy is.
  const byRegion = await db.query<Snapshot["regions"][number]>(
    `select ${regionSql("b.utc_offset")} as region, (count(*) filter (where ${SEEN_ACTIVITY} <> 'asleep'))::int as awake,
            coalesce(sum(d.turns), 0)::int as today_turns
       from buddies b left join buddy_days d on d.buddy = b.id and d.day = ${TODAY}
      where b.utc_offset is not null
      group by 1`,
    [awakeSecs],
  );
  const regions = REGIONS.map(({ region }) => byRegion.find((r) => r.region === region) ?? { region, awake: 0, today_turns: 0 });

  const { goal } = await checkGoal(db);

  const rewards = await db.query<Snapshot["rewards"][number]>(
    `select reward_tag as tag, ${date("(reached_at at time zone 'utc')::date + reward_days")} as until
       from goals
      where reached_at is not null and (reached_at at time zone 'utc')::date + reward_days > ${TODAY}
      order by id`,
  );

  const rows = await db.query<Snapshot["buddies"][number] & { name_ok: boolean; reports: number }>(
    `select id::text as id, name, name_ok, reports, level, stage, utc_offset, ${SEEN_ACTIVITY} as activity
       from buddies
      order by (${SEEN_ACTIVITY} <> 'asleep') desc, seen_at desc
      limit $2`,
    [awakeSecs, SNAPSHOT_BUDDIES],
  );
  const buddies = rows.map(({ name_ok, reports, ...b }) => ({ ...b, name: shownName({ name: b.name, name_ok, reports }) }));

  return { at, awake: total - doing.asleep, total, doing, today, year, regions, goal, rewards, buddies };
}
