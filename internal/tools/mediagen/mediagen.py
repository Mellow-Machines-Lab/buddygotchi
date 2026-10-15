"""The READMEs' pictures, each from a real run: the firmware's own drawing
in the native simulator, the popover from `Boop --snapshots`, agent-hooks' watch
example on hooks sent through its client, and Beacon on events sent with
mellowharness-emit (README.md here).

    internal/tools/.venv/bin/python internal/tools/mediagen/mediagen.py [boop moods popover watch beacon]
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "internal" / "tools"))

from boopctl_lib.cli import SIM_PROGRAM, build_sim  # noqa: E402
from boopctl_lib.device import Sim  # noqa: E402
from boopctl_lib.image import to_image  # noqa: E402

KEY = (255, 0, 255)  # the corners' colour, transparent in every GIF
BEZEL = (28, 28, 32)
MENLO = "/System/Library/Fonts/Menlo.ttc"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(MENLO, size, index=1 if bold else 0)


def save_gif(frames: list[Image.Image], durations: list[int], path: Path, extra: list[tuple] = ()) -> None:
    """One palette for every frame, from a spread of them (and `extra`
    colours), with the key colour transparent."""
    picks = frames[:: max(1, len(frames) // 12)][:12] + [frames[-1]]
    w, h = frames[0].size
    sheet = Image.new("RGB", (w, h * len(picks) + 8), KEY)
    for k, f in enumerate(picks):
        sheet.paste(f, (0, k * h))
    for k, c in enumerate(extra):
        sheet.paste(c, (k * 8, h * len(picks), k * 8 + 8, h * len(picks) + 8))
    ref = sheet.quantize(colors=96, method=Image.Quantize.MAXCOVERAGE)
    rgb = ref.getpalette()[: 96 * 3]
    key = min(range(96), key=lambda i: sum((a - b) ** 2 for a, b in zip(rgb[i * 3 : i * 3 + 3], KEY)))
    pal = [f.quantize(palette=ref, dither=Image.Dither.NONE) for f in frames]
    path.parent.mkdir(parents=True, exist_ok=True)
    pal[0].save(path, save_all=True, append_images=pal[1:], duration=durations, loop=0, optimize=True,
                disposal=1, transparency=key)
    print(f"{path.relative_to(REPO)}: {len(frames)} frames, {path.stat().st_size // 1024} KB")


# --- The face, in the native simulator ------------------------------------

STEP_MS = 80


def record(steps: list[tuple[int, dict | None]]) -> list[Image.Image]:
    """Plays `steps` ((at ms, message or None), the last one's time the end)
    on the native simulator's frozen clock, a screenshot every STEP_MS."""
    frames = []
    with Sim(str(SIM_PROGRAM)) as sim:
        sim.request({"t": "dbg.reset"})
        i = 0
        for t in range(0, steps[-1][0], STEP_MS):
            while i < len(steps) and steps[i][0] <= t:
                if steps[i][1]:
                    sim.send(steps[i][1])
                i += 1
            sim.request({"t": "dbg.clock", "freeze": t})
            frames.append(to_image(sim.shot()).convert("RGB"))
    return frames


def device(screen: Image.Image, caption: str, scale: int = 2, pad: int = 22) -> Image.Image:
    """The screen on a rounded bezel, with a caption under it."""
    sw, sh = screen.width * scale, screen.height * scale
    W, H = sw + pad * 2, sh + pad * 2 + 46
    img = Image.new("RGB", (W, H), KEY)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, W - 1, H - 1), radius=34, fill=BEZEL)
    img.paste(screen.resize((sw, sh), Image.Resampling.NEAREST), (pad, pad))
    f = font(22, True)
    d.text(((W - d.textlength(caption, font=f)) / 2, pad + sh + 8), caption, font=f, fill=(235, 235, 235))
    return img


STORY = [  # (at ms, message, caption from then on)
    (0, {"t": "state", "base": "asleep", "busy": 0}, "no agents: napping"),
    (2600, {"t": "state", "base": "working", "act": "terminal", "mood": "calm", "busy": 1, "variant": 1},
     "agents working: so is Boop"),
    (6400, {"t": "state", "base": "working", "attn": {"agent": "claude", "project": "landing", "more": 0},
            "busy": 1}, "one needs you"),
    (9600, {"t": "state", "base": "working", "act": "testing", "mood": "engaged", "busy": 1, "variant": 1},
     "back to work: running tests"),
    (12000, {"t": "state", "base": "idle", "mood": "happy", "busy": 0}, "done! a big finish"),
    (12000, {"t": "do", "id": 11, "name": "task_complete", "play": "now",
             "args": {"outcome": "success", "variant": 1, "mood": "excited", "loops": 1,
                      "who": {"agent": "claude", "thread": "fix-nav"}}}, None),
    (18000, None, None),
]


def boop_gif() -> None:
    frames = record([(at, m) for at, m, _ in STORY])
    out = []
    for i, f in enumerate(frames):
        caption = [c for at, _, c in STORY if c and at <= i * STEP_MS][-1]
        out.append(device(f, caption))
    save_gif(out, [STEP_MS] * len(out), REPO / "documentation" / "media" / "boop.gif")


MOODS = ["excited", "proud", "curious", "calm", "grumpy", "sad", "tired", "wounded"]


def moods_gif() -> None:
    clips = {m: record([(0, {"t": "state", "base": "idle", "mood": m, "busy": 0}),
                        (400, {"t": "do", "id": 5, "name": "react", "play": "now",
                               "args": {"mood": m, "loops": 3}}),
                        (4400, None)]) for m in MOODS}
    cols, tw, th, gap, pad, lab = 4, 320, 240, 14, 22, 40
    rows = (len(MOODS) + cols - 1) // cols
    W = pad * 2 + cols * tw + (cols - 1) * gap
    H = pad * 2 + rows * (th + lab) + (rows - 1) * gap
    out = []
    for i in range(len(clips[MOODS[0]])):
        img = Image.new("RGB", (W, H), KEY)
        d = ImageDraw.Draw(img)
        d.rounded_rectangle((0, 0, W - 1, H - 1), radius=34, fill=BEZEL)
        for k, m in enumerate(MOODS):
            x, y = pad + (k % cols) * (tw + gap), pad + (k // cols) * (th + lab + gap)
            img.paste(clips[m][i], (x, y))
            f = font(20, True)
            d.text((x + (tw - d.textlength(m, font=f)) / 2, y + th + 8), m, font=f, fill=(235, 235, 235))
        out.append(img)
    save_gif(out, [STEP_MS] * len(out), REPO / "documentation" / "media" / "moods.gif")


# --- Terminals ---------------------------------------------------------------

TERM_BG, TERM_FG, TERM_BAR = (24, 24, 28), (215, 215, 220), (44, 44, 50)
DOTS = [(255, 95, 86), (255, 189, 46), (39, 201, 63)]
COLOURS = {"2": (110, 110, 120), "1;34": (110, 170, 255), "1;33": (255, 196, 70), "1;37": (240, 240, 245),
           "1;32": (120, 220, 140), "1;35": (220, 140, 255), "36": (110, 210, 220)}
PROMPT = "\x1b[1;32m$\x1b[0m "
LINE_H = 25


def spans(s: str) -> list[tuple[str, str | None]]:
    out, code = [], None
    for part in re.split(r"(\x1b\[[0-9;]*m)", s):
        m = re.fullmatch(r"\x1b\[([0-9;]*)m", part)
        if m:
            code = None if m.group(1) in ("0", "") else m.group(1)
        elif part:
            out.append((part, code))
    return out


class Terminal:
    """A window that types commands and prints lines, a frame per change."""

    def __init__(self, title: str, cols: int, rows: int) -> None:
        self.title, self.rows = title, rows
        self.f, self.fb = font(17), font(17, True)
        self.size = (int(cols * self.f.getlength("M")) + 40, rows * LINE_H + 70)
        self.lines: list[str] = []
        self.frames: list[Image.Image] = []
        self.durations: list[int] = []

    def frame(self, ms: int, extra: str | None = None) -> None:
        W, H = self.size
        img = Image.new("RGB", (W, H), KEY)
        d = ImageDraw.Draw(img)
        d.rounded_rectangle((0, 0, W - 1, H - 1), radius=14, fill=TERM_BG)
        d.rounded_rectangle((0, 0, W - 1, 36), radius=14, fill=TERM_BAR)
        d.rectangle((0, 22, W - 1, 36), fill=TERM_BAR)
        for k, c in enumerate(DOTS):
            d.ellipse((16 + k * 22, 12, 28 + k * 22, 24), fill=c)
        d.text(((W - d.textlength(self.title, font=self.f)) / 2, 8), self.title, font=self.f, fill=(160, 160, 170))
        shown = (self.lines + ([extra] if extra is not None else []))[-self.rows :]
        for r, line in enumerate(shown):
            x, y = 20, 50 + r * LINE_H
            for text, code in spans(line):
                bold = bool(code) and code.startswith("1")
                d.text((x, y), text, font=self.fb if bold else self.f, fill=COLOURS.get(code, TERM_FG))
                x += self.f.getlength(text)
            if extra is not None and r == len(shown) - 1:
                d.rectangle((x + 2, y + 2, x + 11, y + 20), fill=TERM_FG)
        self.frames.append(img)
        self.durations.append(ms)

    def type(self, command: str, step: int = 1) -> None:
        self.frame(500, PROMPT)
        for i in range(1, len(command) + 1, step):
            self.frame(40, PROMPT + command[:i])
        self.lines.append(PROMPT + command)
        self.frame(350)

    def print(self, lines: list[str], pause: int = 0, gap: int = 60) -> None:
        if self.durations:
            self.durations[-1] += pause
        for line in lines:
            self.lines.append(line)
            self.frame(gap)

    def save(self, path: Path) -> None:
        self.frame(3500, PROMPT)
        save_gif(self.frames, self.durations, path, extra=DOTS + [TERM_FG])


def swift_build(package: str, *args: str) -> Path:
    subprocess.run(["swift", "build", *args], cwd=REPO / package, check=True, capture_output=True)
    out = subprocess.run(["swift", "build", *args, "--show-bin-path"], cwd=REPO / package, check=True,
                         capture_output=True, text=True)
    return Path(out.stdout.strip())


def watch_gif() -> None:
    """agent-hooks' Examples/watch.sh while hooks from two made-up sessions
    go through the real client, in a throwaway home and two git repos."""
    bin_dir = swift_build("agent-hooks")
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "src"
        for name, branch in (("landing", "fix-nav"), ("api", "rate-limits")):
            repo = src / name
            subprocess.run(["git", "init", "-q", "-b", branch, str(repo)], check=True)
            subprocess.run(["git", "-C", str(repo), "commit", "-q", "--allow-empty", "-m", "init"], check=True)
        hooks_dir = tempfile.mkdtemp(prefix="ah", dir="/tmp")  # a socket's path has room for 103 bytes
        env = {**os.environ, "HOME": tmp, "AGENT_HOOKS_DIR": hooks_dir}
        watch = subprocess.Popen([str(REPO / "agent-hooks/Examples/watch.sh"), str(bin_dir / "agent-hooks")],
                                 env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        time.sleep(1)
        L, A = str(src / "landing"), str(src / "api")
        script = [  # (agent, hook, pause after in s)
            ("claude", {"hook_event_name": "SessionStart", "session_id": "s1", "cwd": L, "source": "startup"}, .5),
            ("codex", {"hook_event_name": "SessionStart", "session_id": "c1", "cwd": A, "source": "startup"}, .7),
            ("claude", {"hook_event_name": "UserPromptSubmit", "session_id": "s1", "cwd": L, "prompt": "fix the nav"}, .7),
            ("codex", {"hook_event_name": "UserPromptSubmit", "session_id": "c1", "cwd": A, "prompt": "add rate limits"}, .7),
            ("codex", {"hook_event_name": "PreToolUse", "session_id": "c1", "cwd": A, "tool_name": "Bash",
                       "tool_use_id": "call_1", "tool_input": {"command": "cargo build"}}, .7),
            ("claude", {"hook_event_name": "PreToolUse", "session_id": "s1", "cwd": L, "tool_name": "Bash",
                        "tool_use_id": "toolu_1", "tool_input": {"command": "npm test"}}, .4),
            ("claude", {"hook_event_name": "PermissionRequest", "session_id": "s1", "cwd": L, "tool_name": "Bash",
                        "tool_input": {"command": "npm test"}}, 2.6),
            ("claude", {"hook_event_name": "PostToolUse", "session_id": "s1", "cwd": L, "tool_name": "Bash",
                        "tool_use_id": "toolu_1", "tool_response": {"stdout": "ok"}}, .7),
            ("codex", {"hook_event_name": "PostToolUse", "session_id": "c1", "cwd": A, "tool_name": "Bash",
                       "tool_use_id": "call_1", "tool_response": {"stdout": "ok"}}, .7),
            ("claude", {"hook_event_name": "Stop", "session_id": "s1", "cwd": L,
                        "last_assistant_message": "Fixed."}, 1),
        ]
        import json
        for agent, hook, pause in script:
            subprocess.run([str(bin_dir / "agent-hook"), agent], input=json.dumps(hook), env=env, text=True,
                           check=True)
            time.sleep(pause)
        subprocess.run(["pkill", "-f", "agent-hooks tail --sessions --name watch"])
        lines = watch.stdout.read().splitlines()
        shutil.rmtree(hooks_dir, ignore_errors=True)
    # One group per hook: its event line, then its session's line when it changed.
    groups: list[list[str]] = []
    for line in lines:
        if line.startswith("\x1b[2m") or not groups:
            groups.append([])
        groups[-1].append(line)
    term = Terminal("agent-hooks", cols=58, rows=19)
    term.type("Examples/watch.sh")
    for (_, _, pause), group in zip([(None, None, 0)] + script, groups):
        term.print(group, pause=int(pause * 1000))
    term.save(REPO / "agent-hooks" / "media" / "watch.gif")


def beacon_gif() -> None:
    """Beacon listening, and three builds sent to it with mellowharness-emit."""
    bin_dir = swift_build("mellowharness")
    sock = "/tmp/beacon-media.sock"
    beacon = subprocess.Popen([str(bin_dir / "beacon"), "listen", "--socket", sock], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, bufsize=1)
    first = beacon.stdout.readline().rstrip()
    builds = ["build_failed", "build_failed", "build_passed"]
    outputs = []
    for kind in builds:
        subprocess.run([str(bin_dir / "mellowharness-emit"), "--socket", sock, "ci", kind, "branch=main"],
                       check=True)
        time.sleep(1.5)
        out = []
        while True:  # this event's lines, up to its pass
            line = beacon.stdout.readline().rstrip()
            out.append(line)
            if line.lstrip().startswith("pass"):
                break
        outputs.append(out)
    beacon.terminate()

    def colour(line: str) -> str:
        s = line.lstrip()
        code = {"▸": "1;37", "✓": "1;32", "…": "36", "p": "1;35"}.get(s[:1], "2")
        return f"\x1b[{code}m{line}\x1b[0m"

    term = Terminal("mellowharness", cols=76, rows=16)
    term.type(f"beacon listen --socket {sock} &", step=3)
    term.print([colour(first)])
    for kind, out in zip(builds, outputs):
        term.type(f"mellowharness-emit --socket {sock} ci {kind} branch=main", step=3)
        term.print([colour(line) for line in out], gap=260)
        term.durations[-1] += 900
    term.save(REPO / "mellowharness" / "media" / "beacon.gif")


# --- The popover --------------------------------------------------------------


def stretch(pane: Image.Image, height: int) -> Image.Image:
    """The pane made `height` tall by repeating the plain row just above its
    footer's rule, so two panes' footers line up."""
    rows = [pane.crop((0, y, pane.width, y + 1)) for y in range(pane.height)]
    plain = [len(set(r.get_flattened_data())) == 1 for r in rows]
    # The footer's rule: the lowest plain row not the background's colour
    # (the pane's last row) with a plain background row above it.
    bg = rows[-1].getpixel((0, 0))
    rule = next(y for y in range(pane.height - 1, 0, -1)
                if plain[y] and plain[y - 1] and rows[y].getpixel((0, 0)) != bg and rows[y - 1].getpixel((0, 0)) == bg)
    fill = rows[rule - 1]
    out = Image.new("RGBA", (pane.width, height))
    out.paste(pane.crop((0, 0, pane.width, rule)), (0, 0))
    for y in range(rule, rule + height - pane.height):
        out.paste(fill, (0, y))
    out.paste(pane.crop((0, rule, pane.width, pane.height)), (0, rule + height - pane.height))
    return out


def popover_png() -> None:
    """Two of the popover's panes side by side, working and needs you, in
    each appearance, from `Boop --snapshots` (after `make build`)."""
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([str(REPO / ".build/debug/Boop"), "--snapshots", tmp], check=True, capture_output=True)
        for look in ("light", "dark"):
            panes = [Image.open(Path(tmp) / f"overview-{p}-{look}.png").convert("RGBA")
                     for p in ("working", "needs-you")]
            tallest = max(p.height for p in panes)
            panes = [stretch(p, tallest) for p in panes]
            gap = 40
            img = Image.new("RGBA", (sum(p.width for p in panes) + gap, max(p.height for p in panes)), (0, 0, 0, 0))
            x = 0
            for pane in panes:
                img.paste(pane, (x, 0))
                x += pane.width + gap
            path = REPO / "documentation" / "media" / f"popover-{look}.png"
            img.save(path, optimize=True)
            print(f"{path.relative_to(REPO)}: {img.width}x{img.height}, {path.stat().st_size // 1024} KB")


GIFS = {"boop": boop_gif, "moods": moods_gif, "popover": popover_png, "watch": watch_gif, "beacon": beacon_gif}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Makes the READMEs' pictures again, each from a real run.")
    parser.add_argument("names", nargs="*", metavar="NAME",
                        help=f"which to make: {', '.join(GIFS)} (all of them by default)")
    names = parser.parse_args().names or list(GIFS)
    for name in names:
        if name not in GIFS:
            parser.error(f"no picture named {name}: choose from {', '.join(GIFS)}")
    if {"boop", "moods"} & set(names):
        build_sim()
    for name in names:
        GIFS[name]()
