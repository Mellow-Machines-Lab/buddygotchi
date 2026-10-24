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
internal/tools/boopctl ping  # firmware version and SHA, uptime, heap, fps, link
```

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
keeps its packages in `firmware/.platformio-core`, inside the checkout.
It uses the `pio` on your `PATH`; without one, its first run installs
PlatformIO there too, with pip, into `firmware/.platformio-core/venv`.
Either way the ESP32 platform needs Python 3.10 or later, newer than the
Mac's own 3.9.
Each build bakes in the version from `VERSION` and the git SHA
(`firmware/tools/version.py`).

The firmware talks over USB serial at **460800 baud**. The CYD flashes
at the same 460800, because its CH340 on macOS's own driver can't do
921600; the AMOLED board's native USB flashes at 921600.
Opening the port must not change DTR or RTS, or the auto-reset circuit
reboots the board; `boopctl` leaves them alone.

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
| Chip | ESP32-S3, 8 MB PSRAM, 32 MB flash | Built as 16 MB flash (`default_16MB.csv`) |
| Screen | 2.06" AMOLED, 410×502, CO5300 on quad SPI | Held sideways, USB-C on the left |
| Touch | FT3168 on I2C (SDA 15, SCL 14, INT 38) | Read only around a touch, since it naps when idle |
| Sound | ES8311 codec over I2S, NS4150B amp (enable on 46) | 16-bit mono at 22.05 kHz |
| microSD | SPI3 (SCK 2, MOSI 1, MISO 3, CS 17) | The voice, as on the CYD |
| USB | The S3's own USB-Serial/JTAG | `/dev/cu.usbmodem*`; flashing needs no BOOT press |
| Buttons | BOOT (IO0) | The main button. No LED |
| Motion | QMI8658 on I2C (0x6B, else 0x6A) | Picked up, put down, shaken, a thump on the desk, face down (do not disturb) and up: `app/motion_gesture.h`'s first guesses, read every 20 ms at ±4 g (`amoled206/imu.cpp`). Its z is flipped to point out of the screen (`kFlipZ`: the chip reads about −1 g resting screen up); x and y are still a guess. Check them on the board, where `dbg.state`'s `imu` is the reading now (`internal/tools/boopctl state`) and `dbg.imu` stands in for the sensor. The CYD has no motion sensor |

Waveshare's example repo (`waveshareteam/ESP32-S3-Touch-AMOLED-2.06`) has
a recovery image in `FirmWare/` if you ever need the factory firmware back.

## Bringing up a board

1. **Backlight:** a dark screen right after flashing almost always means
   GPIO21 (on the CYD) was never driven high.
2. **Test pattern:** `internal/tools/boopctl play pattern` shows six colour
   blocks, labelled corners, a big UP arrow and a black bar down the USB-C
   edge. Upright, the arrow is at the top; the colours confirm inversion
   and colour order.
3. **Screenshot:** `internal/tools/boopctl shot` matches the simulator
   pixel for pixel.
4. **The rest:** `internal/tools/boopctl state` reports BOOT, raw touch,
   the LED and the amp, and `ping` shows Bluetooth advertising and
   whether the voice is on the card. Presses, the speaker and the LED's
   glow need a person.

How every check works is in [internal/VERIFICATION.md](../internal/VERIFICATION.md).

## Known quirks

- **Blank screen but backlight on:** usually wrong panel settings or pins.
  Check inversion, colour order and the SPI pins first.
- **Touch does nothing:** wrong pins, no calibration, or touch sharing the
  screen's bus.
- **A hold doesn't dismiss the needs-you sign:** the finger must stay
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
