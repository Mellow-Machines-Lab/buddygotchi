#include "render/stream.h"

#include <algorithm>
#include <cstdio>
#include <cstring>


namespace render {

namespace {

constexpr const char* kCallStyleNames[] = {"land",   "helper", "back",    "shatter", "bonk",   "bonk2",  "bonk3",
                                           "throw",  "shrug",  "timeout", "no",      "drop",   "gather"};
static_assert(sizeof(kCallStyleNames) / sizeof(kCallStyleNames[0]) == int(CallStyle::kCount), "a name for every style");

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
    case CallMove::kGather: return 700;  // the word reaches its mouth
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

void Stream::setLanes(const Lane* in, int n, bool showing, bool cleared, uint32_t t) {
  if (!showing && on) ending = true, endedAt = t;
  if (showing) ending = false;
  on = showing;
  if (n > kLanes) n = kLanes;
  int to = -1;  // the lane whose word is the newest now
  for (int i = 0; i < n; ++i) {
    const int was = column(in[i].slot);
    if (was < 0 || in[i].count != lanes[was].count) to = i;
    else if (to < 0 && in[i].slot == newestSlot) to = i;
  }
  // The lane that had it has gone: the last that's left.
  if (to < 0 && n) to = n - 1;
  for (int i = 0; i < n; ++i) lanes[i] = in[i];
  laneCount = n;
  // Its word as it is now: the Mac holds a word a moment, then changes it
  // at the same count ("thinking", the time a long call takes).
  if (to >= 0) {
    std::snprintf(newest, sizeof(newest), "%s", lanes[to].word);
    newestSlot = lanes[to].slot;
  } else {
    newest[0] = '\0';
    newestSlot = -1;
  }
  if (cleared) {
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
  if (in.result == ActResult::kRunning) {
    std::snprintf(act.text, sizeof(act.text), "%s", in.text);
  } else if (act.result == ActResult::kRunning) {
    act.result = in.result;
    std::snprintf(act.resultText, sizeof(act.resultText), "%s", in.text);
    const uint32_t ready = act.at + kActLeadMs;
    act.resultAt = int32_t(ready - t) > 0 ? ready : t;
    if (!act.text[0]) std::snprintf(act.text, sizeof(act.text), "%s", in.text);
  }
}

Stream::ActNow Stream::actNow(uint32_t t) const {
  ActNow now;
  if (act.kind == ActKind::kNone || act.hidden) return now;
  now.kind = act.kind, now.text = act.text;
  now.ageMs = std::max(0, int(int32_t(t - act.at)));
  if (act.result != ActResult::kRunning && int32_t(t - act.resultAt) >= 0) {
    now.result = act.result, now.text = act.resultText;
    now.resultMs = int(int32_t(t - act.resultAt));
    now.leftMs = int(kActResultMs) - now.resultMs;
    if (now.leftMs <= 0) now.kind = ActKind::kNone;
  }
  return now;
}

void Stream::prune(uint32_t t) {
  if (call.live && int32_t(t - call.at) >= int32_t(kCallMs)) call.live = false;
  // The stream ended a while ago: its last word forward goes.
  if (ending && int32_t(t - endedAt) >= int32_t(kEndMs + kCallMs)) {
    ending = false;
    call.live = false;
  }
}

}  // namespace render
