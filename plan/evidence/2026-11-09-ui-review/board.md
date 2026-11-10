# Boop board screen (gel renderer): pixel-level UI review

Date: 2026-11-09. Worktree: `.claude/worktrees/v1-polish` (548c6e03). Research only; no repo file changed.
Frames: `~/.boopdev/ui-review-2026-11-09/sim/gel/<scenario>/*.png` (570 frames, all viewed in sheets; key ones zoomed 3-8x).
Crops: `board/crops/`. Measuring scripts: `board/tools/` (`m.py`, `safe.py`).
Code paths: `G/` = `characters/boop/firmware/src/render/gel/`, `F/` = `firmware/src/`.

## 0. Read this first: the brief's scale was wrong

The brief says 320x240 and 0.13 mm per pixel. That is the CYD canvas. The gel draws natively:

- Frame: **502 x 410 px** (every one of the 570 PNGs). `F/board/amoled206/config.h:63-65`.
- Panel: 2.06 in, 410x502 → **0.0807 mm per px** (315 ppi). Visible area 40.5 x 33.1 mm.
- Corner radius: **110 px = 8.9 mm** (`kNativeCorner`, `F/board/amoled206/config.h:69`, "measured from a photo").
- So the thresholds at 70 cm are: comfortable x-height 1.2 mm = **15 px**; legible 0.8 mm = **10 px**.
- A 7 mm finger target is **87 px**.

All numbers below use these values.

---

## A. Findings

Severity: broken / rough / nit. Effort: S (<1 h), M (a day), L (more). Conf = confidence.

### Type and legibility

**BRD-1. Narration (the caption) is unreadable at any distance beyond the hand.** broken · S · conf high
- Frame: `states/poked.png`, `v1/ring-closed.png` ("Today's done!"), all of `reasons/`. Crop: `crops/brd03-caption.png`, `crops/brd40-from-the-chair-key-states.png`.
- Measured: kSmall (Geist Mono Medium 13 px). Ink rows 391-401. x-height 7 px = 0.56 mm, cap 9 px = 0.73 mm. Colour (140,134,123), contrast 5.7:1. Stems are 1 px with 4-bit coverage, so most pixels are 40-60% grey.
- Why: this line carries the "why" (and today the ring's "Today's done!"). It is under the 0.8 mm floor.
- Cause: `G/lane.cpp:205-209` (`caption` uses `kSmall`, `kInkGrey`); `captionTop` at `lane.cpp:178`.
- Fix: draw it in kLarge (22 px; x 12 px = 0.97 mm) in (173,163,150). 18 glyphs x 13 = 234 px fits the 356 px that rows 372-402 leave between the corners. Put its cell top at y=370 (ink 377-395). When a bubble is over it, the bubble keeps `bottom = 366`.

**BRD-2. The ring bar's label ("49 today") is unreadable.** broken · S · conf high
- Frame: `v1/ring-filling.png`, all `growbar/`. Crop: `crops/brd05-ring-label.png`.
- Measured: kSmall, digits 9 px = 0.73 mm, x-height 7 px. x 372-447, y 20-34. Colour (173,163,150).
- Cause: `G/layers.cpp:839-841` (`r.text(today, …, kLabel)` defaults to kSmall).
- Fix: show the number only, in kLarge, inside the bar's right end or straight after it: "49" in (246,244,238), cap 16 px. Drop the word "today" from the bar (the bar is "today"). Bar width 232 → 200 so the number keeps its 4 px corner gap.

**BRD-3. Drawer sub-line and status chips are unreadable.** broken · M · conf high
- Frame: `drawer/open.png`. Crops: `crops/brd08-drawer-rows.png`, `brd40`.
- Measured: sub-line "claude · landing" kSmall x-height 0.56 mm, grey on (20,25,32) = 4.8:1. Chips "WORKING/IDLE/NEEDS YOU" kSmall caps 9 px = 0.73 mm in a 24 px tall chip.
- Cause: `G/drawer.cpp:47-54` (chip in kSmall), `drawer.cpp:63` (sub-line in kSmall).
- Fix: see BRD-20 (taller rows). Sub-line in kLarge grey; replace the word chips by the strip's own marks (spinner / z / amber dot, 18 px) at the row's right end. The colour bar and the title ink already say the state.

**BRD-4. "Continue on your Mac" and all lower-case kLarge text are marginal.** rough · S · conf medium
- Frame: `states/needs_you.png`. Crop: `crops/brd01-needs-you-card-body.png`.
- Measured: kLarge x-height 12 px = 0.97 mm (cap 16 px = 1.29 mm). Same font: drawer titles, two-line low sign, small low sign, the work stream's words.
- Cause: `G/props.cpp:250`.
- Fix: the card's second line goes to kSign (x 15 px = 1.21 mm). See D4 for the layout; "Continue on your Mac" is 20 glyphs x 17 = 340 px, wider than the 320 px card, so use the kind line there instead (≤ 16 glyphs).

**BRD-5. Four fonts and up to three sizes on one screen; one weight differs.** rough · M · conf high
- kSmall is Medium 13; kLarge, kSign, kBubble are SemiBold 22/28/34. `internal/tools/fontgen/fontgen.py:27-31`.
- Worst frame: `drawer/open.png` (28 digits, 22 titles, 13 sub-lines, 13 chips) and `reasons/say-then-poke.png` (34/28 bubble + 13 caption).
- Fix: retire kSmall from everything a person must read (BRD-1, 2, 3). Keep it only for art (the monitor's "TEST", "context", the stream's clock). Result: three reading sizes, 22 / 28 / 34, one weight.

**BRD-6. The bubble shrinks from 34 px to 28 px whenever a caption is under it.** nit · S · conf high
- Frame: `reasons/say-alone.png` vs `reasons/say-then-poke.png` ("Go" changes size).
- Cause: `G/lane.cpp:190-193`: captioned height 48 - 4 < kFontBubble.h 46.
- Fix: with BRD-1's taller caption the bubble is always above it: use kSign for every bubble (x 1.21 mm, passes) and delete the 34 px font from the board (44 KB of flash). One voice size.

**BRD-7. Truncation is two dots ("Make the device.."), in the text's own ink.** rough · S · conf high
- Frame: `lane/needs-you-long-name.png`. Crop: `crops/brd04-long-name.png`.
- Why: ".." reads as a typo; in a mono font it costs 34 px.
- Cause: `G/lane.cpp:86-87`; `F/render/font.h` ("the fonts have no …").
- Fix: add a one-cell "…" glyph (index 96) in fontgen and draw one cell; or fade the last two glyphs to 40% and 15% alpha (no glyph needed, +2 letters of name).

**BRD-8. Mixed case with no rule.** rough · S · conf medium
- Seen: NEEDS YOU / LISTENING / NEW TASK / COMPACTED / FAIL / PASS / BUILT (caps); "shipped!" / "building" / "running tests" / "git push" (lower); "Level 12!" / "Today's done!" (sentence); "boop back!" / "bye bye code" (lower).
- `acts/tests-proud.png` "✓ PASS" vs `acts/push-proud.png` "✓ shipped!": the same low sign, two styles.
- Fix (look only): CAPS for the board's own labels in cards (NEEDS YOU, LISTENING, NEW TASK). Lower case for everything Boop holds (sign, low sign): "pass", "fail", "built", "shipped!", "level 12!".

**BRD-9. The monitor's "TEST", the stream's "context" label and clock are 0.56-0.73 mm.** nit · S · conf high
- Crop: `crops/brd25-activity-monitors-3x.png`. Cause: `G/props.cpp:171`, `G/stream.cpp:255,317`.
- Fix: treat as art; replace "TEST" by a tick/cross row. Do not rely on it.

### The lane, the strip

**BRD-10. The strip's chip sits 4 px from the corner arc; the glass edge may clip its ring.** rough · S · conf medium
- Frames: every frame with a chip (39 lit px within 6 px of the arc; `safe.py`). Crop: `crops/brd02-strip-chips.png`.
- Measured: chip x 55-93, y 361-396; arc at x=51 on row 396. `kCornerGap = 4` (`G/lane.cpp:39`).
- Why: the radius was measured from a photo; ±4 px is inside that error.
- Fix: `kCornerGap = 10` for the lane (`lane.cpp:39`), low sign (`low_sign.cpp:16`), drawer (`drawer.cpp:22`), bar (`layers.cpp:811`). Left margin becomes 61.

**BRD-11. The strip is a rebus: "✳2 ●●●● z3 3/7".** rough · M · conf medium
- Frames: `lane/working-counts.png`, `lane/working-todo.png`, `lane/helpers-seven.png`. Crops: `crops/brd02-strip-chips.png`, `crops/brd19-helpers.png`.
- Measured: digits 20 px = 1.6 mm (pass). Spinner 16 px with 2.5 px spokes at 30-100% alpha; the "z z" 12 px and 7 px; minis 16x15 px with 3 px eyes; "+3" grey. From the chair (`brd40`) only the digits survive; nothing says what they count.
- Cause: `G/lane.cpp:216-232` (marks), `lane.cpp:272-314` (counts).
- Fix: D3. Words when there is room ("2 working · 1 idle" is 18 glyphs = 306 px of the 380 px lane), marks only when the name takes the room.

**BRD-12. Idle chip ring is near invisible.** nit · S · conf medium
- kIdleRing (51,58,66) on black ≈ 1.6:1; working ring (89,97,107) = 3.4:1, 2 px. `G/lane.h:37-38`.
- Fix: drop the rings (BRD-11) or raise idle ring to (89,97,107) and tell idle by ink only.

**BRD-13. The lane shows the strip OR the caption/bubble: a poke hides the counts for 2.5 s.** rough · M · conf medium
- Frames: `states/poked.png` (working, strip gone, rule gone), `hand/*`, `reasons/poke.png`.
- Why: the lane jumps between two layouts on every touch; the rule and chevron vanish, so the drawer handle goes too.
- Cause: `G/lane.cpp:462-468` (`if (line || note) … else strip`).
- Fix: keep the rule + chevron in every lane state. Caption replaces only the strip's row (D1).

**BRD-14. A low sign rising draws over the strip while the strip is still there.** rough · S · conf high
- Frame: `transitions/act-on-1.png`. Crop: `crops/brd26-low-sign-over-strip.png`. The chip "✳1" and the rule show left of and behind "··· building"; the sign's hands sit on the rule.
- Cause: `G/lane.cpp:538-545`: lane painted, then `paintLowSign` over it; only `laneAtRest` skips the strip.
- Fix: while `low.shows()` fade the strip by the sign's rise (opacity = drop/most), or do not draw the strip at all.

**BRD-15. The low sign's hands cover its top corners and rim; the sign Boop holds has hands on its sides.** nit · S · conf medium
- Crops: `crops/brd06-low-sign.png`, `crops/brd07-sign-hands.png`. Low sign hands r=10 at the top corners (`G/low_sign.cpp:124-129`); sign hands r=12 at mid-height (`G/layers.cpp:916-921`).
- Fix: one grip: hands at the sides, mid-height, r=10, for both. The low sign then also clears the rule's row.

**BRD-16. Two-line low sign runs into the finish glow and to 9 px from the bottom edge.** rough · S · conf high
- Frame: `done/sign-long.png`, `sign/remember-long.png`. Crops: `crops/brd24-finish-sign-long.png`, `crops/brd23-low-sign-two-lines.png`.
- Measured: card y 336-401; glow visible from y=389 at centre. Second line is kLarge (0.97 mm).
- Cause: `G/low_sign.cpp:62-63` (`tallTwo` = 65), `topOf` at `:25`.
- Fix: two-line card rises: top = 410 - 26 - 65 = 319 when a glow is on; or cap the finish name at one line of kLarge (30 glyphs at 13 px = 390 px is too wide: cut to 26 with the fade of BRD-7).

**BRD-17. The amber dot sits 3 px above the name's optical middle.** nit · S · conf medium
- Frame: `lane/needs-you-short-name.png`. Dot centre y=379; lower-case x-height spans 375-389 (middle 382).
- Cause: `G/lane.cpp:337,367` (dot on `cy`, text cell centred on `cy`).
- Fix: dot at `cy + 3`.

**BRD-18. "+2" after a needs-you name is the same size as the name and grey; it reads as part of the name.** nit · S · conf medium
- Crop: `crops/brd04-long-name.png`. Cause: `G/lane.cpp:385`.
- Fix: put it in a small amber-outlined pill at the lane's right end ("+2"), kLarge.

**BRD-19. An ask's two answers are one bubble with four spaces between them.** rough · M · conf medium (no simulator frame exists for an ask; from code)
- Cause: `F/app/behaviour.cpp:441-444` builds `"%*s    %-*s"`; `G/lane.cpp:186-200` draws it as one outlined box in the voice's amber. Tap split at x=251 (`F/app/device.cpp:679-682`).
- Why: nothing shows two targets, and it looks like speech.
- Fix: two pills, each 180x52 px (14.5 x 4.2 mm), x 61-241 and 261-441, y 344-396, 2 px rim (120,164,200), text kSign in (184,233,245). The lane's whole half stays the hit area (251 x 82 px = 20 x 6.6 mm). Also add an `ask` scenario to the simulator.

### The drawer

**BRD-20. Drawer rows are 3.9 mm tall.** broken · M · conf high
- Frame: `drawer/open.png`. Crop: `crops/brd08-drawer-rows.png`.
- Measured: rows y 122-169 (48 px = 3.87 mm), pitch 53 px = 4.28 mm, x 35-466. 5.4 rows show.
- Why: under the 7 mm (87 px) finger rule; a miss opens the wrong session on the Mac.
- Cause: `G/drawer.h:31-32` (`rowH = u(48)`, pitch +5).
- Fix: `rowH = u(66)`, pitch 72 (5.8 mm; with the gap counted to the nearer row, as `rowAt` could). 4 rows show: lid 66-122, rows at 122, 194, 266, 338. Title kSign at y+6, sub-line kLarge at y+34.

**BRD-21. The lid's chips (x=18) and the rows (x=35) do not share a left edge.** rough · S · conf high
- Crop: `crops/brd30-drawer-lid-misaligned.png`. Cause: `G/drawer.cpp:141` (lid margin from its own rows) vs `drawer.cpp:72-75` (row margin from the last row).
- Fix: `lid = l.margin()`.

**BRD-22. No scroll affordance; the last row is cut by the panel's corners.** rough · S · conf medium
- Frames: `drawer/more.png`, `drawer/scrolled.png`. Crop: `crops/brd09-drawer-bottom.png`. Row 6 shows 23 px, clipped by the arc on both sides (1418 px out in `drawer/picked.png`).
- Fix: a 24 px fade to the sheet colour at the bottom (rows 386-410) and a 3x40 px scroll thumb at x=478, (89,97,107).

**BRD-23. Rows barely differ from the sheet.** nit · S · conf low (AMOLED will tell)
- Row (20,25,32) on sheet (13,16,21): 1.08:1. `G/drawer.cpp:17`.
- Fix: sheet (0,0,0) (free on AMOLED, and it matches the lane); rows (22,28,36).

**BRD-24. The drawer handle is a 20x9 px chevron in the dimmest ink.** rough · S · conf medium
- Measured: chevron y 342-353, ink (74,68,62) = 2.2:1; rule 2 px same ink. Pull zone is y ≥ 350 (`F/app/device.h:178`, 60 px = 4.8 mm, full width): fine.
- Cause: `G/lane.cpp:320-326`.
- Fix: a 44x5 px pill grabber at y=344 in (112,104,96), no chevron; the rule in (58,54,50).

### Cards, signs, the top band

**BRD-25. The needs-you card covers the top of Boop's head.** rough · M · conf high
- Frames: `states/needs_you.png`, `growth/chonk-needs-you.png`. Crops: `crops/brd01-needs-you-card-body.png`, `crops/brd29-chonk-needs-you.png`.
- Measured: card x 90-410, y 30-117. Dome top is y=100 at rest: 17 px of crown is behind the card, and the card's bottom edge cuts the dome flat. Hatchling: dome top 196, a 78 px gap instead.
- Cause: `G/props.cpp:13` (`kAlertCard{180,75,640,215,32}`, fixed), no body pose for it.
- Fix: D4. Card y 16-92 (76 px), and the body ducks 12 px (as the drawer's `DrawerPose` squashes it), leaving 20 px between card and crown.

**BRD-26. Five box styles for five kinds of message.** rough · L · conf high
- Sign: filled (27,55,78), 2 px rim (120,164,200), r=12, hands at sides. Low sign: fill (22,20,18), rim in the text ink, r=16, hands on top. Needs-you card: amber fill (239,189,103), 1-3 px pale rim, r=26. Start card: sign's colours, r≈25, no hands. Bubble: no fill, 2 px dim rim, r=14, tail. Wish: cream cloud.
- Fix: two families. "Boop holds it" (sign, low sign, ask pills): one fill (22,28,36), one rim width 2, r=14, side hands. "The board says it" (needs you, start card, LISTENING): no hands, r=20; needs you alone is filled amber. Bubble stays the outline with a tail.

**BRD-27. Amber has three jobs.** rough · M · conf medium
- Needs you (dot, name, card, drawer row); the voice's words in the bubble (`G/lane.cpp:199`, kInkAmber); gold celebration (ring full (242,196,86), trophy, "TA-DA!", flood, hard hat, barrier).
- Why: `lane/bubble-longest-take.png` "Technical difficulties" in amber reads as an alert from the chair.
- Fix: bubble text in warm white (246,244,238). Amber (255,176,0) = needs you only. Gold stays (242,196,86), always with a shape (bar, trophy), never as text.

**BRD-28. Two ambers for needs you.** nit · S · conf high
- Card fill (239,189,103) (`G/props.cpp:148`) vs strip/drawer (255,176,0) (`F/render/palette.h:27`).
- Fix: card fill (255,176,0) with ink (28,20,0); or keep the pale card and state it as the "large fill" tint (lower AMOLED load). Pick one and name both in palette.h.

**BRD-29. Warm greys and cool greys are mixed.** nit · S · conf medium
- Lane: (140,132,121), (74,68,62) warm. Chips and drawer: (89,97,107), (154,163,173), (238,242,245) cool. Sheet (13,16,21) blue-black next to the lane's pure black.
- Fix: one grey ramp, warm: 246/244/238, 173/163/150, 112/104/96, 58/54/50.

**BRD-30. The top band stacks: ring bar, label, LISTENING, flying heart.** rough · M · conf medium
- Frame: `growbar-listening/heart-1100.png`. Crop: `crops/brd27-top-band-stack.png`. Bar y 18-35; LISTENING y 42-76; hearts cross both.
- Fix: one thing in the top band at a time: while listening, the bar waits (its XP lands after), or LISTENING moves into the lane (D1: it is a state of the lane, as the strip is).

**BRD-31. Ring-full sparkles are clipped by the top edge and are dim dots.** nit · S · conf high
- Frame: `v1/ring-sparkle.png`, `v1/ring-closed.png` (lit px at y=0-9). Crop: `crops/brd28-ring-sparkle-top-edge.png`.
- Cause: `G/layers.cpp:846-850`: upper stars rise to `top - 26`, top = 18.
- Fix: upper stars rise at most 12 px; or move the bar to kTop = 30.

**BRD-32. Ring closed is the quietest big moment on the board.** rough · M · conf high (decided: becomes one moment with level-up)
- Frame: `v1/ring-closed.png`: a gold 18 px bar, "100 today" and "Today's done!" both in 0.56 mm type. From the chair: a yellow line. `v1/level-up.png`: a white low sign and a calm face, no colour, no rim.
- Fix: D5.

**BRD-33. The sign cuts the open mouth.** nit · S · conf medium
- Frame: `v1/boop.png`, `v1/boop-reason.png`. Crop: `crops/brd07-sign-hands.png`: the mouth's light interior shows as a sliver over the sign's top rim.
- Cause: `G/layers.cpp:906` (`underMouth` uses eye spacing / 9, too little for a wide laugh).
- Fix: `underMouth = mouth.y + eyeGap / 6`, or close the mouth to a smile while a sign is up.

**BRD-34. "<3" sign is 70 px wide with two 24 px hands: the hands are bigger than the message.** nit · S · conf medium
- Frame: `wish/met.png` (sign x 158-363 incl. hands? ink 70 px). Fix: minimum sign width 120 px, or draw the heart shape (the wish already has one) instead of "<3".

**BRD-35. LISTENING is fine in size (cap 1.29 mm) but its mic icon and label are two blues.** nit · S · conf low
- Crop: `crops/brd12-listening.png`. Ring (100,184,207), label (184,233,245). x 169-336, y 42-76: clear of corners.
- Fix: one ink.

**BRD-36. Start cards ("NEW TASK", "COMPACTED") use the sign's colours without hands, above the head.** nit · S · conf medium
- Frame: `states/starting.png`: card x 140-359, y 34-79; cap 16 px. Crop: `crops/brd13-start-card.png`. See BRD-26.

**BRD-37. No app: the only signal is a 24x18 px grey plug in the bottom right; Boop looks happy.** broken · S · conf high
- Frames: `states/no_app.png`, `alone/*`. Crop: `crops/brd11-no-app-plug.png`, `brd40`.
- Measured: plug x 423-447, y 370-388 (1.9 x 1.5 mm), (140,134,123). From the chair it is not seen.
- Cause: `G/lane.cpp:246-251, 416`.
- Fix: plug 2x (48x36) at the lane's centre with "no Mac" in kSign grey beside it (6 glyphs = 102 px): total 170 px, x 166-336.

### Shapes, edges, gradients

**BRD-38. The finish glow bands and shifts hue in its tail.** rough · S · conf medium (panel will tell)
- Frames: `lane/finish-*.png`. Crop: `crops/brd16-rim-glow-corner.png`. Profile at y=205: (123,154,115) (99,121,90) (74,89,66) (49,65,49) (33,44,33) (24,24,16) (8,12,8) (0,4,0): RGB565 steps; (24,24,16) is yellow, (0,4,0) is green.
- Cause: `G/done.cpp:58-94` (alpha (1-d/26)², blended per pixel, no dither); `G/done.h:21`.
- Fix: 2x2 ordered dither on the alpha (add {0,8,12,4}/16 of one step before `mix565`), and cut alpha < 12 to 0.

**BRD-39. The trophy disappears on the gold flood.** rough · S · conf high
- Frame: `finish/gold.png`, `done/cheer-*.png`. Crop: `crops/brd17-gold-flood.png`: gold cup on gold rays, outline only.
- Cause: `G/finish.cpp:223-225` (trophy inks) over `finish.cpp:582-591` (flood).
- Fix: during Gold Rush give the trophy a 2 px (90,51,0) outline (the ink "TA-DA!" already uses for its shadow, `finish.cpp:784`), or a white cup.

**BRD-40. Gold flood and mega light 80% of the panel.** rough · S · conf medium
- Measured: `finish/gold.png` mean (169,142,65), 49% of full white; idle is 13%; `finish/mega.png` 42%.
- Why: AMOLED current and brightness jump ~3.7x; at night it is a flash. Burn-in is not a risk at these durations.
- Fix: cap the flood's two golds at 70% value ((178,123,22) / (190,150,45)) and let the `night` tag halve them.

**BRD-41. Card corners step visibly.** nit · S · conf medium
- Crop: `crops/brd15-card-corner.png` (8x): the rim's arc has 2-3 px stairs; the rim is 3 px on straight runs and 1 px on the arc.
- Cause: `G/props.cpp` `fillCard` (rim as a second rounded rect with a different radius).
- Fix: rim = `ring()` of constant 2 px, as the sign's (`layers.cpp:913`).

**BRD-42. The spotlight's beam is a flat grey wedge with hard edges.** nit · M · conf medium
- Frame: `finish/spotlight.png`. Crop: `crops/brd18-spotlight.png`. One colour (≈(58,52,40)), no falloff; the podium's "1" is kLarge on gold with a 1 px outline.
- Cause: `G/finish.cpp:795-807`.
- Fix: three nested wedges at 40/25/12% alpha; podium numeral in kSign, ink (90,51,0).

**BRD-43. Body outline: fine.** (no finding) `crops/brd14-body-edge.png`: 1 px anti-aliased light rim, no stair runs longer than 2 px. Body shading shows 8-level 565 steps only at 6x.

**BRD-44. Stream words are cut by the body and the corner mid-word.** nit · S · conf medium
- Frames: `stream/falling.png` ("it log", "it +18"), `stream/buried.png` ("pyt" at x<60), `growth/*-work-desk.png` ("gr"). Crop: `crops/brd20-stream-words.png`.
- Cause: `F/render/stream.cpp:117` (`kWordEdgePx` on a 502 width, no corner inset); words fall behind the body by design.
- Fix: lanes' x so a 10-glyph word clears the dome's widest row (x < 100 or > 400 is only 100 px = 7 glyphs): cap falling words at 7 glyphs, and take `Surface::inset` for the word's rows.

### Hierarchy, activities, emotions

**BRD-45. The 8 activities differ by 20-950 px (0.01-0.46% of the screen).** broken · L · conf high (decided: 8 → 4 with body-size props)
- Frames: `states/{working,testing,delegating,terminal,searching,analyzing,tool_use,waiting,planning}.png`. Crops: `crops/brd25-activity-monitors-3x.png`, `crops/brd42-from-the-chair-activities.png`.
- Measured in the monitor's box (96x52 px = 7.7 x 4.2 mm): delegating vs working 20 px; terminal vs working 43 px; waiting 136; planning 293; tool_use 362; searching 386; testing 403; analyzing 808. From the chair: all nine are "Boop at a desk".
- Cause: `G/props.cpp:160-186`.
- Sketch for 4: a prop ≥ 120 px (10 mm) beside or on the body, one shape and one colour each. Thinking: thought cloud (the wish's cloud, 60 px). Writing: the keyboard + a page that fills. Running (tests, terminal, tools): a hard hat or a spinning gear 80 px. Looking (search, read): a magnifier 90 px held up to one eye.

**BRD-46. 42 emotions: about 10 are distinct at real size.** rough · L · conf medium (decided: 42 → 18)
- Sheet: `crops/brd41-from-the-chair-42-emotions.png` (0.35x). Groups a person cannot tell apart:
  1. dot eyes + tiny mouth: calm, curious, hopeful, engaged, surprised, uneasy, confused, baffled, lonely
  2. flat or slanted eyes + small frown: annoyed, bored, irritated, grumpy, skeptical, speechless, overwhelmed
  3. closed arcs down + frown: sad, disappointed, tired, exhausted
  4. tears: crying, frightened, wounded, whiny
  5. closed smile + "w" mouth: affectionate, proud, pleased, lazy, embarrassed, determined
  6. open laugh: excited, amused, relieved, happy, comfy, angry (!)
  7. squeezed > <: disgusted, shy
  8. white round eyes: scared, uncomfortable, stunned
  9. alone: mischievous ("3" mouth)
- **`moods/angry.png` shows a laughing > < face with an open smile.** It reads as delight. Check the frame's time or the design (conf medium).
- For the 18: keep one per group plus the ones with a second cue (tears, white eyes, brows, blush colour). Give each kept emotion a silhouette change (body squash, lean) or a colour cue, since eyes are 10-14 px.

**BRD-47. Hatchling leaves 85% of the screen black and the card/strip float far from it.** nit · M · conf low
- Frames: `growth/hatchling-*.png` (body ≈ 110 px wide). Fix: hatchling drawn at 1.3x, or the lane's elements stay and the top band drops to the body (card at crown - 100).

**BRD-48. No `ask`, no `needs you + ring`, no `finish + bubble + caption` scenario in the simulator set.** nit · S · conf high
- These are the lane's worst cases and cannot be reviewed from frames. Add them to the `lane` scenario.

### What reads in one second (from `crops/brd40-from-the-chair-key-states.png`)

Sheet factor: **0.5x with a 0.5 px blur**. Reason: on a 220 ppi "2x" laptop the panel's real size is 0.70x of the frame at 1 device px per image px; the board at 70 cm against the laptop at 50 cm is another 0.71x.

| State | Survives | Lost |
| --- | --- | --- |
| Working, 3 agents | Boop at a desk; digits "2", "3" | what the digits count; minis; the activity |
| Needs you | amber card, "NEEDS YOU"; amber name | "Continue on your Mac" (marginal); "+1" |
| Finish success / failure | green or red rim; the name on the low sign | tick vs cross (18 px); two-line names |
| Ring closed | a yellow bar | "100 today", "Today's done!" |
| Level-up | "Level 12!" | that it is a celebration |
| A wish | a white cloud by the head | the icon (20 px hand / laptop / dots) |
| A notice with a sign | the sign's words | - |
| Listening | "LISTENING" | - |
| No app | nothing: a happy Boop | the plug |
| Drawer open | titles; the amber row | sub-lines, chips |
| Poked | nothing in the lane | "you poked Boop" |

---

## B. Type table

Fonts on the board: Geist Mono only. `firmware/assets/fonts.h` (kSmall, kLarge, kSign) and `characters/boop/firmware/include/fonts_gel.h` (kFontBubble). Heights measured from the glyph data ('H', 'x', coverage ≥ 50%).

| Font | Cell | Cap px / mm | x px / mm | Lower case at 70 cm | Caps at 70 cm |
| --- | --- | --- | --- | --- | --- |
| kSmall, Medium 13 | 8x18 | 9 / 0.73 | 7 / 0.56 | **no** | **no** |
| kLarge, SemiBold 22 | 13x30 | 16 / 1.29 | 12 / 0.97 | marginal | yes |
| kSign, SemiBold 28 | 17x38 | 20 / 1.61 | 15 / 1.21 | yes | yes |
| kFontBubble, SemiBold 34 | 20x46 | 25 / 2.02 | 19 / 1.53 | yes | yes |

| Text style | Font | Judged height | Legible at 70 cm? | Where set |
| --- | --- | --- | --- | --- |
| Card "NEEDS YOU" | kSign caps | 20 px / 1.61 mm | yes | `G/props.cpp:249` |
| Card "Continue on your Mac" | kLarge | x 12 / 0.97 | marginal | `G/props.cpp:250` |
| Name strip (needs you, finish) | kSign | x 15 / 1.21 | yes | `G/lane.cpp:336,384,411` |
| Chip digits "2", "1" | kSign digits | 20 / 1.61 | yes | `G/lane.cpp:273-285` |
| Chip marks (spinner, z) | drawn, 16 px / 12+7 px | 1.3 / 1.0+0.6 mm | marginal / no | `G/lane.cpp:216-232` |
| Helper minis | drawn 16x15, eyes 3 px | 1.3 mm | marginal (as dots) | `G/lane.cpp:291-300` |
| "+3", "+2" | kSign, grey | 20 / 1.61 | yes | `G/lane.cpp:303,385` |
| To-do "3/7" | kSign | 20 / 1.61 | yes | `G/lane.cpp:310` |
| Sign Boop holds | kSign | x 15 / 1.21 | yes | `G/layers.cpp:900` |
| Low sign, one line ≤ ~17 glyphs | kSign | x 15 / 1.21 | yes | `G/low_sign.cpp:66-68` |
| Low sign, longer / two lines | kLarge | x 12 / 0.97 | marginal | `G/low_sign.cpp:69-75` |
| Work act low sign ("··· git push", "✓ shipped!") | kSign | x 15 / 1.21 | yes | via `actSign`, `G/low_sign.cpp` |
| Bubble (voice) | kFontBubble; kSign if long or captioned; then kLarge, kSmall | x 19 / 15 / 12 / 7 | yes / yes / marginal / no | `G/lane.cpp:191-193` |
| Narration (caption) | kSmall, grey | x 7 / 0.56 | **no** | `G/lane.cpp:208` |
| Ring label "49 today" | kSmall | x 7, digits 9 / 0.73 | **no** | `G/layers.cpp:841` |
| Drawer title | kLarge | x 12 / 0.97 | marginal | `G/drawer.cpp:57` |
| Drawer sub-line | kSmall, grey | x 7 / 0.56 | **no** | `G/drawer.cpp:63` |
| Drawer chips WORKING / IDLE / NEEDS YOU | kSmall caps | 9 / 0.73 | **no** | `G/drawer.cpp:54` |
| LISTENING | kLarge caps | 16 / 1.29 | yes | `G/props.cpp:226` |
| Start cards NEW TASK / COMPACTED | kLarge caps | 16 / 1.29 | yes | `G/props.cpp:231` |
| Stream words | kLarge, dim lane inks | x 12 / 0.97 | marginal (dim by design) | `G/stream.cpp:204` |
| Word forward, "mm!", "TA-DA!" | kSign | 15-20 | yes | `G/stream.cpp:328-366`, `G/finish.cpp:785` |
| Monitor "TEST", "context", clock, "burp" | kSmall | 0.56-0.73 | no (art) | `G/props.cpp:171`, `G/stream.cpp:255,317,487` |

Contrast on black: amber name 11.5:1; warm white 18:1; ring label 8.5:1; caption grey 5.7:1; working ring 3.4:1; rule / bubble box (74,68,62) 2.2:1; idle ring 1.6:1. On the card: "NEEDS YOU" 8.7:1, second line 7.5:1. Sign words on sign 9.4:1; sign rim against the body 1.2:1 (the sign's edge is lost on the body; its fill at 4:1 carries it).

---

## C. The screen's zones as shipped (502 x 410)

```
y    0 ─ top edge. Corner arcs: at y=18 the glass starts at x=49; at y=36, x=30
    18-35   ring bar: track x 135-366 (232 wide), label to x=447           layers.cpp:811
    30-117  needs-you card  x 90-410                                        props.cpp:13
    34-79   start card      x 140-359
    42-76   LISTENING: mic ring + label, x 169-336                          props.cpp:218-226
    72-126  wish cloud, x ≥ 380 (right of the crown)                        layers.cpp:763
   100      dome top at rest (buddy). Hatchling 196. Chonk ≈ 96
   277-321  the sign Boop holds (48 tall; never below y=324)                layers.cpp:907
   316-322  desk line / body foot
   328 ──── lane top (kLaneTop 192/240). Shapes above stop here             screens.h:18
   326-346  low sign's hands
   334-394  bubble (tail up to 328); 334-382 when a caption is under it     lane.cpp:53-58
   336-382  low sign, one line (336-401 with two)                           low_sign.cpp:25,62
   342-353  chevron;  348-349 the rule, x 55-446                            lane.cpp:320
   350-410  drawer pull zone (touch)                                        device.h:178
   361-396  strip chips (36 tall, first at x=55); text cell 360-398         lane.cpp:260,337
   386-404  caption cell (ink 391-401)                                      lane.cpp:178
   384-410  finish glow, 26 px all round every edge and arc                 done.h:21
   410 ─ bottom edge. At y=396 the glass starts at x=51; at y=404, x=73
```

Safe area in code: `Surface::inset(y0, y1, radius)` + a 4 px gap. The lane, low sign, bar label, sign and drawer use it. `safe.py` over all 570 frames, r=110: nothing that must be read is outside the arcs. Within 6 px of the arc: the first strip chip (every strip frame), the bubble's box at 52-450, the drawer's last row.

Outside the arcs, by design or harmless: the finish glow (follows the arc), gold flood, acts' scenery (barrier, ground line: `reasons/act-reason.png` 1155 px), confetti.

Collisions found:
1. Card over the dome's crown, 17 px (BRD-25).
2. Low sign rising over a live strip (BRD-14).
3. Two-line low sign inside the glow, rows 389-401 (BRD-16).
4. Caption or bubble removes the strip, rule and chevron (BRD-13).
5. Ring bar + LISTENING + heart in rows 18-76 (BRD-30).
6. Sign over the open mouth (BRD-33).
7. Stream words cut by the dome and the left arc (BRD-44).
8. Ring sparkles cut at y=0 (BRD-31).

No collision: sign (≤324) vs rule (348); wish cloud vs bar label; caption vs corner (18 glyphs of kSmall need 144 px of the 356 px free on its rows).

---

## D. Layout proposals (502 x 410; one character ≈ 8 px wide, one text row ≈ 20 px)

### D6 first: one safe-area rule

- Content box: **x 24-478, y 16-394** for anything a person reads; plus `inset(rows) + 10` near the arcs (today +4).
- Three bands with fixed rows: **top band 16-92**, **face 92-328**, **lane 328-394**. One message per band at a time.
- Reading sizes: 28 px (kSign) by default; 22 px (kLarge) only for a second line; 13 px never.
- Minimum touch target 87 x 60 px (7 x 4.8 mm); a row or a pill may look smaller but its hit box is not.

### D1. The lane, simplified: one rule, one row

```
y328 ┌──────────────────────────────────────────────────────────────┐
     │                        ▁▁▁▁▁▁  grabber 44x5, y=344            │
y348 │  ──────────────────────────────────────────────────────────   │ rule: always there
     │                                                              │
y379 │      [ one row, 38 px cell, kSign, centred on y=379 ]         │ x 61 … 441
     │                                                              │
y394 └──────────────────────────────────────────────────────────────┘ nothing below 394
```
The row shows exactly one of, by priority: needs-you name > ask pills > finish name (low sign) > voice (bubble) > narration > the strip. The low sign, the bubble and the narration all take this same row and the same rise (220 ms from below); only their dress differs:

```
needs you   ● codex · Native gel                         (+1)     amber
finish      ╭ ✓ fix-nav ╮   held by two side hands, rim in the outcome's ink
voice         ⌃
            ( Tsk… Validate )   outline, tail up, warm-white text
narration     you poked Boop    kLarge, (173,163,150), no box
strip         2 working · 1 idle                           3/7
```

### D2. Narration made readable

```
y366 ─ a bubble over it ends here
y370 ┌ cell top, kLarge (22 px)
y377 │  you poked Boop          ← ink rows 377-395, x-height 12 px = 0.97 mm
y395 │                            colour (173,163,150) = 8.5:1
y400 └ cell bottom; free width on these rows: 356 px = 27 glyphs
```
Alone, it sits on the lane's row (y=379 centre). Max 18 glyphs = 234 px.

### D3. The strip in words

```
room ≥ 306 px        2 working · 1 idle                     3/7
with helpers         2 working +4 helpers · 1 idle
tight (name shown)   ● codex · fix-nav              ✳2  z1
```
- Numbers in warm white kSign, words in (173,163,150) kSign. "·" as separator. To-do right-aligned at x=441.
- Marks (spinner, z) only in the tight form, no rings round them: 18 px mark + digit, 14 px apart.
- Helpers as "+4 helpers" (words) or "+4" after the working count; the minis go (16 px faces do not read).

### D4. The needs-you card, with its kind

```
y 16 ╭────────────────────────────────────────────────╮  x 91 … 411 (320 wide), r=20
     │   ?   NEEDS YOU                                │  icon 36 px at x=115; kSign caps, ink (28,20,0)
y 54 │       a yes or no                              │  kSign lower case, same ink at 80%
y 92 ╰────────────────────────────────────────────────╯  76 tall; fill amber
y112        ╭──── Boop, ducked 12 px ────╮               20 px clear under the card
            …
y379   ● codex · Native gel                      (+1)    lane row, amber
```
- Kind line, ≤ 16 glyphs (272 px): "a yes or no", "a question", "a plan to read". Icon by kind, 36 px, drawn (not type): "✓✕" split disk, "?", a three-line page.
- Both lines left-aligned at x=163 (icon column 115-151). Left alignment makes the card scan as icon + two lines, and the kind line never re-centres as it changes.
- "Continue on your Mac" goes (the card's presence says it); if kept, it is the narration row's job once, the first time.
- Hatchling/sprout: card stays in the top band; the body does not chase it.

### D5. The ring closes and the level goes up: one moment

```
y 18      ████████████████████████████  100          bar full, gold; number kLarge, no "today"
          ✦      ✦       ✦       ✦                   sparkles only below the bar (rows 40-60)

              ╭──── Boop, proud, hopped 14 px ────╮
           ●╭───────────────────────╮●              the sign it holds: y 277-325, kSign
            │     today's done!     │               13 glyphs = 221 px + 40 pad; side hands
            ╰───────────────────────╯
y348  ─────────────────────────────────────────────
y379           ●╭  ★ level 12!  ╮●                  low sign, rim + text gold (242,196,86), star mark
      gold rim glow, 26 px, as a finish's           fill (22,20,18); mark is a drawn 18 px star
```
- Order: bar fills to gold (300 ms) → sign rises (220 ms) → low sign rises 400 ms later, with the gold rim glow. Hold 3 s. Then the low sign drops, the sign drops, the bar slides out.
- No ring-closed-without-level case changes: same layout without the low sign and the glow.
- The narration row is not used here (it was carrying "Today's done!" at 0.56 mm).

### D7. The drawer

```
y  8  ( squished Boop  > ᵕ < )                                    as now
y 66  ───────────────── ▁▁▁▁ ─────────────────
y 97   2 working · 1 idle                                         lid, same words as the strip, x=35
y122 ┃ Hero copy                                         ●        row 66 tall (5.3 mm), pitch 72
     ┃ codex · landing                                            title kSign; sub-line kLarge grey
y194 ┃ Fix the lane colours                              ✳        mark 18 px replaces the word chip
     ┃ claude · buddygotchi
y266 ┃ Needs-you lasts                                   ✳
y338 ┃ mellowharness                                     z       ▐ scroll thumb x=478
y386  ░░░░░░░ fade to black ░░░░░░░
```

---

## E. What only a person at the real panel can judge

1. Corner radius: is 110 px right, and does the first strip chip (4 px from the arc) show whole? Check all four corners; the photo measured one.
2. Real legibility at 70 cm of kLarge lower case (0.97 mm): "Continue on your Mac", drawer titles, two-line low signs. My "marginal" is from the rule of thumb.
3. Dim inks on AMOLED: the rule and bubble outline (74,68,62), the idle ring (51,58,66), drawer rows against the sheet (1.08:1). AMOLED crushes or lifts near-black differently from an LCD.
4. Banding and hue shift in the finish glow, the body's shading and the night sky on the CO5300 (RGB565; the PNGs show 8-level steps).
5. Brightness jump of gold flood / mega (49% vs 13% of full white), in a dark room.
6. Amber (255,176,0) vs gold (242,196,86) vs card amber (239,189,103): do they read as three colours or one on this panel?
7. Motion: sign rise (220 ms), low sign rise and fall, the spinner at 8 steps/s, the drawer's pull; the frame rate while the gold flood or mega plays (notes say 23-29 fps).
8. Shimmer of 1 px features in motion: kSmall stems, the monitor's lines, the keyboard's keys, the sparkles.
9. Touch: hitting a 3.9 mm drawer row; finding the pull zone at the bottom edge near the rounded corners; the ask's left/right halves; whether the FT3168 reports touches in the corners at all.
10. Viewing angle and glare on the glass at desk height (the lane is the lowest band and the first to wash out).
11. Whether the 42 → 18 emotions keep apart on the panel at 70 cm: eyes are 10-14 px (0.8-1.1 mm).

## Crop index

`brd01` card/body · `brd02` strip chips · `brd03` caption · `brd04` long name ".." · `brd05` ring label · `brd06` low sign · `brd07` sign + hands · `brd08` drawer rows · `brd09` drawer bottom · `brd10` bubble · `brd11` no-app plug · `brd12` LISTENING · `brd13` start card · `brd14` body edge 6x · `brd15` card corner 8x · `brd16` rim glow · `brd17` gold flood + trophy · `brd18` spotlight · `brd19` helpers · `brd20` stream words · `brd21` act low sign · `brd22` wish cloud · `brd23` two-line low sign · `brd24` long finish sign in the glow · `brd25` activity monitors 3x · `brd26` low sign over strip · `brd27` top band stack · `brd28` ring sparkles at the top edge · `brd29` chonk needs you · `brd30` drawer lid misaligned · `brd40` from the chair: key states · `brd41` from the chair: 42 emotions · `brd42` from the chair: activities.
