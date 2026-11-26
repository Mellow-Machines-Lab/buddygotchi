// Who has what: each of Boop's parts has one owner a frame, the first in
// its list that's true now (documentation/design/screen-guide.md, "Who has
// what"). The face gathers what's true (GelFace::truths) and acts on the
// owners; nothing else picks them. A lower owner still true runs on under
// the upper one, in phase, and every change of owner is a fade or a spring.
// The hands' owners are the frame's (render/gel/hands.h, HandsPlan).
#pragma once
#include <cstdint>

namespace render::gel {

// What's true now, as the face sees it.
struct WhatsTrue {
  // What has the body over its own look.
  bool moment = false;     // a Moment, an invite or a word forward
  bool finger = false;     // your finger on it
  bool needsYou = false;   // its needs-you look
  bool listening = false;  // push-to-talk
  bool pastime = false;    // a pastime, a transition, the engine's own bit
  // Its own look shows, idle or at work, with the Mac here: going with you
  // rides only on that.
  bool place = false;
  bool desk = false;       // at work, or a card held: the jam is the desk's
  bool light = false;      // at work in a pose of its own, or a card held (GelFace::light)
  bool posed = false;      // at work in a pose whose clip has the eyes
  bool signUp = false;     // a sign held up has its hands
  bool keepsFace = false;  // its mood keeps its own face (slime::kKeepsFaceThroughGestures)
  // You at the Mac: the tags, and `ptr`.
  bool call = false, speaking = false, music = false, typing = false, scrolling = false, pointer = false;
};

// Each part's owners, lowest first where there's an order.
enum class BodyBy : uint8_t { kLook, kPastime, kListening, kNeedsYou, kFinger, kMoment };
enum class BeatBy : uint8_t { kBreath, kTyping, kMusic, kSpeaking, kCall };
enum class EyesBy : uint8_t { kOwn, kJam, kPointer, kScroll, kCall, kPose, kBody, kFinger };
enum class FaceBy : uint8_t { kMood, kJam, kMoment };
enum class MarkBy : uint8_t { kNone, kTicks, kNotes, kEar, kMuted };

struct Owners {
  BodyBy body = BodyBy::kLook;
  BeatBy beat = BeatBy::kBreath;  // whose rhythm it is, shown or covered
  bool with = false;              // going with you rides on its look now
  bool beatShows = false;         // the beat rides on the body now
  bool small = false;             // at the desk's size: the jam's smaller there
  EyesBy eyes = EyesBy::kOwn;
  FaceBy face = FaceBy::kMood;
  MarkBy mark = MarkBy::kNone;
  bool keys = false;  // its hands type with you (typing along), where nothing
                      // else has them
};

inline Owners whoHasWhat(const WhatsTrue& f) {
  Owners o;
  o.body = f.moment      ? BodyBy::kMoment
           : f.finger    ? BodyBy::kFinger
           : f.needsYou  ? BodyBy::kNeedsYou
           : f.listening ? BodyBy::kListening
           : f.pastime   ? BodyBy::kPastime
                         : BodyBy::kLook;
  o.beat = f.call       ? BeatBy::kCall
           : f.speaking ? BeatBy::kSpeaking
           : f.music    ? BeatBy::kMusic
           : f.typing   ? BeatBy::kTyping
                        : BeatBy::kBreath;
  // Going with you rides on its own look alone; the facts stay true under
  // whatever has the body, so each is there again, in phase, as it leaves.
  const bool with = f.place && o.body == BodyBy::kLook;
  o.with = with, o.beatShows = with && o.beat != BeatBy::kBreath, o.small = f.desk;
  const bool jam = o.beatShows && o.beat == BeatBy::kMusic && !f.desk;  // the whole jam, eyes shut
  // At the light size the eyes stay the pose's.
  o.eyes = f.finger                                                 ? EyesBy::kFinger
           : o.body != BodyBy::kLook && o.body != BodyBy::kNeedsYou ? EyesBy::kBody
           : !with                                                  ? EyesBy::kOwn
           : f.light                                                ? (f.posed ? EyesBy::kPose : EyesBy::kOwn)
           : f.call                                                 ? EyesBy::kCall
           : f.scrolling                                            ? EyesBy::kScroll
           : f.pointer                                              ? EyesBy::kPointer
           : jam                                                    ? EyesBy::kJam
                                                                    : EyesBy::kOwn;
  // The jam's content face goes with its shut eyes: open on you, the mood's.
  o.face = f.moment ? FaceBy::kMoment : o.eyes == EyesBy::kJam && !f.keepsFace ? FaceBy::kJam : FaceBy::kMood;
  o.keys = with && f.typing && !f.signUp;
  // One mark beside it, through a pastime too.
  const bool beside = f.place && (o.body == BodyBy::kLook || o.body == BodyBy::kPastime);
  o.mark = !beside      ? MarkBy::kNone
           : f.call     ? MarkBy::kMuted
           : f.speaking ? MarkBy::kEar
           : f.music    ? MarkBy::kNotes
           : o.keys     ? MarkBy::kTicks
                        : MarkBy::kNone;
  return o;
}

}  // namespace render::gel
