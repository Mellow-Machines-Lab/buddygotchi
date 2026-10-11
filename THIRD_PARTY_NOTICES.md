# Third-party notices

Boop's own code is MIT ([LICENSE](LICENSE)); so are the three packages,
each with its own copy ([agent-hooks](agent-hooks/LICENSE),
[mellowharness](mellowharness/LICENSE), [linkkit](linkkit/LICENSE)).
The Swift packages use nothing from outside the repo. What follows is the
third-party work the firmware is built with or carries. A firmware binary
you hand to someone else should come with this file and the licences it
names.

## Carried in the repo

| What | Where | Licence |
| --- | --- | --- |
| Geist Mono, © 2023 Vercel, in collaboration with basement.studio | Rasterised into `firmware/assets/fonts.h` by `internal/tools/fontgen/` | SIL Open Font License 1.1 ([firmware/assets/OFL.txt](firmware/assets/OFL.txt)) |
| The recorded voice, 2,722 takes generated with ElevenLabs' text-to-speech, then trimmed and shaped for the board's speaker | `characters/pixel/voice/voice.bin`, with its table, `characters/pixel/mac/takes.tsv` | MIT, with the rest of the repo. The recordings they were built from aren't in it |

## Linked into the firmware

PlatformIO fetches these at build time, at the versions
`firmware/platformio.ini` pins; none are copied into the repo.

| Library | Licence | Notes |
| --- | --- | --- |
| [Arduino core for the ESP32](https://github.com/espressif/arduino-esp32) (pioarduino `platform-espressif32` 55.03.39) | LGPL-2.1 | Linked statically. The firmware's source and build steps are in this repo (`firmware/`, [its README](firmware/README.md)), so anyone can relink it against a changed core, as the LGPL asks |
| [ESP-IDF](https://github.com/espressif/esp-idf), under the core | Apache-2.0 | Its own components carry their licences and NOTICE |
| [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) 2.5.1 | Apache-2.0 | Ships a NOTICE file, which a binary release passes on; it includes TinyCrypt (BSD-3-Clause) |
| [LovyanGFX](https://github.com/lovyan03/LovyanGFX) 1.2.32 | FreeBSD (BSD-2-Clause), with parts under BSD and MIT from Adafruit GFX and TFT_eSPI | Not built for the native tests |
| [ArduinoJson](https://github.com/bblanchon/ArduinoJson) 7.4.3 | MIT | Also used by LinkKit's device library |
| [Unity](https://github.com/ThrowTheSwitch/Unity) 2.6.1 | MIT | Tests only, never in the firmware |

## Register settings from vendor drivers

The AMOLED board's audio codec (ES8311) and screen (CO5300) are set up
with the register values and timings from Espressif's ES8311 driver
(Apache-2.0) and Waveshare's driver for the board. The code that writes
them is Boop's own (`firmware/src/board/amoled206/`).

## Names

Claude and Claude Code are trademarks of Anthropic; Codex is a trademark
of OpenAI. Boop works with them but isn't made or endorsed by either.
