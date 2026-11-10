from d import *
from w import *
R = ident("br3")["id"]
K = ("base","moment","sign","reason","screen")
def fetch():
    # the gestures come in a send's reply, a 10-min check, or on an unlock
    adv(m=11); sl(3)
mark("G1 a boop arrives while idle")
wdev("br2", to=R, gesture="boop"); sl(2)
fetch(); sl(4); bstate(*K)
mark("G2 the hour's limit: wave, heart (Sol) + boop (Tam)")
wdev("br2", to=R, gesture="wave"); sl(0.5); wdev("br2", to=R, gesture="heart"); sl(0.5); wdev("br4", to=R, gesture="boop"); sl(2)
fetch(); sl(12); bstate(*K)
mark("G2b Sol's 4th gesture to Rex in the hour")
wdev("br2", to=R, gesture="boop"); sl(3)
mark("G3 a cheer with no ship")
wdev("br4", to=R, gesture="cheer"); sl(2)
fetch(); sl(8); bstate(*K)
mark("G4 a heart while something needs you")
a = Agent("rv-g1", "/tmp/rv/api")
a.start(); sl(0.3); a.prompt("push it"); sl(1); a.pre("Bash", {"command": "git push"}); a.ask(); sl(2)
wdev("br4", to=R, gesture="heart"); sl(2)
fetch(); sl(4); bstate(*K)
mark("G5 answered: the heart comes back")
a.post(); sl(8); bstate(*K)
a.stop("Pushed."); sl(6)
mark("G6 end")
