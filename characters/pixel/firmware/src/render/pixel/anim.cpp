#include "render/pixel/anim.h"
#include <cstring>

#include "render/maths.h"
namespace render::pixel {
static_assert(EffectTrack::kMaxOut == Face::kMaxCues, "face cue buffer holds the pixel scheduler output");
namespace {
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
// Variations of a design, split in their order into the plain ones and
// the occasions' (those with tags).
struct Split {
  uint8_t plain[kMaxVariants], occasions[kMaxVariants];
  int np = 0, no = 0;
};
Split split(Mood m, SceneState s, const uint8_t* vs, int n) {
  Split out;
  for (int i = 0; i < n; ++i) {
    if (tagged(m, s, vs[i]))
      out.occasions[out.no++] = vs[i];
    else
      out.plain[out.np++] = vs[i];
  }
  return out;
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
  // A new look starts on its first variation, or on an occasion's while
  // one fits; so does the look again when the mood has fewer of them. The
  // turns bring the rest.
  FaceSource wanted = next;
  if (pending_ || wanted.lookVariant >= variants(wanted.mood, wanted.look)) {
    lookVariant_ = firstLook(wanted.mood, wanted.look);
    pending_ = false;
    wanted.lookVariant = lookVariant_;
  }
  // The working looks keep their place in the loop as the pace changes.
  if (context.pace != pace_) {
    uint32_t into = designMs(t);
    pace_ = context.pace;
    lookAt_ = t - uint32_t((uint64_t(into) * 100 + pace_ - 1) / pace_);  // never a step back
  }
  if (!(wanted == src_)) {
    bool restart = wanted.anim != SceneState::kNone && wanted.at != src_.at;
    if (sceneOf(wanted.mood, wanted.state(), wanted.variant()) != sceneOf(src_.mood, src_.state(), src_.variant()) ||
        restart)
      switched_ = true, switchAt_ = t;
    if (wanted.look != src_.look || wanted.lookVariant != src_.lookVariant) lookAt_ = t;
    src_ = wanted;
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
  uint32_t loop = uint32_t(uint64_t(loopMs(src_.mood, src_.look, src_.lookVariant)) * 100 / pace_);
  if (!loop) loop = 1;
  return t - (t - lookAt_) % loop + loop;
}
int PixelFace::fittingLooks(Mood m, SceneState s, int avoid, uint8_t* out) const {
  int k = 0;
  for (int v = 0; v < variants(m, s); ++v)
    if (v != avoid && lookFits(m, s, v)) out[k++] = uint8_t(v);
  return k;
}
uint8_t PixelFace::firstLook(Mood m, SceneState s) const {
  uint8_t fit[kMaxVariants];
  const Split c = split(m, s, fit, fittingLooks(m, s, -1, fit));
  return c.no ? c.occasions[0] : c.np ? c.plain[0] : 0;
}
uint8_t PixelFace::pickLook(Mood m, SceneState s, int avoid, linkkit::Rng& rng) const {
  uint8_t fit[kMaxVariants];
  const Split c = split(m, s, fit, fittingLooks(m, s, avoid, fit));
  if (c.no && (!c.np || rng.range(1, 100) <= kTaggedPct)) return c.occasions[rng.range(0, c.no - 1)];
  if (c.np) return c.plain[rng.range(0, c.np - 1)];
  return avoid >= 0 && avoid < variants(m, s) ? uint8_t(avoid) : 0;
}
// The next blink, or the look's loop ending while its variations may take
// turns. What's due then is decided here, before Behaviour syncs the face
// to that instant: a moment ending at the same instant doesn't make a turn
// due.
bool PixelFace::nextDue(uint32_t from, uint32_t to, uint32_t& at) {
  bool found = false;
  auto consider = [&](uint32_t c) {
    if (after(c, from) && !after(c, to) && (!found || after(at, c))) at = c, found = true;
  };
  consider(nextBlink_);
  if (turnable()) consider(loopEnd(from));
  due_ = 0;
  if (!found) return false;
  dueAt_ = at;
  if (at == nextBlink_) due_ |= kBlink;
  if (turnable() && at == loopEnd(at - 1)) due_ |= kTurn;
  return true;
}
void PixelFace::step(uint32_t t, linkkit::Rng& rng) {
  const uint8_t due = t == dueAt_ ? due_ : 0;
  due_ = 0;
  if (due & kBlink) {
    blink_ = src_.anim == SceneState::kNone && src_.look != SceneState::kAsleep && src_.look != SceneState::kNoApp &&
             !blinksItself(src_.mood, src_.look, src_.lookVariant);
    blinkAt_ = t;
    nextBlink_ = t + (blink_ ? kBlinkMs : 0) + blinkGap(rng);
  }
  // A variation whose occasion is over (or whose mood lost it) turns at
  // once; any other may, now and then, to one that fits.
  if ((due & kTurn) && turnable() &&
      (!lookFits(src_.mood, src_.look, lookVariant_) ||
       (int32_t(t - lookAt_) >= int32_t(kTurnMinMs) && rng.range(1, 100) <= kTurnPct)))
    lookVariant_ = pickLook(src_.mood, src_.look, lookVariant_, rng);
}
void PixelFace::alert(uint32_t t, bool replacing) {
  lookAt_ = t;
  if (replacing) switched_ = true, switchAt_ = t;
}
void PixelFace::started(SceneState a, Mood, uint8_t variant, Outcome, StartCtx) {
  last_[int(a)] = uint8_t(variant + 1);
  blink_ = false;
}
uint8_t PixelFace::pick(SceneState s, Mood mood, int wanted, Outcome o, StartCtx c, linkkit::Rng& rng) const {
  uint8_t all[kMaxVariants], fit[kMaxVariants];
  int k0 = fitting(mood, s, o, c, all), n = 0;
  // Only those whose tags are on; an occasion's first, whatever the Mac
  // asked for (the Mac never asks for one).
  for (int i = 0; i < k0; ++i)
    if (fits(mood, s, all[i], context_.when, UINT32_MAX)) fit[n++] = all[i];
  const Split byTags = split(mood, s, fit, n);
  if (byTags.no) return byTags.occasions[rng.range(0, byTags.no - 1)];
  if (!n) n = k0, std::memcpy(fit, all, k0);
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
SceneShow PixelFace::show(uint32_t t, bool mouthOpen, int dy) const {
  SceneShow s;
  s.mood = src_.mood;
  s.state = src_.state();
  s.variant = src_.variant();
  s.t = designMs(t);
  uint32_t loop = loopMs(s.mood, s.state, s.variant);
  if (src_.anim != SceneState::kNone) s.t = s.t >= src_.playMs ? loop - 1 : s.t % loop;
  if (s.state == SceneState::kNeedsYou && s.t >= loop) s.t = 0;
  s.eyesShut = blinking(t) || (switched_ && within(t, switchAt_, kBlendMs));
  s.mouthOpen = mouthOpen;
  s.dy = int16_t(dy);
  return s;
}
// The design's sounds, on its clock unwrapped since the timeline counts
// its own loops, then the needs-you arc's on the request's clock: each cue
// once, as the clock reaches it, and one that late dropped, as the design's
// are. A new request starts the clock over, and so the cues.
int PixelFace::cues(uint32_t t, bool shown, voice::FxEvent* out, bool& changed) {
  if (!shown) {
    arcOn_ = false;
    return fx_.follow(nullptr, out, changed);
  }
  SceneShow s = show(t, false, 0);
  s.t = designMs(t);
  int n = fx_.follow(&s, out, changed);
  if (s.state != SceneState::kNeedsYou) {
    arcOn_ = false;
    return n;
  }
  if (!arcOn_ || s.t + EffectTrack::kLeadMs < arcCovered_) arcOn_ = true, arcCovered_ = s.t;
  const uint32_t until = s.t + EffectTrack::kLeadMs;
  for (const ArcCue& c : kArcCues) {
    if (c.at < arcCovered_ || c.at >= until || c.at + EffectTrack::kLateMs < s.t) continue;
    const int clip = clips().index(c.clip);
    if (clip < 0 || n >= Face::kMaxCues) continue;
    voice::FxEvent e;
    e.clip = uint8_t(clip), e.gain = c.gain, e.pitch = c.pitch, e.duck = false;
    out[n++] = e;
  }
  if (until > arcCovered_) arcCovered_ = until;
  return n;
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
