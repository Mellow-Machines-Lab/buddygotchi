# mediagen

The pictures in the READMEs, each from a real run, so they can be made
again when the face, the popover or a command's output changes:

| Name | File | From |
| --- | --- | --- |
| `boop` | `documentation/media/boop.gif` | boop-sim, the firmware's own drawing on the Mac: napping, working, needs you, tests, a big finish |
| `moods` | `documentation/media/moods.gif` | boop-sim: a reaction in eight of the moods |
| `popover` | `documentation/media/popover-light.png`, `popover-dark.png` | `Boop --snapshots`: the working and needs-you panes side by side |
| `watch` | `agent-hooks/media/watch.gif` | `agent-hooks/Examples/watch.sh`, on hooks from two made-up sessions sent through the real `agent-hook`, in a throwaway home |
| `beacon` | `mellowharness/media/beacon.gif` | `beacon listen`, with three builds sent by `mellowharness-emit` |

```sh
make build                                                        # for the popover's snapshots
internal/tools/.venv/bin/python internal/tools/mediagen/mediagen.py              # all of them, about a minute
internal/tools/.venv/bin/python internal/tools/mediagen/mediagen.py boop watch   # just these
```

It builds boop-sim and the two packages itself. The terminals are drawn
with Menlo, which macOS has, and every GIF's corners are transparent, so
they sit on a light or a dark page.
