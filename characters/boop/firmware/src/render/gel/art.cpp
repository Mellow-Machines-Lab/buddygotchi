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
constexpr int kMaxPaths = maxPaths(), kMaxSteps = kLayers * kMaxPaths;
// One face layer's art, as the controls place it and at its drawn scales,
// in Q12 face units: what the painter blends or fades.
struct Placed {
  const slime::ArtRange* range;
  int baseX, baseY, baseM, eye, mouthWidth, mouthHeight, weight;
};
// The layers' arts, paired and in one order. It depends only on the arts,
// so it is worked out again only when they change: at a retarget, or a
// cross-over's end.
struct Pairing {
  int count = 0, arts[kLayers]{};
  // For each path of a layer's art, each layer's path of its group in the
  // same place, where that layer's art has the group in the same shape
  // (else -1).
  int16_t path[kLayers][kMaxPaths][kLayers];
  // Each layer's art in runs, its paths in a row of one group and one ink,
  // which make one picture: run r is its paths [run[r], run[r + 1]).
  int runs[kLayers]{};
  int8_t run[kLayers][kMaxPaths + 1];
  // For each run, each layer's run of the same paths in the same shape,
  // drawn once, or -1.
  int8_t same[kLayers][kMaxPaths][kLayers];
  // The draw order: each step one run of each layer it has (else -1), its
  // runs of one group, the same paths or of one ink, drawn at once.
  int steps = 0;
  int8_t step[kMaxSteps][kLayers];
};
// A step's claim on layer j's run r, merging it in: kSame for the run of its
// paths there, 1 for one of its group and ink that's the same as none
// before, else 0. The same paths must be one step, so they outweigh every
// ink there can be.
constexpr int kSame = 2 * kMaxPaths;
int claim(const Pairing& p, int s, int j, int r) {
  const auto& path = slime::kArtPaths[slime::kArt[p.arts[j]].first + p.run[j][r]];
  int same = -1, group = 0, color = -1;
  for (int i = 0; i < j; ++i) {
    const int e = p.step[s][i];
    if (e < 0) continue;
    const auto& own = slime::kArtPaths[slime::kArt[p.arts[i]].first + p.run[i][e]];
    group = own.group, color = own.color;
    if (p.same[i][e][j] >= 0) same = p.same[i][e][j];
  }
  if (same >= 0) return same == r ? kSame : 0;
  for (int i = 0; i < j; ++i)
    if (p.same[j][r][i] >= 0) return 0;
  return path.group == group && path.color == color ? 1 : 0;
}
// Layer j's runs merged into the steps so far: the order that keeps each
// layer's own and makes the most of their claims (a longest common
// subsequence), its runs otherwise as late as they can be, over the older.
void merge(Pairing& p, int j) {
  const int steps = p.steps, n = p.runs[j];
  int16_t most[kMaxSteps + 1][kMaxPaths + 1];
  for (int s = 0; s <= steps; ++s)
    for (int r = 0; r <= n; ++r) {
      int best = 0;
      if (s) best = std::max(best, int(most[s - 1][r]));
      if (r) best = std::max(best, int(most[s][r - 1]));
      if (s && r) {
        const int gain = claim(p, s - 1, j, r - 1);
        if (gain) best = std::max(best, most[s - 1][r - 1] + gain);
      }
      most[s][r] = int16_t(best);
    }
  int8_t merged[kMaxSteps][kLayers];
  int m = 0;
  for (int s = steps, r = n; (s || r) && m < kMaxSteps; ++m) {
    if (r && most[s][r] == most[s][r - 1]) {  // layer j's alone
      std::fill(merged[m], merged[m] + kLayers, int8_t(-1));
      merged[m][j] = int8_t(--r);
      continue;
    }
    std::copy(p.step[s - 1], p.step[s - 1] + kLayers, merged[m]);
    if (most[s][r] != most[s - 1][r]) merged[m][j] = int8_t(--r);
    --s;
  }
  p.steps = m;
  for (int i = 0; i < m; ++i) std::copy(merged[m - 1 - i], merged[m - i], p.step[i]);
}
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
    p.runs[i] = 0;
    for (int k = 0; k < range.count; ++k) {
      const auto& path = slime::kArtPaths[range.first + k];
      const int g = path.group, at = nth[g]++;
      if (!k || path.group != slime::kArtPaths[range.first + k - 1].group ||
          path.color != slime::kArtPaths[range.first + k - 1].color)
        p.run[i][p.runs[i]++] = int8_t(k);
      for (int j = 0; j < f.count; ++j) {
        const auto& other = slime::kArt[p.arts[j]];
        p.path[i][k][j] = -1;
        if (other.shape[g - 1] != range.shape[g - 1]) continue;
        for (int m = 0, seen = 0; m < other.count; ++m)
          if (slime::kArtPaths[other.first + m].group == g && seen++ == at) {
            p.path[i][k][j] = int16_t(other.first + m);
            break;
          }
      }
    }
    p.run[i][p.runs[i]] = int8_t(range.count);
  }
  // A run's paths are the same as another layer's run when they pair with
  // it, path for path: two arts with a group in one shape have its paths
  // in the same order, so its first path pairing with a run's first, the
  // two of one length, is enough.
  for (int i = 0; i < f.count; ++i)
    for (int r = 0; r < p.runs[i]; ++r)
      for (int j = 0; j < f.count; ++j) {
        p.same[i][r][j] = -1;
        const int first = p.path[i][p.run[i][r]][j] - slime::kArt[p.arts[j]].first;
        for (int q = 0; first >= 0 && q < p.runs[j]; ++q)
          if (p.run[j][q] == first && p.run[j][q + 1] - first == p.run[i][r + 1] - p.run[i][r])
            p.same[i][r][j] = int8_t(q);
      }
  p.steps = p.runs[0];
  for (int r = 0; r < p.steps; ++r) {
    std::fill(p.step[r], p.step[r] + kLayers, int8_t(-1));
    p.step[r][0] = int8_t(r);
  }
  for (int j = 1; j < f.count; ++j) merge(p, j);
  return p;
}
// The points of the shapes a step draws at once.
constexpr int kPoolPoints = 320;
Point pool[kPoolPoints];
}  // namespace
// The engine's face layers: settled, one art as authored. While arts cross
// over, their paths are drawn in one order that keeps each art's own, so
// nothing changes places as a layer comes in or goes out. A group (an eye,
// the mouth, the tears, the cheeks) that has one shape in several layers is
// drawn once, their points, widths and opacities averaged by weight, at
// their summed weight; groups of different shapes cross-fade, each at its
// weight, their paths of one ink drawn as one (Raster::sum), so where both
// cover a pixel it keeps the ink instead of showing the body through.
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
  // A step's pictures: the layers whose runs there are the same paths, drawn
  // once, their members' paths (each run's first) and weights summed.
  struct Picture {
    int members[kLayers], paths[kLayers], n = 0, length = 0, weight = 0;
  };
  for (int s = 0; s < pairs.steps; ++s) {
    Picture pictures[kLayers];
    int count = 0;
    for (int j = 0; j < f.count; ++j) {
      const int r = pairs.step[s][j];
      if (r < 0) continue;
      int at = 0;
      while (at < count && pairs.same[pictures[at].members[0]][pairs.step[s][pictures[at].members[0]]][j] != r) ++at;
      if (at == count) ++count;
      Picture& into = pictures[at];
      into.members[into.n] = j, into.paths[into.n++] = placed[j].range->first + pairs.run[j][r];
      into.length = pairs.run[j][r + 1] - pairs.run[j][r];
      into.weight += placed[j].weight;
    }
    const auto& first = slime::kArtPaths[pictures[0].paths[0]];
    const int g = first.group;
    if (!c.eyes && (g == 1 || g == 2)) continue;
    // Two pictures or more are summed; one draws its shapes as they come.
    int live = 0;
    for (int k = 0; k < count; ++k) live += pictures[k].weight > 0;
    Raster::Shape drawn[2 * kLayers];
    int drawnCount = 0, used = 0, alone = 0;
    // What's kept: one shape as it's always drawn, at its opacity times its
    // weight (`alone`), more summed.
    auto draw = [&] {
      if (drawnCount == 1) {
        raster.alpha = alone;
        if (drawn[0].width16)
          raster.stroke16(drawn[0].v, drawn[0].n, drawn[0].width16, first.color);
        else
          raster.polygon16(drawn[0].v, drawn[0].n, first.color, drawn[0].clip, drawn[0].clipCount);
      } else if (drawnCount) {
        raster.alpha = 255;
        raster.sum(drawn, drawnCount, first.color);
      }
      drawnCount = used = 0;
    };
    for (int k = 0; k < count; ++k) {
      const Picture& picture = pictures[k];
      const int weight = picture.weight;
      if (weight <= 0) continue;
      for (int t = 0; t < picture.length; ++t) {
        const auto& path = slime::kArtPaths[picture.paths[0] + t];
        if (path.count > kMaxPoints || path.clipCount > kMaxPoints) continue;
        // The weights are shares of one, so they sum to at most 4096 and
        // every sum by weight below stays far inside 32 bits: an opacity's
        // under 2^20, a pen's under 2^28, a point's under 2^28.
        int alpha = 0, width = 0;
        for (int m = 0; m < picture.n; ++m) {
          const auto& p = slime::kArtPaths[picture.paths[m] + t];
          alpha += p.alpha * placed[picture.members[m]].weight;
          width += p.width * placed[picture.members[m]].weight;
        }
        // Its opacity: the members' averaged, and that times their summed
        // weight (at most one) drawn alone.
        int own = std::min(255, alpha / weight);
        alpha /= std::max(weight, 4096);
        if (g == 4) alpha = alpha * scalar(f.controls[7]) / 4096, own = own * scalar(f.controls[7]) / 4096;
        if (g == 5) alpha = alpha * scalar(f.controls[6]) / 4096, own = own * scalar(f.controls[6]) / 4096;
        if (!alpha) continue;
        // A step's shapes are drawn at once as far as the pool holds them.
        if (used + path.count + path.clipCount > kPoolPoints || drawnCount == 2 * kLayers) draw();
        Point* vertices = pool + used;
        Point* clip = vertices + path.count;
        auto blend = [&](Point* out, int n, bool clipped) {
          if (picture.n == 1) {  // one art's: its own points, as authored
            const auto& p = slime::kArtPaths[picture.paths[0] + t];
            for (int v = 0; v < n; ++v) {
              const Point q = place(placed[picture.members[0]], slime::kArtPoints[(clipped ? p.clip : p.first) + v], g);
              out[v] = projection.face(q.x, q.y);
            }
            return;
          }
          for (int v = 0; v < n; ++v) {
            int x = 0, y = 0;
            for (int m = 0; m < picture.n; ++m) {
              const auto& l = placed[picture.members[m]];
              const auto& p = slime::kArtPaths[picture.paths[m] + t];
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
        // The authored width, to a sixteenth, never thinner than 3/4 pixel.
        const int width16 =
            path.width ? std::max(12, int(int64_t(width / weight) * unit * 16 / 4096 * c.scale / 4096)) : 0;
        drawn[drawnCount] = {vertices, path.count, clip, path.clipCount, width16, own, weight, drawnCount && t};
        ++drawnCount, alone = alpha;
        used += path.count + path.clipCount;
        if (live == 1) draw();
      }
    }
    draw();
  }
  if (mouthOpen) {
    raster.alpha = 255;
    const auto& top = placed[f.count - 1];
    const Point p = place(top, {0, int16_t(top.baseM)}, 3);
    const Point at = projection.face(p.x, p.y);
    raster.disk16(at.x, at.y, (4 * 16 + 8) * c.scale / 4096, rgb565(13, 43, 72));
  }
}
}  // namespace render::gel
