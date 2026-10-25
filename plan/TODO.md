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
      Still to do: pinning a layer to the screen ("brb"). The Mac's
      mirror draws them: it's the board's own firmware.
- [x] **Outfits by the time of day and the calendar.** A nightcap and
      gown at night (and a sleepier face), a party hat, reading glasses;
      then the holidays. The gel has the hats, shades, the air and lower
      lids at night, and now a gown under the nightcap while it sleeps
      (on two rings low on the body, `rig::Anchors::lap` and `hem`) and
      reading glasses while the Mac's new `reading` tag is on: the
      latest prompt was an essay or for docs, for its turn
      (`Occasions.reads`). Pixel wears neither; the Mac's mirror draws
      them once it runs the gel's engine on WebAssembly.
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
- [x] **The slime's hats cost frames.** On the AMOLED board (140c9f2,
      measured 2026-10-23 with `boopctl ping`'s `draw_us` and `fps`): idle
      in the daytime draws in 26 ms, 37 fps; with a hat 31-35 ms, 27-30
      fps (night's cap and lower lids 33.5 ms, winter's bobble 34.7,
      Halloween 31.3, a party 31.5), and the e2e check's p95 latency at
      night neared its 200 ms limit. Now the layers have their own
      `layers_us` in the profile build's `gel_parts` (and `boopctl perf
      --scenes`), and the outfit is kept (`OutfitLayer`,
      `render/gel/layers.h`): drawn into a recording when its look
      changes or the body moves it past a slack, blended from it
      otherwise, and drawn where it is again once the body is still, so
      still frames are as before (the goldens didn't change); the
      nightcap's swing steps. In a minute of 30 ms frames natively (-O2,
      best of 15), the layers
      take 12-14 µs a frame with a hat instead of 43-49 (night idle
      42.9 → 11.9, winter 49.2 → 14.4 with its snow, Halloween 45.2 →
      12.4), the frame 107-113 µs instead of 142-150 (day idle 95), the
      hat redrawn in 4-10% of frames. Still to measure on the board:
      `draw_us` with a hat, and the e2e p95 at night.
- [x] **Fluid animations and interactions** (taken up as the character
      engine, below). Today the face visibly cuts
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

- [x] **1. The slime flows**: faces morph or cross-fade, the lane fades.
      Checked on the AMOLED board: `boopctl run` matches the simulator,
      and a cross-fade frame costs 0.5 to 2.6 ms.
- [x] **2. The dashboard and the reference pipeline.**
- [x] **3. The rig core**: channels, styles, clips, the mixer, its Ramp
      and anchors, the pack schema and its generator, cut on 2026-10-24
      to what Pixel's face uses (character-engine.md, the final pass).
- [x] **4. Pixel on the rig**: sprite parts, one mood first, then all.
      Idle's plain face in every drawn mood: mood changes dissolve and
      morph, and the hand-overs to and from the baked designs cross-fade
      (character-engine.md, Checkpoint 4 as built).
- [x] **Pixel's rig face, the rest**: in its designs' place wherever they
      draw the resting face, the working looks over their desk and the
      reactions included; whiny's tears as its design's decorations;
      curious's idle baked again (character-engine.md, Checkpoint 4b as
      built).
- [ ] **Pixel's rig face on the board**: its frame cost on the CYD
      (`boopctl ping`'s `draw_us`), and a look at the working day on it.
- [ ] **5. The slime on the rig**: the mixer drives the gel face. Done
      so far (character-engine.md, Checkpoint 5 as built): the lane's
      fade decided once for both faces, the gel's remaining cuts, one
      anchors type. The Mac's mirror now runs the board's engine
      (character-engine.md, The Mac's slime on the board's engine); the
      rest waits for phase 2 there, retiring the slime's JavaScript twin.
- [ ] **6. Retire what the engine replaces.**

## Waiting on the owner

- [x] Whether the Mac's mirror runs the WebAssembly engine, retiring the
      slime's JavaScript twin, so the gel's expressions can move onto
      the mixer (character-engine.md, checkpoints 5 and 6): yes. Phase 1,
      the Mac on the board's engine, is built (character-engine.md, The
      Mac's slime on the board's engine); phase 2 retires the JavaScript
      twin.
- [x] Push AgentHooks' `terminal-tab-and-edit-sizes`, merge it, then
      bump `agent-hooks` and merge `boop-terminal-tab` (the exact
      terminal tab and "lines gone"): 03fad1a on AgentHooks' main,
      bumped in db97abb.
- [ ] Try the exact terminal tab in iTerm2 and Terminal.
- [x] Push AgentHooks' `lifecycle-fixes` and merge it (a turn silent an
      hour stops working, a day forgets any session, wrappers aren't the
      agent, `HookSocket.listed`), then bump `agent-hooks`: a1f6417 on
      AgentHooks' main, bumped in 9f34a2a.
- [ ] Try what only a real Mac session and Bluetooth can show (the review
      of 2026-10-24's fixes): onboarding's window coming forward over the
      terminal at the agent's hello, and reopening Boop.app; pairing
      pinning the board you tap, not the first hello, and "I don't have
      my Boop yet" pinning none; in act 5, BOOT ticking only the button's
      lesson; an update with both boards plugged in (a refusal for the
      wrong board, the chip's image, a restart after a cut-off write);
      opening an agent's tab from the bundled app (the Automation
      prompt); `make onboarding` keeping its own Keychain entry and
      leaving no socket behind.
- [ ] Review the worked reference (Studio, Review: notice from the perk
      reference). It keeps Boop's `notice` clip, which no face plays yet;
      its reading still names beats for the rig's dropped `eyeCurve` and
      `cheek`.
- [ ] Reference frames are committed, capped at 512 px a side: fine for
      sketches and GIFs, heavy for long videos. Keep, or commit only the
      contact sheets?
- [ ] Design calls the final review left, each a change to how it looks:
      - The gel: falling asleep cross-fades two arts in 480 ms (the
        longest that keeps the ink check's 85%); a morph that squashes the
        face shut would let the length be a choice.
- [ ] On the AMOLED board: turn it over once to confirm the motion
      sensor's z (flipped on 2026-10-22: resting on the desk it read
      -1 g and thought it was face down; now +1 g), and try a stroke, a
      tickle and the nose under a finger.

## Later

- [x] The always evals that fail before and after the overnight work
      (03, 08, 13, 38, 39, 47; 04 and 28 flaky; 48 and 52 too): the
      steering and the mood and react questions say what they meant,
      and 13, 39 and 40 take the faces the character makes. The whole
      `--always` set ran once against Jev: 26 of 27, and 40, whose faces
      predated the puzzled ones, passed once it took them.
- [ ] Two left from the always evals: 38's second thing said gets its
      face narrowly (curious about 0.5 against none about 0.4, three runs
      of three), and Pixel's five evals haven't run against Jev since
      the mood and react questions changed (`make -C internal
      eval-pixel`, about 18 requests).
- [x] The agent's last message through the same reader as your prompt.
- [x] A first `boopctl sim` or `run` straight after a merge sometimes
      reported changed pictures and a second run passed (three times on
      2026-10-24, and a `check-headless --native` once). No dependency
      was missing: every checkout's runs shared `/tmp/boop-sim`, and
      after `fw-test` the native `program` was a unit-test runner. Each
      checkout has its own folder now, the tests build in `.pio/test`,
      and a stage changes only what differs.
- [x] Device::reset cleared a hand-kept list of the members keyed to the
      clock (the motion sensor's were missed once): they're one struct,
      `Device::Live`, which reset assigns `{}` (the lifecycle fixes).
- [x] The rig channels `x`, `y`, `tilt` and `mouthWidth` were read by
      Pixel's face but set by no clip or input: dropped, with the face
      code that read them (test_rig, test_rig_face).
