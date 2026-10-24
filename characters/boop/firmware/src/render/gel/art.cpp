#include "render/gel/engine.h"
#include "render/gel/geometry.h"
#include "render/gel/painter.h"
#include "render/gel/raster.h"
#include "slime_art.h"
namespace render::gel {
namespace {
constexpr int kMaxPoints = 96;
constexpr int kLayers = SemanticFace::kMaxLayers;
// The most paths an art has.
constexpr int maxPaths() {
  int most = 0;
  for (const auto& art : slime::kArt) most = std::max(most, int(art.count));
  return most;
}
constexpr int kMaxPaths = maxPaths();
// One face layer's art, as the controls place it and at its drawn scales,
// in Q12 face units: what the painter blends or fades.
struct Placed {
  const slime::ArtRange* range;
  int baseX, baseY, baseM, eye, mouthWidth, mouthHeight, weight;
};
// The layers' paths, paired: for each path of a layer's art, each layer's
// path of its group in the same place, where that layer's art has the
// group in the same shape (else -1), and whether this layer is the newest
// of them, which draws them. It depends only on the arts, so it is worked
// out again only when they change: at a retarget, or a cross-over's end.
struct Pairing {
  int count = 0, arts[kLayers]{};
  int16_t path[kLayers][kMaxPaths][kLayers];
  bool newest[kLayers][kMaxPaths];
};
const Pairing& pairing(const SemanticFace& f) {
  static Pairing p;
  bool same = p.count == f.count;
  for (int i = 0; same && i < f.count; ++i) same = p.arts[i] == f.layers[i].art;
  if (same) return p;
  p.count = f.count;
  for (int i = 0; i < f.count; ++i) p.arts[i] = f.layers[i].art;
  for (int i = 0; i < f.count; ++i) {
    const auto& range = slime::kArt[p.arts[i]];
    int nth[6] = {};
    for (int k = 0; k < range.count; ++k) {
      const int g = slime::kArtPaths[range.first + k].group, at = nth[g]++;
      p.newest[i][k] = true;
      for (int j = 0; j < f.count; ++j) {
        const auto& other = slime::kArt[p.arts[j]];
        p.path[i][k][j] = -1;
        if (other.shape[g - 1] != range.shape[g - 1]) continue;
        if (j > i) p.newest[i][k] = false;
        for (int m = 0, seen = 0; m < other.count; ++m)
          if (slime::kArtPaths[other.first + m].group == g && seen++ == at) {
            p.path[i][k][j] = int16_t(other.first + m);
            break;
          }
      }
    }
  }
  return p;
}
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
  Placed placed[kLayers];
  for (int i = 0; i < f.count; ++i) {
    const auto& l = f.layers[i];
    const auto& face = slime::kProfile[l.art].face;
    const auto scale = drawnScale(f, l);
    placed[i] = {&slime::kArt[l.art], scalar(face[0]),  scalar(face[1]),  scalar(face[3]),
                 scalar(scale[0]),    scalar(scale[1]), scalar(scale[2]), scalar(l.weight)};
  }
  const Pairing& pairs = pairing(f);
  // Where the controls put a point of a layer's art, in Q12 face units:
  // under 2^16 either way, the art's 16-bit points moved by controls of
  // under one (4096) and scaled by ratios under 4/3.
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
    for (int k = 0; k < range.count; ++k) {
      const auto& path = slime::kArtPaths[range.first + k];
      const int g = path.group;
      if (!pairs.newest[i][k] || path.count > kMaxPoints || path.clipCount > kMaxPoints) continue;
      // The layers whose art has this group's shape: drawn once, with the
      // newest of them.
      int members[kLayers], paths[kLayers], n = 0, weight = 0;
      for (int j = 0; j < f.count; ++j)
        if (pairs.path[i][k][j] >= 0) {
          members[n] = j;
          paths[n++] = pairs.path[i][k][j];
          weight += placed[j].weight;
        }
      if (weight <= 0) continue;
      // The weights are shares of one, so they sum to at most 4096 and
      // every sum by weight below stays far inside 32 bits: an opacity's
      // under 2^20, a pen's under 2^28, a point's under 2^28.
      int alpha = 0, width = 0;
      for (int m = 0; m < n; ++m) {
        const auto& p = slime::kArtPaths[paths[m]];
        alpha += p.alpha * placed[members[m]].weight;
        width += p.width * placed[members[m]].weight;
      }
      // Its opacity: the members' averaged, times their summed weight (at
      // most one).
      alpha /= std::max(weight, 4096);
      if (g == 4) alpha = alpha * scalar(f.controls[7]) / 4096;
      if (g == 5) alpha = alpha * scalar(f.controls[6]) / 4096;
      raster.alpha = alpha;
      if (!alpha) continue;
      auto blend = [&](Point* out, int count, bool clipped) {
        if (n == 1) {  // one art's: its own points, as authored
          const auto& p = slime::kArtPaths[paths[0]];
          for (int v = 0; v < count; ++v) {
            const Point q = place(placed[members[0]], slime::kArtPoints[(clipped ? p.clip : p.first) + v], g);
            out[v] = projection.face(q.x, q.y);
          }
          return;
        }
        for (int v = 0; v < count; ++v) {
          int x = 0, y = 0;
          for (int m = 0; m < n; ++m) {
            const auto& l = placed[members[m]];
            const auto& p = slime::kArtPaths[paths[m]];
            const Point q = place(l, slime::kArtPoints[(clipped ? p.clip : p.first) + v], g);
            x += q.x * l.weight;
            y += q.y * l.weight;
          }
          // Kept in sixteenths of a pixel: a feature moves smoothly with the
          // body instead of stepping a whole pixel at a time.
          out[v] = projection.face(x / weight, y / weight);
        }
      };
      blend(vertices, path.count, false);
      blend(clip, path.clipCount, true);
      if (path.width)
        // The authored width, to a sixteenth, never thinner than 3/4 pixel.
        raster.stroke16(vertices, path.count, std::max(12, width / weight * unit * 16 / 4096), path.color);
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
