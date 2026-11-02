# The wish

Updated 2026-11-01. The plan for Boop's one want a day: a need you can
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

No hardcoded trigger. At the moments asks use (an idle check-in, a
working check-in, a finished turn, the dream's telling) the react output
offers one more question, `wish: none | pet | chat | work`, only when:

- no wish is open, and none was made this day (`boopDay`);
- you're at the Mac and the buddy is awake;
- nothing needs you, and it isn't listening or hushed;
- `work` only while no agent is working (else your next prompt meets it
  for nothing).

Jev picks when and which, by mood, MEMORY and CONTEXT. The guide says
about one a day, when it feels like it. CONTEXT's You row says "no wish
yet today", and from midday "no wish yet today, and the day's half
gone": a nudge, not a trigger. Code holds the cap: one a day, one open.

On Quiet a wish is still made, as the icon and the sign, with no sound.

## While it waits

- The icon stays in the strip, beside the count chips, carried in
  `state` (`state.wish`), so the board times nothing.
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
- After a miss, no new wish that day.

## Memory keeps the pattern

- The MemoryReader counts wishes made, met and missed (each `missed`
  with how long you were at the Mac while it waited, so a day away
  doesn't read as neglect).
- CONTEXT's Today row: "wishes met 5 of the last 7 days."
- The night's writer sees them and may write a You and Boop line: "You
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
| Core | `Core+Wish.swift`: the open wish, the rules that meet it, the wait clock and its pauses, the 3 h give-up, the 5:00 close; transcript events `wish` (start, met, missed) |
| React output | the `wish` question, offered only when eligible (the shape of `Asks.askable`) |
| CONTEXT | the You row's wish facts and "no wish yet today"; the Today row's count |
| Reason | rows for made, met, waiting and missed |
| MemoryReader | made, met and missed counts |
| Wire (LinkKit stays generic) | `state.wish`, the met and give-up reactions; the firmware draws three icons, the fulfilment animation and the fade |
| Pack (SlimeBuddy first, Pixel's one-line lane too) | each kind's words; the pet ask removed; sad, lonely, calm and comfy steering lines |
| Evals | made at a morning check-in; met by a stroke → happy or comfy; waited an hour at the Mac → sad; away all day → not sad; missed three days → MEMORY's lean; `work` not offered mid-turn |
| Tests that pin the numbers | one a day, one open, 3 h give-up, 5:00 close, the pauses |
| Docs | CLAUDE.md Words (`wish`), `documentation/architecture.html`, `characters/CHARACTER.md`, `linkkit` docs only if the protocol changes, `internal/EVALS.md` |

Timings to tune by eval and feel: about 1 h before sad (steering), 3 h
give-up (code).
