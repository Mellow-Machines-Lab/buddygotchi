# Slime validation

Updated 2026-10-25. What checks the gel slime, and which rule each check
holds it to. The slime has one engine, the C++ one
(`characters/boop/firmware/src/render/gel/`), so every rule
[CONTINUITY.md](CONTINUITY.md) states is checked on it, from the
repository root:

```sh
node characters/boop/tools/slimegen/slimegen.mjs --check
make -C internal fw-test
internal/tools/boopctl sim --face gel
make -C internal mirror
```

None of them contacts Jev, a paid API or a device.

## The design's data (slimegen)

`slimegen.mjs` checks the design before it bakes it (`check.mjs`), and
`--check` fails unless every generated file is the one checked in:
`slime.h`, `slime_art.h`, `slime_mesh.h`, the pack's moods in
`character.json` and [MOODS.md](MOODS.md). It fails, naming what's wrong,
when:

- an edge goes to a mood that isn't one, or to itself, or twice, or a mood
  has more than eight; the ordinary edges alone don't reach every mood
  from every other; or an intensity ladder (`intensityLadders`) doesn't
  climb by ordinary edges;
- a canonical mood has no expression of its own or no sound profile, an
  expression hasn't three gestures, a mood or idle names a gag there
  isn't, or a notice take borrows an expression there isn't;
- two occasions share an id, one needs neither a tag nor a wait, plays in
  a state the board hasn't, borrows a gag no occasion has, has neither a
  gag nor a recipe, or gives idle a recipe;
- a sound sketch renders differently from one seed, doesn't start from
  silence, isn't finite, is louder than 0.8, longer than 3 s, or isn't
  silent at no gain;
- the gestures or the notices are out of `render::Gesture`'s order, or an
  occasion needs a tag `render/tags.h` hasn't.

## The engine (`test_gel`)

`make -C internal fw-test` runs the pack's `tests/firmware/test_gel/` on
the Mac (env `native`). Every frame its tests drive is held to the bounds
of what may be drawn (`frames.h`, CONTINUITY.md, Continuity of what is
drawn): every spring and channel inside its bounds, each art's weight and
drawn size, each prop and the desk moving no more in a frame than their
ramps and springs can, and no jolt at an event. By file:

- `test_cells.cpp`: every canonical mood in every state, each of its
  takes, driven as the board drives it (`test_every_cell_plays_truthfully`):
  the mood held, one reveal for each of a request's, the prop it needs
  shown, only a successful finish's trophy and proud's gift, quiet states
  silent but for comedy and still but for a snore, each take moving the
  body its own way; ten minutes at work; contacts a finger or an alert
  interrupts; a card's reveal on its own ramp; asleep's stillness.
- `test_finish.cpp`: a successful finish's size by its loops and its
  turn's tier (the cap short of tier2, the tier4 and tier5 floors, a sad
  one small);
  each mood's two big finishes taking turns, the Mac's choice and a proud
  board's spotlight; the face's pure pick, a finish above small played
  once, its length and its `say`'s start; one cheer and its bounces, never
  the fanfare; the desk put away by a takeover and no card; every finish
  moving smoothly and settling by its end; Gold Rush's flood above the
  lane and Little Win's trophy; only what draws behind the body erasing the
  frame whole first, less the rows the flood covers.
- `test_bridges.cpp`: every directed edge in each of its three variants
  (the retarget changing no spring and nothing drawn, its primitive,
  windows, amplitude and direction, the controls between their ends, every
  sixteenth of its window passed through, the variants moving differently);
  each primitive's waveform and spring; a grab deferring then expiring the
  bridge; a quiet or alerting body holding it; a rapid chain settling on
  its last; each edge's own bag; the semantic face's spring, windows and
  saturation.
- `test_motion.cpp`: the accepted V1 springs, impulses, breath, blink,
  gaze and clock (the motion contract: changing the motion means editing
  this test); a finger's springs, reach and fling; acting's timing and
  springs; every setter keeping every spring, and an engine replaying the
  same from the same seed; the scenes' formulas (the waiting wave, the
  cards' and the error's, the recovery gesture, the desk's jitter, a gag's
  keys inside their bounds).
- `test_requests.cpp`: what routes when (no app, listening, needs you, a
  moment, the look), a request's identity, cues sparse and quiet, a
  request sounding once whatever changes, and sound's randomness changing
  nothing drawn.
- `test_main.cpp`: the rest: arithmetic (a `Divisor`'s quotients exactly
  `/`'s), the binary64 clock's rounding, every expression's bounds,
  deterministic pixels, the body's outline soft with no seam inside, over
  the crown too, and holding still as the mesh turns
  (`test_the_outline_holds_still_as_the_mesh_turns`: leaned or squashed
  end to end, no row's edge jumps a pixel and a quarter), the material
  (1025 × 513 texels) drawing the same body from the AMOLED's copy
  (`test_the_materials_copy_draws_the_same_body`), request identity and bounded caches, alerts
  interrupted by listening or a link timeout at eight points signalling
  exactly once, the face's arts crossing over without jumps and never
  fading (its visible ink through five cross-fades), falling asleep as a
  morph (the awake face squashing shut on its slow spring, to lines, the
  sleeping face crossing in once it's 0.9 shut, waking quick, sleep's
  spring kept through a mood change), the night's lids, a finger moving the dome its own
  way, every result card's mark and none for a finish that names whose
  turn it was (`test_a_named_finish_shows_no_card`), a finished turn's
  glow and ticket (`test_a_finished_turn_glows_and_hangs_a_ticket`: the
  glow's timing, strength and reach, nothing past the panel's corners,
  the ticket above the top as it comes, in the middle or left of a
  success's trophy, and gone back up), comedy, the ten gestures, the notice
  playing the rig's clip (`test_a_notice_plays_its_rig_clip`: perking up
  tall, off the ground and landing flat, its eyes and mouth, a sound at
  each cue, no gag), a reply's clip (`test_a_reply_plays_its_clip_once`:
  every reply has one, 1 to 1.8 s, its name fits the board's buffer, a
  shake of the head leans the body, once for each reply, nothing for a
  reply with no clip, from a `ReactionIn` too), a nap or a dance asked
  for (`test_a_nap_or_a_dance_plays_its_pastime_when_idle`: idle with no
  tier the snuggle plays at once, its length, and nothing after; at
  `tier5` the rest follows it and the next dealt isn't another; asleep,
  after listening, the dance; at work the yawn and the sway and no
  pastime; notme's eyes off to one side), the
  occasions, a clip of the rig's on both faces (the stretch from `tier4`,
  over the gel's pose and on Pixel's rig face, faded out by a reaction),
  the pastimes (`test_pastimes.cpp`: each one's clip in the rig and its
  turn, each drawing above the lane and over at its clip's end, half an
  hour at `tier2` dealing only working ones of `tier1` and `tier2`, after
  a rest of 4 to 10 s, never the same twice running, the newest tier's
  about 60% of the time, and none with no tier; the kit by the tiers, the
  hat winning the head, none while something needs you; the headphones'
  tune, a note from each cup in turn every 3 s, out past the band's ends,
  and none while bopping; the headphones put on first, coming down over
  its ears with its paws away, and on again after a needs-you; the moves
  at least 90 s apart over half an hour at `tier5`, the paws theirs while
  they play; working's base by tier, its lids lower the further in and
  faded out under a reaction or while something needs you; and the paws
  lifting before each key contact and tapping softly between), the rig's
  `x`, `reach` and `melt` on the gel
  (`test_the_rig_carries_reaches_and_melts_the_gel`: x off the screen, the
  reach's side out and the other in, a melt most of the way down and
  wider, its base where it was),
  the lane at the panel's size (fading whatever the draw cadence, blended
  once, cut and marked as the canvas does), the lane clear of the AMOLED's
  rounded corners (`test_the_lane_clears_the_rounded_corners`), the layers on the body's
  anchors, coming and going through the rig's layer stack, each at its
  opacity, the sign fading out at its own, drawing by coverage (a
  polygon's exact area in each pixel, so a lid 3/16 of a pixel thin never
  flickers, `test_polygon_edges_move_a_sixteenth_at_a_time`; arts of
  different shapes cross-fading with nothing showing through,
  `test_a_cross_fade_never_shows_through`, every two arts' in their room,
  `test_every_cross_fade_fits_its_room`), what moves gliding between
  pixels (`test_a_recording_replays_between_pixels`,
  `test_text_glides_between_pixels`, the outfit half a pixel down while
  the body moves), tracked
  clearing and kept cards and lanes matching a fresh frame, a finished
  turn's ticket and glow coming and going over them, steady frames
  allocating nothing, and the work stream
  (`test_the_work_stream_falls_behind_and_hits_in_front`: words in their
  lanes' columns behind the body, a hit's knock and daze and its lids
  opening after, every gag drawn off the heap), and the agents' drawer
  (`test_drawer.cpp`: a pull up the strip opening it and what the Mac
  hears, a swipe up the face staying the face's, a short pull springing
  back, a tap on a row picking it, shutting itself after 15 s and saying
  it's open till then, BOOT shutting it, its rows inside the panel's
  rounded corners, a long list's rows scrolling under a finger, gliding,
  springing back and resting on a whole row as the board asks for the
  rows it comes to, the body pressed flat under it, and its frames
  allocating nothing).

## The board's frames

- `internal/tools/boopctl sim --face gel` plays the pack's
  `tests/scenarios-gel/` against its `tests/golden-gel/`: every canonical
  mood and factual state, failure and neutral-finish frames, the host lane
  at the panel's size (`lane.jsonl`: the working count, a long name that
  needs you, the finish's marks and the bubble in each of its fonts), the
  comedy (`comedy.jsonl`: the yawn, the sneeze's wind-up, the doze, the
  long yawn, the zoomies at either edge, a snore, the hiccups and the
  gift), the gestures (`gestures.jsonl`: BOOT's hand-off, a stroke, a boop
  on the nose, a shake and peekaboo, each by the board's own input, its
  variation expected), the occasions (`occasions.jsonl`: a party's bounce,
  a night's drowse, frantic typing, in a nightcap and a party hat, and
  `tier4`'s kit), the pastimes (`pastimes.jsonl`: the working kit at
  `tier5` and a pastime over it, the done beat's tick, reading closely
  with the glass fogged, the headphones coming down, the coffee reach's
  sip, a puddle mid-melt, a stretch break's empty desk and its stretch,
  the idle plant and a pastime beside it, and needs you's wave), the
  replies (`replies.jsonl`: each reply's clip partway through under its
  face and sign, and a nap and a dance idle, asleep and at work), the
  layers (`layers.jsonl`: each outfit and air by its tags, Zs asleep at
  night, the morning's coffee at its side, at a sip and on the desk, a
  sign under the nightcap), a reaction's sign (`sign.jsonl`), a finished
turn's glow and ticket as a face for it talks, lingers, fades, goes up
and is taken down (`done.jsonl`), the
  work stream (`stream.jsonl`: two lanes' words falling, the to-do bar and
  the clock, a thought cloud, and every gag as it lands: arrive, bonk and
  its dizzy eyes, helmet, shrug, shatter, pass, hail's umbrella, look,
  stir, stamp, launch, poof, plane, phone, page, helper and back (landing
  as a word does), combo, the
  tower's stack, flag and topple, an edit's bars, and the whole turn's
  moments: a compaction's cube, a freeze, a drop, buried, and a turn's
  end gathering its words after the stream goes), and
  a finger in idle (`swipes.jsonl`), and the agents' drawer
  (`drawer.jsonl`: shut with the strip's chevron, pulled part way, open
  with the body squeezed flat and its paw over the edge, a row picked,
  handed over, and a long list scrolled, a row still coming as it
  scrolls). `--accept` updates only the gel
  goldens, after looking at them.
- `boopctl mirror` (in `make -C internal mirror`) plays the same scenarios
  on the Mac's mirror of the board (`characters/boop/mac/mirror/board.js`)
  and on the native simulator, both with no card, and checks every shot is
  the same, pixel for pixel; `firmware/tools/mirror.sh --check` builds the
  mirror again and checks it's the one checked in.
- `test_gel`'s `test_a_helper_draws_the_same_body` draws the body with a
  stand-in for the AMOLED's second core, its rows shared out differently
  every frame, and checks the frame is the same pixels as one core's.
- On the AMOLED, `internal/tools/boopctl perf --scenes` with the
  `amoled206_profile` build: each scene's frames a second against its
  budget, and the body's time (`body_us`, the erase included); its
  `stream` scene keeps two lanes' words falling and a word coming forward
  every 2 s (`stream_us`).
- `internal/tools/fluid/measure.py` measures how fluid the everyday
  transitions are on the board (`transitions.jsonl`, `idle-swipes.jsonl`),
  and the Character Studio's Transitions view ranks them in the page.

## For the eye

The Character Studio's **Gel on the board** card is the board's firmware:
its **Tools** record the review sets (24 representative activities, 13
directed mood bridges, `characters/boop/studio/review-sets.json`) from the
board as silent WebM clips, and play the sound sketches each on its own.
The studio's server saves the clips only with `--capture-dir DIR`, only
those the pack names, from its own page with its token, at most 8 MiB
each, never over a file (`characters/studio/tests/`). `node
characters/studio/check.cjs` records one in a headless browser
([the studio's README](../../../studio/README.md), Checking it). Clips are
art evidence, not owner approval.

## Limits that remain

- V3 artwork and the SFX sketches need the owner's art and listening
  review on the board.
- The owner approved the representative set; the directed bridges' clips
  are for the owner's spot-check.
- Real touch hardware and physical audio latency are separate tests, and
  so is the board's frame time (`boopctl ping`'s `draw_us`).
