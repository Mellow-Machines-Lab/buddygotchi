# VideoG Slime Blob — colleague handover

Updated 2026-10-15. Imported from `VideoG-Slime-Blob` and integrated on
`main`: this engine is the reference the AMOLED's gel face ports and the
Mac's popover bundles. This is a separate, code-rendered character series, not
a replacement of the shipping pixel animation bank (the CYD keeps that).

## Start here

Build **one living, coherent slime**, not a collection of interchangeable
emoji pictures. Keep the same blue, softly glowing, semi-translucent body,
rest silhouette, face placement system and material. Mood retargets its
face and acting; state retargets its activity. Its spring displacement,
velocity and animation clock survive both changes. Squash, stretch, tilt,
local indentation and rebound are allowed; a new silhouette/character,
full-body color swap or flash to another asset is not.

The personality is overconfident, emotionally transparent, theatrical,
easily wounded and secretly needy: a tiny dramatic coworker who keeps doing
the job while expressing how it feels. Negative moods must still be cute,
not human-looking rage, accusation, coercion, guilt or tool misbehavior.
Reference images inform the simple rounded facial language—not copied
Rimuru/Pokémon accessories, exact character identity or licensed artwork.

Review it in the [Character Studio](../../../studio/README.md) as **Gel slime**: open
`characters/studio/index.html` directly in a modern browser. It uses local JS/CSS
only, including the manual sound sketches. WebGL is
preferred; a simpler Canvas fallback is included. No backend, model file,
saved face image, video, recording, API key or LLM is needed to run it.

From the repository root:

```sh
node characters/boop/design/slime-blob/tools/check.cjs
node characters/studio/serve.cjs --port 4190
```

Then open `http://127.0.0.1:4190/`. Stop the server with Ctrl-C. Rebuild
derived catalogues after editing the JSON design inputs:

```sh
node characters/boop/design/slime-blob/tools/build.cjs
```

If browser downloads of the recorded clips are unavailable, opt into local
saving when starting the server (choose an empty output folder):

```sh
node characters/studio/serve.cjs --port 4190 --capture-dir /tmp/slime-review-clips
```

After **Record review set** (in the studio's **Tools**) finishes, **Save review clips locally** writes
the reviewed set there. The server accepts only the named review clips,
requires its local page's request token and never overwrites existing files.
Without `--capture-dir`, it remains a read-only static server.

The builder is a deterministic mechanical export, not AI generation. Node
18+ is sufficient. Browser QA is optional; instructions and actual checks
are in [VALIDATION.md](VALIDATION.md). No command here launches Boop,
installs agent hooks, accesses Bluetooth/Keychain, calls Jev/ElevenLabs or
consumes credits.

## What exists, and what you must still build

| Component | Included now | Remaining work |
| --- | --- | --- |
| Body/material | Procedural gel dome, blue glow, black stage, WebGL + Canvas fallback | Art review, production renderer/board budget |
| Baseline motion | Accepted V1 springs and timing, source-hash protected | Ports require equivalence tests, not just matching names |
| Faces | V3 candidate faces for every canonical mood, plus two face alternates | Owner review of cuteness/readability at target size |
| Acting | Three authored gesture recipes per expression; recipes share primitives | Tune every recipe in motion, layer activity choreography |
| Drag | Bounded local surface pull, face follows body, release wobble | Host-boundary termination and real touchscreen QA |
| Mood topology | Complete design graph and 295 tested directed bridges, three variants each | Host eligibility/pacing, Jev choices, production enum migration |
| Activity/state | All 22 routed scenes, persistent desk/helpers/cards, full mood matrix and factual contexts/outcomes | Physical board measurements/review |
| Sounds | Contact-synchronized scheduler, sparse voice-first browser player and procedural sketch library | Speaker review and physical audio latency |

**Coverage is earned by execution.** The preview has all scene families, an
event-script player and local clip recording. Its direct mood selector
bypasses graph traversal; pokes preserve mood. Full-matrix tests exercise
every active cell and all three variations, each start context and completion
outcome, plus the explicit quiet aliases. The owner approved the initial
24-clip representative set before expansion. All directed bridges are exercised
from mid-gesture, with rest, drag and alert interruption checks. Production
graph gating remains planned. Contact-synchronized sound is implemented with
sketch timbres and an opt-in browser player.

### Folder map

- [emotion-graph.json](emotion-graph.json): canonical mood IDs, meanings,
  edges, evidence and provisional pacing. Source of graph truth here.
- [MOODS.md](MOODS.md): generated readable inventory, face descriptions,
  body behavior and every outgoing ordinary/dramatic edge.
- [expressions.json](expressions.json): V3 art profiles, reference mapping,
  three gesture recipes per expression. Edit this, then rebuild.
- [state-plan.json](state-plan.json) and [STATES.md](STATES.md): activity
  coverage, scene reuse, events and outcome/context distinctions.
- [coverage.json](coverage.json): generated checklist for every mood×state;
  quiet aliases are explicit, not missing rows.
- [transitions.json](transitions.json): every graph edge with tested reusable
  primitives and three implemented variants.
- [CONTINUITY.md](CONTINUITY.md): persistent actor, layer ownership,
  transition/variation authoring and renderer integration plan.
- [sound/sound-plan.json](sound/sound-plan.json), [sound/README.md](sound/README.md)
  and [sound/sfx.js](sound/sfx.js): sound specification and executable sketches.
- [contracts/motion-v1.json](contracts/motion-v1.json): accepted source
  blocks; [tools/check-motion.cjs](tools/check-motion.cjs) protects them.
- [engine/index.mjs](engine/index.mjs): pure seeded reference engine, with
  an injected presentation clock and persistent springs.
- [render/webgl.mjs](render/webgl.mjs), [render/canvas2d.mjs](render/canvas2d.mjs)
and [render/face-painter.mjs](render/face-painter.mjs): draw engine controls.
  [render/props.mjs](render/props.mjs) draws the shared desk, cards and host lane.
- [preview/character.mjs](preview/character.mjs): the slime as a studio
  character: engine, renderer, sound and pointer input behind
  `window.SlimeStudio`, a local audition API, not a device protocol.
  `tools/build.cjs` bundles these modules into `preview/slime.bundle.js`
  without dependencies, so opening the studio with `file://` still works.
- [tools/trace.mjs](tools/trace.mjs): headless fixed-step channel traces,
  from [scripts](scripts/) into [traces](traces/).
- [tools/check-scenes.mjs](tools/check-scenes.mjs): full-matrix scene
  checks and the earned coverage manifest. **Record review set** in the
  studio captures the verified cases as silent, local WebM clips. Download
  them from the review gallery; no camera or desktop capture is involved.
- [tools/check-bridges.mjs](tools/check-bridges.mjs): every directed edge and
  variation, face continuity, context suppression and the 13-case edge review.
  Choose **Directed mood bridges** in the studio's **Review set** selector to record
  that set. The generated [preview/review-cases.json](preview/review-cases.json)
  limits the server's capture filenames to these two verified sets.
- [tools/smooth.mjs](tools/smooth.mjs): the per-frame bounds on what is
  drawn (no jolt at an event, face ratios in range, props without pops, a
  face that never fades) that the engine, bridge and scene checks apply.

## 1. Mood, state, personality and variation are different things

**Mood** is the persistent emotional graph node. **State** is what the
host knows is happening. **Personality** governs how this character
interprets events and performs feelings, not which tool may run.
**Variation** is a local bounded choice of choreography in the same
mood/state; it is not another mood or an intensity value selected by Jev.

The control vocabulary remains `mood` + `state`. Host-owned facts such as
`ctx` for starting and `outcome` for completion select compatible designs.
The runtime may keep clock/seed/physics/variation bookkeeping, but those
are internal renderer controls, not new LLM-selected emotional axes.

Example: a grumpy slime switches from terminal work to a web search. The
desk remains, its eyes remain grumpy, velocities continue, and a search
cue replaces the terminal cue. A separately justified graph decision may
later soften grumpy → irritated, or branch grumpy → whiny. A tool change
alone neither resets it to calm nor escalates it.

## 2. The expanded mood system

This branch's design target is the graph in [emotion-graph.json](emotion-graph.json):
42 moods, 12 presentation families and 295 directed edges. Ordinary edges
alone make the graph strongly connected; every node can eventually reach
every other. There are at most eight outgoing destinations plus staying.
Those are topology properties, not guarantees that every edge is eligible
under every context.

All 13 shipping IDs are retained: happy, excited, proud, curious,
determined, grumpy, sad, calm, engaged, annoyed, irritated, whiny, wounded.
The other 29 are additions; none is deleted. `wounded` displays as Hurt;
`stunned` maps the reference's Shook; `mischievous` maps Naughty. `idle` is
a state, not a mood. `comfy:rosy` and `speechless:tearful` are face
alternates in [expressions.json](expressions.json), not graph nodes.

The node list and exact adjacencies live in [MOODS.md](MOODS.md). The main
within-family ladders are:

- pleased → happy → excited
- annoyed → irritated → grumpy → angry
- disappointed → sad → crying
- uneasy → scared → frightened
- surprised → stunned; confused → baffled; tired → exhausted

These are named intensity neighborhoods, not compulsory journeys. Calm,
comfy, lazy and bored are distinct motivations, not four strengths of
one feeling. Whiny is an active plea; wounded is hurt/withdrawal. Exhausted
can be intense but slow. Never compare intensity numerically across
families or ask Jev for a global affect vector.

Cross-family routes make this a web. Examples actually present in the
graph: grumpy → whiny (ordinary), grumpy → sad (dramatic), frightened →
wounded/sad (ordinary), frightened → angry (dramatic), scared → relieved
(ordinary), wounded → angry (dramatic), proud → embarrassed (dramatic).
Do not assume the reverse edge exists, or belongs to the same category.

### How Jev learns the next options

The **Boop host**, not generic MellowHarness or the renderer, owns the full
adjacency data and eligibility guards. For a mood question:

1. Take a decision snapshot: current mood, factual activity, mood age,
   current attention, personality and sanitized fresh evidence.
2. Read only that node's outgoing edges. Deduplicate event identity, so a
   repeated permission notification does not create a second escalation.
3. Filter ordinary edges by context/pacing. Escalation requires fresh
   relevant evidence; a frame, timer, animation loop or heartbeat is not
   evidence that an obstacle got worse. Quiet recovery can offer a
   justified neighbor without inventing success or clearing attention.
4. Admit dramatic edges only with strong new evidence for that particular
   branch. A tool failure is not danger; permission denial is not abuse.
5. Ask Jev to choose staying or one eligible neighbor with a one-line
   meaning. The full graph and all moods do not enter every prompt.
6. Check the answer against the decision ID, current mood, offered set and
   directed edge. Invalid or stale answers hold. Consume evidence once.
7. Retarget the same actor; preserve the factual state and unresolved alert.

The graph uses an implicit `hold` choice. The shipping `MoodAction` uses
the current mood's own ID for its stay option. Adapt between them in
Boop's Mood output; do not change MellowHarness's generic multiple-choice
machinery or mistake `hold` for a mood asset.

The graph's dwell, reversal and brief-reaction values are **provisional
design values**. The opt-in host policy now installs a tested selection
from those ranges, while v2 remains default. A brief surprised/stunned/speechless
reaction needs a justified outgoing recovery edge; it cannot teleport to
a remembered mood or be trapped by a long stable-mood cooldown. Implement
and test these exemptions before turning on the expanded graph.

The graph is a character-engineering design, not a validated psychology
instrument or a detector of the user's emotions. Research provenance is
retained in its `source` block; no source validates our exact topology.

## 3. Use the state system, without multiplying scene designs

Preserve every existing semantic state ID and its event meaning. Simplify
**visual scenes**, not event coverage: the state plan groups the IDs into
nine reusable scene families. Most work states share one persistent
computer/keyboard, with small overlays and state-specific behavior.
There is no need for hundreds of unrelated professions or props.

Every mood/state cell has three variants in [coverage.json](coverage.json),
with implementation status earned by full-matrix tests. All are implemented
in the reference engine or justified quiet aliases; this does not establish
production integration or port equivalence.
For normal active states, compose its mood face/acting profile with the
shared state scene and bounded variations. For asleep/no_app, reuse quiet
resting choreography and suppress dramatic acting/SFX while retaining the
stored mood. These are deliberate aliases, not angry sleeping faces.

Special cases deserve authored composition: crying+working can slump and
occasionally drip liquid tears by the keyboard; grumpy+terminal has compact
firm contacts; frightened+working has hesitant guarded input. Keep them
the same blob with the same desk. Visual drama need not add dense audio.

`task_complete` has separate success/failure coverage under the same
state. Failure must never use the trophy/fanfare; `error` is an observed
tool failure, not automatically a failed whole task. `reply_ready` is a
ready reply, not an accomplishment. `starting` has new_task/session/
continuation/compacted variants with truthful card wording. See [STATES.md](STATES.md).

The bottom 20% is reserved for host text/status in the **future device
composition**. Use softly rounded, readable gel-compatible text bubbles.
The reference scenes reserve this lane for host status. Do not
shrink an outer frame: there should be no decorative screen frame.

## 4. Continuous animation and variation

See [CONTINUITY.md](CONTINUITY.md) for the implementation plan. The core
rule: keep one actor alive, blend target controls, add bounded impulses
to its current state, and let its residual wobble settle. Never recreate
the mesh/clock/springs when mood, state or variation changes.

Three variants must differ in action rhythm/intent—not just amplitude.
Working: short typing burst then think; two irregular bursts then glance;
lean in, one confirm, relax. Choose non-repeating variants at safe action
boundaries, with bounded timing/pose jitter. No LLM generates intermediate
frames or decides each tap. Code owns physical continuity and small
randomness; Jev only chooses a permissible emotional step.

Every graph edge has an entry in [transitions.json](transitions.json).
They reference implemented **composable bridges**, with execution earning each
entry's status. Semantic face controls retarget from the current interpolated
pose; body springs retain their motion through gather/release or recoil beats.
The 13 edge clips are for the owner's visual spot-check. State
transitions use common enter/exit phases while preserving desk props.
Attention must interrupt decorative actions promptly without destroying
the body's motion state. Quiet states use minimal bridges.

## 5. Basic slime sounds, not speech

Follow [sound/README.md](sound/README.md). Design wet-but-clean gel squish,
elastic rebound, soft plop, touch and occasional crisp keyboard contact.
Do not use background music, robotic mumble, a human sob/laugh recording
or ElevenLabs in this phase. The audition sketches are synthesized from
code and generated samples in memory, not stored audio assets.

Synchronize a sound to a **visible physical cue** on the animation clock,
not a parallel evenly spaced metronome. Select sparse contacts, vary
which visible bursts sound, and leave most working/idle movement silent.
Every notification retains the same iconic ding family after its
mood-shaped taps; play once per new request, never once per loop/mood
change. Task success/failure have distinct one-shot attention signatures.

The existing quiet, voice-first mix remains the integration reference.
Future speech may duck routine SFX and use the scene's safe voice window,
but speech selection/recording is outside this package.

## 6. Current repository integration — read before changing production

This package is **nonshipping design code** under `characters/boop/design/`, in Boop's pack.
CYD ships [boop-sound-bank-v4](../../../pixel/design/boop-sound-bank-v4/README.md); AMOLED ships the generated native gel catalogs.
The host graph, the one mood graph Boop runs, with its pacing, is
generated into Boop's `character.json` by
`characters/boop/tools/slimegen`. The design's `fallback`s stay design
data: the engine has none, and Pixel's art lends its 13 moods to the
others by a temporary table of its own (`characters/pixel/tools/borrowed.json`). The native face port now passes complete
reference-trace equivalence, and has been checked on the board for
performance. Owner appearance/listening review remains separate.

The repository evolved after the earlier transcript examples:

- [agent-hooks](../../../../agent-hooks/README.md) normalizes source hooks and
  tracks sessions/attention. It includes subagent start as well as end.
- [MellowHarness](../../../../mellowharness/README.md) owns generic events, logging,
  multiple-choice questions and output execution—not slime logic.
- [LinkKit](../../../../linkkit/README.md) owns state/do/hello/ev and the
  device's turn/lifecycle. Do not bypass it or put rendering into Jev.
- Boop's `app/BoopKit/Core/Activity.swift` classifies work; `Core` owns
  factual priority; `Actions/MoodAction.swift` and `MoodGraph.swift` own
  Boop's emotional choices; `Actions/ReactAction.swift` owns reactions.
- `StateSnapshot.swift` and `DeviceLink/BoopDevice.swift` express Boop's
  vocabulary over LinkKit. Existing `state.base` is asleep/idle/working;
  `act`, `attn` and `do` select the other visuals. The design's `state`
  parameter is not a new wire field.
- `firmware/src/render/` and `firmware/src/app/` currently render the
  selected board face. `facegen`/`sfxgen` build the pixel bank; `slimegen`
  builds the gel catalogs and authored vector face paths. The native renderer
  uses an integer ellipse approximation, with no WebGL on the board.

The old log's `ts/type/phase` shape is accepted as legacy; current logs
use `at/kind/data` and MellowHarness self `did`/`ended`. Current events also
include talk, presence and separate needs_you. Use the current code and
[LinkKit's spec](../../../../linkkit/SPEC.md) as contracts, not an old
copied schema. Coverage of both forms is in [STATES.md](STATES.md).

Gel firmware recognizes every canonical mood; pixel retains its compatibility
vocabulary. Sending a new
ID such as `frightened` to old firmware does **not** enable its face;
unknown moods fall back. The Mac maps outgoing IDs using `hello.face`;
the v3 host graph remains opt-in and v2 remains unchanged.

The desktop WebGL renderer uses a mipmapped runtime face texture, a
supersampled scene buffer (the body is drawn offscreen, where the context's
antialiasing never reaches) and bloom buffers;
compact disk code does not imply tiny RAM/GPU cost. The original device
has no WebGL GPU and tight RAM. The owner chose one face per board:
pixel on CYD, integer gel on AMOLED, selected behind a shared face interface.
The completed native port has been measured on a flashed board. Never stream
frames over the control link or claim ESP32 performance without actual board
measurements. This desktop renderer remains the reference implementation.

## 7. Handover prompt for the next engineer

> Read this README, MOODS, STATES, CONTINUITY and sound/README plus the
> repository AGENTS.md before editing. Continue the VideoG Slime Blob
> series from the supplied procedural preview. Keep the same original
> blue translucent glowing body and accepted V1 motion. Build the shared
> activity layers for every state, compose them with every mood, and
> implement three genuinely different bounded variants per active cell
> with explicit quiet aliases. Cover every directed mood transition with
> continuous retargeting, not asset switching. Add reviewed procedural
> nonverbal gel/keyboard/attention SFX at visible contact cues, using the
> quiet voice-first policy. Implement host-side graph gating separately
> from rendering and preserve factual needs-you priority. Start with
> desktop preview; do not assume ESP32 WebGL support or change LinkKit.
> Update coverage and QA status honestly as work becomes real. Review a
> small representative set of positive/negative work and alert scenes
> with the owner before filling out the rest. Do not generate voices,
> spend credits, flash hardware, push further work, open a PR or merge
> without the owner's consent.

### Acceptance before production integration

- All canonical moods and reference alternates are cute/readable at the
  real viewport, including angry/hurt/crying/frightened; owner art review.
- Every coverage cell is implemented/tested or an explicit justified
  quiet alias; every completion outcome and starting context is covered.
- Every directed mood edge has a tested bridge; state changes preserve
  mood and springs. Ten-minute working runs contain no reset/flash.
- Interruptions and rapid event bursts cannot hide attention, replay old
  dings, claim false success, produce a stuck grab or approve a tool.
- Sound events follow physical cues; silence/mute/reduced motion and
  future voice headroom work. Listen on the actual output device.
- Production architecture/specs, enums and validation are updated only
  when integration is implemented; package QA is not hardware approval.

This branch push was requested on 2026-10-02. It authorizes this package
publication, not a merge, pull request, future pushes or paid generation.
