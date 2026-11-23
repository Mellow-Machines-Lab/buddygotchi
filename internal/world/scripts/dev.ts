// Serves the world locally, for the Mac app's tests: on PGlite in memory, so
// it needs no database and starts empty each time. PORT picks the port
// (8787 by default); ADMIN_TOKEN and CRON_SECRET are "dev" unless set;
// SEEDS=20 fills it with 20 made-up buddies (src/seeds.ts).
//
//   npm run dev
//   BOOP_WORLD_URL=http://localhost:8787 .build/debug/Boop --headless …

import { serve } from "@hono/node-server";
import { createApp } from "../src/app.js";
import { memoryDb } from "../src/db.js";
import { addSeeds } from "../src/league.js";
import { SEED_NAMES } from "../src/seeds.js";

const port = Number(process.env.PORT ?? 8787);
const db = memoryDb();
const app = createApp(() => db, {
  adminToken: () => process.env.ADMIN_TOKEN ?? "dev",
  cronSecret: () => process.env.CRON_SECRET ?? "dev",
});
const seeds = Number(process.env.SEEDS ?? 0);
if (seeds > 0) await addSeeds(await db, seeds, SEED_NAMES);
serve({ fetch: app.fetch, port }, (info) => {
  console.log(`The world, on PGlite in memory: http://localhost:${info.port}/v1/health`);
});
