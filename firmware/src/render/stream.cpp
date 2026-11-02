#include "render/stream.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

#include "render/font.h"

namespace render {

namespace {

constexpr const char* kCallStyleNames[] = {"land",   "helper", "back",    "shatter", "bonk",   "bonk2",  "bonk3",
                                           "throw",  "shrug",  "timeout", "no",      "compact", "buried", "freeze",
                                           "drop",   "gather"};
static_assert(sizeof(kCallStyleNames) / sizeof(kCallStyleNames[0]) == int(CallStyle::kCount), "a name for every style");

// The same few bits for the same word, slot and count on every board, so a
// word falls where it did in the simulator.
uint32_t mix(uint32_t h) {
  h ^= h >> 16, h *= 0x7feb352d, h ^= h >> 15, h *= 0x846ca68b, h ^= h >> 16;
  return h;
}

}  // namespace

const char* callStyleName(CallStyle style) { return style < CallStyle::kCount ? kCallStyleNames[int(style)] : "land"; }

CallStyle callStyleFromName(const char* name) {
  if (!name) return CallStyle::kLand;
  for (int i = 0; i < int(CallStyle::kCount); ++i)
    if (!std::strcmp(name, kCallStyleNames[i])) return CallStyle(i);
  return CallStyle::kLand;
}

CallMove callMove(CallStyle style) {
  switch (style) {
    case CallStyle::kBonk:
    case CallStyle::kBonk2:
    case CallStyle::kBonk3:
    case CallStyle::kThrow:
    case CallStyle::kNo:
    case CallStyle::kTimeout: return CallMove::kHit;
    case CallStyle::kShrug: return CallMove::kShrug;
    case CallStyle::kShatter: return CallMove::kShatter;
    case CallStyle::kCompact: return CallMove::kCompact;
    case CallStyle::kBuried: return CallMove::kBuried;
    case CallStyle::kFreeze: return CallMove::kFreeze;
    case CallStyle::kDrop: return CallMove::kDrop;
    case CallStyle::kGather: return CallMove::kGather;
    default: return CallMove::kSink;
  }
}

uint32_t callFlightMs(CallStyle style) {
  if (style == CallStyle::kTimeout) return 1400;
  switch (callMove(style)) {
    case CallMove::kHit: return 380;
    case CallMove::kSink: return 520;
    case CallMove::kDrop: return 300;
    case CallMove::kGather: return 700;  // the words reach its mouth
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
  switch (call.style) {
    case CallStyle::kGather: return w.slot == call.slot;
    case CallStyle::kCompact:
    case CallStyle::kDrop: return true;
    default: return false;
  }
}

void Stream::drop(const Lane& lane, int column, int columns, uint32_t t) {
  // The newest of its lane's words still falling (or waiting to): this one
  // drops kWordGapPx behind it, no faster.
  const Word* ahead = nullptr;
  for (const auto& o : words)
    if (o.live && o.slot == lane.slot && (!ahead || int32_t(o.born - ahead->born) > 0)) ahead = &o;
  const uint32_t h = mix(lane.slot * 131u + lane.count * 7919u + uint8_t(lane.word[0]));
  uint16_t speed = uint16_t(95 + (h >> 8) % 50);
  uint32_t born = t;
  if (ahead) {
    speed = std::min(speed, ahead->speed);
    const uint32_t due = ahead->born + (uint32_t(kWordGapPx) * 1000 + ahead->speed - 1) / ahead->speed;
    if (int32_t(due - t) > 0) born = due;
    if (int32_t(born - t) > int32_t(kMostWaitMs)) return;
  }
  // The slot reused longest ago, or a free one.
  Word* w = &words[0];
  for (auto& o : words) {
    if (!o.live) {
      w = &o;
      break;
    }
    if (int32_t(o.born - w->born) < 0) w = &o;  // the clock wraps
  }
  std::snprintf(w->text, sizeof(w->text), "%s", lane.word);
  w->slot = lane.slot;
  const int half = glyphCount(lane.word) * kLarge.w / 2, lo = kWordEdgePx + half, hi = 502 - kWordEdgePx - half;
  w->x = int16_t(std::clamp(laneX(column, columns) + int(h % 81) - 40, lo, std::max(lo, hi)));
  w->speed = speed;
  w->born = born;
  w->live = true;
}

void Stream::setLanes(const Lane* in, int n, bool showing, bool cleared, uint32_t t) {
  if (showing && !on) {
    if (!paused) since = t;
    movedAt = t;
  }
  if (!showing && on) ending = true, endedAt = t;
  // A needs-you over the agents' work pauses it; anything else that stops
  // it ends it.
  paused = !showing && cleared && (on || paused);
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
      drop(l, i, n, t);
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

void Stream::startCall(const char* text, uint8_t slot, CallStyle style, uint32_t t) {
  std::snprintf(call.text, sizeof(call.text), "%s", text ? text : "");
  call.slot = slot;
  call.style = style;
  call.at = t;
  call.live = true;
}

ActKind actKindFromName(const char* name) {
  if (!name) return ActKind::kNone;
  if (!std::strcmp(name, "tests")) return ActKind::kTests;
  if (!std::strcmp(name, "push")) return ActKind::kPush;
  if (!std::strcmp(name, "build")) return ActKind::kBuild;
  return ActKind::kNone;
}

void Stream::setAct(const ActIn& in, bool hold, uint32_t t) {
  if (in.kind == ActKind::kNone) {
    if (hold && act.kind != ActKind::kNone) act.hidden = true;
    else act = Act{};
    return;
  }
  // The same run goes on, or comes to its result; anything else is a new one.
  const bool same = act.kind == in.kind && (act.result == ActResult::kRunning || in.result != ActResult::kRunning);
  if (!same) {
    act = Act{};
    act.kind = in.kind, act.at = t;
  }
  act.hidden = false;
  act.full = in.full;
  if (in.result == ActResult::kRunning) {
    std::snprintf(act.text, sizeof(act.text), "%s", in.text);
  } else if (act.result == ActResult::kRunning) {
    act.result = in.result;
    std::snprintf(act.resultText, sizeof(act.resultText), "%s", in.text);
    const uint32_t ready = act.at + actLeadMs(act.kind, act.full);
    act.resultAt = int32_t(ready - t) > 0 ? ready : t;
    if (!act.text[0]) std::snprintf(act.text, sizeof(act.text), "%s", in.text);
  }
}

Stream::ActNow Stream::actNow(uint32_t t) const {
  ActNow now;
  if (act.kind == ActKind::kNone || act.hidden) return now;
  now.kind = act.kind, now.full = act.full, now.text = act.text;
  now.ageMs = std::max(0, int(int32_t(t - act.at)));
  if (act.result != ActResult::kRunning && int32_t(t - act.resultAt) >= 0) {
    now.result = act.result, now.text = act.resultText;
    now.resultMs = int(int32_t(t - act.resultAt));
    now.leftMs = int(actResultMs(act.full)) - now.resultMs;
    if (now.leftMs <= 0) now.kind = ActKind::kNone;
  }
  return now;
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
