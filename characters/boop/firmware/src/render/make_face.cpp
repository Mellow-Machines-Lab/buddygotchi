// Boop's faces (characters/CHARACTER.md §9): the gel slime on the
// AMOLED, Pixel's face on the CYD, and in the simulator the one
// BOOP_SIM_FACE names.
#include "render/face.h"
#if defined(BOOP_FACE_GEL) || !defined(ARDUINO)
#include "render/gel/face.h"
#endif
#if defined(BOOP_FACE_PIXEL) || !defined(ARDUINO)
#include "render/pixel/anim.h"
#endif
#ifndef ARDUINO
#include <cstdlib>
#include <cstring>
#endif
namespace render {
std::unique_ptr<Face> makeFace() {
#if defined(BOOP_FACE_GEL)
  return std::make_unique<gel::GelFace>();
#elif defined(BOOP_FACE_PIXEL)
  return std::make_unique<pixel::PixelFace>();
#else
  const char* face = std::getenv("BOOP_SIM_FACE");
  if (face && !std::strcmp(face, "gel")) return std::make_unique<gel::GelFace>();
  return std::make_unique<pixel::PixelFace>();
#endif
}
}  // namespace render
