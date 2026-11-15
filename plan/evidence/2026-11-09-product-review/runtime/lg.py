import sys,re
marks=[l.rstrip("\n").split(" ",1) for l in open("marks.txt")]
a=sys.argv[1]; b=sys.argv[2] if len(sys.argv)>2 else None
w=int(sys.argv[3]) if len(sys.argv)>3 else 430
log=sys.argv[4] if len(sys.argv)>4 else "headless.log"
t0=[t for t,n in marks if n.startswith(a)][-1]
t1=([t for t,n in marks if n.startswith(b)][-1] if b else "99")
cur=None; last_state=None
mk=[(t,n) for t,n in marks if t0<=t<=t1]
for l in open(log,errors="replace"):
    l=l.rstrip("\n")
    if l.startswith("    │"): continue
    m=re.match(r"(\d\d:\d\d:\d\d\.\d\d\d) ",l)
    if m: cur=m.group(1)
    if cur is None or cur<t0 or cur>=t1: continue
    while mk and mk[0][0]<=cur:
        print("#### "+mk[0][1]); mk.pop(0)
    if "  pass scripted" in l and "held" in l: continue
    if l.startswith(cur+" brain ") and "held" in l: continue
    if '"t":"state"' in l:
        s=l.split("→",1)[1]
        if s==last_state: continue
        last_state=s
    print(l[:w])
