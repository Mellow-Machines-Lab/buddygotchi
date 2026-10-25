# Boop's agent tooling: the builds agents and tests use, the tests, the
# simulator's checks and the device tools. The owner needn't read it. Run
# them as `make -C internal <target>` from the repo root. Every recipe runs
# from the repo root, so the paths below are the same as in the root
# Makefile. See internal/VERIFICATION.md §2.
.PHONY: build app simulator check test tools faces fw fw-test sim sim-test mirror e2e tools-test eval-pixel

ROOT := $(abspath ..)
PIO := firmware/tools/pio.sh

# The whole package in one `swift build`: the Mac app, boopdev and the
# BoopTests runner, whose main is generated first; then agent-hooks' hook
# client, agent-hook, which the app copies from next to it, MellowHarness'
# tools, mellowharness-emit and beacon (mellowharness/README.md), and LinkKit's USB
# bridge, linkkit-bridge, and its flasher, linkkit-flash (linkkit/README.md).
# SWIFT_CHECK makes importing a target that isn't a declared dependency an
# error, not a warning, so app/ can't reach internal/ code (internal/README.md).
# `test` runs this target, then the tests. Both targets first stage the
# chosen character pack for the app to bundle (characters/charactergen.py
# --stage, characters/CHARACTER.md §2).
SWIFT_CHECK := --explicit-target-dependency-import-check error
build:
	cd $(ROOT) && python3 characters/charactergen.py --stage
	cd $(ROOT) && python3 internal/app/tools/gen-test-runner.py
	cd $(ROOT) && swift build $(SWIFT_CHECK)
	cd $(ROOT) && for product in agent-hook mellowharness-emit beacon linkkit-bridge linkkit-flash; do \
	  swift build $(SWIFT_CHECK) --product $$product || exit 1; \
	done

# The Mac app, the agent-hook it copies from next to it and boopdev, without
# the tests' generated runner, which is most of `build`'s time after a
# change to what BoopKit declares. The root `make dev` builds with it.
app:
	cd $(ROOT) && python3 characters/charactergen.py --stage
	cd $(ROOT) && swift build $(SWIFT_CHECK) --product Boop
	cd $(ROOT) && swift build $(SWIFT_CHECK) --product agent-hook
	cd $(ROOT) && swift build $(SWIFT_CHECK) --product boopdev  # the doctor skill checks the hooks with it

# The board in a browser on this Mac, alone (simulator/README.md): the
# firmware's own code built to WebAssembly, the page that is its screen,
# finger, speaker and card, and its USB as a bridge's socket for the Mac app
# and the tools. Needs Emscripten (brew install emscripten). No Bluetooth,
# so agents may run it; the owner's `make dev` starts one beside the app.
simulator:
	cd $(ROOT) && python3 characters/charactergen.py --stage
	cd $(ROOT) && simulator/web/build.sh
	cd $(ROOT) && python3 simulator/web/serve.py

# Every check that needs no board, camera or Jev key, one after another:
# the Swift tests, the firmware's, the tools', the simulator's scenarios
# against the goldens and the Mac's mirror of the board.
check: test fw-test tools-test sim mirror

# Swift unit tests through the XCTest shim (there's no Xcode here):
# `build` (one `swift build` of the whole package, the tests' runner
# included), then the runner. Then the own tests of agent-hooks, mellowharness
# and linkkit, which use Swift Testing and so run under `swift test`, each
# in a build folder of its own. That build now and then fails with "plugin
# for module 'TestingMacros' not found", a toolchain flake, so that
# failure alone is tried again, up to eight tries in all. One test at a
# time: MellowHarness's loop tests wait on the brain's real deadline, which
# a busy CI runner's parallel tests can starve.
SWIFT_PACKAGES := agent-hooks mellowharness linkkit

test:
	$(MAKE) build
	cd $(ROOT) && .build/debug/BoopTests
	for pkg in $(SWIFT_PACKAGES); do \
	  cd $(ROOT)/$$pkg && mkdir -p .build && for try in 1 2 3 4 5 6 7 8; do \
	    swift test --no-parallel --scratch-path .build/tests > .build/test.log 2>&1; status=$$?; cat .build/test.log; \
	    [ $$status -eq 0 ] && break; \
	    grep -q "plugin for module 'TestingMacros' not found" .build/test.log || exit $$status; \
	    [ $$try -eq 8 ] && exit 1; \
	    echo "$$pkg: the TestingMacros flake; trying again"; \
	  done; \
	done

# Pixel's own eval scenarios against Jev (L5, internal/EVALS.md §4), with
# its pack and steering, one run each. It needs BOOP_JEV_KEY.
eval-pixel:
	$(MAKE) build
	cd $(ROOT) && CHARACTER=pixel .build/debug/boopdev eval --runs 1 \
	  --scenarios characters/pixel/evals --steering characters/pixel/steering

# internal/tools/.venv with pyserial, Pillow and Textual, for boopctl.
# internal/tools/boopctl makes it through this when it's missing; this also
# refreshes it after internal/tools/requirements.txt changes. A venv that
# already works (a worktree's may be a link to the main checkout's) is
# kept, and only its packages brought up to date. The pinned Pillow and
# Textual need Python 3.10 or later, newer than the Mac's own python3.
tools: tools/.venv/.ok

tools/.venv/.ok: tools/requirements.txt
	@cd $(ROOT) && test -x internal/tools/.venv/bin/python || firmware/tools/find-python.sh >/dev/null \
	  || { echo "tools: boopctl needs Python 3.10 or later, and found none: python3 is $$(python3 --version 2>&1 | cut -d' ' -f2), and no python3.10 to python3.14 (brew install python)" >&2; exit 1; }
	cd $(ROOT) && test -x internal/tools/.venv/bin/python || { $$(firmware/tools/find-python.sh) -m venv internal/tools/.venv \
	  && internal/tools/.venv/bin/pip install --quiet --upgrade pip; }
	cd $(ROOT) && internal/tools/.venv/bin/pip install --quiet -r internal/tools/requirements.txt
	touch $@

# The device's faces, characters/pixel/firmware/include/faces.h, from the animation bank's
# designs (characters/pixel/design/boop-sound-bank-v4/, which facegen runs with
# node), checked against Chrome's drawing of them first. Rerun it when the
# bank changes, then its sounds: node characters/pixel/tools/sfxgen/sfxgen.mjs.
faces: tools
	cd $(ROOT) && internal/tools/.venv/bin/python characters/pixel/tools/facegen/facegen.py --check

# Firmware for both boards (envs cyd24 and amoled206).
fw:
	cd $(ROOT) && $(PIO) run -e cyd24 -e amoled206

# Firmware unit tests on the Mac: Boop's, with the chosen character
# pack's (which pio.sh stages), then LinkKit's device library's own
# (linkkit/device/platformio.ini).
fw-test:
	cd $(ROOT) && $(PIO) test -e native
	cd $(ROOT) && $(PIO) test -d $(ROOT)/linkkit/device -e native

# Every device scenario in the simulator, against the goldens (L1): the
# pixel face's, then the gel face's (characters/boop/tests/golden-gel/). The
# PNGs land in /tmp/boop-sim/<checkout>/<face>/<scenario>/; internal/tools/boopctl sim NAME
# [--face gel] runs one.
sim:
	cd $(ROOT) && internal/tools/boopctl sim
	cd $(ROOT) && internal/tools/boopctl sim --face gel

# The simulator (simulator/tests/): its core on the Mac in real time, with
# the test as its front end and at its serial port; then the same core as
# the browser runs it, built to WebAssembly (it needs Emscripten: brew
# install emscripten), with Pixel's pack built beside the staged one, and
# the page's USB cables.
sim-test:
	cd $(ROOT) && $(PIO) run -e native
	cd $(ROOT) && python3 -m unittest discover -s simulator/tests
	cd $(ROOT) && simulator/web/build.sh
	cd $(ROOT) && simulator/web/build.sh pixel
	cd $(ROOT) && node --test simulator/tests/*.test.mjs

# The Mac's mirror of the board (characters/CHARACTER.md §9): its page's
# own tests, then every gel scenario played on it and on the native
# simulator, each shot the same on both, pixel for pixel, then its
# board.js built again and checked to be the one checked in (it needs
# Emscripten and Node).
mirror:
	cd $(ROOT) && node --test characters/boop/tests/mirror/page.test.mjs
	cd $(ROOT) && internal/tools/boopctl mirror
	cd $(ROOT) && firmware/tools/mirror.sh --check

# Hook → app → USB → device pipeline check (L4), on the board over USB.
e2e:
	$(MAKE) build
	cd $(ROOT) && internal/tools/boopctl e2e

# The tools' own tests, with no board or camera: boopctl's commands (the
# working day's script and report among them, the takes they read from
# the voice pack, and a reference cut into frames with ffmpeg), the
# fluidity measure, the webcam recorder on synthetic video, charactergen's
# staging and studio rules (internal/characters/), the studio's own logic
# and server (with Node), and each character pack's own (its tests/tools/).
tools-test: tools
	cd $(ROOT) && internal/tools/.venv/bin/python -m unittest discover -s internal/tools/boopctl_lib/tests
	cd $(ROOT) && internal/tools/.venv/bin/python -m unittest discover -s internal/tools/fluid/tests
	cd $(ROOT) && node --test characters/studio/tests/*.test.cjs
	cd $(ROOT) && python3 -m unittest discover -s internal/tools/webcam/tests
	cd $(ROOT) && python3 -m unittest discover -s internal/tools/session/tests
	cd $(ROOT) && python3 -m unittest discover -s internal/characters
	cd $(ROOT) && for tests in characters/*/tests/tools; do \
	  [ -d $$tests ] || continue; python3 -m unittest discover -s $$tests || exit 1; \
	done
