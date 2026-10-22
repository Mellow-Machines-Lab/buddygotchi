# The AMOLED builds compile the gel engine's step for size (-Os) and the
# rest for speed (-O2): the engine runs once a step through about 117 KB of
# code, which -O2's inlining makes miss the ESP32-S3's 16 KB instruction
# cache on nearly every line; at -Os it's 45 KB and takes half the time.
# The pixel loops stay -O2. Only the board builds run this; the simulator's are unchanged.
# It runs before tools/pack_face.py, which builds the pack's sources.
Import("env")

ENGINE = ("acting.cpp", "engine.cpp", "face.cpp", "motion.cpp", "router.cpp", "scenes.cpp")


def for_size(env, node):
    if node.name not in ENGINE:
        return node
    # The last -O on the command line wins: CPPFLAGS comes after CCFLAGS
    # (build_flags' -O2), and nothing else sets it. Only CPPFLAGS is
    # replaced, so the rest of the flags are read when the file compiles,
    # after this pre-script.
    return env.Object(node, CPPFLAGS=["-Os"])


env.AddBuildMiddleware(for_size, "*/render/gel/*.cpp")
