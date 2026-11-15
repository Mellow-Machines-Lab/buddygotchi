# Boop tab, World tab, Memory pane, Settings: UI review

Reviewed 2026-11-09 from `~/.boopdev/ui-review-2026-11-09/snaps/` (94 files: every `boop-*`, `world-*`, `memory-*`, `settings-*`, light and dark). All numbers are measured with Pillow on the 2x PNGs and given in points (px / 2) unless they say px. Crops are in `tabs/crops/`. Code paths are relative to the `v1-polish` worktree. Nothing in the repo was changed.

Severity: **broken** (wrong or misleading), **rough** (visible to a buyer), **nit**. Effort: S under an hour, M a day, L more.

## Measured baseline (what is consistent, keep it)

| Thing | Value |
| --- | --- |
| Gutter, card left/right edges | 18 pt / 342 pt on every surface |
| Section heading | 10 pt semibold, tracked, left at 20 pt; heading to card 10 pt on all four surfaces; card to next heading 22 pt |
| Row buttons (Wave, Boop, Heart, Remove, Reconnect, Forget, Uninstall…, Open Settings, Save, Try again) | all 22 pt tall, radius 7, 11 pt medium |
| Settings controls | every control's right edge is at 330 pt; every icon is centred on x = 39 pt |
| Toggle | 28 x 16 pt; slider 84 pt wide, 14 pt knob, 4 pt groove; key field 22 pt tall |
| Big ring | 96 pt, 9 pt stroke, round caps, starts at 12 o'clock, clockwise |
| Small rings | 26 pt, 4 pt stroke, pitch 46.3 pt; ring centres and label centres agree within 0.5 pt |
| Soft grey text (`inkSoft`) | 5.89:1 on paper, 5.40 on cards, 4.94 on the well (light); 7.12 / 6.46 / 5.90 (dark). Passes |
| Settings pane | 1,499 pt of content in `settings-light.png`; the scroll area is at most 544 pt, so 2.76 screens |

---

## A. Findings

### The Boop tab

**BOOP-1. Part-full ring is blush, which reads as red/trouble. (Decided: blue. This is the look.)**
- State: `boop-light/dark`, `boop-long-*`. Crop: `crops/boop-today.png`, `crops/boop-week.png`.
- Wrong: blush `#F1787D` is 2.54:1 on paper and 2.14:1 on its track. It is also the "waiting" dot on the band, and the app's only other red is clay (trouble).
- Cause: `app/Boop/Views/BoopPane.swift:118` (`full ? Theme.sage : Theme.blush`).
- Fix: add `Palette.ringBlueLight = "#2F7FD6"`, `ringBlueDark = "#58A6F0"`, `Theme.ring = adaptive(...)`. Measured: light 3.83:1 on paper, 3.22:1 on the track; dark 6.84:1 on paper, 5.67:1 on the track. It sits in the gel's own blue family (the face tile samples at `#4AAFFF`, which is only 2.22:1 on light paper, so do not use that one in light). Full stays sage `#6E9B5E`. Keep the round end cap. Give the full ring a 1 pt lighter inner highlight or a small tick mark at 12 o'clock so "full" does not depend on hue alone.
- Severity rough, effort S, confidence high.

**BOOP-2. The arc's round start cap pokes 4.5 pt back past 12 o'clock.**
- Crop: `crops/boop-ring-top.png` (source `boop-light.png`).
- Wrong: with `lineCap: .round` the start cap adds half a stroke (4.5 pt big, 2 pt small) before the top. A 1% day draws a 9 pt blob that looks like 4%; on the small rings a 3% day looks like 10%.
- Cause: `BoopPane.swift:116-118`.
- Fix: start the trim half a cap in: `trim(from: capFraction, to: max(capFraction, fill))` with `capFraction = (width/2) / (pi * diameter)`, or draw nothing under 1%. Severity nit, S, high.

**BOOP-3. Big and small rings have different proportions.**
- Crop: `crops/boop-week.png`.
- Wrong: big is 9/96 = 9.4% stroke; small is 4/26 = 15.4%. The small rings look like a heavier, different object. The sketch draws the week at about 10%.
- Cause: `BoopPane.swift:30` (`width: 9`) and `:65` (`width: 4`, 26 pt).
- Fix: week ring 28 pt with a 3 pt stroke (10.7%). Nit, S, high.

**BOOP-4. The week strip does not share any left edge with the rest of the tab.**
- Crop: `crops/boop-week.png`.
- Wrong: the first ring starts at 28 pt and the last ends at 332 pt. The heading above starts at 20 pt and the cards below run 18 to 342 pt. The strip floats 10 pt in on both sides.
- Cause: `BoopPane.swift:62-71`: seven `frame(maxWidth: .infinity)` cells, each ring centred in a 46.3 pt cell.
- Fix: `HStack` with `Spacer()` between cells so the first ring's left edge is at 20 pt and the last ring's right edge at 340 pt (pitch 49 pt), or put the strip in a `Card` (see B2). Rough, S, high.

**BOOP-5. First day: one ring alone, centred, under "THE LAST 7 DAYS".**
- Crop: `crops/boop-first-day.png` (source `boop-first-day-light.png`).
- Wrong: a single empty 26 pt ring sits in the middle of a 324 pt row. It looks left over, and the heading is not true.
- Cause: `BoopPane.swift:13` shows whatever `status.week` holds; `:63` centres it.
- Fix: always draw seven slots. Days before the first day are a dashed 1 pt track with a faint label, today is last. Or hide the section until there are two days. Rough, S, high.

**BOOP-6. "82" is on screen three times and the numbers have no unit once "XP" goes.**
- Crop: `crops/boop-today.png`.
- Wrong: the ring says "82 today", the line says "82 today. Fill the ring…", and two grey lines say "1,182 XP together" and "18 to level 13". Four numbers in 96 pt of height, two of them the same.
- Cause: `BoopPane.swift:36-45, 54`.
- Fix: see B1. Rough, S, high.

**BOOP-7. "Level N" jumps 7 pt between states.**
- Source: `boop-light.png` (cap top at y = 139 pt) and `boop-ring-full-light.png` (146 pt).
- Wrong: the text block is centred on the ring, so its first line moves whenever the last line changes from two lines to one (and to three with a long name).
- Cause: `BoopPane.swift:28` `HStack(alignment: .center)`.
- Fix: top-align the block with a fixed 4 pt top inset, or move the line under the row (B1). Rough, S, high.

**BOOP-8. The number in the ring sits 2.5 pt low.**
- Crop: `crops/boop-today.png`.
- Wrong: the ink of "82" + "today" spans y = 165.5 to 206.5 pt; its centre is 186 pt, the ring's is 183.5 pt.
- Cause: `BoopPane.swift:32-37`, a `VStack` centred by line boxes, not ink.
- Fix: `.offset(y: -2)` on the overlay, or 2 pt bottom padding. Nit, S, high.

**BOOP-9. The line wraps into the text column.**
- Crop: `crops/boop-today.png`, `crops/boop-long-dark.png`.
- Wrong: the column is 210 pt wide, so "82 today. Fill the ring and you're / done for the day." is always two lines, and three with a long name ("…or give Wobblebottom / McSnugs Jr a pet.").
- Cause: `BoopPane.swift:41-44`.
- Fix: put the line under the ring row at full width (324 pt holds it on one line), or shorten it (B1). Nit, S, high.

**BOOP-10. Empty ring track is nearly invisible.**
- Source: `boop-first-day-light.png`, `boop-long-dark.png`.
- Wrong: the track (`well`) is 1.19:1 on light paper and 1.21:1 on dark. At 0 the ring is a ghost and the tab's first-second focus is a bare "0".
- Cause: `BoopPane.swift:115`.
- Fix: track in `hairlineStrong` (1.6:1 light) for rings only. Nit, S, medium.

**BOOP-11. Peek cards use padding 10; the empty-state card uses 12.**
- Crops: `crops/boop-peek-pad.png`, `crops/boop-peek-pad2.png`.
- Wrong: note text starts at 28 pt on a normal day and at 30 pt on the first day and in the Memory pane.
- Cause: `BoopPane.swift:86` `Card(padding: 10)` vs `NoteCard` (12) at `:83`.
- Fix: 12. Nit, S, high.

**BOOP-12. The peek cards look clickable and are not; the only way in is a text link.**
- Crop: `crops/boop-peek-pad2.png`.
- Wrong: they share the chrome of the Now tab's session cards, which open. The real target is a 12 pt sage link 176 pt wide.
- Cause: `BoopPane.swift:85-96`.
- Fix: make each card a button to the Memory pane with `OpensButtonStyle`, or drop the card chrome and show the notes as plain lines in one card with the link as its last row. Rough, S, medium.

**BOOP-13. The link carries the name and nearly fills the row with a long one.**
- Crop: `crops/boop-long-dark.png`.
- Wrong: "See everything Wobblebottom McSnugs Jr knows ›" ends at 319 of 342 pt. Two more letters and it wraps.
- Cause: `BoopPane.swift:91`.
- Fix: "See everything ›" (the heading above already has the name). Nit, S, high.

**BOOP-14. Full week ring and "Connected" share one green; today is in the strip twice.**
- Wrong: sage means connected, on, resting on the band, and a full ring. Today's ring appears big and again as the seventh small ring 80 pt lower.
- Fix: in B2, today's small ring is replaced by a marker. Nit, S, medium.

**BOOP-15. Differences from the owner's sketch.**
- Ring label "of 100" became "today". The grey breakdown "Today: claude's work 60 · you 22" and "A full ring is 100. More doesn't count…" are gone. The sketch's week rings are thinner and all one colour. The sketch shows two notes; three ship. The sketch's tiles-to-content gaps are 8 pt; the shipped tab is airier (20 pt). No finding by itself; listed as asked.

### The World tab

**WORLD-1. The region labels are not under their regions.**
- Crop: `crops/world-band-light.png` (source `world-card-light.png`).
- Wrong: the band maps UTC-12…+14 across 308 pt, so the regions are 118.5 pt (Americas), 56 pt (Europe and Africa) and 127 pt (Asia and Oceania) wide. They are not thirds. Label centres are at 90.75, 180 and 269 pt; a thirds layout would be 72, 180, 288. "Europe and Africa" is 78 pt wide over a 56 pt region, so it overhangs both neighbours by 11 pt. Gaps between labels are 30 pt and 12 pt. Nothing on the band marks where a region starts.
- Cause: `app/Boop/Views/WorldBand.swift:160-179` (`middle()` returns -6.5, 1, 8.5) with no boundary marks.
- Fix: draw two 1 pt hairline ticks (full height at 0.5 opacity) at UTC-1.9 and UTC+3.1, and left-align each label to its region's start, 10 pt. Or drop the labels and let the legend row and the region rows carry it (B3). Rough, S, high.

**WORLD-2. Buddies stack in exact vertical columns and overlap.**
- Crop: `crops/world-band-light.png`.
- Wrong: x is exactly the UTC offset, so each time zone is a column. I count seven overlapping pairs among 44 dots, and six dots sit on the "you" line.
- Cause: `WorldBand.swift:82-86` (x from offset only; y from one hash).
- Fix: jitter x by a second hash within ±0.4 h, then one relax pass that pushes centres at least 7 pt apart. Rough, M, high.

**WORLD-3. A picked asleep buddy is hidden under another dot.**
- Crop: `crops/world-pick.png` (source `world-card-light.png`).
- Wrong: the card says "Bean · asleep", but the ring surrounds a green (resting) dot that is drawn on top of Bean's grey one. The selection reads as the wrong buddy.
- Cause: `WorldBand.swift:34` draws in array order; the picked dot is not redrawn.
- Fix: draw asleep dots first, then awake, then redraw the picked dot and your own on top, before their rings. Rough (misleading), S, high.

**WORLD-4. "you" collides with dots, and your own dot can wear two rings.**
- Crop: `crops/world-you.png` (source `world-card-you-light.png`).
- Wrong: the 9 pt word sits at y = 7 and the top dot lane starts at y = 14, so the word touches a dot. The line runs through every dot in your zone. Picked, your dot has a 10 pt ring and a 14 pt ring.
- Cause: `WorldBand.swift:37, 42, 85, 155-156`.
- Fix: keep the top 18 pt free of dots (`inset + 12`), draw the line behind the dots at 0.25 opacity, and skip the `me` ring when `pick == me`. Rough, S, high.

**WORLD-5. In light mode the dots almost match the band in luminance.**
- Crop: `crops/world-band-light.png`.
- Wrong: on the night side teal is 1.03:1, amber 1.02:1, lilac 1.41:1, asleep 1.37:1. On the day side teal is 1.46:1 and asleep 1.72:1. Only hue separates them, which fails for low vision and colour-blind buyers. Dark mode is fine (4.5:1 to 10.5:1; asleep 2.8 to 3.1:1).
- Cause: `WorldBand.swift:118, 135, 140-148` (lane colours made for a black screen).
- Fix: in light mode add a 0.75 pt `ink.opacity(0.35)` outline to awake dots and draw asleep dots as hollow rings (`inkSoft`, 1 pt). Hollow-for-asleep also makes the legend readable without colour. Rough, S, high.

**WORLD-6. The band's left 12 pt is a lighter strip that reads as a rendering seam.**
- Crops: `crops/world-band-light.png`, `crops/world-band-dark.png`.
- Wrong: the band spans 26 hours, so UTC-12 repeats UTC+12's dusk at the left edge: night starts 12 pt in, after a pale strip. The gradient itself is smooth (120 stops, no banding seen at 2x).
- Cause: `WorldBand.swift:25, 121-126`.
- Fix: clamp darkness across the first and last `inset` so each edge holds its neighbour's value. Nit, S, medium.

**WORLD-7. Day and night are hard to tell apart in light, and inverted in weight in dark.**
- Wrong: light: night is 1.41:1 against day. Dark: the "day" half is 1.21:1 against the paper and the night half is near black, so the band looks like a hole with a grey patch. Nothing says which half is which (the sketch's caption did: "The dark side is night").
- Cause: `WorldBand.swift:118`.
- Fix: a 9 pt `sun.max.fill` and `moon.fill` in `inkFaint` at the band's bottom corners of each half, or the words in the legend row. Nit, S, medium.

**WORLD-8. Six dot colours and no key. (Decided: a legend. This is the look.)**
- Cause: `WorldBand.swift:140-148`.
- Fix: one legend row in the place of today's caption, 10 pt `inkSoft`, 6 pt dots, 4 pt dot-to-word, 10 pt between items: `● coding  ● testing  ● shipping  ● waiting  ● resting  ○ asleep`. Estimated 314 pt wide of 324; if a locale overflows, wrap to two rows of three. Show only the kinds present in a small world. "Click a buddy" moves to the band's hover help and an empty-card hint. See B3. Rough, S, high.

**WORLD-9. The tiles float away from the band.**
- Crop: `crops/world-tiles.png`.
- Wrong: tiles to band is 20 pt with no heading between; band to labels 5, to caption 10.5, to card 8.5. The sketch has 8.
- Cause: `WorldPane.swift:11` (`gapSection` between the two stacks at `:29` and `:38`).
- Fix: one stack, 12 pt. Nit, S, high.

**WORLD-10. Mixed card paddings: 10 and 12.**
- Crops: `crops/world-tiles.png`, `crops/world-arrivals.png`, `crops/world-regions.png`.
- Wrong: tiles and arrivals use 10 (content 28 to 332 pt); the buddy card, regions and notes use 12 (30 to 330 pt). Stacked right edges disagree by 2 pt.
- Cause: `WorldPane.swift:86, 216`.
- Fix: 12 everywhere. Nit, S, high.

**WORLD-11. The three tiles look like buttons.**
- Crop: `crops/world-tiles.png`.
- Wrong: 55 pt bordered cards with a bold number are the tab's first-second focus and use the chrome of things that open. They do nothing.
- Cause: `WorldPane.swift:85-98`.
- Fix: one card with three columns split by hairlines, or no chrome at all (B3). Rough, S, medium.

**WORLD-12. The buddy card does not look like it came from the dot.**
- Crop: `crops/world-card.png`.
- Wrong: it has the chrome of every other card, 8.5 pt under the caption. The sketch lifted it (paper fill, shadow, a face tile). Three equal 96 x 22 pt buttons are the densest cluster on the tab.
- Cause: `WorldPane.swift:106-152`.
- Fix: B4 (one gesture). Rough, M, medium.

**WORLD-13. "Cheer" is 2 pt taller and 4 pt wider than its siblings.**
- Crop: `crops/world-card-shipping.png`.
- Wrong: Wave, Boop, Heart are 69.5 x 22 pt; Cheer is 73.5 x 24 pt because `party.popper.fill` is a taller glyph.
- Cause: `WorldPane.swift:125-130`.
- Fix: `.frame(height: 12)` on the image, or it goes away with one gesture. Nit, S, high.

**WORLD-14. Private: three dead buttons.**
- Crop: `crops/world-off-card.png` (source `world-off-light.png`).
- Wrong: the card shows Wave, Boop, Heart at 0.4 opacity over two lines that say why they cannot be pressed. Sending looks the same (all three dimmed), so two different states share one look.
- Cause: `WorldPane.swift:120-140`.
- Fix: when `!world.on`, hide the buttons and show the line with an "Open Settings" row button. While sending, dim only the pressed button and show a spinner in it. Rough, S, high.

**WORLD-15. The close cross is a 9 pt glyph in a 25 x 17 pt target.**
- Crop: `crops/world-card.png`.
- Cause: `WorldPane.swift:145-149`.
- Fix: `.frame(width: 22, height: 22)` and 11 pt glyph. Nit, S, high.

**WORLD-16. Level is not formatted on the card.**
- Crop: `crops/world-long-card.png` (source `world-long-light.png`).
- Wrong: "level 1234" on the card; "Level 1,235" in the header.
- Cause: `WorldPane.swift:110`. Fix: `buddy.level.formatted()`. Nit, S, high.

**WORLD-17. The time column forces arrivals to wrap.**
- Crop: `crops/world-arrivals.png`.
- Wrong: icon 16 + time 48 + three 8 pt gaps leave 216 pt, so "Someone in Europe or Africa / booped Mochi." is two lines with 70 pt of empty card between the text and "10:42 AM". Row heights alternate 50 and 36 pt.
- Cause: `WorldPane.swift:216-227`.
- Fix: drop the time column; put a short time ("10:42") as the first word in `inkSoft`, or under the sentence only when it wraps. Rough, S, high.

**WORLD-18. Arrivals are a card each.**
- Source: `world-arrivals-many-light.png`.
- Wrong: five cards, four 8 pt gaps and a caption take about 240 pt before the regions.
- Cause: `WorldPane.swift:211-229`.
- Fix: one card with hairline rows, as the regions card is built (29 pt rows): about 150 pt. Rough, S, medium.

**WORLD-19. The same count is shown three ways.**
- Wrong: the tile says 214 awake, the band shows it, and the regions card says 88 + 97 + 29 = 214, under labels the band already has.
- Cause: `WorldPane.swift:56-58, 247-263`.
- Fix: merge the region counts into the band's footer (B3). Rough, M, medium.

**WORLD-20. "Joining" and "stale" put the same kind of label at different distances.**
- Crops: `crops/world-joining.png`, `crops/world-stale.png`.
- Wrong: "Joining the world…" is 20.5 pt above the tiles; "The world isn't answering…" is 8.5 pt above them. Same type, same icon size.
- Cause: `WorldPane.swift:23-27` (outside the stack) vs `:30-35` (inside).
- Fix: one slot for both, inside the tiles' stack. Nit, S, high.

**WORLD-21. Loading, trouble and unreachable are three grey cards, and the popover changes height.**
- Crop: `crops/world-empty-states.png`.
- Wrong: each is one soft `NoteCard`. Loading and trouble then show "FOR MOCHI TODAY / Nothing yet today.", which is not known while the world cannot be read. The tab is 234 to 329 pt tall in these states and 690 pt once loaded, so the popover jumps. Trouble has no icon and no way to retry.
- Cause: `WorldPane.swift:15, 50-55, 212-214`.
- Fix: keep the layout: three empty tiles ("–") and an empty band in `well` at full height, with the message centred on the band. Trouble gets `exclamationmark.triangle` and a "Try again" row button. Hide "For Mochi today" when there is no snapshot and no arrivals. Rough, M, high.

**WORLD-22. 9 pt type on and under the band.**
- Crop: `crops/world-band-light.png`.
- Wrong: "you" and the three region names are 9 pt, the smallest type in the app. At 2x their strokes only reach `rgb(125,119,107)`, about 3.9:1.
- Cause: `WorldBand.swift:156, 164`. Fix: 10 pt. Nit, S, medium.

**WORLD-23. Asleep dots in dark mode.**
- Crop: `crops/world-band-dark.png`.
- Fine for contrast (2.83:1 day, 3.10:1 night) but they are the same grey as nothing in the legend-to-be, and an asleep dot under an awake one disappears (WORLD-3). Hollow rings (WORLD-5) fix both. Nit, S, medium.

**WORLD-24. Differences from the owner's sketch.**
- Missing: the world goal card ("A million tests this month", bar, "Mochi added 340"). The card's face tile, its lift, and "Bean will see it when it wakes" before sending. City labels inside the band. Countries with flags (three regions ship). Emoji became SF Symbols. The time moved from inline to a right column. Caption lost "The dark side is night".

### The Memory pane

**MEM-1. One card per section, one heading per card.**
- Crop: `crops/mem-rows.png` (source `memory-light.png`).
- Wrong: five sentences take 572 pt: four headings, four cards, 22 pt between each.
- Cause: `MemoryPane.swift:35-40, 47-74`.
- Fix: B6. Rough, M, medium.

**MEM-2. Pin and cross cost every note 70 pt of width.**
- Crop: `crops/mem-rows.png`.
- Wrong: text wraps at 219 pt of the card's 300, so every note in `memory-light.png` is two lines; the same notes run to 304 pt in the Boop tab's peek.
- Cause: `MemoryPane.swift:52-68`.
- Fix: show the two buttons on row hover (always for VoiceOver and a pinned note's pin), overlaid at the trailing edge. Rough, M, medium (hover cannot be seen in stills).

**MEM-3. The glyphs do not line up with the card's padding.**
- Crop: `crops/mem-rows.png`.
- Wrong: the cross's ink ends at 321 pt; the card's content edge is 330 pt. Left padding looks like 12, right like 21.
- Cause: `.buttonStyle(.quiet)` pads 8 pt each side (`Theme.swift:432`) inside the card's 12.
- Fix: `.padding(.trailing, -8)` on the row's buttons. Nit, S, high.

**MEM-4. "Forget" is a 10 pt cross touching the pin's target, with no undo.**
- Crop: `crops/mem-rows.png`.
- Wrong: the two 26 pt targets are adjacent (centres 33 pt apart), one is harmless, one deletes for good. The cross is also the app's "close" glyph (the buddy card).
- Cause: `MemoryPane.swift:62-66`.
- Fix: after a forget, swap the row for "Forgotten. Undo" for 5 s; use `trash` or the word. Rough, M, medium.

**MEM-5. A whole card for "Nothing yet."**
- Crop: `crops/mem-partly.png` (source `memory-partly-light.png`).
- Cause: `MemoryPane.swift:50, 84-86`.
- Fix: hide an empty section, or one soft line without a card. Nit, S, high.

**MEM-6. Empty and not-running look the same.**
- Crop: `crops/mem-empty-states.png`.
- Wrong: both are one grey note card over the same footer line. "Not running" still says "Written on this Mac as Boop dreams…", and nothing marks it as trouble.
- Cause: `MemoryPane.swift:17-21, 42`.
- Fix: no footer line when `status == nil`; give the note the `exclamationmark.triangle` label. Nit, S, high.

**MEM-7. The footer bar holds only "Quit".**
- Crop: `crops/mem-rows.png` is the top; see `memory-light.png` bottom.
- Wrong: Settings and the bug button leave the footer on this pane, so a 36 pt bar carries one word.
- Cause: `PopoverView.swift:53-76`.
- Fix: put the "Written on this Mac…" caption there (as Settings puts its version there) and save 46 pt of scroll. Nit, S, medium.

**MEM-8. Pinned and unpinned notes differ by one 10 pt glyph.**
- Crop: `crops/mem-rows.png`.
- Fix: pinned pin in `ink`, unpinned in `inkFaint`; pinned notes first in their section. Nit, S, medium.

**MEM-9. Long title.**
- Crop: `crops/mem-long-dark.png`.
- "What Wobblebottom McSnugs Jr knows" fits at 16 pt (ends at about 337 of 342 pt) and wraps cleanly past that (`fixedSize` at `Theme.swift:194`). No fix needed; listed because it has 5 pt to spare.

### Settings

**SET-1. It is 1,499 pt long: 2.76 screens, 8 sections, 17 rows.**
- Source: `settings-light.png` (2,998 px).
- Wrong: a buyer scrolls past Bluetooth pins, a simulator and an API key to find the world switch (at 1,089 pt) and "Open at login" (1,321 pt). Talk alone is 190 pt.
- Cause: `SettingsPane.swift:24-36`.
- Fix: B5 (about 880 pt, 5 sections). Rough, M, high.

**SET-2. Icons and controls are centred on the row, not on the title.**
- Crops: `crops/set-no-voice.png`, `crops/set-long.png`.
- Wrong: with a five-line detail the Reconnect button is 44 pt below its title; in `settings-long` it is about 110 pt below. The icon drifts the same way.
- Cause: `SettingsPane.swift:469` (`HStack` default centre).
- Fix: `HStack(alignment: .top)`, icon and trailing control each in a 16 pt-high first-line box (`.frame(height: 16)`), so both sit on the title line. Two-line rows look the same as now. Rough, S, high.

**SET-3. Trouble is a wall of red inside the row.**
- Crops: `crops/set-no-voice.png`, `crops/set-hooks-off.png`, `crops/set-firmware-failed.png`.
- Wrong: up to five lines of 11 pt clay text wrap in a 150 to 200 pt column beside the button; the row grows from 49 to 115 pt.
- Cause: `SettingsPane.swift:194-196, 150-165, 246-251`.
- Fix: row detail keeps a short state ("Can't talk"); the explanation goes in a clay-toned `Card(tone:)` strip under the row at full width (two lines), with Details. Rough, M, medium.

**SET-4. The Talk picker is three nested boxes and 190 pt tall.**
- Crop: `crops/set-talk.png`.
- Wrong: card (radius 12) > well (8) > chosen row (6). It is 13% of Settings for a choice made once.
- Cause: `SettingsPane.swift:312-322, 402-455`.
- Fix: a `SettingRow` with a three-segment control (Quiet | Normal | Chatty, 168 x 22 pt, same well-and-raised look as the tab bar) and only the chosen kind's line as the detail: 58 pt. Rough, M, medium.

**SET-5. In dark mode "raised" selections are darker than their surround.**
- Crops: `crops/set-dark-device.png`; see also `settings-dark.png` Talk.
- Wrong: the chosen Talk row is `paper` `#1B1815` on a `well` `#2C2822`: it reads as a hole. Outlined row buttons (Reconnect, Forget) are also `paper` on a lighter card.
- Cause: `SettingsPane.swift:438-440`; `Theme.swift:494-495`.
- Fix: a `Theme.lifted` = adaptive(paper light, `#38332B` dark) for chosen rows, chosen tabs and outlined buttons. Rough, S, medium.

**SET-6. The off switch is 1.41:1; disabled, it is 1.07:1.**
- Crop: `crops/set-login-unavailable.png` (source `settings-login-unavailable-light.png`).
- Wrong: off track `hairlineStrong` on a card is 1.41:1 light, 1.64:1 dark. Disabled at 0.4 opacity it measures 1.07:1: the switch is not visible.
- Cause: `Theme.swift:517, 524`.
- Fix: off track `inkFaint` (2.44:1 light, 3.28:1 dark); disabled opacity 0.5 and keep a 0.5 pt knob outline. Rough, S, high.

**SET-7. The firmware offer is never rendered.**
- Source: `settings-firmware-offer-*.png` are byte-identical to `settings-simulator-off-*.png` (same MD5). Crop: `crops/set-firmware-writing.png`.
- Wrong: no "Update to 1.1.0" row and no filled Update button in any still; writing and failed show the title "Firmware" with no version.
- Cause: `internal/app/Boop/Snapshots.swift:207-213`: the fixture's `BoardFirmware(board: "cyd24")` does not match the fixture device, so `BoardFirmware.update(for:among:)` returns nil (`app/Boop/MenuBarApp.swift:259-262`).
- Fix: give the fixture device the matching board. Then review the row. Broken (coverage), S, high.

**SET-8. "Forget about me" squeezes its own explanation.**
- Crop: `crops/set-brain-memory.png`.
- Wrong: a 108.5 pt button leaves 160 pt, so the detail is three lines and the row 62 pt. It is a destructive action in the same style as Reconnect.
- Cause: `SettingsPane.swift:93-97`.
- Fix: put the action on its own line under the text, clay ink, with a confirm. Rough, S, high.

**SET-9. Two different "Forget"s 300 pt apart.**
- Crops: `crops/set-agents-device.png`, `crops/set-brain-memory.png`.
- Wrong: "Forget" (the board's Bluetooth pin) and "Forget about me" (the memory) share a word and a style.
- Cause: `SettingsPane.swift:95, 213`.
- Fix: the board row moves under Advanced (B5) and its button says "Unpair". Rough, S, medium (the word is a copy call; the layout part is that both are on one scroll).

**SET-10. A buyer never needs three Device rows.**
- Crop: `crops/set-agents-device.png`.
- Wrong: "Boop-01DD / Forget", "Simulator" and the firmware row are support or developer tools. They are 40% of the Device card. (The Simulator row only shows in debug and internal builds: `MenuBarApp.swift:494-500`; every still has it.)
- Fix: B5, under a closed "Advanced" disclosure. Rough, M, high.

**SET-11. World rows two and three are not settings.**
- Crop: `crops/set-world-app.png`.
- Wrong: "Shown as Mochi · Europe and Africa" and "What Mochi shares" are icon rows with no control. They look tappable and take 120 pt.
- Cause: `SettingsPane.swift:68-83`.
- Fix: "Shown as" becomes the rename row's detail (B5); "What Mochi shares" becomes an 11 pt caption under the card, as the sketch had it. Nit, S, medium.

**SET-12. Four left edges inside the cards.**
- Crops: `crops/set-talk.png`, `crops/set-brain-memory.png`.
- Wrong: row titles at 58 pt, the Talk titles at 42 pt, the key field at 30 pt, headings at 20 pt.
- Cause: `SettingsPane.swift:319, 391, 435`.
- Fix: Talk and the key become `SettingRow`s (icons `bubble.left`, `key`), so everything is at 58 pt. Nit, S, high.

**SET-13. The key's note is 10 pt.**
- Crop: `crops/set-brain-memory.png`.
- Wrong: every other detail is 11 pt; this one is 10 pt and two lines.
- Cause: `SettingsPane.swift:383`. Fix: `.caption()`. Nit, S, high.

**SET-14. Up to three filled black buttons on one screen.**
- Crops: `crops/set-offline-nokey.png`, `crops/set-agents-device.png`.
- Wrong: Connect, Repair and Update all use `rowFilled`; `Theme.swift:459` says one filled button per screen.
- Cause: `SettingsPane.swift:177, 183, 255`.
- Fix: filled only for the one thing that is broken now (Repair, or Connect when no agent is connected); Update is outlined. Nit, S, medium.

**SET-15. The volume slider is 84 pt for 11 steps.**
- Crop: `crops/set-sound.png`.
- Wrong: 7.6 pt per step under a 14 pt knob, while 100 pt of the row is empty.
- Cause: `SettingsPane.swift:108`. Fix: 120 pt. Nit, S, medium.

**SET-16. Not running: a dash for the volume and a ghost switch.**
- Crop: `crops/set-not-running.png`.
- Wrong: the Sound and Talk cards dim their controls to 0.4 but keep full-ink titles; volume reads "–".
- Cause: `SettingsPane.swift:110, 124, 320`.
- Fix: hide Sound and Talk while `status == nil` and show one note card ("Boop isn't running…") in their place; the pane drops to about 700 pt. Nit, S, medium.

**SET-17. Long names wrap titles in odd places.**
- Crop: `crops/set-long.png`.
- Wrong: "Wobblebottom McSnugs / Jr's body" (the button reserves 77 pt); "Shown as Wobblebottom McSnugs Jr · Europe / and Africa".
- Cause: `SettingsPane.swift:68, 194`.
- Fix: titles never carry the name ("Body", "Shown as"); the name and region go in the detail. Nit, S, high.

**SET-18. Hairlines and cards in dark mode.**
- Crop: `crops/set-dark-device.png`.
- Card on paper is 1.10:1, card edge 1.41:1, row divider 1.28:1. They hold at 2x; no doubled or missing lines found. No fix; listed because it was asked.

---

## B. Layout proposals

### B1. The Boop tab without "XP"

The ring is the day. The level is the long run. Say each once.

```
┌──────────────────────────────────────────────┐
│   ╭─────╮                                    │
│  ╱  82   ╲    Level 12                       │  18 pt bold rounded
│ │  of 100 │   ▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░  18 to go    │  4 pt bar, 120 pt, ring blue
│  ╲       ╱    12 full days so far            │  11 pt soft (optional)
│   ╰─────╯                                    │
│ Fill the ring and you're done for the day.   │  12 pt, full width, one line
└──────────────────────────────────────────────┘
```

- In the ring: `82` (28 pt bold) over `of 100` (11 pt soft), as the sketch had it. "today" is in the week strip.
- "1,182 XP together" goes. If a lifetime number must stay, count days: "12 full days so far".
- "18 to level 13" becomes a 4 pt bar toward the next level with "18 to go" after it. The bar uses the ring's blue, so the eye links ring and level.
- The line sits under the row at 324 pt, so it never wraps and "Level 12" never moves (BOOP-7, BOOP-9). Full: "Today's ring is full. Nice work." in sage ink with a check.
- Ring: blue `#2F7FD6` / `#58A6F0` part-full, sage full, track `hairlineStrong`.

### B2. The week strip

```
 THE LAST 7 DAYS
┌──────────────────────────────────────────────┐
│  ◯    ◔    ◯    ◯    ◑    ◯    ◕             │  28 pt rings, 3 pt stroke
│  Mon  Tue  Wed  Thu  Fri  Sat  Today         │  10 pt, Today semibold
└──────────────────────────────────────────────┘
```

- First ring's left edge at the heading's edge (20 pt), last ring's right edge at 340 pt.
- Always seven slots. A day before Boop existed is a dashed 1 pt circle and a faint label. On the first day the heading says "This week".
- Full days: sage ring with a 9 pt check inside, so full does not rely on colour.
- Today's slot: the ring plus a 3 pt dot under the label, not a second copy of the big number.

### B3. The World tab, for a small world, with a legend

```
 3 awake · 1 coding · 12 tests today             one line, 13 pt, numbers bold
┌──────────────────────────────────────────────┐
│ ☾        ·    you            ☀           ☾   │  96 pt band; top 18 pt lane for "you"
│      ●        │ ●      ○         ●           │  dots r 4 in a small world (r 3 over 40)
│   ○           │    ●                         │  hairline ticks at region starts
├───────────────┬────────┬─────────────────────┤
│ Americas  2   │ Eur·Af 1 │ Asia·Oceania  0   │  10 pt, in the band's footer, left-aligned
└──────────────────────────────────────────────┘
 ● coding  ● testing  ● shipping  ● waiting  ● resting  ○ asleep     the legend, 10 pt
 5 buddies in the world so far. More arrive as people join.           small world only

 ┌─ Bean · level 7 ────────────────────────[x]─┐   opens under the band
 │ Asia and Oceania · asleep · 3:20 PM          │
 │ [  👋 Say hi  ]   Bean will see it when it wakes. │
 └──────────────────────────────────────────────┘

 FOR MOCHI TODAY
┌──────────────────────────────────────────────┐
│ 👆 10:42  Someone in Europe or Africa booped Mochi. │  one card, hairline rows
│ 🎉  9:15  3 buddies cheered your ship.              │
│ And 4 more today.                                    │
└──────────────────────────────────────────────┘
```

- Numbers: under about 20 buddies, the three tiles become one line. Three big tiles saying "3 / 1 / 12" look like a failure; a sentence looks honest. Over that, one card with three columns.
- The region counts move into the band's footer strip, each under its own region, between ticks. The separate "Around the world" card goes (WORLD-19).
- Legend: 6 pt dots, labels in `inkSoft`, asleep hollow. Only the kinds present.
- Small world: bigger dots, no jitter needed, and with 8 or fewer buddies show their names beside the dots (10 pt), since a name is worth more than a dot.
- Worth opening: the "For Mochi today" card moves above the band when it has anything new since the last open, with a count on the World tab's label.

### B4. The buddy card with one gesture

```
┌──────────────────────────────────────────────┐
│ [face]  Bean · level 7                  [x]  │  28 pt face tile; paper fill, 1 pt hairlineStrong,
│         Asia and Oceania · asleep · 3:20 PM  │  shadow 0/2/8 at 8%: it is lifted
│                                              │
│ [ 👋  Say hi ]   Bean will see it when it wakes. │  one 22 pt button, filled; the line beside it
└──────────────────────────────────────────────┘
 sending:  [ ◌ Sending… ]   (only the button dims)
 sent:     [ ✓ Said hi ]    sage ink, not a disabled button
 failed:   [ 👋 Try again ]  "It didn't go through." in clay
 private:  no button.  "Mochi is private, so it can't say hi."  [Open Settings]
 you:      no button.  "This is Mochi, as other buddies see it."
 shipping: the same one button reads "Cheer the ship" (an open call for the owner).
```

- One filled button is allowed here: it is the tab's one action.
- A small pointer (6 pt notch) on the card's top edge under the picked dot ties card to dot.

### B5. Settings, regrouped (about 880 pt, from 1,499)

```
 MOCHI
┌──────────────────────────────────────────────┐
│ ✎  Name            [ Mochi            ] Save │  rename: 22 pt field, as the key field
│    Shown to other buddies as "Mochi".        │
│ 💬 Talk            [Quiet|Normal|Chatty]     │  segmented, 168 pt
│    Reacts to what stands out, mostly a word. │  the chosen kind's line only
│ !  Swearing                            ( o ) │  off by default
│    Mochi may swear when things go badly.     │
│ 🔊 Volume          ━━━━━━●━━━━   6           │  120 pt slider
│ ≡  Work stream                         (●)   │
└──────────────────────────────────────────────┘
 AGENTS
│ </> Claude Code   Connected          [Remove]│
│ {}  Codex         Not found on this Mac      │
 THE WORLD
│ 🌍 Mochi lives in the world            (●)   │
└ Shares its name, level, rough time zone, what it's doing, and counts. Nothing about you or your code.
 MEMORY AND PRIVACY
│ 🧠 What Mochi remembers          [See it ›]  │
│    Forget about me…  (clay text button, confirm)
│ 🔑 Jev API key   [ ••••••••      ] ✓ Saved   │
 APP
│ ⏻ Open at login                        (●)   │
│ ▸ Advanced                                   │  closed by default
│     Body: Connected over Bluetooth [Reconnect]
│     Paired board Boop-01DD          [Unpair] │
│     Firmware 1.0.0                  [Update] │  only when there is an offer
│     Simulator                          ( o ) │  internal builds only
│     Uninstall…                               │
```

- The body's row leaves Advanced and goes to the top as a clay strip only when something is wrong (Bluetooth off, no voice, old firmware). When all is well, the header's "Connected" already says it.
- Rename and the world's "Shown as" are one row: the name is the thing others see.
- The swear switch sits under Talk: it is about what Mochi says.

### B6. The Memory pane

```
 ‹  What Mochi knows
┌──────────────────────────────────────────────┐
│ YOU                                          │  the heading inside the card, 10 pt
│ You work late most nights, and you say       │
│ please to claude.                    (📌 ✕ on hover)
│ ──────────────────────────────────────────── │
│ YOUR WORK                                    │
│ "api": you and claude fixed the failing tests on Tuesday.
│ ──────────────────────────────────────────── │
│ YOU AND MOCHI                                │
│ 📌 You stroke Mochi when you sit down in the morning.   pinned: pin in the left margin
└──────────────────────────────────────────────┘
 RECENTLY
│ Yesterday  A long day on "api"; the tests finally passed. …
│ Tuesday    Three turns broke on "api". You said "still broken".
───────────────────────────────────────────────
 Written on this Mac as Mochi dreams.        Quit      the caption moves to the footer
```

- One card for the three sections, hairlines between, empty sections hidden: about 330 pt from 572.
- Text runs the full 300 pt; the pin and cross appear on hover at the trailing edge.
- After forgetting: the row shows "Forgotten. Undo" for 5 s.

---

## C. What stills cannot show

- Hover on the band: whether a dot highlights, the cursor changes, or a name tip shows. The only click cue in the stills is the caption.
- The card opening and closing (opacity transition), and whether the popover's height animates or jumps by the card's 92 pt.
- The popover's height change between world loading (314 pt) and loaded (690 pt).
- Scrolling: Settings at 544 pt visible; whether headings scroll under the title, the scroll bar's inset, and what is above the fold (I estimate Sound, Agents and half of Device).
- Toggle, slider and Talk-row animations; the `matchedGeometryEffect` on the chosen Talk row.
- Hover and pressed states of row buttons, quiet buttons (pin, cross, close) and the Memory link; focus rings; the key field while focused or holding a key.
- The ring filling: whether it animates, and how the colour changes at 100.
- The night gradient across a real day (stills hold one time: about 06:20 UTC), and dots at the band's edges for UTC-12 and UTC+14 buddies (none in the fixture; by code a dot at the edge is 8 pt in, so not clipped).
- Dot overlap with a real, larger world (the fixture has 44 dots; `world-long` is a name test, not a crowd test).
- Text selection in Memory, and the real firmware offer row (SET-7).
- Non-English lengths of the legend and region names.
