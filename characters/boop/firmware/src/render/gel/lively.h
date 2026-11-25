// The motion layer, under every clip: five rules the face runs on the rig's
// channels after its mixer, its follows and its moves, so a clip's author
// writes only the main pose and the gel adds the rest. Motion V2, Lively:
// V1's springs (render/gel/motion.h) as they were, and these over them.
//
// - stretch: the body goes tall while it moves up or down fast, and flat as
//   it lands, then wobbles back (its own spring, `flat`). Its volume stays
//   the same, as the painter keeps it for every squash.
// - settle: each body channel (squash, lean, lift, x, reach, melt, the
//   glass and the turn) is a loose spring toward what the clips ask, so a
//   stop goes past and wobbles back. Off, the channels are the clips' own.
//   The turn goes round the short way: a whole turn on is where it began,
//   so a spin that ends never unwinds.
// - drag: the crown follows the base, so a slide sideways or its stop bends
//   the dome: the lean, opposite the body's speed across, on a spring of its
//   own.
// - face: the eyes and the mouth trail the body by a few px and catch up,
//   on two springs of their own (across and up). It's the one rule that
//   moves the face on the body by itself: until V2 the face never did.
// - hands: each hand's place and size follow its clip on springs, so a hand
//   arrives late and leaves late; a hand that comes from the desk's keys
//   starts there, and one going back to them goes there before the desk has
//   it again, so a hand never jumps from one owner to the next.
//
// The body's place, for stretch, drag and face, is the rig's lift and x and
// the engine's own lift and slide (its gestures and bits), in canvas px.
//
// Each rule has its switch (kRules, all on by default), which a scenario or
// the Studio sets by name with dbg.motion; a reset puts them back. Off, a
// rule gives back the motion before it exactly. At rest every spring rests
// on its target, so a still pose is drawn as it was before V2.
//
// Stepped on the face's clock (GelFace::advanceTo), in the same 1/240 s
// substeps as every spring: deterministic, so the board, the simulator and
// the Mac's mirror draw the same. Nothing allocates.
#pragma once
#include <cstdint>

#include "render/gel/fixed.h"
#include "render/rig/rig.h"

namespace render::gel {

enum class Rule : uint8_t { kStretch, kSettle, kDrag, kFace, kHands, kCount };
constexpr int kRuleCount = int(Rule::kCount);
// Each rule's name, for dbg.motion, and whether it's on by default.
struct RuleInfo {
  const char* name;
  bool on;
};
constexpr RuleInfo kRules[kRuleCount] = {
    {"stretch", true}, {"settle", true}, {"drag", true}, {"face", true}, {"hands", true}};

// The numbers of motion V2 (test_motion's test_the_motion_v2_numbers pins
// them). A spring is its frequency (rad/s, stiffness its square) and its
// damping (per s), as render/gel/fixed.h's integrate takes them.
struct LivelySpring {
  int frequency, damping;
};
struct Lively {
  // settle: by the channels it springs, in kSettled's order.
  static constexpr int kSettledCount = 8;
  static constexpr rig::Channel kSettled[kSettledCount] = {rig::Channel::kSquash, rig::Channel::kLean,
                                                           rig::Channel::kLift,   rig::Channel::kX,
                                                           rig::Channel::kReach,  rig::Channel::kMelt,
                                                           rig::Channel::kGlass,  rig::Channel::kTurn};
  static constexpr LivelySpring kSettle[kSettledCount] = {{44, 31}, {30, 21}, {40, 36}, {34, 31},
                                                          {30, 30}, {30, 30}, {36, 36}, {26, 24}};
  // The turn's whole turn, in its channel's thousandths.
  static constexpr int kWholeTurn = 1000;
  // stretch: the squash kTallPerSpeed thousandths of a thousandth taller
  // for each px a second up or down, at most kTallMost; landing, the flat spring is kicked by kLand
  // thousandths a second for each px a second it came down at.
  static constexpr int kTallPerSpeed = 700, kTallMost = 220;
  static constexpr int kLand = 30, kFlatMost = 300;
  static constexpr LivelySpring kFlat = {38, 23};
  // drag: the crown's lean, kDragPerSpeed thousandths of a thousandth for
  // each px a second across (the other way), at most kDragMost, on its
  // spring.
  static constexpr int kDragPerSpeed = 2500, kDragMost = 320;
  static constexpr LivelySpring kCrown = {19, 11};
  // face: where the face is follows where the body is on this spring; it's
  // drawn kFaceGain (thousandths) of the way it's behind, at most kFaceMost
  // canvas px either way.
  static constexpr LivelySpring kFaceSpring = {22, 22};
  static constexpr int kFaceGain = 1000, kFaceMost = 8;
  // hands: each hand's x and y, and its size.
  static constexpr LivelySpring kHandPlace = {24, 24}, kHandSize = {34, 38};
  // The desk's paw, as the rig's hand channels have it: x (each side, px),
  // y and size (thousandths); a hand that's back at the desk within kHome
  // px and thousandths is the desk's again.
  static constexpr int kDeskX = 12, kDeskY = 4, kDeskSize = 765, kHome = 3;
  // A step this long or longer sets everything where it's going, as the
  // mixer's springs do.
  static constexpr uint32_t kSettledMs = 1000;

  bool on[kRuleCount];
  Spring settled[kSettledCount], flat, crown, face[2], hand[2][3];
  // Where the body was last step (px across and up), how fast it went, and
  // whether it was up off the floor.
  F lastX, lastY, speedX, speedY;
  bool up = false, started = false;
  // Each hand: whether a clip has it (its size above 0), and whether it's on
  // its way back to the desk.
  bool held[2]{}, homing[2]{};
  // Each hand off the desk's keys: how far it had to go from them (px,
  // across and up), its size the desk's until it's on its way, shrinking to
  // the clip's as it gets there; none once it's there.
  F fromDesk[2]{};

  Lively() { reset(); }
  void reset();
  // A rule on or off by name ("all" for every one): false for a name it
  // doesn't know.
  bool set(const char* rule, bool on);
  bool rule(Rule r) const { return on[int(r)]; }
  // A step of `ms` toward `target` (the channels before the layer), the
  // engine's own lift and slide in canvas px, and whether the desk's paws
  // are out.
  void advance(uint32_t ms, const rig::Channels& target, F engineLift, F engineSlide, bool desk);
  // The channels as drawn: `target` with each rule's part.
  rig::Channels apply(const rig::Channels& target) const;
  // How far the face is behind the body, in sixteenths of a canvas px (x
  // right, y up).
  int faceX16() const;
  int faceY16() const;
};

}  // namespace render::gel
