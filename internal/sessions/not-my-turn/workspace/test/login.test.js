// Logging in shows the welcome text.
const assert = require("assert");
const { screen, login } = require("../src/login");

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

(async () => {
  login("ana");
  await sleep(100);
  assert.ok(screen.text().includes("Welcome"), "the welcome text shows after logging in");
  console.log("login test passed");
})().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
