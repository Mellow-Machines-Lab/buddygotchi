# TODO

Updated 2026-11-02. What's next, one at a time, top first. Tick an item
in the commit that finishes it, and say there what checked it. Ideas
that aren't decided yet stay in [product-ideas.md](product-ideas.md).

## Morning report, the night of 2026-11-01

Frames, verdicts and logs are on the owner's Mac in `~/.boopdev/night-2026-11-01/`.

**Landed:** the eval levels and daily limit; must and feel evals with a judge; the prompt cut to level A; the rest of the wish; every lock and unlock reaching Jev; idle check-ins with no agents; no plug on a Boop already asleep; any brief touch on a finish opens its thread; the finish's low sign; the falling word and three work acts; the memory pane; alive without the Mac.

**Not landed:** growth. It's on branch `growth`, with its pack commits in the clones under `.claude/worktrees/growth`: keep that worktree. The core and body work are done and tested with no board. It predates the cleanup and review fixes, and it changes existing users' stages (Chonk starts at 5,000, and the old saved stage is ignored). Look at `frames-growth/` and try it on the board first.

**The prompt: level A, about 4,800 tokens, down from about 6,800.** Tags `prompt-level-A`, `-B` and `-C` keep the others.

| Level | Tokens | Musts | Judge: reasonable, odd, unreasonable | Mood moves | Passes with a moment |
| --- | --- | --- | --- | --- | --- |
| A | 4,800 | 18/18 | 67, 15, 9 | 235 | 85% |
| B | 3,140 | 10/18 | 64, 17, 10 | 149 | 84% |
| C | 2,100 | 8/18 | 50, 26, 15 | 144 | 68% |

A is the only level that holds the musts, and it keeps moods fluid. B's judged feel is close to A's, so B's musts are the question if the prompt must go lower: they mostly failed on replies, hush and Talk. At C, pokes made Boop happier and strokes stopped lifting its mood. No must rule was moved into code.

**Evals on what landed:** the musts on the final tree are 17/18. `129` (hush) fails twice: the hush it picks is too small. Standard wasn't re-run after the prompt cut's run, so feel isn't judged on the final tree. On level A, the judge's re-run confirmed 7 unreasonable: `11`, `19`, `47`, `90`, `91`, `96`, `140`: special days are flat, and quick wins repeat. The judge passed its test, 10 of 10, on deliberately obvious made-up runs only. The feel briefs were written by an agent and not read one by one. `27` moved to must by my call.

**Wishes:** no cap in code, as the owner said. A guideline alone gave no wish; one added line in the sign question gave one, in one Chatty run, at 39 min. Normal talk is unmeasured.

**Jev requests:** 2,336 on Nov 1 and 283 on Nov 2 by the limit's count, which began partway through Nov 1 (before it, one full run of about 1,000 isn't counted).

**Flag for the owner:** `make eval` is refused without `BOOP_JEV_OVER_LIMIT=1`, so the bare command never runs. That's what was asked, but it's a surprise: `boopdev eval --level standard` is the merge check.

**Choices to overrule if you disagree:** a ruffle also meets a pet wish. A wish may come while Boop is asleep only for having no agents. The plug no longer stays up after a touch: Boop sleeps again after 5 minutes. Chat is offered only once push-to-talk works. Jev rarely speaks over an act from a calm mood, and I didn't push it.

## Now: the simplify branch, on the board (2026-11-01)

What the `simplify` branches change on the board, for the owner to look
at after `make flash` and a new voice on the card (the report of
2026-11-01 has each step):
- [ ] A stopped or failed turn shows no card; a helper coming back plays nothing.
- [ ] Pastimes still come by tier; a yawn or sneeze from `tier1`; busy typing still speeds up.
- [ ] Free heap at boot is about 76.8 KB higher than before.
- [ ] The voice plays once the card has the new `voice.bin` (`353ddadc006b`).

## Owed on the board, from the night of 2026-11-01

From the plans that were finished and deleted, for the owner, after
`make flash`:
- [ ] Work acts: the look and the frame rate of the push, the tests and the build, full and small.
- [ ] A finish's low sign: can you read the thread's name at arm's length, and does a cheer still read?
- [ ] A tap on a finish: the face, the rim and the strip during a finish each open the thread.
- [ ] A lock and an unlock: a wave, a snub or the nap; a Boop asleep when the Mac goes quiet stays asleep with no plug until you touch it.
- [ ] Alive without the Mac: it breathes, sleeps, answers a poke or a stroke in its last mood, and gives a small hello when the Mac returns.
- [ ] The wish's bubble: its place beside the head, its how, the heart popping; none during a full act or with no Mac.

## Now: from the night's review (2026-11-02)

- [ ] A dream's write can be lost if the writer fails (`Memory.swift`, `dream()`).
- [ ] Several buddies don't replay an away (`Pipeline.readBack`).
- [ ] The Pixel wish's text (`screens.h:48`, `sameModel`).
- [ ] A `Measure` around `paintActFront`, for the board's frame rate check.
- [ ] **For the owner:** `make eval` refuses without the override, so your bare command never runs.
- [ ] Stale `ReactOutput` mentions in SlimeBuddy's asks' and replies' comments.
- [ ] Remove the dead lost-link path.
- [ ] Acts: wall caching and a frame cap.
- [ ] Unify the acts' timing.
- [ ] The idle `tower` pastime is hard to read.
- [ ] The takes "We pushing!", "shipped!" and "built it!" aren't recorded: until then Jev has the voice's existing words.
- [ ] Jev rarely speaks over an act from a calm mood.
- [ ] The duplicated memory cards on the Overview ("What Boop remembers", "Recently") and the Memory pane: whether they move is the owner's call.
- [ ] Eval Level A's 7 confirmed unreasonable runs: 11, 19, 47, 90, 91, 96, 140.
- [ ] No standard eval run since items 2 to 10 of the night.
- [ ] Pixel Bro's clone fails `boopdev check`: `personality.md` is missing.
- [ ] A chat wish already open when you take back the mic's authorization still waits and can give up: nothing rechecks it.
- [ ] A wish can give up while you're idle, before the away is noticed: the away takes back the wait, but not a give-up already played.
- [ ] A wish's wait read back on launch counts time a needs-you or a doze held, and time Boop wasn't running between two events of the same day: the transcript has no launch marker, and the wait isn't recorded until its end.

## Now: left by the finished plans (2026-11-01)

- [ ] **The care lean.** A cuddly "You and Boop" note still leaves a
      poke from calm curious (eval 149, 3 of 3); the lever left is a
      sentence in `calm.md` letting its fade follow the note.
- [ ] **Lonely on the AMOLED:** look at the lonely idle, the lonely
      wake-up and a stroke ending it; add a reunion clip (Boop perking
      up toward you) if the look falls flat.
- [ ] **The work stream's replay check:** the owner's 229-call session
      as a fixture through `Boop --headless --brain scripted` to the
      simulator: words reach `state.calls`, at most 4 states a second,
      none of the first rank dropped but by ttl, and the brain's passes
      the same with the stream on and off.
- [ ] **Pixel's copy of the voice** still has the 164 `attention` takes
      the gel's lost (SlimeBuddy's voicegen leaves them out now): copy the
      new `voice.bin` and `takes.tsv` over, then drop `Take.Part.attention`.
- [ ] **Eval 09** fails 1 run in 3 (accepted for now); 14 and 98 are
      known gaps (internal/EVALS.md).

## Now: Pixel Bro, the third character (2026-10-26)

Pixel Bro is in [PixelBro](https://github.com/Mellow-Machines-Lab/PixelBro):
Pixel's face on the AMOLED with a new soul. Making him showed what makes a
new character slow; [new-character-playbook.md](../characters/new-character-playbook.md)
has the playbook and the fixes to pick from.

- [ ] Pick which of the playbook's fixes to build first (a scaffold,
      a shared voicegen and the pack-generic voice checks would have
      saved the most).
- [ ] CHARACTER.md §14 still says to copy a pack into the engine's
      `characters/`; rewrite it for packs in repositories of their own.

## Now: the QA night, as users (2026-10-26)

The owner asked for a night of using Boop as users would. Seven testers
played profiles on the simulated board through the headless app: a
first-week buyer with no key, a multi-agent power user, a talker with
the real brain, the clock and calendar, the Mac app's surfaces, a real
workday with the brain, and odd inputs with restarts. What they found
and is fixed is in the night's commits here and SlimeBuddy's; what's
left is below.

- [ ] The mood after a win: calm goes to annoyed at your frustration
      (`mood/calm.md`), where annoyed itself says frustration means
      determined, and annoyed has no way out at a check passing or a
      turn done but a 3-minute fade, so Boop frowns through a success.
      Suggested: calm to determined at frustration; annoyed and irritated
      to relieved when a check passes after failing. Needs the moods'
      `moves` (the design's emotion graph) and Jev's mood evals.
- [ ] Voice: quick, easy wins can say relief ("Phew", "Whew"), tagged
      plain `glad`; some takes' meanings read wrong where they play
      ("Yep" as tickled at a poke, "Failed" as upset, "Search" at a
      compaction, "Restart" as retry, "Mwahaha" for a typo fix). The
      bank's tags (voice-range).
- [ ] Steering: `boop.md` says an idle check-in gets "a small face or
      nothing" but its Example gives medium; an approval's Example
      cheers ("pleased, says glad"), which on a day of approvals is
      noise and requests.
- [ ] A request restored at relaunch whose answer came while the app
      was down stays amber up to a day (the agent's process lives on);
      and each relaunch numbers requests afresh, so the board knocks
      again for one already seen. Both in AgentHooks' session tracking.
- [ ] With four lanes, a long word in an outer lane is cut by the panel's
      edge; moving it in puts it over the next lane and behind the body.
      A smaller font, or a shorter word, at three and four lanes.
- [ ] A demo's `wait` that jumps the clock while a reaction plays ends
      it as "didn't happen" in HISTORY.

## Now: the overnight UI audit (2026-10-26)

The owner asked for every UI and UX bug on the Mac and the board,
fixed overnight. Four reviews (the popover, onboarding, the board's
drawing, its touch and sound) found them; what's fixed is in the audit's
commit here and SlimeBuddy's.

- [ ] On the AMOLED: none of it is played on the board yet. It stopped
      answering over USB (not even its bootloader), so unplug it and
      plug it back in, flash, and feel the drawer, the needs-you hold,
      a rub, and carrying it (the put-down's new steadiness, 40 mg for
      1.5 s, is a first guess to tune).
- [ ] The strip comes back at once after a bubble: its fade belongs in
      `Behaviour::strip` (when the bubble ended), not the face.
- [ ] Decide: the popover's mic button says "Talk", which the Words
      table keeps for the talk level; and an agent's first hook after
      Connect counts as the hello even from a session already open.

## Now: calm work (2026-10-25)

The owner found the working look's body boring and its kit cluttered,
and chose a calm look that works harder the longer the agents do, with
the whole body moving now and then (the calm-work plan (in git: `plan/calm-work.md`)).

- [ ] On the AMOLED: how the moves and the typing feel, by the owner.

## Now: talking back (2026-10-25)

The owner wanted the buddy to understand what's said to it, a smart pet
rather than a conversation (the talk-back plan (in git: `plan/talk-back.md`)).

- [ ] On the real AMOLED: whether each reply's clip reads as meant, a
      nod, a shake of the head, a shrug and the rest
      (`make demo NAME=talk-back FACE=gel` plays them in the simulator).

## Now: four questions, and talking back, part two (2026-10-25)

Every reaction asks the same four things, and talk covers what it
didn't (the talk-back plan (in git: `plan/talk-back.md`), Part two).

- [ ] On the real AMOLED: the zipped mouth while hushed.
- [ ] On the real AMOLED: the new clips, and the nap and dance on
      request.

## Now: the polish pass (2026-10-25)

The owner asked for smoother animation, crisper pictures, quicker touch
and a simpler build. Four audits (the gel's picture, the board's frame
pacing and touch, the Mac app, the architecture) found what's below.

- [ ] On a real Mac: the popover opens quickly and never shows a stale
      pose; the 46 pt slime is crisp at 60 fps; with Bluetooth off it
      stays the slime; onboarding's acts show no black glass; two quick
      confetti bursts both play; the menu-bar glyph looks centred.
- [ ] On the real board: whether the hat and the falling words now look
      smooth asleep and at work, and whether words entering behind the
      panel's top corners (110 px radius) look like they come from above
      or look cut off.
- [ ] No tearing sync. The CO5300's TE line is wired to GPIO 13 (a
      probe counted 12 rising edges in 200 ms: 60 Hz; LovyanGFX's init
      already sends TE on). Syncing isn't simple: a push writes bands of
      16 panel columns each across the whole scan, so it crosses the
      scan line ~26 times a frame, and at 40 MHz the writer (~15-20 panel
      rows a ms, preempted by the body's helper) is about half the scan's
      speed (30 rows a ms). Tear-free needs pushes in scan order (bands of
      panel rows) started just behind the scan line, the scan's direction
      checked on the panel; or 80 MHz QSPI (needs eyes on the panel).
      Tried 2026-10-26 (branch `tearing-scan-order`, not merged): bands of
      16 panel rows sent in scan order, each band's changed rows as up to
      four runs, from TE's rising edge (`dbg.scan off|down|up`), with a tear
      counted when the scan, timed from TE, passes a band as it's sent.
      `perf --scenes`: 26% of frames counted torn unsynced, 26-29% synced
      (either direction), the push 3-4 ms longer and attention under its
      28 fps. A push takes 22-38 ms for 60-130 K pixels, far below the
      bus's 10 px/µs: it waits on the body's helper (priority 2, above the
      push's 1) and packing, so it can't stay ahead of the scan. Raising
      the push above the helper while a synced frame goes made it worse
      (34% torn; working 33.7 -> 30.2 fps, night 22.7 -> 20.2), and even
      unpreempted a push of 65 K pixels took ~20 ms. A push's time is its
      wall time on core 0, under the body's helper since the pass added
      it (60 K pixels took ~7.5 ms before; the material read from flash
      instead of PSRAM leaves it at ~25 ms, so that isn't it). The loop
      waits on it only 0.1-1 ms a frame, but a synced frame can't stay
      ahead of the scan while the helper shares the core: a tear-free
      push wants core 0 to itself for ~8 ms, which the body's split
      can't give without slowing every frame.
- [ ] The engine's step is 2.3-2.6 ms a frame on the AMOLED (2.5 µs on
      the Mac): its 25 KB `Engine` is in PSRAM (malloc puts anything over
      4 KB there) and its code runs from flash past a 16 KB cache. The
      other core can't hide much of it (looked at 2026-10-26, natively):
      a frame takes 2.6-3 steps (the 16 ms grid and the pass's own time),
      and only the first, about 38% of them, depends on nothing that
      arrives during the pass (messages, the finger, `sync`'s occasion and
      held expression, a landing word); `Engine::step` is 59% of
      `engine_us`, the face's work after it the rest. Stepping a copy
      ahead on the other core would hide at most ~0.55 ms a frame, likely
      0.2-0.5 with the shared caches and bus, for a second 25 KB engine
      copied each frame and a guard on everything that changes it. The
      lever is the step itself: fewer of them a frame, or less code
      (about 45 KB at -Os, fetched from flash each step).
- [ ] The board's frame rate, all of the above merged (01ee9a01,
      `perf --scenes`, 12 s a scene, muted; before is the pass's start,
      008e5e7d): asleep 45.3 → 42.4 fps, working 38.4 → 37.0, pokes
      38.2 → 36.8, attention 34.0 → 32.7, frightened 31.3 → 31.9; the
      new stream scene 31.2 and night 24.4. The sharper material and the
      outline cost ~1 ms of body, the hat's sub-pixel replay ~3.5 ms at
      night. Every scene passes; the internal heap's least is 50,968
      against 50,000, so ~1 KB is left (by bebdb5a7 it was 48.2 KB, every
      scene failing; SlimeBuddy's 09fb042 puts the outfit's recordings in
      PSRAM: 66.4 KB, every scene passing, fps unchanged). Owner's call: whether night's
      24 fps is enough for a smooth hat (whole-pixel replay gives ~28),
      and whether an even 30 fps reads better than ~37 on the 60 Hz
      panel. `perf --motion`'s 60 KB heap budget fails, as it already did
      at 008e5e7d (51.5 KB): the budget or the heap wants a look.

## Now: the character engine

The plan is the character-engine plan (in git: `plan/character-engine.md`): one rig, mixer and
layer stack for both faces, packs as data agents edit, references turned
into clips, and the Studio as the dashboard. Each checkpoint lands
reviewed, simplified and merged. Measure fluidity with
`internal/tools/fluid/` (baseline 2026-10-23, gel: a mood change's
largest frame 32x its median, a finish's 33x, going to work 9x).

**The CYD is frozen** (the owner, 2026-10-24): it keeps building and
gets no new features; new work is the AMOLED board's, on the gel's own
engine and its rig (checkpoint 5), starting with
the work-stream plan (in git: `plan/work-stream.md`). Pixel's rig face on the board waits
with it.

- [ ] **The gel on the rig on the board**: its frame cost on the AMOLED
      with a hat, asleep at night and at `tier5`, its pastimes and kit
      out (`boopctl perf --scenes`), and a look at the stretch, the
      layers' fades, the notice and the pastimes.
- [ ] **6. Retire what the engine replaces.**

## Now: something new at every glance

The tiers' art, from the glance-and-wait plan (in git: `plan/glance-and-wait.md`) §3, redone
with the owner on 2026-10-25: five tiers, closer together, and something
to see at each.

- [ ] **The pastimes on the board**: a look on the AMOLED, and their
      frame cost there with the kit and a pastime out (`boopctl perf
      --scenes`); tune their timing and art.

## On a real Mac, later

The owner's checks, when they're at the desk: what only a real Mac
session, Bluetooth and the boards can show.

- [ ] The exact terminal tab: a tap on the board brings forward the tab
      the agent runs in, in iTerm2 and in Terminal, with macOS's
      Automation prompt the first time.
- [ ] 2026-10-24's setup fixes on a real launch: act 5's talk lesson
      ticking with what the Mac heard, act 6's plain words, act 7 without
      the mic card once act 5 had it allowed, the Dock icon while setup
      shows, and the found board holding up "Tap me!".
- [ ] Onboarding's window coming forward over the terminal at the
      agent's hello in act 6.
- [ ] Act 6's tour on the AMOLED, with a fresh Claude Code session
      asked to list its files: the words fall on the board and in the
      window, Boop cheers once the turn ends and a tap on it opens the
      thread, the drawer swiped up and its row tapped opens it again, the
      window comes back after each, and Next unlocks only then. Act 2's
      FAIL rain on the window's Boop.
- [ ] Reopening Boop.app while it runs brings its window or popover.
- [ ] "I don't have my Boop yet" remembers no board.
- [ ] In act 5, BOOT ticks only the button's lesson.
- [ ] An update with both boards plugged in: a refusal for the wrong
      board, the chip's image, a restart after a cut-off write. It needs
      a board on older firmware than the app carries.
- [ ] Opening an agent's tab from the bundled app (the Automation
      prompt).
- [ ] `make dev FRESH=1` keeping its own Keychain entry and leaving no
      socket behind.
- [ ] An SD card for the CYD's voice (`boop/voice.bin`); the CYD isn't
      a priority.

## Later

- [ ] Apologies don't soften a grumpy Boop's mood against Jev: 56
      (one apology softens it) passes 0 or 1 of 3 and 57 (undone by
      poking) 0 of 3, before and after 2026-10-24's grumpy wording. The
      face is right (annoyed); the mood question gives grumpy 0.61,
      irritated 0.27, annoyed 0.12: the stay option ("hasn't been grumpy as
      long as MOOD says it lasts. No change is fine.") outweighs grumpy's
      "a sorry cools it at once". A full Jev run of every scenario (about
      820 requests) would show what else sits outside the always set.
- [ ] The gel's lane scales with its panel (lane.cpp's fonts, margins
      and bubble are fixed px), then the Mac mirror renders at the
      tile's size (about 20× fewer pixels). Drawn at the popover tile's
      113 × 92 (2026-10-24, the simulator's `BOOP_SIM_NATIVE`), the
      slime, desk and needs-you plate scale, but the lane's text, dots
      and sign come out several times too big and run off the panel.

## The five repositories: a recommendation (investigated 2026-11-01, nothing changed)

**How it is.** The engine fetches the packs it's tested with from
`characters/packs.json`, at each pack's `main`, into `characters/.repos/`.
Each pack in turn pins the engine as `engine/`, a submodule, and its
`Makefile` runs every target through it (`make setup` links the pack in
and chooses it). A pack's CI checks it against its pinned engine; the
engine's checks run against the packs' `main`. A change that spans both
lands pack first (or the engine's checks fail), but the pack's CI runs
against the old pin until the engine is pushed and bumped: each such
change is three commits in two repositories, and for a while one side's
checks are red. The gel's engine (`render/gel/`) is the pack's own C++,
so most slime work is exactly such a change.

**Can the packs drop `engine/`?** Who builds a pack on its own: its CI,
and a contributor who clones only SlimeBuddy or PixelBuddy and runs
`make flash` or `make dev`. Buyers never do: they get Boop.app with its
packs inside. Both need *an* engine at a known commit, not a submodule.
Recommendation: yes, replace the submodule with a pinned commit in the
pack (`character.json`'s `engine`, or one line in `Makefile`) that
`make setup` clones into an ignored `.engine/`. The same reproducibility,
no gitlink to bump by hand, no nested submodules (the engine's own two)
inside a submodule, and a pack clone needs no `--recurse-submodules`.

**What would make cross-repo changes lighter**, in order of payoff:
1. *Bring the two first-party packs back in as folders* (`characters/boop`,
   `characters/pixel`): one commit per change, one CI, no bump dance.
   Keep SlimeBuddy and PixelBuddy as their public faces, published from
   those folders by `git subtree split` on release. Pixel Bro and any
   third-party pack stay outside, on a pinned engine. This undoes the
   split of 2026-10-26, so it's the owner's call; it's the only option
   that removes the problem rather than easing it.
2. Short of that, *pin the packs in the engine too*: `packs.json` names
   each pack's commit, not `main`, and `packs.py --bump` moves them. The
   engine's checks are then reproducible, and a cross-repo change is:
   the pack's branch pushed, the engine's commit pinning it, the pack's
   pin moved by a script, with neither side red in between.
3. A `boopctl` command that starts one branch name in the engine and
   both packs, runs `make -C internal check` across them, and prints the
   pushes in order (package, engine, packs), so the order is a tool's,
   not a person's memory.
