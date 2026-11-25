#include "render/gel/lively.h"

#include <algorithm>
#include <cstring>

namespace render::gel {

namespace {

using rig::Channel;
using rig::HandPart;

// Far past anything a channel reaches: integrate's limits, which these
// springs never meet.
const F kFar = F(100000);
// Within this of its target and this slow, a spring is there.
const F kNear = q(.25), kStill = q(1);

void step(Spring& s, F dt, F target, LivelySpring k) { integrate(s, dt, target, F(k.frequency), F(k.damping), kFar, kFar); }
// At its target and still: set there, so it rests exactly.
void rest(Spring& s, F target) {
  if (abs(s.x - target) < kNear && abs(s.v) < kStill) s = {target, 0};
}
F value(const rig::Channels& c, Channel ch) { return F(int(c[ch])); }
int rounded(F f) { return (f + (f < F(0) ? q(-.5) : q(.5))).integer(); }
int16_t within(int v, Channel ch) {
  const rig::ChannelInfo& info = rig::kChannelInfo[int(ch)];
  return int16_t(std::clamp(v, int(info.lo), int(info.hi)));
}
constexpr HandPart kFollowed[3] = {HandPart::kX, HandPart::kY, HandPart::kSize};

}  // namespace

void Lively::reset() {
  for (int i = 0; i < kRuleCount; ++i) on[i] = kRules[i].on;
  for (auto& s : settled) s = {};
  flat = crown = {};
  face[0] = face[1] = {};
  for (auto& h : hand)
    for (auto& s : h) s = {};
  lastX = lastY = speedX = speedY = 0;
  up = started = false;
  for (int side = 0; side < 2; ++side) held[side] = homing[side] = false, fromDesk[side] = 0;
}

bool Lively::set(const char* name, bool value) {
  if (!std::strcmp(name, "all")) {
    for (bool& r : on) r = value;
    return true;
  }
  for (int i = 0; i < kRuleCount; ++i)
    if (!std::strcmp(name, kRules[i].name)) {
      on[i] = value;
      return true;
    }
  return false;
}

void Lively::advance(uint32_t ms, const rig::Channels& target, F engineLift, F engineSlide, bool desk) {
  if (!ms) return;
  const bool jump = !started || ms >= kSettledMs;
  const F dt = F::ratio(ms, 1000);
  // settle: the body's channels after the clips'. Off, or after a jump,
  // they're the clips' own.
  for (int i = 0; i < kSettledCount; ++i) {
    Spring& s = settled[i];
    const F to = value(target, kSettled[i]);
    if (!rule(Rule::kSettle) || jump) {
      s = {to, 0};
      continue;
    }
    // Round the short way: more than half a turn off, it's a whole turn
    // nearer where it is. Exactly half a turn off is as near either way,
    // and a whole turn would leave it half a turn off again. Come round
    // past the channel's limits, it starts from the limit, which is what
    // draws, so it never sits still there while the spring comes back.
    if (kSettled[i] == Channel::kTurn) {
      while (abs(s.x - to) * 2 > F(kWholeTurn)) s.x = s.x + (s.x < to ? F(kWholeTurn) : F(-kWholeTurn));
      const rig::ChannelInfo& info = rig::kChannelInfo[int(Channel::kTurn)];
      s.x = clamp(s.x, F(int(info.lo)), F(int(info.hi)));
    }
    step(s, dt, to, kSettle[i]);
    // The body stands on the floor: a lift going past it lands there.
    if (kSettled[i] == Channel::kLift && s.x < F(0)) s = {0, 0};
    rest(s, to);
  }
  // Where the body is, and how fast it goes.
  const F x = settled[3].x + engineSlide, y = max(0, settled[2].x + engineLift);
  if (jump) {
    speedX = speedY = 0;
  } else {
    speedX = (x - lastX) / dt;
    speedY = (y - lastY) / dt;
  }
  // stretch: a landing, the body back on the floor coming down, kicks the
  // flat spring as hard as it came down.
  const bool landed = up && y <= F(0) && speedY < F(0);
  if (rule(Rule::kStretch) && !jump) {
    if (landed) flat.v = flat.v - speedY * kLand;
    step(flat, dt, 0, kFlat);
    flat.x = clamp(flat.x, -kFlatMost, kFlatMost);
    rest(flat, 0);
  } else {
    flat = {};
  }
  up = y > F(0);
  // drag: the crown, behind the base's speed across.
  if (rule(Rule::kDrag) && !jump) {
    const F lean = clamp(-speedX * kDragPerSpeed / 1000, -kDragMost, kDragMost);
    step(crown, dt, lean, kCrown);
    rest(crown, 0);
  } else {
    crown = {};
  }
  // face: where the face is, after where the body is.
  if (rule(Rule::kFace) && !jump) {
    step(face[0], dt, x, kFaceSpring);
    step(face[1], dt, y, kFaceSpring);
    rest(face[0], x);
    rest(face[1], y);
  } else {
    face[0] = {x, 0}, face[1] = {y, 0};
  }
  lastX = x, lastY = y;
  // hands: each one's place and size after its clip's, from the desk's
  // keys when the desk had it, and back to them when it has it again.
  for (int side = 0; side < 2; ++side) {
    Spring* h = hand[side];
    const int sign = side ? 1 : -1;
    const bool wanted = target[rig::hand(side, HandPart::kSize)] > 0;
    if (!rule(Rule::kHands) || jump) {
      for (int p = 0; p < 3; ++p) h[p] = {value(target, rig::hand(side, kFollowed[p])), 0};
      held[side] = wanted, homing[side] = false;
      continue;
    }
    if (wanted && !held[side]) {
      // Out of the body, or off the keys.
      homing[side] = false;
      fromDesk[side] = 0;
      if (desk) {
        h[0] = {F(sign * kDeskX), 0}, h[1] = {F(kDeskY), 0}, h[2] = {F(kDeskSize), 0};
        fromDesk[side] = max(F(1), abs(value(target, rig::hand(side, HandPart::kX)) - h[0].x) +
                                       abs(value(target, rig::hand(side, HandPart::kY)) - h[1].x));
      }
      else if (h[2].x <= F(0)) h[0] = {value(target, rig::hand(side, HandPart::kX)), 0},
                               h[1] = {value(target, rig::hand(side, HandPart::kY)), 0}, h[2] = {0, 0};
    }
    if (!wanted && held[side] && desk) homing[side] = true;
    held[side] = wanted;
    if (!wanted && !desk) homing[side] = false;
    F to[3];
    for (int p = 0; p < 3; ++p) to[p] = value(target, rig::hand(side, kFollowed[p]));
    if (homing[side]) to[0] = F(sign * kDeskX), to[1] = F(kDeskY), to[2] = F(kDeskSize);
    if (fromDesk[side] > F(0)) {
      // The desk's size, less as it nears where the clip has it.
      const F left = (abs(to[0] - h[0].x) + abs(to[1] - h[1].x)) / fromDesk[side];
      if (left < q(.2) || !wanted) fromDesk[side] = 0;
      else to[2] = max(to[2], F(kDeskSize) * min(F(1), left));
    }
    for (int p = 0; p < 3; ++p) {
      step(h[p], dt, to[p], p == 2 ? kHandSize : kHandPlace);
      rest(h[p], to[p]);
    }
    if (h[2].x < F(0)) h[2] = {0, 0};
    // Home: the desk has it again.
    if (homing[side] && abs(h[0].x - to[0]) <= F(kHome) && abs(h[1].x - to[1]) <= F(kHome) &&
        abs(h[2].x - to[2]) <= F(kHome) * 10) {
      homing[side] = false;
      h[2] = {0, 0};
    }
  }
  started = true;
}

rig::Channels Lively::apply(const rig::Channels& target) const {
  rig::Channels c = target;
  if (!started) return c;
  if (rule(Rule::kSettle))
    for (int i = 0; i < kSettledCount; ++i) c[kSettled[i]] = within(rounded(settled[i].x), kSettled[i]);
  if (rule(Rule::kStretch)) {
    const F tall = min(abs(speedY) * kTallPerSpeed / 1000, kTallMost);
    c[Channel::kSquash] = within(c[Channel::kSquash] + rounded(flat.x - tall), Channel::kSquash);
  }
  if (rule(Rule::kDrag)) c[Channel::kLean] = within(c[Channel::kLean] + rounded(crown.x), Channel::kLean);
  if (rule(Rule::kHands))
    for (int side = 0; side < 2; ++side)
      for (int p = 0; p < 3; ++p) {
        const Channel ch = rig::hand(side, kFollowed[p]);
        c[ch] = within(rounded(hand[side][p].x), ch);
      }
  return c;
}

int Lively::faceX16() const {
  if (!started || !rule(Rule::kFace)) return 0;
  return std::clamp(rounded((face[0].x - lastX) * kFaceGain * 16 / 1000), -kFaceMost * 16, kFaceMost * 16);
}
int Lively::faceY16() const {
  if (!started || !rule(Rule::kFace)) return 0;
  return std::clamp(rounded((face[1].x - lastY) * kFaceGain * 16 / 1000), -kFaceMost * 16, kFaceMost * 16);
}

}  // namespace render::gel
