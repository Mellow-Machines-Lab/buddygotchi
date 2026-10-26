#!/bin/sh
# Builds Boop.app, the app as it ships: a release build for Apple silicon
# and Intel, with agent-hook beside the binary (where the app copies it
# from), the character packs, the icon and each board's firmware (which
# the app updates a board with, firmware/tools/package.py) in Resources,
# the Info.plist with the version from VERSION and a build number, signed
# with the hardened runtime, once the binary is checked to open on macOS 15.
#   app/tools/bundle.sh            (or `make bundle` from the repo root)
# SIGN_IDENTITY is who signs it: "-", ad hoc, by default, which runs on
# this Mac only; a Developer ID's name, once there is one, for others.
# BUNDLE_OUT is where it goes, .build/Boop.app by default.
# INTERNAL=1 makes the internal build, into .build/internal/Boop.app: the
# same app with what's for us and not for buyers, compiled in with
# BOOP_INTERNAL. For now that's the simulator, the board's firmware in a
# window of the app's own (app/Boop/BoardWindow.swift), a body to choose
# in onboarding and Settings for anyone without a board. It needs
# Emscripten (`brew install emscripten`) to build the simulator's page.
# The build number is the commit count, which only goes up, so a clone
# made with --depth gets a wrong one: CI needs the whole history.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"
identity=${SIGN_IDENTITY:--}
internal=${INTERNAL:-}
app=${BUNDLE_OUT:-.build/${internal:+internal/}Boop.app}
if [ -n "$internal" ] && ! command -v emcc >/dev/null; then
  echo "bundle: INTERNAL=1 needs Emscripten for the simulator: brew install emscripten" >&2
  exit 1
fi

python3 characters/charactergen.py --stage
build="swift build -c release --arch arm64 --arch x86_64${internal:+ -Xswiftc -DBOOP_INTERNAL}"
$build --product Boop
$build --product agent-hook
bin=$($build --show-bin-path)
packs=$(find "$bin/Boop_Boop.bundle" -maxdepth 3 -type d -name packs | head -1)
[ -n "$packs" ] || { echo "bundle: no packs in $bin/Boop_Boop.bundle" >&2; exit 1; }
# Each board's firmware the pack has a face for, with the same character
# pack, whose objects each env builds in a folder of its own.
boards=$(python3 characters/charactergen.py --boards)
for board in $boards; do
  firmware/tools/pio.sh run -e "$board"
done

version=$(tr -d '[:space:]' < VERSION)
number=$(git rev-list --count HEAD)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Boop" "$bin/agent-hook" "$app/Contents/MacOS/"
# Boop opens on macOS 15, and Apple Intelligence's prompt labels need 26:
# FoundationModels must be linked weak, or macOS 15 won't start the app.
for arch in arm64 x86_64; do
  loads=$(otool -arch "$arch" -l "$app/Contents/MacOS/Boop")
  printf '%s\n' "$loads" | grep -B2 'name .*/FoundationModels\.framework/' | grep -q 'cmd LC_LOAD_WEAK_DYLIB' \
    || { echo "bundle: $arch: FoundationModels isn't linked weak" >&2; exit 1; }
  printf '%s\n' "$loads" | grep -A3 'cmd LC_BUILD_VERSION' | grep -q 'minos 15\.0$' \
    || { echo "bundle: $arch: the minimum macOS isn't 15.0" >&2; exit 1; }
done
cp -R "$packs" "$app/Contents/Resources/packs"
cp app/Boop/AppIcon.icns "$app/Contents/Resources/"
for board in $boards; do python3 firmware/tools/package.py "$board" "$app/Contents/Resources/firmware"; done
# The internal build's simulator: the page, its core and the pack's voice,
# with the face the pack gives the AMOLED board, which the window draws.
if [ -n "$internal" ]; then
  simulator/web/build.sh >/dev/null
  sim="$app/Contents/Resources/simulator"
  mkdir -p "$sim"
  cp simulator/web/dist/app.html simulator/web/dist/boop-simulator.js simulator/web/dist/boop-sim.js \
    simulator/web/dist/boop-sim.wasm "$sim/"
  pack=$(python3 characters/charactergen.py --which)
  [ -f "$pack/voice/voice.bin" ] && cp "$pack/voice/voice.bin" "$sim/voice.bin"
  python3 -c 'import json,sys; faces = json.load(open(sys.argv[1])).get("faces", {}); print(faces.get("amoled206") or "pixel")' \
    "$pack/character.json" > "$sim/face"
fi
plist="$app/Contents/Info.plist"
cp app/Boop/Info.plist "$plist"
plutil -insert CFBundleShortVersionString -string "$version" "$plist"
plutil -insert CFBundleVersion -string "$number" "$plist"
plutil -insert CFBundleIconFile -string AppIcon "$plist"

# Inside out: the helper first, then the app, which seals it in.
# Ad hoc signatures can't have a secure timestamp; a Developer ID's must.
stamp=--timestamp
[ "$identity" = - ] && stamp=--timestamp=none
codesign --force --options runtime $stamp --sign "$identity" "$app/Contents/MacOS/agent-hook"
codesign --force --options runtime $stamp --sign "$identity" --entitlements app/Boop/Boop.entitlements "$app"
codesign --verify --strict --deep "$app"
echo "bundle: $app, Boop $version ($number)${internal:+, internal}, signed by ${identity}"
