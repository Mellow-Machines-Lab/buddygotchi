# Product ideas: the running list (updated 2026-11-01)

The owner's brainstorm for making a single buddy more fun, interactive
and useful, and what's decided about it. What's built is in the code and
[documentation/architecture.html](../documentation/architecture.html);
what's next to build is [TODO.md](TODO.md).

## Ground rules from the owner

- **Built for people who buy a ready-made Boop**, not people who flash their own.
- **One buddy first.** Several buddies are for demos for now.
- **Everything on the buddy.** No phone, nothing outside the desk.
- **A Jev key is fine for now.** The aim is to ship with a rules brain
  built from the evals, and grow into Jev for the richer things. So
  keep reactions as data in the pack (Examples, phrase tables,
  templates) that either brain can use.
- **Nothing that keeps the Mac's mic on.** The orange dot would never go away.
- **Nothing that routes or touches approvals.** Keep v1 simple.
- **Nothing a buyer has to be taught.** The screen says what to do, or a
  touch does the obvious thing.
- **Every feature lands with a demo and evals** that cover what's
  expected. The owner audits the evals from time to time.

## Built

The first list's eleven items are built: idle agents and BOOT opening
the next one, frantic with more agents, time of day, Fridays and day
counts, the holidays (the starter set and the in-jokes), pastimes that
grow with time in a look, a demo and evals for every feature, opinions
in the steering, touch and motion on the AMOLED, and the agents'
drawer. Helpers as minis were cut (calm work), and the diary became the
dream and the written memory.

## Next ideas

- **Regional holidays** by the Mac's region (Thanksgiving, Diwali,
  Hanukkah, Eid), and a table of years for dates that move (Easter,
  Diwali, Eid). Open: which regions buyers come from.
- **The gel's art for the in-joke tags**: `aprilfools`, `piday`,
  `may4` and `friday13` are sent, and the gel draws none of them.
- **Growth's props:** designs gated by the stage tags (a plant that
  grows by stage, hobbies with age), and stage-tagged trick lines in
  `replies.md`.
- **The studio's tag picker and time-in-look slider** for designs with
  `when` or `after`, and its preview of each work-stream gag in every
  mood.
- **More work-stream gags:** a to-do tick into a jar that fills, hiding
  at a Friday deploy, words scattering at a poke mid-stream, a timeout
  that makes it nod off, glasses on a long lookup run, the monitor's
  screensaver through the idle tiers.
- **More `show` answers** for a reply, as the drawer is for "how many
  agents": today's to-dos.
- **Asks with no new code:** a nickname for you (an ask filling a
  `{you}` word), a Friday shipper teased on Fridays, a cuddly Boop that
  leans into your hand, a trick with permission.
- **Lonely's own voice takes**: it borrows sad's, which may sound too
  heavy.
- **A better writer for `memory.md`:** Apple Intelligence edits poorly,
  so the checks pass few new notes and the memory grows slowly.
- **The CYD's pixel face, if it thaws:** design-to-design blinks and
  cuts, hats that swap at once on a tag change, no shared tear or sweat
  part.

## Decided (2026-11-01)

The simplifying audit's calls that bound what comes next: several
buddies, the CYD and real-agent demos stay; the move stays Jev's, as
does the poke hold; moods fade in the prose, with the hourly heartbeat;
the counted memory (rows of counts a day, traits latched by rule) is
skipped for now; and the ordinary-versus-dramatic split waits.

## Maybe: liked, or still open
- **What it needs, at a glance:** "needs you" shows whether it's a
  permission, a question or a plan to review, by its kind only, never
  the command.
- **Quiet on calls:** when an app is using the mic or camera, its knocks
  turn visual and its sounds wait.
- **Shipped!** An agent pushes, opens a PR or deploys, and gets the
  biggest celebration. Only the category leaves the Mac's own
  classification.
- **Hatching on first run:** an egg on the board until setup, wobbling
  when the Mac finds it, hatching when you name it. That's day 1.
- **Shiny moments:** about one in 500 variations is rare (golden, a tiny
  hat), something to show people.
- **Transitions out of idle** (liked): a short animation in place of a
  cut, e.g. getting up and rolling up its sleeves when work starts,
  sitting back when it ends. The wake-up already does this coming out
  of asleep.
- **Out of juice:** an agent hits its usage limit and Boop slumps.
  - **Maybe detectable.** A failed turn's hook carries an error class,
    and eval `03` already feeds `rate_limit`.
  - **Not the reset time.**
  - **Unconfirmed:** that a plan's limit arrives as `rate_limit`.
    Check it the next time one hits.
- **Your birthday,** set in Settings if you want one.
- **Stuck sense:** the same test failing five times in a row makes Boop worried.
- **"Waited on you" as a daily number.**
- **Long-turn clock:** "api · 14m" under the face after about 10 minutes.
- **"You're absolutely right!"**: Boop rolls its eyes at the agent's
  stock phrases (a steering Example; the last message's reading, fawning, goes to Jev).
- **Quieter at night by itself.**

## Wild: new ways to interact (2026-10-21, not yet discussed)

- **Parcels** (liked, but hard to build). Each idle agent is a parcel at
  Boop's feet, and "needs you" is one that rattles. A BOOT press: Boop
  picks one up and carries it to you, and the tab opens.
  - **A cheap first step:** parcel icons in place of the idle number in
    the line under the face.
- **A climb for long turns.** Claude's to-do list as rungs Boop climbs:
  3 of 7 done. It uses counts only and needs AgentHooks to count items.
- **The orchestra.** Each working agent adds an instrument to a quiet
  loop. You hear how busy things are without looking: a finish is a
  cymbal, a failure a sour note.
- **Babble.** Boop "reads" the agent's last message as gibberish of the
  right length and tune, in the style of Animal Crossing, with one clear
  word at the end. The text stays on the Mac; only its length and shape play.
- **Tip it to open.** Tip the board toward your screen and the parcel
  pours into the tab. A knock on the desk does it too. Both use the IMU.
- **Agents can wink through Boop.** An MCP tool lets Claude pick one of
  Boop's moods on purpose, e.g. nervous before a scary migration. It's
  multiple choice, so no free text.
- **A hidden quirk for each Boop** (round 5). At hatching the seed
  already in `long-term.md` picks one quirk: afraid of deploys, a
  neat freak, a night owl, hates Mondays, a drama queen, a foodie. You
  find out over time. Each is a small steering file, plus a slot in the
  prompt.
- **Agent-isms** (round 5). A family of reactions to the agent's stock
  phrases, steering only: "You're absolutely right!" gets an eye-roll,
  "I apologize for the confusion" a pat, "Let me try a different
  approach" a sigh, "Perfect!" a side-eye.
- **Deploying on a Friday?!** (round 5). Horror at a deploy prompt on
  a Friday afternoon. Steering only, once the line carries the day.
- **Superstitions** (round 5). Crossed fingers during tests, knocking
  wood before a deploy. Steering, over faces it already has.
- **Covers its eyes at scary commands** (round 5). `rm -rf`,
  `git push --force` or `DROP TABLE` falls in a "risky" kind sorted on
  the Mac, and only the kind reaches Jev.
- **A bug jar** (round 5). A test that fails, then passes, is a bug
  caught: an insect in a jar that fills over the week.
- **Tabs or spaces?** (round 5). Once a day, when idle, Boop asks a
  two-option hot take on the screen (tabs or spaces, vim or emacs) and
  you tap a side. It remembers your answer and judges you for it
  through the steering.
- **Hide and seek** (round 5). When bored it hides, with only its eyes
  peeking from an edge. Tap it to find it.
- **Desk clock** (round 5). With nothing running, it holds up the time,
  so it earns its desk space. The board has a real-time clock.
- **A door sign** (round 5). It faces the room: "on a call", "deep in
  it", for people around you.
- **Beyond the current scope:**
  - A friend's Boop on your desk showing their agents (co-working presence).
  - Hold BOOT on an idle agent and dictate its next prompt. That would
    break "it only watches".

## Demo only, for now

- **Agent races between two buddies,** each on its own agent, with no
  prompt to pick a side. One script beside `not-my-turn`.

## Later

- **It remembers**: its biggest win, worst streak, favourite project, and callbacks to them.
- **Ask it things** ("who's waiting?"). A buyer would have to learn it exists.
- **A light LLM for replies.** Open question: a pet that answers in
  sentences becomes a chatbot.

## No, for now

- Pushes to your phone
- The usage belly: your plan's limit isn't readable locally
- Allowlist suggestions
- A favourite agent
- **Ears that are always listening** (the fun branch's stage 5): the
  Mac's mic indicator would always be on.
  - The board has its own two mics (ES7210), which would avoid the
    indicator, but a desk toy that listens raises the same trust
    question.
  - Push-to-talk on BOOT stays.
- A reunion that scales with time away: the existing wake-up covers it
- "Stretch with me" as a break nudge: folded into Yes §6
