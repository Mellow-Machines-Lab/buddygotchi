#!/usr/bin/env python3
"""Driver daemon for the review: stays alive as the 'agent process' of every
hook it runs, keeps one connection to the simulator board's bridge, and takes
commands on a unix socket (one JSON line in, one JSON line out)."""
import json, os, socket, subprocess, sys, threading, time, datetime

ROOT = "/tmp/boop-review/runtime"
WT = "/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish"
HOOK = WT + "/.build/debug/agent-hook"
HOOK_SOCK = sys.argv[1] if len(sys.argv) > 1 else "/tmp/br1/boop.sock"
BRIDGE = sys.argv[2] if len(sys.argv) > 2 else "/tmp/brb.sock"
CTRL = sys.argv[3] if len(sys.argv) > 3 else "/tmp/brd.sock"
HOME = "/tmp/brhome"
os.makedirs(HOME + "/.agent-hooks", exist_ok=True)
os.makedirs(HOME + "/.codex", exist_ok=True)
ENV = {"AGENT_HOOKS_SOCKET": HOOK_SOCK, "HOME": HOME, "AGENT_HOOKS_DIR": HOME + "/.agent-hooks",
       "CODEX_HOME": HOME + "/.codex", "PATH": "/usr/bin:/bin"}

def ts():
    return datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]

board_lock = threading.Lock()
board_sock = None
replies = []
replies_cv = threading.Condition()
boardlog = open(ROOT + "/board.log", "a", buffering=1)

def board_reader():
    global board_sock
    while True:
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(BRIDGE)
            board_sock = s
            buf = b""
            while True:
                d = s.recv(65536)
                if not d:
                    break
                buf += d
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    t = line.decode(errors="replace")
                    if len(t) > 3000:
                        t = t[:200] + "...(%d bytes)" % len(t)
                    if '"dbg.' in t[:14]:
                        with replies_cv:
                            replies.append(t)
                            replies_cv.notify_all()
                    else:
                        boardlog.write(ts() + " board> " + t + "\n")
        except OSError:
            pass
        board_sock = None
        time.sleep(1)

if BRIDGE != "none":
    threading.Thread(target=board_reader, daemon=True).start()

def board(msg, wait=1.0):
    with replies_cv:
        replies.clear()
    with board_lock:
        board_sock.sendall(json.dumps(msg, separators=(",", ":")).encode() + b"\n")
    end = time.time() + wait
    with replies_cv:
        while time.time() < end:
            for r in replies:
                if ('"t":"%s"' % msg["t"]) in r:
                    return r
            replies_cv.wait(0.05)
    return None

HELPER = """
import sys, json, subprocess
for line in sys.stdin:
    c = json.loads(line)
    p = subprocess.run(c["argv"], input=json.dumps(c["p"]).encode(), env=c["env"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    sys.stdout.write(json.dumps({"rc": p.returncode, "out": (p.stdout + p.stderr).decode(errors="replace")[:200]}) + "\\n"); sys.stdout.flush()
"""
procs = {}

def hook(agent, payload):
    # One long-lived process per session: the hook client takes its parent
    # for the agent's own process, and Claude Code is one thread a process.
    sid = payload.get("session_id", "?")
    if sid not in procs:
        procs[sid] = subprocess.Popen([sys.executable, "-c", HELPER], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    pr = procs[sid]
    pr.stdin.write(json.dumps({"argv": [HOOK, agent, "--keep-text"], "p": payload, "env": ENV}) + "\n"); pr.stdin.flush()
    return json.loads(pr.stdout.readline())

def kill(sid):
    pr = procs.pop(sid, None)
    if pr:
        pr.kill(); pr.wait()
    return {"ok": bool(pr)}

def dev(obj):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1)
    s.connect(HOOK_SOCK)
    s.sendall(json.dumps(obj, separators=(",", ":")).encode() + b"\n")
    s.close()

def handle(cmd):
    if "hook" in cmd:
        return hook(cmd["hook"], cmd["p"])
    if "dev" in cmd:
        dev(cmd["dev"]); return {"ok": True}
    if "board" in cmd:
        return {"reply": board(cmd["board"], cmd.get("wait", 1.0))}
    if "kill" in cmd:
        return kill(cmd["kill"])
    if "mark" in cmd:
        with open(ROOT + "/marks.txt", "a") as f:
            f.write(ts() + " " + cmd["mark"] + "\n")
        return {"ok": True}
    return {"err": "?"}

if os.path.exists(CTRL):
    os.unlink(CTRL)
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(CTRL)
srv.listen(4)
while True:
    c, _ = srv.accept()
    f = c.makefile("rw")
    for line in f:
        try:
            out = handle(json.loads(line))
        except Exception as e:  # noqa
            out = {"err": repr(e)}
        f.write(json.dumps(out) + "\n"); f.flush()
    c.close()
