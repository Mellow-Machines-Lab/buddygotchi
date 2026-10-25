#include "app/device.h"
#include "render/tags.h"

#include <ArduinoJson.h>

#include <algorithm>
#include <cstdio>
#include <cstring>

#include "render/font.h"
#include "render/maths.h"
#include "render/palette.h"
#include "render/pattern.h"
#include "render/screens.h"

namespace app {

using render::after;

namespace {

using linkkit::Do;
using linkkit::How;
using linkkit::Link;

// Motion redraws at most this often, in real ms: about 60 fps. Parts of
// the face that cross block lines a few ms apart show together.
constexpr uint32_t kFrameMs = 16;
// BOOT's cap on talking is where listening stops listening.
static_assert(ButtonGesture::kTalkCapMs == Behaviour::kListenMs, "the talk cap is listening's");

// A repeated state keeps the link alive but doesn't invalidate the picture.
// Compare fields, not bytes: Model has padding and its strings are terminated.
bool sameRow(const render::Drawer::Row& a, const render::Drawer::Row& b) {
  return a.id == b.id && a.status == b.status && a.slot == b.slot && !std::strcmp(a.agent, b.agent) &&
         !std::strcmp(a.title, b.title) && !std::strcmp(a.project, b.project);
}

bool sameModel(const Model& a, const Model& b) {
  if (a.listed != b.listed || a.listCount != b.listCount || a.listSkip != b.listSkip || a.unlisted != b.unlisted)
    return false;
  for (int i = 0; i < a.listCount; ++i)
    if (!sameRow(a.list[i], b.list[i])) return false;
  return a.base == b.base && a.act == b.act && a.mood == b.mood && a.attn == b.attn && a.attnId == b.attnId &&
         a.more == b.more && a.busy == b.busy && a.idle == b.idle && a.helpers == b.helpers && a.vol == b.vol &&
         a.when == b.when && a.todoDone == b.todoDone && a.todoTotal == b.todoTotal && !std::strcmp(a.agent, b.agent) &&
         !std::strcmp(a.project, b.project) && !std::strcmp(a.name, b.name);
}

// Boop's do names, in hello.does's order, and the
// animation each plays: none for `react` (a `say`, a face) and for
// stop_listening. A tap's poked and tap_spam aren't among them: the device
// plays those itself.
enum DoIndex : uint8_t {
  kReact,
  kTaskComplete,
  kReplyReady,
  kStarting,
  kStopped,
  kError,
  kHelperReturn,
  kWakeUp,
  kListening,
  kStopListening,
  kNotice,
  kCall,
  kDoCount
};
constexpr const char* kDoNames[kDoCount] = {"react",         "task_complete", "reply_ready", "starting",
                                            "stopped",       "error",         "helper_return", "wake_up",
                                            "listening",     "stop_listening", "notice",      "call"};
constexpr render::SceneState kDoAnims[kDoCount] = {render::SceneState::kNone,         render::SceneState::kTaskComplete,
                                                   render::SceneState::kReplyReady,   render::SceneState::kStarting,
                                                   render::SceneState::kStopped,      render::SceneState::kError,
                                                   render::SceneState::kHelperReturn, render::SceneState::kWakeUp,
                                                   render::SceneState::kListening,    render::SceneState::kNone,
                                                   render::SceneState::kNotice,       render::SceneState::kNone};

// A number the device holds to lo–hi: any JSON number,
// one past either end (even too big for an int) as that end, and a
// fraction as its whole part. Missing or not a number reads as `missing`.
int heldTo(JsonVariantConst v, int lo, int hi, int missing) {
  if (!v.is<double>() || v.is<bool>()) return missing;
  double n = v.as<double>();
  return n >= hi ? hi : n > lo ? int(n) : lo;
}

}  // namespace

Device::Device(Hal& hal, uint8_t* pixels) : hal_(hal), canvas_(pixels) {
  const render::Size size = hal_.nativeSize();
  if (b_.face().drawsNative() && !size.empty()) {
    const size_t bytes = size_t(size.width) * size_t(size.height) * sizeof(uint16_t);
    auto* a = static_cast<uint16_t*>(hal_.allocateSurface(bytes));
    auto* b = static_cast<uint16_t*>(hal_.allocateSurface(bytes));
    native_ = std::make_unique<render::SurfacePair>(size.width, size.height, a, b, size.corner);
    size_t assetBytes = 0;
    const void* assets = b_.face().assets(assetBytes);
    if (assets && assetBytes) b_.face().readAssetsFrom(hal_.quickerCopy(assets, assetBytes));
  }
}
Device::~Device() {
  if (!native_) return;
  if (native_->back().pixels) hal_.releaseSurface(native_->back().pixels);
  if (native_->front().pixels) hal_.releaseSurface(native_->front().pixels);
}

int Device::does(const char* const*& names) const {
  names = kDoNames;
  return kDoCount;
}

// The voice file on the card, which the Mac checks before it sends takes.
void Device::hello(JsonObject extra) {
  extra["voice"] = voice::assetsVersion();
  extra["face"] = b_.face().name();
  extra["pack"] = render::kPackId;  // the character pack it was built with
  extra["pack_version"] = render::kPackVersion;
  extra["reset"] = hal_.resetReason();  // why it last restarted: the Mac logs a crash or a watchdog
  if (*hal_.boardName()) extra["board"] = hal_.boardName();  // which firmware the Mac updates it with
}

void Device::begin() {
  b_.reset(0, kit().rng());
  // A board seeds the kit's randomness from its boot id (linkkit/SPEC.md
  // §7); the simulator starts frozen and keeps the face's own seed.
  if (!kit().frozen()) b_.face().seed(kit().rng().next());
  b_.startWithNoApp();
  fpsSinceReal_ = hal_.realMs();
}

// Forgets everything the Mac said. The kit has frozen the clock at 0 and
// reseeded, so a scenario starts from the same place on the board and in
// the simulator.
void Device::reset() {
  b_.reset(0, kit().rng());
  drain();
  hush();
  hal_.stopEffects();
  live_ = {};
  dirty_ = true;
}

void Device::drain() {
  PlayedOut p;
  if (b_.takePlayedOut(p)) kit().ended(p.key, p.by == CutBy::kNone ? How::kDone : How::kCut, cutByName(p.by));
}

void Device::input(const char* k, uint32_t t, int x, int y) {
  live_.last = {k, t, x, y};
  dirty_ = true;
}

// ---- The Mac's messages ----------------------------------------------------

void Device::onState(JsonObjectConst doc, uint32_t at) {
  Model m;
  m.base = baseFromName(doc["base"]);          // idle if missing or unknown
  m.act = actFromName(doc["act"]);             // working's design if missing or unknown
  m.mood = render::moodFromName(doc["mood"]);  // the startup mood if missing or unknown
  JsonObjectConst attn = doc["attn"];
  if (attn) {
    m.attn = true;
    copyStr(m.agent, sizeof(m.agent), attn["agent"] | "");
    copyStr(m.project, sizeof(m.project), attn["project"] | "");
    copyStr(m.name, sizeof(m.name), attn["name"] | "");
    m.more = attn["more"] | 0;
    m.attnId = attn["id"] | 0u;
  }
  m.busy = doc["busy"] | 0;
  m.idle = doc["idle"] | 0;
  m.helpers = doc["helpers"] | 0;
  JsonObjectConst todo = doc["todo"];
  m.todoDone = todo["done"] | 0;
  m.todoTotal = todo["total"] | 0;
  m.vol = heldTo(doc["vol"], 0, 10, 6);
  // A tag the board doesn't know is left out.
  for (JsonVariantConst tag : doc["when"].as<JsonArrayConst>()) m.when |= render::tagBit(tag.as<const char*>());
  m.when = render::reached(m.when) | render::busyTags(m.busy);
  // The work stream's lanes, `[slot, calls, word]`, their words
  // as the fonts draw them.
  for (JsonArrayConst lane : doc["calls"].as<JsonArrayConst>()) {
    if (m.laneCount >= render::Stream::kLanes) break;
    auto& l = m.lanes[m.laneCount++];
    l.slot = uint8_t(heldTo(lane[0], 0, render::Stream::kLanes - 1, 0));
    l.count = uint16_t(heldTo(lane[1], 0, 999, 0));
    render::foldText(lane[2].as<const char*>(), render::Stream::kWordBytes - 1, l.word, sizeof(l.word));
  }
  // The agents' drawer's rows, `[id, status, slot, agent, title,
  // project]`: status "n" needs you, "w" working, else idle; slot -1 for
  // no lane; project "" when the title is it. The sessions before them,
  // `skip`, and after, `unlisted`.
  m.listed = doc["list"].is<JsonArrayConst>();
  for (JsonArrayConst row : doc["list"].as<JsonArrayConst>()) {
    if (m.listCount >= render::Drawer::kRows) break;
    auto& r = m.list[m.listCount++];
    r.id = uint32_t(row[0] | 0u);
    const char* status = row[1] | "";
    r.status = status[0] == 'n'   ? render::Drawer::Status::kNeedsYou
               : status[0] == 'w' ? render::Drawer::Status::kWorking
                                  : render::Drawer::Status::kIdle;
    r.slot = int8_t(heldTo(row[2], -1, render::Stream::kLanes - 1, -1));
    copyStr(r.agent, sizeof(r.agent), row[3] | "");
    render::foldText(row[4] | "", int(sizeof(r.title)) - 2, r.title, sizeof(r.title));
    render::foldText(row[5] | "", int(sizeof(r.project)) - 2, r.project, sizeof(r.project));
  }
  m.listSkip = heldTo(doc["skip"], 0, 999, 0);
  m.unlisted = heldTo(doc["unlisted"], 0, 999, 0);
  if (!sameModel(m, b_.model()) || live_.pattern || b_.noApp(at))
    dirty_ = true, latency_.mark(Latency::kState, hal_.realMs());
  b_.onState(m, at);
  if (m.attn || m.vol == 0) hush();
  if (m.vol == 0) hal_.stopEffects();
  live_.pattern = false;
  drain();  // "needs you" cuts what plays
}

// A do's args, as a reaction's fields. The variation
// is picked here, as the reaction is about to play: the Mac's (from 1) when
// it's one of its design's, in the mood it's drawn in, for the finish's
// outcome or the start's context; else the device picks one of those,
// never the one it showed last. A finish's `loops` and `turn` (the tier its
// turn reached) may size it, the face's call; one they sized plays once.
ReactionIn Device::parse(const Do& c) {
  ReactionIn mo;
  mo.key = c.key;
  mo.id = c.id > 0 ? uint32_t(c.id) : 0;
  if (c.what == kStopListening) {
    mo.empty = true;
    return mo;
  }
  JsonObjectConst args = c.args;
  mo.anim = c.what < kDoCount ? kDoAnims[c.what] : render::SceneState::kNone;
  mo.expr = render::parseMood(args["mood"], mo.mood);  // unknown or missing: the state's mood
  mo.loops = heldTo(args["loops"], 1, Behaviour::kMaxLoops, 1);
  if (mo.anim != render::SceneState::kNone) {
    render::Outcome outcome = render::Outcome::kNone;
    render::StartCtx ctx = render::StartCtx::kNone;
    if (mo.anim == render::SceneState::kTaskComplete) outcome = render::outcomeFromName(args["outcome"]);
    if (mo.anim == render::SceneState::kStarting) ctx = render::ctxFromName(args["ctx"]);
    mo.outcome = outcome;
    mo.ctx = ctx;
    mo.variant = b_.pick(mo.anim, mo.expr ? mo.mood : b_.model().mood, heldTo(args["variant"], 0, 255, 0), outcome,
                         ctx, kit().rng(), mo.loops,
                         heldTo(args["turn"], render::kNoTurn, render::kTurnTiers, render::kNoTurn));
    // A design its loops sized plays once.
    mo.loops = b_.face().plays(mo.anim, mo.variant, mo.loops);
  }
  mo.said = !args["say"].isNull();
  JsonObjectConst who = args["who"];  // copied by play, while the args live
  if (who) mo.whoAgent = who["agent"] | "", mo.whoThread = who["thread"] | "";
  // The `say`: a take by its id, and maybe a second, `then`, from the
  // card's voice file. `{}`, or an id the file doesn't have (or no card),
  // is still a `say` (the reply listening waits for) but plays nothing.
  mo.take = voice::takeIndex(args["say"]["take"].as<const char*>());
  mo.then = mo.take >= 0 ? voice::takeIndex(args["say"]["then"].as<const char*>()) : -1;
  // The words to hold up, as the fonts draw them, cut to kSignGlyphs.
  render::foldText(args["sign"].as<const char*>(), kSignGlyphs, mo.sign, sizeof(mo.sign));
  // What a face it brings replies to what you said, by name.
  if (mo.expr) copyStr(mo.reply, sizeof(mo.reply), args["reply"].as<const char*>());
  return mo;
}

// While something needs you, with no app, or while
// listening holds the face, a reaction none of which would play is skipped;
// so is stop_listening with nothing to stop. A reply ends listening either
// way.
const char* Device::refuse(const Do& c, uint32_t t) {
  // A word of the work stream shows only over the agents' work.
  if (c.what == kCall) return b_.callShows(t) ? nullptr : "hidden";
  live_.parsed = parse(c);
  const char* why = b_.admit(live_.parsed, t);
  drain();  // a listening reaction the reply ended
  if (why) live_.parsed = ReactionIn{};
  return why;
}

// The reaction starts playing: layered over what plays, and it says when
// it may be replaced: a
// `react` half a second after its `say` and bubble have played, or 1.7 s
// in for a face with no `say` (it ends sooner if nothing of it plays by
// then), and not before its sign comes down; a finish and the compacted
// start never, until they're over; the rules' other reactions, a poke and
// listening at once; stop_listening is over as it starts. The Mac's
// `listening` drops the reactions its own host has waiting in the queue.
void Device::onDo(const Do& c, uint32_t t) {
  latency_.mark(Latency::kDo, hal_.realMs());  // from when it plays, past its wait in the queue
  if (c.what == kCall) {
    // A word that comes forward: the face flies it and the body answers
    // as it lands. It holds nothing up.
    JsonObjectConst args = c.args;
    char word[render::Stream::kWordBytes];
    render::foldText(args["w"].as<const char*>(), render::Stream::kWordBytes - 1, word, sizeof(word));
    b_.call(word, uint8_t(heldTo(args["a"], 0, render::Stream::kLanes - 1, 0)),
            render::callGagFromName(args["as"].as<const char*>()), uint16_t(heldTo(args["n"], 0, 999, 0)), t);
    dirty_ = true;
    kit().rest(c.key);
    return;
  }
  const ReactionIn mo = live_.parsed.key == c.key ? live_.parsed : parse(c);
  live_.parsed = ReactionIn{};
  uint32_t seq = b_.reactionSeq();
  // A `say`'s sound goes with its bubble: now, or at its animation's voice
  // window. Any other reaction drops one still waiting.
  const bool say = b_.play(mo, t);
  if (!say) live_.saidSeq = b_.reactionSeq();
  if (!startSay(t) && b_.reactionSeq() != seq) hush();  // a new reaction replaces the `say`
  dirty_ = true;
  live_.restKey = 0;
  switch (c.what) {
    case kReact:
      live_.restKey = c.key;
      live_.restAt = (say ? b_.sayEnd() : t + Behaviour::kBubbleReadMs) + kReactGapMs;
      if (mo.sign[0] && b_.signUp(t) && after(b_.signEnd(), live_.restAt)) live_.restAt = b_.signEnd();
      break;
    case kTaskComplete:
    case kReplyReady:
    case kWakeUp:  // the brain's, like a finish: it plays through
    case kNotice:
      break;
    case kListening:
      kit().dropWaiting("mic_on", c.from);  // the mic went on: the reactions waiting would end it
      kit().rest(c.key);
      break;
    case kStopListening:
      kit().ended(c.key);
      break;
    case kStarting:
      // The compacted card is news to read: it holds, as a finish does,
      // until it has played. Any other start is over as it starts.
      if (mo.ctx != render::StartCtx::kCompacted) kit().rest(c.key);
      break;
    default:
      kit().rest(c.key);
      break;
  }
  drain();
}

void Device::advance(uint32_t t) {
  b_.advance(t, kit().rng());
  drain();
  if (live_.restKey && !after(live_.restAt, t)) kit().rest(live_.restKey), live_.restKey = 0;
}

bool Device::nextDue(uint32_t from, uint32_t to, uint32_t& at) {
  bool found = b_.nextEnd(from, to, at);
  if (live_.restKey && after(live_.restAt, from) && !after(live_.restAt, to) && (!found || after(at, live_.restAt))) {
    at = live_.restAt, found = true;
  }
  return found;
}

// ---- Inputs ----------------------------------------------------------------

// A tap goes to the Mac as what the device did about it: the poke, or the
// press dip while the face is held or a finish names whose turn it was,
// with that finish's id, the thread the Mac opens.
void Device::tapped(uint32_t t, bool injected, bool button) {
  uint32_t finish = b_.finishShown(t);
  const char* did = button ? b_.press(t, kit().rng()) : b_.tap(t, kit().rng());
  input("tap", t);
  // Where it came from (`src`), and the finish it landed on, if any.
  char on[24] = "", data[48];
  if (finish) std::snprintf(on, sizeof(on), ",\"on\":%lu", (unsigned long)finish);
  std::snprintf(data, sizeof(data), "{\"src\":\"%s\"%s}", button ? "button" : "screen", on);
  kit().emit("tap", did, data, injected);
  drain();  // the poke cuts an animation
}

// BOOT and touch, turned into gestures. Every press and
// touch shows on screen at once, before the Mac hears about it.
void Device::readInputs(uint32_t t) {
  const uint32_t real = hal_.realMs();
  // When an injected press or touch let go, in real time: the clock runs
  // with real time, so as far back as the device clock is past its end.
  // A tool's input then times its release exactly (dbg.latency).
  auto letGo = [&](uint32_t until) { return kit().frozen() ? real : real - (t - until); };
  uint32_t pressGone = real, touchGone = real;
  if (live_.injPress && !after(live_.injPressUntil, t)) live_.injPress = false, pressGone = letGo(live_.injPressUntil);
  switch (live_.boot.update(hal_.bootDown() || live_.injPress, t)) {
    case ButtonGesture::kDown:
      live_.bootInjected = !hal_.bootDown();
      b_.pressDown(t);
      dirty_ = true;
      latency_.mark(Latency::kPress, real);
      break;
    case ButtonGesture::kTap:
      b_.pressUp();
      if (drawerOpen(t) > 0) moveDrawer(0, t, live_.bootInjected);
      latency_.mark(Latency::kTap, live_.bootInjected ? pressGone : real);
      tapped(t, live_.bootInjected, true);
      break;
    case ButtonGesture::kHoldStart:  // push-to-talk: listening at once, before the Mac hears
      b_.pressUp();
      // The reactions waiting would end it: dropped for every Mac that
      // hears talk_on, which for a tool's dbg.press is only USB's.
      kit().dropWaiting("mic_on", live_.bootInjected ? Link::kUsb : Link::kNone);
      b_.talkOn(t, kit().rng());
      input("talk_on", t);
      kit().emit("talk_on", "listening", nullptr, live_.bootInjected);
      drain();  // listening cuts what played
      break;
    case ButtonGesture::kHoldEnd:  // let go, or the 30 s cap
      b_.talkOff(t);
      input("talk_off", t);
      kit().emit("talk_off", nullptr, nullptr, live_.bootInjected);
      break;
    default:
      break;
  }

  // A touch anywhere is a tap, sent on release however long it was held,
  // but for a finger held still on the needs-you screen (TouchGesture::held):
  // that's the gesture `dismiss`, sent as the hold completes with the
  // number of the request the screen showed as the finger went down, so the
  // Mac dismisses that one or none, never one that took the screen during
  // the hold. Its release does nothing, as a touch's on a screen that has
  // gone does. The press shows at once. The panel may miss readings under
  // a light press, so its touch ends after kTouchReleaseMs without
  // contact, in real time so that it ends while a tool has the clock
  // frozen, or at once when the panel says the finger lifted; an injected
  // one ends when it says. The debug pattern ignores touches.
  if (live_.injTouch && !after(live_.injTouchUntil, t)) live_.injTouch = false, touchGone = letGo(live_.injTouchUntil);
  int x = 0, y = 0;
  bool contact = live_.injTouch ? (x = live_.injX, y = live_.injY, true) : hal_.touch(x, y);
  if (live_.injTouch && live_.injTouchUntil != live_.injTouchFrom) {  // a stroke's way along
    const int64_t along = int64_t(t - live_.injTouchFrom), ms = int64_t(live_.injTouchUntil - live_.injTouchFrom);
    x = live_.injX + int((live_.injToX - live_.injX) * along / ms),
    y = live_.injY + int((live_.injToY - live_.injY) * along / ms);
  }
  if (contact) live_.touchSeenReal = real, live_.touchInjected = live_.injTouch;
  const bool lifted = hal_.touchLifted() && !contact;
  bool touching = contact || (live_.touchDown && !live_.touchInjected && !lifted &&
                              real - live_.touchSeenReal < kTouchReleaseMs);
  bool faced = !live_.pattern;
  if (touching && !live_.touchDown) {
    input("touch", t, x, y);
    live_.touchPath.down(x, y, t);
    // A touch on the open drawer is the drawer's, and so is one that
    // starts on the strip, should it go up; neither moves the face.
    const int open = drawerOpen(t);
    live_.drawerTouch = faced && b_.face().hasDrawer() && !b_.noApp(t) && (open > 0 || y >= kDrawerFromY);
    live_.drawerPulling = live_.scrolling = false;
    if (live_.drawerTouch) {
      live_.drawerGrabbed = open, live_.drawerTouchedAt = t, live_.drawerInjected = live_.injTouch;
      // A finger down on gliding rows stops them where they are.
      const int at = drawerScroll(t);
      live_.scrollCaught = at != live_.scrollTo;
      live_.scrollGrabbed = live_.scrolled = at;
      glideDrawer(at, t);
    }
    // Only a touch that began on the screen holds it: a request that comes
    // up under a finger already down isn't dismissed by it.
    live_.touchOnNeedsYou = faced && needsYouShows(t) && open <= 0;
    live_.touchAttnId = live_.touchOnNeedsYou ? b_.model().attnId : 0;
    live_.touchDismissed = false;
    if (faced) {
      b_.pressDown(t);
      if (!live_.drawerTouch) b_.face().finger(true, x, y);
      latency_.mark(Latency::kPress, real);
    }
  } else if (touching && contact) {
    live_.touchPath.move(x, y, t);
    if (live_.drawerTouch) {
      // Up opens it: once the finger has gone kDrawerPullPx (either way,
      // when it's open already), the drawer follows it, with a little give
      // past either end. Open, with more rows than show, it scrolls them
      // instead, as far as they go, with the same give.
      const int pulled = live_.touchPath.path().y0 - y;
      const int most = b_.face().drawerScrollMax(drawer_.total());
      if (!live_.drawerPulling && !live_.scrolling &&
          (live_.drawerGrabbed > 0 ? std::abs(pulled) : pulled) >= kDrawerPullPx) {
        if (live_.drawerGrabbed >= 900 && most > 0 && (pulled > 0 || live_.scrollGrabbed > 0))
          live_.scrolling = true;
        else
          live_.drawerPulling = true;
        if (!live_.drawerToldOpen) sayOpen(0, t);
      }
      if (live_.scrolling) {
        int at = live_.scrollGrabbed + pulled;
        if (at > most) at = most + (at - most) / 4;
        if (at < 0) at /= 4;
        live_.scrolled = at;
      }
      if (live_.drawerPulling) {
        int open = live_.drawerGrabbed + pulled * 1000 / std::max(1, b_.face().drawerTravel());
        if (open > 1000) open = 1000 + (open - 1000) / 4;
        if (open < 0) open /= 4;
        live_.drawerPulled = open;
      }
    } else if (faced) {
      b_.face().finger(true, x, y);
    }
  }
  if (touching && live_.touchOnNeedsYou && !live_.touchDismissed && !live_.drawerPulling && needsYouShows(t) &&
      live_.touchPath.held(t)) {
    // Nothing plays: the screen goes when the Mac's next state says so.
    live_.touchDismissed = true;
    input("gesture", t);
    char data[24];
    std::snprintf(data, sizeof(data), "{\"attn\":%lu}", (unsigned long)live_.touchAttnId);
    kit().emit("gesture", kDismissGesture, live_.touchAttnId ? data : nullptr, live_.touchInjected);
  }
  if (!touching && live_.touchDown) {
    b_.pressUp();
    // The face may carry on the finger's motion as it lets go.
    int vx, vy;
    live_.touchPath.velocity(vx, vy);
    if (!live_.drawerTouch) b_.face().letGo(vx, vy);
    render::Gesture g = render::Gesture::kHandoff;
    const TouchGesture::Kind kind = live_.touchPath.up(g);
    live_.lastTouch = live_.touchPath.path();
    live_.lastTouchWas = kind == TouchGesture::kGesture ? render::gestureName(g)
                         : kind == TouchGesture::kSwipe ? kSwipeGesture
                                                        : "tap";
    if (faced) {
      // The panel's touch let go when it was last in contact, so its tap
      // counts the kTouchReleaseMs the device waits to be sure. Its path
      // may make it a gesture: a stroke, a ruffle, a swipe, a tickle, a
      // boop on the nose; then the board reacts as one, but not while the
      // face is held, where a touch is a tap.
      // A touch that began on the needs-you screen was for it: it gives no tap
      // once its hold dismissed it, or once the screen has gone (its request
      // answered or dismissed on the Mac).
      // A touch the drawer took (a pull, or any on it open) is the
      // drawer's alone: the Mac hears what it did, not a tap.
      if (live_.drawerTouch && (live_.drawerPulling || live_.drawerGrabbed > 0)) {
        live_.lastTouchWas = "drawer";
        if (live_.drawerPulling)
          letGoDrawer(t, vy);
        else if (live_.scrolling)
          letGoScroll(t, vy);
        else if (live_.scrollCaught)
          letGoScroll(t, 0);  // it only stopped the rows, on the nearest whole one
        else
          tapDrawer(live_.lastTouch.x0, live_.lastTouch.y0, t);
      } else if (!(live_.touchOnNeedsYou && (live_.touchDismissed || !needsYouShows(t)))) {
        latency_.mark(Latency::kTap, live_.touchInjected ? touchGone : live_.touchSeenReal);
        if (kind == TouchGesture::kTap || b_.held(t))
          tapped(t, live_.touchInjected, false);
        else
          gestured(g, t, live_.touchInjected, kind == TouchGesture::kSwipe);
      }
    }
  }
  if (!touching && live_.touchDown) live_.drawerTouch = live_.drawerPulling = live_.scrolling = false;
  if (touching != live_.touchDown) dirty_ = true;
  live_.touchDown = touching;
}

// ---- The agents' drawer ------------------------------------------------------

int Device::drawerOpen(uint32_t t) const {
  if (live_.drawerPulling) return live_.drawerPulled;
  const uint32_t age = t - live_.drawerAt;
  if (live_.drawerFrom == live_.drawerTo || age >= kDrawerMs) return live_.drawerTo;
  // Backing out: past the end a little, and back.
  const int64_t u = int64_t(age) * 1000 / kDrawerMs - 1000;  // -1000 … 0
  const int64_t k = 1000 + 23 * u * u * u / 10000000 + 13 * u * u / 10000;
  return int(live_.drawerFrom + (live_.drawerTo - live_.drawerFrom) * k / 1000);
}

void Device::moveDrawer(int to, uint32_t t, bool injected) {
  live_.drawerFrom = drawerOpen(t);
  live_.drawerPulling = false;
  live_.drawerTo = to;
  live_.drawerAt = t;
  live_.drawerInjected = injected;
  if (to > 0 && !live_.drawerToldOpen) sayOpen(0, t);
  if (to <= 0 && live_.drawerToldOpen) sayDrawer("closed", nullptr, t);
  dirty_ = true;
}

void Device::sayDrawer(const char* did, const char* data, uint32_t t) {
  if (!std::strcmp(did, "open")) live_.drawerToldOpen = true, live_.drawerSaidAt = t;
  if (!std::strcmp(did, "closed")) live_.drawerToldOpen = false;
  kit().emit(kDrawerEvent, did, data, live_.drawerInjected);
}

// Opening, its rows start at the top.
void Device::sayOpen(int from, uint32_t t) {
  if (!live_.drawerToldOpen) from = 0, live_.scrollGrabbed = live_.scrolled = live_.scrollFrom = live_.scrollTo = 0;
  live_.drawerAsked = from, live_.drawerAskedAt = t;
  char data[24];
  std::snprintf(data, sizeof(data), "{\"from\":%d}", from);
  sayDrawer("open", from > 0 ? data : nullptr, t);
}

int Device::drawerScroll(uint32_t t) const {
  if (live_.scrolling) return live_.scrolled;
  const uint32_t age = t - live_.scrollAt;
  if (live_.scrollFrom == live_.scrollTo || age >= kDrawerGlideMs) return live_.scrollTo;
  // Easing out, as a glide slows: (1 - u)³ of the way left.
  const int64_t left = int64_t(kDrawerGlideMs - age), all = int64_t(kDrawerGlideMs);
  return int(live_.scrollTo + (live_.scrollFrom - live_.scrollTo) * left * left * left / (all * all * all));
}

void Device::glideDrawer(int to, uint32_t t) {
  live_.scrollFrom = drawerScroll(t);
  live_.scrolling = false;
  live_.scrollTo = to;
  live_.scrollAt = t;
  dirty_ = true;
}

void Device::makeDrawer(uint32_t t) {
  const Model& m = b_.model();
  drawer_.open = drawerOpen(t);
  drawer_.count = m.listCount;
  for (int i = 0; i < m.listCount; ++i) drawer_.rows[i] = m.list[i];
  drawer_.skip = m.listSkip;
  drawer_.unlisted = m.unlisted;
  drawer_.listed = m.listed;
  drawer_.picked = live_.drawerPicked;
  // Fewer rows than it was scrolled for (sessions gone): back as far as
  // they go.
  const int most = b_.face().drawerScrollMax(drawer_.total());
  if (!live_.scrolling && live_.scrollTo > most) glideDrawer(most, t);
  drawer_.scroll = drawerScroll(t);
  const int32_t settled = int32_t(t - live_.drawerAt - kDrawerMs);
  drawer_.paw = live_.drawerTo > 0 && !live_.drawerPulling && settled > 0
                    ? std::min(1000, int(settled * 1000 / int32_t(kDrawerPawMs)))
                    : 0;
}

// A pull let go: it springs open when it went up quickly, or is more than
// four tenths open and not going down quickly; else shut.
void Device::letGoDrawer(uint32_t t, int vy) {
  live_.drawerTouchedAt = t;
  const int speed = -vy * 1000 / std::max(1, b_.face().drawerTravel());  // its open a second, up
  const int open = drawerOpen(t);
  moveDrawer(speed > 1500 || (speed > -1500 && open > 400) ? 1000 : 0, t, live_.drawerInjected);
}

// A scroll let go: its rows glide on as far as the finger was going, as a
// glide easing out over kDrawerGlideMs starts at three times its distance
// a glide's time, to the nearest whole row, up to either end; from past
// one, they spring back. Resting on a whole row, the glass shows the rows
// the Mac sends for it.
void Device::letGoScroll(uint32_t t, int vy) {
  live_.drawerTouchedAt = t;
  const int most = b_.face().drawerScrollMax(drawer_.total()), at = live_.scrolled;
  const int to = at < 0 || at > most ? at : at - int(int64_t(vy) * kDrawerGlideMs / 3000);
  glideDrawer(std::clamp(b_.face().drawerSnap(to), 0, most), t);
}

// A tap on the open drawer: on a row, the Mac opens that session's thread
// and Boop hands it over as the drawer shuts; anywhere else, it shuts.
void Device::tapDrawer(int x, int y, uint32_t t) {
  live_.drawerTouchedAt = t;
  makeDrawer(t);
  const int row = live_.drawerGrabbed >= 900 ? b_.face().drawerRow(drawer_, x, y) : -1;
  if (row >= 0 && !drawer_.at(row)) return;  // a row still coming: nothing to open yet
  if (row >= 0) {
    char data[32];
    std::snprintf(data, sizeof(data), "{\"id\":%lu}", (unsigned long)drawer_.at(row)->id);
    input("drawer", t, x, y);
    sayDrawer("pick", data, t);
    live_.drawerPicked = row;
    b_.gesture(render::Gesture::kHandoff, t);
  }
  moveDrawer(0, t, live_.drawerInjected);
  drain();
}

// Each tick: shut kDrawerShutMs after the last touch, and while open, say
// so again now and then, or soon when the Mac has sent no rows, and ask
// for the rows that show when the Mac's don't start with them and leave
// some out.
void Device::tendDrawer(uint32_t t) {
  const int open = drawerOpen(t);
  if (live_.drawerTo > 0 && !live_.drawerPulling && !live_.touchDown &&
      int32_t(t - live_.drawerTouchedAt) >= int32_t(kDrawerShutMs))
    moveDrawer(0, t, live_.drawerInjected);
  if (live_.drawerToldOpen && live_.drawerTo > 0) {
    const Model& m = b_.model();
    const uint32_t since = t - live_.drawerSaidAt;
    int first = 0, last = -1;
    if (m.listed) makeDrawer(t), b_.face().drawerShown(drawer_, first, last);
    const bool missing = last >= first && first != m.listSkip && (first < m.listSkip || last >= m.listSkip + m.listCount);
    if (missing && (first != live_.drawerAsked || t - live_.drawerAskedAt >= kDrawerReaskMs))
      sayOpen(first, t);
    else if (since >= kDrawerSayMs || (!m.listed && since >= kDrawerAskMs))
      sayOpen(live_.drawerAsked, t);
  }
  if (open <= 0 && live_.drawerTo <= 0) live_.drawerPicked = -1;
  if (open > 0 || (live_.drawerFrom != live_.drawerTo && t - live_.drawerAt < kDrawerMs)) dirty_ = true;
}

bool Device::needsYouShows(uint32_t t) const { return b_.look(t) == render::SceneState::kNeedsYou; }

void Device::gestured(render::Gesture g, uint32_t t, bool injected, bool swipe) {
  if (!swipe || b_.face().playsSwipe()) b_.gesture(g, t);
  input("gesture", t);
  kit().emit("gesture", swipe ? kSwipeGesture : render::gestureName(g), nullptr, injected);
  drain();  // the gesture cuts an animation, as a poke does
}

// The motion sensor, every kMotionMs: picked up, put down, shaken, a thump
// on the desk, laid face down (do not disturb) and turned back up.
void Device::readMotion(uint32_t t) {
  if (int32_t(t - live_.motionAt) < int32_t(kMotionMs)) return;
  live_.motionAt = t;
  int ax = live_.injAx, ay = live_.injAy, az = live_.injAz;
  if (!live_.injMotion && !hal_.motion(ax, ay, az)) return;
  switch (live_.motion.update(ax, ay, az, t)) {
    case MotionGesture::kPickup: gestured(render::Gesture::kPickup, t, live_.injMotion); break;
    case MotionGesture::kPutdown: gestured(render::Gesture::kPutdown, t, live_.injMotion); break;
    case MotionGesture::kShake: gestured(render::Gesture::kDizzy, t, live_.injMotion); break;
    case MotionGesture::kThump: gestured(render::Gesture::kStartle, t, live_.injMotion); break;
    case MotionGesture::kFaceDown:
      b_.setFaceDown(true, t);
      hush();
      kit().emit("gesture", "facedown", nullptr, live_.injMotion);
      dirty_ = true;
      break;
    case MotionGesture::kFaceUp:
      b_.setFaceDown(false, t);
      gestured(render::Gesture::kPeekaboo, t, live_.injMotion);
      break;
    default: break;
  }
}

void Device::tick(uint32_t t) {
  uint32_t real = hal_.realMs();
  if (real - fpsSinceReal_ >= 1000) fps_ = frames_ * 1000 / (real - fpsSinceReal_), frames_ = 0, fpsSinceReal_ = real;
  readInputs(t);
  tendDrawer(t);
  readMotion(t);
  followSound(t);
  drain();

  uint32_t led = b_.led(t);
  if (led != led_) led_ = led, hal_.setLed(led);
  uint8_t bl = b_.backlight(t);
  if (bl != backlight_) backlight_ = bl, hal_.setBacklight(bl);

  const bool noApp = !live_.pattern && b_.noApp(t);
  if (noApp != noApp_) noApp_ = noApp, dirty_ = true;
  // The face may change without a message: its design moves on its own
  // clock (a breath, keys lighting, a blink), so on the face screens every
  // step is checked, and drawn only if its frame changed. A frozen clock
  // looks on every step, so scenario frames stay exact, and the press
  // squish on every pass, so the cap doesn't delay a press.
  bool due = kit().frozen() || b_.pressEasing(t) || hal_.realMs() - drawnReal_ >= kFrameMs;
  if (dirty_ || (!live_.pattern && t != live_.drawnT && due)) render(t);
}

// ---- Sound -----------------------------------------------------------------

void Device::hush() {
  if (saying_) hal_.hush();
  saying_ = false;
}

// The `say` that arrived starts its sound when its bubble shows, at the
// volume then; one replaced, or over, before it started is dropped. True
// when it starts now.
bool Device::startSay(uint32_t t) {
  if (b_.reactionSeq() == live_.saidSeq) return false;
  if (!b_.bubble(t)) {  // it waits for its animation's voice window, or it's gone
    if (!b_.sayAhead(t)) live_.saidSeq = b_.reactionSeq();
    return false;
  }
  live_.saidSeq = b_.reactionSeq();
  const Model& m = b_.model();
  if (m.vol <= 0) return false;
  hal_.say(voice::makeSay(b_.take(), b_.then(), uint8_t(m.vol)));
  saying_ = true;
  return true;
}

// Stops a `say` whose bubble ended or was replaced (by a newer reaction), and
// starts one that waited for its voice window, then plays the face's sound
// effects: its design's events as its clock reaches them,
// and silence for the last design's when it changes or starts over (needs
// you's, for a new needs-you).
void Device::followSound(uint32_t t) {
  if (saying_ && (b_.reactionSeq() != live_.saidSeq || !b_.bubble(t))) hush();
  startSay(t);
  const Model& m = b_.model();
  voice::FxEvent due[render::Face::kMaxCues];
  bool changed;
  int n = b_.face().cues(t, !live_.pattern, due, changed);
  if (changed) hal_.stopEffects();
  if (m.vol == 0) return;
  const voice::EffectClips& clips = b_.face().clips();
  for (int i = 0; i < n; ++i) {
    const voice::EffectClip clip = clips.at(due[i].clip);
    hal_.effect({due[i].clip, due[i].gain, due[i].pitch, uint8_t(m.vol), due[i].duck, clip.samples, clip.len});
    ++fxSent_;
    fxLast_ = due[i].clip;
  }
}

// ---- Drawing ---------------------------------------------------------------

// Draws the frame for t, unless nothing on it can have changed since the
// last one: no message or input since (dirty_), the face's
// design on the same steps with the same additions, and the bubble still
// up or still down. The designs step a few times a second, so most passes
// find the picture unchanged.
void Device::render(uint32_t t) {
  live_.drawnT = t;
  drawnReal_ = hal_.realMs();
  // A native face draws into the surface not being sent.
  render::SurfacePair* native = frames();
  if (live_.pattern) {  // drawn only when dirty: it doesn't move
    if (live_.targetX >= 0) {
      canvas_.fill(render::kBlack);
      canvas_.fillRect(live_.targetX - 10, live_.targetY - 1, 21, 3, render::kAmber);
      canvas_.fillRect(live_.targetX - 1, live_.targetY - 10, 3, 21, render::kAmber);
    } else if (live_.patternFill >= 0) {
      canvas_.fill(uint8_t(live_.patternFill));
    } else {
      render::drawPattern(canvas_);
    }
    if (native) render::blit(canvas_, native->back());
  } else {
    b_.face().watch(&b_.stream());
    // The drawer as it is now: how far open, the Mac's rows and their
    // scroll, and the paw dropping over its edge once it has sprung open.
    makeDrawer(t);
    b_.face().drawer(&drawer_);
    if (!b_.face().draw(canvas_, native ? &native->back() : nullptr, b_.show(t), t, b_.bubble(t), b_.sign(t),
                        b_.done(t), b_.strip(t), dirty_))
      return;
  }
  if (native) native->drew();
  dirty_ = false;
  frame_ = true;
  latency_.drawn();
}

int Device::latencyFields(char* out, size_t n) const {
  int written = 0;
  for (int k = 0; k < Latency::kKinds; ++k) {
    const Latency::Stats s = latency_.stats(Latency::Kind(k));
    int w = std::snprintf(out + written, n - size_t(written), " %s_ms=%lu/%lu", Latency::name(Latency::Kind(k)),
                          (unsigned long)s.p95, (unsigned long)s.max);
    if (w < 0 || size_t(written + w) >= n) return written;
    written += w;
  }
  return written;
}

}  // namespace app
