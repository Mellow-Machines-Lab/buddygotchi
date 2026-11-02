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

## What phase 1 found (2026-11-01)

Each rule above, checked against the code. The model as the code does
it is in `documentation/architecture.html#model`. Where the code
differs from a rule above, one of two calls was made: the rule is
**amended** to what the code does, because the code's way is deliberate
and nothing is wrong with it; or it's a **break**, fixed in phase 5.

| Rule | Verdict | Call |
| --- | --- | --- |
| 1. Three authors | Holds, but onboarding's finale cheers in happy (`Runtime.onboard`), and the shrug with no Jev sends the mood it's in | Amended: onboarding is a script, and its finale's happy is part of it; the shrug's mood is the mood, so nothing differs |
| 2. Boop's own beats | Holds: a musing once an hour, an ask once an hour and 3 a day (6 Chatty, none Quiet), check-ins by `Talk.pace`, only within 2 h of activity | — |
| 3. A mood change is seen | Partly: no bridge while asleep, with no app or under needs you (the new mood's art is there after); under a Moment with its own emotion the bridge runs from that emotion when it ends; the CYD dissolves only when the design differs | Amended: "seen as soon as Boop shows its mood". Bridging a mood nobody can see would cost frames for nothing |
| 4. Emotion within mood | Holds | — |
| 5. One priority | Partly: listening (and its reply) outranks needs you, on the board and the Mac; a newer Moment replaces a resting one only when nothing waits; the rules' Moments are dropped while a busy one plays (`if_free`) | Amended: the order is listening, needs you, Moments, Doing. You talking to Boop is the one thing that should win over a request |
| 6. Two sizes | Holds; a finish with no turn length is sized by its loops, a finish above small plays once, a sad finish is small | — |
| 7. Several agents | Partly: needs you is a screen on top, not a Doing; "busiest" is the working session with the latest event; the activities include a tool and waiting | Amended to the code |
| 8. Buddies | Partly: only the first buddy's prompt has MEMORY (`Runtime.brain`) | Amended: the written memory is the one onboarding set up for the first buddy, and its "You and Boop" is about that buddy. Sharing it is a design question for the owner, not a rename |
| 9. Silence | Partly: Quiet also offers no asks and no sign for a calm prompt that doesn't name Boop; face down refuses Moments (they don't wait) | Amended: Quiet is fewer interruptions by design (`Talk`); a Moment held through face down would play stale when it's picked up |
| 10. The work stream | Partly: a word waiting counts toward the queue's four, so in a busy queue it can push the oldest waiting Moment out (`kit.cpp`); a word arriving while a Moment rests ends that Moment for the Mac early | **Break 1**, fixed in phase 5. The early end is left: the Moment has played, its sign stays up, and the Mac only learns it ended |
| You (the input table) | Put down, peekaboo, a swipe, dismiss and an ask's answer all wake Jev; the button is only a line (its poke fallback wakes); missing rows: swipe, ask answers, hush, going away, a tap on a ticket, the drawer | Amended: the table in architecture.html is the code's |
| The lane | The bubble comes first, even over the needs-you name; the needs-you name and a finish's names are inside the strip; the ticket hangs over the face | Amended: the bubble only shows over needs you for a reply, which outranks it (rule 5) |

**Phase 4's call.** The gel's "gag" (a yawn, a sneeze, a holiday's
bounce: its short comedy) is a *bit* in the engine's and the face's code
(`playBit`, `bitOf`, `Body::kBit`, `Shows::kBit`) and the docs, but the
generated `slime::Gag` table keeps its design's word: `gags` is a key of
the slime's design data (`expressions.json`) that slimegen and the
voice's tools read, and renaming a pack's design format is more than a
rename that draws nothing new. The work stream's gag is the word's
*style* (`render::CallStyle`, `WorkStream`'s `style`; `CallMove` is
already how it moves); the wire's `as` keeps its values.

**Phase 5, the breaks to build (built):**

1. *A word from the work stream never pushes a Moment out of the
   queue.* LinkKit's full queue makes room by dropping the `do` with the
   least time left to live, the newcomer included, instead of the oldest.
   With equal times to live (every Moment has 5 s) that is the oldest, as
   before; a word (1.5 s) loses to any Moment with more time left than it
   has. The app can't veto a `do` as it joins the queue (it's asked only
   as one starts), so the rule belongs to the queue.

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
