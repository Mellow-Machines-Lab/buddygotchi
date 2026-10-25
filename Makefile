# Boop v1. Run from the repo root. See README.md and internal/VERIFICATION.md.
# Only what the owner runs. The rest (the builds agents and tests use, the
# tests, the simulator's checks and the tools) is in internal/Makefile:
# make -C internal <target>.
.PHONY: dev bundle demo flash eval clean

# Importing a target that isn't a declared dependency is an error, not a
# warning, so app/ can't reach internal/ code (internal/README.md).
SWIFT_CHECK := --explicit-target-dependency-import-check error

# The debug app on a folder of its own (~/Library/Application Support/Boop-dev),
# with the simulator, its page, the studio's matrix and the live dashboard
# open beside it (internal/tools/dev.sh). It starts on the board, over
# Bluetooth, so the owner runs this; Settings' Simulator row switches to
# the simulator and back. FRESH=1 starts the folder afresh: onboarding again.
dev:
	internal/tools/dev.sh

# Boop.app, as it ships, in .build/Boop.app (app/tools/bundle.sh): a release
# build for Apple silicon and Intel, with both boards' firmware to update
# them with, signed ad hoc until there's a Developer ID (SIGN_IDENTITY=…).
# Open it to run it; that's Bluetooth, so the owner's.
bundle:
	app/tools/bundle.sh

# A pack's demo by name (characters/DEMOS.md): NAME (landing), and IN for
# where you watch an agent play it, none by default.
DEMO_RUN := internal/tools/session/session.py run $(or $(NAME),landing) --board $(or $(BOARD),sim)
demo:
	@case "$(IN)" in \
	  "") BOARD=$(BOARD) simulator/tools/demo.sh $(or $(NAME),landing) $(or $(FACE),pixel) ;; \
	  claude) $(DEMO_RUN) --ui desktop ;; \
	  simulated-claude-terminal) $(DEMO_RUN) --agent claude ;; \
	  simulated-codex-terminal) $(DEMO_RUN) --agent codex ;; \
	  *) echo "make demo: IN is claude, simulated-claude-terminal or simulated-codex-terminal, or nothing" >&2; exit 1 ;; \
	esac

# The harness eval scenarios (internal/EVALS.md) against Jev, all of them with no
# request budget: the final pass (internal/EVALS.md §2 counts its requests).
# While developing, run .build/debug/boopdev eval --only TEXT instead.
# They need Jev's key in BOOP_JEV_KEY and fail without it
# (internal/VERIFICATION.md L5). Builds boopdev alone, with the chosen
# pack staged, not the rest of `make -C internal build`.
eval:
	python3 characters/charactergen.py --stage
	swift build $(SWIFT_CHECK) --product boopdev
	.build/debug/boopdev eval --no-budget

# Build and upload over USB (auto-reset, no BOOT press), for whichever
# board is plugged in; BOARD (cyd24 or amoled206) or BOOP_PORT picks one
# when it can't tell (firmware/tools/flash.sh, firmware/README.md).
flash:
	firmware/tools/flash.sh

# Every build's output, so the next build starts from nothing: the Swift
# package's and each package's own (their tests' builds), PlatformIO's
# (LinkKit's device library's own project too), the staged character pack,
# the tests' generated runner and the simulator's page, its recorded demos
# with it. Keeps the tools' venv and PlatformIO's own packages
# (firmware/.platformio-core), which are installs, not build output.
clean:
	rm -rf .build agent-hooks/.build mellowharness/.build linkkit/.build \
	  firmware/.pio linkkit/device/.pio .character-build \
	  internal/app/Tests/GeneratedTestRunner.swift simulator/web/dist
