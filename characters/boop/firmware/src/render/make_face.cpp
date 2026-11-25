// Boop's face (characters/CHARACTER.md §9): the gel slime, on the AMOLED
// and in the simulator.
#include "render/face.h"
#include "render/gel/face.h"
namespace render {
std::unique_ptr<Face> makeFace() { return std::make_unique<gel::GelFace>(); }
}  // namespace render
