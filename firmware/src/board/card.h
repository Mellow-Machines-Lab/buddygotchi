// The microSD card: mounted on the
// second hardware SPI bus at boot, with the voice file Boop says its takes
// from. With no card, or no voice file on it, Boop has no voice.
#pragma once

namespace board {

// Mounts the card and opens /boop/voice.bin for voice::openFile. False
// when there's no card or no voice file; BoardHal's cardState says which
// (dbg.ping's `card`). A new voice file copied on over USB
// (dbg.card) goes to /boop/voice.tmp, begun afresh or kept, appended to,
// then checked and renamed over the old one, which reopens (BoardHal's
// copyBegin, copyAppend and copyEnd).
bool cardBegin();

}  // namespace board
