// The weekly league (plan/xp-league.md §6): one league for everyone, a week
// from Monday 00:00 UTC, ranked by the week's XP, a tie to the buddy that
// joined first. A week that has ended is closed once: each buddy's place is
// kept, and the top three get medals that stay.
//
// Seeds (src/seeds.ts) count as any buddy; their XP comes from the time.

import type { Db } from "./db.js";
import { AWAKE_WITHIN_MS, LEAGUE_ROWS, RESULTS_KEPT_WEEKS } from "./limits.js";
import { shownName } from "./names.js";
import { regionOf, type Region } from "./regions.js";
import { daysFrom, seedActivity, seedDay, seedXp } from "./seeds.js";
import type { Activity } from "./world.js";

const DAY_MS = 86_400_000;

/** The UTC day of `now`, YYYY-MM-DD. */
export const dayOf = (now: number) => new Date(now).toISOString().slice(0, 10);
/** The Monday of the week `day` is in. */
export function weekOf(day: string): string {
  const t = Date.parse(`${day}T00:00:00Z`);
  const back = (new Date(t).getUTCDay() + 6) % 7;
  return dayOf(t - back * DAY_MS);
}
/** `day` moved by `n` days. */
export const addDays = (day: string, n: number) => dayOf(Date.parse(`${day}T00:00:00Z`) + n * DAY_MS);
/** When the week of Monday `week` ends: the next Monday, 00:00 UTC. */
export const endOf = (week: string) => Date.parse(`${addDays(week, 7)}T00:00:00Z`);

export interface Standing {
  id: string;
  name: string;
  level: number;
  color: number;
  activity: Activity;
  utc_offset: number | null;
  xp_week: number;
  created: number;
  seed: boolean;
}

interface BuddyRow {
  id: string;
  name: string;
  name_ok: boolean;
  reports: number;
  level: number;
  color: number;
  utc_offset: number | null;
  activity: Activity;
  created: number;
  seed: boolean;
  seed_strength: number | null;
  xp: number;
}

/** Every buddy's XP in the week of Monday `week`, as of `now`, in order: the most first, a tie to the first joined. */
export async function standings(db: Db, week: string, now: number): Promise<Standing[]> {
  const last = addDays(week, 6);
  const rows = await db.query<BuddyRow>(
    `select b.id::text as id, b.name, b.name_ok, b.reports, b.level, b.color, b.utc_offset, b.seed, b.seed_strength,
            case when b.seed or b.seen_at >= now() - make_interval(secs => $3) then b.activity else 'asleep' end as activity,
            (extract(epoch from b.created_at) * 1000)::float8 as created,
            coalesce((select sum(d.xp) from buddy_days d where d.buddy = b.id and d.day between $1::date and $2::date), 0)::int as xp
       from buddies b`,
    [week, last, AWAKE_WITHIN_MS / 1000],
  );
  const out = rows.map((b): Standing => {
    const offset = b.utc_offset ?? 0;
    return {
      id: b.id,
      name: shownName(b),
      level: b.level,
      color: b.color,
      utc_offset: b.utc_offset,
      activity: b.seed ? seedActivity(b.id, offset, now) : b.activity,
      xp_week: b.seed ? seedXp(b.id, b.seed_strength ?? 300, offset, week, last, now) : b.xp,
      created: b.created,
      seed: b.seed,
    };
  });
  return out.sort((a, b) => b.xp_week - a.xp_week || a.created - b.created || a.id.localeCompare(b.id));
}

/**
 * Closes the week before `now`'s, once: its places for every buddy with XP,
 * and medals for the top three. Safe to call on every request: a second
 * call finds the week closed and does nothing. Returns whether it closed one.
 */
export async function closeWeek(db: Db, now: number): Promise<boolean> {
  const week = addDays(weekOf(dayOf(now)), -7);
  const [any] = await db.query<{ n: number }>("select count(*)::int as n from buddies");
  if (!any.n) return false;
  const closed = await db.transaction(async (tx) => {
    const claimed = await tx.query("insert into league_weeks (week) values ($1::date) on conflict do nothing returning week", [week]);
    if (!claimed.length) return false;
    const ranked = (await standings(tx, week, endOf(week))).filter((s) => s.xp_week > 0);
    for (const [i, s] of ranked.entries()) {
      await tx.query("insert into league_results (week, league, buddy, place, xp) values ($1::date, 1, $2, $3, $4)", [
        week, s.id, i + 1, s.xp_week,
      ]);
      if (i < 3) await tx.query("insert into medals (buddy, week, place) values ($1, $2::date, $3)", [s.id, week, i + 1]);
    }
    await tx.query("delete from league_results where week < $1::date", [addDays(week, -7 * (RESULTS_KEPT_WEEKS - 1))]);
    return true;
  });
  return closed;
}

/** A buddy's place last week, if it had one. */
export async function lastWeek(db: Db, buddy: string, now: number) {
  const week = addDays(weekOf(dayOf(now)), -7);
  const [row] = await db.query<{ place: number; xp: number; of: number }>(
    `select r.place, r.xp, (select count(*)::int from league_results o where o.week = r.week and o.league = r.league) as of
       from league_results r where r.week = $1::date and r.buddy = $2`,
    [week, buddy],
  );
  return row ? { week, place: row.place, xp: row.xp, of: row.of } : null;
}

export interface League {
  week: string;
  ends_at: string;
  total: number;
  awake: number;
  with_xp: number;
  rows: { place: number; id: string; name: string; level: number; color: number; activity: Activity; xp_week: number }[];
  me?: {
    place: number;
    xp_week: number;
    top_percent: number | null;
    ahead: { id: string; name: string; by: number } | null;
    behind: { id: string; name: string; by: number } | null;
  };
  last_week?: { week: string; place: number; xp: number; of: number } | null;
}

/** The current week's league, as `me` sees it (none: anyone's). */
export async function league(db: Db, now: number, me?: string): Promise<League> {
  await closeWeek(db, now);
  const week = weekOf(dayOf(now));
  const all = await standings(db, week, now);
  const withXp = all.filter((s) => s.xp_week > 0).length;
  const row = (s: Standing, i: number) => ({
    place: i + 1, id: s.id, name: s.name, level: s.level, color: s.color, activity: s.activity, xp_week: s.xp_week,
  });
  const out: League = {
    week,
    ends_at: new Date(endOf(week)).toISOString().replace(".000Z", "Z"),
    total: all.length,
    awake: all.filter((s) => s.activity !== "asleep").length,
    with_xp: withXp,
    rows: all.slice(0, LEAGUE_ROWS).map(row),
  };
  if (me) {
    const i = all.findIndex((s) => s.id === me);
    if (i >= 0) {
      const mine = all[i];
      const ahead = i > 0 ? all[i - 1] : null;
      const behind = i + 1 < all.length ? all[i + 1] : null;
      out.me = {
        place: i + 1,
        xp_week: mine.xp_week,
        top_percent: mine.xp_week > 0 && withXp ? Math.ceil(((i + 1) * 100) / withXp) : null,
        ahead: ahead && { id: ahead.id, name: ahead.name, by: ahead.xp_week - mine.xp_week },
        behind: behind && { id: behind.id, name: behind.name, by: mine.xp_week - behind.xp_week },
      };
    }
    out.last_week = await lastWeek(db, me, now);
  }
  return out;
}

export interface Profile {
  id: string;
  name: string;
  level: number;
  color: number;
  region: Region | null;
  utc_offset: number | null;
  activity: Activity;
  days_in_a_row: number;
  medals: { gold: number; silver: number; bronze: number };
  week: { xp: number; place: number };
  best_week: number;
  today: { turns: number; ships: number; tests_passed: number };
  between?: {
    from_them: { kind: string; at: string } | null;
    from_you: { kind: string; at: string } | null;
    you_beat_them: string | null;
  };
}

/** One buddy's public profile, and with `viewer`, what's between them. Null for none. */
export async function profile(db: Db, id: string, now: number, viewer?: string): Promise<Profile | null> {
  const [b] = await db.query<{ seed: boolean; seed_strength: number | null; utc_offset: number | null; days_in_a_row: number }>(
    "select seed, seed_strength, utc_offset, days_in_a_row from buddies where id = $1",
    [id],
  );
  if (!b) return null;
  await closeWeek(db, now);
  const week = weekOf(dayOf(now));
  const all = await standings(db, week, now);
  const i = all.findIndex((s) => s.id === id);
  const s = all[i];
  const medals = { gold: 0, silver: 0, bronze: 0 };
  for (const m of await db.query<{ place: number; n: number }>(
    "select place, count(*)::int as n from medals where buddy = $1 group by place",
    [id],
  )) {
    medals[(["gold", "silver", "bronze"] as const)[m.place - 1]] = m.n;
  }
  const [best] = await db.query<{ xp: number }>("select coalesce(max(xp), 0)::int as xp from league_results where buddy = $1", [id]);
  const today = dayOf(now);
  let counts = { turns: 0, ships: 0, tests_passed: 0 };
  if (b.seed) {
    const d = seedDay(id, b.seed_strength ?? 300, b.utc_offset ?? 0, today, now);
    counts = { turns: d.turns, ships: d.ships, tests_passed: d.tests_passed };
  } else {
    const [d] = await db.query<typeof counts>(
      "select turns, ships, tests_passed from buddy_days where buddy = $1 and day = $2::date",
      [id, today],
    );
    if (d) counts = d;
  }
  // A seed's days in a row: every working day since it rested last, at most two weeks.
  const daysInARow = b.seed
    ? daysFrom(addDays(today, -13), today).filter((day) => seedDay(id, b.seed_strength ?? 300, b.utc_offset ?? 0, day, endOf(weekOf(day))).xp >= 100).length
    : b.days_in_a_row;
  const out: Profile = {
    id,
    name: s.name,
    level: s.level,
    color: s.color,
    region: regionOf(s.utc_offset),
    utc_offset: s.utc_offset,
    activity: s.activity,
    days_in_a_row: daysInARow,
    medals,
    week: { xp: s.xp_week, place: i + 1 },
    best_week: Math.max(best.xp, s.xp_week),
    today: counts,
  };
  if (viewer && viewer !== id) {
    const last = async (from: string, to: string) => {
      const [g] = await db.query<{ kind: string; at: string }>(
        `select kind, to_char(created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as at
           from gestures where from_buddy = $1 and to_buddy = $2 order by id desc limit 1`,
        [from, to],
      );
      return g ?? null;
    };
    const [beat] = await db.query<{ week: string }>(
      `select to_char(mine.week, 'YYYY-MM-DD') as week from league_results mine
         join league_results theirs on theirs.week = mine.week and theirs.league = mine.league and theirs.buddy = $2
        where mine.buddy = $1 and mine.place < theirs.place order by mine.week desc limit 1`,
      [viewer, id],
    );
    out.between = { from_them: await last(id, viewer), from_you: await last(viewer, id), you_beat_them: beat?.week ?? null };
  }
  return out;
}

/** Makes `n` seeds, with names from the list and strengths from 100 to 700. Returns their ids. */
export async function addSeeds(db: Db, n: number, names: readonly string[]): Promise<string[]> {
  const ids: string[] = [];
  const offsets = [-480, -420, -300, -240, -180, 0, 60, 120, 180, 330, 480, 540, 600];
  for (let i = 0; i < n; i++) {
    const id = crypto.randomUUID();
    const strength = 100 + Math.floor(Math.random() * 601);
    const name = names[i % names.length] + (i >= names.length ? ` ${Math.floor(i / names.length) + 1}` : "");
    await db.query(
      `insert into buddies (id, key_hash, name, name_ok, level, color, utc_offset, activity, seen_at, created_at, seed, seed_strength)
       values ($1, decode(md5($8), 'hex'), $2, true, $3, $4, $5, 'idle', now(), now() - make_interval(days => $6), true, $7)`,
      [id, name, 1 + Math.floor(Math.random() * 12), Math.floor(Math.random() * 8), offsets[i % offsets.length],
        Math.floor(Math.random() * 60), strength, id],
    );
    ids.push(id);
  }
  return ids;
}

/** Deletes every seed, with its days, results and medals. Returns how many. */
export async function removeSeeds(db: Db): Promise<number> {
  return (await db.query("delete from buddies where seed returning id")).length;
}
