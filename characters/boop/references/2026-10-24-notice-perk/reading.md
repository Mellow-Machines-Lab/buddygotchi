# Notice, like a dog hearing its name: the reading

Read from `sheets/perk.gif.png` (25 frames, 40 ms apart, 1 s). Inspiration,
not a copy: the beats and their timing are what to keep; the drawing is a
sketch.

## Beats

| ms | Beat | What happens |
| --- | --- | --- |
| 0–160 | Dozing | Low and wide, a slow breath; nothing else moves |
| 200 | The name | One frame: eyes snap open, a red `!` appears above, the mouth a small `o` |
| 240–280 | Perk | Shoots up tall and narrow (the tallest frame at 280), lifted a few px off the ground, eyes up |
| 320–400 | Wind-up | Sinks into a squat, wider than it rested; the `!` goes at 360 |
| 440–640 | Hop | Leaves the ground, stretched going up, round at the top (about 46 px up at 560), happy closed eyes and an open smile, blush on |
| 680–760 | Landing | Flattens hard on contact, the flattest frame at 760 |
| 800–960 | Settle | Two small wobbles, round eyes with a highlight, looking straight out, smiling |

The perk is fast (80 ms from the name to the tallest), the hop slow by
comparison (240 ms in the air); the landing and settle take the last
quarter.

## Poses and squash

- Resting squash is a little flat (about +0.2 on the rig's `squash`).
- Perk: tall, about −0.22, with `lift` 6 px.
- Wind-up: flat, about +0.28, back on the ground.
- In the air: stretched at take-off (−0.25), round at the top (0), `lift`
  up to 46 px, the shadow shrinking under it.
- Landing: the flattest, about +0.32, then a damped wobble (two swings,
  gone by 1 s).

## Eyes and mouth

- Dozing: half-lidded (`eyeOpen` about 0.3), a flat mouth.
- The name: wide open, whites showing, pupils up (`gazeY` up), mouth a
  small round `o` (`mouthOpen` 0.4, `mouthWidth` small).
- Hop and landing: happy arcs (`eyeCurve` up, nearly closed), an open
  smile, cheeks on.
- Settle: round, open, a highlight, looking at you; smile; cheeks on.

## Colours and silhouette

A soft mint body with a darker green outline on cream, a warm shadow, pink
cheeks, a red-orange `!`. Only the silhouette matters for us: one round
blob, no limbs, its outline reading as squash and stretch alone. Nothing
here needs more than the rig has (no ears, no arms), so it isn't a rig
extension.

## What it became

Boop's `notice`: the state the board plays, and on the rig the `notice`
clip (`rig/clips/notice.json`, where its keys are). The owner approved
these beats as its reference on 2026-10-24, and the clip took them in the
tracks the rig has: the eyes wide and up at the name (`eyeSize`, `gazeY`)
with the mouth's `o` (`mouthOpen`); the perk tall, the wind-up, the flat
landing and the wobble (`squash`); the hop off the ground (`lift`) with
the eyes squeezed (`eyeOpen`) and the smile; and a body contact cued at
the take-off and the landing. The happy arcs and the cheeks are the face
the board borrows for each take, since the rig has no `eyeCurve` or
`cheek`: the hop's eyes are squeezed shut instead.

The gel plays it (CHARACTER.md §15, The gel on the rig), so
the studio's References view shows it beside the reference, frame for
frame. Pixel's face doesn't play it.
