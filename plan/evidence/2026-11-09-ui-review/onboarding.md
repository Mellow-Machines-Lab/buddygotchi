# Onboarding UI review: 9 acts, all states, light and dark

Reviewed 2026-11-09 from `~/.boopdev/ui-review-2026-11-09/snaps/onboarding-*.png` (108 files, 1440 x 1120 px = 720 x 560 pt at 2 px per pt).
Code read in the worktree `v1-polish`. No repo file was changed.

- Crops: `onboarding/crops/` (47 files). Source PNG names below omit the prefix `~/.boopdev/ui-review-2026-11-09/snaps/onboarding-` and the suffix `.png`.
- All positions are in points, measured with Pillow from the light snapshots. `x` and `y` start at the window's top left.
- Code paths are relative to `app/Boop/Views/`. `OV` = `Onboarding/OnboardingView.swift`, `OI` = `Onboarding/OnboardingIntro.swift`, `OB` = `Onboarding/OnboardingBoard.swift`, `OF` = `Onboarding/OnboardingFinish.swift`, `OK` = `Onboarding/OnboardingBrainKey.swift`, `OW` = `Onboarding/OnboardingWorld.swift`, `TH` = `Theme.swift`.
- Severity: broken / rough / nit. Effort: S (under an hour), M (a day), L (more). Confidence: high / med / low.

## Summary

The window is one size in every act and state: 720 x 560 pt. The palette, the card, the filled button and the footprints hold together well, and dark mode is a faithful copy of light mode.

The flow does not read as one template. Three things cause that:

1. **Act 5 does not fit the window.** Its content is 18 to 43 pt too tall. The whole frame moves: the footprints rise from y 29 to y 7.5 and the button's bottom margin falls from 30 pt to 8.5 pt (ONB-1).
2. **Nothing sits in the same place from act to act.** The title's top is at 7 different heights (50.5 to 295 pt). The face has 8 sizes (44 to 236 pt) and 9 positions. Acts 3, 6 and 7 leave an empty band of 188 to 278 pt above the button (ONB-2 to ONB-5).
3. **The bottom bar has three layouts.** Primary on the right (acts 2 to 8), primary in the centre with no Back (acts 1 and 9), and no primary at all (act 4, looking), where the same link moves 114.5 pt sideways and 4 pt down (ONB-6 to ONB-9).

Weakest act: **act 6, choose** (`6-agents`): two cards and a link in the top 40% of the window, then 278 pt of nothing. Most crowded: **act 5**. Best: **act 2** and **act 8**.

---

## A. Findings

### The frame

**ONB-1. Act 5 overflows the window; the footprints and the button move** (broken, M, high)
- Act and state: 5, every state. Crops: `onb-5-frame-drift.jpg`, `onb-5-top-no-board.png`, `onb-5-bottom-no-board.png`. Sources: `5-how-to-no-board-light`, `5-how-to-talk-light`, `5-how-to-light`, `5-how-to-all-done-light`.
- Wrong: The act's content is taller than the room it has (469.5 pt). SwiftUI centres the overflow, so everything moves. Footprints top: 27.5 (all-done), 20 (base, heard), 12.5 (talk, done, in-window, long), 7.5 (no-board). Button bottom: 531.5, 539, 546.5, 551.5. Bottom margin: 28.5 down to 8.5 pt. Other acts: 29 and 30.
- Why it matters: The button and the progress marks jump when the person arrives at act 5, and jump again when a lesson is done (the row grows from 56 to 71 or 86 pt). In `no-board` the footprints sit in the title-bar zone.
- Cause: `OV:17-33`. The act sits in a `ZStack` with `maxHeight: .infinity`; nothing stops a taller act. `OB:259-285` puts a title, 4 lessons, a chip row and a 3-line legend in one act. A lesson's height changes with its text (`OV:169-170`).
- Fix: (a) Give the act a fixed box: in `OV:23-32` add `.frame(height: 560 - 30 - 15 - 16, alignment: .top)` and `.clipped()`. Then overflow can not move the frame. (b) Make act 5 fit: move "HOW I FEEL" out of this act (to act 2 or the finale; it saves 82.5 pt), or use `compact: true` rows (saves 32 pt) and reserve 2 detail lines in each row (`.lineLimit(2, reservesSpace: true)`) so a row never changes height. (c) Add a snapshot check: footprints top is 29 to 30 pt and the button bottom is 530 pt in every onboarding picture.

**ONB-2. The title has 7 heights** (rough, M, high)
- Acts: all. Crop: `onb-all-light.jpg` (red lines at y 59, 498, 530).
- Wrong: Title top (ink) in pt: act 2 59.5; act 3 181.5; act 4 247 (intro), 295 (looking, errors), 316.5 (found), 283.5 (joined); act 5 38 to 58; act 6 59; act 7 59; act 8 169; act 9 231.5. Act 1 has no title.
- Why: The eye must find the title again on every act. Inside act 4 the title moves 4 times in one sequence of states.
- Cause: Each act builds its own `VStack` with its own spacing (24, 18, 14, 16, 14, 14, 12, 14, 16) and puts the face above or beside the title as it likes: `OI:18`, `OI:142`, `OI:278`, `OB:37`, `OB:74`, `OB:144`, `OB:259`, `OF:19`, `OF:289`, `OW:12`, `OF:370`.
- Fix: One `ActFrame` view with slots (see section C): a hero slot of fixed height, the title at one y, the body under it, the bar at the bottom. Two variants only: "hero" (title top at y 236) and "list" (title top at y 59).

**ONB-3. The face has 8 sizes and 9 positions** (rough, M, high)
- Acts: all. Crop: `onb-all-light.jpg`.
- Wrong: Tile size and top y: act 1 196 at y 150; act 2 236 x 177 at y 102.5; act 3 108 at y 54; act 4 150 at y 64 (intro), 140 at y 94 (looking), 160 at y 76 (joined); act 5 four tiles of 44; act 6 none (choose), 104 (hello), 84 (tour); act 7 none; act 8 96 at y 54; act 9 150 tilted 4 degrees at y 58.5.
- Why: The buddy is the constant of the flow. It shrinks, grows and disappears with no pattern (196, 236, 108, 150, 140, 160, 44, 104, 84, 0, 96, 150).
- Cause: Literal sizes: `OI:21`, `OI:147`, `OI:279`, `OB:78`, `OB:149`, `OB:214`, `OB:236`, `OB:381`, `OF:163`, `OW:13`, `OF:371`.
- Fix: Three sizes as constants in `OnboardingView`: `hero = 150`, `side = 96`, `legend = 44`. Act 1 may keep 196 as the one entrance. Acts 6 (choose) and 7 get the `side` face at the title, so no act is without the buddy.

**ONB-4. Acts 3, 6 and 7 are top-heavy** (rough, M, high)
- Crop: `onb-empty-bands.jpg`. Sources: `3-name-light`, `6-agents-light`, `7-small-things-mic-allowed-before-light`.
- Wrong: Empty band from the last content to the button's top (y 498): act 3 188 pt; act 6 choose 278 pt; act 6 hello 233 pt; act 7 116.5 pt (3 cards) and 209.5 pt (2 cards); act 4 joined 165 pt; act 4 looking 167 pt. For reference: act 2 72 pt, act 8 88 pt, act 9 89 pt.
- Why: Half of the window is blank, and the primary button is far from what it acts on (in act 3 the field is at y 220 and "That's me" at y 498).
- Cause: Every act ends with `Spacer(minLength: 0)` then the bar (`OI:318`, `OF:32`, `OF:294`), so all slack goes under the content.
- Fix: In the frame, centre the body block in the space between the title and the bar (two spacers, or `.frame(maxHeight: .infinity)` on the body), and cap the slack: with the hero slot from ONB-2, act 3's field lands at about y 290.

**ONB-5. Act 1 is laid out differently from all others** (nit, S, med)
- Source: `1-hello-light`. Crop: `onb-all-light.jpg`.
- Wrong: The group is centred as a block: bubble top y 108, tile y 150 to 346, text y 373 to 407, button y 432 to 464. 96 pt of space is under the button; the next act's button is at y 498 on the right.
- Why: The first click target is 261 pt left of and 66 pt above the next one. Fine as an opening scene, but the button should not move twice in two acts.
- Cause: `OI:18-41` (two spacers, own button).
- Fix: Keep the centred scene. Put the button in the shared bar position (bottom, y 498). Centred is fine if act 9 is too, but pick one rule: see ONB-6.

### The bottom bar

**ONB-6. Three bar layouts** (rough, S, high)
- Sources: `1-hello-light`, `9-finale-light`, `4-body-looking-light`, others.
- Wrong: Acts 2 to 8: Back left, primary right (right edge x 672, y 498 to 530). Acts 1 and 9: primary centred (x 315 to 405 and x 316.5 to 403.5), no Back. Act 4 looking and errors: no primary at all.
- Why: The primary button is the one fixed target of a wizard. It is in three places.
- Cause: `OV:225-245` (ActNav) is skipped by `OI:36-38`, `OF:395-397` and `OB:88-94`.
- Fix: Route all through `ActNav`. For acts 1 and 9 use ActNav with a `centred` flag, or put them on the right like the rest. Act 9 has no Back and no reason not to have one (act 8 is reversible); add `ActBack`.

**ONB-7. Act 4 looking: the escape link jumps** (rough, S, high)
- Crops: `onb-4-bar-intro.png`, `onb-4-bar-looking.png`. Sources: `4-body-intro-light`, `4-body-looking-light`.
- Wrong: "I don't have my Boop yet" is at x 400.5 to 549.5, y 508.5 in intro. After "Look for me" it is at x 515 to 664, y 513: 114.5 pt to the right and 4.5 pt lower. The lock label on the left also drops 4 pt (y 508.5 to 512.5).
- Why: The person clicks the primary, and a different control slides under the pointer's old position. A second fast click lands on nothing now, but the bar visibly jerks.
- Cause: `OB:88-94` builds its own `HStack` with no filled button, so the row is 24 pt high, not 32, and the link takes the primary's place.
- Fix: Use `ActNav` with a disabled or progress primary ("Looking…" with a small spinner, `enabled: false`) and the same `quiet:` link. If no primary is wanted, add `.frame(minHeight: 32)` and keep the link's trailing edge at x 549.5 with a hidden primary of the same width.

**ONB-8. Back and the lock label start at different x** (nit, S, high)
- Crops: `onb-bar-back-x.png`, `onb-4-bar-lock-x.png`.
- Wrong: "Back" text starts at x 56.5 (the quiet button has 8 pt of padding). The lock label starts at x 49.5. It is 12 pt; Back is 13 pt.
- Why: The left edge of the bar moves 7 pt between acts 3, 4 and 5.
- Cause: `OV:254` (quiet button, padded) against `OV:257-258` (plain label, `.font(.system(size: 12))`).
- Fix: `OV:257`: add `.padding(.horizontal, 8).padding(.vertical, 4)` and use size 13. Better: align Back's text, not its hit box, to the gutter with `.padding(.leading, -8)` on both, so the text starts at x 48 like every card.

**ONB-9. The lock label wraps with a long name** (rough, S, high)
- Crop: `onb-4-lock-wrap.png`. Source: `4-body-long-unbroken-light`.
- Wrong: "I'm WWWW…W now, for keeps" takes 2 lines (y 500 to 528) and ends 8 pt from "I don't have my Boop yet". The lock icon stays on line 1; line 2 hangs under the text.
- Why: The bar is the only 2-line bar in the flow, and it looks like a layout fault.
- Cause: `OV:257` has no line limit; the `Spacer` in `OV:235` gives it all the width that is left.
- Fix: `.lineLimit(1).truncationMode(.middle).frame(maxWidth: 260, alignment: .leading)`. Or drop the name: "My name is for keeps".

**ONB-10. Secondary links: one style, fine; baseline is not shared** (nit, S, med)
- Sources: `4-body-intro-light`, `6-agents-heard-light`, `8-world-light`.
- Wrong: "I don't have my Boop yet", "Skip the tour" and "Keep Mochi private" all sit 8 pt left of the primary and are centre-aligned with it (text y 508.5 to 521.5; button label about y 508 to 520). They are 13 pt regular against the button's 13 pt semibold. This is consistent. The row uses centre alignment, not a shared baseline, so the link text sits about 0.5 pt low.
- Cause: `OV:233` `HStack` with default alignment.
- Fix: `HStack(alignment: .firstTextBaseline)`. Low priority.

**ONB-11. "Keep <name> private" grows to 256 pt** (nit, S, high)
- Source: `8-world-long-light`.
- Wrong: With the long name the link is x 380 to 636. With the 23 W name (not rendered for act 8) it will not fit beside Back and "Sounds good" (624 pt of bar).
- Cause: `OW:30-31`, no limit on the quiet label (`OV:237`).
- Fix: `.lineLimit(1).truncationMode(.middle)` on the quiet button in `OV:237`, with `.layoutPriority(-1)`. Add an `8-world-unbroken` snapshot.

**ONB-12. A disabled primary leaves the quietest control as the only live one** (rough, S, med)
- Crops: `onb-6-nav-disabled.png`, `onb-6-nav-disabled-dark.png`. Sources: `6-agents-heard-light`, `6-agents-tour-light`, `3-name-invalid-light`.
- Wrong: Disabled "Next" is the fill at 40% opacity: #969491 on paper, label #B7B1A5, label contrast 1.42:1 (light) and 1.90:1 (dark). It is clearly disabled. But during the tour the only way on is "Skip the tour" in soft ink, and nothing says why Next is off.
- Why: A person stuck on a tour step (the agent's turn must finish) sees a dead button and a faint link.
- Cause: `TH:474` (`opacity(enabled ? 1 : 0.4)`), `OF:234-236`.
- Fix: Keep 0.4 for the fill but draw the disabled state as an outline button (hairlineStrong border, inkFaint label, paper fill) so the label stays readable (inkFaint is 2.66:1; use inkSoft at 60%). Add `.help("Finish the steps on my screen, or skip the tour")`.

### Progress marks

**ONB-13. The footprints are charming but small and faint** (rough, S, high)
- Crops: `onb-footprints-light.png`, `onb-footprints-dark.png`.
- Wrong: 9 pairs of 5 x 8 pt capsules in a row 230.5 pt wide and 14.5 to 18.5 pt high. The current pair is scaled 1.35 (7.5 x 10.5 pt). Unwalked pairs are hairlineStrong: 1.54:1 on light paper, 1.81:1 on dark. Walked and current differ only by the 35% scale.
- Why: They read as decoration, not as "step 5 of 9". The current step is hard to pick out; in light mode the unwalked steps almost vanish. At 2 px per pt each capsule is 10 px wide and soft-edged.
- Cause: `OV:71-82`.
- Fix: Capsules 6 x 10 pt, pair spacing 12. Unwalked: `Theme.inkFaint` (2.66:1 light, 3.62:1 dark). Current: scale 1.5 plus a 3 pt dot under it, or amber is not allowed here, so use ink with a ring. Keep the alternate tilt. With 5 acts the row becomes 5 pairs and each can be 7 x 11 pt.

**ONB-14. The footprints' row height changes with the current step** (nit, S, high)
- Wrong: The row measures y 29 to 43.5 when the current pair tilts one way and y 27.5 to 46 when it tilts the other. The 16 pt gap under it is then 13.5 to 16 pt, and in act 3 the bubble comes within 3.5 pt of the footprints.
- Crop: `onb-3-tile-footprints.png`.
- Cause: `OV:79-80`: `scaleEffect` and `rotationEffect` draw outside the layout box; `OI:289` offsets the bubble by -6.
- Fix: Give `Footprints` a fixed `.frame(height: 20)`; raise the bottom padding in `OV:20` from 16 to 20.

### Act 1: hello

**ONB-15. The bubble's tail points away from the face** (nit, S, med)
- Crop: `onb-1-bubble.png`. Source: `1-hello-light`.
- Wrong: The bubble (x 166 to 260, y 108 to 146) sits up and left of the tile. Its small-radius corner (the tail) is bottom left, which points away from the buddy. In act 3 the bubble is on the right of the tile and the same bottom-left tail points at the buddy, which is correct.
- Cause: `OV:197-198` fixes the tail at bottom leading; `OI:24-25` places the bubble at the tile's left.
- Fix: Give `Bubble` a `tail: .leading / .trailing` parameter; act 1 uses trailing. Or move act 1's bubble to the tile's top right, as in act 3.

**ONB-16. Act 1's body text is the only 15 pt text** (nit, S, high)
- Wrong: 15 pt here (`OI:31`), 14 pt for every other act's line under the title (`OV:213`), 13 pt for act 2's and act 4's notes.
- Fix: Use 14 pt and `maxWidth: 440`, as `ActTitle` does.

### Act 2: what I do

**ONB-17. The amber outline goes 6 pt past the gutter** (nit, S, high)
- Crop: `onb-2-outline.png`. Source: `2-what-i-do-light`.
- Wrong: The tile is x 436 to 672. In the "needs you" beat the outline is drawn to x 678 and from y 96.5 to 285.5, so it is 6 pt past the right gutter and 5.5 pt taller than the terminal on each side (terminal y 102 to 280).
- Cause: `OI:149-151`: `.padding(-6)` on a 5 pt stroke.
- Fix: Draw the ring inside: `.padding(0)` with the stroke over the tile's edge, or inset the tile by 6 pt in this act (`.padding(.trailing, 6)`) so the ring ends at x 672.

**ONB-18. Terminal 178 pt, tile 177 pt** (nit, S, high)
- Wrong: The two tiles of the hero row differ by 1 pt (`OI:181` against `OI:147`), so one of them sits on a half pixel (tile top y 102.5).
- Fix: Use one constant, 177, for both.

**ONB-19. The three cards have two heights** (rough, S, high)
- Crop: `onb-2-cards.png`.
- Wrong: "Working along" is 94 pt tall (3 lines); the other two are 79 pt (2 lines). They are centre-aligned, so the tops are at y 298 and y 305.5.
- Why: A row of three cards with ragged tops and bottoms looks unfinished. It is the first card row a person sees.
- Cause: `OI:156-160`: `HStack` of `Card`s; a `Card` only fills width (`TH:165`).
- Fix: `HStack(alignment: .top)` plus `.frame(maxHeight: .infinity, alignment: .top)` on each card's content and `.fixedSize(horizontal: false, vertical: true)` on the row. The copy team can also cut card 1 to 2 lines.

**ONB-20. Terminal is one third empty; mono text is 12.5 pt** (nit, S, med)
- Source: `2-what-i-do-light`.
- Wrong: At most 6 lines of 12.5 pt (x-height about 6.5 pt) fill y 118 to 216 of a card that ends at y 280. The size 12.5 exists only here and in the hooks text.
- Cause: `OI:178`, `OI:181`.
- Fix: 13 pt mono, line spacing 8, so six lines fill the card. Keep to whole point sizes.

### Act 3: name

**ONB-21. The name field has no side padding** (rough, S, high)
- Crop: `onb-3-unbroken-field.png`. Source: `3-name-unbroken-light`.
- Wrong: The field is x 130 to 590 (460 x 45 pt). With 23 W's the text runs from x 133 to x 587: 3 pt from each border.
- Cause: `OI:299`: `.padding(.vertical, 11)` only.
- Fix: `.padding(.horizontal, 16)`, and widen the box to 492 (`OI:302`) so the widest name still fits.

**ONB-22. A grey box sits behind the name** (rough, S, low)
- Crop: `onb-3-field-highlight.png`. Sources: `3-name-light`, `3-name-dark`, all act 3 states.
- Wrong: The text has a grey rectangle behind it (#DCDCDC on the #F3EDE3 box in light; a lighter grey block in dark). This is the system's selection highlight: the field takes focus on appear and selects its text.
- Why: In a live, key window the box will be the system accent colour (blue by default) on warm paper. It is the only system-coloured thing in the flow. It shows when the person comes Back to act 3 with a name set. I can not confirm the live colour from stills.
- Cause: `OI:304` (`nameFocused = true` on appear) and AppKit's select-all on focus.
- Fix: After focus, move the caret to the end (set the field editor's `selectedRange`), or tint the selection with `.tint(Theme.hairlineStrong)` on the field.

**ONB-23. The bubble breaks an unbroken name in the middle** (nit, S, high)
- Crop: `onb-3-unbroken-bubble.png`. Sources: `3-name-unbroken-light`, `3-name-unicode-light`.
- Wrong: 240 pt wide bubble: "WWWWWWWWWWWWW / WWWWWWWWWW! I / love it." (3 lines, 77 pt tall, ends 20 pt above the title). Korean: "…말랑이! I / love it.", so "I" hangs at the end of a line.
- Cause: `OI:287-289`: fixed 240 pt width.
- Fix: Put "I love it." on its own line when the name is longer than about 12 characters (`"\(name)!\nI love it."`), and use `.lineLimit(1).minimumScaleFactor(0.7)` for the name line.

**ONB-24. The two hint lines are 12 pt, centred, under a 20 pt field** (nit, S, med)
- Source: `3-name-light`, `3-name-invalid-light`.
- Wrong: Hints at y 281 to 310, 12 pt soft ink. The error replaces line 1 in clay ink (6.38:1, fine) but the field's border does not change, and the two lines then have two colours.
- Cause: `OI:310-317`; `TH:306-307` has no error state.
- Fix: 13 pt. In the error state colour the field's border clay (`fieldBox` gets an `error:` flag) and hide line 2.

### Act 4: body

**ONB-25. The board drawing is off centre** (rough, S, high)
- Crop: `onb-4-intro-art.png`. Source: `4-body-intro-light`.
- Wrong: The group tile + cable + plug is centred (x 225 to 495), so the tile's centre is at x 300 and the title's centre is at x 360. The face is 60 pt left of the title under it.
- Cause: `OB:213-224`: an `HStack` of the three parts.
- Fix: Centre the tile; draw the cable and plug as `.overlay(alignment: .trailing)` with `.offset(x: 120)`.

**ONB-26. The cable is a floating bar** (nit, S, med)
- Crop: `onb-4-intro-art.png`.
- Wrong: The cable is a 90 x 8 pt capsule in hairlineStrong (1.54:1) that starts 1 pt off the tile and ends inside the plug (30 x 22 pt, radius 6, soft ink). It leaves the tile at its exact middle, straight, with rounded ends: it reads as a slider, not a cable. "z z" (18 pt heavy, x 376 to 392, y 56.5) is 10.5 pt under the footprints.
- Cause: `OB:216-223`.
- Fix: Draw the cable as a `Path` with a slight sag (a quadratic curve, 4 pt stroke, round cap, inkFaint), leaving from the tile's lower right; plug 26 x 18 pt with two 2 x 5 pt prongs. Move "z z" inside the hero slot (offset x 14, y -6).

**ONB-27. Act 4 has four layouts in one sequence** (rough, M, high)
- Crop: `onb-4-states.jpg`. Sources: intro, looking, found, joined.
- Wrong: Tile 150 at y 64 (intro), 140 at y 94 (looking), 160 at y 76 (joined). Title top y 247, 295, 316.5, 283.5. So from "Look for me" to "There you are!" the face and title jump three times.
- Cause: `OB:38` (height 170), `OB:75-80` (height 220), `OB:145-158` (height 210).
- Fix: One hero slot of 200 pt and one tile size (150) for all four states. The rings, the cable and the desk are drawn around the same tile. Then the title stays at one y and only the words change.

**ONB-28. Error states leave a 61 pt hole** (rough, S, high)
- Crop: `onb-4-stuck-gap.png`. Sources: `4-body-bluetooth-off-light`, `4-body-bluetooth-refused-light`, `4-body-cant-start-light`.
- Wrong: The rings are removed but their 220 pt frame stays: tile bottom y 234, title top y 295.5. The face still shows the curious, happy look under "I can't look for my body".
- Cause: `OB:75-80`; the snapshot is `.onboarding(mood: "curious")` in every case (`OB:78`).
- Fix: Same slot as ONB-27. Use a sad or sheepish mood when `stuck` is true.

**ONB-29. Error states: the fix button is small and the way on is far away** (rough, S, med)
- Sources: `4-body-bluetooth-off-light`, `4-body-bluetooth-refused-light`, `4-body-cant-start-light`.
- Wrong: "Open Bluetooth Settings", "Open Privacy & Security" and "Try again" are row buttons: 11 pt medium, 22 pt tall, outlined (y 361 to 383). The act has no filled button. "Go on without my body for now" is a soft link at the far bottom right.
- Why: An error state is where the next step must be most obvious. Here it is the smallest button in the flow.
- Cause: `OB:83`, `OB:121` (`.buttonStyle(.row)`), `OB:88-94`.
- Fix: Make the fix the primary in the bar (`ActNav(next: label)`), with "Go on without my body for now" as its quiet link.

**ONB-30. The rings are faint and partly hidden** (nit, S, med)
- Crop: `onb-4-rings.png`. Sources: `4-body-looking-light`, `4-body-looking-dark`.
- Wrong: Three 2 pt ellipses in hairlineStrong at 100%, 67% and 33% opacity (1.54:1 at best in light, 1.81:1 in dark). The inner ring (162 x 99 pt) is almost all behind the 140 pt tile; only two short arcs show at the sides. The tile's shadow darkens the rings near it.
- Cause: `OV:319-345` (`from = 0.45` of 360 x 220); `OB:77`.
- Fix: Start the rings at the tile's edge: `from = 0.62` for a 150 pt tile in a 360 pt frame, and use `inkFaint` at 70% for the first ring. Make the rings circles or match the tile's rounded square.

**ONB-31. "FOUND BOOP-54FE" is 11 pt caps over a 26 pt title** (nit, S, med)
- Sources: `4-body-found-light`, `4-body-in-window-found-light`.
- Wrong: The label is 12 pt semibold caps, tracked, sage ink (6.11:1), y 292 to 303, 6 pt above the title. It pushes the title 21.5 pt lower than in "looking" (y 295 to 316.5). It is the only tracked caps label in the flow besides "HOW I FEEL" and "TRY" (both untracked).
- Cause: `OB:109-116`.
- Fix: Put the label in the hero slot (a sage chip on the tile's lower edge) so the title does not move. Use one caps style: 11 pt semibold, tracking 0.6, for all three labels.

**ONB-32. The desk is a 6 pt bar** (nit, S, low)
- Crop: `onb-4-desk.png`. Source: `4-body-joined-light`.
- Wrong: A 260 x 5.5 pt bar (hairlineStrong, 1.54:1) at y 236.5, touching the tile's bottom. With the tile's shadow it reads as an underline. In dark mode it is 1.81:1.
- Cause: `OB:235-238`.
- Fix: A 280 x 8 pt bar with radius 4 in `Theme.well`, 4 pt under the tile, plus the tile's own small stand (a 40 x 6 pt foot). Or drop the bar and let confetti carry the moment.

**ONB-33. The "lost my voice" card is full width under centred text** (nit, S, med)
- Crop: `onb-4-no-voice.png`. Sources: `4-body-joined-no-voice-light`, `4-body-long-no-voice-light`.
- Wrong: The card is x 48 to 672, 43.5 pt tall, with one 12 pt line that ends at x 656: 8 pt of spare room. The title and line above are centred and 280 pt wide. The icon is `speaker.slash` in soft ink.
- Cause: `OB:163-167`.
- Fix: `.frame(maxWidth: 520)` like acts 8 and 9, 2 lines allowed. Any longer string will wrap; that is fine at 520.

**ONB-34. The "hungry" card is not in the pictures** (rough, S, high)
- Sources: `4-body-joined-hungry-light` and `-dark` are byte-identical to `4-body-joined-*`.
- Wrong: The snack card (`OB:180-195`) is not drawn, so its layout (title 14 pt, detail 12 pt, a filled row button 22 pt tall) has not been seen in review.
- Cause: `internal/app/Boop/Snapshots.swift:273-276` sets `boardFirmware` but `firmwareOffer` (`MenuBarApp.swift:259-262`) returns nil for the fixture's device.
- Fix: Make the fixture's device match the firmware entry (board id and an older version), then review. Expect the same full-width problem as ONB-33 and a 22 pt "Update" button that is too small for the act's only action.

### Act 5: how to

**ONB-35. "waiting…" narrows the text and makes orphans** (rough, S, high)
- Crop: `onb-5-waiting-wrap.png`. Sources: `5-how-to-talk-light`, `5-how-to-in-window-light`, `6-agents-heard-light`.
- Wrong: "waiting…" (12 pt medium, 51.5 pt wide) plus a spacer takes about 75 pt from the detail. The detail then wraps to a third line of one word ("time.", "it now.", "files here.") and the row grows from 56 to 86 pt.
- Cause: `OV:172-175`.
- Fix: Put "waiting…" on the title's line, trailing (`HStack { title; Spacer(); waiting }` at `OV:165-168`). The detail then keeps the full width. Reserve 2 lines (see ONB-1).

**ONB-36. The current row is marked by a 1.16:1 tint** (rough, S, med)
- Sources: `5-how-to-light`, `5-how-to-dark`, `6-agents-tour-light`.
- Wrong: The row to do now is ink at 8% over the raised card: #E2DDD3 against #F3EDE3 (1.16:1; dark 1.24:1), with an ink border at 45%. The number circle turns ink. Soft text on the tint is 4.65:1 (light), just over the 4.5 line.
- Why: The row is the act's focus. The dark number circle carries it; the tint and "waiting…" in soft ink do not.
- Cause: `OV:153` (`tone: now ? Theme.ink : nil`), `TH:166-170`, `TH:83`.
- Fix: Keep the tint, make the border full ink at 1.5 pt, and give "waiting…" a small pulsing dot in ink (it is live). Do not use amber: amber means needs you.

**ONB-37. "TRY" is 10 pt at 2.66:1** (rough, S, high)
- Crop: `onb-5-try-chips.png`.
- Wrong: The smallest text in the flow: 10 pt semibold, cap height 8 pt (16 px), in inkFaint: 2.66:1 light, 3.62:1 dark. The palette's own note says inkFaint is for decoration and disabled things only (`TH:11-13`).
- Cause: `OB:334`.
- Fix: 11 pt semibold, `Theme.inkSoft`, tracking 0.6 (the caps style of ONB-31).

**ONB-38. The chips' ends have "ears"** (nit, S, med)
- Crop: `onb-5-chip-zoom.png`.
- Wrong: At 6x, each chip's left and right end shows a short vertical stroke outside the curve (about 1 px wide, 20 px tall). The capsule's stroke is not clean where it meets the flat sides.
- Cause: `OB:350`: `Capsule().strokeBorder` as a background of a box with a fractional width (67.5 pt), so the caps land between pixels. Confidence in the cause is low; the artefact itself is real.
- Fix: `RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(...)` in an `.overlay`, and round the chip's width up with `.frame(minWidth:)` or `.padding(.horizontal, 8.5)`.

**ONB-39. The chips look like buttons but do nothing** (nit, S, med)
- Wrong: Outlined capsules (20 pt tall, 11 pt text) are the same shape as the row buttons two acts later ("Allow"). They are examples to say aloud.
- Cause: `OB:347-351`.
- Fix: Drop the outline; set them as quoted italic text separated by middle dots, or fill them with `Theme.well` and no border.

**ONB-40. The mood legend is too small to read as four moods** (rough, M, med)
- Crops: `onb-5-moods.png`, `onb-5-moods-dark.png`.
- Wrong: Four 44 pt tiles. At that size the face's features are 2 to 4 px: Grumpy, Proud and Tired differ by a mouth line and eyelids. The labels carry all the meaning. The row is x 48 to 628 and the last column ends 44 pt short of the gutter. Labels are 13 pt bold with 11 pt details (cap height 7.5 pt).
- Why: This is the one place that shows that Boop has moods, and it is squeezed under four lessons (and causes ONB-1).
- Cause: `OB:272-282`, `OB:381-395`.
- Fix: Move the legend to act 2 (or the finale) with 64 pt tiles and the zoomed slime (`SlimeFace.zoomBelow` logic at `Slime/SlimeView.swift:37`), label under each tile, centred.

**ONB-41. The amber dot is the only colour cue for amber, 7 pt** (nit, S, low)
- Sources: `5-how-to-light`, `9-finale-light`.
- Wrong: A 7 pt amber dot after the title (1.57:1 on the card). It is correct use of amber, but tiny, and in the "waiting" state of lesson 4 the row is still tinted ink, not amber, while the text says "I'm glowing amber now".
- Cause: `OV:167`, `OV:153`.
- Fix: When lesson 4 is the current one, tone the row amber (`tone: Theme.amber`, as act 2's "Needs you" card does at `OI:190`).

**ONB-42. The no-board state looks the same as the board state** (nit, S, med)
- Source: `5-how-to-no-board-light`.
- Wrong: Four numbered rows with empty circles and no "waiting…". They look like steps to do, but nothing can be done. Only the 14 pt line under the title says so.
- Cause: `OB:262-271`.
- Fix: Without a board, drop the numbers and use each lesson's icon (`hand.tap`, `button.programmable`, `mic`, `bell`) in the circle. Then the rows read as a list of facts.

### Act 6: agents

**ONB-43. "Not found" Codex card: the switch is invisible** (rough, S, high)
- Crop: `onb-6-codex.png`. Sources: `6-agents-light`, `6-agents-dark`.
- Wrong: The card is at 60% opacity and the switch is at 40% of that: track #ECE4D7 on #F3EDE3, 1.08:1 (dark 1.11:1); the white knob has no edge. "Not found on this Mac" is 2.42:1 and "Codex" 3.97:1.
- Why: The line that explains why the card is off is the least readable text in the flow.
- Cause: `OF:148` (`.opacity(found ? 1 : 0.6)`) on top of `TH:524` (`.opacity(enabled ? 1 : 0.4)`).
- Fix: Do not fade the whole card. Keep the text at full soft ink (5.40:1), and replace the switch with nothing or a small "Not installed" chip when `found` is false.

**ONB-44. Agent card titles are 16 pt; every other card title is 14 or 15** (nit, S, high)
- Wrong: Card title sizes: 14 pt (act 2 cards, act 9 tips, act 4 snack), 15 pt (act 5 rows, act 7 rows, act 8 lists), 16 pt (act 6 agents), 17 pt (act 6 hello card). Four sizes for one card family. Card detail is 12 pt everywhere, which is good.
- Cause: `OI:197`, `OF:409`, `OB:184`, `OV:166`, `OF:303`, `OF:339`, `OK:22`, `OW:38`, `OF:135`, `OF:166`.
- Fix: One constant: `Font.cardTitle = .boop(15, .bold)`. The hello card may keep 17 as the act's hero.

**ONB-45. The hooks panel: long lines, a white scroller, a cut card** (rough, M, high)
- Crop: `onb-6-hooks.jpg`. Sources: `6-agents-what-gets-added-light`, `-dark`.
- Wrong: (a) Text is 12.5 pt at full ink in lines of 95 to 100 characters (x 60 to 655). Two paragraphs, 7 and 3 lines, with no hierarchy. (b) The scroller is the legacy style: a white track 12 pt wide (x 645 to 660, y 240 to 440) on the well colour, light mode only; in dark mode it is a darker stripe. (c) The first agent's card is cut at the fold after one line (y 437 to 448) with no fade. (d) The panel's radius is 10; the tokens are 12 (card) and 8 (well). (e) The path shown is a temp folder (`/var/folders/…`), which is the fixture, not the app.
- Why: This is the trust moment of the flow ("see exactly what gets added"). It looks like a log dump.
- Cause: `OF:62-77`, `OF:66` (12.5 pt, `Theme.ink`), `OF:74` (height 200), `OF:76` (radius 10).
- Fix: Put the agent's card first (file, hook count, the command), then the two paragraphs as 12 pt soft-ink text limited to `maxWidth: 520`. Use `.scrollIndicators(.never)` plus a 16 pt bottom fade mask. Use `Theme.wellRadius` or `cardRadius`. Give the panel the space that the act has: 240 pt, not 200 (the act has 278 pt free).

**ONB-46. The hello card: black tile on a near-black card** (nit, S, high)
- Crops: `onb-6-hello.png`, `onb-6-hello-dark.png`. Sources: `6-agents-hello-light`, `-dark`.
- Wrong: The tile (#000) on the terminal card (#24211C) is 1.2:1; its shadow does nothing. In light mode the dark card is a strong hero. In dark mode it is the same fill as every other card, so the hero is lost. The card is 140 pt tall for 3 lines of text; the 17 pt title wraps to 2 lines with "files here" alone on line 2.
- Cause: `OF:159-180`, `OV:266-269`, `TH:74`.
- Fix: Give the tile a 1 pt `Theme.terminalEdge` border on this card (see ONB-50). In dark mode give the terminal card a stronger edge (hairlineStrong) so it still stands out.

**ONB-47. Tour rows are a second, tighter StepRow** (nit, S, med)
- Sources: `6-agents-tour-light`, `5-how-to-light`.
- Wrong: Act 5 rows: 56 pt tall, 28 pt circle, 15 pt title, 8 pt apart. Act 6 rows: 46 pt tall, 24 pt circle, 14 pt title, 6 pt apart. The same component in two densities, one act apart.
- Cause: `OV:148-149`, `OV:163-166`, `OV:177`, `OF:214-216`.
- Fix: One density: 48 pt rows, 24 pt circle, 14 pt bold title, 8 pt gap. It also fixes ONB-1 (saves 32 pt in act 5).

**ONB-48. Act 6 choose: the disclosure is a faint centred link** (nit, S, med)
- Source: `6-agents-light`.
- Wrong: "See exactly what gets added" is 12 pt soft ink with a 9 pt chevron, centred at y 207 to 220, under two cards. It is the smallest interactive text on the act and it is the consent detail.
- Cause: `OF:55-61`.
- Fix: 13 pt, left-aligned under the cards at x 48, with the chevron in ink.

### Act 7: small things

**ONB-49. Three rows, three control sizes** (rough, S, high)
- Crops: `onb-7-rows-right.png`, `onb-7-mic-check.png`, `onb-7-key.png`. Sources: `7-small-things-light`, `7-small-things-mic-allowed-light`.
- Wrong: Row 1: a 38.5 x 22 pt switch. Row 2: "Allow", a 49.5 x 22 pt outlined button with 11 pt text; when allowed, a 13 pt tick (the switch above is 22 pt, the act 5 ticks are 28 pt). Row 3: "Save", 22 pt tall, disabled at 40% (label 2.46:1), beside a field that is 24 pt tall with 12 pt text. The rows are 65, 81 and 115.5 pt tall. "Jev's docs" is a 12 pt soft link top right, the only link of that kind in the flow.
- Why: The trailing controls do not line up in size or weight, and "Allow" and "Save" are the smallest buttons in onboarding (22 pt tall against the 32 pt primary).
- Cause: `OF:311-316`, `OF:345-347`, `OK:41-58`, `TH:491-493` (row button: 11 pt, 4 pt vertical padding).
- Fix: An onboarding size for the row button: 13 pt medium, 28 pt tall (`RowButtonStyle(large: true)`). Tick: `.font(.system(size: 20))`. Field: 28 pt tall, 13 pt text. Give all three trailing controls one 64 pt wide column, centred.

**ONB-50. The login switch that can not be used looks like the Codex one** (nit, S, high)
- Source: `7-small-things-from-terminal-light`.
- Wrong: The disabled switch is the off track at 40%: 1.2:1 on the card. Same cause and fix as ONB-43 (`TH:524`).
- Fix: Disabled switch: keep the track at full hairlineStrong and fade only the knob, or hide the switch and show the reason only.

**ONB-51. Act 7 has no face and no lead line** (nit, S, med)
- Source: `7-small-things-light`.
- Wrong: The only act (with act 6 choose) without the buddy and without a line under the title. Three settings cards make it read like a preferences pane.
- Cause: `OF:289-296`.
- Fix: The `side` face at the title (ONB-3) and one 14 pt line ("Each one is optional."; copy team to word it).

### Act 8: world

**ONB-52. Two lists of equal weight; the promise is not the stronger one** (nit, S, med)
- Crop: `onb-8-cards.png`. Sources: `8-world-light`, `8-world-dark`.
- Wrong: "Others see" and "Nobody sees" are identical cards (254 x 131 pt, x 100 to 620). The lines are 12 pt soft ink with 6 pt between them and no bullets, so 4 short lines read as one paragraph. The cards are 520 pt wide while acts 2, 5, 6 and 7 use the full 624 pt.
- Cause: `OW:34-45`, `OW:26`.
- Fix: Keep 520 (it is the better width; see section C). Lines at 13 pt with 8 pt between. Give "Nobody sees" the sage tick style per line (`checkmark` in sage ink) or a sage-toned card, so the private side reads as the promise.

**ONB-53. Act 8 is the cleanest act; keep it as the model** (note)
- Face at the top, title, one line, two cards, a note, a bar with one quiet link. 88 pt of slack. This is the "hero" template in section C.

### Act 9: finale

**ONB-54. A long name: the title wraps and turns left-aligned** (broken, S, high)
- Crop: `onb-9-unbroken.png`. Sources: `9-finale-unbroken-light`, `-dark`.
- Wrong: "WWWW…W / WWW is all set!" takes 2 lines, x 60.5 to 659, and line 2 starts at the left (x 60.5 to 282) under a centred face. The tip grid moves down 35 pt. With the 22-letter name (`9-finale-long`) the title is one line of 527 pt, 48 pt from each edge.
- Cause: `OF:374`: no `.multilineTextAlignment(.center)`, no limit. `ActTitle` has it (`OV:210`).
- Fix: `.multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)`. Better: use `ActTitle` and one title size (ONB-55).

**ONB-55. The finale's title is 30 pt heavy; all others are 26 pt bold** (nit, S, high)
- Cause: `OF:374` against `OV:210`.
- Fix: Use 26 pt bold, or make 30 pt heavy a named "celebration" style and use it for "There you are!" too.

**ONB-56. Tip cards in one row have different heights** (rough, S, high)
- Crop: `onb-9-grid.png`. Sources: `9-finale-no-board-light`, `9-finale-unbroken-light`.
- Wrong: "Got my body?" is 61 pt tall and "Click Talk" beside it is 76 pt (its detail wraps to 2 lines). The short card is centred in the row, so tops and bottoms are 7.5 pt off.
- Cause: `OF:375-392`: `LazyVGrid` does not stretch cells; `OF:412` has no line limit.
- Fix: Use `Grid` with `GridRow` and `.frame(maxHeight: .infinity)` on each tip, or two `HStack`s with `.fixedSize(horizontal: false, vertical: true)`. Reserve 2 detail lines in every tip.

**ONB-57. The tilted tile is soft at its edge, and near the footprints** (nit, S, med)
- Crop: `onb-9-tilt.png`. Source: `9-finale-light`.
- Wrong: The tile is rotated 4 degrees. Its edge is anti-aliased well, but the image inside is resampled, so the slime is slightly softer than in other acts. The top corner is 8 pt under the footprints (y 51.5 against 43.5).
- Cause: `OF:371-373`.
- Fix: Keep the tilt (it is the only one, and it works) but apply it to the hero slot with 12 pt more top padding. Or drop the tilt and let the live "excited" animation carry it.

**ONB-58. Tip icons are 15 pt soft ink in a 20 pt column** (nit, S, low)
- Source: `9-finale-light`.
- Wrong: The four icons differ in optical size (mic is 11 x 17 pt, the drawer glyph 17 x 12 pt) and are soft ink while the act 7 icons are full ink at 15 pt bold beside the title.
- Cause: `OF:406` against `OF:303`.
- Fix: One icon treatment for card icons: 15 pt, medium weight, `Theme.ink`, in a 24 pt box.

### Across acts

**ONB-59. In dark mode the face tile has no edge** (rough, S, high)
- Crop: `onb-1-tile-dark.png`, `onb-all-dark.jpg`. Sources: every dark picture.
- Wrong: The tile is #000 glass on #1B1815 paper: 1.19:1. The shadow (black at 16%) can not be seen on dark paper. The tile's rounded square is hard to see; the slime seems to float in a vague dark patch. On cards (#24211C) it is 1.3:1.
- Cause: `Slime/SlimeView.swift:51-52` (no border); `OV:128` (black shadow).
- Fix: In `OnboardingBuddy` add `.overlay(RoundedRectangle(cornerRadius: r).strokeBorder(Theme.hairlineStrong.opacity(0.9), lineWidth: 1))` in dark mode only (hairlineStrong on black is 2.0:1), or light the tile from behind with a soft oat glow (`.shadow(color: oat.opacity(0.08), radius: 18)`).

**ONB-60. Two corner styles for the same tile** (nit, S, med)
- Wrong: The big tile uses a circular corner (`Slime/SlimeView.swift:52`, radius 27% of the size); the mood tiles use a continuous corner (`Slime/SlimeStills.swift:95,101`). Side by side in act 5 against act 4 the shapes differ slightly.
- Fix: `style: .continuous` in both.

**ONB-61. Seven text sizes for body copy** (rough, S, high)
- Wrong: 15 pt (act 1), 14 pt (line under a title), 13 pt (acts 2, 4, 6 notes; links), 12.5 pt (hooks text, terminal), 12 pt (card details, act 3 hints, act 8 note), 11 pt (chips, mood details, row buttons, mono hooks), 10 pt (TRY).
- Why: Notes that play the same role have different sizes: act 2's note "I only watch…" is 13 pt, act 8's note "You can change this…" is 12 pt, act 3's hints are 12 pt.
- Cause: literals across `OI`, `OB`, `OF`, `OW`, `OK`.
- Fix: Four named sizes in `Theme`: `lead` 14, `note` 13, `detail` 12, `caption` 11. Nothing under 11.

**ONB-62. Soft ink is fine; faint ink and faded things are not** (note, high)
- Measured: soft ink 5.89:1 on paper, 5.40:1 on a card, 4.94:1 on the well, 4.65:1 on the "now" row (light); 7.12, 6.46, 5.21 (dark). All pass 4.5:1. Sage ink 6.11:1, clay ink 6.38:1.
- Fails: inkFaint text (TRY) 2.66:1; faded Codex card text 2.42:1; disabled "Save" 2.46:1; disabled "Next" label 1.42:1; unwalked footprints 1.54:1; card edge 1.29:1 with card fill 1.09:1 on paper (cards are held only by the hairline; fine, but the "now" tint at 1.16:1 is then weak).

**ONB-63. Card padding and radius are one family; three exceptions** (nit, S, high)
- Good: `Card(padding: 14)`, radius 12, hairline, raised fill in acts 2, 4, 6, 7, 8, 9.
- Exceptions: StepRow uses padding 14 x 10 or 14 x 6 (`OV:177`); the hooks panel uses radius 10 and padding 12 (`OF:75-76`); the key field uses radius 7 while the name field uses 12 (`OK:45`, `OI:300`).
- Fix: StepRow 14 x 10 only; hooks panel radius 12; one field radius (8, the well token).

**ONB-64. Centred and left-aligned blocks are mixed in one act** (nit, M, med)
- Sources: `5-how-to-light`, `6-agents-light`, `4-body-joined-no-voice-light`, `9-finale-unbroken-light`.
- Wrong: Act 5: centred title, left rows, left chips indented 56 pt, left legend. Act 6: centred title and line, left cards, a centred link, a left panel. Act 4 joined: centred text over a left-aligned full-width card.
- Fix: Rule for the frame: the title block is always centred; everything in the body slot is left-aligned to the body's edge; notes under the body are centred. The disclosure link in act 6 and the no-voice card follow the body.

**ONB-65. States with no picture** (note)
- Byte-identical pairs: `4-body-joined-hungry` = `4-body-joined`; `9-finale-gel` = `9-finale`; `5-how-to-done` = `5-how-to-talk`; `6-agents-long` = `6-agents-heard`; `7-small-things-long` = `7-small-things`.
- Not rendered at all: act 6 "heard" without the tour (`OF:187-190`), no agent found (`OF:24-28`), hook errors (`OF:51-54`), client missing (`OF:47-49`); act 7 mic asking and refused (`OF:346-348`), key saved and failed (`OK:32-33`, `OK:53-55`), login needs approval (`OF:308-309`); act 4 firmware writing, done, failed (`OB:197-203`); act 9 "Tap my screen" tip (`OF:384`); act 8 with the 23 W name.
- Fix: Add these to `internal/app/Boop/Snapshots.swift:275` and review them. The key-saved text is 2 lines of 12 pt and will make the act 7 card 15 pt taller.

---

## B. Consistency table

Window: 720 x 560 pt in every act and state. Gutter 48 pt (content x 48 to 672). Footprints top y 27.5 to 29 (act 5: 7.5 to 27.5).

| Act | Title top y (pt), size | Face size, top y | Primary: label, w x h, position | Text under title / body sizes | Cards |
| --- | --- | --- | --- | --- | --- |
| 1 hello | none (bubble 17 pt bold at y 108) | 196, y 150 | "Hi, Boop!" 90 x 32, centred, y 432 | 15 pt, 402 pt wide | none |
| 2 what I do | 59.5, 26 bold | 236 x 177, y 102.5, right | "Neat!" 66.5 x 32, right, y 498 | note 13 pt | terminal card 366 x 178; 3 `Card` 14 pad, title 14, detail 12; heights 94/79/79 |
| 3 name | 181.5, 26 bold | 108, y 54 | "That's me" 95 x 32, right, y 498 | hints 12 pt | field 460 x 45, radius 12, 20 pt bold |
| 4 intro | 247, 26 bold | 150, y 64, centre x 300 | "Look for me" 106.5 x 32, right, y 498 | 14 pt; info line 13 pt | row button 22 pt tall |
| 4 looking / errors | 295, 26 bold | 140, y 94 | none (link only, y 513) | 14 pt | row button 22 pt tall |
| 4 found | 316.5, 26 bold | 140, y 94 | none | 14 pt; caps label 12 pt | none |
| 4 joined | 283.5, 26 bold | 160, y 76 | "Next" 61.5 x 32, right, y 498 | 14 pt | `Card` 14 pad, 12 pt, full width |
| 5 how to | 50.5 (38 to 58), 26 bold | 4 x 44, y 414 | "Got it" 67 x 32, right, y 507 (499.5 to 519.5) | 14 pt (no-board only); legend 11 to 13 pt | StepRow 56 to 86 tall, circle 28, title 15, detail 12; chips 20 tall, 11 pt |
| 6 choose | 59, 26 bold | none | "Connect" 85.5 x 32, right, y 498 | 14 pt; link 12 pt | 2 `Card` 14 pad, title 16, 66 tall; panel radius 10 |
| 6 hello / tour | 59, 26 bold | 104 or 84, in the card | "I'll try it later" 113 x 32 / "Next" 61.5 x 32 | note 12 pt | terminal card, title 17; StepRow compact 46 tall, circle 24, title 14 |
| 7 small things | 59, 26 bold | none | "Next" 61.5 x 32, right, y 498 | none | 3 `Card` 14 pad, title 15 with icon, detail 12; 65/81/115.5 tall |
| 8 world | 169, 26 bold | 96, y 54 | "Sounds good" 115 x 32, right, y 498 | 14 pt; note 12 pt | 2 `Card` 14 pad, title 15 with icon, lines 12; 520 wide |
| 9 finale | 231.5, 30 heavy | 150 tilted, y 58.5 | "Let's go!" 87 x 32, centred, y 498 | none | 4 `Card` 14 pad, title 14, detail 12; 520 wide; 61 or 76 tall |

Button label style: all 13 pt semibold, oat on glass (light), glass on oat (dark), radius 10, 16 x 8 padding. This part is consistent. Voice varies ("Neat!", "Got it", "Next" x3, "Sounds good"): fine; the three plain "Next" are the acts with the least character.

---

## C. Layout proposals

### C1. One frame for every act

Two variants of one frame. All x from 48 to 672. All numbers in pt.

```
HERO variant (acts 1, 3, 4, 8, 9)            LIST variant (acts 2, 5, 6, 7)
y
0   +------------------------------------+   +------------------------------------+
30  |          '' '' '' '' ''            |   |          '' '' '' '' ''            |  footprints, 20 high
50  |                                    |   |                                    |
66  |            +--------+              |   | (face 64)  Title 26 bold           |  title top y 66
    |            |  face  |   hero slot  |   |            lead 14, max 440        |
    |            |  150   |   170 high   |   |112 +----------------------------+  |
    |            +--------+   (rings,    |   |    |                            |  |
236 |                          cable,    |   |    |  body slot                 |  |
    |        Title 26 bold     desk)     |   |    |  left-aligned, 624 wide    |  |
270 |     lead 14, max 440 wide          |   |    |  centred in its space      |  |
300 |    +------------------------+      |   |    |  max 360 high              |  |
    |    | body slot, 520 wide    |      |   |    |                            |  |
    |    | centred in its space   |      |   |    +----------------------------+  |
    |    | max 170 high           |      |   |          note 13, centred          |
470 |    +------------------------+      |   |                                    |
    |          note 13, centred          |   |                                    |
498 | Back              quiet  [Primary] |   | Back              quiet  [Primary] |  bar, 32 high
530 +------------------------------------+   +------------------------------------+
560
```

Rules:
- Footprints: fixed 20 pt box at y 30. Never moves.
- Face: `hero` 150 pt (centred, top y 66) or `side` 64 pt left of the title in the list variant. Act 1 may use 196.
- Title: `ActTitle`, 26 pt bold, centred. Top at y 236 (hero) or y 66 (list). Lead line 14 pt soft ink, max 440 pt, max 2 lines.
- Body slot: left-aligned content. 520 pt wide in the hero variant, 624 pt in the list variant. Centred vertically in the space it has; never grows past its maximum (scrolls inside if it must, as the hooks panel does).
- Note: one optional centred line, 13 pt soft ink.
- Bar: always at y 498 to 530. Height 32 even with no primary.
- Type: title 26; card title 15 bold rounded; lead 14; note 13; detail 12; caption 11.

### C2. The bar

```
x 48                                                            x 672
| Back                          I don't have my Boop yet  [ Look for me ] |
| lock  My name is for keeps                   Skip the tour  [  Next   ] |   primary disabled: outline, not a grey slab
| Back                                                        [ Looking… ] |   waiting: disabled primary with a spinner
| Back                                                        [ Let's go! ] |   finale: same place
```

- Left: Back, or the lock label. Text starts at x 48 in both. 13 pt soft ink. One line, middle truncation, max 260 pt.
- Right: primary, right edge x 672, 32 pt tall, min width 72 pt (so "Next" and "Got it" are not 61.5 and 67).
- Quiet link: 8 pt left of the primary, first-baseline aligned, one line, middle truncation.
- Never a bar without a primary. An error's fix ("Open Bluetooth Settings", "Try again") is the primary.

### C3. Progress marks

```
today (9):   ''  ''  ''  ''  "  ..  ..  ..  ..      5 x 8 capsules, current x1.35, unwalked 1.54:1
proposed:    ''  ''  ''  ''  "  ''  ''  ''  ''      6 x 10 capsules, current x1.5 + a 3 pt dot under it,
                             .                      unwalked in inkFaint (2.66:1 / 3.62:1), fixed 20 pt box
with 5 acts: ''    ''    "    ''    ''              7 x 11 capsules, 22 pt between pairs
                         .
```

### C4. A sketch of the 5 acts (for later)

```
1 Hello            2 Name             3 Body                4 Agents              5 All set
HERO               HERO               HERO then LIST        LIST                  HERO
+--------------+   +--------------+   +----------------+    +----------------+    +--------------+
|   (bubble)   |   |   [face]     |   |    [face]      |    |[f] Which agents|    |   [face]     |
|   [face]     |   | What should  |   | Let's find my  |    | [Claude] [Codex]|   | Mochi is set |
| demo strip:  |   | I be called? |   | body           |    | > what's added |    | world: on    |
| term + 3     |   | [  Mochi   ] |   | -> looking     |    | -> Say hi      |    | (2 lists)    |
| cards (old   |   | for keeps;   |   | -> found       |    | -> tour, 4 rows|    | login  [sw]  |
| act 2)       |   | the world    |   | -> 4 lessons,  |    |                |    | mic    [Allow]|
|              |   | sees it      |   |    one at a    |    |                |    | brain  [key] |
| [Hi, Boop!]  |   | [That's me]  |   |    time        |    | [Connect]      |    | [Let's go!]  |
+--------------+   +--------------+   +----------------+    +----------------+    +--------------+
```

- Act 1 takes old acts 1 and 2: the buddy drops in, then the demo plays under it. The mood legend goes here, in the demo.
- Act 3 takes old acts 4 and 5. Show one lesson at a time in the hero slot (the lesson's title as the act title, the board's face above it), not four rows. That removes ONB-1 and ONB-35 at the root.
- Act 5 takes old acts 7, 8 and 9. The world lists become one card with a switch ("In the world: on"), beside login and mic as rows with one control column. The four tips move to the menu's first open, or stay as one line under the title.

---

## D. What stills can not show

- **Transitions between acts** (60 pt slide plus fade, `OV:28-30`). With the title and face at different y in each act (ONB-2, ONB-3), the slide will look like a jump cut. Not visible in stills.
- **The frame jump in act 5 as it happens**: the rows change height when a lesson is done (ONB-1). Stills show the end positions only; live, the footprints and button will slide with a spring (`OV:179`).
- **Every face in the big tiles is the same happy still.** The snapshot feed uses one image (`Snapshots.swift:270`), so "napping" in act 4, "curious" while looking, "excited" at the finale and the six demo looks of act 2 all show the same face. I could not judge whether the mood fits the words (ONB-28). The mood tiles of act 5 are real.
- **Act 2's demo**: word drops, the FAIL hail, the progress bar on the lit card (hidden when still, `OI:204`), the amber ring fading in and out, and whether 2.2 to 3.6 s per beat is readable.
- **Act 1's drop-in**, the bubble's pop, and the hop on each keystroke in act 3.
- **Ripples moving** (2.4 s laps), the jump to the desk in act 4 (the on-screen buddy flies to x +300, y +120: that is off the window's right edge, not toward the desk drawing), confetti.
- **Focus, hover and pressed states**: the name field's 1.5 pt focus border, the selection colour (ONB-22), quiet buttons' hover fill, the keyboard focus ring on switches and cards, and the default-button behaviour of Return in act 7 with the key field focused.
- **The live board steps**: whether the "waiting…" row keeps up with the board, the delay between a tap on the board and the tick, the practice amber in lesson 4.
- **The title bar**: the window is titled with a transparent title bar (`MenuBarApp.swift:813-815`). Stills do not show it. If traffic lights are present they sit at about x 7 to 60, y 6 to 20, clear of the footprints (x 245 to 475) except that act 5's footprints rise into that band.
- **The scroller's style** in the hooks panel depends on the Mac's setting (always, or when scrolling). The stills show the always-on one.
- **States with no picture**: see ONB-65.

## Totals

64 findings and notes: 2 broken (ONB-1, ONB-54), 27 rough, 31 nit, 4 notes. Most are S. The M items (ONB-1 to ONB-4, ONB-27, ONB-40, ONB-45, ONB-64) are one piece of work: the shared `ActFrame` in section C.
