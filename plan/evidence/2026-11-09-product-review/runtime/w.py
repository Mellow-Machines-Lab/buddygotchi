import json, socket, time
def send(state, line):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(1); s.connect("/tmp/%s/boop.sock" % state)
    s.sendall((json.dumps(line) + "\n").encode()); s.close()
def wdev(state, **kw): send(state, {"dev": "world", **kw})
def ident(state):
    try: return json.load(open("/tmp/%s/world.json" % state))
    except Exception: return None
def tail(path, n=5, pat="world"):
    out = [l.rstrip()[:330] for l in open(path, errors="replace") if pat in l and not l.startswith("    │")]
    return out[-n:]
