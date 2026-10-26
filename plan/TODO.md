# TODO

Updated 2026-10-26. What's next, one at a time, top first. Tick an item
in the commit that finishes it, and say there what checked it. Ideas
that aren't decided yet stay in [product-ideas.md](product-ideas.md).

## Now: the QA night, as users (2026-10-26)

The owner asked for a night of using Boop as users would. Seven testers
played profiles on the simulated board through the headless app: a
first-week buyer with no key, a multi-agent power user, a talker with
the real brain, the clock and calendar, the Mac app's surfaces, a real
workday with the brain, and odd inputs with restarts. What they found
and is fixed is in the night's commits here and SlimeBuddy's; what's
left is below.

- [x] Fixed: Boop dozes off with sessions left open; the day's greeting
      wakes only a sleeping Boop and isn't lost; one start card, not
      START then NEW TASK; the brain hears each finish once; a finish
      during another's needs you comes back after; talk with no key
      shrugs with a sign; a reply shows over the needs-you screen; reply
      signs don't repeat a night line; comfort keeps "again"; words
      falling over a kept card don't stay in it; Friday's shades from
      noon and off for feelings; lane 1 rose, not amber; a fifth session
      waits for a lane; a helper's word is "back"; a call ends as it
      starts; the hourly heartbeat lets a settled, sleeping Boop be; no
      word repeats within five says; names the board can't draw give way
      to the project; the diary's singulars; the popover's mood line and
      Hush; demos' talk, back and Codex review.
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

- [x] **The Mac app**: blank face tiles with Boop's pack, a "Try again"
      that couldn't work, Jev's key (trimmed, Return, failures said,
      its own Brain section), Details that wouldn't open, dismissed
      requests, onboarding's dead ends and resume, names the board drew
      as "?". Checked by BoopTests and `Boop --snapshots`.
- [x] **The board's touch, gestures, drawer, sound and stream**: 24
      fixes, each pinned in `internal/firmware/test`, and the gel's
      strip, LISTENING, sky, sign and clocks in SlimeBuddy (test_gel).
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
the whole body moving now and then ([calm-work.md](calm-work.md)).

- [x] **The cuts**: the camp and its pastimes, the sweatband, second
      wind, the little ones; the mug tower from `tier5`.
- [x] **Steady typing** by tier, the done beat, reading closely, the
      headphones put on, and three moves (the coffee reach, the melt,
      the stretch break), on the rig's new `x`, `reach` and `melt`.
      Checked by test_gel (`test_work_settles_by_tier`,
      `test_the_paws_type_on_the_keys`,
      `test_the_headphones_go_on_where_you_see_them`,
      `test_moves_are_rare`,
      `test_the_rig_carries_reaches_and_melts_the_gel`), the gel's
      scenarios looked at, and each played on the AMOLED.
- [ ] On the AMOLED: how the moves and the typing feel, by the owner.

## Now: talking back (2026-10-25)

The owner wanted the buddy to understand what's said to it, a smart pet
rather than a conversation ([talk-back.md](talk-back.md)).

- [x] **Replies.** What you said is asked `react.reply`, one of twelve,
      in place of the feeling, the topic and the animation, and always a
      face; the `do`'s `reply` plays the gel's `reply-<name>` clip.
      Checked by `ReplyTests`, test_gel's
      `test_a_reply_plays_its_clip_once`, `scenarios-gel/replies.jsonl`
      looked at, and Jev's evals `126` (2 runs) and `35`–`40`.
- [x] **A sign for every reply**, from the pack's `replies.md`
      (`SignTests.testThePacksRepliesFit`).
- [x] **Answers about the agents**: a `status` reply holds up what the
      agents are really doing, a check's result or how it came out
      (`StatusReply`; Jev's eval `127`, 3 runs; the `talk-back` demo
      played on the simulated board).
- [ ] On the real AMOLED: whether each reply's clip reads as meant, a
      nod, a shake of the head, a shrug and the rest
      (`make demo NAME=talk-back FACE=gel` plays them in the simulator).

## Now: four questions, and talking back, part two (2026-10-25)

Every reaction asks the same four things, and talk covers what it
didn't ([talk-back.md](talk-back.md), Part two).

- [x] **Four questions**: `react.face`, `react.move`, `react.intensity`
      and `say`, in place of six; steering, evals, demos and the tools
      in their words. Checked by Boop's tests, the expect brain's
      108/108 and Jev's 101/108 ([talk-back.md](talk-back.md), How it
      was checked).
- [x] **Replies**: `nap`, `dance`, `notme`; `huh` takes `dunno`;
      `thanks` your good news, `love` a sorry; signs that know the
      moment.
- [x] **On the gel**: the nap and the dance on request when idle, their
      clips at work, and `notme`'s.
- [x] **`status`**: what an agent is doing, and how long you've been at
      it.
- [x] **The hush, and Quiet in code**: "shh" or the popover's button
      hushes Boop for a while, shown by a countdown and the gel's zipped
      mouth; Quiet holds in code ([talk-back.md](talk-back.md), Part
      three). Checked by `HushTests` and Jev's `129`, `122`.
- [ ] On the real AMOLED: the zipped mouth while hushed.
- [ ] On the real AMOLED: the new clips, and the nap and dance on
      request.

## Now: the polish pass (2026-10-25)

The owner asked for smoother animation, crisper pictures, quicker touch
and a simpler build. Four audits (the gel's picture, the board's frame
pacing and touch, the Mac app, the architecture) found what's below.

- [x] **The gel's frame cost.** A busy frame took 34-48 ms (23-28 fps),
      the body 21.5 ms of it. The body is drawn on both cores, each row
      whole on one, erased a band at a time just before (render/helper.h);
      `perf --scenes` now: working 39 fps, attention 35, frightened 32,
      asleep 46, idle 46 (20.7 ms).
- [x] A take's lookup reads the card once, not ~12 times on the loop.
- [x] Snow and hearts move in sixteenths of a pixel.
- [x] The Mac: the popover's status publishes only when shown and
      changed and opens before the hooks are read; the mirror draws every
      frame the board draws, zooms the 46 pt tile onto the slime, and is
      one page handed between views (onboarding no longer reloads it per
      act); the popover keeps the slime with no board; the still face has
      no seams; snapshots are 2x.
- [x] The Mac, again (the popover in a real NSPopover from fixtures,
      on a 144 Hz display): open, the app took 8.7% of a core, now 2.3%,
      since the live dot's ring is Core Animation's, not a SwiftUI
      animation redrawing the popover every frame; the slime's page loads
      and the views lay out 1.5 s after launch, so the first open takes
      71 ms, not 130 ms and a black tile for 280 ms; the page fades in on
      its first frame; panes that fit don't scroll (with scroll bars
      always shown they were cut off); the volume is a slider of our own.
      With agents at work (a call every 300 ms), open, 13.7% became 4.2%:
      the sessions spring only when rows come, go or change status, not
      at every call's word. Onboarding's looking rings are Core
      Animation's too (7.9% to 2.7% on that act).
- [x] The mirror's board read the moment its pass ran, so at 60 Hz a
      pass run a little earlier than the last read under 16 ms and showed
      the same frame again (30 fps with passes 0.2 and 2.5 ms late in
      turn): it reads the refresh's time on those passes now.
- [x] The mirror drew 36 fps on a 144 Hz display: WebKit runs its
      `requestAnimationFrame` at 72 Hz there, and the board draws only
      when 16 ms have passed (`kFrameMs`, `device.cpp`), so every other
      pass. On a display faster than that the board's clock reads each
      refresh's time to the nearest 60th: 59.9 fps in WebKit, at 6.2% of
      a core in WebContent (4.8% at 36).
- [x] Simpler: no canvas lane under the gel or 8-bit AMOLED push;
      FaceLoops and faces.json's designs gone; EventLine, Core+Talk and
      device_debug.cpp in files of their own.
- [ ] On a real Mac: the popover opens quickly and never shows a stale
      pose; the 46 pt slime is crisp at 60 fps; with Bluetooth off it
      stays the slime; onboarding's acts show no black glass; two quick
      confetti bursts both play; the menu-bar glyph looks centred.
- [ ] Touch's tap waits 50 ms after a finger lifts (`kTouchReleaseMs`,
      for the panel's dropped readings under a light press). The FT3168
      reports a lift-up event (register 0x03, bits 7:6, masked off in
      `amoled206/touch.cpp`): log it under a real finger, then end the
      touch on it, keeping the 50 ms as the fallback.
- [x] Eyes and mouth no longer go see-through mid mood change: each
      look is kept and laid over the body alone, then blended by weight
      (`raster.h`'s `CrossFade`, in PSRAM). test_gel's never-fades now
      keeps at least 92% (was 90%; calm→frightened 109%), and every two
      arts' cross-fade fits half its room.
- [x] The body's outline popped when a triangle's facing flipped, and
      the crown's was hard (the pole's triangles never found the
      outline). The triangles fill by pixel centre and each outline edge
      has a fringe a pixel wide beyond it, meeting the next where the
      outline bends; lone slivers are left out. Swept end to end, the
      worst row-to-row jump fell from 1.0-2.05 px to 0.54-0.94; the crown
      is soft. +0.9 ms of body on the AMOLED. Checked by test_gel's
      `test_the_outline_holds_still_as_the_mesh_turns`.
- [x] Still whole-pixel: falling words (`stream.cpp` `wordAt`), the hat's
      replay (`OutfitLayer::kSlack`), the listening ring and the helper
      minis (`props.cpp`). Now in sixteenths: text by `text16` (bilinear
      between pixels, text()'s own on a whole pixel), the word forward's
      flights and landings, the little ones, the rocket, the monitor's
      page and bars (`subpixel.h`'s `round16`), the outfit replayed with
      `Raster::replay16`; the Zs fade in and out fully rather than pop.
      Checked by test_gel's `test_a_recording_replays_between_pixels`,
      `test_text_glides_between_pixels` and the outfit gliding half a
      pixel, and the stream, states and layers goldens looked at. On the
      board (`perf --scenes`, its new `stream` and `night` scenes): stream
      32.5 fps (33.3 before), night 26.0 (28.4 with the hat on whole
      pixels: replay16 fills what's whole and samples only edges, 10.3 ms
      of layers against 7.2), the rest unchanged, the internal heap's
      least 52.0 KB.
- [x] A lane's words fell on top of each other ("sed" over "sed"): two a
      `state`, 140 ms apart at random speeds. Each now drops a line
      (`kWordGapPx`) behind its lane's newest and never faster
      (test_behaviour's `test_the_work_streams_words`).
- [ ] On the real board: whether the hat and the falling words now look
      smooth asleep and at work, and whether words entering behind the
      panel's top corners (110 px radius) look like they come from above
      or look cut off.
- [x] The sleeper's Zs are drawn, not a font's: one rounded pen
      (`Raster::zee`) growing from 7 to 16 px and drifting by sixteenths,
      where the font's z jumped 40-47 px of ink between sizes (test_gel).
- [x] The face art's polygons take their exact area in each pixel
      (`raster.cpp` `polygon16`, a row's signed area summed along it),
      so a 3/16 px lid keeps its ink wherever it sits and a level edge
      moves a sixteenth at a time (test_gel). Cheaper than the 4
      sub-rows: `perf --scenes` art_us frightened 7.99 → 6.40 ms, working
      3.56 → 3.21, attention 3.93 → 3.58, pokes 3.57 → 3.22, asleep
      1.87 → 1.93; the rows every pixel reads stay in internal memory,
      the rest is in PSRAM (internal heap's least 51.5 → 51.2 KB).
- [x] The body's material is 1025 × 513 texels (was 513 × 257, about
      1.75 px a texel): the highlight and rim keep their edges. Where a
      triangle's texels crowd more than 1.5 under a pixel at rest (40% of
      the body, the sides and crown) it reads a 513 × 257 copy, blended
      from the large one; and the AMOLED reads both from a copy in PSRAM
      (`Hal::quickerCopy`). `body_us` in working: 21.7 ms from flash,
      17.2 from PSRAM, 16.2 with the half size; 15.7 with projection and
      the outline's classification shared between the cores. Checked by
      test_gel's `test_the_materials_copy_draws_the_same_body`.
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
      unpreempted a push of 65 K pixels took ~20 ms: packing is held up
      on the memory bus. The same push took ~7.5 ms for 60 K pixels at
      the polish pass's start (2026-10-25, before the material moved to
      PSRAM, which the push's surface reads share), so the bus, not the
      QSPI clock, is what to win back first.
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
- [x] Act 5's fourth lesson, "When I glow amber, tap me", asked for
      nothing, so after the talk lesson it looked like it was waiting
      (the owner's second setup, 2026-10-25). Once the first three are
      done on a paired board, it glows amber with a practice request (the
      needs-you screen with no agent behind it, `Core.setPractice`), and a
      tap or a press answers it and ticks the lesson
      (`Onboarding.Progress.practiceDue`). Checked by OnboardingTests.
- [x] The work stream's one lane fell from the middle, where a hat
      covered its project's name: lanes sit clear of the head now, one on
      the left (`render::laneX`). Checked in `stream.jsonl`'s
      `one-lane-night`.
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
and new actions. One personality for now.

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
      stretch from `tier4`, on both faces), and its outfit, air and Zs
      come and go through the rig's layer stack, the sign fading out on
      both faces; its expressions stay its own (character-engine.md,
      Checkpoint 5 as built). Checked by test_gel, test_rig,
      test_behaviour and Pixel's test_scene, the goldens (two new), the
      mirror, internal/tools/fluid and a native frame's cost. A reaction
      plays its clip too: Boop's notice, from the approved reference
      (character-engine.md, The slime's notice on the rig).
- [ ] **The gel on the rig on the board**: its frame cost on the AMOLED
      with a hat, asleep at night and at `tier5`, its pastimes and kit
      out (`boopctl perf --scenes`), and a look at the stretch, the
      layers' fades, the notice and the pastimes.
- [ ] **6. Retire what the engine replaces.**

## Now: something new at every glance

The tiers' art, from [glance-and-wait.md](glance-and-wait.md) §3, redone
with the owner on 2026-10-25: five tiers, closer together, and something
to see at each.

- [x] **The tiers and the pastimes**: `tier1` to `tier5` at 30 s, 1, 2, 5
      and 10 minutes, at work from the agents' working stretch (a quick
      reply carries it on) and idle from their rest, the last reached on
      the wire and the ones below it taken as on by the board; on the gel,
      39 pastimes (a rig clip each and its drawing) for work, idle, needs
      you and asleep, dealt after a rest of 4 to 10 s, and the kit (a mug,
      headphones, a sweatband, the camp, the plant). Checked by
      OccasionsTests, CoreTests, test_gel's test_pastimes.cpp, test_rig,
      test_behaviour, eval 116, the gel's goldens (pastimes.jsonl) and
      Pixel's, unchanged but for the stretch's name, the mirror, and both
      boards building; each pastime looked at frame by frame in the
      simulator, not yet on the board.
- [ ] **The pastimes on the board**: a look on the AMOLED, and their
      frame cost there with the kit and a pastime out (`boopctl perf
      --scenes`); tune their timing and art.

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
- [ ] Act 6's tour on the AMOLED, with a fresh Claude Code session
      asked to list its files: the words fall on the board and in the
      window, Boop cheers once the turn ends and a tap on it opens the
      thread, the drawer swiped up and its row tapped opens it again, the
      window comes back after each, and Next unlocks only then. Act 2's
      FAIL rain on the window's Boop.
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
- [x] The gel's draw order flickers for one frame at nine mood changes
      (shy→affectionate, sad→wounded, crying→wounded, wounded→sad,
      wounded→crying, frightened→wounded, frightened→sad,
      frightened→crying, exhausted→overwhelmed): an incoming face added at
      weight zero that shares a feature's shape moves that feature to its
      turn in the draw order, 32 to 630 pixels of the mouth and tears for a
      frame. Found retiring the JavaScript engine (2026-10-24). Fixed in
      SlimeBuddy (416b40d, 2026-10-26): a shared feature is drawn at the
      oldest face's turn; test_gel's `test_a_face_coming_in_moves_nothing`
      checks the nine, and two controls, as a face comes in and goes.
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
