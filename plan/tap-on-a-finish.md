# A tap anywhere on a finish opens its thread

Updated 2026-11-01. Asked for by the owner on 2026-11-01: while a finish
names whose turn it was, tapping anywhere should open that thread, not
only the sign.

## What the code does

Where you touch is already ignored: any `kTap` on the screen opens the
thread (`Device::tapped`, `finishShown`), and only an ask's answers look
at the spot. The gap is what counts as a tap. A touch the classifier calls
a swipe, stroke, tickle or ruffle goes to `gestured`, where
`Behaviour::gesture` drops it during a finish: nothing happens and nothing
opens. Only `kNose` is treated as a tap (`noseOnFinish`). A quick,
imperfect tap on the face can read as one of these. That's the likely
cause, not yet shown on a finger: the log says `gesture swipe` often.

## The change

While `finishShown`:
- Any brief touch is a tap, whatever the classifier called it: under
  about 400 ms, whichever path it took. It opens the thread.
- A longer stroke stays a stroke, so petting doesn't open a window, and it
  still counts for a wish.
- A pull on the drawer stays the drawer's. An ask's answers stay theirs.
- The same on the simulator; the Mac's `on` handling doesn't change.

A test pins it: during a finish, a brief swipe and a brief tickle open
the thread, a slow stroke doesn't, and away from a finish all stay
gestures. Add the classifier's name to the `device: tap` log line, so a
real miss can be read from `boop.log`.

Look for the owner's board check: tap the face, the rim and the strip
during a finish; each opens the thread.
