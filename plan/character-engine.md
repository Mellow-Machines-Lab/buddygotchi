# The character engine: the plan (2026-10-23)

One small engine that both characters, the low-res Pixel face and the
high-res gel slime, are drawn by, so any expression or animation flows into
any other, layers (scene, hats, signs, air, the lane) mix at runtime, and a
character is data that agents edit, from references a person gives them.
Simplicity first: where one engine for both would cost more than it saves,
the shared part shrinks to the contract (the rig, layers, anchors, clips)
and each face keeps its own insides.

## Why

Today each character is its own framework. Pixel is 1,175 baked flip-book
designs (its bank's SVG generators, baked by facegen), so nothing blends:
two drawings have nothing in between, and a nightcap had to be drawn into
every mood. The slime is a procedural engine (springs, recipes, gags) whose
body flows, but its faces are separate art swapped behind a blink, its
bottom lane pops, and it exists twice (a JavaScript reference and the
board's C++ port, matched frame for frame). Recorded in the simulator
(450 frames, 40 ms apart): a mood change closes the face to almost nothing
for a frame; going to work, the desk fades in over 240 ms but the lane and
its count appear in one frame.

## The shape

**Animate numbers, not pictures.** At any instant a character is a set of
numbers on a rig, the same set for every pack:

| Part | Channels (int16, thousandths unless said) |
| --- | --- |
| body | `x`, `y` (px), `squash` (−1000 tall … +1000 flat), `lean` (−1000 … +1000), `tilt`, `lift` (px) |
| eyes | `eyeOpenL`, `eyeOpenR` (0 shut … 1000 open), `eyeCurve` (−1000 sad arc … +1000 happy arc), `eyeSize` (500 … 1500), `gazeX`, `gazeY` (−1000 … 1000) |
| mouth | `mouthWidth` (0 … 1500), `mouthCurve` (−1000 frown … +1000 smile), `mouthOpen` (0 … 1000) |
| extras | `cheek`, `tear`, `sweat` (0 … 1000) |
| styles | `eyeStyle`, `mouthStyle`: an index into the pack's art, each with a mix toward the next one (0 … 1000) |

- An **expression** (happy, grumpy) is target values for some channels and
  a style for eyes and mouth.
- A **clip** (a cheer, a yawn, a notice, a gesture) is keyframed curves on
  channels, timed in ms, with cues (a sound, a contact) at times. Most are
  additive (offsets on what's there), so a yawn works in any mood.
- A **look** (idle, working, asleep) is a looping base clip, a scene (the
  desk), and whether the character dresses for the tags.
- **Continuous faces.** A happy closed-arc eye is an eye nearly shut with
  its curve up, so most expressions are points in one space and morph into
  each other. Only truly different shapes (hearts, X eyes, spirals) change
  style, and a style change cross-fades (both drawn, alphas crossing over
  ~200 ms); the face never disappears.

**The mixer**, one fixed stack, the same for both characters, each frame:

```
 base      the look's loop                         ← state.look
 mood      the expression's targets, eased by springs ← state.mood
 reaction  clips, each with a weight eased in and out ← do (task_complete, notice…)
 input     a poke or stroke as an impulse on the springs ← touch, motion
 → channels (critically damped springs carry every change: no jumps)
 → layers, each with an opacity eased in and out
 → the renderer
```

**The layers**, back to front: scene (desk, computer) · body · face ·
accessories (hats, glasses: on the head anchor) · held (sign, trophy, mug:
on the hands anchor) · air (snow, confetti, Zs: screen space) · lane (the
strip, the needs-you sign). The renderer reports anchors each frame (crown,
brim ring, hands ring, eyes) from the pose it draws, so layers ride the
body; every layer fades in and out (the lane included).

**One engine, two renderers.** Shared: the channel set, expressions, clips,
the mixer, layers and anchors (`firmware/src/render/rig/`, portable C++,
which the board, the native simulator and the WebAssembly simulator all
build). Per character: how channels become pixels.

- **Pixel's renderer** keeps its hand-drawn look as sprite parts: a small
  sheet of eye sprites at a few openness and curve steps, mouth sprites at
  a few widths and curves, cheeks, tears, mitts and props, from its bank's
  existing art. It picks the nearest sprite each frame and places it on the
  rig: blends step through sprites, fluid at pixel scale.
- **The slime's renderer** is its gel painter, fed the rig's channels. Its
  body springs, recipes and gags stay as they are at first (an adapter);
  they move into clips once Pixel's are proven.

**The wire doesn't change.** The Mac still sends `state` and `do`; the
board still decides when things play.

## A pack is data

```
characters/<pack>/
  character.json      name, renderer (gel | pixel), palette  (as now, plus renderer)
  rig/
    expressions.json  happy: {eyeCurve: 800, eyeOpen: 250, mouthWidth: 1200, …, eyeStyle: "arc"}
    clips/*.json      {"id": "notice", "ms": 900, "additive": true,
                       "tracks": {"lift": [[0,0],[180,14,"out"],[600,0,"inout"]], …},
                       "cues": [[120, "pop"]]}
    looks.json        idle: {clip: "breathe", scene: null, dresses: true}, working: {…}
    accessories.json  nightcap: {anchor: "brim", art: "nightcap", tags: ["night"]}, …
    art/              the renderer's parts: Pixel's sprite sheets; the gel's styles
  references/         what people gave us (below)
```

`characters/charactergen.py` validates it and writes it as C++ tables for
the board (`rig_tables.h` in the staged pack), as it stages faces today.
Agents edit these files; nobody has to. The schema is checked, so a bad
edit fails before anyone looks.

## From a reference to the board

A colleague gives a sketch, an image, a GIF or a video, with one line:
inspiration, or "make this".

1. **Intake**: `characters/<pack>/references/<date>-<topic>/`, the files and
   a `reference.json` (`kind: inspiration | direct`, a note, the status).
2. **Read**: `internal/tools/boopctl reference read DIR` cuts video into
   frames every 40 ms (ffmpeg) and contact sheets; an agent looks and writes
   `reading.md`: beats and timing, poses, squash, eye and mouth shapes,
   colours, silhouette.
3. **Translate** into pack data on the rig: inspiration becomes expression
   values or a clip in the character's own style; direct becomes a clip
   timed to the reference's beats, its poses matched as the rig allows, and
   new art parts when needed. A reference that needs more than the rig has
   (arms, ears, a new body) is flagged as a rig extension for the owner,
   never faked.
4. **Preview** in the Studio, beside the reference, frame-synced, and spread
   over every mood and state the clip applies to, on both characters.
5. **Review**: approve, or comment; the agent iterates.

## The Studio is the dashboard

Running the board's own engine (the WebAssembly simulator), not a copy:

| View | What it shows |
| --- | --- |
| Matrix | every mood × state, playing (as now) |
| Transitions | any two cells blending, and the jumpiest transitions, found by recording and measuring each frame's change |
| References | each reference, its status, what it became; side by side with our render, frame-synced |
| Review | what changed since the last approval, before and after, approve or comment; comments are saved where agents read them (`characters/<pack>/review/notes.jsonl`) |

## Checkpoints

Each lands working, reviewed, simplified and merged on its own, with what
checked it in its commit.

1. **The slime flows.** Faces of the same shape morph (eyes, mouth, cheeks
   ease between expressions, no blink); different shapes cross-fade; the
   lane and its strip fade in and out with the desk. In the JavaScript
   reference and the C++ port, matched (check-port). Measured with the
   transition recording: no frame where the face vanishes; the lane never
   appears in one frame. On the board.
2. **The dashboard and the reference pipeline.** The Studio's Transitions,
   References and Review views on the WebAssembly simulator; `boopctl
   reference read`; the intake format; one worked reference.
3. **The rig core.** `firmware/src/render/rig/`: channels, expressions,
   clips, the mixer (springs, weights, style cross-fades), layers and
   anchors; the pack schema and its generator; unit tests natively.
4. **Pixel on the rig.** Sprite parts from the bank's art; one mood (happy)
   through idle, working and a cheer first, compared with the baked art;
   then every drawn mood; Pixel's face draws from the rig, its hats and
   signs on real anchors in every look.
5. **The slime on the rig.** The gel face's expressions and reactions
   driven by the mixer through an adapter; its layers through the shared
   layer stack.
6. **Retire what the engine replaces**, once nothing reads it: facegen's
   baked designs, slimegen's tables that the rig covers, and the slime's
   JavaScript reference (the Studio and the Mac's mirror run the
   WebAssembly engine instead).

## Risks

- **Pixel's look** may lose craft in parts. Checkpoint 4 compares one mood
  first; if it suffers, Pixel keeps its flip-books and shares only layers,
  anchors and the lane (the simplicity fallback).
- **Frame time on the AMOLED**: hats already cost 5-8 ms a frame
  (plan/TODO.md). Cross-fades draw two faces for ~200 ms; the rig adds a
  little per frame. Measure on the board at each checkpoint (`boopctl
  ping`'s `draw_us`).
- **The slime's two engines** must stay matched until checkpoint 6.
