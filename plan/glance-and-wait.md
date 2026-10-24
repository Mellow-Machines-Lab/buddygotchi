# Glance and wait: the plan (updated 2026-10-24)

What a long day with agents needs from Boop that it doesn't have yet:
a request that never gets lost and never gets stuck, the right window
when you open a thread, and something new to see each time you glance
down at a long turn or a quiet desk. Decided with the owner on
2026-10-24. Built on `feature/updated-behavior`, beside the character
engine ([character-engine.md](character-engine.md)), whose work comes
first.

Left out on purpose: a quieter Boop (calls, nights, a sound budget),
and telling a failed turn from a done one, which no hook says reliably.

## 1. "Needs you" lasts as long as the agent does

Today a request clears after 10 silent minutes, and an agent waiting on
you is always silent, so the requests you missed (lunch, a meeting, Boop
face-down) are the ones that vanish.

- **The agent's process.** Each hook says which process the agent is
  (its pid and start time). AgentHooks checks the silent ones every
  5 s: running means still waiting, however long; gone means the session
  ended (a closed terminal, a crash), which Boop's core records in the
  transcript, so the brain and a later launch hear of it from there.
  The 10-minute net stays only for hooks that don't say.
- **The escape hatch on the body.** Hold a finger on the screen for 1 s
  while the sign is up: Boop drops it. It hides the request on Boop
  only and never answers the agent; the session stays in BOOT's line,
  after the requests that show, and a new request from it shows again. The popover's row has
  the same Dismiss.

## 2. Opening the thread where you work

- **Remote Control sessions** (a CLI the Claude app drives) open in the
  Claude app at the session (`claude://code/session_…`), not in the
  terminal the CLI was started in.
- **Terminal sessions** open at their tab (iTerm2, Terminal, tmux),
  from AgentHooks' `terminal-tab-and-edit-sizes`.

## 3. Something new at every glance

The tiers are tags in `state.when` (characters/CHARACTER.md §9), so a
pack's designs pick them up like the time of day's.

| Look | From | Tag | What plays |
| --- | --- | --- | --- |
| Working | 0 s | | The start: rolls up its sleeves |
| Working | 30 s | | At it: a gag for what the agent is doing, a new one every 45–90 s |
| Working | 8 min | `marathon` | A headband and sweat, a snack, a coffee refill, a second wind |
| Working | 15 min | `camp` | A tent and a campfire beside the work, toasting a marshmallow. The last |
| Idle | 0 s | | Settles: sits back, pleased or sulky |
| Idle | 30 s | `fidget` | Looks around, reads, juggles, doodles on the glass, chases a fly |
| Idle | 3 min | `setpiece` | Hides with its eyes peeking out and a "brb" sign; waters its plant; builds something; practises a dance |
| Idle | 10 min | `doze` | Nods off |

The working tier counts from the start of the longest turn working now;
idle's from the end of the last turn. One tier is on at a time.

**What the agent is doing** picks the gag: reading glasses and a
magnifier for reads and searches, hammering for edits, crossed fingers
at tests, a cauldron for builds, a suitcase at compaction, on the phone
for an MCP tool, minis carrying boxes for helpers.

**The to-do list.** Claude's tasks (`TaskCreate`, `TaskUpdate`, the
older `TodoWrite`) and Codex's `update_plan` give done and total. The
line under the face shows `3/7`; later, a ladder Boop climbs. Only the
counts leave the agent: no item's words.

**Growth.** Every stage reached is a tag (`sprout`, `buddy`, `pal`,
`chonk`, `legend`), so a design for Pal shows from Pal on: a plant that
grows, a camp that goes from tent to cabin to treehouse, hobbies that
come with age.

## The order

1. **AgentHooks** (`needs-you-alive`, on `terminal-tab-and-edit-sizes`):
   the agent's process, Remote Control sessions, to-do counts.
2. **Boop:** hold to dismiss, the popover's Dismiss, a session whose
   agent is gone, opening Remote Control sessions.
3. **Boop:** the tier and stage tags, the to-do count under the face, and
   the designs that already exist moved onto the tiers (the stretch to
   `marathon`, nodding off to `doze`).
4. **The art** for every tier, the gags by activity, the ladder, the
   thought bubble and growth's props: after the engine's checkpoints 4
   and 5, authored once as clips for both faces.

## Open

- AgentHooks' two branches need the owner's push and merge, then a bump
  here.
- Hold to dismiss and the tiers' feel want a try on the AMOLED board.
</content>
</invoke>
