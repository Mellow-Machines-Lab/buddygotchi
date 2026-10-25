#include "render/pixel/anim.h"
#include <algorithm>
#include <cstdio>
#include <cstring>

#include "render/maths.h"
#include "render/palette.h"
#include "rig_tables.h"  // the staged pack's (characters/charactergen.py)
namespace render::pixel {
static_assert(EffectTrack::kMaxOut == Face::kMaxCues, "face cue buffer holds the pixel scheduler output");
namespace {
// A hash of a frame's picture, as its bytes.
template <class Picture>
uint64_t frameKey(const Picture& f) {
  const uint8_t* p = reinterpret_cast<const uint8_t*>(&f);
  uint64_t h = 14695981039346656037ull;
  for (size_t i = 0; i < sizeof f; i += 4) {
    uint32_t w = 0;
    std::memcpy(&w, p + i, sizeof f - i < 4 ? sizeof f - i : 4);
    h = (h ^ w) * 1099511628211ull;
    h ^= h >> 29;
  }
  return h;
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
  rig_.reset(src_.mood, context_.base, t);
}
void PixelFace::sync(const FaceSource& next, const FaceContext& context, uint32_t t) {
  rig_.advanceTo(t);
  context_ = context;
  // The look's clip plays under its own designs; a reaction's design has
  // moves of its own (and asleep's shut eyes would shut a poke's).
  const SceneState base = next.anim == SceneState::kNone ? context.base : SceneState::kNone;
  rig_.setLook(base);
  if (occasion_ && (base != occasionBase_ || context.attention || !after(occasionEnds_, t))) {
    rig_.stop(*occasion_);
    occasion_ = nullptr;
  }
  if (!within(t, switchAt_, rig::kFadeMs)) from_.kind = Drew::kNone;  // the dissolve is over
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
      startSwitch(t);
    if (wanted.look != src_.look || wanted.lookVariant != src_.lookVariant) lookAt_ = t;
    // The rig face moves to a new mood while it shows, and is at rest in it
    // when it comes back.
    if (wanted.mood != src_.mood)
      drawn_.kind == Drew::kRig ? rig_.setMood(wanted.mood) : rig_.reset(wanted.mood, base, t);
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
const rig::Look* PixelFace::rigLook() const {
  return src_.anim == SceneState::kNone && !context_.attention ? rig::kRig.look(context_.base) : nullptr;
}
int PixelFace::occasionsFit() const {
  const rig::Look* look = rigLook();
  return look ? look->fitting(context_.when, context_.lookMs) : 0;
}
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
  // A loop's end turns the look's variation, or gives the rig look's
  // occasions their chance.
  const bool turns = turnable() || occasionsFit();
  consider(nextBlink_);
  if (turns) consider(loopEnd(from));
  due_ = 0;
  if (!found) return false;
  dueAt_ = at;
  if (at == nextBlink_) due_ |= kBlink;
  if (turns && at == loopEnd(at - 1)) due_ |= kTurn;
  return true;
}
void PixelFace::step(uint32_t t, linkkit::Rng& rng) {
  rig_.advanceTo(t);
  const uint8_t due = t == dueAt_ ? due_ : 0;
  due_ = 0;
  if (due & kBlink) {
    // The face blinks now and then, but in a design that blinks on its own.
    const bool own = blinksItself(src_.mood, src_.state(), src_.variant());
    if (rigDraws() && !own) rig_.blink();
    blink_ =
        src_.anim == SceneState::kNone && src_.look != SceneState::kAsleep && src_.look != SceneState::kNoApp && !own;
    blinkAt_ = t;
    nextBlink_ = t + (blink_ ? kBlinkMs : 0) + blinkGap(rng);
  }
  // At a loop's end, while the rig face draws the look and none plays,
  // one of the rig look's occasions that fit, kOccasionPct of the time.
  if (occasion_ && !after(occasionEnds_, t)) occasion_ = nullptr;
  const int fit = (due & kTurn) && rigDraws() && !occasion_ ? occasionsFit() : 0;
  if (fit && rng.range(1, 100) <= rig::kOccasionPct) {
    occasion_ = rigLook()->fitting(context_.when, context_.lookMs, rng.range(0, fit - 1));
    occasionEnds_ = t + occasion_->ms;
    occasionBase_ = context_.base;
    rig_.play(*occasion_);
  }
  // A variation whose occasion is over (or whose mood lost it) turns at
  // once; any other may, now and then, to one that fits, but not while an
  // occasion's clip plays.
  if ((due & kTurn) && turnable() &&
      (!lookFits(src_.mood, src_.look, lookVariant_) ||
       (!occasion_ && int32_t(t - lookAt_) >= int32_t(kTurnMinMs) && rng.range(1, 100) <= kTurnPct)))
    lookVariant_ = pickLook(src_.mood, src_.look, lookVariant_, rng);
}
// A needs-you replacing another starts its screen over, dissolving from
// the one that showed.
void PixelFace::alert(uint32_t t, bool replacing) {
  lookAt_ = t;
  if (replacing && drawn_.kind == Drew::kNeedsYou) startSwitch(t);
}
void PixelFace::startSwitch(uint32_t t) {
  // What shows: the picture of the two that shows more.
  if (mix(t) >= 500) from_ = drawn_;
  switchAt_ = t;
}
// A press kicks the rig face, and strokes it until it lets go, only if it
// began while the rig face showed.
void PixelFace::finger(bool down, int x, int y) {
  if (down && !pressing_) rigPress_ = drawn_.kind == Drew::kRig;
  pressing_ = down;
  rig_.finger(down && rigPress_, x, y);
}
void PixelFace::started(SceneState a, Mood, uint8_t variant, Outcome, StartCtx) {
  last_[int(a)] = uint8_t(variant + 1);
  blink_ = false;
}
// Pixel's designs don't come in sizes: a finish's loops play it again.
uint8_t PixelFace::pick(SceneState s, Mood mood, int wanted, Outcome o, StartCtx c, linkkit::Rng& rng, int, int) const {
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
  s.eyesShut = blinking(t);
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
bool PixelFace::draw(Canvas& c, Surface*, const SceneShow& show, uint32_t t, const char* bubble,
                     const SignShow& sign, const DoneShow&, const Strip& strip, bool dirty) {
  rig_.advanceTo(t);
  Picture& p = picture_;
  std::memset(static_cast<void*>(&p), 0, sizeof p);  // its padding too: it's hashed as bytes
  p.lane = Dither::fade(strip.opacity, true).hi, p.bubble = bubble != nullptr;
  // A dissolve shows more of what comes in each frame, some of it from the
  // first, and is over once that's whole.
  const int in = mix(t);
  p.in = Dither::fade(in, true);
  p.in.hi = uint8_t(std::max<int>(p.in.hi, 1));
  p.from = p.in.all() ? Drew::kNone : from_.kind;
  if (strip.agent && show.state == SceneState::kNeedsYou) {
    p.kind = Drew::kNeedsYou;
    p.needsYou = needsYouPose(designMs(t), show.eyesShut, show.dy);
  } else {
    p.kind = rigDraws(show.mood, show.state, show.variant) ? Drew::kRig : Drew::kDesign;
    const bool rig = p.kind == Drew::kRig, stays = rig && p.from == Drew::kRig;
    const FaceMove move = stays ? lerp(faceMove(from_.show), faceMove(show), in) : faceMove(show);
    // The design, without its face where the rig face draws it; and what
    // it wears and holds, which move on their own. On the rig face, the hat
    // and the sign ride its anchors.
    p.design = sceneFrame(show, rig);
    p.held = sign.text != nullptr, p.heldAt = int16_t(sign.text ? heldOffset(sign.ms, show.dy) : 0);
    p.heldIn = sign.text ? Dither::fade(sign.opacity, true).hi : 0;
    if (rig) {
      rig::Anchors now;
      p.face = rig_.frame(show.dy, show.mouthOpen, stays ? Dither{} : p.in, move, &now);
      const RigFace::Pose& rest = *RigFace::pose(show.mood);
      p.hatX = int16_t(now.brimF.x - rest.brim.x), p.hatY = int16_t(now.brimF.y - rest.brim.y);
      if (sign.text) p.heldAt = int16_t(p.heldAt + now.handF.y - rest.hand.y);
    }
    p.dress = dresses(show.mood, show.state, show.variant) ? outfitKey(context_.when, show.mood, t) : 0;
  }
  drawn_.kind = p.kind, drawn_.show = show;
  if (p.kind == Drew::kNeedsYou) {
    drawn_.needsYou = p.needsYou, drawn_.more = strip.more;
    std::snprintf(drawn_.agent, sizeof drawn_.agent, "%s", strip.agent);
    const char* what = strip.name && *strip.name ? strip.name : strip.project;
    std::snprintf(drawn_.what, sizeof drawn_.what, "%s", what ? what : "");
  }
  const uint64_t key = frameKey(p);
  if (!dirty && key == drawnKey_) return false;
  drawnKey_ = key;
  c.fill(kBlack);
  // What showed, fading out under what comes in.
  const Dither out = {p.in.hi, 16};
  if (p.from == Drew::kNeedsYou) {
    // The needs-you screen as it last showed, asking what it asked.
    Strip asked = strip;
    asked.agent = from_.agent, asked.name = asked.project = from_.what, asked.more = from_.more;
    asked.doneAgent = nullptr;  // a finish doesn't play while something needs you
    c.setMask(out);
    drawNeedsYouScreen(c, from_.needsYou, asked);
    c.setMask({});
  } else if (p.from != Drew::kNone) {
    // A face: with the face staying, only its design.
    const SceneShow& was = from_.show;
    const bool rig = p.from == Drew::kRig;
    rig::Anchors now;
    if (rig && p.kind != Drew::kRig)
      drawRig(c, rig_.frame(was.dy, was.mouthOpen, out, faceMove(was), &now), sceneFrame(was, true), out);
    else
      drawScene(c, sceneFrame(was, rig), out);
    if (p.kind == Drew::kNeedsYou) {
      // Under the needs-you screen, what it wears and its lane go with it
      // (no sign or bubble is up while something needs you).
      Overlays over;
      over.dressed = dresses(was.mood, was.state, was.variant), over.mood = was.mood, over.when = context_.when;
      over.ms = t;
      if (rig) {
        const RigFace::Pose& rest = *RigFace::pose(was.mood);
        over.hatX = now.brimF.x - rest.brim.x, over.hatY = now.brimF.y - rest.brim.y;
      }
      c.setMask(out);
      drawOverlays(c, bubble, strip, over);
      c.setMask({});
    }
  }
  if (p.kind == Drew::kNeedsYou) {
    c.setMask(p.in);
    drawNeedsYouScreen(c, p.needsYou, strip);
    c.setMask({});
    return true;
  }
  if (p.kind == Drew::kRig)
    drawRig(c, p.face, p.design, p.in);
  else
    drawScene(c, p.design, p.in);
  Overlays over;
  over.dressed = p.dress != 0, over.mood = show.mood, over.when = context_.when, over.ms = t;
  over.hatX = p.hatX, over.hatY = p.hatY, over.held = sign.text, over.heldOffset = p.heldAt;
  over.heldOpacity = sign.opacity;
  // Over both faces of a dissolve, whole; out of the needs-you screen,
  // coming in with the face.
  c.setMask(p.from == Drew::kNeedsYou ? p.in : Dither{});
  drawOverlays(c, bubble, strip, over);
  c.setMask({});
  return true;
}
}  // namespace render::pixel
