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
engine (`render/gel/`), drawn over the body checkpoint 5 of
[character-engine.md](character-engine.md) put on the rig; the body's
answer to a word is a push on the engine's springs (`Engine::jolt`),
which the rig's pose still adds to, not a rig clip. It takes the place of the working tier's "at it" gags in
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
name from AgentHooks (below, The words for commands); the rest of the
vocabulary is there today.

## The words

| Call | Word |
| --- | --- |
| Read, Grep, Glob (and Codex's) | `read`, `grep`, `glob` |
| An edit | `edit +18 −2` (an edit to a doc: `docs`) |
| A command | its program: `grep`, `sed`, `git log`, `pytest` (below, The words for commands); its topic when it has one (`tests`, `build`, `deploy`) |
| A web fetch or search | `web` |
| An MCP tool | its server's name: `linear`, `slack` (below, Custom tools) |
| Any other tool | its name, split: `send message`, `skill` |
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
  anyway: a `calls` key with a lane for each working session, `[slot,
  calls, word, project]` (`"calls":[[0,1,"grep","landing"]]`, from
  `WorkStreamTests`), so the board drops a word for each new call it
  counts, a board that reconnects only picks up the count, and four
  calls a second don't each cost a `do` and its `ended`. A `state` whose
  only change is a new word waits 250 ms after the last. A word that
  comes forward is a `do` the board's queue times like any reaction:
  `{"t":"do","name":"call","play":"next","ttl":1500,"args":{"a":0,"w":"make","as":"bonk"}}`
  (`n` with a combo's count), whose short `ttl` drops it if it can't
  play while it's news. The `state` key and the `do` name are the
  app's, so LinkKit doesn't change. The error reaction stays the
  core's, for the brain's history; a board whose `hello` says `call`
  gets the bonk in its place.
- **The brain hears no more than it does today**, plus one clause
  (below, What the brain hears).

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
| P0, always | A failure (a bonk on the ladder; a lookup's shrug; a timeout; your NO); a check's result | Always: it cuts a P1 or P2 that's playing, and waits up to 1.5 s behind another P0, else is dropped |
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

## The words for commands

Over the six hours before 21:00 on 2026-10-24, the owner's Claude
sessions made 2,284 `Bash` calls (counted from Claude's own session
files), against 105 `Read`s and 53 `Edit`s. Their first programs: `sed`
483, `python3` 422, `grep` 361, `cat` 97, `ls` 84, `make` 68, `git grep`
62, a `for` loop 51, `boopctl` 47, `git log` 41. So:

- **AgentHooks adds a `program` to a shell call's event**: its first
  command's program, after `cd` and the wrappers its topic matching
  already skips, with the subcommand of the programs that have them
  (`git log`, `git push`, `npm i`, `gh pr`, `docker run`). Only from a
  closed list of about 80 developer programs, and the person's own
  (`~/.agent-hooks/words.json` beside `topics.json`:
  `{"words": ["boopctl", "boopdev"]}`); anything else is `run`. A script's
  name never leaves unless you listed it, and nothing after the program
  does.
- **The family picks the gag, the word labels it:**

  | Family | Programs | Gag |
  | --- | --- | --- |
  | Look | `cat`, `head`, `tail`, `less`, `ls`, `tree`, `wc`, `sed -n` | Reading glasses, the page on the monitor |
  | Search | `grep`, `rg`, `find`, `fd`, `git grep` | Eyes following, the magnifier |
  | Edit in place | `sed -i`, `perl -pi` | A landing, like an edit |
  | Script | `python3`, `node`, `ruby`, a `for` loop | Stirring a pot |
  | Git, reading | `git log`, `git diff`, `git status`, `git show` | Leafing back through pages |
  | Git, writing | `git add`, `git commit` (a stamp), `git push` (a small rocket), `git merge` | Its own each |
  | Files | `mkdir`, `mv`, `cp`; `rm` (a poof) | A box moved |
  | Network | `curl`, `wget`, `gh` | A paper plane |
  | Checks | the topic: `tests`, `build`, `deploy` | Above |

- **A run is a combo, not a flood.** The same word from one agent, each
  within 3 s of the last, counts up over the falling words (`sed ×12`)
  and comes forward at 5, 10 and 20, so 483 `sed`s read as a few combos.

## Custom tools

- **MCP tools** (`mcp__linear__create_issue`) say their server's name,
  `linear`: the name you gave the server, not your data. AgentHooks
  already kinds them as MCP; their gag is a phone call.
- **Tools Boop doesn't know** (`Skill`, `SendMessage`, a new agent's own)
  say their name, lowercased and split (`send message`): a tool's name
  is the agent's vocabulary. They land plainly.
- **Your own commands** are `words.json`'s (above); **your own checks**,
  `topics.json`'s, as today (`{"tests": [["just", "check"]]}`).

## What the brain hears

Today, of every call, the brain hears a line only for a notable one: a
check failing, or passing after it failed
(`TranscriptView.toolDone`); a call with no line never wakes it. The
rest are counted into the turn (its calls, failures and lines), which
its finish and heartbeat lines say. In the session above, none of
the 229 calls was a line: no check failed.

The stream keeps that, and adds no wake and no line per call:

- What comes forward is a `did` by the core's rule in the transcript,
  as the error reaction is today; the background words are derived
  from the calls already there and add nothing.
- The view counts the moments that hit (bonks, a timeout, your NO; not
  a check's failure, a line already) into the turn's counts, and the
  next line that wakes the brain anyway, its working heartbeat or the
  finish, carries one note about those since a line last did:
  "Failed commands hit Boop in the face twice." So the brain can
  answer the run ("ow, two") at a pass it was having anyway. Played
  over every eval scenario, no prompt changed.
- **A setting turns it off**: Settings, Sound, Work stream
  (`settings.json`'s `workStream`, on unless false).

## Checking it reaches the board

A fixture from the owner's session (the 229 calls' kinds, topics,
results and timing, no commands) replayed through
`Boop --headless --brain scripted` to the simulator over its cable,
checking: every call's word reaches `state`'s `calls`, at most four
`state`s a second for them; every P0 is a `call` `do`, and none is
dropped but by its `ttl`; the brain's passes are the same with the
stream on and off. `dbg.state`'s `rx` counts what the board read.

## To decide

1. **Which words leave the agent.** Recommended: the program from a
   closed list and your own (The words for commands), and an edit's
   file extension (`.swift`). Real file names and search
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

1. [x] **A lookup that exits 1 no longer plays the error face**
   (`Core.fold`'s `.callEnded`: topic `inspect` with `exit_code`; in the
   owner's session four lookups that matched nothing played it).
2. [x] **AgentHooks** (its own repository, first): `program` from the
   closed list and `words.json`, and the file extension. Pushed on its
   branch `work-stream-program` (749f05f), and Boop bumped to it; to
   bump again to its squash-merged commit once the pull request merges.
3. [x] **The Mac:** the core's call rule (`WorkStream`: the word, the
   priorities and the slot, the ladder, the combo), the `calls` key and
   the `call` `do`, the note the brain hears, the setting, and
   `WorkStreamTests`, which pin each number above. Still to do: the
   replay of the owner's session to the simulator (Checking it reaches
   the board), once the board plays it.
4. [x] **The board**, on the gel's own engine: the lanes' names and
   their words behind the body (drawn after it onto the background only,
   at most eight at once), the word forward flying at the body's
   anchors, and `Engine::jolt` for the body's answer (slime-blob/
   CONTINUITY.md, The work stream). Measured on the AMOLED board: 35 fps
   off, 31.8 with one busy agent, 28.5 at three lanes' worst.
5. [x] **The gags**, a move each (`render::CallMove`): the families'
   own (the magnifier, the pot, the stamp, the rocket, the puff, the
   paper plane, the phone, the page, the little ones), the hit's dizzy
   eyes, stars, helmet and throw, the shrug, the deletion swallowed, the
   hail and its late umbrella, confetti, the combo, the build's tower
   (stacking, its flag, its fall on a failed build, `topple`), and the
   monitor answering (spinner, count, tick, cross, crack, the page,
   an edit's bars, the globe), its to-do bar, the turn's clock and a
   thought cloud after 20 s with no call. Checked on the board:
   `boopctl run` draws all 27 of `stream.jsonl`'s shots as the
   simulator does. Still to come: the whole turn's moments (compaction's
   cube, buried by a full context, frozen by a rate limit, an interrupt,
   the finish gathering the pile), which need the Mac to send them.
6. [x] **A demo** (`characters/boop/demo/work-stream.jsonl`: two
   sessions, lookups, a lookup that finds nothing, a failed script twice,
   a big deletion, a failing then passing test run). Played headless, its
   transcript's words forward are the script's: two arrivals, a shrug, a
   bonk and a harder one, the deletion swallowed, crossed fingers, hail,
   crossed fingers, a pass. Its commands name their programs as agent-hook does
   (`Program.word`).
   Still to come: the Studio's preview of each gag in every mood.

## The mock

A hand-drawn canvas mock of ten seconds of it, not the engine, was
shown to the owner on 2026-10-24: two agents' background words, a run
of greps the eyes follow with a combo, `edit +18` soaked up, a search
that finds nothing and a shrug, `tests` then FAIL hail and a late
umbrella, `exit 1` hitting its face (stars, spiral eyes, a shake), a
`−400` that shatters and is eaten, and PASS confetti. It isn't kept in
the repository.
