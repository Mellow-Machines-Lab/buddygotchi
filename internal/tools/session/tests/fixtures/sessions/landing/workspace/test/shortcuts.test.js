// The shortcuts against a stand-in document: keys land on a target, and
// the listeners decide what they do.
const assert = require("node:assert");
const { createEditor } = require("../src/editor");
const { useShortcuts } = require("../src/useShortcuts");

function fakeDocument() {
  const listeners = [];
  return {
    addEventListener(type, fn) {
      if (type === "keydown") listeners.push(fn);
    },
    removeEventListener(type, fn) {
      const i = listeners.indexOf(fn);
      if (type === "keydown" && i >= 0) listeners.splice(i, 1);
    },
    press(key, target, mods = {}) {
      const event = { key, target, ...mods, defaultPrevented: false, preventDefault() { this.defaultPrevented = true; } };
      for (const fn of [...listeners]) fn(event);
      return event;
    },
    get listening() {
      return listeners.length;
    },
  };
}

const page = { tagName: "BODY", contentEditable: "inherit", parentNode: null };
const note = { tagName: "DIV", contentEditable: "true", parentNode: page };
const word = { tagName: "SPAN", contentEditable: "inherit", parentNode: note };
const field = { tagName: "INPUT", contentEditable: "inherit", parentNode: page };

function setUp() {
  const doc = fakeDocument();
  const editor = createEditor({ focus() {} });
  const stop = useShortcuts(editor, doc);
  return { doc, editor, stop };
}

const tests = {
  "Mod+K opens the command menu": () => {
    const { doc, editor } = setUp();
    doc.press("k", page, { metaKey: true });
    assert.ok(editor.menu.open, "the menu didn't open");
  },
  "Mod+K works while typing too": () => {
    const { doc, editor } = setUp();
    doc.press("k", word, { ctrlKey: true });
    assert.ok(editor.menu.open, "the menu didn't open from a note");
  },
  "/ opens search outside the editor": () => {
    const { doc, editor } = setUp();
    doc.press("/", page);
    assert.ok(editor.search.open, "search didn't open");
  },
  "typing in an input is left alone": () => {
    const { doc, editor } = setUp();
    const event = doc.press("/", field);
    assert.ok(!editor.search.open && !event.defaultPrevented, "a / typed in an input opened search");
  },
  "typing in an editable target is left alone": () => {
    const { doc, editor } = setUp();
    const event = doc.press("/", word);
    assert.ok(!editor.search.open && !event.defaultPrevented, "a / typed in a note opened search");
  },
  "cleanup removes the listener": () => {
    const { doc, stop } = setUp();
    stop();
    assert.strictEqual(doc.listening, 0, "a keydown listener was left behind");
  },
};

// One at a time, as a test runner prints them.
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
(async () => {
  let failed = 0;
  for (const [name, test] of Object.entries(tests)) {
    await sleep(350);
    try {
      test();
      console.log(`  ✓ ${name}`);
    } catch (error) {
      failed++;
      console.log(`  ✗ ${name}\n      ${error.message}`);
    }
  }
  const passed = Object.keys(tests).length - failed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
