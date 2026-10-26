#include "render/gel/engine.h"
#include "render/gel/geometry.h"
#include "render/gel/painter.h"
#include "render/gel/raster.h"
#include "render/tags.h"
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
// group in the same shape (else -1), and whether this layer is the oldest
// of them, which draws them, at its own turn: a face coming in at weight
// zero then moves nothing the faces before it share to a new place in the
// draw order. It depends only on the arts, so it is worked out again only
// when they change: at a retarget, or a cross-over's end.
struct Pairing {
  int count = 0, arts[kLayers]{};
  int16_t path[kLayers][kMaxPaths][kLayers];
  bool oldest[kLayers][kMaxPaths];
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
      p.oldest[i][k] = true;
      for (int j = 0; j < f.count; ++j) {
        const auto& other = slime::kArt[p.arts[j]];
        p.path[i][k][j] = -1;
        if (other.shape[g - 1] != range.shape[g - 1]) continue;
        if (j < i) p.oldest[i][k] = false;
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
// Room for a cross-fading group's looks (kCrossingBytes, raster.h): one block
// made at start, so on the board it's PSRAM's, not its scarce internal
// memory's.
struct Crossing {
  uint8_t bytes[kCrossingBytes];
  CrossFade fade{bytes, kCrossingBytes};
};
CrossFade& crossing = (new Crossing)->fade;
}  // namespace
int crossingPeak = 0;
// The engine's face layers: settled,
// one art as authored. While arts cross over, a group (an eye, the mouth,
// the tears, the cheeks) that has one shape in several layers is drawn once,
// their points, widths and opacities averaged by weight, at their summed
// weight; groups of different shapes cross-fade, each laid over the body
// alone and the two blended by weight, so nothing shows through mid-way.
void paintArt(Surface& surface, const Engine& engine, const PaintControls& c, bool mouthOpen, rig::Anchors* anchors) {
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
      x = side * eyeX + c.gaze + int(int64_t(x - side * l.baseX) * c.eyeSize / 4096);
      y = eyeY + c.gazeUp + int(int64_t(y - l.baseY) * l.eye * (4096 - c.blink) / (4096 * 4096) * c.eyeSize / 4096);
    } else if (group == 3) {
      x = x * l.mouthWidth / 4096;
      y = mouthY + (y - l.baseM) * l.mouthHeight / 4096;
    }
    return Point{x, y};
  };
  if (anchors) {  // each eye's middle, where its art is centred
    const Point l = projection.face(-eyeX + c.gaze, eyeY + c.gazeUp),
                r = projection.face(eyeX + c.gaze, eyeY + c.gazeUp);
    anchors->eyeL = l, anchors->eyeR = r;
  }
  Point vertices[kMaxPoints], clip[kMaxPoints];
  // The layers whose art has the group of layer i's path k in its shape,
  // and their summed weight: drawn once, with the oldest of them.
  auto classWeight = [&](int i, int k) {
    int weight = 0;
    for (int j = 0; j < f.count; ++j)
      if (pairs.path[i][k][j] >= 0) weight += placed[j].weight;
    return weight;
  };
  // Hushed, its mouth is the zipped one, not the art's (paintZip).
  const bool zipped = hushed(engine);
  auto drawn = [&](int i, int k) {
    const auto& path = slime::kArtPaths[placed[i].range->first + k];
    const int g = path.group;
    return pairs.oldest[i][k] && path.count <= kMaxPoints && path.clipCount <= kMaxPoints &&
           (c.eyes || (g != 1 && g != 2)) && !(zipped && g == 3) && classWeight(i, k) > 0;
  };
  // Each group's shapes, drawn as one look for each shape the layers give
  // it; a group with two or more cross-fades. Its looks are drawn together
  // at the last one's first path, each with its own paths at their own
  // opacities, then blended by their weights (Raster::blend).
  int looks[6] = {}, lastLook[6], firstPath[6];
  for (int i = 0; i < f.count; ++i) {
    bool counted[6] = {};
    const auto& range = *placed[i].range;
    for (int k = 0; k < range.count; ++k) {
      const int g = slime::kArtPaths[range.first + k].group;
      if (!drawn(i, k)) continue;
      if (!counted[g]) ++looks[g], counted[g] = true, lastLook[g] = i, firstPath[g] = k;
    }
  }
  auto draw = [&](int i, int k, bool weighted) {
    const auto& path = slime::kArtPaths[placed[i].range->first + k];
    const int g = path.group;
    int members[kLayers], paths[kLayers], n = 0, weight = 0;
    for (int j = 0; j < f.count; ++j)
      if (pairs.path[i][k][j] >= 0) {
        members[n] = j;
        paths[n++] = pairs.path[i][k][j];
        weight += placed[j].weight;
      }
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
    // most one) when it's drawn straight over what's under it.
    alpha /= weighted ? std::max(weight, 4096) : weight;
    if (g == 4) alpha = alpha * scalar(f.controls[7]) / 4096;
    if (g == 5) alpha = alpha * scalar(f.controls[6]) / 4096;
    raster.alpha = alpha;
    if (!alpha) return;
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
      raster.stroke16(vertices, path.count,
                      std::max(12, int(int64_t(width / weight) * unit * 16 / 4096 * c.scale / 4096)), path.color);
    else
      raster.polygon16(vertices, path.count, path.color, clip, path.clipCount);
  };
  for (int i = 0; i < f.count; ++i) {
    const auto& range = *placed[i].range;
    for (int k = 0; k < range.count; ++k) {
      if (!drawn(i, k)) continue;
      const int g = slime::kArtPaths[range.first + k].group;
      if (looks[g] < 2) {
        draw(i, k, true);
        continue;
      }
      if (i != lastLook[g] || k != firstPath[g]) continue;
      // The group's looks, kept, then blended once.
      crossing.clear();
      for (int j = 0; j < f.count; ++j) {
        const auto& own = *placed[j].range;
        bool started = false;
        for (int m = 0; m < own.count; ++m) {
          if (slime::kArtPaths[own.first + m].group != g || !drawn(j, m)) continue;
          if (!started) crossing.look(classWeight(j, m)), started = true;
          raster.recording = crossing.next();
          if (raster.recording) draw(j, m, false);
        }
      }
      raster.recording = nullptr;
      crossingPeak = std::max(crossingPeak, crossing.used());
      if (crossing.kept()) {
        raster.alpha = 255;
        raster.blend(crossing);
        continue;
      }
      // Too much to keep: drawn one over the other, as they'd fade alone.
      for (int j = 0; j < f.count; ++j) {
        const auto& own = *placed[j].range;
        for (int m = 0; m < own.count; ++m)
          if (slime::kArtPaths[own.first + m].group == g && drawn(j, m)) draw(j, m, true);
      }
    }
  }
  if (zipped) {
    paintZip(surface, engine, c);
  } else if (mouthOpen) {
    raster.alpha = 255;
    const auto& top = placed[f.count - 1];
    const Point p = place(top, {0, int16_t(top.baseM)}, 3);
    const Point at = projection.face(p.x, p.y);
    raster.disk16(at.x, at.y, (4 * 16 + 8) * c.scale / 4096, rgb565(13, 43, 72));
  }
}
bool hushed(const Engine& e) { return hasTag(e.scenes.when, "hushed"); }
void paintZip(Surface& surface, const Engine& e, const PaintControls& c) {
  if (!surface.pixels) return;
  // The mouth's ink: its lines', as the calm art draws them.
  static const uint16_t ink = [] {
    const auto& calm = slime::kArt[slime::kCalm];
    for (int k = 0; k < calm.count; ++k) {
      const auto& p = slime::kArtPaths[calm.first + k];
      if (p.group == 3 && p.width) return p.color;
    }
    return uint16_t(0);
  }();
  Raster raster{surface};
  const Projector projection(surface, c);
  const int mouthY = scalar(e.face.controls[3]);
  // A pen in the art's widths, in sixteenths of a pixel, as paintArt
  // strokes them.
  const int unit = surface.height * 3 / 5;
  auto pen = [&](int width) { return std::max(12, int(int64_t(width) * unit * 16 / 4096 * c.scale / 4096)); };
  // The line in a few steps, so it bends over the dome as the face does.
  constexpr int kSteps = 4;
  Point line[kSteps + 1];
  for (int i = 0; i <= kSteps; ++i) line[i] = projection.face(-kZipHalf + 2 * kZipHalf * i / kSteps, mouthY);
  raster.stroke16(line, kSteps + 1, pen(kZipPen), ink);
  for (int i = 0; i < kZipTicks; ++i) {
    const int x = -kZipHalf + 2 * kZipHalf * (i + 1) / (kZipTicks + 1);
    const Point tick[2] = {projection.face(x, mouthY + kZipTick), projection.face(x, mouthY - kZipTick)};
    raster.stroke16(tick, 2, pen(kZipTickPen), ink);
  }
}
}  // namespace render::gel
