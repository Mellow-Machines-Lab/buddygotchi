# TODO

Updated 2026-11-16. What's next, one at a time, top first. Tick an item
in the commit that finishes it, and say there what checked it. Ideas
that aren't decided yet stay in [product-ideas.md](product-ideas.md).

The reports of built work (2026-10-24 to 2026-11-16) left this file on
2026-11-25: read them with `git show e9772173:plan/TODO.md`.

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
- [ ] An update of the board: the chip's image, a restart after a cut-off
      write. It needs a board on older firmware than the app carries.
- [ ] Opening an agent's tab from the bundled app (the Automation
      prompt).
- [ ] `make dev FRESH=1` keeping its own Keychain entry and leaving no
      socket behind.

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

# The last pieces (from TODOs.md, merged 2026-11-25)

## Decided on 2026-11-09

- **The buyer does not need a key.** How Boop thinks with no key stays
  unsolved until the best behaviour is found. Until then Jev is how we find
  it.
- **XP amounts may change.**
- **Any earlier call may be reopened**, the calls of 2026-11-01 included
  (fades, the move, several buddies, the CYD, onboarding's acts).
- **Boop is a coworker and a pet, about equally.** The rest of the owner's
  answers, and the phases before these two pieces, are in [TODO.md](TODO.md).

## At the end

- [ ] **A brain in the box.** Boop's whole personality with no key: a rules
      brain built from the recorded Jev runs, with Jev as a switch at most
      (`product-review.md` (removed, in git history) §9.1). It waits for the
      behaviour to be right first, since the table is built from it. Each
      cut to the model before then makes it smaller: 7 moods against 16,
      18 emotions against 42, no `move` or `size` question (§8.3).
- [ ] **The voice.** One register across the voice, the signs and the code's
      strings; the 437 espeak placeholder takes; the label words ("Verify",
      "Probe"); the `say` kinds nothing picks; and whether takes are
      recorded or made (`product-review.md` (removed, in git history) §4.3, §8.2,
      idea X6). It waits for the same
      reason: the words to record follow from what Boop does.
