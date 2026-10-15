# Boop: harness example, end to end

Updated 2026-10-05. One turn of failing tests, from the raw events to
what Boop does: the view events, the state and questions Jev gets, its
answers, and what the actions did. How it works is in the code; this
file only shows it.

Everything here is real: run 1 of the eval scenario `04-tests-fight-back`
([EVALS.md](../../../internal/EVALS.md) §4) in a `boopdev eval --runs 1` against
`jev:jev-latest` on 2026-09-29, with the two say questions, the whole
voice bank and the steering of that day.
The lines below are that run replayed through today's code (on
MellowHarness, 2026-09-30) with Jev's recorded answers, so they're in today's
shape and the passes' times are the replay's; the state is left out of
the `pass` lines (`"state":"…"`). The story (§1, §7) is the recorded
run's: replayed today, 14:05 says "Nn... Checking" and 14:07 "Heh...
Test", since Voice's rules for a line of two takes changed after
2026-09-29.

The eval has no device: its fake one answers each reaction `done` at
once ([EVALS.md](../../../internal/EVALS.md) §1), so every `react` action's start is
followed straight away by its end. In the app the end comes when the
device says how its `do` ended.

## 1. The story

A Wednesday afternoon. Claude works in the `fix-nav` worktree of
`landing`. Boop starts calm.

| Time | What happens | Event | Jev's answers | Boop |
| --- | --- | --- | --- | --- |
| 14:00 | A turn starts | 1 | calm · none | Stays quiet |
| 14:01 | The tests fail | 4 | annoyed · annoyed, once · upset 1.00, tests 1.00, a sound | **Turns annoyed**, an annoyed face, held once: "Huh... Verify" |
| 14:03 | They fail again | 10 | determined · determined, once · upset 0.99, tests 0.81, a sound | **Turns determined**, a determined face, held once: "Trouble Probe" |
| 14:05 | A third time | 16 | determined · annoyed, once · upset 1.00, tests 0.72, a sound | An annoyed face, held once: "Nn..." |
| 14:07 | They pass | 21 | proud · proud, twice · glad 1.00, tests 0.98, a sound | **Turns proud**, a proud face, held twice: "Heh..." |

The pass at 14:01 is shown in full (§2–§6), and the ones after it more
briefly (§7). Each answer came back in 200–264 ms.

## 2. The events (14:01)

In the app, the failure arrives as Claude's `PreToolUse` and
`PostToolUseFailure` hooks, which agent-hooks and the adapter turn into
raw `tool` events; the eval hands
the pipeline the same events ([EVALS.md](../../../internal/EVALS.md) §1). The end:

```json
{"event":{"seq":4,"at":1791986460000,"source":"claude","kind":"tool_end","data":{"cwd":"/eval/landing/.worktrees/fix-nav","error":"exit_code","failed":true,"session":"s1","specific_type":"PostToolUseFailure","tool":"Bash","topic":"tests"}},"received_at_ms":1791986460000}
```

The view gives it its line and facts, as the view event with its `seq`, 4. A failed
check with a topic is notable and nothing needs you, so it wakes the
brain. No rule reacts to a tool's end:

```json
{"view":{"facts":{"error":"exit_code","failed_before":0,"result":"failed","thread":{"agent":"claude","name":"fix-nav","project":"landing","session":"s1","turn":1,"workspace":"fix-nav"},"took":"short","took_ms":0,"tool":"shell","tool_name":"Bash","tool_use_id":null,"topic":"tests"},"from":[4],"id":4,"line":"claude's tests failed on \"fix-nav\" (landing).","notes":[],"phase":"end","type":"tool","wakes_brain":true},"received_at_ms":1791986460000}
```

(`took` is `short` because the eval sends a command's start and its
result at the same moment.)

## 3. The state (14:01)

The harness builds the state for event 4. The guide and PERSONALITY are the steering files as they are
([steering/guide.md](../steering/guide.md),
[steering/personality/boop.md](../steering/personality/boop.md)), so
they're left out here; MOOD is calm's file, then HISTORY and NOW:

```
MOOD
Calm. Boop is settled and content, at rest: nothing much is going on.
Its faces lean calm and happy; a failure gets an annoyed face.
Says little: a word to begin a turn.
Stays calm through routine turns, plain finishes and questions.
Leaves for curious or happy at a poke; happy at kind words to Boop or
a long turn's hard work done; engaged while a long turn works on;
annoyed at a failed check or turn, frustration, or 2 pokes in a row;
excited when a very long turn finishes done or the person thanks the
agent; sad when a very long turn fails, the agent gives up or the
person shares sad news; wounded at rude words to Boop.

HISTORY (oldest first; indented lines add to the line above)
1 min ago: claude started turn 1 on "fix-nav" (landing).

NOW (14:01, Wednesday)
claude's tests failed on "fix-nav" (landing).
Boop did nothing on its own.
```

The quiet pass at 14:00 left nothing under the turn's start: a reaction
that didn't happen isn't in HISTORY.

## 4. The questions (14:01)

Seven questions, in one request: `mood`,
offering staying calm and calm's moves on the graph, then `react`'s
six. The log keeps only their keys,
in the order the `pass` line lists them: `mood`, `react.mood`,
`react.animation`, `react.loops`, `say.feeling`, `say.about`,
`say.kind`.

`say.feeling` and `say.about` offer `none`, then every answer in
`ReactAction`'s order, since every face can say each one: `say.feeling`
`none`, `upset`, `glad` and `tickled`, and `say.about` `none` and its
15 topics, as the `p` maps in §5 show.

## 5. The answers (14:01)

Jev answered in 200 ms (the replay's line says 0):

```json
{"pass":{"answers":{"mood":{"choice":"annoyed","p":{"annoyed":0.97,"calm":0.03,"curious":0,"engaged":0,"excited":0,"happy":0,"sad":0,"wounded":0}},"react.animation":{"choice":"none","p":{"failure":0.12,"none":0.88,"reply":0,"success":0}},"react.loops":{"choice":"once","p":{"four times":0,"once":0.9,"three times":0.01,"twice":0.09}},"react.mood":{"choice":"annoyed","p":{"annoyed":0.98,"calm":0,"curious":0,"determined":0,"engaged":0,"excited":0,"grumpy":0,"happy":0,"irritated":0.02,"none":0,"proud":0,"sad":0,"whiny":0,"wounded":0}},"say.about":{"choice":"tests","p":{"answer":0,"command":0,"done":0,"helper back":0,"helpers":0,"looking":0,"none":0,"planning":0,"quiet":0,"retry":0,"start":0,"stopped":0,"tests":1,"tool":0,"waiting":0,"work":0}},"say.feeling":{"choice":"upset","p":{"glad":0,"none":0,"tickled":0,"upset":1}},"say.kind":{"choice":"sound","p":{"phrase":0,"sound":0.95,"swear":0.02,"word":0.03}}},"brain":"jev:jev-latest","dropped":null,"for":4,"latency_ms":0,"now":{"id":4,"line":"claude's tests failed on \"fix-nav\" (landing).","phase":"end","type":"tool"},"options":{"mood":["calm","happy","curious","engaged","annoyed","excited","wounded","sad"],"react.animation":["none","success","failure","reply"],"react.loops":["once","twice","three times","four times"],"react.mood":["none","happy","excited","proud","curious","determined","grumpy","sad","calm","engaged","annoyed","irritated","whiny","wounded"],"say.about":["none","start","helpers","helper back","retry","work","tests","command","tool","looking","planning","done","answer","stopped","waiting","quiet","hello"],"say.feeling":["none","upset","glad","tickled"],"say.kind":["sound","word","phrase","swear"]},"questions":["mood","react.mood","react.animation","react.loops","say.feeling","say.about","say.kind"],"seen":4,"state":"…"},"received_at_ms":1791986460000}
```

## 6. From answers to Boop (14:01)

The harness logged the pass as an event, gave each action its own
answers, in order, and recorded what
each did as a `did` (a started one's end as its `ended`):

```jsonl
{"event":{"seq":5,"at":1791986460000,"source":"self","kind":"pass","data":{"answers":{…},"brain":"jev:jev-latest","dropped":null,"for":4,"ms":0}},"received_at_ms":1791986460000}
{"event":{"seq":6,"at":1791986460000,"source":"self","kind":"did","data":{"action":"mood","by":"brain","for":4,"from":"calm","latency_ms":0,"message":"Boop's mood changed: calm → annoyed.","ok":true,"to":"annoyed"}},"received_at_ms":1791986460000}
{"event":{"seq":7,"at":1791986460000,"source":"self","kind":"did","data":{"action":"react","by":"brain","for":4,"latency_ms":0,"message":"Boop made an annoyed face, held once, and said \"Huh... Verify\".","ok":true,"open":true,"takes":["phase1.nonverbal.deflate.huh__annoyed__contained","phase1.word.test.verify__annoyed__contained"]}},"received_at_ms":1791986460000}
{"event":{"seq":8,"at":1791986460000,"source":"self","kind":"ended","data":{"action":"react","by":"brain","for":7,"outcome":"done"}},"received_at_ms":1791986460000}
```

1. **`mood` got** `annoyed`, one of calm's moves, so it saved it. From
   the next pass MOOD is annoyed's file, and in the app the device gets
   a `state` with `"mood":"annoyed"` at once.
2. **`react` got** an annoyed face, no finish, held `once`, feeling
   `upset` and about `tests`, both at 1.00 (over the 0.35 floor), as a
   `sound`. Voice looked for each in annoyed's takes. For upset, 16
   sounds fit, and it drew
   "Huh...". Annoyed has no tests sound, so it took the nearest kind, a
   word, and drew "Verify". The two run 1,367 + 180 + 1,177 ms, under
   2.8 s, so both play. Nothing needs you, so it queued the face, one
   loop and the line, `say: {"take":"phase1.nonverbal.deflate.huh__annoyed__contained","then":"phase1.word.test.verify__annoyed__contained"}`,
   with a handle, and returned started; the eval's queue ended it
   `done` at once.

The eval checked this step against `react: annoyed|determined`,
`mood: annoyed` and `about: tests|none`, and it passed.

## 7. The passes after it (14:03–14:07)

Each of the next three said something too, in the face's mood:

- **14:03**, the second failure: a determined face, upset (0.99) about
  tests (0.81), as a `sound` (0.56). Determined has no upset sound or
  tests sound, so Voice took words: "Trouble Probe".
- **14:05**, the third: the mood stays determined, but the face is
  annoyed (0.42, over determined's 0.32), upset (1.00) about tests
  (0.72), as a `sound` (0.62). Annoyed's "Nn..." is 1,666 ms, and with
  the tests word Voice drew the line would have run past 2.8 s, so
  "Nn..." played alone.
- **14:07**, the tests passing: a proud face held twice, glad (1.00)
  about tests (0.98), as a `sound` (0.81). Proud's "Heh..." is 1,416
  ms, and again the tests word drawn would have run past 2.8 s, so it
  played alone. (Proud's "Passed" needs a turn that finished a
  success, and a check passing mid-turn isn't one.)

HISTORY at 14:05, as Jev read it:

```
HISTORY (oldest first; indented lines add to the line above)
5 min ago: claude started turn 1 on "fix-nav" (landing).
4 min ago: claude's tests failed on "fix-nav" (landing).
  Boop's mood changed: calm → annoyed.
  Boop made an annoyed face, held once, and said "Huh... Verify".
2 min ago: claude's tests failed on "fix-nav" (landing).
  Boop's mood changed: annoyed → determined.
  Boop made a determined face, held once, and said "Trouble Probe".
Boop has been determined for 2 min.

NOW (14:05, Wednesday)
claude's tests failed on "fix-nav" (landing).
Boop did nothing on its own.
```

The scenario ends at 14:07 with Boop proud. Replayed today, the
transcript holds 25 events: nine of Claude's (the turn's start, and four
starts and four ends of a command), five passes, seven of Boop's actions
(three mood changes and four reactions) and the reactions' four ends,
with five view events.
