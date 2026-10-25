#include "render/stream.h"

#include <cstdio>
#include <cstring>

namespace render {

namespace {

constexpr const char* kGagNames[] = {"land",  "arrive", "look",  "stir",    "stamp", "launch", "poof",
                                     "plane", "phone",  "page",  "helper",  "back",  "shatter", "cross",
                                     "stack", "pass",   "built", "hail",    "bonk",  "bonk2",  "helmet",
                                     "throw", "shrug",  "timeout", "no",    "combo"};
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
    case CallGag::kBuilt:
    case CallGag::kCombo: return CallMove::kCheer;
    case CallGag::kCross:
    case CallGag::kStack:
    case CallGag::kLaunch: return CallMove::kDesk;
    default: return CallMove::kSink;
  }
}

uint32_t callFlightMs(CallGag gag) {
  if (gag == CallGag::kTimeout) return 1400;
  switch (callMove(gag)) {
    case CallMove::kHit: return 380;
    case CallMove::kSink: return 520;
    case CallMove::kHail: return 300;
    case CallMove::kCheer: return 300;
    default: return 450;
  }
}

void Stream::clear() {
  *this = Stream{};
}

int Stream::column(uint8_t slot) const {
  for (int i = 0; i < laneCount; ++i)
    if (lanes[i].slot == slot) return i;
  return -1;
}

void Stream::drop(const Lane& lane, uint32_t t) {
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
  w->dx = int16_t(int(h % 121) - 60);
  w->speed = uint16_t(95 + (h >> 8) % 50);
  w->born = t;
  w->live = true;
}

void Stream::setLanes(const Lane* in, int n, bool showing, uint32_t t) {
  on = showing;
  if (n > kLanes) n = kLanes;
  for (int i = 0; i < n; ++i) {
    const Lane& next = in[i];
    const int was = column(next.slot);
    if (was < 0) {
      drop(next, t);
      continue;
    }
    // Counts go round at 1000.
    const int moved = (next.count - lanes[was].count + 1000) % 1000;
    for (int k = 0; k < moved && k < kDropsPerState; ++k) {
      Lane l = next;
      l.count = uint16_t(next.count + 1000 - k);
      drop(l, t + uint32_t(k) * kDropGapMs);
    }
  }
  // A lane gone takes its words.
  for (auto& w : words) {
    bool kept = false;
    for (int i = 0; i < n; ++i) kept |= in[i].slot == w.slot;
    if (!kept) w.live = false;
  }
  for (int i = 0; i < n; ++i) lanes[i] = in[i];
  laneCount = n;
  if (!on) {
    for (auto& w : words) w.live = false;
    call.live = false;
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
  for (auto& w : words)
    if (w.live && t - w.born >= kFallMs && int32_t(t - w.born) >= 0) w.live = false;
  if (call.live && int32_t(t - call.at) >= int32_t(kCallMs)) call.live = false;
}

bool Stream::moving(uint32_t t) const {
  if (call.live && int32_t(t - call.at) < int32_t(kCallMs)) return true;
  for (const auto& w : words)
    if (w.live && int32_t(t - w.born) < int32_t(kFallMs)) return true;
  return false;
}

}  // namespace render
