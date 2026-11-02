# The wish

Updated 2026-11-02. The plan for Boop's one want a day: a need you can
see, met by one thing you do, with an instant reward, and a small cost
when you leave it. Decided with the owner on 2026-11-01. Build it after
`streamline`; the other ideas from the same talk (chapters, keepsakes,
visible growth) are on hold.

## Why

A Tamagotchi holds people with a care loop: it wants something, you do
one simple thing, you see the effect. Boop reacts richly to your agents,
but it hardly ever wants anything from you, and the effect of your care
goes mostly into the prompt, where you can't see it. The wish is the
loop's smallest form. Your part stays simple; Boop's side (moods,
temperament, faces) can stay rich.

## What a wish is

A lasting state, like "needs you": a buddy has at most one, until you
meet it or it ends. Three kinds, each met by what you do anyway:

| Wish | Sign when made | Icon while it waits | Met by |
| --- | --- | --- | --- |
| `pet` | pet me? | a hand | a stroke |
| `chat` | talk to me? | a speech dot | any push-to-talk to this buddy |
| `work` | work with me? | a little laptop | any interaction with an agent: a prompt you send, a needs-you you answer. You never have to make one up |

The kinds are in code, because code decides what meets each. The pack
writes only the words: each kind's sign, and what the buddy says when
it's met.

## Making one: Jev picks the time

No hardcoded trigger, and no new question. At an idle check-in, a moment
asks use (never at a finish, whose sign names its thread:
`plan/finish-sign.md`), the
react output's sign question ("Does Boop hold up something?",
`ReactOutput.questions`) already offers `none`, the musings and the asks.
A wish is three more options there, the pack's words ("pet me?", "talk
to me?", "work with me?"); picking one makes the wish, as the brain's
`hush` reply calls the core (`core.wish(.pet, at:)`). The sign plays as
part of the reaction. Each is offered only when:

- no wish is open;
- you're at the Mac and the buddy is awake;
- nothing needs you, and it isn't listening or hushed;
- `work` only while no agent is working (else your next prompt meets it
  for nothing).

Jev picks when and which, by mood, MEMORY and CONTEXT. The guide says
about one a day, when it feels like it. CONTEXT's You row says "no wish
yet today", and at an idle check-in from midday "no wish yet today, and
the day's half gone": a nudge, not a trigger. Code holds only one open at a time; how many a day is Jev's, by the steering (the owner's call, 2026-11-01).

On Quiet a wish is still made, as the icon and the sign, with no sound:
unlike asks (`Asks.allowed`), the wish options are offered on Quiet.

## While it waits

- The icon is a tiny thought bubble beside the buddy's head, not a chip
  in the strip: it looks like wanting, not like a status. On Pixel's
  one-line lane it is text ("wants: pet"). It is carried in `state`
  (`state.wish`, none while the wait is paused), so the board times
  nothing.
- The popover's Feeling row: "Boop wishes for a pet (40 min)."
- Jev may hold the sign up again once at a later check-in.
- A turn doesn't block or pause it. The icon stays beside the working
  look; a stroke mid-turn meets it.

**The wait counts only time you could answer:** it pauses while you're
away, while the buddy sleeps (the icon hides) and while the needs-you
screen is up (the icon hides under it). You can only miss a wish by
being at the Mac and leaving it.

## Met

A rule in the core meets it at once; the brain isn't on this path.

- The board plays the fulfilment animation as a rule's reaction, as
  fast as a tap's: a sparkle, a bounce, the icon popping into a heart.
- Then Jev reacts on its next pass, as to anything: the line says you
  gave the buddy its wish.
- The reason: "You gave Boop its wish: a pet.", on the board "wish met!".

## Not met

| Your time at the Mac since the wish | What happens | Who decides |
| --- | --- | --- |
| 0 | The sign, then the icon | Jev picks the moment |
| about 1 h | The buddy may turn sad, or lonely | Jev, from the steering |
| 3 h | It takes the wish down: a small sulky beat, the icon fades, `missed` | Code ends it; Jev picks the feeling |
| 5:00, if still open | Ends quietly as `missed`, no beat | Code |

- CONTEXT's You row gives the facts: "Boop wished for a pet 70 min ago
  (while you were here); still waiting." The steering judges: the sad
  mood's meaning gains "a wish left waiting about an hour while you were
  here", and the "leaves for" lines of the calm moods gain it. Whether a
  long-ignored pet wish is sad or lonely is Jev's, by mood and memory.
- The reason when it reacts: "Boop wished for a pet an hour ago.", on
  the board "wish: 1 h".
- Sad fades as it does now; while the wish is open a later check-in may
  make it sad again. A win may cheer it up; only you meet the wish.
- After a miss, how soon another comes is Jev's.

## Memory keeps the pattern

- Each miss's event says how long you were at the Mac while it waited,
  so a day away doesn't read as neglect.
- CONTEXT's Today row says only today's: "Boop's wish today: met." No
  count over several days and no new store: the written memory carries
  the pattern.
- Wish events are notable lines in the day's journal, so the night's
  writer sees them and may write a You and Boop line: "You
  always pet Boop when it asks.", "You've missed Boop's wishes three
  days running." Jev reads it as MEMORY, so a neglected buddy leans
  sulkier and needier, a loved one warmer.

## What it replaces

- The "pet me?" ask (`asks.md`, `[pet lonely touch daily]`) and its
  follow-ups: the pet wish is it.
- The fixed "lonely after 2 h worked with no touch" cause in the moods'
  steering: an ignored wish is now the way there, and sad or lonely is
  Jev's. Lonely after 20–40 h away stays.

## Several buddies

Each buddy has its own wish. A stroke meets the stroked buddy's;
push-to-talk the named buddy's, or every buddy's when you name none; an
agent interaction meets every open `work` wish.

## The build

| Piece | Change |
| --- | --- |
| Core | `Core+Wish.swift`, on the shape of `Core+Hush.swift`: `Wish { kind, since, waitedMs, countedTo }` per buddy; a new `Event.Kind.wish`, `wish_start` (the kind as `specific_type`) and `wish_end` (`met`, `gaveup`, `closed`); `replayWish` on launch; the wait grows in `advance(to:)` only while you're here, it's awake and nothing needs you; at 3 h `wish_end gaveup` and the rule's reaction `wish_gone`, which wakes Jev; on `newDay` `wish_end closed`, quietly |
| Rules that meet it | pet: `gesture` `stroke`. chat: `said`. work: a `turn_start` from a prompt you sent, or a `needs_you_end` after you answered. Then `wish_end met`, the rule's reaction `wish_met` through the board's queue, and the event wakes Jev |
| React output | the three options in the sign question, with the gates above |
| CONTEXT | the You row: "Boop's wish: a pet, waiting 70 min while you were here.", "no wish yet today"; the Today row: today's only |
| Reason | rows for made, met, waiting and gave up |
| Memory | wish events as notable journal lines; no new store |
| Wire (LinkKit stays generic) | `state.wish`, reactions `wish_met` and `wish_gone`; the firmware draws the thought bubble with three icons, the fulfilment animation (sparkle, bounce, the icon pops into a heart) and the fade |
| Pack (SlimeBuddy first, Pixel's lane text too) | `asks.md` lines `[wish pet] pet me?`, `[wish pet met] <3` and the same for chat and work, no new file; the pet ask removed; sad, lonely, calm and comfy steering lines |
| Evals (`--only` the new ones, no full run) | made at a morning check-in; met by a stroke → happy or comfy; waited an hour at the Mac → sad; away all day → not sad; missed three days → MEMORY's lean; `work` not offered mid-turn |
| Board's checks | goldens, the simulator, the mirror rebuilt, `make -C internal demos ALL=1` (the state changes what the board gets) |
| Tests that pin the numbers | one open, 3 h give-up, 5:00 close, the pauses |
| Docs | CLAUDE.md Words (`wish`), `documentation/architecture.html`, `characters/CHARACTER.md`, `linkkit` docs only if the protocol changes, `internal/EVALS.md` |

Order: the core, wire and pack lines with scripted tests; then the
firmware; then the steering and evals.

Timings to tune by eval and feel: about 1 h before sad (steering), 3 h
give-up (code).

## After the first build (decided 2026-11-01)

The first build on `wish` differs from the above in three places:

- **When a wish comes.** Replace the idle Example ("no wish yet today" →
  "pet me?") with guidelines: what makes Boop want something and when it
  wouldn't, and let Jev's own judgment pick the moment. The owner prefers
  guidelines to Examples: Examples cost context. Keep them short, and
  measure: a wish on most days, not at the first idle check-in every
  time. Code has no daily cap, so the guidelines carry how often: about one a day.
  Built as a guideline in PERSONALITY and a line in the sign question ("With
  no wish yet today and half an hour or more of quiet, a wish fits best.");
  only an idle check-in hears "and the day's half gone".
- **Sad or lonely.** Keep the mood graph as it is. Comfy and lazy going
  lonely at an ignored wish is fine, as long as the mood does move, so
  evals check that it moves, not which. Lonely's "rare" wording must not
  block it.
- **Giving up.** `wish_gone` gets a small silent body beat, a sigh and a
  slump of about a second as the bubble fades, played at once by the
  firmware. The feeling after it stays Jev's.

## Teaching what meets a wish (decided 2026-11-01)

A new owner doesn't know Boop can be stroked or talked to, so the wish
teaches it, with no tutorial and no new concept.

- **Any touch meets a pet wish:** a stroke, a tap (`poke`), a nose boop or
  a tickle; not a shake, a pick-up or face down. The heart always pops. A
  stroke keeps its bigger answer, its own gesture's.
- **The first time, the wish shows how.** Until you've met a kind once,
  its sign says more, in the pack's words, and the bubble's icon moves (a
  hand sliding across, a dot pulsing). After that, the plain sign and a
  still icon. What's kept: a "done once" for each kind, in the key-value
  store, as the asks' records are; `state.wish` carries whether to show
  how, so the board keeps nothing.
- **The chat wish is offered only once push-to-talk works:** the
  recognizer and the mic both authorized (`Talk.swift` already checks
  this). Boop never gets sad over a wish you couldn't answer.

Tests pin which touches meet it, that "done once" ends the showing how,
and that chat isn't offered unauthorized.

These two sections are built. A chat wish already open when you take back
the mic's authorization still waits and can give up: nothing rechecks it.
