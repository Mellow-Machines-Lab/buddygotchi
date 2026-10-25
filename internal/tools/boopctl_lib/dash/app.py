"""`boopctl dash`: Boop's live dashboard. Boop now, with
the face, and three columns side by side: the mood, the automatic reactions
(reflexes) and the decided ones (Jev's), all from debug.jsonl, with the raw
timeline a key away; and keys that force a mood, a reaction or an
animation, or preview any look on the dashboard's own sim. A bug report the
app saves (its ladybug, or `b` here) gets the device's screen, screen.png,
when the app reaches its device through a socket: the simulator's, or a
board's bridge."""
from __future__ import annotations

import json
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any, Callable, Protocol

from rich.table import Table
from rich.text import Text
from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, VerticalScroll
from textual.message import Message
from textual.screen import ModalScreen
from textual.widgets import Footer, Label, OptionList, RichLog, Static

from boopctl_lib.common import MOODS, send_line
from boopctl_lib.dash import controls
from boopctl_lib.device import Device, DeviceError
from boopctl_lib.image import save_shot
from boopctl_lib.dash.feed import Board, Follower, clock, kind

STYLES = {"event": "bold", "pass": "cyan", "ok": "green", "fail": "red", "sent": "magenta", "status": "yellow",
          "head": "bold underline", "dim": "grey62", "mood": "bold yellow", "attn": "bold magenta",
          "playing": "bold cyan"}
# The columns keep this many rows each; the timeline (`t`) keeps the rest.
COLUMN_ROWS = 400
# Narrower than this, the three columns stack; narrower still, so does Boop now.
STACK_COLUMNS = 150
STACK_TOP = 120
# Preview resends its state this often: the device shows the no-app look
# after 30 s without one.
PREVIEW_RESEND_S = 10
LEAVE = "leave Preview"
# How long a new bug report may take to show up (`b`), and its about.json
# after it.
REPORT_S = 5.0


class Face(Protocol):
    def start(self) -> None: ...
    def stop(self) -> None: ...
    def send(self, message: dict) -> None: ...
    def restart(self, state: dict | None) -> None: ...


class Frame(Message):
    """From the sim's thread, without waiting on the app: a drawn frame, or
    why the sim stopped."""

    def __init__(self, text: Text | None, error: str = "") -> None:
        super().__init__()
        self.text, self.error = text, error

    def can_replace(self, message: Message) -> bool:
        # A frame the app hasn't drawn yet is stale once a newer one comes.
        return isinstance(message, Frame) and message.text is not None and self.text is not None


class Picker(ModalScreen[str | None]):
    """One choice from a list; Escape cancels."""

    BINDINGS = [Binding("escape", "dismiss(None)", "cancel")]
    DEFAULT_CSS = """
    Picker { align: center middle; }
    Picker > Label { width: 70; background: $panel; padding: 0 1; }
    Picker > OptionList { width: 70; height: auto; max-height: 16; }
    """

    def __init__(self, title: str, choices: list[str]) -> None:
        super().__init__()
        self.title_text, self.choices = title, choices

    def compose(self) -> ComposeResult:
        yield Label(self.title_text)
        yield OptionList(*self.choices)

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        self.dismiss(self.choices[event.option_index])


class StateView(ModalScreen[None]):
    """The whole state the brain read last."""

    BINDINGS = [Binding("escape,s,q", "dismiss(None)", "close")]
    DEFAULT_CSS = "StateView { background: $background 90%; } StateView > VerticalScroll { border: round $accent; }"

    def __init__(self, state: str) -> None:
        super().__init__()
        self.state = state

    def compose(self) -> ComposeResult:
        with VerticalScroll() as scroll:
            scroll.border_title = "the prompt Jev read (s or Escape closes)"
            yield Static(Text(self.state))


class Dash(App[None]):
    TITLE = "Boop dashboard"
    ENABLE_COMMAND_PALETTE = False
    CSS = """
    #stale { display: none; background: $error; color: $text; padding: 0 1; text-style: bold; }
    #stale.shown { display: block; }
    #top { height: auto; }
    #face { width: auto; min-width: 85; height: auto; min-height: 34; border: round $accent; }
    #facts { width: 1fr; height: 34; border: round $primary; padding: 0 1; }
    #columns { height: 1fr; }
    #columns > VerticalScroll { width: 1fr; height: 1fr; border: round $primary; padding: 0 1; }
    #timeline { height: 0; border: none; }
    #timeline.shown { height: 1fr; border: round $primary; }
    Screen.stack-top #top { layout: vertical; }
    Screen.stack-top #facts { width: 1fr; height: auto; }
    Screen.stack-columns #columns { layout: vertical; height: auto; }
    Screen.stack-columns #columns > VerticalScroll { width: 1fr; height: auto; max-height: 24; }
    Screen.stack-columns { overflow-y: auto; }
    """
    BINDINGS = [
        Binding("m", "mood", "mood"),
        Binding("r", "react", "react"),
        Binding("p", "preview", "preview"),
        Binding("t", "timeline", "toggle timeline"),
        Binding("s", "state", "Jev's state"),
        Binding("b", "report", "bug report"),
        Binding("q", "quit", "quit"),
    ]

    def __init__(self, debug_log: Path, socket_path: str,
                 make_face: Callable[[Callable[[Text], None], Callable[[str], None]], Face] | None = None) -> None:
        super().__init__()
        self.follower = Follower(debug_log)
        self.socket_path = socket_path
        self.board = Board()
        self.pending = controls.Pending()
        self.first = True
        self.look: str | None = None  # Preview's look; None is live
        self.look_mood: str | None = None  # Preview's mood; None is the app's
        self.face_lines = -1  # the drawn face's height, less one
        self.now = time.time  # the wall clock, for the stale-log banner; tests replace it
        self.was_stale: bool | None = None
        self.reports = debug_log.parent / "bug-reports"
        self.reports_seen: set[str] | None = None
        self.unread: dict[Path, float] = {}  # new reports waiting for their about.json, by when they came
        self.report_asked: float | None = None  # when `b` asked for one
        self.copy = copy_text  # tests replace it
        self.face = make_face(lambda text: self.post_message(Frame(text)),
                              lambda why: self.post_message(Frame(None, why))) if make_face else None

    def compose(self) -> ComposeResult:
        # Kept, since queries only search the screen on top, such as a picker.
        self.face_view = Static("starting the native simulator…" if self.face else "no sim", id="face")
        self.banner = Static(id="stale")
        self.facts = Static(id="facts")
        self.columns = {name: Static(id=name) for name in ("mood", "reflexes", "decided")}
        self.timeline = RichLog(id="timeline", wrap=True, max_lines=5000)
        yield self.banner
        with Horizontal(id="top"):
            yield self.face_view
            yield self.facts
        titles = {"mood": "Mood · the lasting backdrop",
                  "reflexes": "Automatic · reflexes, by rule, at once",
                  "decided": "Decided · by Jev, a moment later"}
        with Horizontal(id="columns"):
            for name, widget in self.columns.items():
                with VerticalScroll(id=f"{name}-col") as column:
                    column.border_title = titles[name]
                    yield widget
        yield self.timeline
        yield Footer()

    def on_mount(self) -> None:
        self.facts.border_title = f"Boop now · {self.follower.path.parent}"
        self.timeline.border_title = "timeline · every line of debug.jsonl (t hides it)"
        self.stack(self.size.width)
        self.title_face()
        if self.face:
            self.face.start()
        self.poll()
        self.set_interval(0.25, self.poll)
        self.set_interval(PREVIEW_RESEND_S, self.keep_preview)

    def on_unmount(self) -> None:
        if self.face:
            self.face.stop()

    # Reading debug.jsonl.

    def poll(self) -> None:
        restarted, lines = self.follower.read()
        if restarted:
            self.board = Board()
            self.timeline.write(Text("— debug.jsonl started again: Boop restarted —", "yellow"), width=self.row_width())
        # At the start and after a restart the sim gets only the latest
        # state, never old reactions; after that, every line as it lands.
        catching_up = self.first or restarted
        live = self.face and self.look is None
        for line in lines:
            row = self.board.apply(line)
            if row:
                self.timeline.write(Text(f"{clock(line.get('received_at_ms', 0))} {row[1]}", STYLES[row[0]]),
                                    width=self.row_width())
            if done := self.pending.seen(line):
                self.notify(f"{done}: landed")
            if live and not catching_up and kind(line) == "sent":
                self.face.send(line["sent"])
        if live and catching_up and (lines or restarted):
            self.face.restart(self.board.state)
        self.first = False
        for late in self.pending.late():
            self.notify(f"{late}: nothing in debug.jsonl within {controls.CONFIRM_S:g} s. Is Boop running with --debug?",
                        severity="warning")
        self.watch_reports()
        self.show_now()
        if lines or restarted or not self.board.questions:
            self.show_columns()

    # Bug reports.

    def watch_reports(self, now: float | None = None) -> None:
        """New folders in bug-reports/, from the popover's ladybug or `b`.
        Each waits for its about.json, which the app writes last, to say
        how the app reached its device."""
        now = time.monotonic() if now is None else now
        try:
            names = {p.name for p in self.reports.iterdir() if p.is_dir()}
        except OSError:
            names = set()
        if self.reports_seen is None:
            self.reports_seen = names
        for name in sorted(names - self.reports_seen):
            self.unread[self.reports / name] = now
            if self.report_asked is not None:
                self.report_asked = None
                self.copy(str(self.reports / name))
        self.reports_seen = names
        for folder, came in list(self.unread.items()):
            try:
                about = json.loads((folder / "about.json").read_text())
            except (OSError, ValueError):
                if now - came > REPORT_S:
                    del self.unread[folder]
                    self.notify(f"bug report saved, with no about.json: {folder}", severity="warning")
                continue
            del self.unread[folder]
            self.timeline.write(Text(f"bug report saved: {folder}", STYLES["attn"]), width=self.row_width())
            link = about.get("link") or ""
            if link.startswith("usb:") and about.get("connected"):
                self.notify(f"bug report saved: {folder}. Adding the device's screen…")
                self.save_screen(folder, link[len("usb:"):])
            elif not about.get("connected"):
                self.notify(f"bug report saved: {folder} (no device connected, so no screen)")
            else:
                self.notify(f"bug report saved: {folder} (its device is on {link}, which only the app can ask, so no screen)")
        if self.report_asked is not None and now - self.report_asked > REPORT_S:
            self.report_asked = None
            self.notify(f"no bug report in {self.reports} within {REPORT_S:g} s. Is Boop running with --debug?",
                        severity="warning")

    @work(thread=True)
    def save_screen(self, folder: Path, bridge: str) -> None:
        """The device's screen, through the socket the app reaches it by,
        as any tool on that bridge asks for it: the simulator's, or a
        board's."""
        try:
            with Device(bridge=bridge) as device:
                save_shot(device.shot(), folder / "screen.png")
            self.call_from_thread(self.notify, f"bug report: added the device's screen, {folder / 'screen.png'}")
        except (DeviceError, OSError, ValueError) as exc:
            self.call_from_thread(self.notify, f"bug report: couldn't get the device's screen: {exc}", severity="warning")

    def row_width(self) -> int:
        """The timeline's rows wrap to the screen, less its border and
        scrollbar, even while it's hidden and has no width of its own."""
        return max(40, self.size.width - 4)

    def show_now(self) -> None:
        """Boop now and the stale-log banner, every poll: what's showing
        and whether the log is live depend on the time."""
        now_ms = int(self.now() * 1000)
        stale = self.board.stale(now_ms)
        if stale != self.was_stale:
            self.was_stale = stale
            self.banner.set_class(stale, "shown")
        if stale:
            newest = self.board.newest_ms
            self.banner.update(
                f"No live log: the newest line is from {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(newest / 1000))}. "
                "Start Boop with make dev." if newest else
                f"No live log: {self.follower.path} has no lines yet. Start Boop with make dev.")
        facts = Table.grid(padding=(0, 1))
        facts.add_column(style="bold", no_wrap=True)
        facts.add_column()
        for name, value in self.board.facts(now_ms):
            facts.add_row(name, value)
        self.facts.update(facts, layout=bool(self.screen_stack) and self.screen_stack[0].has_class("stack-top"))

    def show_columns(self) -> None:
        board = self.board
        for name, rows in (("mood", board.mood_column()), ("reflexes", board.reflex_column()),
                           ("decided", board.decided_column())):
            self.columns[name].update(Text("\n").join(Text(text, STYLES[style]) for style, text in rows[:COLUMN_ROWS]))

    def on_resize(self, event) -> None:
        self.stack(event.size.width)

    def stack(self, width: int) -> None:
        if self.screen_stack:  # the columns' screen, under any picker
            self.screen_stack[0].set_class(width < STACK_COLUMNS, "stack-columns")
            self.screen_stack[0].set_class(width < STACK_TOP, "stack-top")

    def on_frame(self, frame: Frame) -> None:
        if frame.text is None:
            self.notify(frame.error, severity="error")
            return
        # Laid out again only when its size changes: the first frame, and `z`.
        lines = frame.text.plain.count("\n")
        self.face_view.update(frame.text, layout=lines != self.face_lines)
        self.face_lines = lines

    def title_face(self) -> None:
        mode = f"PREVIEW: {self.look}" if self.look else "live"
        self.face_view.border_title = f"face · {mode}"

    # The keys.

    def command(self, line: dict[str, Any]) -> None:
        if why := send_line(self.socket_path, line):
            self.notify(why, severity="error")
        else:
            self.pending.add(line)

    async def pick(self, title: str, choices: list[str]) -> str | None:
        return await self.push_screen_wait(Picker(title, choices))

    def questions(self, action: str) -> list[dict]:
        asked = controls.asked_by(self.board.questions, action)
        if not asked:
            self.notify("no questions line in debug.jsonl yet. Is Boop running with --debug?", severity="warning")
        return asked

    @work
    async def action_mood(self) -> None:
        # Any mood, as the app's dev line takes any: Jev is offered only
        # the graph's moves from the mood now.
        asked = self.questions("mood")
        mood = asked and await self.pick("Preview a mood" if self.look else "Set the mood", list(MOODS))
        if mood and not self.look:
            self.command({"dev": "mood", "mood": mood})
        elif mood and self.face:
            self.look_mood = mood
            self.keep_preview()

    @work
    async def action_react(self) -> None:
        asked = self.questions("react")
        if not asked:
            return
        if self.look:
            # Preview: any reaction, its face, its animation, how long it
            # holds and the take it says, straight to the dashboard's sim.
            face = await self.pick("Preview a reaction: the face", [o for o in controls.options(asked[0]) if o != "none"])
            anims = [o for q in asked if q["key"] == "react.animation" for o in controls.options(q)]
            anim = face and (await self.pick("…its animation", anims) if anims else "none")
            holds = [o for q in asked if q["key"] == "react.loops" for o in controls.options(q)]
            hold = anim and (await self.pick("…how long it holds", holds) if holds else "once")
            said = {f"{t.text} ({t.id})": t.id for t in controls.takes()}
            take = hold and await self.pick("…and what it says", ["nothing"] + list(said))
            if take and self.face:
                loops = holds.index(hold) + 1 if hold in holds else 1
                try:
                    line = controls.preview_reaction(face, said.get(take), loops,
                                                     None if anim == "none" else anim)
                    self.face.send(line)
                except DeviceError as exc:
                    self.notify(str(exc), severity="error")
            return
        choices = {}
        for q in asked:
            choice = await self.pick(f"Force a pass · {q['key']}: {q['text']}", controls.options(q))
            if choice is None:
                return
            choices[q["key"]] = choice
        self.command({"dev": "answer", "answers": choices})

    @work
    async def action_preview(self) -> None:
        pick = await self.pick("Preview a look on the dashboard's sim only", controls.LOOKS + ([LEAVE] if self.look else []))
        if not pick or not self.face:
            return
        if pick == LEAVE:
            self.look = self.look_mood = None
            self.face.restart(self.board.state)
        else:
            self.look = pick
            self.keep_preview()
        self.title_face()

    def keep_preview(self) -> None:
        """Preview's look on the sim: when it changes, and every
        PREVIEW_RESEND_S."""
        if self.look and self.face:
            self.face.send(controls.preview_state(self.board.state, self.look, self.look_mood))

    def action_state(self) -> None:
        if self.board.jev_state:
            self.push_screen(StateView(self.board.jev_state))
        else:
            self.notify("no brain pass yet, so no state to show")

    def action_timeline(self) -> None:
        self.timeline.set_class(not self.timeline.has_class("shown"), "shown")

    def action_report(self) -> None:
        """A bug report, as the popover's ladybug saves it; its path is
        copied when it comes."""
        if why := send_line(self.socket_path, {"dev": "report"}):
            self.notify(why, severity="error")
        else:
            self.report_asked = time.monotonic()


def copy_text(text: str) -> None:
    if shutil.which("pbcopy"):
        subprocess.run(["pbcopy"], input=text.encode(), check=False)


def run(state_dir: Path, socket_path: str, sim_program: str) -> None:
    from boopctl_lib.dash.face import SimFace

    Dash(state_dir / "debug.jsonl", socket_path,
         make_face=lambda on_frame, on_error: SimFace(sim_program, on_frame, on_error)).run()
