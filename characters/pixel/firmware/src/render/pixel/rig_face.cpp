#include "render/pixel/rig_face.h"

#include <algorithm>
#include <cstring>

#include "faces.h"
#include "render/maths.h"
#include "rig_tables.h"  // the staged pack's (characters/charactergen.py)

namespace render::pixel {

namespace {

using rig::Channel;
using rig::Channels;
using rig::kRig;

constexpr int kOne = 1024;  // a scale of 1, and a morph's whole way
// Where the face squashes onto and leans from: under its mouth. At a squash
// of 1000 it's half as tall and a quarter wider.
constexpr int kGround = 150, kMiddle = kWidth / 2;
constexpr int kSquashTall = 512, kSquashWide = 256;
// A lean of 1000 moves the top of the eyes (about 94 px up) 12 px; a gaze of
// 1000, the eyes 8 px.
constexpr int kLeanPer = 8000, kGazePx = 8;
// An eye this little open, of its art, shows its shut art.
constexpr int kShutBelow = kOne / 3;

int scaled(int v, int s) { return (v * s + kOne / 2) >> 10; }
// A channel's offset from rest, in thousandths, as a scale of the art.
int scale(int offset) { return kOne + offset * kOne / 1000; }

// The body: the whole face scaled about the ground's middle (1024ths),
// lifted and leaned, from the channels' offsets from rest, and moved as
// its design moves it.
struct Body {
  int sx = kOne, sy = kOne, dx = 0, dy = 0, lean = 0;
  Body(const Channels& d, int press, FaceMove m)
      : sx(kOne + d[Channel::kSquash] * kSquashWide / 1000),
        sy(kOne - d[Channel::kSquash] * kSquashTall / 1000),
        dx(m.dx),
        dy(press + m.dy - d[Channel::kLift]),
        lean(d[Channel::kLean]) {}
  rig::Point at(int x, int y) const {
    return {kMiddle + scaled(x - kMiddle, sx) + dx + lean * (kGround - y) / kLeanPer,
            kGround + scaled(y - kGround, sy) + dy};
  }
  // A part placed by its pivot and scale before the body, through it, each
  // scale the nearest that draws its art a whole pixel wider or taller: two
  // scales drawing the same pixels are one, so a frame changes only when
  // its picture does (the device skips drawing an unchanged one).
  Placed place(Placed p) const {
    const rig::Point at = this->at(p.x, p.y);
    const faces::Part& art = faces::kParts[p.style][p.kind];
    p.x = int16_t(at.x), p.y = int16_t(at.y);
    p.sx = int16_t(whole(scaled(p.sx, sx), art.x1 - art.x0));
    p.sy = int16_t(whole(scaled(p.sy, sy), art.y1 - art.y0));
    return p;
  }
  static int whole(int s, int px) { return px > 0 ? (s * px + kOne / 2) / kOne * kOne / px : s; }
};

// Part `kind` of style a, q of the way (0 … kOne) to style b's: its box
// moved and scaled toward b's box. Without b, as its art has it.
Placed morph(int a, int b, int kind, int q) {
  const faces::Part &A = faces::kParts[a][kind], &B = faces::kParts[b][kind];
  const int x0 = lerp(A.x + A.x0, B.x + B.x0, q, kOne), x1 = lerp(A.x + A.x1, B.x + B.x1, q, kOne);
  const int y0 = lerp(A.y + A.y0, B.y + B.y0, q, kOne), y1 = lerp(A.y + A.y1, B.y + B.y1, q, kOne);
  Placed p;
  p.style = uint8_t(a), p.kind = uint8_t(kind);
  p.sx = int16_t((x1 - x0) * kOne / std::max(1, A.x1 - A.x0));
  p.sy = int16_t((y1 - y0) * kOne / std::max(1, A.y1 - A.y0));
  p.x = int16_t(x0 - scaled(A.x0, p.sx)), p.y = int16_t(y0 - scaled(A.y0, p.sy));
  return p;
}

// A style fader's drawn styles: the one fading out (or the only one) and
// the one fading in, and each one's share of `outer`.
struct Faded {
  int n = 1, part[2] = {}, other[2] = {}, q[2] = {};
  Dither dither[2];
};
Faded faded(const rig::Style& s, Dither outer) {
  Faded f;
  f.part[0] = f.other[1] = s.index, f.other[0] = f.part[1] = s.next, f.dither[0] = outer;
  if (s.index == s.next) return f;
  const int q = s.mix * kOne / 1000;
  f.n = 2, f.q[0] = q, f.q[1] = kOne - q;
  f.dither[0] = Dither::fade(s.mix, false).within(outer), f.dither[1] = Dither::fade(s.mix, true).within(outer);
  return f;
}

rig::Anchors anchorsOf(const rig::Style& eyes, const Body& body) {
  const Faded f = faded(eyes, {});
  // The eyes' boxes, as they show (the one going out's, as it morphs).
  const Placed l = morph(f.part[0], f.other[0], faces::kPartEyeL, f.q[0]);
  const Placed r = morph(f.part[0], f.other[0], faces::kPartEyeR, f.q[0]);
  const faces::Part &L = faces::kParts[f.part[0]][faces::kPartEyeL], &R = faces::kParts[f.part[0]][faces::kPartEyeR];
  const int top = std::min(l.y + scaled(L.y0, l.sy), r.y + scaled(R.y0, r.sy));
  const int left = l.x + scaled(L.x0, l.sx), right = r.x + scaled(R.x1, r.sx);
  rig::Anchors a;
  a.crown = a.brimF = body.at(kMiddle, top);
  a.brimL = body.at(left, top), a.brimR = body.at(right, top);
  a.handF = body.at(kMiddle, kGround);
  a.eyeL = body.at(l.x, l.y), a.eyeR = body.at(r.x, r.y);
  return a;
}

// The drawn mood a style names, -1 for none.
int drawn(const char* style) {
  for (int i = 0; i < faces::kMoodCount; ++i)
    if (!std::strcmp(style, faces::kMoodNames[i])) return i;
  return -1;
}

}  // namespace

bool RigFrame::operator==(const RigFrame& o) const {
  static_assert(sizeof(RigFrame) == RigFrame::kMaxParts * sizeof(Placed) + 8, "a frame has no padding to compare");
  return !std::memcmp(this, &o, sizeof o);
}

const RigFace::Pose* RigFace::pose(Mood m) {
  static const auto poses = [] {
    struct Poses {
      Pose of[kMoodCount];
      bool has[kMoodCount];
    } p{};
    for (int i = 0; i < kMoodCount; ++i) {
      const rig::Expression* e = kRig.expression(kMoodNames[i]);
      const int wears = pixelIndex(Mood(i));
      if (!e && wears >= 0) e = kRig.expression(faces::kMoodNames[wears]);
      const int eyes = e ? drawn(e->eyes) : -1, mouth = e ? drawn(e->mouth) : -1;
      if (eyes < 0 || mouth < 0) continue;
      const rig::Anchors rest = anchorsOf({uint8_t(eyes), uint8_t(eyes), 0}, Body(Channels{}, 0, {}));
      p.of[i] = {uint8_t(eyes), uint8_t(mouth), rest.brimF, rest.handF};
      p.has[i] = true;
    }
    return p;
  }();
  return int(m) < kMoodCount && poses.has[int(m)] ? &poses.of[int(m)] : nullptr;
}

void RigFace::reset(Mood m, SceneState base, uint32_t t) {
  const Pose* p = pose(m);
  const rig::Look* look = kRig.look(base);
  mixer_.reset(p ? p->eyes : 0, p ? p->mouth : 0, look ? look->clip : nullptr);
  at_ = t;
  finger_ = false;
}

void RigFace::setMood(Mood m) {
  if (const Pose* p = pose(m)) mixer_.setStyles(p->eyes, p->mouth);
}

void RigFace::setLook(SceneState base) {
  const rig::Look* look = kRig.look(base);
  mixer_.setLook(look ? look->clip : nullptr);
}

void RigFace::advanceTo(uint32_t t) {
  if (after(t, at_)) mixer_.advance(t - at_);
  at_ = t;
}

void RigFace::blink() {
  if (const rig::Clip* clip = kRig.clip("blink")) mixer_.play(*clip);
}

void RigFace::finger(bool down, int x, int) {
  if (!down) {
    finger_ = false;
  } else if (!finger_) {
    finger_ = true, fingerX_ = x;
    mixer_.impulse(Channel::kSquash, kPressKick);
  } else {
    mixer_.impulse(Channel::kLean, (x - fingerX_) * kStrokeKick);
    fingerX_ = x;
  }
}

RigFrame RigFace::frame(int dy, bool talking, Dither d, FaceMove move, rig::Anchors* anchors) const {
  Channels off;  // the channels' offsets from rest, where the art is drawn
  for (int c = 0; c < rig::kChannelCount; ++c) off.v[c] = int16_t(mixer_.channels().v[c] - rig::kRest.v[c]);
  const Body body(off, dy, move);
  RigFrame f;
  auto add = [&](const Placed& p) {
    if (f.count < RigFrame::kMaxParts) f.parts[f.count++] = body.place(p);
  };
  // Each eye: closed onto its pivot and sized by how open and how big it
  // is, and shut while its design's face is; moved by the gaze.
  const Faded eyes = faded(mixer_.eyes(), d);
  const int size = scale(off[Channel::kEyeSize]);
  for (int i = 0; i < eyes.n; ++i) {
    for (int side = 0; side < 2; ++side) {
      const int open = move.shut ? 0 : scale(off[side ? Channel::kEyeOpenR : Channel::kEyeOpenL]);
      const bool shut = open < kShutBelow;
      const int kind = (shut ? faces::kPartShutL : faces::kPartEyeL) + side;
      Placed p = morph(eyes.part[i], eyes.other[i], kind, eyes.q[i]);
      p.sx = int16_t(scaled(p.sx, size));
      p.sy = int16_t(scaled(scaled(p.sy, size), shut ? kOne : open));
      p.x = int16_t(p.x + move.ex + off[Channel::kGazeX] * kGazePx / 1000);
      p.y = int16_t(p.y + move.ey + off[Channel::kGazeY] * kGazePx / 1000);
      p.dither = eyes.dither[i];
      add(p);
    }
    Placed cheeks = morph(eyes.part[i], eyes.other[i], faces::kPartCheeks, eyes.q[i]);
    cheeks.dither = eyes.dither[i];
    add(cheeks);
  }
  // The mouth (its shut face's while its design's face is shut), opened
  // from the art's, or while talking the "o" at its middle, in its ink.
  const Faded mouth = faded(mixer_.mouth(), d);
  const int open = kOne + off[Channel::kMouthOpen] * kOne / 2000;
  for (int i = 0; i < mouth.n; ++i) {
    Placed p = morph(mouth.part[i], mouth.other[i], move.shut ? faces::kPartShutMouth : faces::kPartMouth, mouth.q[i]);
    p.sy = int16_t(scaled(p.sy, open));
    p.x = int16_t(p.x + move.mx), p.y = int16_t(p.y + move.my);
    p.dither = mouth.dither[i];
    if (!talking) {
      add(p);
    } else if (i == mouth.n - 1) {  // the one coming in, or the only one
      const faces::Part& art = faces::kParts[p.style][p.kind];
      const Placed at = body.place(p);
      f.talkX = int16_t(at.x + scaled((art.x0 + art.x1) / 2, at.sx) - kTalkW / 2);
      f.talkY = int16_t(at.y + scaled((art.y0 + art.y1) / 2, at.sy) - kTalkH / 2 + 1);
      f.talkInk = sceneInk(faces::kPartRects[art.rect0].color);
      f.talk = d;
    }
  }
  if (anchors) *anchors = anchorsOf(mixer_.eyes(), body);
  return f;
}

void drawRig(Canvas& c, const RigFrame& f) {
  for (int i = 0; i < f.count; ++i) {
    const Placed& p = f.parts[i];
    const faces::Part& part = faces::kParts[p.style][p.kind];
    for (int k = 0; k < part.rects; ++k) {
      const faces::Rect& r = faces::kPartRects[part.rect0 + k];
      const int x0 = p.x + scaled(r.x, p.sx), x1 = p.x + scaled(r.x + r.w, p.sx);
      const int y0 = p.y + scaled(r.y, p.sy), y1 = p.y + scaled(r.y + r.h, p.sy);
      if (x1 > x0 && y1 > y0) c.fillRect(x0, y0, x1 - x0, y1 - y0, sceneInk(r.color), p.dither);
    }
  }
  if (f.talkInk) drawTalk(c, f.talkX, f.talkY, f.talkInk, f.talk);
}

void drawRig(Canvas& c, const RigFrame& f, const SceneFrame& design, Dither d) {
  drawScene(c, design, d, 0, design.faceAt);
  drawRig(c, f);
  drawScene(c, design, d, design.faceAt);
}

}  // namespace render::pixel
