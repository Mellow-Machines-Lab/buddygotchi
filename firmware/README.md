# Boop's firmware

The board is Boop's body: it draws the face, plays the sounds, lights the
LED and reports touches, over Bluetooth or USB. It's Boop's app on LinkKit's
device library (`linkkit/device/`), built with PlatformIO for two boards.
How it fits with the Mac is in
[architecture.html](../documentation/architecture.html).

## Build and flash

```sh
make -C internal fw          # build the firmware for both boards (envs cyd24 and amoled206)
make flash                   # build and upload over USB, for whichever board is plugged in
make -C internal fw-test     # the firmware's unit tests on the Mac (env native)
make -C internal sim         # every scenario in the simulator, against the goldens
internal/tools/boopctl ping  # firmware version and SHA, why it last restarted, uptime, heap, fps, link
```

A loop that stops coming round for 5 seconds restarts the board (the
core's task watchdog, on from the end of setup). Its `hello` and
`ping` say why it last restarted in `reset`: `power`, `button`,
`software`, `usb`, or trouble, `panic`, `watchdog`, `brownout` or
`other`, which the Mac's `boop.log` notes.

`make flash` runs `firmware/tools/flash.sh`, which tells the boards apart
by their port: `/dev/cu.usbserial-*` or `/dev/cu.wchusbserial*` is the CYD
(env `cyd24`), `/dev/cu.usbmodem*` the AMOLED board (env `amoled206`).
With more than one board plugged in it stops and lists them; `BOOP_PORT=…`
or `BOARD=cyd24`/`BOARD=amoled206` picks one.

A character pack says which of its faces each board draws (its
`faces`, by the env's `custom_board`; [CHARACTER.md](../characters/CHARACTER.md)
§9), and `firmware/tools/pack_face.py` builds that face and none of the
pack's others, into the env's own build folder, so switching boards
rebuilds nothing that hasn't changed. Boop's draws the gel slime on the
AMOLED alone, and Pixel's the pixel face on the CYD alone, so a board
built with the other's pack stops at the start and says so. `make flash`
builds with the chosen pack, so choose the one for the board
([CHARACTER.md](../characters/CHARACTER.md) §2).

Under the faces, `src/render/` is portable C++ with no display library,
which the boards, the native simulator and the WebAssembly one all
build. Its `rig/` is the engine both faces are moving onto: the rig's
channels, the types of a pack's tables, the ramp its fades ease on and
the anchors a face reports (`rig.h`), and the mixer that plays a mood's
styles, a look and Moments' clips into the channels each frame (`mixer.h`).
Staging writes the pack's rig as `rig_tables.h`
([CHARACTER.md](../characters/CHARACTER.md) §15). The pixel face draws
its face from it, with its moods' own art as parts, wherever a design's
face is its mood's resting face, in the design's place
(`render/pixel/rig_face.h`), so the CYD links the mixer; the gel doesn't
use it yet.

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

The firmware talks over USB serial at **460800 baud**. The CYD flashes
at the same 460800, because its CH340 on macOS's own driver can't do
921600; the AMOLED board's native USB flashes at 921600.
Opening the port must not change DTR or RTS, or the auto-reset circuit
reboots the board; `boopctl` leaves them alone.

### Updating from the app

`make bundle` builds the firmware for each board the chosen pack has a
face for into `Boop.app` (a board it has none for isn't offered an
update), packed by
`firmware/tools/package.py` with a manifest of the board, its chip and
flash, the version and SHA, and where each image goes, read from the
board's own partition table. A board's `hello` names it (`board`, its
env); from firmware before that, its face does, since only the AMOLED
draws the gel. When the board runs an older version than the app
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

## The boards

### The Cheap Yellow Display (env `cyd24`)

MicroTech **MTR024QV01A-V1** (SKU E32R24P), a 2.4" "Cheap Yellow Display":
an ESP32 module, screen, touch, audio amp, RGB LED and LiPo charger on one
board. Its pins are in `src/board/cyd24/config.h`.

| Part | What it is | How Boop uses it |
| --- | --- | --- |
| Module | ESP32-WROOM-32E, dual-core at 240 MHz, 520 KB SRAM, **no PSRAM**, 4 MB flash | RAM is the tightest limit |
| Radio | Wi-Fi and Bluetooth 4.2 | BLE only; Wi-Fi stays off |
| Screen | 2.4" IPS TFT, 240×320, ST7789 on SPI2 (clock 14, MOSI 13, CS 15, DC 2) | Used sideways, as 320×240; backlight on GPIO21, PWM |
| Touch | Resistive XPT2046 on its own pins (25, 32, 39, 33; interrupt 36) | Bit-banged SPI; needs a firm press |
| Audio | 8-bit DAC on GPIO26 → amp (enable on 4, low is on) → speaker header | An 8 Ω, 1–2 W speaker on the header |
| Light | RGB LED, common anode, on 22, 16, 17 (active low) | On the back, so it shows as a glow |
| Buttons | BOOT (IO0) and RESET | BOOT is the main button |
| USB | USB-C with a CH340 USB-serial bridge and auto-reset | `/dev/cu.usbserial-*`; flashing needs no BOOT press |
| microSD | SPI3 (clock 18, MISO 19, MOSI 23, CS 5) | Boop's voice, every recorded take in one file. Use a FAT32 card |

Touch must stay off the screen's SPI bus. Pins 34, 35, 36 and 39 are
input-only with no pull-ups, so a button added on IO35 needs an external
one.

### The AMOLED board (env `amoled206`)

Waveshare **ESP32-S3-Touch-AMOLED-2.06**, a watch-style board, runs the
same app with its own pins, screen, touch, sound and start-up in
`src/board/amoled206/`. Nothing outside the two board folders knows which
board it's on. Its face is the gel slime, so it needs Boop's pack (above).

| Part | What it is | How Boop uses it |
| --- | --- | --- |
| Chip | ESP32-S3, 8 MB PSRAM, 32 MB flash | Built as 16 MB flash (`default_16MB.csv`). The loop runs on core 1; core 0 sends each frame to the screen (`amoled206/display.cpp`) and draws the lower rows of the next one's body while the loop draws the upper (`amoled206/helper.cpp`, `render/helper.h`). The gel's material, 1 MB read a texel a pixel, is copied into PSRAM at start (`Hal::quickerCopy`): the cache fills from there faster than from flash |
| Screen | 2.06" AMOLED, 410×502, CO5300 on quad SPI | Held sideways, USB-C on the left. Its corners are rounded, about 110 px in radius, and show nothing there (`kNativeCorner`, measured from a photo of the board): a native face keeps its lane clear of them (`render::Surface::inset`) |
| Touch | FT3168 on I2C (SDA 15, SCL 14, INT 38) | Read only around a touch, since it naps when idle. A touch ends as soon as the chip reports the finger lifted (no point, or its lift-up event), not 50 ms after the last reading; `internal/tools/boopctl state`'s `touch.lifts` counts those reports. It reads in the panel's own pixels, x along its 410 side and y along its 502, as Waveshare's own example hands them to LVGL unturned; `amoled206/hal.cpp` turns them onto the canvas as the picture is turned. Not yet checked under a finger: held sideways, USB-C on the left, swipe down once, then run `internal/tools/boopctl state`: `touch.last` should go `from` a smaller y `to` a larger one with x about the same, and a swipe right should raise x. If not, the map in `hal.cpp` is the one to fix |
| Sound | ES8311 codec over I2S, NS4150B amp (enable on 46) | 16-bit mono at 22.05 kHz |
| microSD | SPI3 (SCK 2, MOSI 1, MISO 3, CS 17) | The voice, as on the CYD |
| USB | The S3's own USB-Serial/JTAG | `/dev/cu.usbmodem*`; flashing needs no BOOT press |
| Buttons | BOOT (IO0) | The main button. No LED |
| Motion | QMI8658 on I2C (0x6B, else 0x6A) | Picked up, put down, shaken, a thump on the desk, face down (do not disturb: no `say` and none of the face's sounds) and up: `app/motion_gesture.h`'s first guesses, read every 20 ms at ±4 g (`amoled206/imu.cpp`). The same readings give the steady tilt the face sloshes by (`app::Tilt`, `dbg.state`'s `tilt`; `kAcross` says which way x runs). Its z is flipped to point out of the screen (`kFlipZ`: the chip reads about −1 g resting screen up); x and y are still a guess. Check them on the board, where `dbg.state`'s `imu` is the reading now (`internal/tools/boopctl state`) and `dbg.imu` stands in for the sensor. The CYD has no motion sensor |

Waveshare's example repo (`waveshareteam/ESP32-S3-Touch-AMOLED-2.06`) has
a recovery image in `FirmWare/` if you ever need the factory firmware back.

### The boards with no hardware

Two more folders in `src/board/` are boards on a computer, which neither
board's env builds:

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
  `tools/mirror.sh --check` builds it again and checks it's the one
  checked in.

## Bringing up a board

1. **Backlight:** a dark screen right after flashing almost always means
   GPIO21 (on the CYD) was never driven high.
2. **Test pattern:** `internal/tools/boopctl play pattern` shows six colour
   blocks, labelled corners, a big UP arrow and a black bar down the USB-C
   edge. Upright, the arrow is at the top; the colours confirm inversion
   and colour order.
3. **Screenshot:** `internal/tools/boopctl shot` matches the simulator
   pixel for pixel.
4. **The rest:** `internal/tools/boopctl state` reports BOOT, raw touch
   (and the last touch on the canvas: where it went down and was last,
   how long it took and what the board made of it, `touch.last`, and how far
   the face leans into a finger at rest, `touch.lean`),
   the LED and the amp, and `ping` shows Bluetooth advertising and
   whether the voice is on the card. Presses, the speaker and the LED's
   glow need a person.

How every check works is in [internal/VERIFICATION.md](../internal/VERIFICATION.md).

## The invite

After a skit the Mac may send a `do` with an `invite` (`app/behaviour.h`,
`InviteIn`): Boop asks for one touch, and the touch pays off. Only a board
whose face draws invites gets one: its `hello` says `"invites":1`
(`render::Face::drawsInvites`). The gel does; Pixel doesn't, and plays a
`do`'s invite not at all.

1. The `do`'s face, words and sign play as ever.
2. Once none of them plays, the pose: Boop comes up to the glass, the place
   to touch glowing, the `label`'s word by it.
3. The wait, the invite's `ms` (1 to 30 s, 4 s with none). A touch of its
   kind answers it: a `tap` is a tap, a boop on the nose or a tickle (BOOT
   too, when it would poke); a `stroke` is a stroke, a ruffle or a finger
   the face leaned into. That touch is the invite's: no `ev tap` or
   `ev gesture` and no poke. Any other touch is what it always is.
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
round the gel's dome: half a turn is its back, a whole one a spin. Pixel's
draws none of them.

While something needs you the gel's fist knocks on the glass, the same
move for every mood; if nobody comes it climbs in three more steps to its
forehead on the glass. Whether the climb follows the knock at once or
after a wait is one constant in the pack (slimegen's `scenes.mjs`,
`knock`). The knock's sound and the needs-you card's ring keep their
place; the body no longer dips.

`dbg.clip` plays one of the pack's rig clips by its id over what shows
(`{"t":"dbg.clip","name":"flop"}`), for scenarios and the Studio: the
gel's flop of relief, which no Moment names yet, and its meme faces'
moves (`face-deadpan`…).

The gel runs a motion layer under every clip (motion V2: the slime's
`CONTINUITY.md`, The motion layer): stretch with speed, overshoot and
settle, the crown's drag, the face's lag and the hands following.
`dbg.motion` turns one of its rules off or on by name, or every one with
`"all"` (`{"t":"dbg.motion","rule":"face","on":false}`), until the next
reset, so each can be judged on the board; it answers `ok: false` for a
rule the face hasn't.

## Known quirks

- **Blank screen but backlight on:** usually wrong panel settings or pins.
  Check inversion, colour order and the SPI pins first.
- **Touch does nothing:** wrong pins, no calibration, or touch sharing the
  screen's bus.
- **A stroke plays nothing on the gel:** it let go too quickly, a swipe,
  which the dome only flings on (`app/touch_gesture.h`'s `kSwipePxPerS`,
  of its speed as it lets go); stroke slower. `touch.last` in `internal/tools/boopctl state` says what the
  last touch was and how long it took.
- **A swipe up doesn't open the agents' drawer (gel):** it must start on
  the strip, the bottom rows of the screen (`app/device.h`'s
  `kDrawerFromY`, canvas rows from 205 down), and go up `kDrawerPullPx`
  (22 canvas px), while the Mac has sessions to list;
  one that starts on the face is the face's swipe. `dbg.state`'s
  `drawer.open` says how far open it is, 0 to 1000, and `drawer.scroll`
  and `drawer.skip` how far its rows are scrolled (canvas px) and where
  the Mac's window of them starts.
- **A hold doesn't dismiss the needs-you screen:** the finger must stay
  down a second inside a spot 40 px wide each way
  (`app/touch_gesture.h`'s `kHoldMs` and `kHoldSpotPx`). Let go sooner,
  it sends nothing; only a touch shorter than 300 ms
  (`app/device.h`'s `kNeedsYouTapMs`) is the tap that opens the thread. On
  the CYD, press firmly: a touch with no reading for 50 ms has let go.
- **Boop is silent, faces fine:** the popover says "No voice", and
  `ping`'s `card` says why. `no card`: the card is out, or exFAT (cards
  over 32 GB come that way; format it FAT32). `no pack`, no voice file: copy the character
  pack's `voice/voice.bin` onto the card as `boop/voice.bin`. Press the
  board's reset button once the card is back in.
- **A touch doesn't answer the invite:** it was the other kind (a tap on
  one that wants a stroke), or a swipe, which is too quick to be a stroke;
  `dbg.state`'s `invite.stage` says whether it was still waiting.
- **Backlight flickers:** unstable USB power, or PWM under 5 kHz.
- **Download mode:** hold BOOT while pressing RESET. Normal flashing
  doesn't need it.
