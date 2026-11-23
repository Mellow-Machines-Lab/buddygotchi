// Made-up buddies, to fill a small world until real ones come
// (plan/xp-league.md §6.4). A seed is a row in `buddies` with `seed = true`;
// nothing writes for it during the day. What it earned and what it's doing
// come from the time alone, by this pure function, so every request agrees.
//
// A seed's days are UTC days, as the server's are. It works its local
// weekday hours, 9:00 to 18:00 at its UTC offset, rests most weekends and
// now and then a weekday, and its XP for a day grows through those hours.

import { XP_PER_DAY } from "./limits.js";
import type { Activity } from "./world.js";

export const SEED_NAMES = [
  "Bean", "Nori", "Rex", "Tofu", "Pixel", "Miso", "Pip", "Mango", "Kiwi", "Biscuit", "Dumpling", "Olive",
  "Pebble", "Sprout", "Waffle", "Juniper", "Clover", "Noodle", "Peanut", "Basil", "Ziggy", "Momo", "Taro",
  "Yuzu", "Gizmo", "Pickle", "Button", "Sushi", "Truffle", "Maple",
] as const;

/** A number in [0, 1) from a string, the same every time. */
export function unit(key: string): number {
  let h = 2166136261;
  for (let i = 0; i < key.length; i++) h = Math.imul(h ^ key.charCodeAt(i), 16777619);
  // One more mix, so close keys spread.
  h ^= h >>> 15;
  h = Math.imul(h, 2246822507);
  h ^= h >>> 13;
  return (h >>> 0) / 4294967296;
}

export interface SeedDay {
  xp: number;
  turns: number;
  ships: number;
  tests_passed: number;
}

const DAY_MS = 86_400_000;

/** Whether a seed rests on the UTC day `day`: most weekends, now and then a weekday. */
function rests(id: string, day: string): boolean {
  const weekday = new Date(`${day}T00:00:00Z`).getUTCDay();
  const weekend = weekday === 0 || weekday === 6;
  return unit(`${id}:${day}:rest`) < (weekend ? 0.75 : 0.1);
}

/** How far through its working hours a seed at `utcOffset` minutes is on `day` at `now`: 0 to 1. */
function through(day: string, utcOffset: number, now: number): number {
  const start = Date.parse(`${day}T09:00:00Z`) - utcOffset * 60_000;
  const end = start + 9 * 3_600_000;
  return Math.max(0, Math.min(1, (now - start) / (end - start)));
}

/** What a seed of `strength` (its usual week's XP) earned on the UTC day `day`, as of `now`. */
export function seedDay(id: string, strength: number, utcOffset: number, day: string, now: number): SeedDay {
  const none = { xp: 0, turns: 0, ships: 0, tests_passed: 0 };
  if (rests(id, day)) return none;
  const done = through(day, utcOffset, now);
  if (done <= 0) return none;
  const full = Math.min(XP_PER_DAY, Math.round((strength / 5) * (0.6 + 0.8 * unit(`${id}:${day}:xp`))));
  const xp = Math.round(full * done);
  const ships = unit(`${id}:${day}:ship`) < 0.35 && done > 0.6 ? 1 : 0;
  const turns = Math.max(0, Math.round((xp - ships * 10) / 5));
  return { xp, turns, ships, tests_passed: Math.round(turns * 0.6) };
}

/** What a seed is doing at `now`, by its local hour and day. */
export function seedActivity(id: string, utcOffset: number, now: number): Activity {
  const local = now + utcOffset * 60_000;
  const hour = new Date(local).getUTCHours();
  const day = new Date(now).toISOString().slice(0, 10);
  if (hour < 8) return "asleep";
  if (rests(id, day) || hour >= 18) return hour >= 23 ? "asleep" : "idle";
  if (hour < 9) return "idle";
  const r = unit(`${id}:${Math.floor(now / 600_000)}`);
  return r < 0.55 ? "coding" : r < 0.75 ? "testing" : r < 0.9 ? "waiting" : "shipping";
}

/** The UTC days from `from` to `to`, both included, as YYYY-MM-DD. */
export function daysFrom(from: string, to: string): string[] {
  const out: string[] = [];
  for (let t = Date.parse(`${from}T00:00:00Z`); t <= Date.parse(`${to}T00:00:00Z`); t += DAY_MS) {
    out.push(new Date(t).toISOString().slice(0, 10));
  }
  return out;
}

/** A seed's XP over the UTC days `from` to `to`, as of `now`. */
export function seedXp(id: string, strength: number, utcOffset: number, from: string, to: string, now: number): number {
  return daysFrom(from, to).reduce((sum, day) => sum + seedDay(id, strength, utcOffset, day, now).xp, 0);
}
