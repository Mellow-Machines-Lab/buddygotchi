# Design system audit: Boop's tokens and how far the Mac views follow them

- `census.py` and its output `census.md` (every value → count → examples)
- `contrast.py` and its output `contrast.md` (113 pairs, light and dark)
- `changes.py` and its output `changes.md` (177 places, file:line, old → new)
- `sketch.css`, `sketch-body.html` (the sketch's CSS and markup, images removed)

No repo file was changed. No app was launched. Sizes of hit targets and the focus ring come from the code, not from pixels.

## 15-line summary

1. Colour tokens are followed well: 243 references go through `Theme`; only 4 raw hex literals, 1 `Color(white:)` and 9 direct `Palette.*Dark` reads bypass it.
2. Spacing tokens are followed poorly: 36 of 148 `spacing:` values (24%) and 18 of 95 `.padding` calls (19%) use a token.
3. 17 literal padding values are in use, with one-offs 5, 9, 11, 13 beside 4, 8, 12; `gapSnug + 2` is bent into a tenth value 6 times; `gutter` and `gapLoose` are both 18.
4. There are no type tokens beyond `.boop(size, weight)` and `.caption()`: 141 `.font` calls, 17 text sizes (8 to 30, with 10.5 and 12.5), 5 weights, 0 semantic styles.
5. Radii: 3 tokens (12/8/6) but 8 values in use; 7 (row button, fields) and 10 (prominent button) have no token.
6. `Card` is used at 4 paddings (0, 10, 12, 14), and 9 other containers are built by hand; there are 9 row recipes, 6 section headings, 5 chips, 4 link looks, 8 ways to show a notice.
7. Every `*Ink` text tone passes 4.5:1 on paper, card, well, chip and the amber card (lowest: light `inkSoft` on its chip, 4.61).
8. Text that fails: `inkFaint` used as real text, 2.66:1 light / 3.62:1 dark: "Feeling" and "· Level N" (OverviewPane.swift:174, :177), "TRY" (OnboardingBoard.swift:334), the out-of-world "you" (WorldBand.swift:154).
9. Graphics that fail in light mode: all four lane bars (1.29 to 2.18), amber bar and dot (1.57, 1.71), the ring's blush arc (2.54), every World band dot (1.44 to 2.53 by day, 1.01 to 1.78 at night). Dark mode passes almost all.
10. Control edges fail 3:1 in both modes: off switch track 1.41 / 1.64, slider groove the same, outlined button and field edges the same.
11. The existing check (`Snapshots.checkContrast`, internal/app/Boop/Snapshots.swift:1036) tests 58 palette pairs. It skips `inkFaint`, every graphic colour, the terminal card, opacity, and the rendered pixels.
12. Three colours mean two things: amber (needs you; a buddy shipping), sage (on/ok/full; a resting buddy; one link), lane teal/lilac (a session's slot; coding/testing). "Waiting" is amber in Now and blush in World. The World band has no key.
13. Against the sketch: every text size shipped 0.5 to 2 pt smaller (body 12 vs 13.5); ring 96 vs 120; band 96 high vs about 207; gutters 18 vs 14 to 16; the sketch used one radius (10), the app uses three plus two literals.
14. Proposed: spacing 2/4/8/12/16/24, 8 type sizes with names, 4 weights, radii 12/8/6, one `Card` with three named paddings, one row (h12 v8, icon 20), one `Chip`, one button family with a 24 pt minimum. 177 value changes listed in `changes.md`, plus 19 structural ones.
15. Accessibility: all 6 icon-only buttons have labels (3 lack a tooltip); all sizes are fixed; 12 kinds of control are under 24 pt (Dismiss 42 × 13, switch 28 × 16, Pin and Forget 20 high and 6 apart); no code draws a focus state for any custom button.

Paths below are relative to `app/Boop/Views/` in the worktree `/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish` unless they say otherwise.

---

## 1. The tokens that exist (`Theme.swift`)

### 1.1 Colours

`Palette` holds the hex strings (Theme.swift:14-41). `Theme` makes adaptive `Color`s from them (Theme.swift:43-84).

| Token | Light | Dark | Defined | Refs in views | Stated meaning |
| --- | --- | --- | --- | --- | --- |
| `paper` | #FAF7F2 | #1B1815 | :15, :50 | 12 | The ground |
| `raised` | #F3EDE3 | #24211C | :16, :51 | 4 (+ every `Card`) | A card |
| `well` | #EBE3D6 | #2C2822 | :17, :52 | 9 | A sunken track: tabs, picker, ring track, band, header chips |
| `hairline` | #E4DACA | #38332B | :18, :53 | 7 | Card edge, dividers |
| `hairlineStrong` | #D6C8B2 | #4A4339 | :19, :54 | 13 | Control edges, off switch, slider groove, idle bar |
| `ink` | #24211C | #F2EBE0 | :20, :56 | 24 | Text |
| `inkSoft` | #675F53 | #ADA396 | :21, :57 | 85 | Secondary text, working dot |
| `inkFaint` | #A29888 | #787064 | :22, :58 | 12 | "Decoration and disabled things only" (:12-13) |
| `amber` | #FFB000 | same | :25, :60 | 11 | "One amber accent, for needs you only" (:7-8) |
| `amberInk` | #82540F | #E8B970 | :25, :61 | 4 | Amber as text |
| `menuAmberLight` | #B87400 | n/a | :27 | 1 (BoopFace.swift:234) | Menu-bar icon on a light bar |
| `sage` | #6E9B5E | same | :28, :62 | 10 | "Connected and on" (:8-9) |
| `sageInk` | #466638 | #A3CC90 | :28, :63 | 8 | Sage as text |
| `clayInk` | #9C3B2E | #F09384 | :29, :64 | 24 | "Trouble" (:9). There is no base `clay`. |
| `glass` | #000000 | same | :35, :70 | 3 | The face tile |
| `fill` / `fillPressed` / `fillLabel` | #000000 / #2A2620 / #E8DCC4 | #E8DCC4 / #CFC2A8 / #000000 | :79-81 | 2 each (Theme only) | The filled button |
| `terminal` / `terminalEdge` | #24211C / #38332B | same | :74-75 | 1 each | A card dark in both appearances |
| `blush` | #F1787D | same | :36, :84 | 3 | "The designs' coral cheeks" (:31-32). Also the ring. |
| `recording` | #FF3B30 | same | :68 | 1 | Mic on. A hex literal inside `Theme`, not in `Palette`. |
| `lane(0…3)` | #3AD2CE, #FF8ADE, #B58EFF, #9CE763 | same | :40, :66 | 3 | Work-stream lanes by slot. "Only bars wear them" (:38-39). |
| `chipTint`, `cardTint` | 0.12, 0.08 | same | :83 | 1 each | Tint under a chip; under a toned card |

No token exists for: a toned card's edge (0.45, Theme.swift:170), disabled opacity (0.4, four places), any shadow, the knob's white.

### 1.2 Type

| Token | What it is | Defined |
| --- | --- | --- |
| `Font.boop(size, weight = .semibold)` | SF Rounded at any size | Theme.swift:107-109 |
| `View.caption()` | system 11 regular + `inkSoft` | Theme.swift:295-297 |

That is all. No named sizes, no weights by role, no monospaced style. `PaneSection`'s label (10 semibold, tracking 0.6, uppercased, Theme.swift:228-232) and `StatusChip`'s text (10 medium, Theme.swift:415) are styles in effect, but live inside their components.

### 1.3 Spacing

| Token | Value | Defined | Uses in views |
| --- | --- | --- | --- |
| `gapTight` | 4 | :88 | 1 (Theme.swift:187 only) |
| `gapSnug` | 8 | :89 | 30, of which 6 are `gapSnug + 2` |
| `gap` | 12 | :90 | 6 |
| `gutter` | 18 | :87 | 9, of which 3 are `gutter - 8` or `gutter - 4` |
| `gapLoose` | 18 | :91 | 4. Same value as `gutter`. |
| `gapSection` | 20 | :92 | 5 |
| `windowGutter` | 48 | :95 | 1 |
| `width` | 360 | :101 | 1 |

Theme.swift:86 says "One spacing scale, so margins can't drift a point or two per view." Section 2 shows the drift happened.

### 1.4 Radii

`cardRadius` 12 (:97, 7 uses), `wellRadius` 8 (:98, 8 uses), `chipRadius` 6 (:99, 5 uses).

### 1.5 Shadows

No token. Four shadows exist, all different (section 2.5).

### 1.6 Motion

`Animation.boopEase(d = 0.3)` (:115, 3 uses), `boopSettle` (:120, 26 uses), `boopPop` (:123, 13 uses), `EnvironmentValues.stillMotion` (:131-138). Seven more one-off springs and eases sit in onboarding (OnboardingIntro.swift:48, :50, :52, :307, :308; OnboardingModel.swift:237; OnboardingBoard.swift:175).

### 1.7 Components and styles in `Theme.swift`

| Name | Recipe | Line |
| --- | --- | --- |
| `Card(padding: 12, tone: nil)` | padding, `raised` (or tone at 0.08 over `raised`), radius 12, 1 pt `hairline` (or tone at 0.45) | :157-172 |
| `NoteCard(text)` | `Card` + 12 regular `inkSoft` | :143-153 |
| `PaneTitle` | chevron 12 semibold in `.quiet` + `boop(16)`; padding h `gutter-8`, top `gutter-4`, bottom `gap` | :177-201 |
| `PaneSection(label)` | label 10 semibold, tracking 0.6, uppercased, `inkSoft`, leading 2; gap 8 | :217-237 |
| `DayRow` | 10 medium `inkSoft` over 12 regular; gap 2 | :204-215 |
| `MoreDetails` | "Details" plain button 11 medium `inkSoft` | :240-266 |
| `Hairline`, `RowDivider` | 1 pt `hairline`; inset leading 40, trailing 12 | :280-291 |
| `fieldBox(fill, radius, focus)` | fill + 1 pt `hairlineStrong`, 1.5 pt `inkSoft` on focus | :303-309 |
| `StateDot(tone, pulsing)` | 7 pt dot, 16 pt pulse ring | :314-327 |
| `StatusChip(text, tone)` | 10 medium in tone; h7 v3; tone at 0.12; radius 6 | :409-420 |
| `QuietButtonStyle` (`.quiet`) | `inkSoft` → `ink` on hover; h8 v4; radius 6; `well` on hover. Sets no font. | :424-439 |
| `OpensButtonStyle(radius)` | `inkFaint` 1 pt edge on hover; scale 0.99 pressed | :443-457 |
| `ProminentButtonStyle(wide)` | 13 semibold; h16 v8; radius **10**; `fill`; 0.4 disabled | :462-479 |
| `RowButtonStyle(filled)` (`.row`, `.rowFilled`) | 11 medium; h10 v4; radius **7**; `paper` + `hairlineStrong`, or `fill`; 0.4 disabled | :483-503 |
| `SwitchStyle(height)` (`.boop` 16, `.boopLarge` 22) | capsule 1.75 × height; `sage` on, `hairlineStrong` off; white knob | :508-532, :584-589 |
| `StepSlider` | groove 4, knob 14, frame height 18; `ink` fill | :538-582 |

Reused but outside `Theme.swift`: `SettingRow` (SettingsPane.swift:459-487), `RowPicker` (:402-455), `TabBar` (OverviewPane.swift:797-832), `SessionRow` (:674-761), `Opens` (:559-582), `Ring` (BoopPane.swift:105-121), and onboarding's `StepRow`, `Bubble`, `ActTitle`, `ActNav`, `ActBack`, `terminalCard()`, `Footprints` (Onboarding/OnboardingView.swift).

---

## 2. Usage census

Command: `python3 system/census.py [pad|font|radius|frame|opacity|color|a11y]`. It reads the 22 Swift files, skips comment lines, and counts regex matches. Full tables with every example: `system/census.md`. Digest here.

### 2.1 Padding (95 `.padding(...)` calls)

| How the value is given | Count |
| --- | --- |
| A `Theme` token alone | 15 |
| A `Theme` token with arithmetic (`gutter - 8`, `gutter - 4`, `gapSnug + 2`) | 4 |
| A local constant (`Self.edge`, `Self.headerGap`, `padding`, `width / 2`) | 5 |
| A numeric literal | 69 |
| A conditional of literals (`compact ? 6 : 10`, `touring ? 14 : 18`) | 2 |

| Value | Count | Example | Flag |
| --- | --- | --- | --- |
| -6, -4 | 3 | OverviewPane.swift:538, Onboarding/OnboardingIntro.swift:151 | negative, to pull an xmark into a corner |
| 1 | 1 | OverviewPane.swift:756 | one-off |
| 2 | 13 | BoopPane.swift:94, MemoryPane.swift:22, SettingsPane.swift:450 | 8 are `.leading, 2`, to line loose text up with a card's edge |
| 3 | 4 | Theme.swift:417, OverviewPane.swift:206, :268, Onboarding/OnboardingBoard.swift:349 | chip vertical; beside 4 |
| 4 | 3 | Theme.swift:432, :493, OverviewPane.swift:812 | = `gapTight`, never written as the token |
| 5 | 1 | OverviewPane.swift:812 | **one-off beside 4 and 6** |
| 6 | 5 | BoopPane.swift:44, OverviewPane.swift:529, :756, WorldPane.swift:149 | no token |
| 7 | 7 | OverviewPane.swift:206, :753, SettingsPane.swift:435, WorldPane.swift:259 | **beside 8** |
| 8 | 7 | SettingsPane.swift:359, OverviewPane.swift:753, PopoverView.swift:72 | = `gapSnug`, as a literal |
| 9 | 2 | SettingsPane.swift:485, Onboarding/OnboardingView.swift:196 | **one-off beside 8 and 10** |
| 10 | 4 | SettingsPane.swift:391, :435, Theme.swift:493, Onboarding/OnboardingFinish.swift:124 | no token |
| 11 | 1 | Onboarding/OnboardingIntro.swift:299 | **one-off beside 12** |
| 12 | 7 | SettingsPane.swift:319, :391, :485, WorldPane.swift:251, :259, Theme.swift:289 | = `gap`, as a literal |
| 13 | 1 | OverviewPane.swift:753 | **one-off beside 12** |
| 14 | 3 | Onboarding/OnboardingView.swift:177, :196, OnboardingIntro.swift:210 | onboarding only |
| 16 | 3 | Theme.swift:470, Onboarding/OnboardingIntro.swift:179, OnboardingView.swift:20 | no token |
| 18 | 1 | WorldPane.swift:113 | room for the xmark |
| 30 | 1 | Onboarding/OnboardingIntro.swift:29 | = `OnboardingView.edge`, as a literal |
| 40, 56 | 2 | Theme.swift:289, Onboarding/OnboardingBoard.swift:343 | derived indents |

`Card(padding:)` adds 0 (10 sites), 10 (3), 12 default (10), 14 (10). See 3.1.

### 2.2 `spacing:` (148 values)

| Value | Count | Example | Flag |
| --- | --- | --- | --- |
| 0 | 20 | OverviewPane.swift:16 | fine |
| 1 | 2 | WorldPane.swift:87, Onboarding/OnboardingFinish.swift:407 | **one-off beside 2** |
| 2 | 16 | OverviewPane.swift:335, SettingsPane.swift:474 | title over detail. No token. |
| 3 | 11 | OverviewPane.swift:121, :173, :781, BoopPane.swift:37, WorldBand.swift:29 | **the same title-over-detail gap, as 3** |
| 4 | 9 | OverviewPane.swift:135, :196, BoopPane.swift:63 | = `gapTight`, never the token |
| 5 | 3 | OverviewPane.swift:240, :454, Onboarding/OnboardingFinish.swift:164 | **beside 4 and 6** |
| 6 | 16 | OverviewPane.swift:127, :456, :648, MemoryPane.swift:52, SettingsPane.swift:106 | no token; the second most used literal |
| 8 | 5 | OverviewPane.swift:230, SettingsPane.swift:315 | = `gapSnug`, as a literal |
| `Theme.gapSnug` | 21 | MemoryPane.swift:49 | token |
| 10 | 6 | Onboarding/OnboardingFinish.swift:375, :405, OnboardingBrainKey.swift:19 | no token |
| `Theme.gapSnug + 2` | 5 | OverviewPane.swift:333, :400, :438, :521, SettingsPane.swift:469 | **a token bent to make 10**: icon to text |
| 12 | 6 | Onboarding/OnboardingFinish.swift:40 | = `gap`, as a literal |
| `Theme.gap` | 3 | OverviewPane.swift:112 | token |
| 14 | 9 | Onboarding/OnboardingBoard.swift:144, OnboardingView.swift:71, :154 | onboarding's own step, beside 12 and 16 |
| 16 | 3 | Onboarding/OnboardingBoard.swift:24, :74, OnboardingFinish.swift:370 | |
| 18 | 3 | Onboarding/OnboardingBoard.swift:37, OnboardingFinish.swift:159, OnboardingIntro.swift:142 | |
| `Theme.gapLoose` | 1 | BoopPane.swift:28 | token (18) |
| `Theme.gapSection` | 5 | OverviewPane.swift:42 | token (20) |
| 22 | 1 | Onboarding/OnboardingIntro.swift:144 | **one-off beside 24** |
| 24 | 1 | Onboarding/OnboardingIntro.swift:18 | one-off |
| `Theme.gapTight` | 1 | Theme.swift:187 | token |
| `touring ? 8 : 12` | 1 | Onboarding/OnboardingFinish.swift:158 | |

Token use: 36 of 148 (24%); 36 of 128 without the zeros (28%). Distinct non-zero gaps in use: 1, 2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24. That is 15 steps where the scale names 5. Onboarding uses a `Theme` spacing token 4 times (OnboardingBoard.swift:333, :386; OnboardingBrainKey.swift:39; OnboardingFinish.swift:102).

### 2.3 Fonts (141 `.font(...)` calls)

| Face | Count |
| --- | --- |
| System, fixed size | 114 |
| System monospaced | 6 (OverviewPane.swift:636, :745; OnboardingFinish.swift:104, :107, :116; OnboardingIntro.swift:178) |
| Rounded (`.boop`) | 21 |
| Through `.caption()` | 19 more (WorldPane 9, OverviewPane 5) |
| Semantic text styles | 0 |
| `.monospacedDigit()` | 3 (BoopPane.swift:33, SettingsPane.swift:111, WorldPane.swift:91) |

Sizes (text only; the census's 96 to 236 are face sizes):

| Size | Count | Example | Flag |
| --- | --- | --- | --- |
| 8 | 1 | OverviewPane.swift:262 | **one-off**: an xmark in the hush chip |
| 9 | 4 | OverviewPane.swift:535, WorldPane.swift:146, WorldBand.swift:156, :164 | xmarks, "you", region names |
| 10 | 13 | Theme.swift:210, :229, :415, MemoryPane.swift:57, SettingsPane.swift:383 | labels, chips, and one whole paragraph (SettingsPane.swift:383) |
| 10.5 | 2 | OverviewPane.swift:636, :745 (mono) | **half-point beside 10 and 11** |
| 11 | 24 (+19 by `.caption()`) | SettingsPane.swift:476 | caption |
| 12 | 57 | everywhere | body |
| 12.5 | 2 | Onboarding/OnboardingFinish.swift:66, OnboardingIntro.swift:178 | **half-point beside 12 and 13** |
| 13 | 15 (12 system, 3 rounded) | Theme.swift:468, WorldPane.swift:109, OverviewPane.swift:402 | onboarding body; in the popover, 2 icons and 1 name |
| 14 | 5 (2 system, 3 rounded) | OverviewPane.swift:439, Onboarding/OnboardingView.swift:213 | |
| 15 | 6 (2 system, 4 rounded) | Onboarding/OnboardingIntro.swift:31, OnboardingBrainKey.swift:22 | |
| 16 | 2 rounded | Theme.swift:194, Onboarding/OnboardingFinish.swift:135 | **beside 15 and 17** |
| 17 | 2 rounded (+1 in a `ViewThatFits`, WorldPane.swift:90) | Onboarding/OnboardingView.swift:194, OnboardingFinish.swift:166 | **beside 16 and 18** |
| 18 | 3 rounded | OverviewPane.swift:123, BoopPane.swift:38, Onboarding/OnboardingBoard.swift:217 | |
| 20 | 1 rounded | Onboarding/OnboardingIntro.swift:296 | **one-off** |
| 26 | 1 rounded | Onboarding/OnboardingView.swift:210 | act title |
| 28 | 1 rounded | BoopPane.swift:33 | ring number |
| 30 | 1 rounded | Onboarding/OnboardingFinish.swift:374 | **one-off beside 26 and 28** |

17 distinct text sizes. Rounded alone has 10 sizes for 21 uses.

Weights: regular 76 (system, no weight given); medium 18 (+2 `on ? .semibold : .medium`); semibold 15 system + 2 rounded (`.boop`'s default); bold 5 system (icons only: xmark 8 and 9, checkmark 10 and 12) + 17 rounded; heavy 2 rounded (OnboardingBoard.swift:217, OnboardingFinish.swift:374). `.boop`'s default weight is used only twice; so "Level 12" is `boop(18, .bold)` (BoopPane.swift:38) and the name beside the face is `boop(18)` semibold (OverviewPane.swift:123).

The same role at different sizes or weights:

| Role | Variants |
| --- | --- |
| A card's title line | 12 semibold (OverviewPane.swift:336, :407, :524, :782), 12 medium (:441, :733, SettingsPane.swift:475), 13 semibold (WorldPane.swift:109) |
| Soft body line | 12 regular `inkSoft`, hand-written 25 times with no name |
| Caption | `.caption()` 19 times; the same 11 + `inkSoft` hand-written 5 times (OnboardingBoard.swift:348, :390; OnboardingFinish.swift:111, :115, :120) |
| Small print under the key field | 10 regular (SettingsPane.swift:383) against 12 regular for the same field in onboarding (OnboardingBrainKey.swift:36) |
| Icon beside a title | 12 (OverviewPane.swift:334, SettingsPane.swift:471), 13 (OverviewPane.swift:402, :522), 14 (:439), 15 (OnboardingFinish.swift:406), 11 (WorldPane.swift:219) |
| Close or dismiss xmark | 8 bold (OverviewPane.swift:262), 9 bold (:535, WorldPane.swift:146), 10 regular (MemoryPane.swift:63) |
| Monospaced | 10.5, 11, 12.5 |

### 2.4 Corner radii

| Value | Count | Where | Flag |
| --- | --- | --- | --- |
| `Theme.cardRadius` (12) | 7 | Theme.swift:167-169, OverviewPane.swift:373, Onboarding/OnboardingView.swift:267-268, OnboardingIntro.swift:214 | token |
| 12 literal | 1 | Onboarding/OnboardingIntro.swift:300 | the token's value, as a literal |
| 10 | 3 | Theme.swift:473, :477 (prominent button), Onboarding/OnboardingFinish.swift:76 | **between 8 and 12; no token** |
| `Theme.wellRadius` (8) | 8 | OverviewPane.swift:463, :754, :758, :830, SettingsPane.swift:451, WorldBand.swift:54-55, OnboardingFinish.swift:126 | token |
| 7 | 5 | Theme.swift:494, :496, :499 (row button), SettingsPane.swift:361, OnboardingBrainKey.swift:44 (fields) | **beside 8 and 6; no token** |
| `Theme.chipRadius` (6) | 5 | Theme.swift:418, :433, :435, OverviewPane.swift:816-817 | token |
| 6 literal | 3 | SettingsPane.swift:438, :440, OnboardingBoard.swift:222 | the token's value, as a literal |
| 3, 2 | 3 | OnboardingBoard.swift:237; OverviewPane.swift:756, OnboardingView.swift:301 | small decorations |
| 16 and 4 | 1 | Onboarding/OnboardingView.swift:197 (speech bubble) | |
| `size * 0.27` | 6 | BoopFace.swift:78, :80, Slime/SlimeStills.swift:95, :101, Slime/SlimeView.swift:52 | the face tile |
| `Capsule()` | 11 | header chips, switch, slider, footprints | |

The face tile uses `style: .continuous` in `BoopFace` (BoopFace.swift:78) and `MoodTile` (SlimeStills.swift:95), but the default circular corner in `SlimeFace` (SlimeView.swift:52). The two faces swap in the same header slot (OverviewPane.swift:114-119), so the corner changes shape with them.

### 2.5 Line widths and shadows

`lineWidth`: 1 (10 times: every edge); 1.5 (focused field, Theme.swift:307; picked buddy, WorldBand.swift:43); 0.5 (slider knob, Theme.swift:554); 2 (ripple, OnboardingView.swift:330); 5 (amber ring, OnboardingIntro.swift:150); `max(1.5, size * 0.04)` (needs-you face edge, BoopFace.swift:82); ring strokes 9 and 4 (BoopPane.swift:29, :64).

| Shadow | Where |
| --- | --- |
| black 0.06, radius 1, y 1 | chosen tab (OverviewPane.swift:818) |
| black 0.2, radius 1, y 0.5 | switch knob (Theme.swift:522) |
| black 0.22, radius 1.5, y 0.5 | slider knob (Theme.swift:555) |
| black 0.16, radius 14, y 8 | onboarding's Boop (OnboardingView.swift:128) |

The two knobs are the same object with two shadows. The chosen segment has a shadow in `TabBar` and none in `RowPicker` (SettingsPane.swift:438-441).

### 2.6 Frames for icons and controls

| Thing | Size | Where |
| --- | --- | --- |
| Icon column in a row | 18 wide | OverviewPane.swift:334, :404, :457, :522, SettingsPane.swift:473 |
| Icon column, arrivals | **16** | WorldPane.swift:219 |
| Icon column, onboarding tip | **20** | Onboarding/OnboardingFinish.swift:406 |
| "No agents awake" icon | no frame | OverviewPane.swift:439 |
| State dot | 7 × 7 | Theme.swift:323 |
| Device and buddy dots | **6 × 6** | OverviewPane.swift:223, :242 |
| Switch | 28 × 16 (`.boop`), 38.5 × 22 (`.boopLarge`) | Theme.swift:518, :586, :588 |
| Slider | 84 × 18, knob 14 | SettingsPane.swift:108, Theme.swift:544, :574 |
| Field height | 22 in Settings, **24** in onboarding | SettingsPane.swift:360, OnboardingBrainKey.swift:43 |
| Step number disc | 24 or 28 | Onboarding/OnboardingView.swift:163 |
| Face tile | 46 popover; 44 legend; 84 to 236 onboarding | OverviewPane.swift:153, OnboardingBoard.swift:370 |
| Ring | 96 (stroke 9); 26 (stroke 4) | BoopPane.swift:29-30, :64-65 |
| World band | 96 high | WorldBand.swift:23 |
| Tab bar | 36 with its gap | OverviewPane.swift:800 |

### 2.7 Opacity literals

| Value | Where | Role |
| --- | --- | --- |
| 0.4 | Theme.swift:474, :498, :524, :575; OverviewPane.swift:690 | disabled ×4; the dismissed session's amber bar ×1 |
| 0.6 | OnboardingFinish.swift:148; BoopFace.swift:81; WorldBand.swift:38 | **a second "disabled" (agent not found)**; tile edge; own ring |
| 0.7 | BoopFace.swift:95, :101; WorldBand.swift:135 | asleep |
| 0.55 | OnboardingIntro.swift:206; WorldBand.swift:135 | progress bar; asleep dot (dark) |
| 0.45 | Theme.swift:170 | toned card's edge |
| 0.35 / 0.25 | WorldBand.swift:155 | the "you" line |
| 0.8 / 0.2 | WorldBand.swift:118 | night shade |

### 2.8 Colours not from `Theme`

| Colour | Where | Note |
| --- | --- | --- |
| `Color(hex: "#3A9BF0")` | Onboarding/OnboardingView.swift:289 | a blue confetti piece; the only blue in the app |
| `Color(hex: "#05070D")`, `"#3B3328"` | WorldBand.swift:118 | the band's night, dark and light |
| `Color(white: 0.92)` | BoopFace.swift:152 | the fallback eyes; near `oat` but not it |
| `.white` | Theme.swift:520, :553 | knobs |
| `.black.opacity(…)` | Theme.swift:522, :554, :555, OverviewPane.swift:818, OnboardingView.swift:128 | shadows |
| `Color(hex: Palette.inkDark / inkSoftDark / sageInkDark / clayInkDark / amberInkDark / oat)` | OnboardingIntro.swift:83-88; OnboardingFinish.swift:166, :170, :173 | 9 direct `Palette` reads for text on the terminal card. `Theme` has `terminal` and `terminalEdge` but no inks for it. |
| `#151515` as `NSColor(red:…)` | app/Boop/BoardWindow.swift:119 | the simulator window's ground |
| `Color(hex: "#FF3B30")` | Theme.swift:68 | the one `Theme` colour that skips `Palette` |

`FaceDesigns.colors` (BoopFace.swift:125-127) are the pack's own face colours and are correctly outside `Theme`. `MenuBarApp.swift` sets no colour, font, padding or radius.

---

## 3. Components built more than one way

### 3.1 Card: 4 paddings of `Card`, and 9 recipes that are not `Card`

| `Card` padding | Count | Where |
| --- | --- | --- |
| 12 (default) | 10 | Theme.swift:148 (`NoteCard`, used 8 times); MemoryPane.swift:48, :75; OverviewPane.swift:330, :399 (amber), :437, :520, :780; WorldPane.swift:63, :106 |
| 0 (rows inside) | 10 | SettingsPane.swift:30, :31, :58, :102, :131, :192, :265, :313; WorldPane.swift:248; Onboarding/OnboardingView.swift:153 |
| 10 | 3 | BoopPane.swift:85 (a note), WorldPane.swift:86 (a number tile), :216 (an arrival) |
| 14 | 10 | OnboardingBoard.swift:163, :181; OnboardingBrainKey.swift:18; OnboardingFinish.swift:25, :132, :300, :336, :404; OnboardingIntro.swift:195; OnboardingWorld.swift:35 |

The same note is a `Card` at 12 in What Boop knows (MemoryPane.swift:48) and at 10 in the Boop tab's peek (BoopPane.swift:85). `NoteCard("Nothing yet today.")` at 12 sits directly above arrival cards at 10 (WorldPane.swift:213, :216).

Containers built by hand:

| # | Recipe | Where |
| --- | --- | --- |
| 1 | `raised`, radius 8, 1 pt `hairline`, padding lead 13 / trail 8 / v7 | `SessionRow`, OverviewPane.swift:753-758 |
| 2 | `terminal`, radius 12, 1 pt `terminalEdge`; padding 16, or 14/18 | `terminalCard()`, OnboardingView.swift:266-269; used OnboardingIntro.swift:179-182, OnboardingFinish.swift:178-179 |
| 3 | `well`, radius **10**, no edge, padding 12 | the hooks list, OnboardingFinish.swift:74-76 |
| 4 | `paper`, radius 8, no edge, padding 10 | each agent's additions inside #3, OnboardingFinish.swift:124-126 |
| 5 | `raised`, radius 12 literal, `hairlineStrong`, v11 | the name field, OnboardingIntro.swift:299-300 |
| 6 | `well`, radius 8, 1 pt `hairline`, clipped | the world band, WorldBand.swift:53-55 |
| 7 | `well`, radius 8, no edge, padding 2 | `TabBar` (OverviewPane.swift:828-830) and `RowPicker` (SettingsPane.swift:450-451) |
| 8 | `ink` fill, uneven radius 16/4, h14 v9 | `Bubble`, OnboardingView.swift:196-198 |
| 9 | `glass`, radius 0.27 × size | the face tile |

### 3.2 Row: 9 kinds in the popover, 2 in onboarding

| Row | Padding | Icon column | Gap | Title / detail | Where |
| --- | --- | --- | --- | --- | --- |
| `SettingRow` (14 uses) | h12, v**9** | 12 pt icon, 18 wide | 10 | 12 medium / 11 | SettingsPane.swift:468-486 |
| `SessionRow` | lead **13**, trail 8, v**7** | a 3 pt bar | 8 | 12 medium / mono 10.5 | OverviewPane.swift:728-759 |
| `RowPicker` row | h**10**, v**7** | none; a 10 bold tick at the end | 8 | 12 semibold or medium / 11 | SettingsPane.swift:421-435 |
| Region row | h12, v**7** | none | default | 12 / 12 `inkSoft` | WorldPane.swift:253-259 |
| Brain key block | h12, v**10** | none | 6, 8 | field / 10 / 11 | SettingsPane.swift:354-391 |
| Talk block | **12** all round, then the picker's own 2 | n/a | 8 | n/a | SettingsPane.swift:315-319 |
| Memory note row | card's 12 | none; two icon buttons | 6 | 12 | MemoryPane.swift:52-68 |
| Dressing row | card's 12 | 12 pt icon, 18 wide | 10 | 12 semibold / 11 | OverviewPane.swift:333-342 |
| Arrival | its own `Card` at 10 | 11 pt icon, **16** wide | 8 | 12 / 11 | WorldPane.swift:216-226 |
| `StepRow` | h14, v10 or 6, in a `Card` at 0 | 24 or 28 disc | 14 | rounded 15 or 14 bold / 12 | OnboardingView.swift:153-177 |
| Tip | `Card` at 14 | 15 pt icon, **20** wide | 10 | rounded 14 bold / 12 | OnboardingFinish.swift:404-413 |

Five vertical paddings for a row in the popover: 7, 9, 10, 12, and the card's 12. Dividers: `RowDivider` in Settings; a bare `Hairline().padding(.horizontal, 12)` for the same job in World (WorldPane.swift:251).

### 3.3 Section heading: 6 kinds

| Heading | Recipe | Where |
| --- | --- | --- |
| `PaneSection` label (16 uses) | 10 semibold, tracking 0.6, `.uppercased()`, `inkSoft`, leading 2 | Theme.swift:228-233 |
| Agent group header in Sessions | 11 semibold, `inkSoft`, icon 18 wide, mixed case, no tracking | OverviewPane.swift:456-461 |
| "HOW I FEEL" | 11 semibold, `inkSoft`, capitals typed in the string, no tracking | OnboardingBoard.swift:273 |
| "TRY" | 10 semibold, **`inkFaint`**, capitals typed, no tracking | OnboardingBoard.swift:334 |
| "FOUND <NAME>" | 12 semibold, tracking 0.6, `sageInk` | OnboardingBoard.swift:110-112 |
| `PaneTitle` / `ActTitle` | rounded 16 semibold / rounded 26 bold + 14 `inkSoft` | Theme.swift:194; OnboardingView.swift:210-214 |

### 3.4 Chip or badge: 5 kinds

| Chip | Text | Padding | Shape | Fill | Where |
| --- | --- | --- | --- | --- | --- |
| `StatusChip` | 10 medium, tone | h7 v3 | radius 6 | tone at 0.12 | Theme.swift:409-420; one caller, OverviewPane.swift:751 |
| Header reminder chip | 10 medium `inkSoft`, icon | h7 v3 | **capsule** | `well` | OverviewPane.swift:203-207 |
| Hush chip (a button) | the same, + 8 bold xmark | h7 v3 | **capsule** | `well` | OverviewPane.swift:265-269 (a copy of the five modifiers above) |
| Sample words | **11** regular `inkSoft` | h**8** v3 | **capsule, stroked**, no fill | none | OnboardingBoard.swift:348-350 |
| "+N more" | 11 medium `amberInk`, no box | none | none | none | OverviewPane.swift:420 |

### 3.5 Button: 4 styles, 4 loose links, 2 segmented controls

| Button | Font | Padding | Radius | Est. height | Where |
| --- | --- | --- | --- | --- | --- |
| `ProminentButtonStyle` (3 uses) | 13 semibold | h16 v8 | **10** | about 32 | Theme.swift:462-479 |
| `RowButtonStyle` (25 uses: 19 `.row`, 4 `.rowFilled`, 2 by init at OverviewPane.swift:284, :302) | 11 medium | h10 v4 | **7** | about 21 | Theme.swift:483-503 |
| `QuietButtonStyle` (10 uses) | **none set**: takes 12 (PopoverView.swift:84), 13 (OnboardingView.swift:237, :254; OnboardingBoard.swift:93), or an icon's 9, 10, 12 | h8 v4 | 6 | 17 to 24 | Theme.swift:424-439 |
| `OpensButtonStyle` (1 use) | the content's | none | 12 or 8, passed in | n/a | Theme.swift:443-457 |
| `.plain` links | "Dismiss" 11 medium `amberInk` (OverviewPane.swift:383-385); "Details" 11 medium `inkSoft` (Theme.swift:253-257); "See everything … ›" 12 semibold `sageInk` (BoopPane.swift:89-93); `Link` "Jev's docs" 12 regular `inkSoft` (OnboardingBrainKey.swift:24-30) | none | none | 13 to 15 | four links, four looks, three colours |
| `TabBar` segment | 12 semibold or medium | h4 v5 | `chipRadius`, `hairline` edge, shadow | about 25 | OverviewPane.swift:806-822 |
| `RowPicker` segment | 12 semibold or medium | h10 v7 | **literal 6**, **`hairlineStrong`** edge, no shadow | 28 and up | SettingsPane.swift:418-445 |

### 3.6 Notice: 8 ways to tell the reader something

| # | Form | Icon | Text | Where |
| --- | --- | --- | --- | --- |
| 1 | `notice(...)` card | 13 pt, tone, 18 wide, top-aligned | 12 semibold + caption, Details, `.row` button, xmark 9 bold | OverviewPane.swift:517-544; 9 call sites (:48, :52, :60, :68, :73, :82, :434, :490, :503) |
| 2 | Needs-you card | 13 pt `amberInk`, 18 wide | 12 semibold, 11 medium, caption; "Dismiss" laid over the corner | OverviewPane.swift:396-425, :377-389 |
| 3 | "No agents awake" card | **14** pt `inkFaint`, no frame, centre-aligned | 12 **medium** + caption | OverviewPane.swift:437-447 |
| 4 | `NoteCard` | none | 12 regular `inkSoft` | Theme.swift:143-153; 8 uses |
| 5 | Private note | none | 12 regular `inkSoft` + `.row` button | WorldPane.swift:62-73 |
| 6 | Inline `Label` in caption style, leading 2 | 11 pt `inkSoft` | caption | WorldPane.swift:24-26, :31-34; SettingsPane.swift:140-142 |
| 7 | A row's detail line turned `clayInk` or `sageInk` | the row's icon stays `inkSoft` | 11 | SettingsPane.swift:150-166, :195, :246-251, :282-291 |
| 8 | Small print under a field turned `clayInk` | none | **10** | SettingsPane.swift:381-384 |

Two of these change the meaning:

- **A trouble shown as a caption.** "The world isn't answering, so this may be out of date." is form 6, with an outline `exclamationmark.triangle` in `inkSoft` (WorldPane.swift:31). Every other trouble is form 1 with `exclamationmark.triangle.fill` in `clayInk`.
- **One message, two forms.** "Restart your agent sessions" is a card in Now (OverviewPane.swift:73) and a caption `Label` in Settings (SettingsPane.swift:140).

---

## 4. Colour and contrast

Command: `python3 system/contrast.py`. WCAG 2 formula, the same as the app's own check. Tints are composited first. Full output: `system/contrast.md` (113 pairs, each in light and dark, plus the band's night side and the menu bar).

Thresholds: 4.5:1 for text; 3:1 for large text and for graphics that carry meaning.

### 4.1 Text inks on the three surfaces: all pass except `inkFaint`

| Ink | on paper (L / D) | on raised (L / D) | on well (L / D) |
| --- | --- | --- | --- |
| `ink` | 15.01 / 14.93 | 13.77 / 13.55 | 12.60 / 12.37 |
| `inkSoft` | 5.89 / 7.12 | 5.40 / 6.46 | **4.94** / 5.90 |
| `inkFaint` | **2.66 / 3.62 fail** | **2.44 / 3.28 fail** | **2.23 / 3.00 fail** |
| `amberInk` | 6.09 / 9.77 | 5.59 / 8.86 | 5.11 / 8.09 |
| `sageInk` | 6.11 / 9.76 | 5.60 / 8.86 | 5.12 / 8.09 |
| `clayInk` | 6.38 / 7.75 | 5.86 / 7.04 | 5.36 / 6.43 |

| On tints | Light | Dark |
| --- | --- | --- |
| `ink` on the amber card (#F4E8D1 / #362C1A) | 13.23 | 11.55 |
| `inkSoft` on the amber card | 5.19 | 5.51 |
| `amberInk` on the amber card | 5.37 | 7.56 |
| `ink` on its chip ("working") | 10.94 | 9.66 |
| `inkSoft` on its chip ("idle") | **4.61** | 5.23 |
| `amberInk` on its chip ("needs you") | 4.74 | 6.85 |
| `sageInk` on its chip | 4.76 | 6.85 |
| `clayInk` on its chip | 4.91 | 5.66 |
| `inkSoft` on the "now" step card (`ink` 8% over raised) | 4.64 | 5.20 |
| Terminal card (same in both modes) | oat 11.81, `inkSoftDark` 6.46, `clayInkDark` 7.04, `amberInkDark` 8.86, `sageInkDark` 8.86, `inkDark` 13.55 | |

"White on buttons": there is none. The filled button's label is `oat` on `glass` in light (15.47) and `glass` on `oat` in dark (15.47); pressed, 11.07 and 11.94. The only white is the two knobs.

Light `inkSoft` has the least room (4.61 on its chip, 4.94 on the well). It is the most used text colour (85 references), much of it at 10 or 11 pt.

### 4.2 Failures: text

| What | L / D | Needs | Where |
| --- | --- | --- | --- |
| "Feeling" and "· Level 12" in the header, 11 pt, `inkFaint` on paper | **2.66 / 3.62** | 4.5 | OverviewPane.swift:174, :177 |
| "TRY", 10 pt semibold, `inkFaint` on paper | **2.66 / 3.62** | 4.5 | Onboarding/OnboardingBoard.swift:334 |
| "you" on the band when out of the world, 9 pt, `inkFaint` on the well | **2.23 / 3.00** | 4.5 | WorldBand.swift:154-156 |
| Disabled quiet button's label | 2.66 / 3.62 | exempt | Theme.swift:431 |
| Disabled filled button (0.4), label on fill | 2.57 / 3.40 | exempt | Theme.swift:474 |
| Disabled row button (0.4) | 2.44 / 3.49 | exempt | Theme.swift:498 |

The first three break the palette's own rule (Theme.swift:12-13). "Level 12" is information, and that line is the only place the level shows in the header. Disabled states are exempt under WCAG, but "Uninstall…" disabled at 2.44:1 (SettingsPane.swift:274) is still a label a person must read to understand its row.

### 4.3 Failures: graphics that carry meaning (3:1)

| What | Light | Dark | Where |
| --- | --- | --- | --- |
| Session lane bars: teal / rose / lilac / lime | **1.60 / 1.81 / 2.18 / 1.29** | pass (6.3 to 10.7) | OverviewPane.swift:692, :756 |
| Waiting session's amber bar | **1.57** | pass | OverviewPane.swift:691 |
| Dismissed session's bar (amber at 0.4) | **1.22** | **2.54** | OverviewPane.swift:690 |
| Idle session's bar (`hairlineStrong`) | **1.41** | **1.64** | OverviewPane.swift:693 |
| Needs-you state dot, amber on paper | **1.71** | pass | OverviewPane.swift:314 |
| Idle / asleep / stopped state dot, `inkFaint` | **2.66** | 3.62 | OverviewPane.swift:316 |
| Not-connected device dot, `inkFaint` | **2.66** | 3.62 | OverviewPane.swift:223, :241 |
| Connected dot, `sage` on paper | 3.02 (just) | 5.48 | same |
| Ring's blush arc on paper | **2.54** | pass | BoopPane.swift:116 |
| Blush arc against its `well` track | **2.14** | pass | BoopPane.swift:113-116 |
| Full ring's sage arc against its track | **2.53** | pass | same |
| Ring's empty track on paper | **1.19** | **1.21** | BoopPane.swift:113 |
| Needs-you face edge, amber on paper | **1.71** (11.5 against the black tile) | pass | BoopFace.swift:81 |
| Amber ring round the demo face | **1.71** | pass | Onboarding/OnboardingIntro.swift:150 |
| Needs-you card's edge (amber at 0.45) on paper | **1.36** | 3.16 | Theme.swift:170 |
| Step-done tick: `paper` on `sage` | 3.02 (just) | 5.48 | Onboarding/OnboardingView.swift:156-158 |
| `checkmark.circle.fill`, `sage` on a card | **2.77** | pass | Onboarding/OnboardingFinish.swift:347 |
| Band dots, day side: coding / testing / shipping / waiting / resting | **1.46 / 1.99 / 1.44 / 2.14 / 2.53** | pass | WorldBand.swift:140-148 |
| Band dots, night side | **1.03 / 1.40 / 1.01 / 1.51 / 1.78** | pass | WorldBand.swift:118 |
| Asleep dot | **1.71** day, **1.36** night | **2.81** day, 3.10 night | WorldBand.swift:135 |
| "You" line (`ink` at 0.35) | **2.06** | **2.82** | WorldBand.swift:155 |

The pattern: **the board's colours (amber, the lanes, blush, sage) were chosen for black glass. On light paper they sit between 1.0:1 and 3.0:1.** Dark mode passes almost everywhere. Amber for shipping on the band's night side in light mode is 1.01:1: the dot is not there.

The session bars are backed by the status chip's word, so the bar is a second cue. The World band has no such word (section 5).

### 4.4 Failures: control edges (WCAG 1.4.11, 3:1)

| What | Light | Dark | Where |
| --- | --- | --- | --- |
| Switch, off: `hairlineStrong` track on a card | **1.41** | **1.64** | Theme.swift:517 |
| Switch, off: white knob on its track | **1.65** | 9.75 | Theme.swift:520 |
| Switch, on: `sage` track on a card | **2.77** | 4.97 | Theme.swift:517 |
| Slider groove on a card | **1.41** | **1.64** | Theme.swift:551 |
| Slider knob (white) against a card | **1.16** (it relies on its shadow) | pass | Theme.swift:553-555 |
| Slider knob (white) against the `ink` fill | pass | **1.18** | Theme.swift:552-553 |
| Outlined row button's edge on a card | **1.41** | **1.64** | Theme.swift:497 |
| Field's edge on a card | **1.41** | **1.64** | Theme.swift:307 |
| Chosen tab or picker pill (`paper` on `well`) | **1.19** | **1.21** | OverviewPane.swift:816, SettingsPane.swift:439 |

The outlined button and the tabs also say what they are in words, so these weigh less. The off switch is the real one: in light mode it is a pale track with a white knob at 1.65:1, on a card at 1.41:1. Theme.swift:505-507 says the custom switch exists because the system one "looked off" when on. The custom one is now faint when off.

Card and tile edges (`hairline` on paper 1.29 / 1.41; `raised` on paper 1.09 / 1.10; the terminal card on dark paper 1.10) are decoration and need no ratio. They make up most of the 85 sub-threshold lines in `contrast.md`.

### 4.5 The existing check: what it does and does not cover

`Snapshots.checkContrast()` (internal/app/Boop/Snapshots.swift:1036-1068) runs first on every `Boop --snapshots DIR` (Snapshots.swift:18). It builds 58 pairs, fails the run with the list if any is low, and otherwise prints `contrast: 58 pairs pass`.

It covers, in light and dark:

- `ink`, `inkSoft`, `amberInk`, `sageInk`, `clayInk` at 4.5:1 on paper, a card, the well, the tone's own chip over a card, and the amber wash over a card (50 pairs).
- The filled button's label on its fill and pressed fill at 4.5:1; the fill against a card at 3:1 (6 pairs).
- The menu-bar needs-you icon at 3:1 on a light bar (#F5F5F5, 3.48) and a dark bar (#2A2A2A, 7.83) (2 pairs).

It does not cover:

1. **`inkFaint`.** Left out on purpose, but nothing stops its use for text, and it is used for text in three places.
2. **Any graphic.** No dot, bar, ring, switch, slider, tick or band colour. All of 4.3 and 4.4 is outside it.
3. **`amber`, `sage`, `blush`, the lanes and `recording` as colours.** Only the `*Ink` tones are listed.
4. **The terminal card** and the nine `Palette.*Dark` inks on it.
5. **Card tones other than amber.** `Card(tone: Theme.ink)` passes today (4.64) but is unchecked.
6. **Text on `hairline`** (a pressed quiet button, Theme.swift:434; a later step's number, OnboardingView.swift:156-160) and `paper` on `sage`, `ink` or `inkSoft`.
7. **Opacity**: disabled 0.4, the 0.6 "not found" card, asleep 0.7.
8. **The band's night shade.**
9. **Rendered pixels.** It checks palette arithmetic, not the 286 PNGs. A view that uses the wrong token passes.
10. **Size.** One threshold per pair; no notion of the 8, 9 and 10 pt text.

---

## 5. Colours with a meaning

| Colour | Means | Where | Verdict |
| --- | --- | --- | --- |
| **amber** / `amberInk` | Needs you | state dot (OverviewPane.swift:314), face edge (BoopFace.swift:81), session bar (OverviewPane.swift:691), chip and "+N more" (:682, :420), card tone (:399), "Dismiss" (:385), menu-bar icon (BoopFace.swift:234), onboarding's demo (OnboardingIntro.swift:87, :150, :189), tips' dots (OnboardingFinish.swift:410) | consistent |
| amber | **A buddy that is shipping** | WorldBand.swift:144 | **second meaning.** Breaks Theme.swift:7-8, "one amber accent, for needs you only". |
| **sage** / `sageInk` | Connected, on, saved, done, full | device dot (OverviewPane.swift:223, :241), switch on (Theme.swift:517), "Connected" (SettingsPane.swift:157, :195), "Saved" (:371), firmware updated (:249), full ring (BoopPane.swift:116), step done (OnboardingView.swift:156), "Found on this Mac" (OnboardingFinish.swift:138) | consistent: "good, nothing to do" |
| sage | **A buddy that is resting** | WorldBand.swift:146 | **second meaning** |
| `sageInk` | **A link**: "See everything Mochi knows ›" | BoopPane.swift:93 | **third meaning.** The only green link. Others are `inkSoft` (Details, Jev's docs) or `amberInk` (Dismiss). The sketch has it green too. |
| **`clayInk`** | Trouble, and what failed | notice icons (OverviewPane.swift:48, :52, :68, :82, :490, :503), device dot and word (:241, :245), row details (SettingsPane.swift:151, :158-162, :250, :283, :288, :383), onboarding errors | consistent. One oddity: "Needs a repair" and "Allow Boop in System Settings" are clay (SettingsPane.swift:158, :288). They ask you to act, which is amber's meaning. |
| **blush** | Today's XP, not yet full | ring (BoopPane.swift:116) | has a line of words beside it |
| blush | **A buddy that is waiting** | WorldBand.swift:145 | **second meaning** |
| **lanes** | Which work-stream slot (0 to 3) a working session has on the board | `SessionRow`'s bar (OverviewPane.swift:692) | no key in the popover; the key is the board |
| lane 0 teal, lane 2 lilac | **A buddy that is coding; testing** | WorldBand.swift:142-143 | **second meaning.** Breaks Theme.swift:38-39, "only bars wear them". |
| **`recording`** red | The mic is on | state dot (OverviewPane.swift:312) | one use |
| `inkSoft` as a dot or bar | Working | :315, :692 | |
| `inkFaint` as a dot | Idle, asleep, stopped, not connected | :316, :223, :241; WorldBand.swift:147 | four states, one colour; the headline says which |
| `ink` as a card tone | The step you are on | OnboardingView.swift:153, OnboardingIntro.swift:189 | |

**One meaning, two colours**

- **Waiting.** A waiting session is amber in Now. A waiting buddy is blush on the band.
- **Idle or resting.** A resting session is grey. A resting buddy is sage.
- **Working.** A grey dot in the header (Theme.swift:8), a lane colour on the row's bar, `ink` in the chip, teal or lilac on the band. The sketch drew the header's Working dot in sage.
- **Asks you to act.** Amber for an agent's request; clay for "Needs a repair".

**Colours with no key**

- **The World band's dots.** Five colours by activity (WorldBand.swift:140-148) and nothing in the view says which is which. The caption is "Buddies around the world, by time zone. Click one." (WorldPane.swift:42). A click gives one buddy's activity in words (WorldPane.swift:114). The sketch's caption also said "The dark side is night"; the shipped one dropped it.
- **The band's rings and line.** A thin ring is your buddy, a thick ring is the picked one, a line is your time zone (WorldBand.swift:35-45, :152-156). Only "you" has a label.
- **Session lane bars.** No key in the popover. A person on the simulator, or with no board, sees four unexplained colours.
- **The week's rings.** Blush for a part day, sage for a full one. The VoiceOver label says "full" (BoopPane.swift:71); nothing visible does.

---

## 6. The v1 sketch against what shipped

Source: `~/.boopdev/v1-ui/v1-ui.html`, one `<style>` block of 6,636 characters. The sketch says it is "rough on purpose: for judging layout and content, not final art", so these are differences, not defects.

### 6.1 Type

| Element | Sketch | Shipped | Where shipped |
| --- | --- | --- | --- |
| Body text | 13.5 px | 12 | throughout |
| Name | 18, weight 700 | rounded 18 semibold | OverviewPane.swift:123 |
| Status line | 13.5 | 12 | :129 |
| "Feeling happy · Level 12" | 12.5; mood in **`ink`** bold; rest `inkFaint` | 11; mood in `inkSoft` semibold; rest `inkFaint` | :172-179 |
| "Connected" | 12, dot 7 | 10 medium, dot 6 | :240-245 |
| Tab label | 12.5, weight 600 | 12 semibold or medium | :808 |
| Section label | 11, weight 700, tracking 0.08 em | 10 semibold, tracking 0.6 pt | Theme.swift:229-230 |
| Session title | 13.5, weight 600; project weight 400 | 12 medium; project 11 | OverviewPane.swift:733-736 |
| Session's doing line | mono 11.5 | mono 10.5 | :745 |
| Status chip | 11.5, always grey on `well` | 10 medium, in its tone on a 12% tint | Theme.swift:415-418 |
| Ring number / under it | 28 / 11 "of 100" | rounded 28 bold / 11 "today" | BoopPane.swift:33-34 |
| "Level 12" | 20, weight 700 | rounded 18 bold | :38 |
| XP lines | 12.5 | 12 | :39-40 |
| The how-it-works line | 11.5, `inkFaint` | 12, `ink` | :41-44 |
| Day names | 10.5 | 10 | :66 |
| "See everything …" | 12.5, weight 600, `sageInk` | 12 semibold, `sageInk` | :90-93 |
| World number / label | 17 bold / 11 | rounded 17, 14 or 12 bold / 11 | WorldPane.swift:90-94 |
| Band caption | 11, **`inkFaint`** | 11, `inkSoft` | :42-43 |
| Footer | 13 | 12 | PopoverView.swift:84 |

Every text size shipped 0.5 to 2 points smaller. The shipped captions use `inkSoft` where the sketch used `inkFaint` (`.cap`, `.note`, `.how`, `.small`). That is the right call for contrast.

### 6.2 Spacing and layout

| Element | Sketch | Shipped | Where shipped |
| --- | --- | --- | --- |
| Width | 360 | 360 | Theme.swift:101 |
| Header padding | 16 / 16 / 10, gap 12 | 18 / 18 / 4, gap 12 | OverviewPane.swift:148-150 |
| Face | 52, radius 12 | 46, radius 12.4 | :153 |
| Tab bar | margin 4 / 14 / 6; gap 4; inner pad 3 | h 18, top 8; gap 2; inner pad 2 | :19-20, :803, :828 |
| Body padding | 6 / 14 / 10 | top 12, h 18, bottom 18 | :29-31 |
| Between sections | 12 above the label, 6 below | 20 between, 8 under the label | :42, Theme.swift:227 |
| Footer padding | 10 / 16 | 8 / 10, plus the quiet button's 4 / 8 | PopoverView.swift:86-87 |
| Card padding | 8 / 10 | 12 (or 10) | Theme.swift:158 |
| Between cards | 6 | 8 | `Theme.gapSnug` |
| Session row | pad 7 / 10 / 7 / 0; gap 10; rows 6 apart | lead 13, trail 8, v7; gap 8; rows 5 apart | OverviewPane.swift:730, :753, :454 |
| Session bar | 4 wide, full height, radius 3 | 3 wide, inset 6 top and bottom, radius 2 | :756 |
| Session list | flat | grouped under an agent header | :453-461 |
| Ring | 120, stroke 12, gap 14 | 96, stroke 9, gap 18 | BoopPane.swift:28-30 |
| Week rings | 34, stroke 5 | 26, stroke 4 | :64-65 |
| World tiles | pad 6 / 8, gap 8 | `Card` at 10, gap 8 | WorldPane.swift:78, :86 |
| Band | about 332 × 207 (viewBox 480 × 300) | 324 × 96 | WorldBand.swift:23 |
| Buddy card | pad 8 / 10; face 38, radius 9 | pad 12; no face; a close xmark | WorldPane.swift:106-151 |
| Region list | 4 rows 4 apart, pad 4 / 8, no card | one `Card` at 0, hairlines, pad 7 / 12 | :248-261 |
| Settings rows | plain rows, a hairline under each, pad 7 / 2 | `SettingRow` in a card, with icons, pad 9 / 12 | SettingsPane.swift:58-85 |
| Switch | 34 × 20, knob 16 | 28 × 16, knob 12 | Theme.swift:518, :586 |

### 6.3 Radii and surfaces

| Element | Sketch | Shipped |
| --- | --- | --- |
| Card, row, tile, band | **10** everywhere | card 12, row 8, band 8 |
| Tab track / segment | 9 / 7 | 8 / 6 |
| Chip | 6 | 6 |
| Gesture button | 8 | 7 |
| Onboarding buttons | **pill** (999) | 10 |
| Primary button fill | `ink` #24211C with `paper` text | black glass with oat text (reversed in dark) |
| Chosen tab | shadow 0 1 2 at 0.10, no edge | radius 1, y 1, at 0.06, plus a `hairline` edge |
| Band's ground | `raised` | `well` |
| Buddy card | **white**, `hairlineStrong`, radius 12, shadow 0 4 14 at 0.12: it floats | a plain `Card` in the column |

### 6.4 Colour

| Element | Sketch | Shipped |
| --- | --- | --- |
| "Working" dot in the header | sage | `inkSoft` grey (OverviewPane.swift:315) |
| Status chip | always grey | toned |
| Ring | blush on `well` | the same; sage when full |
| Band's night | #1B1815 at 0.25 and 0.55, in strips | #3B3328 up to 0.2 (light), #05070D up to 0.8 (dark), one gradient |

### 6.5 In the sketch, not shipped

- The "why" line as the first thing in Now. Shipped: the reason card comes after Sessions (OverviewPane.swift:93).
- "Today: claude's work 60 · you 22" (the split of today's XP).
- "of 100" under the ring's number. Shipped says "today".
- The world goal card.
- Countries with flags. Shipped: three regions.
- Emoji on gesture buttons and arrivals. Shipped: SF Symbols.
- The buddy's face on its card.
- A "Leave the world" row in clay. Shipped: the switch does it.
- "The dark side is night." in the band's caption.

### 6.6 Shipped, not in the sketch

Talk and Hush buttons, reminder chips, notices, agent group headers, workspace names, "Why Mochi looks like this", the close xmark on the buddy's card, "Joining the world…", the private note.

---

## 7. A smaller, stricter set

The aim: keep Warm Terminal's colours, paper, hairlines and rounded face. Cut the number of values. Each number below is already the most common one in the code, or one step from it.

### 7.1 Spacing: 6 steps on a 4 pt grid

| Token | Value | Replaces | Use |
| --- | --- | --- | --- |
| `Theme.hair` | 2 | 1, 2, 3 | title over detail; lining loose text up with a card's edge |
| `Theme.gapTight` | 4 | 3, 4, 5 | an icon to its word inside a chip or button; lines in a group |
| `Theme.gapSnug` | 8 | 6, 7, 8, 9, 10 | icon column to text; between cards; a row's vertical padding |
| `Theme.gap` | 12 | 10, 11, 12, 13, 14 | a card's padding; a row's horizontal padding |
| `Theme.gutter` | 16 | 14, 16, 18 | the popover's sides; a roomy card. `gapLoose` goes: it was the same value. |
| `Theme.gapSection` | 24 | 20, 22, 24 | between sections. Keep 20 if 24 makes the popover too tall. |
| `Theme.windowGutter` | 48 | 48 | onboarding's sides |

Rules:

- No arithmetic on a token. `gapSnug + 2`, `gutter - 8` and `gutter - 4` go.
- The icon column becomes 20 wide with an 8 gap. 12 + 20 + 8 = 40, so `RowDivider`'s inset stays 40 and becomes a sum of tokens.

The gutter moves from 18 to 16. That matches the sketch and gives the column 4 more points of text.

### 7.2 Type: 8 sizes, 4 weights, named

| Name | Face | Size / weight | Replaces | Use |
| --- | --- | --- | --- | --- |
| `.boopDisplay` | rounded | 28 bold | 26, 28, 30 | the ring's number; onboarding act titles |
| `.boopTitle` | rounded | 18 bold | 16, 17, 18, 20 | the name, "Level 12", pane title, speech bubble, the name field |
| `.boopHeading` | rounded | 15 bold | 14, 15, 16 | onboarding card and step titles |
| `.boopLabel` | rounded | 13 bold | 13 | step numbers, the face legend |
| `.lead` | system | 14 regular | 13, 14, 15 | onboarding's body lines |
| `.body` / `.bodyMedium` / `.bodyStrong` | system | 12 regular / medium / semibold | 12, 12.5, 13 | text; a row's title; a card's title |
| `.caption` / `.captionStrong` | system | 11 regular / medium | 11 | detail lines; small buttons |
| `.label` | system | 10 semibold, tracking 0.6, uppercased | the 10, 11 and 12 section labels | every section heading |
| `.chip` | system | 10 medium | 8, 9, 10 | chips, day names, the device line |
| `.mono` | system mono | 11 (12 in the onboarding terminal, as body) | 10.5, 11, 12.5 | what an agent is doing; file names |

Weights: regular, medium, semibold for the system face; bold for the rounded face only. `heavy` goes. System `bold` (five icons) becomes semibold. Nothing under 10 pt.

Rule: a row's title is `.bodyMedium`; a card's title is `.bodyStrong`. Today both are used for both.

### 7.3 Radii: 3, plus capsule

| Token | Value | Use | Replaces |
| --- | --- | --- | --- |
| `cardRadius` | 12 | cards, the terminal, the name field | literal 12 |
| `wellRadius` | 8 | rows, tracks, **every button and field** | 7 (row button, fields), 10 (prominent button, hooks list) |
| `chipRadius` | 6 | chips, segments, the quiet button's hover | literal 6 |
| `Capsule()` | n/a | switch, slider, footprints only | header chips move to `chipRadius` |
| bar | 2 | the session bar, small decorations | 3 |

The face tile keeps 0.27 × size, with `style: .continuous` in all three places (add it at Slime/SlimeView.swift:52).

### 7.4 One card

`Card(padding:tone:)` with three paddings by name:

- `.regular` = 12: every content card in the popover.
- `.rows` = 0: a card of rows, which bring their own padding.
- `.roomy` = 16: onboarding's cards.

`Card(padding: 10)` (3 places) and `Card(padding: 14)` (10 places) go. `terminalCard()` becomes a `Card` surface with matching `Theme.terminalInk…` tokens, so the nine `Palette.*Dark` reads go. The hooks list (OnboardingFinish.swift:74-76, :124-126) becomes a well at `wellRadius` holding `.regular` cards.

### 7.5 One row

Horizontal 12, vertical 8. Icon column 20, gap 8. Title `.bodyMedium`, detail `.caption`, gap 2.

- `SettingRow`: v9 → 8, gap 10 → 8, icon frame 18 → 20 (SettingsPane.swift:469, :473, :485).
- `SessionRow`: lead 13 → 12, v7 → 8 (OverviewPane.swift:753).
- `RowPicker` row: h10 → 12, v7 → 8 (SettingsPane.swift:435).
- Region row: v7 → 8; the bare hairline → a `RowDivider` (WorldPane.swift:251, :259).
- Brain key block: v10 → 12 (SettingsPane.swift:391).
- Arrival and note cards: 10 → 12 (WorldPane.swift:216, BoopPane.swift:85).

### 7.6 One chip

`Chip(text, icon: nil, tone: nil)`: `.chip` text, padding h8 v4 (was h7 v3), `chipRadius`, fill = the tone at `chipTint`, or `well` with no tone. It replaces `StatusChip`, the header reminder chip, the hush chip's label and onboarding's sample-words capsule. The chip grows about 2 pt in height.

### 7.7 One button family

| Style | Font | Padding | Radius | Min height | Use |
| --- | --- | --- | --- | --- | --- |
| `.prominent` | 13 semibold (the one exception) or `.lead` semibold | h16 v8 | 8 (was 10) | 32 | one per screen |
| `.row` / `.rowFilled` | `.captionStrong` | h12 v4 (was h10) | 8 (was 7) | 24 | in rows and cards |
| `.quiet` | `.body`, set **by the style** | h8 v4 | 6 | 24 | footer, Back, "See exactly what gets added" |
| `.quietIcon` | 10 semibold icon | a 24 × 24 frame | 6 | 24 | xmark, pin, chevron, ladybug |
| `.link(tone)` | `.captionStrong` | v4, with `contentShape` | none | 24 | Dismiss, Details, "See everything … ›", Jev's docs |
| `.opens(radius)` | the content's | none | card or well | n/a | unchanged |

And one segmented control: `RowPicker` and `TabBar` share one chosen-pill recipe (`paper`, `chipRadius`, 1 pt `hairlineStrong`, one shadow or none).

Other tokens to add: `Theme.disabled = 0.4` (also for the 0.6 at OnboardingFinish.swift:148), `Theme.toneEdge = 0.45`, two shadows (`shadowKnob`, `shadowLift`), `Theme.knob` for the white.

### 7.8 Colour rules to make stricter

These keep the palette and change where it is used.

1. `inkFaint` never on text. "Feeling", "· Level 12" (OverviewPane.swift:174, :177), "TRY" (OnboardingBoard.swift:334) and the out-of-world "you" (WorldBand.swift:154) → `inkSoft`.
2. Extend `checkContrast()`: `inkFaint` must not be a text tone; each graphic colour at 3:1 on each surface it is drawn on, in both modes.
3. Give the board's bright colours a light-paper partner, as amber already has (`menuAmberLight` #B87400, 3.48:1). Or draw bars and dots on a `glass` chip, where they are at home.
4. The off switch and the slider groove use `inkSoft` for the track in light mode (5.4:1).
5. The World band gets a key, or its own palette. Amber leaves it. Then Theme.swift:7-8 and :38-39 are true again.
6. One colour for a link.

### 7.9 Every place that would change

`python3 system/changes.py` applies the rules above and lists **177 places** (file:line, old → new). Full list: `system/changes.md`.

| Kind | Places | By file |
| --- | --- | --- |
| `spacing:` literal off the scale | 51 | onboarding 35, OverviewPane 8, SettingsPane 3, WorldPane 2, BoopPane 1, MemoryPane 1, WorldBand 1 |
| `.padding` literal off the scale, and `Card(padding: 10 / 14)` | 44 | onboarding 20, OverviewPane 10, WorldPane 5, SettingsPane 4, Theme 3, BoopPane 2 |
| Token arithmetic and `gapLoose` | 13 | OverviewPane 6, SettingsPane 2, Theme 2, BoopPane 1, MemoryPane 1, PopoverView 1 |
| System font size off the scale | 23 | onboarding 12, OverviewPane 6, WorldBand 2, WorldPane 2, Theme 1 |
| Rounded font size off the scale | 11 | onboarding 10, Theme 1 |
| Weight (`heavy`, system `bold`) | 7 | onboarding 3, OverviewPane 2, SettingsPane 1, WorldPane 1 |
| Radius literal | 13 | onboarding 5, Theme 5, SettingsPane 3 |
| Icon column 16 or 18 → 20 | 6 | OverviewPane 4, SettingsPane 1, WorldPane 1 |
| Shadow and disabled opacity → tokens | 9 | Theme 6, onboarding 2, OverviewPane 1 |

The script's rules for a `6` (8 in an `HStack`, 4 in a `VStack`) and for a system `13` (12 in the popover, 14 in onboarding) are mechanical. Read each line before you apply it. One row needs a different answer than the rule gives: OverviewPane.swift:386 `padding(Theme.gapSnug + 2)` is the room round "Dismiss" and should become the card's 12, not 8. The script also misses WorldPane.swift:90, where 17, 14, 12 sit in an array.

Structural changes the script does not list:

| Where | Old | New |
| --- | --- | --- |
| OverviewPane.swift:199-207, :259-269 | two hand-built capsule chips | `Chip(icon:text:)` |
| OverviewPane.swift:751, Theme.swift:409-420 | `StatusChip` | `Chip(text:tone:)` |
| Onboarding/OnboardingBoard.swift:348-350 | stroked capsule | `Chip` |
| OverviewPane.swift:437-447 | "No agents awake" hand-built card | `notice("moon.zzz.fill", Theme.inkSoft, …)` |
| WorldPane.swift:31-34 | a trouble as an `inkSoft` caption | `notice("exclamationmark.triangle.fill", Theme.clayInk, …)` |
| SettingsPane.swift:140-142 and OverviewPane.swift:73 | one message, two forms | one form |
| OverviewPane.swift:456-461; OnboardingBoard.swift:273, :334, :110-112 | four hand-built headings | the `.label` style |
| OverviewPane.swift:383-385, Theme.swift:253-257, BoopPane.swift:89-93, OnboardingBrainKey.swift:24-30 | four link looks | `.link(tone)` |
| OverviewPane.swift:284, :302 | `RowButtonStyle(filled:)` | `.row` / `.rowFilled` |
| OverviewPane.swift:814-820 and SettingsPane.swift:436-443 | two chosen-pill recipes | one |
| WorldPane.swift:251 | `Hairline().padding(.horizontal, 12)` | `RowDivider` |
| SettingsPane.swift:360 and OnboardingBrainKey.swift:43 | field height 22 and 24 | 24 |
| OverviewPane.swift:223, :242 against Theme.swift:323 | 6 pt and 7 pt dots | one size |
| Slime/SlimeView.swift:52 | circular corner | `style: .continuous` |
| OnboardingIntro.swift:83-88; OnboardingFinish.swift:166, :170, :173 | `Color(hex: Palette.…Dark)` | `Theme.terminalInk…` |
| BoopFace.swift:152 | `Color(white: 0.92)` | a named token |
| Onboarding/OnboardingView.swift:289 | `#3A9BF0` | a lane colour |
| WorldBand.swift:118 | two hex literals | `Theme.night` |
| Theme.swift:68 | a hex inside `Theme` | `Palette.recording` |

---

## 8. Accessibility basics visible in the code

### 8.1 Text size

- All 141 `.font` calls give a fixed point size. 0 semantic text styles, 0 `dynamicTypeSize`, 0 `@ScaledMetric`. The macOS text-size setting has nothing to scale in Boop.
- Text under 11 pt: 8 pt ×1 (OverviewPane.swift:262), 9 pt ×4 (OverviewPane.swift:535, WorldPane.swift:146, WorldBand.swift:156, :164), 10 pt ×13, 10.5 pt ×2. The 10 pt set includes real sentences: the key's privacy note (SettingsPane.swift:381-383) and each recent day's date (Theme.swift:210).
- The layout mostly allows growth: `fixedSize(horizontal: false, vertical: true)` is widely used and nothing has a `lineLimit`. Fixed frames that would clip: the Talk button's 50 (OverviewPane.swift:300), the volume number's 22 (SettingsPane.swift:113), field heights 22 and 24, the onboarding window's 720 × 560 (OnboardingView.swift:10).

### 8.2 Tooltips (`.help`): 19

BoopPane.swift:95; MemoryPane.swift:60, :66; OverviewPane.swift:227, :249, :272, :286, :304, :387, :576; PopoverView.swift:66; SettingsPane.swift:96, :175, :200, :214, :225, :229; OnboardingIntro.swift:217; OnboardingView.swift:131. Only one names a shortcut (BoopPane.swift:95, "⇧⌘M"). ⌘1 to ⌘3, ⌘,, ⌘B and ⌘[ are shown nowhere.

### 8.3 Icon-only buttons

There are six. **All six have an accessibility label; none is unlabelled.** Three have no tooltip:

| Button | Label | `.help` | Where |
| --- | --- | --- | --- |
| Back chevron | "Back" | **none** | Theme.swift:188-193 |
| Bug report (ladybug) | "Save a bug report" | yes | PopoverView.swift:59-67 |
| Notice's xmark | "Dismiss" | **none** | OverviewPane.swift:534-539 |
| Pin a note | "Pin" / "Unpin" | yes | MemoryPane.swift:56-61 |
| Forget a note (xmark) | "Forget" | yes | MemoryPane.swift:62-67 |
| Close a buddy's card (xmark) | "Close" | **none** | WorldPane.swift:145-150 |

"Forget" deletes a note for good on one click, with no confirm, and wears the same xmark as the harmless "Dismiss" and "Close" (MemoryPane.swift:62).

Present and right: section labels are headers (Theme.swift:233); the custom switch and slider have `accessibilityRepresentation` (Theme.swift:530, :578-580); tabs and picker rows carry `.isSelected` (OverviewPane.swift:825, SettingsPane.swift:447); the band offers its awake buddies as buttons (WorldBand.swift:61-65); Reduce Motion stops the pulse, confetti, ripples and blink (Theme.swift:318, OnboardingView.swift:279, :321, BoopFace.swift:111).

Gaps: the header's buddy dots say connected or not by colour and a tooltip only (OverviewPane.swift:223-227); the World band's colours (section 5); notice icons carry no label and a notice is not one element, so VoiceOver may read the symbol's name.

### 8.4 Hit targets under 24 pt

Estimates from font size and padding (line height taken as about 1.2 × the size). Not measured on screen.

| Control | About | Where |
| --- | --- | --- |
| "Dismiss" on the needs-you card | 42 × **13**. The 10 pt padding comes after `.buttonStyle`, so it is outside the button. | OverviewPane.swift:383-386 |
| "Details" | 55 × **13** | Theme.swift:253-258 |
| "See everything … ›" | wide × **15** | BoopPane.swift:89-94 |
| "Jev's docs" link | 70 × **15** | Onboarding/OnboardingBrainKey.swift:24-30 |
| Switch, popover size | 28 × **16** | Theme.swift:518, :586 |
| Slider | 84 × **18**, knob 14 | Theme.swift:544, :574 |
| Hush chip | wide × **18** | OverviewPane.swift:256-270 |
| Notice and buddy-card xmark (9 pt) | 25 × **19** | OverviewPane.swift:534-538, WorldPane.swift:145-149 |
| Pin and Forget (10 pt), 6 pt apart | 26 × **20** each | MemoryPane.swift:56-67 |
| Row button (25 uses) | wide × **21** | Theme.swift:491-493 |
| Field; the large switch | wide × **22** | SettingsPane.swift:360; Theme.swift:588 |
| Footer quiet buttons, Back chevron | wide × **23** | PopoverView.swift:84-87, Theme.swift:188-191 |

At or over 24: tab segments (about 25), picker rows (28 and up), the prominent button (32), a band dot (14 pt pick radius, WorldBand.swift:102).

The smallest and the most destructive are neighbours: Pin and Forget are 20 pt high and 6 pt apart.

### 8.5 Keyboard and focus in the popover

Present:

- Esc goes back a pane, then closes (PopoverView.swift:45).
- Shortcuts: ⌘1, ⌘2, ⌘3 for tabs (OverviewPane.swift:824); ⌘, Settings (PopoverView.swift:58); ⌘B bug report (:64); ⇧⌘M memory, by a hidden button (:77-80); ⌘[ back (Theme.swift:192, OnboardingView.swift:255); ⌘Q (PopoverView.swift:82, OnboardingView.swift:38); Return for onboarding's main button (3 places).
- Fields show focus with a darker, thicker edge (Theme.swift:307). Return saves the key (SettingsPane.swift:366).
- The popover's window is made key on open (app/Boop/MenuBarApp.swift:1036).

Missing or unverified:

- **No code draws a focus state for any button.** `QuietButtonStyle`, `RowButtonStyle`, `ProminentButtonStyle`, `OpensButtonStyle`, `SwitchStyle` and the `.plain` tabs, picker rows and links never read `isFocused` (grep for `isFocused`, `focusable`, `focusEffect`: 0 hits). I did not check whether the system's ring still appears round these custom styles with Full Keyboard Access on. The snapshots can't show it. Check it by hand.
- The slider takes drags only (`DragGesture`, Theme.swift:562). Arrow keys depend on the `accessibilityRepresentation` slider; plain keyboard use is unverified.
- The World band takes clicks only (WorldBand.swift:48). No key picks a buddy.
- Nothing sets where focus starts when the popover opens (no `defaultFocus`).
- The hidden ⇧⌘M button has `opacity(0)` and a 0 × 0 frame but is still in the focus order (PopoverView.swift:77-80).

---

## Commands run

```sh
cd /Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish
git branch --show-current                                   # v1-polish
wc -l app/Boop/Views/*.swift app/Boop/Views/Onboarding/*.swift app/Boop/MenuBarApp.swift
python3 system/census.py > system/census.md      # also per section: pad font radius frame opacity color a11y
python3 system/contrast.py > system/contrast.md
python3 system/changes.py  > system/changes.md
grep -rniE "contrast|4\.5" app internal --include="*.swift" --exclude-dir=.build   # found Snapshots.checkContrast
grep -nE "\.background|\.overlay|\.padding|strokeBorder|\.font\(|buttonStyle|…" app/Boop/Views/Onboarding/*.swift
grep -nE "Card(\(|\s*\{)" app/Boop/Views/*.swift app/Boop/Views/Onboarding/*.swift
grep -c "\.caption()" …; grep -n "\.help(" …; grep -n "accessibilityLabel" …
grep -n "isFocused\|focusable\|focusRing\|FocusState" app/Boop/Views/*.swift app/Boop/Views/Onboarding/*.swift
python3 (inline): extract the <style> block and markup from ~/.boopdev/v1-ui/v1-ui.html, read only
```

Read in full: `Theme.swift`, `OverviewPane.swift`, `SettingsPane.swift`, `BoopPane.swift`, `MemoryPane.swift`, `PopoverView.swift`, `WorldPane.swift`, `WorldBand.swift`, and `internal/app/Boop/Snapshots.swift:1028-1089`. Read by their styling lines only: the six onboarding views, `BoopFace.swift`, `Slime/*.swift`, `MenuBarApp.swift`, `BoardWindow.swift`.

Not done: no app launched, no snapshot re-rendered, the 286 PNGs in `~/.boopdev/ui-review-2026-11-09/snaps` not measured. `findings.md` not written (see the top).