// Fills the world with made-up buddies until real ones come
// (plan/xp-league.md §6.4), or takes them all out again:
//
//   npm run seed -- 30         # 30 seeds
//   npm run seed -- --remove   # every seed, with its results and medals
//
// It uses DATABASE_URL, or .env.local's (`npx vercel env pull .env.local`).

import { existsSync } from "node:fs";
import { connectPostgres } from "../src/db.js";
import { addSeeds, removeSeeds } from "../src/league.js";
import { SEED_NAMES } from "../src/seeds.js";

const envFile = new URL("../.env.local", import.meta.url);
if (!process.env.DATABASE_URL && existsSync(envFile)) process.loadEnvFile(envFile);
const url = process.env.DATABASE_URL;
if (!url) {
  console.error("DATABASE_URL is not set. Run `npx vercel env pull .env.local` first, or set it.");
  process.exit(1);
}

const arg = process.argv[2];
const db = await connectPostgres(url);
try {
  if (arg === "--remove") {
    console.log(`Removed ${await removeSeeds(db)} seeds.`);
  } else {
    const n = Number(arg);
    if (!Number.isInteger(n) || n < 1 || n > 1000) {
      console.error("Say how many seeds, 1 to 1000, or --remove.");
      process.exit(1);
    }
    console.log(`Added ${(await addSeeds(db, n, SEED_NAMES)).length} seeds.`);
  }
} finally {
  await db.close();
}
