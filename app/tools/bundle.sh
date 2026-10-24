#!/bin/sh
# Builds Boop.app, the app as it ships: a release build for Apple silicon
# and Intel, with agent-hook beside the binary (where the app copies it
# from), the character packs, the icon and each board's firmware (which
# the app updates a board with, firmware/tools/package.py) in Resources,
# the Info.plist with the version from VERSION and a build number, signed
# with the hardened runtime.
#   app/tools/bundle.sh            (or `make bundle` from the repo root)
# SIGN_IDENTITY is who signs it: "-", ad hoc, by default, which runs on
# this Mac only; a Developer ID's name, once there is one, for others.
# BUNDLE_OUT is where it goes, .build/Boop.app by default.
# The build number is the commit count, which only goes up, so a clone
# made with --depth gets a wrong one: CI needs the whole history.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"
identity=${SIGN_IDENTITY:--}
app=${BUNDLE_OUT:-.build/Boop.app}

python3 characters/charactergen.py --stage
build="swift build -c release --arch arm64 --arch x86_64"
$build --product Boop
$build --product agent-hook
bin=$($build --show-bin-path)
packs=$(find "$bin/Boop_Boop.bundle" -maxdepth 3 -type d -name packs | head -1)
[ -n "$packs" ] || { echo "bundle: no packs in $bin/Boop_Boop.bundle" >&2; exit 1; }
# Each board's firmware, with the same character pack.
boards="cyd24 amoled206"
# PlatformIO keeps the staged pack's objects in one folder for every env,
# and its timestamps can keep one board's face for the next: each board
# starts that folder afresh.
for board in $boards; do
  rm -rf firmware/.pio/build/.character-build
  firmware/tools/pio.sh run -e "$board"
done

version=$(tr -d '[:space:]' < VERSION)
number=$(git rev-list --count HEAD)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Boop" "$bin/agent-hook" "$app/Contents/MacOS/"
cp -R "$packs" "$app/Contents/Resources/packs"
cp app/Boop/AppIcon.icns "$app/Contents/Resources/"
for board in $boards; do python3 firmware/tools/package.py "$board" "$app/Contents/Resources/firmware"; done
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
echo "bundle: $app, Boop $version ($number), signed by ${identity}"
