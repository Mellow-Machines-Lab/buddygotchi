#include "render/gel/painter.h"
#include "render/gel/engine.h"
#include "render/gel/raster.h"
#include "render/gel/geometry.h"
#include "slime_art.h"
namespace render::gel {
void paintArt(Surface& surface, const Engine& engine, const PaintControls& c, bool mouthOpen, Anchors* anchors) {
  if (!surface.pixels) return;
  Raster raster{surface};
  const auto& f = engine.face;
  const auto& profile = slime::kProfile[f.artId];
  Projector projection(surface, c);
  int unit = surface.height * 3 / 5;
  auto scalar = [](F v) { return int(v.raw / (F::scale / 4096)); };
  int baseX = scalar(profile.face[0]), baseY = scalar(profile.face[1]), baseM = scalar(profile.face[3]);
  // The engine's drawn scales (CONTINUITY.md, Directed edge bridges): the
  // face never fades; its art eases in size and the mouth dots at the swap.
  const int eyeX = scalar(f.controls[0]), eyeY = scalar(f.controls[1]), eyeScale = scalar(f.eyeScale());
  const int mouthY = scalar(f.controls[3]), mouthWidth = scalar(f.mouthScaleX()), mouthHeight = scalar(f.mouthScaleY());
  auto point = [&](slime::ArtPoint p, int group) {
    int x = p.x, y = p.y;
    if (group == 1 || group == 2) {
      int side = group == 1 ? -1 : 1;
      x = x - side * baseX + side * eyeX + c.gaze;
      y = eyeY + int(int64_t(y - baseY) * eyeScale * (4096 - c.blink) / (4096 * 4096));
    } else if (group == 3) {
      x = x * mouthWidth / 4096;
      y = mouthY + (y - baseM) * mouthHeight / 4096;
    }
    // Kept in sixteenths of a pixel: a feature moves smoothly with the
    // body instead of stepping a whole pixel at a time.
    return projection.face(x, y);
  };
  if (anchors) {  // each eye's middle, where its art is centred
    const Point l = projection.face(-eyeX + c.gaze, eyeY), r = projection.face(eyeX + c.gaze, eyeY);
    anchors->eyeL = {l.x, l.y}, anchors->eyeR = {r.x, r.y};
  }
  auto range = slime::kArt[f.artId];
  Point vertices[96], clip[96];
  for (int i = 0; i < range.count; ++i) {
    const auto& path = slime::kArtPaths[range.first + i];
    if (path.count > 96 || path.clipCount > 96) continue;
    int alpha = path.alpha;
    if (path.group == 4) alpha = alpha * scalar(f.render[SemanticFace::kTear]) / 4096;
    if (path.group == 5) alpha = alpha * scalar(f.render[SemanticFace::kCheek]) / 4096;
    raster.alpha = alpha;
    if (!alpha) continue;
    for (int n = 0; n < path.count; ++n) vertices[n] = point(slime::kArtPoints[path.first + n], path.group);
    for (int n = 0; n < path.clipCount; ++n) clip[n] = point(slime::kArtPoints[path.clip + n], path.group);
    if (path.width)
      // The authored width, to a sixteenth, never thinner than 3/4 pixel.
      raster.stroke16(vertices, path.count, std::max(12, int(path.width) * unit * 16 / 4096), path.color);
    else
      raster.polygon16(vertices, path.count, path.color, clip, path.clipCount);
  }
  if (mouthOpen) {
    raster.alpha = 255;
    auto p = point({0, int16_t(baseM)}, 3);
    raster.disk16(p.x, p.y, 4 * 16 + 8, rgb565(13, 43, 72));
  }
}
}  // namespace render::gel
