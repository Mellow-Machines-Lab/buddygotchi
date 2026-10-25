// The gel face's stage timings (render/profile.h), reported by
// GelFace::profile as BOOP_GEL_PROFILE's gel_parts line.
#pragma once
#include <cstdint>
#include "render/profile.h"
namespace render::gel {
struct Profile {
  uint32_t engine = 0, sync = 0, body = 0, clear = 0, art = 0, layers = 0, props = 0, lane = 0, stream = 0;
};
inline Profile profile;
using render::Measure;
}  // namespace render::gel
