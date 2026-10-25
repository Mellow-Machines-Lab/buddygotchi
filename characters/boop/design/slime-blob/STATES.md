# State coverage and event mapping

Updated 2026-10-25. The board's 25 states (the firmware's `kStateNames`,
`firmware/src/render/types.cpp`) fall into nine visual scene families, below.
Each state's takes (three each; idle's six or seven and asleep's four,
with their comedy, a successful finish's four and a gesture's ten) are
slimegen's `scenes.mjs` recipes, baked into `slime.h`; the gel engine's
router (`render/gel/router.cpp`) picks the state from the facts and
moments it's given. The owner approved the representative set before the
remaining matrix was implemented and exercised.

## Compact scenes, complete semantic coverage

| Shared scene | States | Distinction to preserve |
| --- | --- | --- |
| Quiet rest | no_app, asleep | Lost app vs no sessions; both quiet, retained mood suppressed visually; only asleep snores now and then |
| Idle | idle | Available but not working; face/microgesture carries mood, then now and then a yawn, a doze or a sneeze (excited has zoomies, the low moods a long yawn) |
| Listen | listening | Actual mic-on, not every input event |
| Start | starting, wake_up, notice | ctx new_task/session/continuation/compacted selects truthful card; wake_up (you back after a long break) stretches with no card; notice (you named it) looks up at you, a gag under a borrowed face, with no card |
| Desk | planning, working, terminal, tool_use, searching, analyzing, testing, waiting | One computer, different activity rhythms/cues |
| Helpers | delegating, helper_return | Dispatch/live helpers vs an observed returning helper |
| Alert | needs_you | Permission/input pending, stable recognizable ding and card |
| Result | reply_ready, task_complete, error, stopped | Reply vs whole-task success/failure vs tool error vs interruption |
| Touch | poked, tap_spam, gesture | Ordinary local response vs repeated-tap response vs the board's own gesture (a stroke, a shake, BOOT's hand-off: a gag each, under a borrowed face) |

`test_gel` plays every one of the 1,050 mood/state cells, each of its
takes, the two completion outcomes and four start contexts apart. Shared
rest rows alias one quiet family; they still keep the mood. Active cells
are compositions, not isolated exported assets.

`starting` expands each variant for all three ctx values. `task_complete`
expands each for both success and failure. Do not count these as new
moods/states or choose an outcome at random. A sad success is a small
tearful-but-valid achievement; a happy failure is still visibly failure,
never a misleading trophy. A success comes in four sizes, by how long it's
held and how long its turn ran, from Little Win to the whole screen
([CONTINUITY.md](CONTINUITY.md), Finishes): its variations go on past its
takes, one for each finish above small.

Comedy adds takes, never states or moods ([CONTINUITY.md](CONTINUITY.md),
Comedy). Idle's variations 4 to 6 are its gags (yawn and settle, doze off
and snap awake, sneeze and shake it off), after an expression's own gag:
excited's zoomies, the low moods' long yawn. Asleep's fourth is a snore
(only it sounds). A small successful finish's fourth is Little Win's
trophy, then hiccups; failure keeps its three. Proud's lifted success
shows a gift, a small bug beside its trophy. Each joins its bag's second
round, so a fresh state opens as it always has.

Occasions add takes too ([CONTINUITY.md](CONTINUITY.md), Occasions): idle,
the typing desk modes and asleep deal one that needs the tags on or the
wait the look has shown, two picks in three while one fits.
## Source events: account for everything, do not animate everything

Rules own activity truth and urgent attention. Mood is independent.
The current normalized contract is Boop's
[`Event.swift`](../../../../app/BoopKit/Core/Event.swift);
the user's earlier seven-type log is a supported legacy input, not the
current serialized shape. Map through the repo's adapter/core/view rather
than parsing raw private tool inputs in this renderer.

| Earlier event type / phase | Current form / visual handling |
| --- | --- |
| session start/end | session_start/end; start may trigger starting with correct ctx; end recomputes base/remaining work, never automatically task success |
| turn start | turn_start; core may show starting and working/planning, as appropriate; a prompt is not mic listening |
| turn end done | turn_end; update base immediately; eligible authorized reaction selects task_complete success/failure or reply_ready using actual content, or no one-shot |
| turn end failed | turn_end; update base; failed finish must use failure outcome if a finish is played; not a trophy |
| turn end stopped | turn_end; stopped one-shot and updated base, not a task failure |
| tool start | tool_start; specific activity classification below, generic fallback only last |
| tool wait permission/input | tool_wait; authoritative needs_you after existing source/grace rules; alert survives mood shifts |
| tool end success | tool_end; remove live call, recompute activity; test/tool success is not automatically whole-task completion |
| tool end failure | tool_end with failed/error; core's error one-shot, preserve subsequent/other work; do not invent security danger or full-task failure |
| subagent end | subagent_end; helper_return, with neutral report unless outcome is known; recompute remaining delegation |
| poke | poke; local poked or tap_spam under existing rules; attention/finish tap can open thread, never approve anything |
| heartbeat working/idle | heartbeat; retain truthful base/activity; may justify a later expressive response, never auto-escalation per tick |
| action start/end or unphased | Current MellowHarness self did/ended, plus needs_you_start/end for attention; record lifecycle and retarget validated mood/react; never re-trigger the same action from its own log |

Current additional types are accounted for: **subagent start** can show
delegating; **talk** carries a sanitized user utterance but listening is
owned by actual mic lifecycle; **presence start/end** reports away/back to
the view and must not fabricate task/activity/mood outcomes; separate
**needs_you start/end** records attention lifecycle. Generic MellowHarness
self/pass events remain bookkeeping unless a specific output has a
noticeable effect. Do not turn every log row into a new animation state.

Older recordings with only subagent end cannot retrospectively prove
when a helper spawned. A delegation tool can establish dispatch; an
actual subagent start establishes live-helper presence in current hooks.
Do not invent a swarm launch from a return event alone.

## Specific tool matching, as implemented now

Use [Core/Activity.swift](../../../../app/BoopKit/Core/Activity.swift) and
agent-hooks' ToolKind as the authoritative classification, rather than
a second brittle list of tool-name guesses:

1. Topic tests → testing, even for Bash.
2. Topic inspect → analyzing, even for shell.
3. Planning tools → planning.
4. Shell/CLI → terminal.
5. Read/local search → analyzing.
6. Web tools → searching.
7. Main-agent Task/Agent → delegating; nested-agent calls use tool_use.
8. Edit/MCP/other → tool_use, unless above applies.

The host already holds an activity briefly to avoid flicker and uses
specific priority/multi-session rules. Follow those rules unchanged;
the renderer should not guess a second current activity. A completed web
search does not prove the agent is now analyzing it: show analyzing when
the next actual activity provides evidence, otherwise preserve/settle
according to the core. Never display actual command/file/query contents;
terminal can use harmless generic stylized snippets.

## Completion and attention are different

A tool can fail while the overall task continues. A turn can end done
because it answered a question or explained failure. Use the existing
finish judgment/validated host facts; do not equate Stop with success.
Under `task_complete`, select an outcome-compatible variant first, then
randomize within it. A denied permission is a normal outcome, not a
reason for fear, accusations or sad guilt acting toward the user.

Needs_you always means a real pending permission/input request. Use large
rounded upper-screen signs plus broad surface contacts; leave the bottom
text lane. Grumpy knocks are firmer and clustered, determined steady,
sad lighter/slower, excited in several positions. All end in the same
ding family. Signs hold silently after their entry; a changed face must
not replay an old alert. See [sound/README.md](sound/README.md).

## Production integration is not flat `state` JSON

The 25 state IDs correspond to existing visuals, but on the wire the
repo sends base/act/attn and named do requests, not a single state field.
Follow LinkKit's [spec](../../../../linkkit/SPEC.md) and its
turn. `no_app` is device timeout, needs_you is attn, activities are act,
and finishes/starts/wake-ups/taps are one-shots or local device behavior. This
design preserves those meanings without expanding the generic protocol.
The expanded moods themselves require a reviewed production migration.
