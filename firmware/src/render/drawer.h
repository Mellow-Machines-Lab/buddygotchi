// The agents' drawer: swiped up from the status strip, a sheet listing
// the agents the Mac knows, each a row you tap to open its thread on the
// Mac. The Mac sends the rows (`list`) only while the board says the
// drawer is open; the device keeps the finger, the spring and the clock,
// and a face that has one draws it (Face::hasDrawer). Fixed sizes, no heap.
#pragma once
#include <cstdint>

namespace render {

struct Drawer {
  // The most rows the Mac sends, and the drawer shows: one more session
  // than it has room for goes as `unlisted`, said in the last row's place.
  static constexpr int kRows = 5;
  enum class Status : uint8_t { kNeedsYou, kWorking, kIdle };
  struct Row {
    uint32_t id = 0;  // the Mac's number for the session: what a tap on the row sends back
    Status status = Status::kIdle;
    int8_t slot = -1;  // its work stream lane (Stream::kLanes), whose colour it wears; -1 for none
    char agent[12] = "";
    char title[32] = "";    // the thread's name, else its project
    char project[24] = "";  // "" when the title is the project
  };
  Row rows[kRows];
  int count = 0;
  int unlisted = 0;     // sessions the rows leave out
  bool listed = false;  // the Mac has sent a list since the drawer opened
  // How far open, 0 (shut: the strip is the strip) to 1000, a little past
  // either end as it springs; and the paw that hangs over its edge once
  // it's open, 0 to 1000.
  int open = 0;
  int paw = 0;
  int picked = -1;  // the row a tap picked, lit as the drawer shuts; -1 for none
  bool shows() const { return open > 0; }
};

}  // namespace render
