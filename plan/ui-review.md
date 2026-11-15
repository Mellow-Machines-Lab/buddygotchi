# A UI and UX review of Boop, down to the pixel

Updated 2026-11-09. A review of how Boop looks and feels to use, on the Mac and on the board, at branch `v1-polish` (`548c6e03`). It changes no product code. Its brief was `plan/ui-review-prompt.md` (at commit `510a78ac`). It builds on [product-review.md](product-review.md) and fits the phases in [TODO.md](TODO.md) ("Plan, 2026-11-09"). It does not repeat that review's word fixes or its decided items; where a decided item needs a look, this review gives the look.

> Its evidence folder, `plan/evidence/2026-11-09-ui-review/`, left the repository on 2026-11-14: read it at commit `510a78ac` (`git show 510a78ac:plan/evidence/2026-11-09-ui-review/…`). A copy, with the pictures, is in `~/.boopdev/ui-review-2026-11-09/` on the owner's Mac.

## 1. Summary

**What was done.** Every one of the Mac's 286 snapshots and the board's 570 simulator frames was looked at, measured in pixels and traced to its cause in code. Five reviews ran side by side (the design system, the header and Now tab, the other tabs and Settings, onboarding, the board), and I checked their main findings against the pictures. The long form of every finding, with its measurements, is in `evidence/2026-11-09-ui-review/`. This document holds what is broken or rough, the layout proposals with mockups, and the plan.

**The state of the UI.** The look is sound. Colours go through `Theme` almost everywhere, the gutters and card edges line up, dark mode holds, and the writing in onboarding is good. The problems are of four kinds:

1. A few real layout bugs that move or cut the whole screen.
2. Text on the board that is too small to read.
3. Signal colours that are too weak on light paper.
4. No type or spacing system, so every screen has its own sizes.

**One correction to carry forward.** The board's screen is 502 × 410 pixels at 315 pixels an inch, not 320 × 240 as the brief and [product-review.md](product-review.md) say. All board numbers here use the real size: 1 pixel is 0.081 mm.

**The 5 worst problems.**

| # | Problem | Evidence |
| --- | --- | --- |
| 1 | **A long mood word pushes the whole popover sideways.** The header's third line cannot shrink. The left gutter is 8 pt, not 18, in the default "working" state ("determined"), and the face and Talk are cut by the window's edge with a long name | NOW-1 |
| 2 | **The board's smallest font carries what matters.** The narration, the ring's label, "Today's done!" and the drawer's detail are 0.56 mm tall. Nobody reads them from a chair. The drawer's rows are 3.9 mm tall, about half a fingertip | BRD-1, 2, 3, 20 |
| 3 | **Onboarding has no frame.** Act 5 is taller than its window, so the progress marks and the button jump. The title sits at 7 heights, the face has 8 sizes, and the bottom bar has 3 layouts | ONB-1, 2, 3, 6 |
| 4 | **In light mode the signals are the faintest things on screen.** The needs-you card is 1.14:1 against the paper and its dot 1.71:1. The lane bars, the ring and every dot on the World band fail 3:1. Grey meant for decoration is used for text | NOW-4, 5, 6, 7; WORLD-5 |
| 5 | **There is no system under the look.** 17 text sizes, 17 padding values, 8 corner radii, 9 ways to build a row, 8 ways to show a notice. Settings is 1,499 pt long, 2.8 screens | §2; SET-1 |

**The 5 best changes.**

| # | Change | Why first |
| --- | --- | --- |
| 1 | **A two-row header that cannot overflow** (§4.1). The level moves to the Boop tab; mood joins the status line | It fixes the worst bug at its root and gives every tab 37 pt back |
| 2 | **A reading rule for the board: nothing a person must read under 22 px** (§4.5). The narration, the ring's number and the drawer move up a size; drawer rows grow to 66 px | One rule fixes six findings |
| 3 | **The Now tab in the order of need** (§4.2): a needs-you card with real buttons and real weight, one sorted list, notices as one strip, a mood card that says why | It is the tab people stay on |
| 4 | **One frame for every onboarding act** (§4.6): fixed progress marks, title, face and bar | It removes the jumps now, and the 5-act version needs it anyway |
| 5 | **A stricter token set** (§2.3): 6 spacing steps, 8 named type styles, 3 radii, a light-paper partner for each signal colour, and a contrast check that covers them | It stops the next 200 small differences |

**What I could not see.** The real panel (the owner's app was connected to it), hover, motion, scrolling and focus. They are listed in §8.

## 2. The system

The full audit, with every count and the commands, is `evidence/2026-11-09-ui-review/system.md`. Its census is `evidence/2026-11-09-ui-review/system/census.md`, its contrast table `evidence/2026-11-09-ui-review/system/contrast.md`, and a list of 177 places to change `evidence/2026-11-09-ui-review/system/changes.md`.

### 2.1 What the tokens are

`app/Boop/Views/Theme.swift` holds the look called the Warm Terminal: a warm paper, three surface tones (paper, raised, well), two hairlines, three inks (ink, soft, faint), amber for needs you, sage for good, clay for trouble, and four lane colours shared with the board. It has spacing constants, three radii (12, 8, 6), and a few components (`Card`, `SettingRow`, `StatusChip`, button styles).

### 2.2 How far the screens follow them

| Token kind | Followed? | Numbers |
| --- | --- | --- |
| Colour | **Well.** | 243 references go through `Theme`; 4 raw hex values and 9 direct palette reads do not |
| Spacing | **Poorly.** | 36 of 148 `spacing:` values (24%) and 18 of 95 paddings (19%) use a token. 17 literal padding values are in use, with 5, 9, 11 and 13 beside 4, 8 and 12. `gapSnug + 2` makes a tenth value 6 times |
| Type | **There are none.** | 141 `.font` calls, 17 sizes from 8 to 30 (with 10.5 and 12.5), 5 weights, no named styles |
| Radii | Half. | 3 tokens, 8 values in use; 7 and 10 have no token |
| Components | Half. | `Card` at 4 paddings, plus 9 containers built by hand; 9 row recipes; 6 section headings; 5 chips; 4 looks for a link; 8 ways to show a notice |

**Against the sketch the owner chose** (`~/.boopdev/v1-ui/v1-ui.html`): every text size shipped 0.5 to 2 pt smaller (body 12 against 13.5). The ring is 96 pt against 120. The band is 96 pt high against about 207. The sketch put the mood and its reason first on Now; the app puts a bare mood last. The sketch's world goal card, the buddy card's face and lift, and the line "claude's work 60 · you 22" did not ship.

**Colours that mean two things.**

| Colour | Meanings today |
| --- | --- |
| Amber | Needs you (Mac and board); a buddy shipping (World); the voice's words in the board's bubble; gold for celebration on the board |
| Sage | Connected; a switch that is on; a full ring; a resting buddy; one link |
| Lane teal and lilac | A session's lane; coding and testing on the World band |
| "Waiting" | Amber on Now, blush on World |

**Contrast.** Every `*Ink` text tone passes 4.5:1 on every surface. What fails:

| What | Light | Dark | Where |
| --- | --- | --- | --- |
| `inkFaint` used as text | 2.66 | 3.62 | "Feeling", "· Level N", "TRY", the out-of-world "you" |
| Needs-you dot and bar | 1.71, 1.57 | passes | `OverviewPane.swift:314, :691` |
| Lane bars | 1.29 to 2.18 | pass | `OverviewPane.swift:692` |
| The ring's part-full arc | 2.54 | passes | `BoopPane.swift:118` |
| World band dots | 1.02 to 2.53 | pass | `WorldBand.swift:140-148` |
| Off switch, slider groove, button and field edges | 1.41 | 1.64 | `Theme.swift:517` |

The snapshot run's own contrast check (`internal/app/Boop/Snapshots.swift:1036`) tests 58 palette pairs. It skips `inkFaint`, every graphic colour, opacity, and the pixels as drawn.

### 2.3 A smaller, stricter set

It keeps the Warm Terminal's colours, paper and hairlines. Each value below is already the most common one in the code, or one step from it.

| Kind | Proposed | Replaces |
| --- | --- | --- |
| Spacing | 2, 4, 8, 12, 16, 24 (and 48 for onboarding's sides). No arithmetic on a token | 17 values. The gutter goes from 18 to 16, as in the sketch |
| Type, rounded face | Display 28 bold; Title 18 bold; Heading 15 bold; Label 13 bold | 13, 14, 15, 16, 17, 18, 20, 26, 28, 30 |
| Type, system face | Lead 14; Body 12 (regular, medium, semibold); Caption 11; Label 10 semibold, tracked, capitals; Chip 10 medium; Mono 11 | 8, 9, 10, 10.5, 11, 12, 12.5, 13, 14, 15. Nothing under 10 pt |
| Radii | 12 (cards), 8 (rows, every button and field), 6 (chips, segments) | 7, 10 and capsule chips |
| Card | One `Card`, three named paddings: regular 12, rows 0, roomy 16 | Paddings 10 and 14, and 9 hand-built containers |
| Row | Horizontal 12, vertical 8, icon column 20, gap 8 | 9 recipes |
| Chip | One `Chip(text, icon, tone)` | 5 kinds |
| Buttons | Prominent (32 tall, one a screen), row (24 tall), quiet, quiet icon (24 × 24), link | 12 kinds of control under 24 pt today |
| Colour rules | `inkFaint` never on text. Each signal colour gets a light-paper partner, as amber has in the menu bar (`#B87400`). Amber means needs you only. The contrast check covers graphics at 3:1 | |

**Accessibility, from the code.** All 6 icon-only buttons have labels. All text sizes are fixed. No custom button draws a focus state. 12 kinds of control are under 24 pt (Dismiss is 42 × 13; pin and forget are 20 high and 6 apart).

## 3. Findings, by surface

Each row is one finding: what is wrong, the cause, the fix. **Sev.** is broken (it looks like a bug), rough (a careful person notices), or nit. **Eff.** is S (under an hour), M (a day), L (more). The picture is a marked crop; numbers are in points on the Mac and pixels on the board. Only broken and rough findings are in the tables. Nits are listed by id after each table, and every finding's long form (why it matters, the measurements, the confidence) is in the surface's own file. Confidence is high unless the row says otherwise.

### 3.1 The popover's header, the Now tab, the footer, the menu bar icon

Long form: `evidence/2026-11-09-ui-review/now.md` (40 findings, a measured spec of the header and a row, 6 proposals).

!The gutter is 8 pt, not 18

| Id | Sev. | Eff. | State | What is wrong | Cause | Fix | Picture |
| --- | --- | --- | --- | --- | --- | --- | --- |
| NOW-1 | broken | S | `working`, `long`, `long-buddies` | The header's third line cannot shrink. Over 266 pt wide, the whole column grows past 360 pt and is centred: the left gutter is 8 pt in `working`, 0 in `long-buddies`, where the face and Talk are cut. The label has 140 pt; a mood over about 8 letters or a level of 100 or more overflows | `OverviewPane.swift:135-140`; `.fixedSize()` at `:180`, `:285`, `:303` | Remove `.fixedSize()` at `:180`; `lineLimit(1)` with a low layout priority. Better: §4.1. Add a snapshot check that the face's left edge is at the gutter in every state | 1, 2 |
| NOW-2 | rough | S | needs you | An invisible "+0 more" column is always laid out, so the hint wraps 52 pt early | `OverviewPane.swift:420-422` | Draw "+N more" only when N > 0, as an overlay | crop |
| NOW-3 | rough | S | needs you | Dismiss is bare 11 pt text in the corner of a card that is itself one button. "+1 more" looks the same and does nothing | `OverviewPane.swift:383-386, :420` | A small outlined button; "+1 more" as plain soft text. Better: §4.2 | crop |
| NOW-4 | rough | S | needs you, light | The card's fill is 1.14:1 on paper and its edge 1.38:1. The eye goes to the face, the name and the tabs first. Medium confidence | `Theme.swift:83, :170` | Tint 0.08 → 0.16 and a solid amber edge, or a 4 pt amber bar on its leading edge | crop |
| NOW-5 | rough | S | needs you, light | The amber status dot is 1.71:1 | `OverviewPane.swift:314, :691` | `#B87400` in light mode, as the menu bar icon already uses | crop |
| NOW-6 | rough | S | all | "Feeling" and "· Level 12" use `inkFaint`: 2.66:1 at 11 pt | `OverviewPane.swift:174, :177` | `Theme.inkSoft` | crop |
| NOW-7 | rough | S | rows, light | Lane bars are 1.29 to 2.18:1. The fifth working session has no lane, so its bar is dark grey: the strongest bar, by accident | `OverviewPane.swift:692`; `Theme.swift:40` | A light-mode lane set at 3:1; a faint fallback bar; a tooltip "Its lane on the board" | 1, 2 |
| NOW-8 | rough | M | `crowded` | Sessions are grouped by agent in a fixed order, so a waiting session can be the 7th row. Medium confidence | `OverviewPane.swift:451-468` | One list sorted needs you, working, idle (§4.2) | — |
| NOW-9 | rough | S | needs you | The card says project then name; the row says name then project | `OverviewPane.swift:398-413` against `:729-740` | One order: name first | crop |
| NOW-10 | rough | S | `long` | Rows never truncate. A long row is 4 lines; a branch breaks inside a word. The code wants this ("neither is ever cut"), so it is a decision. Medium confidence | `OverviewPane.swift:642-658, :733-747` | Title 2 lines; workspace 1 line, cut in the middle; full text in the tooltip | crop |
| NOW-11 | rough | S | notices | A notice's cross costs its text 39 pt of width | `OverviewPane.swift:532-540` | The cross as an overlay; pad the title only | crop |
| NOW-12 | rough | M | `long-notices` | Each notice is a full card 20 pt apart. Six push the sessions to 838 pt down. Raw system errors show in the same style as plain words | `OverviewPane.swift:42, :47-87` | At most two, the rest folded into "3 more"; raw text in monospace (§4.2) | crop |
| NOW-13 | rough | M | `*-bounded` | With a visible scroll bar the cards end at 326.5 pt while the header ends at 342 pt. Medium confidence: it depends on the Mac's scroll bar setting | `PopoverView.swift:114-118` | Overlay scrollers on the pane | crop |
| NOW-14 | rough | S | `*-bounded` | The last row is cut through its second line by the footer, with no fade | `PopoverView.swift:116` | A 16 pt fade above the footer while more is below | crop |
| NOW-15 | rough | S | dark | The selected tab is darker than the well, so it looks pressed in. In light it is raised | `OverviewPane.swift:816` | Paper in light, `hairlineStrong` in dark | crop |
| NOW-16 | rough | M | all | The header holds up to 9 things and is 73.5 to 128 pt tall. It repeats on Boop and World, where the mood, the level and Connected do not matter | `OverviewPane.swift:110-151` | §4.1 | crop |
| NOW-17 | rough | S | long name | A 20-letter name wraps at 187 pt because "Connected" sits beside it | `OverviewPane.swift:122-126` | §4.1 | crop |
| NOW-18 | rough | S | `hushed` | After Hush is clicked the button goes, and a "Hushed · 24 min ×" chip appears two rows lower, looking like the passive chips. Medium confidence | `OverviewPane.swift:255-289` | One control in one place: the button becomes a filled "Hushed 24m" | crop |
| NOW-19 | rough | S | about 30 of 40 states | The mood card says "Mochi is calm." and nothing else. The header already says it | `OverviewPane.swift:93-94, :780-788` | Show the card only with a reason, and lead with the reason (§4.2) | crop |
| NOW-20 | rough | S | `waking-up` | The pane is empty: tabs, 28.5 pt of nothing, the footer | `OverviewPane.swift:88` | A "Waking up…" note | crop |
| NOW-21 | rough | S | footer | The ladybug is "Save a bug report" (⌘B). It has no word and reads as decoration | `PopoverView.swift:59-67` | Move it into Settings; keep it in the "stopped unexpectedly" notice | crop |
| NOW-22 | rough | S | rows | Status chips are almost shapeless in light (1.17 to 1.26:1), and "working" is louder than "needs you". Medium confidence | `Theme.swift:409-420` | Needs you: solid amber. Working: soft ink. Idle: no chip | crop |
| NOW-23 | rough | S | face tile | The slime tile has circular corners and no border; the still face has continuous corners, a hairline and an amber rim. In dark the tile has no edge (1.18:1). Medium confidence | `Slime/SlimeView.swift:51-52`; `BoopFace.swift:78-82` | One shape and one border for both | crop |
| NOW-25 | rough | S | no agents | The "No agents awake" card is built by hand and differs from a notice (icon size, alignment) | `OverviewPane.swift:438-446` | Build it with `notice(…)` | crop |
| NOW-26 | rough | M | menu bar | Idle and working differ by one 3 pt dot. The asleep bars sit 2 pt low. Waking up draws the asleep icon. Medium confidence | `BoopFace.swift:217-284` | A 4 pt dot or eyes that look down; bars at the eyes' height | crop |

**Nits** (in `evidence/2026-11-09-ui-review/now.md`): NOW-24 the tile's art is soft and its laptop is cut; NOW-27 nine different left edges; NOW-28 Connected ends 2.5 pt left of Talk; NOW-29 the `</>` and `{}` marks; NOW-30 "grep · 12m" but "idle 27m"; NOW-31 seven radii; NOW-32 gaps of 5, 3 and 2; NOW-33 Talk is 0.5 pt taller than Hush; NOW-34 the Details arrow; NOW-35 the face against the text; NOW-36 the footer; NOW-37 a name in tracked capitals; NOW-38 trouble shown twice; NOW-40 the idle bar. NOW-39 found the hairlines sound.

### 3.2 The Boop tab

Long form: `evidence/2026-11-09-ui-review/tabs.md` (58 findings for this tab, World, the memory pane and Settings, and 6 proposals).

| Id | Sev. | Eff. | What is wrong | Cause | Fix | Picture |
| --- | --- | --- | --- | --- | --- | --- |
| BOOP-1 | rough | S | Decided: the part-full ring becomes blue. The look: `#2F7FD6` in light (3.83:1 on paper), `#58A6F0` in dark (6.84:1). Full stays sage, with a small check inside a full week ring, so "full" does not depend on colour alone. Do not use the gel's own blue `#4AAFFF` in light: it is 2.22:1 | `BoopPane.swift:118` | Add `Theme.ring` | crop |
| BOOP-4 | rough | S | The week's rings start at 28 pt; the heading is at 20 and the cards at 18 | `BoopPane.swift:62-71` | Put the strip in a card, or align its ends to the heading | crop |
| BOOP-5 | rough | S | On the first day one ring sits alone in the middle under "THE LAST 7 DAYS" | `BoopPane.swift:13, :63` | Always seven slots; days before the first are dashed | crop |
| BOOP-6 | rough | S | "82" is on screen three times, with four numbers in 96 pt of height | `BoopPane.swift:36-45, :54` | §4.3 | crop |
| BOOP-7 | rough | S | "Level N" moves 7 pt between part-full and full, because the text block is centred on the ring | `BoopPane.swift:28` | Top-align; move the line under the row | — |
| BOOP-12 | rough | S | The three note cards share the look of cards that open, and do not open. Medium confidence | `BoopPane.swift:85-96` | One card of plain lines with the link as its last row | crop |

**Nits:** BOOP-2 the arc's round cap pokes 4.5 pt back past the top; BOOP-3 the small rings' stroke is 15% of their size, the big ring's 9%; BOOP-8 the number sits 2.5 pt low; BOOP-9 the line always wraps; BOOP-10 the empty track is 1.19:1; BOOP-11 paddings of 10 and 12; BOOP-13 the link carries the name; BOOP-14 today is shown twice.

### 3.3 The World tab

!The region labels are not under their regions, and dots stack

| Id | Sev. | Eff. | What is wrong | Cause | Fix | Picture |
| --- | --- | --- | --- | --- | --- | --- |
| WORLD-1 | rough | S | The band maps 26 hours, so the regions are 118.5, 56 and 127 pt wide, not thirds. "Europe and Africa" is 78 pt of label over a 56 pt region. Nothing marks where a region starts | `WorldBand.swift:160-179` | Two hairline ticks; each label left-aligned to its region, in a footer strip (§4.4) | crop |
| WORLD-2 | rough | M | A buddy's x is exactly its time zone, so buddies stack in vertical columns and overlap | `WorldBand.swift:82-86` | Spread x a little by a hash; keep centres 7 pt apart | crop |
| WORLD-3 | rough | S | A picked asleep buddy is hidden under another dot: the card says "Bean · asleep" and the ring is round a green dot | `WorldBand.swift:34` | Draw asleep first, then awake, then the picked dot and your own on top | crop |
| WORLD-4 | rough | S | "you" touches the top dots; the line runs through every dot in your zone; your own picked dot wears two rings | `WorldBand.swift:37, :42, :85, :155` | Keep the top 18 pt for "you"; line behind the dots | crop |
| WORLD-5 | rough | S | In light mode the dots nearly match the band in brightness: teal 1.03:1 and amber 1.02:1 on the night side | `WorldBand.swift:118, :140-148` | A thin ink outline on awake dots; asleep as hollow rings, in both modes | crop |
| WORLD-8 | rough | S | Decided: a legend. The look: one 10 pt row under the band with 6 pt dots, asleep hollow, and only the kinds present | `WorldBand.swift:140-148` | §4.4 | — |
| WORLD-11 | rough | S | The three number tiles look like buttons and do nothing. Medium confidence | `WorldPane.swift:85-98` | One sentence in a small world; one card with three columns in a large one | crop |
| WORLD-12 | rough | M | The buddy's card looks like every other card; the sketch lifted it and gave it a face. Medium confidence | `WorldPane.swift:106-152` | §4.4 | crop |
| WORLD-14 | rough | S | Private and sending look the same: three dimmed buttons over a line of text | `WorldPane.swift:120-140` | Private: no buttons, the line and "Open Settings". Sending: dim only the pressed button | 1, 2 |
| WORLD-17 | rough | S | The time column forces every arrival onto two lines, with 70 pt empty before the time | `WorldPane.swift:216-227` | A short time as the first word | crop |
| WORLD-18 | rough | S | Each arrival is its own card. Medium confidence | `WorldPane.swift:211-229` | One card with hairline rows | — |
| WORLD-19 | rough | M | The same count shows three ways: a tile, the band, and a regions card. Medium confidence | `WorldPane.swift:56-58, :247-263` | Region counts in the band's footer; the regions card goes | crop |
| WORLD-21 | rough | M | Loading, trouble and unreachable are three grey cards, and the popover jumps from 314 to 690 pt when the world loads. Trouble has no way to try again | `WorldPane.swift:15, :50-55, :212-214` | Keep the layout at full height with the message on the empty band | crop |

**Nits:** WORLD-6 a lighter 12 pt strip at the band's left edge; WORLD-7 day and night are hard to tell apart; WORLD-9, 10, 20 uneven gaps and paddings; WORLD-13 Cheer is 2 pt taller than its siblings; WORLD-15 the close cross is a 9 pt mark; WORLD-16 "level 1234" without a comma; WORLD-22 9 pt type; WORLD-23 asleep dots in dark.

### 3.4 The memory pane

| Id | Sev. | Eff. | What is wrong | Cause | Fix | Picture |
| --- | --- | --- | --- | --- | --- | --- |
| MEM-1 | rough | M | A card for each section: five sentences take 572 pt. Medium confidence | `MemoryPane.swift:35-40, :47-74` | One card, headings inside, empty sections hidden | crop |
| MEM-2 | rough | M | The pin and the cross cost each note 70 pt of width, so every note is two lines. Medium confidence | `MemoryPane.swift:52-68` | Show both on hover, over the row's end | crop |
| MEM-4 | rough | M | Forget is a 10 pt cross beside the pin, and it deletes with no undo. The cross also means "close" elsewhere. Medium confidence | `MemoryPane.swift:62-66` | "Forgotten. Undo" in the row for 5 s | crop |

**Nits:** MEM-3 the marks miss the card's padding; MEM-5 a whole card for "Nothing yet."; MEM-6 empty and not-running look alike; MEM-7 the footer holds only Quit; MEM-8 pinned and unpinned differ by one mark.

### 3.5 Settings

| Id | Sev. | Eff. | What is wrong | Cause | Fix | Picture |
| --- | --- | --- | --- | --- | --- | --- |
| SET-1 | rough | M | It is 1,499 pt long: 2.76 screens, 8 sections, 17 rows. The world's switch is about 1,090 pt down | `SettingsPane.swift:24-36` | §4.4 | — |
| SET-2 | rough | S | Icons and controls are centred on the row, not on the title. With a five-line error the button sits 44 pt below its title | `SettingsPane.swift:469` | Top-align the row | crop |
| SET-3 | rough | M | Trouble is up to five lines of red 11 pt text squeezed beside the button. Medium confidence | `SettingsPane.swift:150-165, :194-196` | A short state in the row; the reason in a strip under it, full width | crop |
| SET-4 | rough | M | The Talk picker is three nested boxes and 190 pt tall. Medium confidence | `SettingsPane.swift:312-322, :402-455` | A three-part control and only the chosen kind's line: about 58 pt | crop |
| SET-5 | rough | S | In dark mode chosen rows and outlined buttons are darker than their surround. Medium confidence | `SettingsPane.swift:438-440`; `Theme.swift:494-495` | A "lifted" tone: paper in light, `#38332B` in dark | crop |
| SET-6 | rough | S | An off switch is 1.41:1. A disabled one is 1.07:1: it cannot be seen | `Theme.swift:517, :524` | Off track in `inkFaint`; disabled at 0.5 with a knob outline | crop |
| SET-8 | rough | S | "Forget about me" squeezes its own explanation to three lines, and looks like Reconnect though it deletes | `SettingsPane.swift:93-97` | Its own line, in clay ink, with a confirm | crop |
| SET-9 | rough | S | Two different "Forget" buttons on one scroll: the board's pairing and the memory. Medium confidence | `SettingsPane.swift:95, :213` | The board's goes under Advanced | crop |
| SET-10 | rough | M | A buyer never needs "Boop-01DD / Forget", the firmware row or the Simulator | `SettingsPane.swift` (Device) | A closed Advanced group (§4.4) | crop |

**Nits:** SET-11 two World rows that are not settings; SET-12 four left edges inside the cards; SET-13 one 10 pt note; SET-14 up to three filled buttons on a screen; SET-15 an 84 pt slider for 11 steps; SET-16 ghost controls when not running; SET-17 long names wrap titles.

### 3.6 Onboarding

Long form: `evidence/2026-11-09-ui-review/onboarding.md` (65 entries, a table of every act's sizes, and 4 proposals). The window is 720 × 560 pt in every act. Review the 9 acts for polish only: the move to 5 acts is decided for later, and §4.6 is the frame both need.

!Act 5 does not fit: the marks and the button move

| Id | Sev. | Eff. | Act | What is wrong | Cause | Fix | Picture |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ONB-1 | broken | M | 5 | The content is 18 to 43 pt taller than its room, and SwiftUI centres the overflow. The progress marks rise from 29 pt to 7.5 pt and the button's bottom margin falls from 30 to 8.5 pt. The frame also moves when a lesson is done | `OnboardingView.swift:17-33`; `OnboardingBoard.swift:259-285` | A fixed box for the act; move the mood legend out; a snapshot check on the marks and the button | crop |
| ONB-54 | broken | S | 9 | With a long name the finale's title wraps to two lines and turns left-aligned under a centred face | `OnboardingFinish.swift:374` | `.multilineTextAlignment(.center)`, 2 lines, scale down to 0.7 | crop |
| ONB-2 | rough | M | all | The title's top is at 7 heights, from 59 to 316.5 pt. Act 4 alone moves it 4 times | Each act builds its own stack | §4.6 | crop |
| ONB-3 | rough | M | all | The face has 8 sizes (44 to 236 pt) and 9 positions | Literals in every act | Three sizes: hero 150, side 64, legend 44 | crop |
| ONB-4 | rough | M | 3, 6, 7 | Empty bands above the button: 278 pt in act 6, 188 in act 3, up to 210 in act 7 | Every act ends with a spacer | Centre the body between the title and the bar | crop |
| ONB-6 | rough | S | all | Three bottom bars: the main button on the right (acts 2 to 8), centred with no Back (acts 1 and 9), none at all (act 4 looking and its errors) | `OnboardingView.swift:225-245` is skipped by three acts | One bar | — |
| ONB-7 | rough | S | 4 | After "Look for me", the link "I don't have my Boop yet" jumps 114.5 pt right and 4.5 pt down | `OnboardingBoard.swift:88-94` | The shared bar with a disabled "Looking…" | 1, 2 |
| ONB-9 | rough | S | 4 | The "for keeps" label wraps to two lines with a long name | `OnboardingView.swift:257` | One line, cut in the middle | crop |
| ONB-12 | rough | S | 6 | A disabled "Next" is 1.42:1, and the only live control is the quiet "Skip the tour". Medium confidence | `Theme.swift:474` | An outline with a readable label | crop |
| ONB-13 | rough | S | all | The footprints are 5 × 8 pt, unwalked ones 1.54:1, and the current one differs only by size. They read as decoration, not "step 5 of 9" | `OnboardingView.swift:71-82` | 6 × 10 pt, `inkFaint`, a dot under the current pair | crop |
| ONB-19 | rough | S | 2 | The three cards are 94, 79 and 79 pt tall | `OnboardingIntro.swift:156-160` | Equal heights | crop |
| ONB-21 | rough | S | 3 | The name field has no side padding: text runs to 3 pt from its border | `OnboardingIntro.swift:299` | 16 pt at each side | crop |
| ONB-22 | rough | S | 3 | A grey box sits behind the name: the system's selection. Low confidence on how it looks live | `OnboardingIntro.swift:304` | Caret at the end, not select-all | crop |
| ONB-25 | rough | S | 4 | The board's drawing is 60 pt left of centre | `OnboardingBoard.swift:213-224` | Centre the tile; the cable as an overlay | crop |
| ONB-27 | rough | M | 4 | Four layouts in one sequence: tile 150, 140, 160; four title heights | `OnboardingBoard.swift:38, :75-80, :145-158` | One slot and one tile size | crop |
| ONB-28 | rough | S | 4 | Error states leave a 61 pt hole, and the face still looks curious | `OnboardingBoard.swift:75-80` | The same slot; a sad mood | crop |
| ONB-29 | rough | S | 4 | In an error state the fix is a 22 pt row button, and there is no main button. Medium confidence | `OnboardingBoard.swift:83, :121` | The fix is the bar's main button | — |
| ONB-35 | rough | S | 5 | "waiting…" takes 75 pt of the row, so details wrap to a one-word last line | `OnboardingView.swift:172-175` | Put it on the title's line | crop |
| ONB-36 | rough | S | 5 | The current lesson is marked by a 1.16:1 tint. Medium confidence | `OnboardingView.swift:153` | A full-ink 1.5 pt border | — |
| ONB-37 | rough | S | 5 | "TRY" is 10 pt at 2.66:1 | `OnboardingBoard.swift:334` | 11 pt, soft ink | crop |
| ONB-40 | rough | M | 5 | The mood legend's four faces are 44 pt; Grumpy, Proud and Tired differ by 2 to 4 pixels. Medium confidence | `OnboardingBoard.swift:272-282` | Move it, with 64 pt faces | crop |
| ONB-43 | rough | S | 6 | On the "not found" Codex card the switch is 1.08:1 and the text 2.42:1 | `OnboardingFinish.swift:148`; `Theme.swift:524` | Do not fade the card; hide the switch | crop |
| ONB-45 | rough | M | 6 | The hooks panel: 100-character lines, a white scroll track, the first card cut with no fade | `OnboardingFinish.swift:62-77` | The agent's card first; 520 pt wide text; no track, a fade | crop |
| ONB-49 | rough | S | 7 | Three rows, three control sizes: a 22 pt switch, a 22 pt "Allow" with 11 pt text, a 13 pt tick, a 24 pt field | `OnboardingFinish.swift:311-316, :345-347` | One 28 pt control size in one column | crop |
| ONB-56 | rough | S | 9 | Tip cards in one row are 61 and 76 pt tall | `OnboardingFinish.swift:375-392` | A grid with stretched cells | crop |
| ONB-59 | rough | S | all, dark | The black face tile on dark paper is 1.19:1 and its shadow is gone: the tile has no edge | `Slime/SlimeView.swift:51-52` | A 1 pt border in dark mode | crop |
| ONB-61 | rough | S | all | Seven body text sizes: 15, 14, 13, 12.5, 12, 11, 10 | Literals | Four named sizes (§2.3) | — |

**Nits:** ONB-5, 8, 10, 11, 14 to 18, 20, 23, 24, 26, 30 to 33, 38, 39, 41, 42, 44, 46 to 48, 50 to 52, 55, 57, 58, 60, 63, 64. ONB-53 notes that act 8 is the cleanest act and the model for the frame.

### 3.7 The board

Long form: `evidence/2026-11-09-ui-review/board.md` (48 findings, a table of every text style, a map of the screen's zones, 7 proposals). The frame is 502 × 410 px; 1 px is 0.081 mm. At 70 cm, text reads comfortably with an x-height of 15 px and is legible down to 10 px. A finger needs about 87 px.

!From the chair: what survives

The sheet above shows key states at half size with a slight blur, which is about how the panel looks from a chair. The amber card, the names, the digits and the signs survive. The narration, the ring's label, "Today's done!", the drawer's detail and the no-app plug do not.

**The board has four fonts, all Geist Mono:**

| Font | x-height | Reads at 70 cm? | Carries today |
| --- | --- | --- | --- |
| 13 px, medium | 7 px, 0.56 mm | **No** | The narration, the ring's label, the drawer's sub-line and its chips |
| 22 px, semibold | 12 px, 0.97 mm | Marginal (capitals pass) | "Continue on your Mac", drawer titles, two-line low signs, the work stream |
| 28 px, semibold | 15 px, 1.21 mm | Yes | Signs, low signs, names, counts |
| 34 px, semibold | 19 px, 1.53 mm | Yes | The bubble |

| Id | Sev. | Eff. | Frame | What is wrong | Cause | Fix | Picture |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BRD-1 | broken | S | `states/poked`, `v1/ring-closed`, `reasons/*` | The narration is in the 13 px font: 0.56 mm. It carries the "why" and today the ring's "Today's done!" | gel `lane.cpp:205-209` | The 22 px font in a lighter grey; 18 letters fit | crop |
| BRD-2 | broken | S | `growbar/*`, `v1/ring-filling` | The ring's label "49 today" is 0.56 mm | gel `layers.cpp:839-841` | The number alone, in 22 px, after the bar; the bar 200 wide | crop |
| BRD-3 | broken | M | `drawer/open` | The drawer's sub-line and its WORKING / IDLE / NEEDS YOU chips are 0.56 to 0.73 mm | gel `drawer.cpp:47-54, :63` | Sub-line in 22 px; the strip's marks in place of word chips | crop |
| BRD-20 | broken | M | `drawer/open` | Drawer rows are 48 px tall: 3.9 mm. A miss opens the wrong session | gel `drawer.h:31-32` | Rows 66 px, pitch 72; 4 rows show | crop |
| BRD-37 | broken | S | `states/no_app`, `alone/*` | With no app the only sign is a 24 × 18 px grey plug in a corner, and Boop looks happy | gel `lane.cpp:246-251, :416` | The plug twice the size, centred, with words beside it | crop |
| BRD-45 | broken | L | the 8 activities | They differ by 20 to 950 pixels inside a monitor 7.7 mm wide. Delegating against working: 20 pixels. Decided: 4 activities with props the size of the body | gel `props.cpp:160-186` | A prop of 120 px or more for each | crop |
| BRD-4 | rough | S | `states/needs_you` | "Continue on your Mac" is 0.97 mm: marginal. Medium confidence | gel `props.cpp:250` | The kind line in 28 px (§4.5) | crop |
| BRD-5 | rough | M | `drawer/open` | Up to three sizes and two weights on one screen | `internal/tools/fontgen/fontgen.py:27-31` | Retire 13 px from all reading text | — |
| BRD-7 | rough | S | `lane/needs-you-long-name` | A cut name ends in two dots, "Make the device..", in the name's own ink | gel `lane.cpp:86-87` | A one-cell "…", or fade the last two letters | crop |
| BRD-8 | rough | S | many | Case has no rule: NEEDS YOU, PASS, "shipped!", "Level 12!", "boop back!". Medium confidence | — | Capitals for the board's own cards; lower case for all that Boop holds | crop |
| BRD-10 | rough | S | every strip | The first chip is 4 px from the corner's arc, and the arc's radius came from a photo. Medium confidence | gel `lane.cpp:39` | A 10 px gap everywhere | crop |
| BRD-11 | rough | M | `lane/working-counts` | The strip is a rebus: `✳2 ●●●● z3 3/7`. Only the digits survive from the chair. Medium confidence | gel `lane.cpp:216-232, :272-314` | Words when there is room (§4.5) | crop |
| BRD-13 | rough | M | `states/poked` | A touch replaces the strip, the rule and the drawer's handle with the caption for 2.5 s. Medium confidence | gel `lane.cpp:462-468` | The rule stays; the caption takes only the strip's row | crop |
| BRD-14 | rough | S | `transitions/act-on-1` | A low sign rises over the strip while the strip still shows | gel `lane.cpp:538-545` | Fade the strip as the sign rises | crop |
| BRD-16 | rough | S | `done/sign-long` | A two-line low sign runs into the finish's glow, to 9 px from the edge | gel `low_sign.cpp:62-63` | Raise it when a glow is on, or one line | crop |
| BRD-19 | rough | M | an ask (from code; no frame exists) | An ask's two answers are one bubble with four spaces between them, in the voice's colour. Medium confidence | `firmware/src/app/behaviour.cpp:441-444` | Two pills. Add an `ask` scenario to the simulator | — |
| BRD-21 | rough | S | `drawer/open` | The drawer's lid chips start at x 18 and its rows at x 35 | gel `drawer.cpp:141` against `:72-75` | One margin | crop |
| BRD-22 | rough | S | `drawer/more` | Nothing shows that the drawer scrolls, and the last row is cut by the corners. Medium confidence | gel `drawer.cpp` | A fade at the bottom and a small thumb | crop |
| BRD-24 | rough | S | every strip | The drawer's handle is a 20 × 9 px arrow in the dimmest ink (2.2:1). Medium confidence | gel `lane.cpp:320-326` | A 44 × 5 px grabber | crop |
| BRD-25 | rough | M | `states/needs_you` | The card covers 17 px of Boop's head and cuts the dome flat | gel `props.cpp:13` | The card higher (y 16 to 92); the body ducks 12 px | crop |
| BRD-26 | rough | L | many | Five box styles for five kinds of message: sign, low sign, card, start card, bubble | gel `layers.cpp`, `low_sign.cpp`, `props.cpp`, `lane.cpp` | Two families: "Boop holds it" and "the board says it" | crop |
| BRD-27 | rough | M | `lane/bubble-*` | Amber has three jobs: needs you, the voice's words, and gold. "Technical difficulties" in amber reads as an alert. Medium confidence | gel `lane.cpp:199` | The bubble's words in warm white; amber for needs you only | crop |
| BRD-30 | rough | M | `growbar-listening/*` | The top band stacks the ring's bar, LISTENING and the flying heart. Medium confidence | gel `layers.cpp`, `props.cpp` | One thing in the top band at a time | crop |
| BRD-32 | rough | M | `v1/ring-closed`, `v1/level-up` | The ring closing is the quietest big moment: a yellow line and two labels at 0.56 mm. Decided: one moment with the level | — | §4.5 | — |
| BRD-38 | rough | S | `lane/finish-*` | The finish's glow shows bands and a shift of hue in its tail. Medium confidence: the panel will tell | gel `done.cpp:58-94` | Dither the fade | crop |
| BRD-39 | rough | S | `finish/gold` | The gold trophy disappears on the gold flood | gel `finish.cpp:223-225, :582-591` | A dark outline during Gold Rush | crop |
| BRD-40 | rough | S | `finish/gold`, `finish/mega` | The gold flood lights 49% of full white against 13% at rest: a flash at night. Medium confidence | gel `finish.cpp` | Cap its golds at 70%; halve them at night | crop |
| BRD-46 | rough | L | `moods/*` | About 10 of the 42 emotions are distinct at real size. Decided: 18. The report gives 9 groups. Medium confidence | — | Give each kept emotion a change of shape or colour, since eyes are 10 to 14 px | crop |

**One to check by eye:** `moods/angry.png` shows squeezed eyes and an open smile. It reads as delight, not anger (BRD-46).

**Nits:** BRD-6 the bubble shrinks when a caption is under it; BRD-9 art text in 13 px; BRD-12 the idle chip's ring is 1.6:1; BRD-15 hands on top of the low sign but at the sides of the sign; BRD-17 the amber dot sits 3 px high; BRD-18 "+2" reads as part of the name; BRD-23 drawer rows against the sheet are 1.08:1; BRD-28 two ambers for needs you; BRD-29 warm and cool greys mixed; BRD-31 sparkles cut at the top edge; BRD-33 the sign cuts the open mouth; BRD-34 a `<3` sign smaller than its hands; BRD-35, 36, 41, 42, 44, 47. BRD-43 found the body's outline sound. BRD-48 lists scenarios the simulator lacks.

**The safe area holds.** The code already insets content from the rounded corners. Over all 570 frames, nothing a person must read is outside the arcs.

## 4. Layout and UX changes

The mockups are rough. The Mac's are HTML in `Theme.swift`'s colours, not SwiftUI, so spacing and type are close but not exact. The board's are drawn on real frames with the board's own font. Their sources are in `evidence/2026-11-09-ui-review/mock/`.

### 4.1 A two-row header

!Now: before and after

**Today** the header has up to nine things in four rows, is 73.5 to 128 pt tall, and overflows (NOW-1, 16, 17).

**Proposed:** two rows as tall as the face.

- Row 1: the name, and Talk.
- Row 2: one status line ("2 need you · feeling calm"), and the board's state on the right.
- The level moves to the Boop tab, where it is the content.
- Hush leaves the header. It is in Talk's menu, and it shows as a filled "Hushed 24m" beside Talk only while it is on.
- The face's border turns amber when something needs you, on the slime tile too.

**It fixes** NOW-1, 6, 16, 17, 18, 28, 33 and 35. Nothing on a line can overflow: the status line truncates. Every tab gets about 37 pt back. **It costs** one more click to hush. Effort: M.

### 4.2 The Now tab, in the order of need

The same mockup shows four changes.

1. **A needs-you card with weight and real buttons** (NOW-2, 3, 4, 9). A 4 pt amber bar and a stronger tint. The session's name first. The kind of thing that waits, as decided. Two buttons, "Open in Codex" and "Dismiss", in place of "click anywhere" and corner text. "1 of 2" in place of "+1 more".
2. **One list, sorted** (NOW-8, 22, 29, 30): needs you, then working, then idle, in one card with hairlines. The agent's name starts each detail line, so the sub-headings go. Needs you gets a solid amber chip, working a quiet word, idle nothing.
3. **Notices as one strip** (NOW-11, 12, 38): one line for each trouble with its one action, at most two lines, then "3 more". About 30 pt a trouble against 60 to 125 today.
4. **A mood card that says why** (NOW-19), shown only when there is a reason, a wish or a pastime to tell. The sketch put this first on Now. It should come after the needs-you card and the sessions, since status outranks it.

**It costs:** rows change place when a session's state changes. The code avoids that today (`OverviewPane.swift:449`). Animate the move. Effort: M for each of the four.

### 4.3 The Boop tab without "XP"

!Boop: before and after

- **In the ring:** `82` over `of 100`, as the sketch had it. Blue while filling, sage when full.
- **Beside it:** "Level 12", a thin bar to the next level with "18 to go", and "11 full days together" in place of "1,182 XP together".
- **Under it, full width:** the one line of words. It never wraps, so "Level 12" never moves (BOOP-7, 9).
- **The week:** always seven slots, in a card that shares the tab's edges, with a check inside each full day (BOOP-4, 5).
- **What Mochi knows:** one card of plain lines, and "See everything ›" as its last row (BOOP-12, 13).

Effort: M.

### 4.4 The World tab and Settings

!World: before and after

**World, for a small world.**

- **One sentence, not three tiles,** under about 20 buddies: "3 awake · 1 coding · 12 tests today". Three large tiles that say 3, 1 and 12 look like a failure; a sentence looks honest (WORLD-11).
- **The band** keeps its top 18 pt for "you", marks night and day, and has a footer strip with each region's name and count under its own part (WORLD-1, 4, 7, 19). With 8 or fewer buddies it prints their names.
- **Dots:** a thin outline in light mode, and asleep as hollow rings (WORLD-5). **The legend** is one row of the kinds present (WORLD-8).
- **The buddy's card** is lifted, has a face, and has one button: "Say hi" (WORLD-12, 14).
- **A goal card,** since a monthly goal is decided: the goal, a bar, and "Mochi added 340".
- **"For Mochi today"** is one card with the time as each row's first word (WORLD-17, 18).

!Settings: before and after

**Settings, regrouped:** about 990 pt in the mockup against 1,499.

- **Mochi:** the name (rename, as decided, joined with "Shown as"), Talk as a three-part control, the swear switch (decided, off by default), volume, the work stream.
- **Agents, The world, Memory, App:** as now, shorter. "What Mochi shares" becomes a caption under the world's card. "Forget about me…" is its own line in clay ink.
- **Advanced, closed by default:** the board and its pairing, updates, the Simulator, uninstall, and the brain's key until the brain is in the box.
- When the board has trouble, one clay strip shows at the top of Settings with its one action.

Effort: M for World, M for Settings.

### 4.5 The board: a reading rule and a calmer lane

!Needs you, with its kind

**The needs-you card, with its kind** (decided; BRD-4, 25, 28). The card moves up to the top band and clears Boop's head. A drawn mark for the kind, "NEEDS YOU", and the kind in the 28 px font: "a yes or no", "a question", "a plan to read". "Continue on your Mac" goes: the card says it by being there.

!The ring closes and the level goes up: one moment

**The ring and the level, one moment** (decided; BRD-1, 2, 32). The bar fills to gold with its number in the 22 px font. Boop holds up `today's done!`. A gold low sign follows with the level, and the finish's glow in gold. The narration row is not used.

!The strip in words

**The strip in words** (BRD-11, 12). "2 working · 3 idle" fits in the lane at the 28 px size. Marks come back only when a name takes the room.

!Narration you can read

**Narration you can read** (BRD-1, 13). The 22 px font in a lighter grey, on the lane's own row, with the rule and the handle still there.

**The rule behind all four.** One content box (x 24 to 478, y 16 to 394). Three bands: top 16 to 92, face 92 to 328, lane 328 to 394, with one message in each band at a time. Reading sizes are 28 px, and 22 px for a second line; 13 px is for art only. A touch target is at least 87 × 60 px. The full wireframes, with the drawer at 66 px rows, are in `evidence/2026-11-09-ui-review/board.md` §D.

Effort: S each for the narration and the ring's label; M for the card, the strip and the drawer.

### 4.6 One frame for onboarding

Two variants cover all nine acts, and the five to come. The wireframes are in `evidence/2026-11-09-ui-review/onboarding.md` §C.

| Part | Rule |
| --- | --- |
| Progress marks | Fixed at the top in a 20 pt box. They never move |
| Hero acts (1, 3, 4, 8, 9) | A 150 pt face, then the title at 236 pt, then the body |
| List acts (2, 5, 6, 7) | A 64 pt face beside the title at 66 pt, then a left-aligned body, centred in its space |
| The bar | Back on the left at x 48. The main button on the right, always there: disabled with a spinner while waiting, and an error's fix when stuck. One quiet link 8 pt to its left |
| Type | Title 26, card title 15, lead 14, note 13, detail 12, caption 11 |

It fixes ONB-1 to 4, 6, 7, 27, 28, 29 and 64. Effort: M to L, as one piece of work.

## 5. Quick fixes

Each is under an hour and stands alone. Paths are under `app/Boop/Views/` unless they say otherwise; "gel" is `characters/boop/firmware/src/render/gel/`.

| # | Where | Change | Finding |
| --- | --- | --- | --- |
| 1 | `OverviewPane.swift:180` | Remove `.fixedSize()`; add `.lineLimit(1)` and a low layout priority | NOW-1 |
| 2 | `OverviewPane.swift:174, :177` | `Theme.inkFaint` → `Theme.inkSoft` | NOW-6 |
| 3 | `OverviewPane.swift:314, :691` | Amber dot and bar: `#B87400` in light mode | NOW-5 |
| 4 | `OverviewPane.swift:420-422` | Lay "+N more" out only when N > 0 | NOW-2 |
| 5 | `OverviewPane.swift:816` | Selected tab: paper in light, `hairlineStrong` in dark | NOW-15 |
| 6 | `OverviewPane.swift:532-540` | A notice's cross as an overlay | NOW-11 |
| 7 | `OverviewPane.swift:88` | A "Waking up…" note when there is no status | NOW-20 |
| 8 | `OverviewPane.swift:248` | Remove `.padding(.trailing, 2)` | NOW-28 |
| 9 | `OverviewPane.swift:753` | Row padding: leading 13 → 12, vertical 7 → 8 | NOW-27, 32 |
| 10 | `PopoverView.swift:59-67` | Move the bug report into Settings | NOW-21 |
| 11 | `PopoverView.swift:116` | A 16 pt fade above the footer while more is below | NOW-14 |
| 12 | `Slime/SlimeView.swift:52` | `style: .continuous`, and the still face's border | NOW-23, ONB-59 |
| 13 | `BoopPane.swift:118`, `Theme.swift` | `Theme.ring`: `#2F7FD6` light, `#58A6F0` dark | BOOP-1 |
| 14 | `BoopPane.swift:116-118` | Start the arc half a cap in | BOOP-2 |
| 15 | `BoopPane.swift:28` | Top-align the ring's row | BOOP-7 |
| 16 | `BoopPane.swift:86`, `WorldPane.swift:86, :216` | Card padding 10 → 12 | BOOP-11, WORLD-10 |
| 17 | `BoopPane.swift:91` | "See everything ›", without the name | BOOP-13 |
| 18 | `WorldBand.swift:34` | Draw asleep dots first, the picked dot and your own last | WORLD-3 |
| 19 | `WorldBand.swift:156, :164` | 9 pt → 10 pt | WORLD-22 |
| 20 | `WorldPane.swift:110` | `buddy.level.formatted()` | WORLD-16 |
| 21 | `WorldPane.swift:125-130` | `.frame(height: 12)` on the Cheer image | WORLD-13 |
| 22 | `WorldPane.swift:120-140` | No buttons when private; dim only the pressed one while sending | WORLD-14 |
| 23 | `SettingsPane.swift:469` | `HStack(alignment: .top)` in `SettingRow` | SET-2 |
| 24 | `SettingsPane.swift:383` | 10 pt → `.caption()` | SET-13 |
| 25 | `Theme.swift:517, :524` | Off track in `inkFaint`; disabled at 0.5 | SET-6 |
| 26 | `Onboarding/OnboardingFinish.swift:374` | `.multilineTextAlignment(.center)`, 2 lines, scale to 0.7 | ONB-54 |
| 27 | `Onboarding/OnboardingView.swift:257` | The "for keeps" label: one line, cut in the middle | ONB-9 |
| 28 | `Onboarding/OnboardingIntro.swift:299` | `.padding(.horizontal, 16)` on the name field | ONB-21 |
| 29 | `Onboarding/OnboardingBoard.swift:334` | "TRY": 11 pt, `inkSoft` | ONB-37 |
| 30 | `Onboarding/OnboardingFinish.swift:148` | Do not fade the "not found" card | ONB-43 |
| 31 | `Onboarding/OnboardingIntro.swift:156-160` | Equal card heights in act 2 | ONB-19 |
| 32 | gel `lane.cpp:205-209` | The narration in the 22 px font, grey (173,163,150) | BRD-1 |
| 33 | gel `layers.cpp:839-841` | The ring's number in 22 px, without "today" | BRD-2 |
| 34 | gel `lane.cpp:39`, `low_sign.cpp:16`, `drawer.cpp:22`, `layers.cpp:811` | Corner gap 4 → 10 | BRD-10 |
| 35 | gel `lane.cpp:199` | The bubble's words in warm white | BRD-27 |
| 36 | gel `lane.cpp:538-545` | Fade the strip while a low sign rises | BRD-14 |
| 37 | gel `drawer.cpp:141` | The lid's margin equals the rows' | BRD-21 |
| 38 | gel `lane.cpp:337, :367` | The amber dot 3 px lower | BRD-17 |
| 39 | gel `layers.cpp:846-850` | Sparkles rise at most 12 px | BRD-31 |
| 40 | gel `finish.cpp:223-225` | A dark outline on the trophy during Gold Rush | BRD-39 |

A change to what the gel draws rebuilds the mirror (`firmware/tools/mirror.sh`) and changes simulator goldens.

**Bugs that are not about the look.**

| Bug | Where | How it fails |
| --- | --- | --- |
| The firmware offer is never rendered in a snapshot | `internal/app/Boop/Snapshots.swift:207-213, :273-276`; `app/Boop/MenuBarApp.swift:259-262` | `settings-firmware-offer-*` is byte-identical to `settings-simulator-off-*`, and `onboarding-4-body-joined-hungry-*` to `…-joined-*`. The fixture's board does not match the fixture's device, so no offer is made. The row with "Update" has never been seen in a picture |
| Four more snapshot pairs are byte-identical | `Snapshots.swift` | `9-finale-gel` = `9-finale`; `5-how-to-done` = `5-how-to-talk`; `6-agents-long` = `6-agents-heard`; `7-small-things-long` = `7-small-things` |
| Every big face in the snapshots is one still | `Snapshots.swift:270` | "Asleep", "listening" and "needs you" all show the same awake, happy face, so a wrong face would not be caught |
| About 10 onboarding states have no snapshot | `OnboardingFinish.swift:24-28, :47-54, :346-348`; `OnboardingBrainKey.swift:32-33` | No agent found, hook errors, mic refused, key saved and failed, firmware writing |
| The contrast check skips what fails | `Snapshots.swift:1036` | It tests 58 pairs of text on surfaces. It does not test `inkFaint`, any graphic colour, or opacity |
| The simulator has no frame for an ask, for needs you with the ring, or for a finish with a bubble and a caption | the gel's `lane` scenario | The lane's hardest cases cannot be reviewed |

## 6. A plan

Fitted to the phases in [TODO.md](TODO.md). Each step ships alone. A step that changes the Mac is checked with `--snapshots`; a step that changes the gel is checked with `make -C internal sim` and then on the panel.

| Step | Phase in TODO | What | Size | The owner checks by eye |
| --- | --- | --- | --- | --- |
| 1 | 0 | Quick fixes 1 to 31 on the Mac, in three commits (popover, tabs, onboarding). A snapshot check that the face's left edge is at the gutter | 1 day | Flip through the working, needs-you and long states: nothing moves sideways |
| 2 | 0 | Fix the snapshot fixtures: the firmware offer, the identical pairs, a real face for each state. Extend the contrast check to graphics and `inkFaint` | 1 day | The "Update" row, seen for the first time |
| 3 | 0 | Quick fixes 32 to 40 on the board; rebuild the mirror; new goldens | 1 day | **On the panel, from your chair:** the narration, the ring's number, the corner gap at all four corners |
| 4 | 1 | The Boop tab (§4.3) with the decided ring colour | 1 to 2 days | The blue against the gel's own blue; the ring at 0 and at 100 |
| 5 | 2 | The token set (§2.3): spacing, named type, radii, one card, row, chip and button family. Use `evidence/2026-11-09-ui-review/system/changes.md` as the list, and read each line before you apply it | 3 days | Every snapshot, before and after, side by side: it should look the same, only more even |
| 6 | 2 | The two-row header (§4.1) | 1 to 2 days | A long name, a long mood, hushed, muted |
| 7 | 2 | The board's lane (§4.5): the strip in words, one row, the needs-you card with its kind, the ring and level moment, the drawer's rows. With the model's cuts: 4 activities with props | 1 week | **On the panel:** read each state from 70 cm; hit each drawer row with a finger; the gold flood in a dark room |
| 8 | 3 | The Now tab (§4.2): the card, the sorted list, the notices strip, the mood card | 3 days | Six notices at once; a session changing state while you watch |
| 9 | 4 | The World tab and Settings (§4.4) | 1 week | The band with 3 buddies and with 200; the popover's height as the world loads |
| 10 | 4 | Onboarding's frame (§4.6), then the 5 acts | 1 week | A full first run: nothing jumps between acts |

Steps 1 to 3 need no decision. Steps 6 to 9 each depend on an open question below.

## 7. Open questions for the owner

| # | The decision | My recommendation |
| --- | --- | --- |
| 1 | The two-row header moves the level to the Boop tab and Hush into Talk's menu. Is one more click to hush acceptable? | Yes. Hush is rare; the header is on every tab |
| 2 | Sessions as one list sorted by need, so rows move, or grouped by agent as now, so rows stay? | Sorted, with the move animated |
| 3 | May a row be cut? The code's rule today is "never" | Yes: 2 lines for a title, 1 for a branch, the full text in the tooltip |
| 4 | Lane colours in the popover: keep them with stronger light-mode partners, or one neutral bar? | Keep, with partners and a tooltip. They tie the Mac to the board |
| 5 | The gutter from 18 to 16, and body text: stay at 12, or go back to the sketch's 13.5? | Gutter 16; keep 12. The popover is already tall |
| 6 | On the board, amber for needs you only? Then the bubble's words turn warm white | Yes |
| 7 | The strip in words ("2 working · 3 idle") or in marks? | Words, with marks only when a name takes the room |
| 8 | Drawer rows at 66 px: 4 rows show, not 5.4 | Yes. A row you cannot hit is not a row |
| 9 | Case on the board: capitals for the board's own cards, lower case for all Boop holds (so "level 12!", "pass")? | Yes. It also settles the signs' register |
| 10 | Settings: an Advanced group, closed, for the board, updates, the Simulator and the brain's key? | Yes |
| 11 | Memory: pin and forget on hover only, and forget with a 5-second undo? | Undo: yes. Hover only: no, keep them visible but smaller, since hover cannot be found |
| 12 | The World band's top-level numbers as a sentence in a small world? Under how many buddies? | Yes, under 20 |
| 13 | `moods/angry.png` looks delighted. Is that the design? | Check it; it may only be the frame's moment |
| 14 | The corner radius of 110 px came from a photo. Is the first strip chip whole on your panel? | Look at all four corners; then keep 4 px or go to 10 |
| 15 | Should the next mockups be in SwiftUI on a scratch branch, so they are exact? | Yes, for the header and the Now tab only, before step 6 |

## 8. Evidence index

No product code was changed. No Jev request was made. Nothing was pushed.

**Not checked, and why.**

| What | Why | Who can judge it |
| --- | --- | --- |
| The real panel: colour, brightness, real legibility, banding, touch, frame rate | `boopctl ping` showed `ble: conn` (the owner's app was connected) and `face_down: true`, so the board was left alone | The owner, with the app off its Bluetooth. `evidence/2026-11-09-ui-review/board.md` §E lists 11 things to look at |
| The app live: hover, pressed and focus states, motion, scrolling, the popover's own frame and arrow | The internal build was not opened: it puts a window on the owner's screen, and the stills answered the layout questions | The owner, or a later session with leave to open it |
| The simulator's page in a browser | A simulator was already running on port 8206; the same firmware's frames were read from `make -C internal sim` | — |
| Whether each face fits its words in onboarding | Every big face in the stills is one image | After the fixture is fixed (§5) |
| An ask on the board | No simulator frame exists | After a scenario is added |

**What is a judgement of taste, not a measurement:** the severity of each rough finding; "looks like a button"; the layout proposals; the readings "from the chair", which use a rule of thumb for letter height at 70 cm and a half-size blurred sheet, not the panel.

**Commands run, from the `v1-polish` worktree.**

| Command | Result |
| --- | --- |
| `git status`, `git log --oneline -8`, `make -C internal build` | Clean; `548c6e03`; the build passed |
| `.build/debug/Boop --snapshots /tmp/ui/snaps` | 286 PNGs at 2 pixels a point |
| `make -C internal sim` (run earlier the same day; no firmware change since) | 570 gel frames, 502 × 410 |
| `internal/tools/boopctl board`, `ping`, `state` | Free; `ble: conn`; `face_down: true`; the board was not used |
| Pillow, from `internal/tools/.venv`, for every measurement and crop | The scripts are beside each report |
| Playwright, for the HTML mockups | `evidence/2026-11-09-ui-review/mock/shot.js` |

**Where it is kept.**

| What | Where |
| --- | --- |
| The five long reports | `evidence/2026-11-09-ui-review/system.md`, `evidence/2026-11-09-ui-review/now.md`, `evidence/2026-11-09-ui-review/tabs.md`, `evidence/2026-11-09-ui-review/onboarding.md`, `evidence/2026-11-09-ui-review/board.md` |
| 158 marked crops | `evidence/2026-11-09-ui-review/now/crops/` (33), `evidence/2026-11-09-ui-review/tabs/crops/` (45), `evidence/2026-11-09-ui-review/onboarding/crops/` (47), `evidence/2026-11-09-ui-review/board/crops/` (33) |
| The mockups and their sources | `evidence/2026-11-09-ui-review/mock/`: four before-and-after pairs for the Mac, four for the board, the HTML, and `board.py` |
| The design system's census, contrast table and change list | `evidence/2026-11-09-ui-review/system/` |
| Everything else: all 286 snapshots, the 570 frames, work sheets | `~/.boopdev/ui-review-2026-11-09/` on the owner's Mac |
| The sketch compared against | `~/.boopdev/v1-ui/v1-ui.html`, `v1-ui.png` |

In the long reports, a path that starts `~/.boopdev/ui-review-2026-11-09/snaps` is a snapshot, and one that starts `…/sim` is a simulator frame.
