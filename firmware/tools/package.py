#!/usr/bin/env python3
"""Packs a built board's firmware for Boop.app to update the board with.

    python3 firmware/tools/package.py ENV OUT_DIR

After `firmware/tools/pio.sh run -e ENV`, writes OUT_DIR/ENV/: the app
(firmware.bin), the record that boots its slot (boot_app0.bin, from the
Arduino core), and manifest.json, which says the board, its chip and
flash, the version and SHA it was built from, and each image's offset.
The offsets come from the board's own partition table (its otadata and
first app slot), and the chip from the app image's header, so the Mac
writes exactly what PlatformIO would, but not the bootloader, partition
table or settings (NVS). make bundle (app/tools/bundle.sh) runs it for
both boards. Standard library only, for the Mac's own Python 3.9.
"""
import configparser
import json
import os
import re
import shutil
import struct
import sys

FIRMWARE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHIPS = {0: "esp32", 9: "esp32s3"}


def partitions(path):
    """(type, subtype, offset, size) for each entry of a partition table."""
    data = open(path, "rb").read()
    for i in range(0, len(data) - 31, 32):
        entry = data[i:i + 32]
        if entry[:2] != b"\xaa\x50":
            break
        offset, size = struct.unpack("<II", entry[4:12])
        yield entry[2], entry[3], offset, size


def setting(env, key):
    """An env's key in platformio.ini, following `extends`."""
    ini = configparser.ConfigParser(interpolation=None)
    ini.read(os.path.join(FIRMWARE, "platformio.ini"))
    section = "env:" + env
    while section:
        if ini.has_option(section, key):
            return ini.get(section, key).strip()
        parent = ini.get(section, "extends", fallback="").strip()
        section = parent or None
    sys.exit(f"package: no {key} for env {env} in platformio.ini")


def size(text):
    match = re.fullmatch(r"(\d+)\s*MB", text, re.I)
    return int(match.group(1)) << 20 if match else int(text)


def main(env, out):
    build = os.path.join(FIRMWARE, ".pio", "build", env)
    app = os.path.join(build, "firmware.bin")
    header = open(app, "rb").read(16)
    if header[0] != 0xE9:
        sys.exit(f"package: {app} isn't an app image")
    chip = CHIPS.get(struct.unpack("<H", header[12:14])[0])
    if not chip:
        sys.exit(f"package: {app} is for a chip this doesn't know")
    table = list(partitions(os.path.join(build, "partitions.bin")))
    otadata = next((offset for kind, sub, offset, _ in table if kind == 1 and sub == 0), None)
    slot = next((offset for kind, sub, offset, _ in table if kind == 0), None)
    if otadata is None or slot is None:
        sys.exit("package: the partition table has no otadata or no app slot")
    stamp = open(os.path.join(build, "generated", "boop_version.h")).read()
    version = re.search(r'BOOP_FW_VERSION "([^"]+)"', stamp).group(1)
    sha = re.search(r'BOOP_GIT_SHA "([^"]+)"', stamp).group(1)
    core = os.environ.get("PLATFORMIO_CORE_DIR", os.path.join(FIRMWARE, ".platformio-core"))
    boot = os.path.join(core, "packages", "framework-arduinoespressif32", "tools", "partitions", "boot_app0.bin")
    dest = os.path.join(out, env)
    os.makedirs(dest, exist_ok=True)
    shutil.copyfile(boot, os.path.join(dest, "boot_app0.bin"))
    shutil.copyfile(app, os.path.join(dest, "firmware.bin"))
    manifest = {
        "board": env, "chip": chip, "flash_size": size(setting(env, "board_upload.flash_size")),
        "version": version, "sha": sha,
        "images": [{"offset": otadata, "file": "boot_app0.bin"}, {"offset": slot, "file": "firmware.bin"}],
    }
    with open(os.path.join(dest, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"package: {env} {version} ({sha}) for an {chip}, into {dest}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    main(sys.argv[1], sys.argv[2])
