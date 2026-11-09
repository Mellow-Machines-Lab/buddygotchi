// What the tests share: one PGlite world per file, emptied before each test,
// and small helpers to call the app as a Mac would.

import { readFileSync } from "node:fs";
import { after, beforeEach } from "node:test";
import { createApp } from "../src/app.js";
import { memoryDb, type Db } from "../src/db.js";
import { SEND_EVERY_MS } from "../src/limits.js";

export const ADMIN = "admin-token-for-tests";
export const CRON = "cron-secret-for-tests";
export const IP_SALT = "ip-salt-for-tests";

export function fixture<T = Record<string, unknown>>(name: string): T {
  return JSON.parse(readFileSync(new URL(`../fixtures/${name}`, import.meta.url), "utf8")) as T;
}

export interface Buddy {
  id: string;
  key: string;
  name: string;
  name_ok: boolean;
  name_reason?: string;
}

export interface World {
  db: Db;
  app: ReturnType<typeof createApp>;
  /** A request with a JSON body and, when given, a bearer token. */
  call(method: string, path: string, opts?: { key?: string; body?: unknown; ip?: string }): Promise<Response>;
  /** The same, returning the status and the parsed body. */
  json<T = any>(method: string, path: string, opts?: { key?: string; body?: unknown; ip?: string }): Promise<{ status: number; body: T }>;
  /** Joins with a name and a UTC offset in minutes (null: none sent), each from its own address. */
  join(name?: string, utcOffset?: number | null): Promise<Buddy>;
  /** A state send as the fixture's, with changes. */
  send(b: Buddy, state: Record<string, unknown>): Promise<{ status: number; body: any }>;
  /** Moves a buddy's last send back, past the send limit. */
  rewind(b: Buddy, seconds?: number): Promise<void>;
}

/** Call once at the top of a test file. */
export function world(): World {
  const dbReady = memoryDb();
  const app = createApp(() => dbReady, { adminToken: () => ADMIN, cronSecret: () => CRON, ipSalt: () => IP_SALT });
  let joins = 0;
  const w: World = {
    db: undefined as unknown as Db,
    app,
    call(method, path, { key, body, ip } = {}) {
      if (method === "GET" || method === "HEAD") body = undefined;
      const headers: Record<string, string> = {};
      if (key) headers.authorization = `Bearer ${key}`;
      if (ip) headers["x-forwarded-for"] = ip;
      if (body !== undefined) headers["content-type"] = "application/json";
      return Promise.resolve(app.request(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }));
    },
    async json(method, path, opts) {
      const res = await w.call(method, path, opts);
      return { status: res.status, body: (await res.json()) as any };
    },
    async join(name = "Mochi", utcOffset = 0) {
      const { status, body } = await w.json("POST", "/v1/buddies", { body: { name, utc_offset: utcOffset }, ip: `10.0.${joins >> 8 & 255}.${joins++ & 255}` });
      if (status !== 201) throw new Error(`join: ${status}`);
      return body as Buddy;
    },
    send(b, state) {
      return w.json("PUT", "/v1/buddies/me", { key: b.key, body: state });
    },
    async rewind(b, seconds = SEND_EVERY_MS / 1000 + 1) {
      await w.db.query("update buddies set sent_at = sent_at - make_interval(secs => $2) where id = $1", [b.id, seconds]);
    },
  };
  beforeEach(async () => {
    w.db = await dbReady;
    await w.db.query("truncate buddies, buddy_days, totals_by_day, goals, gestures, name_reports, joins restart identity cascade");
  });
  after(async () => (await dbReady).close());
  return w;
}

/** The fixture's state, with no counts: what most tests start from. */
export function state(changes: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    seq: 1,
    activity: "coding",
    day: "2026-11-08",
    xp_today: 0,
    added: { turns: 0, tests_passed: 0, ships: 0, lines_changed: 0 },
    ...changes,
  };
}
