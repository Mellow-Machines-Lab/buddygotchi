# Slime export validation

Updated 2026-10-21. Package-only checks; no production/hook/firmware/device
integration is claimed. Historical face audition QA is recorded separately
in [contracts/historical-face-qa.json](contracts/historical-face-qa.json).

From the repository root, Node 18+:

```sh
node characters/boop/design/slime-blob/tools/build.cjs
node characters/boop/design/slime-blob/tools/check.cjs
```

The offline check covers retained IDs, all mood/state/edge checklist
entries, ordinary-graph connectivity, canonical catalogue export, seven
accepted motion hashes, unchanged blue gel material, deterministic finite
bounded procedural sound output/mute, and local Markdown links.
It also checks that `preview/slime.bundle.js` matches the source modules,
that fixed-step traces reproduce, and that fact/mood retargets preserve
the actor's displacement and velocity. The engine, bridge and scene checks
also bound what is drawn in every frame they run
([CONTINUITY.md](CONTINUITY.md), Continuity of what is drawn): no jolt at an
event, drawn face ratios in range, props without pops, a face that never
fades and body modes that move only by their springs. Trace generation is explicit:

```sh
node characters/boop/design/slime-blob/tools/trace.mjs --script characters/boop/design/slime-blob/scripts/idle-60s.jsonl --seed 53
node characters/boop/design/slime-blob/tools/check-engine.mjs
node characters/boop/design/slime-blob/tools/check-scenes.mjs
node characters/boop/design/slime-blob/tools/check-bridges.mjs
node characters/boop/design/slime-blob/tools/check-cues.mjs
```

These engine checks establish deterministic control output, not artistic
approval or equivalence of the C++ port.

The scene check exercises all routing IDs separately from choreography
coverage. Its representative script covers 24 cases in 20 distinct cells;
full-matrix checks execute every canonical mood/state cell, all its active
variants (idle's gags and a success's hiccups among them), all start contexts
and completion outcomes, a wake-up with no
start card, plus a
ten-minute work run, attention identity, alerts interrupted at every stage
(each request knocks and confirms exactly once), drag interruption, quiet rest
(a minute asleep snores, two breaths at a time, and a lost link never does),
latest-facts recovery and truthful success/failure. Its comedy checks pin the
gags' catalogue and durations, their springs and keys, the bag that deals them
from its second round, the hiccups' timings, the gift on proud's lifted success
alone, each gag's look (the yawn stretches with squeezed eyes, the doze droops
and sinks then blinks awake, the sneeze is one contact a second in, the zoomies
reach both edges, small under reduced motion) and sleep's still first 12.8 s.
The cue check plays twenty minutes of idle and of sleep: only the sneeze and
the snore's breaths sound, sparsely. The builder runs the
full coverage check before updating `coverage.json`; no cell earns a
status merely from a scene name or counter. `preview/script-catalog.js` must match the scripts
and verified review manifest.

The bridge check walks all 295 directed edges from mid-gesture in each of
their three variants, verifies that face controls stay between their current
values and the target (within the span of every target in a rapid chain),
and permits primitive changes only while the single face is fully closed.
It checks that every primitive's targets fit inside their bounds and that
the face painter never fades the face through the edge review script. It also covers every edge during rest, drag and pending attention,
rapid interrupted retargets, reduced motion, direction, bounded springs and
the drag expiry boundary. Its 13-case script includes ordinary and dramatic
edges. Passing earns `transitions.json` status; visual approval is separate.

For visual review, choose **Representative activities** or **Directed mood bridges** in **Review set**,
then **Record review set** in the studio's **Tools**. It records
each case from the rendered body and prop canvases to a silent local WebM,
then exposes a video player and download link. It never requests camera,
microphone or desktop capture. Recording is art evidence, not a substitute
for deterministic engine traces or owner approval.
Starting a script or recording explicitly starts a fresh seed-53 actor and
clock, so earlier grabs or moments cannot contaminate it. The actor then
persists through every event in that run. Manual controls are disabled
during recording; stopping retains a clearly identified partial last clip.
The studio server's optional `--capture-dir DIR` endpoint (`characters/studio/serve.cjs`) saves only the named
WebM files in generated `preview/review-cases.json` (24 activity and 13 edge
cases). It requires the exact loopback Host and Origin plus a per-server
token, a WebM content type and header, at most 8 MiB per clip, and a 15-second
request inactivity limit. Exclusive file creation refuses existing files
and symlinks. The directory comes only from the CLI; no client path is used.
Without the flag all capture writes are disabled. `tools/check-server.cjs`
exercises this local endpoint separately because it needs a loopback socket:

```sh
node characters/boop/design/slime-blob/tools/check-server.cjs
```

Optional real-browser QA requires Playwright and Chromium. Use existing
dependencies through `BOOP_PLAYWRIGHT_MODULE` (path to the Playwright module)
and `BOOP_QA_BROWSER` (Chromium executable). Otherwise it resolves the
installed `playwright` package and its managed Chromium. These are test-only
dependencies, not required by the studio, builder or offline validator.

With the studio server running from the README, from the repo root:

```sh
node characters/boop/design/slime-blob/tools/browser.cjs
```

`BOOP_QA_URL` overrides the local URL; defaults to http://127.0.0.1:4190/studio/#pack=boop&c=boop.
`BOOP_QA_OUTPUT` chooses a screenshot output directory; by default a fresh
temporary directory is used. `BOOP_CAPTURE_FACES=0` skips per-face screenshots,
not the expression-selection checks. `--help` is supported by all package
scripts. QA images are review evidence, not packaged runtime assets.

## The firmware port

The C++ gel face (`characters/boop/firmware/src/render/gel/`) is checked
against this package's reference engine, from the repository root:

```sh
make -C internal fw-test      # first: it fetches the ArduinoJson check-port.py compiles against, and stages the pack
python3 characters/boop/tools/slimegen/check-port.py --output /tmp/boop-gel-port
internal/tools/boopctl sim --face gel
```

- `check-port.py` builds the native trace adapter (with `BOOP_GEL_TRACE`,
  the one build that keeps the recipes' `intent`) and replays every
  `scripts/*.jsonl` against the saved traces, `comedy.jsonl`'s gags,
  hiccups, gift and snore included. It checks every scalar,
  categorical field, cue and frame count within its tolerance, and fails
  on unexpected extra fields too. It reads the staged pack's `moods.h`
  (`.character-build/`, which `fw-test` stages) after the pack's own headers.
- `test_gel` (in the pack's `tests/firmware/`, run by `fw-test`) checks
  arithmetic, reference clock rounding, every expression buffer's
  bounds, deterministic pixels, request identity, bounded caches, alerts
  interrupted by listening or a link timeout signalling exactly once,
  drawn face ratios and the alert's ramp moving without jumps across
  every directed edge, voice lead, stale cues, return to the latest
  facts, projected face anchors against the reference camera,
  extreme-pose buffer bounds, drawing by coverage (a shape's ink is its
  area wherever it sits between pixels, a stroke keeps its width and
  blends once, the body's outline is soft with no seam inside), and
  tracked-clear parity with full clearing across pose and prop changes.
  RGB565 opacity rounding is checked against an independent scalar
  reference across every channel value and all 256 opacity levels. Its
  comedy test pins each row's takes, the hiccups' and the snore's
  recipes, the one gift, idle's takes per expression, the bag's rounds,
  the doze's lids and sink, the zoomies' reach, a sneeze that allocates
  nothing, and sleep that snores after its still start (never with the
  link lost); the extreme pose includes the slide at its bound.
- `boopctl sim --face gel` plays the pack's `tests/scenarios-gel/`
  against its `tests/golden-gel/`: every canonical mood and factual
  state, failure and neutral-finish frames, the host lane at the
  panel's size (`lane.jsonl`: the working count, a long name that needs
  you, the finish's marks and the bubble in each of its fonts), and the
  comedy (`comedy.jsonl`: the yawn, the sneeze's wind-up, the doze, the
  long yawn, the zoomies at either edge, a snore, the hiccups and the
  gift).
  `--accept` updates only the gel goldens, after looking at them.
  `boopctl run` reads the board's `hello` to pick the matching face.

These are simulator and host checks. Display throughput on the board
and speaker review are separate.

## Imported export's recorded result

The colleague's imported validation report recorded these passes on
2026-10-02. They describe the original audition before the engine split;
they were not all rerun for the current scene implementation. Current
executed checks and browser captures are in the phase evidence above.

- Deterministic builder and offline validator: 42 moods, 44 expressions,
  22 states, 924 explicit coverage cells; 295 directed edges (224 ordinary,
  71 dramatic), ordinary graph strongly connected and retained IDs intact.
- All seven accepted V1 source hashes and the original blue gel fragment
  shader hash match; catalogue export and local Markdown links pass.
- 27 seeded procedural sound renders (nine recipes × three variants)
  are deterministic/finite/bounded; mute is silent. Peak at the default
  audition gain was 0.28533. This is numeric QA, not physical listening QA.
- Real headless Chrome: shader compilation, all expression selections and
  normalized weights, three happy gestures, mouse/touch drag, bounded
  pull, release settling, mobile width, reduced-motion path, manual sound
  button/play/stop UI, and a separate genuinely WebGL-disabled Canvas
  fallback all passed. No browser console/page errors remained.
- Every package script's `--help` ran; Git whitespace checks and the
  repository's identical CLAUDE.md/AGENTS.md check passed.

The browser run used installed Playwright/Chrome overrides and
`BOOP_CAPTURE_FACES=0`: all faces were selected/checked, but this export
did not generate a new full contact sheet or individually replay every
gesture. Temporary drag/mobile/fallback screenshots were inspected locally
and are not committed. No runtime assets depend on those pictures.

## Limits that remain

- V3 artwork and the new SFX sketches need owner artistic/listening review.
- The full reference scene matrix and host-fact router are implemented.
  The owner approved the representative set. Directed bridges are implemented
  and checked; the selected clips require the owner's spot-check. The opt-in host
  graph and bundled Mac mirror are implemented; the native port now passes the separate `check-port.py` gate. Contact audio is implemented;
  timbres remain sketches pending speaker review.
- All expressions are browser-selectable. Prior recipe execution checked
  three happy gestures; it did not exhaustively play every recipe.
- Drag checks concern browser-local releases. Cross-container termination,
  real touch hardware and physical audio latency are separate tests.
- WebGL and Canvas do not have identical materials. The integer firmware renderer is separate; its builds, native trace checks
  and screenshots are recorded in the integration evidence. Physical performance
  and speaker checks are pending. These package checks require no hooks, Jev
  key or paid API calls.
