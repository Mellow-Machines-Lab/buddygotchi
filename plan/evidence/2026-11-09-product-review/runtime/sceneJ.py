from d import *
b = Agent("rv-j1", "/tmp/rv/web")
mark("J1 grind to the ring, nothing else going on")
b.start(); sl(0.3); b.prompt("go"); sl(4)
for i in range(99):
    b.read("/tmp/rv/web/f%d.ts" % i, gap=0.02)
sl(2); xp()
mark("J2 the 100th XP")
b.read("/tmp/rv/web/z.ts")
for i in range(8):
    sl(2); bstate("moment","sign","reason","xp","turn")
mark("J3 end")
