#include "render/stream.h"

#include <cstdio>
#include <cstring>

namespace render {

namespace {

constexpr const char* kGagNames[] = {"land",  "arrive", "look",   "stir",    "stamp",   "launch", "poof",  "plane",
                                     "phone", "page",   "helper", "back",    "shatter", "cross",  "stack", "pass",
                                     "built", "hail",   "bonk",   "bonk2",   "helmet",  "throw",  "shrug", "timeout",
                                     "no",    "combo",  "topple", "compact", "buried",  "freeze", "drop",  "gather"};
static_assert(sizeof(kGagNames) / sizeof(kGagNames[0]) == int(CallGag::kCount), "a name for every gag");

// The same few bits for the same word, slot and count on every board, so a
// word falls where it did in the simulator.
uint32_t mix(uint32_t h) {
  h ^= h >> 16, h *= 0x7feb352d, h ^= h >> 15, h *= 0x846ca68b, h ^= h >> 16;
  return h;
}

}  // namespace

const char* callGagName(CallGag gag) { return gag < CallGag::kCount ? kGagNames[int(gag)] : "land"; }

CallGag callGagFromName(const char* name) {
  if (!name) return CallGag::kLand;
  for (int i = 0; i < int(CallGag::kCount); ++i)
    if (!std::strcmp(name, kGagNames[i])) return CallGag(i);
  return CallGag::kLand;
}

CallMove callMove(CallGag gag) {
  switch (gag) {
    case CallGag::kArrive: return CallMove::kArrive;
    case CallGag::kLook: return CallMove::kLook;
    case CallGag::kStir: return CallMove::kStir;
    case CallGag::kStamp: return CallMove::kStamp;
    case CallGag::kLaunch: return CallMove::kRocket;
    case CallGag::kPoof: return CallMove::kPoof;
    case CallGag::kPlane: return CallMove::kPlane;
    case CallGag::kPhone: return CallMove::kPhone;
    case CallGag::kPage: return CallMove::kPage;
    case CallGag::kHelper: return CallMove::kHelper;
    case CallGag::kBack: return CallMove::kBack;
    case CallGag::kBonk:
    case CallGag::kBonk2:
    case CallGag::kHelmet:
    case CallGag::kThrow:
    case CallGag::kNo:
    case CallGag::kTimeout: return CallMove::kHit;
    case CallGag::kShrug: return CallMove::kShrug;
    case CallGag::kShatter: return CallMove::kShatter;
    case CallGag::kHail: return CallMove::kHail;
    case CallGag::kPass:
    case CallGag::kBuilt: return CallMove::kCheer;
    case CallGag::kCombo: return CallMove::kCombo;
    case CallGag::kCross:
    case CallGag::kStack: return CallMove::kDesk;
    case CallGag::kTopple: return CallMove::kTopple;
    case CallGag::kCompact: return CallMove::kCompact;
    case CallGag::kBuried: return CallMove::kBuried;
    case CallGag::kFreeze: return CallMove::kFreeze;
    case CallGag::kDrop: return CallMove::kDrop;
    case CallGag::kGather: return CallMove::kGather;
    default: return CallMove::kSink;
  }
}

uint32_t callFlightMs(CallGag gag) {
  if (gag == CallGag::kTimeout) return 1400;
  switch (callMove(gag)) {
    case CallMove::kHit: return 380;
    case CallMove::kSink:
    case CallMove::kArrive: return 520;
    case CallMove::kHail:
    case CallMove::kCheer:
    case CallMove::kCombo:
    case CallMove::kDrop: return 300;
    case CallMove::kPlane:
    case CallMove::kGather: return 700;  // the words reach its mouth
    case CallMove::kBack: return 650;
    case CallMove::kTopple: return 1000;  // its wobble, then the fall
    case CallMove::kCompact: return 900;  // squashed, then the cube's drop
    case CallMove::kBuried: return 1200;  // the pile reaching its eyes
    case CallMove::kFreeze: return 600;   // the poke
    default: return 450;
  }
}

void Stream::clear() { *this = Stream{}; }

int Stream::column(uint8_t slot) const {
  for (int i = 0; i < laneCount; ++i)
    if (lanes[i].slot == slot) return i;
  return -1;
}

bool Stream::accepts(uint32_t t) const { return on || (ending && int32_t(t - endedAt) < int32_t(kEndMs)); }

bool Stream::drawn(uint32_t t) const { return on || (ending && int32_t(t - endedAt) < int32_t(kEndMs + kCallMs)); }

bool Stream::taken(const Word& w) const {
  if (!call.live || !w.live || int32_t(w.born - call.at) > 0) return false;
  switch (call.gag) {
    case CallGag::kGather: return w.slot == call.slot;
    case CallGag::kCompact:
    case CallGag::kDrop: return true;
    default: return false;
  }
}

void Stream::drop(const Lane& lane, int column, int columns, uint32_t t) {
  // The slot reused longest ago, or a free one.
  Word* w = &words[0];
  for (auto& o : words) {
    if (!o.live) {
      w = &o;
      break;
    }
    if (o.born < w->born) w = &o;
  }
  const uint32_t h = mix(lane.slot * 131u + lane.count * 7919u + uint8_t(lane.word[0]));
  std::snprintf(w->text, sizeof(w->text), "%s", lane.word);
  w->slot = lane.slot;
  w->x = int16_t(laneX(column, columns) + int(h % 81) - 40);
  w->speed = uint16_t(95 + (h >> 8) % 50);
  w->born = t;
  w->live = true;
}

void Stream::setLanes(const Lane* in, int n, bool showing, bool cleared, uint32_t t) {
  if (showing && !on) since = movedAt = t;
  if (!showing && on) ending = true, endedAt = t;
  if (showing) ending = false;
  on = showing;
  if (n > kLanes) n = kLanes;
  for (int i = 0; i < n; ++i) {
    const Lane& next = in[i];
    const int was = column(next.slot);
    if (was < 0) {
      drop(next, i, n, t);
      movedAt = t;
      continue;
    }
    // Counts go round at 1000.
    const int moved = (next.count - lanes[was].count + 1000) % 1000;
    if (moved) movedAt = t;
    for (int k = 0; k < moved && k < kDropsPerState; ++k) {
      Lane l = next;
      l.count = uint16_t(next.count + 1000 - k);
      drop(l, i, n, t + uint32_t(k) * kDropGapMs);
    }
  }
  for (int i = 0; i < n; ++i) lanes[i] = in[i];
  laneCount = n;
  if (cleared) {
    for (auto& w : words) w.live = false;
    call.live = false;
    ending = false;
  }
}

void Stream::startCall(const char* text, uint8_t slot, CallGag gag, uint16_t count, uint32_t t) {
  std::snprintf(call.text, sizeof(call.text), "%s", text ? text : "");
  call.slot = slot;
  call.gag = gag;
  call.count = count;
  call.at = t;
  call.live = true;
}

void Stream::prune(uint32_t t) {
  // The words a gather, a compaction or a drop takes go once they're taken.
  if (call.live && int32_t(t - call.at) >= int32_t(kTakeMs))
    for (auto& w : words)
      if (taken(w)) w.live = false;
  // A freeze over, the words it held fall on from where they stopped.
  if (frozen() && int32_t(t - call.at) >= int32_t(kCallMs))
    for (auto& w : words)
      if (w.live && int32_t(w.born - call.at) <= 0) w.born += kCallMs;
  if (call.live && int32_t(t - call.at) >= int32_t(kCallMs)) call.live = false;
  for (auto& w : words) {
    const bool held = frozen() && int32_t(w.born - call.at) <= 0;
    if (w.live && !held && int32_t(t - w.born) >= int32_t(kFallMs)) w.live = false;
  }
  // The stream ended a while ago: its last words and word forward go.
  if (ending && int32_t(t - endedAt) >= int32_t(kEndMs + kCallMs)) {
    ending = false;
    for (auto& w : words) w.live = false;
    call.live = false;
  }
  if (ending && int32_t(t - endedAt) >= int32_t(kEndMs))
    for (auto& w : words)
      if (w.live && !taken(w)) w.live = false;
}

bool Stream::moving(uint32_t t) const {
  if (call.live && int32_t(t - call.at) < int32_t(kCallMs)) return true;
  for (const auto& w : words)
    if (w.live && int32_t(t - w.born) < int32_t(kFallMs)) return true;
  return false;
}

}  // namespace render
