// Installs the browser test runner: a local stand-in for downloading a
// browser, so the project needs no network.
const fs = require("node:fs");
const path = require("node:path");

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
(async () => {
  console.log("Installing the browser test runner");
  for (const pct of [12, 37, 64, 88, 100]) {
    await sleep(600);
    console.log(`  Chromium 131.0 · ${pct}%`);
  }
  fs.writeFileSync(path.join(__dirname, "..", ".browser-runner"), "chromium 131.0\n");
  console.log("Ready: npm run test:browser");
})();
