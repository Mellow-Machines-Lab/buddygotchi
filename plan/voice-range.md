# Voice range

Updated 2026-10-25. A draft for the owner to review. Nothing here is
generated: new paid takes need the owner's go
(`boop-voice-v1/plans/deferred.json` says so too).

The owner asked how to make Boop more expressive without making the
prompt much bigger, aiming at two to three times the range, not a
hundred. The prompt holds `say`'s options, not the takes: adding lines
to a meaning costs no tokens, and a new meaning costs about 25. So the
plan adds a few meanings and a lot of lines.

## Where the range is short today

Counted from `characters/pixel/mac/takes.tsv` (2,722 takes, 387 texts).
The voice was recorded in 13 moods; the other 29 faces borrow one of
those (`characters/pixel/tools/borrowed.json`).

1. **Three feelings.** `say` can feel only upset, glad or tickled. The
   bank already holds finer ones that voicegen folds into these
   (`FEELING` in `characters/boop/tools/voicegen/voicegen.py`): relief,
   pride, delight and insight into glad; frustration, setback and
   deflate into upset.
2. **Phrases play in few faces.** Each phrase was recorded in one mood.
   So a big or huge moment finds a phrase in only 2 to 14 of the 42
   faces, and says a word in the rest. `done` has a phrase in 4 faces,
   `helpers`, `helper back` and `retry` in 2.
3. **Few sounds.** A small moment asks for a sound, and small is the
   usual size. Only glad (all faces), upset (17), looking (18) and work
   (10) have sounds; the other 15 meanings say a word instead.
4. **Holes.** `command`, `tool` and `quiet` have no phrases at all;
   `hello` has 3 phrases and 5 words, `tickled` 5 words. Every `tests`
   line is about tests about to run.

## 1. Four new feelings

Each is an option of `say` beside upset, glad and tickled: about 100
tokens for the four. Proud isn't one: the proud face already plays the
bank's pride phrases, since a take plays only in its own mood's faces.

| Feeling | Option text | Not for |
| --- | --- | --- |
| relieved | Relief: something that was going wrong came right: a check passing after failing, a turn done after failed checks, the agent unstuck. | A plain win with nothing wrong before it, which is glad. |
| worried | Worry: it's going badly but isn't over: a check failing again mid-turn, a stuck or slow command, a risky ship. | A turn that finished failed, which is upset; a first small hiccup. |
| surprised | Surprise: what nobody expected: a huge deletion, a very fast finish, your shouting, its name in your prompt, the context compacted. | Anything routine or expected. |
| sleepy | Sleepy: late at night, a long quiet stretch, or a long day's work behind it. | Work going on, or a win. |

**What exists and what's new.** Words go in every voice mood they fit
(about 10 of the 13); phrases two to a mood, as in step 2.

| Feeling | Already recorded | New sounds | New words | New phrases |
| --- | --- | --- | --- | --- |
| relieved | Phew, Ahh, Whew, Haa (relief, all 13 moods) | none needed | Finally, Saved, Safe, Better, Unstuck, Sorted | Oh, thank goodness · That was close · Panic over · Back on track · Crisis averted · We live · Breathe out · Knew it'd work |
| worried | none | Eek, Gulp, Hnn?, Mm-mm, Ooh-ooh | Yikes, Careful, Gulp, Uh, Steady, Hold on | Oh, careful · Not looking good · Easy does it · This is fine · Please, please · Uh, guys? · I don't like this · Hold together |
| surprised | none | Oh!, Whoa!, Eh?!, Hah!, Wha-? | Whoa, Wow, Wait, What?, Wowza, Already? | Didn't see that · Well, well · Hold the phone · Say what? · Look at that · No way · Where'd it go? · Out of nowhere |
| sleepy | none | Yawn, Mmh..., Hwaah, Zzz, Mm-mm... | Sleepy, Bedtime, Snooze, Drowsy, Late, Pillow | Five more minutes · So sleepy · Past my bedtime · Is it night? · Little nap? · Eyes closing · Sleepy circuits · Just resting |

**Relieved costs no recording to start.** Moving `relief` from glad to
relieved in voicegen gives it four sounds in every face; a sound asked
for a word says the nearest kind, so it works at every size. Two
changes come with it:
- The relief takes need any finish, not a success only, so a check
  that passes mid-turn can say "Phew".
- Glad then has no takes in the six bad moods (annoyed, irritated,
  grumpy, whiny, wounded, sad), which the owner's rule in
  `testNoFaceIsWithoutWords` forbids. Step 2 records grudging glad
  lines for them, so the rule holds.

**Steering.** PERSONALITY's Examples already have the moments; they
change what they say:

| Example | Today | Then |
| --- | --- | --- |
| claude's build passed on "api" after failing | proud, says glad, medium | relieved, medium |
| done, a long turn, 25 tool calls, after 3 failed checks | proud, success, says glad, huge | proud, success, says relieved, huge |
| You asked … to ship it, on a Friday afternoon | uneasy, says upset | uneasy, says worried |
| You asked … for a fix, SHOUTING "STILL BROKEN" | surprised, says upset | surprised, says surprised |
| You asked … and said Boop's name | surprised, notice, says glad | surprised, notice, says surprised |
| Nothing has happened for 45 min | lazy, says quiet, medium | lazy, says sleepy, medium |

Add one example each where none fits yet: worried at `claude's tests
failed again on "api", 3 times in a row` (today determined, retry), and
sleepy at a late-night check-in. The evals that pin these examples
change with them; check them with `--only` those scenarios.

## 2. Fill the holes

**2a. Phrases in every face: 324 takes, already scripted.** The
deferred plan has every phrase's script for its other moods.
`plan/evidence/2026-10-25-voice-range/phrase-slots.json` picks 324 of
them (`phrase_slots.py` there remakes it): for each meaning, up to two
phrases in each voice mood that has none. After it, 13 meanings have a
phrase in all 13 voice moods, and so in all 42 faces. Done, glad and
start reach 7: their phrases fit only the good moods, which is right.

**2b. Sounds for the topics. About 300 takes, new.** Three or four
each, in the moods they fit, so a small moment makes a sound:

| Topic | Sounds |
| --- | --- |
| start | Hup!, Mm!, Okay-ay, Hnn-ya |
| helpers | Psst, Fwee (a whistle), Shoo-shoo |
| helper back | Oh!, Mm-hm, Ding? |
| retry | Hff, Hnn, Mmph |
| tests | Mm?, Hmm..., Tk-tk |
| command | Brr, Tik tik, Vrrm |
| tool | Bip, Blip?, Mm |
| planning | Hmm, Mmm..., Tsk-tsk-tsk (thinking) |
| done | Mm!, Ta!, Hah |
| answer | Oh?, Mm, Ooh |
| stopped | Oh., Huh., Hm. |
| waiting | Hmmm..., La la, Tap tap |
| quiet | Mm, Hmm-mm, Hoo |
| hello | Oh!, Hi-i!, Heyy |

**2c. Thin meanings. About 250 takes, new.**
- `command`, phrases: Here goes · Push the button · Beep boop · Running, running · Big red button · Engines on
- `tool`, phrases: Phone a friend · Fetch, boy · Little lookup · Asking around · One sec, calling · Internet, please
- `quiet`, phrases: All quiet · Nice and calm · Just us · Peace and quiet · Little break · Nothing doing
- `hello`, words: Hiya, Oh hi, Welcome, Yo, Heya, Ahoy; phrases: There you are · Look who's back · Missed you · Oh, it's you · Welcome back · Hello, human
- `tickled`, words: Hehe, Tee-hee, Stop it, Bonk, Squish; phrases: That tickles · Hey, rude · Again, again · Boop to you · Not the face
- `tests`, phrases that fit any test moment: Test time · The verdict · Let's see · Judgement day · Science! · Show me

**2d. Grudging glad, for the bad moods. About 40 takes, new.** Words:
Fine, Okay, Finally, Whatever, Hmph-okay. Phrases: About time · Took
long enough · I guess so · Fine, fine. Glad then has takes in every
face again.

## 3. A sound before a word

Built on this branch, in its own commit. Half the time, a word or a
swear at a medium moment or bigger gets a sound of the same meaning
before it, performed in the same mood: "Ugh.... Broken", "Ooh! Yay" (`Voice.lead`). The board has played
a `say` of two takes all along, 180 ms apart; the pair stays within
2.8 s, the voice bank's own limit for a joined line. Not on Quiet.

It is never two things said. Earlier on 2026-10-25 the owner disliked
Boop saying random pairs of words, a feeling and then a topic, and `say`
became one thing (eval 124). This pairs a sound with the word it
belongs to, as the bank's design allows (a nonverbal before its
anchor). It grows with step 1 and 2b: today only glad, upset, looking
and work have sounds to lead with.

## What it adds up to

| | Today | After |
| --- | --- | --- |
| Feelings | 3 | 7 |
| Meanings with a phrase in every face | 0 | 13 |
| Meanings with sounds | 4 | 21 |
| Texts | 387 | about 650 |
| Takes | 2,722 | about 4,300 (some 1,550 new, 324 of them scripted) |
| The voice file | 30 MB | about 48 MB |
| The prompt | | about 100 tokens more |

## Order

1. Step 3, already built: the owner listens on the board or the
   simulator and keeps it or drops the commit.
2. Relieved from the relief takes, with 2d's grudging glad: the first
   new feeling, with the Examples and evals that change.
3. 2a, the scripted phrases: the most range for the least writing.
4. The other three feelings, then 2b and 2c, in batches: write the
   lines into `dictionary.json`, generate, listen on the bank's review
   page, rerun voicegen.
