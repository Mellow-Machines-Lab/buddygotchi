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
| `hello` | A greeting, one asking how it's going included | a hop and a sway | the `hello` topic |
| `bye` | Goodbye, good night, "I'm off" | a slow sway | glad |
| `thanks` | Praise or thanks | puffing up tall | glad |
| `love` | Affection | snuggling down, eyes shut | glad |
| `ouch` | Rude words | a flinch | upset |
| `comfort` | You sound tired, sad or stressed, or bring bad news | leaning in low | nothing: the upset takes are as often cross as kind |
| `hehe` | A joke or teasing | giggling bounces | tickled |
| `status` | Any question about the agents or the work, how many are running included | looking down at its sign | work |

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
that isn't there is `no codex around`, one resting `codex: resting`, and
several of its sessions at work `2 claude working`. The agent's name is
left off a fact it won't fit beside in 18 characters.

## 4. Asked about them all: the drawer

Added the same day, after "how many agents are running?" got
`claude: done!`: one fact can't answer a question about every agent,
and 18 characters can't list them. So a reply has three parts, each
decided in one place: **what you meant** (Jev, `react.reply`), **what's
true** (the Mac, the sign) and **where to look** (the Mac, `show`, one of
the board's own screens). Jev's questions didn't change.

- **Name no agent or place with two or more sessions open** and the
  sign counts them (`StatusReply.count`): who needs you, else
  `2 working, 1 idle`, else `3 resting`. The `do` carries
  `"show": "drawer"`.
- **The board opens the drawer itself** 1.5 s in (`kShowDrawerMs`), once
  the sign has been read, and says `open` as a pull does, so the Mac
  sends the rows; it shuts after 15 s untouched, as after a touch. A
  finger or BOOT first keeps it shut, and so does a request that shows.
  Push-to-talk (BOOT held, or the Mac's `listening`) shuts an open
  drawer, so Boop's face listens.
- **One session, or a name**, gets one fact and no drawer: the sign is
  the whole answer.
- **A greeting is `hello`**, one asking how it's going included: "hey,
  how's it going?" had been read as `status`, which would now slide the
  drawer up at a hello.
- **Onboarding shows what to say**: the talk lesson's chips ("hi Boop!",
  "good job!", "how many agents are running?"), the brain key's card
  once saved ("Now I can answer you…"), the finale's tip and the Talk
  button's.

A pack whose face has no drawer (Pixel) shows the count alone. Later
screens (today's to-dos, the diary) would be more values of `show`,
never more questions for Jev.

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

Section 4: `ReplyTests` (the count, the drawer only with nothing named
and several sessions, a named agent's sessions counted, `show` on the
`do`); the gel's firmware tests (`test_a_reaction_shows_the_drawer_once_its_sign_is_read`,
`test_a_finger_or_a_request_first_keeps_it_shut`,
`test_holding_boot_to_talk_shuts_it`) and the drawer scenario's `asked`
and `shown`; the mirror rebuilt; evals `126` and `127` with a greeting
and the count question added.

The first three sections:

Swift unit tests (`ReplyTests`: the questions, `huh`, the reply's clip,
takes and sign, a forced pass after what you said, the facts' order, the
10 minutes, names and places; `SignTests`: the pack's `replies.md`); the
gel's firmware test (`test_a_reply_plays_its_clip_once`) and simulator
scenario (`scenarios-gel/replies.jsonl`); both boards' firmware and the
mirror; the `talk-back` demo played through headless Boop on the
simulated board; and Jev's evals: `126` (16 things said, 2 runs), `127`
(3 runs), the talk scenarios, the always-on set and the prompt-sign ones.

The board's look of each clip on the AMOLED is the owner's to see.

## Part two: four questions, and what talk didn't cover (2026-10-25)

Using it showed seven kinds of things you say that the twelve replies
answered badly. Covering them as more replies made one question of
seventeen options, so the owner asked for the questions as a whole to
make sense first: one about the mood, one about the face, one about
what the body does, one about what it says, and one about how big the
moment is, from which how long it holds follows. Jev still makes every
choice, so all of it stays steerable; the app adds only facts.

### What went wrong

| You say | What happened |
| --- | --- |
| "tell claude yes", "approve it" | `yes`, a nod: as if Boop approved something, which it never does |
| "we shipped it!", "wish me luck" | `thanks` or `hehe`: your good news had no reply |
| "dance!", "go to sleep", "shh" | `yes`, a nod, then nothing: a promise it didn't keep |
| "sorry, boop" after an insult | `love` or `thanks`, as if nothing happened |
| "how are you?" | `hello`, `dunno` or `status` |
| "what's claude doing?" | `status`: how long, not what |
| "how long have I been at it?" | `status` about the agents, or `dunno` |

### The questions

Every pass asks the same four of a reaction, after the mood's:

| Question | Asks | Options |
| --- | --- | --- |
| `react.face` | Which face, if any | none, or the pack's faces; never none to what you said |
| `react.move` | What its body does | at an event, none or a turn's finish (success, failure, reply), a wake-up or a notice; to what you said, its reply |
| `react.intensity` | How big the moment is | small, medium, big, huge |
| `say` | What it says | none, a feeling (upset, glad, tickled), a swear, or a topic (start, tests, done…) |

They replace six: `react.mood`, `react.animation` and `react.reply`
became the face and the move, `say.feeling` and `say.about` became one
`say` (one thing said, never a feeling and then a topic), and
`react.loops` and `say.kind` became the intensity. The intensity sets
both how long the face holds and how big the take is
(`ReactOutput.sizes`): small once and a sound, medium twice and a word,
big three times and a phrase, huge four times and a phrase. A swear is
`say`'s, at any size. TALK still only steers Jev, and only what it says
(`say` judges by TALK first): quiet says nothing at a small moment and
never names what NOW is about, chatty says something at every face; how
big a moment is stays the Examples'. PERSONALITY's Examples read the
same way, an Example with no size being small: `→ grumpy, failure,
swears, huge`, `→ engaged, says work, medium`, `→ proud, replies thanks,
says glad, medium`.

### The replies

Fourteen, `react.move`'s options to what you said:

- **New:** `nap` ("go to sleep", "shh"), `dance`, and `notme` (asked to
  answer, approve or tell an agent something: Boop never does, and looks
  to the Mac).
- **`yes` and `no` are never a promise.** `yes` is never a request;
  `no` turns down any other trick, and a trick it isn't in the mood for
  (the cheeky personality turns one down as often as it does it).
- **`thanks` takes your good news** and wishing you luck; **`love` takes
  a sorry**.
- **`huh` takes `dunno`**: Boop can't answer it. The board plays a shrug
  (`dunno`) when your words are a question and a head tilt when not
  (`ReactOutput.played`), its clip and signs as before.
- "How are you?" is `yes` or `no` by its mood, its face saying the rest.

### Signs that know the moment

`replies.md` lines take the moment's tags beside the calendar's
(`ReactOutput.momentTags`): `working` while an agent works, `waiting`
while something waits on you (`Core.moment`), and `makeup` within 10
minutes of an `ouch` (`makeupMs`). So a nap while claude works holds up
"after this", notme while a request waits "that's ur job", and a sorry
after an insult "...fine".

### Tricks the gel knows

On the gel, `nap` and `dance` while the look is idle or asleep play its
own pastimes, the snuggle under its blanket and the dance
(`kReplyPastimes`, `GelFace::reply`), started as a dealt one is: they
cut the one playing short, count as the last dealt and rest after. At
work they play their clips, a yawn and a wiggle; the blanket stays out
of work. `notme` is a firm little head shake, its eyes off to one side.

### More from `status`

Asked what an agent is doing ("doing", "working on", "up to"), the work
going on says what you last asked it for, its prompt's reading
(`claude: a fix`, `TranscriptView.asked`). Asked how long you've been at
it ("how long" with "I" or "we"), the working stretch the tiers count
from answers (`at it 1 h 20`, `Core.stretchSince`), ahead of counting
the agents, but never ahead of something waiting on you.

### How it was checked

Boop's Swift tests (492 passed, the soak skipped), with `ReplyTests`
for the fourteen replies, `huh` played as `dunno` at a question, the
moment's signs and `makeupMs`, and what an agent is doing and how long
you've been at it; `HarnessTests` and `VoiceTests` for the four
questions, the intensities' holds and sizes, and one take said. The
gel's firmware tests, with a nap and a dance playing their pastime when
idle and their clips at work; the simulator's scenarios, with
`replies.jsonl`'s new frames looked at; the mirror rebuilt; both
boards' firmware; `boopctl`'s tests, which still read logs from before;
the evals with the expect brain (108/108); and `make -C internal check`.

Jev, by full runs of every scenario: 92/110 at first, 101/108 at the
end. Comparing like with like on main (the same scenarios, 3 to 6 runs
each) found the four questions shifted a few marginal judgements, which
the steering now states plainly: a sorry or a thanks moves the mood at
once (grumpy, calm, whiny), a long failed turn is big and swears, a
failed turn that calls itself done is still a failure (an Example), and
an Example gives no size when it's small, since "small" read as
routine. What still fails, and how often, on the last run: Quiet (`122`)
still names what NOW is about at a frustrated prompt and gives a short
finish a word, as PERSONALITY's Examples do: with what to say and
whether to say it one question, TALK's text alone doesn't hold it, and
doing better means Quiet taking options out of `say` in code, the
owner's call. `08` and `27` (a very long failure or giving up makes Boop
sad) and `103` and `124`'s first step (a clean-up prompt gets a face)
are marginal choices that pass in some runs and not others, as `56`
and `57` are on main.

The board's look of the new clips, and the nap and dance on request, on
the real AMOLED is the owner's to see.

## Part three: the hush, and Quiet in code (2026-10-25)

With what to say and whether to say it one question, TALK's text alone
couldn't keep a quiet Boop quiet (eval `122`): Jev followed
PERSONALITY's Examples over it. The owner reversed "Talk is never a
gate in code" for this, and asked for a way to tell Boop to be quiet
that holds, and shows.

- **The hush is a state, not a mood.** Moods are Boop's feelings, moved
  a step at a time and fading on their own; a hush is your instruction
  with a clock. The core keeps it (`Core.Hush`: who, until when),
  records it starting and ending (the `hush` event), reads it back on
  launch, and sends the board `hushed` while it lasts, for which the gel
  zips its mouth.
- **Started** by the reply `hush` ("shh", "be quiet", "shut up"), for
  as long as the moment is big (`Core.hushMsBySize`: 15 minutes small,
  30 medium, an hour big, two hours huge), or by the popover's Hush
  button, for 30 (`Core.hushMs`), which wakes the brain once. **Ended**
  by the time running out, the popover's chip, or the reply `unhush`
  ("you can talk now"), offered only while hushed.
- **While hushed**, `ReactOutput` asks no `say` but of what you said,
  and says nothing but an `unhush`; faces, moves and signs go on. The
  popover shows "Hushed · 23 min", which ends it on a click.
- **Boop sulks a little**: PERSONALITY moves its mood one ordinary step
  down (calm to tired, happy to calm, annoyed to whiny).
- **Quiet in code**: `say` offers no topic and no swear, and a small
  moment or a finish says nothing, the cheer still playing.

