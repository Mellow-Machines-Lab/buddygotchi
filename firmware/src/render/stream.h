// The work stream (the Mac's WorkStream): each working agent's tool calls
// as words falling past the buddy from its lane, and now and then one that
// comes forward and hits it. The Mac decides which word comes forward and
// as which style; the device keeps the words falling and times the flight,
// and a face draws them. Fixed sizes, no heap.
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
  kCompact,  // its context compacted
  kBuried,   // its context ran out
  kFreeze,   // a rate limit or an overload
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
  kShrug,    // beside the head, then an empty bubble: a shrug
  kShatter,  // above the crown, bursting into bits it swallows
  kCompact,  // the words falling squashed into a cube that thuds onto the desk
  kBuried,   // words piling up as bricks, to its eyes
  kFreeze,   // the words falling stop where they are, icy, and it pokes one
  kDrop,     // the words falling drop, switched off
  kGather,   // its lane's words gathered into its mouth
};
CallMove callMove(CallStyle style);
// How long its word flies before it lands, when the body answers: a
// timeout's falls slowly, the rest quickly.
uint32_t callFlightMs(CallStyle style);

// A work act (the Mac's WorkStream.Act): a command Boop plays out, for as
// long as the Mac's `state` says it runs. The full act plays a scene with a
// low sign; a small one is only its prop and sign.
enum class ActKind : uint8_t { kNone, kTests, kPush, kBuild };
enum class ActResult : uint8_t { kRunning, kPass, kFail };
ActKind actKindFromName(const char* name);
// How long its opening plays, however soon the command ends: a result waits
// for it. Then how long the result shows. The Mac's `WorkStream.Act` holds
// the result in `state` for the same times.
constexpr uint32_t actLeadMs(ActKind kind, bool full) {
  return !full ? 900 : kind == ActKind::kPush ? 3400 : 1800;
}
constexpr uint32_t actResultMs(bool full) { return full ? 6000 : 2600; }

struct Stream {
  static constexpr int kLanes = 4;        // WorkStream.maxLanes
  static constexpr int kWordBytes = 16;   // WorkStream.maxWordBytes, its end and a little room
  static constexpr int kWords = 8;        // falling at once, at most: the frame rate's budget
  // A word falls for this long, and at most this many drop for one `state`
  // however many calls it counts: the state names only a lane's latest
  // word, so a second would be the same word again. A word drops only once
  // the newest of its
  // lane has fallen kWordGapPx (a line of the large font and a little), and
  // never falls faster, so a lane's words never overlap; one that would
  // wait over kMostWaitMs for that isn't dropped: the lane is busy enough.
  // Its middle keeps the whole word, in the large font, kWordEdgePx inside
  // the screen's sides, however far its lane's column and its jitter put it
  // out.
  static constexpr uint32_t kFallMs = 3200;
  static constexpr int kDropsPerState = 1;
  static constexpr int kWordEdgePx = 12;
  static constexpr int kWordGapPx = 36;
  static constexpr uint32_t kMostWaitMs = 800;
  // A word forward: its flight, then what it does once it lands, all
  // gone by kCallMs.
  static constexpr uint32_t kCallMs = 2500;
  // With no new call this long while they work, it's thinking.
  static constexpr uint32_t kThinkMs = 20000;
  // When the agents stop, the words on screen stay this long, and a word
  // forward may still come (a turn's end gathers them); then they go.
  static constexpr uint32_t kEndMs = 1500;
  // A word forward that takes the words falling (a gather, a compaction, a
  // drop) has them for this long, and then they're gone.
  static constexpr uint32_t kTakeMs = 700;

  // A working session's lane, as the Mac's `state` says it.
  struct Lane {
    uint8_t slot = 0;
    uint16_t count = 0;
    char word[kWordBytes] = "";
  };
  struct Word {
    char text[kWordBytes] = "";
    uint8_t slot = 0;
    int16_t x = 0;       // its middle, px on a 502-wide surface: its column's as it dropped, a little off
    uint16_t speed = 0;  // px a second
    uint32_t born = 0;
    bool live = false;
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
    bool full = false;
    ActResult result = ActResult::kRunning;
    char text[kActBytes] = "";
  };
  struct Act : ActIn {  // `text` is its sign's words running
    char resultText[kActBytes] = "";  // and at its result
    uint32_t at = 0, resultAt = 0;  // when it began, and when its result's scene begins
    bool hidden = false;            // something else holds the screen: it runs on, unseen
  };
  Act act;
  // The act from a `state`. `hold`: something else holds the screen, so an
  // act that's gone from the state only waits to come back, where it would
  // have got to. A result that came before the opening is over waits for it.
  void setAct(const ActIn& in, bool hold, uint32_t t);
  // What of it shows at t: no kind when nothing does. Its result's words and
  // result only from when its scene begins.
  struct ActNow {
    ActKind kind = ActKind::kNone;
    bool full = false;
    ActResult result = ActResult::kRunning;
    const char* text = "";
    int ageMs = 0;     // since it began
    int resultMs = 0;  // since its result's scene began
    int leftMs = -1;   // how long until its result has gone, -1 with no end yet
    bool shows() const { return kind != ActKind::kNone; }
  };
  ActNow actNow(uint32_t t) const;

  Lane lanes[kLanes];
  int laneCount = 0;
  // Whether the stream shows: the agents work and nothing needs you.
  bool on = false;
  Word words[kWords];
  Call call;
  // When the agents started working (the stream came on), for the
  // monitor's clock, and when a lane last counted a new call. A needs-you
  // only pauses them (`paused`): the clock runs on from `since` after it.
  uint32_t since = 0, movedAt = 0;
  bool paused = false;
  // The stream went off at endedAt, the agents done, its words lingering.
  bool ending = false;
  uint32_t endedAt = 0;

  // The lanes from a `state`: a lane whose count moved drops words, up to
  // kDropsPerState; a new lane drops its latest. A word keeps falling where
  // it dropped, its lane gone or not. The stream off lets its words linger
  // kEndMs, unless something needs you (`cleared`): then all goes at once,
  // and the stream on again after it keeps its `since`.
  void setLanes(const Lane* in, int n, bool showing, bool cleared, uint32_t t);
  // Whether a word may come forward at t: the stream on, or just ended.
  bool accepts(uint32_t t) const;
  // Whether anything of it is drawn at t.
  bool drawn(uint32_t t) const;
  // Whether the word forward is freezing the words, and whether it takes
  // `w` (a gather its lane's, a compaction or a drop all of them falling
  // as it came).
  bool frozen() const { return call.live && call.style == CallStyle::kFreeze; }
  bool taken(const Word& w) const;
  // A word comes forward at t (the `call` do).
  void startCall(const char* text, uint8_t slot, CallStyle style, uint32_t t);
  // Forgets what has finished by t.
  void prune(uint32_t t);
  void clear();
  // A slot's column, from 0, among the lanes showing; -1 for none.
  int column(uint8_t slot) const;
  // Whether anything moves at t, so the face draws again.
  bool moving(uint32_t t) const;

 private:
  void drop(const Lane& lane, int column, int columns, uint32_t t);
};

// Where lane `column` of `columns` sits across a 502-wide screen, the
// middle its words fall from: off the middle, where the head and its hat
// are. One lane
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
