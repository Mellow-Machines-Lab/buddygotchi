from d import *
a = Agent("rv-h1", "/tmp/rv/api"); b = Agent("rv-i2", "/tmp/rv/web")
mark("I1 grind to 99")
r = xp(); need = 99 - r["xp"]
b.start(); sl(0.3); b.prompt("go"); sl(3)
for i in range(need):
    b.read("/tmp/rv/web/f%d.ts" % i, gap=0.02)
sl(1); xp()
mark("I2 the level-up starts, and 0.6 s later an agent needs you")
a.prompt("push"); sl(3)
b.read("/tmp/rv/web/z.ts"); sl(0.6)
a.pre("Bash", {"command": "git push"}); a.ask(); sl(4)
bstate("screen","moment","sign","xp","turn")
mark("I3 answered: is the level-up shown again?")
a.post(); sl(9)
bstate("screen","moment","sign","xp")
mark("I4 end")
