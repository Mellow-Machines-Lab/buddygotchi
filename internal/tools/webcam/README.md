# The webcam recorder

A small AVFoundation recorder and frame extractor for looking at Boop's
physical screen. When and how to use the camera is the
[`webcam-verify` skill](../../skills/webcam-verify/SKILL.md), and the L3
checks ([internal/VERIFICATION.md](../../VERIFICATION.md) L3) use it
through `internal/tools/boopctl cam`. This page is the recorder itself.

It needs only Command Line Tools, with no FFmpeg or Python packages.
`webcam.sh` compiles `Webcam.swift` into `.build/webcam` next to it on
first use and after an edit. Run it from the repository root;
`internal/tools/webcam/webcam.sh help` lists its options.

## Camera permission

macOS gives camera access to the app that launched the process, so run
`record` from a terminal that has it. For agents here, that's a terminal
the Claude app opens (its Terminal panel); from an agent's
own shell `record` says the camera is missing or access is denied. If
macOS asks, allow it in System Settings → Privacy & Security → Camera.
Listing cameras never records.

## Commands

```sh
internal/tools/webcam/webcam.sh list  # cameras and their exact ids
internal/tools/webcam/webcam.sh record --camera ID --seconds 3 --out /tmp/boop-camera-framing
internal/tools/webcam/webcam.sh record --camera ID --seconds 10 --fps 30 --out /tmp/boop-camera-cheer
internal/tools/webcam/webcam.sh analyze --input /tmp/boop-camera-cheer/capture.mov \
  --out /tmp/boop-camera-cheer-review --roi 0.35,0.3,0.3,0.5 --start 1 --seconds 5
```

`record` prints `RECORDING …` once frames arrive and stops by itself after
`--seconds` (1–60, default 10); trigger the moment after that line. It
records video only, with no microphone and no upload. It picks a
640–1920 px format that supports `--fps` (15–60, default 30), and fails if
the camera has none.

`analyze` reviews `--seconds` (up to 15, default 5) from `--start`.
`--roi` crops with normalized **top-left** `x,y,width,height`; pick it from
the framing clip's `preview.png`.

Both refuse an `--out` directory that already exists, so evidence is never
overwritten.

## What it writes

- `capture.mov` and `capture.json` (record): the original video, which
  shows the whole room, and the camera's settings. Keep it local and out
  of git.
- `preview.png` (analyze): the first selected frame at full crop
  resolution, for framing and focus.
- `sequence-000.png`, … (analyze): every decoded frame in the interval,
  30 per sheet, left to right and top to bottom, with timestamps. These
  are consecutive frames, not sparse keyframes.
- `frames.csv`: every presentation timestamp and the interval since the
  one before.
- `report.json`: the observed capture cadence, gaps over 1.5× the median
  interval, the crop and interval, and a verdict of `unreviewed`.

A gap in the capture voids any smoothness claim across it. Regular
timestamps don't prove the firmware's frame rate either: duplicate camera
frames, auto-exposure, motion blur, the panel's scan and rolling shutter
can hide or mimic stutter.

## Tests

`make -C internal tools-test` generates a moving-square movie with one frame missing
and checks gap detection, that consecutive frames are kept, interval
selection, overwrite protection and bad arguments. It never opens a
camera.
