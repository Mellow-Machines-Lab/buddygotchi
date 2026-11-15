# Boop popover review: header, Now tab, footer, menu bar icon

Reviewed: every `overview-*.png` (68 files, light and dark), `menubar-*.png`, `slime-tile.png` in `~/.boopdev/ui-review-2026-11-09/snaps`.
Code read in `/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish`. Code paths below are relative to it.
Numbers are measured from the PNGs with Pillow (2 px = 1 pt). Contrast is the WCAG ratio from the palette in `app/Boop/Views/Theme.swift`.
Crops are in `now/crops/`. A red box marks the problem.

Short verdict: the system is consistent and calm, but one layout bug breaks the gutter in the default "working" picture, the header carries too much, and the needs-you card is quieter than the face tile above it.

## A. Findings

Severity: **broken** / rough / nit. Effort: S (under an hour), M (a day), L (more).

### Broken

**NOW-1 · Header, states `working`, `long`, `long-buddies` · broken · S · confidence high**
Crops: `01-working-gutter-8pt.png`, `02-long-buddies-clipped.png`. Sources: `overview-working-*.png`, `overview-long-*.png`, `overview-long-buddies-*.png`.
- Wrong: the third header line (`Feeling X · Level N` + Hush + Talk) cannot shrink. When it is wider than 266 pt, the whole column grows past 360 pt and is centred. Measured left gutter: 18 pt in 30 states, **8 pt in `working`** ("determined"), 17 pt in `long`, **0 pt in `long-buddies`** (face and Talk are cut by the window edge).
- Why it matters: every card, the tab bar and the face jump sideways when the mood word changes. The default demo state is one of the broken ones.
- Budget: 266 pt − Hush 48 − Talk 70 − 2 × 4 = 140 pt for the label. "Feeling calm · Level 12" is 118 pt. A mood longer than about 8 letters overflows. In the pack: determined, mischievous, uncomfortable, disappointed, frightened, speechless, embarrassed, affectionate, overwhelmed, and probably the 9-letter ones. A level of 100+ also overflows.
- Cause: `app/Boop/Views/OverviewPane.swift:135-140` (HStack), `:180` (`moodLabel` `.fixedSize()`), `:285` and `:303` (buttons `.fixedSize()`); `app/Boop/Views/PopoverView.swift:37` frames the column but does not clip it.
- Fix: remove `.fixedSize()` at `:180`; give the label `.lineLimit(1).truncationMode(.tail).layoutPriority(-1)`, or wrap the row in `ViewThatFits { one line; label above buttons }`. Better: move the buttons off this line (proposal C1). Add a snapshot check: the face's left edge is at 18 pt in every overview (the harness has `checkNothingCut` for height only, `internal/app/Boop/Snapshots.swift:930`).

### Rough

**NOW-2 · Needs-you card, `needs-you-said`, `crowded`, `bounded` · rough · S · high**
Crop: `07-needs-you-reserved-column.png`. Source: `overview-needs-you-said-light.png`.
- Wrong: an invisible "+0 more" column (42 pt + 10 pt gap) is always laid out. The hint wraps 52 pt early ("…Click to / open it in Claude.") with empty card to its right.
- Why: the most important card looks unbalanced and is one line taller than needed.
- Cause: `OverviewPane.swift:420-422` (`.opacity(attn.more > 0 ? 1 : 0)`).
- Fix: draw "+N more" only when `more > 0`, as `.overlay(alignment: .topTrailing)`; pad only the title line's trailing edge. Reserve room for Dismiss with a bottom inset on the last line only.

**NOW-3 · Needs-you card, Dismiss and "+1 more" · rough · S · high**
Crop: `06-needs-you-card.png`. Source: `overview-needs-you-light.png`.
- Wrong: Dismiss is bare 11 pt text in the corner of a card that is itself one big button. Text is 42 × 9.5 pt. Its right edge is at 332 pt; "+1 more" ends at 329.5 pt (2.5 pt off). Its baseline is about 1 pt below the hint's last line. "+1 more" has the same colour and weight as Dismiss but does nothing.
- Why: two click targets nested with no visible boundary; a slip opens the agent's app instead of dismissing.
- Cause: `OverviewPane.swift:383-386` (`.buttonStyle(.plain)`, `.padding(10)`), `:420`.
- Fix: Dismiss as a small outlined button (`RowButtonStyle`, amber ink), trailing inset 12 to match the card padding. Make "+1 more" plain `inkSoft` text, or make it scroll to the next waiting row.

**NOW-4 · Needs-you card, light mode weight · rough · S · medium**
Crop: `06-needs-you-card.png`.
- Wrong: fill `#F4E8D1` on paper is 1.14:1 and the edge 1.38:1. In dark the edge is 3.48:1. In light the card is only a little stronger than a session row (1.09:1).
- Why: in the first second the eye goes to the black face tile, then the bold name, then the tab bar. The card that says "an agent waits" comes fourth.
- Cause: `Theme.swift:83` (`cardTint = 0.08`), `:170` (edge `opacity(0.45)`).
- Fix: light mode tint 0.08 → 0.16 and edge to solid amber 1.5 pt, or a 4 pt amber bar on the card's leading edge, as rows have.

**NOW-5 · Header status dot, light, all needs-you states · rough · S · high**
Crop: `20-status-dot-amber-light.png`.
- Wrong: the amber dot `#FFB000` on `#FAF7F2` is 1.71:1. The amber row bar on a row is 1.57:1.
- Why: needs-you is the one state that must be seen. The code already knows this for the menu bar (`menuAmberLight`, `Theme.swift:27`).
- Cause: `OverviewPane.swift:314`, `:691`.
- Fix: use `#B87400` (3.2:1) for the dot and the bar in light mode; keep `#FFB000` in dark (9.7:1).

**NOW-6 · Header, "Feeling" and "· Level 12" · rough · S · high**
Crop: `18-feeling-contrast.png`.
- Wrong: both use `inkFaint`: 2.66:1 light, 3.62:1 dark, at 11 pt. `Theme.swift:12-13` says `inkFaint` "is for decoration and disabled things only".
- Cause: `OverviewPane.swift:174`, `:177`.
- Fix: `Theme.inkSoft` for both (5.9:1). Keep the mood word semibold.

**NOW-7 · Session rows, lane bars, light · rough · S · high**
Crops: `08-rows-lanes.png`, `29-lime-bar-light.png`. Source: `overview-working-light.png`.
- Wrong: lane colours against the row in light: lime 1.29, teal 1.60, rose 1.81, lilac 2.18. In dark they are 6 to 11. The fifth working session has no lane, so its bar is `inkSoft` (5.4:1): the strongest bar in the list, for no reason.
- Why: four colours with no stated meaning. The popover never says they match the board's lanes. One row looks "special" by accident.
- Cause: `OverviewPane.swift:692`; palette `Theme.swift:40`.
- Fix: a light-mode lane set at 3:1 or more (for example `#149A96`, `#D9489F`, `#8257E6`, `#5E9E1F`; check these before use); fallback bar `Theme.inkFaint`; tooltip "Its lane on the board". Or drop lane colours here and keep one neutral "working" bar.

**NOW-8 · Session list order, `crowded` · rough · M · medium**
Source: `overview-crowded-*.png`.
- Wrong: rows are grouped by agent in a fixed order. The waiting session is the 7th row, at y = 533 pt. With two or more waiting, only the first is on the card.
- Why: "needs you comes first" holds for the card, not for the list.
- Cause: `OverviewPane.swift:451-468`.
- Fix: one flat list sorted needs you, working, idle; show the agent as a small glyph or word on each row (proposal C3). This also removes the sub-headers.

**NOW-9 · Card and row name the same session in opposite order · rough · S · high**
Crops: `06-needs-you-card.png`, `27-row-order-vs-card.png`.
- Wrong: card: **project** `branch` / name. Row: **name** / project.
- Cause: `OverviewPane.swift:398-413` (`sessionTitle`) against `:729-740` (`rowTitle`).
- Fix: the card uses `rowTitle` order (name first, project and branch small).

**NOW-10 · Rows never truncate, `long`, `needs-you-long` · rough · S · medium**
Crop: `26-long-needs-you-card.png`. Source: `overview-long-light.png`.
- Wrong: a long row is 61 to 65 pt (4 lines) against 43 pt. The branch breaks inside a token ("…name-for-/the-hero-section"). The card grows to 118 pt.
- Why: five long sessions fill 700 pt. The code wants this ("neither is ever cut", `:640`, and `checkNothingCut`), so this is a decision to revisit.
- Cause: `OverviewPane.swift:642-658`, `:733-747`.
- Fix: title `lineLimit(2)`; workspace `lineLimit(1)` + `truncationMode(.middle)`; detail line `lineLimit(1)`; full text in `.help`.

**NOW-11 · Notices: the cross takes text width · rough · S · high**
Crop: `11-notice-x-wrap.png`. Source: `overview-no-key-light.png`.
- Wrong: with a cross, detail text ends at 287 pt; without, at about 309 pt; the card's inner edge is 330 pt. The cross costs about 39 pt (button 19 + two 10 pt gaps from the `Spacer`).
- Cause: `OverviewPane.swift:532-540`.
- Fix: remove the `Spacer` and the button from the HStack; add the button as `.overlay(alignment: .topTrailing)`; pad the title only (`.padding(.trailing, 20)`).

**NOW-12 · Notices stack as a wall, `long-notices`, `hook-failed` · rough · M · high**
Crops: `12-notices-wall.png`, `33-long-notices-header.png`.
- Wrong: each notice is a full card, 20 pt apart (the section gap). Six notices push "Sessions" to y = 838 pt, below a 560 to 720 pt popover. Raw error text shows at the same size and colour as the plain words. The header also repeats the trouble in red ("Wrong firmware").
- Cause: `OverviewPane.swift:42` (one VStack, `gapSection`), `:47-87`.
- Fix: group notices in their own `VStack(spacing: 8)`. Show at most 2; the rest fold into one row "3 more things to fix". Raw detail in 10.5 pt monospaced. See proposal C4.

**NOW-13 · Scrolling states (`*-bounded`): cards get narrower than the header · rough · M · medium**
Crop: `09-bounded-scroller.png`. Source: `overview-bounded-light.png`.
- Wrong: with a visible scroll bar, cards end at 326.5 pt. Header and tab bar end at 342 pt. Right margin 33.5 pt, left 18 pt. The scroller track (345 to 360 pt) starts under the tab bar and is a grey system strip on warm paper.
- Cause: `PopoverView.swift:114-118`, `OverviewPane.swift:29-31` (padding is inside the scroll view).
- Fix: force overlay scrollers on the pane's `NSScrollView` (`scrollerStyle = .overlay`), or hide indicators and add the fade of NOW-14. Medium confidence: on a trackpad the bar already overlays; mouse users and "Always show scroll bars" get this.

**NOW-14 · Scrolling states: content is cut with no cue · rough · S · high**
Crop: `10-bounded-cut.png`.
- Wrong: the last row is cut through its second line by the footer hairline. No fade, no shadow.
- Cause: `PopoverView.swift:116`.
- Fix: a 16 pt paper-to-clear gradient over the bottom of the scroll area while more is below, or a soft shadow on the footer.

**NOW-15 · Tab bar, dark mode · rough · S · high**
Crop: `05-tab-pill-dark.png`.
- Wrong: the selected pill is `paper` `#1B1815` inside the well `#2C2822`. It is darker than the well, so the selected tab looks pressed in. In light it is raised.
- Cause: `OverviewPane.swift:816`.
- Fix: an adaptive fill: paper in light, `hairlineStrong` `#4A4339` in dark.

**NOW-16 · Header is too busy and too tall · rough · M · high**
Crops: `03-header-anatomy.png`, `17-all-chips-header.png`, `16-hushed-chip.png`.
- Wrong: up to 9 things: face, name, Doing dot + word, "Feeling X", "Level N", Connected, Hush, Talk, and chips. Height 73.5 pt plain, 93 pt with chips, 128 pt with a long name and chips (23% of a 560 pt popover). It repeats on Boop and World, where Feeling, Level and Connected do not matter. Level is the Boop tab's own content.
- Cause: `OverviewPane.swift:110-151`.
- Fix: proposals C1 and C2.

**NOW-17 · Name wraps early because Connected sits beside it · rough · S · high**
Crop: `17-all-chips-header.png`.
- Wrong: "Wobblebottom McSnugs" (20 letters, under the 23 limit) wraps to two lines at 187 pt, though the column is 266 pt.
- Cause: `OverviewPane.swift:122-126`.
- Fix: move the device line to the status row's trailing edge (C1).

**NOW-18 · Hush moves from a button to a chip · rough · S · medium**
Crop: `16-hushed-chip.png`.
- Wrong: after a click on Hush, the button goes away and a "Hushed · 24 min ×" capsule appears two rows lower. It looks like the passive Chatty and Muted chips but is a button. Its × is 8 pt.
- Cause: `OverviewPane.swift:255-289`.
- Fix: keep one control in one place: the Hush button becomes a filled "Hushed 24m" toggle.

**NOW-19 · The mood card says what the header says · rough · S · high**
Crop: `31-mood-card-bare.png`.
- Wrong: "Mochi is calm." alone in a 38 pt card, in about 30 of 40 states. The header already says "Feeling calm". A card with one bold line looks like a title with a missing body.
- Cause: `OverviewPane.swift:93-94`, `:780-788`.
- Fix: show the card only when it has a reason line. Then lead with the reason (C5).

**NOW-20 · `waking-up` is empty · rough · S · high**
Crop: `14-waking-up-empty.png`.
- Wrong: tabs, then 28.5 pt of nothing, then the footer. Three live tabs lead to empty panes.
- Cause: `OverviewPane.swift:88` (everything is inside `if let status`).
- Fix: a `NoteCard("Waking up…")` or two placeholder rows; dim the tab bar until the first status.

**NOW-21 · Footer: the ladybug · rough · S · high**
Crop: `19-footer.png`.
- What it is: `Image(systemName: "ladybug")`, "Save a bug report" (⌘B), `PopoverView.swift:59-67`. It is disabled when Boop is not running.
- Wrong: an icon with no word beside a button with a word. It reads as decoration or a debug switch. It shows on every open of the popover for an action that is rarely needed. Gap gear to "Settings" is 9.5 pt (loose); "Settings" to ladybug 26 pt.
- Fix: move it into Settings ("Save a bug report…"). Keep it in the "stopped unexpectedly" notice, where it already is. Label icon gap: `HStack(spacing: 5)`.

**NOW-22 · Status chips · rough · S · medium**
Crops: `08-rows-lanes.png`, `30-rows-dark.png`.
- Wrong: chip fill against the row: 1.17 to 1.26 in light, so the shape is almost invisible. "working" is in full ink (11:1), louder than "needs you" (4.75:1). "idle" text is 4.61:1. Widths 33, 50.5 and 65 pt give a ragged left edge.
- Cause: `Theme.swift:409-420`, `OverviewPane.swift:679-686`.
- Fix: needs you = solid amber fill, dark ink; working = `inkSoft`; idle = no chip (the detail line already says "idle 27m").

**NOW-23 · Face tile: two treatments · rough · S · medium**
Crops: `21-tiles.png`, `22-tile-edge-dark.png`.
- Wrong: the slime tile has circular corners and no border (`app/Boop/Views/Slime/SlimeView.swift:51-52`). The still face has continuous corners, a hairline, and an amber rim when an agent needs you (`app/Boop/Views/BoopFace.swift:78-82`). In dark, black on `#1B1815` is 1.18:1, so the slime tile has no edge. The slime tile never shows the amber rim.
- Fix: one modifier for both: `RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)` + the same `strokeBorder`.

**NOW-24 · Slime tile art · rough · M · low**
Crop: `21-tiles.png`. Source: `slime-tile.png` (92 × 92 px).
- Wrong: the picture is soft at 46 pt, and the laptop prop is cut by the tile's left edge. It reads as a glitch block. (This is the fixture still; the live mirror may differ.)
- Fix: crop to the body for the tile, or hide kit in the tile.

**NOW-25 · "No agents awake" card differs from notices · rough · S · high**
Crop: `13-no-agents-icon.png`.
- Wrong: icon centred vertically (notices: top), 14 pt (notices: 13 pt), no 18 pt frame, so text starts at 56.5 pt and not 58 pt.
- Cause: `OverviewPane.swift:438-446`.
- Fix: build it with `notice(…)`.

**NOW-26 · Menu bar icon · rough · M · medium**
Crop: `15-menubar.png`.
- Wrong: (a) idle and working differ by one 3 × 3 pt dot; at 1× that is a 3 px square. (b) Asleep bars sit at y 10 to 12 of 18, 2 pt below the eyes' centre, and read as two low dashes. (c) Waking up draws the asleep icon (`FaceMood(nil)`, `BoopFace.swift:15-17`). (d) Needs-you is not a template image (`:279`), so it may not dim on an inactive display or invert when highlighted; this is read from the code, not seen. Light amber `#B87400` is 3.24:1; dark 7.9:1. Good: crisp at 1×, and the eyes do not move when the dot comes.
- Cause: `BoopFace.swift:217-284` (`:268` bars, `:274` dot).
- Fix: working = dot 4 pt, or eyes that look down; asleep bars at y 8 to 10; keep amber. Check (d) on a real bar.

### Nits

**NOW-27 · Left-edge ladder · nit · S · high**
Crops: `23-text-left-edges.png`, `24-agent-header-indent.png`.
- Measured left edges (pt): cards 18; agent glyph 19 (`</>`), further in for the narrower `{}`; section label 20; mood-card text 30.5; row title 31; footer "Settings" 41; agent name 42; notice text 58; header text 76.5.
- Cause: `Theme.swift:232` (label `.padding(.leading, 2)`), `OverviewPane.swift:753` (row leading 13 against card 12), `:457` (18 pt glyph frame).
- Fix: row leading 13 → 12; section label leading 2 → 12 (aligns with card text at 30); agent name at 30.

**NOW-28 · Connected ends 2.5 pt left of Talk · nit · S · high**
Crop: `04-header-right-edges.png`. Cause: `OverviewPane.swift:248` (`.padding(.trailing, 2)`). Fix: remove it.

**NOW-29 · Agent sub-headers · nit · S · medium**
Crop: `24-agent-header-indent.png`.
- `</>` for Claude Code and `{}` for Codex are generic code symbols with no tie to either agent, and their widths differ. With one session (`gel`): "SESSIONS · 1", "</> Claude Code", then one row. That is 49 pt of labels for one row.
- Cause: `OverviewPane.swift:549-555`, `:456-461`. Fix: hide the sub-header when only one agent has sessions; or C3.

**NOW-30 · Detail line format · nit · S · high**
Crop: `08-rows-lanes.png`.
- "grep · 12m" but "idle 27m" and "waiting 2m" (no dot). In monospace " · " is 3 cells, about 19 pt of air. "✓" appears to come from another font.
- Cause: `OverviewPane.swift:699-708`, `:745`.
- Fix: system font 10.5 pt with `.monospacedDigit()`, or a thin space + dot; one pattern for all three states ("idle · 27m").

**NOW-31 · Radii · nit · S · high**
- In use: 12 (cards), 12.4 (face), 10 (prominent button), 8 (rows, tab well), 7 (row buttons), 6 (chips, tab pill), capsule (header chips), 2 (bar).
- Cause: `Theme.swift:97-99`, `:494`, `OverviewPane.swift:207`. Fix: buttons 7 → 8 (`wellRadius`); header chips → `chipRadius` 6.

**NOW-32 · Vertical rhythm one-offs · nit · S · high**
- Measured: header to tabs 12; tabs to content 12; section to section 20; label to content 8; agent header to row 5; row to row 5; agent group to group 12; last card to footer hairline 19; footer 40.
- Outside the scale (4/8/12/18/20): 5 (`OverviewPane.swift:454`), 3 (`:121`, `:781`), 2 (`:405`, `:731`), tab bar inset 2 (`:828`), row padding 7 (`:753`).
- Fix: 4 between rows and 8 under the agent header; row vertical padding 7 → 8.

**NOW-33 · Talk button · nit · S · high**
Crop: `03-header-anatomy.png`. Talk is 70 × 22.5 pt, Hush 48 × 22 pt. Mic to "Talk" gap is 9.5 pt inside a fixed 50 pt frame. Cause: `OverviewPane.swift:297-300`. Fix: `HStack(spacing: 4)`, `.frame(height: 22)`.

**NOW-34 · Details disclosure · nit · S · high**
Crop: `25-details-indent.png`. The chevron starts at 60 pt, the text above at 58 pt. Opened raw text has the caption style, so "NSCocoaErrorDomain error 257" reads as advice. Cause: `Theme.swift:253-263`. Fix: `HStack(spacing: 3)` in place of `Label`; raw text monospaced 10.5 pt on a `well` box.

**NOW-35 · Face against text column · nit · S · medium**
Crop: `03-header-anatomy.png`. Face 18 to 64 pt; text column 21 to 82 pt. The buttons hang 18 pt below the face. Name cap top is 3 pt below the face top. Fix: C1 (two rows equal to the face height).

**NOW-36 · Footer · nit · S · medium**
Crop: `19-footer.png`. Quit has the same weight as Settings and takes the bottom-right corner. Buttons are about 21 pt tall (12 pt text + 4 + 4). Gear left edge 19 pt, Quit right edge 341.5 pt (both good). Cause: `PopoverView.swift:81-87`. Fix: leave Quit where it is, or move Quit and the bug report into one "…" menu.

**NOW-37 · Dressing card · nit · S · low**
Crop: `28-dressing-card.png`. In `long` the section label "WHY WOBBLEBOTTOM MCSNUGS JR LOOKS LIKE THIS" runs almost the full width in tracked capitals; a name in capitals loses its shape. Icons are 12 pt outline while notice icons are 13 pt filled. Cause: `OverviewPane.swift:96`, `:334`. Fix: a label without the name; the same icon size and weight as notices.

**NOW-38 · Trouble shown twice · nit · S · medium**
Crop: `33-long-notices-header.png`. `no-voice`, `no-bluetooth`, `long-notices`: a red word in the header and a red notice card under the tabs. Fix: keep the header word and make it scroll to the notice; or drop the header colour while the notice is on screen.

**NOW-39 · Hairlines · no change needed · high**
Hairline on paper: 1.29:1 light, 1.41:1 dark. It does not vanish in dark; it is slightly stronger there. The raised card on paper is 1.09 and 1.10. Button edges 1.54 and 1.81. No half-pixel blur found: card edges are 2 px solid with 1 px anti-aliased corners.

**NOW-40 · Idle bar · nit · S · medium**
The idle bar (`hairlineStrong`) is 1.41:1 on the row in light. It reads as a defect in the card's edge. Fix: no bar for idle, or `inkFaint`.

## B. Measured spec, as shipped (pt)

### Header (`overview-needs-you-light.png`)

| Part | Value |
| --- | --- |
| Popover width | 360 |
| Gutter left / right | 18 / 18 (8 or 0 when NOW-1 hits) |
| Top padding | 18 |
| Face tile | 46 × 46, radius 12.4, x 18 to 64, y 18 to 64 |
| Face to text | 12 |
| Text column | x 76.5; width 266 |
| Name | SF Rounded 18 semibold; cap top y 21; height 15 |
| Device line | 10 medium, `inkSoft`; dot 6; dot to text 5; right edge 339.5 |
| Row gap in column | 3 |
| Status row | dot 7 (y 47 to 54), gap 6, text 12 regular `inkSoft` (y 44 to 57) |
| Mood line | 11; "Feeling" and "· Level" `inkFaint`; mood semibold `inkSoft`; y 66 to 77.5 |
| Hush | 48 × 22; 11 medium; padding 10 / 4; radius 7; 1 pt `hairlineStrong` edge; paper fill |
| Talk | 70 × 22.5; label frame 50; mic 8.5 × 12; gap to Hush 4 |
| Chips row (when shown) | 8 under the column; chip 10 medium, padding 7 / 3, about 19 tall, capsule, `well` fill, gap 4, indent 76 |
| Header bottom to tab bar | 12 (4 + 8) |
| Tab bar | 324 × 28; well radius 8; inset 2; pill about 107 × 24, radius 6, 1 pt hairline, shadow y 1 blur 1 at 6% |
| Tab label | 12; semibold on, medium off |
| Tab bar to content | 12 |
| Top of popover to tab bar bottom | 123 plain; about 143 with chips; about 178 with a long name + chips |

### Now row and its neighbours

| Part | Value |
| --- | --- |
| Section label | 10 semibold, tracking 0.6, capitals, `inkSoft`, x 20 |
| Label to content | 8 |
| Agent header | 11 semibold `inkSoft`; glyph frame 18; gap 6; name x 42 |
| Agent header to first row | 5 |
| Row | 324 × 43 (2 lines), 59 (3 lines), 61 to 65 (4 lines); radius 8; `raised` fill; 1 pt hairline |
| Row padding | leading 13, trailing 8, vertical 7 |
| Lane bar | 3 × 32 (row height − 12); x 19 to 22; radius 2 |
| Title | 12 medium `ink`; x 31 |
| Beside the title | project 11 regular `inkSoft`, or branch 10.5 monospaced `inkSoft`; gap 6; first baselines aligned |
| Detail line | 10.5 monospaced `inkSoft`; 2 under the title |
| Chip | 10 medium; padding 7 / 3; 19 tall; widths 33 / 50.5 / 65; radius 6; tint 12%; right edge 334 |
| Row to row | 5 |
| Agent group to group | 12 |
| Section to section | 20 |
| Card | radius 12; padding 12; 1 pt hairline; needs-you: amber 8% fill, amber 45% edge |
| Needs-you card | icon 13 in an 18 frame, x 33; text x 58; title 12 semibold; name 11 medium; hint 11 regular; Dismiss 11 medium, inset 10 |
| Mood card | 38 tall with one line; 12 semibold; text x 30.5 |
| Content bottom padding | 18 |
| Footer | 1 pt hairline + 40; text 12; side padding 10 + 8; gear x 19; Quit right edge 341.5 |

## C. Layout proposals

### C1. Two-row header, as tall as the face (fixes NOW-1, 16, 17, 28, 33, 35)

```
┌──────────────────────────────────────────────┐
│ ┌────┐  Mochi                      [🎙 Talk] │   name 18, Talk 22 high
│ │face│  ● Working · calm          ● Connected│   one status line, 12
│ └────┘                                       │
│ [ Now ][ Boop ][ World ]                     │
```
- Mood joins the Doing line ("Working · calm"). Level moves to the Boop tab only. Hush shows in the chips slot only while it is on, or goes into Talk's menu.
- Height: 46 pt of face + 18 pt top, about 37 pt shorter than today. Nothing on the line can overflow: the status text truncates and the device line is fixed.
- Cost: S to M. Hush is one step further away.

### C2. Header that changes by tab (fixes "repeats on every tab but matters on one")

```
Now:    face  Mochi                 [Hush][Talk]
              ● 2 sessions need you
Boop:   face  Mochi · Level 12
              Feeling calm
World:  face  Mochi                 ● In the world
```
- Each tab shows only its own facts. Device trouble still shows on every tab as a red word.
- Cost: M. The header's height must stay equal across tabs so the tab bar does not move.

### C3. Flat session list, sorted by need (fixes NOW-8, 9, 22, 29, 30)

```
SESSIONS · 4
┌────────────────────────────────────────────┐
│▌Fix the hero image on mobile   [needs you] │  amber bar, solid amber chip
│ landing-page-redesign-v2 · fix-nav         │
│ Codex · waiting 2m                         │
├────────────────────────────────────────────┤
│▌jetpack                        [needs you] │
│ Claude Code · waiting 7m                   │
├────────────────────────────────────────────┤
│▌buddygotchi                       working  │  lane bar
│ Codex · swift test · ✓ 3/7 · 12m           │
├────────────────────────────────────────────┤
│ notes                                      │  no bar, no chip
│ Claude Code · idle 17m                     │
└────────────────────────────────────────────┘
```
- One card with hairline dividers, not N cards: one outline to read. The agent's name starts the detail line, so the sub-headers go.
- Cost: M. Rows change place when a status changes (the code avoids that today, `OverviewPane.swift:449`); animate the move.

### C4. Notices as one strip (fixes NOW-11, 12, 38)

```
┌─────────────────────────────────────────────┐
│ ⚠ Mochi stopped unexpectedly [Save report] ×│
│ ⚠ Jev isn't answering              Details ›│
│   3 more                                   ›│
└─────────────────────────────────────────────┘
```
- One line per trouble: icon, title, one action. The explanation opens in place. At most two lines show, then "N more".
- Height: about 30 pt per trouble against 60 to 125 pt today. Sessions stay on the first screen.
- Cost: M. Long titles need `lineLimit(2)`.

### C5. Mood card with its "because" (fixes NOW-19)

```
┌────────────────────────────────────────────┐
│ Determined                                 │  12 semibold, the mood word only
│ claude finished a long turn on "api".      │  12 regular, the reason
│ Wishing for a stroke.                      │  when there is a wish
└────────────────────────────────────────────┘
```
- Shown only when a reason, a wish or a pastime line exists. With none, no card: the header already names the mood.
- The owner's sketch puts this card first on Now ("Mochi is happy. claude finished a long turn on 'api'."). That works when no agent needs you; the needs-you card must still come before it.
- Cost: S.

### C6. Needs-you card with a real action row (fixes NOW-2, 3, 4)

```
┌▌───────────────────────────────────────────┐
│▌👋 Fix the hero image on mobile     1 of 2 │
│▌   landing-page-redesign-v2 · fix-nav      │
│▌   (what kind of thing waits)              │  already decided; shown here only for place
│▌   [Open in Codex]  [Dismiss]              │
└▌───────────────────────────────────────────┘
```
- Two visible buttons replace "click anywhere" + corner text. A 4 pt amber bar and a 16% tint give it weight in light mode. "1 of 2" replaces "+1 more".
- Cost: S to M. The card is about 20 pt taller.

## D. What stills cannot show

- Hover: rows and the needs-you card show no sign at rest that they open a session. `OpensButtonStyle` adds an `inkFaint` edge on hover (`Theme.swift:443-457`); not judged.
- Motion: the pulse ring on the status dot, the blink, the `.boopPop` spring when rows move, the card's scale-in, and chips fading in and pushing the tab bar down by about 20 pt.
- Scrolling: overlay or legacy scroller on the owner's Mac; bounce; whether the header really stays; scroll position after a row changes.
- Focus and keyboard: focus rings on Hush, Talk, tabs and rows; tab order; ⌘1 to ⌘3, ⌘B, ⌘,.
- The popover's own chrome: arrow, shadow, corner radius. The PNGs are the bare content.
- The live slime tile: frame rate, crop, the fade between faces. The snapshots use one still for every state, so "asleep", "listening" and "needs you" all show the same awake face.
- The menu bar icon on a real bar: wallpaper tint, highlight while the popover is open, inactive displays, the notch, its neighbours' weight.
- Text selection, `.help` tooltips, VoiceOver order, larger text settings.
- Real timing: how long "Waking up…" lasts, and whether the empty state is ever seen.
