# Prompt: a holistic product review of Boop v1, and ideas to make it better

You are a senior product designer and engineer joining Boop for one long
session. Your job has three parts:

1. **Review the product as a whole**, as a buyer would live with it, against
   its four pillars. Find what works, what is weak, what is confusing and what is
   missing. Back every finding with evidence.
2. **Simplify.** Find the states, moods, concepts and tools that cost more than
   they give, and propose a smaller model of Boop.
3. **Propose many improvements**, from small polish to fundamental changes,
   ranked, with enough detail that an engineer could build each one.

Do not write product code in this session. Your output is one document (see
"What to deliver"). Be thorough and concrete. I prefer too much detail to too
little.

---

## 1. Where you are working

- Repository: `/Users/michaeljxzhu/src/buddygotchi` (GitHub:
  `Mellow-Machines-Lab/buddygotchi`).
- **Work in the worktree for the branch `v1-polish`:**
  `/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish`.
  Run every command from there. Do not `cd` to the repository root, and do not
  check out branches in the main checkout.
- How the branches relate:
  - `main` is the last release line (`b87a22c2`). Leave it alone.
  - `main-v2` holds Boop v1 (`c2b0e392`): XP kept simple, the popover's three
    tabs (Now, Boop, World), and the world of buddies.
  - **`v1-polish` is the branch we are working on.** It is `main-v2` plus a
    review-and-fix pass from 2026-11-09:
    - World fixes: asleep holds while locked, the retry and seq fix, the cheer
      window, gestures waiting during needs-you.
    - XP fixes: no level-up or ring lost over a quit, no ring played the next
      morning.
    - Popover fixes: the World tab's off, joining and stale states, your own
      dot, steadier gesture buttons, word fixes.
    - Board fixes: the ring's label inside the rounded corner, one sparkle,
      the heart, the bar sliding out at 5:00.
    - `boopctl run` stops when the board is face down.
  - Read `git log --oneline main-v2..v1-polish` and the top report in
    `plan/TODO.md` ("Report, 2026-11-09") first.
- The gel slime's pack (art, words, sounds, evals) is its own repository,
  checked out at `characters/.repos/SlimeBuddy` on its branch `main-v2`, with one
  local commit not pushed (`a1eea4a`, the ring's label). `characters/boop` links
  into it. Pixel's pack is at `characters/.repos/PixelBuddy`.
- **Nothing is pushed. Do not push, tag, merge or force anything.** Only the
  owner does that.
- First, in the worktree, run `git status` and `git log --oneline -12`, and
  check that `make -C internal build` works. If it does not, run
  `git submodule update --init && make -C internal packs`, then build again.

## 2. Rules you must keep

Read `CLAUDE.md` in full before anything else. It is the project's index and
its rules. In particular:

- **Never use Bluetooth from a shell.** Never launch the Boop app with
  Bluetooth, and never run `bleak`. macOS kills the process. For the board, use
  USB only (see §5).
- **Never touch `~/.claude`, `~/.codex`, or the everyday app's state**
  (`~/Library/Application Support/Boop`). Use a short temporary state folder
  under `/tmp` for anything you run.
- **No webcam** unless the owner asks.
- **Jev (the brain) costs money and has a daily limit.** No full eval run.
  `boopdev eval --scripted` and `--list` are free. If you need Jev at all, use
  `boopdev eval --only <name>` on a few scenarios, and say how many requests
  you used. Never read the Keychain or go looking for the key.
- **Board tests stay muted** (volume 0). The owner sleeps near the board.
- **Use the project's words.** The Words table in `CLAUDE.md` defines one word
  per concept: doing, mood, moment, voice, sign, narration, needs you, touch,
  poke, wish, notice, ring, level, and so on. Your document must use them, and
  must not use the words in the table's "Not" column.

## 3. What Boop is

Boop is a small desk creature with a personality of its own. It watches your
Claude Code and Codex agents. It grunts, huffs and says the odd word. It tells
you when an agent needs your approval on the Mac, and it celebrates work that
earns it. It never approves anything. A Mac menu-bar app does the thinking, and
an ESP32 board with a screen is the body. The production body is the Waveshare
ESP32-S3 2.06" AMOLED with touch, a motion sensor, a speaker and an SD card for
its voice. The default character is a blue gel slime, called "Boop" by default
and named by the buyer (often "Mochi" in our fixtures).

Boop shows three layers:
- **Doing:** what it is busy with (resting, working, asleep, listening, no app).
- **Mood:** one of 16 lasting moods.
- **Moment:** a beat on top, made by the board, the rules or Jev.

It speaks on three channels:
- **Voice:** recorded takes.
- **Sign:** a caption of at most 18 characters.
- **Narration:** the plain words for why.

The full model is in `documentation/architecture.html`.

## 4. The four pillars: the frame for your whole review

These come from `plan/v1-buddy.md` §1. **Organise your review and your ideas
by these four pillars.**

| | Pillar | The promise | How often you feel it |
| --- | --- | --- | --- |
| 1 | **Status monitor** | You always know what your agents are doing, at a glance, and it's fun to watch | Every few minutes |
| 2 | **Friend** | It greets you, notices you, and remembers small things | A few times a day |
| 3 | **A buddy that grows** | Your work and care earn XP; it closes a ring each day and climbs levels forever | Daily |
| 4 | **A world** | It lives among everyone's buddies, and together they reach goals | Daily to monthly |

Each pillar feeds the next: your work (1) and your care (2) earn XP (3), and
your XP adds to what the world achieves (4). Judge whether that chain is real
in the product today, or only on paper.

### The principles every idea must respect (`plan/v1-buddy.md` §2)

1. **Whole from day one.** A buddy at level 1 does everything useful. XP and the world only add moments, never features.
2. **No grind.** A full ring is the most a day can give. No streaks to lose.
3. **Nothing is ever lost.** XP and levels never go down.
4. **The small screen stays clear.** Nothing new lives on the board all the time. The Mac holds the detail.
5. **The world is cooperative.** No ranking or beating each other.
6. **Install and go.** No account, no friends to add.
7. **Privacy stays plain.** Never code, words, thread names or memory leave the Mac.
8. **Status outranks everything.** Needs-you and finishes are never hidden.

### The owner's ground rules (`plan/product-ideas.md`)

- Built for **buyers of a ready-made Boop**, not people who flash boards. **Nothing a buyer has to be taught.** The screen says what to do, or a touch does the obvious thing.
- **One buddy first.** Several buddies are for demos.
- **Everything on the buddy.** No phone pushes.
- **Nothing that keeps the Mac's mic on.** Push-to-talk on BOOT stays.
- **Nothing that routes or touches approvals.**
- **Steer Jev with guidelines, not long examples.** Keep reactions as data in the pack, so a rules brain could use them later.
- **The UI's words are short and warm**, like a friend, not a manual (`plan/world.md` §9).
- **Every feature lands with a demo and evals.**

You may propose an idea that breaks one of these rules, if you think it is worth it. Put it in its own section, "Ideas that bend a rule", say which rule it bends, and argue the case.

## 5. How to experience the product (do this, don't only read code)

Experience Boop the way a buyer would, as far as you can without Bluetooth. Use
each of these, and keep the evidence, such as PNG paths and log lines:

1. **The Mac app's screens:**
   `.build/debug/Boop --snapshots /tmp/boop-review/snaps`. This renders the
   popover's Now, Boop, World and Settings tabs, every onboarding act, and many
   states (needs you, offline, long names, world off, and more), in light and
   dark. **Open the PNGs and look at them.** Judge them as a buyer would: is it
   clear, warm, calm, and obvious what to do?
2. **The whole runtime with no UI:**
   `.build/debug/Boop --headless --state-dir /tmp/br --brain scripted --debug`.
   Then drive it with the demo scripts and real hook events
   (`internal/VERIFICATION.md` §2, `internal/sessions/README.md`). Read the
   debug log to see what Boop decided, and why.
3. **The board in a browser:** `make -C internal simulator`, then open
   `http://127.0.0.1:8206/`. Play the demos (`characters/DEMOS.md`,
   `simulator/tools/demos.py`) and the scenarios. The gel's scenario frames
   are written to `/tmp/boop-sim/...` by `make -C internal sim`. Look at the
   frames for the ring, level-up, finishes, needs you, the drawer, wishes,
   notices and world boops.
4. **The real board, over USB only:** the AMOLED is plugged in at
   `/dev/cu.usbmodem*`.
   - Check `internal/tools/boopctl board` says it is free, then run
     `internal/tools/boopctl ping`. The `sha` should start with this branch's
     firmware, and `ble` must not be `conn`. If the owner's app is connected,
     stop and say so.
   - `boopctl state` shows the live state. Make sure `face_down` is false.
   - `boopctl run <scenario>` plays a scenario on the panel. `boopctl shot`
     takes a screenshot.
   - Do not flash unless the board's `sha` differs from `v1-polish`'s HEAD
     (`make flash`). Note anything only a person at the panel can judge.
5. **The daily counts:** `.build/debug/Boop --counts --state-dir DIR`. Ask
   what we could learn from real use, and what is missing to measure each
   pillar.
6. **The evals as a spec of behaviour:** `boopdev eval --list` and
   `--scripted`. Read `internal/EVALS.md`. The scenarios tell you what Boop is
   meant to do in each situation.
7. **The world:** the server is in `internal/world` (`npm run dev`, port 8787).
   `internal/tools/world_e2e.py http://localhost:8787` runs two headless Boops
   that join, boop and leave. **Never use the live server.**

## 6. What to read (in this order)

1. `CLAUDE.md`: the index, the rules and the Words table.
2. `plan/TODO.md`: the 2026-11-09 and 2026-11-08 reports, then the earlier
   reports for what was measured and owed.
3. `plan/v1-buddy.md` and `plan/world.md`, §9 especially: the v1 plan and the
   owner's decisions.
4. `plan/product-ideas.md`: the running list of ideas, with Built, Next,
   Decided, Maybe, Wild, Later and No. **Don't propose again what is under No
   without a new argument. Build on Maybe and Wild where you agree.**
5. `documentation/architecture.html`: the model, one turn through every piece,
   and the rules.
6. `characters/CHARACTER.md` and the gel pack's steering
   (`characters/boop/steering/`: `personality.md`, `signs.md`, `asks.md`,
   `replies.md`, `dreams.md`, `mood/`): who Boop is, and what it can say.
7. `plan/alive-and-noticing.md`, `plan/memory-writer.md`,
   `plan/voice-range.md`: earlier pillar-2 work.
8. The code, where you need evidence. Key places:
   - The Mac UI: `app/Boop/Views/`.
   - The core's rules: `app/BoopKit/Core/`.
   - What plays: `app/BoopKit/Outputs/`.
   - XP: `app/BoopKit/Core/Growth.swift`, `app/BoopKit/Memory/GrowthStore.swift`.
   - The world: `app/BoopKit/World/`.
   - The board: `firmware/src/app/`, and the gel's renderer in the pack's
     `character/firmware/src/render/gel/`.

## 7. How to review

### 7.1 Walk through a buyer's life with Boop

Write each of these as a short scene: what the buyer sees and hears, on the
board and on the Mac, minute by minute where it matters. Mark each moment as
delight, fine, flat, confusing or broken, and say why.

1. Unboxing and onboarding: first launch, naming, the body, the world screen.
2. The first hour of real work with one agent.
3. A busy workday: several agents, needs-you, failures, a long turn, a push.
4. Stepping away: lock, coming back, lunch, the end of the day.
5. The next morning: the greeting, the dream, the remembered line.
6. A week in: XP, levels, the 7-day rings, what Boop seems to know about you.
7. A month in: is there still anything new? What makes them keep it on the desk?
8. A quiet day with no agents: does Boop still earn its place?

### 7.2 Score each pillar

For each of the four pillars, give:
- **A score from 1 to 5**, and one sentence why.
- **What delivers the promise today**, with evidence: file:line, a PNG path,
  a log line, or an eval name.
- **Where the promise breaks or is weak**, ranked by how much a buyer would
  feel it.
- **The question the buyer can't answer**, for example "why did it do that?",
  "what do I do now?" or "what's the ring for?".
- **What we can't know without real use**, and which daily count, or new count,
  would tell us.

Also judge the **seams between pillars**:
- Does work really feel like it feeds growth?
- Does care feel like it counts?
- Does the world feel like it holds the other three together?
- Does the order of what plays (status first) still hold with world moments
  added?

### 7.3 Check the fundamentals

- **Clarity at a glance:** can a buyer read the board in one second from arm's length?
- **Feel:** frame rate on the board, latency of a touch, how long moments last, repetition.
- **Personality:** is Boop's cheek consistent? Does it repeat itself? Is it too quiet or too loud? (`plan/TODO.md` notes that idle may be too quiet, and that notices may be too faint.)
- **Words:** every UI string and sign. Are they warm and short, and do they use the project's words?
- **Trust:** privacy, what the world sees, and how plain consent is.
- **First-run risk:** what could make a buyer return it in the first week?

## 8. How to generate ideas

Aim for **at least 12 ideas per pillar (48 or more in all)**, plus **at least 8
that cross pillars**. Push past the obvious: draw on games, pets, tamagotchis,
fitness rings, Duolingo, Animal Crossing, Finch, desk toys, and ambient
displays. Then filter hard.

For **every** idea, give these fields:

- **Name**: short.
- **Pillar(s).**
- **The moment**: when it happens, and what triggers it.
- **What the buyer sees and hears**: on the board (Doing, Mood, Moment; voice,
  sign, narration) and on the Mac. Be specific: the words on the sign (18
  characters or fewer), the face, how long it lasts.
- **Why it matters**: which promise it strengthens, or which weakness it fixes.
- **Principles and rules**: which it honours, and any it strains.
- **Where it lives**: board firmware, the pack (art, steering, voice), the Mac
  app, the core's rules, Jev, or the world server. Name the files you'd touch.
- **Size**: S (under a day), M (a few days), L (a week or more).
- **How we'd know it works**: the demo, the evals or tests, and the daily count
  to watch.
- **Risk**: noise, nagging, privacy, frame cost, or teaching the buyer.

Give a **confidence** for each: high, medium or low.

## 9. Simplify: what costs more than it gives

The owner says the product has **too many states and moods**. They add
complexity for him to hold in his head, and he isn't sure they add value. The
Character Studio is also very large. Treat simplification as seriously as new
ideas: a smaller Boop that feels the same, or better, is a win.

### 9.1 Make an inventory, with numbers

Count every concept a person (the owner, a pack author or a buyer) has to
understand. For each one, say how many values it has, where it is defined,
and how many lines of code, art and tests it costs. At least:

- **Doing:** resting, working, asleep, listening, no app.
- **Activities:** testing, delegating, terminal, searching, analysing, a tool,
  waiting, planning.
- **Tiers:** tier 1 to 5 by time in a look.
- **Pastimes:** 39 for the gel (`render/gel/pastimes.h`), with the **kit** and
  the **dressing**.
- **Moods:** the 16 lasting moods (`CharacterPack.Mood.lasting`,
  `steering/mood/`), their neighbours, jumps and fades.
- **Emotions:** a Moment's 42 faces.
- **Sizes:** small, medium, big, huge.
- **Moments' kinds:** finishes, greetings, waves, replies, asks, wishes,
  notices, musings, the telling, the day's greeting, work acts, the work
  stream, level-ups, the ring, world gestures.
- **Talk:** quiet, normal, chatty, and the hush.
- **Touches:** poke, stroke, lean, ruffle, nose boop, tickle, swipe, shake,
  pick-up, put-down, thump, peekaboo, face down.
- **Memory:** the transcript, daily counts, digests, the written memory,
  remembered lines, dreams.
- **Growth:** XP, the ring, levels, sizes.
- **The world.**
- **Tags, special days, variations.**
- **The Character Studio** (`characters/studio/`):
  - What each view is for, and who uses it.
  - What a new character really needs from it.
  - Note: `packs.js` is about 118,000 generated lines. The hand-written part is
    about 3,000 lines. Check this.
- **`charactergen.py`, the pack contract** (`characters/CHARACTER.md`), and
  **`new-character-playbook.md`**: what it costs to make a new character.

### 9.2 Measure what each concept is worth

Use evidence, not taste:
- How often each mood, emotion, pastime, tier and Moment kind actually
  happens. Use the eval trajectories (`boopdev eval --scripted`), the demo
  recordings (`characters/boop/demo/recordings/`), and any debug logs.
- Whether a buyer could tell two of them apart on the panel, at arm's length.
  Put frames side by side, from the simulator or `--snapshots`.
- Whether the brain uses it well. Read the eval judge's notes in
  `plan/TODO.md` for the moods it gets wrong.

### 9.3 Propose a simpler model

For each concept, recommend one of these, with the reason and the evidence:
- **keep**;
- **merge** (into what);
- **cut**;
- **make it data** (move it out of code, into the pack).

Then propose **one simpler model of Boop as a whole**. For example: how few
moods, faces and Doing states could carry the same personality? Show it as a
table: today's concepts on the left, the new ones on the right. Estimate what
it deletes: lines of code, art, steering, evals and tests. Also say what it
risks: the feel lost, the evals to redo, and the work in the packs.

Read the earlier audit before you start. It is on the branch `plan-simplify`:
`git show plan-simplify:plan/simplify-behavior.md`. The owner's calls from it
are in `plan/product-ideas.md` under "Decided (2026-11-01)": he kept 16 lasting
moods, several buddies, the CYD board and real-agent demos. **He now asks again.**
So you may argue against those calls, with new evidence.

Give a separate plan for the **Character Studio**. What is its smallest
useful form? What could be a script instead of a page? What could go?

## 10. Fundamental changes: rethink the product

Beyond polish and new features, propose **3 to 5 fundamental changes**. Each
one changes what Boop is, how it works, or who it is for. Possible directions,
but don't stop at these:

- **A smaller core.** Boop as a status monitor with a soul: far fewer states,
  a sharper personality, and much less code.
- **A different brain.** A rules brain built from the evals, so no Jev key is
  needed. Or Jev only for rare, big moments. Think about the cost, the latency
  and how a buyer sets it up.
- **A different loop.** What brings a buyer back each day? Growth, the world,
  care, or something new such as collecting, rituals, or a shared desk.
- **A different relationship.** Boop as a coworker who comments on your work,
  as a pet you care for, or as a mirror of your day. Which one is the product?
- **A different body or surface.** What if the Mac's face were the main
  product, and the board an add-on? Or the reverse?
- **What to stop doing.** For example: the second character, the CYD board,
  the world, or the voice bank.

For each fundamental change, give:
- the one-line thesis;
- what the buyer's day looks like after it;
- what it deletes and what it adds;
- its effect on each of the four pillars;
- the biggest risk, and the cheapest experiment to test it in a week;
- your recommendation: do it, test it, or don't.

## 11. Then decide

1. **Top 10**, ranked by the buyer's delight per unit of effort, with one
   paragraph each on why it beats the next.
2. **Quick wins**: polish that's S-sized and ready now. List file paths and
   the exact change, such as strings, timings or thresholds.
3. **A two-week plan** for the Top 10, in order, each step shippable alone.
   For each step, say what the owner must check by eye on the panel.
4. **The Top 10 must mix the kinds:** at least 3 simplifications from §9 and
   at least 1 step towards a fundamental change from §10, if you recommend one.
5. **Open questions for the owner**: the decisions only they can make, each
   with your recommendation.

## 12. What to deliver

- **One file:** `plan/product-review.md` in the `v1-polish` worktree.
- Sections, in this order: Summary (a page at most); The buyer's life (§7.1);
  The four pillars, scored (§7.2); The fundamentals (§7.3); Ideas, by pillar
  (§8); Ideas across pillars; Ideas that bend a rule; Simplify (§9: the
  inventory, what each is worth, the simpler model, the Studio); Fundamental
  changes (§10); Top 10; Quick wins; A two-week plan; Open questions; Evidence
  index (every PNG,
  log and command you used).
- Put "Updated <date>" under the title, as the other plan files do.
- **Writing style:** about 80% of the way to ASD-STE100 Simplified Technical
  English:
  - Short sentences, one idea each.
  - Active voice, common words, one word for one meaning.
  - Keep the technical words of the subject.
  - Tables where they help.
- Commit only that file on `v1-polish`, with a plain message that ends
  `Co-Authored-By: <your model> <noreply@anthropic.com>`. **Do not push.**
- Do not change any code, steering, art or tests. If you find a bug, list it in
  the review with file:line and how it fails. Don't fix it.
- End your session with a short recap for the owner: what you did, the three
  findings that matter most, the biggest simplification, the top 3 ideas, and what you need from them.
  They will read it with little memory of this thread, so keep it to a few
  short lines.

## 13. Take your time

This is a long task. Read before you judge. Look at the screens before you
comment on them. When a claim depends on behaviour, run it and cite what you
saw. Say plainly when something is a guess. If the board, the simulator or a
build fails, write down what failed and carry on with the rest. Don't stop.
