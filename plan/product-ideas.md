# Product ideas: the running list (updated 2026-10-21)

The implementation plan for the Yes list is [updated-behavior.md](updated-behavior.md).

The owner's brainstorm for making a single buddy more fun, interactive
and useful. The fun audit's plan (comedy, the cuss, ladders, idle
check-ins, ears) is a separate track, not repeated here.

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

## Yes: we're building these

### 1. Idle agents, and BOOT opens the next one
- **The count.** The line under the face shows how many agents are
  idle: their turn ended and they're waiting for your next prompt. There's
  no read or unread. A session leaves the count when you prompt it or close it.
- **The buttons.**
  - A BOOT press opens the next one on the Mac, with a cheerful
    hand-off the board plays at once.
  - Holding BOOT is still talk.
  - A tap on the screen is still a poke.
  - The product's own button replaces BOOT when it's ready.
- **The order.**
  - "Needs you" first, oldest first, as now.
  - Then idle ones, newest first, since the oldest idle session is
    usually one you've abandoned.
  - Presses in a row walk down the list, and after a pause it starts again.
- **The exact tab.** Claude and Codex desktop threads open exactly today.
  A terminal session only brings the terminal app forward. The fix is in
  AgentHooks: the hook client records its terminal and tab (iTerm's
  session ID, Terminal's tty, a tmux pane), and Boop selects that tab.
  macOS asks for automation permission once.
- **Open:** whether sessions idle for hours leave the count.

### 2. Frantic with more agents running
- **How it looks.** The working look gets more intense with the
  working count, which the board already receives (`busy`), e.g. 1 calm,
  2–3 busy, 4+ frantic.
- **How to build it.** Start with playback speed, then add frantic
  variations in the packs. It's firmware and pack content only.
  "Needs you" still wins.
- **Only sessions count.** Helpers have their own count (§3).

### 3. Helpers as minis
- **One mini for each subagent running now**, across all agents (each
  session already keeps its `helpers`).
  - A mini pops out when a helper starts and goes back when it returns,
    when `helper_return` already plays.
  - Up to about 4 minis around Boop, then "+N".
- **A helper count** in the line under the face, next to the working count.
- **The look in each pack.** On the gel, minis are droplets that split
  off and are reabsorbed. On Pixel, tiny faces.
- **A tap on a mini** makes it squeak (the AMOLED's touch has position).
- **What it needs:** a `helpers` field in `state`, art in both packs,
  and screen tests for 0, 1, 4 and 7 helpers.

### 4. Time of day, Fridays, and day counts
- **Coffee and pyjamas.** Coffee in the morning, pyjamas late at night,
  Fridays. The Mac tells the board the part of the day, and the pack
  marks which variations may play when.
- **Day counts.** On days 10, 50 and 100, then every 100, plus one year
  since setup, a party on the first wake-up of the day. The brain hears
  "today is Boop's 50th day", and the popover shows "Day 47".
- **Growth stage-ups** (counted today but never celebrated) and the
  100th finished turn get the same party.

### 5. Major holidays
- **The same mechanism as §4:** the Mac tells the board the day, the
  pack marks variations for it, and the brain hears "It's Halloween" so
  Jev plays along.
- **The holidays.**
  - **A starter set:** New Year (a countdown, then a party hat),
    Valentine's (hearts), Halloween (a costume, candy as the gift),
    winter holidays (a hat and snow), Lunar New Year.
  - **Developer in-jokes:** April Fools (it does something wrong on
    purpose), Pi Day, Programmers' Day (the 256th day), May the 4th,
    Friday the 13th.
  - **Regional ones by the Mac's region:** Thanksgiving, Diwali,
    Hanukkah, Eid.
  - **Dates that move** (Lunar New Year, Easter, Diwali, Eid) come
    from a table of years.
- **Open:** Halloween (10-31) first, as the timely demo? Which
  regions do buyers come from?

### 6. Random animations that grow with time in a look
- **How it works.** The longer a look has shown, the more variations
  join the board's pool. The board already turns variations and knows
  how long a look has shown, so it's pack content plus a timer on the
  board. The fun plan's comedy batch (a yawn, nodding off, a sneeze, a
  snore, hiccups, a gift, zoomies) gives a pool to start from.
- **Ideas for the pool:**
  - **Working long (~20 min):** a stretch, cracking its knuckles,
    wiping its brow, a sip of coffee, rubbing its eyes.
  - **Working very long (1 h+):** bags under its eyes, a second coffee,
    nodding off and jolting awake.
  - **Idle long:** bored. It juggles, bounces a ball, doodles, reads,
    sighs at the clock.
  - **Asleep long:** a dream bubble, rolling over, a snore, a twitch,
    sleep-talk, drool.
  - **After a big finish:** smug for a few minutes.
  - **After a failure:** sulky for a while.
  - **Several finishes in a row:** a little dance.

### 7. Every feature: a demo and evals
- **The model.** A demo is an eval plus a scripted brain. An eval runs
  the same situation on Jev and checks it does the right thing.
  - An eval scenario's steps carry `expect` (the sets of answers it accepts).
  - A demo's steps carry `brain` (one answer each).
- **What follows from it:**
  - **Every eval plays as a demo.** A scripted brain picks from each
    step's `expect`, so auditing the evals is watching them in the simulator.
  - **Every demo is checked against the evals.** Its answers must be
    ones an eval accepts, so a demo never shows what Jev would be failed for.
  - **Screen expectations on eval steps.** The look, the idle count,
    the minis, the costume. They pass or fail with the scripted brain:
    free, exact, in CI. So a big suite per feature costs Jev requests
    only for the brain's part.
- **A test pinning each number.**
- **The formats need:**
  - several sessions on one buddy in demos (evals have `session` already)
  - a start date and time in both (evals start on a fixed Wednesday 14:00 UTC)
  - more demos with two buddies (`not-my-turn` is the one today)

### 8. Opinions about you, mostly in the steering files
- **It judges your prompts.** "please" gets a smile, "thanks" a beam,
  ALL CAPS a flinch, swearing at Claude a gasp, "ultrathink" a furrowed
  brow, a bare "continue" a yawn. Your prompt already goes to Jev, so
  this is steering Examples and evals only.
- **It loves deleted code.** A big deletion gets a happy dance. It's
  steering plus one count in the line ("claude deleted 1,200 lines"),
  made on the Mac from the edit events and never sent.
- **Its verdict on a finish,** shown through the face and words it
  already has: steering only. Stars would need a new question, so
  they wait.
- **Steering budget.** The steering is nearly full (the fun audit
  measured `boop.md` at 729 of 750 tokens). The fun plan's R1 makes room
  first, or this gets its own file.

### 9. Boop's diary
- **What it is.** One line a night in the popover: "Tuesday. api fell
  over three times. I stayed brave."
- **How it's made.** The templates live in a steering file, filled from
  the day's counts. Jev picks one by multiple choice, so there's no free
  text.
- **The code.** One small output asked once a day, and one row in the
  popover.
- **Later:** it plays yesterday's line as a little standup at the first
  wake-up.

### 10. Touch and motion on the AMOLED board
- **What you can do.** Stroke it, boop its nose, tickle it; pick it up,
  tilt it, shake it, rock it. The interactions are in round 7 of the
  brainstorm.
- **Face-down is do not disturb** (decided). It holds everything except
  "needs you", and plays peekaboo when you turn it back up.
- **A proposed order:**
  1. Stroking and the nose boop (the touch panel works, and the gel's
     drag exists).
  2. Picking it up, putting it down, shaking it, and face-down (the
     motion sensor's driver first).
  3. Tilting, rocking and upside down.
- **How it's built.** The board plays its own reaction at once, as a
  tap's does today, then tells the Mac. The brain (rules or Jev) follows
  up with the mood later, so the instant part needs no brain.
- **The hardware.** The touch panel (FT3168) gives positions, so the
  board can tell a stroke from a tap. The motion sensor (QMI8658, unused
  today) has an interrupt pin. The gel engine already has a "pulled by a
  finger" drag (`dragStart`/`dragMove`) that nothing feeds yet. Tilt could
  feed it too.
- **Tests.** The simulator page needs a fake tilt and shake, and demos
  and evals need steps for stroke, shake and pick up. The thresholds
  (shake vs. typing on the desk) are pinned in tests.
- **The Cheap Yellow Display** has neither a capacitive screen nor a
  motion sensor, so it keeps tap and BOOT.

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
  stock phrases (a steering Example; the last message already goes to Jev).
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
