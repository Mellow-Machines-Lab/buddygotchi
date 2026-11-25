# The brain: who thinks for Boop

Updated 2026-11-24. How Boop decides what to feel, say and remember, with no
key and no bill. It says what each layer is for and how Boop should behave;
the code and [architecture.html](../architecture.html) say how.

## What is built

On the `brain` branch, not merged:

- Built: layer 1, the rules brain (`RulesBrain`, `MoodMap`). Key or none,
  it answers every pass, and the mood moves only as the mood files say. All
  30 must scenarios pass with it (`boopdev eval --brain rules`).
- Built: the dream by your own agent tool (`AgentToolModel`), behind
  Settings' "Your agent helps Boop think", on by default. On held-out
  questions it answered 61 of 64 right, against Apple Intelligence's 55
  (`boopdev memory gates --held-out --model agent`).
- Built: layer 2. The brief (`agent-brief.json`, `AgentBrief`), the result
  card's `boop_lines`, `you_seemed` and `remember`, Boop's pick of a line
  after the finish (`MomentRule.offeredLine`), the read of you as a mood
  fact, and the note judged by the dream.
- Built: layer 4, skits (`Skits`, the pack's `skits`). It replaces the
  babble plan. With them the invite (`InviteLedger`) and the remark
  (`Remarks`, against your usual, `Normals`).
- Built: Jev on top of the rules, in five seats (`SeatedBrain`).
- Not built: the dream writing tomorrow's lines.

## The aim

Every Boop has its whole personality from the first minute. A buyer adds no
key, makes no account and pays nothing more. And Boop feels like it thinks:
it says something true about this turn, it remembers you, and its words do
not run out.

## Four ideas

1. **Rules answer at once.** Anything that follows from the facts is decided
   by code, in under a tenth of a second. Most of what Boop does is this.
2. **Borrow the thinking that is already running.** A coding agent is a
   strong model, it has read the whole turn, and the buyer already pays for
   it. While it works, it thinks for Boop too.
3. **Write ahead while asleep.** What cannot be written in the moment is
   written the night before, and rules deal it out the next day.
4. **Boop keeps the judgement.** An agent offers words and facts. Boop's own
   rules decide what to show, and how it feels about it. Boop is on your
   side, not the agent's.

## The layers

| Layer | What it does | When | Wait | Needs |
| --- | --- | --- | --- | --- |
| 1. Rules | The mood and its fades, the face at every event, sizes, moves, touches, locks | Always | None | Nothing |
| 2. The calling agent | Offers Boop's line for the turn's end, says how you seemed, notes one thing worth remembering | While an agent's turn runs | None | The card tools the agent already calls |
| 3. The dream | Writes Boop's memory, and fresh lines for the next day | While Boop sleeps | None | The buyer's own agent tool, run by Boop |
| 4. Skits | Says a word at the few moments that call for one, each from takes of its own, and may invite one touch after | A long win, a failure, a fix, you back | None | Recorded takes on the board |
| On top: Jev | A finer pick in five seats, for people who add a key | When a key is there and it answers in time | 0.3 s, never waited past the pass | A key |

Each layer works without the ones below it in the table, and Boop is whole
with only the first. A later layer adds life; it never adds a duty.

## Layer 1: rules

Rules decide everything that is plain from what happened.

- **The mood map stays as it is.** The pack's seven moods, cross's three
  levels, each mood's fade and what holds it (`character.json`), and what
  each mood's file says keeps it, ends it and moves it, and to which mood
  (`steering/mood/`). The rules follow that map; they do not replace it. A
  move the map does not name does not happen.
- **The map has one source.** The mood files stay the place where a
  character's moods are written. The rules are built from them, and a test
  holds each move they name.
- **Each event has a small set of fitting faces,** by the mood, the outcome
  and the turn's length. Rules pick one, and not the one shown last.
- **Size and move are facts.** A finish is as big as its turn was long, and
  its move follows its outcome. This is so today.
- **A touch is answered whole, at once.** No half of the answer waits on a
  network.

How it should feel: steady and readable. The same day gives the same Boop,
with enough variety that two finishes in a row do not look alike.

## Layer 2: the calling agent

While a turn runs, the agent is the smartest thing in the room. It already
hands Boop a card at the start and at the end of a turn. Through those same
two calls it also plays a part in Boop's mind.

**What the agent is told,** once, as its session starts: what Boop is, who
this Boop is (its personality), and what Boop remembers of you. When it
reports its status, it hears Boop's mood now.

**What the agent gives back,** with the turn's result. Each part is
optional:

| The agent gives | Boop does with it |
| --- | --- |
| Two short lines Boop might say about this turn, in different feelings, one of them doubtful | Picks one by its own mood and by what it saw (a failed check, a long fight), or picks neither. Holds it up at the finish |
| How you seemed this turn, from a short list | Counts it as a fact the mood map already knows ("the person sounding frustrated"). The map decides the move, or none |
| One plain sentence about you or your work that is worth keeping | Keeps it for the dream, which decides whether it becomes a memory |

How it should behave:

- **A full sentence at the end of real work.** "third try. it stuck this
  time." It is about this turn, in Boop's voice, and at most 40 characters on
  the board. The Mac's popover may show a longer one whole.
- **Boop is not the agent's mouthpiece.** The agent never tells Boop to be
  proud of the agent's work. It offers; Boop chooses. A turn that failed its
  checks does not get the proud line, whatever the agent wrote.
- **Short turns are left alone.** A quick answer carries none of this. The
  agent is told so, and the fields ride on a call it makes anyway, so no turn
  grows by more than a moment.
- **The agent never waits and is never held.** Boop only listens. If the
  agent sends nothing, the rules answer as if it had never been asked.
- **Every ask is made at the session's start,** plainly and once. Nothing in
  a later answer asks the agent for new work: a careful agent would be right
  to distrust that.
- **The agent's words are checked** as a memory's line is: short, plain
  characters, no secret, no order to you.
- **Quiet still means quiet.** On Quiet, on a call or face down, the rules
  that silence Boop today silence these lines too.

## Layer 3: the dream

Boop sleeps when you are away, and it dreams. The dream is where the slow
thinking happens, because nobody is waiting.

- **Who writes it.** Boop runs the buyer's own agent tool (Claude Code or
  Codex) by itself, once, with the day's digest and no tools. Onboarding
  already knows these tools, so the buyer sets up and schedules nothing. The
  run uses a little of the plan the buyer has. It is invisible: it shows in
  no session list and Boop does not see it as an agent at work.
- **What it writes.** The memory: notes about you, your work, and you and
  Boop, from the day's counts, what you said to Boop, and what the agents
  noted. And tomorrow's lines: hellos, musings and answers to a touch, in
  Boop's voice, from what it remembers.
- **How the lines are used.** The next day rules deal them, the one shown
  longest ago first, with no wait. So a quiet moment has something new to
  say, and the first repeat is days away, not hours.
- **When no tool can run.** A long agent turn may be offered the dream at
  its end, at most once a day. Failing that, Boop keeps the memory that code
  alone can count and says the pack's own lines.

How it should feel: Boop knows you a little better each morning, and says
so in words it did not have yesterday.

## Layer 4: skits

This replaces the babble plan: syllable babble was turned down as uncanny.

What Boop says is no brain's question. A skit is one kind of moment that
has takes of its own and always speaks, and a plain rule says when each
plays (`Skits.play`, from the slot the rules read an event as). There are
four:

| Skit | When it plays | What it says |
| --- | --- | --- |
| `win` | A turn of a minute or more done | "Done", "Nailed it", "Ta-da-da" |
| `upset` | A failed turn, the agent giving up, or the third failed check in a row | "Oh no", "Not again"; a swear only when the failures pile up and swearing is on |
| `fix` | A check passing after it failed | "Phew...", "Fixed" |
| `back` | You back at the Mac after a break | "Hello", "Hey" |

- No brain can veto one: when Jev picks no face, the skit plays in the
  rules brain's face for it.
- Every other Moment is silent but your words' reply and a lock's real
  wave, which say their own words. On Quiet a small moment or a finish says
  nothing, as before.
- The takes are the recorded voice's, listed again as the skit's
  (voicegen's `SKIT_OF`): no new recordings, and no board needs a new card.

### The invite

A skit answers "it spoke to me, but what next?" with one touch. After the
`win`, the `upset` and the `back`, Boop may turn to you in a pose and ask
for one touch with its body, never with words: a palm held up for a tap
(it high-fives), its back turned for a stroke (it sighs), a lean in for a
stroke (it purrs). You never talk back.

| Skit | Pose | Touch | Payoff |
| --- | --- | --- | --- |
| `win` | `palm` | `tap` | `highfive` |
| `upset` | `back` | `stroke` | `sigh` |
| `back` | `lean` | `stroke` | `purr` |

- It is part of the Moment's `do`: the board plays the body and the take,
  then the pose and the wait, then the payoff or a shrug, and only then
  ends the `do`. With the agent's offered line or a remark after a
  finish, it rides that second Moment, so the pose comes after the line.
- Code asks it, no brain: only of a board that says it plays invites,
  never on a call or while something needs you, at most 10 a Boop day,
  and after 3 misses in a row of a pose only every second time
  (`InviteLedger`, a fold of the transcript). The wait is 4 s, and 12 s
  the very first time, so everyone learns the loop once (no longer, so the
  longest Moment, the wait and the payoff end inside the link's 60 s grace). The pack's word
  by the place to touch ("tap", "pet") shows until a pose was answered 5
  times, and again after 3 misses in a row.
- The touch that answers is the invite's: in time, or late within 30 s of
  a miss, it does what that touch does, once (care XP shown as "+3 XP", a
  pet wish met, a stroke's soothing). HISTORY reads how it ended as one
  plain line; it wakes no pass.

### The remark

Boop knows you when it notices how now differs from your own usual, many
times a day: "that was fast", "you're early", "5 today". Code counts your
usual (`Normals`, a fold of the transcript: your turns' lengths, the hour
you first show up, your breaks, your wins a day and your best run), and a
plain rule picks the one remark (`Remarks.pick`). No model is involved.

| Remark | On the skit | When |
| --- | --- | --- |
| `fast`, `slow` | `win` | The turn took under half your median, or over twice it (10 turns kept) |
| `run` | `win` | The 3rd win in a row, or a new best run of 4 or more |
| `count` | `win` | Today's wins just reached 5 or 10, or passed your best day of the last 14 (5 days kept) |
| `early`, `late` | `back` | Your first time today, 45 minutes or more off your median first hour (5 days kept) |
| `soon`, `longBreak` | `back` | Away under half your median break, or over twice it and under 4 hours (5 breaks kept) |

- It rides a skit that plays anyway, so it adds no interruption: at most
  one skit in three carries one, `upset` and `fix` never, none on Quiet,
  and none while your usual is empty.
- It's text, the pack's words (`signs.md`'s `[remark …]`): on a `win` a
  low Moment after the finish, unless the agent offered a line, which
  wins; on a `back` the sign, over the dream's, unless it's a special day's. No
  take says these words yet.

## Jev, on top

Jev stays for people who add a key. The rules answer every pass first, at
once and with no network; Jev is asked the same questions, and may replace
the rules' answer in five seats:

| Seat | The rules' answer | What Jev adds |
| --- | --- | --- |
| The mood | The mood map | It reads the whole day |
| The face | The slot's faces, as the mood colours them | The face that fits this turn |
| A reply to your words | Word matching | What you meant |
| The sign, on every pass that asks one: a reply's, a prompt's caption, the idle beat held up, an answered ask's, the dream's | A line that fits, by rule | The line that fits this moment |
| Which take a skit says | None: Voice's pick, the one not said lately | The take that fits this turn |

Three rules hold for every seat. Jev picks from the options the rules pick
from. Its answer counts only if it comes within the pass's deadline, is
one of them and is as sure as the output needs (a reply under its floor is
a guess, and the rules' reply stands); slow, failing, absent, unsure or
wrong, it changes nothing a person sees. And no seat vetoes a skit.
Everything else stays the rules': the size, the move, when Boop speaks. The
transcript keeps every pass's answers, whoever gave them, and the pass's
brain says whose it played: `rules`, or `rules+` Jev's id and the seats it
took. A key's owner sees a notice when Jev turns the key down,
runs out of credit or fails three passes in a row; Boop carries on without
it. No screen asks for a key, and nothing is missing without one.

## Who answers what

For each thing Boop does, the first that can answer does.

| Boop does | First | Then | Last |
| --- | --- | --- | --- |
| Feels something at an event | Jev in its seat, with a key, in time | Rules | |
| Says a line at a turn's end | The agent's offered line, picked by rules | A line the dream wrote | The pack's line |
| Says a line when idle, at a hello, at a touch | A line the dream wrote | The pack's line | |
| Says a take at a skit | Jev in its seat, with a key, in time | Voice's pick, by rule | |
| Moves its mood | Jev in its seat, with a key, in time | Rules, with the agent's read of you as one more fact | |
| Remembers | The dream, by the agent tool | The dream inside a long turn | What code counts |
| Replies to your words | Jev in its seat, with a key, in time | Word matching by rule | "huh?" |

## What leaves the Mac

This changes one promise, and the README must say it plainly.

- Boop's personality and its memory of you go into your coding agent's
  context, and so to that agent's provider: the same one that already has
  your code and your prompts. The dream's digest goes the same way.
- Nothing new goes anywhere else. Notes and lines an agent writes come to
  Boop and stay on the Mac. With no Jev key, nothing goes to TypeSafe.
- One switch turns the agent's part off. Then the agent is told nothing of
  Boop's memory, and the dream is code's alone.

## Chosen, and open

| Question | Answer |
| --- | --- |
| Does a buyer need a key? | No. Rules in the box; Jev is an extra |
| Does the agent write Boop's line? | It offers two; Boop picks. To confirm with the trial |
| Do the moods and their map change? | No. Seven moods, the levels, the fades and each mood's moves stay. Rules follow the map |
| Can the agent move the mood? | Only as a fact the map already names. It adds no new move |
| May Boop's memory go to the agent? | Yes, said plainly, with a switch |
| Who dreams? | The buyer's agent tool, run by Boop asleep. A long turn is the fallback |
| Why not the Mac's own model? | Its notes were not good enough |
| Does Boop speak? | A recorded word at a skit, with a caption. Never natural speech |
| A paid speech service? | No. Nothing that needs a subscription |
| Where does a long sentence show? | 40 characters on the board; whole in the popover |

## To check while building

1. **How well do agents play Boop?** How often they send each part, whether
   the lines fit and sound like Boop, whether the notes are true.
2. **Is a dream by the agent tool good?** Its notes beside today's, on a
   real week. And whether the tool runs unseen with only a plan's login.
3. **Does the rules brain hold up?** The eval scenarios, with no Jev.
4. **The provider's terms** for an app that runs a buyer's agent tool.
5. **On the board:** is a skit's word a charm or a noise, and how many takes
   a skit needs so two in a row rarely repeat.
