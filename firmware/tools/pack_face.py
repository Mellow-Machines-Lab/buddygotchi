# PlatformIO pre-script for every env: builds the staged character pack's
# firmware sources (.character-build/firmware/src) into the env's own
# $BUILD_DIR/character, so each env keeps its own objects and builds them
# again only when they change.
#
# On a board (an env with custom_board), the staged pack says which face
# the board draws (character.json's `faces`, by custom_board): the build
# defines BOOP_FACE_<NAME> for the pack's make_face.cpp, and compiles that
# face's folder, render/<name>/, and none of the pack's other faces'. A
# pack with no face for the board stops the build at the start, saying
# why, instead of at the link. The native env (the tests and the
# simulator) builds every face.
import json
import os
import sys

Import("env")  # noqa: F821

stage = os.path.abspath(os.path.join(env["PROJECT_DIR"], "..", ".character-build"))  # noqa: F821
src = os.path.join(stage, "firmware", "src")
render = os.path.join(src, "render")
board = env.GetProjectOption("custom_board", "")  # noqa: F821
src_filter = ["+<*>"]
if board:
    try:
        pack = open(os.path.join(stage, "pack")).read().strip()
        faces = json.load(open(os.path.join(pack, "character.json"))).get("faces", {})
    except OSError:
        pack, faces = "(none staged)", {}
    face = faces.get(board)
    if not face or not os.path.isdir(os.path.join(render, face)):
        sys.stderr.write(
            "\nThe %s board (env %s) needs a character pack with a face for it, and the\n"
            "staged pack, %s, has none (its character.json's faces: %s).\n"
            "See characters/CHARACTER.md.\n\n" % (board, env["PIOENV"], os.path.basename(pack), faces or "none"))  # noqa: F821
        env.Exit(1)  # noqa: F821
    env.Append(CPPDEFINES=["BOOP_FACE_" + face.upper()])  # noqa: F821
    others = [name for name in sorted(os.listdir(render)) if name != face and os.path.isdir(os.path.join(render, name))]
    src_filter += ["-<render/%s/>" % name for name in others]

# Outside src/, the pack's sources miss the include paths PlatformIO's
# library finder gives src/, and the faces include LinkKit's
# (render/face.h includes linkkit/clock.h).
env.Append(CPPPATH=[os.path.join(env["PROJECT_DIR"], "..", "linkkit", "device", "src")])  # noqa: F821
env.BuildSources(os.path.join("$BUILD_DIR", "character"), src, src_filter)  # noqa: F821
