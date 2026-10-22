#include "render/tags.h"

#include <cstring>

namespace render {

uint32_t tagBit(const char* name) {
  if (!name) return 0;
  for (int i = 0; i < kTagCount; ++i)
    if (!std::strcmp(kTagNames[i], name)) return uint32_t(1) << i;
  return 0;
}

uint32_t busyTags(int working) {
  return working >= kFranticFrom ? tagBit("frantic") : working >= kBusyFrom ? tagBit("busy") : 0;
}

}  // namespace render
