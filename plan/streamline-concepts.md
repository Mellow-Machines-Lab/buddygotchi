# Streamlining Boop's concepts: the plan (2026-11-02)

Boop works, but it takes about 120 named things to say how. This plan
brings that down to a small model with one word for each idea, so the
owner, a new contributor or an agent can hold all of Boop at once.
Agreed with the owner on 2026-11-02, after the simplify work landed on
branch `simplify`.

**The rule: same behaviour.** Nothing anyone sees or hears changes,
except at the edges where a rule turns out to be missing or two pieces
disagree; each such change is listed below with its reason. Wire and
on-disk keys keep their names (`base`, `act`, `anim`, `react.face`,
`say`, the transcript's kinds), as the Words table already says: the
concepts change in the code, the prompt Jev reads and the docs, not in
saved data.

## The model, on one page

```
 The agents ─┐                         ┌─ DOING   what Boop is busy with      rules, at once
 You ────────┼─► the Mac (the mind) ──►├─ MOOD    how Boop feels, minutes      Jev
             │                         └─ MOMENT  a beat on top, seconds       board, rules or Jev
             │
             └─ each night: MEMORY      what Boop keeps of you                  the Mac
```

Everything Boop shows is one of three layers on the board, and
everything it says goes through one of three channels:

| Layer | Definition | Lasts | Decided by |
| --- | --- | --- | --- |
| **Doing** | What Boop is busy with, from the facts: resting, working (and how), asleep, needs you, listening, no app | While the facts hold | Rules |
| **Mood** | How Boop feels: one of 16 lasting moods, the backdrop that shades Doing | Minutes | Jev |
| **Moment** | A short beat on top when something happens: an event, an emotion, a size, and its voice | Seconds | The board (a touch), rules (a start, a greeting) or Jev |

| Channel | Definition | Owner |
| --- | --- | --- |
| **Voice** | What Boop says aloud: a recorded sound, word or phrase; the speech bubble is its caption | A Moment |
| **Sign** | What Boop holds up: at most 18 characters, often your own words | A Moment |
| **Narration** | The Mac explaining why, in plain words (the reason); never Boop's voice | The Mac |

And four supporting ideas:

| Idea | Definition |
| --- | --- |
| **The agents** | Sessions, turns, tool calls, checks, helpers, to-do lists, needs you |
| **You** | What you do to Boop: touch, words, presence, buttons |
| **Time** | Two clocks: how long (working or resting, the tiers), and what day (part of the day, Boop's 5:00 day, special days, growth) |
| **Tags and dressing** | Tags are facts true now (Friday, busy, a party); dressing is how Doing shows them (a hat, shades, the sun, faster typing) |

## The vocabulary

The words below are the only ones the docs, the code and the prompt use
for these ideas. "Was" lists the words they replace; "kept on the wire"
lists names that stay because they're saved or sent.

**The agents**

| Word | Means | Was | Kept on the wire |
| --- | --- | --- | --- |
| agent | Claude Code or Codex | | |
| session | One conversation, with its thread's name and project | thread (for the conversation) | `session` |
| turn | From your prompt to its finish: done, failed, stopped or answering | | `turn` |
| call | One tool use | tool call, tool use | `call` (stream) |
| check | A test or build run, which passes or fails | | |
| helper | A subagent | subagent (in prose) | `subagent` |
| to-do | An agent's plan, "3/7" | todo list | `todo` |
| needs you | An agent waiting on your approval: a request | attn, alert | `attn` |
| the line | Agents waiting for you, in order | | |
| reading | What Boop takes from a text: kind, tone, length, named, a few words | | |

**You**

| Word | Means | Was |
| --- | --- | --- |
| touch | Anything you do to the board with a finger or a hand: a poke, a stroke, a ruffle, a nose boop, a tickle, a shake, a pick-up, a put-down, a thump | tap, gesture (as two kinds) |
| poke | One tap on the face; a run is several in a row | tap |
| care | The touches and words that count as caring (strokes, kind words, talking, coming back) | |
| words | What you say to Boop on push-to-talk | talk (for the event), said |
| listening | Boop hearing you, while BOOT or the mic is held | push-to-talk (the state) |
| presence | You at the Mac, away, or back | |
| button | BOOT: hands you the next agent in the line | press, hand-off |
| dismiss | A finger held on the needs-you screen | |
| face down | Do not disturb: Moments pause, Doing goes on | |

**Doing**

| Word | Means | Was | Kept on the wire |
| --- | --- | --- | --- |
| doing | What Boop is busy with | base, look (for the state), activity (as a separate idea) | `base`, `act` |
| look | Only the art that draws a Doing | look (for the state) | |
| activity | How it's working: testing, searching, terminal, analysing, planning, delegating, waiting, calls | act | `act` |
| tier | How long it's been working or resting: tier 1 at 30 s to tier 5 at 10 min | | `tier1`…`tier5` |
| pastime | What Boop does to pass the time, by doing and tier | gag (the gel's), idle gag, occasion (the rig's), look occasion | |
| kit | Props shown while true: mugs, headphones, the zone, the plant | | |
| dressing | Outfits and decorations from tags | outfit, layers, occasion (as a design) | |
| pace | Working faster when busy or frantic | | `busy`, `frantic` |
| the work stream | Agents' calls as falling words: part of Doing's surface, never a Moment | gag (the stream's), call forward | `call` |
| the strip | The counts along the bottom | | |
| the drawer | Every agent in a list, pulled up from the strip | roll call | `list` |
| the needs-you screen | Amber, naming who's waiting | | |

**Mood**

| Word | Means | Was |
| --- | --- | --- |
| mood | One of 16 lasting moods | (also used for a reaction's face) |
| resting mood | Calm, where moods settle | default mood |
| neighbours | The moods a mood can move to; a jump is a big move | moves (the graph's), ordinary and dramatic |
| fade | A mood settling after its minutes | |
| mood file | The steering for one mood | |

**Moment**

| Word | Means | Was | Kept on the wire |
| --- | --- | --- | --- |
| moment | A beat on top of Doing: event, emotion, size, voice | reaction (for the beat), one-shot | `do` |
| event | What happened: a finish, a check, you came back, your words, your prompt naming Boop, a touch, or Boop's own beat | | |
| Boop's own beat | A Moment with no outside event: an idle check-in, a musing, an ask | | |
| emotion | The expression for one Moment, any of 42 | face | `react.face`, `mood` (in a `do`) |
| size | How much the Moment matters: small, medium, big, huge | intensity, loops | `react.intensity`, `loops` |
| finish | The animation a turn's end plays, scaled by how long the turn ran (a hop to Mega Boop); the ticket and rim glow name the thread | move (success, failure, reply), task_complete | `task_complete`, `reply_ready`, `outcome` |
| greeting | The animation of your coming back, or of your prompt naming Boop | move (wake up, notice) | `wake_up`, `notice` |
| reply | Boop's answer to your words, with its clip | move (for talk) | `reply` |
| ask | A Moment's sign that is a question, with two answers you tap | | `ask` |
| musing | Boop's own beat with a sign and no question | | |
| the telling | The morning Moment that tells the dream | | |
| variation | Which version of a design plays; the board picks | | `variant` |

**Voice, sign, narration**

| Word | Means | Was | Kept on the wire |
| --- | --- | --- | --- |
| voice | What Boop says aloud: none, a sound, a word, a phrase, a swear | say | `say` |
| take | One recorded clip; a lead sound may come first | | `take` |
| sign | A caption Boop holds up | | `sign` |
| bubble | The voice's words as text | | |
| talk | How much Boop says: quiet, normal, chatty, or silent for a while | hush (as its own setting) | `talk` settings |
| narration | The Mac's plain words for why | reason, dressing (the popover's) | `reason` |

**The mind**

| Word | Means | Was |
| --- | --- | --- |
| transcript | Every event, one file a day | log |
| line | One event as a sentence Jev reads | |
| the prompt | What Jev reads: guide, PERSONALITY, MEMORY, MOOD, CONTEXT, HISTORY, NOW | the state |
| pass | One request to Jev | |
| wake / hold | Whether an event asks Jev at all | |
| check-in | Boop looking in by itself: working (during a turn), idle (while you're here), hourly | heartbeat |
| personality | Who Boop is, temperament included | |
| steering | The pack's text Jev reads | |

**Memory and time**

| Word | Means | Was |
| --- | --- | --- |
| Boop's day | 5:00 to 5:00; it closes each night | |
| dream | Yesterday as tags and a sentence | |
| written memory | `memory.md`: You, Your work, You and Boop, Recently | |
| the night's write | Apple Intelligence editing the written memory | |
| growth | XP and stages, Hatchling to Legend | |
| special day | A holiday, a milestone day, Boop's birthday, a stage reached | occasion (for a day) |
| tag | A fact true now, sent to the board | when, flag |

## The edge cases, decided

Each is a rule the model needs. Most write down what the code does;
where the code may differ, phase 1 checks it and phase 5 fixes it.

1. **Three authors, one shape.** A Moment is made by the board (a touch,
   at once), the rules (a start, a greeting, a stage's celebration) or
   Jev. A Moment the board or the rules make carries no emotion of its
   own: it shows the mood.
2. **Boop's own beat.** An idle check-in, a musing or an ask is a Moment
   whose event is Boop's own. Each is optional, and capped as it is
   today.
3. **A mood change is always seen.** When the mood moves with no Moment,
   the board's transition from one mood's design to the next is what
   you see. (Check: the transition plays on every mood change in a
   `state`.)
4. **Emotion within mood.** A Moment's emotion is free within the mood
   file's steering (a grumpy Boop's grudging proud at a win); after the
   Moment, Doing shows in the mood again.
5. **One priority, top first:** needs you; listening; Moments, in the
   order they arrive, a newer one replacing one that's resting; Doing.
   Doing can change under a Moment and shows when it ends. (Check: the
   board's queue and `Core.reactionBlock` agree with this order.)
6. **Two sizes, two facts.** Jev's size sets how long a Moment holds and
   how much it says; a turn's length sets how grand its finish is.
7. **Several agents, one Doing.** Needs you wins, then working, then
   resting, then asleep; the activity shown is the busiest working
   agent's; the strip and the drawer show the rest.
8. **Buddies.** Each buddy has its own Doing (its agents) and Mood;
   memory is about you, and shared. One buddy's Moment can be another's
   event.
9. **Silence mutes only the voice.** Quiet and silent take away the
   voice and keep the emotion and the size; face down pauses Moments
   and keeps Doing. (Check: a sign still shows while silent, as today.)
10. **The work stream is Doing.** A word coming forward is queued like a
    Moment, but it never carries an emotion or a voice, and it never
    keeps a real Moment waiting.

## The surfaces

**1. Voice, sign, narration.** One owner each, as in the model. Every
source of a sign (your prompt, your words, a reply, a dream, an ask, a
musing, an agent's status) goes through the one sign table already in
`ReactOutput`. The Mac's narration (`Reason`) absorbs `Dressing`, the
popover's "why it wears this", which is narration of dressing.

**2. You.** One table, in the docs and in `Yours`, of every input, who
answers it at once, and whether Jev hears it:

| Input | The board, at once | Jev, later |
| --- | --- | --- |
| A poke | Its tap reaction; the third in a run is a bigger one | Yes, once a run |
| A care touch (stroke, nose, tickle, pick-up) | Its own animation | Yes |
| A rough touch (ruffle, shake, thump) | Its own animation | Yes |
| Put down, peekaboo | Its own animation | No |
| Face down | Pauses Moments | No (held) |
| Your words | Listening | Yes, with a reply |
| Coming back | Nothing | Yes, with a greeting |
| BOOT | Hands you the next agent | Yes, as the line's pick |
| Dismiss | Clears the needs-you screen | No |

(Phase 1 checks every row against the board's and the view's code.)

**3. The lane.** The bottom band shows one thing at a time, in this
order: the needs-you name; an ask's two answers; the bubble while the
voice plays; the narration's fact; a finish's ticket; the strip.
(Check: `drawLane` and the gel's lane follow it; phase 5 fixes any row
that doesn't.)

**4. Time.** Two clocks, named once: how long (tiers, and check-ins and
dozing off measured on it) and what day (part of the day, Boop's day,
special days, growth). The check-ins get one word: working, idle and
hourly check-ins, where the code says heartbeat.

**5. Tags and dressing.** "Occasion" stops meaning three things: a
special day is a special day, a design that needs tags is dressing, and
the rig's now-and-then clip is already a pastime.

## The phases

Each phase is its own commits, each passing `make -C internal check`.

1. **Write the model down, once.** The model, the vocabulary and the
   ten edge cases go into `documentation/architecture.html`'s "How Boop
   works" (the definitions) and CLAUDE.md's Words table (the words, the
   "was", the wire names). While writing, check each "Check" above
   against the code, and list any rule the code breaks for phase 5. No
   code changes. *This alone answers "how does Boop work".*
2. **Rename in the Mac's code.** Types, properties, functions, files and
   comments take the vocabulary, with the wire and saved keys kept:
   - `DeviceReaction` → `Moment`; `ReactOutput` → `MomentOutput` (its
     output name, `react`, kept); `faceKey`'s Swift name → `emotionKey`
     (`react.face` kept); `intensity` → `size` (`react.intensity` kept);
     the move's names → finish, greeting, reply.
   - `StateSnapshot.base` and `act` in Swift → `doing` and `activity`
     (wire `base`, `act` kept).
   - `Occasions` splits into `Calendar` (special days, parts of the day)
     and `Tags`; `Dressing` folds into `Reason`, which becomes
     `Narration` (`reason` kept on the wire).
   - Heartbeats → check-ins (`check_in`, `working`, `idle` kept as the
     transcript's `specific_type`).
   - Touches: one `Touch` type for pokes and gestures in Swift (the
     `tap` and `gesture` events kept).
   Behaviour unchanged; the tests prove it.
3. **The words Jev reads.** The prompt's questions and headings use the
   vocabulary: the face question asks for the Moment's emotion; the
   size, the voice and the sign say what they are; the guide names Doing,
   Mood and Moment in its one sentence about the screen; HISTORY's lines
   for Boop's own reactions say "moment". Gate: `--only` on what each
   change touches, then one full eval run, which holds at 108 of 112 or
   better.
4. **Rename on the board and in the pack.** The firmware and the gel:
   `SceneState`'s looks and reactions read as Doing and Moment; the
   gel's "gag" → pastime or bit where it means idle comedy; `Kit`,
   dressing and pastime keep their names; the pack contract
   (CHARACTER.md) and the Studio's labels take the vocabulary. The
   goldens don't change (a rename draws nothing new).
5. **The edges.** Only the rules phase 1 found the code breaking, each
   fixed with its eval or golden, and listed here before it's built.
6. **The docs agree.** Every doc's old words go (grep for each "was"),
   and the Words table's "Not" column lists them.

## What doesn't change

- What Boop shows, says and decides, except phase 5's listed edges.
- The wire (`hello`, `state`, `do`, `ev` and their fields), the
  transcript's kinds and keys, the answers' keys, `settings.json`, the
  memory files, the packs' file names.
- Several buddies, the CYD, onboarding, the mirror, the drawer's
  scrolling, the bubble beside the sign, the hourly check-in, and every
  other "keep" from the simplify decisions.

## Order and size

Phase 1 is a day's careful writing and is worth doing first on its own:
it is the "how Boop works" the owner asked for. Phases 2 and 4 are
mechanical renames, large in lines and small in risk. Phase 3 is small
in lines and the only one that needs Jev. Phase 5 is unknown until
phase 1 has checked the rules, and may be empty.
