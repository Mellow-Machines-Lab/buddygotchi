# VideoG Slime Blob — the gel slime's design

Updated 2026-11-25. Imported from `VideoG-Slime-Blob` on 2026-10-02, this
is the design of Boop's gel slime: its moods, faces, acting, scenes and
sounds as data. The slime has one engine, the C++ one the AMOLED runs
(`character/firmware/src/render/gel/`), which the simulator and the
Mac's mirror of the board run too ([CHARACTER.md](https://github.com/Mellow-Machines-Lab/buddygotchi/blob/main/characters/CHARACTER.md)
§9). [slimegen](../../tools/slimegen/README.md) bakes this design into the
engine's tables. The JavaScript reference engine it was first written in,
with its WebGL preview, traces and checks, retired once the engine was the
C++ one alone; git keeps it. This is a separate, code-rendered character
series; the pixel animation bank it once stood beside went with Pixel and
the CYD, both archived.

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

Review it on the board: the [Character Studio](https://github.com/Mellow-Machines-Lab/buddygotchi/blob/main/characters/studio/README.md)'s
board is the firmware itself: every rig clip as a move in its group
(each clip's `group`), every face at rest and the change between two, each
skit's Moment with its invite answered or missed, and the motion layer's
switches; and in its **Tools** the review sets (recorded from the board
as silent clips) and the sound sketches. From the repository root:

```sh
python3 simulator/web/serve.py
```

Then open `http://127.0.0.1:8206/characters/studio/`. To save the review clips, start the
server with `--capture-dir DIR` (an empty folder); it saves only the clips
the pack's [review-sets.json](../../studio/review-sets.json) names, and
never over a file. After editing this design, bake it and check it:

```sh
node character/tools/slimegen/slimegen.mjs
make -C internal fw-test
internal/tools/boopctl sim
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
| Acting | Three authored gesture recipes per expression; idle comedy: a yawn and a sneeze for every mood, zoomies for excited | Owner review of the comedy on the board |
| Drag | Bounded local surface pull, face follows body, release wobble | Real touchscreen QA |
| Mood changes | The face crosses over, and the body gives one of three small beats at a change of mood | Owner review on the board |
| Activity/state | All 21 states in eight scene families, one set of takes for each state with the mood's timing, persistent desk/cards and factual contexts/outcomes; asleep's snore, a success's hiccups, proud's gift; a gag and a borrowed face for each of the board's ten gestures and the notice's three takes; occasions for idle, typing and sleep | Physical board measurements/review |
| Sounds | Contact-synchronized cues, sparse and voice-first, cut from procedural sketches (a sneeze and a snore's breath among them) | Speaker review and physical audio latency; the snore's level |

**Coverage is earned by execution.** `test_gel` plays every canonical mood
in every state and each of its takes, a change from every face to every
other, the interruptions, a finger, and every frame against the bounds
of what may be drawn ([VALIDATION.md](VALIDATION.md)). The owner approved
the initial 24-clip representative set before the matrix was filled out.

### Folder map

- [MOODS.md](MOODS.md): how the 7 moods and the 24 faces fit; the table
  itself is the pack's `character.json`.
- [expressions.json](expressions.json): V3 art profiles, reference mapping,
  three gesture recipes per expression, the comedy gags idle plays
  (`gags`, an expression's own `gags`), the board's gestures
  (`gestures`), the notice's takes (`notices`) and the occasions' bodies,
  a gag or a take each (`pastimes`: the face's table says when each
  plays). Edit this, then run slimegen.
- [STATES.md](STATES.md): the 21 states in their eight scene families, and
  how the host's events reach them.
- [CONTINUITY.md](CONTINUITY.md): the persistent actor, layer ownership,
  the scenes, comedy, gestures, tagged pastimes, the mood beat and the rules of what is
  drawn, each with the C++ that keeps it.
- [VALIDATION.md](VALIDATION.md): what checks each rule.
- [sound/sound-plan.json](sound/sound-plan.json), [sound/README.md](sound/README.md)
  and [sound/sfx.js](sound/sfx.js): the sound specification and the
  procedural sketches slimegen cuts the board's effects from.
- The scenes, faces and dome as slimegen bakes them are its own code:
  `character/tools/slimegen/scenes.mjs` (every state's recipes),
  `face.mjs` (each face's controls), `painter.mjs` (each face's art) and
  `mesh.mjs` (the dome and its material).

## 1. Mood, state, personality and variation are different things

**Mood** is the feeling the buddy has settled into. **State** is what the
host knows is happening. **Personality** governs how this character
interprets events and performs feelings, not which tool may run.
**Variation** is a local bounded choice of choreography in the same
mood/state; it is not another mood or an intensity value selected by Jev.

The control vocabulary remains `mood` + `state`. Host-owned facts such as
`outcome` for completion select compatible designs.
The runtime may keep clock/seed/physics/variation bookkeeping, but those
are internal renderer controls, not new LLM-selected emotional axes.

Example: a grumpy slime switches from terminal work to a web search. The
desk remains, its eyes remain grumpy, velocities continue, and a search
cue replaces the terminal cue. Its crossness cools by itself, a level at
a time. A tool change alone neither resets it to calm nor escalates it.

## 2. Moods and faces

The pack's [character.json](../../character.json) is the one source: its
`lasting` table has the 7 moods Boop settles into, each with its fade, and
its `moods` the 18 faces the Mac picks from, and its `board_faces` six
more the board draws, the meme faces. Read it there; nothing here
restates it. [MOODS.md](MOODS.md) says how the two fit.

What the design holds for each face is in
[expressions.json](expressions.json): its art, its scenes' timing traits,
any bit of its own, and its sound profile in `sound/sound-plan.json`. The
board's own sleeping face is the alternate `calm:asleep`, which is no
mood. Each lasting mood's idle move is a rig clip, `rig/clips/idle-<mood>.json`
([CONTINUITY.md](CONTINUITY.md), Idle moves).

There is no mood graph. Jev may move to any mood when what happened gives
a reason; the app fades a mood by its minutes and counts how cross it is.
The body gives a small beat when the mood changes
([CONTINUITY.md](CONTINUITY.md), The mood beat).

## 3. Use the state system, without multiplying scene designs

Preserve every existing semantic state ID and its event meaning. Simplify
**visual scenes**, not event coverage: [STATES.md](STATES.md) groups the IDs into
eight reusable scene families. Most work states share one persistent
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

A state has one set of takes; the mood shapes it by its traits alone:
sad works later and slower and softer, grumpy earlier and firmer. Keep
them the same blob with the same desk. Visual drama need not add dense audio.

`task_complete` has separate success/failure coverage under the same
state, and a success comes in three sizes ([CONTINUITY.md](CONTINUITY.md),
Finishes). Failure must never use the trophy, fanfare or cheer; `error` is an observed
tool failure, not automatically a failed whole task. `reply_ready` is a
ready reply, not an accomplishment. See [STATES.md](STATES.md).

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

A change of mood gets one of three small body beats (CONTINUITY.md, The
mood beat). Semantic face controls retarget from the current interpolated
pose; body springs keep their motion. State
transitions use common enter/exit phases while preserving desk props.
Attention must interrupt decorative actions promptly without destroying
the body's motion state. Quiet states play no beat.

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

This package is **nonshipping design data** under `character/design/`, in Boop's pack.
The AMOLED ships the generated native gel catalogs.
The moods and faces Boop runs are the pack's
`character.json`, which `character/tools/slimegen` reads for the faces'
names and the mood each is of.
The gel engine has been checked on the board for performance. Owner
appearance/listening review remains separate.

The repository evolved after the earlier transcript examples:

- [agent-hooks](https://github.com/Mellow-Machines-Lab/buddygotchi/blob/main/agent-hooks/README.md) normalizes source hooks and
  tracks sessions/attention. It includes subagent start as well as end.
- [MellowHarness](https://github.com/Mellow-Machines-Lab/buddygotchi/blob/main/mellowharness/README.md) owns generic events, logging,
  multiple-choice questions and output execution—not slime logic.
- [LinkKit](https://github.com/Mellow-Machines-Lab/buddygotchi/blob/main/linkkit/README.md) owns state/do/hello/ev and the
  device's turn/lifecycle. Do not bypass it or put rendering into Jev.
- Boop's `app/BoopKit/Core/Activity.swift` classifies work; `Core` owns
  factual priority; `Outputs/MoodOutput.swift` and `Brains/MoodMap.swift` own
  Boop's emotional choices; `Outputs/MomentOutput.swift` owns reactions.
- `StateSnapshot.swift` and `DeviceLink/BoopDevice.swift` express Boop's
  vocabulary over LinkKit. Existing `state.base` is asleep/idle/working;
  `act`, `attn` and `do` select the other visuals. The design's `state`
  parameter is not a new wire field.
- `firmware/src/render/` and `firmware/src/app/` render the selected board
  face; the gel's is `character/firmware/src/render/gel/`, whose
  `face.cpp` turns what the board's Behaviour follows into the engine's
  facts, mood and moments. `slimegen` builds the gel catalogs and authored vector face paths. The
  native renderer uses an integer mesh and rasterizer, with no GPU.

The old log's `ts/type/phase` shape is accepted as legacy; current logs
use `at/kind/data` and MellowHarness self `did`/`ended`. Current events also
include talk, presence and separate needs_you. Use the current code and
[LinkKit's spec](https://github.com/Mellow-Machines-Lab/buddygotchi/blob/main/linkkit/SPEC.md) as contracts, not an old
copied schema. Coverage of both forms is in [STATES.md](STATES.md).

Gel firmware recognizes every canonical mood. Sending a new
ID such as `focused` to old firmware does **not** enable its face;
unknown moods fall back. The Mac maps outgoing IDs using `hello.face`.

The owner chose one face per board: integer gel on the AMOLED, behind a
shared face interface (pixel on the CYD is archived). Never stream frames over the
control link or claim ESP32 performance without actual board measurements
(`boopctl ping`'s `draw_us`).

## 7. Handover prompt for the next engineer

> Read this README, MOODS, STATES, CONTINUITY, VALIDATION and
> sound/README plus the repository AGENTS.md before editing. The slime's
> design is this package's data and slimegen's scenes, faces and mesh;
> its one engine is the C++ in character/firmware/src/render/gel/,
> held to its rules by test_gel and the gel goldens. Keep the same
> original blue translucent glowing body and accepted V1 motion. Change a
> mood's face or acting in expressions.json, a state's choreography in
> slimegen's scenes.mjs, behaviour in the C++ engine, and pin each rule
> you change in test_gel. Look at what you changed on the board, in the
> Character Studio or with boopctl sim.
> Do not generate voices, spend credits, flash hardware, push, open a PR
> or merge without the owner's consent.

### Acceptance before production integration

- All canonical moods and reference alternates are cute/readable at the
  real viewport, including angry, wounded and the new curious; owner art review.
- Every mood/state cell plays truthfully (`test_gel`); every completion
  outcome is covered.
- Every change of face crosses over continuously; state changes preserve
  mood and springs. Ten-minute working runs contain no reset/flash.
- Interruptions and rapid event bursts cannot hide attention, replay old
  dings, claim false success, produce a stuck grab or approve a tool.
- Sound events follow physical cues; silence/mute and future voice
  headroom work. Listen on the actual output device.
- Package QA is not hardware approval.
