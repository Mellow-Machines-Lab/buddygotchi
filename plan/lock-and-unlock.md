# Lock and unlock

Updated 2026-11-02. Built. Boop answers every lock and unlock of the Mac: a
slight silent wave by default, more when it has been a while, a goodnight
at night, a snub when it's cross. Decided with the owner on 2026-11-01.
Build on `wish`. Nothing here needs a permission: `PresenceSignals`
already hears these.

## Today

A lock counts only once it's an away, after `lockAwayMs` (10 minutes),
and only a back wakes the brain. So Boop doesn't notice you leaving.

## The design

It goes through Jev, not a rule, so the mood can steer it. Every lock and
unlock is an event in the transcript and wakes a pass. The away and back
stay exactly as they are.

The line gives facts only: "You locked the Mac, first time in 3 h.", "You
unlocked the Mac after 2 min." The narration: "You locked the Mac.", "You
unlocked the Mac.", shown under the bubble, alone when nothing is said.

The steering sets the defaults; Jev may depart from them:

| Moment | Default | Voice |
| --- | --- | --- |
| A lock or unlock soon after the last | A slight wave (small) | None; only the narration under it |
| First lock in a while, about an hour or more | A real wave, a `[bye]` sign | Yes |
| A lock at night (the existing night part of the day) | `[bye night]` "nite nite", then the nap: Boop sleeps at once, and the dream follows by itself | Yes; tweak later if it's too much |
| An unlock after an away | The welcome back that exists; the unlock line stays silent, so one reaction | As today |
| The first unlock of the day | That same welcome back and the dream's telling | As today |
| Boop is cross with you | A turned-away face or a huff, no wave | Jev's |

- Always reacts, auto-lock included; there is no repeat limit.
- Needs you: the needs-you screen stays; the reaction waits or drops as any does.
- Hushed or Quiet: the wave with no voice, by the rules that exist.
- No key, or Jev too slow: nothing, later or not at all, as for every reaction.
- Closing the lid may miss its reaction. Accepted; don't engineer for it.

## The build

| Piece | Change |
| --- | --- |
| `PresenceDetector` | Emits lock and unlock events too; `lockAwayMs` and away and back unchanged. Plain state, tests drive it |
| Pipeline and the transcript view | Lock and unlock wake a pass; their lines, with how long since the last; an unlock ending an away makes no line of its own |
| Moment output | The wave offered at these lines, `none` for a snub, the nap at night; `[bye]` signs at a lock and `[hello]` at an unlock |
| Narration | The two rows |
| Pack | PERSONALITY's Examples and the moods' words; a `[bye working]` sign, "i got this", for a lock while agents work |
| Firmware | Check whether the wave honours `small` as a slighter motion; if not, make it |
| Evals (`--only`) | A plain lock: a silent small wave. First in a while: voice. Grumpy: no wave. A night lock: sleep. A long unlock: one reaction. Agents working at a lock: Boop keeps watching |
| Tests that pin | The away's 10 minutes unchanged; one reaction at a long unlock |
| Docs | CLAUDE.md Words if a word is added, `documentation/architecture.html`, `internal/EVALS.md` |

## No plug on a sleeping Boop

So it can't hold up the wave. When the board hears nothing for
`kHostGoneMs` (30 s) it shows the plug and the no-app look. On a Mac
gone to sleep that puts a plug on a sleeping Boop right after "nite nite".

If Boop is already asleep when the Mac goes quiet, it stays asleep with no
plug, and the plug shows only once you touch the board. Awake, the plug
shows as today. Firmware only, no new message, with a test that pins it.
