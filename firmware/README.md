# Boop's firmware

The board is Boop's body: it draws the face, plays the sounds and reports
touches, over Bluetooth or USB. It's Boop's app on LinkKit's device library
(`linkkit/device/`), built with PlatformIO for one board, the AMOLED. The
CYD board is archived (CLAUDE.md, Repositories).
How it fits with the Mac is in
[architecture.html](../documentation/architecture.html).

## Build and flash

```sh
make -C internal fw          # build the firmware for the board (env amoled206)
make flash                   # build and upload over USB, to the board plugged in
make -C internal fw-test     # the firmware's unit tests on the Mac (env native)
make -C internal sim         # every scenario in the simulator, against the goldens
internal/tools/boopctl ping  # firmware version and SHA, why it last restarted, uptime, heap, fps, link
```

A loop that stops coming round for 5 seconds restarts the board (the
core's task watchdog, on from the end of setup). Its `hello` and
`ping` say why it last restarted in `reset`: `power`, `button`,
`software`, `usb`, or trouble, `panic`, `watchdog`, `brownout` or
`other`, which the Mac's `boop.log` notes.

`make flash` runs `firmware/tools/flash.sh`, which finds the board on
`/dev/cu.usbmodem*` (env `amoled206`). With more than one board plugged
in it stops and lists them; `BOOP_PORT=…` picks one.

A character pack says which of its faces each board draws (its
`faces`, by the env's `custom_board`; [CHARACTER.md](../characters/CHARACTER.md)
§9), and `firmware/tools/pack_face.py` builds that face and none of the
pack's others, into the env's own build folder. Boop's draws the gel
slime on the AMOLED. The firmware needs a face that draws natively: with
any other, the board stops at the start and says so on USB. `make flash`
builds with the chosen pack ([CHARACTER.md](../characters/CHARACTER.md) §2).

Under the faces, `src/render/` is portable C++ with no display library,
which the boards, the native simulator and the WebAssembly one all
build. Its `rig/` is the engine the faces are moving onto: the rig's
channels, the types of a pack's tables, the ramp its fades ease on and
the anchors a face reports (`rig.h`), and the mixer that plays a look
and Moments' clips into the channels each frame (`mixer.h`).
Staging writes the pack's rig as `rig_tables.h`
([CHARACTER.md](../characters/CHARACTER.md) §15). The gel plays its
clips through a mixer of its own, over its own engine's pose.

The make targets run PlatformIO through `firmware/tools/pio.sh`, which
keeps its packages, a few GB of toolchains, in the main checkout's
`firmware/.platformio-core` (`firmware/tools/pio-core.sh`), so every
worktree shares one copy. `PLATFORMIO_CORE_DIR` overrides it.
An upload through it (`-t upload`) builds first, then waits for the
board's lock, so it never flashes over another session's test, and is
logged; `internal/tools/boopctl board` says who has the board and what
was flashed on it ([internal/VERIFICATION.md](../internal/VERIFICATION.md) §2).
It uses the `pio` on your `PATH`; without one, its first run installs
PlatformIO there too, with pip, into that folder's `venv`.
Either way the ESP32 platform needs Python 3.10 or later, newer than the
Mac's own 3.9.
Each build bakes in the version from `VERSION` and the git SHA
(`firmware/tools/version.py`).

The firmware talks over USB serial at **460800 baud**. The AMOLED
board's native USB flashes at 921600.
Opening the port must not change DTR or RTS, or the auto-reset circuit
reboots the board; `boopctl` leaves them alone.

### Updating from the app

`make bundle` builds the firmware for each board the chosen pack has a
face for into `Boop.app` (a board it has none for isn't offered an
update), packed by
`firmware/tools/package.py` with a manifest of the board, its chip and
flash, the version and SHA, and where each image goes, read from the
board's own partition table. A board's `hello` names it (`board`, its
env). When the board runs an older version than the app
carries, or the same one built with another character pack, Settings
offers the update, and so it does when the board's firmware doesn't
fit the app at all. Plugged in over USB, the board must be the one on
Bluetooth: its bootloader reports its MAC, and the Bluetooth address
made of it ends in the two bytes its `hello.id` does. Another is refused
before anything is written. Then the app writes the image for the chip
its bootloader reports, the app image and the boot-slot record, through
the chip's ROM bootloader (LinkKit's `Flasher`) and restarts it, even
when the write fails, leaving the bootloader, partition table and NVS
as they were. A write that stopped partway can be tried again: the
half-written board has left Bluetooth, but its MAC still matches.
From a terminal,
`linkkit-flash` writes the same images:

```sh
linkkit/.build/debug/linkkit-flash --chip esp32s3 --flash-size 16MB \
  0xe000:.build/Boop.app/Contents/Resources/firmware/amoled206/boot_app0.bin \
  0x10000:.build/Boop.app/Contents/Resources/firmware/amoled206/firmware.bin
```

## The board

### The AMOLED board (env `amoled206`)

Waveshare **ESP32-S3-Touch-AMOLED-2.06**, a watch-style board, runs the
app with its own pins, screen, touch, sound and start-up in
`src/board/amoled206/`. Nothing outside the board's folders knows which
board it's on. Its face is the gel slime, so it needs Boop's pack (above).

| Part | What it is | How Boop uses it |
| --- | --- | --- |
| Chip | ESP32-S3, 8 MB PSRAM, 32 MB flash | Built as 16 MB flash (`default_16MB.csv`). The loop runs on core 1; core 0 sends each frame to the screen (`amoled206/display.cpp`) and draws the lower rows of the next one's body while the loop draws the upper (`amoled206/helper.cpp`, `render/helper.h`). The gel's material, 1 MB read a texel a pixel, is copied into PSRAM at start (`Hal::quickerCopy`): the cache fills from there faster than from flash |
| Screen | 2.06" AMOLED, 410×502, CO5300 on quad SPI | Held sideways, USB-C on the left. Its corners are rounded, about 110 px in radius, and show nothing there (`kNativeCorner`, measured from a photo of the board): a native face keeps its lane clear of them (`render::Surface::inset`) |
| Touch | FT3168 on I2C (SDA 15, SCL 14, INT 38) | Read only around a touch, since it naps when idle. A touch ends as soon as the chip reports the finger lifted (no point, or its lift-up event), not 50 ms after the last reading; `internal/tools/boopctl state`'s `touch.lifts` counts those reports. It reads in the panel's own pixels, x along its 410 side and y along its 502, as Waveshare's own example hands them to LVGL unturned; `amoled206/hal.cpp` turns them onto the canvas as the picture is turned. Not yet checked under a finger: held sideways, USB-C on the left, swipe down once, then run `internal/tools/boopctl state`: `touch.last` should go `from` a smaller y `to` a larger one with x about the same, and a swipe right should raise x. If not, the map in `hal.cpp` is the one to fix |
| Sound | ES8311 codec over I2S, NS4150B amp (enable on 46) | 16-bit mono at 22.05 kHz |
| microSD | SPI3 (SCK 2, MOSI 1, MISO 3, CS 17) | Boop's voice, every recorded take in one file. Use a FAT32 card |
| USB | The S3's own USB-Serial/JTAG | `/dev/cu.usbmodem*`; flashing needs no BOOT press |
| Buttons | BOOT (IO0) | The main button. No LED |
| Motion | QMI8658 on I2C (0x6B, else 0x6A) | Picked up, put down, shaken, a thump on the desk, face down (do not disturb: no `say` and none of the face's sounds) and up: `app/motion_gesture.h`'s first guesses, read every 20 ms at ±4 g (`amoled206/imu.cpp`). The same readings give the steady tilt the face sloshes by (`app::Tilt`, `dbg.state`'s `tilt`; `kAcross` says which way x runs). Its z is flipped to point out of the screen (`kFlipZ`: the chip reads about −1 g resting screen up); x and y are still a guess. Check them on the board, where `dbg.state`'s `imu` is the reading now (`internal/tools/boopctl state`) and `dbg.imu` stands in for the sensor |

Waveshare's example repo (`waveshareteam/ESP32-S3-Touch-AMOLED-2.06`) has
a recovery image in `FirmWare/` if you ever need the factory firmware back.

### The boards with no hardware

Two more folders in `src/board/` are boards on a computer, which the
board's env doesn't build:

- `hosted/`: the firmware's device on LinkKit, fed what a host sends on
  its USB, ticked as the firmware's loop ticks it, and its frames read,
  as RGBA for a page, with what it says kept until the page takes it.
  The simulator ([simulator/README.md](../simulator/README.md)) and the
  Mac's mirror run it, each behind a Hal of its own. `platformio.ini`'s
  `[hosted]` lists it and the portable code it runs, once: the native
  env builds from that list, and `tools/wasm.sh` reads it to build a
  hosted board to WebAssembly with Emscripten (`brew install
  emscripten`), with a pack's faces, or only the one it gives a board
  (`--board`), and an entry's own sources and flags.
- `mirror/`: the Mac's mirror of the board, the face the popover and
  onboarding show: the hosted board with the page's clock and nothing
  else (no touch, motion sensor, light, sound or card), on a frozen
  clock the page settles and then runs, with the face a character pack
  gives the AMOLED, built by `tools/mirror.sh` (on `tools/wasm.sh`)
  into the pack's `mac/mirror/board.js`
  ([characters/CHARACTER.md](../characters/CHARACTER.md) §9);
  it's a build's output, not checked in: `make -C internal build` and
  `app` build it when it's stale (`tools/mirror.sh --if-stale`).

## Bringing up a board

1. **Test pattern:** `internal/tools/boopctl play pattern` shows six colour
   blocks, labelled corners, a big UP arrow and a black bar down the USB-C
   edge. Upright, the arrow is at the top; the colours confirm inversion
   and colour order.
2. **Screenshot:** `internal/tools/boopctl shot` matches the simulator
   pixel for pixel.
3. **The rest:** `internal/tools/boopctl state` reports BOOT, raw touch
   (and the last touch on the canvas: where it went down and was last,
   how long it took, whether it began on the body and what the board made of
   it, `touch.last`, and how far
   the face leans into a finger at rest, `touch.lean`),
   and the amp, and `ping` shows Bluetooth advertising and
   whether the voice is on the card. Presses and the speaker need a
   person.

How every check works is in [internal/VERIFICATION.md](../internal/VERIFICATION.md).

## The invite

After a skit the Mac may send a `do` with an `invite` (`app/behaviour.h`,
`InviteIn`): Boop asks for one touch, and the touch pays off. Only a board
whose face draws invites gets one: its `hello` says `"invites":1`
(`render::Face::drawsInvites`). The gel does; a face that doesn't plays a
`do`'s invite not at all.

1. The `do`'s face, words and sign play as ever.
2. Once none of them plays, the pose: Boop comes up to the glass, the place
   to touch glowing, the `label`'s word by it.
3. The wait, the invite's `ms` (1 to 30 s, 4 s with none). A touch of its
   kind answers it: a `tap` is a tap, a boop on the nose or a tickle (BOOT
   too, when it would poke); a `stroke` is a stroke, a ruffle or a finger
   the face leaned into. That touch is the invite's: no `ev tap` or
   `ev gesture` and no poke. It may land beside the body, where the glow is:
   there a quick stroke is a swipe, which is the invite's with one agent and a
   switch with several. Any other touch is what it always is.
4. The payoff at once, or with no touch a shrug, and only then the `do`'s
   `ended`. It never rests, so nothing queued replaces it.
5. For 30 s after a miss (`Behaviour::kLateWindowMs`), a touch of its kind
   still pays off, late.

Needs you, face down, listening or a `now` reaction cut it before its
answer. The board says how it ended before the `do`'s `ended`:
`{"t":"ev","kind":"invite","did":"answered","data":{"skit":"win","touch":"tap","ms":1300}}`,
`did` `answered`, `missed`, `late` or `cut` (`ms` from the pose, 0 when
cut before it). `dbg.state`'s `invite` says how it stands: `stage`
(`ahead`, `pose`, `payoff`, `shrug`, `window` or `late`), `ms` since the
pose began, and the `pose` while one shows.

What the gel draws for it is the pack's: every pose, payoff, miss and
late return is a rig clip, the palm and the lean with the two hands and
the glass, the back and the high five's spin with `turn`
(`render/gel/moves.h`, the pack's CONTINUITY.md, Hands and the glass, and
Turning round). The state machine, the wire and `test_device`'s tests are the
same for every face.

## Hands, the glass, turning round and the knock

The rig has channels for the glass, the screen as a pane Boop lives
behind (`glass`, how close the body is to it, and the patch where it
touches it), and for two hands, each `X`, `Y`, `Size`, `Shape` (a fist, a
ball, an open palm) and `Glass` (`render/rig/rig.h`). A face that draws
them (the gel) brings the whole body up to the glass at 1.15 its size at
most. A `turn` channel (thousandths of a whole turn) moves only the face
round the gel's dome: half a turn is its back, a whole one a spin.

While something needs you the gel's fist knocks on the glass, the same
move for every mood; if nobody comes it climbs in three more steps to its
forehead on the glass. Whether the climb follows the knock at once or
after a wait is one constant in the pack (slimegen's `scenes.mjs`,
`knock`). The knock's sound and the needs-you card's ring keep their
place; the body no longer dips.

`dbg.clip` plays one of the pack's rig clips by its id over what shows
(`{"t":"dbg.clip","name":"flop"}`), for scenarios and the Studio: the
gel's flop of relief, which a fix's Moment plays by its `clip`, and its
meme faces' moves (`face-deadpan`…). A clip may be another's move at a
size and a pace (`of`, `size` and its own `ms`, characters/CHARACTER.md
§15): the mixer and the gel's moves read a track through `Clip::value`,
which scales its values and its time, and `rig::crossed` its cues.

The gel runs a motion layer under every clip (motion V2: the slime's
`CONTINUITY.md`, The motion layer): stretch with speed, overshoot and
settle, the crown's drag, the face's lag and the hands following.
`dbg.motion` turns one of its rules off or on by name, or every one with
`"all"` (`{"t":"dbg.motion","rule":"face","on":false}`), until the next
reset, so each can be judged on the board; it answers `ok: false` for a
rule the face hasn't.

## Known quirks

- **Blank screen:** usually wrong panel settings or pins.
  Check inversion, colour order and the SPI pins first.
- **Touch does nothing:** wrong pins, no calibration, or touch sharing the
  screen's bus.
- **A tap or a stroke does nothing:** it started off the body, on the
  screen beside it (`render::Face::bodyAt`, a finger's width round the
  body as drawn, never in the bar under the desk, `render::Face::barTop`).
  Off the body a tap is nothing, but in the bar's left or right third with
  several agents, and a move a swipe, which switches agent with several and
  does nothing with one. `touch.last` in
  `internal/tools/boopctl state` says where the last touch went down,
  whether that was on the body (`body`), what it was and how long it took.
- **A swipe up doesn't open the agents' drawer (gel):** it must start in
  the bar under the desk (`render::Face::barTop`, the gel's `kDeskRow`,
  canvas rows from 179 down), and go up `kDrawerPullPx` (22 canvas px)
  before it goes as far across, while the Mac has sessions to list; one
  that goes further across first is a swipe between agents, and one that
  starts on the body is a stroke. `dbg.state`'s
  `drawer.open` says how far open it is, 0 to 1000, and `drawer.scroll`
  and `drawer.skip` how far its rows are scrolled (canvas px) and where
  the Mac's window of them starts.
- **One press, several pokes:** a firm finger bounces on the AMOLED's
  panel, the chip reporting a lift and a new touch while it stays down.
  The board takes a touch that goes down within 300 ms of the last lift,
  and within 40 canvas px of where that one was, as the same press, and it
  sends nothing more (`app/touch_gesture.h`'s `kBounceMs` and `kBouncePx`:
  the device, not the chip's driver, decides, since holding a lift that
  long there would hold back every tap). `touch.last.was` says `bounce`.
  Two taps at one spot closer than that are one poke.
- **The Mac thinks Boop is face down:** lying face down, the board says
  so (`gesture facedown`) after its `hello` to every Mac that greets it
  anew (`Device::greeted`); face up, it says it's back up (`peekaboo`) to a
  Mac it last told face down. Turn it over and back to tell it again.
- **A hold doesn't dismiss the needs-you screen:** the finger must stay
  down a second inside a spot 40 px wide each way
  (`app/touch_gesture.h`'s `kHoldMs` and `kHoldSpotPx`). Let go sooner,
  it sends nothing; only a touch shorter than 300 ms
  (`app/device.h`'s `kNeedsYouTapMs`) is the tap that opens the thread.
- **Boop is silent, faces fine:** the popover says "No voice", and
  `ping`'s `card` says why. `no card`: the card is out, or exFAT (cards
  over 32 GB come that way; format it FAT32). `no pack`, no voice file: copy the character
  pack's `voice/voice.bin` onto the card as `boop/voice.bin`. Press the
  board's reset button once the card is back in.
- **A touch doesn't answer the invite:** it was the other kind (a tap on
  one that wants a stroke), or, with several agents, a quick stroke that
  started off the body, which is a swipe between them;
  `dbg.state`'s `invite.stage` says whether it was still waiting.
- **Download mode:** hold BOOT while pressing RESET. Normal flashing
  doesn't need it.
