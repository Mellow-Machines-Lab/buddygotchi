# Agent cards

Updated 2026-11-15. An agent hands Boop a small card and Boop holds it up:
what the agent is on now, and what its turn made. Built on the branch
`agent-cards` (here and in SlimeBuddy), not merged. What's still the owner's
to decide is at the end.

## What a card is

One main thing, large enough to read from a chair, and at most one small
line under it. Two kinds, and no others:

| Card | Main thing (24 characters) | Small line (28) | When it shows |
| --- | --- | --- | --- |
| status | what the agent is doing: "fixing the overflow" | its step and its guess: "2 of 5 · 4 min left" | while its turn runs |
| result | what the turn made: "nav overflow fixed" | one more line: "3 files, 212 tests green" | 15 s after the turn ends |

- The words are the agent's own. Boop cuts them to fit and changes nothing.
- The guess is counted down in whole minutes as the agent gave it and never
  corrected: "4 min left", "any minute now", "2 min over" in red. A result
  with no detail of its own says how the first guess did: "said 5 min, took
  12". How wrong an agent is, is part of the fun.
- A result may carry a link: a web page, or an absolute path.
- A card's words go to the screen, the popover's row and the transcript. No
  line for Jev carries them (`CardsTests` pins it).

## How it sits with everything else

A card is part of Doing, like the work stream. The screen's priority doesn't
change, and the card has one place in it:

1. your hand or voice (push-to-talk, a held finger, face down)
2. needs you
3. a Moment (a finish, a reply, a sign, an ask, a level-up)
4. a work act (the tests, the build, the push)
5. Doing: the work stream, **the card**, the headphones, a pastime

Anything above covers the card, and the card comes back when it's over. So a
finish plays as it does today, and the result card is what's left standing
after it. While a card is held, Boop stands up behind it, the desk is put
away and no pastime is dealt; the work stream's words still fall.

A finished card never has to be put away: it goes by itself after 15 s, or at
once at that session's next prompt. One that finished while you were away
waits, and shows as you come back.

## Several agents

Boop holds one card. Which:

- the card that changed last, but not before the one in its hands has had 8 s;
- a result always gets its turn, since its start is a change;
- a swipe across the card moves to the next (leftwards) or the one before,
  and keeps your choice for 2 minutes.

Dots under the card say how many there are and which this is. The card's rim
is its session's lane colour, the same as its words in the work stream and
its row in the drawer.

## Touch

- A tap on the card opens it on the Mac: a result's link (a web page in the
  browser; a file shown in the Finder, never run or opened in an app), or
  with no link the session's thread, as a row picked in the drawer does.
- A swipe across it changes card.
- A touch anywhere else is Boop's, as ever. A card that isn't drawn can't be
  touched: under the needs-you screen, a sign or a work act, a tap is Boop's.

## How an agent sends one

`boop-cards` is a Model Context Protocol server over stdio with two tools,
`status` and `result` (`CardTool`). Each call is one line on Boop's hook
socket: the tool's arguments as the card kept them, and the agent's
process, so Boop knows whose card it is. Boop holds the line to the limits
again, since anything may write to the socket. It returns
at once, needs nothing back, and works with Boop closed. It can't block or
answer for the agent: it's the same one-way path the hooks use.

A card from a process Boop can't match goes to the only session at work, and
with several at work it's dropped.

## Do agents send good cards?

`internal/tools/cards/trial.py` runs fixed tasks through real Claude Code
sessions and scores the cards. Two rounds, Opus and Sonnet, 20 runs each
(2026-11-15; results in `~/.boopdev/agent-cards/`):

| | Soft wording ("you may") | Firm wording ("in every turn that…") |
| --- | --- | --- |
| Tool server alone | 1 of 10 runs sent a card | 10 of 10 sent a result, 9 of 10 a status |
| And one line in the system prompt | 8 of 10 | 10 of 10 |

With the firm wording, which is what ships in `CardTool.instructions`:

- Every result was true to the turn, including the bad news: "tests can't
  run here" / "needs SERVICE_TOKEN and VPN"; "--json flag added" / "6 new
  tests pass; 2 slug fail".
- Every deploy gave the right preview URL as its link.
- Statuses were short and plain: "fixing slugify", "running the tests",
  "deploying preview". On the six-step task Opus sent 4 with steps, Sonnet 2
  or 3.
- Guesses were given on the longer tasks and were all too long, by about 2 to
  3 times at the start (4 → 1.5 min).
- Sonnet's flaws: a first call with no words (now answered with what's
  missing, and it calls again), capitals, and 5 of 30 headlines over 24
  characters, which Boop cuts at a word.
- Opus's one flaw: a relative path as a link, which Boop leaves out.
- A card costs a turn about one extra tool call each.

So: agents send good cards when the tool tells them firmly, and almost none
when it's optional. Not tried: Codex, Haiku, and very long turns.

## How it's installed

The server goes in and out with the hooks (`CardInstaller`):

- Connecting an agent in onboarding or Settings adds it; disconnecting takes
  it out; Uninstall takes it out of both and deletes its copy.
- At launch, every agent whose hooks are in gets it, so a Boop from before
  cards gets it too, and an entry pointing somewhere else is put right.
- Claude Code: `mcpServers.boop-cards` in `~/.claude.json`, as `claude mcp
  add --scope user` writes it. Codex: `[mcp_servers.boop-cards]` in
  `~/.codex/config.toml`. `~/.claude.json` is backed up once before Boop
  first changes it, as the hooks' files are.
- The entry runs `boop-cards claude` or `boop-cards codex` from the state
  directory's `bin/`, copied there from the app like `agent-hook`.
- Only the everyday Boop installs: `make dev`'s copy, on its own folder,
  hears the cards but never changes the agents' files.
- Its failing is only logged: the hooks are what Boop needs.

There is no switch of its own: an agent that's connected gets cards.

## What's built

- Mac: `app/BoopKit/Cards/Card.swift` (the card, its limits, the tools'
  words, the socket line), `Cards/CardInstaller.swift` (registering it), `app/BoopCards/` (the server), `Core/Cards.swift` (which card, how
  long), `Core/Core+Cards.swift` (whose card, the `state`, the tap), the
  popover's row.
- Wire: `state.card` = `{"a":slot,"k":"s"|"r","t":main,"d":small,"o":1,"at":[index,count]}`;
  the board's `ev` `card` did `next`, `prev` or `open`.
- Board: the engine parses and routes touches (`app/device.cpp`); the gel
  draws it (`render/gel/card.h`).
- Tests: `CardsTests`, `CardInstallerTests`, `test_device`'s card test, the gel's `cards` scenario.

## The owner's to decide

1. **A switch.** Cards come with a connected agent. Add a Settings switch
   only if someone wants hooks without cards.
2. **The finish.** Today the finish plays and the result card follows. If
   cards prove reliable in real use, the result card could be the finish's
   low sign instead of the thread's name.
3. **"Said 5 min, took 12"** shows only when the result has no detail, which
   agents nearly always give. It could take the detail's place when the guess
   was far out.
4. **The to-do card.** A turn with a to-do list and no status card could show
   the item in progress. AgentHooks drops the item's words on purpose, so it
   needs a change there first.
5. **Codex.** `codex mcp list` reads the entry, but no Codex session has
   sent a card yet.
