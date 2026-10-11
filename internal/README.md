# Internal code

Everything in the repo that doesn't ship. What ships is in `app/` (the Mac
app and its library, BoopKit), `firmware/` (the board's firmware, its
generated assets and the scripts that build it), and three packages of
their own, each with its own tests beside its code
([documentation/architecture.html](../documentation/architecture.html#joins)): `agent-hooks/` (the hook client
and its library), `mellowharness/` (the brain's harness, `mellowharness-emit` and
its example, Beacon) and `linkkit/` (the device link: its Swift host and
the C++ device library the firmware builds). This folder has Boop's
tests, evals, dev tools and skills.

| Path | What it is |
| --- | --- |
| `app/Boop/` | `Headless.swift` and `Snapshots.swift`: the sources of `Boop --headless` and `Boop --snapshots`, which are compiled into the shipped `Boop` target |
| `app/BoopDevKit/` | A library for `boopdev` and the tests: the harness evals (`Eval/`, [EVALS.md](EVALS.md)) and hook replay (`Replay.swift`) |
| `app/BoopDev/` | `boopdev`, the developer CLI ([VERIFICATION.md](VERIFICATION.md) §2) |
| `app/Tests/` | Boop's Swift unit tests (`BoopTests`) and their fixtures. The packages' tests are in each package, under `swift test` (`agent-hooks/Tests/`, `mellowharness/Tests/`, `linkkit/Tests/`); the hook fixtures are agent-hooks' (`agent-hooks/Tests/AgentHooksTests/Fixtures/`), and only the pipeline check's are here (`Fixtures/hooks/e2e/`) |
| `app/TestSupport/XCTestShim/` | A stand-in XCTest for Command Line Tools, which has none |
| `app/tools/` | `gen-test-runner.py`, which writes the tests' `main` for the shim (`make build` runs it) |
| `firmware/test/` | The firmware's unit tests, the simulator scenarios and their golden pictures. LinkKit's device library tests in its own project (`linkkit/device/test/`) |
| `firmware/pack_file.h` | The voice pack read from `.build/voice/voice.bin`, for the simulator and the tests, which have no SD card |
| `tools/` | `boopctl` (the board over USB, the simulator, the live dashboard, a day's summary from the debug logs, and `boopctl workday`, a scripted working day through the headless app and its brain, [EVALS.md](EVALS.md) §5), `fontgen` (the device's fonts), `mediagen` (the READMEs' GIFs and the popover's picture, each from a real run, into `documentation/media/` and the packages' `media/`), `export` (lays out the public repository without private character packs, and checks it for leaks, [characters/CHARACTER.md](../characters/CHARACTER.md) §11), and the `webcam/` recorder. The faces', sounds' and voice's generators are their character packs' (`characters/pixel/tools/`: `facegen`, `sfxgen`; `characters/boop/tools/`: `voicegen`, `slimegen`), and so are the designs they build from ([characters/CHARACTER.md](../characters/CHARACTER.md)) |
| `characters/` | The tests of `characters/charactergen.py`'s studio rules (`make -C internal tools-test`) |
| `skills/` | `doctor` and `webcam-verify`, linked from `.claude/skills/`, `.codex/skills/` and `.cursor/skills/` |

## How it's wired

- **Swift.** `Package.swift` is at the repo root, because SwiftPM takes no
  target outside the package's root and the targets live in both `app/`
  and here. The production targets (`BoopKit`, `Boop`, and the products
  they take from the three local packages the root one depends on,
  `agent-hooks`, `mellowharness` and `linkkit`) never depend on the internal
  ones (`BoopDevKit`, `BoopDev`, `BoopTests`, `XCTest`). SwiftPM alone only warns about an import of a
  target that isn't a dependency, so `make build`, `make app` and
  `make -C internal test` build with
  `--explicit-target-dependency-import-check error`, and code in
  `app/` that imports anything from here fails the build. The one
  exception is the `Boop` target: its path is the repo root and its
  sources are `app/Boop/` and `internal/app/Boop/`, so headless mode and
  snapshots are part of the app while their sources live here. Everything
  builds into `.build/` at the root. Each package's own tests run under
  `swift test` in its folder, into its own `.build/tests`, which
  `make -C internal test` runs after Boop's.
  SwiftPM builds no app bundle here, so the app's `Info.plist`
  (`LSUIElement`, and the Bluetooth, microphone and speech usage
  descriptions) is linked into the `Boop` binary with `-sectcreate`.
- **Stable contracts.** What the parts build against, and so changes
  only with care: the common event (`app/BoopKit/Adapters/`), the
  memory file (`app/BoopKit/Memory/`), the harness's two contracts,
  events in and actions out, and the protocol
  ([linkkit/SPEC.md](../linkkit/SPEC.md), with Boop's vocabulary in
  `app/BoopKit/DeviceLink/BoopDevice.swift`).
- **Firmware.** `firmware/platformio.ini` points its `test_dir` here, and
  the `native` env's `build_src_filter` adds the simulator's core,
  `simulator/core/` (the filter is relative to `firmware/src/`). Both envs link LinkKit's
  device library, `linkkit/device/`, through `lib_deps`
  (`symlink://../linkkit/device`), so the tests and the simulator run the
  same kit as the board. The library's own tests are in its folder, with
  a PlatformIO project of their own (`linkkit/device/platformio.ini`),
  which `make -C internal fw-test` runs after Boop's.
- **Tools.** Scripts find the repo root from their own path. `boopctl`
  keeps its Python in `internal/tools/.venv` (`make -C internal tools`), and the
  webcam recorder builds into `internal/tools/webcam/.build`, apart from
  SwiftPM's `.build/`.

`internal/Makefile` has the development targets; run them from the repo
root as `make -C internal <target>`. They are listed in
[VERIFICATION.md](VERIFICATION.md) §2.

`tools/slimegen/slimegen.mjs` generates the opt-in host graph (into Boop's character pack), bundled Mac mirror and native gel catalogs from the slime
catalog (`--check` checks freshness). The shipping output has no runtime
dependency on internal tools; see [verification](VERIFICATION.md).

The integer gel engine is checked with
`python3 characters/boop/tools/slimegen/check-port.py --output /tmp/boop-gel-port`.
Its native JSON adapter lives in `characters/boop/tools/gel-trace/` and never ships.
`internal/tools/boopctl sim --face gel` checks the separate gel goldens;
`--face pixel` checks the unchanged pixel set. See [VERIFICATION.md](VERIFICATION.md) for
on-board checks and the limits of native evidence.
