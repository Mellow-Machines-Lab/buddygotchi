#include "render/gel/engine.h"
#include "render/gel/geometry.h"
#include "render/gel/painter.h"
#include "render/gel/raster.h"
#include "slime_art.h"
namespace render::gel {
namespace {
constexpr int kMaxPoints = 96;
int scalar(F v) { return int(v.raw / (F::scale / 4096)); }
// One face layer's art, as the controls place it and at its drawn scales,
// in Q12 face units: what the painter blends or fades.
struct Placed {
  const slime::ArtRange* range;
  int baseX, baseY, baseM, eye, mouthWidth, mouthHeight, weight;
  // The art's path of a group by its place among the group's paths.
  int path(int group, int nth) const {
    for (int i = 0; i < range->count; ++i)
      if (slime::kArtPaths[range->first + i].group == group && !nth--) return range->first + i;
    return -1;
  }
};
}  // namespace
// The engine's face layers (CONTINUITY.md, Directed edge bridges): settled,
// one art as authored. While arts cross over, a group (an eye, the mouth,
// the tears, the cheeks) that has one shape in several layers is drawn once,
// their points, widths and opacities averaged by weight, at their summed
// weight; groups of different shapes cross-fade, the newer over the older.
void paintArt(Surface& surface, const Engine& engine, const PaintControls& c, bool mouthOpen, Anchors* anchors) {
  if (!surface.pixels) return;
  Raster raster{surface};
  const auto& f = engine.face;
  Projector projection(surface, c);
  int unit = surface.height * 3 / 5;
  const int eyeX = scalar(f.controls[0]), eyeY = scalar(f.controls[1]), mouthY = scalar(f.controls[3]);
  Placed placed[SemanticFace::kMaxLayers];
  for (int i = 0; i < f.count; ++i) {
    const auto& l = f.layers[i];
    const auto& face = slime::kProfile[l.art].face;
    const auto scale = drawnScale(l);
    placed[i] = {&slime::kArt[l.art], scalar(face[0]),  scalar(face[1]),  scalar(face[3]),
                 scalar(scale[0]),    scalar(scale[1]), scalar(scale[2]), scalar(l.weight)};
  }
  // Where the controls put a point of a layer's art, in Q12 face units.
  auto place = [&](const Placed& l, slime::ArtPoint p, int group) {
    int x = p.x, y = p.y;
    if (group == 1 || group == 2) {
      int side = group == 1 ? -1 : 1;
      x = x - side * l.baseX + side * eyeX + c.gaze;
      y = eyeY + int(int64_t(y - l.baseY) * l.eye * (4096 - c.blink) / (4096 * 4096));
    } else if (group == 3) {
      x = x * l.mouthWidth / 4096;
      y = mouthY + (y - l.baseM) * l.mouthHeight / 4096;
    }
    return Point{x, y};
  };
  if (anchors) {  // each eye's middle, where its art is centred
    const Point l = projection.face(-eyeX + c.gaze, eyeY), r = projection.face(eyeX + c.gaze, eyeY);
    anchors->eyeL = {l.x, l.y}, anchors->eyeR = {r.x, r.y};
  }
  Point vertices[kMaxPoints], clip[kMaxPoints];
  for (int i = 0; i < f.count; ++i) {
    const auto& range = *placed[i].range;
    int nth[6] = {};
    for (int k = 0; k < range.count; ++k) {
      const auto& path = slime::kArtPaths[range.first + k];
      const int g = path.group, at = nth[g]++;
      if (path.count > kMaxPoints || path.clipCount > kMaxPoints) continue;
      // The layers whose art has this group's shape: drawn once, with the
      // newest of them.
      int members[SemanticFace::kMaxLayers], paths[SemanticFace::kMaxLayers], n = 0, weight = 0;
      bool newest = true;
      for (int j = 0; j < f.count; ++j)
        if (placed[j].range->shape[g - 1] == range.shape[g - 1]) {
          if (j > i) newest = false;
          members[n] = j;
          paths[n++] = placed[j].path(g, at);
          weight += placed[j].weight;
        }
      if (!newest || weight <= 0) continue;
      int64_t alpha = 0, width = 0;
      for (int m = 0; m < n; ++m) {
        const auto& p = slime::kArtPaths[paths[m]];
        alpha += int64_t(p.alpha) * placed[members[m]].weight;
        width += int64_t(p.width) * placed[members[m]].weight;
      }
      // Its opacity: the members' averaged, times their summed weight.
      alpha = alpha * std::min(weight, 4096) / (int64_t(weight) * 4096);
      if (g == 4) alpha = alpha * scalar(f.controls[7]) / 4096;
      if (g == 5) alpha = alpha * scalar(f.controls[6]) / 4096;
      raster.alpha = int(alpha);
      if (!alpha) continue;
      auto blend = [&](Point* out, int count, bool clipped) {
        for (int v = 0; v < count; ++v) {
          int64_t x = 0, y = 0;
          for (int m = 0; m < n; ++m) {
            const auto& l = placed[members[m]];
            const auto& p = slime::kArtPaths[paths[m]];
            const Point q = place(l, slime::kArtPoints[(clipped ? p.clip : p.first) + v], g);
            x += int64_t(q.x) * l.weight;
            y += int64_t(q.y) * l.weight;
          }
          // Kept in sixteenths of a pixel: a feature moves smoothly with the
          // body instead of stepping a whole pixel at a time.
          out[v] = projection.face(int(x / weight), int(y / weight));
        }
      };
      blend(vertices, path.count, false);
      blend(clip, path.clipCount, true);
      if (path.width)
        // The authored width, to a sixteenth, never thinner than 3/4 pixel.
        raster.stroke16(vertices, path.count, std::max(12, int(width / weight) * unit * 16 / 4096), path.color);
      else
        raster.polygon16(vertices, path.count, path.color, clip, path.clipCount);
    }
  }
  if (mouthOpen) {
    raster.alpha = 255;
    const auto& top = placed[f.count - 1];
    const Point p = place(top, {0, int16_t(top.baseM)}, 3);
    const Point at = projection.face(p.x, p.y);
    raster.disk16(at.x, at.y, 4 * 16 + 8, rgb565(13, 43, 72));
  }
}
}  // namespace render::gel
