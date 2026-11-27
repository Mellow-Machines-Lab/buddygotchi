# Boop's voice bank

Every take Boop's voice is built from, in one voice: ElevenLabs' stock
voice Callum (`N2lVS1w4EtoT3dr4eOWO`), model `eleven_v4`, seed 42, each
master played 1.55 times higher and 1.15 times faster with ffmpeg, then
made 8-bit. All takes are unreviewed by ear.

500 takes: 76 of the 50 sentences in `plans/sentences.json`, and 424 of
the 212 words a reply or a skit says, two deliveries each. A take is one
entry said in one delivery: B bright, F flat or G glum (the plan's
`deliveries`, each with a bank mood, an audio tag, an acting direction and
the faces it plays in). Its id is `<entry id>__<mood>`, the mood `happy`,
`calm` or `sad`: `word.success.done__calm`, `sentence.win.all-yours__happy`.

| File | What it is |
| --- | --- |
| `manifest.json` | Every take: its entry, delivery, script, length, review status, generation settings, the master's hash and its two files |
| `dictionary.json` | The entries a take says: each one's text, kind and intent |
| `plans/sentences.json` | The sentences: each one's spoken words and deliveries, and the voice's settings |
| `provenance.json` | Where the audio came from and how it was treated |
| `audio-pcm8/robot-soft/` | What voicegen builds the board's voice from: mono 8-bit unsigned, 11.025 kHz WAVs |
| `audio-pcm8/original/` | The same takes before the robot-soft chain |

The masters stay outside the repo; the manifest keeps their hashes.

`characters/boop/tools/voicegen/record.py` records takes (`--dry-run`
first; tier 3 is the words), and `voicegen.py` builds `voice/voice.bin`
and `mac/takes.tsv` from this folder (characters/CHARACTER.md §8). Rerun
voicegen after any change here.
