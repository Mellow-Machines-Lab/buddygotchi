# Glance and wait: the plan (updated 2026-10-25)

What a long day with agents needs from Boop that it doesn't have yet:
a request that never gets lost and never gets stuck, the right window
when you open a thread, and something new to see each time you glance
down at a long turn or a quiet desk. Decided with the owner on
2026-10-24. Built on `feature/updated-behavior` (in main since
922b1da), beside the character engine
([character-engine.md](character-engine.md)), whose work comes first.

Left out on purpose: a quieter Boop (calls, nights, a sound budget),
and telling a failed turn from a done one, which no hook says reliably.

## 1. "Needs you" lasts as long as the agent does

Today a request clears after 10 silent minutes, and an agent waiting on
you is always silent, so the requests you missed (lunch, a meeting, Boop
face-down) are the ones that vanish.

- **The agent's process.** Each hook says which process the agent is
  (its pid and start time). AgentHooks checks the silent sessions that
  wait or work every 5 s: running means still waiting, however long up
  to a silent day; gone (a closed terminal, a crash) means the request
  clears and the turn stops, which Boop's core records in the transcript
  as the turn stopping, so a later launch hears of it from there. The
  session stays, idle: one process can outlive many sessions (the Codex
  app's server, `/new` in a running CLI), so an idle session's process
  isn't checked. Any session is forgotten after a silent day, a waiting
  one too, since a launch reads back only the last day. A turn silent an
  hour stops working, whatever its process: its `Stop` was lost, or an
  interrupt sent no hook. The 10-minute net stays only for hooks that
  don't say.
- **The escape hatch on the body.** Hold a finger on the needs-you
  screen for 1 s: Boop drops it. It hides the request on Boop
  only and never answers the agent; the session rests from then, as an
  idle one does, and stays in BOOT's line, after the requests that show,
  and a new request from it shows again. The board names the request
  its needs-you screen showed, so one that takes the screen during the
  hold isn't dismissed unseen, and a relaunch keeps it dismissed while
  it waits.
  The popover's card has the same Dismiss, which names its request too.

## 2. Opening the thread where you work

- **Remote Control sessions** (a CLI the Claude app drives) open in the
  Claude app at the session (`claude://code/session_…`), not in the
  terminal the CLI was started in.
- **Terminal sessions** open at their tab (iTerm2, Terminal, tmux),
  from AgentHooks' `TerminalTab`.
- **A tap on the brain's finish** opens the thread it names as it plays
  and for a moment after it plays out (`Behaviour::kFinishLingerMs`),
  the strip still naming it, unless another animation or a needs-you
  takes the face first. A finish with no cheer has no tap; BOOT still
  hands you the one that finished last.

## 3. Something new at every glance

The tiers are tags in `state.when` (characters/CHARACTER.md §9), so a
pack's designs pick them up like the time of day's. Redone with the
owner on 2026-10-25: five, closer together, the same for work and idle,
and on the gel every one has pastimes, a little scene each over the
body, and kit that stays while the tier lasts (the slime's
CONTINUITY.md, Pastimes, has the whole table).

| Tag | From | At work | Idle |
| --- | --- | --- | --- |
| | 0 s | Rolls up its sleeves | Settles: sits back, pleased or sulky |
| `tier1` | 30 s | A mug; sips, peeks at you, hums | Looks round, looks up at you, hops |
| `tier2` | 1 min | An idea, the tongue out, nodding along | A bubble, a fly, a heart on the glass |
| `tier3` | 2 min | Headphones; bopping, drumming, a sticky note | A plant; a book, a game, watering it |
| `tier4` | 5 min | A sweatband; the stretch, a refill, a cookie, a second wind | A "brb" sign, a tower of blocks, a dance, a paper plane |
| `tier5` | 10 min, the last | The camp, mugs stacking up; a marshmallow, a pizza, the stars, a blanket | Snoozing, counting sheep, a nap under a blanket, nodding off |

The working tiers count from the start of the agents' working stretch:
a rest of under 30 seconds (a quick reply) carries it on. Idle's count
from the latest a session came to rest (its turn ended, or you dismissed
its request). The Mac sends the last tier reached, and the board takes
every one below it as on, so a design for `tier2` shows from then on and
the steady state at `tier5` mixes in the older ones. While something
needs you the gel waves (30 s), taps on the glass (2 minutes), checks
its watch (5) and nods off (10); asleep it rolls over, dreams of sheep
and blows a snore bubble.

**What the agent is doing** picks the gag: reading glasses and a
magnifier for reads and searches, hammering for edits, crossed fingers
at tests, a cauldron for builds, a suitcase at compaction, on the phone
for an MCP tool, minis carrying boxes for helpers.

**The to-do list.** The longest turn's, or the next working one's that
has a list. Claude's tasks (`TaskCreate`, `TaskUpdate`, the
older `TodoWrite`) and Codex's `update_plan` give done and total. The
line under the face shows `3/7`; later, a ladder Boop climbs. A list
all done is dropped at the next prompt, so it doesn't show on later
turns. Only the counts leave the agent: no item's words.

**Growth.** Every stage reached is a tag (`sprout`, `buddy`, `pal`,
`chonk`, `legend`), so a design for Pal shows from Pal on: a plant that
grows, a camp that goes from tent to cabin to treehouse, hobbies that
come with age.

## The order

1. **AgentHooks** (in its main since 03fad1a): the agent's process,
   Remote Control sessions, to-do counts.
2. **Boop:** hold to dismiss, the popover's Dismiss, a session whose
   agent is gone, opening Remote Control sessions.
3. **Boop:** the tier and stage tags, the to-do count under the face, and
   the designs that already exist moved onto the tiers (the stretch to
   `tier4`, nodding off to `tier5`).
4. **The art** for every tier (built 2026-10-25, the gel only): its
   pastimes, the rig's clips with the gel's drawing in time with them, and
   the kit. Still to come: the ladder, and growth's props.

## Open

- AgentHooks' `lifecycle-fixes` (a turn silent an hour stops working, a
  day forgets any session, wrappers aren't the agent, the apps listed)
  needs the owner's push and merge, then a bump here.
- Hold to dismiss and the tiers' feel want a try on the AMOLED board.
</content>
</invoke>
