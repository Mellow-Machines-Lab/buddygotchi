// VERSION is the one place Boop's version is written: the firmware's build
// reads it too (firmware/tools/version.py). #embed makes the compiler read
// it, so its dependency tracking rebuilds this file when VERSION changes,
// with nothing generated first. SwiftPM caches what Package.swift reads,
// so the manifest can't pass it on.
#include "boop_version.h"

static const char version[] = {
#embed "../../VERSION"
    , 0};

const char *boop_version(void) { return version; }
