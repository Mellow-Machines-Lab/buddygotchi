# Internal code

Agent tooling: the owner doesn't need to read this folder or learn its
commands. What the owner runs is the root `Makefile` (`make dev`,
`make bundle`, `make flash`, `make demo`, `make eval`, `make clean`);
everything here is for agents, tests and CI, starting from
`make -C internal <target>` ([VERIFICATION.md](VERIFICATION.md) §2).

Everything in the repo that doesn't ship. What ships is in `app/` (the Mac
app and its library, BoopKit), `firmware/` (the board's firmware, its
generated assets and the scripts that build it, the Mac's mirror of the
board among them, built into the character pack's `mac/mirror/`), and three packages of
their own, each with its own tests beside its code
([documentation/architecture.html](../documentation/architecture.html#joins)): `agent-hooks/` (the hook client
and its library), `mellowharness/` (the brain's harness, `mellowharness-emit` and
its example, Beacon) and `linkkit/` (the device link: its Swift host and
the C++ device library the firmware builds). This folder has Boop's
tests, evals, dev tools and skills.

| Path | What it is |
| --- | --- |
| `app/Boop/` | `Headless.swift` and `Snapshots.swift`: the sources of `Boop --headless` and `Boop --snapshots`, which are compiled into the shipped `Boop` target |
| `app/BoopDevKit/` | A library for `boopdev` and the tests: the harness evals (`Eval/`, [EVALS.md](EVALS.md)), hook replay (`Replay.swift`) and the character pack check (`PackCheck.swift`, `boopdev check`) |
| `app/BoopDev/` | `boopdev`, the developer CLI ([VERIFICATION.md](VERIFICATION.md) §2) |
| `app/Tests/` | Boop's Swift unit tests (`BoopTests`) and their fixtures. The packages' tests are in each package, under `swift test` (`agent-hooks/Tests/`, `mellowharness/Tests/`, `linkkit/Tests/`); the hook fixtures are agent-hooks' (`agent-hooks/Tests/AgentHooksTests/Fixtures/`), and only the pipeline check's are here (`Fixtures/hooks/e2e/`) |
| `app/TestSupport/XCTestShim/` | A stand-in XCTest for Command Line Tools, which has none |
| `app/tools/` | `gen-test-runner.py`, which writes the tests' `main` for the shim (`make -C internal build` runs it) |
| `firmware/test/` | The firmware's unit tests, the simulator scenarios and their golden pictures. LinkKit's device library tests in its own project (`linkkit/device/test/`) |
| `firmware/voice_file.h` | The voice file read from the chosen character pack's `voice/voice.bin`, for the firmware's tests, which have no SD card |
| `tools/` | `dev.sh` (the root `make dev`: the debug app on its own folder, with the simulator, its page, the studio's matrix and the dashboard beside it), `appicon` (draws the app's placeholder icon, `app/Boop/AppIcon.icns`, until a designed one replaces it), `boopctl` (the board over USB, the simulator and the Mac's mirror of the board checked against it, the live dashboard, a day's summary from the debug logs, and `boopctl workday`, a scripted working day through the headless app and its brain, [EVALS.md](EVALS.md) §5), `fontgen` (the device's fonts), `mediagen` (the READMEs' GIFs and the popover's picture, each from a real run, into `documentation/media/` and the packages' `media/`), `session/` (plays a pack's demo script through the real Claude Code or Codex, with the project from `sessions/`: the replay server, the agent's terminal, the gate and the desktop app's `/demo`, `make demo IN=…`), `fluid/` (each frame's change across the everyday transitions, recorded in the simulator, by the rule the Character Studio's Transitions measures with too), and the `webcam/` recorder. `boopctl reference` takes in a reference a person gave and cuts it into frames ([characters/CHARACTER.md](../characters/CHARACTER.md) §16). The faces', sounds' and voice's generators are their character packs' (`characters/pixel/tools/`: `facegen`, `sfxgen`; `characters/boop/tools/`: `voicegen`, `slimegen`), and so are the designs they build from ([characters/CHARACTER.md](../characters/CHARACTER.md)) |
| `sessions/` | The projects a pack's demo scripts run in when a real agent plays them, for videos (`make demo IN=…`, [sessions/README.md](sessions/README.md)) |
| `characters/` | The tests of `characters/charactergen.py` (`make -C internal tools-test`, and CI): the studio lists the board's states, each once; every pack here passes the studio's rules; those rules on small made-up packs (a studio entry is optional, states match the board's, declared files exist, a preview wears only the pack's moods, and the data's paths are from the page), and every pack's moods are exactly the universal ones; a pack's rig/ (every pack here clean, a bad edit failing with its file and key, the tables written as its files say); a pack's references and review queue (every key, value and file, what each status says is there, what it became on the rig) and the studio's data from them, a board for each face among it, which a pack's own entry for it adds to; and `--stage` takes the chosen pack's own files only, with the two headers it makes |
| `skills/` | `doctor` and `webcam-verify`, linked from `.claude/skills/` and `.codex/skills/` |

## How it's wired

- **Swift.** `Package.swift` is at the repo root, because SwiftPM takes no
  target outside the package's root and the targets live in both `app/`
  and here. The production targets (`BoopKit`, `Boop`, `CBoopVersion`, and the products
  they take from the three local packages the root one depends on,
  `agent-hooks`, `mellowharness` and `linkkit`) never depend on the internal
  ones (`BoopDevKit`, `BoopDev`, `BoopTests`, `XCTest`). SwiftPM alone only warns about an import of a
  target that isn't a dependency, so `make -C internal build`, `make -C internal app` and
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
  descriptions) is linked into the `Boop` binary with `-sectcreate`;
  `make bundle` (`app/tools/bundle.sh`) builds the real `Boop.app`.
  Testability (`-enable-testing`) is for debug builds only, which the
  tests use.
- **Stable contracts.** What the parts build against, and so changes
  only with care: the common event (`app/BoopKit/Adapters/`), the
  memory file (`app/BoopKit/Memory/`), the harness's two contracts,
  events in and outputs out, and the protocol
  ([linkkit/SPEC.md](../linkkit/SPEC.md), with Boop's vocabulary in
  `app/BoopKit/DeviceLink/BoopDevice.swift`).
- **Firmware.** `firmware/platformio.ini` points its `test_dir` at
  `../.character-build/firmware-test`, which `characters/charactergen.py
  --stage` fills with links to the suites here (`firmware/test/test_*`)
  and the chosen pack's own (`tests/firmware/test_*`). The
  `native` env's `build_src_filter` adds the hosted board,
  `firmware/src/board/hosted/`, which the Mac's mirror of the board runs
  too (`[hosted]`, which `firmware/tools/wasm.sh` reads for the
  WebAssembly builds), and the simulator's core on it, `simulator/core/`
  (the filter is relative to `firmware/src/`). Both envs link LinkKit's
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

The shipping output has no runtime dependency on internal tools.
