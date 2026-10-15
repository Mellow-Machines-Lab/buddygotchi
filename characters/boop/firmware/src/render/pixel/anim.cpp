#include "render/pixel/anim.h"
#include <cstring>
namespace render::pixel {
static_assert(EffectTrack::kMaxOut == Face::kMaxCues, "face cue buffer holds the pixel scheduler output");
namespace {
bool after(uint32_t a, uint32_t b) { return int32_t(a - b) > 0; }
bool within(uint32_t t, uint32_t from, uint32_t ms) {
  return int32_t(t - from) >= 0 && int32_t(t - from) < int32_t(ms);
}
uint64_t frameKey(const SceneFrame& f, bool bubble) {
  static_assert(sizeof f % 4 == 0, "a frame hashes as whole words");
  const uint8_t* p = reinterpret_cast<const uint8_t*>(&f);
  uint64_t h = 14695981039346656037ull;
  for (size_t i = 0; i < sizeof f; i += 4) {
    uint32_t w;
    std::memcpy(&w, p + i, 4);
    h = (h ^ w) * 1099511628211ull;
    h ^= h >> 29;
  }
  return (h << 1 | (bubble ? 1 : 0)) | (uint64_t(1) << 63);
}
}  // namespace
void PixelFace::reset(uint32_t t, linkkit::Rng& rng) {
  *this = PixelFace{};
  nextBlink_ = t + blinkGap(rng);
  lookAt_ = t;
}
void PixelFace::sync(const FaceSource& next, const FaceContext& context, uint32_t t) {
  context_ = context;
  if (switched_ && !within(t, switchAt_, kBlendMs)) switched_ = false;
  if (!(next == src_)) {
    bool restart = next.anim != Anim::kNone && next.at != src_.at;
    if (sceneOf(next.mood, next.state(), next.variant()) != sceneOf(src_.mood, src_.state(), src_.variant()) || restart)
      switched_ = true, switchAt_ = t;
    if (next.look != src_.look || next.lookVariant != src_.lookVariant) lookAt_ = t;
    src_ = next;
  }
}
void PixelFace::rewind(uint32_t t, linkkit::Rng& rng) {
  if (after(nextBlink_, t + 10000)) nextBlink_ = t + blinkGap(rng);
  if (after(lookAt_, t)) lookAt_ = t;
}
uint32_t PixelFace::blinkGap(linkkit::Rng& rng) const {
  return uint32_t(rng.range(2000, context_.working ? 5000 : 6000));
}
bool PixelFace::turnable() const { return context_.mayVary && variants(context_.mood, context_.look) > 1; }
uint32_t PixelFace::loopEnd(uint32_t t) const {
  uint32_t loop = loopMs(src_.mood, src_.look, src_.lookVariant);
  return t - (t - lookAt_) % loop + loop;
}
bool PixelFace::nextDue(uint32_t from, uint32_t to, uint32_t& at) const {
  bool found = false;
  auto consider = [&](uint32_t c) {
    if (after(c, from) && !after(c, to) && (!found || after(at, c))) at = c, found = true;
  };
  consider(nextBlink_);
  if (turnable()) consider(loopEnd(from));
  return found;
}
unsigned PixelFace::dueAt(uint32_t t) const {
  unsigned result = t == nextBlink_ ? 1u : 0u;
  if (turnable() && t == loopEnd(t - 1)) result |= 2u;
  return result;
}
void PixelFace::step(uint32_t t, linkkit::Rng& rng, unsigned due) {
  if (due & 1u) {
    blink_ = src_.anim == Anim::kNone && src_.look != SceneState::kAsleep && src_.look != SceneState::kNoApp &&
             !blinksItself(src_.mood, src_.look, src_.lookVariant);
    blinkAt_ = t;
    nextBlink_ = t + (blink_ ? kBlinkMs : 0) + blinkGap(rng);
  }
  if ((due & 2u) && turnable() && int32_t(t - lookAt_) >= int32_t(kTurnMinMs) && rng.range(1, 100) <= kTurnPct) {
    int v = rng.range(0, variants(context_.mood, context_.look) - 2);
    if (v >= lookVariant_) ++v;
    lookVariant_ = uint8_t(v);
  }
}
void PixelFace::alert(uint32_t t, bool replacing) {
  lookAt_ = t;
  if (replacing) switched_ = true, switchAt_ = t;
}
void PixelFace::started(Anim a, Mood, uint8_t variant, Outcome, StartCtx) {
  last_[int(animState(a))] = uint8_t(variant + 1);
  blink_ = false;
}
uint8_t PixelFace::pick(Anim a, Mood mood, int wanted, Outcome o, StartCtx c, linkkit::Rng& rng) const {
  SceneState s = animState(a);
  uint8_t fit[kMaxVariants];
  int n = fitting(mood, s, o, c, fit);
  for (int i = 0; i < n; ++i)
    if (fit[i] + 1 == wanted) return fit[i];
  uint8_t others[kMaxVariants];
  int k = 0;
  for (int i = 0; i < n; ++i)
    if (fit[i] + 1 != last_[int(s)]) others[k++] = fit[i];
  if (k <= 1) return k ? others[0] : fit[0];
  return others[rng.range(0, k - 1)];
}
uint32_t PixelFace::holdMs(Mood mood, int loops, uint32_t t) const {
  uint32_t loop = loopMs(mood, src_.state(), src_.variant());
  uint32_t into = designMs(t) % loop;
  return loop - into + uint32_t(loops - 1) * loop;
}
bool PixelFace::blinking(uint32_t t) const { return blink_ && within(t, blinkAt_, kBlinkMs); }
SceneShow PixelFace::show(uint32_t t, uint32_t playMs, bool mouthOpen, int dy) const {
  SceneShow s;
  s.mood = src_.mood;
  s.state = src_.state();
  s.variant = src_.variant();
  s.t = designMs(t);
  uint32_t loop = loopMs(s.mood, s.state, s.variant);
  if (src_.anim != Anim::kNone) s.t = s.t >= playMs ? loop - 1 : s.t % loop;
  if (s.state == SceneState::kNeedsYou && s.t >= loop) s.t = 0;
  s.eyesShut = blinking(t) || (switched_ && within(t, switchAt_, kBlendMs));
  s.mouthOpen = mouthOpen;
  s.dy = int16_t(dy);
  return s;
}
bool PixelFace::draw(Canvas& c, Surface*, const SceneShow& show, uint32_t t, const char* bubble, const Strip& strip,
                     bool dirty) {
  if (strip.agent && show.state == SceneState::kNeedsYou) {
    SignPose pose = signPose(designMs(t), show.eyesShut, show.dy);
    if (!dirty && drawnSign_ && pose == drawnPose_) return false;
    drawnSign_ = true;
    drawnPose_ = pose;
    drawnKey_ = 0;
    drawSignScreen(c, pose, strip);
  } else {
    drawnSign_ = false;
    SceneFrame frame = sceneFrame(show);
    uint64_t key = frameKey(frame, bubble != nullptr);
    if (!dirty && key == drawnKey_) return false;
    drawnKey_ = key;
    drawFaceScreen(c, frame, bubble, strip);
  }
  return true;
}
}  // namespace render::pixel
