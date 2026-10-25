# TODO

Updated 2026-10-24. What's next, one at a time, top first. Tick an item
in the commit that finishes it, and say there what checked it. Ideas
that aren't decided yet stay in [product-ideas.md](product-ideas.md).

## Now: the first launch, from the owner's setup

What the owner's own first-time setup on 2026-10-24 ran into, `make run`
on a Mac with no Boop state and both boards powered.

- [x] Act 5's third lesson, "Hold my button and talk", did nothing in
      the window, and promised an answer before Jev's key is asked (act
      7). It waits after the button's lesson now, and push-to-talk that
      heard words ticks it (`Onboarding.Progress.talked`, the runtime's
      `onHeard`); the card says what the Mac heard, that it heard nothing
      and to keep holding, or why the mic can't hear, and without a key
      that the answer comes in a couple of steps. Checked by
      OnboardingTests and RuntimeTests, and act 5's snapshots.
- [x] Act 7 asked for the microphone again after act 5's push-to-talk
      had it allowed: its card is left out then. Opening at login from
      `make run`'s bare binary says that only Boop.app can, and that this
      copy runs from a terminal. Checked in act 7's snapshots.
- [x] Act 6's "See exactly what gets added" was the installer's preview
      as one block of text: it's two paragraphs of what the hooks do and
      promise, then each agent's file, its hooks, the ones that run only
      for some types, the command each runs, and Codex's switch. Checked
      in `6-agents-what-gets-added`.
- [x] With two boards powered, act 4 took the first one it heard
      (`ble: found Boop-54FE`, the CYD) and named it only in small print,
      while the board itself gave no sign that it was the one: the CYD's
      sleeping face held still (0 fps), so it looked frozen, and a tap on
      the AMOLED, the board in hand, did nothing. The owner's call (option
      A): the found board beckons every 6 s until it's tapped, a `notice`
      holding up "Tap me!" (`Runtime.Greeting.beckon`), and the window says
      it's the one holding that up. Checked by RuntimeTests, a throwaway
      simulator scenario on both faces (the napping slime and Pixel look up
      holding the card), and `4-body-found`. Left until someone needs it:
      a "Not this one?" that lets go of the found board for the next.
- [x] Onboarding had no Dock icon: the app is `.accessory`, and there's
      no menu-bar icon until onboarding finishes, so the window, once
      behind others, had no Dock icon or Command-Tab entry to bring it
      back. It runs as `.regular` while onboarding shows, and `.accessory`
      once it's done. Only a real launch shows it (On a real Mac, later).

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

**The CYD is frozen** (the owner, 2026-10-24): it keeps building and
gets no new features; new work is the AMOLED board's, on the gel's own
engine and its rig (checkpoint 5), starting with
[work-stream.md](work-stream.md). Pixel's rig face on the board waits
with it.

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
- [x] **5. The slime on the rig**: the gel plays the rig's clips over
      its engine's pose, a look's occasions are the rig's (working's
      stretch on a marathon, on both faces), and its outfit, air and Zs
      come and go through the rig's layer stack, the sign fading out on
      both faces; its expressions stay its own (character-engine.md,
      Checkpoint 5 as built). Checked by test_gel, test_rig,
      test_behaviour and Pixel's test_scene, the goldens (two new), the
      mirror, internal/tools/fluid and a native frame's cost. A reaction
      plays its clip too: Boop's notice, from the approved reference
      (character-engine.md, The slime's notice on the rig).
- [ ] **The gel on the rig on the board**: its frame cost on the AMOLED
      with a hat, asleep at night and on a marathon (`boopctl perf
      --scenes`), and a look at the stretch, the layers' fades and the
      notice.
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
- [x] Push AgentHooks' `lifecycle-fixes` and merge it (a turn silent an
      hour stops working, a day forgets any session, wrappers aren't the
      agent, `HookSocket.listed`), then bump `agent-hooks`: a1f6417 on
      AgentHooks' main, bumped in 9f34a2a.
- [x] Review the worked reference (Studio, Review: notice from the perk
      reference): approved on 2026-10-24, in chat. The notice clip took
      its beats, the gel plays it on the rig, and its reading names what
      the rig has (character-engine.md, The slime's notice on the rig).
- [x] Reference frames were committed, capped at 512 px a side: fine for
      sketches and GIFs, heavy for long videos. The owner's call
      (2026-10-24): the contact sheets, reading and media are committed,
      the frames stay where `boopctl reference read` cut them, and
      `charactergen.py --check` asks for them only where they're cut.
- [x] Design calls the final review left, each a change to how it looks:
      - The gel: falling asleep is a morph now, the awake face squashing
        shut on a slow spring (ω 4) to lines and swapping to the sleeping
        face over 360 ms once it's one, alone by about 1.3 s; waking
        stays the face's 180 ms.
- [x] On the AMOLED board: turn it over once to confirm the motion
      sensor's z (flipped on 2026-10-22), and try a stroke, a tickle and
      the nose under a finger: the owner says it works (2026-10-24).

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
- [ ] Reopening Boop.app while it runs brings its window or popover.
- [x] Pairing remembers the board you tap, not the first hello: on
      2026-10-24 the CYD said hello first, and the AMOLED, tapped, is the
      one remembered.
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

- [x] The always evals that fail before and after the overnight work
      (03, 08, 13, 38, 39, 47; 04 and 28 flaky; 48 and 52 too): the
      steering and the mood and react questions say what they meant,
      and 13, 39 and 40 take the faces the character makes. The whole
      `--always` set ran once against Jev: 26 of 27, and 40, whose faces
      predated the puzzled ones, passed once it took them.
- [ ] The gel's draw order flickers for one frame at nine mood changes
      (shy→affectionate, sad→wounded, crying→wounded, wounded→sad,
      wounded→crying, frightened→wounded, frightened→sad,
      frightened→crying, exhausted→overwhelmed): an incoming face added at
      weight zero that shares a feature's shape moves that feature to its
      turn in the draw order, 32 to 630 pixels of the mouth and tears for a
      frame. Found retiring the JavaScript engine (2026-10-24).
- [ ] Apologies don't soften a grumpy Boop's mood against Jev: 56
      (one apology softens it) passes 0 or 1 of 3 and 57 (undone by
      poking) 0 of 3, before and after 2026-10-24's grumpy wording. The
      face is right (annoyed); the mood question gives grumpy 0.61,
      irritated 0.27, annoyed 0.12: the stay option ("hasn't been grumpy as
      long as MOOD says it lasts. No change is fine.") outweighs grumpy's
      "a sorry cools it at once". A full Jev run of every scenario (about
      820 requests) would show what else sits outside the always set.
- [ ] One left from the always evals: 38's second thing said gets its
      face narrowly (curious about 0.5 against none about 0.4, three runs
      of three). Pixel's five pass against Jev with the new mood and
      react questions (2026-10-24).
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
- [ ] The gel's lane scales with its panel (lane.cpp's fonts, margins
      and bubble are fixed px), then the Mac mirror renders at the
      tile's size (about 20× fewer pixels). Drawn at the popover tile's
      113 × 92 (2026-10-24, the simulator's `BOOP_SIM_NATIVE`), the
      slime, desk and needs-you plate scale, but the lane's text, dots
      and sign come out several times too big and run off the panel.
