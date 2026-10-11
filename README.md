<p align="center">
  <img src="documentation/media/boop.gif" width="440" alt="Boop's face on the board: napping, working along, an amber 'Claude needs you' sign, running tests, then a trophy for a big finish">
</p>

<h1 align="center">Boop</h1>

<p align="center">
  <b>A little creature for your desk that keeps an eye on your AI coding agents.</b>
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white">
  <img alt="ESP32" src="https://img.shields.io/badge/board-ESP32-E7352C?logo=espressif&logoColor=white">
  <img alt="MIT licence" src="https://img.shields.io/badge/licence-MIT-blue">
</p>

You've got three Claude sessions and two Codex threads going, and one of
them has been waiting on you for ten minutes. Boop noticed.

- 💤 **Naps** while no agent is open.
- ⌨️ **Works along** while they work: tests, the terminal, planning.
- 🟧 **Lights up amber** and knocks when one needs your approval, and says who.
- 🏆 **Celebrates** a finish that earns it, and grumbles at a failed test (never at you).
- 👉 **Pokes back** when you tap it, and answers when you hold its button and talk.

It has moods of its own, and there's no reset button. It only watches:
it never approves, denies or blocks anything an agent does.

> **Would you like a ready-made Boop?** The software is free and stays MIT.
> If you'd rather not flash a board yourself,
> [let us know →](https://tally.so/r/ZjprM5?src=readme)

<p align="center">
  <img src="documentation/media/moods.gif" width="720" alt="Eight of Boop's 13 moods reacting: excited, proud, curious, calm, grumpy, sad, tired and wounded">
</p>

A menu-bar app on your Mac does the thinking, and a cheap ESP32 board
with a screen is the body:

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="documentation/media/popover-dark.png">
    <img src="documentation/media/popover-light.png" width="560" alt="Boop's menu-bar popover: every session and what it's doing, then a 'needs you' card naming who's waiting">
  </picture>
</p>

## Get started

### What you need

| You need | Why |
| --- | --- |
| 💻 **A Mac** | macOS 26 or later, with Command Line Tools (`xcode-select --install`) |
| 🐍 **Python 3.10 or later** | For flashing the board and for the dashboard. The Mac's own is 3.9, so `brew install python`. PlatformIO installs itself |
| 🟨 **A board** | One of the two below, and a USB cable that carries data |
| 🔑 **A Jev key** | Optional. [Jev](https://docs.typesafe.ai/api) is TypeSafe's small hosted model, and it's what picks Boop's reactions. It needs a key from TypeSafe, which may cost money. Without one, Boop still shows what your agents are doing and when you're needed, but doesn't react or celebrate. Add it in Boop's Settings |

### Supported boards

| Board | Screen | Touch | Connects over |
| --- | --- | --- | --- |
| **Cheap Yellow Display**<br>MicroTech MTR024QV01A-V1 | 2.4" IPS, 320×240 | Resistive | Bluetooth, USB |
| **Waveshare ESP32-S3-Touch-AMOLED-2.06** | 2.06" AMOLED, 410×502 | Capacitive | Bluetooth, USB |

Pins, parts and quirks are in [the firmware's README](firmware/README.md).

### Three steps

Clone this repository with its submodules, and run everything from its
folder:

```sh
git clone --recurse-submodules https://github.com/Mellow-Machines-Lab/buddygotchi.git && cd buddygotchi
```

1. **Flash it.** Plug the board in over USB and run `make flash`. It
   works out which board it is. The first time, it installs PlatformIO
   and the ESP32 toolchain inside the checkout, which takes a few
   minutes; a `pio` already on your `PATH` is used instead.
2. **Run it.** From your own terminal, run `make run`. The first build
   takes a minute or two, then Boop appears in the menu bar.
3. **Say hello.** Give it a name, pick sweet or cheeky, and choose which
   agents to watch. Restart open agent sessions so they pick up Boop's
   hooks.

Then tap the screen or press BOOT to poke it.

### Everyday commands

| To | Run |
| --- | --- |
| Flash the firmware (over USB) | `make flash` |
| Run Boop in the menu bar | `make run` |
| See what it did today, and why | `make day` |
| Try Boop with no board, in a browser | `make simulator` ([simulator/README.md](simulator/README.md)) |

Start `make run` from your own terminal: macOS stops anything that uses
Bluetooth from an editor's or an agent's shell. Debugging and the brain's
evals are in [CONTRIBUTING.md](CONTRIBUTING.md).

## What leaves your Mac

Nothing, unless you add a Jev key. With one, each time Boop thinks, it
sends TypeSafe a short text: what's been happening, in lines like
`claude started turn 1 on "landing".`, and Boop's personality and mood.
Three things in your own words go too, each cut to 300 characters: your
prompt, the agent's last message, and what you say to Boop when you hold
its button. Your files, commands and tool output never do.

## Uninstall

Quit Boop from its menu, then take its hooks out of Claude Code and
Codex:

```sh
.build/debug/boopdev hooks remove --home ~
```

Run `make build` first if `.build/` is gone.

## Built from open packages

Boop stands on small packages that know nothing about it. Each one is
useful on its own:

| | Package | What it does | How it works |
| --- | --- | --- | --- |
| 🪝 | [agent-hooks](agent-hooks/README.md) ([repo](https://github.com/Mellow-Machines-Lab/AgentHooks)) | Tells you what every coding agent is doing, and which one needs you | [ARCHITECTURE.md](agent-hooks/ARCHITECTURE.md) |
| 🧠 | [MellowHarness](mellowharness/README.md) ([repo](https://github.com/Mellow-Machines-Lab/MellowHarness)) | Gives anything a personality with Markdown and multiple choice | [ARCHITECTURE.md](mellowharness/ARCHITECTURE.md) |
| 📡 | [LinkKit](linkkit/README.md) (in this repository for now) | Links your Mac app to a little gadget, over Bluetooth or USB | [ARCHITECTURE.md](linkkit/ARCHITECTURE.md) |

## Learn more

- **[architecture.html](https://htmlpreview.github.io/?https://github.com/Mellow-Machines-Lab/buddygotchi/blob/main/documentation/architecture.html)**:
  how Boop fits together, following one finished turn through every piece.
