# Security

Please report a vulnerability privately, through the repository's
Security tab:
[report a vulnerability](https://github.com/Mellow-Machines-Lab/buddygotchi/security/advisories/new).
Don't open a public issue for it. Say what you found, how to reproduce
it, and which version (`Boop --help` prints it) or commit you used.

The hook layer and the brain's harness are packages with their own
policies: [agent-hooks](agent-hooks/SECURITY.md) and
[MellowHarness](mellowharness/SECURITY.md).

## What's in scope

- **The hook socket**, `~/Library/Application Support/Boop/boop.sock`,
  mode 0600, listed in `~/.agent-hooks/sockets/`: what can send Boop
  events.
- **What Boop keeps**, in `~/Library/Application Support/Boop/`: the
  transcript (two weeks of events, with your prompts and agents' last
  messages cut to 300 characters), `boop.log`, `debug.jsonl`, bug
  reports, settings, memory, and the copies of your agents' settings in
  `backups/`.
- **Jev's key**, in your login Keychain. Boop reads it through
  `/usr/bin/security`, so any program running as you can read it without
  a prompt; a signed release will read it through the Security framework
  instead.
- **What goes to TypeSafe** with each brain call, when there's a key
  (the README's "What leaves your Mac").
- **The board's links.** Over Bluetooth the link isn't paired or
  encrypted yet: anything in range running Boop can connect to a board
  and send it what the Mac sends (`state`, `do`). The debug commands
  (`dbg.*`), which can fake taps, reset the board or write its card, are
  taken over USB only.
- **Firmware updates**, written over USB through the chip's ROM
  bootloader from the firmware `Boop.app` carries.
- **The installer and the uninstaller**, which edit `~/.claude/settings.json`,
  `~/.codex/hooks.json` and `~/.codex/config.toml`.

## What Boop never does

Boop only watches. It never approves, denies or blocks anything an agent
does, and its hooks fail open: if Boop isn't running, an agent carries on
as if they weren't there.
