# The character engine: the plan (2026-10-23, updated 2026-10-24)

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
    expressions.json  styles: {eyes: ["dot", "arc"], mouth: […]},
                      expressions: {happy: {eyeCurve: 800, eyeOpen: 250, mouthWidth: 1200, …, eyes: "arc"}}
    clips/<id>.json   {"ms": 900, "additive": true,
                       "tracks": {"lift": [[0,0],[180,14,"out"],[600,0,"inout"]], …},
                       "cues": [[120, "pop"]]}
    looks.json        idle: {clip: "breathe", scene: null, dresses: true}, working: {…}
    accessories.json  nightcap: {anchor: "brim", art: "nightcap"}, …  (when: render::outfitFor)
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

### Checkpoint 1, as built (2026-10-24)

The slime's face is layers of arts with weights (the slime package's
CONTINUITY.md, Directed edge bridges), in the reference and the port,
matched by check-port. Where it differs from the sketch above, and why:

- **Morph or cross-fade is a feature's, not the face's.** Each eye, the
  mouth, the tears and the cheeks morph where the arts draw them in one
  shape (the same calls and colours, only the numbers differing) and
  cross-fade otherwise, so the eyes can morph while the mouth cross-fades.
- **Up to four arts at once**, each weight a Hermite from its value and
  slope over the edge's face window, so a retarget mid-window starts from
  what's drawn and keeps every weight's velocity. The windows are longer
  than the blink's were, so a state is seen changing rather than switched:
  ordinary edges 320 to 460 ms, dramatic ones 240 to 340, snappier for
  surprise; going to sleep and waking, 180. A fifth art within one window
  drops the faintest; the window is counted in ms in both engines.
- **The face never fades**, checked on the port's rendered frames: through
  five cross-fades its eyes and mouth keep at least 85% of the fainter
  face's visible ink (87% at the least, falling asleep). Where shapes don't
  overlap, the half-way frames hold each at about half strength.
- **Known: two rules for "the same shape".** The JS painter records each
  feature's drawing and compares the calls and colours; slimegen's
  `slime_art.h` gives each group a shape id from its paths' point counts,
  fill or stroke and colour, and keeps the cheeks and the strain mark as
  one group. They disagree on 80 of the 4,730 pairs of arts' groups (calm
  and embarrassed's eyes morph in the reference and cross-fade on the
  board; comfy and excited's mouths the other way round). The JS reference
  retires at checkpoint 6, so they aren't unified.
- **The lane fades its strip** on the props' 200 ms ramp as it comes and
  goes; what it shows while shown, and the bubble, change at once.
- **Measured** (internal/tools/fluid): a mood change's largest 40 ms frame
  fell from 1394 changed pixels to 476 (11.1x its median, from 32.4x),
  and the lane's from 1212 in one frame to about 220 over three. The
  finish's largest frame is still its card's 200 ms reveal; a longer prop
  ramp would spread it.

### Checkpoint 2, as built (2026-10-24)

The intake and its checks are [CHARACTER.md](../characters/CHARACTER.md)
§16, the tool `boopctl reference`, and the views the
[Studio's README](../characters/studio/README.md). Where it differs from
the sketch above, and why:

- **The Studio runs the board for each face a pack's boards have**,
  beside the JavaScript previews, with no entry in the pack: it's the
  firmware, so it's the engine's. The views run on it, on its frozen
  clock a frame every 40 ms, so a recording is the same every time.
- **A reference's frames and sheets are committed** with it, no bigger
  than 512 px a side: the reading cites them and the Studio scrubs them.
- **`show` is a start and, as `anim`, the state asked for at the
  reference's 0 ms**: the Transitions view's pair, so one recorder serves
  both views.
- **`became` names the rig's data** (a clip by its file, an expression
  by its mood, art by a style, scene or accessory's art), checked, since
  checkpoint 3 landed first. None of it stops a pack staging.
- **The jumpiest list is ranked in the page** (Rank): the everyday
  transitions recorded on the stage's board, by the rule `measure.py`
  keeps for native recordings, pinned once for both
  (`internal/tools/fluid/tests/changed.json`); clicking one records it.
- **A verdict goes through the Studio's server** (`POST /review`, from its
  own page only) into `review/notes.jsonl`; from `file://` the page shows
  the queue and says to use the server.

### Checkpoint 3, as built (2026-10-24)

The rig core is `firmware/src/render/rig/` and its schema is
[CHARACTER.md](../characters/CHARACTER.md) §15. Where it differs from the
sketch above, and why:

- **The mood is the bottom of the stack, the look's clip over it.** The
  springs carry only the mood's targets, and the look's loop plays over
  them with a weight, as a reaction's does: so a look's loop is offsets
  on any mood, an absolute one (asleep's shut eyes) wins over the mood,
  and a new look fades over the old.
- **An expression keeps every channel**, those its file doesn't name at
  rest, so the mask is the file's and nothing needs one at run time.
- **Accessories carry no tags.** Which outfit is `render::outfitFor`'s one
  rule, and the air `render::airFor`'s; the file says where each outfit
  sits and what it's drawn as.
- **A layer shows a content**, not only on or off, and a new one waits
  for the old to fade out (as the gel's props keep what they showed), so
  a hat changes at midnight without a pop.
- **A clip's id is its file's name**; clips are additive and keys ease in
  and out unless they say. Which clip a reaction plays, by its state,
  facts and variation, is checkpoint 4's.
- **`rig_tables.h` is made at staging**, as `moods.h` is, not checked in,
  and Pixel's rig is a copy of Boop's, so Pixel's pack still needs
  nothing of Boop's.

### Checkpoint 4, as built (2026-10-24)

Pixel's face is `render/pixel/rig_face.h` and its part of the schema
[CHARACTER.md](../characters/CHARACTER.md) §15, Pixel's face on the rig.
Where it differs from the sketch above, and why:

- **A style is a drawn mood's art.** Pixel's moods differ in drawn detail
  no channel reaches (brows, lids, star cut-outs, chevrons, odd-sized
  eyes), so each mood's eyes and mouth are a style, cut by facegen from
  its idle face at rest, rather than a few shapes at openness and curve
  steps. Openness is the one step baked (each eye open and shut); a mood
  change dissolves the styles over the mixer's 200 ms with each part
  morphing from its box to the next one's, and the face never closes.
- **A pose is where the art sits.** Each part draws as its art has it at
  its mood's pose, and the channels move it by their difference from
  that pose, so any pack's poses look right at rest. Boop keeps the poses
  read off the gel's faces and takes Pixel's styles (it wears Pixel's
  face on the CYD); Pixel's own are fitted to its art. One rig with a
  pose per mood for both of Boop's faces is checkpoint 5's to keep or
  split.
- **The rig face draws idle's plain face only**, its first two
  variations, in every drawn mood. Working's desk, the reactions (so
  which clip a reaction plays is still open), the occasions and the
  comedy stay baked. A switch between the two dissolves over 150 ms while
  the design blinks open, as designs did, so the baked convention and its
  tests stand; design to design still blinks and cuts.
- **Tears and sweat stay in the art**: sad's drops are its eyes'; a
  shared, falling tear or sweat part waits for a clip that uses one.
  Some drawn idles move more than the rig face does (curious's eyes,
  whiny's tears, the newer moods' glances); Pixel's breathe glances to
  either side and lifts it a pixel instead.
- **A short clip fades over a quarter of itself** (the mixer's one
  change), so a 180 ms blink clip shuts the eyes whole.
- **Measured** (internal/tools/fluid, `transitions-pixel.jsonl`, Boop's
  rig on Pixel's face, 40 ms shots, largest frame's changed pixels):
  idle mood changes 5648, 4384 and 5053 fell to 2620, 2110 and 1929 (a
  dissolve, where the face had shut for 150 ms and cut); going to work
  6560 to 3630; a finish handing back to idle 76800 (its whole card, in
  one frame) to 29552. At rest the rig face is its mood's idle face as
  drawn, pixel for pixel, so it kept its craft and is the default.

### Checkpoint 4b, as built (2026-10-24)

The rig face in more of Pixel's looks, [CHARACTER.md](../characters/CHARACTER.md)
§15, Pixel's face on the rig. Where it differs from the sketch above, and
from what this step set out to do, and why:

- **The rig face draws a face in its design's place**, not a look of its
  own. Pixel's working looks, occasions and most reactions draw the
  mood's resting face, moved about, with a desk or props round it and
  decorations on it, so facegen finds, for each design, where that face
  sits at each step (moved whole, its eyes moved within it) and splits
  the decorations (a sparkle, a falling tear, an anger mark) into groups
  of their own. The board draws the design without its face, the rig
  face in the face's place, then the decorations: at rest, the design as
  drawn, pixel for pixel, which facegen checks at every step and the rig
  face test checks on the board. 585 of the 1214 designs, 195 of the 312
  working looks'. Idle's first two variations are taken near enough, as
  checkpoint 4 took them (sad's trembling lip and irritated's twitch are
  lost, the morphs kept); the rest only exactly.
- **So a reaction plays its design's own choreography**, not the rig's
  notice, cheer or poke clip: following its design keeps its props, its
  sounds, its timing and its outcome exactly as the queue and the Mac have
  them, and the face no longer cuts to a baked one. Pixel's rig clips stay
  for Boop's gel on the mixer (checkpoint 5's rest); Pixel plays its blink and its looks'.
- **A switch between two designs the rig face draws** dissolves their
  desks over the 150 ms the hand-overs take while the face stays whole,
  moving from where the one had it to where the other has it; the look's
  clip changes with the state's base, so going to work the eyes look down
  at the desk. Design to design still blinks and cuts.
- **What stays baked, and why**: a face that changes shape, which the
  rig's one drawing of each eye can't (curious's eyes, whose big eye
  moves side to side: a look-around clip on eyeOpen, tilt and gaze read
  as a squint, so curious's idle is baked again and its look-around
  back); tears that pour from inside the eyes (sad's working looks); the
  comedy (a yawn, nodding off, a sneeze), the finishes, wake-ups, asleep
  and no app, whose faces are their own. Whiny's falling tears came back
  without a tear part: they're its idle design's decorations.
- **Measured** (internal/tools/fluid, `transitions-pixel.jsonl`, now with
  a happy working day after the rest, Boop's rig on Pixel's face, largest
  frame's changed pixels, on checkpoint 5's lane): going to work, the
  switch's frames 1576 to 4479 fell to 1196 to 1816 (the largest is now
  the conveyor's own step);
  mood changes at work 12475 and 10643 to 4511 and 3942; a notice at
  work 6891 to 4186 (its perk's own step); the finish 63173 (a cut) to
  23723 (a dissolve), and back to idle the same. Sad's working rows are
  unchanged (its working look stays baked), idle's mood changes within a
  hundred pixels of before; waking from asleep went 1708 to 2919, the rig
  face opening its eyes as it dissolves in. A part's scale is now whole
  pixels, so a still face isn't redrawn. The CYD's firmware grew 27 KB
  (67.3% of flash); a native frame with its shot took 1136 µs on the Mac,
  1134 before, within the noise. The board's `draw_us` is still to measure.

### Checkpoint 5, as built (2026-10-24)

A scoped checkpoint: the gel's JavaScript reference and its C++ port stay
matched frame for frame, so the slime's expressions and reactions on the
mixer wait for the owner's decision on the Mac's mirror (retiring the
JavaScript twin, checkpoint 6). What landed instead:

- **The lane's fade is decided once, by the app, for both faces.**
  Behaviour stamps when the strip comes or goes (every change goes
  through one place, a message's or a time-based one advance stops at:
  no app, a finish ending) and eases its opacity on the layers' 200 ms
  ramp (`rig::Ramp`) from then, keeping the last strip shown, names and
  all, while it fades out; what it shows while it shows changes at once.
  A plain function of the time since the stamp, rather than the layer
  stack's lane slot: the slot's rule that new content waits for the old
  to fade out is wrong for the strip, whose content changes at once. The
  strip carries its opacity to the face (`Strip::opacity`); the gel draws
  it at that alpha, and the canvas lane dithers it (Pixel's checkpoint-4
  dither, now the canvas's), so Pixel's lane no longer pops. How often
  frames are drawn changes no frame (test_behaviour, test_gel).
- **The gel's remaining cuts**, found on the transition recording's
  contact sheets, changed in both engines, matched (check-port):
  - a card's reveal rises in over 400 ms (`cardRevealMs`), twice the
    props' ramp; a card whose route ends while it rises keeps rising as
    it fades, or its rise would stop dead (the jolt check found it);
  - let go, the dome settles back on a softer spring (stiffness 100,
    damping 10, from 256 and 8, which it keeps while held), so a stroke's
    release is a wobble rather than a snap from stretched to round in a
    frame;
  - falling asleep crosses over in its own 480 ms with its controls on a
    slower spring (ω 8 from 20), so the lids droop shut; waking keeps
    the face's 180 ms. Longer windows dimmed the half-way face below the
    85% floor (test_gel); 480 keeps falling asleep's least at 87%.

  The poke stays a hit, and idle's first gesture, going to work (the desk
  and the lane fading in together) and a mood change read as motion.
  Measured (internal/tools/fluid, largest 40 ms frame's changed pixels,
  and its ratio to the median):

  | Transition | Before | After |
  | --- | --- | --- |
  | finish | 3474 (33.1x) | 2095 (20.0x), its largest now a blink over the rising card |
  | stroke | 15043 (15.0x) | 8706 (11.7x) |
  | to asleep | 824 (10.4x) | 640 (4.1x) |
  | to working, idle, poke, mood, to idle | 10.3x, 9.0x, 8.9x, 11.1x, 5.8x | unchanged |
- **One anchors type.** The gel's painter reports `rig::Anchors` (its own
  copy, with its `Spot`, is gone), so both faces' layers sit on one
  type; no picture or trace changed.
- **Waits for the owner:** the gel's expressions and reactions on the
  mixer, and its layers through the shared layer stack, which need the
  JavaScript twin retired (the Mac's mirror running the WebAssembly
  engine) first.

### The rig cut to what a face uses (2026-10-24)

Pixel's face is the rig's only user and the gel isn't on the mixer yet, so
11ca4f0 cut the rig to what Pixel's face draws: the layer stack (`Layers`,
`layers.h`) and the accessories (`Accessory`, `Anchor`, both packs'
`accessories.json`), a look's scene and `dresses`, clips' cues and
`Mixer::cut`, the cheer and poke clips and Pixel's notice (Boop's stays,
its reference in review), the channels no face read (`eyeCurve`,
`mouthCurve`, `cheek`, `tear`, `sweat`), and the expressions' poses: an
expression is a mood's styles, and the face draws the channels' offsets
from rest. The anchors lost the hands' sides, which nothing read. The
gel's move onto the rig grows back what it needs of them, from git. Since,
every switch of Pixel's designs dissolves over the rig's one 200 ms fade,
and the blink that hid a switch is retired.

## Risks

- **Pixel's look** may lose craft in parts. Checkpoint 4 compares one mood
  first; if it suffers, Pixel keeps its flip-books and shares only layers,
  anchors and the lane (the simplicity fallback). It didn't: the parts
  are its own art.
- **Frame time on the AMOLED**: hats already cost 5-8 ms a frame
  (plan/TODO.md). Cross-fades draw two faces for ~200 ms; the rig adds a
  little per frame. Measure on the board at each checkpoint (`boopctl
  ping`'s `draw_us`).
- **The slime's two engines** must stay matched until checkpoint 6.
