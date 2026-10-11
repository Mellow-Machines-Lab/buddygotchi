# Boop V4 — six new moods, full new-mood variation coverage

Built 2026-09-28; the COMPACTED start card added 2026-10-11. The V2 production assets and the 308 V3 performances are kept alongside it.

Review it as **Pixel Boop** in the [Character Studio](../../../studio/README.md) (`#pack=pixel`), whose adapter for it is Pixel's `studio/adapter.js`. The studio works offline, plays synchronized procedural sound once sound is on, loops or plays once, and scrubs frames silently.

## Inventory

- Retain unchanged: happy, excited, proud, curious, determined, grumpy, sad — 308 existing V3 performances, 44 per mood. Each also has one COMPACTED start card, drawn the V3 way after the freeze: 7 more, with no V3 fingerprint.
- Add: calm, engaged, annoyed, irritated, whiny, wounded — 480 performances, 80 per mood.
- Delete: none. All old mood names map directly to themselves. Curious already has art even though the inspected production selector did not expose it.
- Combined: **13 moods × 22 states = 286 mood/state pairs, 795 selectable performances.**

Every **new** mood gets three distinct actions for every state, with five working actions, twelve starting selections (three actions × four factual contexts: new task, session, continuation and compacted), and six task-complete selections (three success + three failure). Shared sleeping/disconnected routines are intentional: those 36 selections are not 36 uniquely emotional sleeping animations. Each new mood therefore has 74 expressive performances and six shared-quiet selections. This bank does not claim to have filled the older seven moods' single-action V3 state gaps.

`coverage.json` is the exact per-mood/state count. `manifest.json` lists all IDs, captions, source actions, timings, sound scores and suggested new-scene voice windows. “Variation count” means selectable performances; some share reusable choreography and all share primitive code, not 795 hand-drawn film strips.

The 22 states remain: no_app, asleep, idle, listening, starting, planning, working, terminal, tool_use, searching, analyzing, testing, delegating, helper_return, waiting, needs_you, reply_ready, task_complete, error, stopped, poked, tap_spam.

## Design grammar

- 320×240 SVG, coarse square effects, stepped corners, big minimal eyes. No new outer frame, raster/video assets, gradients, detailed fingers or human hands.
- New art is clipped at y=192. The bottom 48 pixels remain black for host text. Downstream text should use a matching stepped pixel bubble with a short tail; wrap/paginate instead of shrinking text into illegibility; escape all inserted text. Host content must not cover the face or falsely report results.
- Annoyed holds a side-eye; irritated twitches and makes clipped corrections. Whiny protests and continues working; wounded flinches and cautiously reapproaches. Calm moves deliberately; engaged tracks and acts fluidly.
- Thirty new working actions are authored across the six moods, not just a reskinned keyboard loop. Other states share three semantic actions, performed with mood-specific facial poses, body movement, rhythm and timing. Quiet sleep/no_app intentionally ignore mood visually while retaining it in state.
- Exact home-pose loop closure plus a small end hold. Reduced-motion fallback preserves the meaningful notification or outcome. Browser reference player respects reduced motion.
- Labels on props are decorative except factual start/outcome labels. Binary rain and RUN() text are toy animation, not actual captured commands, file contents or progress percentages.

## Runtime use

Deploy **either** `dist/boop-runtime.js` or the `runtime/` modules. The bundle exposes `globalThis.Boop`; modules expose `createBoopPlayer` from `runtime/player.mjs`. Do not deploy QA, manifest and expanded SVG copies just to run the bank. Expanded SVGs are optional editable/inspection output; the compact runtime generates the selected SVG on demand.

```js
const player = Boop.createBoopPlayer({ mount: document.querySelector('#boop'), volume: 0.4 });
// Call from an enabled audio/user gesture in a browser.
await player.setState({ mood: 'whiny', state: 'terminal' });
await player.setState({ mood: 'wounded', state: 'task_complete' }, {
  hostContext: { completionOutcome: 'failure' }
});
player.setSpeechActive(true); // ducks routine material accents, not attention cues
```

Only mood/state are the character selection axes. Host-only `completionOutcome` and `startContext` are factual filters, not mood intensity values or JEV-authored results. Missing completion outcome falls back to reply_ready. Valid start contexts are new_task/session/continuation; omitted context means READY. `force: true` is for a genuinely fresh same-state event; ordinary duplicate updates must not retrigger entry sounds.

Graph design and JEV handover: `../boop-mood-spectrum-v2/HANDOVER.md`, with `mood-graph.json`. This bank does **not** enforce graph traversal or infer agent events. Do not silently add that policy inside the generic player or harness. Implement it in the application's Mood action under repository instructions, with persistence and stale-decision tests.

## Sound and voice integration

No audio recordings are stored. Existing synthesis primitives and the accepted natural, voice-first mix are reused. All 308 V3 SVGs and scores are compared byte-for-byte / structurally against V3 during QA.

- Idle, asleep, no_app, listening and waiting are silent by default.
- New routine actions keep only a few contact sounds, with irregular seed-dependent selection. Every selected cue stays at its actual visible contact time; no audio-only jitter. A fresh seed can change which gestures are audible without changing the scene's timing.
- Every needs_you variant has broad taps followed by the same pitch/timbre of alertDing. Tap pace/strength depends on mood. The alert does not approve anything; the host must keep the pending indication until resolved.
- Task success/failure and tool error use entry-only protected cues. Repeating their visual loop does not repeat the attention sound. A failed task does not play a trophy sound regardless of mood.
- New speech/mumbles belong to the sound chat. The manifest's voiceWindow is an initial safe-window **suggestion**, not guaranteed room for any arbitrary clip. Audition lengths and joins. When an utterance cannot fit, extend a host hold or follow after the scene; do not compress the voice to fit. Keep the alert ding clear, then let voice speak. No constant background music.

JEV should select semantic intent/mood, while a deterministic compatibility filter and recency ledger select acceptable variations. Never concatenate arbitrary clips solely to maximize combinations. The handover to **【Buddygotchi】Sound** includes the full 13-mood inventory, all states, silent exceptions and recording constraints; no ElevenLabs credits are used by this bank.

## Rebuild and checks

```sh
node characters/pixel/design/boop-mood-spectrum-v2/validate.mjs
node characters/pixel/design/boop-sound-bank-v4/source/build.mjs
node characters/pixel/design/boop-sound-bank-v4/qa/check.mjs
node characters/pixel/design/boop-sound-bank-v4/qa/browser.mjs
node characters/pixel/design/boop-sound-bank-v4/source/build.mjs --svg
```

Run those commands from the repository root. The final command is optional and exports all 795 SVG selections to `dist/svg/`. Sound remains procedural in the runtime and manifest, not embedded audio files in SVG. The browser QA script uses installed Playwright, pngjs and Chromium; see the [dependency setup](../README.md). Optional BOOP_PLAYWRIGHT_MODULE, BOOP_PNGJS_MODULE and BOOP_QA_BROWSER select existing installations. No hard-coded workstation paths are required.

The checked-in compact player and coverage/storage reports are generated by the builder. The large per-scene manifest, expanded SVG files and QA screenshots are ignored build outputs. The immutable `qa/v3-fingerprints.json` was captured from V3 independently at import; QA compares the exact SVG bytes and serialized score hashes against it, without needing the old workspace folder.

QA covers IDs/counts, all state/outcome/context selections, legacy preservation, finite synthesized samples, monotonic and closed animation clocks, sound/pose alignment, SVG parsing, home-frame checks, selected pixel-level seams/text-lane checks, preview controls and reduced motion. Automated checks do not replace the user's visual and listening approval. No SD-card I/O, speaker response, Bluetooth timing or physical device playback was tested in this pass. The reference renderer/player targets desktop browsers/WebViews; the firmware draws the designs through facegen, held to Chrome pixel for pixel, and plays the timelines sfxgen bakes from this bank (see [the package guide](../README.md)).
