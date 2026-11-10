from d import *
c1 = Agent("rv-c1", "/tmp/rv/api"); c2 = Agent("rv-c2", "/tmp/rv/web"); c3 = Agent("rv-c3", "/tmp/rv/infra", agent="codex")
mark("F0 sessions end: no agents")
for c in (c1, c2, c3):
    c.end(); sl(0.5)
sl(3); bstate("base","idle","when","moment","reason")
mark("F1 quiet day, no agents, you at the Mac: 5 h in 5-min steps")
dev(dev="presence", idle_ms=0)
for i in range(60):
    adv(m=5); sl(0.45)
sl(3)
bstate("base","when","moment","xp")
mark("F2 end")
