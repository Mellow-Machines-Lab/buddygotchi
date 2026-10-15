// The voice file read from disk, for the simulator and the
// firmware's tests, which have no SD card: the chosen character pack's
// voice/voice.bin (characters/CHARACTER.md §8).
#pragma once
#include <cstdio>
#include <fstream>
#include <string>

#include "voice/player.h"

namespace voicefile {

struct FileSource : voice::Source {
  std::FILE* f = nullptr;
  bool read(uint32_t at, void* buf, uint32_t n) override {
    return f && !std::fseek(f, long(at), SEEK_SET) && std::fread(buf, 1, n, f) == n;
  }
};

// The chosen pack's voice file. The pack's folder is the one staging
// names in .character-build/pack, found from this file's own path.
inline FileSource& source() {
  static FileSource src;
  if (!src.f) {
    std::string here = __FILE__;  // <repo>/internal/firmware/voice_file.h
    std::string repo = here.substr(0, here.rfind("/internal/firmware/"));
    std::string pack;
    std::ifstream chosen(repo + "/.character-build/pack");
    if (std::getline(chosen, pack)) src.f = std::fopen((pack + "/voice/voice.bin").c_str(), "rb");
  }
  return src;
}

// Opens it as the voice file; false when the chosen pack has none.
inline bool open() { return source().f && voice::openFile(&source()); }

}  // namespace voicefile

// A test that plays takes skips when the chosen pack has no voice
// (characters/CHARACTER.md §8). Unity's, so for the tests only.
#define NEEDS_VOICE_PACK() \
  do {                     \
    if (!voicefile::source().f) TEST_IGNORE_MESSAGE("needs a voice file, which the chosen character pack hasn't"); \
  } while (0)
