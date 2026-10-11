// The voice pack from a file, for the simulator and the
// firmware's tests, which have no SD card: the chosen character pack's
// voice/voice.bin (characters/CHARACTER.md §8).
#pragma once
#include <cstdio>
#include <fstream>
#include <string>

#include "voice/player.h"

namespace packfile {

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
    std::string here = __FILE__;  // <repo>/internal/firmware/pack_file.h
    std::string repo = here.substr(0, here.rfind("/internal/firmware/"));
    std::string pack;
    std::ifstream chosen(repo + "/.character-build/pack");
    if (std::getline(chosen, pack)) src.f = std::fopen((pack + "/voice/voice.bin").c_str(), "rb");
  }
  return src;
}

// Opens it as the voice pack; false when the chosen pack has no voice.
inline bool open() { return source().f && voice::openPack(&source()); }

}  // namespace packfile

// A test that plays takes skips when the chosen pack has no voice
// (characters/CHARACTER.md §8). Unity's, so for the tests only.
#define NEEDS_VOICE_PACK() \
  do {                     \
    if (!packfile::source().f) TEST_IGNORE_MESSAGE("needs a voice pack, which the chosen character pack hasn't"); \
  } while (0)
