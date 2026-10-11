# Boop's development targets: tests, the simulator and the device tools.
# Run them as `make -C internal <target>` from the repo root. Every recipe
# runs from the repo root, so the paths below are the same as in the root
# Makefile. See internal/VERIFICATION.md §2.
.PHONY: test tools faces fw fw-test sim sim-test demo e2e tools-test

ROOT := $(abspath ..)
PIO := firmware/tools/pio.sh

# Swift unit tests through the XCTest shim (there's no Xcode here): the
# root `build` (one `swift build` of the whole package, the tests' runner
# included), then the runner. Then the own tests of agent-hooks, mellowharness
# and linkkit, which use Swift Testing and so run under `swift test`, each
# in a build folder of its own. That build now and then fails with "plugin
# for module 'TestingMacros' not found", a toolchain flake that passes
# when run again, so that failure alone is tried again, up to seven times
# (it has failed five times running for one package).
SWIFT_PACKAGES := agent-hooks mellowharness linkkit

test:
	$(MAKE) -C $(ROOT) build
	cd $(ROOT) && .build/debug/BoopTests
	for pkg in $(SWIFT_PACKAGES); do \
	  cd $(ROOT)/$$pkg && mkdir -p .build && for try in 1 2 3 4 5 6 7 8; do \
	    swift test --scratch-path .build/tests > .build/test.log 2>&1; status=$$?; cat .build/test.log; \
	    [ $$status -eq 0 ] && break; \
	    grep -q "plugin for module 'TestingMacros' not found" .build/test.log || exit $$status; \
	    [ $$try -eq 8 ] && exit 1; \
	    echo "$$pkg: the TestingMacros flake; trying again"; \
	  done; \
	done

# internal/tools/.venv with pyserial, Pillow and Textual, for boopctl.
# internal/tools/boopctl makes it through this when it's missing; this also
# refreshes it after internal/tools/requirements.txt changes. A venv that
# already works (a worktree's may be a link to the main checkout's) is
# kept, and only its packages brought up to date. The pinned Pillow and
# Textual need Python 3.10 or later, newer than the Mac's own python3.
tools: tools/.venv/.ok

tools/.venv/.ok: tools/requirements.txt
	@cd $(ROOT) && test -x internal/tools/.venv/bin/python || python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' \
	  || { echo "tools: boopctl needs Python 3.10 or later, and python3 is $$(python3 --version 2>&1 | cut -d' ' -f2) (brew install python)" >&2; exit 1; }
	cd $(ROOT) && test -x internal/tools/.venv/bin/python || { python3 -m venv internal/tools/.venv \
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

# Firmware unit tests on the Mac: that the character pack's moods.h is
# fresh (characters/CHARACTER.md §9), Boop's, then LinkKit's device
# library's own (linkkit/device/platformio.ini).
fw-test:
	cd $(ROOT) && python3 characters/charactergen.py --check
	cd $(ROOT) && $(PIO) test -e native
	cd $(ROOT) && $(PIO) test -d $(ROOT)/linkkit/device -e native

# Every device scenario in the simulator, against the goldens (L1): the
# pixel face's, then the gel face's (characters/boop/tests/golden-gel/). The
# PNGs land in /tmp/boop-sim/<face>/<scenario>/; internal/tools/boopctl sim NAME
# [--face gel] runs one.
sim:
	cd $(ROOT) && internal/tools/boopctl sim
	cd $(ROOT) && internal/tools/boopctl sim --face gel

# The simulator (simulator/tests/): its core on the Mac in real time, with
# the test as its front end and at its serial port; then the same core as
# the browser runs it, built to WebAssembly (it needs Emscripten: brew
# install emscripten), and the page's USB cable.
sim-test:
	cd $(ROOT) && $(PIO) run -e native
	cd $(ROOT) && python3 -m unittest discover -s simulator/tests
	cd $(ROOT) && simulator/web/build.sh
	cd $(ROOT) && node --test simulator/tests/

# Records the staged character pack's demo for the simulator's page
# (simulator/README.md, Demos): played through the headless app on the
# simulator's board, FACE=gel for Boop's own face. As long as the demo runs.
demo:
	$(MAKE) -C $(ROOT) build
	cd $(ROOT) && $(PIO) run -e native
	cd $(ROOT) && simulator/tools/record-demo.sh $(or $(FACE),pixel)

# Hook → app → USB → device pipeline check (L4), on the board over USB.
e2e:
	$(MAKE) -C $(ROOT) build
	cd $(ROOT) && internal/tools/boopctl e2e

# The tools' own tests, with no board or camera: boopctl's commands (the
# working day's script and report among them, and the takes they read from
# the voice pack), the webcam recorder on synthetic video, charactergen's
# staging and studio rules (internal/characters/), and each character
# pack's own (its tests/tools/).
tools-test: tools
	cd $(ROOT) && internal/tools/.venv/bin/python -m unittest discover -s internal/tools/boopctl_lib/tests
	cd $(ROOT) && python3 -m unittest discover -s internal/tools/webcam/tests
	cd $(ROOT) && python3 -m unittest discover -s internal/characters
	cd $(ROOT) && for tests in characters/*/tests/tools; do \
	  [ -d $$tests ] || continue; python3 -m unittest discover -s $$tests || exit 1; \
	done
