#include "render/pixel/scene.h"

#include <algorithm>
#include <cstring>

#include "faces.h"
#include "render/palette.h"

namespace render {

namespace {

using namespace faces;

static_assert(kMaxGroups <= SceneFrame::kMaxGroups, "a scene's groups fit its frame");
static_assert(int(SceneState::kCount) == kStateCount, "faces.h's states");
static_assert(faces::kMaxVariants <= render::kMaxVariants, "a state's variations fit");
static_assert(int(Outcome::kFailure) == 2 && int(StartCtx::kCompacted) == 4, "faces.h's host facts");

constexpr uint16_t kNone = 0xFFFF;

// The small "o" the mouth becomes while a take is loud, from the old curious
// design asking for you, where it was the mouth: 14 × 12 px, on the mouth
// that shows, in its colour. Its middle sits on the mouth's, a pixel lower,
// which puts it where the first pack's mouth is.
struct Box {
  int16_t x, y, w, h;
};
constexpr Box kTalk[] = {{0, 0, 14, 4}, {0, 4, 4, 4}, {10, 4, 4, 4}, {0, 8, 14, 4}};
constexpr int kTalkW = 14, kTalkH = 12;
// Where the first pack's "o" sat, from its mouth's place: the "o" for a
// mouth with nothing drawn to measure.
constexpr int kTalkX = 153, kTalkY = 128;
// So a frame's talkInk, a scene colour, is black only while the mouth doesn't talk.
static_assert(kSceneBase > kBlack, "a scene colour is never black");

const Scene& scene(const SceneShow& s) { return kScenes[sceneOf(s.mood, s.state, s.variant)]; }

// A scene colour as the canvas holds it, and back: the canvas's colours
// that aren't the scene's (text, the strip) read as black.
uint8_t toCanvas(int color) { return color == 0 ? kBlack : uint8_t(kSceneBase + color - 1); }
int fromCanvas(uint8_t px) { return px >= kSceneBase && px < kSceneBase + kColorCount - 1 ? px - kSceneBase + 1 : 0; }

// The step a track is on t ms into its scene.
int step(const Track& tr, uint32_t t) {
  uint32_t lt = t % tr.dur;
  int k = 0;
  while (k + 1 < tr.n && kKeys[tr.key0 + k + 1] <= lt) ++k;
  return k;
}

// Where each group sits, whether it shows and the colour it fills with,
// parents first. A flip-book design has a face, and a mouth in it, in each
// of its steps: a press moves every face, and `mouth` is the one that
// shows, which talking opens.
struct Placed {
  // A group is drawn (kOn); shows in the design, the mouth included while
  // it talks (kShown); is the mouth that shows, or in it (kInMouth).
  static constexpr uint8_t kOn = 1, kShown = 2, kInMouth = 4;
  int16_t x[kMaxGroups], y[kMaxGroups];
  uint8_t flags[kMaxGroups];
  uint8_t fill[kMaxGroups];
  int mouth = -1;
  bool on(int i) const { return flags[i] & kOn; }
};

void place(const Scene& sc, const SceneShow& s, Placed& p) {
  for (int i = 0; i < sc.groups; ++i) {
    const Group& g = kGroups[kSceneGroups[sc.group0 + i]];
    int x = g.tx, y = g.ty;
    bool own = g.visible, shown = true, mouth = false;
    uint8_t fill = 0;
    if (g.parent != kNone) {
      x += p.x[g.parent], y += p.y[g.parent], fill = p.fill[g.parent];
      shown = p.flags[g.parent] & Placed::kShown;
      mouth = p.flags[g.parent] & Placed::kInMouth;
    }
    if (g.move != kNone) {
      const Track& tr = kTracks[g.move];
      uint32_t v = tr.val0 + 2 * uint32_t(step(tr, s.t));
      x += kValues[v], y += kValues[v + 1];
    }
    if (g.show != kNone) {
      const Track& tr = kTracks[g.show];
      own = kValues[tr.val0 + step(tr, s.t)] != 0;
    }
    if (g.fill != kNone) {
      const Track& tr = kTracks[g.fill];
      fill = uint8_t(kValues[tr.val0 + step(tr, s.t)]);
    }
    switch (g.role) {
      case kRoleFace: y += s.dy; break;
      // The first pack's eyes follow the device's blinks, not the design's.
      case kRoleEyesOpen: own = !s.eyesShut; break;
      case kRoleEyesClosed: own = s.eyesShut; break;
      // A flip-book's steps follow their own clock, and while the eyes are
      // shut, its blink step shows in place of the others.
      case kRoleStep: own = own && !s.eyesShut; break;
      case kRoleBlinkStep: own = own || s.eyesShut; break;
      default: break;
    }
    shown = shown && own;
    if (g.role == kRoleMouth && shown && p.mouth < 0) p.mouth = i, mouth = true;
    p.x[i] = int16_t(x), p.y[i] = int16_t(y), p.fill[i] = fill;
    p.flags[i] = uint8_t((shown ? Placed::kShown : 0) | (mouth ? Placed::kInMouth : 0) |
                         (shown && !(mouth && s.mouthOpen) ? Placed::kOn : 0));
  }
}

// The talking "o": where it goes and its colour, from the mouth that shows,
// all its rectangles and those of the groups in it. False with no mouth.
bool talk(const Scene& sc, const Placed& p, int16_t& ox, int16_t& oy, uint8_t& ink) {
  if (p.mouth < 0) return false;
  int x0 = kWidth, y0 = kHeight, x1 = -kWidth, y1 = -kHeight;
  int color = -1;
  for (int i = p.mouth; i < sc.groups; ++i) {
    if ((p.flags[i] & (Placed::kShown | Placed::kInMouth)) != (Placed::kShown | Placed::kInMouth)) continue;
    const Group& g = kGroups[kSceneGroups[sc.group0 + i]];
    for (int k = 0; k < g.rects; ++k) {
      const Rect& r = kRects[kRectIdx[g.rect0 + k]];
      int c = r.color == kInherit ? p.fill[i] : r.color;
      if (color < 0 && c > 0 && c < kBlend) color = c;
      if (r.x + p.x[i] < x0) x0 = r.x + p.x[i];
      if (r.y + p.y[i] < y0) y0 = r.y + p.y[i];
      if (r.x + p.x[i] + r.w > x1) x1 = r.x + p.x[i] + r.w;
      if (r.y + p.y[i] + r.h > y1) y1 = r.y + p.y[i] + r.h;
    }
  }
  if (x1 <= x0) {
    ox = int16_t(kTalkX + p.x[p.mouth]), oy = int16_t(kTalkY + p.y[p.mouth]);
  } else {
    ox = int16_t((x0 + x1) / 2 - kTalkW / 2), oy = int16_t((y0 + y1) / 2 - kTalkH / 2 + 1);
  }
  ink = toCanvas(color < 0 ? 1 : color);
  return true;
}

// A rectangle cut to the scene's clip and the screen, in colour `color`:
// translucent from kBlend on, where each pixel it covers becomes the blend
// of its colour over what's there.
void clipRect(Canvas& c, int x, int y, int w, int h, int color, const Scene& sc) {
  int x0 = std::max({x, int(sc.clipX), 0}), y0 = std::max({y, int(sc.clipY), 0});
  int x1 = std::min({x + w, sc.clipX + sc.clipW, kWidth}), y1 = std::min({y + h, sc.clipY + sc.clipH, kHeight});
  if (color < kBlend) return c.fillRect(x0, y0, x1 - x0, y1 - y0, toCanvas(color));
  uint8_t* px = c.pixels();
  for (int yy = y0; yy < y1; ++yy) {
    for (int xx = x0; xx < x1; ++xx) {
      uint8_t& d = px[yy * kWidth + xx];
      d = toCanvas(kBlendOver[color - kBlend][fromCanvas(d)]);
    }
  }
}

int moodIndex(Mood m) { return std::max(0, pixelIndex(m)); }
int stateIndex(SceneState s) { return int(s) < kStateCount ? int(s) : 0; }

// A mood and state's variation as the screen draws it: the first for one
// out of range.
const Design& design(Mood m, SceneState s, int variant) {
  int mi = moodIndex(m), si = stateIndex(s);
  int n = kVariants[mi][si];
  return kDesigns[kFirst[mi][si] + (variant >= 0 && variant < n ? variant : 0)];
}

}  // namespace

int pixelMoods() { return faces::kMoodCount; }

int pixelIndex(Mood m) {
  // Each of the pack's moods' place among the designs', looked up once.
  static const auto places = [] {
    struct Places {
      int8_t of[render::kMoodCount];
    } p{};
    for (int i = 0; i < render::kMoodCount; ++i) {
      p.of[i] = -1;
      for (int j = 0; j < faces::kMoodCount; ++j) {
        if (!std::strcmp(render::kMoodNames[i], faces::kMoodNames[j])) p.of[i] = int8_t(j);
      }
    }
    return p;
  }();
  return int(m) < render::kMoodCount ? places.of[int(m)] : -1;
}

Mood pixelMood(int i) { return moodFromName(faces::kMoodNames[i >= 0 && i < faces::kMoodCount ? i : 0]); }

int variants(Mood m, SceneState s) { return kVariants[moodIndex(m)][stateIndex(s)]; }

Outcome variantOutcome(Mood m, SceneState s, int variant) { return Outcome(design(m, s, variant).outcome); }
StartCtx variantCtx(Mood m, SceneState s, int variant) { return StartCtx(design(m, s, variant).ctx); }

int fitting(Mood m, SceneState s, Outcome o, StartCtx c, uint8_t* out) {
  int n = variants(m, s), k = 0;
  for (int v = 0; v < n; ++v) {
    const Design& d = design(m, s, v);
    if ((o == Outcome::kNone || d.outcome == uint8_t(o)) && (c == StartCtx::kNone || d.ctx == uint8_t(c))) {
      out[k++] = uint8_t(v);
    }
  }
  if (k == 0) {
    for (int v = 0; v < n; ++v) out[k++] = uint8_t(v);
  }
  return k;
}

int sceneOf(Mood m, SceneState s, int variant) { return design(m, s, variant).scene; }

uint32_t loopMs(Mood m, SceneState s, int variant) { return kScenes[sceneOf(m, s, variant)].loopMs; }

uint8_t sceneInk(int color) { return color > 0 && color < kColorCount ? toCanvas(color) : kBlack; }

bool blinksItself(Mood m, SceneState s, int variant) {
  const Scene& sc = kScenes[sceneOf(m, s, variant)];
  for (int i = 0; i < sc.groups; ++i) {
    if (kGroups[kSceneGroups[sc.group0 + i]].role == kRoleBlinkStep) return true;
  }
  return false;
}

bool eyesClosed(const SceneShow& s) {
  const Scene& sc = scene(s);
  Placed p;
  place(sc, s, p);
  bool opens = false;
  for (int i = 0; i < sc.groups; ++i) {
    uint8_t role = kGroups[kSceneGroups[sc.group0 + i]].role;
    if ((role == kRoleEyesClosed || role == kRoleBlinkStep) && p.on(i)) return true;
    opens = opens || role == kRoleEyesOpen || role == kRoleStep;
  }
  return !opens;  // a design with no eyes to open, such as the first pack's asleep, keeps them shut
}

bool operator==(const SceneFrame& a, const SceneFrame& b) { return std::memcmp(&a, &b, sizeof a) == 0; }

SceneFrame sceneFrame(const SceneShow& s) {
  SceneFrame f;
  std::memset(&f, 0, sizeof f);  // padding too, since frames compare as bytes
  f.scene = uint16_t(sceneOf(s.mood, s.state, s.variant));
  f.talkX = f.talkY = -1;
  const Scene& sc = kScenes[f.scene];
  Placed p;
  place(sc, s, p);
  for (int i = 0; i < sc.groups; ++i) {
    if (!p.on(i)) continue;
    f.x[i] = p.x[i], f.y[i] = p.y[i], f.on[i] = 1, f.fill[i] = p.fill[i];
  }
  if (s.mouthOpen) talk(sc, p, f.talkX, f.talkY, f.talkInk);
  return f;
}

void drawScene(Canvas& c, const SceneFrame& f) {
  const Scene& sc = kScenes[f.scene];
  for (int i = 0; i < sc.groups; ++i) {
    if (!f.on[i]) continue;
    const Group& g = kGroups[kSceneGroups[sc.group0 + i]];
    for (int k = 0; k < g.rects; ++k) {
      const Rect& r = kRects[kRectIdx[g.rect0 + k]];
      clipRect(c, r.x + f.x[i], r.y + f.y[i], r.w, r.h, r.color == kInherit ? f.fill[i] : r.color, sc);
    }
  }
  if (f.talkInk != kBlack) {
    for (const Box& b : kTalk) c.fillRect(f.talkX + b.x, f.talkY + b.y, b.w, b.h, f.talkInk);
  }
}

void drawFaceScreen(Canvas& c, const SceneFrame& face, const char* bubble, const Strip& s) {
  c.fill(kBlack);
  drawScene(c, face);
  drawLane(c, bubble, s);
}

}  // namespace render
