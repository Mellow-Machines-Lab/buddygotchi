// The card as files on the Mac: BOOP_SIM_CARD names a folder for it, where
// a pack copied on with dbg.card goes to <folder>/boop/voice.bin, as on the
// board, and is played from there. Without it the card holds the repo's own
// pack (.build/voice/voice.bin), when that's been built, and takes no copy.
#pragma once
#include <cstdio>
#include <cstdlib>
#include <string>
#include <sys/stat.h>

#include "linkkit/codec.h"
#include "pack_file.h"
#include "sim_hal.h"

namespace sim {

struct FileCard : Card {
  std::string dir = std::getenv("BOOP_SIM_CARD") ? std::getenv("BOOP_SIM_CARD") : "";
  packfile::FileSource pack, copy;
  std::string path(const char* name) const { return dir + "/boop/" + name; }

  bool open() override {
    if (dir.empty()) return packfile::open();
    if (pack.f) std::fclose(pack.f), pack.f = nullptr;
    pack.f = std::fopen(path("voice.bin").c_str(), "rb");
    return pack.f && voice::openPack(&pack);
  }
  bool packBegin(bool keep, uint32_t& have, const char*& why) override {
    have = 0;
    if (dir.empty()) return why = "no card", false;
    ::mkdir(dir.c_str(), 0755), ::mkdir((dir + "/boop").c_str(), 0755);
    if (copy.f) std::fclose(copy.f);
    copy.f = std::fopen(path("voice.tmp").c_str(), keep ? "ab" : "wb");
    if (!copy.f) return why = "can't open /boop/voice.tmp", false;
    have = uint32_t(std::ftell(copy.f));
    return true;
  }
  bool packAppend(const uint8_t* d, size_t n, uint32_t& have) override {
    if (!copy.f) return have = 0, false;
    bool ok = !n || std::fwrite(d, 1, n, copy.f) == n;
    std::fflush(copy.f);
    have = uint32_t(std::ftell(copy.f));
    return ok;
  }
  bool packEnd(uint32_t size, uint32_t crc, const char*& why) override {
    if (!copy.f) return why = "no copy begun", false;
    std::fclose(copy.f), copy.f = nullptr;
    std::FILE* f = std::fopen(path("voice.tmp").c_str(), "rb");
    uint8_t buf[4096];
    uint32_t got = 0, sum = 0;
    for (size_t n; f && (n = std::fread(buf, 1, sizeof(buf), f)) > 0; got += uint32_t(n)) sum = linkkit::crc32(buf, n, sum);
    if (f) std::fclose(f);
    if (got != size || sum != crc) return why = got != size ? "wrong size" : "wrong crc", false;
    voice::closePack();
    if (std::rename(path("voice.tmp").c_str(), path("voice.bin").c_str()) || !open()) return why = "can't swap it in", false;
    return true;
  }
};

}  // namespace sim
