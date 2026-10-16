# Contributing to Boop

Thanks for helping. This file is the short version; the full rules are in
[CLAUDE.md](CLAUDE.md). It's written for coding agents (`AGENTS.md` is the
same file), but every rule in it applies to people too.

## Build and test

You need macOS 26 or later and Command Line Tools. Xcode works but isn't
needed; the three packages alone need macOS 13. Flashing the board
(unless you already have PlatformIO's `pio`) and the dev tools
(`internal/tools/boopctl`: the dashboard, `make day`, the simulator's
snapshots) also need a newer Python than the Mac's own
(`brew install python`; [firmware/README.md](firmware/README.md#build-and-flash)). The simulator's page also needs Emscripten, to
build the firmware for a browser, and Node, to test it
(`brew install emscripten node`). Making the faces again
(`make -C internal faces`) needs Node and Google Chrome, and takes
several minutes. The first firmware build downloads the ESP32 toolchain
into the checkout, which takes about five minutes.

`agent-hooks/` and `mellowharness/` are submodules, each a repository
of its own: clone with `--recurse-submodules`, or run
`git submodule update --init` in a clone or worktree that has them
empty. A change to one of them is a pull request in its own repository
(CLAUDE.md, Repositories).

```sh
make build                 # the Mac app, the dev tools and the hook client
make -C internal test      # Boop's Swift tests, then each package's
make -C internal fw-test   # the firmware's and LinkKit's device tests, on the Mac
make -C internal sim       # the firmware's drawing, as PNGs, against the goldens
make -C internal sim-test  # the simulator: its core on the Mac, and in a browser's WebAssembly
```

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
| Run Boop and print everything it sees and decides | `make debug` |
| Watch and poke it live, in a second terminal beside `make debug` | `make dash` |
| See what it did on the latest day `make debug` logged, and why (`DATE=YYYY-MM-DD` for another) | `make day` |
| Check the brain against the eval scenarios (needs `BOOP_JEV_KEY`, above) | `make eval` |

The dashboard shows the face, Boop's mood, its automatic reactions and the
ones Jev decided, and can force any mood or reaction.

How each level of checking works, from unit tests to the board, is in
[internal/VERIFICATION.md](internal/VERIFICATION.md).
