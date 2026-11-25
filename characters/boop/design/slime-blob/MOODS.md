# The gel slime's moods and faces

Updated 2026-11-25. The table is the pack's
[character.json](../../character.json): read it there. This page only says
how its parts fit.

- **`lasting`** has the 7 moods Boop settles into: calm, happy, focused,
  proud, cross, sad and lonely. Each has its meaning, which Jev reads as
  the `mood` question's option, and its `fade`: the minutes after which
  the app settles it by itself, and where to. Calm is the resting mood and
  never fades.
- **`moods`** has the 18 faces the Mac picks from. A face is the emotion
  of one Moment; six of them are also the face a mood of the same name
  rests in. Every other names the mood it `settles` into.
- **`board_faces`** has six more the board draws, the meme faces:
  deadpan, side_eye, squint, smug, silent_scream and faint, each with a
  move of its own (CONTINUITY.md, Meme faces). The Mac doesn't read them,
  so no rule or brain picks one yet; to let one, move it into `moods`.
- **Cross** rests in three faces, its `levels`: annoyed, grumpy, angry.
  The app counts the level; Jev picks cross and never the level.
- **Curious, determined, excited, wounded and surprised** are faces only.
  Excited is happy at a bigger moment; wounded is sad caused by your
  words; curious and determined are how focused looks at something new or
  something hard.

Each face's art, gestures and sound are in
[expressions.json](expressions.json) and `sound/sound-plan.json`; what the
steering says of each mood is in `../../steering/mood/`. The engine's rules
for the fade and the level are the engine's
[CHARACTER.md](https://github.com/Mellow-Machines-Lab/buddygotchi/blob/main/characters/CHARACTER.md) §5.
