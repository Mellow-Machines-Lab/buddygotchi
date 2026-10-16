# PlatformIO pre-script for the board builds: the staged character pack
# says which face each board draws (character.json's `faces`, by the env's
# custom_board). The build defines BOOP_FACE_<NAME> for the pack's
# make_face.cpp, and compiles that face's folder,
# render/<name>/, and none of the pack's other faces'. A pack with no face
# for the board stops the build at the start, saying why, instead of at
# the link.
import json
import os
import sys

Import("env")  # noqa: F821

stage = os.path.join(env["PROJECT_DIR"], "..", ".character-build")  # noqa: F821
board = env.GetProjectOption("custom_board")  # noqa: F821
try:
    pack = open(os.path.join(stage, "pack")).read().strip()
    faces = json.load(open(os.path.join(pack, "character.json"))).get("faces", {})
except OSError:
    pack, faces = "(none staged)", {}
face = faces.get(board)
render = os.path.join(stage, "firmware", "src", "render")
if not face or not os.path.isdir(os.path.join(render, face)):
    sys.stderr.write(
        "\nThe %s board (env %s) needs a character pack with a face for it, and the\n"
        "staged pack, %s, has none (its character.json's faces: %s).\n"
        "See characters/CHARACTER.md.\n\n" % (board, env["PIOENV"], os.path.basename(pack), faces or "none"))  # noqa: F821
    env.Exit(1)  # noqa: F821

env.Append(CPPDEFINES=["BOOP_FACE_" + face.upper()])  # noqa: F821
others = [name for name in sorted(os.listdir(render)) if name != face and os.path.isdir(os.path.join(render, name))]
env.Append(SRC_FILTER=["-<../../.character-build/firmware/src/render/%s/>" % name for name in others])  # noqa: F821
