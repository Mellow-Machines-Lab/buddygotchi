# Boop v1. Run from the repo root. See README.md and internal/VERIFICATION.md.
# The development targets (tests, simulator, tools) are in internal/Makefile:
# make -C internal <target>.
.PHONY: build app run debug dash day simulator flash eval clean

PIO := firmware/tools/pio.sh

# The whole package in one `swift build`: the Mac app, boopdev and the
# BoopTests runner, whose main is generated first; then agent-hooks' hook
# client, agent-hook, which the app copies from next to it, MellowHarness'
# tools, mellowharness-emit and beacon (mellowharness/README.md), and LinkKit's USB
# bridge, linkkit-bridge (linkkit/README.md).
# SWIFT_CHECK makes importing a target that isn't a declared dependency an
# error, not a warning, so app/ can't reach internal/ code (internal/README.md).
# `make -C internal test` runs this target, then the tests. Both targets
# first stage the chosen character pack for the app to bundle
# (characters/charactergen.py --stage, characters/CHARACTER.md §2).
SWIFT_CHECK := --explicit-target-dependency-import-check error
build:
	python3 characters/charactergen.py --stage
	python3 internal/app/tools/gen-test-runner.py
	swift build $(SWIFT_CHECK)
	swift build $(SWIFT_CHECK) --product agent-hook
	swift build $(SWIFT_CHECK) --product mellowharness-emit
	swift build $(SWIFT_CHECK) --product beacon
	swift build $(SWIFT_CHECK) --product linkkit-bridge

# The Mac app, the agent-hook it copies from next to it and boopdev, without
# the tests' generated runner, which is most of `build`'s time after a
# change to what BoopKit declares.
app:
	python3 characters/charactergen.py --stage
	swift build $(SWIFT_CHECK) --product Boop
	swift build $(SWIFT_CHECK) --product agent-hook
	swift build $(SWIFT_CHECK) --product boopdev  # the doctor skill checks the hooks with it

# The Mac app with Bluetooth. The owner runs this, not agents. Builds the
# app, then starts the binary: `swift run` would check the build all over
# again.
run: app
	.build/debug/Boop

# The same, printing everything to this terminal as it happens: hooks, the
# core's decisions, device messages and every brain pass.
debug: app
	.build/debug/Boop --debug

# The live dashboard for the app `make debug` started.
# Run it in a second terminal.
dash:
	internal/tools/boopctl dash

# What Boop did in a day, and why, by the hour, from the logs `make debug`
# leaves. DATE=YYYY-MM-DD picks the day; the
# newest line's by default.
day:
	internal/tools/boopctl day $(if $(DATE),--date $(DATE))

# The board in a browser, on this Mac (simulator/README.md): the firmware's
# own code built to WebAssembly, the page that is its screen, finger,
# speaker and card, and its USB as a bridge's socket for the Mac app and
# the tools. Needs Emscripten (brew install emscripten). No Bluetooth.
simulator:
	python3 characters/charactergen.py --stage
	simulator/web/build.sh
	python3 simulator/web/serve.py

# The harness eval scenarios (internal/EVALS.md) against Jev, all of them with no
# request budget: the final pass (internal/EVALS.md §2 counts its requests).
# While developing, run .build/debug/boopdev eval --only TEXT instead.
# They need Jev's key in BOOP_JEV_KEY and fail without it
# (internal/VERIFICATION.md L5).
eval: build
	.build/debug/boopdev eval --no-budget

# Build and upload over USB (auto-reset, no BOOT press), for whichever
# board is plugged in; BOARD (cyd24 or amoled206) or BOOP_PORT picks one
# when it can't tell (firmware/tools/flash.sh, firmware/README.md).
flash:
	firmware/tools/flash.sh

clean:
	rm -rf .build firmware/.pio
