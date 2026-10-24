# Continuous actor and animation authoring

Updated 2026-10-24. The pure reference engine and all activity scene
families are implemented, idle, sleep and a finish have their comedy
(Comedy, below), the board's gestures have a take each (Gestures), the
looks have occasions (Occasions), and one face flows into the next
(Directed edge bridges: its arts morph or cross-fade, never closing). Q1 representative art review was approved on
2026-10-02. Full scene coverage is engineering evidence; the opt-in host graph, Mac mirror and native integer port are implemented. Contact-synchronized
reference sound is implemented; timbres remain sketches.

## Keep the object; change its targets

The current [renderer](render/webgl.mjs) generates a dome mesh and
deforms it analytically. It shades blue translucent gel and a soft rim,
then applies low-resolution bloom. There is no inner jellyfish cap or
model asset. `paintFace` draws pupil-free rounded eyes/mouth/cheeks/tears
to a scratch Canvas texture; the renderer attaches it to the body using
rest-surface coordinates. Do not make the face slide independently during
a grab or body deformation.

Source areas to inspect:

| Area | Current responsibility | How to extend |
| --- | --- | --- |
| `profiles`, `paintFace` | Face designs from expressions.json | Edit catalogue + a matching painter primitive; rebuild catalog.js |
| `advance`, `pose`, `impulse` | Accepted V1 springs/blink/gaze | Preserve seven locked blocks; add channels outside them |
| `perform`, `actorChannels`, `composePose`, `posture` | Additive authored emotion acting | Add bounded activity layer without replacing base pose |
| `createGL`, `shape`, material fragment and bloom | Persistent body + gel appearance | Keep silhouette/material identity; don't change them per mood |
| `startGrab`, `moveGrab`, `releaseGrab` | Local pull, pointer capture, rebound | Retain bounded spring state; explicitly handle host termination |
| `createFallback` | Lower-cost Canvas approximation | Preserve expression/interaction semantics; not identical 3D material |

The seven accepted source blocks are executed from
[engine/motion-v1.mjs](engine/motion-v1.mjs), including the exported GLSL
deformation and injected frame driver. Their hashes remain unchanged in
[contracts/motion-v1.json](contracts/motion-v1.json). The hash validator
protects their exact JS/GLSL code, not all mutable art around it. Changed
physics require an explicitly named reviewed motion revision. The
surface-drag/acting extensions are later review candidates, not silently
part of the accepted V1 lock.

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
outside the locked code. While one face gives way to another, the painters
draw both arts, features of the same shape morphing and the others
cross-fading (Directed edge bridges, below), so the face never closes or
fades. The original face weights remain only for the locked timing; the
mood posture reads its own critically damped weights.

## Headless reference traces

`createSlime({seed, catalog, reducedMotion})` returns `setFacts`, `setMood`,
`poke`, `shake`, `perform`, `dragStart`, `dragMove`, `dragEnd`, `step` and
`inspect`. Only `step(ms)` advances the monotonic presentation clock;
retarget calls preserve displacement and velocity. The engine uses no
DOM, wall clock or global random source. The browser adapter freezes its
presentation clock while hidden or paused and terminates grabs on pointer
cancel, lost capture, focus/visibility loss and host boundary exit.
The scene router adds `oneShot({id,name,args})`, `setLinkTimedOut(bool)`,
`clearTransient()` and `holdExpression(mood|null)`. `setFacts` now takes a complete host snapshot:
an omitted attention object clears attention. The explicit timeout is an
adapter input; elapsed time alone never invents `no_app`. These are local
engine calls, not new wire fields. The browser script player uses the same
event operations and clock; its pause/hidden gaps do not skip script time.

`tools/trace.mjs --script scripts/idle-60s.jsonl --seed 53` emits every frame
at a 16 ms cadence, beginning with `step(0)`. Events apply at the first
frame at or after their timestamp. JSON stores scalars to six decimal
places (at most 0.5e-6 rounding error); deterministic full-precision replay
is checked separately. Traces omit repeated static art/prose, labels, input
facts and internal posture weights; dynamic face controls, physics and
presentation channels remain in every frame. Golden traces are checked, never refreshed by
`check.cjs`. The builder checks the module bundle separately from traces.

## Phase 1 channel bounds

The accepted springs, frame cap, contact bounds, breathing, blink and gaze
values remain in the motion contract. The imported additive gesture
springs retain frequencies 11 (lift), 10 (roll), 9 (other channels), damping
6.4 and the same 1/240 s substeps. Displacement limits are 0.24 for lift,
0.12 for roll, 0.18 for forward and 0.42 otherwise, velocity limit 5.
Grab spring stiffness is 256 and damping 8 while held (100 and 10 once let
go, so the dome settles back with a wobble rather than snapping),
displacement limit 0.72 and velocity limit 6; target magnitude is at most
0.64, reduced to 35% with
reduced motion. Reduced gesture impulses are 18%. Gesture cadence retains
the authored duration plus 7–15 seconds, starting after one second, or
0.4 seconds after retarget; release defers the next gesture three seconds.
These are the imported audition constants, not approved production pacing.
The face's own window defaults to 180 ms (falling asleep takes 480,
below); directed edge variants select
the face windows below, over which one art crosses over another. Each
semantic control is a critically damped spring,
`a = ω²(target − x) − 2ωv`, with ω = 20 (8 while it sleeps, from falling
asleep until it wakes, a mood changing meanwhile; 30 with reduced motion),
in the
same 1/240 s substeps: it starts from rest without a jump in velocity, and a
retarget keeps both its position and its velocity. Cheek and tear opacity
stay in [0, 1]. Dimensional endpoints come from the original face
primitives; the painters draw each of the engine's `face.layers` at its
ratios (Directed edge bridges, below), so settled faces retain their
authored proportions.

The mood posture (the per-mood squash, and the excited, scared, frightened,
crying and irritated oscillations) is weighted by one critically damped
spring per expression, ω = 10 (25 with reduced motion), whose target is one
for the current expression and zero for the others. The weights sum to one,
so the posture eases between moods with no step in velocity; the locked V1
weights keep timing the motion blocks. `posture` reports its lean and
squash after the quiet blend.

## Representative activity scenes

The first owner review covered working, terminal, needs-you,
task-complete success/failure and the quiet rest alias. Q1 approved that
representative art on 2026-10-02, allowing the rest of the matrix to be
implemented. The review matrix exercises happy, grumpy, sad and frightened in six cases
each (success and failure separately): 24 cases, 20 mood/state cells.
[scripts/representative-matrix.jsonl](scripts/representative-matrix.jsonl)
gives each case an eight-second window. `tools/check-scenes.mjs --coverage`
validates those windows and the full matrix described below before the
builder marks cells implemented or quiet-alias. Sleeping is a justified
shared alias, not three newly authored sleep animations; its one addition
is a snore (Comedy, below). The 24 clips
record the approved representative set; they do not claim separate owner
review of every cell in the expanded matrix.

Priority is explicit no-app, listening, needs-you, the admitted moment,
then the latest base/activity. An activity applies only to working;
unknown activity falls back to working and unknown base to idle. A flat
`state` property does not select a scene.
Attention identity follows the device: a new activation or changed id,
agent or project; changing mood, display name, more or variant leaves the
request's reveal consumed. Attention cuts future decorative contacts
immediately. Clearing and showing the same request id again creates a new
activation. Leaving an alert for a higher-priority state (listening, an
explicit link timeout) saves how far it got: its age and its next contact.
Returning to one that had already confirmed restores its silent hold;
returning to one that had not resumes at that age, so only the knocks and
confirmation not yet reached follow. Each request's knocks and ding play
exactly once, never twice and never not at all
([scripts/alert-interrupted.jsonl](scripts/alert-interrupted.jsonl) pins
it). Returning from a moment resolves the latest snapshot. Only an explicit
successful outcome permits a trophy; failure, missing outcome and unknown
outcome never do.

The local `oneShot` adapter mirrors visual lifecycle, not LinkKit's queue,
TTL, acknowledgments or audio playback. A host that times its own moments,
as the board's Behaviour does, sends `hold:true`: the moment never expires
or finishes on its own and rests after its loops until `clearTransient()`;
`args.variant` (0–2) then names the take the host has already timed, and
`holdExpression` holds its borrowed expression with no expiry. The port
runs this path too ([scripts/host-held.jsonl](scripts/host-held.jsonl)). Unknown names are refused. Repeated
moment id/name pairs do not replay. `args.loops` uses the existing
protocol range, defaults to one, and repeats the same selected recipe; only a new request
chooses the next variation. `react` with a known mood overlays the active
animation without changing its outcome, request identity or lasting mood.
This prototype's expression hold is the first cycle duration below per
requested loop. Bare `react` has nothing to play; a speech-only request
adds no visual animation. A non-null `say`, including `{}`, ends listening
before visual admission. Repeated `listening` keeps its existing lifetime;
`stop_listening` ends only listening.

Every one-shot now has a finite authored recipe, then returns to current
facts. Listening has its own visual recipe and waits for explicit
stop/reply input: this reference engine has no autonomous microphone/listen
deadline and no Voice-duration hold. The production device's timeout,
voice playback and turn lifecycle remain its responsibility. Explicit
no-app masks current activity and suppresses contacts; presentation time
continues, so elapsed moments are not replayed when the link returns.

One desk, id `desk-1` with normalized anchor (0.5, 0.64), persists across
work modes. Three shuffle-bag recipes per mood/state/factual outcome or context differ
in rhythm, with no adjacent repeats; asleep and a successful finish have a
fourth (Comedy, below). Routine work changes variation after
recovery; alert/result requests choose once at entry. Mood retargeting does
not restart an existing recipe or alert. Original emotion gesture recipes
run only in idle without a grab; the activity scene owns the choreography
elsewhere. A state change cancels future recipe contacts but retains every
spring position and velocity, including the composed body pose.

A drag consumes elapsed physical keyboard/knock contacts without emitting
them. Factual alert/result reveals still happen while held, so dragging
cannot hide a real completion or its outcome. Release never plays an
elapsed contact again. Rest retains the stored mood, cancels acting and
contacts immediately, and lets residual springs settle. The shared sleepy
art crosses over the awake one in a window of its own, 480 ms, its
controls on the slower spring, so the lids droop shut rather than snap;
waking takes the face's own 180 ms (`sleepTransition`,
[engine/face.mjs](engine/face.mjs)). Its semantic
targets are eye openness 0.004, mouth width 0.018, curve 0.008, and zero
cheek/tear opacity; changing the stored mood during rest leaves this face
quiet.

The candidate art timings live in
[engine/scenes/constants.mjs](engine/scenes/constants.mjs): 240 ms
entry, 480 ms recovery, 120 ms contact envelopes; cycles of 3,200, 3,700 and
4,200 ms. Contact jitter is at most 40 ms and gain jitter 10%. Activity
springs use frequency 12, damping 10, velocity limit 1.2 and displacement
limits 0.08 lean, 0.06 squash, 0.05 forward. The desk's visibility uses
frequency 10 and damping 14; these springs retain the motion contract's
integration substep. Activity target magnitudes use the existing
reduced-gesture multiplier. The quiet posture blend uses the activity spring
coefficients and remains in [0, 1]. Final pose bounds are
[1.25, 1.32, 1.14, 0.72], life bounds [0.24, 0.12, 0.23], with no edit to
V1's own springs. These values are pinned by scene checks and remain art
candidates, not host mood pacing. Decorative props are clipped above
normalized y=0.8; the lower 20% belongs to host status. Both browser
renderers use the same prop painter, and the board's props draw from the
same channels.

Every other prop (the alert, result and start cards, the helpers,
the listening cue and the touch marks) has a **200 ms visibility ramp** for
entry and exit ([engine/scenes/ramp.mjs](engine/scenes/ramp.mjs)): a cubic
Hermite from its current value and slope to the target, so from rest it is a
smoothstep and a reversal keeps its velocity; it ends exactly. Held within
zero and one, it's flat where it's held, so a retarget never brings back
what it held at zero. Each prop's
`visible` is its drawn opacity: the ramp, times a card's reveal or the
helpers' recovery. When its route ends, a prop fades out still carrying the
content it last showed (the alert's request, agent, project, name and count;
a card's state, label and outcome; the helpers' mode, count and progress;
the listening pulse; the touch kind). New content (another request, or the
helpers' next cycle) waits until nothing of the old is drawn, then fades in
from zero; the alert's content follows the current request at once. Contact
envelopes (the knock, the confirmation, the key and touch pulses) stay
deliberate impacts.

The authored keyboard contact times, in milliseconds before jitter, are
specified by [engine/scenes/desk.mjs](engine/scenes/desk.mjs) and pinned in
the scene tests:

| Rhythm | Variant 0 | Variant 1 | Variant 2 |
| --- | --- | --- | --- |
| Working | 580, 780, 1040 | 560, 760, 1680, 1880 | 1100, 2220 |
| Terminal | 600, 780, 960 | 780, 1810, 2090 | 580, 740, 900, 1060, 1960, 2120 |
| Frightened working/terminal | 800, 1700, 2040 | 740, 1800, 2240, 2480 | 1080, 2380 |
| Grumpy terminal | 640, 800, 960 | 800, 960, 1120, 2100 | 660, 820, 980, 1140, 2120 |

Sad work retains every other contact of its ordinary rhythm, starting with
the first, for longer pauses. Keyboard strength/lean are 1.05/0.018 for
happy, 1.12/0.032 for grumpy terminal, 0.62/−0.016 for sad and 0.68/−0.018
for frightened; other work uses 1/0.018. Contact side alternates. The body
uses the contact envelope and strength for side lean 0.024, squash −0.052
and forward 0.045. A successful reveal targets squash/forward 0.036/0.025;
a failed reveal −0.048/−0.035, before the activity bounds and reduced-motion
multiplier. These candidate motions are covered by the full channel traces.

Alert entry has one, two or three knocks at [420], [420, 740] or
[420, 690, 960] ms. Result reveal is at [680, 960, 1240] ms. The alert and
result recipes shape those times and forces using
[engine/scenes/mood.mjs](engine/scenes/mood.mjs):

| Mood | Delay (ms) | Knock spacing multiplier | Strength | Lean |
| --- | ---: | ---: | ---: | ---: |
| Happy | 0 | 1 | 1.05 | 0.014 |
| Grumpy | −40 | 0.86 | 1.12 | 0.024 |
| Sad | 160 | 1.18 | 0.62 | −0.016 |
| Frightened | 240 | 1.28 | 0.68 | −0.018 |
| Other canonical moods | Derived from authored expression recipes below | Derived | Derived | Derived |

The first knock receives the delay, subsequent spacing is multiplied, and
the alert reveal follows the last knock by 240 ms. Its card ramps in from
the request's arrival, with no opacity floor, and ramps out when attention
clears; `props.alert.confirmation` uses the contact envelope to brighten it
once at the reveal, then returns to zero. Its reveal strength is invariant
at 1. A result receives the mood's delay and strength while its success or
failure remains factual. A card's reveal is its own, a second ramp of its
prop's: up over 400 ms from its reveal contact (`cardRevealMs`, twice the
prop ramp, so it rises in rather than appears) and down over the recovery's
480 ms, each from its time on the route's clock, but not down before it's
up: one revealed in the recovery rises whole, then falls; it is cleared before an
explicitly repeated loop. A route that ends while its card rises or falls
leaves the reveal going as it was while the card's ramp fades it out, so it
never stops dead. Contacts carry unique request,
generation, iteration and index identity; the `cues` audio output is consumed once per contact by the synchronized
scheduler (sound/README.md).

The studio's **Record review set** captures 24 activity or 13 directed-edge
silent 6.4-second clips, selected by **Review set**,
from the composed canvases, with their case labels, at up to 30 fps. It
does not use the camera, microphone or desktop capture. Clips remain local
until downloaded or saved through the opt-in loopback server; the page exposes
a save link for each. This is visual
evidence only; audio is independently enabled; the captured videos remain silent.

Suggested composition order: base shape → mood posture → activity pose →
gesture impulses → local grab → final bounds. There must be one owner of
each channel: a drag owns the grabbed patch, activity owns keyboard
contact, mood owns face style, and attention owns priority. Blend
additive offsets; cap the combined result, not each layer in isolation.
Make suppression explicit so angry+typing+drag cannot exceed the body's
safe envelope or produce competing repeated impacts.

## Full activity scene matrix

The reference engine implements all 25 factual states in the nine scene
families from [state-plan.json](state-plan.json). The full check executes
all 42 canonical moods × 25 states: 1,050 cells, including 84 quiet aliases
for asleep/no-app. Starting is exercised with each of its four contexts,
and task-complete with success and failure, giving 1,218 factual test
cases. Every active case exercises all its variants: three, a successful
finish's four, a gesture's ten (each asked for, as the board does), and
idle's takes (an expression's three gestures and its comedy, six or
seven); quiet aliases retain mood and use the shared
sleeping face without acting, and without contacts but a snore's breaths.
The two optional face alternates are outside this canonical matrix.

Coverage requires actual execution, bounded physical channels, factual
labels, a distinct motion/contact signature and visible props for each
variant. Signatures use the same number of normalized phase samples
so duration or metadata alone cannot make identical acting pass. The
builder consumes the checked cells; declaring a state implemented is
insufficient. These tests establish engineering coverage, not separate
owner art approval for every cell.

The activity scene selects a shuffle bag keyed by mood, state and factual
outcome/context. Desk modes, delegating and listening select again only
after recovery. A one-shot selects once per request and keeps that recipe
across explicit loops; an attention entry selects once and then holds.
Idle uses its expression's three original gesture recipes, then its comedy,
with a separate automatic shuffle bag per expression and the quiet interval
specified above. A bag's first round deals its first three entries; every
later round deals all of them (Comedy, below). Each round is exhausted
before the next and no entry repeats across a refill. Explicit review `perform(index)` remains
an exact selection. Changing targets never replaces the body or its
springs. The intentional idle scheduler change updates seeded reference
traces; the seven V1 source locks remain unchanged.

For the other canonical moods, [engine/scenes/profile.mjs](engine/scenes/profile.mjs)
derives bounded traits from the expression's authored performances. Let
`D` be their mean duration in seconds, `E` the mean absolute cue velocity,
and `L` the sum of signed lean/forward cue velocities divided by the total
cue count. Empty cue lists use a denominator of one. The traits are:

| Trait | Formula and bound |
| --- | --- |
| Delay, milliseconds | `clamp((D − 3) × 120, −160, 160)` |
| Contact spacing | `clamp(D / 3.2, 0.88, 1.18)` |
| Contact strength | `clamp(0.6 + E × 0.32, 0.68, 1.12)` |
| Lean | `clamp(L × 0.045, −0.022, 0.022)` |

The four reviewed moods retain the explicit table above. Their existing
working/terminal rhythms remain unchanged. For other desk moods, the
first contact receives the delay and later offsets from that first
contact receive the spacing multiplier; lean adds the trait to the
ordinary desk target. Crying+working has an authored exception: contact
times [760, 1780], [640, 2120] or [1020, 2300] ms, strength 0.55 and lean
−0.024. All keyboard contacts then receive the existing bounded jitter.

Outside the four reviewed moods, the selected expression performance also
contributes a bounded recovery gesture. Recovery progress maps the entire
authored performance duration into the scene's recovery window. Each cue
contributes `velocity × gain × sin²(π × cueAge / 0.48)` only while its
authored age is between zero and 0.48 seconds. Roll maps to lean, lift to
squash, and ripple to forward; the corresponding gains are 0.025, 0.018
and 0.015. Existing lean/squash/forward cues retain their channel. The
result passes through the activity spring and final bounds above. A grab
or quiet state suppresses these contributions. No new physical body,
face silhouette, mood decision or factual outcome is introduced.

The additional desk rhythms before mood shaping and jitter are:

| State | Variant 0 contacts (ms) | Variant 1 contacts (ms) | Variant 2 contacts (ms) |
| --- | --- | --- | --- |
| Planning | 940 | 620, 860 | 760, 1560 |
| Tool use | 520 | 780, 1060 | 620, 1460 |
| Searching | 620 | 540, 760 | 660, 1640 |
| Analyzing | 1020 | 720, 1680 | 1520 |
| Testing | 560 | 480, 720 | 740, 1840 |
| Waiting | None | None | None |

The frightened contact-bearing desk modes share its hesitant rhythm;
sad desk modes retain every other ordinary contact, beginning with the
first. Waiting overrides contacts to an empty list and uses lean targets
[0.006, 0.014, −0.010]. Its focus cycles are [1, 2, 3] per recipe. Listening
also has no contacts, uses lean [0.022, −0.012, 0.008] and pulse cycles
[2, 1, 3]. For both, lean is modulated by
`0.65 + 0.35 × sin(2π × progress × cycles)`, in addition to entry/recovery
envelopes. The visual focus/pulse is
`0.5 + 0.5 × sin(2π × progress × cycles)`, held at 0.5 with reduced motion.
The same desk stays in place; its screen shows a list, link, magnifier,
inspection cards, neutral test dots or a quiet waiting cue. Testing never
claims PASS/FAIL before the host sends a result.

The remaining scene recipes use the shared cycle, entry and recovery
timings above:

| Family/state | Authored contacts before mood delay | Visible meaning |
| --- | --- | --- |
| Starting | Reveal at [520, 820, 1080] ms by variant | `new_task` → NEW TASK, `session` → START, `continuation` → RESUME, `compacted` → COMPACTED; missing context stays neutral START |
| Wake up | Stretch [560], [760], [900, 1500] ms, then settle [1180], [1240, 1420], none | You back after a long break: the start family's body, with no card. The stretch is a start reveal (the second of variant 2 at 0.7 strength); a settle is a body contact of strength 0.35, sides 0, then ±1 |
| Delegating | [660, 1040], [540, 880, 1220], [820, 1640] ms | Dispatch [2, 3, 2] small helpers beside the same hero |
| Helper return | Reveal at [680, 960, 1240] ms | One returning helper and a neutral report; no assumed success |
| Reply ready/error/stopped | Reveal at [680, 960, 1240] ms | READY / TOOL ERROR / STOPPED, without a trophy |
| Poked | [160], [200, 480], [160, 520] ms | Bounded local dent/wobble/bounce |
| Tap spam | [160, 400], [160, 340, 520], [220, 620] ms | Bounded wobble/squash/dodge complaint |

Start, wake-up, helper and status-result contacts receive the mood/profile delay;
their reveals take its strength. Helper contact sides alternate; variant 2 reverses travel
direction. Their travel progress is smoothstep of age divided by the last
contact time, clamped to [0, 1], so arrival coincides with the factual
report reveal. Helper visibility multiplies the entry and recovery
envelopes. Touch contacts have strength 0.6 for poked and 0.9 for tap spam,
alternating sides and lean targets [0.008, −0.018, 0.012]; they have no
timing jitter or mood-derived delay. Their mood face remains the current
expression, with the bounded recovery profile where applicable.
An admitted `poked` moment also applies the existing locked V1 poke input;
an admitted `tap_spam` applies its shake input. These intentional touch
impulses can change velocity, but never reset displacement or layer state.
Duplicate/refused requests apply no impulse. Fact and mood retargets still
preserve every spring's position and velocity exactly.

The start/helper/status reveal envelope adds squash 0.018 and forward
0.018; a tool-error reveal instead adds forward −0.025. These additions
use contact strength, the existing reduced-motion multiplier and bounds.
All factual cards reveal while dragging; body contacts are consumed
silently during the grab. Return and stop remain neutral, error means a
tool warning, and only explicit task success permits the trophy. A state
change cancels pending contacts at once and resolves the latest facts.

The browser state/context/outcome controls exercise these same calls.
Playing a script or recording the review set explicitly starts a fresh
seed-53 run with a fresh presentation clock and released grabs. Within a
run, every retarget and scene uses the same continuous actor. The capture
controls do not allow a second script to reset a running recording. The
preview remains a local visual reference: LinkKit admission, actual
microphone deadlines, Voice playback, finish-thread taps and production
ports remain their existing owners' responsibilities.

## Comedy

Idle, sleep and a finish have comedy, all of it the same body: a squash,
a stretch, a tilt, a slide or a rebound, never a new silhouette or another
asset.

| Comedy | Where | Its takes | Sound |
| --- | --- | --- | --- |
| Yawn and settle (2.9 s), doze off and snap awake (3.6 s), sneeze and shake it off (2.7 s) | Idle, every expression | Idle's takes 4 to 6 (`idleGags`) | The sneeze's one contact |
| A long, slow yawn (4.2 s) | Idle, bored, tired, lazy and comfy (and comfy's rosy face) | Their own take 4 | None |
| Zoomies, edge to edge (2.6 s) | Idle, excited | Its own take 4 | A landing (`bounce`) at each edge |
| A snore: two breaths, each a slight swell | Asleep | Asleep's fourth take | Each breath |
| Hiccups: the first take's card, then three small hiccups | A successful finish | Its fourth take | The card's fanfare, then three squishes |
| A gift: a small bug beside the card | Proud's successful finish | Its second take, lifted | As that take |

**Idle's comedy is gags, beside the gestures.** Idle's variations are an
expression's performances, so its comedy is more of them, dealt by acting's
bag: an expression's three gestures, its own `gags` (expressions.json), then
everyone's `idleGags`. A gag is in `gags` once, shared. It is a performance
(its `cues`, impulses on the gesture springs) with `keys`, which set a
channel's target (from (0, 0) at its start, a smoothstep to each of the
channel's keys in turn, then its last value), and `contacts`, which sound
and move nothing. The six gesture springs follow their keys under-damped,
as gel does; a gag has two springs of its own, its `slide` (frequency 10,
damping 9, at most 0.7) and its `lids` (critically damped, frequency 24).
The lids close the eyes as a blink does: the drawn blink is the largest of
the natural one, the bridge's and the lids'. The slide carries the whole
dome sideways, its face and its shadow with it, and leaves its shape as it
is. Reduced motion scales a gag's body keys as it scales impulses (0.18),
not its lids. The three gestures stay as they were, so the traits the scene
recipes take from them, and every existing recipe, are unchanged.

**A scene's fourth take is a table of its own.** Every row of
`slime::kRecipes` keeps its three takes; asleep and a successful finish
have a fourth, in `slime::kFourthTakes`, and `slime::kRecipeTakes` says how
many each row has. Widening every row to four would have carried 296 KB of
empty recipes on the AMOLED; the fourths are about 20 KB. A host may ask
for a take from 0 to 3; one its state hasn't is dealt from the bag. A
finish timed without its outcome finds a success's fourth (`GelFace::recipe`).
A fourth take has no gesture of its own, so no recovery gesture.

**Comedy joins a bag's second round.** One rule for every bag, acting's
and the scenes': its first round deals the first three takes, the ones every
state has always had; every later round deals all of them, never opening on
the take just dealt. A fresh mood, a reset and every first round play as
they always did, and the joke comes once the straight takes have been seen.
Acting's bags hold at most seven (`kMaxGestures`: three gestures, an own
gag, three idle gags), the scenes' four (`kMaxTakes`). In calm idle, with a
gesture every 10 to 20 seconds, the first gag plays after about 40 seconds,
then each about once a round, a minute and a half.

**Asleep picks again after each take**, as routine work does. Its first
rest is always the still one, drawn from no bag, so sleep starts still for at
least 12.8 s (the first rest and the bag's first round). The snore lasts
4.8 s: breaths at 600 and 2,600 ms, strength 0.35, each swelling the body's
squash by sin² over 1,200 ms, times its strength, times 0.07, even while
quiet. They are quiet rest's only contacts. A lost link rests still and
never snores.

**The hiccups** reveal the first take's card at 680 ms (plus the mood's
delay), then three body contacts at 1,640, 2,060 and 2,480 ms, strength
0.45, in a 3.7 s take. **The gift** is a flag on proud's second success
take: the result card's content carries it (`props.result.gift`, present
only with one), and both painters draw an amber bug beside the card.

**Comedy's contacts sound in any state**, each with the routine chance (a
quarter): a sneeze's (`sneeze`), a zoomies landing (`bounce`), a snore's
breath (`breath`). They are routine sounds, ducked under a line. The
reference sounds 4 of 14 sneezes over twenty minutes of idle, and 11 of 40
snore breaths over five minutes of sleep.

**Traces keep their columns.** A gag's channels (`actorChannels.slide`,
`actorChannels.lids` and the drawn `slide`) join the inspection once a gag
has played, and `gift` appears only with one, so a trace with no comedy
keeps its columns. Of the twelve earlier reference traces only two changed:
`idle-60s` from its second round (40 s), and `representative-matrix` from
asleep's first pick again (3.2 s into each sleep). `scripts/comedy.jsonl`
plays every gag, the hiccups, the gift and a snore, sounds included, and
the port replays it frame for frame.

## Gestures

`gesture` is the board's own reaction to what you do to it, a one-shot
in the touch family. Its takes are the board's gestures, in its order
(`render::Gesture`, [engine/scenes/gesture.mjs](engine/scenes/gesture.mjs)):
the board names one (`args.variant`, 0 to 9), no bag deals them, and a
gesture asked for without one plays the first. Each is the same in every
mood: a scene recipe whose body contacts dent the dome, pulse the touch
mark and sound a squish on its first loop, and a gag of its own
(`expressions.json` `gestures`, keyed as Comedy's are) that acting plays
with it. The board borrows a face for each while it plays, as a react's
expression is borrowed, and the mood stays.

| Gesture | What the body does | Face it borrows | Gag |
| --- | --- | --- | --- |
| handoff (BOOT hands you an agent) | Lifts and leans in, offering | pleased | 2.4 s |
| stroke | Melts under the hand, eyes shut | affectionate | 3 s |
| ruffle (stroked the wrong way) | Bristles in ripples, then huffs | annoyed | 2.2 s |
| nose | Squished in at the nose, pops back | surprised | 1.8 s |
| tickle | Giggles, jiggling side to side, eyes squeezed | excited | 2.4 s |
| dizzy (shaken) | Wobbles round, sliding and rolling side to side | baffled | 3.2 s |
| pickup | Stretches up tall | surprised | 2.2 s |
| putdown | Lands squashed and settles | relieved | 2 s |
| startle (a thump on the desk) | Flinches, jumps, lands | stunned | 1.9 s |
| peekaboo (turned face up again) | Squashed low with eyes shut, then rises | happy | 2.6 s |

A scene lasts its gag and 200 ms more. **A recipe may carry a gag.**
The scene names it (`gag`), and acting plays it once for each pass of the
recipe (its generation and iteration), in any state, then waits: its own
next gesture comes three seconds after the gag ends, and none is dealt
while one is held. Acting is suppressed outside idle only while the
recipe has no gag. A recipe with a gag recovers with the gag, not with the
expression's recovery gesture. `scripts/gestures.jsonl` plays all ten as
the board does (held, with their faces), one from work and one with no
take named, and the port replays it frame for frame.

## Notice

The brain's reaction when you name it in your prompt: it heard its name and
looks up at you, surprised and pleased. Its three takes are `notices` in
`expressions.json`, each a gesture's shape (a gag of keys and impulses
under a face it borrows, the scene's contacts) and played as one
(`gestureRecipe`), but dealt from its bag as any state's takes are:
`notice-perk` perks up and leans in (surprised), `notice-hop` hops and
beams (happy), `notice-tilt` tilts toward you and leans in (pleased). It
is the start family with no card. The board borrows each take's face
(`kNoticeFaces`) unless the Mac sends a mood with it.

## Occasions

A look may have takes that need tags (`when`, every one on: the board's
`render/tags.h`, the part of the day, the holidays, `party`, `busy` and
`frantic`) or a wait (`after`, seconds the look has shown), as Pixel's
designs do (characters/CHARACTER.md §9). The host says them with
`setOccasion({when, lookMs})`; the board does on every sync, the Mac's
mirror with the Mac's tags and no wait. While one fits, a pick goes to one
of those that fit 67% of the time (`occasionShare`), any one alike;
otherwise, and while none fits, the look deals as it always has, drawing
no randomness of its own, so no trace without occasions changed.
`expressions.json` `occasions` holds them ([engine/scenes/occasion.mjs](engine/scenes/occasion.mjs)):

| Look | Occasion | Needs | What plays |
| --- | --- | --- | --- |
| idle | morning-stretch | morning | A big stretch up, eyes squeezed, a lean each way |
| idle | night-drowse | night | Heavy lids, sunk a little, a slow sway |
| idle | nod-off | 1,200 s idle | Nods three times deeper, lids closing, then jerks awake |
| idle | party-bounce (and New Year's, Lunar New Year's, Programmers' Day's) | party (newyear, lunar, programmers) | Three hops side to side, eyes squinting; each landing a bounce at comedy's chance |
| idle | friday-sway | friday | A little dance, leaning and sliding |
| idle | winter-shiver | winter | Huddled down, shivering |
| idle | halloween-wobble | halloween | A slow spooky roll and drift, lids half shut |
| idle | valentines-swoon | valentines | Eyes shut, lifted, a lean |
| working, terminal, tool_use | busy-typing | busy | Two quick three-key bursts, leaning in |
| working, terminal, tool_use | frantic-typing | frantic | Six keys in 0.6 s, leaning in harder |
| working | work-stretch | 1,200 s at work | A desk recipe with a stretch-up gag |
| asleep | deep-snore | night | Three deeper breaths |
| asleep | dream | 1,800 s asleep | Two soft breaths and a twitch-and-wriggle gag |

Idle's are gags acting plays in place of its next gesture (numbered after
the expression's takes); the other looks' are recipes the scene deals at
a pick (numbered after the row's takes), the same in every mood, and a
jittered one takes the desk's jitter. A gesture or a host's moment never
takes one. An occasion whose tags go off simply isn't picked again. The
engine has no colour channel, so no occasion tints the gel. The working
looks' quicker pace while the agents are busy is the board's
(`render::workPace`), not an occasion. `scripts/occasions.jsonl` plays a
night, a party, idle dozing, frantic and busy work, a long turn's
marathon, a night asleep and half an hour asleep, and the port replays it.

### Layers over the body (the board's)

The engine draws no costume, but the board's port draws layers over the
body by the same tags, after the face art and before the props
(`firmware/src/render/gel/layers.h`): a hat by the first tag that has one
(Halloween's witch hat; a party hat for party, New Year's, Lunar New Year
and Programmers' Day; a nightcap at night; a bobble hat in winter),
shades on a Friday's day, and the air (snow, confetti, hearts, Zs asleep
at night), and last the sign a reaction holds up. Each sits on anchors
the painter takes from the very vertices it projects for the body
(the rig's `Anchors`, both faces' one type: the dome's apex, ring 6's
sides and front for a brim, ring 15's front for the hands) and the face art's
eye centres, so a layer leans,
squashes, dips under a finger and slides off the screen with the body
and is cut off there with it. Peekaboo's gesture hides the hat. At night
the lids hang a little lower (`kNightLids`) on the awake face, easing out
as the sleeping face crosses in and back as it wakes. The layers read
the engine and never change it, so the traces don't see them; the Mac's
mirror doesn't draw them yet.

## States share one scene

Build a persistent desk and computer once. Working, terminal, searching,
analyzing, testing, planning and generic tool use are activity submodes,
not swaps to unrelated sets. Keep desk positions and parent transforms
stable, change screen cue/cards and contact choreography. Waiting simply
pauses the work action. Helper blobs enter alongside the hero, never
replace it. Every state in [state-plan.json](state-plan.json) still has
its own meaning, variations and audio policy.

An action recipe has phases `enter → act → recover → sustain`. Start
from the current pose, blend in, perform its contacts, recover toward the
current state target, and sustain. A state change cancels future contacts
from the old recipe but leaves physical velocities alive. Bridge from
current controls, not from a hard-coded neutral first frame. A loopable
authored offset starts/ends at zero offset and compatible derivative;
the continuing physical body need not return to a frozen identical frame.

Never reset face/mood when terminal becomes searching. Never destroy the
desk between work variations. A completion reveal may raise a card in
front of the same hero; after the one-shot, return toward the **latest**
host snapshot, not a stale state saved before the animation.

## Directed edge bridges

[engine/bridges.mjs](engine/bridges.mjs) derives the 295 directed edges
from `catalog.graph`, with three variants per edge. The generated
[transitions.json](transitions.json) records the same category and primitive
mapping. A shuffle bag per directed edge selects variants without an
adjacent repeat. Tests exercise each variant from a moving body before
the builder marks the edge implemented. This is an animation catalogue,
not host graph gating: the host still decides whether a transition is
justified. A direct review retarget outside the graph uses the soft
primitive and does not create a new graph edge.

| Category | Variant 0 | Variant 1 | Variant 2 |
| --- | --- | --- | --- |
| Ordinary primitive | Soft retarget | Gather/settle | Blink retarget |
| Ordinary body duration (ms) | 420 | 680 | 360 |
| Ordinary face window (ms) | 320 | 360 | 460 |
| Dramatic primitive | Recoil/compress | Recoil/compress, second motion | Blink retarget with a short hold |
| Dramatic body duration (ms) | 760 | 920 | 560 |
| Dramatic face window (ms) | 240 | 280 | 340 |

The blink retarget keeps its name from when the face closed behind a
blink to swap its art; now its face window crosses over as the others do,
and the name is its body's hold. Direction follows the authored source and
destination profiles. Using
their lean `L`, strength `G`, delay `D`, eye openness `E` and mouth width
`M`, the directional score is
`(Lto − Lfrom) + (Gto − Gfrom) × 0.025 + (Dfrom − Dto) / 10000 + (Eto − Efrom) × 0.01 + (Mto − Mfrom) × 0.005`.
Direction is its sign and amplitude is `clamp(0.8 + abs(score) × 4, 0.8, 1.2)`.
Reversing an edge reverses its directional lean; it does not reuse an
undirected transition identity. Face dimensions distinguish otherwise
equal authored body profiles.

Let `p` be normalized body-bridge progress clamped to [0, 1],
`P = sin²(πp)`, and `H = 0` before progress 0.25, otherwise
`sin²(π(p − 0.25) / 0.75)`. The additive target coefficients are:

| Primitive | Lean | Squash | Forward |
| --- | --- | --- | --- |
| Soft retarget | direction × 0.009 × P | 0.004 × P | 0.003 × P |
| Gather/settle | direction × 0.026 × P | −0.032 × P | 0.012 × sin(2πp) × P |
| Ordinary blink retarget | direction × 0.006 × H | −0.014 × H | −0.004 × H |
| Dramatic blink retarget | direction × 0.026 × H | −0.035 × H | −0.014 × H |
| Dramatic recoil, variant 0 | −direction × 0.045 × sin(2πp) × P | −0.038 × P | −0.032 × P |
| Dramatic compression, variant 1 | direction × 0.022 × P | −0.048 × P | 0.026 × sin(2πp) × P |

Targets multiply the directional amplitude, limited per primitive so that
no target leaves its channel's displacement bound: the amplitude is at most
each bound over the primitive's largest coefficient on that channel. Only
the dramatic compression is affected; its squash limits it to
0.05 / 0.048 ≈ 1.042. Reduced motion further
multiplies them by 0.18. The bridge owns three additive springs with
frequency 14, damping 12, velocity bound 1, displacement bounds 0.06
lean, 0.05 squash and 0.04 forward, integrated in at most 1/240 s substeps.
These channels compose with the current activity, mood posture and
gesture channels before the existing aggregate pose/life clamps. A
retarget preserves every spring's position and velocity. The short hold
is part of the additive target; it never pauses or resets the V1 body.
The inspector labels body progress below 0.35 as gather and the remaining
active part as release; this label adds no new timing behavior.

Face controls retarget immediately from their actual current values and
velocities. From rest, their critically damped springs stay between those
captured values and the new semantic target; a rapid A→B→C retarget uses
the in-progress controls and their velocity as C's start, so it may coast
briefly past its captured value but stays within the span of every value it
started from or was asked for. Sleeping continues to use the shared quiet
face.

**The face's layers.** `face.layers` are the arts drawn, oldest first and
the current one (`face.artId`) last, at most four. At a retarget every
layer's weight starts again from its value and slope then, a cubic Hermite
over the transition's face window toward one for the new art and zero for
the others (`hermite` in [engine/scenes/ramp.mjs](engine/scenes/ramp.mjs),
the props' ramp): from rest a smoothstep, and a retarget mid-window keeps
every weight's velocity. The window is counted in milliseconds,
`face.transition`'s `elapsedMs` of its `durationMs`, the one clock both
engines keep. A layer's weight is its share of them all, so the weights sum
to one. An art still fading comes back from the weight it has; a layer at
zero that can only stay there is dropped (one the Hermite held at zero
among them: going out fast into falling asleep's longer window, a weight
dips below zero, and is flat there); a fifth art drops the faintest of
the four, the others' shares growing to fill what it leaves: the one step
there is, and only when more than four arts change within one window (a
rapid chain, moods 48 ms apart, drops the art that came 48 ms before, at 5
to 11%). When the window ends, only the current art is left. Natural blinks
and a gag's lids close the eyes; nothing else does.

**Morph or cross-fade, feature by feature.** The painters draw each layer's
features: each eye, the mouth, the tears and the cheeks. Where layers draw
a feature in the same shape, the same calls, colours and styles with only
their numbers differing (the reference painter records each feature's
drawing to compare them; the port's `slime_art.h` names each group's
`shape`, the same paths with the same point counts and colours), it is
drawn once, its numbers averaged by weight (positions, sizes, curves,
angles, pen widths, opacities), at their summed weight: two bean eyes ease
into each other, a closed arc eases into a droop. Different shapes
cross-fade, each at its weight, the newer over the older, so the eyes' and
the mouth's opacity, summed over the arts, stays one: a ring of a mouth
gives way to an open U. The cheeks and tears are drawn at their opacity
controls.

**Drawn ratios.** Each layer's art is drawn at the live control over its
own dimension, passed through a smooth saturation `1 + x·r / (r + |x|)`
(with `x = ratio − 1`, `r = 1/3` above one and `1/4` below), so it has
slope one at rest and never leaves (0.75, 4/3), and at rest is one: the
arts crossing over are drawn near one size as the controls move. The
shared sleeping face is the tired art drawn at its own squashed size (eye
0.004, mouth 0.018 × 0.008), so its ratios also settle at one. Pen widths
never stretch with a feature's scale. The port draws a second art only
while one crosses over.

Quiet rest and active attention permanently suppress the current bridge's
body gesture, with existing bridge springs settling toward zero. Clearing
an alert or waking does not replay it. The face still retargets, and the
attention request, card and consumed reveal retain their identity. A grab
defers the current body bridge while the face continues: progress may be
held for at most 320 ms of accumulated grab time. Releasing sooner lets
the current bridge continue from its retained springs; reaching the limit
expires its body gesture permanently. There is only one current bridge,
so a newer retarget replaces deferred work and release never drains a
gesture backlog. Bridges emit no new contacts or sound cues.

The locked V1 motion source and material hashes remain unchanged. Directed
bridge coverage is verified engineering behavior; the selected visual
review clips support owner spot-checking rather than claiming separate
art approval for all 885 edge/variant combinations. The opt-in host policy and native port are implemented; hardware performance
and owner appearance review remain pending. Contact sound is implemented;
timbres remain sketches pending speaker review.

## Continuity of what is drawn

[tools/smooth.mjs](tools/smooth.mjs) bounds every frame of every script
(check-engine), every directed edge in all three variants with its rapid,
rest, drag and attention runs (check-bridges), and the full scene matrix
with its routing and interruption runs (check-scenes). For each channel the
painters draw (the eight face controls, each layer's weight and drawn
sizes, the mood posture's lean and squash, every prop's `visible` and a
card's reveal while the card is drawn):

- **No jolt at an event.** Let `Δ²` be a frame's change in per-frame
  velocity, `x[n+1] − 2x[n] + x[n−1]`. Where an event (a mood, fact,
  one-shot or input) lands in a frame, its `Δ²` is at most **2×** the largest
  `Δ²` the same channel makes anywhere else in that corpus. A first-order
  filter fails this (about 5×: its velocity jumps from rest to its maximum
  in one frame); a critically damped spring passes (about 1.1×). Every
  art's weight counts as one channel, and a drawn size as its control's.
- **Sizes follow their controls.** Each layer's drawn ratios stay in
  [0.75, 4/3], and a drawn size (a ratio times its art's own) moves no
  further in a frame than the control it follows, the saturation's slope
  being at most one.
- **Arts cross over without pops.** A layer's weight moves at most a 16 ms
  slice of the Hermite over the shortest face window, the face's own 180 ms
  (waking), reversals
  included (sampled, with 2% margin: about 0.149 per frame), a new art's
  first frame included; the weights sum to one.
- **No prop pops.** A prop's `visible` moves at most a 16 ms slice of its
  ramp: the Hermite's steepest slope over its 200 ms, reversals included
  (sampled, with 2% margin: about 0.134 per frame). The desk moves at most
  its own spring's steepest frame from rest (about 0.074). The board's lane
  fades its strip over the same 200 ms as it comes and goes, one going
  still showing what it showed: the board's app decides it for every face
  from when the strip came or went (`app/behaviour.h`'s `strip`), so how
  often frames are drawn doesn't change one. The gel draws the strip whole
  and blends it once at that opacity: its rows hold nothing else, over
  black, so that is scaling the pixels it wrote, in place, with no buffer,
  and a hole (the working mark's open half, a mini's eyes) stays one. The
  preview's lane fades who needs you with the alert's card.
- **The face never fades.** Through a cross-fade between differently
  shaped arts (calm to happy, happy to sad, calm to frightened's welling
  eyes, falling asleep and waking), the port's painter's frames, 40 ms
  apart, keep at least 85% of the visible ink of the fainter of the two
  faces settled: the pixels the face takes at least a quarter of the way
  from the body's luminance to the ink's, eyes and mouth (a water eye's
  fill, the cheeks and the tears are paler than the body and don't count).
  The least is 87%, falling asleep (waking 88%, happy to sad 97%; calm to
  happy and to frightened show more than the fainter end, both arts
  showing). Where two shapes don't overlap, the frames half way are dimmer
  by a stricter count: of the pixels taken at least half way to the ink,
  calm to frightened keeps 48% of the fainter face's, scared to frightened
  50% and falling asleep, over its longer window, 76%; of those three
  quarters of the way, 13%, 12% and 31%. Each shape is at about half its
  strength there, which is the cross-fade.
- **The body never teleports.** Each V1 body mode's position and velocity
  in a frame equal its own spring's integration from the frame before (an
  admitted impulse changes only velocity, at its event).

The scene check also replays [scripts/alert-interrupted.jsonl](scripts/alert-interrupted.jsonl)
and interrupts alerts with listening and with a link timeout at eight points
from 0 to 2,000 ms: every request knocks and confirms exactly once. The
native port's `test_gel` repeats the interruption cases, the weights' and
sizes' bounds and the alert's ramp over every directed edge, a fifth art's
drop, sleep's spring kept through a mood change, and the lane's fade (the
same whatever the draw cadence, the strip blended once), and checks that
the face never fades.

## Variability, without chaos

Use a deterministic seed for replay/tests and a per-actor seeded PRNG in
normal runs. First pick an authored variation compatible with state/mood
and host outcome/context, excluding the most recently used. Then choose
bounded microparameters: a small gaze offset, pause length, number of
typing contacts or side of a lean. Make variability visible in action
rhythm, not only random tint/volume. Clamp inputs; an LLM cannot add a
limb, change physics, execute JS or invent a successful result.

The audition has authored recipe cues and quiet auto intervals. The full
activity matrix uses the shuffle bags described above, preserving
recovery-boundary changes and no immediate repeats.
Ten minutes of work can vary silently without ten minutes of sound.
Whole-state completion and alerts are event-gated one-shots, not periodic
random surprises. No per-frame LLM/API call is required.

## Alerts, taps and interruption

Use the repo's existing LinkKit turn/attention semantics, not an invented
priority scheduler that delays needs_you. A new request starts the upper
alert once, with broad surface knocks followed by the visible confirmation;
then its card holds silently. An alert that listening or a link timeout
interrupts before its confirmation resumes where it stopped, so no request
loses its knocks or ding. Synchronized sound will attach the invariant
ding to that reveal; it is not played by the current scene engine. Mood may
change expression/knock character but must not restart an already-consumed
notification sound once that layer is added. Preserve the
bottom text lane and do not obscure the prompt with long acting.

Poke can add an impulse immediately while the engine retains factual
state. If the current alert/finish tap opens a thread, honor that existing
behavior; it still never grants permission. Surface drag is a separate
interaction. A poke preserves the mood. The explicit face selector is only a review
control, outside production graph logic.

A production desktop container must terminate grabs on pointerup,
pointercancel, lost capture, visibility/focus loss and host boundary exit.
The embedded-preview guards cannot guarantee delivery of events outside
a browser iframe. The standalone preview removes that embedding boundary,
but OS/window-boundary and hardware-touch behavior still need testing.

## Proposed renderer adapter, not a new wire schema

Keep the existing primary controls. A future desktop adapter can translate
Boop's validated snapshots/moments to target mood/state, plus factual
outcome/context, then advance locally each frame. State and motion data
never need to be generated by Jev. Queued one-shots must retain request
identity and lifecycle so played/cut/skipped is logged correctly.

Before integrating, implement and test this adapter in Boop-specific code;
do not place slime or mood logic in the generic agent-hooks/MellowHarness/
LinkKit packages. No adapter is provided by the audition API. The preview's
`setEmotion`, `poke`, `shake`, `perform` and `getState` are local tools for
review; they are not permission to send unsupported 42-mood wire IDs.

## Desktop first; the selected embedded renderer still needs measurement

Disk size is not device runtime cost. The WebGL mesh, scratch RGBA face
texture, full scene targets and bloom require capabilities/memory the
original ESP32 does not have. The owner has selected one face per board at
build time: the CYD keeps its pixel bank; the AMOLED uses the integer gel renderer behind the common face interface. There
is no runtime character switcher and no frame streaming over the link.
The bundled Mac mirror now uses this engine; firmware uses the separately tested integer port. Facegen does not convert
the gel shader. `clearTransient()` drops
elapsed one-shots/listening when the popover hides without resetting any
body spring. The host restores its current listening hold when it reopens.

The original handoff called for hardware review before the full port. The
owner subsequently asked to continue through the rendered buddy without routine
stops; engineering continued without inferring physical approval. The native
port passes every saved reference trace at its tolerance. The owner then authorized flashing. The first full-panel run missed the
provisional frame-rate target, so the renderer briefly used the handoff's
lower internal-resolution fallback; it has since returned to native panel
pixels with a smaller mesh and tracked clearing.
Appearance, speaker quality and physical audio latency remain separate reviews.
