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

## What it becomes

Boop's `notice`: the state the board plays, and on the rig the `notice`
clip (`rig/clips/notice.json`, 900 ms, additive: `lift` up to 12 px,
`gazeY` up, `eyeSize` a little bigger, then back). The clip has the
look-up; this reference adds what's before and after it, in this order,
as tracks the rig has:

| ms | `squash` | `lift` | Eyes and mouth |
| --- | --- | --- | --- |
| 0 | +200 | 0 | half shut, flat |
| 200 | +200 | 0 | open wide (`eyeOpen`, `eyeSize` up), mouth `o` |
| 280 | −220 | 6 | gaze up |
| 400 | +280 | 0 | |
| 560 | 0 | 46 | happy arcs (`eyeCurve` up, nearly shut), smile, `cheek` |
| 760 | +320 | 0 | |
| 1000 | 0 | 0 | open, looking at you, smile |

The studio's References view plays it beside the board's `notice` over a
calm idle, frame for frame; whether the clip should take these beats is
the owner's call (review/queue.json, `notice-perk`).
