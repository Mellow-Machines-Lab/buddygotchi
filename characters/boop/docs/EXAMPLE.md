# Boop: harness example, end to end

Updated 2026-10-25. One turn of failing tests, from the raw events to
what Boop does: the view events, the state and questions Jev gets, its
answers, and what the outputs did. How it works is in the code; this
file only shows it.

Everything here is real: the first of three runs of the eval scenario
`04-tests-fight-back` ([EVALS.md](../../../internal/EVALS.md) §4), in a
run of every scenario against `jev:jev-latest` on 2026-10-25, with that
day's code, steering and voice bank. Nothing is replayed: the lines
below are copied from that run's log, and the passes' times are Jev's.
The state is left out of the `pass` lines (`"state":"…"`).

The eval has no device: its fake one answers each reaction `done` at
once ([EVALS.md](../../../internal/EVALS.md) §1), so every `react` output's start is
followed straight away by its end. In the app the end comes when the
device says how its `do` ended.

## 1. The story

A Wednesday afternoon. Claude works in the `fix-nav` worktree of
`landing`. Boop starts calm.

| Time | What happens | Event | Jev's answers | Boop |
| --- | --- | --- | --- | --- |
| 14:00 | A turn starts | 1 | calm · none | Stays quiet |
| 14:01 | The tests fail | 6 | annoyed · annoyed, no move, medium · upset 0.73 | **Turns annoyed**, an annoyed face, held twice: "Uh-oh" |
| 14:03 | They fail again | 14 | determined · determined, no move, medium · retry 0.95 | **Turns determined**, a determined face, held twice: "Redo" |
| 14:05 | A third time | 22 | determined · determined, no move, medium · retry 0.89 | A determined face, held twice: "Retry" |
| 14:07 | They pass | 29 | proud · proud, no move, medium · glad 0.67 | **Turns proud**, a proud face, held twice: "Heh..." |

Beside the brain, the rules play their own: the `starting` reaction at
the turn's start, and the work stream's words, each run of the tests
coming forward as `tests` and its result as `FAIL` or `PASS`.

The pass at 14:01 is shown in full (§2–§6), and the ones after it more
briefly (§7). Each answer came back in 98–116 ms.

## 2. The events (14:01)

In the app, the failure arrives as Claude's `PreToolUse` and
`PostToolUseFailure` hooks, which agent-hooks and the adapter turn into
raw `tool` events; the eval hands
the pipeline the same events ([EVALS.md](../../../internal/EVALS.md) §1). The end:

```json
{"event":{"seq":6,"at":1791986460000,"source":"claude","kind":"tool_end","data":{"cwd":"/eval/landing/.worktrees/fix-nav","error":"exit_code","failed":true,"session":"s1","specific_type":"PostToolUseFailure","tool":"Bash","topic":"tests"}},"received_at_ms":1791986460000}
```

The work stream's rule answers it at once: the failed check's word,
`FAIL`, comes forward and hails Boop (the start, event 4, had brought
`tests` forward as the turn's first call, `arrive`):

```json
{"event":{"seq":7,"at":1791986460000,"source":"self","kind":"did","data":{"action":"call","as":"hail","by":"rule","for":6,"ok":true,"session":"claude/s1","word":"FAIL"}},"received_at_ms":1791986460000}
```

The view gives the end its line and facts, as the view event with its
`seq`, 6. A failed check with a topic is notable and nothing needs you,
so it wakes the brain. The brain hears nothing of the `call`: the check's
failure is a line of its own already.

```json
{"view":{"facts":{"error":"exit_code","failed_before":0,"result":"failed","thread":{"agent":"claude","name":"fix-nav","project":"landing","session":"s1","turn":1,"workspace":"fix-nav"},"took":"very short","took_ms":0,"tool":"shell","tool_name":"Bash","tool_use_id":null,"topic":"tests"},"from":[6],"id":6,"line":"claude's tests failed on \"fix-nav\" (landing).","notes":[],"phase":"end","type":"tool","wakes_brain":true},"received_at_ms":1791986460000}
```

(`took` is `very short` because the eval sends a command's start and its
result at the same moment.)

## 3. The state (14:01)

The harness builds the state for event 6, in two parts. Its head, the
guide, PERSONALITY, MOOD and TALK, the log writes as a `head` line only
when it changes, so this pass shares the one written before the 14:00
pass. HISTORY and NOW are the pass line's `state`. The guide and
PERSONALITY are the steering files as they are
([steering/guide.md](../steering/guide.md),
[steering/personality/boop.md](../steering/personality/boop.md)), so
they're left out here; MOOD is calm's file and TALK normal's
([steering/talk/normal.md](../steering/talk/normal.md)), then HISTORY
and NOW:

```
MOOD
Calm. Boop is settled and content, at rest: nothing much is going on.
Its faces lean calm and happy; a failure gets an annoyed face, a very
long turn failing a sad one.
Says little: one thing, small or medium.
Stays calm through routine turns (requests that don't sound fed up,
shipping too, their commands and plain finishes), questions and a
streak of quick wins, whatever faces they get.
Leaves for curious or happy at a poke; happy at kind words to Boop or
a long turn's hard work done; engaged while a long turn works on;
annoyed at a failed check, a failed turn short of very long,
frustration, or 2 pokes in a row; excited at once when the person
thanks the agent, or a very long turn finishes done; sad when a very long
turn fails, the agent gives up or the person shares sad news; wounded
at rude words to Boop.

TALK
Normal: Boop says how it feels or names what NOW is about as
PERSONALITY's Examples do, and this outranks what MOOD says of words.
A failed turn keeps its Example's swear. A plain prompt, a check
failing or passing or a check-in still gets its face, saying something
or nothing as its Example does. A prompt that sounds like
something still holds up its sign.

HISTORY (oldest first; indented lines add to the line above)
1 min ago: claude started turn 1 on "fix-nav" (landing).

NOW (14:01, Wednesday)
claude's tests failed on "fix-nav" (landing).
Boop did nothing on its own.
```

The quiet pass at 14:00 left nothing under the turn's start: a reaction
that didn't happen isn't in HISTORY. Nor are the rules' `starting` and
the work stream's words: NOW's last line says Boop did nothing on its
own.

## 4. The questions (14:01)

Five questions, in one request: `mood`, offering staying calm and
calm's 12 moves on the graph, then `react`'s four. The log keeps only
their keys, in the order the `pass` line lists them: `mood`,
`react.face`, `react.move`, `react.intensity`, `say`.

`react.face` offers `none` and the pack's 42 faces; `react.move` `none`
and its five moves, a turn's finish (`success`, `failure`, `reply`),
`wake up` and `notice`; `react.intensity` `small`, `medium`, `big` and
`huge`, which hold the face once to four times and say a sound, a word,
then a phrase; and `say` `none`, `swear`, the three feelings and the 16
topics, as the `options` in §5 show.

## 5. The answers (14:01)

Jev answered in 104 ms:

```json
{"pass":{"answers":{"mood":{"choice":"annoyed","p":{"annoyed":0.96,"calm":0.04,"comfy":0,"curious":0,"engaged":0,"excited":0,"happy":0,"pleased":0,"sad":0,"surprised":0,"tired":0,"uneasy":0,"wounded":0}},"react.face":{"choice":"annoyed","p":{"affectionate":0,"amused":0,"angry":0,"annoyed":0.9,"baffled":0,"bored":0,"calm":0,"comfy":0,"confused":0,"crying":0,"curious":0,"determined":0.04,"disappointed":0,"disgusted":0,"embarrassed":0,"engaged":0,"excited":0,"exhausted":0,"frightened":0,"grumpy":0,"happy":0,"hopeful":0,"irritated":0.06,"lazy":0,"lonely":0,"mischievous":0,"none":0,"overwhelmed":0,"pleased":0,"proud":0,"relieved":0,"sad":0,"scared":0,"shy":0,"skeptical":0,"speechless":0,"stunned":0,"surprised":0,"tired":0,"uncomfortable":0,"uneasy":0,"whiny":0,"wounded":0}},"react.intensity":{"choice":"medium","p":{"big":0.02,"huge":0.01,"medium":0.74,"small":0.23000000000000001}},"react.move":{"choice":"none","p":{"failure":0.04,"none":0.96,"notice":0,"reply":0,"success":0,"wake up":0}},"say":{"choice":"upset","p":{"answer":0,"command":0,"done":0,"glad":0,"hello":0,"helper back":0,"helpers":0,"looking":0,"none":0,"planning":0,"quiet":0,"retry":0,"start":0,"stopped":0,"swear":0.02,"tests":0.25,"tickled":0,"tool":0,"upset":0.73,"waiting":0,"work":0}}},"brain":"jev:jev-latest","dropped":null,"for":6,"latency_ms":104,"now":{"id":6,"line":"claude's tests failed on \"fix-nav\" (landing).","phase":"end","type":"tool"},"options":{"mood":["calm","comfy","curious","engaged","pleased","tired","uneasy","happy","annoyed","surprised","wounded","excited","sad"],"react.face":["none","calm","comfy","lazy","bored","pleased","happy","excited","curious","engaged","determined","proud","mischievous","shy","uncomfortable","annoyed","irritated","grumpy","angry","disappointed","sad","crying","whiny","wounded","uneasy","scared","frightened","surprised","stunned","speechless","amused","hopeful","relieved","confused","baffled","skeptical","embarrassed","affectionate","lonely","tired","exhausted","overwhelmed","disgusted"],"react.intensity":["small","medium","big","huge"],"react.move":["none","success","failure","reply","wake up","notice"],"say":["none","swear","upset","glad","tickled","start","helpers","helper back","retry","work","tests","command","tool","looking","planning","done","answer","stopped","waiting","quiet","hello"]},"questions":["mood","react.face","react.move","react.intensity","say"],"seen":7,"state":"…"},"received_at_ms":1791986460000}
```

## 6. From answers to Boop (14:01)

The harness logged the pass as an event, gave each output its own
answers, in order, and recorded what
each did as a `did` (a started one's end as its `ended`):

```jsonl
{"event":{"seq":8,"at":1791986460000,"source":"self","kind":"pass","data":{"answers":{…},"brain":"jev:jev-latest","dropped":null,"for":6,"ms":104}},"received_at_ms":1791986460000}
{"event":{"seq":9,"at":1791986460000,"source":"self","kind":"did","data":{"action":"mood","by":"brain","for":6,"from":"calm","latency_ms":0,"message":"Boop's mood changed: calm → annoyed.","ok":true,"to":"annoyed"}},"received_at_ms":1791986460000}
{"event":{"seq":10,"at":1791986460000,"source":"self","kind":"did","data":{"action":"react","by":"brain","for":6,"latency_ms":1,"message":"Boop made an annoyed face (medium), and said \"Uh-oh\".","ok":true,"open":true,"takes":["phase1.word.setback.uh-oh__annoyed__contained"]}},"received_at_ms":1791986460000}
{"event":{"seq":11,"at":1791986460000,"source":"self","kind":"ended","data":{"action":"react","by":"brain","for":10,"outcome":"done"}},"received_at_ms":1791986460000}
```

1. **`mood` got** `annoyed` (0.96), one of calm's moves, so it saved
   it. From the next pass MOOD is annoyed's file, in a new `head` line,
   and in the app the device gets a `state` with `"mood":"annoyed"` at
   once.
2. **`react` got** an annoyed face (0.90), no move (0.96), `medium`
   (0.74) and `upset` (0.73, over the 0.35 floor; `tests` had 0.25).
   Medium holds the face twice and says a word. Voice looked in
   annoyed's takes: 14 takes of an upset word fit, and it drew "Uh-oh". Nothing
   needs you, so it queued the face, two loops and the take,
   `say: {"take":"phase1.word.setback.uh-oh__annoyed__contained"}`,
   with a handle, and returned started; the eval's device ended it
   `done` at once.

The step expects `react: annoyed|determined`, `mood: annoyed` and
`say: tests|none|upset|glad|tickled`, and the answers meet all three.

## 7. The passes after it (14:03–14:07)

Each of the next three said something too, in the face's mood, and
each was `medium`, held twice and saying a word where the face had one:

- **14:03**, the second failure, "2 times in a row": the mood turns
  determined (0.92), with a determined face (0.81), saying `retry`
  (0.95). Determined has 8 retry words, and Voice drew "Redo".
- **14:05**, the third: the mood stays determined (0.98), so `mood`
  changed nothing. A determined face (0.58, over grumpy's and
  irritated's 0.18), `medium` (0.54, over `huge`'s 0.36), saying
  `retry` (0.89). Voice doesn't say the last `say`'s words again while
  another fits, so it drew "Retry", not "Redo".
- **14:07**, the tests passing "after failing": the mood turns proud
  (0.89), with a proud face (0.97), saying `glad` (0.67, over `tests`'
  0.30). Proud has no glad word, so Voice took the nearest kind that has
  one, a sound, and drew "Heh...", one of 8.

HISTORY at 14:05, as Jev read it:

```
HISTORY (oldest first; indented lines add to the line above)
5 min ago: claude started turn 1 on "fix-nav" (landing).
4 min ago: claude's tests failed on "fix-nav" (landing).
  Boop's mood changed: calm → annoyed.
  Boop made an annoyed face (medium), and said "Uh-oh".
2 min ago: claude's tests failed again on "fix-nav" (landing), 2 times in a row.
  Boop's mood changed: annoyed → determined.
  Boop made a determined face (medium), and said "Redo".
Boop has been determined for 2 min.

NOW (14:05, Wednesday)
claude's tests failed again on "fix-nav" (landing), 3 times in a row.
Boop did nothing on its own.
```

The scenario ends at 14:07 with Boop proud. The transcript holds 34
events: nine of Claude's (the turn's start, and four starts and four
ends of a command), five passes, sixteen of Boop's outputs (the rules'
`starting` and eight work-stream `call`s, three mood changes and four
reactions) and the reactions' four ends, with five view events.
