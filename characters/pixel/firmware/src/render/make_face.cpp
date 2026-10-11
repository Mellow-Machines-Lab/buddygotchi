// The Pixel pack's face (characters/CHARACTER.md §9): the pixel face on
// every board and in the simulator. A pack with more faces has its own
// make_face.cpp, which chooses among them.
#include "render/face.h"
#include "render/pixel/anim.h"
namespace render {
std::unique_ptr<Face> makeFace() { return std::make_unique<pixel::PixelFace>(); }
}  // namespace render
