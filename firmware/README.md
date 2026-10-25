# Boop's firmware

The board is Boop's body: it draws the face, plays the sounds, lights the
LED and reports taps, over Bluetooth or USB. It's Boop's app on LinkKit's
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
rebuilds nothing that hasn't changed. Boop's draws the pixel face on the CYD and the gel slime
on the AMOLED; Pixel's names only the CYD, so built with Pixel the
AMOLED's build stops at the start and says so.

Under the faces, `src/render/` is portable C++ with no display library,
which the boards, the native simulator and the WebAssembly one all
build. Its `rig/` is the engine both faces are moving onto: the rig's
channels, the types of a pack's tables, the ramp its fades ease on and
the anchors a face reports (`rig.h`), and the mixer that plays a mood's
styles, a look and reactions into the channels each frame (`mixer.h`).
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

`make bundle` builds both boards' firmware into `Boop.app`, packed by
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
| Motion | QMI8658 on I2C (0x6B, else 0x6A) | Picked up, put down, shaken, a thump on the desk, face down (do not disturb) and up: `app/motion_gesture.h`'s first guesses, read every 20 ms at ±4 g (`amoled206/imu.cpp`). Its z is flipped to point out of the screen (`kFlipZ`: the chip reads about −1 g resting screen up); x and y are still a guess. Check them on the board, where `dbg.state`'s `imu` is the reading now (`internal/tools/boopctl state`) and `dbg.imu` stands in for the sensor. The CYD has no motion sensor |

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
   how long it took and what the board made of it, `touch.last`),
   the LED and the amp, and `ping` shows Bluetooth advertising and
   whether the voice is on the card. Presses, the speaker and the LED's
   glow need a person.

How every check works is in [internal/VERIFICATION.md](../internal/VERIFICATION.md).

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
  `kDrawerFromY`, canvas rows from 205 down), and go up `kDrawerPullPx`;
  one that starts on the face is the face's swipe. `dbg.state`'s
  `drawer.open` says how far open it is, 0 to 1000, and `drawer.scroll`
  and `drawer.skip` how far its rows are scrolled (canvas px) and where
  the Mac's window of them starts.
- **A hold doesn't dismiss the needs-you screen:** the finger must stay
  down a second inside a spot 24 px wide each way
  (`app/touch_gesture.h`'s `kHoldMs` and `kHoldSpotPx`). On the CYD,
  press firmly: a touch with no reading for 50 ms has let go, and its
  release is a tap.
- **Boop is silent, faces fine:** the popover says "No voice", and
  `ping`'s `card` says why. `no card`: the card is out, or exFAT (cards
  over 32 GB come that way; format it FAT32). `no pack`, no voice file: copy the character
  pack's `voice/voice.bin` onto the card as `boop/voice.bin`. Press the
  board's reset button once the card is back in.
- **Backlight flickers:** unstable USB power, or PWM under 5 kHz.
- **Download mode:** hold BOOT while pressing RESET. Normal flashing
  doesn't need it.
