from d import *
from w import *
import time
N = ident("br5")["id"]
K = ("base","moment","sign","reason","screen","when")
mark("G7 Sol's world forgot it: next heartbeat")
send("br2", {"dev": "advance", "ms": 11*60000}); sl(3)
send("br2", {"dev": "advance", "ms": 2*60000}); sl(3)
send("br2", {"dev": "advance", "ms": 16*60000}); sl(4)
print("Sol", ident("br2") and ident("br2")["id"])
mark("G8 night: a boop and a heart arrive at 02:30")
wdev("br2", to=N, gesture="boop"); sl(0.6); wdev("br2", to=N, gesture="heart"); sl(2)
adv(m=11); sl(4); bstate(*K)
print(tail("/tmp/boop-review/runtime/world-night.log", 4))
import os
print("waiting file:", os.path.exists("/tmp/br5/world-waiting.json") and open("/tmp/br5/world-waiting.json").read()[:300])
mark("G9 the night ends (you at the Mac): 30-min steps to 05:30")
for i in range(6):
    adv(m=30); sl(1.2)
sl(6); bstate(*K)
mark("G10 end")
