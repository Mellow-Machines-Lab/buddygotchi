#include "render/gel/moves.h"

#include <algorithm>
#include <cstdio>

#include "render/gel/engine.h"
#include "render/gel/fixed.h"
#include "render/gel/raster.h"
#include "render/palette.h"
#include "rig_tables.h"  // the staged pack's (characters/charactergen.py)

namespace render::gel {

namespace {

using Phase = InviteShow::Phase;

const rig::Clip* clipOf(const char* a, const char* b = nullptr, const char* c = nullptr) {
  if (!a || !b) return nullptr;
  char id[32];
  std::snprintf(id, sizeof id, c ? "%s-%s-%s" : "%s-%s", a, b, c);
  return rig::kRig.clip(id);
}

}  // namespace

MoveShow inviteMove(const InviteShow& v) {
  const char* pose = invitePoseName(v.pose);
  const char* payoff = kInvitePayoffNames[int(v.payoff) < 4 ? int(v.payoff) : 0];
  const uint32_t ms = v.ms;
  switch (v.phase) {
    case Phase::kPose: {
      const rig::Clip* in = clipOf("invite", pose);
      if (in && ms < in->ms) return {in, ms};
      const rig::Clip* wait = clipOf("invite", pose, "wait");
      if (wait) return {wait, in ? ms - in->ms : ms};
      return {in, ms};
    }
    case Phase::kPayoff: return {clipOf("invite", payoff), ms};
    case Phase::kShrug: return {clipOf("invite", pose, "miss"), ms};
    case Phase::kLate:
      if (ms < InviteShow::kTurnMs) return {clipOf("invite", pose, "late"), ms};
      return {clipOf("invite", payoff), ms - InviteShow::kTurnMs};
    default: return {};
  }
}

MoveShow currentMove(const Engine& e) {
  if (e.invite.shows()) return inviteMove(e.invite);
  const Scenes& s = e.scenes;
  if (!s.generation || s.route.state != SceneState::kNeedsYou) return {};
  const int age = F(s.ageMs).integer();
  if (age >= int(slime::kKnockClimbAtMs)) {
    const rig::Clip* climb = rig::kRig.clip("knock-climb");
    if (climb && age - int(slime::kKnockClimbAtMs) < int(climb->ms))
      return {climb, uint32_t(age) - slime::kKnockClimbAtMs, true};
    return {};
  }
  const rig::Clip* knock = rig::kRig.clip("knock");
  if (knock && age < int(knock->ms)) return {knock, uint32_t(age), false};
  return {};
}

int sinceHit(const MoveShow& m) {
  if (!m.on()) return -1;
  const uint32_t t = m.clip->local(m.ms);
  int last = -1;
  for (const rig::Cue& c : m.clip->cues)
    if (m.clip->played(c.ms) <= t) last = int(m.clip->played(c.ms));
  return last < 0 ? -1 : int(t) - last;
}

void addMove(rig::Channels& c, const MoveShow& m, bool shake) {
  if (!m.on()) return;
  const uint32_t t = m.clip->local(m.ms);
  for (const rig::Track& track : m.clip->tracks) {
    const rig::ChannelInfo& info = rig::kChannelInfo[int(track.channel)];
    int16_t& to = c[track.channel];
    to = int16_t(std::clamp(int(to) + m.clip->value(track, t), int(info.lo), int(info.hi)));
  }
  if (shake) addShake(c, m);
}

void addShake(rig::Channels& c, const MoveShow& m) {
  // A hit shakes the body (and the hands on it) a little side to side,
  // dying away.
  const int hit = sinceHit(m);
  if (hit >= 0 && hit < kShakeMs) {
    const int left = kShakeMs - hit;
    const int shake = kShakePx * sinTurn(hit * 4096 / 70) * left / kShakeMs / 4096;
    c[rig::Channel::kX] = int16_t(std::clamp(c[rig::Channel::kX] + shake, -400, 400));
  }
}

void paintHits(Surface& s, const MoveShow& m, const Hand hands[2]) {
  const int hit = sinceHit(m);
  if (!s.pixels || hit < 0 || hit >= kHitMs) return;
  const Hand& h = hands[hands[1].glass * hands[1].shown() >= hands[0].glass * hands[0].shown() ? 1 : 0];
  if (!h.shown() || h.glass <= 0) return;
  Raster r{s};
  // A ring going out from it, and four short marks round it, fading.
  const int size = h.drawn16(), age = hit * 4096 / kHitMs;
  r.alpha = 255 - hit * 255 / kHitMs;
  Point ring[25];
  const int radius = size + size * age / 4096 / 2 + 8 * 16;
  for (int i = 0; i <= 24; ++i) {
    const int a = i * 4096 / 24;
    ring[i] = {h.x16 + radius * sinTurn(a + 1024) / 4096, h.y16 + radius * sinTurn(a) / 4096};
  }
  const uint16_t white = rgb565(255, 255, 255);
  r.stroke16(ring, 25, 3 * 16, white);
  for (int i = 0; i < 4; ++i) {
    const int a = 512 + i * 1024, from = radius + 5 * 16, to = from + 9 * 16;
    const Point mark[2] = {{h.x16 + from * sinTurn(a + 1024) / 4096, h.y16 + from * sinTurn(a) / 4096},
                           {h.x16 + to * sinTurn(a + 1024) / 4096, h.y16 + to * sinTurn(a) / 4096}};
    r.stroke16(mark, 2, 3 * 16, white);
  }
  r.alpha = 255;
}

}  // namespace render::gel
