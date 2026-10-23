# TODO

Updated 2026-10-22. What's next, one at a time, top first. Tick an item
in the commit that finishes it, and say there what checked it. Ideas
that aren't decided yet stay in [product-ideas.md](product-ideas.md).

## Now: the prompt, read on the Mac

The plan: your prompt is scrubbed of secrets and read by Apple
Intelligence on the Mac; Jev gets only the reading (a kind, a tone, a
length, whether you named the buddy, and up to three short phrases of
yours), and the transcript keeps no prompt text. Boop reacts to it with
the board's new layers: a sign with words, outfits by the time of day,
and new actions. One personality (Boop's default nature) for now.

- [ ] **Scrubber.** `app/BoopKit/Prompt/Scrubber.swift`: one table of
      secret patterns (API keys, tokens, JWTs, long hex and base64,
      `KEY=value`, URLs with tokens, emails), each `[secret]`, pinned by a
      fixture of fake keys.
- [ ] **The reading and its readers.** `PromptReading` (closed lists for
      kind and tone; length band; named; phrases), `PromptReader`,
      `AppleIntelligenceReader` (FoundationModels, a dynamic schema, an
      availability check, a timeout) and `CountingReader` (length and
      name only: the fallback, and the tests').
- [ ] **The intake.** `PromptIntake` between `Runtime.hook` and the
      pipeline: scrub, strip the prompt from the event, read, then
      `Pipeline.promptRead`. The reading's event wakes the brain; the turn
      start no longer does. The view's line for it; the turn start's
      `You asked` note goes. CLAUDE.md's rule on what reaches the brain
      says so.
- [ ] **Evals and `read-check`.** Scenario steps carry a `reading`;
      evals 94 and 95 move to readings. `boopdev read-check` runs the real
      on-device model over sample prompts and reports how often it gets
      the kind and tone right.
- [ ] **The sign.** A reaction's `sign` argument (about 18 characters,
      your words when they fit, else the pack's canned captions); react
      asks which, from the reading's phrases. The board draws it in the
      sign font in the design's sign slot.
- [ ] **Anchors and layers on the gel.** The body's head and hands each
      frame; the outfit, prop or sign and air layers drawn over it; a
      design may move a layer, pin it to the screen ("brb" while it
      hides), or keep none. Prove one nightcap over the slime first.
- [ ] **Outfits by the time of day and the calendar.** A nightcap and
      gown at night (and a sleepier face), a party hat, reading glasses;
      then the holidays.
- [ ] **First three scenarios**, each with evals and a demo:
      "still broken" (sad, holds up the words); its name in your prompt
      (it looks up at you); a delete or clean-up (glee, "bye bye code").
- [ ] **More scenarios** from the catalogue: a bug hunt, a new feature,
      a refactor, tests, a deploy (panic on a Friday), docs, a question,
      an essay of a prompt, "just" and "quickly", "be careful", thanks.
- [ ] **Pixel gets the layers too**, after the gel.

## Waiting on the owner

- [ ] Push AgentHooks' `terminal-tab-and-edit-sizes`, merge it, then
      bump `agent-hooks` and merge `boop-terminal-tab` (the exact
      terminal tab and "lines gone"). Try it in iTerm2 and Terminal.
- [ ] On the AMOLED board: turn it over and check the motion sensor's
      axis (`kFlipZ`, `dbg.imu`), and try a stroke, a tickle and the nose
      under a finger.

## Later

- [ ] The always evals that fail before and after the overnight work
      (03, 08, 13, 38, 39, 47; 04 and 28 flaky): Jev or the steering has
      drifted from them. Look at each with real runs.
- [ ] The agent's last message through the same reader as your prompt.
