// The work stream (the Mac's WorkStream): each working agent's tool calls
// as words falling past the buddy from its lane, and now and then one that
// comes forward and hits it. The Mac decides which word comes forward and
// as which gag; the device keeps the words falling and times the flight,
// and a face draws them. Fixed sizes, no heap.
#pragma once
#include <cstdint>

namespace render {

// What a word that comes forward does, by the `call` do's `as`.
enum class CallGag : uint8_t {
  kLand,  // drops on its head and sinks in (and any `as` the board doesn't know)
  kArrive,
  kLook,
  kStir,
  kStamp,
  kLaunch,
  kPoof,
  kPlane,
  kPhone,
  kPage,
  kHelper,
  kBack,
  kShatter,
  kCross,
  kStack,
  kPass,
  kBuilt,
  kHail,
  kBonk,
  kBonk2,
  kHelmet,
  kThrow,
  kShrug,
  kTimeout,
  kNo,
  kCombo,
  kCount
};
CallGag callGagFromName(const char* name);
const char* callGagName(CallGag gag);

// How a gag moves: where its word flies and what the body does when it
// lands.
enum class CallMove : uint8_t {
  kSink,     // onto the crown, sinking in: a squash and a ripple
  kHit,      // between the eyes: a knock back, lids shut a while, stars
  kShrug,    // beside the head, then an empty bubble: a shrug
  kShatter,  // above the crown, bursting into bits it swallows
  kHail,     // a run of them raining on the crown
  kCheer,    // up over the head, with confetti: a hop
  kDesk,     // to the desk's monitor
};
CallMove callMove(CallGag gag);
// How long its word flies before it lands, when the body answers: a
// timeout's falls slowly, the rest quickly.
uint32_t callFlightMs(CallGag gag);

struct Stream {
  static constexpr int kLanes = 4;    // WorkStream.maxLanes
  static constexpr int kWordBytes = 16;  // WorkStream.maxWordBytes, its end and room for a combo's count
  static constexpr int kLabelBytes = 13;  // WorkStream.maxLabelBytes and its end
  static constexpr int kWords = 12;   // falling at once, at most
  // A word falls for this long, and at most this many drop for one `state`
  // however many calls it counts, this far apart.
  static constexpr uint32_t kFallMs = 3200;
  static constexpr int kDropsPerState = 2;
  static constexpr uint32_t kDropGapMs = 140;
  // A word forward: its flight, then what it does once it lands, all
  // gone by kCallMs.
  static constexpr uint32_t kCallMs = 2500;

  // A working session's lane, as the Mac's `state` says it.
  struct Lane {
    uint8_t slot = 0;
    uint16_t count = 0;
    char word[kWordBytes] = "";
    char label[kLabelBytes] = "";
  };
  struct Word {
    char text[kWordBytes] = "";
    uint8_t slot = 0;
    int16_t dx = 0;  // from its column's middle, px on a 502-wide surface
    uint16_t speed = 0;  // px a second
    uint32_t born = 0;
    bool live = false;
  };
  struct Call {
    char text[kWordBytes] = "";
    uint8_t slot = 0;
    CallGag gag = CallGag::kLand;
    uint16_t count = 0;  // a combo's
    uint32_t at = 0;
    bool live = false;
  };

  Lane lanes[kLanes];
  int laneCount = 0;
  // Whether the stream shows: the agents work and nothing needs you.
  bool on = false;
  Word words[kWords];
  Call call;

  // The lanes from a `state`: a lane whose count moved drops words, up to
  // kDropsPerState; a new lane drops its latest; a lane gone takes its
  // words with it.
  void setLanes(const Lane* in, int n, bool showing, uint32_t t);
  // A word comes forward at t (the `call` do).
  void startCall(const char* text, uint8_t slot, CallGag gag, uint16_t count, uint32_t t);
  // Forgets what has finished by t.
  void prune(uint32_t t);
  void clear();
  // A slot's column, from 0, among the lanes showing; -1 for none.
  int column(uint8_t slot) const;
  // Whether anything moves at t, so the face draws again.
  bool moving(uint32_t t) const;

 private:
  void drop(const Lane& lane, uint32_t t);
};

// The lanes' colours by slot, RGB565, the same on the board, its mirror
// and the lane: teal, amber, lilac, lime.
constexpr uint16_t kLaneInk[Stream::kLanes] = {0x3E99, 0xFD88, 0xB47F, 0x9F2C};
// A failure's word, a passing check's, and the stars.
constexpr uint16_t kFailInk = 0xFAEB, kPassInk = 0x5F0F, kStarInk = 0xFF0C;

}  // namespace render
