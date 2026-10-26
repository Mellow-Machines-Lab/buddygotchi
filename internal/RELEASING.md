# Releasing Boop

Updated 2026-10-25. How a version of Boop goes out, as far as it can
today. Only the owner tags and pushes.

## 1. The version

`VERSION` is the only place it's written. The app compiles it in
(`BoopVersion`), the firmware's build reads it, and `make bundle` stamps
it into `Boop.app`'s Info.plist, with the commit count as the build
number. App and firmware share it: an app offers its own firmware to a
board running an older version, or the same one built with another
character pack (Settings, Device).

## 2. Checks

```sh
make -C internal test      # Boop's Swift tests, then each package's
make -C internal fw-test   # the firmware's and LinkKit's device tests
make -C internal sim       # the firmware's drawing against the goldens
make bundle                # Boop.app, its pack's boards' firmware inside, signed and verified
```

Then on a Mac, by hand: copy `.build/Boop.app` into `/Applications`
and open it from there, set it up, allow Bluetooth, the mic and speech,
connect a board, see a hook arrive (`internal/skills/doctor/doctor.sh`),
open an agent's session from the popover (macOS asks to let Boop
control your terminal), update a board from Settings, and uninstall
from Settings.

## 3. Tagging

Bump `VERSION` to the new version in a commit of its own, tag that
commit as the version, and push the tag:

```sh
echo 1.1.0 > VERSION && git commit -m "Boop 1.1.0" VERSION
git tag 1.1.0 && git push origin 1.1.0
```

## 4. Not yet

- **Signing with a Developer ID.** `SIGN_IDENTITY="Developer ID
  Application: …" make bundle` signs with it once there is one; until
  then `Boop.app` is signed ad hoc and opens only on the Mac that built
  it.
- **Notarizing and stapling** with `notarytool`, so Gatekeeper opens it
  elsewhere.
- **Updates in the app** (Sparkle) and an appcast to publish them on.
- **Release builds in CI**, with the certificate and keys as secrets,
  and its checkout's whole history for the build number.
