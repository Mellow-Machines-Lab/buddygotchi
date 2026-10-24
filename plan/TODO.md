# TODO

Updated 2026-10-24. What's next, one at a time, top first. Tick an item
in the commit that finishes it, and say there what checked it. Ideas
that aren't decided yet stay in [product-ideas.md](product-ideas.md).

## Now: the prompt, read on the Mac

The plan: your prompt is scrubbed of secrets and read by Apple
Intelligence on the Mac; Jev gets only the reading (a kind, a tone, a
length, whether you named the buddy, and up to three short phrases of
yours), and the transcript keeps no prompt text. Boop reacts to it with
the board's new layers: a sign with words, outfits by the time of day,
and new actions. One personality (Boop's default nature) for now.

- [x] **Scrubber.** `app/BoopKit/Prompt/Scrubber.swift`: one table of
      secret patterns (API keys, tokens, JWTs, long hex and base64,
      `KEY=value`, URLs with tokens, emails), each `[secret]`, pinned by a
      fixture of fake keys.
- [x] **The reading and its labeler.** `PromptReading` (closed lists for
      kind and tone; length band; named; phrases), counted with no model
      (length, name, and the tone the words plainly show), and
      `AppleIntelligenceLabeler` (FoundationModels, three plain lines with
      examples, permissive guardrails, greedy, a 3 s timeout) for the
      kind, a heard tone and the phrases.
- [x] **The intake.** `PromptIntake` between `Runtime.hook` and the
      pipeline: scrub, strip the prompt from the event, read, then
      `Pipeline.promptRead`. The reading's event wakes the brain; the turn
      start waits for it (one with no prompt still wakes it). The view's line for it; the turn start's
      `You asked` note goes. CLAUDE.md's rule on what reaches the brain
      says so.
- [x] **Evals and `read-check`.** Scenario steps carry a `reading`
      (every prompt in the evals has one); `--labeler apple` reads them
      for real. `boopdev read-check` runs the real
      on-device model over sample prompts and reports how often it gets
      the kind and tone right.
- [x] **The sign.** A reaction's `sign` argument (about 18 characters,
      your words when they fit, else the pack's canned captions); react
      asks which, from the reading's phrases. The board draws it in the
      sign font in the design's sign slot. The Mac's side is in: each
      pack's `signs.md`, with `{words}` captions that play your phrases
      back in the buddy's way; the `react.sign` question; the `notice`
      animation; evals 101-103 and demos. The board draws it on both faces,
      held up in front (the gel's hands ring; Pixel's mitts under the face).
- [x] **Anchors and layers on the gel.** The body's head and hands each
      frame; the outfit, prop or sign and air layers drawn over it; a
      design may move a layer, pin it to the screen ("brb" while it
      hides), or keep none. Prove one nightcap over the slime first.
      Done on the board (`render/gel/layers.h`); peekaboo hides the hat.
      Still to do: pinning a layer to the screen ("brb"), and the Mac's
      mirror drawing the layers.
- [ ] **Outfits by the time of day and the calendar.** A nightcap and
      gown at night (and a sleepier face), a party hat, reading glasses;
      then the holidays. The gel has the hats, shades, the air and lower
      lids at night; still to do: a gown, reading glasses.
- [x] **First three scenarios**, each with evals and a demo:
      "still broken" (sad, holds up the words); its name in your prompt
      (it looks up at you); a delete or clean-up (glee, "bye bye code").
- [x] **More scenarios** (evals 104-114, Mac side) from the catalogue: a bug hunt, a new feature,
      a refactor, tests, a deploy (panic on a Friday), docs, a question,
      an essay of a prompt, "just" and "quickly", "be careful", thanks.
- [x] **Pixel gets the layers too**, after the gel. Its hats and air
      over idle's and asleep's plain variations (`render/pixel/outfit.h`),
      at the place its occasion art puts them, and the sign; its working
      looks and reactions keep their own props up there, undressed.
- [ ] **The slime's hats cost frames.** On the AMOLED board (140c9f2,
      measured 2026-10-23 with `boopctl ping`'s `draw_us` and `fps`): idle
      in the daytime draws in 26 ms, 37 fps; with a hat 31-35 ms, 27-30
      fps (night's cap and lower lids 33.5 ms, winter's bobble 34.7,
      Halloween 31.3, a party 31.5). Drawing the bands as filled ribbons
      instead of strokes didn't help (night 28 fps), so it's the filled
      area. The slower loop reads USB less often: the e2e check's p95
      latency went from 139 ms to 182-221 ms at night and fails its 200 ms
      limit about half the time. Marking only the rows a shape draws as
      changed (in place) and skipping the square root inside disks didn't
      move the frame rate either. The fix is to cache the hat: draw it
      into a small buffer when the brim's shape changes (about 95% of
      frames reuse it; step the nightcap's swing every 400 ms as Pixel's
      does) and blit it, about 4 ms back; give paintLayers its own field
      in the gel's profile first, so `boopctl ping` shows it.
- [ ] **Fluid animations and interactions.** Today the face visibly cuts
      from one state to the next (a look to a reaction and back, one mood
      to another, a gesture in and out). It should flow: blend between
      states (the slime's springs carry motion over; Pixel's flip-books
      could cross-fade or share in-between poses), ease a reaction in and
      out of the look it interrupts, keep the eyes and body moving
      through a change instead of resetting, and let a touch or a poke
      bend the current motion rather than replace it. Start by filming or
      recording a few transitions on the board to see where it jumps.

## Now: the character engine

The plan is [character-engine.md](character-engine.md): one rig, mixer and
layer stack for both faces, packs as data agents edit, references turned
into clips, and the Studio as the dashboard. Each checkpoint lands
reviewed, simplified and merged. Measure fluidity with
`internal/tools/fluid/` (baseline 2026-10-23, gel: a mood change's
largest frame 32x its median, a finish's 33x, going to work 9x).

- [ ] **1. The slime flows**: faces morph or cross-fade, the lane fades.
- [ ] **2. The dashboard and the reference pipeline.**
- [ ] **3. The rig core**: channels, expressions, clips, the mixer, layers,
      anchors, the pack schema and its generator.
- [x] **4. Pixel on the rig**: sprite parts, one mood first, then all.
      Idle's plain face in every drawn mood: mood changes dissolve and
      morph, and the hand-overs to and from the baked designs cross-fade
      (character-engine.md, Checkpoint 4 as built).
- [ ] **Pixel's rig face, the rest**: in the working looks over their
      desk and in the reactions (which clip a reaction plays), parts that
      move as some drawn idles do (curious's eyes, falling tears), and its
      frame cost on the CYD (`boopctl ping`'s `draw_us`).
- [ ] **5. The slime on the rig**: the mixer drives the gel face.
- [ ] **6. Retire what the engine replaces.**

## Waiting on the owner

- [ ] Push AgentHooks' `terminal-tab-and-edit-sizes`, merge it, then
      bump `agent-hooks` and merge `boop-terminal-tab` (the exact
      terminal tab and "lines gone"). Try it in iTerm2 and Terminal.
- [ ] On the AMOLED board: turn it over once to confirm the motion
      sensor's z (flipped on 2026-10-22: resting on the desk it read
      -1 g and thought it was face down; now +1 g), and try a stroke, a
      tickle and the nose under a finger.

## Later

- [ ] The always evals that fail before and after the overnight work
      (03, 08, 13, 38, 39, 47; 04 and 28 flaky): Jev or the steering has
      drifted from them. Look at each with real runs.
- [ ] The agent's last message through the same reader as your prompt.
