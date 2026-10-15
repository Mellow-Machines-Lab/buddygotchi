"""The pipeline check (internal/VERIFICATION.md L4): hook → app → USB → device.

Starts `linkkit-bridge` and a headless app with throwaway state, sends each
fixture's payloads through the real `agent-hook`, run as Boop installs it
(`--keep-text`), and checks the device's `dbg.state` at every checkpoint.
Latency is hook launch to the device having received the new `state` (its
`rx.state` count going up), on the host clock.

Fixture lines, besides hook payloads:
  {"wait_ms": N}                         sleep
  {"advance_ms": N}                      jump the app's clock (a long turn without the wait)
  {"expect": {...}, "within_ms": N}      poll dbg.state until it matches (default 2000 ms)
  {"expect_not": {...}, "for_ms": N}     dbg.state must not match for that long
  {"expect_not": {...}, "until_ms": N}   … until N ms after the last hook was launched
  "shot": "name" on an expect line       also save a screenshot
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any

from boopctl_lib.common import REPO, call, restarted
from boopctl_lib.device import Device, DeviceError
from boopctl_lib.headless import BIN, Headless, stop_proc
from boopctl_lib.image import save_shot
from boopctl_lib.scenario import matches

FIXTURES = REPO / "internal" / "app" / "Tests" / "Fixtures" / "hooks" / "e2e"
RUN_ORDER = ["claude/session.jsonl", "codex/quick.jsonl", "codex/slow.jsonl"]
# How long a hook's `state` may take before it counts as "no new state". A
# later one still fails the checkpoint that expects the change.
STATE_WAIT = 0.5


def percentile(values: list[float], p: float) -> float:
    s = sorted(values)
    if not s:
        return 0.0
    k = max(0, min(len(s) - 1, int(-(-len(s) * p // 1)) - 1))
    return s[k]


class Run:
    def __init__(self, root: Path, out: Path, brain: str, port: str | None) -> None:
        self.root = root
        self.out = out
        self.brain = brain
        self.port = port
        self.state = root / "state"
        self.debug_log = self.state / "debug.jsonl"
        self.bridge_sock = str(root / "usb.sock")
        self.hook_sock = str(root / "boop.sock")
        self.log: list[str] = []
        self.failures: list[str] = []
        self.hooks: list[dict[str, Any]] = []
        self.bridge: subprocess.Popen | None = None
        self.app = Headless(self.state, self.hook_sock, f"usb:{self.bridge_sock}", brain)
        self.last_hook = time.monotonic()

    def say(self, line: str) -> None:
        print(line, flush=True)
        self.log.append(line)

    def fail(self, line: str) -> None:
        self.failures.append(line)
        self.say("FAIL " + line)

    # Processes

    def start(self) -> None:
        if self.root.exists():
            shutil.rmtree(self.root)
        self.root.mkdir(parents=True)
        self.out.mkdir(parents=True, exist_ok=True)
        for name in ("Boop", "agent-hook", "linkkit-bridge"):
            if not (BIN / name).exists():
                raise DeviceError(f"no {BIN / name}; run make build")
        bridge = [str(BIN / "linkkit-bridge"), "--socket", self.bridge_sock] + (["--port", self.port] if self.port else [])
        self.bridge = subprocess.Popen(bridge, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.app.wait_for(lambda: os.path.exists(self.bridge_sock), 10, "the bridge's socket")
        self.app.start()
        # The first launch of a freshly built agent-hook is slow (~270 ms) while
        # macOS checks the new binary; agents run it hundreds of times a day.
        # Warm it once, against a socket nobody listens on.
        subprocess.run([str(BIN / "agent-hook"), "claude"], input=b"{}",
                       env=dict(os.environ, AGENT_HOOKS_SOCKET=str(self.root / "none.sock")))
        self.say(f"bridge and headless app up (brain {self.brain}, state {self.state})")

    def stop(self) -> None:
        if (code := self.app.stop()) is not None:
            self.say(f"Boop exit {code}")
        if self.bridge and self.bridge.poll() is None:
            self.say(f"linkkit-bridge exit {stop_proc(self.bridge)}")
        self.bridge = None

    # Steps

    def hook(self, dev: Device, agent: str, payload: str) -> None:
        before = dev.request({"t": "dbg.state"})["rx"]["state"]
        env = dict(os.environ, AGENT_HOOKS_SOCKET=self.hook_sock)
        t0 = self.last_hook = time.monotonic()
        proc = subprocess.run([str(BIN / "agent-hook"), agent, "--keep-text"], input=payload.encode(), env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        hook_ms = (time.monotonic() - t0) * 1000
        name = json.loads(payload).get("hook_event_name", "?")
        if proc.returncode != 0 or proc.stdout or proc.stderr:
            self.fail(f"agent-hook {name}: exit {proc.returncode}, printed {len(proc.stdout) + len(proc.stderr)} bytes")
        latency = None
        while time.monotonic() - t0 < STATE_WAIT:
            if dev.request({"t": "dbg.state"})["rx"]["state"] > before:
                latency = (time.monotonic() - t0) * 1000
                break
        self.hooks.append({"agent": agent, "hook": name, "hook_ms": round(hook_ms, 1),
                           "state_ms": None if latency is None else round(latency, 1)})
        self.say(f"  {agent} {name}: agent-hook {hook_ms:.0f} ms, " +
                 (f"state on the device after {latency:.0f} ms" if latency is not None else "no new state"))

    def advance(self, ms: int) -> None:
        self.app.send({"dev": "advance", "ms": ms})
        time.sleep(0.3)
        self.say(f"  app clock +{ms / 1000:.0f} s")

    def expect(self, dev: Device, step: dict[str, Any], where: str) -> None:
        want = step["expect"]
        end = time.monotonic() + step.get("within_ms", 2000) / 1000
        state: dict[str, Any] = {}
        t0 = time.monotonic()
        while True:
            state = dev.request({"t": "dbg.state"})
            if matches(want, state):
                self.say(f"  ok {json.dumps(want)} after {(time.monotonic() - t0) * 1000:.0f} ms")
                break
            if time.monotonic() > end:
                keys = {k: state.get(k) for k in ("screen", "base", "attn", "moment")}
                self.fail(f"{where}: expected {json.dumps(want)}, got {json.dumps(keys)}")
                break
        if step.get("shot"):
            path = save_shot(dev.shot(), self.out / f"{step['shot']}.png")
            self.say(f"  shot {path}")

    def expect_not(self, dev: Device, step: dict[str, Any], where: str) -> None:
        want = step["expect_not"]
        if "until_ms" in step:
            end = self.last_hook + step["until_ms"] / 1000
        else:
            end = time.monotonic() + step.get("for_ms", 1000) / 1000
        while time.monotonic() < end:
            state = dev.request({"t": "dbg.state"})
            if matches(want, state):
                self.fail(f"{where}: {json.dumps(want)} showed up too early")
                return
        self.say(f"  ok not {json.dumps(want)} until {(end - self.last_hook) * 1000:.0f} ms after the last hook")

    def fixture(self, dev: Device, path: Path) -> None:
        agent = "codex" if "/codex/" in str(path) else "claude"
        self.say(f"## {path.relative_to(REPO)}")
        for n, raw in enumerate(path.read_text().splitlines(), 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            step = json.loads(line)
            where = f"{path.name}:{n}"
            if "hook_event_name" in step:
                self.hook(dev, agent, line)
            elif "wait_ms" in step:
                time.sleep(step["wait_ms"] / 1000)
            elif "advance_ms" in step:
                self.advance(step["advance_ms"])
            elif "expect" in step:
                self.expect(dev, step, where)
            elif "expect_not" in step:
                self.expect_not(dev, step, where)
            else:
                self.fail(f"{where}: unknown step {line}")


def check_after(run: Run, events: list[str]) -> None:
    """The app's files and logs once the app has stopped: the `events` the
    harness should have seen, and nothing private."""
    brain_log = run.debug_log.read_text() if run.debug_log.exists() else ""
    for want in events:
        (run.say if want in brain_log else run.fail)(f"the harness saw an event with {want!r}: {want in brain_log}")
    # Nothing private may reach the app's files, debug.jsonl and the
    # transcript included, but your prompt and the agent's last message,
    # which `--keep-text` keeps: the fixtures mark them
    # PRIVATE_PROMPT and PRIVATE_CLOSING.
    leaks = []
    for f in run.state.rglob("*"):
        if f.is_file() and set(re.findall(r"PRIVATE_[A-Z]*", f.read_text(errors="replace"))) - KEPT_WORDS:
            leaks.append(str(f))
    (run.fail if leaks else run.say)(f"PRIVATE_ markers in app files or the brain log: {leaks or 'none'}")


# The fixtures' markers for the words that do get through.
KEPT_WORDS = {"PRIVATE_PROMPT", "PRIVATE_CLOSING"}


def order(log: str) -> list[dict[str, Any]]:
    """Every brain reaction sent in an app log, in order: when it was sent,
    how long after the rules' reaction to the last hook, how the device said
    it ended, whether the next reaction sent was the brain's or a rule's
    (`next_by`), and whose `now` came next (`now_by`), the only kind
    that cuts a busy one short.

    With --debug the app logs `hook: …` for each hook and `link rules → …` or
    `link brain → …` for each message sent to the device (a `state` sent again
    unchanged, such as the keepalive, only the first time), and always
    `device: do N ended HOW (WHY)` for the device's `ended` (linkkit/SPEC.md
    §4)."""
    stamp = re.compile(r"^(\d\d):(\d\d):(\d\d)\.(\d\d\d) (.*)$")
    ended_line = re.compile(r"^device: do (\d+) ended (\w+)(?: \((\w+)\))?$")
    how_ended: dict[int, str] = {}  # how each `do` ended, by id: "done", "cut (tap)"
    reactions: list[dict[str, Any]] = []
    # The reactions still waiting to learn who sent the next reaction, and
    # the next `now`.
    no_next: list[dict[str, Any]] = []
    no_now: list[dict[str, Any]] = []
    last_hook: str | None = None
    reaction: tuple[int, str] | None = None
    for raw in log.splitlines():
        m = stamp.match(raw)
        if not m:
            continue
        h, mi, s, ms, text = m.groups()
        t = (int(h) * 3600 + int(mi) * 60 + int(s)) * 1000 + int(ms)
        if text.startswith("hook: "):
            last_hook = text[6:]
        elif e := ended_line.match(text):
            how_ended[int(e.group(1))] = e.group(2) + (f" ({e.group(3)})" if e.group(3) else "")
        elif text.startswith(("link rules → ", "link brain → ")):
            by = text[5:10]
            line = json.loads(text[len("link rules → "):])
            if by == "rules" and last_hook and (reaction is None or reaction[1] != last_hook):
                reaction = (t, last_hook)
            c = call(line)
            if c is None:
                continue
            for a in no_next:
                a["next_by"] = by
            no_next.clear()
            if c["play"] == "now":
                for a in no_now:
                    a["now_by"] = by
                no_now.clear()
            if by == "brain":
                reactions.append({
                    "moment": c["anim"] or "line",  # a face with its line, and no animation
                    "at": raw[:12], "id": c["id"], "next_by": None, "now_by": None,
                    "after_reaction_ms": None if reaction is None else t - reaction[0],
                    "reaction_to": None if reaction is None else reaction[1],
                })
                no_next.append(reactions[-1])
                no_now.append(reactions[-1])
    for a in reactions:
        a["ended"] = how_ended.get(a["id"]) if a["id"] is not None else None
    return reactions


# How a brain reaction may end without anything being wrong (linkkit/SPEC.md
# §4): played through; cut by a tap, something needing you, a `now` from
# someone else or a reset; or skipped because it waited in the queue past its
# ttl, behind another's `say` (the Mac used to drop those before sending), or
# the device refused it (`nothing` when none of it would play). `skipped
# (unknown)` means the device doesn't play that name, and a `now` of the
# brain's own never cuts it: those fail.
FINE_ENDS = re.compile(r"^(done|cut \((tap|needs_you|now|reset)\)|skipped( \((late|busy|full|needs_you|no_app|listening|mic_on|"
                       r"not_listening|nothing|reset)\))?)$")


def check_order(run: Any) -> dict[str, Any]:
    """The brain's reactions come after the rules' reaction, and each gets
    the device's `ended` (linkkit/SPEC.md §4). The device queues the brain's
    reactions (`next`, up to 5 s), so a reaction that waited behind
    another's `say`, or was skipped for waiting too long, is fine; one the
    brain's own next reaction cut short isn't (the next waits until the
    one playing has played), nor is one the device didn't know. Each fixture ends
    with seconds to spare, so every brain reaction has its `ended` by then."""
    answers = order(run.app.log_text())
    # The log is written in order, so a brain line after the rules' line came
    # after it, even in the same millisecond: the scripted brain answers an
    # agent start at once.
    early = [a for a in answers if a["after_reaction_ms"] is None or a["after_reaction_ms"] < 0]
    unended = [a for a in answers if a["id"] is not None and a["ended"] is None]
    cut = [f"{a['at']} {a['moment']} ({a['id']}) by {a['now_by']}" for a in answers if a["ended"] == "cut (now)"]
    cut_by_brain = [c for c in cut if c.endswith("by brain")]
    odd = [f"{a['at']} {a['moment']} ({a['id']}) {a['ended']}" for a in answers
           if a["ended"] is not None and not FINE_ENDS.match(a["ended"])]
    queued = [a for a in answers if (a["ended"] or "").startswith("skipped")]
    for a in answers:
        run.say(f"  {a['at']} brain {a['moment']}: {a['after_reaction_ms']} ms after the rules' reaction to "
                f"{a['reaction_to']}; the device said it ended {a['ended']}")
    run.say(f"brain reactions: {len(answers)}, early: {len(early)}, cut short by a newer `now`: {cut or 'none'}, "
            f"skipped: {len(queued)}, with no `ended` from the device: {len(unended)}")
    if early:
        run.fail(f"{len(early)} brain reactions came before the rules' reaction")
    if cut_by_brain:
        run.fail(f"{len(cut_by_brain)} brain reactions were cut short by the brain's next one: {cut_by_brain}")
    if odd:
        run.fail(f"{len(odd)} brain reactions ended in a way nothing should end them: {odd}")
    if unended:
        run.fail(f"{len(unended)} brain reactions never got the device's `ended`: {[a['id'] for a in unended]}")
    return {"brain_moments": len(answers), "early": len(early), "cut_by_newer": cut, "skipped": len(queued),
            "odd_ends": odd, "unended": len(unended), "answers": answers}


def main(out: Path, brain: str, port: str | None, fixtures: list[str] | None, clip: bool = False,
         camera: str | None = None) -> int:
    root = Path("/tmp/boop-e2e")
    run = Run(root, out, brain, port)
    expected = json.loads((FIXTURES / "expect.json").read_text())
    paths = [FIXTURES / f for f in (fixtures or RUN_ORDER)]
    started = time.time()
    try:
        run.start()
        os.environ["BOOP_BRIDGE"] = run.bridge_sock
        with Device() as dev:
            if clip:
                # L3: a short Claude session through the whole pipeline, on
                # camera (VERIFICATION.md §6: authorised runs only).
                from boopctl_lib import cam

                session = FIXTURES / "claude" / "clip.jsonl"
                result = cam.clip(dev, "e2e-session", camera or cam.CAMERA, seconds=10, frames=24,
                                  play=lambda: run.fixture(dev, session))
                shutil.copy(result["sheet"], out / "clip-e2e-session.png")
                run.say(f"clip {out / 'clip-e2e-session.png'}")
            for path in paths:
                run.fixture(dev, path)
    except DeviceError as exc:
        run.fail(str(exc))
    finally:
        run.stop()
    for gone in (run.hook_sock, run.bridge_sock):
        (run.fail if os.path.exists(gone) else run.say)(f"{gone} removed: {not os.path.exists(gone)}")

    lat = [h["state_ms"] for h in run.hooks if h["state_ms"] is not None]
    p50, p95 = percentile(lat, 0.5), percentile(lat, 0.95)
    run.say(f"latency, hook launch to state on the device: n {len(lat)}/{len(run.hooks)} hooks, "
            f"p50 {p50:.0f} ms, p95 {p95:.0f} ms, max {max(lat, default=0):.0f} ms")
    if not lat or p95 >= 200:
        run.fail(f"p95 latency {p95:.0f} ms is not under 200 ms")
    # expect.json's events are the whole run's; a part of it is still
    # checked for private words.
    check_after(run, expected["events"] if fixtures is None and not clip else [])
    order = check_order(run)

    if (run.state / "boop.log").exists():
        shutil.copy(run.state / "boop.log", out / f"app-{brain}.log")
    for name in ("long-term.md", "settings.json"):
        if (run.state / name).exists():
            shutil.copy(run.state / name, out / f"{brain}-{name}")
    result = {"brain": brain, "started": started, "seconds": round(time.time() - started), "hooks": run.hooks,
              "latency": {"p50": p50, "p95": p95, "n": len(lat)}, "order": order,
              "failures": run.failures, "ok": not run.failures}
    (out / f"e2e-{brain}.json").write_text(json.dumps(result, indent=2))
    (out / f"e2e-{brain}.txt").write_text("\n".join(run.log) + "\n")
    print("PASS" if not run.failures else f"FAIL ({len(run.failures)})")
    return 0 if not run.failures else 1


def soak(out: Path, brain: str, port: str | None, minutes: float) -> int:
    """J2's soak: the e2e fixtures on a loop through the whole pipeline, with
    a tap on the board between rounds, for `minutes`. Samples the board
    (resets, heap, audio errors) and the app (alive, memory), counts
    checkpoint misses, and at the end checks that calm brings back the plain
    face with nothing stuck."""
    root = Path("/tmp/boop-soak")
    run = Run(root, out, brain, port)
    samples: list[dict[str, Any]] = []
    rounds, misses = 0, 0
    glitches: list[str] = []
    started = time.time()
    t0 = time.monotonic()
    final: dict[str, Any] = {}

    def sample(dev: Device) -> None:
        vitals = dev.vitals()
        st = dev.request({"t": "dbg.state"})
        app = run.app.proc
        assert app
        rss = subprocess.run(["ps", "-o", "rss=", "-p", str(app.pid)], capture_output=True, text=True).stdout.strip()
        samples.append({"t": round(time.monotonic() - t0, 1), **vitals,
                        "audio_errors": st.get("audio", {}).get("out", {}).get("errors"),
                        "app_alive": app.poll() is None, "app_rss_kb": int(rss) if rss else None})

    try:
        run.start()
        os.environ["BOOP_BRIDGE"] = run.bridge_sock
        with Device() as dev:
            # A lost reply or short shot (Link.retries) is asked for again
            # once and the glitch counted; a second loss in a row still
            # fails the soak.
            def glitch(exc: Exception) -> None:
                glitches.append(f"{time.monotonic() - t0:.0f} s: {exc}"[:160])
                run.say(f"  link glitch, retrying: {glitches[-1]}")

            dev.retries, dev.on_retry = 1, glitch
            sample(dev)
            while time.monotonic() - t0 < minutes * 60:
                rounds += 1
                run.say(f"# round {rounds} at {(time.monotonic() - t0) / 60:.1f} min")
                for f in RUN_ORDER:
                    before = len(run.failures)
                    run.fixture(dev, FIXTURES / f)
                    misses += len(run.failures) - before
                    sample(dev)
                    if not samples[-1]["app_alive"]:
                        raise DeviceError("the headless app exited")
                dev.request({"t": "dbg.press", "ms": 100})  # a tap: the device's poke, noted in the transcript
                time.sleep(3)
            # Nothing stuck: once every session has stopped and a quiet minute
            # has passed, the board is back on the plain face.
            time.sleep(60)
            final = dev.request({"t": "dbg.state"})
            sample(dev)
    except DeviceError as exc:
        run.fail(str(exc))
    finally:
        run.stop()

    # The first sample after 2 minutes; none when the run never started.
    later = next((s for s in samples if s["t"] >= 120), samples[-1] if samples else {})
    errors = [s["audio_errors"] or 0 for s in samples]
    rss = [s["app_rss_kb"] for s in samples if s["app_rss_kb"]]
    lat = [h["state_ms"] for h in run.hooks if h["state_ms"] is not None]
    result = {
        "brain": brain, "minutes": round((time.monotonic() - t0) / 60, 1), "rounds": rounds,
        "hooks": len(run.hooks), "checkpoint_misses": misses, "link_glitches": glitches,
        "latency": {"p50": percentile(lat, 0.5), "p95": percentile(lat, 0.95), "n": len(lat)},
        "reset": restarted([s["up"] for s in samples]),
        "heap_min_after_2min": later.get("heap_min"), "heap_min_end": samples[-1]["heap_min"] if samples else None,
        "heap_min_drift": later["heap_min"] - samples[-1]["heap_min"] if samples else None,
        "audio_errors": max(errors, default=0) - min(errors, default=0),
        "app_rss_kb": {"after_2min": later.get("app_rss_kb"), "end": rss[-1] if rss else None,
                       "max": max(rss, default=None)},
        "app_exited_early": any(not s["app_alive"] for s in samples),
        "final": {k: final.get(k) for k in ("screen", "base", "attn", "moment")},
    }
    stuck = final.get("screen") != "face" or final.get("attn") is not None or final.get("moment") is not None
    result["stuck"] = stuck
    result["failures"] = run.failures
    result["ok"] = (not result["reset"] and not stuck and not result["app_exited_early"]
                    and (result["heap_min_drift"] or 0) <= 2048 and result["audio_errors"] == 0)
    out.mkdir(parents=True, exist_ok=True)
    (out / f"soak-{brain}.json").write_text(json.dumps({**result, "series": samples}, indent=1))
    (out / f"soak-{brain}.txt").write_text("\n".join(run.log) + "\n")
    if (run.state / "boop.log").exists():
        shutil.copy(run.state / "boop.log", out / f"soak-app-{brain}.log")
    if run.debug_log.exists():
        shutil.copy(run.debug_log, out / f"soak-brain-{brain}.jsonl")
    print(json.dumps({k: v for k, v in result.items() if k != "failures"}, indent=1))
    print("PASS" if result["ok"] else "FAIL")
    return 0 if result["ok"] else 1
