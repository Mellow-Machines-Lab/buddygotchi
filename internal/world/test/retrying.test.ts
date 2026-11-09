import assert from "node:assert/strict";
import { test } from "node:test";
import { retrying, transactionTries } from "../src/db.js";

const noPause = async () => {};

test("a deadlocked transaction runs again, and succeeds", async () => {
  let runs = 0;
  const result = await retrying(async () => {
    runs++;
    if (runs < 3) throw Object.assign(new Error("deadlock detected"), { code: "40P01" });
    return "done";
  }, noPause);
  assert.equal(result, "done");
  assert.equal(runs, 3);
});

test("it gives up after its tries, with Postgres's error", async () => {
  let runs = 0;
  await assert.rejects(
    retrying(async () => {
      runs++;
      throw Object.assign(new Error("deadlock detected"), { code: "40P01" });
    }, noPause),
    /deadlock/,
  );
  assert.equal(runs, transactionTries);
});

test("any other error is not run again", async () => {
  let runs = 0;
  await assert.rejects(
    retrying(async () => {
      runs++;
      throw Object.assign(new Error("syntax error"), { code: "42601" });
    }, noPause),
  );
  assert.equal(runs, 1);
});
