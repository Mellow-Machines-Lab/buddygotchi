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
  return a.base == b.base && a.act == b.act && a.mood == b.mood && a.attn == b.attn && a.attnId == b.attnId && a.attnKind == b.attnKind &&
         a.more == b.more && a.busy == b.busy && a.idle == b.idle && a.helpers == b.helpers && a.vol == b.vol &&
         a.when == b.when && a.todoDone == b.todoDone && a.todoTotal == b.todoTotal && !std::strcmp(a.agent, b.agent) &&
         !std::strcmp(a.project, b.project) && !std::strcmp(a.name, b.name) && !std::strcmp(a.buddy, b.buddy) && a.workAct.kind == b.workAct.kind &&
         a.workAct.result == b.workAct.result && a.wish == b.wish && a.card.same(b.card) &&
         a.pointer.same(b.pointer);
}

// Boop's do names, in hello.does's order, and the
// animation each plays: none for `react` (a `say`, a face) and for
// stop_listening. A tap's poked and tap_spam aren't among them: the device
// plays those itself.
enum DoIndex : uint8_t {
  kReact,
  kTaskComplete,
  kReplyReady,
  kWakeUp,
  kListening,
  kStopListening,
  kNotice,
  kCall,
  kWishMet,
  kWishGone,
  kDoCount
};
constexpr const char* kDoNames[kDoCount] = {"react",          "task_complete", "reply_ready", "wake_up",  "listening",
                                            "stop_listening", "notice",        "call",        "wish_met", "wish_gone"};
constexpr render::SceneState kDoAnims[kDoCount] = {render::SceneState::kNone,       render::SceneState::kTaskComplete,
                                                   render::SceneState::kReplyReady, render::SceneState::kWakeUp,
                                                   render::SceneState::kListening,  render::SceneState::kNone,
                                                   render::SceneState::kNotice,     render::SceneState::kNone,
                                                   render::SceneState::kNotice,     render::SceneState::kNone};

// A number the device holds to lo–hi: any JSON number,
// one past either end (even too big for an int) as that end, and a
// fraction as its whole part. Missing or not a number reads as `missing`.
int heldTo(JsonVariantConst v, int lo, int hi, int missing) {
  if (!v.is<double>() || v.is<bool>()) return missing;
  double n = v.as<double>();
  return n >= hi ? hi : n > lo ? int(n) : lo;
}

}  // namespace

Device::Device(Hal& hal, uint8_t* pixels) : Device(hal, pixels, render::makeFace()) {}

Device::Device(Hal& hal, uint8_t* pixels, std::unique_ptr<render::Face> face)
    : hal_(hal), canvas_(pixels), b_(std::move(face)) {
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
  if (ownsCanvas_) hal_.releaseSurface(canvas_.pixels());
  if (showRoom_) hal_.releaseSurface(showRoom_);
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
  if (b_.face().drawsInvites()) extra["invites"] = 1;  // the Mac sends a `do`'s invite only then
  // The character pack it was built with, as `id version`.
  static char pack[48];
  if (!*pack) std::snprintf(pack, sizeof pack, "%s %s", render::kPackId, render::kPackVersion);
  extra["pack"] = static_cast<const char*>(pack);
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
  showId_ = 0, showSize_ = 0;
  drain();
  hush();
  hal_.stopEffects();
  live_ = {};
  toldFaceDown_ = false;
  dirty_ = true;
}

void Device::drain() {
  // An invite's end and an ask's go first: the Mac hears the answer before
  // the reaction's `ended`.
  InviteEnd v;
  while (b_.takeInviteEnd(v)) {
    JsonDocument d;
    d["skit"] = v.skit;
    d["touch"] = v.stroke ? "stroke" : "tap";
    d["ms"] = v.ms;
    char data[80];
    serializeJson(d, data, sizeof(data));
    kit().emit("invite", v.did, data, v.injected);
  }
  AskEnd a;
  if (b_.takeAskEnd(a)) {
    JsonDocument d;
    d["q"] = a.q;
    d["question"] = a.question;
    if (a.answer[0]) d["answer"] = a.answer;
    char data[160];
    serializeJson(d, data, sizeof(data));
    kit().emit("ask", a.pick, data, a.injected);
  }
  PlayedOut p;
  if (b_.takePlayedOut(p)) kit().ended(p.key, p.by == CutBy::kNone ? How::kDone : How::kCut, cutByName(p.by));
}

void Device::input(const char* k, uint32_t t, int x, int y) {
  live_.last = {k, t, x, y};
  dirty_ = true;
}

// ---- The show's picture ----------------------------------------------------

uint8_t* Device::blobRoom(int32_t id, size_t size) {
  (void)id;
  if (size > kShowBytes) return nullptr;
  if (!showRoom_) showRoom_ = static_cast<uint8_t*>(hal_.allocateSurface(kShowBytes));
  // The one kept is written over: it's no longer whole.
  showId_ = 0, showSize_ = 0;
  return showRoom_;
}

void Device::onBlob(int32_t id, size_t size, uint32_t t) {
  (void)t;
  showId_ = id, showSize_ = size;
  dirty_ = true;
}

render::CardShow Device::cardShow(uint32_t t) const {
  render::CardShow c = b_.cardShow(t);
  const Model::ShowIn& w = b_.model().show;
  if (c.pic == 's' && w.blob && w.blob == showId_ && showRoom_) c.picture = showRoom_, c.pictureBytes = showSize_;
  return c;
}

// ---- The Mac's messages ----------------------------------------------------

void Device::onState(JsonObjectConst doc, uint32_t at) {
  Model m;
  m.base = baseFromName(doc["base"]);          // idle if missing or unknown
  m.act = actFromName(doc["act"]);             // working's design if missing or unknown
  m.mood = render::moodFromName(doc["mood"]);  // the startup mood if missing or unknown
  render::foldText(doc["buddy"].as<const char*>(), kBuddyBytes - 1, m.buddy, sizeof(m.buddy));
  JsonObjectConst attn = doc["attn"];
  if (attn) {
    m.attn = true;
    copyStr(m.agent, sizeof(m.agent), attn["agent"] | "");
    copyStr(m.project, sizeof(m.project), attn["project"] | "");
    copyStr(m.name, sizeof(m.name), attn["name"] | "");
    m.more = attn["more"] | 0;
    m.attnId = attn["id"] | 0u;
    m.attnKind = render::attnKindFromName(attn["kind"]);
  }
  m.busy = doc["busy"] | 0;
  m.idle = doc["idle"] | 0;
  m.helpers = doc["helpers"] | 0;
  JsonObjectConst todo = doc["todo"];
  m.todoDone = todo["done"] | 0;
  m.todoTotal = todo["total"] | 0;
  if (JsonObjectConst card = doc["card"]; !card.isNull()) {
    Model::CardIn& c = m.card;
    c.on = true;
    c.slot = heldTo(card["a"], -1, render::Stream::kLanes - 1, render::CardShow::kNoSlot);
    c.result = !std::strcmp(card["k"] | "s", "r");
    render::foldText(card["t"].as<const char*>(), kCardGlyphs, c.text, sizeof(c.text));
    render::foldText(card["d"].as<const char*>(), kCardSmallGlyphs, c.small, sizeof(c.small));
    render::foldText(card["g"].as<const char*>(), render::CardShow::kAgentBytes - 1, c.agent, sizeof(c.agent));
    c.over = (card["o"] | 0) != 0;
    c.count = heldTo(card["at"][1], 1, 9, 1), c.index = heldTo(card["at"][0], 1, c.count, 1);
  }
  m.pic = Model::PicIn{};
  if (JsonArrayConst pic = doc["pic"].as<JsonArrayConst>(); pic.size() >= 3) {
    Model::PicIn& p = m.pic;
    const char* kind = pic[0] | "";
    p.kind = (kind[0] == 'p' || kind[0] == 'c' || kind[0] == 'h') ? kind[0] : 0;
    p.slot = heldTo(pic[1], -1, render::Stream::kLanes - 1, render::CardShow::kNoSlot);
    render::foldText(pic[2].as<const char*>(), render::CardShow::kAgentBytes - 1, p.agent, sizeof(p.agent));
    if (p.kind == 'p') {
      p.a = heldTo(pic[3], 0, 999, 0), p.b = heldTo(pic[4], 0, 999, 0);
      render::foldText(pic[5].as<const char*>(), sizeof(p.step) - 1, p.step, sizeof(p.step));
      p.left = pic.size() > 6 ? heldTo(pic[6], -999, 999, 0) : render::CardShow::kNoLeft;
    } else if (p.kind == 'c') {
      for (size_t i = 3; i + 2 < pic.size() && p.rows < render::CardShow::kRows; i += 3, ++p.rows) {
        render::foldText(pic[i].as<const char*>(), sizeof(p.file[0]) - 1, p.file[p.rows], sizeof(p.file[0]));
        p.added[p.rows] = heldTo(pic[i + 1], 0, 99999, 0), p.removed[p.rows] = heldTo(pic[i + 2], 0, 99999, 0);
      }
    } else if (p.kind == 'h') {
      p.a = heldTo(pic[3], 0, 99, 0), p.b = heldTo(pic[4], 0, 99, 0);
    }
  }
  if (JsonObjectConst show = doc["show"]; !show.isNull()) {
    Model::ShowIn& w = m.show;
    w.on = true;
    w.slot = heldTo(show["a"], -1, render::Stream::kLanes - 1, render::CardShow::kNoSlot);
    w.blob = int32_t(show["b"] | 0);
    render::foldText(show["g"].as<const char*>(), render::CardShow::kAgentBytes - 1, w.agent, sizeof(w.agent));
    render::foldText(show["h"].as<const char*>(), render::CardShow::kHeadlineBytes - 1, w.headline, sizeof(w.headline));
  }
  const char* wish = doc["wish"] | "";
  m.wish = !std::strcmp(wish, "pet")    ? render::WishShow::kPet
           : !std::strcmp(wish, "chat") ? render::WishShow::kChat
           : !std::strcmp(wish, "work") ? render::WishShow::kWork
                                        : render::WishShow::kNone;
  // Several agents: "w0i-c1", a kind and a slot ("-" for none) each.
  {
    const char* pips = doc["pips"] | "";
    m.pipCount = 0;
    for (const char* p = pips; p[0] && p[1] && m.pipCount < render::Strip::kPips; p += 2, ++m.pipCount) {
      m.pipKind[m.pipCount] = std::strchr("wcia", p[0]) ? p[0] : 'i';
      m.pipSlot[m.pipCount] = p[1] >= '0' && p[1] <= '9' ? int8_t(p[1] - '0') : int8_t(-1);
    }
    m.watch = heldTo(doc["watch"], -1, m.pipCount - 1, -1);
    copyStr(m.who, sizeof(m.who), doc["who"] | "");
    m.pillAt = -1, m.pill[0] = '\0';
    if (JsonArrayConst pill = doc["pill"].as<JsonArrayConst>(); pill.size() == 2) {
      m.pillAt = heldTo(pill[0], -1, m.pipCount - 1, -1);
      render::foldText(pill[1].as<const char*>(), sizeof(m.pill) - 1, m.pill, sizeof(m.pill));
    }
  }
  const char* energy = doc["energy"] | "";
  m.energy = !std::strcmp(energy, "bright")  ? render::Energy::kBright
             : !std::strcmp(energy, "tired") ? render::Energy::kTired
                                             : render::Energy::kNormal;
  m.vol = heldTo(doc["vol"], 0, 10, 6);
  m.color = heldTo(doc["color"], 0, 7, 0);
  // A tag the board doesn't know is left out.
  for (JsonVariantConst tag : doc["when"].as<JsonArrayConst>()) m.when |= render::tagBit(tag.as<const char*>());
  m.when = render::reached(m.when) | render::busyTags(m.busy);
  // The way to your pointer, `[x, y]`, `[x, y, 1]` at the edge nearest the
  // board; none when missing, as an older Mac sends.
  if (JsonArrayConst ptr = doc["ptr"].as<JsonArrayConst>(); ptr.size() >= 2) {
    m.pointer.on = true;
    m.pointer.x = int8_t(heldTo(ptr[0], -10, 10, 0));
    m.pointer.y = int8_t(heldTo(ptr[1], -10, 10, 0));
    m.pointer.near = (ptr[2] | 0) != 0;
  }
  // The work stream's lanes, `[slot, calls, word]`, their words
  // as the fonts draw them.
  for (JsonArrayConst lane : doc["calls"].as<JsonArrayConst>()) {
    if (m.laneCount >= render::Stream::kLanes) break;
    auto& l = m.lanes[m.laneCount++];
    l.slot = uint8_t(heldTo(lane[0], 0, render::Stream::kLanes - 1, 0));
    l.count = uint16_t(heldTo(lane[1], 0, 999, 0));
    render::foldText(lane[2].as<const char*>(), render::Stream::kDoingBytes - 1, l.word, sizeof(l.word));
  }
  // The work act, `[kind, words]`, then `[kind, words, result]`: its result
  // "p" or "f" once the command has ended, as its words change to say so.
  JsonArrayConst workAct = doc["wact"].as<JsonArrayConst>();
  if (workAct.size() >= 2) {
    m.workAct.kind = render::actKindFromName(workAct[0].as<const char*>());
    render::foldText(workAct[1].as<const char*>(), render::Stream::kActBytes - 1, m.workAct.text,
                     sizeof(m.workAct.text));
    const char* result = workAct[2] | "";
    m.workAct.result = *result == 'p'   ? render::ActResult::kPass
                       : *result == 'f' ? render::ActResult::kFail
                                        : render::ActResult::kRunning;
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
// outcome; else the device picks one of those, never the one it showed
// last. A finish's `loops` and `turn` (the tier its
// turn reached) may size it, the face's call; one they sized plays once.
ReactionIn Device::parse(const Do& c, uint32_t t) {
  ReactionIn mo;
  mo.key = c.key;
  mo.id = c.id > 0 ? uint32_t(c.id) : 0;
  if (c.what == kStopListening) {
    mo.empty = true;
    return mo;
  }
  JsonObjectConst args = c.args;
  mo.anim = c.what < kDoCount ? kDoAnims[c.what] : render::SceneState::kNone;
  // A touch's own answer stays when it meets a wish: the bigger one, the heart over it.
  mo.wishMet = c.what == kWishMet;
  if (mo.wishMet && b_.gesturing(t)) mo.anim = render::SceneState::kNone;
  mo.expr = render::parseMood(args["mood"], mo.mood);  // unknown or missing: the state's mood
  mo.loops = heldTo(args["loops"], 1, Behaviour::kMaxLoops, 1);
  if (mo.anim != render::SceneState::kNone) {
    render::Outcome outcome = render::Outcome::kNone;
    if (mo.anim == render::SceneState::kTaskComplete) outcome = render::outcomeFromName(args["outcome"]);
    mo.outcome = outcome;
    mo.variant = b_.pick(mo.anim, mo.expr ? mo.mood : b_.model().mood, heldTo(args["variant"], 0, 255, 0), outcome,
                         kit().rng(), mo.loops,
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
  mo.low = (args["low"] | false) && b_.face().holdsUpFinish();
  render::foldText(args["sign"].as<const char*>(), mo.low ? kLowGlyphs : kSignGlyphs, mo.sign, sizeof(mo.sign));
  // A celebration's, held low in gold; a face that holds nothing low holds
  // it up as its sign, when it has none.
  render::foldText(args["gold"].as<const char*>(), kLowGlyphs, mo.gold, sizeof(mo.gold));
  mo.goldMark = render::goldMarkFromName(args["mark"].as<const char*>());
  // What it earned, "+5 XP" on its finish's or its low sign.
  mo.xp = heldTo(args["xp"], 0, 999, 0);
  if (mo.gold[0] && !b_.face().holdsUpFinish()) {
    if (!mo.sign[0]) copyStr(mo.sign, sizeof(mo.sign), mo.gold);
    mo.gold[0] = 0;
  }
  // Why it plays, for the lane, cut the same.
  render::foldText(args["reason"].as<const char*>(), kSignGlyphs, mo.reason, sizeof(mo.reason));
  // What a face it brings replies to what you said, by name.
  if (mo.expr) copyStr(mo.reply, sizeof(mo.reply), args["reply"].as<const char*>());
  if (mo.expr) copyStr(mo.clip, sizeof(mo.clip), args["clip"].as<const char*>());
  mo.showDrawer = !std::strcmp(args["show"] | "", "drawer");
  mo.greeting = args["greeting"] | false;
  // What it asks: the question's id and its two answers, each cut to half
  // the lane. One with no id or an answer missing asks nothing.
  JsonObjectConst ask = args["ask"];
  if (ask) {
    render::foldText(ask["a"].as<const char*>(), kAnswerGlyphs, mo.askA, sizeof(mo.askA));
    render::foldText(ask["b"].as<const char*>(), kAnswerGlyphs, mo.askB, sizeof(mo.askB));
    if (mo.askA[0] && mo.askB[0]) copyStr(mo.askQ, sizeof(mo.askQ), ask["q"].as<const char*>());
  }
  // What it invites (`invite`), on a face that draws one: one with a pose,
  // a touch or a payoff the board doesn't know invites nothing.
  JsonObjectConst invite = args["invite"];
  if (invite && b_.face().drawsInvites()) {
    InviteIn& v = mo.invite;
    const char* touch = invite["touch"] | "";
    const render::InvitePose pose = render::invitePoseFromName(invite["pose"]);
    const render::InvitePayoff payoff = render::invitePayoffFromName(invite["payoff"]);
    const bool known = !std::strcmp(touch, "tap") || !std::strcmp(touch, "stroke");
    if (pose != render::InvitePose::kNone && payoff != render::InvitePayoff::kNone && known) {
      v.pose = pose, v.payoff = payoff, v.stroke = !std::strcmp(touch, "stroke");
      copyStr(v.skit, sizeof(v.skit), invite["skit"].as<const char*>());
      render::foldText(invite["label"].as<const char*>(), kInviteLabelGlyphs, v.label, sizeof(v.label));
      v.waitMs = uint32_t(heldTo(invite["ms"], 1000, 30000, 4000));
      v.xp = heldTo(invite["xp"], 0, 999, 0);
    }
  }
  return mo;
}

// While something needs you, with no app, or while
// listening holds the face, a reaction none of which would play is skipped;
// so is stop_listening with nothing to stop. A reply ends listening either
// way.
const char* Device::refuse(const Do& c, uint32_t t) {
  // A word of the work stream shows only over the agents' work.
  if (c.what == kCall) return b_.callShows(t) ? nullptr : "hidden";
  // A wish left has no animation of the Mac's to play: only face down refuses it.
  if (c.what == kWishGone) return b_.faceDown() ? "facedown" : nullptr;
  live_.parsed = parse(c, t);
  const char* why = b_.admit(live_.parsed, t);
  // It replaces the ask, its answer `ignored`, and cuts the invite waiting,
  // each before its reaction's `ended`.
  if (!why) b_.dropAsk(t), b_.dropInvite(t);
  drain();  // a listening reaction the reply ended, or the ask's
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
            render::callStyleFromName(args["as"].as<const char*>()), t);
    dirty_ = true;
    // It holds nothing up, so it's over as it starts: resting, its
    // `ended` would wait for whatever came next, and after a quiet minute
    // the host would give up on it.
    kit().ended(c.key);
    return;
  }
  if (c.what == kWishGone) {
    // The bubble fades as the face sighs and slumps, at once and in silence.
    // Over as it starts: what comes next is Jev's.
    b_.wishPopped(false, t);
    dirty_ = true;
    kit().ended(c.key);
    return;
  }
  if (c.what == kWishMet) b_.wishPopped(true, t);
  const ReactionIn mo = live_.parsed.key == c.key ? live_.parsed : parse(c, t);
  live_.parsed = ReactionIn{};
  if (Behaviour::noteOnly(mo)) {
    // Only why: it plays nothing and holds nothing up.
    b_.note(mo.reason, t);
    dirty_ = true;
    kit().ended(c.key);
    return;
  }
  uint32_t seq = b_.reactionSeq();
  // A `say`'s sound goes with its bubble: now, or at its animation's voice
  // window. Any other reaction drops one still waiting.
  const bool say = b_.play(mo, t);
  if (!say) live_.saidSeq = b_.reactionSeq();
  // The drawer a reaction asks for waits for its sign; any later one,
  // listening included, takes its place.
  live_.showDrawer = mo.showDrawer && b_.face().hasDrawer();
  if (live_.showDrawer) live_.showDrawerAt = t + kShowDrawerMs;
  if (!startSay(t) && b_.reactionSeq() != seq) hush();  // a new reaction replaces the `say`
  dirty_ = true;
  live_.restKey = 0;
  // One that invites plays through: its pose and payoff are its point.
  if (b_.invites(c.key) && c.what != kListening && c.what != kStopListening) {
    drain();
    return;
  }
  switch (c.what) {
    case kReact:
      live_.restKey = c.key;
      live_.restAt = (say ? b_.sayEnd() : t + Behaviour::kBubbleReadMs) + kReactGapMs;
      // An ask rests once its question has been read: anything newer may
      // replace it, and ends it unanswered.
      if (mo.sign[0] && b_.signPending(t) && !b_.asking(t) && after(b_.signEnd(), live_.restAt))
        live_.restAt = b_.signEnd();
      if (b_.asking(t) && after(t + Behaviour::kSignMinMs, live_.restAt)) live_.restAt = t + Behaviour::kSignMinMs;
      break;
    case kTaskComplete:
    case kReplyReady:
    case kWakeUp:  // the brain's, like a finish: it plays through
    case kNotice:
      break;
    case kListening:
      kit().dropWaiting("mic_on", c.from);  // the mic went on: the reactions waiting would end it
      if (drawerOpen(t) > 0) moveDrawer(0, t, false);  // its face listens, out from under the drawer
      kit().rest(c.key);
      break;
    case kStopListening:
      kit().ended(c.key);
      break;
    case kWishMet:  // its sign is read; with none up, nothing holds it
      if (b_.signPending(t)) live_.restKey = c.key, live_.restAt = b_.signEnd();
      else if (b_.reactionSeq() == seq) kit().ended(c.key);  // only the heart: over as it starts
      else kit().rest(c.key);
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
// With no app a touch is the board's alone: no Mac hears of it later.
void Device::tell(const char* event, const char* did, const char* data, uint32_t t, bool injected) {
  if (b_.noApp(t)) return;
  kit().emit(event, did, data, injected);
  // Which way up the Mac now takes the board to lie, if a link carried it.
  if (did && (injected || kit().live(linkkit::Link::kBle) || kit().live(linkkit::Link::kUsb))) {
    if (!std::strcmp(did, "facedown")) toldFaceDown_ = true;
    if (!std::strcmp(did, render::gestureName(render::Gesture::kPeekaboo))) toldFaceDown_ = false;
  }
}

// Face down and back up are the one touch the Mac keeps as a state (it
// holds every event while Boop lies face down), so one it didn't hear, with
// the Mac away or the link down, is told once it's back: the board says
// which way up it lies now.
void Device::tellWayUp(uint32_t t) {
  if (toldFaceDown_ == b_.faceDown() || b_.noApp(t)) return;
  if (!kit().live(linkkit::Link::kBle) && !kit().live(linkkit::Link::kUsb)) return;
  kit().emit("gesture", b_.faceDown() ? "facedown" : render::gestureName(render::Gesture::kPeekaboo), nullptr, false);
  toldFaceDown_ = b_.faceDown();
}

void Device::tapped(uint32_t t, bool injected, bool button, const char* was) {
  // BOOT, when it would poke, is a tap like any.
  const Model& m = b_.model();
  if (button && !(m.attn || m.idle > 0) && b_.inviteTouch(false, t, injected)) {
    input("invite", t);
    drain();
    return;
  }
  uint32_t finish = b_.finishShown(t);
  const char* did = button ? b_.press(t, kit().rng()) : b_.tap(t, kit().rng());
  input("tap", t);
  // Where it came from (`src`), and the finish it landed on, if any.
  char on[24] = "", classed[32] = "", data[80];
  if (finish) std::snprintf(on, sizeof(on), ",\"on\":%lu", (unsigned long)finish);
  if (was) std::snprintf(classed, sizeof(classed), ",\"was\":\"%s\"", was);
  std::snprintf(data, sizeof(data), "{\"src\":\"%s\"%s%s}", button ? "button" : "screen", on, classed);
  tell("tap", did, data, t, injected);
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
      live_.showDrawer = false;  // BOOT first: the drawer a reaction asked for stays shut
      live_.bootInjected = !hal_.bootDown();
      b_.pressDown(t);
      dirty_ = true;
      latency_.mark(Latency::kPress, real);
      break;
    case ButtonGesture::kTap:
      b_.pressUp();
      latency_.mark(Latency::kTap, live_.bootInjected ? pressGone : real);
      if (drawerOpen(t) > 0) {  // it only shuts the drawer: the Mac opens nothing
        input("tap", t);
        moveDrawer(0, t, live_.bootInjected);
        break;
      }
      tapped(t, live_.bootInjected, true);
      break;
    case ButtonGesture::kHoldStart:  // push-to-talk: listening at once, before the Mac hears
      b_.pressUp();
      if (b_.noApp(t)) break;  // nobody to hear it
      if (drawerOpen(t) > 0) moveDrawer(0, t, live_.bootInjected);  // its face listens, out from under the drawer
      // The reactions waiting would end it: dropped for every Mac that
      // hears talk_on, which for a tool's dbg.press is only USB's.
      kit().dropWaiting("mic_on", live_.bootInjected ? Link::kUsb : Link::kNone);
      b_.talkOn(t, kit().rng());
      input("talk_on", t);
      kit().emit("talk_on", "listening", nullptr, live_.bootInjected);
      drain();  // listening cuts what played
      break;
    case ButtonGesture::kHoldEnd:  // let go, or the 30 s cap
      if (b_.noApp(t)) break;
      b_.talkOff(t);
      input("talk_off", t);
      kit().emit("talk_off", nullptr, nullptr, live_.bootInjected);
      break;
    default:
      break;
  }

  // A touch anywhere is a tap, sent on release however long it was held,
  // unless the face leaned into it (followLean), but on the needs-you screen, where only a quick one is (kNeedsYouTapMs)
  // and a finger held still (TouchGesture::held)
  // is the gesture `dismiss`, sent as the hold completes with the
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
    live_.showDrawer = false;  // a finger first: the drawer a reaction asked for stays shut
    live_.touchPath.down(x, y, t);
    // A touch on the open drawer is the drawer's, and so is one that
    // starts on the strip, should it go up, while there are sessions to
    // list; neither moves the face.
    const int open = drawerOpen(t);
    live_.drawerTouch =
        faced && b_.face().hasDrawer() && !b_.noApp(t) && (open > 0 || (y >= kDrawerFromY && hasSessions()));
    // The face is told of the card as it is now: it may not have drawn it yet.
    const render::CardShow held = cardShow(t);
    if (faced) b_.face().card(held);
    live_.cardTouch = faced && !live_.drawerTouch && open <= 0 && held.on && b_.face().cardAt(x, y);
    live_.drawerPulling = live_.scrolling = live_.touchSpent = false;
    live_.drawerDownId = 0;
    if (live_.drawerTouch) {
      live_.drawerGrabbed = open, live_.drawerTouchedAt = t, live_.drawerInjected = live_.injTouch;
      // A finger down on gliding rows stops them where they are.
      const int at = drawerScroll(t);
      live_.scrollCaught = at != live_.scrollTo;
      live_.scrollGrabbed = live_.scrolled = at;
      glideDrawer(at, t);
      // The session under it now, which a tap picks even if a state
      // reorders the rows before it lets go.
      if (open >= 900) {
        makeDrawer(t);
        const int row = b_.face().drawerRow(drawer_, x, y);
        if (row >= 0 && drawer_.at(row)) live_.drawerDownId = drawer_.at(row)->id;
      }
    }
    // Only a touch that began on the screen holds it: a request that comes
    // up under a finger already down isn't dismissed by it.
    live_.touchOnNeedsYou = faced && needsYouShows(t) && open <= 0;
    live_.touchAttnId = live_.touchOnNeedsYou ? b_.model().attnId : 0;
    live_.touchDismissed = live_.touchLeant = false;
    if (faced) {
      b_.pressDown(t);
      if (!live_.drawerTouch && !live_.cardTouch) b_.face().finger(true, x, y);
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
    } else if (faced && !live_.cardTouch) {
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
    if (!live_.drawerTouch && !live_.cardTouch) b_.face().letGo(vx, vy);
    render::Gesture g = render::Gesture::kHandoff;
    const TouchGesture::Kind kind = live_.touchPath.up(g, b_.face().noseDrop(), live_.touchLeant);
    live_.lastTouch = live_.touchPath.path();
    live_.lastTouchWas = kind == TouchGesture::kGesture ? render::gestureName(g)
                         : kind == TouchGesture::kSwipe ? kSwipeGesture
                         : kind == TouchGesture::kLean  ? kLeanGesture
                                                        : "tap";
    if (faced) {
      // The panel's touch let go when it was last in contact, so its tap
      // counts the kTouchReleaseMs the device waits to be sure. Its path
      // may make it a gesture: a stroke, a ruffle, a swipe, a tickle, a
      // boop on the nose; then the board reacts as one, but not while the
      // face is held, where a touch is a tap. While a finish names whose
      // turn it was, any brief touch and any boop on the nose is a tap on
      // it, opening that thread: a quick tap is rarely a perfect one. A
      // longer stroke stays a stroke, so petting opens nothing.
      // A touch that began on the needs-you screen was for it: it gives no tap
      // once its hold dismissed it, or once the screen has gone (its request
      // answered or dismissed on the Mac).
      // A touch the drawer took (a pull, or any on it open) is the
      // drawer's alone: the Mac hears what it did, not a tap.
      // A touch whose drawer shut under it (needs you came, or the Mac
      // went) sends nothing. On the needs-you screen only a quick, still
      // touch is a tap, opening the thread: one held kNeedsYouTapMs or
      // more, or that strayed past kHoldSpotPx, was a hold let go early.
      // A touch the face leaned into is only that: it says so, and a finish
      // or a needs-you that came up under it hears no tap.
      const bool brief = live_.lastTouch.ms < kNeedsYouTapMs && live_.touchPath.spread() <= TouchGesture::kHoldSpotPx;
      if (live_.cardTouch) {
        // The card's: across it, the next card or the one before, which the
        // Mac picks; else a tap, which the Mac opens. Nothing plays here, and
        // a card gone from under the finger hears nothing.
        live_.lastTouchWas = "card";
        const int dx = live_.lastTouch.x - live_.lastTouch.x0, dy = live_.lastTouch.y - live_.lastTouch.y0;
        if (b_.cardShow(t).on) {
          input("card", t);
          const bool across = std::abs(dx) >= kCardSwipePx && std::abs(dx) > std::abs(dy);
          kit().emit("card", across ? (dx < 0 ? "next" : "prev") : "open", nullptr, live_.touchInjected);
        }
      } else if (live_.touchSpent) {
        if (live_.drawerTouch) live_.lastTouchWas = "drawer";
      } else if (live_.drawerTouch && (live_.drawerPulling || live_.drawerGrabbed > 0)) {
        live_.lastTouchWas = "drawer";
        if (live_.drawerPulling)
          letGoDrawer(t, vy);
        else if (live_.scrolling)
          letGoScroll(t, vy);
        else if (live_.scrollCaught)
          letGoScroll(t, 0);  // it only stopped the rows, on the nearest whole one
        else if (live_.touchPath.spread() < kDrawerPullPx)
          tapDrawer(live_.lastTouch.x0, live_.lastTouch.y0, t);
        else
          live_.drawerTouchedAt = t;  // a drag across it: it lets go, picking nothing
      } else if (!live_.touchOnNeedsYou && invited(kind, g, t, live_.touchInjected)) {
        live_.lastTouchWas = "invite";
      } else if (kind == TouchGesture::kLean) {
        leaned(t, live_.touchInjected);
      } else if (!(live_.touchOnNeedsYou && (live_.touchDismissed || !needsYouShows(t) || !brief))) {
        latency_.mark(Latency::kTap, live_.touchInjected ? touchGone : live_.touchSeenReal);
        const bool nose = kind == TouchGesture::kGesture && g == render::Gesture::kNose;
        const bool tapOnFinish =
            kind != TouchGesture::kTap && b_.finishShown(t) && (nose || live_.lastTouch.ms < kBriefOnFinishMs);
        // While an ask is up, a tap in the lane is only its answer: the
        // left half picks `a`, the right `b`.
        const bool onAnswer = kind == TouchGesture::kTap && b_.asking(t) && live_.lastTouch.y0 >= render::kLaneTop;
        if (onAnswer) {
          input("tap", t);
          b_.answer(live_.lastTouch.x0 < render::kWidth / 2 ? "a" : "b", t, live_.touchInjected);
          drain();
        } else if (kind == TouchGesture::kTap || b_.held(t) || tapOnFinish) {
          tapped(t, live_.touchInjected, false, kind == TouchGesture::kTap ? nullptr : live_.lastTouchWas);
        } else if (kind == TouchGesture::kSwipe && b_.model().pipCount > 1 && !b_.model().attn) {
          // Several agents: a swipe across the desk asks the Mac for the
          // next one, or the one before, which the screen follows.
          live_.lastTouchWas = "agent";
          input("agent", t);
          const int dx = live_.lastTouch.x - live_.lastTouch.x0;
          kit().emit("agent", dx < 0 ? "next" : "prev", nullptr, live_.touchInjected);
        } else {
          gestured(g, t, live_.touchInjected, kind == TouchGesture::kSwipe);
        }
      }
    }
  }
  // After letGo, which wakes a doze with a start: it has to see the lean.
  followLean(touching, t);
  if (!touching && live_.touchDown) live_.drawerTouch = live_.drawerPulling = live_.scrolling = live_.cardTouch = false;
  if (touching != live_.touchDown) dirty_ = true;
  live_.touchDown = touching;
  // A finger or BOOT jolts the board: the motion sensor's thump isn't one.
  if (touching || live_.boot.down()) live_.motion.hands(t);
}

// A finger at rest on the face: it leans in, then dozes, wherever nothing else
// has this touch or the screen. Never on the needs-you screen, whose hold
// dismisses; never on the drawer's, a finish's or an ask's lane, whose touches
// mean something else; never with BOOT's listening or a Moment. Whatever comes
// up over it ends the lean at once, and its touch goes on.
void Device::followLean(bool touching, uint32_t t) {
  using Lean = render::Face::Lean;
  Lean lean = Lean::kNone;
  const uint32_t rest = live_.touchPath.restMs(t);
  const bool free = touching && rest >= TouchGesture::kLeanMs && !live_.pattern && !live_.drawerTouch && !live_.cardTouch &&
                    !live_.touchOnNeedsYou &&
                    !b_.held(t) && !b_.finishShown(t) && !b_.faceDown() && drawerOpen(t) <= 0 &&
                    !(b_.asking(t) && live_.touchPath.path().y0 >= render::kLaneTop) && b_.face().leans(t);
  if (free) {
    lean = rest >= TouchGesture::kDozeMs ? Lean::kDoze : Lean::kIn;
    live_.touchLeant = true;
  }
  live_.lean = lean;
  b_.face().lean(lean, t);
}

bool Device::hasSessions() const {
  const Model& m = b_.model();
  return m.base != render::SceneState::kAsleep || m.attn || m.busy > 0 || m.idle > 0 || m.listCount > 0;
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
// and Boop hands it over as the drawer shuts; anywhere else, it shuts. The
// session is the one under the finger as it went down, and only while the
// drawer was open then and still is.
void Device::tapDrawer(int x, int y, uint32_t t) {
  live_.drawerTouchedAt = t;
  makeDrawer(t);
  const bool open = live_.drawerGrabbed >= 900 && drawerOpen(t) >= 900;
  const int row = open ? b_.face().drawerRow(drawer_, x, y) : -1;
  if (row >= 0 && !live_.drawerDownId) return;  // a row still coming: nothing to open yet
  if (row >= 0) {
    char data[32];
    std::snprintf(data, sizeof(data), "{\"id\":%lu}", (unsigned long)live_.drawerDownId);
    input("drawer", t, x, y);
    sayDrawer("pick", data, t);
    live_.drawerPicked = -1;  // its row lights where it is now
    for (int i = 0; i < drawer_.total(); ++i)
      if (drawer_.at(i) && drawer_.at(i)->id == live_.drawerDownId) live_.drawerPicked = i;
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
  // The drawer a reaction asked for, once its sign has been read: not over
  // a request that shows, nor under a finger.
  if (live_.showDrawer && !after(live_.showDrawerAt, t)) {
    live_.showDrawer = false;
    if (!live_.pattern && !b_.noApp(t) && !needsYouShows(t) && !live_.touchDown && live_.drawerTo <= 0) {
      live_.drawerTouchedAt = t;  // and shuts kDrawerShutMs on, as after a touch
      moveDrawer(1000, t, false);
    }
  }
  // A new needs-you shuts it, so its screen shows and a hold can dismiss
  // it; so does the Mac going, whose rows it can no longer trust. A finger
  // on it then sends nothing as it lets go.
  const bool alert = b_.alerts() != live_.alertsSeen && needsYouShows(t);
  live_.alertsSeen = b_.alerts();
  if ((alert || b_.noApp(t)) && (live_.drawerTo > 0 || live_.drawerPulling)) {
    if (live_.touchDown && live_.drawerTouch) live_.touchSpent = true;
    moveDrawer(0, t, live_.drawerInjected);
  }
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

// A touch of an invite's kind is the invite's, the Mac's poke or stroke: a
// tap, a boop on the nose or a tickle; a stroke, a ruffle or a finger the
// face leaned into. A swipe is a stroke here too, unless there are agents
// to swipe between: a finger petting a back lifts still moving. It plays
// the payoff and nothing else: no tap or gesture goes to the Mac, the
// invite's end does.
bool Device::invited(TouchGesture::Kind kind, render::Gesture g, uint32_t t, bool injected) {
  using G = render::Gesture;
  const bool gesture = kind == TouchGesture::kGesture;
  const bool swipe = kind == TouchGesture::kSwipe && b_.model().pipCount <= 1;
  const bool tap = kind == TouchGesture::kTap || (gesture && (g == G::kNose || g == G::kTickle));
  const bool stroke = kind == TouchGesture::kLean || ((gesture || swipe) && (g == G::kStroke || g == G::kRuffle));
  if (!(tap || stroke) || !b_.inviteTouch(stroke, t, injected)) return false;
  input("invite", t);
  dirty_ = true;
  drain();
  return true;
}

void Device::gestured(render::Gesture g, uint32_t t, bool injected, bool swipe) {
  if (!swipe || b_.face().playsSwipe()) b_.gesture(g, t);
  input("gesture", t);
  tell("gesture", swipe ? kSwipeGesture : render::gestureName(g), nullptr, t, injected);
  drain();  // the gesture cuts an animation, as a poke does
}

// A touch the face leaned into, let go. It tells the Mac as a stroke does: care,
// which meets a pet wish. Nothing plays: the face is already waking.
void Device::leaned(uint32_t t, bool injected) {
  input("gesture", t);
  b_.touchCaption(kLeanGesture, t);
  tell("gesture", kLeanGesture, nullptr, t, injected);
  drain();
}

// The motion sensor, every kMotionMs: picked up, put down, shaken, a thump
// on the desk, laid face down (do not disturb) and turned back up.
void Device::readMotion(uint32_t t) {
  if (int32_t(t - live_.motionAt) < int32_t(kMotionMs)) return;
  live_.motionAt = t;
  int ax = live_.injAx, ay = live_.injAy, az = live_.injAz;
  if (!live_.injMotion && !hal_.motion(ax, ay, az)) return;
  live_.tilt.update(ax, ay, az, t);
  b_.face().tilt(b_.faceDown() ? 0 : live_.tilt.mg(), t);
  switch (live_.motion.update(ax, ay, az, t)) {
    case MotionGesture::kPickup: gestured(render::Gesture::kPickup, t, live_.injMotion); break;
    case MotionGesture::kPutdown: gestured(render::Gesture::kPutdown, t, live_.injMotion); break;
    case MotionGesture::kShake: gestured(render::Gesture::kDizzy, t, live_.injMotion); break;
    case MotionGesture::kThump: gestured(render::Gesture::kStartle, t, live_.injMotion); break;
    case MotionGesture::kFaceDown:
      b_.setFaceDown(true, t);
      hush();
      hal_.stopEffects();  // do not disturb: the face's sounds too
      tell("gesture", "facedown", nullptr, t, live_.injMotion);
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
  tellWayUp(t);
  followSound(t);
  drain();

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
  if (m.vol == 0 || b_.faceDown()) return;  // muted, or face down: do not disturb
  const voice::EffectClips& clips = b_.face().clips();
  for (int i = 0; i < n; ++i) {
    const voice::EffectClip clip = clips.at(due[i].clip);
    hal_.effect({due[i].clip, due[i].gain, due[i].pitch, uint8_t(m.vol), due[i].duck, clip.samples, clip.len});
    ++fxSent_;
    fxLast_ = due[i].clip;
  }
}

// ---- Drawing ---------------------------------------------------------------

// Draws the frame for t. The face may skip one when nothing on it can have
// changed since the last (dirty_ says a message or input came since): the
// stub face does. The gel draws on every due pass (kFrameMs), so each is a
// frame.
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
    b_.face().wish(b_.wishShow(t));
    b_.face().color(b_.model().color);
    b_.face().card(cardShow(t));
    if (!b_.face().draw(canvas_, native ? &native->back() : nullptr, b_.show(t), t, b_.laneBubble(t), b_.caption(t), b_.sign(t),
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
