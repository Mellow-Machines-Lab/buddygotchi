# VideoG Slime Blob — the gel slime's design

Updated 2026-10-24. Imported from `VideoG-Slime-Blob` on 2026-10-02, this
is the design of Boop's gel slime: its moods, faces, acting, scenes and
sounds as data. The slime has one engine, the C++ one the AMOLED runs
(`characters/boop/firmware/src/render/gel/`), which the simulator and the
Mac's mirror of the board run too ([CHARACTER.md](../../../CHARACTER.md)
§9). [slimegen](../../tools/slimegen/README.md) bakes this design into the
engine's tables. The JavaScript reference engine it was first written in,
with its WebGL preview, traces and checks, retired once the engine was the
C++ one alone; git keeps it. This is a separate, code-rendered character
series, not a replacement of the shipping pixel animation bank (the CYD
keeps that).

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

Review it on the board: the [Character Studio](../../../studio/README.md)'s
**Gel on the board** card is the firmware itself, every mood and state on
its matrix, transitions measured frame by frame, and in its **Tools** the
review sets (recorded from the board as silent clips) and the sound
sketches. From the repository root:

```sh
node characters/studio/serve.cjs --port 4190
```

Then open `http://127.0.0.1:4190/`. To save the review clips, start the
server with `--capture-dir DIR` (an empty folder); it saves only the clips
the pack's [review-sets.json](../../studio/review-sets.json) names, and
never over a file. After editing this design, bake it and check it:

```sh
node characters/boop/tools/slimegen/slimegen.mjs
make -C internal fw-test
internal/tools/boopctl sim --face gel
```

None of these launches Boop, installs agent hooks, touches Bluetooth or
the Keychain, or calls Jev, ElevenLabs or anything paid. What checks what is
in [VALIDATION.md](VALIDATION.md).

## What exists, and what you must still build

| Component | Included now | Remaining work |
| --- | --- | --- |
| Body/material | The gel dome, sampled with its blue glow and studio material into a mesh the board deforms and projects every frame (slimegen's `mesh.mjs`) | Art review on the panel |
| Baseline motion | Accepted V1 springs and timing, their numbers held by `test_gel` | Any change is a named motion revision |
| Faces | V3 candidate faces for every canonical mood, plus two face alternates (slimegen's `painter.mjs`, baked as vector paths) | Owner review of cuteness/readability at target size |
| Acting | Three authored gesture recipes per expression; idle comedy: a yawn, a doze and a sneeze for every mood, a long yawn for the low moods, zoomies for excited | Owner review of the comedy on the board |
| Drag | Bounded local surface pull, face follows body, release wobble | Real touchscreen QA |
| Mood topology | Complete design graph and 295 directed bridges, three variants each | Host eligibility/pacing, Jev choices |
| Activity/state | All 25 states in nine scene families, persistent desk/helpers/cards, the full mood matrix and factual contexts/outcomes; asleep's snore, a success's hiccups, proud's gift; a gag and a borrowed face for each of the board's ten gestures and the notice's three takes; occasions for idle, typing and sleep | Physical board measurements/review |
| Sounds | Contact-synchronized cues, sparse and voice-first, cut from procedural sketches (a sneeze and a snore's breath among them) | Speaker review and physical audio latency; the snore's level |

**Coverage is earned by execution.** `test_gel` plays every canonical mood
in every state and each of its takes, every directed edge in each of its
variants, the interruptions, a finger, and every frame against the bounds
of what may be drawn ([VALIDATION.md](VALIDATION.md)). The owner approved
the initial 24-clip representative set before the matrix was filled out.

### Folder map

- [emotion-graph.json](emotion-graph.json): canonical mood IDs, meanings,
  edges, evidence and provisional pacing. Source of graph truth here; slimegen
  writes the pack's moods and the bridges' edges from it.
- [MOODS.md](MOODS.md): the moods to read (faces, bodies, gestures, comedy,
  edges), which slimegen writes from the graph and the expressions.
- [expressions.json](expressions.json): V3 art profiles, reference mapping,
  three gesture recipes per expression, the comedy gags idle plays
  (`gags`, `idleGags`, an expression's own `gags`), the board's gestures
  (`gestures`), the notice's takes (`notices`) and the looks' occasions
  (`occasions`). Edit this, then run slimegen.
- [STATES.md](STATES.md): the 25 states in their nine scene families, and
  how the host's events reach them.
- [CONTINUITY.md](CONTINUITY.md): the persistent actor, layer ownership,
  the scenes, comedy, gestures, occasions, bridges and the rules of what is
  drawn, each with the C++ that keeps it.
- [VALIDATION.md](VALIDATION.md): what checks each rule.
- [sound/sound-plan.json](sound/sound-plan.json), [sound/README.md](sound/README.md)
  and [sound/sfx.js](sound/sfx.js): the sound specification and the
  procedural sketches slimegen cuts the board's effects from.
- The scenes, faces and dome as slimegen bakes them are its own code:
  `characters/boop/tools/slimegen/scenes.mjs` (every state's recipes),
  `face.mjs` (each face's controls), `painter.mjs` (each face's art) and
  `mesh.mjs` (the dome and its material).

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

The graph uses an implicit `hold` choice. The shipping `MoodOutput` uses
the current mood's own ID for its stay option. Adapt between them in
Boop's Mood output; do not change MellowHarness's generic multiple-choice
machinery or mistake `hold` for a mood asset.

The graph's dwell, reversal and brief-reaction values are **provisional
design values**, and the shipping host doesn't enforce them: its mood
question offers staying and every move the pack lists from the current
mood, the dramatic ones marked as jumps, and the steering's prose carries
the pacing (characters/CHARACTER.md §5). Steps 3 and 4 above are this
design's proposal, not what ships. A brief surprised/stunned/speechless
reaction still needs a justified outgoing recovery edge, which its
steering names as the mood it fades to.

The graph is a character-engineering design, not a validated psychology
instrument or a detector of the user's emotions. Research provenance is
retained in its `source` block; no source validates our exact topology.

## 3. Use the state system, without multiplying scene designs

Preserve every existing semantic state ID and its event meaning. Simplify
**visual scenes**, not event coverage: [STATES.md](STATES.md) groups the IDs into
nine reusable scene families. Most work states share one persistent
computer/keyboard, with small overlays and state-specific behavior.
There is no need for hundreds of unrelated professions or props.

Every mood/state cell has three takes (idle six or seven, asleep four, a
successful finish four: the comedy of [CONTINUITY.md](CONTINUITY.md); a
gesture ten, one for each), each played by `test_gel`. Every one is
implemented on the board or a justified quiet alias.
For normal active states, compose its mood face/acting profile with the
shared state scene and bounded variations. For asleep/no_app, reuse quiet
resting choreography and suppress dramatic acting/SFX while retaining the
stored mood. These are deliberate aliases, not angry sleeping faces; asleep
only snores now and then, a slight swell and a soft breath.

Special cases deserve authored composition: crying+working can slump and
occasionally drip liquid tears by the keyboard; grumpy+terminal has compact
firm contacts; frightened+working has hesitant guarded input. Keep them
the same blob with the same desk. Visual drama need not add dense audio.

`task_complete` has separate success/failure coverage under the same
state. Failure must never use the trophy/fanfare; `error` is an observed
tool failure, not automatically a failed whole task. `reply_ready` is a
ready reply, not an accomplishment. `starting` has new_task/session/
continuation/compacted variants with truthful card wording. See [STATES.md](STATES.md).

The bottom 20% is the host's lane: the board's strip and bubble, softly
rounded and readable. The scenes keep their props above it. Do not
shrink an outer frame: there should be no decorative screen frame.

## 4. Continuous animation and variation

See [CONTINUITY.md](CONTINUITY.md) for how it's built. The core
rule: keep one actor alive, blend target controls, add bounded impulses
to its current state, and let its residual wobble settle. Never recreate
the mesh/clock/springs when mood, state or variation changes.

Three variants must differ in action rhythm/intent—not just amplitude.
Working: short typing burst then think; two irregular bursts then glance;
lean in, one confirm, relax. Choose non-repeating variants at safe action
boundaries, with bounded timing/pose jitter. No LLM generates intermediate
frames or decides each tap. Code owns physical continuity and small
randomness; Jev only chooses a permissible emotional step.

Every graph edge has three **composable bridges** (CONTINUITY.md,
Directed edge bridges), each played by `test_gel`. Semantic face controls retarget from the current interpolated
pose; body springs retain their motion through gather/release or recoil beats.
The 13 edge clips (the Studio's review set) are for the owner's visual spot-check. State
transitions use common enter/exit phases while preserving desk props.
Attention must interrupt decorative actions promptly without destroying
the body's motion state. Quiet states use minimal bridges.

## 5. Basic slime sounds, not speech

Follow [sound/README.md](sound/README.md). Design wet-but-clean gel squish,
elastic rebound, soft plop, touch and occasional crisp keyboard contact.
Do not use background music, robotic mumble, a human sob/laugh recording
or ElevenLabs in this phase. The sketches are synthesized from code;
slimegen cuts the board's effects from them.

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

This package is **nonshipping design data** under `characters/boop/design/`, in Boop's pack.
CYD ships [boop-sound-bank-v4](../../../pixel/design/boop-sound-bank-v4/README.md); AMOLED ships the generated native gel catalogs.
The host graph, the one mood graph Boop runs, with its pacing, is
generated into Boop's `character.json` by
`characters/boop/tools/slimegen`. The design's `fallback`s stay design
data: the engine has none, and Pixel's art lends its 13 moods to the
others by a temporary table of its own (`characters/pixel/tools/borrowed.json`).
The gel engine has been checked on the board for performance. Owner
appearance/listening review remains separate.

The repository evolved after the earlier transcript examples:

- [agent-hooks](../../../../agent-hooks/README.md) normalizes source hooks and
  tracks sessions/attention. It includes subagent start as well as end.
- [MellowHarness](../../../../mellowharness/README.md) owns generic events, logging,
  multiple-choice questions and output execution—not slime logic.
- [LinkKit](../../../../linkkit/README.md) owns state/do/hello/ev and the
  device's turn/lifecycle. Do not bypass it or put rendering into Jev.
- Boop's `app/BoopKit/Core/Activity.swift` classifies work; `Core` owns
  factual priority; `Outputs/MoodOutput.swift` and `MoodGraph.swift` own
  Boop's emotional choices; `Outputs/ReactOutput.swift` owns reactions.
- `StateSnapshot.swift` and `DeviceLink/BoopDevice.swift` express Boop's
  vocabulary over LinkKit. Existing `state.base` is asleep/idle/working;
  `act`, `attn` and `do` select the other visuals. The design's `state`
  parameter is not a new wire field.
- `firmware/src/render/` and `firmware/src/app/` render the selected board
  face; the gel's is `characters/boop/firmware/src/render/gel/`, whose
  `face.cpp` turns what the board's Behaviour follows into the engine's
  facts, mood and moments. `facegen`/`sfxgen` build the pixel bank;
  `slimegen` builds the gel catalogs and authored vector face paths. The
  native renderer uses an integer mesh and rasterizer, with no GPU.

The old log's `ts/type/phase` shape is accepted as legacy; current logs
use `at/kind/data` and MellowHarness self `did`/`ended`. Current events also
include talk, presence and separate needs_you. Use the current code and
[LinkKit's spec](../../../../linkkit/SPEC.md) as contracts, not an old
copied schema. Coverage of both forms is in [STATES.md](STATES.md).

Gel firmware recognizes every canonical mood; pixel retains its compatibility
vocabulary. Sending a new
ID such as `frightened` to old firmware does **not** enable its face;
unknown moods fall back. The Mac maps outgoing IDs using `hello.face`.

The owner chose one face per board: pixel on the CYD, integer gel on the
AMOLED, behind a shared face interface. Never stream frames over the
control link or claim ESP32 performance without actual board measurements
(`boopctl ping`'s `draw_us`).

## 7. Handover prompt for the next engineer

> Read this README, MOODS, STATES, CONTINUITY, VALIDATION and
> sound/README plus the repository AGENTS.md before editing. The slime's
> design is this package's data and slimegen's scenes, faces and mesh;
> its one engine is the C++ in characters/boop/firmware/src/render/gel/,
> held to its rules by test_gel and the gel goldens. Keep the same
> original blue translucent glowing body and accepted V1 motion. Change a
> mood's face or acting in expressions.json, a state's choreography in
> slimegen's scenes.mjs, behaviour in the C++ engine, and pin each rule
> you change in test_gel. Look at what you changed on the board, in the
> Character Studio or with boopctl sim, and rebuild the Mac's mirror of
> the board (firmware/tools/mirror.sh) when what the board draws changes.
> Do not generate voices, spend credits, flash hardware, push, open a PR
> or merge without the owner's consent.

### Acceptance before production integration

- All canonical moods and reference alternates are cute/readable at the
  real viewport, including angry/hurt/crying/frightened; owner art review.
- Every mood/state cell plays truthfully (`test_gel`); every completion
  outcome and starting context is covered.
- Every directed mood edge bridges continuously; state changes preserve
  mood and springs. Ten-minute working runs contain no reset/flash.
- Interruptions and rapid event bursts cannot hide attention, replay old
  dings, claim false success, produce a stuck grab or approve a tool.
- Sound events follow physical cues; silence/mute and future voice
  headroom work. Listen on the actual output device.
- Package QA is not hardware approval.
