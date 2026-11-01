# A new character: the playbook, and what would make it repeatable

Updated 2026-10-26. Written while building Pixel Bro
([Mellow-Machines-Lab/PixelBro](https://github.com/Mellow-Machines-Lab/PixelBro)),
the third character: Pixel's body with a new soul, on the AMOLED. The first
half is the playbook as it ran, so the next character can follow it. The
second half is what cost time, and the longer-term fixes, for the owner to
pick from. Nothing here is decided.

## The playbook as it ran

1. **Write the bible first.** One page in the pack's `design/` (Pixel
   Bro's is `design/BRO.md`): who the character is, the few rules every
   interaction follows, the line it never crosses, and a table of every
   look and reaction. Every worker after this reads it, and it is what
   keeps the steering, the voice and the art one character.
2. **Copy the closest pack's repository**, not only its `character/`:
   the Makefile, CI, CLAUDE.md and README are what make it a repository of
   its own. Set `id`, `name` and `faces` in `character.json`.
3. **Pick the face per board.** `faces: {"amoled206": "pixel"}` builds,
   but a build is not a picture: the AMOLED pushes only native frames
   (its `displayPush(const render::Canvas&)` has been empty since the
   gel became its only face, 5cf11c49), so the pixel face drew into a
   canvas nobody saw, while `boopctl shot`, which reads the canvas,
   looked fine. Only the board's `push_us` (5 µs) gave it away. Pixel
   Bro's face now draws natively (`scaleInto` in his
   `render/pixel/anim.cpp`): the canvas 1.5 times as large at the
   board's picture window, so the touch map holds. It has every state
   but not the gel's own extras (the agents' drawer, the work stream,
   the pastimes: `Face::hasDrawer`, `watch`, `playPastime` in
   `firmware/src/render/face.h`).
4. **Map the moments to moods.** The face picks its performance by mood,
   so a ladder (failures, pokes, wins) is a climb through moods, each rung
   with its own art and takes. Say this in the moods' `face` strings in
   `character.json`, which the brain reads, and in the personality's
   Examples.
5. **Three workers at once**, each owning its own files: steering and
   evals; the voice; the art, sounds and face code. Only one runs the
   shared builds (staging, PlatformIO, the simulator), because they share
   `.character-build/` and `firmware/.pio/`.
6. **Demos after all three**, then record them (`make -C internal demos`).
7. **Check**: `boopdev check`, `charactergen.py --check`,
   `CHARACTER=<id> make -C internal fw-test`, the board's firmware build,
   `boopdev eval --scripted`, then a few Jev scenarios, the simulator, and
   the board last.

## What cost time, and the fixes

| Friction | Longer-term fix |
| --- | --- |
| CHARACTER.md §14 still says to copy a pack into the engine's `characters/`; packs are repositories of their own now, and the repository's files (Makefile, CI, CLAUDE.md, README) were copied and edited by hand | A scaffold: `packs.py new <Repo> --from pixel --id <id>` that writes the repository, links it, and edits the names and the board; rewrite §14 around it |
| Nothing says a face can run on another board; §9 reads as if the AMOLED needs the gel. The pixel face built for the AMOLED and showed nothing, and no check caught it: the simulator, `shot` and the tests all read the canvas | Put the 1.5× canvas push back in the AMOLED's `display.cpp` (or move Pixel Bro's `scaleInto` into the engine for any canvas face), then a line in §9 and a board × face table; and a check that fails when a pack names a face for a board that never pushes it |
| The simulator page maps a click to the canvas in proportion to the native picture (`CANVAS` in `boop-simulator.js`), while the board maps through its picture window (`panelToCanvas`); a centred 1.5× canvas is then off by up to 15 canvas pixels at its top and bottom edges, in the simulator only | One touch map for both: the board's |
| Pixel's steering is much thinner than Boop's (no `replies.md`, no `talk/`); the real template is Boop's | Make one pack the complete steering template, or a `characters/template/steering/` with every file and a comment on what each is for |
| `signs.md` and `diary.md` get the mood files' token budget (225) by falling through `Steering.Budget`, though only 6 signs and 8 diary lines are ever offered, so good lines were cut | Budgets of their own for `signs.md`, `replies.md` and `diary.md`, sized by what's offered |
| There is no voice builder in the engine: each pack copies SlimeBuddy's voicegen, and the lists of what `say` offers (feelings, topics, replies) are copied from Swift | A pack-agnostic voicegen in `internal/tools/`, reading a pack's phrase bank (Pixel Bro's `design/bro-voice/lines.txt` format) or its recordings, with `boopdev` printing `say`'s options as JSON so no list is copied by hand |
| The voice's rules are checked only by `VoiceTests`, pinned to Boop's pack (counts, ids), and the XCTest shim stops at the first failure | Split the pack-generic voice rules (every face has every feeling and topic, swears only on failures, replies' words) into a test that runs for every pack, `boopdev check` included |
| `make -C internal check` fails with any third pack chosen: boopctl's tests expect Boop's take ids in the chosen pack's voice, and the session tests' `scripts.find("context-wall")` finds two packs with that demo. PixelBro's `make check` runs `tools-test` with `CHARACTER=pixel` to get past it | Pin the tools' tests to the pack they're written against, as `make -C internal test` pins Boop's, and have `scripts.find` prefer the chosen pack |
| A character repository's `engine/` submodule gets its own PlatformIO core (`firmware/tools/pio-core.sh`), 5 GB more on a disk that had 8 GB free | Find the main checkout's core, or a shared one in `~/.cache`, from a submodule too |
| `boopdev eval` and `boopdev check` read the staged pack, so a renamed eval or a new demo is "missing" until a restage | Have both restage first, or read the pack in use directly |
| `boopdev check` doesn't check a demo's `react.sign` against the pack's signs and replies | Check it there, as the other brain answers are |
| The animation bank is copied whole (1,214 performances); a new character that keeps the motion still has to edit generators to change the look | A wardrobe layer in the bank: a character's outfit and props as data, drawn over every resting face, with its new performances added beside the bank's, not edited into it |
| The simulator draws the pixel face only on the CYD's 320×240 layout, never the AMOLED's 1.5× one, so how a pixel-face pack looks on the AMOLED shows only on a board | Let the simulator pick the board's layout from the pack's `faces`, not from the face |
| Pixel's firmware tests (`tests/firmware/`) and the bank's `qa/check.mjs` pin Pixel's exact counts, and the bank's check can't find the engine in a character repository's layout | Tests that check rules (every state answered, loops close) rather than counts; the bank's check finding the engine through `engine/` or `charactergen.py --which` |
| There's no tool that draws a pack's designs as the board does, for looking at them; Pixel Bro's art worker wrote `tools/facegen/sheet.py` | Make a contact sheet a standard `boopctl` command: any mood × state, every frame, as one PNG |
| facegen cut the rig face's parts from the first idle design, which a new outfit can leave untagged | Cut from the first tagged idle (Pixel Bro's facegen does), and say so in the bank's guide |
| The studio's `check.cjs` fails unless every face's simulator build exists | Skip, with a note, a face whose build isn't there |
| The pixel face plays no clip for a push-to-talk reply (`reply-<name>`, §15), so a reply is only a sign and a face | Reply clips for the pixel face, or a reply state the bank can draw |
| The studio registers a face's adapter by the pack's face id, and the bank's bundle sets one global (`window.Boop`), so a second pack on the pixel face clashes with Pixel's (Pixel Bro's sets `globalThis.PixelBro`) | Register adapters by pack id, and give each bank's bundle the pack's name |
| The popover's snapshots (`internal/app/Boop/Snapshots.swift`) show Boop's own diary lines whatever the pack, so `make media` drew "I stayed brave" in Pixel Bro's README until the lines were swapped by hand for the run; the social preview is made by hand too | Fill the snapshot's diary from the pack's `diary.md`, and have `mediagen` make the social preview from the pack's name and README tagline |
| `boopdev eval` prints its verdicts only to stdout; the run files in `/tmp/boop-eval` hold the answers but not whether each step passed, so a lost stdout means paying for the run again | Write each step's verdict and the run's result into its run file |
| The brain hears the work stream ("hitting Pixel Bro in the face", `EventLine.swift`) on a face that doesn't draw it | Word that line by what the pack's face draws, or leave it out when the face has no stream |
| The engine's option texts describe Boop's own moves ("It snuggles up", "It giggles") whatever the character | Let a pack word its replies' moves, or keep the options' texts neutral |
| A pack that's not in `characters/packs.json` gets no engine CI, and the engine's tests read only Boop's and Pixel's | A `packs.json` entry marked `optional`, checked by `boopdev check` and the pack's own CI only |

## Pixel Bro's own leftovers

- His voice is espeak-ng placeholders (`design/bro-voice/`); a real voice
  replaces `voice/voice.bin` and `mac/takes.tsv` with the same lines.
- He has no mirror (`mac/mirror/`), so the popover shows his still faces,
  not the board's firmware.
- His voice file hasn't been on a board's card: copying 17 MB over USB
  takes hours, so the board ran him with Boop's card, silent and muted.
- He has no simulator goldens of his own (`boopctl sim` checks Pixel's),
  and no reply clips for push-to-talk replies.
- His picture on the AMOLED has been measured (frames, heap, push) but
  not seen: the webcam is the owner's to turn on.
