# Prompt: a UI and UX review of Boop, down to the pixel

Updated 2026-11-09. The brief for one long session. The output is
`plan/ui-review.md`.

---

You are a senior product designer with a sharp eye for detail, joining Boop
for one long session. Your job is to find everything about how Boop **looks
and feels to use** that is off, on the Mac and on the board, and to say
exactly how to fix it. That means two levels:

1. **Polish.** Jagged or misaligned edges, uneven spacing, clipped or badly
   wrapped text, wrong sizes, weak contrast, icons that don't match, states
   that look broken, anything that "looks weird".
2. **Layout and UX.** What is on each screen, in what order, and why: the
   hierarchy, the density, what the eye goes to first, what a person must
   understand, and what to click. Larger changes to layout are welcome.

Do not write product code on `v1-polish`. Your output is one document, plus
the pictures that back it. Be concrete. I prefer too much detail to too little.

## 1. Where you are working

- Repository: `/Users/michaeljxzhu/src/buddygotchi`. Work in the worktree for
  branch `v1-polish`: `/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish`.
  Run every command from there. Don't cd to the repository root, and don't
  check out branches in the main checkout.
- First run `git status` and `git log --oneline -8`, then `make -C internal build`.
  If the build fails, run `git submodule update --init && make -C internal packs`
  and build again.
- Nothing is pushed. Do not push, tag, merge or force anything.

## 2. Rules you must keep

Read `CLAUDE.md` in full first. In particular:

- **Never use Bluetooth from a shell.** Never launch the everyday Boop app,
  and never run `bleak`. macOS kills the process.
- **Never touch** `~/.claude`, `~/.codex`, or the everyday app's state
  (`~/Library/Application Support/Boop`). Use a short state folder under `/tmp`.
- **No webcam.**
- **No Jev requests.** This review doesn't need the brain.
- **The board stays muted** (volume 0); the owner sleeps near it.
- **Use the project's words** (the Words table in `CLAUDE.md`), and never the
  words in its "Not" column.

## 3. What is already decided (don't propose again)

Read the top of `plan/TODO.md` ("Plan, 2026-11-09") and `plan/product-review.md`.
These are decided. You may propose **how they look**, but not whether:

- Part-full rings are blue, not red. No "XP" and no stage names in the UI.
- The needs-you card says what kind of thing waits.
- One moment for the ring and a level-up: the sign `today's done!` with
  `Level N!` on the low sign.
- The World tab gets a legend for its dots and honest words for a small world.
  The world's gestures go from three (wave, boop, heart) to one.
- A rename in Settings. A switch for swearing, off by default.
- Onboarding goes from 9 acts to 5 later; review today's 9 for polish only.
- Boop is a coworker and a pet, about equally.

The product review's word fixes are in `plan/product-review.md` §11.1 and
`plan/evidence/2026-11-09-product-review/words.md`. Don't repeat them. This
review is about the screen: layout, look and feel.

## 4. The surfaces, and how to see each one

Look at every surface in every state you can make. Keep every picture you
cite.

| Surface | How to see it |
| --- | --- |
| The popover: header, Now, Boop, World, the memory pane, Settings | `.build/debug/Boop --snapshots /tmp/ui/snaps` renders each tab in many states, light and dark, at 2 pixels a point (about 290 PNGs). `internal/app/Boop/Snapshots.swift` shows how each state is made, and is where to add a state you need |
| The menu bar icon | The same run: `menubar-*.png` |
| Onboarding, every act and state | The same run: `onboarding-*.png` |
| The board, the gel | `make -C internal sim` writes every scenario's frames to `/tmp/boop-sim/<branch>/gel/...` (moods, states, lane, drawer, growbar, v1, wish, notice, acts, finish, pastimes, reasons, transitions). The board is 320 × 240 |
| The board, live in a browser | `make -C internal simulator`, then `http://127.0.0.1:8206/`. Play the demos (`characters/DEMOS.md`). Use the pre-installed Playwright to take screenshots |
| The real panel | Only over USB. Run `internal/tools/boopctl board` (it must say free) and `boopctl ping`. If `ble` is `conn`, the owner's app is connected: **stop and leave the board alone.** Check `boopctl state` shows `face_down: false`. Then `boopctl run <scenario>` and `boopctl shot` |
| The app live, with hover, motion and real sizes (optional) | The internal build opens on the simulator with no Bluetooth: `make bundle INTERNAL=1`, then open `.build/internal/Boop.app` with its own `--state-dir` under `/tmp`, and choose the simulator in onboarding's act 4 **before anything looks for a board**. It needs Emscripten. It opens a window on the owner's screen, so quit it when done. If it can't run, say so and use the snapshots |

Also read:

- **The design tokens:** `app/Boop/Views/Theme.swift`. The look is called the
  Warm Terminal.
- **The v1 sketches the owner chose:** `~/.boopdev/v1-ui/v1-ui.html` and
  `v1-ui.png`. Compare what shipped with what was sketched.
- **The views' code**, to find the cause of each defect:
  - the popover: `app/Boop/Views/`;
  - onboarding: `app/Boop/Views/Onboarding/`;
  - the board: `firmware/src/app/` and the gel's renderer in
    `characters/boop/firmware/src/render/gel/`.
- **`internal/VERIFICATION.md`**, the Mac's look check (the snapshot rules) and
  the board's checks.

## 5. How to look

### 5.1 Go over each picture at full size, then zoom in

Crop and scale up the areas that matter (the venv at
`internal/tools/.venv/bin/python` has Pillow). Look at:

- **Alignment.** Do left edges line up across cards, rows, headings and
  buttons? Do baselines line up in a row? Are icons centred on their text?
- **Spacing.** Is the padding inside cards the same everywhere? The gaps
  between sections? Are there one-off values? Measure in pixels and list the
  values you find; a good design has few.
- **Size and shape.** Button heights, corner radii, icon sizes, stroke
  weights, chip sizes. Note any that differ for no reason.
- **Type.** How many sizes and weights are used? Is the hierarchy clear (what
  is the title, what is detail)? Is monospace used for a reason? Are there
  orphan words, widows, or lines that wrap at a bad place?
- **Edges.** Jagged anti-aliasing, seams between layers, half-pixel blur,
  hairlines that disappear in one mode, shadows cut off at a frame.
- **Clipping and overflow.** Text cut off, ellipses in the wrong place,
  content that runs under another layer, scroll areas that hide what matters.
- **Colour.** Contrast against WCAG AA (measure it), colours with a meaning
  that is never explained, light and dark modes that don't match, a colour
  that means two things.
- **States.** Empty, loading, error, long, crowded, first day, a long name, a
  name in another script, no board, no agents. Does each look designed or
  left over?

### 5.2 Then judge as a person would

- **The first second.** Where does the eye go first? Is that the right thing?
- **What can I click?** Is every control clear as a control? Is anything that
  looks like a button not one?
- **Density.** Is the popover calm, or does it ask for attention it doesn't
  need? Is anything shown on every tab that only matters on one?
- **Consistency.** Does the same thing look the same everywhere: a session, a
  mood, the buddy's name, a warning, the ring?
- **The Mac and the board as one product.** Do they share a look, a colour
  for each meaning, and the same words?
- **The board at arm's length.** Scale each frame to the real panel's size
  (2.06 inches) and judge from about 70 cm. Which text is too small? Which
  shapes can't be told apart? What is noise?

### 5.3 For layout, think in alternatives

For each screen, ask whether a different arrangement would be clearer:

- Which tab holds what.
- What the header carries on every tab.
- The order of the Now tab.
- How Settings is grouped, and its length.
- How the World tab tells its story.
- The board's lane, strip and low sign.

Where you propose a layout change, show it (§6).

## 6. Mockups

Mockups are welcome and make your case. Two ways:

- **In code, thrown away.** Make a scratch worktree on a new local branch
  (`ui-mockups`, never pushed and never merged), change the SwiftUI views
  there, and render with `--snapshots`. Keep only the PNGs.
- **In HTML.** A static page per proposal, using `Theme.swift`'s colours,
  rendered to PNG with Playwright.

Show each change as **before and after, side by side**, at the same scale.

## 7. What to deliver

### 7.1 One document: `plan/ui-review.md` in the `v1-polish` worktree

Put "Updated 2026-MM-DD" under the title. Sections, in this order:

1. **Summary.** A page at most: the state of the UI in a few lines, the 5
   worst problems, the 5 best changes.
2. **The system.** What the design tokens are, and how far the screens follow
   them: the spacing values, type sizes, radii and colours found in use,
   against `Theme.swift`. Propose a smaller, stricter set.
3. **Findings, by surface:** the header, Now, Boop, World, the memory pane,
   Settings, the menu bar icon, onboarding (act by act), the board.
4. **Layout and UX changes.** The larger proposals, each with a mockup.
5. **Quick fixes.** Ready now, each under an hour: file, line, and the exact
   value or change.
6. **A plan.** In order, each step shippable alone, with what the owner must
   check by eye. Fit it to the phases in `plan/TODO.md`.
7. **Open questions** for the owner, each with your recommendation.
8. **Evidence index.** Every picture and command you used.

**Each finding has these fields:**

- An id (`UI-12`).
- The surface and state.
- **A picture:** a crop with the problem marked (a red box or arrow is
  enough), and the source PNG's path.
- What is wrong, in one or two sentences.
- Why it matters to a person.
- The cause in code: `file:line`, where you can find it.
- The fix: exact, such as "padding 12 → 16", "use `Theme.inkSoft`", "one line
  with ellipsis at the middle".
- Severity: **broken** (it looks like a bug), **rough** (a careful person
  notices), **nit**.
- Effort: S (under an hour), M (a day), L (more).
- Confidence: high, medium, low.

### 7.2 The pictures

- Annotated crops and before-and-after pairs that the document cites go in
  `plan/evidence/<date>-ui-review/`. Keep that folder under about 10 MB: crop
  tightly and use PNG.
- Everything else (full snapshot runs, frames, mockup renders) goes in
  `~/.boopdev/ui-review-<date>/`.
- Don't link to `/tmp` in the document: it gets cleared.

### 7.3 Writing and committing

- **Writing style:** about 80% of the way to ASD-STE100. Use short sentences,
  the active voice and common words, and keep the subject's technical terms.
  Use tables where they help.
- **Commit:** only the document and its evidence folder, on `v1-polish`, with
  a plain message that ends with the attribution line your session gives you.
  Do not push.
- **Bugs:** if you find a bug that isn't a look-and-feel problem, list it with
  `file:line` and how it fails. Don't fix it.
- **Not checked:** say plainly what you could not see (hover, motion, the
  real panel) and what only the owner can judge by eye.

## 8. How to work

- **Look before you judge.** Open the PNGs. Don't review from code alone.
- **Cover every state.** The snapshot run has about 290 pictures; the
  simulator has hundreds of frames. A defect that shows in one state of
  forty still counts.
- **Split the work if it helps.** You may use agents, for example one per
  surface. Give each the rules in §2 and §3, and check their findings
  against the pictures yourself before they go in the document.
- **Measure, don't guess.** Give pixel values, contrast ratios and counts.
  Say when something is a judgement of taste.
- **If something fails to run** (the internal build, the board), write down
  what failed and carry on.

## 9. End with a recap

End your session with a short recap for the owner, who will read it with
little memory of this thread:

- what you did;
- the 3 worst problems;
- the 3 changes you'd make first;
- what you need from the owner.
