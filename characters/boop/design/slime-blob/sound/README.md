# Nonverbal slime sound handover

Updated 2026-10-25. Scope: basic material/emotion/attention SFX, **not**
ElevenLabs, recorded speech/mumbles or background music. The executable
[sfx.js](sfx.js) provides procedural timbre sketches; slimegen cuts the
board's effects from them, and the gel engine's cues sound them at
visible contacts (The board's cues, below). No new speech is synthesized.

## Sound identity

Aim for small, soft, elastic, clean wet-gel contacts with occasional crisp
mechanical keys. Avoid viscous horror, bodily grossness, drum-like pounding,
constant electronic bleeps or a musical layer competing with future voice.
Most mood expression should be visual. Stronger feeling can have faster
or heavier **visible** action without making its whole loop noisy.

[sound-plan.json](sound-plan.json) has a profile for every mood, family
direction, recipe catalogue, three-take sketch variation and quiet mix
parameters. Profiles are tuning plans, not all individually reviewed audio.
The original nine sketch recipes are squish, bounce, wobble, poke, keyboard, tear,
knock_ding, complete and failed. They generate PCM in memory at playback;
two isolated stems, knock and ding, now support contact timing, and two
comedy sketches, a little sneeze and a snore's soft breath. Listen to each
with the sound sketches in the [Character Studio](../../../../studio/README.md)
**Gel on the board** card's **Tools**, or in context with its sound on.

Three variant indices are supported; short material effects vary pitch,
texture seed and resonance slightly. The alert changes knock count but
keeps its ding notes fixed. Success/failure vary texture seeds, not their
meaning. These are starting timbres for review—not a claim that all moods
already have three independently art-directed finished sounds.

## Where each sound belongs

| Physical cue | Sound and timing |
| --- | --- |
| Body reaches meaningful compression | Short squish at compression; skip minor breathing |
| Body lands after a real hop | One soft plop at contact, not at takeoff |
| Large elastic rebound | Optional wobble on first rebound, not every oscillation |
| Finger indents gel | Tiny poke; drag remains mostly silent until release/landing |
| Key contacts keyboard | Crisp tactile click selected among actual visible contacts |
| Tear lands on desk/body | Occasional subtle plip; do not sonify every flowing tear |
| Alert contacts surface then sign appears | Mood-shaped knocks → invariant ding; hold sign silently |
| Confirmed successful result is revealed | Thicker short celebration swell, no full BGM |
| Confirmed failed result/tool warning | Distinct descending/soft sputter cue, never trophy notes |

Use **semantic cue IDs** from the same animation clock: body_contact,
key_contact, screen_knock, alert_reveal, success_reveal, failure_reveal.
Give every cue instance a unique identity (request/action, iteration,
contact index). Schedule once, drop stale cues after interruptions, never
replay an elapsed cue on mood retarget or variation switch. Audio latency
compensation belongs to the output backend and must be measured.

Do not run a second timer playing evenly spaced clicks. Randomness first
chooses contact choreography; SFX can select or omit those real contacts.
Pitch/gain jitter is small and bounded. Moving a click off its actual
frame to make it sound random breaks synchronization.

## Mood changes the performance, not the notification identity

- Calm/comfy/lazy/bored: routine resting/idle silent. A notable gesture
  may use a tiny gel accent where permitted; no periodic idle soundtrack.
- Happy/excited/amused/pleased: buoyant rounded contacts, modestly brighter
  resonance; excited gestures can be busier but the sound gate stays sparse.
- Curious/engaged/determined/confused/baffled/skeptical: precise contacts,
  thoughtful pauses; determined is steady, not angry percussion.
- Proud/mischievous: firm clean accent and small settling wobble, no
  prerecorded laugh or spoken expression in this phase.
- Annoyed/irritated/grumpy/angry: compact lower/stronger contacts with
  bounded clustering; don't make every aggressive movement audible.
- Disappointed/sad/crying/whiny/wounded: softer, lower, slower contacts;
  liquid tear accents, not sobbing recordings or guilt sounds.
- Uneasy/scared/frightened: airy short recoil; no real-danger siren.
- Surprised/stunned/speechless: one brief pop/freeze then silence.
- Shy/embarrassed/affectionate/lonely: timid soft touches, long spaces.
- Tired/exhausted, hopeful/relieved, uncomfortable/disgusted/overwhelmed:
  use their distinct settling/strained/recovery direction; many cues silent.

For needs_you, grumpy taps more firmly/in a short cluster, determined
steadily, sad lightly/slowly, excited at several surface positions. Taps
are broad soft body/surface contacts—not detailed hands or cursor points.
Every variation ends in the same recognizable ding family, with one new
request identity authorizing one alert. It must not sound again simply
because the mood changed or the sign loop repeats. The board sounds
separate contact-timed knock and ding stems; the combined sketch remains
for the studio's audition.

## Quiet policy and future voice space

Keep the shipping voice-first policy as reference.
The plan file records the local target constants. Routine sounds should
cover only about a quarter of visible contacts and a few gestures per
cycle, with extra silent cycles for fast loops. Rest, idle, listening and
waiting are silent. Attention/result cues remain whole recognizable
one-shots, once per event, then silence. Mute must silence everything.

Future spoken overlays are not synthesized here. Leave their safe entry
window after attention cues; duck routine effects rather than adding a
busy background. The host/Voice owns what is said and the renderer/audio
backend owns contact timing. An alert is not an excuse to play a mumble
over its ding. Preserve existing needs_you speech suppression unless a
separate reviewed behavior change explicitly revises it.

## Script storage is not the shipping audio format

The studio's audition synthesizes the sketches live. The board doesn't
run JavaScript: slimegen renders each sketch's three takes at 11,025 Hz,
8-bit, into `slime.h` (`kClip`, `kSamples`, about 230 KB), and the board's
effects mixer plays them. A native oscillator/noise port is an alternative
requiring CPU/audio-driver tests. Choose this explicitly; code-sized
design inputs do not imply zero runtime buffers or zero flash.

## Definition of done

Approve a few material timbres on the intended speaker, then tune mood
families and state-specific contacts. Implement clock/cue deduplication,
interrupt/mute/ducking, measure audio latency, and audition representative
work/alert/success/failure scenes in context. Mark sound-plan/coverage
status only after hearing the integrated result. No paid generation or
voice-bank additions belong to this milestone.

## The board's cues

The gel engine (`render/gel/engine.cpp`) takes the scene's actual contacts
each frame, a gag's after the scene's, and makes a cue of those that may
sound; a frame stepped again makes none, and it emits no separate timed
events. Sound uses its own seeded random source (the engine's seed XOR
0xa511e9b3), leaving motion unchanged. A cue keeps its contact's request,
generation, iteration and index.
All seven routine work states use the plan's probability 0.25 and cap of four
contacts per cycle; loops under 3.5 seconds sound only on even iterations.
Other active states sound on their first iteration. Rest, idle, no app,
listening and waiting remain silent, but for comedy: an idle sneeze, excited's
zoomies landing at each edge and a snore's breath while asleep sound in any
state, each contact with the routine chance (a quarter), ducked as routine
sounds are ([CONTINUITY.md](../CONTINUITY.md), Comedy). This quarter-contact
policy is more conservative than the pixel bank's roughly 30% policy; it is
not a claim of identical choreography. Reveal guards keep request identity
across mood retargets and repeated result loops, in a bounded history of
the last 64 requests.

`key_contact` maps to keyboard, `body_contact` to squish, `screen_knock` to
knock, and `alert_reveal` to ding. Only explicit success maps to complete;
a successful finish a size above small maps its reveal to cheer and its
landings to bounce instead ([CONTINUITY.md](../CONTINUITY.md), Finishes);
explicit failure and tool error map to failed. Neutral starting/helper/reply/
stopped reveals receive a small squish. Neutral completion is silent.
`sneeze_contact` maps to sneeze, `zoom_contact` to bounce and
`breath_contact` to breath, two sketches added for the comedy. There
is no tear/landing/rebound sound without an authored visible contact.
The ding uses fixed variant 0, seed 53, pitch 1 and gain 0.45, with its existing
880 and 1318.51 Hz notes; mood never retunes it.

The board's face hands its cues to the device (`render/gel/face.cpp`):
one more than 150 ms late for the device is dropped, and a new request, a
state change or a fresh needs-you silences what the last left. The
device's effects mixer (`firmware/src/voice/effects.h`) plays at most four
at once, a fifth replacing the oldest, fades each out over 4 ms, ducks
routine ones to a quarter under a line and leaves needs you's, a finish's
and an error's whole. Volume zero is silence. The plan's future voice
windows (0.45 s routine and 0.12 s after protected audio) stay metadata.

`test_gel` (`test_requests.cpp`) checks that cues stay sparse (at most
four a pass at work, short loops silent on odd passes, under 0.4 of the
contacts over ten minutes), that quiet states sound only comedy, sparsely,
over twenty minutes of idle and five of sleep, that a request dings once
whatever changes (a mood, a name, a lost link), each ding variant 0, seed
53, pitch 1 and gain 0.45, that a finish loops six times with one fanfare,
and that sound's randomness changes nothing drawn. The device mixer's
limits are `internal/firmware/test/test_effects`'s. Timbres remain
sketches; mathematical checks do not establish listening quality on a
speaker.

Choosing a sound sketch in the studio, or **Stop sound**, turns the board's
sound off, so an isolated timbre audition cannot layer over the scene.
