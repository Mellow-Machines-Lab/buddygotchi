// The needs-you screen: Boop holds up an amber placard that
// fills the screen, with who's asking in large type, and peeks over its top
// edge, ducking and popping up at the left corner, the right, then the
// middle. The longer the request waits, the harder it asks (Arc): it sways
// the placard and waves a mitt over its edge, then shakes it and waves both,
// then lowers it and stares at you over it, and at last gives up and goes
// back to peeking. It replaces the mood's needs-you design; the design's sounds
// still play, and the arc's own cues (kArcCues) play over them. Pure
// drawing, a function of the time since the request came.
#pragma once
#include <cstdint>

#include "render/canvas.h"
#include "render/screens.h"

namespace render {

// How the asking grows, in ms from the request.
struct Arc {
  static constexpr uint32_t kSwayAt = 5000;     // calm until here, then it sways the placard and waves
  static constexpr uint32_t kShakeAt = 12000;   // then shakes it and waves both mitts
  static constexpr uint32_t kStareAt = 17000;   // then lowers it and stares at you over it
  static constexpr uint32_t kGiveUpAt = 22000;  // then it gives up: calm again, for good
  // The sway and the shake: the placard goes kSway px either way and bobs up
  // kBob px once every kBeat ms. Swaying, the head pops from spot to spot
  // every kSwayHopMs; shaking, it bounces in the middle.
  static constexpr uint32_t kSwayBeatMs = 560, kShakeBeatMs = 280;
  static constexpr int kSway = 6, kShake = 12;
  static constexpr int kSwayBob = 6, kShakeBob = 9;
  static constexpr uint32_t kSwayHopMs = 1400;
  // The waving mitts, kUp px above the placard's edge, wave back and forth
  // kWave px either way, tilting kTilt px at the knuckles, once every
  // kWaveMs: one mitt swaying, kOut px from the head's spot on the side
  // away from it; both shaking, kOut px either side of the middle.
  static constexpr uint32_t kSwayWaveMs = 700, kShakeWaveMs = 360;
  static constexpr int kSwayWave = 16, kShakeWave = 18, kTilt = 5;
  static constexpr int kMittOut = 92, kMittUp = 22;
  // The stare: the placard comes down to kStareTop over kLowerMs, and the head
  // grows to kStareScale at kStareY in the middle, all of the face showing.
  static constexpr uint32_t kLowerMs = 400;
  static constexpr int kStareTop = 84, kStareY = 52, kStareScale = 40;
};

// The arc's sounds: a clip from the face's bank (by name) at a time from
// the request, at a gain (255 as loud as a take) and a pitch (permille),
// over the needs-you design's own. They grow with the picture: a soft
// knock as it starts to sway, two higher ones mid-sway, three louder and
// higher as it shakes, a burst at the height of it, then the brake into
// the stare. Never ducked, like needs you's.
struct ArcCue {
  uint32_t at;
  const char* clip;
  uint8_t gain;
  uint16_t pitch = 1000;
};
constexpr ArcCue kArcCues[] = {
    {Arc::kSwayAt, "swipe", 200},                    // it starts to sway the placard and wave
    {Arc::kSwayAt + 300, "alertKnock", 170},         // knock
    {Arc::kSwayAt + 3500, "alertKnock", 190, 1060},  // knock, knock
    {Arc::kSwayAt + 3800, "alertKnock", 190, 1060},
    {Arc::kShakeAt, "alertKnock", 225, 1120},  // the shake: knock, knock, knock
    {Arc::kShakeAt + 250, "alertKnock", 225, 1120},
    {Arc::kShakeAt + 500, "alertKnock", 225, 1120},
    {Arc::kShakeAt + 2500, "alertKnock", 255, 1200},  // the height of it: a burst
    {Arc::kShakeAt + 2650, "alertKnock", 255, 1200},
    {Arc::kShakeAt + 2800, "alertKnock", 255, 1200},
    {Arc::kShakeAt + 2950, "alertKnock", 255, 1200},
    {Arc::kStareAt, "brake", 230},   // and it stops dead
    {Arc::kGiveUpAt, "slide", 200},  // the placard goes back up
};

struct NeedsYou {
  // Timings, in ms from the request.
  static constexpr uint32_t kHoldMs = 500;         // the whole face first
  static constexpr uint32_t kRiseMs = 550;         // the placard comes up and the head shrinks behind it
  static constexpr uint32_t kSettledMs = 1200;     // the nudges and hops start
  static constexpr uint32_t kNudgeEveryMs = 3600;  // the placard bumps up, the alert
  static constexpr uint32_t kNudgeMs = 350;
  static constexpr int kNudgePx = 5;
  static constexpr uint32_t kHopMs = 4200;  // the head stays in one spot this long
  static constexpr uint32_t kDuckMs = 300;  // at a spot's end it ducks behind the placard
  static constexpr uint32_t kPopMs = 350;   // and pops up at the next
  // The placard, settled, and the head's spots along its top edge.
  static constexpr int kLeft = 8, kTop = 48, kWidth = 304, kHeight = 188;
  static constexpr int kSpots = 3;
  static constexpr int kSpotX[kSpots] = {64, 256, 160};  // left corner, right corner, the middle
  static constexpr int kHeadY = 43;      // the head's centre when it peeks
  static constexpr int kHeadScale = 29;  // its size then, in 64ths of the whole face
  static constexpr int kPad = 16;        // the placard's text from its edges
};

// Where everything is at one moment. Two equal poses draw the same pixels
// for the same text, so the device skips redrawing an unchanged one: the
// pose has no padding, so two compare as bytes.
struct NeedsYouPose {
  int16_t placardY = 0;          // the placard's top
  int16_t headX = 0, headY = 0;  // the face's centre
  int16_t handX = 0, handY = 0;  // the spot the mitts are for, and their top
  int16_t placardX = 0;          // the placard swayed from its place, and the mitts with it
  int16_t waveX = 0, waveY = 0;  // the waving mitt's centre (the right one, with both) and top
  int16_t waveX2 = 0;            // with both, the left one's centre
  uint8_t scale = 64;            // the face's size in 64ths
  int8_t glance = 0;             // the eyes look left (-1), ahead or right (1)
  bool eyesShut = false;         // a blink
  bool whole = true;             // the cheeks and mouth show, before the placard hides them
  bool hands = false;            // the mitts on the placard's top edge, either side of the head
  uint8_t waving = 0;            // mitts let go to wave over the edge: none, the one at waveX, or both
  int8_t tilt = 0;               // how far the mitts' knuckles lean, left (-) or right
  bool flat = false;             // the stare's flat mouth, in place of the "o"
};
static_assert(sizeof(NeedsYouPose) == 9 * 2 + 8, "a pose has no padding to compare");

// The pose `ms` after the request, with the device's blink (none while it
// stares) and press dip.
NeedsYouPose needsYouPose(uint32_t ms, bool eyesShut = false, int dy = 0);
// The needs-you screen: the strip until the placard covers it, the head, the
// placard over it with the strip's agent, thread (else project) and "+N more",
// and the mitts either side of the head, or one of them waving. Drawn
// whole over the black the face clears the canvas to; under a mask (a
// dissolve), only the pixels the mask draws, its black too, so it
// dissolves as a picture.
void drawNeedsYouScreen(Canvas& c, const NeedsYouPose& p, const Strip& s);

}  // namespace render
