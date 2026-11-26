# Boop's words

Updated: 2026-11-25. Moved here from `CLAUDE.md`, so agents load it only when they name things.

One concept, one word, in code, comments, the prompt and docs. Wire and
on-disk keys keep their names (the last column). The model they name,
and its rules, is [documentation/architecture.html](architecture.html#model):
Boop shows three layers, **Doing**, **Mood** and **Moment**, and says
things on three channels, **voice**, **sign** and **narration**.

**The agents**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| agent | Claude Code or Codex | | |
| session | One conversation, with its thread's name and project | thread (for the conversation) | `session` |
| turn | From your prompt to its finish: done, failed, stopped or answering | | `turn` |
| call | One tool use | tool call, tool use | `call` |
| check | A test or build run, which passes or fails | | |
| helper | A subagent | subagent (in prose) | `subagent` |
| to-do | An agent's plan, "3/7" | todo list | `todo` |
| needs you | An agent waiting on your approval: a request | attn, alert | `attn` |
| in a row | The same thing coming again with no break, counted one way and said one way in a line (", the 3rd in a row"): pokes, shakes, quick wins, a check failing, calls failing (`InARow`) | streak, run, again | `in_a_row`, `wins_in_a_row`, `failed_before`, `failing` |
| the line | Agents waiting for you, in order | | |
| reading | What Boop takes from a text in its place: kind, tone, length, names said, a few words (`PromptReading`, `MessageReading`) | summary, label | `reading` |

**You**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| touch | Anything you do to the board with a finger or a hand, one of seven: a poke, a stroke, a hold (a finger kept still), a shake, a pick-up, a swipe, face down. The board finds more kinds and plays each its own way; the Mac reads them as these (`Touch.read`): a wrong-way stroke is a stroke, a nose boop or a tickle a poke, a thump a shake, a put-down and turning it back up the ends of a pick-up and of face down. A touch is Boop's only where it starts on the body (a finger's width round it counts, `Face::bodyAt`): one on the rest of the screen is the screen's, a swipe between agents or nothing, so the board sends no `swipe` now. The touch that answers an invite comes only as the invite's end, and counts once as the poke or stroke it was (`Touch.answering`) | tap, gesture (as two kinds), lean, ruffle, tickle | `tap`, `gesture`; the board's `lean`, `ruffle`, `nose`, `tickle`, `dizzy`, `startle`, `putdown`, `peekaboo` |
| poke | One tap of a finger on Boop's body, a finger's width round it included; several are counted in a row. A firm press the panel reads as several (it bounces) is one. A tap on the empty screen is no poke, and does nothing | tap | `tap` |
| care | The touches and words that count as caring (strokes, an invite answered, kind words, talking, coming back) | | |
| words | What you say to Boop on push-to-talk | talk (for the event), said | `talk` |
| listening | Boop hearing you, while BOOT or the mic is held | push-to-talk (the state) | `listening` |
| presence | You at the Mac, away, or back | | `presence_start`, `presence_end` |
| your hands | Whether you're typing at the Mac, scrolling, or there with your hands still: idle times, never the keys or the page; a tag, not an event (`Hands`) | pace (that's the agents'), activity | `typing`, `scrolling`, `reading` |
| with you | What Boop notices you do at the Mac besides your hands, each a plain fact sent as a tag or `ptr`, never content, never an event, the transcript, the logs or the brain's (`Along`); Settings' "Notices what you do at the Mac" turns it all off | watching you, tracking, telemetry | the tags below, `ptr` |
| typing fast | Keys in at least 6 of the last 8 quarter seconds (`Along.fastSlots`) | | `typingfast` |
| pointer | The way from Boop to your pointer while it moves, as you see the board beside the screen, each of x and y in -10…10; none 3 s after it stops, or with no anchor (`Pointer`) | cursor, mouse | `ptr`: `[x, y]`, `[x, y, 1]` at the edge nearest Boop |
| anchor | Where Boop sits beside your screen: the spot nearest it, shown once in Settings by pointing there and touching Boop ("Show Boop where it sits"); the side the screen is on comes from it, and up when it's in the middle third (`Anchor`) | calibration, position | `macleft`, `macright`, `macup` |
| music | Any sound an app plays for 10 s and more, whatever plays it, a browser in front or a video too, so a short sound effect never counts; it ends 8 s after the sound stops, so a gap between tracks doesn't end it (Core Audio's process objects, macOS 14.2+). Boop jams along, and the Mac says "Boop likes your music" (`Narration.music`) | audio, song | `music` |
| the way you scroll | Down or up, from the sign of the last scroll alone, never how far, where or in which app (a scroll monitor that needs no permission, `AlongSignals`); none when not known | scroll direction | `scrolldown`, `scrollup` |
| on a call | A camera on 5 s and more: Boop keeps still and silent, the board is sent no volume, no take is spoken and every Moment is small | meeting, call (that's a tool use) | `oncall` |
| speaking | Another app recording sound with no camera (dictation, a voice prompt; never Boop's push-to-talk), on after 0.6 s and off 1.5 s after: Boop leans in with a hand cupped at its ear and rings pulsing by it, nods on a 1.6 s beat, and is silent; it wins over typing along (`Along.speaking`, the gel's `speak-along`) | listening (that's Boop hearing you), dictating | `speaking` |
| lock, unlock | The Mac's screen locking and unlocking, every time however short; an away only after 10 min | | `lock_start`, `lock_end` |
| button | BOOT: hands you the next agent in the line | press, hand-off | `press` |
| dismiss | A finger held on the needs-you screen | | |
| face down | Do not disturb: Moments are refused, Doing goes on | | `facedown` |

**Doing**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| doing | What Boop is busy with: resting, working, asleep, listening, no app. With no agent open, resting while you're at the Mac and asleep once you're away, the screen is locked or you've been still its doze time (`Core.sleepsAlone`) | base, look (for the state) | `base` |
| nap | Boop asleep at once, the rule's at a bye at night with no agent working, after its good-night wave, until you show up (`MomentRule.bye`, `Core.nap`); with no agent open, any lock puts it to sleep too (`doing`) | | `base`: `asleep` |
| look | Only the art that draws a Doing | | |
| activity | How it's working, one of four the whole body shows (`Act`): typing (an edit, any other tool, a plan), looking (a read, a search, the web), running (a command, the tests, a build, helpers at work), waiting (a call gone quiet) | act | `act`: `tool_use`, `analyzing`, `terminal`, `waiting` |
| tier | How long it's been working or resting: tier 1 at 1 min, tier 2 at 5 min, tier 3 at 15 min (`Tags.tiers`) | stage | `tier1`…`tier3` |
| pastime | What Boop does to pass the time, by Doing and tier or wait: a move of the body (its hands are the body's) and nothing beside it, none while something needs you (`render/gel/pastimes.h`) | gag (the gel's), idle gag, occasion (the rig's) | |
| dressing | What's worn for the tags: on the gel, nothing, not even at night (the night shows on its lids) and nothing for a special day, nothing in the sky or the air; it wears nothing for music either: a note rising from behind it says that | outfit, layers, occasion (as a design) | |
| pace | Working faster when busy or frantic | | `busy`, `frantic` |
| gaze | Where Boop's eyes look by themselves: one thing at a time, held, then forward; at work only while it types, as the other activities' poses have the eyes (the gel's `render/gel/gaze.h`) | look (that's a Doing's art), attention | `macleft`, `macright`, `ptr` |
| typing along | Boop typing while you do, a small sway over its keys, never a hop, quicker when you type fast, a key's tick bursting beside the hand that taps (the gel's `typingTicks`), and a look up at you when a long stretch stops: with its keyboard out when idle, at its desk at work, and at the light size in any other work pose or with a card held, the body swaying with you while the hands and eyes stay the pose's (`GelFace::showAlong`, `GelFace::light`) | mirroring | `typing`, `typingfast` |
| the scroll's look | Boop looking straight down while you scroll down, straight up while you scroll up, held, its eyes all the way and its face nodded that way; nothing with no way known (`GelFace::showWithYou`, `kLookNod`) | the scroll's eyes (that was a dart), reading along (that was the page it had) | `scrolling`, `scrolldown`, `scrollup` |
| the jam | Boop jamming along while music plays: eyes closed, a bounce on the beat and its head bobbing side to side, three bars that differ, a note now and then rising from behind it; smaller at its desk at work (the gel's `jam`, `jam-desk`). The on-a-call look (still, a muted mic by its ear) is the same function's; each mark shows at the light size too (the gel's `Engine::With`) | groove (that was the old sway) | `music` |
| tilt | How far the board is tipped against how it's been resting, which the body sloshes by (`app::Tilt`); no touch | hold (that's a finger's) | |
| the work stream | Agents' calls as words: the newest call's doing first in the strip (the work's term), and the few that come forward from the desk's monitor and land on Boop: part of Doing, never a Moment | gag (the stream's), call forward, falling words | `call` |
| work act | A command worth naming while it runs, the tests, the push or the build: on the gel, the monitor's icon (a flask for tests) and the strip's term say what's running, then a tick or a cross and `tests passed` or `tests failed`, never a card, and Boop hops or flinches at the result | act (that's the activity) | `wact` |
| the strip | The row along the bottom: while agents work, the work's term first, what the newest call is doing ("searching TODO", `WorkStream.doing`), a work act's words, or a failure's, and with one agent the counts as marks after it; with several, the watched one's doing across the whole row, its name on the line in its pip; else the counts in words (`termFor`, the gel's) | | |
| the drawer | The AMOLED board's list of every agent, pulled up from the strip, a row each to open on the Mac (`render::Drawer`) | roll call, list view | `list`, `drawer` |
| show | A result as a picture an agent drew with the `boop-cards` `show` tool, a headline and one small SVG or a PNG, checked against the board's rules (`Show.problems`: 420 by 190, 4 kB, five colours and currentColor, text 14 px and inside its sides, lines 3 px, 16 words), what's wrong going back to the agent. The popover holds the latest up 30 min (`Core.shown`, `ShowCard`); the board holds it up in its agent's window, its headline over the picture, from when it comes until 30 s after its turn ends, the screen following its agent, several 8 s each at least (`Core.boardShow`, the gel's `paintShow`); the picture goes there as a blob in 16 colours (`ShowPicture`, `ShowBlobs`, linkkit/SPEC.md §3). Its picture never goes to the brain or the log | infographic | `show` |
| held picture | The live picture Boop holds of the watched agent's work while it works, from the hooks and no word of the agent's: its plan (the to-do), its changes (each project file's lines this turn, once 10 lines or 2 files) or its helpers; the kind of work picks which, and it's put down 30 s after its data stops (2 min for a plan) (`Core.picture`, the gel's `paintCard`) | status card | `pic` |
| watched | The agent the screen follows, with two or more: a show's while it's up; your swipe along the strip or the empty screen (one on the body is a stroke), kept while it works; else the one Boop holds a card for; else the one you last prompted (`Core.watched`). Its monitor (framed in its colour), strip and card show, sliding in from the side you swiped toward, and its pip on the line holds its name; the others are pips | focused, current | `watch`, `who` |
| pips | A mark each for every agent on the strip's line in the drawer's grabber's place, in its own colour, which every agent gets when Boop first sees it and keeps (`Core.colour`), its lane taking the same: the watched one a pill holding its name, as much as fits beside the others, cut with "…" (`Core.watchLabel`, the gel's `fitPips`), an idle one hollow, one that wants you pulsing (`Core.watchFields`, the gel's `paintPips`) | dots, pager | `pips` |
| pill | News from an agent you aren't watching, in its colour, in the strip's row for 4 s, by its short name (`Core.label`): "api finished", "docs waits for you" (`Core.turnEndedElsewhere`) | toast, alert, tag | `pill` |
| card | What an agent hands Boop to hold, through the `boop-cards` tool server: a result for 15 s after its turn (a status's words show only in the popover's row and as the plan's step; on the board a working agent's card is its held picture); one main thing and at most one small line, in the agent's own words, never Jev's to read. A result may also offer lines Boop might say, how you seemed and a note, which Boop's rules weigh (`MomentRule.offeredLine`, `agent-brief.json`). On the gel it's the agent's window: a title bar in its lane colour naming the agent, square-ish corners, and the desk's monitor lit in that colour, never one of Boop's round signs. Part of Doing: a swipe changes card, a poke opens it on the Mac (`Card`, `Cards`, `gel::paintCard`) | artifact, widget; sign, low sign (those are Boop's own) | `card` |
| the needs-you screen | Amber, naming who's waiting, until you answer or dismiss it; Boop's fist knocks on the glass, the same in every mood, and when nobody comes the knock climbs to its forehead on the glass (the gel's `knock`, `knock-climb`) | sign (that's a Moment's) | |
| hands | Boop's one pair: gel stubs, part of its body, that bud out when they act and sink back in, a ball, an open palm with three small fingertips over its top, or a fist; the same two type on the keys, grip a card or a sign, hold the low sign, cup an ear, hang over the drawer and act in a move (the rig's hand channels, the gel's `HandsPlan`) | paws, arms | `handLX` … `handRGlass` |
| the glass | The screen, a pane Boop lives behind: up at it the body is bigger, 1.15 at most, and what touches it goes flat with a pale patch; a hit rings (the rig's `glass` and `patch`) | window | `glass`, `patch` |
| turning round | Only the face going round the dome, the body's outline and light still: half way one eye at the rim (the look over the shoulder), all the way its back, a whole turn a spin; the eye nearer the rim narrows by itself (the rig's channel, the gel's `Projector::face`) | turn (that's the agent's) | `turn` (the rig's) |

**Mood**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| mood | One of the pack's 7 lasting moods: calm, happy, focused, proud, cross, sad, lonely (`CharacterPack.lasting`). The rules brain moves it only as the pack's mood files say (`MoodMap`), and Jev, in its seat, may keep it or move it to any other; the wire carries the face it rests in | (a Moment's emotion) | `mood` |
| resting mood | Calm, where moods settle | default mood | |
| level | How cross it is, 1 to 3, which code counts and Jev never picks: pokes and shakes in a row, failed checks and turns, rude words; a stroke takes it one down. It picks cross's resting face: annoyed, grumpy, angry (`MoodOutput.level`) | intensity, step | `level` (the transcript's) |
| fade | A mood settling by itself after its minutes in `character.json`, to calm (proud to happy, cross a level down), run by code on the Mac's clock, never by Jev (`MoodOutput.fade`) | drift | `fade` (the transcript's) |
| mood file | The steering for one mood (`steering/mood/`): what it is, how its faces lean, what moves it. No minutes: code fades it | | |
| energy | How awake Boop is, one of three, a plain rule on the Mac, never Jev's: bright for an hour after you first show up on a Boop day, tired at night or after 15 minutes' working stretch, else normal. The board draws it on the lids and the eyes and in the idle tempo, never on the work or a reaction to you; the popover says it (`Energy`, `Core.energy`, `Narration.energy`) | sleepiness, nightcap | `energy` |

**Moment**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| moment | A beat on top of Doing: event, emotion, size, voice and sign; made by the board or the rules, Jev in its seats. Jev may pick only the emotion, the sign and a skit's take; the move, the size and when it speaks are the rules' (`MomentRule`, `Skits`), and so is the whole Moment at your lock or unlock, a working check-in, a boop from the world and Boop's growth, and which idle beat is due (`IdleBeat`) | reaction (for the beat), one-shot | `do` |
| event | What happened: a finish, a check, you came back, your words, your prompt naming Boop, a touch, or Boop's own beat | | |
| Boop's own beat | A Moment with no outside event: an idle beat | | |
| idle beat | The one thing Boop may hold up at an idle check-in, which code deals: the first that's due of an agent waiting on you (the `waiting` notice), the wish, another notice, an ask, a remembered line, a musing; at most one an hour and four a Boop day, on Quiet only the first. The brain says only whether to hold it up (`IdleBeat`). In a working stretch of 5 minutes or more a working check-in may deal one too, under the same cap, no musing, never on Quiet or a call: the rules hold it up (`IdleBeat.atWork`) | | `beat` |
| emotion | The expression for one Moment, any of the pack's 18 faces in `moods`; six more, the meme faces (`board_faces`), each only at the rare moment a rule names it for (`RulesBrain.meme`) | face | `react.face`, a `do`'s `mood` |
| size | How much the Moment matters: small, medium, big. A rule's pick, never Jev's: a finish by its turn's length, your words medium, a touch small (`MomentRule.size`) | intensity | `loops` |
| finish | The animation a turn's end plays, the rule's pick by how the turn ended (`MomentRule.move`), one for each size by the turn's length: Little Win, Confetti, Gold Rush; the low sign and rim glow name the thread. A chat turn (its last message a question or an answer, or quick with no calls) plays none and names nothing: Boop looks up at you once (the notice) and holds "your turn" low, in the strip's place (`MomentOutput.yourTurn`) | move (success, failure), task_complete | `task_complete`, `reply_ready`, `outcome` |
| hello | You came: your unlock, your coming back from an away, or your first touch of Boop's day. The rule picks its size by the time away (small; medium with the wake-up after an hour; big after a day) and at most one extra: a special day's sign, else the dream told, else what happened while you were away. The first of Boop's day, and one that tells the dream, plays whole. An unlock's is the rule's alone, a slight wave; the brain picks the face only after a real away, 10 min or more, and the `back` skit says the hello (`MomentRule.hello`, `TranscriptView.hello`) | greeting, wave, the day's greeting, the telling | `wake_up`, `reply`: `hello` and `wave`, `greeting` |
| bye | You went: your lock of the Mac, by rule and with no pass (`MomentRule.bye`): a real wave with a word and a sign at a first lock in an hour, good night and the nap at a lock at night, else `reply-wave`, slighter and silent; cross, a snub, which has none. Stepping away has none | wave | `reply`: `bye` and `wave` |
| reply | Boop's answer to your words, the brain's pick of 11 (yes, no, huh, hello, bye, thanks, ouch, comfort, hehe, status, hush), with its clip, its sign and its own words, when the face has some (`MomentOutput.replies`) | answer (that's a topic), response | `react.reply`, `reply` |
| ask | A sign that is a question, with two answers you touch, from the pack's `asks.md`, dealt as an idle beat; never needs an answer | quiz, prompt | `ask` |
| wish | Boop's want, one a Boop day, kind pet, chat or work, dealt as an idle beat, never while it's cross; a rule meets it at once by a touch on its face, push-to-talk or working with an agent; left too long it sighs and slumps (`Core.Wish`, `[wish …]` in `asks.md`, `state.wish`, `wish_met`, `wish_gone`) | need, request | `wish` |
| invite | Boop asking with its body for one touch after a skit, never a word or a question: a pose (a palm on the glass, its cheek on the glass, its back turned), the place to touch glowing, the pack's word by it until you know it ("tap", "pet", `[invite …]` in `signs.md`), a wait of 4 s, 12 s the very first time. The pack's skit has it (`win` a palm for a poke, `upset` its back for a stroke, `back` a lean for a stroke, `fix` none); code asks it on the last Moment the skit queues, only of a board that says `invites`, never on a call or while something needs you, at most 10 a Boop day, and after 3 misses in a row of a pose every second one skipped (`InviteLedger`, a view of the transcript). The board plays it inside that Moment's `do` and says how it ended: answered, missed, late or cut (`Moment.invite`, `ev invite`); it wakes no pass | request, prompt, ask (that's a question) | `invite`, `ev invite` |
| payoff | What your touch on an invite plays, on the board: a high five, a purr or a sigh, with the XP care would add today, "+3 XP", none when it has no room; a shrug when the wait runs out, and the payoff after all for a touch within 30 s (late). The touch does what that touch does, once: care XP, a pet wish met, a stroke's soothing, a touch in the daily counts | reward | `payoff`, `highfive`, `purr`, `sigh` |
| notice | Something true about your day that Boop may care about: a fact on a moment that exists (`Noticed` in CONTEXT), or a line of its own dealt as an idle beat, `waiting` first, `stretch`, `rough` or `late` after the wish (`Notices`, `[notice …]` in `signs.md`). The animation called `notice` on the wire is your prompt naming Boop's, which a played notice borrows to look up at you | nag, reminder | `notice_key` |
| musing | An idle beat with a sign and no question, a `[idle]` line of `signs.md`: what's dealt when nothing else is due | thought, quip | |
| variation | Which version of a design plays; the board picks | | `variant` |
| the queue | LinkKit's rule for what plays when (linkkit/SPEC.md §4) | the turn | |

**Voice, sign and narration**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| voice | What Boop says aloud: none, a sound, a word, a phrase, a swear (only with Settings' swearing on), as big as the Moment. A rule says when: at a skit (a take of the skit's), to your words and at a lock's real wave (the reply's own); every other Moment is silent. Only which of a skit's takes is a seat's (`skit.take`) | say | `say` |
| skit | One kind of moment that has takes of its own and always speaks, by a plain rule from the slot the rules read the event as, the brain unable to veto it (`Skits.play`, the pack's `skits`): `win` (a turn of a minute or more done), `upset` (a failed turn, the agent giving up, the third failed check in a row; a swear only when failures pile up), `fix` (a check passing after it failed) and `back` (you back after a break); one may name a clip of the pack's its Moment plays as its face starts (`fix` the flop of relief, `Skit.clip`); all but `fix` may invite a touch after (`invite`), and `win` and `back` may carry a remark (`remark`) | scene (that's a board animation), babble | `skit` (the record's) |
| take | One recorded clip; a lead sound may come first. Its part says what it is: a skit's or a reply's; the voice file keeps takes nothing says, which the pack's table leaves out | line | `take` |
| the voice file | `voice/voice.bin`, on the board's card | voice pack | |
| sign | A caption Boop holds up, at most 18 characters (`Signs`, `signs.md`) | banner, label | `sign` |
| low sign | A card Boop holds up in the strip's place, two lines at most, one under the rim's glow: a finish's thread, a ship or a fix, a remembered line, a win's remark, a level or the ring in gold; with an XP chip, `+5 XP`, when its moment earned (`gel::LowSign`) | ticket | `low`, `gold`, `mark`, `xp` |
| bubble | The voice's words as text in the lane | | |
| remark | The one short thing Boop says about how now differs from your usual, as text on a skit that plays anyway, a plain rule's pick (`Remarks`): on a `win` a turn far faster or slower than yours, the 3rd win in a row or a new best run, today's 5th or 10th win or a new best day, as a low sign after the finish unless the agent offered a line; on a `back` you first here 45 minutes early or late, or back from a break far shorter or longer than yours, as its sign over the dream's, unless it's a special day's. At most one skit in three, never `upset` or `fix`, none on Quiet or with your usual empty; never a take yet; the pack's words (`[remark …]` in `signs.md`) | comment, quip, observation | `remark` (the record's) |
| talk | How much Boop says: quiet or normal. "Shh", the hush reply and the popover's Hush make it quiet for half an hour, then it's the setting's again; talking to Boop ends that sooner (`Talk`, `Core.quiet`) | chattiness, mute (that's the volume), hush (as a state) | `talk` |
| narration | The plain words for why, the Mac's and the gel's board's own for a touch, never Jev's or Boop's voice (`Narration`, `app/touch_reason.h`); on the board, the caption | explanation | `reason` |

**The mind**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| transcript | Every event, one file a day (`Transcript`) | the log | |
| daily counts | A row a day of numbers on the Mac, `daily-counts.jsonl`, for "This week" and a summary you may send; no words, threads or notes (`DayCounts`, `Boop --counts`) | stats, telemetry | |
| line | One event as a sentence Jev reads (MellowHarness's `Line`) | | |
| message | One JSON line on the wire: `hello`, `state`, `do`, `ev` | line | |
| the prompt | What Jev reads: guide, PERSONALITY, MEMORY, MOOD (the mood's file, then cross's level now), CONTEXT, HISTORY, NOW | the state | |
| CONTEXT | The prompt's section for how things stand: When, Talk, the buddy, you, the agents, the day so far (`ContextSection`) | NOW (that's the event), status | |
| pass | One request to the brain: its mood and its emotion; to your words, its reply too; at some events a sign; at a skit with more than one, which take. The rules answer it whole, and Jev's answers replace theirs in its seats when they come in time; never whether Boop speaks | | |
| rules brain | The brain every Boop has, key or none: each pass's questions answered at once by rules on the Mac, from the event's facts and the mood map, never the prompt's prose (`RulesBrain`, `MoodMap`) | rules engine | `rules` (the brain's id) |
| seat | One question whose answer Jev may improve, of five: the mood, the face, a reply to your words, the sign on every pass that asks one (a reply's, a prompt's caption, the idle beat held up, an answered ask's, the dream's), and which take a skit says. Jev picks from the rules' own options, and its answer replaces theirs only when it comes within the pass's deadline, is one of them and is as sure as the output needs (a reply's floor); slow, failing or absent, it changes nothing you see, and a key's owner gets a notice (`SeatedBrain`, `BrainTrouble`). Everything else is the rules' | upgrade, fallback | `mood`, `react.face`, `react.reply`, `react.sign`, `skit.take` |
| wake, hold | Whether an event gets a pass at all. What wakes the brain: your prompt's reading, a finish, your words, a failed check or a fix, a touch, your coming back, an answered ask, a wish's end, a push's result, an answered request, and the idle check-in (`TranscriptView.wakes`). A turn's start, your lock and unlock, the working check-in, a boop from the world and Boop's growth never do | | |
| check-in | Boop looking in by itself: working (during a turn), the rule's small Moment in silence and no pass (`MomentRule.checkIn`); or idle (while you're here), where the idle beat is dealt and the brain picks the face | heartbeat | `check_in`, `working` |
| output | What the brain's answers drive (MellowHarness's `Output`; Boop's `mood` and `react`) | action | |
| speeds | Reflex, reactive and deliberative | loops | |
| personality | Who Boop is, temperament included (characters/CHARACTER.md §7) | nature | |
| steering | The pack's text Jev reads | | |
| buddy | One board running one pack, with its own name, Doing, Mood and agents (`Buddy`) | body, creature | |
| step | One row of a demo script or an eval scenario | line | |

**Memory and time**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| Boop's day | 5:00 to 5:00, today for CONTEXT's Today row and the ring; it triggers nothing | | |
| dream | Everything since the last dream as tags and a sentence, and the memory's update from it: on `d`, once a night's sleep or one of 5 h, or after two days (`DreamReader`, `Memory.dream`, `dreams.md`) | diary, journal, closing the day | |
| digest | One dream's span in numbers and the few words that may be kept, in `memory-days.json`: what habits and notices are read from (`DayDigest`) | summary, day file | |
| your usual | Your own numbers, which a remark compares now with: how long your turns take, the hour you first show up, how long your breaks are, your wins a day and your best run, and the skits since the last remark; a view over the transcript, never a store of its own, its lists short so a median is a sort (`Normals`, `NormalsReader`) | normals, baseline, average | |
| written memory | `memory.md`: You, Your work, You and Boop, Recently (`WrittenMemory`) | diary, memory file | |
| remembered line | A note of the written memory in the pet's voice, at most 40 characters: what Boop brings up on the low sign as an idle beat, each line once in 14 days (`Memory.Felt`, `memory-days.json`) | | `low`, `felt` |
| the dream's write | Code proposing the written memory's edits as Boop dreams, with a model answering small questions: your own Claude Code or Codex while Settings allows (`AgentToolModel`), else Apple Intelligence; and the checks holding each (`MemoryPipeline`, `MemoryProposer`, `MemoryEdits`) | the night's write | |
| XP | What Boop earns, for four things you see happen: a turn whose finish is a success 5, a ship 10, a check passing after it failed 5, your time with Boop (a care touch, an invite answered, your words, a met wish) 3 and at most 30 a day; at most 300 a day in all; never lost (`Growth`, plan/xp-league.md §3) | points | |
| the ring | Today's XP against 100, a Boop day's goal: XP counts past it, to the day's 300. On the board, no bar: a finish's or a ship's low sign carries what it earned, `+5 XP` (the `do`'s `xp`); its closing is the rules' moment, `100 XP today, day 12` low in gold behind a full ring (the `do`'s `mark`), one with a level reached at once, and one `growth` event for both | daily goal, progress bar | `growth`, a `do`'s `xp` and `mark` |
| level | 1 + every XP / 500, no maximum, never down; a level-up is the rules' moment, `Level 12!` on the low sign, the same at every level: Boop's body is one size | stage, size (for growing) | `growth`'s `level` |
| days in a row | The Boop days in a row with a full ring, kept through up to two days without one, so a weekend never breaks it (`GrowthStore.daysInARow`) | streak | `xp.row` |
| colour | The buddy's colour, one of eight picked in Settings, at any level: the gel's material turned once in hue, saturation and brightness (`BuddyColor`, the gel's `bodyColor`); 0 is its own blue | skin, theme | `state.color`, the world's `color` |
| special day | A holiday, a milestone day, Boop's birthday | occasion (for a day) | |
| tag | A fact true now, sent to the board | flag, label | `when` |

**The world**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| the world | Everyone's buddies together on one server (`internal/world/`), which Boop joins unless you keep it private; the Mac's client is `WorldLink` | map, network | |
| boop (from the world) | Another buddy's gesture for yours: a boop, a wave, a heart, or a cheer for your ship, named by its sender when one sent it (`from_name`) so it can be answered; a `world` event, which the rules answer with a warm small face and one of the pack's signs for it, no pass (`MomentRule.world`). One reply's are one moment, at most 3 an hour; at night they wait for the morning (`WorldGestures`) | ping, notification | `world` |
| region | Where a buddy is, from its UTC offset only: the Americas, Europe and Africa, Asia and Oceania | country, location | `from_region` |

