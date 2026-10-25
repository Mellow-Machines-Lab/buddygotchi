// The rig face: Pixel's plain face drawn from the rig's channels
// (render/rig/), so it moves continuously, with each drawn mood's own art as
// its parts (faces.h's kParts, which facegen cuts from the mood's idle face
// at rest). A style of the staged pack's rig names the drawn mood whose eyes
// or mouth it draws.
//
// At rest each part is drawn as its art has it, and the channels' offsets
// from rest move it. The body's lift, squash and lean the whole face; the
// eyes' close each eye onto the line it shuts on (its shut art below a
// third open), scale them and shift them; the mouth's opens it. The cheeks
// stay as the style's art has them. A style changing cross-fades over the
// mixer's style mix: each part dithers out as the next one's dithers in,
// both morphing from the one's box to the other's. In a design whose face
// is its mood's resting face (render::rigFaced), it's drawn in the face's
// place, moved as the design moves it, and shut where the design's face is
// (its shut eyes and its shut face's mouth). Pure: a function of the
// mixer's state.
#pragma once
#include <cstdint>

#include "render/canvas.h"
#include "render/pixel/scene.h"
#include "render/rig/mixer.h"

namespace render::pixel {

// A part placed: which one (faces::kParts[style][kind]), where its pivot
// is, its scale each way in 1024ths, and the pixels it draws.
struct Placed {
  uint8_t style = 0, kind = 0;
  int16_t x = 0, y = 0, sx = 1024, sy = 1024;
  Dither dither;
};
// What the rig face draws: its parts placed, and while it talks the "o" in
// its mouth's place (its corner, and its ink; 0 for none). Two equal frames
// draw the same pixels.
struct RigFrame {
  static constexpr int kMaxParts = 8;  // two styles' eyes and cheeks, and two mouths
  Placed parts[kMaxParts];
  int16_t talkX = 0, talkY = 0;
  uint8_t count = 0, talkInk = 0;
  Dither talk;
  bool operator==(const RigFrame& o) const;
};

class RigFace {
 public:
  // The velocity a press gives the squash, and each px of a stroke the lean.
  static constexpr int kPressKick = 6000, kStrokeKick = 400;
  // What the rig face wears in a mood: the drawn moods (faces::kMoodNames)
  // whose eyes and mouth it draws, and where its brim and hands are at rest,
  // which the hat and the sign ride from.
  struct Pose {
    uint8_t eyes, mouth;
    rig::Point brim, hand;
  };
  // Mood m's: from the staged rig's expression for it, else for the drawn
  // mood it wears, when both its styles name drawn moods. nullptr for none:
  // the baked designs draw that mood.
  static const Pose* pose(Mood m);
  // At rest in mood m (one without a pose: at rest), at t, with the clip of
  // the look `base` (idle, working or asleep) playing.
  void reset(Mood m, SceneState base, uint32_t t);
  // A mood without a pose keeps the one it has.
  void setMood(Mood m);
  // The look's clip fades in over the one before.
  void setLook(SceneState base);
  void advanceTo(uint32_t t);
  // Plays the rig's blink clip, if it has one.
  void blink();
  // Plays a clip of the rig's over what plays (a look's occasion), and
  // fades it out.
  void play(const rig::Clip& clip) { mixer_.play(clip); }
  void stop(const rig::Clip& clip) { mixer_.stop(clip); }
  const rig::Mixer& mixer() const { return mixer_; }
  // A finger on the screen: a press squashes the face, a stroke leans it.
  void finger(bool down, int x, int y);
  // The face now, `dy` px lower (the press's dip), with the "o" in its
  // mouth's place while `talking`, of the pixels `d` draws, moved and shut
  // as a design has its face when the rig face draws it there (`move`);
  // and where the body is, in canvas px, into `anchors` when given.
  RigFrame frame(int dy, bool talking, Dither d = {}, FaceMove move = {}, rig::Anchors* anchors = nullptr) const;

 private:
  rig::Mixer mixer_;
  uint32_t at_ = 0;
  bool finger_ = false;
  int fingerX_ = 0;
};

void drawRig(Canvas& c, const RigFrame& f);
// The rig face in its design's place: the design (a faceless sceneFrame),
// of the pixels `d` draws, up to its face, the rig face, then the rest.
void drawRig(Canvas& c, const RigFrame& f, const SceneFrame& design, Dither d = {});

}  // namespace render::pixel
