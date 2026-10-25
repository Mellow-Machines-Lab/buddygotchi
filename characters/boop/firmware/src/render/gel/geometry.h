#pragma once
#include "render/gel/painter.h"
#include "render/gel/raster.h"
#include <algorithm>
#include <cstdint>
namespace render::gel {
// Q12 world coordinates; the camera and dome are slimegen's mesh's.
inline int root(uint32_t n) {
  if (!n) return 0;
  uint32_t r = 1u << ((33 - __builtin_clz(n)) / 2);
  for (;;) {
    uint32_t next = (r + n / r) / 2;
    if (next >= r) return int(r);
    r = next;
  }
}
inline int product(int a, int b) { return a * b / 4096; }
struct World {
  int x, y, z;
};
struct Projector {
  const Surface& surface;
  const PaintControls& c;
  int sx, sy, sn, cs;
  Projector(const Surface& s, const PaintControls& controls) : surface(s), c(controls) {
    sy = 4096 + product(c.squash, 2130);
    sx = 16777216 / std::max(1, root(uint32_t(std::max(3113, sy)) * 4096));
    sn = c.roll - product(product(c.roll, c.roll), c.roll) / 6;
    cs = 4096 - product(c.roll, c.roll) / 2;
  }
  World deform(World p, int h, int h2, int front = 4096, int dent = 4096) const {
    p.x = product(p.x, sx) + product(product(c.lean, 1393), h2);
    p.z = product(p.z, sx) + product(product(c.lean, 369), h) - product(product(c.dent, 492), dent);
    p.x += product(product(product(c.dent, 102), p.x), front);
    p.y = product(p.y, sy);
    // A finger's pull leans and squashes the body (Engine::pose); here it
    // carries the top a little further after the finger, front and back
    // alike, so the base stays put and the outline stays whole.
    int grabWeight = product(532, h2);
    p.x += product(c.grabX, grabWeight);
    p.y += product(c.grabY, grabWeight);
    int x = p.x, y = p.y - 2540;
    p.x = product(x, cs) - product(y, sn);
    p.y = std::max(74, product(x, sn) + product(y, cs) + 2540 + c.lift);
    p.z += product(c.forward, h2);
    p.x += c.slide;
    return p;
  }
  Point project(World p) const {
    // eye=(0,1.45,3.3), target=(0,.74,0), f=1/tan(.42).
    int y = p.y - 5939, z = p.z - 13517, vy = product(y, 4005) - product(z, 862),
        depth = std::max(1024, -product(y, 862) - product(z, 4005));
    int height = surface.height * 95 / 100, focal = height * 4586;
    int perspective = focal * 16 / depth;
    return {surface.width * 8 + product(p.x, perspective), height * 8 - product(vy, perspective) + c.dy * 16};
  }
  Point face(int x, int y) const {
    // Undo the face texture's 1.24 scale and .92 UV mapping.
    int bx = product(x, 5521), by = product(y, 5521), bz = root(uint32_t(std::max(0, 16777216 - bx * bx - by * by)));
    int raw = 2294 + product(3727, by), py = (raw + root(uint32_t(raw * raw + 53687))) / 2 + 78;
    int radius = 4506 - product(287, by), h = py * 4096 / 6103;
    World p{product(radius, bx), py, product(product(radius, bz), 3154)};
    int dist = product(bx, 15974), dy = product(by - 819, 12698);
    int dent = std::max(0, 4096 - int((int64_t(dist) * dist + int64_t(dy) * dy) / 4096));
    dent = product(dent, dent);
    return project(deform(p, h, product(h, h), 4096, dent));
  }
};
}  // namespace render::gel
