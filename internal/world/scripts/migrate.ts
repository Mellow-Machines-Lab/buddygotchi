// Applies db/migrations/ to DATABASE_URL: only those not yet applied, each
// once, recorded in schema_migrations. Run it with `npm run migrate`, after
// `npx vercel env pull .env.local`, which this reads if DATABASE_URL is unset.

import { existsSync } from "node:fs";
import { connectPostgres, migrate } from "../src/db.js";

const envFile = new URL("../.env.local", import.meta.url);
if (!process.env.DATABASE_URL && existsSync(envFile)) process.loadEnvFile(envFile);

const url = process.env.DATABASE_URL;
if (!url) {
  console.error("DATABASE_URL is not set. Run `npx vercel env pull .env.local` first, or set it.");
  process.exit(1);
}

const db = await connectPostgres(url);
try {
  const applied = await migrate(db);
  console.log(applied.length ? `Applied: ${applied.join(", ")}` : "Nothing to apply: the database is up to date.");
} finally {
  await db.close();
}
