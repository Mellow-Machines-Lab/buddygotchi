// The work stream (the Mac's WorkStream): each working agent's lane with
// what its latest call is doing, the newest of them, which a face shows as the
// work's term, and now and then a word that comes forward and hits the
// buddy. The Mac decides which word comes forward and as which style; the
// device times the flight, and a face draws it. Fixed sizes, no heap.
#pragma once
#include <cstdint>

namespace render {

// What a word that comes forward does, by the `call` do's `as`.
enum class CallStyle : uint8_t {
  kLand,  // drops on its head and sinks in (and any `as` the board doesn't know)
  kHelper,
  kBack,
  kShatter,
  kBonk,
  kBonk2,
  kBonk3,
  kThrow,
  kShrug,
  kTimeout,
  kNo,
  // The whole turn's moments.
  kDrop,     // you stopped it, or it failed
  kGather,   // its turn is done
  kCount
};
CallStyle callStyleFromName(const char* name);
const char* callStyleName(CallStyle style);

// How a style moves: where its word flies, what it does there and what the
// body does when it lands.
enum class CallMove : uint8_t {
  kSink,     // onto the crown, sinking in: a squash and a ripple
  kHit,      // between the eyes: knocked back, dizzy, stars
  kShrug,    // beside the head: a shrug
  kShatter,  // above the crown, bursting into bits it swallows
  kDrop,     // its word drops, switched off
  kGather,   // its word gulped down
};
CallMove callMove(CallStyle style);
// How long its word flies before it lands, when the body answers: a
// timeout's falls slowly, the rest quickly.
uint32_t callFlightMs(CallStyle style);

// A work act (the Mac's WorkStream.Act): a command worth naming (the
// tests, a push, the build), for as long as the Mac's `state` says it
// runs. A face shows what's running, then how it ended.
enum class ActKind : uint8_t { kNone, kTests, kPush, kBuild };
enum class ActResult : uint8_t { kRunning, kPass, kFail };
ActKind actKindFromName(const char* name);
// How long it shows as running, however soon the command ends: a result
// waits for it. Then how long the result shows. The Mac's `WorkStream`
// holds the result in `state` for the same times (`leadMs`, `resultMs`).
constexpr uint32_t kActLeadMs = 900, kActResultMs = 2600;

struct Stream {
  static constexpr int kLanes = 4;        // WorkStream.maxLanes
  static constexpr int kWordBytes = 16;   // WorkStream.maxWordBytes, its end and a little room
  static constexpr int kDoingBytes = 26;  // WorkStream.maxDoingBytes, its end and a little room
  // A word forward: its flight, then what it does once it lands, all
  // gone by kCallMs.
  static constexpr uint32_t kCallMs = 2500;
  // When the agents stop, a word forward may still come this long after
  // (a turn's end); then the stream is gone.
  static constexpr uint32_t kEndMs = 1500;

  // A working session's lane, as the Mac's `state` says it.
  struct Lane {
    uint8_t slot = 0;
    uint16_t count = 0;
    char word[kDoingBytes] = "";  // what its agent is doing: "searching TODO"
  };
  struct Call {
    char text[kWordBytes] = "";
    uint8_t slot = 0;
    CallStyle style = CallStyle::kLand;
    uint32_t at = 0;
    bool live = false;
  };

  static constexpr int kActBytes = 24;  // a sign's longest words and their end
  // The act running, as the Mac's `state` says it (`wact`), or its result.
  struct ActIn {
    ActKind kind = ActKind::kNone;
    ActResult result = ActResult::kRunning;
    char text[kActBytes] = "";
  };
  struct Act : ActIn {  // `text` is its sign's words running
    char resultText[kActBytes] = "";  // and at its result
    uint32_t at = 0, resultAt = 0;  // when it began, and when its result shows
    bool hidden = false;            // something else holds the screen: it runs on, unseen
  };
  Act act;
  // The act from a `state`. `hold`: something else holds the screen, so an
  // act that's gone from the state only waits to come back, where it would
  // have got to. A result that came before kActLeadMs is over waits for it.
  void setAct(const ActIn& in, bool hold, uint32_t t);
  // What of it shows at t: no kind when nothing does. Its result's words and
  // result only from when the result shows.
  struct ActNow {
    ActKind kind = ActKind::kNone;
    ActResult result = ActResult::kRunning;
    const char* text = "";
    int ageMs = 0;     // since it began
    int resultMs = 0;  // since its result showed
    int leftMs = -1;   // how long until its result has gone, -1 with no end yet
    bool shows() const { return kind != ActKind::kNone; }
  };
  ActNow actNow(uint32_t t) const;

  Lane lanes[kLanes];
  int laneCount = 0;
  // Whether the stream shows: the agents work and nothing needs you.
  bool on = false;
  // The newest call's word of any lane: the word, as it is now, of the lane
  // whose count moved last or that came last; when that lane goes, the last
  // lane left's. A face shows it as the work's term.
  char newest[kDoingBytes] = "";
  int newestSlot = -1;
  Call call;
  // The stream went off at endedAt, the agents done, a word forward may still come.
  bool ending = false;
  uint32_t endedAt = 0;

  // The lanes from a `state`: a lane whose count moved, or a new one, makes
  // its word the newest, and keeps it up to date while no other moves. The stream off lets a word forward still come for
  // kEndMs, unless something needs you (`cleared`): then all goes at once.
  void setLanes(const Lane* in, int n, bool showing, bool cleared, uint32_t t);
  // Whether a word may come forward at t: the stream on, or just ended.
  bool accepts(uint32_t t) const;
  // Whether anything of it is drawn at t.
  bool drawn(uint32_t t) const;
  // A word comes forward at t (the `call` do).
  void startCall(const char* text, uint8_t slot, CallStyle style, uint32_t t);
  // Forgets what has finished by t.
  void prune(uint32_t t);
  void clear();
  // A slot's column, from 0, among the lanes showing; -1 for none.
  int column(uint8_t slot) const;
  // Whether anything moves at t, so the face draws again.
  bool moving(uint32_t t) const;
};

// Where lane `column` of `columns` sits across a 502-wide screen, the
// middle its word forward comes from: off the middle, where the head and
// its hat are. One lane
// on the left; two either side; three or four along both sides.
inline int laneX(int column, int columns) {
  static constexpr int kXs[Stream::kLanes][Stream::kLanes] = {
      {84, 0, 0, 0}, {84, 418, 0, 0}, {62, 158, 420, 0}, {56, 150, 352, 446}};
  if (columns < 1) columns = 1;
  if (columns > Stream::kLanes) columns = Stream::kLanes;
  if (column < 0 || column >= columns) return 251;
  return kXs[columns - 1][column];
}

// The lanes' colours by slot, RGB565, the same on the board, its mirror
// and the lane: teal, rose, lilac, lime. Never amber, which is needs you's.
constexpr uint16_t kLaneInk[Stream::kLanes] = {0x3E99, 0xFC5B, 0xB47F, 0x9F2C};
// A failure's word, a passing check's, and the stars.
constexpr uint16_t kFailInk = 0xFAEB, kPassInk = 0x5F0F, kStarInk = 0xFF0C;

}  // namespace render
