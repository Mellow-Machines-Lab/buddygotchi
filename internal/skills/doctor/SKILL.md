---
name: doctor
description: Self-diagnose whether the current agent harness (Claude Code or Codex) is correctly wired to Boop — hook registration, the agent-hook binary, the running app's socket and its listing, a synthetic round trip, and a live check that this harness's own hooks fire. Use when asked "is Boop working", "check my hooks", "/doctor", or before trusting any hook-dependent test.
---

# Boop doctor

`internal/skills/doctor/doctor.sh` does the checking; this file says how
to drive it. It checks the four things listed at the top of `doctor.sh`, needs
`make -C internal build` first, and only reads `~/.claude` and `~/.codex`.

## Procedure

1. From the repo root run:

   ```sh
   internal/skills/doctor/doctor.sh
   ```

   Pass `--agent claude|codex` if it prints `agent: unknown`, and
   `--state-dir DIR` for a headless app (the default is the everyday app's
   `~/Library/Application Support/Boop`).

2. Read the report. Exit codes:
   - `1`: something is broken. Fix it (below) before running anything that
     depends on hooks.
   - `2`: everything passed and the check is **armed** for the live step.
     Arming writes `doctor-armed` in the state directory; while it's there
     the app logs every hook to `boop.log`. The app drops an arm nobody
     confirms after a while, so go on straight away.

3. Run exactly one harmless shell command through your own tool-calling
   path, so your harness fires its hooks:

   ```sh
   echo BOOP_DOCTOR_PING
   ```

4. Then confirm, which also disarms:

   ```sh
   internal/skills/doctor/doctor.sh --confirm
   ```

   Exit `0` means this session's hooks reached Boop. Only this agent's
   own hooks count, matched by its session id (`CLAUDE_CODE_SESSION_ID`
   or `CODEX_THREAD_ID`) when the shell has one, so other sessions busy at
   the same time can't make it pass.

`--headless` runs checks 1–3 against a throwaway headless app instead of
the everyday one, and exits `0` when they pass. It fails when the agent
running it, or every agent, has no Boop hooks. With a temporary `HOME` it
checks the installer without touching the owner's setup. With no agent
named, `boopdev` installs both, so this works from Claude or Codex:

```sh
H=$(mktemp -d /tmp/boop-h.XXXX)
.build/debug/boopdev hooks install --home "$H"
HOME="$H" internal/skills/doctor/doctor.sh --headless
```

## Fixes, by finding

- **No socket, or the socket doesn't accept.** The app isn't running. Ask
  the owner to start Boop (open Boop.app). Don't launch it yourself: an
  agent-launched Boop is killed on its first Bluetooth use.
- **Not listed for agent-hook.** `agent-hook` sends to every socket in
  `~/.agent-hooks/sockets/`, and the everyday Boop lists its own there
  as `boop.sock`, a link, when it starts. Ask the owner to restart Boop.
- **Hooks old, or calling another `agent-hook`.** Common after a new
  build: Boop repairs them when it next starts, so ask the owner to
  restart it (Boop.app: a copy on another folder, as `make dev` runs, never repairs them), then restart the agent's sessions so they
  reload their hook config.
- **Hooks missing.** Boop → Settings → Agents → Connect for this agent,
  then restart the agent's sessions.
- **The app's `agent-hook` is missing.** The app copies it into
  `~/Library/Application Support/Boop/bin/` at launch, from the one built
  next to it. Run `make -C internal build` if it isn't built, then ask the owner to
  restart Boop.
- **Round trip fails but the socket accepts.** Another Boop owns the socket,
  or `boop.log` belongs to a different state directory.
- **Confirm fails.** This session didn't fire its hooks, even if others
  did: it was started before the hooks were installed, or it reads a
  different config.

## Report back

State the agent, the pass/fail counts, and any fix applied. If the live
confirm failed, say so plainly and don't run hook-dependent tests as if they
were meaningful.
