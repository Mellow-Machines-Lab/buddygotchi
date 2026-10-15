# Nonverbal slime sound handover

Updated 2026-10-05. Scope: basic material/emotion/attention SFX, **not**
ElevenLabs, recorded speech/mumbles or background music. The executable
[sfx.js](sfx.js) provides procedural timbre sketches. The pure cue scheduler and browser
player synchronize them to visible contacts. Animation sound starts muted
and is enabled only by the preview button. No new speech is synthesized.

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
two isolated stems, knock and ding, now support contact timing. Listen with the sound sketches in the
[Character Studio](../../../../studio/README.md)'s **Tools**.

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
because the mood changed or the sign loop repeats. The integrated player uses separate contact-timed knock and ding stems;
the combined sketch remains available for manual audition.

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

Desktop Web Audio can synthesize the sketches live. The current firmware
bakes procedural recipes into small shared PCM effects plus event scores
via sfxgen; it does not execute JS. A native oscillator/noise port is an
alternative requiring CPU/audio-driver tests. Choose this explicitly;
code-sized design inputs do not imply zero runtime buffers or zero flash.
Do not replace the shipping synthesizer or regenerate firmware assets
just by adding these sketches. No device audio has been tested here.

## Definition of done

Approve a few material timbres on the intended speaker, then tune mood
families and state-specific contacts. Implement clock/cue deduplication,
interrupt/mute/ducking, measure audio latency, and audition representative
work/alert/success/failure scenes in context. Mark sound-plan/coverage
status only after hearing the integrated result. No paid generation or
voice-bank additions belong to this milestone.

## Synchronized reference cues

`engine/cues.mjs` consumes the scene's actual contact IDs after each frame.
It deduplicates repeated frame inspections and emits no separate timed events.
Audio uses its own seeded PRNG (actor seed XOR 0xa511e9b3), leaving motion
unchanged. Cue IDs include request, generation, iteration and contact identity.
All seven routine work states use the plan's probability 0.25 and cap of four
contacts per cycle; loops under 3.5 seconds sound only on even iterations.
Other active states sound on their first iteration. Rest, idle, no app,
listening and waiting remain silent. This quarter-contact prototype policy is
more conservative than the pixel bank's roughly 30% policy; it is not a claim
of identical choreography. Reveal guards retain request identity across mood
retargets and repeated result loops. Notification history currently has the
same actor-lifetime scope as the reference router's request history.

`key_contact` maps to keyboard, `body_contact` to squish, `screen_knock` to
knock, and `alert_reveal` to ding. Only explicit success maps to complete;
explicit failure and tool error map to failed. Neutral starting/helper/reply/
stopped reveals receive a small squish. Neutral completion is silent. There
is no tear/landing/rebound sound without an authored visible contact.
The ding uses fixed variant 0, seed 53, pitch 1 and gain 0.45, with its existing
880 and 1318.51 Hz notes; mood never retunes it.

`sound/player.mjs` consumes even muted, suspended and stale cues. More than
150 ms late is dropped; there is no backlog at unmute. Four sources play at
most; a fifth replaces the oldest immediately. Scene interruption uses a 4 ms fade for
all tails; an expression retarget fades routine tails while preserving a
protected notification. Mute or zero volume stops all immediately. Volume is
bounded to [0,1]. Voice activity reduces routine levels to 0.25 and leaves
protected attention/result/error cues whole. The player adds no voice; the
plan's future voice windows (0.45 s routine and 0.12 s after protected audio)
remain metadata for the device integration. Desktop latency compensation is
zero until measured; the pixel device's 70 ms lead is not assumed for Web Audio.

`tools/check-cues.mjs` checks contact alignment, duplicate consumption, unchanged
motion, deterministic cue lists, the 60-second attention hold with three mood
changes and one ding, repeated completion loops, sparse routine cycles and the
player's limits/mute/suspension/ducking using a fake audio backend. Timbres remain
sketches; mathematical checks do not establish listening quality on a speaker.

Choosing a manual sound sketch or **Stop sound** mutes integrated animation
audio, so an isolated timbre audition cannot layer over the scene mixer.
