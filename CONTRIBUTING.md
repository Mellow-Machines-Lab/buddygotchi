# Contributing to Boop

Thanks for helping. This file is the short version; the full rules are in
[CLAUDE.md](CLAUDE.md). It's written for coding agents (`AGENTS.md` is the
same file), but every rule in it applies to people too.

## Build and test

You need macOS 15 or later and Command Line Tools 26 or later
(`xcode-select --install`; `swift --version` says 6.2 or later):
`Package.swift` asks for Swift 6.2, and the prompt's labels import
FoundationModels, which only the macOS 26 SDK has. Xcode 26 works but
isn't needed; the three packages alone need macOS 13. Flashing the board
(unless you already have PlatformIO's `pio`) and the dev tools
(`internal/tools/boopctl`: the dashboard, the day's report, the
simulator's snapshots) also need a newer Python than the Mac's own
(`brew install python`; [firmware/README.md](firmware/README.md#build-and-flash)). The simulator's page and the Mac's mirror of
the board also need Emscripten, to build the firmware for a browser (the
mirror is checked in, so it's rebuilt only when what the board draws
changes), and Node, to test them (`brew install emscripten node`). Making the faces again
(`make -C internal faces`) needs Node and Google Chrome, and takes
several minutes. The first firmware build downloads the ESP32 toolchain
into the checkout, which takes about five minutes.

`agent-hooks/` and `mellowharness/` are submodules, each a repository
of its own: clone with `--recurse-submodules`, or run
`git submodule update --init` in a clone or worktree that has them
empty. A change to one of them is a pull request in its own repository
(CLAUDE.md, Repositories).

```sh
make dev                   # the debug app, with the simulator, the studio and the live dashboard
make bundle                # Boop.app as it ships, in .build/Boop.app
make -C internal build     # the Mac app, the dev tools and the hook client
make -C internal check     # every check that needs no board: the Swift, firmware and tools' tests, the goldens, the mirror
make -C internal test      # Boop's Swift tests, then each package's
make -C internal sim-test  # the simulator: its core on the Mac, and in a browser's WebAssembly
```

The root `Makefile` has only what you run day to day; everything else,
the tests and the tools agents use to check their work, is in
`internal/` ([internal/README.md](internal/README.md)).

One thing that will surprise you:

- **Jev runs (`make eval`) need your own key** in `BOOP_JEV_KEY`.
  `--brain scripted` runs the whole pipeline without one. To use the key
  you saved in Boop's Settings:

  ```sh
  BOOP_JEV_KEY=$(security find-generic-password -s com.boopcomputer.boop -a jev -w) make eval
  ```

## Debugging and evals

| To | Run |
| --- | --- |
| Run Boop and print everything it sees and decides, with the simulator, the studio and the live dashboard open | `make dev` |
| Go through the first launch's onboarding again, without touching your Boop | `make dev FRESH=1` |
| See what it did on a day, and why (`--date YYYY-MM-DD`) | `internal/tools/boopctl day --state-dir ~/Library/Application\ Support/Boop-dev` |
| Check the brain against the eval scenarios (needs `BOOP_JEV_KEY`, above) | `make eval` |

`make dev` runs the debug app on a folder of its own,
`~/Library/Application Support/Boop-dev`, beside your everyday Boop: it
hears your agents' hooks too (the everyday Boop installs them; this one
never changes them, nor the login item), and keeps a Jev key of its own,
which you give it once in its Settings. It starts on your board over
Bluetooth; while the simulator runs, its Settings shows a **Simulator**
row, where **Use it** switches to the board in your browser and **Use
the board** switches back. Only one Boop can have the board, so use the
simulator or quit the everyday Boop. Ctrl-C stops the app, the simulator
and the dashboard.

The dashboard shows the face, Boop's mood, its automatic reactions and the
ones Jev decided, and can force any mood or reaction. `b` saves a bug
report, as the popover's ladybug does, and with Boop on the simulator a
report gets the board's screen too.

How each level of checking works, from unit tests to the board, is in
[internal/VERIFICATION.md](internal/VERIFICATION.md).
