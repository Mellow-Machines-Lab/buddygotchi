# Boop: audit of the words and the personality

Date: 2026-11-09. Worktree: `.claude/worktrees/v1-polish` (branch `v1-polish`, HEAD `270ee70c`).
Research only. No file in the repo was changed. The app was not launched. No Jev request was made.
All strings were read from source, so on-screen truncation and wrapping are not checked.

Paths are relative to the worktree. `characters/boop` is a link to `characters/.repos/SlimeBuddy/character`.

## 0. The short version

1. **The Mac UI is mostly warm and plain.** The first-person onboarding voice ("Let's find my body", "Feed me an update?", "Yum.") is the best writing in the product. The popover is good where it copies that voice and weak where it reports status.
2. **The weak UI strings are in four groups:** the brain (Jev, TypeSafe, API key), the connection to agents (hooks), the body (board, device, body, firmware, simulator, character pack, voice.bin, FAT32), and trouble notices. These read as a manual for developers.
3. **One thing has several names.** Session / thread / agent. Body / board / device / "my Boop". Brain / Jev / TypeSafe's AI. Idle / resting. Hush / Quiet / Muted / volume Off.
4. **The pack's written content is very thin.** `signs.md` has 58 lines, `replies.md` 67, `asks.md` 21, `dreams.md` 17. Most sections have 1 to 3 lines. A buyer sees most repeats inside the first week, and some inside the first day.
5. **Asks run out on day one.** There are only two questions, and both are `keeps` (asked once, ever). After the buyer answers both, Boop never asks a question again.
6. **Two registers.** Signs are lowercase text-speak ("nite nite", "u got this", "idk"). Voice words are a different character: military and corporate ("Debrief", "Jawohl", "Standby", "Execute"), plus a polyglot habit ("Tadaima", "Andiamo", "Yare yare") that `personality.md` never mentions. Code-made signs ("Level 12!", "Today's done!", "Happy Halloween!") are a third register, in Title case.
7. **The charming voice lines are the rare ones.** In a given face, every topic has about 8 words and a median of 0 phrases. So the usual `tests` line is one of Verify, Trial, Validate, Measure, Probe, Test, Testing, Checking, Passed. "Fingers crossed" and "Please work" play in one mood group each.
8. **Trust: the world's field list is pinned and close to what the UI says, but not complete.** The UI names "counts, like tests passed". The code also sends turns, ships, lines changed, today's XP, the stage and the local date. Settings says "Nothing about you or your code"; lines changed is a number about your code.
9. **Trust: Jev gets more than "a short reading".** It also gets up to three of your own phrases from each prompt, up to three of the agent's, your project and thread names, your spoken words (up to 300 characters) and the memory notes. The UI says "never your code", which is true, but it does not say the rest.
10. **A buyer cannot tell how to get a brain.** The link says "Jev's docs" and goes to `docs.typesafe.ai/api`. No price. Settings has no link at all. Without a key the product has no personality, and the key card sits third in an act called "A few small things".
11. **Boop swears aloud ("Fuck", "Shit") and nothing in the UI says so.** There is no switch for it except Talk: Quiet.

---

## A. The Mac UI

Verdicts: **warm**, **ok**, **manual** (reads like a manual), **jargon** (an internal word a buyer does not know), **confusing**, **banned** (a word from CLAUDE.md's "Not" column, or a second name for one thing), **long**.

### A1. The popover: header, tabs, footer

| String | Where | Verdict | Rewrite |
| --- | --- | --- | --- |
| `Now` / `Boop` / `World` (tabs) | app/Boop/MenuBarApp.swift:46 | ok. The tab says "Boop" when the buddy is called Mochi. | Use the buddy's name for the middle tab. |
| `Waking up…` / `Not running` / `Listening…` / `Needs you` / `N sessions need you` / `Working` / `Resting` / `Napping` | MenuBarApp.swift:430-437 | ok. "sessions" here, "agents" elsewhere. | `3 agents need you` |
| `Feeling` + mood + `· Level N` | Views/OverviewPane.swift:174-177 | ok | |
| `Hushed · N min`, `Hush`, `Talk`, `Send`, `Muted`, `Quiet`/`Chatty` chips | OverviewPane.swift:191-297 | confusing. Four words for "silent": Hush (30 min), Quiet (a Talk level), Muted (volume 0), and Settings shows volume `Off`. | Keep `Hush` and `Quiet`. Change `Muted` to `Sound off`, to match the volume row. |
| `Hush X for N min: it keeps making faces, but says nothing` | OverviewPane.swift:286 | warm | |
| `Talk to X with the Mac's microphone. Only Jev answers, so this needs a Jev API key` | OverviewPane.swift:305 | jargon (Jev, API key) | `Talk to X with the Mac's microphone. X needs its brain to answer: add one in Settings.` |
| `Talk to X with the Mac's microphone: try “how many agents are running?” It stops by itself after 30 seconds` | OverviewPane.swift:306 | ok | |
| `Settings`, `Quit`, `What X knows` | Views/PopoverView.swift:56-81 | ok | |
| `Save a bug report: what X saw and did this launch, to hand to an agent` | PopoverView.swift:66 | manual. "this launch", "hand to an agent" is the developer's workflow. | `Something wrong? Save a report to send us.` |
| `Boop 1.0 · firmware 0.x` | PopoverView.swift:70 | jargon (firmware). Fine in a footer. | `Boop 1.0 · body 0.x` |

### A2. The Now tab

| String | Where | Verdict | Rewrite |
| --- | --- | --- | --- |
| `Boop couldn't start` + `Try again` | OverviewPane.swift:48 | ok | |
| `X stopped unexpectedly` / `It didn't close properly last time. A bug report keeps what it knew, with macOS's crash report if there is one.` | OverviewPane.swift:52-53 | manual | `X fell over last time` / `Sorry about that. Save a report and send it to us, and we'll look.` |
| `X has no brain yet` / `It shows what your agents do and when one needs you. Add a Jev API key in Settings, and X reacts to it, and answers when you talk.` | OverviewPane.swift:60-61 | jargon. "reacts to it" has no clear "it". | `X can watch, but can't feel or answer yet. Give it a brain in Settings.` |
| `X can't hear you` + reason | OverviewPane.swift:68 | warm | |
| `Restart your agent sessions` / `Open sessions pick up Boop's hooks when they restart.` | OverviewPane.swift:73-74 | jargon (hooks), banned (session and agent as one phrase). "Boop's" is fixed text, not the buddy's name. | `Restart your open agents` / `X can hear them once they start again.` |
| `Couldn't change Claude Code's hooks` / `Claude Code's settings were left as they were.` | OverviewPane.swift:82-83 | jargon | `Couldn't connect Claude Code` / `Nothing was changed.` |
| `Sessions` / `Sessions · 3` | OverviewPane.swift:89 | banned: onboarding calls the same rows "agents" and "threads". | `Your agents · 3` |
| `Why X looks like this` | OverviewPane.swift:96 | warm | |
| `X is calm.` + wish, reason and pastime lines | OverviewPane.swift:781 | warm. This card is the best idea in the popover. | |
| `claude is waiting for you. Click to open it in Claude.` / `Answer it in its window.` | OverviewPane.swift:375 | ok | |
| `Dismiss` / `Stop showing this on X. claude still waits.` | OverviewPane.swift:383-387 | ok | |
| `X isn't listening to any agent yet` / `Connect Claude Code or Codex in Settings, and X will notice them.` | OverviewPane.swift:434-435 | warm | |
| `Start Claude Code or Codex and X will notice.` | OverviewPane.swift:442 | warm | |
| `Jev is out of credit` / `Top up your Jev account at TypeSafe. Until then, X shows what your agents do, but doesn't react.` / `Jev's docs` | OverviewPane.swift:483-486 | jargon (Jev, TypeSafe). The button opens API docs, not a billing page. | `X's brain is out of credit` / `Top it up, and X feels things again. Until then it only watches.` / button `Top up` |
| `Jev didn't accept your key` / `Check the Jev API key in Settings.` | OverviewPane.swift:487 | jargon | `X's brain key didn't work` / `Check it in Settings.` |
| `Jev isn't answering` | OverviewPane.swift:488 | jargon | `X's brain isn't answering` |
| `Untitled session` | OverviewPane.swift:624, 666 | banned (session) | `An agent` or the agent's name |
| `needs you` / `working` / `idle` / `dismissed` (row chips) | OverviewPane.swift:721-724 | banned: "idle" here, "Resting" in the menu, "resting" in the World tab and in StatusReply. | Use `resting` everywhere a person reads it. |
| `waiting 3m` / `idle 3m` / `✓ 3/7` (row detail) | OverviewPane.swift:702-715 | ok, terse | |

### A3. The Boop tab and the memory pane

| String | Where | Verdict | Rewrite |
| --- | --- | --- | --- |
| `The last 7 days` | Views/BoopPane.swift:14 | ok | `This week` |
| `Level 4` / `1,240 XP together` / `60 to level 5` | BoopPane.swift:38-40 | game jargon. CLAUDE.md's UI rule says "No game jargon"; XP is the one piece of it. "together" is a nice word. | `Level 4` / `1,240 together` / `60 more to level 5` |
| `Today's ring is full. Nice work.` | BoopPane.swift:53 | warm | |
| `Nothing yet today. Work with your agents, or give X a pet.` | BoopPane.swift:54 | warm. It shows how XP is earned without a rule. | |
| `82 today. Fill the ring and you're done for the day.` | BoopPane.swift:55 | warm (the plan's own example) | |
| `X is still getting to know you. What it learns shows here after it dreams.` | BoopPane.swift:82, MemoryPane.swift:33 | warm. "after it dreams" does not say when. | `…shows here after a night's sleep.` |
| `See everything X knows ›` | BoopPane.swift:90 | ok | |
| `Written on this Mac as X dreams. Its notes go to the brain with each request, and nowhere else.` | MemoryPane.swift:19 | ok, a little stiff ("with each request") | `X writes these on your Mac while it sleeps. Only its brain reads them.` |
| `Let it age as the others do` / `Keep it for good, as it is` / `Forget it` | MemoryPane.swift:60-66 | warm | |
| `Nothing yet.` | MemoryPane.swift:86 | ok | |
| `X isn't running, so its memory can't be read now.` | MemoryPane.swift:43 | manual | `X is asleep right now. Try again in a moment.` |

### A4. The World tab

| String | Where | Verdict | Rewrite |
| --- | --- | --- | --- |
| `The world isn't reachable from here.` | Views/WorldPane.swift:15 | ok | |
| `Joining the world…` / `Looking around the world…` | WorldPane.swift:24, 53 | warm | |
| `The world isn't answering, so this may be out of date.` | WorldPane.swift:31 | ok | |
| `Buddies around the world, by time zone. Click one.` | WorldPane.swift:42 | manual. It teaches the chart. | `Everyone's buddies, right now. Click one to say hi.` |
| `The world can't be reached just now. X will keep trying.` | WorldPane.swift:51 | warm | |
| `For X today` / `Around the world` | WorldPane.swift:55-57 | warm | |
| `X is private. Others can't see or boop it.` + `Open Settings` | WorldPane.swift:65-69 | warm | |
| `awake` / `coding` / `tests today` (tiles) | WorldPane.swift:79-81 | ok | |
| `· level 7 · you` / `This is X, as other buddies see it.` | WorldPane.swift:110-117 | warm | |
| `X is private, so it can't say hi. Turn on the world in Settings.` | WorldPane.swift:174 | warm | |
| `X is still finding its way into the world. Try again in a moment.` | WorldPane.swift:175 | warm | |
| `Sending a boop…` / `The boop didn't go through. Try again in a while.` / `Sent. Pip will see it when it wakes.` | WorldPane.swift:176-182 | warm | |
| `Nothing yet today.` / `And 4 more today.` / `3 hellos from other buddies today.` | WorldPane.swift:213-242 | warm | |
| `Someone in Europe or Africa booped Mochi.` / `While you were away, 3 buddies booped Mochi and 2 cheered your ship.` | BoopKit/World/WorldWire.swift:195-209 | warm. "cheered your ship" is jargon for a non-developer, fine for this buyer. | |
| `waiting on its person` (a buddy's activity) | WorldWire.swift:14 | warm | |

### A5. Settings

| String | Where | Verdict | Rewrite |
| --- | --- | --- | --- |
| Section titles: `Sound`, `Agents`, `Device`, `Talk`, `Brain`, `Memory`, `World`, `App` | Views/SettingsPane.swift:25-35 | banned: `Device` is "X's body" in its own first row. `Talk` is also the name of the microphone button. | `Body` for Device. `How much X says` for Talk. |
| `Volume` / `How loud X talks.` / `Off` | SettingsPane.swift:104-110 | warm | |
| `Work stream` / `Your agents' work falls past X, and failures hit it.` | SettingsPane.swift:117-118 | jargon title, warm detail | Title: `Falling words` |
| `Restart open agent sessions to pick up the change.` | SettingsPane.swift:140 | manual | `Restart your open agents, so X can hear them.` |
| `Connected` / `Needs a repair` / `Not connected` / `Not found on this Mac` / `Connect` / `Repair` / `Remove` / `Show file` | SettingsPane.swift:154-183 | ok | |
| `Couldn't change its hooks: …` / `Can't read its settings: …` | SettingsPane.swift:151-159 | jargon | `Couldn't connect: …` |
| `Its hooks are turned off in its own settings, so X can't see it. Turn them on there.` | SettingsPane.swift:161 | jargon, and no path to "there" | `Claude Code has hooks turned off, so X can't see it. Turn them on in Claude Code's settings.` |
| `X's body` + `Reconnect` / `Drop the connection and look for X's body again now` | SettingsPane.swift:194-200 | warm | |
| `X talks only to this board over Bluetooth.` / `Forget` / `Let X take any board, and remember the next one tapped` | SettingsPane.swift:211-214 | banned (board vs body) | `X lives only in this body.` / `Let X move into the next body you tap` |
| `Simulator` / `The simulator window, a board for when the board isn't here.` | SettingsPane.swift:221-240 | jargon. Should a buyer see this row at all? | Hide it outside internal builds. |
| `X's body runs 0.9. Plug it into this Mac with a USB cable, then update. It takes about half a minute.` / `Writing… 40%. Keep the cable in.` / `Updated to 1.0. X's body is starting it.` | SettingsPane.swift:245-250 | ok. Onboarding says the same thing better ("Eating… 40%"). | Reuse onboarding's words. |
| `Firmware` / `Update to 1.0` | SettingsPane.swift:252 | jargon | `Body update` |
| `Uninstall` / `Takes X out of your agents and off this Mac. Its memory stays.` | SettingsPane.swift:271-272 | warm | |
| `Only the everyday Boop uninstalls. This copy runs on a folder of its own.` | SettingsPane.swift:273 | dev-only. Fine if buyers never see it. | |
| `X opens when you log in, so it's there for your agents.` / `X only watches your agents while it's open.` | SettingsPane.swift:286-287 | warm | |
| `Allow X in System Settings, under General, Login Items.` | SettingsPane.swift:288 | **bug**: System Settings lists the app as "Boop", not as the buddy's name. `Talk.swift:40` gets this right. | `Allow Boop in System Settings, under General, Login Items.` |
| `Quiet`: `X shows what stands out on its face, and says a little only when something big happens.` `Normal`: `X reacts to what stands out, mostly with a sound or a word.` `Chatty`: `X says more, and checks in more often while agents work.` | BoopKit/Core/Talk.swift:35-37 | ok. "what stands out" twice is vague. | Quiet: `Faces, and a word only for big things.` Normal: `A sound or a word when something happens.` Chatty: `More words, and it looks in on you more often.` |
| `Jev API key` (field) | SettingsPane.swift:357 | jargon | `Brain key` |
| `This is how X thinks. It stays in your Keychain. What X notices goes to TypeSafe, never your code.` | SettingsPane.swift:382 | jargon and incomplete (see F2). No way to get a key from here. | `X's brain is an AI service called Jev. The key stays in your Keychain. The brain gets a short summary of what happens, a few of your own words and your project names. Never your code.` + a `Get a key` link |
| `Without a Jev API key, X shows what the agents are doing and when one needs you, but doesn't react or change its mood, and shrugs when you talk to it.` | SettingsPane.swift:309 | long, jargon. "shrugs" is the one warm word. | `No brain yet: X watches your agents and tells you when one needs you. It can't feel or answer.` |
| `What X remembers` / `Written on this Mac as X dreams. Its notes go to the brain with each request.` / `Forget about me` | SettingsPane.swift:93-96 | ok | |
| `X lives in the world` / `Other buddies can see X and say hi. Off, X leaves the world.` / `X is private. You can still look around.` | SettingsPane.swift:60-62 | warm | |
| `Shown as Mochi · Americas` / `Others see this name and level.` / `The world didn't take this name, so others see “a buddy”.` | SettingsPane.swift:68-70 | warm | |
| `Nobody sees X now` / `Turn on the world, and others see its name and level.` | SettingsPane.swift:74-75 | warm | |
| `What X shares` / `Its name, level, rough time zone, what it's doing, and counts like tests passed. Nothing about you or your code.` | SettingsPane.swift:80-81 | incomplete (see F1) | `Its name, level and size, its time zone, one word for what it's doing, and today's counts: turns, tests passed, ships and lines changed. Nothing else.` |

### A6. Device states and trouble (MenuBarApp.swift)

| String | Where | Verdict | Rewrite |
| --- | --- | --- | --- |
| `Starting…` / `Looking…` / `Connected` / `Connected over Bluetooth.` | MenuBarApp.swift:536-589 | ok | |
| `Looking for it over Bluetooth. Plug it into USB power.` | :555 | ok | `Looking for X's body. Is it plugged in?` |
| `X can't look for its body` / `No Bluetooth` | :544 | warm | |
| `No device` / `This copy of Boop runs without a device.` | :540 | dev-only, third name for the body | |
| `X's window is closed` / `X's body is the simulator, in a window of its own. Show it to bring X back.` | :548-549 | dev-only | |
| `X's body has the wrong firmware` / `Wrong firmware` / `…its firmware doesn't fit this app, so X shows how things are and doesn't react. Update its firmware.` | :564-567 | jargon | `X's body needs an update` / `Needs update` / `X's body is behind this app, so X only watches for now. Update it in Settings.` |
| `X's body has another character's faces` / `Other character` / `…the board was built with the pixel character pack, and the app runs boop, so some faces won't match. Flash the board with the app's character pack.` | :573-576 | jargon (character pack, flash, board). A buyer cannot do this. | `X's body needs an update` / `Update it in Settings.` |
| `X has lost its voice` / `No voice` | :583 | warm title | |
| `…it has no card, or no voice file on its card, so X can't talk. Put this app's voice file on the card, then press the board's reset button.` + `The voice file is the character pack's voice/voice.bin, copied onto the card as boop/voice.bin. The card must be FAT32: cards over 32 GB come as exFAT, so format one first.` | :582-587 | manual. A buyer of a ready-made Boop cannot do this. | `X can't find its voice. Unplug X, wait a moment and plug it back in. Still silent? Tell us.` (The owner's notes say a wedged card recovers on a full power cycle, not on reset.) |
| `Another copy of Boop is already running. Quit it, then try again.` / `Boop can't listen for your agents. Quit any other copy of Boop, then try again.` / `Something went wrong while starting. Try again, or quit Boop and open it again.` | :631-633 | ok | |
| `Boop's hook helper is missing. Install Boop again.` | :504 | jargon | `A part of Boop is missing. Install Boop again.` |
| `Uninstall X?` / `X takes its hooks out of Claude Code and Codex, stops opening at login, moves Boop.app to the Trash and quits. Its memory stays in <folder>, so a Boop installed again remembers. Delete that folder to forget it too.` | :1075-1078 | ok. Clear and honest. | |
| `Names can't use “·” or “:”.` | :66 | ok | |
| `Allow Boop in System Settings → Privacy & Security → Microphone.` / `No microphone is connected.` / `On-device speech recognition isn't available on this Mac.` | app/Boop/Talk.swift:40-121 | ok | |

### A7. Text built in BoopKit that the Mac shows

| String | Where | Verdict | Rewrite |
| --- | --- | --- | --- |
| `X's getting ready for the work act.` / `X's coming back from the work act.` | characters/boop/mac/passing.tsv:58-59 (shown by Narration.passing, Narration.swift:256) | jargon: "work act" is an internal word. | `getting into costume` / `packing its props away` |
| `X's having a little think to pass the time.` (and 50 more) | passing.tsv:3-55 | warm. The pastime line is a delight. | |
| `claude's calls on api keep failing: 3 times in 5 minutes.` | BoopKit/Core/Narration.swift:284 | jargon (calls), numbers not needed | `claude's commands on api keep failing.` |
| `claude's memory on api was compacted.` | Narration.swift:132 | jargon | `claude on api ran out of room and started from a summary.` |
| `claude's thread on api ended.` / `You opened a thread from its drawer.` | Narration.swift:134, 117 | banned (thread), jargon (drawer is never named to the buyer) | `claude on api closed.` / `You opened an agent from X's list.` |
| `claude started a helper on api.` / `A helper of claude's finished on api.` | Narration.swift:136 | ok | |
| `The other buddy reacted.` | Narration.swift:138 | confusing for one buddy; demos only | |
| `You've been here 3 hours and haven't touched it.` | Narration.swift:153 | tone break: it reads as a scold. `personality.md:32` says "never scolds". | `It's been 3 hours since you two said hi.` |
| `Mochi wished for a pet, and you left it.` | Narration.swift:114 | tone break: blames the buyer | `Mochi's wish for a pet went by.` |
| `You gave Mochi its wish: a pet.` / `Mochi wants a pet.` / `Mochi wishes for a pet (12 min).` | Narration.swift:113, 195; BoopKit/App/Runtime+Status.swift:177 | ok. Three verbs (wants, wishes for, wished for) for one thing. | Use "wants" in all three. |
| `Nobody answered its question.` / `It will remember: cookie.` / `You answered: pizza.` | Narration.swift:90-93 | warm | |
| `You told it to be quiet for 30 minutes.` / `It may talk again.` | Narration.swift:119-121 | ok | |
| `No agents are open, so X went to sleep.` / `Nothing's happened for an hour, so X dozed off.` / `X went for a nap, and you haven't been back.` / `claude got to work on api, so X woke up.` | Narration.swift:240-249 | warm | |
| `claude finished a turn on api.` / `claude finished 3 quick turns in a row on api.` / `claude answered you on api.` / `claude gave up on api.` / `claude has a question for you on api.` / `claude got the tests passing on api.` | Narration.swift:266-276 | ok. "turn" is Boop's word, not the buyer's. | `claude finished on api.` / `claude finished 3 quick ones in a row on api.` |
| `You asked claude for a fix on api, sounding frustrated.` | Narration.swift:305-320 | warm, and honest about what was read | |
| `It noticed a rough hour: 3 failures.` / `It noticed claude has sat idle on "api" for 20 min.` / `It noticed you sounded sharp a while ago, and it's quiet now.` / `It noticed past midnight again: up past 1 on 4 of the last 7 nights.` | Narration.swift:183 with BoopKit/Core/Notices.swift:114-139 | mixed. The facts are written for Jev's CONTEXT row and reused for the person. "you sounded sharp" and "up past 1 on 4 of the last 7 nights" read as surveillance. | Give each notice a second, human sentence: `It's been a rough hour.` / `claude's been free for 20 minutes.` / `It's late again.` |
| `While you were gone, claude finished on api, codex failed on blog, 2 more.` | Notices.swift:146-151 | warm and useful | |
| `Day 41. …` / `Mochi remembers you stay up late on Fridays.` | Narration.swift:34, 38-41 | warm | |
| `It's night` → `A nightcap and pyjamas`; `It's Friday` → `Shades` | Narration.swift:436-441 | warm | |
| Status signs: `claude needs you`, `2 need you`, `3 resting`, `2 working, 1 idle`, `claude: 12 min in`, `claude: tests failed`, `claude: 3/7 done`, `no codex around`, `all quiet`, `at it 1 h 20`, `just started` | BoopKit/Outputs/StatusReply.swift:141-193 | ok. `resting` (line 156, 192) and `idle` (line 157) are in the same function. | Line 157: `2 working, 1 resting` |

### A8. What the UI teaches rather than shows

- **`Buddies around the world, by time zone. Click one.`** (WorldPane.swift:42) explains a chart.
- **Onboarding act 5, "Here's how we get along"** is four numbered lessons, a four-face legend ("HOW I FEEL") and a rule ("My mood holds steady. Big moments move it, and it settles back with time.", OnboardingBoard.swift:280). The lessons are done on the board, which is showing, not teaching. The legend and the rule are teaching, and the popover's "X is calm." card already does that job later.
- **The finale** lists four more tips (OnboardingFinish.swift:377-391) that repeat acts 5 and 6.
- **`See exactly what gets added`** (OnboardingFinish.swift:84-93) is 130 words. It is behind a disclosure and it earns trust, so it is fine.

### A9. The same thing named two ways

| Concept | Names in the UI | Where |
| --- | --- | --- |
| One conversation with an agent | `Sessions`, `agent sessions`, `Untitled session`; `thread` (5 times in onboarding act 6 and the finale); `agent` ("click any agent in my menu") | OverviewPane.swift:89, 73, 624; OnboardingFinish.swift:188, 221-224, 378; Narration.swift:117, 134 |
| The hardware | `my body`, `the board on your desk`, `this board`, `Device` (section), `No device`, `my Boop` ("I don't have my Boop yet") | OnboardingBoard.swift:40-58; SettingsPane.swift:27, 212; MenuBarApp.swift:540 |
| The LLM | `brain`, `Jev`, `Jev API key`, `TypeSafe's AI`, `TypeSafe` | OnboardingBrainKey.swift:22-34; SettingsPane.swift:30, 357, 382; OverviewPane.swift:485-488 |
| Not working | `idle` (row chip, drawer `IDLE`, sign "1 idle", "{agent} sits idle"), `Resting` (menu headline), `resting` (World tab, StatusReply) | OverviewPane.swift:724; MenuBarApp.swift:436; WorldPane.swift:168; StatusReply.swift:156-157, 192; characters/boop/firmware/src/render/gel/drawer.cpp:46 |
| Silence | `Hush`, `Hushed`, `Quiet`, `Muted`, volume `Off` | OverviewPane.swift:192, 261, 282; SettingsPane.swift:110; Talk.swift |
| The button | `my button`, `The one on my side`, `BOOT` | OnboardingBoard.swift:264, 299; characters/boop/steering/asks.md:17 |
| The firmware update | `Feed me an update?` / `Eating…` / `Yum.` in onboarding; `Firmware`, `Writing…`, `Updated to` in Settings | OnboardingBoard.swift:184-202; SettingsPane.swift:247-252 |
| A wish | `wants`, `wishes for`, `wished for` | Narration.swift:195, 114; Runtime+Status.swift:177 |

---

## B. The gel pack's steering

Files: `characters/boop/steering/`. Sizes: personality 117 lines, guide 29, signs 59, asks 22, replies 68, dreams 18, sixteen mood files of 9 to 17 lines.

### B1. `personality.md` and `guide.md`

**The character is clear in one paragraph and buried under rules.** The file is about 110 lines. About 80 are when-and-how-big rules. The temperament starts at line 88:

> At heart Boop is cheeky: playful, a bit sassy and a little smug. The cheek is in how it reacts, never in reacting more

and the best line of the whole pack is 107-111:

> It teases the agents and the work, never the person, and is never mean. It drops the act where it matters: rude words hurt it, manners warm it, shouting makes it flinch, sad news gets comfort

That is a real character. The takes below it are good too ("A long turn's win gets a proud face, as if it knew all along", "Praise for Boop it takes as its due", "a bare 'continue' bores it").

Problems:

1. **The cheek has seven bullet points and nothing about how it talks.** Nothing says lowercase, text-speak, short, or teasing. So the signs, the voice words and the code-made signs each chose a register of their own (see B6).
2. **"Proud" is steered in from four places.** personality.md:21 ("pleased, amused, smug, proud on top"), :76 ("Cheers for your ship make it proud"), :92 ("A long turn's win gets a proud face"), and seven mood files send a pass-after-fail to proud. A level-up is also proud (CLAUDE.md, `level`). This matches plan/v1-buddy.md:94, "proud finishes nearly everywhere".
3. **One garbled sentence.** Lines 13-15: "A plain one gets a small one, or at most a small face in silence with no sign if HISTORY shows Boop reacting in the last 3 min." "A small one, or at most a small face" says the same thing twice; the first "small one" probably means a small face with a sound.
4. **Idle is told to do nothing.** Line 33: "An idle check-in where nothing has happened mostly gets nothing, now and then a small face in silence". Line 42 then says "Idle, it now and then muses or asks." The first rule wins in the evals (TODO.md:101, 36 of 83 idle check-ins have a moment, 8 a real face).
5. **Notices are steered toward the flat one.** Line 30-31: "at an idle check-in a small look up at you, an agent sat idle usually its sign." That sentence asks for the `waiting` sign, which is the one the review called a flat report.
6. **Only two Examples blocks remain** (4 examples). That follows the owner's rule (guidelines over examples) and is fine.
7. `guide.md` is short and plain. Line 17, "a streak gets bigger, then gets old", is a good rule in a good voice.

### B2. `signs.md`: every line

58 lines in 33 sections. No line is over 18 characters as written. Filled lengths: `{turns} turns today!` is 16 to 17 with a 2- or 3-digit count; `{agent}'s waiting` is 16 with "claude". `'{words}', sure` only fits a phrase of 10 characters or fewer.

| Line | Section | Chars | Verdict |
| --- | --- | --- | --- |
| `{words} :(` | frustrated | 10+ | in character |
| `{words}?!` | frustrated | 9+ | in character |
| `{words}. again.` | frustrated | 15+ | in character, the best of the three |
| `{WORDS}!!` | shouting | 9+ | in character |
| `{words} <3` | polite | 10+ | sweet, not cheeky |
| `'{words}', sure` | rushed | 15+ | in character, real cheek |
| `{words}...` | careful | 10+ | ok |
| `{words} lol` | playful | 11+ | in character |
| `me?!` | named | 4 | in character |
| `you rang?` | named | 9 | in character |
| `bug, again` | fix frustrated | 10 | in character |
| `bug hunt` | fix | 8 | bland label |
| `who broke it?` | fix | 13 | in character |
| `bugs at night?` | fix night | 14 | in character |
| `new thing!` | feature | 10 | bland |
| `ooh, shiny` | feature | 10 | in character |
| `another one?!` | feature | 13 | in character |
| `bye bye code` | cleanup | 12 | in character |
| `delete it all` | cleanup | 13 | in character |
| `tidy time` | refactor | 9 | bland |
| `tests! tests!` | tests | 13 | ok |
| `ship it?` | deploy | 8 | ok |
| `yolo` | deploy | 4 | in character |
| `on a FRIDAY?` | deploy friday | 12 | in character, the best line in the file |
| `docs...` | docs | 7 | in character (bored) |
| `hmm?` | question | 4 | bland |
| `good q` | question | 6 | ok |
| `onward!` | carry_on | 7 | tone break: earnest. personality.md:97 says "a bare 'continue' bores it". |
| `reading...` | essay | 10 | ok. A missed tease ("a novel?"). |
| `{words}` | plain | varies | ok |
| `quiet day...` | idle | 12 | bland |
| `{turns} turns today!` | idle | 16-17 | report, and "turns" is jargon |
| `{thread} again?` | idle | varies | in character |
| `still here, u?` | idle | 14 | in character |
| `snack time?` | idle cookie | 11 | in character |
| `pizza later?` | idle pizza | 12 | in character |
| `{agent}'s waiting` | notice waiting | 16 | report |
| `{agent} sits idle` | notice waiting | 16 | flat report (TODO.md:103) |
| `{agent}'s done` | notice waiting | 13 | report |
| `stretch?` | notice stretch | 8 | ok, caring |
| `legs ok?` | notice stretch | 8 | in character |
| `water break?` | notice stretch | 12 | ok |
| `i'm here` | notice rough | 8 | warm. Same text as `[comfort]` in replies.md:47. |
| `*hug*` | notice rough | 5 | warm. Same text as replies.md:45. |
| `rough one` | notice rough | 9 | ok |
| `bed?` | notice late | 4 | close to telling you what to do |
| `still up?` | notice late | 9 | warm (the review's one warm notice) |
| `getting late...` | notice late | 15 | ok |
| `boop back!` | world boop | 10 | in character |
| `who was that?` | world boop | 13 | in character |
| `hi, friend!` | world wave | 11 | sweet |
| `*waves back*` | world wave | 12 | ok |
| `aww, a heart` | world heart | 12 | sweet |
| `<3 <3` | world heart | 5 | ok |
| `we shipped!` | world cheer | 11 | ok |
| `thanks, all!` | world cheer | 12 | earnest, not smug. Boop "takes praise as its due". |
| `hi, world!` | world | 10 | ok |
| `a friend!` | world | 9 | sweet |

Count: about 22 lines are clearly the cheeky character, about 20 are sweet or neutral, 9 are bland labels or reports, 2 break tone.

### B3. `asks.md`: every line

| Line | Section | Chars | Verdict |
| --- | --- | --- | --- |
| `fav snack? \| cookie \| pizza` | snack idle keeps | 10 / 6 / 5 | in character |
| `hat or bow? \| hat \| bow` | hat idle keeps | 11 / 3 / 3 | in character |
| `nom nom` | snack cookie | 7 | in character |
| `pizza party!` | snack pizza | 12 | in character |
| `dapper!` | hat hat | 7 | in character |
| `so pretty` | hat bow | 9 | in character (smug) |
| `pet me?` / `scritches?` / `pat pat?` | wish pet | 7 / 10 / 8 | in character |
| `<3` | wish pet met | 2 | bland, and the 4th use of `<3` in the pack |
| `stroke my face?` | wish pet how | 15 | ok, it shows what to do |
| `talk to me?` / `say something?` / `got a word?` | wish chat | 11 / 14 / 11 | in character |
| `i hear u` | wish chat met | 8 | flat |
| `hold BOOT, say hi?` | wish chat how | 18 | **bug**: a buyer's board has no "BOOT". Onboarding calls it "my button … The one on my side." |
| `work with me?` / `give me work?` / `bored. any work?` | wish work | 13 / 13 / 16 | the third is in character, the first two are needy rather than cheeky |
| `lets go!` | wish work met | 8 | ok |
| `prompt an agent?` | wish work how | 16 | jargon ("prompt") |

**Only two questions exist, and both are `keeps`.** Asks.swift:31-33: "a `keeps` one answered never comes back". The limits allow 3 asks a day. So the whole section is used up on day one, or day two if one is ignored. After that the `ask` Moment kind is dead for the life of the buddy. The follow-ups (`nom nom`, `dapper!`) are each seen exactly once, ever.

### B4. `replies.md`: every line

67 lines in 25 sections. One literal duplicate across sections: `{words} 2 u!` (hello, line 24; bye, line 28), which is by design.

| Section (n) | Lines | Verdict |
| --- | --- | --- |
| yes (4) | `yep!`, `uh-huh`, `mhm!`, `yes yes!` | neutral |
| no (5) | `nope`, `nuh-uh`, `nah`, `make me`, `no way` | `make me` is the character; the rest neutral |
| dunno (4) | `no idea!`, `beats me`, `who knows?`, `{words}? idk` | in character |
| huh (3) | `huh?`, `come again?`, `'{words}'?` | ok |
| huh nobrain (2) | `no brain yet :(`, `need my brain!` | warm and it shows the fix |
| hello (5) | `hi hi!`, `oh, hi!`, `good, u?`, `right here!`, `{words} 2 u!` | in character |
| hello morning (1) | `morning!` | bland |
| bye (3) | `bye bye`, `see ya!`, `{words} 2 u!` | neutral. At a lock there are no words, so two lines. |
| bye night (2) | `nite nite`, `{turns} turns today` | first in character, second a report |
| bye working (1) | `i got this` | in character, but the only line (see B7) |
| thanks (6) | `i know ;)`, `hehe thx`, `woo!`, `yay!`, `{words}? me?!`, `we rock` | `i know ;)` is the best reply in the file. `woo!` and `yay!` are generic. |
| love (3) | `<3`, `love u too`, `aww` | sweet, not cheeky |
| love makeup (2) | `...fine`, `forgiven <3` | in character |
| ouch (2) | `:(`, `rude.` | in character, thin |
| comfort (3) | `*hug*`, `there there`, `i'm here` | drops the act, as the personality says |
| comfort night (1) | `bed time?` | ok |
| comfort working (2) | `u got this`, `we'll fix it` | warm |
| hehe (3) | `hehe`, `lol`, `{words} lol` | ok |
| nap (2) | `zzz`, `nap time` | bland |
| nap working (2) | `after this`, `not now, busy` | in character |
| hush (3) | `ok, shh`, `*zips lips*`, `fine. hmph.` | in character |
| unhush (2) | `i can talk!`, `words! yay!` | ok |
| dance (3) | `*wiggle*`, `look at me go`, `wheee` | in character |
| notme (2) | `ask them!`, `not my job` | in character |
| notme waiting (1) | `that's ur job` | in character |

About 28 lines carry the cheek. The yes, no, hello, bye, nap and hehe sections are generic chat fillers that any character could say.

### B5. `dreams.md`: every line

17 lines in 15 sections; 13 sections have one line.

`dreamt of u` (fond), `warm dreams` (fond), `poke dreams` (fond poked), `i remember!` (answered), `where were u?` (distant), `up so late...` (late), `long day, huh` (here), `bug nightmares` (failed long), `bad dream` (failed), `what a day` (clean long), `sweet dreams` (clean), `epic dreams` (long), `dreamt of nothing` (quiet), `spooky dreams` (halloween), `snowy dreams` (winter), `zzz... hi!`, `had a dream` (plain).

Verdict: a formula. Nine of the 17 lines are "<adjective> dreams". `bug nightmares`, `where were u?` and `dreamt of nothing` have character. `sweet dreams` is what you say to someone going to sleep, not on waking. `had a dream` is bland.

### B6. Is it one consistent cheeky character?

No. There are three registers.

1. **The pack's signs and replies:** lowercase, text-speak, emoticons: `u`, `ur`, `thx`, `idk`, `lol`, `nite nite`, `<3`, `:(`, `*hug*`. Tone: a teasing kid.
2. **The voice words** (takes.tsv): capitalised dictionary words and action-movie chatter: `Debrief`, `Reporting for duty`, `Scout reporting`, `Squad goals`, `Jawohl`, `Mission update`, `Execute`, `Standby`, `Cease`, `Behold`, `Smooth operator`, `Bada bing bada boom`, `Bruh moment`. Plus many languages: `Salut`, `Andiamo`, `Vamos`, `Dai`, `Tadaima`, `Yatta`, `Aigo`, `Shiba`, `Chotto`, `Attends`, `Basta`, `Evviva`, `Ole`, `Yare yare`, `Mamma mia`, `Finito`, `Piano`, `Voila`. Nothing in `personality.md` says Boop is a polyglot or a tiny soldier.
3. **Code-made signs:** Title case with a "!": `Level 12!` (Core.swift:534), `Today's done!` (Core.swift:537), `Tap me!` (Runtime.swift:597), `Happy Halloween!`, `Happy New Year!`, `Programmers' Day!`, `Day 50!`, `1 month old!` (Days.swift:27-99). The pack would write `lvl 12!!` or `we did today`.

A buyer hears "Jawohl" and reads "nite nite" from the same creature in one minute. Pick one. The signs' register is the better one, because it is specific and it is the one `personality.md`'s examples use ("so cute lol", "still broken?!").

### B7. Thin sections and days to the first repeat

Assumptions for one buyer on a workday: 8 hours at the Mac, about 40 prompts, 3 to 5 locks, 1 wish, at most 2 notices (Notices.swift:26), at most 1 musing an hour (Signs.swift, `musingEveryMs`), 1 dream told each morning. Jev picks among the offered lines, and it answers "much the same at the same prompt" (internal/EVALS.md:262), so real variety is lower than the line count.

| Section | Lines | How often it fires | First repeat |
| --- | --- | --- | --- |
| asks: questions | 2, both `keeps` | up to 3 a day | **Never repeats: the section is empty after day 1 or 2** |
| `[bye working]` | 1 | every first lock in an hour while an agent works: 1 to 3 a day | **Day 1.** Tagged lines are the only ones offered ("only the lines with the most of the moment's tags"), so it is `i got this` every time. |
| ring closing sign `Today's done!` (code) | 1 | once every full day | Day 2 |
| `[wish pet met]`, `[wish chat met]`, `[wish work met]` | 1 each | once on each day a wish is met | Day 2 or 3, per kind |
| `[carry_on]` `onward!`, `[tests]`, `[docs]`, `[refactor]`, `[essay]` | 1 each | several prompts a day are "go on" or about tests | Day 1 |
| tone signs: `[shouting]`, `[polite]`, `[rushed]`, `[careful]`, `[playful]` | 1 template each | several a day | Day 1 for the template; the words change |
| `[idle]` musings | 4 plain (2 need data) + 1 by snack | at most 1 an hour | Day 1 |
| `[notice waiting]` | 3 | about once a day (13 of the 17 notices in the final eval run, TODO.md:103) | Day 3 or 4 |
| `[world boop/wave/heart]` | 2 + 2 generic each | up to 3 an hour | The same hour, on a busy day |
| `[hello morning]` | 1 | a spoken hello in the morning | Day 2 |
| dreams | 17, 3 to 5 fit a normal day | once a day | Days 3 to 5 |
| `[wish pet]`, `[wish chat]`, `[wish work]` | 3 each, rotated by day | 1 wish a day; chat is "most of them" (TODO.md:157) | Day 4 |
| `[notice stretch]`, `[notice rough]` | 3 each | at most once a day each | Day 4 |
| `[ouch]`, `[nap]`, `[unhush]`, `[notme]` | 2 each | only when spoken to | Second use |
| `[notice late]` | 3 | rests 7 days | Week 4 |

### B8. Bland lines

- Signs: `bug hunt`, `new thing!`, `tidy time`, `hmm?`, `quiet day...`, `{turns} turns today!`, `{agent} sits idle`, `{agent}'s waiting`, `{agent}'s done`.
- Replies: `morning!`, `zzz`, `nap time`, `woo!`, `yay!`, `bye bye`.
- Asks: `<3` (pet met), `i hear u`, `work with me?`, `give me work?`.
- Dreams: `had a dream`, `what a day`, `sweet dreams`.
- Voice words: see C4.

### B9. The mood files: candidates to merge

Sixteen lasting moods. Each file is mostly a list of exits ("Leaves for …"). About 70% of each file is the same six clauses, repeated: "sad when a very long turn fails, the agent gives up or the person shares sad news", "wounded at rude words to Boop", "annoyed at 2 pokes in a row", "excited when a very long turn finishes done or the person thanks the agent", "proud when a check passes after failing or a long turn's hard work is done". These could be said once in `guide.md`.

**1. comfy and lazy are the same file.**

comfy.md:
> Stays comfy through idle check-ins, quick wins and kind words, unless CONTEXT says its wish is waiting 1 h or more. Leaves for lazy as nothing goes on; happy at a win; surprised at a big event; lonely at an idle check-in when CONTEXT says its wish is "waiting 1 h" or more, in hours, or back after 20 to 40 hours away. Fades to calm once Boop has been comfy for 10 min.

lazy.md:
> Stays lazy through idle check-ins, routine turns and quick wins, unless CONTEXT says its wish is waiting 1 h or more. Leaves for engaged when a long turn works on; comfy at kind words; surprised at a big, sudden event; lonely at an idle check-in when CONTEXT says its wish is "waiting 1 h" or more, in hours, or back after 20 to 40 hours away. Fades to calm once Boop has been lazy for 10 min.

Their faces also overlap ("Its faces lean comfy and pleased" / "Its faces lean lazy and comfy"). The voice cannot tell them apart: calm, comfy and lazy share one voice group ("calm comfy lazy bored relieved tired exhausted", 329 takes).

**2. calm and comfy.** calm.md: "Boop is settled and content, at rest: nothing much is going on." comfy.md: "Safe and snug: all is quiet, and it's nice." One feeling, two intensities. With lazy that is three "nothing is happening" moods.

**3. annoyed, irritated and grumpy are one ladder in three files.** The files define themselves by each other:

- annoyed.md: "Boop is mildly put out: one thing failed, or 2 pokes. Milder than irritated."
- irritated.md: "Boop's patience is fraying: failures or pokes keep coming. More than annoyed, short of grumpy."
- grumpy.md: "Boop is fed up: turns failed, or pokes kept coming."

All three give a win "a grudging" happy or proud face. A buyer cannot tell irritated from annoyed on a 2-inch screen. One mood, "cross", with a size would do the same work.

**4. sad and wounded.** sad.md: "Boop is deflated: a very long turn failed, the agent gave up…". wounded.md: "Boop is hurt and withdraws: rude words, or a big failure after a lot of work. Quiet, not sulky." Both are ended at once by the person taking it back, both fade to calm after 10 min. Wounded's own cause list includes sad's ("a big failure after a lot of work").

**5. curious and surprised.** surprised.md: "It's brief: the next NOW decides… Fades to curious once Boop has been surprised for 1 min." A mood that lasts one minute is a Moment, not a mood. They share one voice group.

**6. happy and excited.** Both "lean happy and excited" / "lean excited"; excited fades to happy after 5 min.

**7. sad and lonely** share one voice group ("sad disappointed crying lonely"), which plan/product-ideas.md already notes ("Lonely's own voice takes: it borrows sad's, which may sound too heavy").

A buyer-level set would be about 8: calm (with comfy and lazy as pastimes), curious, engaged, determined, happy (excited as its big size), proud, cross (annoyed, irritated, grumpy as sizes), sad (wounded and lonely as causes).

**Inconsistencies between the mood files:**

- **The poke ladder differs by file.** calm, happy, curious, proud: "annoyed at 2 pokes in a row". annoyed.md:8 and determined.md:10: "irritated at 3+ pokes". irritated.md:6: "grumpy at … 4+ pokes in a row". But sad.md:16 and wounded.md:12: "grumpy at 3+ pokes", which skips irritated.
- **A long-waiting wish leads to different moods by file.** calm.md:14: "lonely, sad or annoyed". happy.md:11: "annoyed or sad" (no lonely). comfy.md and lazy.md: "lonely" only. lonely.md:3 says lonely is what a wish waiting an hour causes.
- **Rude words have no exit from seven moods.** "wounded at rude words to Boop" is in calm, happy, curious, proud, annoyed and sad. It is missing from engaged, determined, excited, comfy, lazy, irritated and grumpy. personality.md:108 says "rude words hurt it" always.
- **grumpy.md says saying sorry "ends it at once"** and then that the result is "irritated, or annoyed, with that face, never a content one". So an apology to a grumpy Boop still shows a cross face. That may be intended, but a buyer who says sorry and gets an irritated face will read it as "it didn't hear me".

---

## C. The voice

Sources: `characters/boop/mac/takes.tsv` (3,482 lines, version `353ddadc006b`), `app/BoopKit/Voice/Voice.swift`, `characters/CHARACTER.md` §8, `plan/voice-range.md`.

### C1. Counts

- **3,479 takes, 486 distinct texts.**
- By kind: 2,637 words, 520 sounds, 304 phrases, 18 swears.
- By part: 2,016 `about` (16 topics), 599 `feeling` (4 feelings), 864 `reply` (17 replies).
- Recorded in 13 mood groups; the 42 faces each borrow one group.
- Swears: 5 texts, `Crap`, `Damn`, `Fuck`, `Shit`, `Shiba`.

Distinct texts by meaning: upset 49, looking 41, glad 40, work 25, start 20, helper back 18, waiting 18, no 18, tests 17, hello (reply) 17, answer 16, done 16, helpers 16, planning 16, retry 16, stopped 16, thanks 16, yes 16, bye 12, dance 12, huh 12, love 12, status 12, tickled 12, comfort 11, dunno 11, hehe 11, nap 11, ouch 11, unhush 10, shaken 9, command 8, tool 8, quiet 8, hello (about) 8, hush 8, notme 8.

### C2. Recorded and placeholder

- **437 takes are espeak placeholders (ids `placeholder.*`), covering 128 texts. 118 texts exist only as placeholders.**
- Every placeholder is in the `reply` part. So everything Boop says back when you talk to it is, in part, a robot voice.
- Placeholder share by reply: notme 29 of 29 (100%), bye 32/52, ouch 28/42, comfort 24/33, yes 54/77, dunno 20/29, no 43/73, love 28/50, huh 18/33, hush 21/40, dance 18/35, status 24/55, thanks 20/47, nap 21/60, hehe 18/53, hello 27/103, unhush 12/53.
- The `about` and `feeling` parts are all recorded (ids `phase1.*`, `previous.*`, `new.*`).
- plan/voice-range.md:3-6 confirms it: "step 4's new lines spoken by placeholders; nothing new is recorded: new paid takes need the owner's go".

### C3. How say → take works

1. Jev answers the `say` question: nothing, a feeling (`upset`, `glad`, `tickled`, `shaken`), a swear, or what NOW is about (one of 16 topics). For a reply to your words, the reply's own takes are used.
2. The Moment's size picks the kind: small a sound, medium a word, big or huge a phrase (CHARACTER.md §8).
3. The face picks the mood. `Voice.take` (Voice.swift:34-46) keeps takes where part and meaning match, the take's moods include the face, and the finish fits (a success take only on a success, a swear only on a failure).
4. It tries the asked kind first, then the nearest kinds (`order`, Voice.swift:18-23).
5. It avoids texts said lately; when all were said, it takes the one said longest ago (`fresh`, Voice.swift:50-55).
6. Half the time a word gets a lead sound of the same meaning and mood first, "Ugh.... Broken" (`lead`, Voice.swift:73-84), with a 2.8 s cap.

### C4. Repetition risk

Distinct texts available **in one face** (min / median / max over the 42 faces):

| Meaning | Sounds | Words | Phrases |
| --- | --- | --- | --- |
| glad | 4 / 12 / 12 | 0 / 12 / 12 | 0 / 0 / 8 |
| upset | 0 / 0 / 14 | 10 / 10 / 13 | 0 / 0 / 8 |
| looking | 0 / 0 / 8 | 16 / 16 / 16 | 0 / 0 / 17 |
| work | 0 / 0 / 8 | 9 / 9 / 9 | 0 / 0 / 7 |
| tests | 0 | 9 / 9 / 9 | 0 / 0 / 6 |
| command, tool, quiet | 0 | 8 / 8 / 8 | 0 |
| done, answer, retry, planning, stopped, helpers | 0 | 8 / 8 / 8 | 0 / 0 / 8 |
| tickled | 0 | 5 / 5 / 5 | 0 / 0 / 5 |
| shaken | 0 / 0 / 1 | 3 / 3 / 6 | 0 / 0 / 1 |
| replies (comfort, dance, dunno, huh, notme, ouch, love, hush) | 0 to 2 | 0 to 1 median | 0 median |

What this means:

- **Small is the usual size and wants a sound, but only glad has sounds in every face.** Every other small moment says a word.
- **Big moments want a phrase, and the median face has none, for every meaning.** So the fallback word plays. The charming phrases ("Fingers crossed", "Please work", "Moment of truth", "Go, little test", "Buffering brain", "Tiny gears") are each recorded in one mood group.
- **So the usual line is a bare word.** For tests, the nine words in any face are: `Checking`, `Measure`, `Passed`, `Probe`, `Test`, `Testing`, `Trial`, `Validate`, `Verify`. This is the "Verify, Trial" problem in plan/v1-buddy.md:94. It is not two bad words. It is the whole word tier.
- **Working check-ins come every 4 to 6 minutes** (personality.md:2) "with a word about the work". In 4 hours of agent work that is about 48 lines from pools of 8 or 9. `command` (`Code`, `Compile`, `Execute`, `Process`, `Run`, `Script`, `Shell`, `Terminal`) and `tool` (`Call`, `Connect`, `Fetch`, `Load`, `Query`, `Request`, `Sync`, `Tool`) will each cycle fully in a morning.
- **`quiet` has 8 words** (`Chill`, `Comfy`, `Cozy`, `Hullo`, `Mellow`, `Ohh`, `Peace`, `Quiet`) for every idle word. TODO.md:99 notes "a lonely face can still say 'Cozy'".
- **A reply to your words has 0 to 1 word and 0 phrases in the median face.** Asked to dance, most faces can only say `Dance!` or nothing.

Bland label words, about 55 of the 486 texts: command (all 8), tool (all 8), tests (`Measure`, `Probe`, `Trial`, `Validate`, `Verify`, `Test`, `Testing`, `Checking`), looking (`Browse`, `Compare`, `Inspect`, `Scan`, `Sort`, `Study`, `Trace`, `Read`, `Search`, `Seek`), stopped (`Cease`, `Halt`, `Stopped`, `Stop`), retry (`Reboot`, `Recheck`, `Redo`, `Rerun`, `Restart`, `Rewind`, `Retry`), waiting (`Pending`, `Standby`, `Waiting`, `Hold`), done (`Complete`, `Cleared`, `Finished`, `Success`), answer (`Answer`, `Reply`), helpers (`Assist`, `Backup`, `Helpers`).

---

## D. Narration

Sources: `app/BoopKit/Core/Narration.swift`, `app/BoopKit/Core/Touch.swift:66-84`, `firmware/src/app/touch_reason.h`.

Each reason has a sentence for the Mac ("cause") and, where the screen does not already show it, a caption for the board of at most 18 characters ("fact").

### D1. The templates

| Moment kind | Mac sentence | Board caption |
| --- | --- | --- |
| You came back | `You came back after 12 hours away.` | `you were away 12 h` / `away 12 h` |
| You stepped away | `You stepped away.` | `you stepped away` |
| Lock / unlock | `You locked the Mac.` / `You unlocked the Mac.` | `you locked the Mac` / `you unlocked it` |
| Poke | `You poked it.` / `You poked it 3 times in a row.` / `You poked it while it slept.` | `you poked Mochi` / `you poked Mochi x3` / `you woke Mochi` |
| Stroke | `You stroked it.` | `you stroked Mochi` |
| Lean | `You held a finger on it.` | `you held Mochi` |
| Ruffle | `You stroked it the wrong way.` | `you ruffled Mochi` |
| Nose boop | `You booped its nose.` | `you booped Mochi` |
| Tickle | `You tickled it.` | `you tickled Mochi` |
| Shake | `You shook it.` / `You shook it 3 times in a row.` | `you shook Mochi` / `… x3` |
| Pick-up / put-down | `You picked it up.` / `You put it down.` | `you picked Mochi up` / `you put Mochi down` |
| Thump | `You thumped the desk.` | `a thump nearby` |
| Face down / back up | `You turned it face down.` / `You turned it back up.` | `you turned Mochi over` / `you flipped Mochi up` |
| Swipe | `You swiped it.` | none |
| Dismiss | `You held a finger on the needs-you screen, to stop it showing.` | none |
| Ask | `Nobody answered its question.` / `It will remember: cookie.` / `You answered: pizza.` | none / `Mochi will remember` / `you picked pizza` |
| Your words | `You said "…".` (up to 160 characters) | none (the sign answers) |
| Level | `Mochi reached level 5 and grew: it's a Sprout now.` | `level 5!` |
| Ring | `Today's ring is full. Nice work.` | `today's done!` |
| World | `Someone in the Americas booped Mochi.` | `someone booped Mochi` / `a boop from afar` |
| Wish made / met / left | `Mochi wants a pet.` (+ `: you haven't said hi today.`) / `You gave Mochi its wish: a pet.` / `Mochi wished for a pet, and you left it.` | `Mochi wants a pet` / `wish met!` / `wish left` |
| Button | `You pressed its button.` / `You opened a thread from its drawer.` | none |
| Hush | `You told it to be quiet for 30 minutes.` / `It may talk again.` | `you hushed Mochi` / `Mochi may talk` |
| Your prompt | `You asked claude for a fix on api, sounding frustrated.` | `you asked claude` |
| Needs you | `claude needs you on api.` / `You answered claude on api.` | none |
| Turn start | `claude started work on api.` | `claude started` |
| Compaction, thread end | `claude's memory on api was compacted.` / `claude's thread on api ended.` | `claude compacted` / none |
| Helper | `claude started a helper on api.` / `A helper of claude's finished on api.` | none |
| Work act | `claude is running the tests on api.` / `The tests on api pass.` / `The push on api failed.` | `claude runs tests` / `tests pass` / `push failed` |
| Check | `The tests on api failed again: 3 times in a row.` / `The build on api passes again.` | `tests failed x3` / `build passes again` |
| Calls failing | `claude's calls on api keep failing: 3 times in 5 minutes.` | `calls failed x3` |
| Working check-in | `claude has been working on api for 25 minutes.` | `working 25 min` |
| Idle check-in | `Nothing has happened for 20 minutes.` / `You've been here 3 hours and haven't touched it.` | none / `no touch in 3 h` |
| Finish | `claude's turn on api failed.` / `…was stopped.` / `claude gave up…` / `claude has a question for you…` / `claude got the tests passing…` / `claude finished 3 quick turns in a row…` / `claude finished a long turn…` / `claude answered you…` / `claude finished a turn…` | none (the low sign names the thread) |
| Notice | `It noticed <fact>.` appended to the cause | the notice's short: `claude idle 20 min`, `2 h at the Mac`, `a rough hour`, `you sounded sharp`, `past midnight` |
| Remembered line | `Mochi remembers you stay up late on Fridays.` | |
| First showing up | `Day 41. <dream's sentence>` | `day 41: …` |
| Sleep, wake | `No agents are open, so Mochi went to sleep.` / `Nothing's happened for an hour, so Mochi dozed off.` / `claude got to work on api, so Mochi woke up.` | `no agents open` / `quiet for 1 h` / `claude woke Mochi` |
| Mood moved, nothing else to show | | `Mochi's grumpy now` |

### D2. Are they plain, and do they answer "why did it do that?"

Mostly yes. They are short, they use "you", and they never quote the brain. The firmware captions match the Mac's (touch_reason.h:14-25 against Touch.swift:68-80; a test holds the two together).

Gaps:

1. **The reason says what happened, not why this feeling.** "Mochi is proud. claude finished a turn on api." does not say why proud and not happy. For a finish the board shows no caption at all (Narration.swift:260, "No fact: the finish's sign names the thread"). A reader cannot tell a "comeback" finish from a routine one on the board.
2. **A mood that settled by itself has no sentence of its own.** The popover shows the latest change's cause (MoodOutput.swift:33-36). After a fade this is "Mochi is calm. Nothing has happened for 20 minutes." That is acceptable. But the same rule means the popover can show "Mochi is annoyed. You poked it 2 times in a row." long after, until the event leaves the log.
3. **Kinds with no reason** (`Narration.of` returns nil):
   - A wish that ended with the day (`closed`), Narration.swift:112-115.
   - A prompt with no reading, Narration.swift:124.
   - A return with no `away_ms`, Narration.swift:71.
   - A check-in with none of the four facts, Narration.swift:162, which includes the hourly check-in.
   - Any tool event that is not a check or a failing run, Narration.swift:287.
   - The silent list (Narration.swift:171-179): listening, link, dream, memory, last message, tool start, tool wait.
4. **A musing or an ask has no reason of its own.** It plays at an idle check-in, so the reason is "Nothing has happened for 20 minutes." That says when, not why Boop asks "fav snack?".
5. **Three captions have no board text:** swipe, dismiss, button. By design.
6. **Tone:** two reasons scold (Narration.swift:153 and :114, see A7). The notice facts were written for Jev and read as monitoring.

---

## E. The onboarding script, as a first-time buyer

Nine acts (`BoopKit/App/Onboarding.swift:9`): hello, whatIDo, makeMeYours, body, howTo, agents, smallThings, world, finale. Window title: "Welcome to Boop".

### E1. The text, in order

**1. Hello** (OnboardingIntro.swift:24-36)
- Bubble: "Hi! I'm a Boop."
- "A little creature for your desk. I keep an eye on your coding agents, and I'll show you how in a couple of minutes."
- Button: "Hi, Boop!"

**2. What I do** (OnboardingIntro.swift:143-165)
- "I keep an eye on your agents"
- Card: "Working along. The files, searches and commands of your agent fall past me. Failures hit me."
- Card: "Needs you. I glow amber and knock, and say who's waiting."
- Card: "A big finish. I cheer work that earns it, and hold up whose it was."
- "I only watch. I never approve, deny or block anything for you."
- Button: "Neat!"

**3. A name** (OnboardingIntro.swift:287-319)
- "What should I be called?" Field: "A name".
- "My name is for keeps, so pick one you love."
- "Other buddies in the world will see it too."
- Bubble: "Mochi! I love it." Button: "That's me".

**4. The body** (OnboardingBoard.swift:40-202)
- "Let's find my body. Plug the board on your desk into power with its USB cable. Its screen lights up when it's on."
- "macOS will ask if I can use Bluetooth. Say OK, so I can find my body."
- Buttons: "Look for me" / "I don't have my Boop yet".
- "Looking for my body… Keep me plugged in and close by."
- After 20 s: "Can't see me yet. Is my screen on? Try unplugging me and plugging me back in."
- Found: "FOUND MOCHI. Tap my screen on your desk. I'm the one holding up “Tap me!”. A tap is also how you poke me, any time."
- "There you are! That's me on your desk. Say hi to my body."
- Maybe: "I'm a bit hungry. Feed me an update?" / "Firmware 1.0. Plug me into this Mac with a USB cable, then update. About half a minute." / "Eating… 40%. Keep the cable in." / "Yum. I'm on 1.0 now."
- Maybe: "I've lost my voice: there's no voice file on my card. I'll still show everything; Settings says how to fix it."

**5. How to** (OnboardingBoard.swift:260-363)
- "Here's how we get along"
- 1 "Tap my screen. I poke back. Tap a lot and I get grumpy."
- 2 "Press my button. The one on my side. It opens your next agent, or pokes me. Try it now."
- 3 "Hold my button and talk. Say hi, cheer me on, tease me, ask about your agents, or tell me to hush. I answer with a face and a sign, and often a word. macOS asks for the microphone the first time." TRY: “hi Mochi!”, “good job!”, “how many agents are running?”
- 4 "When I glow amber, tap me. I'm glowing amber now, as if an agent were waiting. Tap me to answer it."
- "HOW I FEEL": Happy "it's going well", Grumpy "failures pile up", Proud "a big finish", Tired "a long day".
- "My mood holds steady. Big moments move it, and it settles back with time."
- Button: "Got it".

**6. The agents** (OnboardingFinish.swift:20-240)
- "Which agents should I watch? I listen through their hooks. I never approve, deny or block anything."
- Toggles: "Watch Claude Code", "Watch Codex" with "Found on this Mac".
- Disclosure "See exactly what gets added" (130 words, quoted in F2).
- Button: "Connect".
- "Say hi from your agent. Open a new Claude Code session, and ask it to list the files here. I'll wave when your agent's first hook reaches me."
- "Heard you! Claude Code is connected. Now let me show you around."
- Tour: "Watch my screen. What your agent works on falls past me as words. Nothing yet? Ask it to list the files here." / "When I cheer, tap me. When your agent finishes, I cheer and hold up its thread's name. A tap takes you there." / "Swipe up from my bottom edge. Every agent you have open is in there." / "Tap your thread. It opens right where it runs. That's how you get back to any of them."
- "Sessions already open need a restart to pick up my hooks."
- Buttons: "Next" / "I'll try it later" / "Skip the tour".

**7. A few small things** (OnboardingFinish.swift:290-358, OnboardingBrainKey.swift:22-56)
- "I'll be here when you log in. I only watch your agents while I'm open." Toggle "Open at login".
- "Want to talk to me? macOS will ask for the microphone and speech. Your voice stays on this Mac; only the words, cut short, reach my brain." Button "Allow".
- "Give me a brain. A Jev API key lets TypeSafe's AI pick how I react and what mood I'm in. Without one I still show what your agents do and when you're needed." Link "Jev's docs". Field "Jev API key". Button "Save".
- After a save: "Now I can answer you. Hold my button and ask me “how many agents are running?”"

**8. The world** (OnboardingWorld.swift:14-30)
- "I live in a world of buddies. Everyone's buddies are in it together. We can wave at each other, and send a boop or a heart."
- "Others see": "My name and level", "Roughly where I am, by time zone", "What I'm doing, in one word", "Counts, like tests passed".
- "Nobody sees": "Your name", "Your projects and code", "What you say", "What I remember about you".
- "You can change this in Settings any time."
- Buttons: "Sounds good" / "Keep Mochi private".

**9. Finale** (OnboardingFinish.swift:374-395)
- "Mochi is all set!"
- Tips: "Hold my button and ask how your agents are doing" / "Amber, or cheering? Tap me to open that thread" / "Swipe up from the bottom for every agent; tap one to open it" / "Find me in the menu bar, up top".
- Button: "Let's go!"

### E2. Judgement

**Voice: very good.** First person, short, funny ("Feed me an update?", "Yum.", "That's me"). It is the standard the rest of the UI should meet.

**Length: too long for "a couple of minutes".** About 600 words on screen, plus 130 behind the disclosure. The buyer must do about 20 things: 2 clicks, type a name, plug in, allow Bluetooth, tap the board, maybe update firmware, 4 lessons (one needs a microphone permission), pick agents, open a terminal, start a new agent session and type a prompt, 4 tour steps, a login toggle, a mic permission, a key, the world screen, the finale. Realistic time: 8 to 12 minutes, and act 6 sends the buyer out of the window to a terminal.

**It teaches twice.** Act 5's four lessons, act 6's four tour steps and the finale's four tips cover the same six gestures. The ground rule is "Nothing a buyer has to be taught. The screen says what to do, or a touch does the obvious thing" (plan/product-ideas.md). The pack already has "how" signs for wishes (`stroke my face?`). The board could teach each gesture the first time it matters, and act 5 could go.

**Clarity problems:**

- Act 4 says "the board on your desk" and then "my body". Say "me" ("Plug me in").
- "Firmware 1.0." breaks the "feed me" joke with a jargon word (OnboardingBoard.swift:199).
- Act 6: "I listen through their hooks" and "your agent's first hook reaches me". A Claude Code user may know hooks. The sentence does not need the word.
- Act 6 uses "thread" 5 times; the popover says "Sessions".
- Act 5 lesson 2: "It opens your next agent, or pokes me." "Opens your next agent" is unclear before any agent is connected (agents come in act 6).
- Act 5 lesson 3 comes before the brain exists. The reply is "I heard “…”. I'll answer once I have a brain, in a couple of steps." (OnboardingBoard.swift:359). Honest, but the first time the buyer talks to Boop, Boop cannot answer. Move the key before the talk lesson.

**If the board is not found:** handled well. Bluetooth trouble gets its own title "I can't look for my body" with a button to the right System Settings page (MenuBarApp.swift:482-484). After 20 s the hint changes. "I don't have my Boop yet" skips; act 5 then says "You'll try these on my body when we meet." and the finale says "Got my body? plug it in, and I'll find it". Two gaps: there is no "it's taking long, here is help" link, and the lost-voice line sends the buyer to a Settings text about `voice.bin` and FAT32.

**The world screen's consent wording:**

- It follows plan/world.md §9: it tells, with a plain "Keep Mochi private" link, and nothing is sent before it is shown.
- **"On by default" is implied, not said.** The title is "I live in a world of buddies" and the main button is "Sounds good". A buyer reads this as an invitation and a yes. That is fair. But the screen never says the plain facts: "this goes over the internet to Boop's server", or "I've already said yes for you". One line would do: "I'll join when you click. It's Boop's own server, on the internet."
- **What is said about sharing** is four lines for "Others see" and four for "Nobody sees". The "Nobody sees" list is the stronger half and it is true for the world. "Counts, like tests passed" hides three other counts (see F1).
- **"Your name" under "Nobody sees" can be false.** If the buyer names the buddy after themselves, others see it. The naming screen warns ("Other buddies in the world will see it too."), but that is five acts earlier.
- **The name is public and "for keeps".** There is no rename in Settings. A typo or a regretted name stays in the world unless the buyer goes private.
- "You can change this in Settings any time." is good. It could add that leaving removes the buddy from the world (the client calls `DELETE /v1/buddies/me`, WorldClient.swift:117).

**Privacy wording:** "I only watch. I never approve, deny or block anything for you." is said three times (acts 2 and 6, and the disclosure). Good. The mic line is accurate. The brain's privacy is only in the hooks disclosure, which most buyers will not open.

**The Jev key:**

- It is asked in act 7, as the third card of "A few small things", after login and microphone.
- **A buyer cannot get one from this screen.** The only link is "Jev's docs" → `https://docs.typesafe.ai/api` (MenuBarApp.swift:416): API documentation. No "create an account", no price, no "this costs about X a month". "A Jev API key lets TypeSafe's AI pick how I react" uses three unknown nouns in nine words.
- **With no key:** Boop shows the work stream, needs-you and the finish. It does not react, its mood never changes, and it "shrugs when you talk to it" with the signs `no brain yet :(` / `need my brain!` (replies.md:18-19). The popover shows a dismissable "X has no brain yet" notice (OverviewPane.swift:60), and its button opens Settings, where there is no link to get a key (SettingsPane.swift:357-382).
- So the product's main promise, "a personality of its own", is behind an optional card with no path. The plan accepts a key "for now" (plan/product-ideas.md). The wording should still say what it is and how to get it, and it should be its own act, before the talk lesson.

**Swearing:** nothing in onboarding or Settings says Boop may say "Fuck" or "Shit" aloud on a failure. Only Talk: Quiet stops it ("never a swear", ContextSection.swift, the Talk row). A buyer in an open office finds out the loud way.

---

## F. Trust: what the UI says against what the code does

### F1. The world

What the Mac sends is `World.State` (WorldWire.swift:90-104) by `PUT /v1/buddies/me`, and `Join` (WorldClient.swift:79-83) once. The comment at WorldWire.swift:88 says "this, and nothing else, leaves the Mac. A test fails if a key is added."

| Field sent | Said in onboarding? | Said in Settings? |
| --- | --- | --- |
| `name` | yes, "My name" | yes |
| `level` | yes | yes |
| `stage` (hatchling, sprout, buddy, chonk) | no | no |
| `utc_offset`, rounded to 15 minutes (Runtime+World.swift:38) | yes, "Roughly where I am, by time zone" | yes, "rough time zone" |
| `activity`, one of six | yes, "What I'm doing, in one word" | yes |
| `day`, the buddy's local date | no | no |
| `xp_today` | no | no |
| `added.tests_passed` | yes, "Counts, like tests passed" | yes |
| `added.turns` | only by "like" | only by "like" |
| `added.ships` | only by "like" | only by "like" |
| `added.lines_changed` | only by "like" | only by "like" |
| `seq` | no (a counter, harmless) | no |
| A gesture: `to` (a buddy's id) and `kind` | implied | implied |
| The Mac's IP address and `User-Agent: Boop/<version>` | no | no |

Findings:

1. **Nothing sensitive is hidden, but the list is not "all of it".** plan/world.md §9 lists "counts (turns, tests passed, ships, lines changed, today's XP)". The UI names one of five.
2. **"Nothing about you or your code" (SettingsPane.swift:81) is too strong.** Lines changed, turns and ships are numbers about your work, and `activity` plus `utc_offset` say when you are at your desk and when you sleep. A truthful line: "Nothing you write, and nothing from your code."
3. **"Others see" overstates.** Other buddies get `name`, `level`, `stage`, `utc_offset`, `activity` (World.Buddy, WorldWire.swift:140-158) and totals. Your own counts go to the server and come back only as world totals. The screen could say so; it is a point in Boop's favour.
4. **The server's address is `boop-world-michaeljxzhu.vercel.app`** (WorldClient.swift:8). A buyer who looks at network traffic sees a personal Vercel name. Use a product domain before selling.
5. **"Nothing is sent before that screen has been shown"** holds in code (`worldScreenShown`, OnboardingModel.swift:404; Runtime+World.swift:104).
6. CLAUDE.md's architecture rule lists "the buddy's name, level and stage, its UTC offset, one of six activities and counts". It leaves out `day` and `xp_today`. A small doc gap.

### F2. Jev (the brain)

What the UI says:

- Onboarding disclosure (OnboardingFinish.swift:89-90): "My brain only ever hears a short reading of your prompt and the reply, never your code or the glimpses."
- Settings (SettingsPane.swift:382): "What X notices goes to TypeSafe, never your code."
- Mic (OnboardingFinish.swift:358): "Your voice stays on this Mac; only the words, cut short, reach my brain."
- Memory (MemoryPane.swift:19): "Its notes go to the brain with each request, and nowhere else."

What the prompt builder includes:

| Goes to Jev | Where in code | Said in the UI? |
| --- | --- | --- |
| The prompt's reading: kind, length, tone, whether you said the buddy's name | EventLine.swift:101-106 | yes, "a short reading" |
| **Up to 3 phrases copied exactly from your prompt**, each up to 18 characters ("Your words: "still broken", "keep happening"") | PromptReading.swift:62 (`phrases: up to 3 short phrases copied exactly`), Reading.swift:143-144, EventLine.swift:110 | **no** |
| The agent's last message's reading, and **up to 3 of its phrases** ("Its words") | MessageReading.swift, EventLine.swift:113 | partly ("the reply") |
| **Project, workspace and thread names** ("claude on "fix-nav" (landing)") | EventLine.swift:343-345, ContextSection.swift `agents` | **no** |
| What you say to Boop, cut to 300 characters | EventLine.swift:86, 170 | yes |
| The written memory's notes (You, Your work, You and Boop, Recently) | the MEMORY section | yes |
| The buddy's name, level, age, today's ring; how long you have been at the Mac; how long since you touched it; turn and failure counts; the clock, weekday and special days | ContextSection.swift | no, but harmless |
| What Boop noticed: "you've been at the Mac for 2 h with no break", "up past 1 on 4 of the last 7 nights", "you sounded sharp a while ago" | Notices.swift:114-139 → CONTEXT's Noticed row | **no**. These are habits about the person. |
| Topics of commands (tests, build, deploy, docs) and pass or fail | EventLine.swift:321 | no, but it is not code |

Not sent, as claimed: the prompt's full text, code, commands, tool output, file names from the work stream ("the glimpses"). The prompt is labelled on the Mac by Apple Intelligence (PromptLabeler.swift:10-12, "so the prompt never leaves the Mac"); on a Mac without it, only counted facts are used.

Findings:

1. **"Never your code" is true. "A short reading" is not the whole truth.** A few of your own words, your project names and your habits also go. A copied phrase of 18 characters can be a function name or a customer's name. The reading "scrubs" secrets (Reading.swift:205, "none a secret"), which is good and worth saying.
2. **The fullest statement is hidden** behind "See exactly what gets added", in a paragraph about hooks. Settings' one line is the only place a buyer will look later, and it is the vaguest.
3. **The memory line is accurate.**
4. **Suggested single truthful sentence**, for Settings and onboarding: "My brain gets a short summary of what happens, a few of your own words, your project names and what I remember about you. Never your code, your files or your full prompts."

---

## G. Known personality problems, with references

| Problem | Reference | What this audit adds |
| --- | --- | --- |
| **Idle may be too quiet.** "36 of 83 idle check-ins have a moment, 8 of them a real face, and 5 a word, all on Chatty. On one workday, moments went from 13 of 13 to 4 of 13." | plan/TODO.md:101; plan/v1-buddy.md:92 | personality.md:33 asks for it ("mostly gets nothing"). And there are only 4 musings and 2 asks to show, so more idle moments would repeat within a day. Content must grow first. |
| **Notices are faint.** "`stretch` and `rough` chose no sign and no face in `173`, `180`, `181`: in the eval's record only the narration shows them" | plan/TODO.md:103; plan/v1-buddy.md:89; evals `173-a-workday`, `180-noticed-stretch`, `181-noticed-rough` | The steering asks for "a small look up at you" (personality.md:31). A small look with no sign cannot be told from a pastime. |
| **"claude sits idle" is flat.** "is 13 of them [17], and reads as a flat report, not care" | plan/TODO.md:103; eval `179-noticed-waiting` | All three `[notice waiting]` lines are reports (signs.md:38-40). personality.md:31 steers to this sign by name. The Mac's reason is also a report ("It noticed claude has sat idle on "api" for 20 min."). |
| **Notice evals pass with no sign.** "Evals 179 to 186 pass even if a notice's sign never shows." | plan/TODO.md:197 | |
| **Bland words: "Verify", "Trial".** | plan/v1-buddy.md:94 | It is the whole word tier of the voice, about 55 words (C4). |
| **Proud everywhere.** "proud finishes nearly everywhere" | plan/v1-buddy.md:94 | Four places in personality.md and seven mood files steer to proud (B1). |
| **Faces repeat.** "168 of 581 faces in the last run matched the one before" | plan/TODO.md:247-250 | A guideline was added (guide.md:17). The code half ("dropping the last face") is not built. |
| **The voice does not know the face.** "a lonely face can still say 'Cozy' on a calm mood, because `say` doesn't know the face" | plan/TODO.md:99 | Calm, comfy and lazy share one voice group; lonely borrows sad's (C1, B9). |
| **A finish just after its fix still goes big.** | plan/TODO.md:168; eval `11-comeback-still-showing` | |
| **Special days feel alike.** "Halloween and day 50 are still alike, as a return offers no sign" | plan/TODO.md:168; evals `90-halloween-morning`, `91-day-50` | The special-day signs are code strings in a different register (B6). |
| **Wishes cluster.** "Every workday wish came before 11:00, and chat is most of them." | plan/TODO.md:157 | With chat most days, the 3 `[wish chat]` lines and the single `i hear u` repeat fastest. |
| **A hush from the Mac does not sulk.** "Jev picks calm (0.56, 0.61) over annoyed (0.27)" | plan/TODO.md:170; eval `129` | |
| **Long quiet grind.** "`18-long-grind` (20 quiet minutes of work, against 7)" | plan/TODO.md:69 | |
| **Judge's odd list:** `121`, `144`, `173`, `180`, `181`, `186`, `28`, `54`, `57`, `85`, `94` | plan/TODO.md:97 | Five of the eleven are idle or notice scenarios. |
| **Lonely's voice is too heavy.** | plan/product-ideas.md, "Lonely's own voice takes" | |
| **Night words not audited.** "Night signs were already gated by tags; the voice's words weren't audited." | plan/TODO.md:105 | |

The eval files (`characters/boop/evals/`, 142 scenarios) hold cases and judge briefs, not known problems. The problems are recorded only in plan/TODO.md and plan/v1-buddy.md.

---

## H. The 25 best string rewrites

| # | Where | Old | New |
| --- | --- | --- | --- |
| 1 | app/Boop/Views/SettingsPane.swift:288 | `Allow \(model.name) in System Settings, under General, Login Items.` | `Allow Boop in System Settings, under General, Login Items.` (bug: macOS lists the app) |
| 2 | characters/boop/steering/asks.md:17 | `hold BOOT, say hi?` | `hold button, hi?` |
| 3 | characters/boop/steering/asks.md:22 | `prompt an agent?` | `give claude a job?` |
| 4 | characters/boop/steering/signs.md:39 | `{agent} sits idle` | `{agent}'s all urs` |
| 5 | characters/boop/steering/signs.md:38 | `{agent}'s waiting` | `{agent} misses u` |
| 6 | characters/boop/steering/signs.md:29 | `onward!` | `again? fine.` |
| 7 | app/Boop/Views/Onboarding/OnboardingBrainKey.swift:34-35 | `A Jev API key lets TypeSafe's AI pick how I react and what mood I'm in. Without one I still show what your agents do and when you're needed.` | `My brain is an AI service called Jev. With a key I have moods, react and answer you. Without one I only watch.` |
| 8 | app/Boop/Views/Onboarding/OnboardingBrainKey.swift:26 | `Jev's docs` | `Get a key` (and point it at a sign-up page) |
| 9 | app/Boop/Views/SettingsPane.swift:382 | `This is how X thinks. It stays in your Keychain. What X notices goes to TypeSafe, never your code.` | `X's brain. The key stays in your Keychain. The brain gets a short summary of what happens, a few of your own words and your project names. Never your code.` |
| 10 | app/Boop/Views/SettingsPane.swift:309 | `Without a Jev API key, X shows what the agents are doing and when one needs you, but doesn't react or change its mood, and shrugs when you talk to it.` | `No brain yet: X watches your agents and tells you when one needs you. It can't feel or answer.` |
| 11 | app/Boop/Views/OverviewPane.swift:61 | `It shows what your agents do and when one needs you. Add a Jev API key in Settings, and X reacts to it, and answers when you talk.` | `X can watch, but can't feel or answer yet. Give it a brain in Settings.` |
| 12 | app/Boop/Views/OverviewPane.swift:485 | `Jev is out of credit` / `Top up your Jev account at TypeSafe. Until then, …` | `X's brain is out of credit` / `Top it up and X feels things again. Until then it only watches.` |
| 13 | app/Boop/Views/SettingsPane.swift:81 | `Its name, level, rough time zone, what it's doing, and counts like tests passed. Nothing about you or your code.` | `Its name, level and size, its time zone, one word for what it's doing, and today's counts: turns, tests passed, ships and lines changed. Nothing you write.` |
| 14 | app/Boop/Views/Onboarding/OnboardingWorld.swift:19 | `Counts, like tests passed` | `Today's counts: turns, tests, ships, lines` |
| 15 | app/Boop/Views/Onboarding/OnboardingBoard.swift:43 | `Plug the board on your desk into power with its USB cable. Its screen lights up when it's on.` | `Plug me in with my USB cable. My screen lights up.` |
| 16 | app/Boop/Views/Onboarding/OnboardingBoard.swift:199 | `Firmware \(v). Plug me into this Mac with a USB cable, then update. About half a minute.` | `Plug me into this Mac with my cable. It takes half a minute.` |
| 17 | app/Boop/Views/Onboarding/OnboardingFinish.swift:21 | `I listen through their hooks. I never approve, deny or block anything.` | `I only listen. I never approve, deny or block anything.` |
| 18 | app/Boop/Views/Onboarding/OnboardingFinish.swift:169 | `I'll wave when your agent's first hook reaches me.` | `I'll wave when I hear it.` |
| 19 | app/Boop/Views/OverviewPane.swift:73-74 | `Restart your agent sessions` / `Open sessions pick up Boop's hooks when they restart.` | `Restart your open agents` / `X can hear them once they start again.` |
| 20 | app/Boop/Views/OverviewPane.swift:89 | `Sessions` / `Sessions · 3` | `Your agents` / `Your agents · 3` |
| 21 | app/Boop/MenuBarApp.swift:584-587 | `…Put this app's voice file on the card, then press the board's reset button.` + the `voice/voice.bin`, FAT32 and exFAT text | `X can't find its voice. Unplug X, wait a moment and plug it back in. Still silent? Tell us.` |
| 22 | app/Boop/MenuBarApp.swift:573-576 | `X's body has another character's faces` / `…Flash the board with the app's character pack.` | `X's body needs an update` / `Update it in Settings.` |
| 23 | app/BoopKit/Core/Narration.swift:153 | `You've been here \(hours) hours and haven't touched it.` | `It's been \(hours) hours since you two said hi.` |
| 24 | app/BoopKit/Core/Narration.swift:114 | `\(name) wished for \(kind.words), and you left it.` | `\(name)'s wish for \(kind.words) went by.` |
| 25 | characters/boop/mac/passing.tsv:58-59 | `getting ready for the work act` / `coming back from the work act` | `getting into costume` / `packing its props away` |

Next in line: Narration.swift:284 (`calls` → `commands`), Narration.swift:132 (`compacted`), WorldPane.swift:42, StatusReply.swift:157 (`idle` → `resting`), PopoverView.swift:66, SettingsPane.swift:117 (`Work stream`), Core.swift:534-537 and Days.swift:27-99 (lowercase, in the pack's register, or moved into the pack).

---

## I. The 10 thinnest content sections

| # | Section | Now | Why it matters | Add |
| --- | --- | --- | --- | --- |
| 1 | `asks.md` questions | 2, both `keeps` | Empty for good after day 1 or 2. | 15 to 20. At least 10 that are not `keeps`, so they can come back after 30 days. Some `daily` ("good day?"). |
| 2 | `replies.md` `[bye working]` | 1 | `i got this` at every real lock while an agent works, several times a day. | 6 |
| 3 | `signs.md` `[idle]` musings | 4 plain, 2 by answer | All seen on day 1. More idle life needs this first. | 20 to 25, many with a calendar or mood tag |
| 4 | `asks.md` `[wish * met]` | 1 per kind | The reward for meeting a wish is the same sign every day. | 4 per kind (12) |
| 5 | `signs.md` `[notice waiting]` | 3, all reports | The most frequent notice, and the flat one. | Replace the 3 and add 5 (8 in all), written as care or cheek |
| 6 | `dreams.md` | 17, 13 sections of 1 | Seen every morning. Repeats inside the first week. | 25 to 30. At least 3 per tag. Drop the "<adjective> dreams" formula. |
| 7 | `signs.md` prompt kinds with 1 line: `tests`, `docs`, `refactor`, `carry_on`, `essay`, and the tone templates `shouting`, `polite`, `rushed`, `careful`, `playful` | 1 each | Fires many times a day. | 3 more each (30) |
| 8 | `signs.md` `[world *]` | 2 per kind, 2 generic | Up to 3 an hour; repeats inside the hour. | 4 more per kind (16) |
| 9 | Code-made signs: `Today's done!`, `Level N!`, the 12 special-day signs | 1 each, in code | `Today's done!` shows on every full day. Wrong register. | Move to the pack as `[ring]`, `[level]`, `[day <tag>]`; 5 for ring, 4 for level, 2 per day |
| 10 | Voice: `command`, `tool`, `quiet` (8 words each, no sounds, no phrases), `tickled` (5 per face), `shaken` (3 per face) | 8 / 8 / 8 / 5 / 3 | Working check-ins every 4 to 6 minutes use these. | 8 sounds and 8 phrases per topic, recorded in all 13 mood groups. Cut the label words. |

Also thin: `[ouch]` 2, `[nap]` 2, `[unhush]` 2, `[notme]` 2, `[hello morning]` 1, `[comfort night]` 1, `[notice stretch]` 3, `[notice rough]` 3, `[wish *]` 3 per kind.

Total suggested: about 170 new lines of sign text. That would take the pack from 163 lines to about 330.

---

## J. Bugs and inconsistencies found

**Bugs**

1. `app/Boop/Views/SettingsPane.swift:288`: tells the buyer to allow the buddy's name in System Settings. macOS lists "Boop". `app/Boop/Talk.swift:40` has it right.
2. `characters/boop/steering/asks.md:17`: `hold BOOT, say hi?` names a button the buyer was never told about. Onboarding calls it "my button … The one on my side" (`OnboardingBoard.swift:264, 299`). "BOOT" is only said for the simulator.
3. `characters/boop/steering/asks.md:2-3`: both questions are `keeps`, so asks end for good after two answers (`app/BoopKit/Outputs/Asks.swift:31-33`).
4. `app/Boop/Views/OverviewPane.swift:74`: `Boop's hooks` is fixed text; the rest of the pane uses the buddy's name.
5. `app/Boop/Views/SettingsPane.swift:357-382`: no link to get a key. The "has no brain yet" notice (`OverviewPane.swift:60-62`) sends the buyer here.
6. `app/Boop/MenuBarApp.swift:416` with `OverviewPane.swift:485-486`: "Jev is out of credit" opens API docs, not a place to top up.
7. `characters/boop/steering/replies.md:31`: `[bye working]` has one line and is the only line offered when it fits.
8. `app/BoopKit/World/WorldClient.swift:8`: the live world server is a personal Vercel hostname.

**Inconsistencies in the UI**

9. Session / thread / agent: `OverviewPane.swift:89, 73, 624`; `OnboardingFinish.swift:188, 221-224, 378`; `Narration.swift:117, 134`; `MenuBarApp.swift:433`. CLAUDE.md's Words table says "session", not "thread".
10. Idle / resting: `OverviewPane.swift:724`; `MenuBarApp.swift:436`; `WorldPane.swift:168`; `StatusReply.swift:156` against `:157`; `characters/boop/firmware/src/render/gel/drawer.cpp:46`.
11. Body / board / device / "my Boop": `OnboardingBoard.swift:40-58`; `SettingsPane.swift:27, 212`; `MenuBarApp.swift:540`.
12. Brain / Jev / TypeSafe: `OnboardingBrainKey.swift:22-34`; `SettingsPane.swift:30, 357, 382`; `OverviewPane.swift:305, 485-488`.
13. Muted / Off / Hush / Quiet: `OverviewPane.swift:192`; `SettingsPane.swift:110`.
14. Wants / wishes for / wished for: `Narration.swift:195, 114`; `Runtime+Status.swift:177`.
15. Feed / update / firmware: `OnboardingBoard.swift:184-202` against `SettingsPane.swift:247-252`.
16. "XP" in the UI (`BoopPane.swift:39`) against CLAUDE.md's "No game jargon".
17. `Narration.swift:256` shows `passing.tsv:58-59`, "the work act", an internal word.
18. `Narration.swift:153` and `:114` scold; `personality.md:32` says "never scolds".
19. Code-made signs are Title case (`Core.swift:534, 537`; `Runtime.swift:597`; `Days.swift:27-99`); the pack's are lowercase.

**Inconsistencies in the steering**

20. `personality.md:13-15`: "A plain one gets a small one, or at most a small face…" is garbled.
21. `personality.md:33` ("mostly gets nothing") against `:42` ("now and then muses or asks").
22. `personality.md:97` ("a bare 'continue' bores it") against `signs.md:29` (`onward!`).
23. `personality.md:106` ("Praise for Boop it takes as its due") against `signs.md:57` (`thanks, all!`) and `replies.md:34-35` (`woo!`, `yay!`).
24. The poke ladder: `mood/annoyed.md:8`, `mood/determined.md:10`, `mood/irritated.md:6` against `mood/sad.md:16` and `mood/wounded.md:12`.
25. A waiting wish's mood: `mood/calm.md:14`, `mood/happy.md:11`, `mood/comfy.md:7`, `mood/lazy.md:9` each name a different set.
26. "wounded at rude words" is missing from `mood/engaged.md`, `determined.md`, `excited.md`, `comfy.md`, `lazy.md`, `irritated.md`, `grumpy.md`.
27. `mood/comfy.md` and `mood/lazy.md` are near copies; `mood/surprised.md` lasts 1 minute.
28. `signs.md:44-45` and `replies.md:45, 47` share `*hug*` and `i'm here`. `<3` is in five lines (`signs.md:6, 55`; `asks.md:11`; `replies.md:38, 42`).
29. Voice register against sign register (B6): `characters/boop/mac/takes.tsv`.
30. 437 placeholder takes, all in replies; `notme` is 100% placeholder (`takes.tsv`, ids `placeholder.*`).

**Trust**

31. `OnboardingWorld.swift:17-20` and `SettingsPane.swift:81` name one of five counts; `stage`, `day` and `xp_today` are not named (`WorldWire.swift:90-104`).
32. `SettingsPane.swift:81`, "Nothing about you or your code", against `lines_changed`, `turns`, `ships`, `activity`.
33. `OnboardingWorld.swift:22`, "Nobody sees: Your name", is false if the buddy has your name; the name is "for keeps" (`OnboardingIntro.swift:311`) and Settings has no rename.
34. `OnboardingFinish.swift:89-90` and `SettingsPane.swift:382` do not say that copied phrases, project and thread names and noticed habits go to Jev (`PromptReading.swift:62`; `EventLine.swift:110-113, 343-345`; `Notices.swift:114-139`).
35. No warning and no switch for swearing aloud (`takes.tsv`: `Fuck`, `Shit`, `Crap`, `Damn`, `Shiba`).
