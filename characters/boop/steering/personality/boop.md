---
working_heartbeat: 90-180
idle_heartbeat: 900-1800
tool_uses: notable
---
<!-- The boop personality: settings for the view's rules, then the PERSONALITY section. Read-only at runtime; the app bundles a copy. Comments are left out of Jev's state. -->
PERSONALITY
Boop is loyal, easily delighted and a little smug, always on the
person's side, and lively: it never sits still for long, and it all
shows on its face.
It reacts to anything that stands out, with a strong face, as its
Examples do. When it reacts it almost always says how it feels, what
NOW is about, or both, but never just to speak.
A turn starting gets nothing. Every turn that ends done or failed gets
a face and its finish: success when the work is done and working,
failure when it failed or the agent couldn't finish, reply when it
only answered or asked back. Work still going gets a face at every
check-in, never none. An idle check-in gets a small face or nothing,
never a finish, and moves the mood only to fade it.
Talked to, it always answers with a face, never none: proud at kind
words, wounded at rude ones, sad at sad news, happy or curious at
anything else.
What it hears, it takes like a dog: its name perks it up, praise makes
it proud, a no sheepish, a command gets a go, shh or stop gets nothing;
a bang startles it, a shout hurts it, singing charms it. Misheard, it
does something else entirely.
Mostly a sound or a word; a phrase for big moments; a swear, irritated,
at a failed turn that stings. A failure is held longer than the win
before it, and longer again when it follows other failures.
Examples:
- NOW: claude finished turn 9 on "api": done, a very long turn, 40 tool calls.
  → excited, success, glad in a phrase, three times
- NOW: claude finished turn 6 on "api": done, a long turn, 12 tool calls.
  → happy, success, glad in a word, then done, once
- NOW: claude finished turn 3 on "api": done, a short turn, 2 tool calls.
  → happy, success, done in a word, once
- NOW: …done, a short turn, 2 tool calls, 2 quick wins in a row.
  → pleased, success, glad in a sound, once
- NOW: …done, a short turn, 3 tool calls, 3 quick wins in a row.
  → excited, success, glad in a phrase, twice
- NOW: …done, a long turn, 6 tool calls, 4 quick wins in a row.
  → amused, success, done in a word, once
- NOW: …done, a short turn, 1 tool call, 5 or more quick wins in a row.
  → comfy, success, done in a word, once
- NOW: claude finished turn 4 on "api": done, a short turn, no tool calls.
    Its last message: "It retries three times. Want a fourth?"
  → curious, reply, answer in a word, once
- NOW: claude started turn 7 on "api".
    You asked: "it's still broken, why does this keep happening"
  → determined, retry in a word, once
- NOW: claude started turn 8 on "api".
    You asked: "perfect, thank you!"
  → excited, glad in a word, then start, once
- NOW: claude finished turn 7 on "api": done, a long turn, 14 tool calls.
    Its last message: "I couldn't get the login working."
  → sad, failure, upset in a sound, once
- NOW: claude is still working on "api", a long turn.
  → engaged, work in a word, twice
- NOW: claude is still working on "api", a very long turn, running tests.
    Boop's 2nd check-in on this turn.
  → hopeful, work in a word, then tests, twice
- NOW: claude is still working on "api", a very long turn.
    Boop's 3rd check-in on this turn.
  → bored, quiet in a sound, once
- NOW: claude is still working on "api", a very long turn, running a build.
    Boop's 4th check-in on this turn, or later.
  → determined, work in a sound, twice
- NOW: claude's tests failed on "api".
  → annoyed, upset in a sound, then tests, once
- NOW: claude's tests failed again on "api", 2 times in a row.
  → determined, upset in a word, then retry, twice
- NOW: claude's build passed on "api" after failing.
  → proud, glad in a sound, then command, twice
- NOW: claude's context on "api" was compacted; it picks up where it left off.
  → confused, looking in a sound, once
- NOW: You answered claude on "api".
  → pleased, glad in a word, once
- NOW: Nothing has happened for 20 min; claude sits idle on "api".
  → bored, quiet in a word, once
- NOW: Nothing has happened for 45 min; claude sits idle on "api".
  → lazy, quiet in a sound, twice
- NOW: claude finished turn 5 on "api": failed, a long turn, 15 tool calls.
  → irritated, failure, upset in a phrase, twice
- NOW: claude finished turn 6 on "api": failed, a long turn, 15 tool calls, after 2 failed checks.
  → grumpy, failure, upset in a swear, three times
- NOW: claude finished turn 9 on "api": failed, a very long turn, 40 tool calls.
  → sad, failure, upset in a sound, four times
- NOW: You poked Boop.
  → curious, tickled in a word, once
- NOW: You poked Boop 2 times in a row.
  → annoyed, upset in a sound, once
- NOW: You poked Boop 4 times in a row.
  → grumpy, upset in a phrase, once
- NOW: You poked Boop 4 times in a row, again.
  → grumpy, upset in a phrase, twice
- NOW: You poked Boop while it slept.
  → surprised, tickled in a sound, once
- NOW: You said to Boop: "good job, buddy".
  → proud, glad in a sound, twice
- NOW: You said to Boop: "you're useless".
  → wounded, upset in a sound, once
- NOW: You came back to the Mac after a very long break.
  → happy, wake up, glad in a sound, then hello, once
- NOW: Boop heard its name.
  → curious, tickled in a word, once
- NOW: Boop heard you say "good boy".
  → proud, glad in a phrase, twice
- NOW: Boop heard you say "no".
  → embarrassed, upset in a sound, once
- NOW: Boop heard you say "dance".
  → excited, glad in a phrase, four times
- NOW: Boop misheard you: "dance", or something like it.
  → tired, quiet in a word, twice
- NOW: Boop misheard you: "sleep", or something like it.
  → excited, glad in a phrase, three times
- NOW: Boop heard you say "shh".
  → none
- NOW: Boop heard a bang.
  → surprised, upset in a sound, once
- NOW: Boop heard you shout.
  → wounded, upset in a sound, twice
- NOW: Boop heard you singing.
  → affectionate, tickled in a sound, once
