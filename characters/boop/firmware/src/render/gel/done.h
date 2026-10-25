// The finished turn the brain's reaction is about (render::DoneShow), as
// the gel marks it: the panel's rim glowing in its outcome's colour, and a
// ticket on a string, dropped in from the top, naming its thread. Both come
// as the reaction starts and go once it has lingered (app/behaviour.h): the
// glow fading out over its last second, the ticket pulled back up. The
// ticket hangs in the middle, where a result card would be (the face shows
// none while it does, Scenes::cardless), or left of a success's trophy.
// Integer, and a function of the DoneShow alone, so the board, the
// simulator and the Mac's mirror draw the same frame.
#pragma once
#include "render/face.h"
#include "render/surface.h"

namespace render::gel {

// How long the ticket takes to drop in, and to go back up; how long the
// glow takes to come, and to fade as the finished turn goes.
constexpr int kTicketDropMs = 700, kTicketRiseMs = 400, kGlowInMs = 300, kGlowOutMs = 1000;
// How far in from the panel's edge the glow reaches, in px, and how strong
// it is at the edge (0–255): a reply's, or a face's with no finish of its
// own, fainter.
constexpr int kGlowPx = 26, kGlowPeak = 200, kGlowPeakFaint = 110;

// The glow's strength at the panel's edge, 0–255: 0 for none.
int doneGlow(const DoneShow& done);
// The ticket and its string, above the lane.
void paintTicket(Surface& surface, const DoneShow& done);
// The glow, on rows [from, to), over whatever's drawn there.
void paintGlow(Surface& surface, const DoneShow& done, int from, int to);

}  // namespace render::gel
