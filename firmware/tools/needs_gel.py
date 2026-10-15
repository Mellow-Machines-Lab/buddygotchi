# PlatformIO pre-script for the AMOLED builds: they draw the gel face
# (BOOP_FACE_GEL), so the staged character pack must carry one. Without it
# the build would fail only at the link, on a missing face. Stops it at the
# start instead, saying why.
import os
import sys

Import("env")  # noqa: F821

stage = os.path.join(env["PROJECT_DIR"], "..", ".character-build")  # noqa: F821
if not os.path.isdir(os.path.join(stage, "firmware", "src", "render", "gel")):
    try:
        pack = os.path.basename(open(os.path.join(stage, "pack")).read().strip())
    except OSError:
        pack = "(none staged)"
    sys.stderr.write(
        "\nThe AMOLED board (env %s) needs a character pack with a gel face, which only\n"
        "Boop's pack has for now; the staged pack, %s, has none. The CYD board (env\n"
        "cyd24) runs any pack (characters/CHARACTER.md).\n\n" % (env["PIOENV"], pack))  # noqa: F821
    env.Exit(1)  # noqa: F821
