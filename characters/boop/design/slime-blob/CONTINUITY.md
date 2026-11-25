# Continuous actor and animation authoring

Updated 2026-11-25. The slime's one engine is the C++ in
`character/firmware/src/render/gel/` (below, `gel/`): the board runs
it, and so do the simulator and the Mac's mirror of the board, the
firmware built to WebAssembly (characters/CHARACTER.md §9). Every activity
scene family is implemented; idle, sleep and a finish have their comedy
(Comedy, below), a successful finish comes in three sizes (Finishes), the
board's touches have a take each (Gestures), the
face deals its pastimes, tagged ones too, from one table (Pastimes,
Tagged pastimes), and one face flows into the next
(The mood beat: its arts morph or cross-fade, never closing). Q1
representative art review was approved on 2026-10-02. Each rule below
names the code that keeps it; [VALIDATION.md](VALIDATION.md) names the
test that pins it. The scenarios in `tests/scenarios-gel/` shoot every
scene, but while the pictures are redesigned only one or two shots a
scenario are pinned to a golden, on purpose; a new small set is pinned
when the redesign settles. Contact-synchronized sound is implemented, but for
the keys, which make none; timbres remain sketches.

## Keep the object; change its targets

The board draws the dome from a mesh slimegen samples once (`mesh.mjs`,
into `slime_mesh.h`): its vertices and a dense lookup of the blue
translucent gel's studio lighting, rim and bloom. Every frame
`gel/painter.cpp` deforms and projects the mesh by the body's pose and
rasterizes it, erasing the last frame's pixels a band of rows at a time
just before drawing the body there. It fills the triangles facing the
camera by pixel centre, and its outline, the edges between those and the
ones turned away, has a soft fringe a pixel wide beyond it, each fringe
meeting the next where the outline bends: so as the mesh turns and a
sliver of a triangle on the outline turns toward the camera or away, the
outline doesn't jump; on the AMOLED the board's other core
does the lower rows meanwhile (`render/helper.h`), each row whole on one
core in the same order, so the frame is pixel for pixel one core's
(test_gel's `test_a_helper_draws_the_same_body`). `gel/art.cpp` draws the face's art (slimegen's
`painter.mjs`, baked as vector paths into `slime_art.h`) on the body, moved
and sized by the face's controls. There is no inner jellyfish cap or model
asset. The face rides the body during a grab or a deformation; since
motion V2 it trails the body a few px as it moves (The motion layer,
below), and catches up.

| Area | What it does | How to extend |
| --- | --- | --- |
| `expressions.json`, slimegen's `painter.mjs`, `face.mjs` | Face designs and the controls they're drawn at | Edit the catalogue and a matching painter primitive; run slimegen |
| `gel/motion.cpp` `Motion` | The accepted V1 springs, blink, breath and gaze | A change is a named motion revision, with its own pinned numbers |
| `gel/lively.cpp` `Lively` | Motion V2's layer: the five rules under every clip | A change is a named motion revision: a new test like `test_the_motion_v2_numbers` |
| `gel/acting.cpp`, `gel/engine.cpp` `pose`, `posture` | Additive authored emotion acting, the mood posture | Add bounded layers without replacing the base pose |
| `gel/painter.cpp`, `slime_mesh.h` | The persistent body and gel appearance | Keep silhouette and material identity; never change them per mood |
| `gel/engine.h` `dragStart`, `dragMove`, `dragEnd` | Local pull and rebound | Keep the bounded spring state |
| `gel/scenes.cpp`, slimegen's `scenes.mjs` | Each state's scene, its recipes and props | Edit the recipe in `scenes.mjs`; the engine plays it |

## Proposed layer ownership

One monotonic presentation clock drives all layers and sound cue IDs:

```
authoritative host facts ──> state target ──> activity/props ──┐
validated mood edge ──────> face + emotion acting ────────────┤
local touch/poke ─────────> bounded pull/impulses ────────────┼─> ONE body
continuous V1 springs/blink/breath/gaze ──────────────────────┘     │
actual contact/card-reveal cues ──> sparse procedural SFX ──────────┘
```

Preserve current displacement and velocity when changing any target.
Eye and mouth geometry, cheek opacity and tear amount move on springs
(`gel/motion.cpp` `SemanticFace`). While one face gives way to another,
the board draws both arts, features of the same shape morphing and the
others cross-fading (The mood beat, below), so the face never
closes or fades. The mood posture reads its own critically damped weights.

## One engine, driven as the board drives it

`gel/engine.h`'s `Engine(seed)` takes `setFacts` (a complete host
snapshot: an omitted attention clears it), `setMood`, `play`,
`linkTimedOut`, `clear`, `borrow`, `setOccasion`,
`dragStart`, `dragMove` and `dragEnd` (with the finger's velocity as it let
go, if it was moving), and `step(ms)`, the only call that advances its
clock; every other call keeps every spring's displacement and velocity. It
has no wall clock and no global random source: its `Random`s are its own,
seeded (53 after a reset, so a reset board replays the same). The explicit
timeout is the board's input; elapsed time alone never invents `no_app`.

The board's `GelFace` (`gel/face.cpp`) turns what Behaviour follows into
these calls, and steps the engine on a 16 ms grid from its last reset: a
frame advances at most 45 ms, and a repeated time doesn't advance it. The
board times every Moment itself: the engine holds each one (below),
and the board clears it when it ends.

## Phase 1 channel bounds

The accepted V1 springs (`gel/motion.cpp`) are the body's four modes, lean,
squash, ripple and dent, at frequency 11, 13, 18 and 16 and damping 4.6,
4.5, 5.3 and 6, in 1/240 s substeps, within 0.72 and velocity 9; a poke
adds velocity (lean ±2.6 away from where it's poked, squash −3.5, ripple
3.5, dent 4.8) and a shake (lean 4.5, squash −2.6, ripple 5), never
position, each mode's velocity within ±8 after it; breathing adds 0.011 ×
sin(1.65 t) to the squash; a blink is sin² over 0.24 s, the first at 2.8 s,
then every 3 to 7 s; the gaze looks within ±0.014, every 3.2 to 7.2 s,
easing at rate 3.

The additive acting springs (`gel/acting.cpp`), which a bit plays on, are frequency 11 (lift),
10 (roll) and 9 (the other channels), damping 6.4, in the same substeps,
within 0.24 for lift, 0.12 for roll, 0.18 for forward and 0.42 otherwise,
velocity 5. The grab spring is stiffness 256 and damping 20 while held (100
and 13 once let go, so the dome settles back with a small wobble rather
than snapping or bouncing past where it stood), within 0.72 and velocity 6;
its target is the finger's displacement up to 0.32, giving less and less
past it and never reaching 0.64 (`gel/engine.h`; A finger on the body,
below). Gesture cadence is the authored duration plus 7 to 15 seconds,
starting after one second, or 0.4 seconds after a retarget; a release
defers the next gesture three seconds.

The face's own window is 180 ms (falling asleep swaps faces over 360,
below); directed edge variants select the face windows below, over which
one art crosses over another. Each semantic control is a critically
damped spring, `a = ω²(target − x) − 2ωv`, with ω = 20 (4 while it sleeps,
from falling asleep until it wakes, a mood changing meanwhile), in the
same 1/240 s substeps: it starts from rest without a jump in velocity, and a retarget
keeps both its position and its velocity. Cheek and tear opacity stay in
[0, 1]. The controls' endpoints are each face's (slimegen's `face.mjs`,
read off the painter's primitives); the board draws each of the face's
layers at its ratios (The mood beat, below), so settled faces keep
their authored proportions.

The mood posture (the per-face squash, curious's lean toward its bigger
eye and excited's bounce, `gel/engine.cpp` `posture`) is weighted
by one critically damped spring per expression, ω = 10, whose target is one
for the current expression and zero for the others. The weights sum to one,
so the posture eases between moods with no step in velocity, and it reads
after the quiet blend.

## The motion layer (motion V2)

Motion V2, Lively, is V1's springs as they were (above: the body's four
modes, blink, breath and gaze, still pinned by `test_the_motion_v1_numbers`)
and over them five rules that run under every rig clip, so a clip's author
writes only the main pose and the gel adds the rest (`gel/lively.h`
`Lively`, stepped by the face with the engine, in the same 1/240 s
substeps; `test_the_motion_v2_numbers` pins its numbers). The face lays
it on the rig's channels after its mixer, its follows and its moves
(`GelFace::clipChannels`), and a hit's shake on the glass after it, so no
spring softens a knock.

| Rule (its switch) | What it does | Its numbers |
| --- | --- | --- |
| Stretch with speed (`stretch`) | Taller while the body moves up or down fast, flat as it lands, then a wobble; the volume kept, as for every squash | 0.7 thousandths taller per px/s, at most 220; a landing kicks a `flat` spring (frequency 38, damping 23) 30 per px/s, within 300 |
| Overshoot and settle (`settle`) | Each body channel (squash, lean, lift, x, reach, melt, the glass, `turn`) a loose spring toward what the clips ask: a stop goes past and wobbles back. The lift stops at the floor; `turn` goes round the short way, so a spin that ends a whole turn round never unwinds | Frequency and damping: squash 44, 31; lean 30, 21; lift 40, 36; x 34, 31; reach and melt 30, 30; the glass 36, 36; `turn` 26, 24 |
| The crown drags (`drag`) | The crown behind the base: the lean opposite the body's speed across, so a slide and its stop bend the dome | 2.5 thousandths per px/s, at most 320, on a spring of 19, 11 |
| The face lags (`face`) | The eyes and the mouth trail the body by a few px and catch up: the one rule that moves the face on the body by itself | Two springs (across, up) of 22, 22; drawn all the way behind, at most 8 canvas px |
| Hands follow (`hands`) | Each hand's place and size follow its clip, arriving and leaving late; a hand off the desk's keys starts there at the hand's size, and one going back goes there before the desk has it again, so no hand jumps between owners | Place 24, 24; size 34, 38; the desk's hand at ±12 px, 4 up, size 765, home within 3 |

The body's place, for stretch, drag and the face, is the rig's lift and x
and the engine's own lift and slide (a bit's), in canvas px. At rest every
spring rests exactly on its target, so a still pose draws as it did in V1;
a step of 1 s or more sets each where it's going, as the mixer's springs do.

**Each rule has a switch**, all on: `Lively::kRules`, the one place, which
`dbg.motion` sets by name (`{"t":"dbg.motion","rule":"face","on":false}`,
or `"rule":"all"`) for a scenario or the Studio, until the next reset. Off,
a rule gives back V1's motion for its part exactly
(`test_each_motion_rule_off_gives_back_the_motion_before`), and every
spring comes to rest after a clip (`test_the_motion_layer_comes_to_rest`).
The face lag is the owner's open question, alive or loose: judge it on the
board with `face` off and on.

**What changed from V1, and why.** V1 drew each clip exactly as keyed and
the face fixed on the body, so a clip's stop was a stop and its author had
to key every wobble. In V2 the drawn channels trail the keys by tens of ms
and pass a stop a little before settling; a fast authored shake on a body
channel (faster than about 5 a second) is softened, so a hit's shake is
the glass's, laid on after the layer. The face moving on the body by
itself is new, on purpose. The 60 gel goldens pinned then were accepted
again once with it.

**Prepare is the author's.** Every big move starts with a small opposite
one: a crouch before a hop, a lean back before a lean in, a dip before the
glass. The engine adds none, so each clip keys its own (as `idle-happy`,
`invite-palm`, `knock` and `knock-climb` do).

**Its cost.** Seventeen springs more each 16 ms step (seven settled
channels, flat, the crown, two for the face, three for each hand), integer
and on the face's clock; nothing more is drawn: the face's lag is an
offset of where its art already goes.

## Idle moves

Each lasting mood has one idle move, a rig clip `idle-<mood>` that ends
where it starts, which idle plays as its acting deals it (the mood's move
and the expression's own bits, `Acting::takes`): the face plays the clip
(`GelFace::advanceTo`), and every face plays its lasting mood's
(slimegen's `kIdleMoves`), but a meme face, which plays its own move
(Meme faces, below). They replace the faces' three mood gestures
each, the spring kicks motion V2 gives every pose by itself.

| Mood | Its move | Why it reads so |
| --- | --- | --- |
| calm | `idle-calm`: a slow look aside, held, and back, a glance the other way | Nothing to do and all is well: unhurried, it just looks |
| happy | `idle-happy`: a crouch, one buoyant hop beaming, eyes squeezed, landing round | Joy is a hop for nothing at all |
| focused | `idle-focused`: a lean back, then in to inspect something, eyes narrowed | Attention: it goes closer to look |
| proud | `idle-proud`: a dip, then chin up, tall, eyes up and half shut | Pride stands tall and looks down its nose |
| cross | `idle-cross`: two stomps, flat at each, then a huff to one side | Temper comes out as a stamp |
| sad | `idle-sad`: a slow sag, flatter, eyes down, and gathering itself again | Sadness weighs it down |
| lonely | `idle-lonely`: it looks around for someone, one way and the other, finds nobody, sinks | Looking for you, and you're not there |

## Representative activity scenes

The first owner review covered working, terminal, needs-you,
task-complete success/failure and the quiet rest alias. Q1 approved that
representative art on 2026-10-02, allowing the rest of the matrix to be
implemented: four moods in six cases each (success
and failure separately), 24 cases in 20 mood/state cells, now happy,
grumpy, sad and wounded, the Studio's
**Representative activities** review set
(`character/studio/review-sets.json`). Sleeping is a justified
shared alias, not three newly authored sleep animations; its one addition
is a snore (Comedy, below).

Priority is explicit no-app, listening, needs-you, the Moment held,
then the latest Doing and activity (`gel/router.cpp`). An activity applies only
to working, and the gel shows four, each as one state (`Activity`,
`Facts::look`): typing as working, looking as analyzing, running as
terminal, and waiting; unknown activity falls back to working and an
unknown Doing to idle. Attention identity follows the device: a new activation or changed
id, agent or project; changing mood, display name or more leaves the
request's reveal consumed. Attention cuts future decorative contacts
immediately. Clearing and showing the same request id again creates a new
activation. Leaving an alert for a higher-priority state (listening, an
explicit link timeout) saves how far it got: its age and its next contact.
Returning to one that had already confirmed restores its silent hold;
returning to one that had not resumes at that age, so only the knocks and
confirmation not yet reached follow. Each request's knocks and ding play
exactly once, never twice and never not at all. Returning from a Moment
resolves the latest snapshot. Only an explicit successful outcome permits a
trophy; failure, missing outcome and unknown outcome never do.

A Moment (`play`) mirrors visual lifecycle, not LinkKit's queue, TTL,
acknowledgments or audio playback. The router is a plain struct: the
facts, listening, the Moment held, the borrowed face and the lost link.
Behaviour times every Moment, so the engine never expires or finishes
one on its own: it rests after its loops until `clear()`. Its `variant`
names the take the board has already timed, and `borrow` holds a borrowed
expression over whatever shows, with no expiry. Each Moment, and each
needs-you, is numbered as it comes, and the scenes key their takes by that
number (`Route::key`), not by a string. `loops` uses the protocol's range,
1 to 6, defaults to one, and repeats the same selected recipe; only a new
Moment chooses the next variation. A borrowed face plays over the
Moment without changing its outcome, its number or the lasting mood; a
bare Moment has nothing to play. Any Moment ends listening, even one
refused because needs you shows; listening asked again starts anew; the
board's `stop_listening` clears it.

Every Moment has a finite authored recipe, then holds its last until
it's cleared, and returns to current facts. Listening has its own recipe and waits for an explicit stop or
reply: the engine has no microphone deadline of its own. Explicit no-app
masks current activity and suppresses contacts; presentation time
continues, so elapsed moments are not replayed when the link returns.

One desk persists across work modes. Three shuffle-bag recipes per
state and factual outcome differ in rhythm, with no adjacent repeats
(One set of takes for each state, below); asleep and a successful finish have a fourth (Comedy, below).
Routine work changes variation after recovery; alert/result requests choose
once at entry. Mood retargeting does not restart an existing recipe or
alert. The mood's idle move (Idle moves, below) plays only in idle without a
grab; the activity scene owns the choreography elsewhere. A state change cancels
future recipe contacts but keeps every spring's position and velocity,
including the composed body pose.

A drag consumes elapsed physical keyboard/knock contacts without emitting
them. Factual alert/result reveals still happen while held, so dragging
cannot hide a real completion or its outcome. Release never plays an
elapsed contact again. Rest keeps the stored mood, cancels acting and
contacts immediately, and lets residual springs settle. **Falling asleep
is a morph** (`gel/motion.cpp` `SemanticFace`): the awake face squashes
shut on sleep's slow spring, ω = 4, the same art all the while, its eyes
to lines (no thinner than the sleeping lids' pen, 0.030) and its mouth to
the sleeping one's size, the cheeks and tears fading; once it's 0.9 shut,
about a second on, the shared sleeping face crosses in over 360 ms, its
lids easing in over the lines, alone by about 1.3 s. How shut it is,
`shut`, springs on the controls' spring, and an awake art's drawn sizes
follow the controls below their saturation that far (The mood beat,
Drawn ratios). Waking stays quick: the face's own 180 ms and
spring, ω = 20, the eyes opening from lines; woken before it's a line, the
same art simply opens again. The sleeping face's semantic targets are eye
openness 0.004, mouth width 0.018, curve 0.008, and zero cheek/tear
opacity; changing the stored mood during rest leaves this face quiet.

A scene's timings (`gel/scenes.cpp`, its recipes slimegen's `scenes.mjs`):
240 ms entry, 480 ms recovery, 120 ms contact envelopes; cycles of 3,200,
3,700 and 4,200 ms. A desk's contacts are jittered at most 40 ms and their
strength 10%. Activity springs use frequency 12, damping 10, velocity
limit 1.2 and displacement limits 0.08 lean, 0.06 squash, 0.05 forward. The
desk's visibility uses frequency 10 and damping 14; these springs use the
same integration substep. The quiet posture blend uses the activity spring
coefficients and stays in [0, 1]. Final pose bounds are [1.25, 1.32, 1.14,
0.72], life bounds [0.24, 0.12, 0.23], with no edit to V1's own springs.
These values are art candidates, not host mood pacing. Props stay above
y = 0.8 of the screen; the lower 20% belongs to the host's lane. The
AMOLED's corners are rounded, about 110 px in radius, and show nothing
there, so the lane keeps clear of them: the strip stands in from the
sides as far as the corners reach on its marks' and chips' rows, and the bubble
stands off the panel's foot and in from the curve, its own corners cut
away like the panel's, which holds the longest take in the sign's font.
The strip's working and idle counts each sit in a chip outlined as the
drawer's rows' chips are, so the drawer says what they mean: the working
count's bright, by a spinner that turns once a second, and the idle
count's dim, by a sleeper's z. The lane is drawn again for the spinner
only while sessions work. The counts never run past the strip's
margin: the names before them are cut to what they leave. While
something needs you, the strip is the only place that says who's
asking (the needs-you card says only to continue on your Mac), so the
name comes first: the agent and its thread (or project) whole, then the
thread alone, each with the working and idle chips while there's room
for them (the idle one goes first), and else the thread cut to the room
there is with no chips; the helpers and the to-do list wait until
nothing needs you. A finished turn with no thread names its agent
alone, with no dot after it.

Every other prop (the alert's card, and the listening cue,
a mic in a breathing ring with LISTENING beside it in the large font
to read at arm's length, in a row over the head) has a **200 ms visibility ramp** for
entry and exit (`gel/scenes.h` `Ramp`): a cubic Hermite from its current
value and slope to the target, so from rest it is a smoothstep and a
reversal keeps its velocity; it ends exactly. Held within zero and one,
it's flat where it's held, so a retarget never brings back what it held at
zero. Each prop's visibility is its drawn opacity. When its route ends, a prop fades out still carrying the
content it last showed (the alert's request, agent, project, name and
count; the listening pulse). New content (another request) waits until nothing of the old is
drawn, then fades in from zero; the alert's content follows the
current request at once. Contact envelopes (the knock, the key and touch
pulses) stay deliberate impacts.

The authored keyboard contact times, in milliseconds before jitter, are
slimegen's `scenes.mjs`:

| Rhythm | Variant 0 | Variant 1 | Variant 2 |
| --- | --- | --- | --- |
| Working | 580, 780, 1040 | 560, 760, 1680, 1880 | 1100, 2220 |
| Terminal | 600, 780, 960 | 780, 1810, 2090 | 580, 740, 900, 1060, 1960, 2120 |
| Analyzing | 1020 | 720, 1680 | 1520 |

Each mood times these by its traits (below): its delay, its spacing,
its strength and its lean added to the desk's 0.018. Contact side
alternates. The body
uses the contact envelope and strength for side lean 0.024, squash −0.052
and forward 0.045. A successful reveal targets squash/forward 0.036/0.025;
a failed reveal −0.048/−0.035, before the activity bounds.

Needs you knocks the same way in every mood and take: its recipe is the
pack's rig clip `knock` (slimegen's `scenes.mjs`, `alertRecipe`), a fist
knocking twice on the glass, the clip's cues (900 and 1,200 ms) its
knocks and the ding 240 ms after the last. The knock's contact sounds and
rings the card's mark; it no longer dips the body (`Scenes::advance`):
the hand knocks. If nobody comes, the knock climbs (`knock-climb`) from
`slime::kKnockClimbAtMs`, which `scenes.mjs`'s `knock` sets: `climb:
'follows'` (the default) after `followsMs`, 20 s, with nobody come, or
`'replaces'` straight after the knock, so the climb is the whole knock.
The recipe lasts until the climb is over, so a needs-you interrupted after
its ding comes back to its silent hold and never climbs twice. A result
receives its mood's delay and strength (`profileTraits`) while its success
or failure remains factual. Contacts carry unique request, generation,
iteration and index identity; the sound cues take each once
(sound/README.md).

Suggested composition order: base shape → mood posture → activity pose →
gesture impulses → local grab → final bounds. There must be one owner of
each channel: a drag owns the grabbed patch, activity owns keyboard
contact, mood owns face style, and attention owns priority. Blend
additive offsets; cap the combined result, not each layer in isolation.
Make suppression explicit so angry+typing+drag cannot exceed the body's
safe envelope or produce competing repeated impacts.

## Full activity scene matrix

The engine implements all 22 factual states in the eight scene families of
[STATES.md](STATES.md), 17 of them with takes of their own: 24 faces × 22
states, 528 cells (the Mac's 18 and the six meme faces) from one set of
takes for each state, including 48 quiet aliases for asleep/no-app, and task-complete with success and failure. Every active cell has
all its takes: three, a successful finish's four, a gesture's ten (each
asked for, as the board does), and idle's (its mood's move, and excited's
zoomies); quiet aliases keep the mood and use the
shared sleeping face without acting, and without contacts but a snore's
breaths. The two face alternates are outside this canonical matrix.

The scene selects a shuffle bag keyed by mood, state and factual
outcome/context. Desk modes and listening select again only
after recovery. A Moment selects once per request and keeps that recipe
across explicit loops; an attention entry selects once and then holds.
Idle plays its lasting mood's one move, and an expression's own bit, with
a separate automatic shuffle bag per expression and the quiet interval
above. A bag's first round deals its first three entries; every later round
deals all of them (Comedy, below). Each round is exhausted before the next
and no entry repeats across a refill. Changing targets never replaces the
body or its springs.

For the other canonical moods, the traits are the expression's own
`traits` in `expressions.json`, numbers once derived from the three mood
gestures each had before motion V2, and kept as they were when those were
folded into the idle moves. They were derived so: let `D` be the
gestures' mean duration in seconds, `E` the mean absolute cue velocity,
and `L` the sum of signed lean/forward cue velocities divided by the total
cue count (a denominator of one for none):

| Trait | Formula and bound |
| --- | --- |
| Delay, milliseconds | `clamp((D − 3) × 120, −160, 160)` |
| Contact spacing | `clamp(D / 3.2, 0.88, 1.18)` |
| Contact strength | `clamp(0.6 + E × 0.32, 0.68, 1.12)` |
| Lean | `clamp(L × 0.045, −0.022, 0.022)` |

The reviewed moods (happy, grumpy, sad) keep the explicit table above.

### One set of takes for each state

`slime::kRecipes` has one set of takes for each state, the same in every
mood: 19 rows (17 states' and a finish's success and failure) of three,
and two fourths, 59 recipes. The mood changes only the face and, on a
moody recipe (a desk's, a result's, a reply's, a start's and a wake's),
the timing, as the board deals the take (`scenes.h`'s `inMood`): each
contact moves to first + delay + (at − first) × spacing, from its first
contact's time; its strength takes the gain; the recipe's lean adds the
mood's. Waiting, listening, the rests, idle, needs you, a touch, a
gesture and notice are the same in every mood. Proud's lifted success
alone shows its gift. The desk's contacts then take the bounded jitter.

Before, slimegen baked each of the 25 profiles' 24 rows apart, 1,850
recipes, and three moods' desks were exceptions: happy kept the plain
lean, grumpy's terminal had a compact cluster of its own and grumpy's
working no traits, and sad kept every other contact with a lean of
−0.016. They now take their traits as every mood does: happy leans 0.014
more at the desk, grumpy types a little earlier and closer together on
every desk, and sad types every key, 160 ms late and 1.18 apart. A
success's hiccups and a wake's settles take the spacing and the gain too.

The five activities the desk shows as another's have no row of their own
(`scenes.mjs`'s `standsIn`): tool_use and planning play working's,
searching analyzing's, testing and delegating terminal's. The Mac sends
tool_use for typing; it no longer sends the other four.

Until motion V2 a mood's gesture also echoed as a small recovery pose at
the desk; it went with the gestures, and the desk's recovery is now the
scene's lean easing back alone.

Waiting has no contacts and uses lean targets
[0.006, 0.014, −0.010]. Its focus cycles are [1, 2, 3] per recipe. Listening
also has no contacts, uses lean [0.022, −0.012, 0.008] and pulse cycles
[2, 1, 3]. For both, lean is modulated by
`0.65 + 0.35 × sin(2π × progress × cycles)`, in addition to entry/recovery
envelopes. The listening pulse is `0.5 + 0.5 × sin(2π × progress ×
cycles)`. The same desk stays in place; its screen shows a list, link,
magnifier, inspection cards, neutral test dots or a quiet waiting cue.
Testing never claims PASS/FAIL before the host sends a result.

The remaining scene recipes use the shared cycle, entry and recovery
timings above:

| Family/state | Authored contacts before mood delay | Visible meaning |
| --- | --- | --- |
| Wake up | Stretch [560], [760], [900, 1500] ms, then settle [1180], [1240, 1420], none | You back after a long break: the start family's body, with no card. The stretch is a start reveal (the second of variant 2 at 0.7 strength); a settle is a body contact of strength 0.35, sides 0, then ±1 |
| Reply ready | Reveal at [680, 960, 1240] ms | A neutral reveal, with no card and no trophy |
| Poked | [160], [200, 480], [160, 520] ms | Bounded local dent/wobble/bounce |
| A run of pokes | [160, 400], [160, 340, 520], [220, 620] ms | Bounded wobble/squash/dodge complaint |

Start, wake-up and reply contacts take the mood's traits as the desk's
do; a single reveal only moves by the delay. Touch contacts have strength 0.6 for poked
and 0.9 for a run, alternating sides and lean targets [0.008, −0.018,
0.012]; they have no timing jitter or mood-derived delay. Their mood face
stays the current expression, with the bounded recovery profile where it
applies. An admitted `poked` moment also applies the V1 poke and an
admitted `tap_spam` its shake: they can change velocity, but never reset
displacement or layer state. Duplicate or refused requests apply no
impulse.

The start and reply reveal envelope adds squash 0.018 and forward
0.018. Body contacts are consumed silently during the
grab. A reply stays neutral, and only explicit task success permits the
trophy, which a successful finish shows (Finishes). A state change cancels pending contacts at once
and resolves the latest facts.

## Comedy

Idle, sleep and a finish have comedy, all of it the same body: a squash,
a stretch, a tilt, a slide or a rebound.

| Comedy | Where | Its takes | Sound |
| --- | --- | --- | --- |
| Yawn and settle (2.9 s), sneeze and shake it off (2.7 s) | Idle, every expression, from `tier1` | The face's pastimes (`kYawn`, `kSneeze`) | The sneeze's one contact |
| Zoomies, edge to edge (2.6 s) | Idle, excited | Its own take 4 | A landing (`bounce`) at each edge |
| A snore: two breaths, each a slight swell | Asleep | Asleep's fourth take | Each breath |
| Hiccups: Little Win's hop and trophy, then three small hiccups | A small successful finish | Its fourth take | The fanfare, then three squishes |
| A gift: a small bug beside the trophy | Proud's small successful finish | Its second take, lifted | As that take |

**Idle's comedy is bits, beside the mood's move.** Acting's bag
(`gel/acting.cpp`) deals its lasting mood's move (Idle moves, below) and
the expression's own `gags` (expressions.json); the comedy every
expression shares, the yawn and the sneeze, is the face's to deal, rows of
its pastimes (Pastimes, below), which acting plays in place of its next
take. A bit is in
`gags` once, shared. It is a performance (its `cues`, impulses on the gesture
springs) with `keys`, which set a channel's target (from (0, 0) at its
start, a smoothstep to each of the channel's keys in turn, then its last
value), and `contacts`, which sound and move nothing. Every channel's keys
lie inside its bound and come back to rest. The six acting springs follow
their keys under-damped, as gel does; a bit has two springs of its own,
its `slide` (frequency 10, damping 9, at most 0.7) and its `lids`
(critically damped, frequency 24). The lids close the eyes as a blink
does: the drawn blink is the larger of the natural one and the lids'. The
slide carries the whole dome sideways, its face and its shadow with it,
and leaves its shape as it is.

**A scene's fourth take is a table of its own.** Every row of
`slime::kRecipes` keeps its three takes; asleep and a successful finish
have a fourth, in `slime::kFourthTakes`, and `slime::kRecipeTakes` says how
many each row has, so the other rows carry no empty fourth. A host may ask
for a take from 0 to 3; one its state hasn't is dealt from the bag. A
finish timed without its outcome finds a success's fourth (`GelFace::recipe`).
A finish's row goes on past its fourth with the finishes a size
above small (Finishes), which no bag deals.

**Comedy joins a bag's second round.** One rule for every bag, acting's
and the scenes': its first round deals the first three takes, the ones every
state has always had; every later round deals all of them, never opening on
the take just dealt. A fresh mood, a reset and every first round play as
they always did, and the joke comes once the straight takes have been seen.
Acting's bags deal at most two (`kIdleTakes`: the mood's move and an own
bit), the scenes' four (`kMaxTakes`). In idle, with a take every 8 to 19
seconds, excited's zoomies come every other take or so.

**Asleep picks again after each take**, as routine work does. Its first
rest is always the still one, drawn from no bag, so sleep starts still for at
least 12.8 s (the first rest and the bag's first round). The snore lasts
4.8 s: breaths at 600 and 2,600 ms, strength 0.35, each swelling the body's
squash by sin² over 1,200 ms, times its strength, times 0.07, even while
quiet. They are quiet rest's only contacts. A lost link rests still and
never snores.

**The hiccups** reveal Little Win's trophy at 680 ms (plus the mood's
delay), then three body contacts at 1,640, 2,060 and 2,480 ms, strength
0.45, in a 3.7 s take. **The gift** is a flag on proud's second success
take: its recipe carries it (`gift`), and the board draws an amber bug
beside the trophy.

**Comedy's contacts sound in any state**, each with the routine chance (a
quarter): a sneeze's (`sneeze`), a zoomies landing (`bounce`), a snore's
breath (`breath`). They are routine sounds, ducked under a line, and
sparse: over twenty minutes of idle only sneezes sound, over five minutes
of sleep only breaths, each fewer than half of its contacts.

## Finishes

A successful finish comes in three sizes (`gel/finish.h`), so the more
work, the bigger the party: the tier its turn reached (the `do`'s `turn`,
characters/CHARACTER.md §9, the tiers the tags count: `tier1` a minute,
`tier2` 5 minutes) chooses it as the board picks the
variation (`GelFace::pick`), so the Mac never names a design, and the
brain decides only whether to celebrate and in which face. A turn short
of `tier1` is small, to `tier2` medium, and from `tier2` big, however
long it's held. A finish with no turn (onboarding's) is sized by how long it's held (`loops`) instead: once
small, twice medium, three times or more big. A
success in a sad face (sad, wounded) is
small whatever else: tearful but valid. A failure never plays one: its
row keeps its card and its three takes, unless the finish names whose
turn it was, when its low sign takes the card's place (A finished turn,
below).

| Size | Finish | What it does |
| --- | --- | --- |
| Small | Little Win | The row's own takes (and hiccups for a fourth): a hop at its reveal, a little trophy popping up over its head, a ring of sparkles |
| Medium | Confetti | Little Win's hop and trophy, a second hop, and confetti cannons from both bottom corners, twice |
| Big | Gold Rush | It steps back to 0.84 of its size, the gold floods out from behind it with turning rays, it leaps, the trophy lands on its head, confetti from both corners, and the gold drains away |

**Variations.** A success's variations are Little Win's four takes, then
one for each finish above small (`finishVariant`): the confetti 5 and Gold
Rush 6, from 1. A finish above small plays once, whatever its loops (`plays`), for
its recipe's length, 3.6 or 4.6 s; its recipe (`finishRecipe`) holds its
reveal, where its `say` starts as a card's does, and its landings.

**Its body.** A finish moves, scales and squashes the whole body, its face
and its anchors with it (PaintControls' `scale` about where it stands, its
`offset`, and its squash and lean), as a pure function of how far into it
it is, so the board, the simulator and the mirror draw the same frame.
Every finish moves under 16 px and a tenth of its size a frame, and is back at
rest by its end. Gold Rush, which covers the screen, puts the desk away
while it plays. Its flood and rays are drawn behind the body, so the frame is erased
whole before them, not band by band with the body (`drawsBehind`), less
the rows the flood covers whole once it reaches every corner
(`finishCovers`, `Surface::forget`); the trophy, confetti and sparkles
over it, all above the lane.

**Its cost.** A finish draws dozens of small shapes a frame, so it fills
them itself: confetti and sparkles as convex spans sampled four
times a pixel, dots by their distance, Gold Rush's gold and rays a row at a
time with each pixel written once, outlines as a second, larger fill, and
its sines from a quarter wave's table. On the AMOLED's profiling build
Gold Rush plays at about 23 to 29 frames a second, Little Win and
the confetti at 33 to 37, where the look alone draws 40.

**Its sound.** Little Win's reveal plays the fanfare (`complete`); a finish
above small cheers at its reveal instead (`cheer`: two chord stabs, a held
chord, a run up and a rattle of soft claps) and bounces (`bounce`) as it
lands, once each, never ducked.

## A finished turn

The brain's Moment to a finished turn, a finish or only a face, names
whose turn it was (the `do`'s `who`), and the board marks it on screen
for as long as the Moment plays and 5 s after (`Behaviour::done`,
`kFinishLingerMs`), so a face or a word reads as being about that turn
(`gel/done.h`):

- **The rim glows** in the outcome's colour, the strip's marks' sage for
  a success, clay for a failure, and a fainter warm white for a reply or
  a face with no finish of its own. It comes over 0.3 s, holds, and fades
  over the last second; strongest at the panel's edge, it reaches 26 px
  in, following the rounded corners, over everything, the lane too.
- **Boop holds up the low sign** (`gel/low_sign.h`) once the Moment's words
  have ended, at once with none, and 3 s in at the latest. It's the thread's
  name (else the agent's), with the strip's mark, in the outcome's colour,
  in the lane's rows, in the strip's place, the whole face clear above it:
  a name that fits in the sign's font, else in the bubble's, on one line or
  two, up to 50 characters. It rises from the panel's foot over 0.28 s,
  stays through the Moment and 5 s after, and falls away over the last
  0.4 s. Under it, the lane's words give
  way: past the 3 s, the bubble doesn't show, though the voice goes on; a
  newer Moment's words take the lane back as the sign falls.

Another Moment that names no turn takes them down: they leave in 0.4 s,
and the strip and a tap stop naming the turn at once. A needs-you takes
them at once. A lane under a steady glow, and a sign at rest, is kept, glow
and all; while the glow changes or the sign moves, the lane is drawn again.

## Gestures

`gesture` is the board's own Moment to what you do to it, a Moment
in the touch family. Its takes are the board's touches, in its order
(`render::Gesture`, slimegen's `scenes.mjs` `gestureNames`): the board
names one (its variant, 0 to 9), no bag deals them, and a gesture asked
for without one plays the first. Each is the same in every mood: a scene
recipe whose body contacts dent the dome and sound a
squish on its first loop, and a bit of its own (`expressions.json`
`gestures`, keyed as Comedy's are) that acting plays with it. The board
borrows a face for each while it plays, as a react's expression is
borrowed, and the mood stays. A low or cross mood keeps its own face
through a gesture instead, so a touch never cheers it on the screen
alone: a mood whose family is one of `expressions.json`'s
`gestureFaceGivesWayTo` (frustration, sadness, alarm and strain; slime.h's
`kKeepsFaceThroughGestures`). The brain's Moment after it follows the
mood too.

| Gesture | What the body does | Face it borrows | Bit |
| --- | --- | --- | --- |
| handoff (BOOT hands you an agent) | Lifts and leans in, offering | pleased | 2.4 s |
| stroke (a slow one; a quick swipe is none: A finger on the body) | Melts under the hand, eyes shut | affectionate | 3 s |
| ruffle (stroked slowly the wrong way, upward) | Bristles in ripples, then huffs | annoyed | 2.2 s |
| nose | Squished in at the nose, pops back | surprised | 1.8 s |
| tickle | Giggles, jiggling side to side, eyes squeezed | excited | 2.4 s |
| dizzy (shaken) | Wobbles round, sliding and rolling side to side | surprised | 3.2 s |
| pickup | Stretches up tall | surprised | 2.2 s |
| putdown | Lands squashed and settles | pleased | 2 s |
| startle (a thump on the desk) | Flinches, jumps, lands | surprised | 1.9 s |
| peekaboo (turned face up again) | Squashed low with eyes shut, then rises | happy | 2.6 s |

A scene lasts its bit and 200 ms more. **A recipe may carry a bit.**
The scene names it (`gag`), and acting plays it once for each pass of the
recipe (its generation and iteration), in any state, then waits: its own
next take comes three seconds after the bit ends, and none is dealt
while one is held. Acting is suppressed outside idle only while the
recipe has no bit.

## A finger on the body

A finger grabs the body and the body goes its way, on its springs: no
take plays while it's down. `dragMove` is the finger's displacement since
it went down, in body units with y up; the pull follows it (Phase 1 channel
bounds), and the whole body draws the pull as its own lean and squash (2
and 1 per unit, `kGrabLean` and `kGrabSquash`, added to the pose before its
bounds): down squashes it and spreads it on the floor, up stretches it,
sideways leans its top that way, and its base stays where it stands. Let
go, the pull settles back on the softer spring, and `dragEnd(velocity)`
flings it on first: 0.3 of the finger's velocity (in body units a second)
joins the pull's, less as it nears its limit going that way (times 1 −
|x| / 0.72) and never past its velocity bound, so a swipe pushes the body
its way and then lets it settle, and quick swipes in a row carry on from
wherever the last left it instead of piling up.

The board feeds it (`gel/face.cpp`): the canvas's pixels are 85 to a body
unit at the dome (128 of the panel's, which draws the canvas half as large
again), its middle at (160, 129), y flipped. It tells a touch that travels
40 px or more by its speed (`app/touch_gesture.h`): faster than 600 px a
second on average, from going down to its last reading, it's a swipe, the
face's alone, with no poke or other touch and nothing to the Mac; slower, a
stroke (upward, a ruffle), and the gesture above plays as it lets go. The
finger's velocity as it lets go is over its last 80 ms. The board's
`tests/scenarios-gel/swipes.jsonl` swipes on the board itself.

A finger that starts on the strip is no finger on the body: going up, it
pulls out the agents' drawer (`render/gel/drawer.h`), and the body is
pressed under its edge. Shut, it stands at rest; as the sheet rises its
edge pushes the body up until it meets the glass, then flattens it, its
rest rows mapped onto those left above the edge, spread a little wider
(`Projector::project`, the painter's `squeezeTop` and `squeezeBottom`),
its pose and springs carrying on inside them. Past six tenths flat it
squeezes its eyes shut: the art, layers and props wait and the drawer
draws its own face (`> <`, pink cheeks, a wobbly mouth), and once it has
sprung open one of its hands drops over the sheet's edge. Shut again, it stands
back up as it was. `tests/scenarios-gel/drawer.jsonl` pulls it.

## A finger at rest

While a finger is down the eyes go toward it (`GelFace::finger`,
`Motion::gazeTarget`, `gazeUpTarget`): measured from where the eyes are, half way there at 40 canvas px off and never
past `kGazeReach`. They don't follow with the eyes shut or asleep. When it
goes, they drift back at the wander's rate, and the wander's dice go on as
before under a finger.

A finger at rest a second (`app::TouchGesture`'s `kLeanMs`, staying inside 16 px
each way) leans the body in: the pull's target is toward the spot in the body's
own half-widths, so at any size a finger on its edge pulls as far, up to
`kLeanReach`, on a slow spring (`kGrabLeaning`), forward, slumped, and
breathing. It wears a stroke's shut eyes, or, in a mood that keeps its face
through a touch, its own eyes under lids (`kLeanLids`). Past `kDozeMs` (5 s) it
slumps further under the sleeping face. Lifting wakes it, with a small start up
if it dozed. A Moment, the needs-you screen, a finish or listening
takes the body from it at once, and the finger drags as any finger does.

The bank has no purr. A lean's sound is the snore's soft `breath` (every 1.8 s,
gain 72/255, pitch 0.9; dozing every 2.8 s, 56/255, 0.8), through the same queue
as the contacts, at the state's volume, and none at 0 or face down.

## Notice

The brain's Moment when you name it in your prompt: it heard its name and
looks up at you. It plays the pack's rig clip for it,
`character/rig/clips/notice.json`, from the notice-perk reference
(CHARACTER.md §16): its eyes snap open wide and up and it perks up tall,
winds up, hops off the ground with its eyes squeezed happy, lands flat with
a squish and wobbles, looking at you. The face plays the clip on its
mixer as the moment starts, the painter lays its channels over the
engine's pose (CHARACTER.md §15, The gel on the rig), and its cues sound
a body contact at the take-off and the landing through the engine's
contacts. Its scene is the start
family's with no card, timed to the clip and a little more, with no bit or
contact of its own. Its three takes, `notices` in `expressions.json`, are
the one clip under a face each, dealt from its bag as any state's takes
are: `notice-surprised`, `notice-happy` and `notice-pleased`. The board
borrows the take's face (`kNoticeFaces`) unless the Mac sends a mood with
it.

## Replies

The brain's answer to what you said on push-to-talk: a face (a `react`
with a mood) that names its reply (`reply`). As the face starts, the gel
plays the pack's rig clip for the reply, `character/rig/clips/reply-<name>.json`,
over it, once, on its mixer as it plays the notice's: a nod for yes, a
shake of the head for no, a shrug for dunno, a head tilt with one eye
narrowed for huh, a little hop and a sway for hello, a slow sway for bye,
puffing up tall for thanks,
a flinch for ouch, leaning in low for comfort, giggling bounces for
hehe, looking down at its sign and back up for status, after which a
status reply about every agent (`show`) has the board bring up the
agents' drawer, and for hush (ok, I'll be quiet) its
lips pressed together, its eyes squeezed shut, sinking a little in a
small nod. The clips move only the body,
eyes and mouth: there's no new drawing, and the face and its sign are
the Moment's. A reply the pack has no clip for plays the face alone.

The Mac's reply at your lock or unlock of the Mac (not to what you said)
is the same move, picked by the Mac's rule with no brain (`MomentRule.bye`,
`hello`): `bye` for a real wave, at a first lock in an hour and for good
night at a night's lock, after which Boop's Doing goes to asleep at once;
and for a routine one `reply-wave`, a sway at about a third of `bye`'s
lean with the eyes barely softening, over in a second, so it reads as a
nod to you going by. Both are one clip, `wave`: `reply-bye` plays it as
it is (1.6 s), `reply-wave` at a size of 350 over 1 s, so its sway is
quicker as well as smaller (CHARACTER.md §15, a clip at a size and a
pace).

### One move at its sizes

The spec's table of moves that exist several times asks for each to be
one move with sizes. A clip may now be another's at a size and a pace
(`of`, `size`, `ms`). Of its rows, only the wave is merged: its copies
are one rig clip each, a size and a pace apart. The rest are left, each
for a reason:

| Row | Copies | Why it stays apart |
| --- | --- | --- |
| Hop | `hop`, `reply-hello`, `notice`, the finish's hop, a pass's hop | `hop` is three hops; `notice` snaps its eyes wide and up as it perks; `reply-hello` is a hop then a sway (a size can't make a sequence); the finish's hop is drawn by code (`finishPose`) and a pass's is a spring jolt (`GelFace::answerAct`), not clips |
| Flinch | `reply-ouch`, a failed call's, a failed build's | One clip; the other two are spring jolts (`GelFace::land`, `answerAct`) |
| Droop | `wish-gone`, sad at the desk, a failed result | One clip; the others are recipe contacts and the mood's traits |
| Melt | `melt`, `work-waiting`, the stroke | `work-waiting` loops with its chin on the desk and sways; `melt` drips and pulls itself up; the stroke is a gesture's bit |
| Yawn | `to-sleep`, the yawns | One clip; the yawns are acting bits |
| Shrug | `reply-dunno`, the missed high five | The miss is a sequence (look at the palm, lower it, shrug), timed to the engine's `kShrugMs` |
| Lean in | `reply-comfort`, `speak-along`, the hand-off, `work-looking` | `speak-along` and `work-looking` loop (a nod; a slide to the monitor), `reply-comfort` plays once; the hand-off is a bit |
| Wave | `reply-wave`, `reply-bye`, `reply-hello` | Merged but for `reply-hello` (a hop then a sway). No hand: a size scales every track, a hand's place and shape too, so a small wave's hand would sit inside the body |

While something needs you the face doesn't play, so neither does its
reply, but a reply to what you said, which shows over it.
`tests/scenarios-gel/replies.jsonl` catches each partway through, a no
over the needs-you screen, the slight wave at a lock and the bye at a
night's lock.

## Invites

After a skit the Mac may ask for one touch (the `do`'s `invite`, the
engine's firmware/README.md, The invite): the engine times it and the face
draws it from `FaceContext::invite` (`gel/invite.h`). Every pose, payoff,
miss and late return is the pack's rig clip (Hands and the glass, and Turning
round, below); `gel/invite.h` holds only what no clip is: the glow, the
word, the payoff's sparks, hearts or breath, the "+3 XP" low sign, the
face it wears and its sound. Once the skit's face, words and sign are
over, Boop holds its pose, the palm and the lean up at the glass, 1.15 its
size, the back turned away from it; the place to touch glows
(light means "this is for you"), a warm gold light that breathes, a ripple
going out from it every 1.6 s, so it reads as "touch here" with no word,
and the Mac's `label` ("tap", "pet") stands by it in the sign's font,
rimmed dark, its letters rippling one after another.

| Pose | What it does | Glows | Touch | Payoff |
| --- | --- | --- | --- | --- |
| palm | A hop, then faces you, happy, eyes wide, leaning a little to its right; its right hand, an open palm, flat on the glass beside its right eye (`invite-palm`, then `invite-palm-wait`), about 85 px across, its patch pale, the word under it | the palm, a ring round it | tap | high five (`invite-highfive`): the palm claps, a ring and a shake, sparks; it squashes, hops and spins all the way round (turning round), excited, the palm sinking back into its side |
| lean | It perks up, comes up to the glass and rests its cheek on it, leaning, the patch pale where it touches, eyes up at you (`invite-lean`, `invite-lean-wait`) | its cheek, the word beside it, away from the face | stroke | purr (`invite-purr`): eyes shut, a fast small wiggle against the glass, three hearts rising |
| back | A flinch and a stomp, then it turns its back, slumped, its face gone round the dome to its left (`invite-back`); waiting, it looks over its shoulder now and then, one eye at the rim in side-eye looking back at you, then turns its back again (`invite-back-wait`). It wears side-eye in every mood | its back, on the side away from its face, the word under it | stroke | sigh (`invite-sigh`): a breath in, its shoulders drop as it comes on round, pleased, a puff of breath |

Missed, the palm's looks at its palm, lowers it and shrugs with both
hands (`invite-palm-miss`); the lean's eases off the glass and shrugs
(`invite-lean-miss`); the back's huffs and gets over it by itself, coming
on round the way it turned (`invite-back-miss`); each under heavy lids, as
the glow goes and it settles back to where it stood. A late touch brings
the palm or the cheek back to the glass (`invite-<pose>-late`), with a pop
of sparks by its head; a late stroke makes it look away over its shoulder
with a hop, one eye at the rim (`invite-back-late`), and the sigh brings it
round from the start, so its face is gone only a moment. Then the
payoff. A payoff that earns says so low, "high five", "purr" or
"better now" with the XP's chip, as a finish's does. While an invite shows
no pastime, base pose, typing along, look of its own or idle gesture
plays (`GelFace::showsLook`); a finger still takes the body, and leans in
as it would. A mood that keeps its face through a touch keeps it here too.
Each payoff has one sound from the bank (`inviteSound`): the cheer for a
high five, the snore's breath, low, for a purr and a sigh (the bank has no
purr).

## Hands and the glass

Two hands, one pair, part of the body (`gel/hands.h`): gel stubs that bud
out of its sides when they act and sink back in, hidden at rest. One
function draws a hand, `paintHand`: a gel disk shaded as the dome is, its
light up and to its left, a pale rim as the dome's, a soft shadow down and
to its right, in the buddy's colour; a flat pad when it rests on
something; an open palm has three small fingertips over its top, a fist is
a little tighter; on the glass it's 1.5 times its size (`kHandGlassGrow`),
paler and flat, with a pale patch where it presses; fading, it's one flat
shape so it fades evenly. It never grows fingers.

The same two hands are every hand Boop has. Each frame `paintFrame` says
who holds each (`HandsPlan`), and only that part draws it, in its place:
a move's (the rig's hand channels: the palm, the knock, the flop); else a
sign's or a card's, gripping its sides (`gripping`); the low sign's, by
its top corners (`holdingUp`); speaking's, cupped at its ear (`cupped`);
the desk's, a pad flat on the keys, typing (`onKeys`); and under the
drawer, one hung over its edge (`hung`). A move with one hand out leaves
the other where it was: the knock's first fist knocks while the other
hand stays on the keys.

The glass is the screen. The rig's `glass` brings the whole body up to it,
bigger about where it stands, 1.15 at most (`applyGlass`, the one way
anything comes to the glass: a move's), over a finish's own
scale; the patch where it touches is `patch`, `patchX` and `patchY`, drawn
on the body under its face (`paintPatch`). A move's cue is a hit on the
glass: the hand on it most rings there for 340 ms and the body shakes
3 px side to side, dying away over 260 ms (`gel/moves.h`).

A move is a rig clip the face plays as a pure function of what shows and
how long (`currentMove`): the invite's by its phase and time, the knock's
by the needs-you scene's own age, which an interrupted needs-you keeps.
The face sounds the climb's cues as it crosses them; the knock's are its
scene's contacts, and an invite's payoff has its own sound. The flop
(`flop`), for a check passing after failing, plays as the fix's Moment
starts: the Mac names it in the `do`'s `clip`, and a Moment's clip with no
`reply-<clip>` plays by its own name (`GelFace::reply`).

**Its cost.** A hand is a few disks or bars, each a convex fill: about ten
for a palm, a few hundred pixels for one on the keys and a few thousand
for a palm on the glass, against the body's tens of thousands. The
simulator draws every frame and checks each picture, so it says what is
drawn, not how fast. The body at 1.15 covers 1.15², about a third more
pixels, and the body's fill is most of a frame's cost (Finishes, Its
cost: the look alone draws 40 frames a second). Only the board's profiling
build (`gel_parts`' `body_us`) can say what that costs, and the frame rate
of a palm, the knock and the flop on the AMOLED: not measured yet.

## Turning round

The dome is round, so turning round moves only the face across it (the rig's
`turn`, thousandths of a whole turn, to its right for more than 0); the
mesh, its outline and its light stay where they are. Turned half way, one
eye shows at the rim: the look over the shoulder. Turned all the way, the
face is gone: the back. A whole turn is a spin.

**Each eye its own width.** The face's art is drawn by projecting each of
its points onto the dome (`Projector::face`): a point of the face plane
is a point on the dome's surface. Turning rotates that point about the
dome's upright axis before it's projected, so every point goes round on
its own circle. Nothing in the art changes and nothing needs a width per
eye: the eye nearer the rim narrows by itself, as a mark on a ball does,
and the other keeps its width (`test_the_turn_narrows_each_eye_on_its_own`:
a sixth of a turn, the near eye about an eighth of its width, the far
three quarters). A point gone round behind is held at the rim, and each
path of the art fades by how far its outline faces the camera on average
(`shownFacing`: whole from `kFacingShown`, none at `kFacingGone`), so a
feature thins and goes at the rim instead of sliding off as a sticker.
Its cost: four multiplications more for each point of the face while
turned, a square root for one behind, and nothing at all at rest, where
the art draws exactly as before.

| Move | What it does |
| --- | --- |
| The back (`invite-back`, `invite-back-wait`) | The upset skit's invite: a flinch, a stomp, and it turns its back half a turn to its left; waiting, it looks back over its shoulder (a turn of about 0.21, wider eyes, side-eye) and snaps its back to you again |
| The sigh (`invite-sigh`), the miss (`invite-back-miss`) | It comes on round the way it turned, to a whole turn, which is where it began |
| The spin (`invite-highfive`) | The high five's payoff: all the way round during its hop, out at its right rim, its back, in again at its left |

`gel/invite.h` holds none of this; `turn` is the rig's, so `dbg.clip`
and a scenario play it as any clip (`tests/scenarios-gel/back.jsonl`,
`spin.jsonl`).

## Meme faces

Six faces past the Mac's 18, each with one body move that sells it. They
keep the gel's face language: solid dark eyes with no whites, one small
mouth; the lids and where the eyes look do the acting. They're the pack's
`board_faces` (character.json): the board draws each by its name on the
wire, and the Mac doesn't read them, so no rule or brain picks one yet; a
Moment, `state`, the invite's back or a scenario may name one.

| Face | Its art | Its move (`face-<face>`) |
| --- | --- | --- |
| deadpan | Flat lids half down over each eye, a flat line of a mouth | Nothing but the lids: a still beat, one slow blink |
| side_eye | A flat lid's line across each eye, the eye pressed under its one end, both to your right; a short mouth aslant | The body stays; only the eyes go further aside, hold and come back |
| squint | One eye narrowed to a slit, the other under a flat lid; a wobbly mouth | It comes up to the glass, head tilted, to doubt you |
| smug | Half lids, tilted, glancing aside; a cat's w of a mouth; pink cheeks | A dip, then the whole body tilts, chin up, eyes aside |
| silent_scream | Tall dark eyes, a tall open oval of a mouth | It shoots up tall and shakes, both palms flat on its cheeks; no sound |
| faint | Crosses for eyes, a wobbly mouth | It sways, tips over and melts, lies there, and pulls itself back up |

Each move is a rig clip (`rig/clips/face-<face>.json`, a face's `_` a
`-`): its face's idle move (`kIdleMoves`), played once as a Moment shows
the face (`GelFace::sync`), unless a reply brings its own clip, and by
`dbg.clip`. The every-face test changes each of the 24 to every other.

## Tagged pastimes

A tagged pastime is one that needs a tag (`render/tags.h`: `night`), or
asleep a long wait: a row of the face's one table (Pastimes, below), dealt by its one
dealer like any other. A row that needs a tag needs no tier: it fits
whenever its tag is on, and while it fits it's the newest, dealt 60% of
the deals after another (never twice running), about three in eight of
them. The board says the tags and how long the Doing has shown with
`setOccasion(when, lookMs)` on every sync. `expressions.json` `pastimes`
holds their bodies, a bit or a take; the table (`gel/pastimes.cpp`) names
each and says when it fits:

| Doing | Pastime | Needs | What plays |
| --- | --- | --- | --- |
| asleep | deep-snore | night | Three deeper breaths |
| asleep | dream | 1,800 s asleep | Two soft breaths and a twitch-and-wriggle bit |

They are takes the scene plays at once as the Doing's next (numbered after the
row's takes), the same in every mood. Work has none: the tempo at work is
yours, by typing along (the engine's documentation/design/screen-guide.md,
"Small details"), so it has no busier typing of its own. A gesture or a host's Moment never takes one. A tagged pastime
whose tags go off simply isn't dealt again. The engine has no colour
channel, so no pastime tints the gel. The working looks' quicker pace
while the agents are busy is the board's (`render::workPace`), not a
tagged pastime.

### The four activities (the board's)

At arm's length the monitor is too small to say what the agents do, so
the whole body says it, with no prop, costume or change of scene: a
change of activity changes the silhouette. The Mac sends four
(`Act`); the board still knows the eight older state names, and the gel
shows each as one of the four (`activityOf`: planning and tool_use as
typing, searching as looking, testing and delegating as running).

| Activity | Body (the rig's clip, `looks.json`'s `acts`) | Eyes | Hands (`paintProps`) | Monitor |
| --- | --- | --- | --- | --- |
| typing | Upright over the keys, the tier's base (below), a small dip at each key | On the keys | Typing | Three lines of text typed out, then cleared |
| looking | `work-looking`: leant well in to the monitor at its left (lean −430 to −470, x −34 px, lift 8) and up tall (squash −120 to −145) | Scanning a line left to right, stepping down, four lines in 2.8 s; lids a little lower | Off the keys, still on the desk, to the monitor's side (`kLookingPaws`) | A page of four lines, the one being read lit, stepping down |
| running | `work-running`: sat back and up, away from the monitor (lean 200 to 260, x 30 px, squash −200 to −240), a slow breath and a small rock over 4 s | Fixed on the monitor | Lifted off the keys and held together in front (`kRunningPaws`) | One bar filling over 2.4 s, and again |
| waiting | `work-waiting`: slumped (squash 260 to 300), swaying side to side (lean ±160) over 6 s | Up and out at you, half-lidded, a slow blink | Flat on the keys, still (`kWaitingPaws`) | Three dots, each brighter in its turn |

- **Activity beats tier.** The tiers vary only the typing pose; pace
  (`busy`, `frantic`) only speeds things up.
- **A change is a move, not a jump.** The look's clip changes over
  `kPoseMs` (400 ms, the mixer's `setLook`), the hands ease on a spring as
  quick (`Scenes::pose`), and typing's taps go with typing's share. The
  monitor cuts.
- **Keys only while it types.** A recipe's key contacts and the hands'
  taps play in typing alone, and the keys make no sound: a click at every
  word was too much, and the hands show the typing (`gel/engine.cpp`'s
  recipes, `key_contact` none) (`Scenes::advance`). The states never
  shown (planning, tool_use, searching, testing, delegating) have no
  recipe row of their own: each plays its activity's.
- **Pastimes.** At work only the stretch is dealt, in any pose.
- **The Mac holds them** so the body doesn't rock: running and looking
  show at least 3 s (`Core.poseHoldMs`), typing and waiting 1.5 s.
- A work act (`wact`) runs under the running pose; its result's hop or
  flinch plays over it.

Pinned by `test_each_activity_is_a_pose` and shot by
`tests/scenarios-gel/activities.jsonl`.

### Calm work (the board's)

Work is the Doing on screen most of the day, so it works calmly and
settles deeper the longer the agents work: effort shows as the eyes
settling, never as strain. While working shows (no Moment over it) the
gel loops the rig's base for the last tier reached (`looks.json`'s
`tiers`): at `tier1` an easy sway with its eyes open on the keys
(`work-easy`), focused at `tier2` (`work-focused`), and at `tier3`, in
the zone, low calm lids, a slow wide sway and a deep breath
(`work-zone`). These are the typing pose's; another activity loops its
own (above). Under a
Moment, or while something needs you, the base fades out over the
mixer's 150 ms, and back after. While it types, the desk's hands type: before each key
contact of the recipe (silent: the keys make no sound) a hand lifts and lands on it
(`kTapMs`, `kTapLift`), and between them they tap softly by turns,
lower and without a sound (`kTypeMs`, `kTypeLift`), so the hands work
even between the recipe's bursts. A pastime may take them (below).

### Pastimes (the board's)

A little something now and then, however long the agents work or you're
away (`render/gel/pastimes.h`): the pastimes are one table, a row each.
Calm comes first: a pastime is the body's own move, and it brings
nothing, holds nothing and leaves nothing beside the face or on the
monitor (the screen's rule, in `layers.h` and `pastimes.h`). The working
screen is Boop, the desk with its monitor's icon, and the strip with the
work's term.
A row's body is a clip of the pack's rig (`rig/clips/`: a stretch, a hop,
a look round), or a bit or a take of the engine's (the comedy every mood
shares, and the tagged ones, above). The tiers are the Mac's (`tier1`
from a minute, `tier2` from 5, `tier3` from 15): of the agents' working
stretch at work, of their rest idle. The face (`GelFace`) deals one at a
time, while the engine shows the look itself and nothing holds the body
(a finger, a word of the work stream in flight), after a rest of 20 to
45 s (`kRestMinMs`, `kRestMaxMs`), the newest 60% of the time (the
highest tier, then the longest wait, and a tagged one above any) and an
older one's the rest, never the same twice running; and holds the
engine's own idle takes off while a clip plays. The gel's `looks.json`
has no `occasions`. The one playing fades out when the look gives way.
A row may be a **move**, the whole body going somewhere, and none starts
within 5 minutes of the last (`kMoveGapMs`); no row is one now. A pastime
that used the desk's hands would say where (`pawsFor`); none does now.

| Look | From | Pastimes |
| --- | --- | --- |
| working | tier2 | The rig's stretch: eyes squeezed, up tall, a lean each way |
| idle | tier1 | Looking round; looking up at you; three hops; a yawn; a sneeze |
| idle | tier3 | Snoozing, Zs rising beside it |
| asleep | 1, 4 minutes | Rolling over; a snore bubble |

Nothing is dealt while something needs you: the amber screen is the
message. The only things a pastime draws are sleep's, in front, at the
body's anchors: a snooze's Zs and a snore's bubble. No sounds of their
own but a few landings (`body_contact`), and none asleep.

### Where it looks, typing along, and with you (the board's)

The eyes rest forward and turn to one thing at a time, for a reason you
can name (`render/gel/gaze.h`, the screen's rule, part three). The face
gathers the facts each tick (`GelFace::showGaze`), `Gaze` picks a point on
or off the screen by the first rule that applies, and the engine turns the
eyes to it (`Engine::attend`), at `Motion::kAttendRate`, under half as
quick as they follow a finger, so a look is a turn and never a dart.

| When | It looks | For how long |
| --- | --- | --- |
| Something needs you | Up at you, then to the Mac's side (the `macleft` or `macright` tag), or up at the screen (`macup`); forward with none | 1.2 s at you (`kNoticeMs`), then turned for as long as it waits |
| Typing along, idle or at work, its hands tapping | Down at its keys | While they tap |
| A stretch of typing along of 8 s or more stops (thinking with you) | Up at you | 2 s (`kThinkAfterMs`, `kThinkMs`) |
| At work in a pose of its own: looking, running, waiting | Where the pose's clip has its eyes (down a page, on the monitor, out at you: the rig's `gazeX` and `gazeY`); the rule itself rests | While the pose lasts |
| On a call (`oncall`) | Forward, still | While the call lasts |
| Your pointer moves (`state.ptr`), where it's free for you (never asleep) | Its way, as you see the board: across `ptr`'s x × 42 px and up or down y × 36 (`kPointerX`, `kPointerY`); at the edge of the screen nearest the board, right at it on the Mac's side, or up | Until the Mac stops sending it, 3 s after it stops |
| Reading along (`scrolling`) | At its page, to the Mac's side (`kPageReach`, `kPageY`) or up at the screen (`kPageUpY`); the line-by-line travel is the `read-along` clip's | While it reads along |
| A video (`video`) | The Mac's side, at its eyes' height, or up at the screen, still | While it watches |
| Otherwise | Forward, with the engine's own small wander | |

Nothing of it applies while anything else has the eyes: a finger, a
Moment, a pastime, a transition, a word forward, listening or sleep. The
rig's gaze tracks are added to the engine's own, so a look over a pose's
clip would pull its eyes off the page or the monitor: that's why the pose
comes before the pointer in the list.

**Typing along** (`GelFace::showAlong`): while your hands are busy at the
Mac (the `typing` tag), it types with you: its body sways a little over
the keys, to one side and then the other, dipping slightly onto each beat,
a beat every 600 ms, never hopping (the rig's looping `type-along` clip);
its hands swing 30 high, one every 300 ms (`kBriskLift`, `kBriskMs`),
against the agents' soft 12 every 340. At the Buddy's size, more was a
bounce. The keys under the
hands light as they land, which a small screen barely shows, so on each
hand's beat a key's tick bursts just off that side of the body, three short
strokes rimmed dark, out and up, gone by that hand's next tap, longer typing
fast (`typingTicks` in `gel/layers.cpp`, read from `Engine::typingAlong`):
the mark that reads from a chair, as speaking's rings do, in every pose,
the light size too, and never under a sign held up. At work that's at its desk, which
is out already, and its eyes drop to the keys; you
stop, and it's back to the soft typing. Only its typing pose types with
you: looking, running or waiting, its hands are off the keys, the pose has
the body, and your typing changes nothing until it types again. Idle, its keyboard comes out for
it over the rig's fade; you stop, and its hands rest; the keyboard stays
`kAlongLingerMs` (4 s) more, so a pause doesn't put it away and bring it
back, and then goes, with a pastime's rest before the next pastime. It is
the lowest thing there is: it waits for a pastime or a transition to end
and never cuts one, and it goes at once for a finger, a Moment, a word
forward, needs you or sleep. No pastime is dealt over the
keyboard alone; at work they're dealt as ever. The Mac says only that your
hands are busy, never what they type.

**With you** (`GelFace::showWithYou`): what else the Mac says of you at
it, each the body, eyes and hands and one mark on or beside it that reads
from a chair (below), lower even than typing along, and only where it's free for you
(`GelFace::freeForYou`: idle, or at work in its typing pose with no word
forward; no finger, card, transition or pastime): on a call (`oncall`) it
keeps still and a little smaller, its eyes half (`on-call`), with no
typing along, music or pastime, and stretches up as the call ends; while
you speak (`speaking`, another app recording with no camera) it leans in,
nods on a slow 1.6 s beat (`speak-along`) and holds a hand cupped at its
ear on the Mac's side with rings pulsing by it (`gel/layers.cpp`), winning
over typing along; while you scroll (`scrolling`) and 6 s after, it reads
along, leaned 220 and slid 14 px to the Mac's side (or stretched up 150 at
it, `macup`), lower, its eyes down on the page, travelling down a line in
1.15 s and snapping back up with a small nod (`read-along`, a 1.4 s loop),
and settles in after 2 minutes of reading, lower still, its lids half down
(`read-along-settled`); a video (`video`) turns and slides it 10 px to the
screen, a little taller, its eyes wide and fixed, with a slow blink and
once every 20 s a small start, a lift and back (`video`); music (`music`)
gets it into a groove 24 s, its eyes half closed, a content face (the
`pleased` one, unless its mood keeps its own), a slow sway and a nod at
each end (`groove`), then 3 minutes' rest, and again; as it stops, a look
round (`look-around`). Each pose comes and goes over 600 ms
(`kWithFadeMs`). The pointer leans it its way, 14 a step of `ptr`, slides
it 1 px a step and turns the eyes further (the rig's gaze, 55 a step
across, 45 up or down), and up its way it stretches up; at the edge nearest
the board it leans in 160 toward the Mac's side, reaching up 50. The lean,
slide and gaze follow over about 350 ms (`kLeanMs`), so a pointer that
jumps is followed, never jumped to. While any of them is on, no pastime is
dealt. The Mac never says what you scroll, hear, watch, say or copy.

A pose alone is too small to tell apart from across a desk, so each has a
mark drawn at the body's anchors, rimmed dark to read over anything
(`Engine::With`, drawn by `paintWith` in `gel/layers.cpp`), each fading in
and out over the rig's fade, in any pose and at the light size too, so at
work it still shows what you're doing while the pose has the body:

| You | The mark |
| --- | --- |
| Music | Headphones: a pale band over its head from ear to ear and a cup on each ear, on for as long as the music plays, through the groove's rest, its pastimes and typing along; in the groove, a note (now and then a beamed pair) rising from each cup in turn every 1.5 s, drifting out and fading over 2.4 s |
| Reading along | A page beside it on the Mac's side (the right with none told), clear of its widest, a little below its eyes, where they look: lines of words scrolling up 14 px a second while you scroll (`kPageScroll`), still while it reads on after, and a scroll bar's thumb going down with them |
| A video | A small screen beside it on the Mac's side at its eyes' height, a play mark on it, lit in the scene's colour, a new one every 2.6 s crossing over 0.5 s (warm, violet, green, pale); that light added to the body, by how bright each pixel is, so the eyes and mouth stay dark, strongest on the screen's side |
| On a call | A muted mic, a dark disc with a mic and a slash, held still by its ear on the Mac's side, and nothing else: no headphones, page or screen |

The page and the screen stand beside it, so neither shows while its hands
type along or a card is held; speaking's hand is at its ear, so no
headphones while you speak.

Typing fast (`typingfast`) moves the hands' phase on quicker, a beat every
210 ms in place of 300 (`kFastMs`), the tap the same share of its beat, so
no hand snaps as it comes or goes (`GelFace::pawPhase`, `briskLift`); its
clip (`type-along-fast`) hunches it in 50, opens its eyes 260 and widens
them 140, and stays through a flicker off of 800 ms (`kFastLingerMs`).

### Layers over the body (the board's)

The engine draws no costume, but the board draws layers over the body by
the same tags, after the face art and before the props
(`gel/layers.h`): Zs beside it asleep at night, the marks of what you do
at the Mac (with you, above: the headphones are the one thing it ever
wears, and only while music plays), and last the sign a
Moment holds up. It wears nothing at night: the night shows on its lids
(below). That's
all: the face comes first, and nothing is put on the screen for a season
or a holiday. It wears no hat or shades for a special day (the Mac's sign
says the day), nothing hangs in the sky behind it (no sun, moon or
stars), nothing drifts through the air (no snow, confetti or hearts; a
finish keeps its own confetti) and it holds no morning coffee. Each sits on anchors the painter takes from
the very vertices it projects for the body (the rig's `Anchors`, both
faces' one type: the dome's apex, ring 6's sides and front for a brim,
ring 15's front for the hands) and the face art's eye centres, so a layer
leans, squashes, dips under a finger and slides off the screen with the
body and is cut off there with it. At night the lids hang a little lower (`kNightLids`) on the awake face,
easing out as it squashes shut, gone by when it's a line, and back as it
wakes. Each part comes and goes through the rig's layer stack
([CHARACTER.md](https://github.com/Mellow-Machines-Lab/buddygotchi/blob/main/characters/CHARACTER.md) §15, The layer stack), which the
face keeps: what's beside it (the Zs) fades in and out over 200 ms. The
sign fades out over 200 ms once it's down, at the opacity Behaviour
gives it. It's held at the body's front, but a lean or a finish carrying
the body sideways carries it only as far as keeps it whole on the
panel, its hands `SignLayer::kEdge` in from the sides and clear of the
rounded corners, so the longest sign still reads. The layers read the engine and never change it. The Zs, drawn with
one rounded pen (`Raster::zee`), grow from 7 to 16 px as they drift, fading
in over their first 200 ms and out to nothing by their last.

### The desk's monitor (the board's)

The monitor says what the work is, in one icon that fills it
(`paintProps`): a pencil writing a line (typing: an edit, any other
tool, a plan), a magnifying glass drifting (looking), a `>_` prompt with
its cursor blinking (running), a flask filling (the tests running, on
`state`'s `wact`), an hourglass with its sand running (waiting). A
failure landing turns it to a red cross on a dark red screen, a timeout
to an amber clock, each for the word forward's 2.5 s; a work act's
result to a tick or a cross for its 2.6 s. As a failure lands the hands
flail up and down by turns for 1.1 s (`flailLift`).

### The work acts (the board's)

A command worth naming, the tests, the build or a push, for as long as
it runs (on `state`'s `wact`). It's the work's, never a card: the
monitor shows it (a flask for the tests) and the strip's term says it
(`running tests`, `building`, `git push`), then how it ended, in sage or
clay (`tests passed`, `build failed`). It shows as running for at least
900 ms and its result for 2.6 s (`kActLeadMs`, `kActResultMs`). As the
result shows, the body answers once (`GelFace::answerAct`, through
`Engine::jolt`): a hop at a pass, a flinch with its lids squeezed at a
fail; nothing while a finger, a Moment or a needs-you has the body. An
agent's card stays in its hands meanwhile.

### Transitions (the board's)

A short clip on the way from one Doing to another, instead of a cut
(`GelFace::showTransition`): `to-work` (it tucks each side, as if rolling up
its sleeves, and settles down at the keys), `to-rest` (it sits back tall and
stretches), and `to-sleep` (a slow stretch with its eyes shutting,
and it settles). Each is half a second to a second, on the body only, over the
new look, which has already come, so it delays nothing. A reaction, a needs-you,
a finger or a word forward cuts through it, and with one of those up, or the Mac
gone, it doesn't start. The mouth is one size of "o", so `to-sleep`'s yawn is
more stretch than mouth.

### An agent's card (the board's)

While an agent has handed Boop a card and nothing above Doing has the
screen, Boop holds it (`gel/card.h`): the agent's window across its front,
one of its two hands at either side. A title bar in the agent's lane colour names
the agent (`claude`, `codex`, the state's `card.g`) with three window
dots, over a flat dark panel with square-ish corners, rimmed in the same
colour; the desk's monitor frame lights in it too (`paintProps`). It
reads as the agent's, never as one of Boop's own round, glowing signs. The main thing is in
the sign's font and the small line under it in the large one; a guess that
has run out turns the small line red. With more than one card, dots under
it say how many and which. Boop stands up on the card (`cardHop`), so its
face stays clear; no pastime is dealt and it doesn't type along, since
its hands are full; the desk stays, and the strip's term too.
The card rises over 220 ms as it comes. A sign, a low sign, an ask,
the needs-you screen and the drawer each take its place, and it comes
back after.

### The work stream (the board's)

While the agents work and nothing needs you, the board draws the Mac's
work stream (`render/stream.h`, `gel/stream.h`). Nothing falls behind the
body. The newest call's doing of any lane (`Stream::newest`), what its
agent is doing in a verb and its object, is the work's term, first in
the strip in its own font, grey: `searching TODO`, with the counts as
marks at the right end (a spinner and its number, a sleeper and its,
the to-do list last), cut to the room they leave (`termFor` in
`gel/lane.cpp`). The counts in full are the drawer's, pulled up from
the strip; with no term, the strip says them in words. It changes in place, with no card and no rise: cards
are for you, the desk and the strip are for the work. A failure or a
timeout landing turns it to its word and what happened, in clay or
amber (`swift failed`, `curl timed out`), for the word forward's 2.5 s.
When the agents stop, a word may still come forward for 1.5 s
(`Stream::kEndMs`), as a turn's end does; something needing you clears
everything at once.

Almost every call is only that, its word in the strip. In front, after
the props and before the sign, the few a `call` brings forward fly from
the desk's monitor and do what their move does (`render::CallMove`),
in sixteenths of a pixel so they glide (`render::gel::text16`),
everything gone by 2.5 s:

| Move | Styles | What plays |
| --- | --- | --- |
| Sink | land, helper, back | Onto the crown, sinking in under a spreading ring (a helper's going and its coming back too) |
| Hit | bonk, bonk2, bonk3, throw, no, timeout | Between the eyes: it sticks, slides off (thrown back on the top rung) under three stars, five up the ladder; dizzy spiral eyes over its own (the body's colour under them), 1 to 1.3 s |
| Shrug | shrug | Its word beside the head, as the body shrugs |
| Shatter | shatter | Bursting into its glyphs, swallowed |
| Gather | gather | A turn done: its word, from the monitor into its mouth, and "mm!" |
| Drop | drop | Stopped, or failed (`failed`, `context full`, `rate limit`, `overloaded`): its word drops onto its crown, grey, switched off |

As it lands the body answers through the engine (`Engine::jolt`): a push
on the finger's pull springs, as a fling let go (knocked back and
squashed by a hit, squashed by a word sinking in, stretched up by a shrug), your no's flinch with its lids squeezed (0.6 for
450 ms) and a timeout's nod (0.9 for 700 ms), opening over their last
300 ms; nothing while a finger holds it. A word forward moves on the
device's clock, not the engine's paced one, so it flies as fast however
busy the agents.

## States share one scene

Build a persistent desk and computer once. Typing, looking, running and
waiting (The four activities, above) are activity submodes,
not swaps to unrelated sets. Keep desk positions and parent transforms
stable, change the body's pose, the hands and the monitor's one shape. Every state ([STATES.md](STATES.md)) still has its own
meaning, variations and audio policy.

An action recipe has phases `enter → act → recover → sustain`. Start
from the current pose, blend in, perform its contacts, recover toward the
current state target, and sustain. A state change cancels future contacts
from the old recipe but leaves physical velocities alive. Start from
current controls, not from a hard-coded neutral first frame. A loopable
authored offset starts/ends at zero offset and compatible derivative;
the continuing physical body need not return to a frozen identical frame.

Never reset face/mood when running becomes looking. Never destroy the
desk between work variations. A completion reveal may raise a card in
front of the same hero; after the Moment, return toward the **latest**
host snapshot, not a stale state saved before the animation.

## The mood beat

There is no mood graph. When the face changes, its arts cross over; and
when the change is a change of mood, the body gives one small beat
(the engine's `MoodBeat`, `gel/acting.cpp`). A change of face within one
mood (happy to pleased, annoyed to grumpy) has none: slimegen's `kMoodOf`
says which lasting mood each face is of, from the pack's
`character.json`. Each change of mood deals its beat afresh, one of three:

| | Variant 0 | Variant 1 | Variant 2 |
| --- | --- | --- | --- |
| Beat | Soft | Gather and settle | Blink: a short hold |
| Body duration (ms) | 420 | 680 | 360 |
| Face window (ms) | 320 | 360 | 460 |

A change of face with no beat is the soft one's, its face window 320 ms.
Direction follows the authored source and
destination profiles. Using their lean `L`, strength `G`, delay `D`, eye
openness `E` and mouth width `M`, the directional score is
`(Lto − Lfrom) + (Gto − Gfrom) × 0.025 + (Dfrom − Dto) / 10000 + (Eto − Efrom) × 0.01 + (Mto − Mfrom) × 0.005`.
Direction is its sign and amplitude is `clamp(0.8 + abs(score) × 4, 0.8, 1.2)`.
Going back reverses the lean. Face dimensions distinguish otherwise
equal authored body profiles.

Let `p` be the beat's progress, clamped to [0, 1],
`P = sin²(πp)`, and `H = 0` before progress 0.25, otherwise
`sin²(π(p − 0.25) / 0.75)`. The additive target coefficients are:

| Primitive | Lean | Squash | Forward |
| --- | --- | --- | --- |
| Soft | direction × 0.009 × P | 0.004 × P | 0.003 × P |
| Gather and settle | direction × 0.026 × P | −0.032 × P | 0.012 × sin(2πp) × P |
| Blink | direction × 0.006 × H | −0.014 × H | −0.004 × H |

Targets multiply the directional amplitude, limited per primitive so that
no target leaves its channel's displacement bound: the amplitude is at most
each bound over the beat's largest coefficient on that channel, which none
of the three reaches at 1.2. The beat owns three additive springs with
frequency 14, damping 12, velocity bound 1, displacement bounds 0.06
lean, 0.05 squash and 0.04 forward, integrated in at most 1/240 s substeps.
These channels compose with the current activity, mood posture and
gesture channels before the aggregate pose/life clamps. A retarget keeps
every spring's position and velocity, and changes nothing drawn at that
instant. The short hold is part of the additive target; it never pauses or
resets the V1 body.

Face controls retarget immediately from their actual current values and
velocities. From rest, their critically damped springs stay between those
captured values and the new semantic target; a rapid A→B→C retarget uses
the in-progress controls and their velocity as C's start, so it may coast
briefly past its captured value but stays within the span of every value it
started from or was asked for. Sleeping continues to use the shared quiet
face.

**The face's layers** (`gel/motion.cpp` `SemanticFace`) are the arts
drawn, oldest first and the current one last, at most four. At a retarget
every layer's weight starts again from its value and slope then, a cubic
Hermite over the transition's face window toward one for the new art and
zero for the others (the props' ramp): from rest a smoothstep, and a
retarget mid-window keeps every weight's velocity. The window is counted in
milliseconds. A layer's weight is its share of them all, so the weights sum
to one. An art still fading comes back from the weight it has; a layer at
zero that can only stay there is dropped (one the Hermite held at zero
among them: going out fast into a longer window, a weight dips below zero,
and is flat there); a fifth art drops the faintest of the
four, the others' shares growing to fill what it leaves: the one step there
is, and only when more than four arts change within one window. When the
window ends, only the current art is left. Natural blinks and a bit's lids
close the eyes; nothing else does.

**Morph or cross-fade, feature by feature, by one rule.** The board
draws each layer's features: each eye, the mouth, the tears, and the
cheeks with the strain mark (`gel/art.cpp`). slimegen gives each art's
features a shape (`slime_art.h`'s `ArtRange::shape`, from their paths'
point counts, fill or stroke and colour); where layers draw a feature in
the same shape, it is drawn once, its points, pen widths and opacities
averaged by weight, at their summed weight, at the oldest of those
layers' turn in the draw order, so a face coming in at weight zero moves
nothing: two bean eyes ease into each other, a closed arc eases into a
droop. Different shapes cross-fade: each
look is laid over the body alone and the looks blended by their weights
(`raster.h`'s `CrossFade`), so the eyes' and the mouth's opacity, summed
over the arts, stays one, and where two looks both ink a pixel none of the
body shows through (drawn one over the other at half each, a quarter
would): a ring of a mouth gives way to an open U. The cheeks and tears are drawn at their opacity controls. (While
the JavaScript reference drew the face, it compared each feature's
recorded drawing instead, and the two rules disagreed on 80 of the 4,730
pairs of arts' features; the board's is the one rule now.)

**Drawn ratios.** Each layer's art is drawn at the live control over its
own dimension, passed through a smooth saturation `1 + x·r / (r + |x|)`
(with `x = ratio − 1`, `r = 1/3` above one and `1/4` below), so it has
slope one at rest and never leaves (0.75, 4/3), and at rest is one: the
arts crossing over are drawn near one size as the controls move. Falling
asleep, an awake art below one is drawn as far toward the control itself
as the face is shut, `soft − (soft − r) × shut`, its eyes' `r` no smaller
than the line (half the lids' pen, 0.015, over the eye's half height). The
shared sleeping face is its own art (`calm:asleep`) drawn at its own squashed size (eye
0.004, mouth 0.018 × 0.008), so its ratios also settle at one. Pen widths
never stretch with a feature's scale. The board draws a second art only
while one crosses over.

Quiet rest and active attention permanently suppress the current beat's
body gesture, with its springs settling toward zero. Clearing an alert or
waking does not replay it. The face still retargets, and the attention
request, card and consumed reveal keep their identity. A grab defers the
current beat while the face continues: progress may be held for at
most 320 ms of accumulated grab time. Releasing sooner lets the current
beat continue from its springs; reaching the limit expires its body
gesture permanently. There is only one current beat, so a newer retarget
replaces deferred work and release never drains a gesture backlog. Beats
emit no contacts or sound cues.

## Continuity of what is drawn

Every frame `test_gel` drives is held to these (`tests/firmware/test_gel/frames.h`),
over every mood in every state and take, every directed edge in all three
variants, and the interruptions: for each channel the board draws (the
eight face controls, each layer's weight and drawn sizes, the mood
posture's lean and squash and every prop's visibility):

- **No jolt at an event.** Let `Δ²` be a frame's change in per-frame
  velocity, `x[n+1] − 2x[n] + x[n−1]`. In the frame after the host says
  something (a mood, the facts, a request, a lost link, a finger), `Δ²` is
  at most **2×** the largest `Δ²` the same channel makes anywhere else in
  those runs. A first-order filter fails this (about 5×: its velocity jumps
  from rest to its maximum in one frame); a critically damped spring passes
  (about 1.1×). Every art's weight counts as one channel, and a drawn size
  as its control's.
- **Sizes follow their controls.** Each layer's drawn ratios stay in
  [0.75, 4/3] (an awake one shutting, down to 0.75 × (1 − shut)), and a
  drawn size (a ratio times its art's own) moves no further in a frame
  than the control it follows, the saturation's slope being at most one,
  and what shutting moves it: its own size times the frame's step of
  `shut`.
- **Arts cross over without pops.** A layer's weight moves at most a 16 ms
  slice of the Hermite over the shortest face window, the face's own 180 ms
  (waking), reversals included (sampled, with 2% margin: about 0.149 per
  frame), a new art's first frame included; the weights sum to one.
- **No prop pops.** A prop's visibility moves at most a 16 ms slice of its
  ramp: the Hermite's steepest slope over its 200 ms, reversals included
  (sampled, with 2% margin: about 0.134 per frame). The desk moves at most
  its own spring's steepest frame from rest (about 0.074). The board's lane
  fades its strip over the same 200 ms as it comes and goes, one going
  still showing what it showed: the board's app decides it for every face
  from when the strip came or went (`app/behaviour.h`'s `strip`), so how
  often frames are drawn doesn't change one. The gel draws the strip whole
  and blends it once at that opacity: its rows hold nothing else, over
  black, so that is scaling the pixels it wrote, in place, with no buffer,
  and a hole (the working mark's open half, a mini's eyes) stays one.
- **The face never fades.** Through a cross-fade between differently
  shaped arts (calm to happy, happy to sad, calm to wounded's thin tears,
  falling asleep's swap and waking), the board's frames, 40 ms apart,
  keep at least 85% of the visible ink of the fainter of the two faces it
  crosses between: the pixels the face takes at least a quarter of the way
  from the body's luminance to the ink's, eyes and mouth (a water eye's
  fill, the cheeks and the tears are paler than the body and don't count).
  Falling asleep, those are the lines it squashed to and the sleeping face:
  the eyes closing is the morph, not a fade. The least is 90%, waking
  (falling asleep's swap 96%, happy to sad 99%; calm to happy and to
  wounded show more than the fainter end, both arts showing). Where two
  shapes don't overlap, the frames half way are dimmer by a stricter count,
  each shape at about half its strength, which is the cross-fade.
- **The body never teleports.** Each V1 body mode's position and velocity
  in a frame equal its own spring's integration from the frame before (an
  admitted impulse changes only velocity, at its event).

## Variability, without chaos

The engine is seeded (53 after a reset; the board's own seed at power-on).
First pick an authored variation compatible with state/mood and host
outcome/context, excluding the most recently used. Then choose bounded
microparameters: a desk contact's time and strength. Make variability
visible in action rhythm, not only random tint/volume. Clamp inputs; an LLM
cannot add a limb, change physics or invent a successful result. Sound has
a random source of its own, so what sounds never changes what's drawn.

The full activity matrix uses the shuffle bags described above, keeping
recovery-boundary changes and no immediate repeats. Ten minutes of work
can vary silently without ten minutes of sound. Whole-state completion and
alerts are event-gated Moments, not periodic random surprises. No
per-frame LLM/API call is required.

## Alerts, pokes and interruption

Use the repo's LinkKit turn/attention semantics, not an invented priority
scheduler that delays needs_you. A new request starts the upper alert
once, with broad surface knocks followed by the visible confirmation;
then its card holds silently. An alert that listening or a link timeout
interrupts before its confirmation resumes where it stopped, so no request
loses its knocks or ding. Mood may change expression/knock character but
never restarts an already-consumed notification sound. Preserve the bottom
text lane and do not obscure the prompt with long acting.

Poke can add an impulse immediately while the engine keeps factual state.
If the current alert/finish tap opens a thread, honor that behavior; it
still never grants permission. Surface drag is a separate interaction. A
poke keeps the mood.

## One face per board

The owner selected one face per board at build time: the AMOLED uses the
integer gel renderer behind the common face interface. There is no runtime character switcher and no frame
streaming over the link. The Mac's popover and onboarding show the
board's own firmware built to WebAssembly (characters/CHARACTER.md §9),
which `boopctl mirror` checks draws every gel scenario as the native
simulator does, pixel for pixel. Facegen does not convert the gel.

The first full-panel run on the board missed the provisional frame-rate
target, so the renderer briefly used a lower internal resolution; it has
since returned to native panel pixels with a smaller mesh and tracked
clearing. Appearance, speaker quality and physical audio latency remain
separate reviews.
