"""Client helpers for scene scripts."""
import json, socket, time, sys, os

CTRL = os.environ.get("BRD", "/tmp/brd.sock")
_s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
_s.connect(CTRL)
_f = _s.makefile("rw")

def _c(cmd):
    _f.write(json.dumps(cmd) + "\n"); _f.flush()
    return json.loads(_f.readline())

def mark(name):
    print("== " + name, flush=True)
    return _c({"mark": name})

def sl(s):
    time.sleep(s)

def dev(**kw):
    return _c({"dev": kw})

def adv(ms=0, s=0, m=0, h=0):
    return dev(dev="advance", ms=int(ms + 1000 * (s + 60 * (m + 60 * h))))

def board(wait=1.0, **kw):
    r = _c({"board": kw, "wait": wait})["reply"]
    return json.loads(r) if r else None

def bstate(*keys):
    r = board(t="dbg.state")
    if r is None:
        print("   board: no reply"); return None
    if keys:
        r2 = {k: r.get(k) for k in keys}
    else:
        r2 = {k: v for k, v in r.items() if k not in ("t", "clock", "rx")}
    print("   board:", json.dumps(r2)[:900], flush=True)
    return r

class Agent:
    def __init__(self, sid, cwd, agent="claude"):
        self.sid, self.cwd, self.agent, self.n = sid, cwd, agent, 0

    def h(self, name, **kw):
        p = {"hook_event_name": name, "session_id": self.sid, "cwd": self.cwd}
        p.update(kw)
        r = _c({"hook": self.agent, "p": p})
        if r.get("rc"):
            print("   hook rc", r)
        return r

    def start(self):
        return self.h("SessionStart", source="startup")

    def prompt(self, text):
        return self.h("UserPromptSubmit", prompt=text)

    def pre(self, tool, inp, **kw):
        self.n += 1
        self.tid = "toolu_%s_%d" % (self.sid, self.n)
        self.tool, self.inp = tool, inp
        return self.h("PreToolUse", tool_name=tool, tool_use_id=self.tid, tool_input=inp, **kw)

    def post(self, resp=None, **kw):
        return self.h("PostToolUse", tool_name=self.tool, tool_use_id=self.tid, tool_input=self.inp,
                      tool_response=resp or {"stdout": "ok"}, **kw)

    def fail(self, error="Exit code 1\nboom", **kw):
        return self.h("PostToolUseFailure", tool_name=self.tool, tool_use_id=self.tid, tool_input=self.inp, error=error, **kw)

    def call(self, tool, inp, gap=0.15, fails=False, **kw):
        self.pre(tool, inp, **kw); sl(gap)
        return self.fail(**kw) if fails else self.post(**kw)

    def bash(self, cmd, fails=False, gap=0.15, **kw):
        return self.call("Bash", {"command": cmd}, fails=fails, gap=gap, **kw)

    def edit(self, path, old="a\n", new="a\nb\nc\n", **kw):
        return self.call("Edit", {"file_path": path, "old_string": old, "new_string": new}, **kw)

    def read(self, path, **kw):
        return self.call("Read", {"file_path": path}, **kw)

    def ask(self, **kw):
        return self.h("PermissionRequest", tool_name=self.tool, tool_use_id=self.tid, tool_input=self.inp, **kw)

    def stop(self, msg="All done. The tests pass now."):
        return self.h("Stop", last_assistant_message=msg)

    def stopfail(self, error="rate_limit", msg="I hit an error."):
        return self.h("StopFailure", error=error, last_assistant_message=msg)

    def end(self):
        return self.h("SessionEnd", reason="exit")

    def kill(self):
        """The agent's process ends with no SessionEnd (terminal closed)."""
        return _c({"kill": self.sid})

def stroke(): return board(t="dbg.touch", x=60, y=120, to_x=200, to_y=120, ms=300)
def ruffle(): return board(t="dbg.touch", x=160, y=180, to_x=160, to_y=60, ms=300)
def poke(x=90, y=80): return board(t="dbg.touch", x=x, y=y, ms=60)
def nose(): return board(t="dbg.touch", x=160, y=134, ms=60)
def lean(ms=2500): return board(t="dbg.touch", x=120, y=110, ms=ms)
def shake():
    board(t="dbg.imu", ax=0, ay=0, az=1000); sl(0.3)
    for az in (1700, 300, 1700, 1000):
        board(t="dbg.imu", ax=0, ay=0, az=az); sl(0.06)
def said(words): return dev(dev="said", words=words)
def xp():
    r = board(t="dbg.state")
    print("   xp:", r and r.get("xp"), "moment:", r and r.get("moment"), "reason:", r and r.get("reason"), "life:", r and r.get("life"), flush=True)
    return r
