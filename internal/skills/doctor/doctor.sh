#!/usr/bin/env bash
# Boop doctor: will Boop see this agent's hooks?
#
#   1. Hooks are registered for each agent and point at an existing agent-hook
#      (the installer's own check, through boopdev: run make -C internal build first).
#   2. The app is running and its socket accepts.
#   3. A synthetic event goes from agent-hook to the app (seen in its log).
#   4. A harmless command run in the agent shows up in Boop as a hook from
#      this agent's own session (--confirm).
#
# Usage:
#   internal/skills/doctor/doctor.sh [--agent claude|codex] [--state-dir DIR]
#   internal/skills/doctor/doctor.sh --confirm [--agent claude|codex] [--state-dir DIR]
#   internal/skills/doctor/doctor.sh --headless     # checks 1–3 against a throwaway headless app
#
# Exit 0 healthy, 1 broken, 2 armed and waiting for the live step: run one
# harmless command through the agent (echo BOOP_DOCTOR_PING), then --confirm.
# It only reads ~/.claude and ~/.codex. Arming writes one file,
# `doctor-armed`, in the state directory; --confirm removes it, and the app
# drops an arm nobody confirms after a while.
set -uo pipefail

AGENT=""; STATE=""; CONFIRM=0; HEADLESS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --state-dir) STATE="$2"; shift 2 ;;
    --confirm) CONFIRM=1; shift ;;
    --headless) HEADLESS=1; shift ;;
    -h|--help) awk 'NR > 1 && /^#/ { print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Physically, from internal/skills/doctor, even when run through a skill
# link (.claude/skills/doctor).
REPO="$(cd -P "$(dirname "$0")/../../.." && pwd -P)"
STATE="${STATE:-$HOME/Library/Application Support/Boop}"
pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
info() { printf '  \033[2m·\033[0m %s\n' "$1"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

if [ -z "$AGENT" ]; then
  if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]; then AGENT=claude
  elif [ -n "${CODEX_SANDBOX:-}" ] || [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_HOME:-}" ]; then AGENT=codex
  else AGENT=unknown; fi
fi

if [ $HEADLESS -eq 1 ]; then
  STATE="$(mktemp -d /tmp/boop-doctor.XXXX)"
  BOOP="$REPO/.build/debug/Boop"
  [ -x "$BOOP" ] || { echo "no $BOOP; run make -C internal build" >&2; exit 1; }
  "$BOOP" --headless --state-dir "$STATE" --brain scripted --name Doctor >/dev/null 2>&1 &
  APP_PID=$!
  trap 'kill -TERM $APP_PID 2>/dev/null; wait $APP_PID 2>/dev/null; rm -rf "$STATE"' EXIT
  for _ in $(seq 50); do [ -S "$STATE/boop.sock" ] && break; sleep 0.1; done
fi

SOCK="$STATE/boop.sock"
LOG="$STATE/boop.log"
ARM="$STATE/doctor-armed"

# --- live confirm -----------------------------------------------------------
if [ $CONFIRM -eq 1 ]; then
  hdr "Boop doctor: confirm ($AGENT)"
  # Only this agent's own hooks count: the owner often has other sessions
  # busy, and theirs say nothing about this one. The session id is the
  # one this agent's hooks carry.
  case "$AGENT" in
    claude) sid="${CLAUDE_CODE_SESSION_ID:-}" ;;
    codex)  sid="${CODEX_THREAD_ID:-}" ;;
    *) bad "can't tell which agent this is; pass --agent claude|codex"; exit 1 ;;
  esac
  if [ ! -f "$ARM" ]; then bad "not armed, or the arm expired; run doctor.sh first, then confirm straight away"; exit 1; fi
  # Only what the log gained since arming: it keeps earlier days' lines,
  # stamped with the time of day alone. Lines read
  # "HH:MM:SS.mmm hook: <agent> <hook> <session>".
  since=$(cat "$ARM")
  rm -f "$ARM"
  new=$(tail -c +$((since + 1)) "$LOG" 2>/dev/null | awk -v a="$AGENT" '$2 == "hook:" && $3 == a && $5 !~ /^doctor-/')
  if [ -z "$sid" ]; then
    seen=$(printf '%s\n' "$new" | sed '/^$/d' | tail -1)
    [ -n "$seen" ] && { ok "a $AGENT hook reached Boop (no session id here to check it's this one's): $(echo "$seen" | cut -d' ' -f3-5)"; exit 0; }
  else
    seen=$(printf '%s\n' "$new" | awk -v s="$sid" '$5 == s' | tail -1)
    [ -n "$seen" ] && { ok "this session's hooks reached Boop: $(echo "$seen" | cut -d' ' -f3-5)"; exit 0; }
    others=$(printf '%s\n' "$new" | awk 'NF { print $5 }' | sort -u | paste -sd' ' -)
    if [ -n "$others" ]; then
      bad "only other $AGENT sessions' hooks reached Boop since arming ($others), none from this one ($sid)"
      exit 1
    fi
  fi
  bad "no hook from $AGENT reached Boop since arming"
  exit 1
fi

hdr "Boop doctor (agent: $AGENT, state: $STATE)"

# --- 1. hook registration ---------------------------------------------------
# The installer is the one source of which hooks each agent gets, so its own
# health check decides (boopdev hooks status). Hooks call the copy of
# agent-hooks' agent-hook the app keeps in its state directory, or, after
# `boopdev hooks install`, the one built next to boopdev.
hdr "Hooks"
BOOPDEV="$REPO/.build/debug/boopdev"
[ -x "$BOOPDEV" ] || { bad "no $BOOPDEV to check the hooks with; run make -C internal build"; exit 1; }
HOOK_BIN=""; hooked=0; before=$fail
for agent in claude codex; do
  case $agent in claude) name="Claude Code"; file="$HOME/.claude/settings.json" ;;
                 codex) name="Codex"; file="$HOME/.codex/hooks.json" ;; esac
  if [ ! -f "$file" ]; then
    # Missing for the agent running this, it can't have Boop's hooks.
    if [ "$agent" = "$AGENT" ]; then bad "$name: no $file, so this agent has no Boop hooks"; else info "$name: no $file"; fi
    continue
  fi
  health=""; first=""
  for bin in "$HOME/Library/Application Support/Boop/bin/agent-hook" "$REPO/.build/debug/agent-hook"; do
    health=$("$BOOPDEV" hooks status $agent --home "$HOME" --hook "$bin" 2>&1 | sed "s/^$agent: //")
    if [ "$health" = installed ]; then HOOK_BIN="$bin"; break; fi
    first="${first:-$health}"
  done
  # The app's copy gone says more than hooks that don't call the repo's build.
  if [ "$first" = clientMissing ] && [ "$health" = outdated ]; then health=clientMissing; fi
  # The everyday app repairs outdated hooks at launch, so
  # after a new build they're outdated until Boop restarts.
  repair=""; [ $HEADLESS -eq 0 ] && repair="; Boop repairs them when it next starts, so ask the owner to restart Boop.app"
  case "$health" in
    installed) ok "$name: every hook registered, calling $HOOK_BIN"; hooked=1 ;;
    notInstalled) bad "$name: no Boop hooks in $file" ;;
    outdated) bad "$name: Boop's hooks in $file are missing, old or point at another agent-hook$repair" ;;
    clientMissing) bad "$name: the app's agent-hook ($HOME/Library/Application Support/Boop/bin) is missing" ;;
    *) bad "$name: $health" ;;
  esac
done
[ $hooked -eq 1 ] || [ $fail -gt $before ] || bad "no agent has Boop's hooks"
[ -n "$HOOK_BIN" ] || HOOK_BIN="$REPO/.build/debug/agent-hook"

# --- 2. the app -------------------------------------------------------------
hdr "App"
if [ ! -S "$SOCK" ]; then
  bad "no socket at $SOCK: the app isn't running (ask the owner to start Boop; don't launch it from an agent)"
  exit 1
fi
if python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.settimeout(0.5); s.connect(sys.argv[1])' "$SOCK" 2>/dev/null; then
  ok "socket accepts at $SOCK"
else
  bad "socket at $SOCK doesn't accept (stale socket? restart Boop)"
  exit 1
fi
# agent-hook sends to every socket listed in agent-hooks' folder, and the
# everyday Boop lists its own there as a link.
if [ $HEADLESS -eq 0 ]; then
  listed="${AGENT_HOOKS_DIR:-$HOME/.agent-hooks}/sockets/boop.sock"
  if [ "$(readlink "$listed" 2>/dev/null)" = "$SOCK" ]; then
    ok "listed for agent-hook at $listed"
  else
    bad "$listed doesn't lead to $SOCK, so hooks never reach Boop; Boop lists it when it starts, so ask the owner to restart it"
  fi
fi

# --- 3. synthetic round trip ------------------------------------------------
hdr "Round trip"
# Arming: the app logs every hook while this file exists, and it holds how
# long the log was, so --confirm reads only what came after.
size=0; [ -f "$LOG" ] && size=$(wc -c < "$LOG" | tr -d ' ')
echo "$size" > "$ARM"
session="doctor-$$"
printf '{"hook_event_name":"SessionEnd","session_id":"%s","cwd":"/tmp"}' "$session" \
  | AGENT_HOOKS_SOCKET="$SOCK" "$HOOK_BIN" claude
code=$?
[ $code -eq 0 ] && ok "agent-hook exited 0" || bad "agent-hook exited $code"
seen=0
for _ in $(seq 20); do grep -q "hook: claude SessionEnd $session" "$LOG" 2>/dev/null && { seen=1; break; }; sleep 0.1; done
[ $seen -eq 1 ] && ok "the app received the synthetic event" || bad "the app didn't log the synthetic event (is $LOG this app's log?)"

hdr "Result"
echo "  $pass passed, $fail failed"
if [ $fail -gt 0 ]; then rm -f "$ARM"; exit 1; fi
if [ $HEADLESS -eq 1 ]; then rm -f "$ARM"; exit 0; fi
echo "  Armed. Run one harmless command through the agent (echo BOOP_DOCTOR_PING), then: $0 --confirm"
exit 2
