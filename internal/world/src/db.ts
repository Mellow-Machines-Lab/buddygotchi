// The database: Postgres from DATABASE_URL, or PGlite in memory when it's
// unset (tests and local runs), with the same migrations applied.
//
// Every query is plain SQL with $1-style parameters. Numbers come back as
// JavaScript numbers only when the SQL casts them (::int, ::float8), and
// dates only as text, because the two drivers differ on both.

import { readdir, readFile } from "node:fs/promises";

export interface Db {
  query<T = Record<string, unknown>>(text: string, params?: unknown[]): Promise<T[]>;
  transaction<T>(fn: (tx: Db) => Promise<T>): Promise<T>;
  close(): Promise<void>;
}

const migrationsDir = new URL("../db/migrations/", import.meta.url);

/** Postgres's codes for a transaction it gave up on and that may simply be
 * run again: a deadlock, or a serialization failure. Two buddies leaving at
 * once can deadlock on each other's gestures. */
const retryable = new Set(["40P01", "40001"]);
export const transactionTries = 4;

/** Runs `fn`, again with a short, growing pause when Postgres gave up on it
 * for a reason that running it again fixes, at most `transactionTries` times. */
export async function retrying<T>(fn: () => Promise<T>, pause = (ms: number) => new Promise((r) => setTimeout(r, ms))): Promise<T> {
  for (let attempt = 1; ; attempt++) {
    try {
      return await fn();
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (!code || !retryable.has(code) || attempt >= transactionTries) throw error;
      await pause(20 * 2 ** attempt + Math.floor(Math.random() * 20));
    }
  }
}

/** A Postgres pool, from a connection string such as Neon's. */
export async function connectPostgres(url: string, { max = 5 } = {}): Promise<Db> {
  const { default: postgres } = await import("postgres");
  // prepare: false works behind any pooler, Neon's included.
  const sql = postgres(url, { max, idle_timeout: 20, prepare: false, onnotice: () => {} });
  const wrap = (q: { unsafe: typeof sql.unsafe }): Omit<Db, "transaction" | "close"> => ({
    async query<T>(text: string, params: unknown[] = []) {
      return (await q.unsafe(text, params as never[])) as unknown as T[];
    },
  });
  const db: Db = {
    ...wrap(sql),
    async transaction<T>(fn: (tx: Db) => Promise<T>) {
      return retrying(async () => (await sql.begin(async (tx) => {
        const inner: Db = { ...wrap(tx), transaction: (f) => f(inner), close: async () => {} };
        return fn(inner);
      })) as T);
    },
    async close() {
      await sql.end({ timeout: 5 });
    },
  };
  return db;
}

/** Real Postgres in memory, migrated: for tests and `npm run dev`. */
export async function memoryDb(): Promise<Db> {
  const { PGlite } = await import("@electric-sql/pglite");
  const pg = new PGlite();
  type Q = { query: typeof pg.query };
  const wrap = (q: Q, self: () => Db): Db => ({
    async query<T>(text: string, params: unknown[] = []) {
      return (await q.query<T>(text, params)).rows;
    },
    transaction: (fn) => self().transaction(fn),
    close: async () => {},
  });
  const db: Db = {
    ...wrap(pg, () => db),
    async transaction<T>(fn: (tx: Db) => Promise<T>) {
      return pg.transaction(async (tx) => {
        const inner: Db = wrap(tx, () => inner);
        inner.transaction = (f) => f(inner);
        return fn(inner);
      });
    },
    async close() {
      await pg.close();
    },
  };
  await migrate(db);
  return db;
}

/**
 * Applies the migrations in db/migrations/ that haven't run, in name order,
 * each in a transaction with its row in schema_migrations. Running it again
 * does nothing. Returns the names it applied.
 */
export async function migrate(db: Db): Promise<string[]> {
  await db.query(
    "create table if not exists schema_migrations (name text primary key, applied_at timestamptz not null default now())",
  );
  const done = new Set((await db.query<{ name: string }>("select name from schema_migrations")).map((r) => r.name));
  const files = (await readdir(migrationsDir)).filter((f) => f.endsWith(".sql")).sort();
  const applied: string[] = [];
  for (const name of files) {
    if (done.has(name)) continue;
    const text = await readFile(new URL(name, migrationsDir), "utf8");
    await db.transaction(async (tx) => {
      for (const statement of splitStatements(text)) await tx.query(statement);
      await tx.query("insert into schema_migrations (name) values ($1)", [name]);
    });
    applied.push(name);
  }
  return applied;
}

/** Splits a migration into statements: on semicolons that end a line, comments dropped. */
function splitStatements(text: string): string[] {
  return text
    .split("\n")
    .map((line) => line.replace(/--.*$/, ""))
    .join("\n")
    .split(/;\s*$/m)
    .map((s) => s.trim())
    .filter(Boolean);
}

let shared: Promise<Db> | undefined;

/**
 * The app's database, made on first use. On Vercel, DATABASE_URL must be
 * set: an in-memory world there would lose every buddy on each restart.
 */
export function defaultDb(): Promise<Db> {
  shared ??= (async () => {
    const url = process.env.DATABASE_URL;
    if (url) return connectPostgres(url);
    if (process.env.VERCEL) throw new Error("DATABASE_URL is not set");
    return memoryDb();
  })();
  shared.catch(() => {
    shared = undefined;
  });
  return shared;
}
