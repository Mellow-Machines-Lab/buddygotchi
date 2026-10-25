# Talking back: the plan (updated 2026-10-25)

What you say to Boop on push-to-talk reached the brain word for word,
but the brain had almost nothing to answer it with: a face, a feeling
out of `glad`, `upset` and `tickled`, a topic about the agents' work, and
no sign. So "good job", "I love you" and "we shipped it" all came out
the same, and "is claude done?" got a curious face. This plan gives Boop
a smart pet's answers: it gets what you meant and answers that, with its
body, a sound or a word, and a sign that can carry real facts. Not a
conversation: one answer to each thing you say, as before. Decided with
the owner on 2026-10-25, and built that day, all three stages.

Left out on purpose: free text of any kind (the brain stays multiple
choice and never writes a word), new recordings (the replies borrow the
takes there are), remembering what you said, tricks on request ("dance",
"shh"), your own words held up back to you (they'd need the words read
on the Mac first), and a sign for each nature: the natures stay as they
are until the personality can shift over time.

## Before

Holding BOOT (or the app's mic button) and speaking, the words reached
NOW as `You said to Boop: "good job, buddy"`, and `ReactOutput` asked
the six questions it asks of anything: `react.mood`, `react.animation`,
`react.loops`, `say.feeling`, `say.about` and `say.kind`. PERSONALITY gave
talk one sentence ("proud at kind words, wounded at rude ones, sad at
sad news, happy or curious at anything else"), and eval `35` took any of
seven faces for a question.

## The idea: one question, the rest from tables and facts

When NOW is something you said, the brain answers **what Boop replies**
(`react.reply`) in place of the feeling, the topic and the animation.
The reply is the understanding. Everything after it is looked up, never
guessed:

- **the clip** Boop's body plays: the `do`'s `reply`, for which the gel
  plays its pack's rig clip `reply-<name>` over the face;
- **what it says**: the takes there are, by the feeling or topic the
  reply borrows;
- **the sign** it holds up: the pack's `replies.md` line for it, or, for
  a question about the agents, the facts the core and the transcript
  already keep (`StatusReply`).

The brain still picks the face, how long it holds and how big what it
says is. It never states a fact.

```
mic ─► Runtime.heard ─► said event ─► NOW: You said to Boop: "…"
                                          │
                         Jev: react.mood (never none), react.reply, react.loops, say.kind
                                          │
          ReactOutput.run: reply ─► reply (the do's arg) ─► the gel's reply-<name> clip
                                 ─► takes (Voice, by the reply's feeling or topic)
                                 ─► sign (replies.md, or StatusReply's facts)
                                          │
                       do react {sign, reply, say, mood, loops} ─► the board
```

Every piece is one that existed: the questions are MellowHarness's, the
output is `ReactOutput`, the sign is `Signs`, the words are Voice's and
the clip is the rig's, as the notice's is. LinkKit and the packages
don't change.

## 1. Replies

| Reply | When (the option's gist) | Clip | Borrows |
| --- | --- | --- | --- |
| `yes` | Agreeing, or yes to a question about Boop itself ("are you awake?") | a nod | glad |
| `no` | Disagreeing, refusing, or no to such a question | a shake of the head | upset |
| `dunno` | A question Boop can't know (the weather, dinner) | a shrug | looking (`Eh?`, `Hm?`) |
| `huh` | Nonsense, or words cut off | a head tilt, one eye narrowed | looking |
| `hello` | A greeting | a hop and a sway | the `hello` topic |
| `bye` | Goodbye, good night, "I'm off" | a slow sway | glad |
| `thanks` | Praise or thanks | puffing up tall | glad |
| `love` | Affection | snuggling down, eyes shut | glad |
| `ouch` | Rude words | a flinch | upset |
| `comfort` | You sound tired, sad or stressed, or bring bad news | leaning in low | nothing: the upset takes are as often cross as kind |
| `hehe` | A joke or teasing | giggling bounces | tickled |
| `status` | Any question about the agents or the work | looking down at its sign | work |

- **Yes and no are never about the agents.** Their options say so:
  "Is claude done?" is `status`, whose sign carries the answer.
- **An unsure brain says `huh`.** Below `sayFloor`, the reply is `huh`.
- **Talk always gets a face.** The talk pass's face question has no
  `none`: a brain that once picked none at 16% left a goodbye unanswered.
- **The clips** are body, eyes and mouth only, no new drawing
  (`characters/boop/rig/clips/reply-*.json`). A pack with no clip for a
  reply plays the face alone (Pixel, on the CYD, which stays frozen).
- **PERSONALITY.** The one sentence about talk became "the reply answers
  what you meant", with four Examples (thanks, ouch, status, comfort):
  the other replies are plain from their options, and the personality
  stays within its budget.

## 2. A sign for every reply

The pack's `steering/replies.md`, a line or two for each reply but
`status`, its first tag the reply and any more the calendar's:

```
- [hello] hi hi!
- [hello morning] morning!
- [bye night] nite nite
- [thanks] i know ;)
- [comfort] *hug*
```

The app picks one that fits, the most tags first, at random among those,
never the one it showed last while another fits. No sign question is
asked and none of it goes to the brain. It's a file of its own, not
lines in `signs.md`: those are captions offered to the brain, with its
budget, and these never are.

## 3. Answers about the agents

`status` holds up one fact, first match wins (`StatusReply.sign`):

1. Something waiting on you: `codex needs you`, `2 need you`. A request
   that shows holds every reaction back, the needs-you screen answering
   for it, so this is one you dismissed and the agent still waits.
2. Work going on: one agent's latest result this turn, whatever it
   checks (`tests failed`, `build passed`), else its to-do list (`claude:
   3/5 done`), else how long (`claude: 4 min in`); several, `3 working`.
3. How the last of it came out, within 10 minutes: `claude: done!`,
   `failed :(`, or a check's result.
4. Nothing: `all quiet`.

A result is anything that came out one way or another: a check (any of
the transcript's check topics) passing or failing, or a turn done,
failed or stopped; the transcript keeps each session's latest
(`TranscriptView.results`). Say an agent ("is codex done?") or a place,
its project, workspace or thread's name, matched as you'd say it ("the
landing page", "landingpage"), and only those sessions count; an agent
that isn't there is `no codex around`, one resting `codex: resting`. The
agent's name is left off a fact it won't fit beside in 18 characters.

## What it got rid of

- **Two questions on every talk pass**: four, not six.
- **The talk clauses all through the other options**: `upset`, `glad`,
  `tickled`, the `quiet` and `hello` topics, `say.kind`'s `none` and
  `react.animation`'s `none` and `wake up` each went back to one thing.
  `say.kind`'s `swear` keeps "words to Boop" in what it isn't for.
- **PERSONALITY's four buckets**, "happy or curious at anything else"
  with them.
- **"It can't talk back"** in the brain's guide (`EventLine`).
- **Eval `35`'s seven faces for anything**, for an exact reply.

Nothing else moved: push-to-talk, `listening` and its reply wait, the
prompt's signs and several buddies hearing the app's button stay as
they were.

## How it was checked

Swift unit tests (`ReplyTests`: the questions, `huh`, the reply's clip,
takes and sign, a forced pass after what you said, the facts' order, the
10 minutes, names and places; `SignTests`: the pack's `replies.md`); the
gel's firmware test (`test_a_reply_plays_its_clip_once`) and simulator
scenario (`scenarios-gel/replies.jsonl`); both boards' firmware and the
mirror; the `talk-back` demo played through headless Boop on the
simulated board; and Jev's evals: `126` (16 things said, 2 runs), `127`
(3 runs), the talk scenarios, the always-on set and the prompt-sign ones.

The board's look of each clip on the AMOLED is the owner's to see.
