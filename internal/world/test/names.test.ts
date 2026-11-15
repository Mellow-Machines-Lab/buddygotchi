// The name filter (plan/world.md §2.7): 23 characters at most, as the Mac's, letters,
// digits, spaces and a few marks; no word from the list, link, handle or
// phone number. A refused name is kept but shown as "a buddy".

import assert from "node:assert/strict";
import { test } from "node:test";
import { HIDDEN_NAME, NAME_MAX, checkName, shownName } from "../src/names.js";
import { REPORTS_TO_HIDE } from "../src/limits.js";

test("ordinary names pass, in any script", () => {
  for (const name of ["Mochi", "Bean", "Mr. Wiggles", "Zoë", "ポチ", "Ana-Maria", "R2", "Cassie", "Peacock", "Booboo", "Spicy", "Torpedo"]) {
    assert.deepEqual(checkName(name), { name, ok: true }, name);
  }
});

test("spaces are trimmed and collapsed", () => {
  assert.deepEqual(checkName("  Big   Bean "), { name: "Big Bean", ok: true });
});

test(`a name is at most ${NAME_MAX} characters`, () => {
  assert.equal(checkName("a".repeat(NAME_MAX)).ok, true);
  assert.equal(checkName("a".repeat(NAME_MAX + 1)).reason, "length");
  assert.equal(checkName("x".repeat(100)).name.length, 32, "kept, cut to 32");
});

test("empty and non-text names are refused", () => {
  assert.equal(checkName("").reason, "empty");
  assert.equal(checkName("   ").reason, "empty");
  assert.equal(checkName(42).reason, "empty");
});

test("links are refused", () => {
  for (const name of ["boop.com", "www.x", "http stuff", "go2 site.io", "visit dot com"]) {
    assert.equal(checkName(name).reason, "link", name);
  }
});

test("handles and odd characters are refused", () => {
  for (const name of ["@mochi", "#tag", "a<b>", "emoji 🙂", "x/y"]) {
    assert.equal(checkName(name).ok, false, name);
  }
  assert.equal(checkName("@mochi").reason, "characters");
});

test("five digits or more reads as a phone number", () => {
  assert.equal(checkName("Bean 1234").ok, true);
  assert.equal(checkName("555 1234").reason, "number");
  assert.equal(checkName("91234567").reason, "number");
});

test("words from the list are refused, folded and spelt out", () => {
  for (const name of ["fuck", "FuCk you", "sh1t", "f.u.c.k", "big ass", "a55hole", "nazi", "Fück"]) {
    assert.equal(checkName(name).reason, "word", name);
  }
});

test(`a name is shown only when it passed and has under ${REPORTS_TO_HIDE} reports`, () => {
  assert.equal(shownName({ name: "Mochi", name_ok: true, reports: 0 }), "Mochi");
  assert.equal(shownName({ name: "Mochi", name_ok: true, reports: REPORTS_TO_HIDE - 1 }), "Mochi");
  assert.equal(shownName({ name: "Mochi", name_ok: true, reports: REPORTS_TO_HIDE }), HIDDEN_NAME);
  assert.equal(shownName({ name: "boop.com", name_ok: false, reports: 0 }), HIDDEN_NAME);
});
