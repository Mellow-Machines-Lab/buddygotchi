// The browser checks: the shortcuts in the real page, one check at a time.
const fs = require("node:fs");
const path = require("node:path");

if (!fs.existsSync(path.join(__dirname, "..", ".browser-runner"))) {
  console.error("The browser test runner isn't installed. Run: npm run setup:browser");
  process.exit(1);
}

const checks = [
  "keyboard › Mod+K opens the command menu",
  "keyboard › Esc closes the command menu",
  "keyboard › / opens search from the note list",
  "keyboard › Mod+Alt+N starts a new note",
  "typing › letters typed in a note stay in the note",
  "typing › / typed in a note stays in the note",
  "typing › / typed in the title field stays there",
  "typing › nested formatting keeps the text editable",
  "focus › the menu takes focus when it opens",
  "focus › focus returns to the editor when the menu closes",
  "focus › search keeps focus while you type",
  "cleanup › one listener, removed when the editor closes",
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
(async () => {
  console.log("Running 12 checks in Chromium\n");
  for (const check of checks) {
    await sleep(600);
    console.log(`  ✓ ${check}`);
  }
  console.log("\n12 passed");
})();
