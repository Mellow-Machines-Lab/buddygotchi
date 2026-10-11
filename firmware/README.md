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

The make targets run PlatformIO through `firmware/tools/pio.sh`, which
keeps its packages in `firmware/.platformio-core`, inside the checkout.
It uses the `pio` on your `PATH`; without one, its first run installs
PlatformIO there too, with pip, into `firmware/.platformio-core/venv`.
Either way the ESP32 platform needs Python 3.10 or later, newer than the
Mac's own 3.9.
Each build bakes in the version from `VERSION` and the git SHA
(`firmware/tools/version.py`).

The firmware talks over USB serial at **460800 baud**, and flashing uses
the same rate: the CYD's CH340 on macOS's own driver can't do 921600.
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
board it's on.

| Part | What it is | How Boop uses it |
| --- | --- | --- |
| Chip | ESP32-S3, 8 MB PSRAM, 32 MB flash | Built as 16 MB flash (`default_16MB.csv`) |
| Screen | 2.06" AMOLED, 410×502, CO5300 on quad SPI | Held sideways, USB-C on the left |
| Touch | FT3168 on I2C (SDA 15, SCL 14, INT 38) | Read only around a touch, since it naps when idle |
| Sound | ES8311 codec over I2S, NS4150B amp (enable on 46) | 16-bit mono at 22.05 kHz |
| microSD | SPI3 (SCK 2, MOSI 1, MISO 3, CS 17) | The voice, as on the CYD |
| USB | The S3's own USB-Serial/JTAG | `/dev/cu.usbmodem*`; flashing needs no BOOT press |
| Buttons | BOOT (IO0) | The main button. No LED |

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
- **Boop is silent, faces fine:** the popover says "No voice", and
  `ping`'s `card` says why. `no card`: the card is out, or exFAT (cards
  over 32 GB come that way; format it FAT32). `no pack`: copy the character
  pack's `voice/voice.bin` onto the card as `boop/voice.bin`. Press the
  board's reset button once the card is back in.
- **Backlight flickers:** unstable USB power, or PWM under 5 kHz.
- **Download mode:** hold BOOT while pressing RESET. Normal flashing
  doesn't need it.
