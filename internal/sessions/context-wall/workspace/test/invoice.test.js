// The invoice totals: the subtotal, discount codes, and sales tax on what's
// left after the discount. Amounts are in cents.
const assert = require("node:assert");
const { subtotal, total } = require("../src/invoice");

const lines = [
  { price: 250, qty: 2 },
  { price: 1000, qty: 1 },
];
const hundred = [{ price: 10000, qty: 1 }];

const tests = {
  "the subtotal adds every line": () => {
    assert.strictEqual(subtotal(lines), 1500);
  },
  "with no code or tax, the total is the subtotal": () => {
    assert.strictEqual(total({ lines }), 1500);
  },
  "SAVE10 takes 10% off": () => {
    assert.strictEqual(total({ lines: hundred, code: "SAVE10" }), 9000);
  },
  "an unknown code is refused": () => {
    assert.throws(() => total({ lines: hundred, code: "FREE" }), /Unknown discount code: FREE/);
  },
  "tax is added after the discount": () => {
    assert.strictEqual(total({ lines: hundred, code: "SAVE10", taxRate: 0.08 }), 9720);
  },
  "tax rounds to the nearest cent": () => {
    assert.strictEqual(total({ lines: [{ price: 1999, qty: 1 }], taxRate: 0.0825 }), 2164);
  },
};

// One at a time, as a test runner prints them.
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
(async () => {
  let failed = 0;
  for (const [name, test] of Object.entries(tests)) {
    await sleep(300);
    try {
      test();
      console.log(`  ✓ ${name}`);
    } catch (error) {
      failed++;
      console.log(`  ✗ ${name}\n      ${error.message.split("\n")[0]}`);
    }
  }
  const passed = Object.keys(tests).length - failed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
