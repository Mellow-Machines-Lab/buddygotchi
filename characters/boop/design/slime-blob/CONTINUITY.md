# Continuous actor and animation authoring

Updated 2026-10-25. The slime's one engine is the C++ in
`characters/boop/firmware/src/render/gel/` (below, `gel/`): the board runs
it, and so do the simulator and the Mac's mirror of the board, the
firmware built to WebAssembly (characters/CHARACTER.md §9). Every activity
scene family is implemented; idle, sleep and a finish have their comedy
(Comedy, below), the board's gestures have a take each (Gestures), the
looks have occasions (Occasions), and one face flows into the next
(Directed edge bridges: its arts morph or cross-fade, never closing). Q1
representative art review was approved on 2026-10-02. Each rule below
names the code that keeps it; [VALIDATION.md](VALIDATION.md) names the
test that pins it. Contact-synchronized sound is implemented; timbres
remain sketches.

## Keep the object; change its targets

The board draws the dome from a mesh slimegen samples once (`mesh.mjs`,
into `slime_mesh.h`): its vertices and a dense lookup of the blue
translucent gel's studio lighting, rim and bloom. Every frame
`gel/painter.cpp` deforms and projects the mesh by the body's pose and
rasterizes it, and `gel/art.cpp` draws the face's art (slimegen's
`painter.mjs`, baked as vector paths into `slime_art.h`) on the body, moved
and sized by the face's controls. There is no inner jellyfish cap or model
asset. The face rides the body: it never slides on its own during a grab
or a deformation.

| Area | What it does | How to extend |
| --- | --- | --- |
| `expressions.json`, slimegen's `painter.mjs`, `face.mjs` | Face designs and the controls they're drawn at | Edit the catalogue and a matching painter primitive; run slimegen |
| `gel/motion.cpp` `Motion` | The accepted V1 springs, blink, breath and gaze | A change is a named motion revision: edit `test_the_motion_v1_numbers` with it |
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
others cross-fading (Directed edge bridges, below), so the face never
closes or fades. The mood posture reads its own critically damped weights.

## One engine, driven as the board drives it

`gel/engine.h`'s `Engine(seed)` takes `setFacts` (a complete host
snapshot: an omitted attention clears it), `setMood`, `oneShot`,
`linkTimedOut`, `clearTransient`, `holdExpression`, `setOccasion`,
`dragStart`, `dragMove` and `dragEnd` (with the finger's velocity as it let
go, if it was moving), and `step(ms)`, the only call that advances its
clock; every other call keeps every spring's displacement and velocity. It
has no wall clock and no global random source: its `Random`s are its own,
seeded (53 after a reset, so a reset board replays the same). The explicit
timeout is the board's input; elapsed time alone never invents `no_app`.

The board's `GelFace` (`gel/face.cpp`) turns what Behaviour follows into
these calls, and steps the engine on a 16 ms grid from its last reset: a
frame advances at most 45 ms, and a repeated time doesn't advance it. The
board times every moment itself: it sends each one held (below), and
clears it when it ends.

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

The additive gesture springs (`gel/acting.cpp`) are frequency 11 (lift),
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
layers at its ratios (Directed edge bridges, below), so settled faces keep
their authored proportions.

The mood posture (the per-mood squash, and the excited, scared, frightened,
crying and irritated oscillations, `gel/engine.cpp` `posture`) is weighted
by one critically damped spring per expression, ω = 10, whose target is one
for the current expression and zero for the others. The weights sum to one,
so the posture eases between moods with no step in velocity, and it reads
after the quiet blend.

## Representative activity scenes

The first owner review covered working, terminal, needs-you,
task-complete success/failure and the quiet rest alias. Q1 approved that
representative art on 2026-10-02, allowing the rest of the matrix to be
implemented: happy, grumpy, sad and frightened in six cases each (success
and failure separately), 24 cases in 20 mood/state cells, the Studio's
**Representative activities** review set
(`characters/boop/studio/review-sets.json`). Sleeping is a justified
shared alias, not three newly authored sleep animations; its one addition
is a snore (Comedy, below).

Priority is explicit no-app, listening, needs-you, the admitted moment,
then the latest base/activity (`gel/router.cpp`). An activity applies only
to working; unknown activity falls back to working and unknown base to
idle. Attention identity follows the device: a new activation or changed
id, agent or project; changing mood, display name or more leaves the
request's reveal consumed. Attention cuts future decorative contacts
immediately. Clearing and showing the same request id again creates a new
activation. Leaving an alert for a higher-priority state (listening, an
explicit link timeout) saves how far it got: its age and its next contact.
Returning to one that had already confirmed restores its silent hold;
returning to one that had not resumes at that age, so only the knocks and
confirmation not yet reached follow. Each request's knocks and ding play
exactly once, never twice and never not at all. Returning from a moment
resolves the latest snapshot. Only an explicit successful outcome permits a
trophy; failure, missing outcome and unknown outcome never do.

A moment (`oneShot`) mirrors visual lifecycle, not LinkKit's queue, TTL,
acknowledgments or audio playback. The board times its own moments, so it
sends them `hold`: the moment never expires or finishes on its own and
rests after its loops until `clearTransient()`; its `variant` names the
take the board has already timed, and `holdExpression` holds its borrowed
expression with no expiry. Unknown names are refused. Repeated moment
id/name pairs do not replay. `loops` uses the protocol's range, 1 to 6,
defaults to one, and repeats the same selected recipe; only a new request
chooses the next variation. A react with a known mood overlays the active
animation without changing its outcome, request identity or lasting mood;
a bare react has nothing to play, and a speech-only request adds no visual
animation. A non-null `say` ends listening before visual admission.
Repeated `listening` keeps its lifetime; `stop_listening` ends only
listening.

Every one-shot has a finite authored recipe, then returns to current
facts. Listening has its own recipe and waits for an explicit stop or
reply: the engine has no microphone deadline of its own. Explicit no-app
masks current activity and suppresses contacts; presentation time
continues, so elapsed moments are not replayed when the link returns.

One desk persists across work modes. Three shuffle-bag recipes per
mood/state/factual outcome or context differ in rhythm, with no adjacent
repeats; asleep and a successful finish have a fourth (Comedy, below).
Routine work changes variation after recovery; alert/result requests choose
once at entry. Mood retargeting does not restart an existing recipe or
alert. The expression's gesture recipes play only in idle without a grab;
the activity scene owns the choreography elsewhere. A state change cancels
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
follow the controls below their saturation that far (Directed edge
bridges, Drawn ratios). Waking stays quick: the face's own 180 ms and
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
sides as far as the corners reach on its marks' rows, and the bubble
stands off the panel's foot and in from the curve, its own corners cut
away like the panel's, which holds the longest take in the sign's font.

Every other prop (the alert, result and start cards, the helpers, the
listening cue and the touch marks) has a **200 ms visibility ramp** for
entry and exit (`gel/scenes.h` `Ramp`): a cubic Hermite from its current
value and slope to the target, so from rest it is a smoothstep and a
reversal keeps its velocity; it ends exactly. Held within zero and one,
it's flat where it's held, so a retarget never brings back what it held at
zero. Each prop's visibility is its drawn opacity: the ramp, times a
card's reveal or the helpers' recovery. When its route ends, a prop fades
out still carrying the content it last showed (the alert's request, agent,
project, name and count; a card's state, label and outcome; the helpers'
mode, count and progress; the listening pulse; the touch kind). New content
(another request, or the helpers' next cycle) waits until nothing of the
old is drawn, then fades in from zero; the alert's content follows the
current request at once. Contact envelopes (the knock, the key and touch
pulses) stay deliberate impacts.

The authored keyboard contact times, in milliseconds before jitter, are
slimegen's `scenes.mjs`:

| Rhythm | Variant 0 | Variant 1 | Variant 2 |
| --- | --- | --- | --- |
| Working | 580, 780, 1040 | 560, 760, 1680, 1880 | 1100, 2220 |
| Terminal | 600, 780, 960 | 780, 1810, 2090 | 580, 740, 900, 1060, 1960, 2120 |
| Frightened working/terminal | 800, 1700, 2040 | 740, 1800, 2240, 2480 | 1080, 2380 |
| Grumpy terminal | 640, 800, 960 | 800, 960, 1120, 2100 | 660, 820, 980, 1140, 2120 |

Sad work keeps every other contact of its ordinary rhythm, starting with
the first, for longer pauses. Keyboard strength/lean are 1.05/0.018 for
happy, 1.12/0.032 for grumpy terminal, 0.62/−0.016 for sad and 0.68/−0.018
for frightened; other work uses 1/0.018. Contact side alternates. The body
uses the contact envelope and strength for side lean 0.024, squash −0.052
and forward 0.045. A successful reveal targets squash/forward 0.036/0.025;
a failed reveal −0.048/−0.035, before the activity bounds.

Alert entry has one, two or three knocks at [420], [420, 740] or
[420, 690, 960] ms. Result reveal is at [680, 960, 1240] ms. The alert and
result recipes shape those times and forces by the mood:

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
clears. Its reveal strength is invariant at 1. A result receives the mood's
delay and strength while its success or failure remains factual. A card's
reveal is its own, a second ramp of its prop's: up over 400 ms from its
reveal contact (`kCardRevealMs`, twice the prop ramp, so it rises in rather
than appears) and down over the recovery's 480 ms, each from its time on
the route's clock, but not down before it's up: one revealed in the
recovery rises whole, then falls; it is cleared before an explicitly
repeated loop. A route that ends while its card rises or falls leaves the
reveal going as it was while the card's ramp fades it out, so it never
stops dead. Contacts carry unique request, generation, iteration and index
identity; the sound cues take each once (sound/README.md).

Suggested composition order: base shape → mood posture → activity pose →
gesture impulses → local grab → final bounds. There must be one owner of
each channel: a drag owns the grabbed patch, activity owns keyboard
contact, mood owns face style, and attention owns priority. Blend
additive offsets; cap the combined result, not each layer in isolation.
Make suppression explicit so angry+typing+drag cannot exceed the body's
safe envelope or produce competing repeated impacts.

## Full activity scene matrix

The engine implements all 25 factual states in the nine scene families of
[STATES.md](STATES.md): 42 canonical moods × 25 states, 1,050 cells,
including 84 quiet aliases for asleep/no-app, starting in each of its four
contexts and task-complete with success and failure. Every active cell has
all its takes: three, a successful finish's four, a gesture's ten (each
asked for, as the board does), and idle's (an expression's three gestures
and its comedy, six or seven); quiet aliases keep the mood and use the
shared sleeping face without acting, and without contacts but a snore's
breaths. The two face alternates are outside this canonical matrix.

The scene selects a shuffle bag keyed by mood, state and factual
outcome/context. Desk modes, delegating and listening select again only
after recovery. A one-shot selects once per request and keeps that recipe
across explicit loops; an attention entry selects once and then holds.
Idle uses its expression's three gesture recipes, then its comedy, with a
separate automatic shuffle bag per expression and the quiet interval
above. A bag's first round deals its first three entries; every later round
deals all of them (Comedy, below). Each round is exhausted before the next
and no entry repeats across a refill. Changing targets never replaces the
body or its springs.

For the other canonical moods, slimegen's `scenes.mjs` derives bounded
traits from the expression's authored performances. Let `D` be their mean
duration in seconds, `E` the mean absolute cue velocity, and `L` the sum
of signed lean/forward cue velocities divided by the total cue count.
Empty cue lists use a denominator of one. The traits are:

| Trait | Formula and bound |
| --- | --- |
| Delay, milliseconds | `clamp((D − 3) × 120, −160, 160)` |
| Contact spacing | `clamp(D / 3.2, 0.88, 1.18)` |
| Contact strength | `clamp(0.6 + E × 0.32, 0.68, 1.12)` |
| Lean | `clamp(L × 0.045, −0.022, 0.022)` |

The four reviewed moods keep the explicit table above. Their
working/terminal rhythms stay as they are. For other desk moods, the first
contact receives the delay and later offsets from that first contact
receive the spacing multiplier; lean adds the trait to the ordinary desk
target. Crying+working has an authored exception: contact times [760,
1780], [640, 2120] or [1020, 2300] ms, strength 0.55 and lean −0.024. All
keyboard contacts then receive the bounded jitter.

Outside the four reviewed moods, the selected expression performance also
contributes a bounded recovery gesture (`gel/scenes.cpp`). Recovery
progress maps the entire authored performance duration into the scene's
recovery window. Each cue contributes `velocity × gain × sin²(π × cueAge /
0.48)` only while its authored age is between zero and 0.48 seconds. Roll
maps to lean, lift to squash, and ripple to forward; the corresponding
gains are 0.025, 0.018 and 0.015. Lean, squash and forward cues keep their
channel. The result passes through the activity spring and final bounds
above. A grab or quiet state suppresses these contributions.

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
sad desk modes keep every other ordinary contact, beginning with the
first. Waiting overrides contacts to an empty list and uses lean targets
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
| Starting | Reveal at [520, 820, 1080] ms by variant | `new_task` → NEW TASK, `session` → START, `continuation` → RESUME, `compacted` → COMPACTED; missing context stays neutral START |
| Wake up | Stretch [560], [760], [900, 1500] ms, then settle [1180], [1240, 1420], none | You back after a long break: the start family's body, with no card. The stretch is a start reveal (the second of variant 2 at 0.7 strength); a settle is a body contact of strength 0.35, sides 0, then ±1 |
| Delegating | [660, 1040], [540, 880, 1220], [820, 1640] ms | Dispatch [2, 3, 2] small helpers beside the same hero |
| Helper return | Reveal at [680, 960, 1240] ms | One returning helper and a neutral report; no assumed success |
| Reply ready/error/stopped | Reveal at [680, 960, 1240] ms | READY / TOOL ERROR / STOPPED, without a trophy |
| Poked | [160], [200, 480], [160, 520] ms | Bounded local dent/wobble/bounce |
| Tap spam | [160, 400], [160, 340, 520], [220, 620] ms | Bounded wobble/squash/dodge complaint |

Start, wake-up, helper and status-result contacts receive the mood/profile
delay; their reveals take its strength. Helper contact sides alternate;
variant 2 reverses travel direction. Their travel progress is smoothstep
of age divided by the last contact time, clamped to [0, 1], so arrival
coincides with the factual report reveal. Helper visibility multiplies the
entry and recovery envelopes. Touch contacts have strength 0.6 for poked
and 0.9 for tap spam, alternating sides and lean targets [0.008, −0.018,
0.012]; they have no timing jitter or mood-derived delay. Their mood face
stays the current expression, with the bounded recovery profile where it
applies. An admitted `poked` moment also applies the V1 poke and an
admitted `tap_spam` its shake: they can change velocity, but never reset
displacement or layer state. Duplicate or refused requests apply no
impulse.

The start/helper/status reveal envelope adds squash 0.018 and forward
0.018; a tool-error reveal instead adds forward −0.025. All factual cards
reveal while dragging; body contacts are consumed silently during the
grab. Return and stop stay neutral, error means a tool warning, and only
explicit task success permits the trophy. Every result card has a mark
over its label: the trophy, a cross for a failure or a tool error, a soft
stop square when stopped, and three calm dots for the other neutral
results (READY, FINISHED). A state change cancels pending contacts at once
and resolves the latest facts.

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
expression's performances, so its comedy is more of them, dealt by
acting's bag (`gel/acting.cpp`): an expression's three gestures, its own
`gags` (expressions.json), then everyone's `idleGags`. A gag is in `gags`
once, shared. It is a performance (its `cues`, impulses on the gesture
springs) with `keys`, which set a channel's target (from (0, 0) at its
start, a smoothstep to each of the channel's keys in turn, then its last
value), and `contacts`, which sound and move nothing. Every channel's keys
lie inside its bound and come back to rest. The six gesture springs follow
their keys under-damped, as gel does; a gag has two springs of its own,
its `slide` (frequency 10, damping 9, at most 0.7) and its `lids`
(critically damped, frequency 24). The lids close the eyes as a blink
does: the drawn blink is the larger of the natural one and the lids'. The
slide carries the whole dome sideways, its face and its shadow with it,
and leaves its shape as it is.

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
take: the result card's content carries it, and the board draws an amber
bug beside the card.

**Comedy's contacts sound in any state**, each with the routine chance (a
quarter): a sneeze's (`sneeze`), a zoomies landing (`bounce`), a snore's
breath (`breath`). They are routine sounds, ducked under a line, and
sparse: over twenty minutes of idle only sneezes sound, over five minutes
of sleep only breaths, each fewer than half of its contacts.

## Gestures

`gesture` is the board's own reaction to what you do to it, a one-shot
in the touch family. Its takes are the board's gestures, in its order
(`render::Gesture`, slimegen's `scenes.mjs` `gestureNames`): the board
names one (its variant, 0 to 9), no bag deals them, and a gesture asked
for without one plays the first. Each is the same in every mood: a scene
recipe whose body contacts dent the dome, pulse the touch mark and sound a
squish on its first loop, and a gag of its own (`expressions.json`
`gestures`, keyed as Comedy's are) that acting plays with it. The board
borrows a face for each while it plays, as a react's expression is
borrowed, and the mood stays.

| Gesture | What the body does | Face it borrows | Gag |
| --- | --- | --- | --- |
| handoff (BOOT hands you an agent) | Lifts and leans in, offering | pleased | 2.4 s |
| stroke (a slow one; a quick swipe is none: A finger on the body) | Melts under the hand, eyes shut | affectionate | 3 s |
| ruffle (stroked slowly the wrong way, upward) | Bristles in ripples, then huffs | annoyed | 2.2 s |
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
expression's recovery gesture.

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
face's alone, with no tap or gesture and nothing to the Mac; slower, a
stroke (upward, a ruffle), and the gesture above plays as it lets go. The
finger's velocity as it lets go is over its last 80 ms. The board's
`tests/scenarios-gel/swipes.jsonl` and
`internal/tools/fluid/idle-swipes.jsonl` swipe on the board itself.

A finger that starts on the strip is no finger on the body: going up, it
pulls out the agents' drawer (`render/gel/drawer.h`), and the body is
pressed under its edge. Shut, it stands at rest; as the sheet rises its
edge pushes the body up until it meets the glass, then flattens it, its
rest rows mapped onto those left above the edge, spread a little wider
(`Projector::project`, the painter's `squeezeTop` and `squeezeBottom`),
its pose and springs carrying on inside them. Past six tenths flat it
squeezes its eyes shut: the art, layers and props wait and the drawer
draws its own face (`> <`, pink cheeks, a wobbly mouth), and once it has
sprung open a paw drops over the sheet's edge. Shut again, it stands
back up as it was. `tests/scenarios-gel/drawer.jsonl` pulls it.

## Notice

The brain's reaction when you name it in your prompt: it heard its name and
looks up at you. It plays the pack's rig clip for it,
`characters/boop/rig/clips/notice.json`, from the notice-perk reference
(CHARACTER.md §16): its eyes snap open wide and up and it perks up tall,
winds up, hops off the ground with its eyes squeezed happy, lands flat with
a squish and wobbles, looking at you. The face plays the clip on its
mixer as the moment starts, the painter lays its channels over the
engine's pose (CHARACTER.md §15, The gel on the rig), and its cues sound
a body contact at the take-off and the landing through the engine's
contacts. Its scene is the start
family's with no card, timed to the clip and a little more, with no gag or
contact of its own. Its three takes, `notices` in `expressions.json`, are
the one clip under a face each, dealt from its bag as any state's takes
are: `notice-surprised`, `notice-happy` and `notice-pleased`. The board
borrows the take's face (`kNoticeFaces`) unless the Mac sends a mood with
it.

## Occasions

A look may have takes that need tags (`when`, every one on: the board's
`render/tags.h`, the part of the day, the holidays, `party`, `busy` and
`frantic`) or a wait (`after`, seconds the look has shown), as Pixel's
designs do (characters/CHARACTER.md §9). The board says them with
`setOccasion(when, lookMs)` on every sync. While one fits, a pick goes to
one of those that fit 67% of the time (`kOccasionShare`), any one alike;
otherwise, and while none fits, the look deals as it always has, drawing no
randomness of its own. `expressions.json` `occasions` holds them:

| Look | Occasion | Needs | What plays |
| --- | --- | --- | --- |
| idle | morning-stretch | morning | A big stretch up, eyes squeezed, a lean each way |
| idle | night-drowse | night | Heavy lids, sunk a little, a slow sway |
| idle | nod-off | tier5 | Nods three times deeper, lids closing, then jerks awake |
| idle | party-bounce (and New Year's, Lunar New Year's, Programmers' Day's) | party (newyear, lunar, programmers) | Three hops side to side, eyes squinting; each landing a bounce at comedy's chance |
| idle | friday-sway | friday | A little dance, leaning and sliding |
| idle | winter-shiver | winter | Huddled down, shivering |
| idle | halloween-wobble | halloween | A slow spooky roll and drift, lids half shut |
| idle | valentines-swoon | valentines | Eyes shut, lifted, a lean |
| working, terminal, tool_use | busy-typing | busy | Two quick three-key bursts, leaning in |
| working, terminal, tool_use | frantic-typing | frantic | Six keys in 0.6 s, leaning in harder |
| asleep | deep-snore | night | Three deeper breaths |
| asleep | dream | 1,800 s asleep | Two soft breaths and a twitch-and-wriggle gag |

Idle's are gags acting plays in place of its next gesture (numbered after
the expression's takes); the other looks' are recipes the scene deals at
a pick (numbered after the row's takes), the same in every mood, and a
jittered one takes the desk's jitter. A gesture or a host's moment never
takes one. The pack's rig has occasions of its own, clips both of its
faces play ([CHARACTER.md](../../../CHARACTER.md) §15, The gel on the
rig): working's stretch from `tier4` (eyes squeezed, up tall, a lean
each way) is the rig's `stretch`, over whatever desk take plays, dealt
with the pastimes (below). An occasion whose tags go off simply isn't
picked again. The
engine has no colour channel, so no occasion tints the gel. The working
looks' quicker pace while the agents are busy is the board's
(`render::workPace`), not an occasion.

### Pastimes (the board's)

Something new at every glance, however long the agents work or you're
away (`render/gel/pastimes.h`): a pastime is a clip of the pack's rig
(`rig/clips/`, the body: a sip, a hop, a lean to look, the eyes
following something round) and what the board draws with it, in time
with it, and the kit the tiers put out stays while they last. The tiers
are the Mac's (`tier1` from 30 seconds, `tier2` from a minute, `tier3`
from 2, `tier4` from 5, `tier5` from 10): of the agents' working stretch
at work, of their rest idle. The face (`GelFace`) deals one at a time,
while the engine shows the look itself and nothing holds the body (a
finger, a word of the work stream in flight), after a rest of 4 to 10 s,
the newest tier's 60% of the time and an older one's the rest, never the
same twice running, with the rig look's occasions among them; and holds
the engine's own idle gestures off while one plays. The one playing
fades out when the look gives way.

| Look | From | Kit | Pastimes |
| --- | --- | --- | --- |
| working | tier1 | A mug on the desk, steaming (not in the morning, when its coffee is in its hand, nor a sip or a refill) | A sip, eyes shut, "ahh"; a peek up at you and a heart; humming, notes floating up |
| working | tier2 | | Wondering, a "?" cloud, then a lightbulb and a hop; the tip of its tongue out, concentrating; nodding along as ticks pop from the monitor |
| working | tier3 | Headphones | Bopping to the music, eyes shut; drumming on the desk; a sticky note slapped on the monitor |
| working | tier4 | A sweatband, a drop of sweat now and then | The rig's stretch; a coffee pot pouring a refill; a cookie in three bites; a second wind, sparkling |
| working | tier5 | A camp beside the desk, a tent and its fire; a mug more on the stack every 10 minutes, up to 4 | A marshmallow toasted on the fire; a pizza; the stars and a shooting star; a plaid blanket over its head |
| idle | tier1 | | Looking round; looking up at you, "...?"; three hops |
| idle | tier2 | | A bubble blown and popped; a fly it follows round and snaps at; a heart drawn on the glass |
| idle | tier3 | A plant that grows, a sprout | A book, its page turning; a handheld game, WIN; watering the plant |
| idle | tier4 | The plant in leaf | A "brb" sign, peeking over it; a tower of blocks that topples; a dance under a disco ball; a paper plane that bonks its head |
| idle | tier5 | The plant in flower | Snoozing, a snore bubble; counting sheep; a nap under the blanket; and the engine's nod-off |
| needs you | 30 s, 2, 5, 10 minutes | | A wave; tapping on the glass; checking its watch and sighing; nodding off and jerking awake |
| asleep | 1, 2, 4 minutes | | Rolling over, mumbling; counting sheep; a snore bubble |

The hat wins the head: the headphones and the sweatband stay off while
it wears one, and peekaboo's gesture takes them off as it does the hat.
The camp, the plant and the stars go behind the body; what it holds,
throws, blows and dreams goes in front, at the body's anchors, and the
headphones and sweatband over what it wears, before the cards. No sounds
of their own but a few landings (`body_contact`), and none while
something needs you or asleep.

### Layers over the body (the board's)

The engine draws no costume, but the board draws layers over the body by
the same tags, after the face art and before the props
(`gel/layers.h`): a hat by the first tag that has one (Halloween's witch
hat; a party hat for party, New Year's, Lunar New Year and Programmers'
Day; a striped nightcap at night, flopping down its left side to a
tassel by its cheek, with pyjamas to match but while it wears reading
glasses; a bobble hat in winter), shades on a Friday's day, and the air
(snow, confetti, hearts, Zs asleep at night), and last the sign a
reaction holds up. In the morning, while it's idle or at work, it
holds a mug of coffee at its side in a little gel hand, steam curling up
off it, and now and then lifts it to its mouth for a sip
(`OutfitLayer::kSipMs`). At night a
crescent moon and twinkling stars sit behind everything, and in the
morning the sun coming up over the lane on its left, drawn last of all
onto only the background's black, so the body, its outfit, the stream's
words and the sign stay in front. Each sits on anchors the painter takes from
the very vertices it projects for the body (the rig's `Anchors`, both
faces' one type: the dome's apex, ring 6's sides and front for a brim,
ring 15's front for the hands) and the face art's eye centres, so a layer
leans, squashes, dips under a finger and slides off the screen with the
body and is cut off there with it. Peekaboo's gesture hides the hat. At
night the lids hang a little lower (`kNightLids`) on the awake face,
easing out as it squashes shut, gone by when it's a line, and back as it
wakes. Each part comes and goes through the rig's layer stack
([CHARACTER.md](../../../CHARACTER.md) §15, The layer stack), which the
face keeps: the sky, what's worn over the eyes or on the body, the hat,
the air and what's beside it (the Zs, the coffee) each fade in and out over 200 ms, a new one only once the old
has gone (a winter evening's bobble fades out at night, then the
nightcap in, while the sky and the pyjamas fade in at once), each on its own, so falling
asleep on a winter night brings the Zs while the nightcap, the pyjamas
and the snow stay. The
sign fades out over 200 ms once it's down, at the opacity Behaviour
gives it. The layers read the engine and never change it.

### The work stream (the board's)

While the agents work and nothing needs you, the board draws the Mac's
work stream (`render/stream.h`, `gel/stream.h`; plan/work-stream.md).
Behind the body: each working lane's words falling from the top edge in
its colour (teal, amber, lilac, lime by slot), with no name: the colours
tell the agents apart, and the screen has no room to say whose is whose.
Lanes sit clear of the head and its hat (`render::laneX`: one lane on the
left, two either side, three or four along both sides). A word falls, in
the large font at most 43% opaque, for each new call a `state` counts
(at most two a `state`, eight at once), easing in over 200 ms and out
over its last 600 ms of 3.2 s. They're drawn after the body, onto the
background's black only, so the body, its props and what it wears cover
them, and a word hidden behind it costs nothing to draw, clear or push.
On the desk, while the Mac sends lanes: the to-do list's progress along
the monitor's foot, the turn's clock in its corner from the first
minute (amber from `tier4`), and, in the working look with no
call for 20 s, a thought cloud. When the agents stop, the words on
screen linger 1.5 s (`Stream::kEndMs`), falling where they dropped, and a
word may still come forward in that time, as a turn's end does to gather
them; something needing you clears everything at once.

In front, after the props and before the sign: the word a `call` brings
forward flies from its lane's name (a paper plane or a little one from
the right-hand edge) and does what its move does (`render::CallMove`),
everything gone by 2.5 s:

| Move | Gags | What plays |
| --- | --- | --- |
| Sink, arrive | land, arrive | Onto the crown, sinking in under a spreading ring; a turn's first twinkles; an edit's lines grow as green and red bars on the monitor |
| Look | look | Beside the head, a magnifier sweeping it; the monitor's page scrolls |
| Stir | stir | Into a pot at the desk's right end, bubbling and steaming |
| Stamp | stamp | Onto a card beside it, and a stamp comes down: OK |
| Rocket | launch | Onto the crown, then up and away on a rocket; the monitor counts 3, 2, 1, LIFTOFF |
| Poof | poof | Beside it, gone in a puff |
| Plane | plane | A paper plane swooping in from the edge, caught at its hands; a globe turns on the monitor |
| Phone | phone | An old phone ringing beside it, the word its call |
| Page | page | A page beside it, its corner turning |
| Helper, back | helper, back | A little one carries it off to the right, or brings `done` back, twinkling |
| Hit | bonk, bonk2, helmet, throw, no, timeout | Between the eyes: it sticks, slides off (thrown back on the top rung) under three stars, five up the ladder, a helmet on the third; dizzy spiral eyes over its own (the body's colour under them), 1 to 1.3 s; the monitor cracks up the ladder |
| Shrug | shrug | Beside the head, an empty bubble over it |
| Shatter | shatter | Bursting into its glyphs, swallowed, and a burp |
| Hail | hail | More FAILs raining and bouncing off; an umbrella opens 0.4 s too late; a cross on the monitor |
| Cheer, combo | pass, built, combo | Over its head with confetti, a tick on the monitor; built raises a flag on the tower; a combo's count twinkles |
| Desk | cross, stack | The monitor's spinner; a build's bricks stacking up at the desk's right end |
| Topple | topple | The tower wobbles a second and falls on its head: dizzy eyes, a cross on the monitor |
| Gather | gather | A turn done: its lane's words, from where they were, gathered into its mouth, and "mm!" |
| Compact | compact | Its context compacted: the words squashed together over its head into a cube that thuds onto the desk |
| Drop | drop | Stopped, or failed: the words fall away grey, switched off |
| Freeze | freeze | A rate limit or an overload: the words falling held where they are, icy, a snowflake turning, and it leans in to poke one; they fall on after |
| Buried | buried | Its context full: bricks of its words piling up to its eyes |

As it lands the body answers through the engine (`Engine::jolt`): a push
on the finger's pull springs, as a fling let go (knocked back and
squashed by a hit or the tower, squashed by a word sinking in or a
stamp, leaning to look, read, phone or catch, stretched up by a shrug, a
rocket or a cheer), your no's flinch with its lids squeezed (0.6 for
450 ms) and a timeout's nod (0.9 for 700 ms), opening over their last
300 ms; nothing while a finger holds it. The stream moves on the device's
clock, not the engine's paced one, so a word falls as fast however busy
the agents. Measured on the AMOLED board (`amoled206_profile`,
2026-10-24): 35 fps with the stream off; 31.8 with one busy agent's
traffic (the stream's drawing 1.5 ms a frame); 28.5 at three lanes'
worst (3.5 ms).

## States share one scene

Build a persistent desk and computer once. Working, terminal, searching,
analyzing, testing, planning and generic tool use are activity submodes,
not swaps to unrelated sets. Keep desk positions and parent transforms
stable, change screen cue/cards and contact choreography. Waiting simply
pauses the work action. Helper blobs enter alongside the hero, never
replace it. Every state ([STATES.md](STATES.md)) still has its own
meaning, variations and audio policy.

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

The engine's `Bridge` (`gel/acting.cpp`) plays each of the graph's 295
directed edges (slimegen's `kEdges`, from emotion-graph.json) in three
variants. A shuffle bag per directed edge selects variants without an
adjacent repeat. This is an animation catalogue, not host graph gating: the
host still decides whether a transition is justified. A retarget outside
the graph uses the soft primitive and does not create a new graph edge.

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
destination profiles. Using their lean `L`, strength `G`, delay `D`, eye
openness `E` and mouth width `M`, the directional score is
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
0.05 / 0.048 ≈ 1.042. The bridge owns three additive springs with
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
window ends, only the current art is left. Natural blinks and a gag's lids
close the eyes; nothing else does.

**Morph or cross-fade, feature by feature, by one rule.** The board
draws each layer's features: each eye, the mouth, the tears, and the
cheeks with the strain mark (`gel/art.cpp`). slimegen gives each art's
features a shape (`slime_art.h`'s `ArtRange::shape`, from their paths'
point counts, fill or stroke and colour); where layers draw a feature in
the same shape, it is drawn once, its points, pen widths and opacities
averaged by weight, at their summed weight: two bean eyes ease into each
other, a closed arc eases into a droop. Different shapes cross-fade, each
at its weight, the newer over the older, so the eyes' and the mouth's
opacity, summed over the arts, stays one: a ring of a mouth gives way to an
open U. The cheeks and tears are drawn at their opacity controls. (While
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
shared sleeping face is the tired art drawn at its own squashed size (eye
0.004, mouth 0.018 × 0.008), so its ratios also settle at one. Pen widths
never stretch with a feature's scale. The board draws a second art only
while one crosses over.

Quiet rest and active attention permanently suppress the current bridge's
body gesture, with its springs settling toward zero. Clearing an alert or
waking does not replay it. The face still retargets, and the attention
request, card and consumed reveal keep their identity. A grab defers the
current body bridge while the face continues: progress may be held for at
most 320 ms of accumulated grab time. Releasing sooner lets the current
bridge continue from its springs; reaching the limit expires its body
gesture permanently. There is only one current bridge, so a newer retarget
replaces deferred work and release never drains a gesture backlog. Bridges
emit no contacts or sound cues.

## Continuity of what is drawn

Every frame `test_gel` drives is held to these (`tests/firmware/test_gel/frames.h`),
over every mood in every state and take, every directed edge in all three
variants, and the interruptions: for each channel the board draws (the
eight face controls, each layer's weight and drawn sizes, the mood
posture's lean and squash, every prop's visibility and a card's reveal
while the card is drawn):

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
  shaped arts (calm to happy, happy to sad, calm to frightened's welling
  eyes, falling asleep's swap and waking), the board's frames, 40 ms apart,
  keep at least 85% of the visible ink of the fainter of the two faces it
  crosses between: the pixels the face takes at least a quarter of the way
  from the body's luminance to the ink's, eyes and mouth (a water eye's
  fill, the cheeks and the tears are paler than the body and don't count).
  Falling asleep, those are the lines it squashed to and the sleeping face:
  the eyes closing is the morph, not a fade. The least is 90%, waking
  (falling asleep's swap 96%, happy to sad 99%; calm to happy and to
  frightened show more than the fainter end, both arts showing). Where two
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
alerts are event-gated one-shots, not periodic random surprises. No
per-frame LLM/API call is required.

## Alerts, taps and interruption

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

The owner selected one face per board at build time: the CYD keeps its
pixel bank; the AMOLED uses the integer gel renderer behind the common
face interface. There is no runtime character switcher and no frame
streaming over the link. The Mac's popover and onboarding show the
board's own firmware built to WebAssembly (characters/CHARACTER.md §9),
which `boopctl mirror` checks draws every gel scenario as the native
simulator does, pixel for pixel. Facegen does not convert the gel.

The first full-panel run on the board missed the provisional frame-rate
target, so the renderer briefly used a lower internal resolution; it has
since returned to native panel pixels with a smaller mesh and tracked
clearing. Appearance, speaker quality and physical audio latency remain
separate reviews.
