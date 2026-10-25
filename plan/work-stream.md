# The work stream: the plan (updated 2026-10-24)

While agents work, the board shows what they're doing as it happens:
each agent's tool calls as words falling from its name, and now and
then one word comes forward and the slime reacts to it with its body. A
failed command flies at its face and leaves it dazed; a failing test
run rains FAIL on it; a big deletion shatters and it eats the bits.
Drafted with the owner on 2026-10-24, after testing main: a long
working turn looked the same for minutes, because the desk's typing is
all the gel has before the marathon tier (glance-and-wait.md §3), and
mid-turn the brain wakes only on its heartbeat (90 to 180 s for Boop's
personality) and on notable tools.

**The AMOLED board only.** On 2026-10-24 the owner froze the CYD: it
keeps building, and gets no new features, so the stream, its reactions
and the monitor are the gel's alone. They're built on the gel's own
engine (its gags, occasions and layers, `render/gel/`), not as clips
shared with Pixel, so the stream doesn't wait on checkpoint 5 of
[character-engine.md](character-engine.md), whose reason was one clip
for both faces. It takes the place of the working tier's "at it" gags in
[glance-and-wait.md](glance-and-wait.md) §3; the marathon and the camp
stay, and play over the stream.

## Why words, and why the body

Icons in the background read as wallpaper: they move, and nothing
happens. What makes the stream legible is cause and effect:

- **Words, not icons.** `grep`, `edit +18`, `tests`, `exit 1`: short,
  big, in the sign font. A buyer reads them without being taught
  (product-ideas.md's ground rules).
- **Each word comes from a named agent.** Every agent has a colour, the
  same as its name in the lane and at the top of the screen where its
  words fall from, so two agents read as two streams and how thick each
  is says how hard it's working.
- **The body answers.** A word that comes forward lands on, hits or is
  caught by the slime, and the slime's reaction is about that word. The
  stream is the scene; the creature stays the star.

## The two planes

- **The background.** Every call, as a small dim word in its agent's
  colour, falling from the agent's name behind the body and fading
  before the lane. No sound. At most about 12 on screen; a burst
  thins out rather than piling up.
- **The foreground.** At most one word at a time comes forward, big,
  and plays a reaction: a gag with the word as a prop. The
  rule picks it (below); most calls never come forward.

The needs-you screen clears both. A finish plays over the stream's
last words, which the slime gathers up first.

## What the Mac knows today

Each tool call already reaches Boop's transcript with, from AgentHooks:
the agent, its tool (`Bash`, `Read`, `Edit`, Codex's `exec_command`…),
its topic (`tests`, `build`, `deploy`, `inspect` for a command that
only looks, `docs` for an edit to a doc), the lines an edit adds and
removes, whether it failed and the error's class (`exit_code`,
`timeout`, `denied`, `other`). A turn that fails says why (`rate_limit`,
`overloaded`, `context_limit`, `auth`, `billing`, `network`, `api_error`).
Helpers start and return, compaction, and the to-do list's done and
total come too. Nothing of the command, the path or the output: only
the topic leaves `agent-hook`.

That isn't enough for the words. In the owner's session on 2026-10-24
(four Claude sessions, 229 calls in half an hour) 204 calls were
`Bash`: agents read and search through the shell (`grep`, `sed`,
`git log`) far more than through Read or Grep. With only the topic,
nine words in ten would say `bash`. So the stream needs the program's
name from AgentHooks (To decide, 1); the rest of the vocabulary is
there today.

## The words

| Call | Word |
| --- | --- |
| Read, Grep, Glob (and Codex's) | `read`, `grep`, `glob` |
| An edit | `edit +18 −2` (an edit to a doc: `docs`) |
| A command | its program: `grep`, `git`, `sed`, `pytest`, `swift` (AgentHooks, To decide 1); its topic when it has one (`tests`, `build`, `deploy`) |
| A web fetch or search | `web` |
| An MCP tool | `mcp` |
| A helper | `helper` |
| The to-do list | `✓ 3/7` |
| A failure | `exit 1` for a command (the class, not the code: `exit` alone until AgentHooks gives the code), `timeout`, `NO` for a request you denied |

## The reactions

Each is a gag on the gel's engine with the word as its prop.

**Everyday work**

| What happens | The word | What the slime does |
| --- | --- | --- |
| Lookups in a burst | `grep` `read` `read` | Its eyes follow each word; a long run puts its glasses on |
| Five lookups in a row or more | `grep ×5` | A combo count over the words; dizzy from looking around |
| An edit | `edit +18` | The word drops on its head and it soaks it up, a squash and a ripple, a little bigger after |
| An edit removing 100 lines or more | `−400` | The word shatters, and it eats the bits |
| An edit to a doc | `docs` | Licks a finger, turns a page |
| A web fetch | `web` | A paper plane from the edge, caught |
| A helper starts, returns | `helper`, `done` | A mini-slime runs off with the word and comes back with `done` |
| No call for 20 s mid-turn | `…` | A thought cloud; it taps its chin |
| A to-do done | `✓ 3/7` | A tick drops into a jar that fills |

**Checks**

| What happens | The word | What the slime does |
| --- | --- | --- |
| Tests start | `tests` | Fingers crossed, peeking |
| Tests pass | `PASS` | Confetti |
| Tests fail | `FAIL` ×7 | Hail; it pops an umbrella, too late |
| A build | `build` | The stream's words stack into a tower beside it |
| A build fails | `build ✗` | The tower topples on it |
| A deploy | `deploy` | The word takes off like a rocket; it salutes |
| A deploy on a Friday | `deploy` | It hides, peeking out (the `friday` tag) |

**Failures**

| What happens | The word | What the slime does |
| --- | --- | --- |
| A command fails | `exit 1` | The word flies at its face: a bonk, stars, spiral eyes, then it shakes it off |
| A lookup "fails" | `grep` and an empty `…` bubble | A shrug, not a bonk: a lookup that exits 1 almost always found nothing |
| A timeout | `timeout` | The word falls in slow motion; it taps its foot and nods off, and the word lands on its head and wakes it |
| You denied a request | `NO` | A red stamp slams down; it flinches and looks up at you sheepishly |
| The same agent fails again within 2 minutes | `exit 1` | The ladder: a harder bonk, then a helmet, then it catches the word and throws it back |
| Two agents fail within a second | two colours | A bonk from each side |

**The whole turn**

| What happens | The word | What the slime does |
| --- | --- | --- |
| Compaction | the words on screen | All squashed into a cube, which it sits on |
| The context runs out | the words pile up | Buried to its eyes |
| A rate limit, an overload | the stream freezes | Words hang in the air; it pokes one |
| You interrupt | the stream stops | The words drop, switched off |
| The turn finishes | the pile | It gathers the last words up and eats them, then the finish plays |
| You poke it mid-stream | | The words scatter like startled fish |

The mock (below) showed `✗ 6 failed` and `✓ 42 passed` on the desk's
screen: counts like those are the command's output and never leave
the agent. The board shows only that a test run passed or failed.

## The desk's monitor

The stream says what every agent did a moment ago; the monitor on the
desk says what the one the slime is watching is doing now: the agent
whose word last came forward, its frame in that agent's colour. Its
screen is about 80 by 40 pixels on the AMOLED board, room for one
picture and one short word, not lines of text, so it shows pictures:

| The agent is | The monitor shows |
| --- | --- |
| Reading, searching | A page scrolling past, a magnifier sweeping it |
| Editing | The diff as two bars, green for the lines added and red for the lines removed, to scale |
| Running a command | `>_` and the topic (`tests`, `build`), or the program's name (To decide, 1) |
| Running tests | A spinner, then a big green ✓ or red ✗ |
| Building | A progress bar that crawls and never claims to know how far |
| Deploying | A countdown, 3, 2, 1, and a rocket |
| On the web | A globe turning |
| Waiting on helpers | One mini-slime for each helper out |
| Thinking (no call for 20 s) | A blinking cursor |
| Failing again and again | A crack across the screen that grows with the ladder, gone at the next success |
| Out of context, rate limited | A sad screen: a frown and `zzz` |

Along its bottom edge, the to-do list's progress (`3/7` as a bar), and
in a corner the longest turn's clock, amber from the marathon tier.
When the agents go idle, the monitor runs a screensaver through the
fidget and set-piece tiers and switches off at `doze`. Like the words,
it shows only what the Mac already knows: no counts from a command's
output, no file names.

## Who decides what

The architecture's split, applied:

- **The Mac's core decides what.** A rule in the core turns each call
  into its word and decides whether it comes forward and as which
  reaction: the failure ladder, a combo, the first call of a turn, a
  check's start and end, a big edit, a helper. It's a plain rule, like
  "needs you": no brain, and at once.
- **The board decides when**, as LinkKit's queue does for every
  reaction: a word that comes forward while another plays waits briefly
  or drops to the background; the needs-you screen and your touches go
  first.
- **The wire: `state` for the background, a `do` for the foreground.**
  The background rides `state`, which the Mac sends on every change
  anyway: a `calls` key with each agent's newest few words and a
  counter, so a board that reconnects catches up and four calls a
  second don't each cost a `do` and its `ended`. A word that comes
  forward is a `do` the board's queue times like any reaction:
  `{"t":"do","id":51,"name":"call","play":"next","ttl":1500,"args":{"agent":1,"word":"exit 1","as":"bonk"}}`,
  whose short `ttl` drops it if it can't play while it's news. The
  `state` key and the `do` name are the app's, so LinkKit doesn't
  change.
- **The brain hears nothing new.** No call wakes it that didn't
  before. It can still say something about a streak with a sign on its
  heartbeat ("again??"), from the lines it already gets.

How the core picks, and how the board flies a word, is the next
section.

## How a word is made, and which ones hit

**A word's life.** A call has two hooks: its start (`PreToolUse`) and
its end (`PostToolUse`, or `PostToolUseFailure` with the error's class).

1. At the start the core makes the word (the table above) and sends it
   in the background: it falls from its agent's name while the call
   runs. An edit's lines are known at the start (`lines_added`,
   `lines_removed`), so `edit +18` is whole at once.
2. At the end the core knows how it went, and decides whether the call
   comes forward and as which reaction. If its word is still falling,
   that same word leaves the stream: it brightens, grows and flies at
   the slime, red if it failed. If it has already fallen out of sight
   (a long build), a fresh one launches from the agent's name.

A check also comes forward at its start (`tests` → fingers crossed),
since the wait is the joke.

**Which come forward.** Every call has a priority:

| Priority | Calls | Comes forward |
| --- | --- | --- |
| P0, always | A failure (a bonk on the ladder; a lookup's shrug; a timeout; your NO); a check's result; compaction; a turn's error | Always: it cuts a P2 that's playing, and waits up to 1.5 s behind a P0 or P1, else is dropped |
| P1, notable | A check's start; an edit of 100 lines or more; a helper's start and return; the first call of a turn; a combo reaching 5, 10 or 20 | When the slot is free, or frees within 1.5 s |
| P2, ambient | Anything else | Only when the slot is free, 8 s since anything came forward, and 30 s since this word did |

One slot: a reaction holds it for about 2.5 s. The ladder counts one
agent's failures in the last 2 minutes: the first a bonk, the second a
harder one, the third a helmet, the fourth and on caught and thrown
back. A combo is the same word from one agent, each within 3 s of the
last; a lookup that exits 1 (topic `inspect`, `exit_code`) is a shrug,
never a bonk.

**Played over the owner's session** (2026-10-24, 20:33 to 21:02, the
transcript's 229 calls from four sessions, by a throwaway script): 79
came forward, about one every 22 s: 8 P0, 28 P1 and 43 P2. For example:

| Time | Call | Priority | What plays |
| --- | --- | --- | --- |
| 20:36:44 | `Edit`, 18 lines added | P2 | `edit +18` lands and is soaked up: nothing had come forward for 8 s |
| 20:39:01 | A session's first call of a new turn | P1 | `arrive`: the word drops in from that agent's name |
| 20:39:06 | `Bash`, `inspect`, failed `exit_code` (a `grep` that matched nothing) | P0 | `shrug`, where Boop today plays its error face |
| 20:39:41 | `Bash`, topic `build`, its start | P1 | The build's words start stacking |
| 20:40:06 | `Bash`, failed `timeout` | P0 | `timeout` falls in slow motion |
| 20:40:08 | The build ends, not failed | P0 | `built ✓` |

No command really failed that half hour, so the ladder never climbed:
every failure was a lookup or a timeout. 39 of the 43 P2s said `bash`,
which is why the program's name comes first.

**Where a word flies, on the board.** The core sends only the word, its
agent and the reaction (`do`'s `args`); the board flies it:

- Each agent has a column: with `n` agents, their names sit at
  `x = W·(i + ½)/n` across the top, and their words fall within ±90 px
  of it at 110 to 160 px/s, on the layer behind the body. A word whose
  column crosses the dome passes behind it and comes out below it:
  "through the body" is the layers' order, nothing more.
- A word that comes forward flies to an anchor the gel's painter
  reports each frame (`rig::Anchors`): between the eyes for a bonk, the
  crown for a landing or a shatter, beside the head on its agent's side
  for a shrug. It aims at the anchor's position every frame, so it hits
  a body that's moving, and its flight has a fixed length (about 350 ms
  for a bonk, 500 for a landing); the impact, at the flight's end,
  starts the gag (the squash, the ripple, the stars).

## To decide

1. **Which words leave the agent.** Today, only the vocabulary above,
   which says `bash` nine times in ten. Recommended: add the program's
   name (`git`, `pytest`, `swift`: the first word of a command after its
   wrappers, which AgentHooks' topic matching already finds) and an
   edit's file extension (`.swift`), in AgentHooks, as fields of the
   event. Real file names and search
   patterns would read best but are what someone walking past the desk
   could read; if ever, they're a setting that's off by default, and
   they go through the Mac's scrubber.
2. **On by default?** Recommended: on, with a setting to turn it off
   (the stream, not the reactions to finishes and needs-you).
3. **Sound.** Recommended: the background never sounds; a word that
   comes forward sounds as a reaction does, at your volume.
4. **How thick.** About 12 background words at once, and one word
   forward every 20 s or so. To try on the board.

## The order

1. **Now, small and apart from the rest:** a lookup that exits 1 no
   longer plays the error face (`Core.fold`'s `.callEnded` plays
   `Core.error` for any `exit_code` today; in the owner's session four
   lookups that matched nothing played it).
2. **AgentHooks** (its own repository, first): the program's name and
   the file extension, if the owner takes decision 1.
3. **The Mac:** the core's call rule (the word, the priorities and the
   slot, the ladder, the combo), the `calls` key and the `call` `do`,
   tests that pin each number above, and evals; a headless run prints
   each word and what came forward.
4. **The board:** the background layer behind the body (pre-drawn
   words, one sprite per word, never typeset per frame), measured with
   `boopctl ping`'s `draw_us` (the gel with a hat already draws at 27
   to 30 fps).
5. **The reactions as gags**, most frequent first: the arrival, the
   shrug, the landing, the check's start and result (crossed fingers,
   hail and umbrella, confetti, the tower), the bonk and its ladder;
   then the rest. Then the monitor.
6. **A demo** (`characters/boop/demo/work-stream.jsonl`: two agents, a
   run of lookups, an edit, a failing then passing test run, an exit 1
   twice, a big deletion) and the Studio's preview of each reaction in
   every mood.

## The mock

A hand-drawn canvas mock of ten seconds of it, not the engine, was
shown to the owner on 2026-10-24: two agents' background words, a run
of greps the eyes follow with a combo, `edit +18` soaked up, a search
that finds nothing and a shrug, `tests` then FAIL hail and a late
umbrella, `exit 1` hitting its face (stars, spiral eyes, a shake), a
`−400` that shatters and is eaten, and PASS confetti. It isn't kept in
the repository.
