import re,json,random,collections,glob
C=collections.Counter
W='/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish/characters/boop/'
src=open(W+'firmware/src/render/gel/pastimes.cpp').read()
rows=[]
for m in re.finditer(r'\{Pastime::(\w+), Body::(\w+), "([^"]+)", SceneState::(\w+), (\d+), (\d+), (\d+)(?:, (nullptr|"[^"]*"))?(?:, (true))?\}',src):
    rows.append(dict(id=m.group(1),body=m.group(2),name=m.group(3),look=m.group(4),tier=int(m.group(5)),after=int(m.group(6)),stage=int(m.group(7)),tag=(m.group(8) or 'nullptr').strip('"') if m.group(8) and m.group(8)!='nullptr' else None,move=bool(m.group(9))))
clip={f.split('/')[-1][:-5]:json.load(open(f))['ms'] for f in glob.glob(W+'rig/clips/*.json')}
for r in rows: r['ms']=clip.get(r['name'],3000)
TIER=[0,30,60,120,300,600]
def tier(s):
    t=0
    for i in range(1,6):
        if s>=TIER[i]: t=i
    return t
def sim(look,dur,stage,free,rng,cnt,morning=False,tags=()):
    t=rng.uniform(4,10); last=None; moved=-1e9; phones=False
    while t<dur:
        # blocked share of the time (a live call in the work stream, a Moment, a finger): skip ahead
        if rng.random()>free: t+=rng.uniform(4,10); continue
        tr=tier(t); opts=[]
        for r in rows:
            if r['look']!=look or r['stage']>stage: continue
            if r['tag']:
                if not (set(r['tag'].split('|'))&set(tags)): continue
            elif look in('kWorking','kIdle'):
                if r['tier']==0 or r['tier']>tr: continue
            else:
                if r['after']>t: continue
            if r['move'] and t-moved<90: continue
            if morning and r['name'] in('sip','coffee-reach','refill'): continue
            opts.append(r)
        if look=='kWorking' and tr>=3 and not phones:
            phones=True; r=[x for x in rows if x['name']=='phones-on'][0]; cnt[r['name']]+=1; last=r['name']; t+=r['ms']/1000+rng.uniform(4,10); continue
        opts=[r for r in opts if r['name']!='phones-on']
        if len(opts)>1: opts=[r for r in opts if r['name']!=last]
        if not opts: t+=rng.uniform(4,10); continue
        rank=lambda r:(1000000 if r['tag'] else r['tier']*100000)+r['after']
        top=max(rank(r) for r in opts); new=[r for r in opts if rank(r)==top]; old=[r for r in opts if rank(r)!=top]
        pool=new if (not old or rng.random()<0.6) else old
        r=rng.choice(pool); cnt[r['name']]+=1; last=r['name']
        if r['move']: moved=t
        t+=r['ms']/1000+rng.uniform(4,10)
# The assumed day (8 h at the Mac, one agent at a time):
DAY={'kWorking':[(40,20),(180,12),(420,6),(1200,2)],   # (seconds, how many turns)
     'kIdle':[(60,20),(300,12),(900,6),(2700,2)],       # the rests between turns
     'kNeedsYou':[(20,6),(90,3),(400,1)],               # permission requests waiting
     'kAsleep':[(1800,1),(3600,1)]}                     # no session open / away: lunch, a meeting
FREE={'kWorking':0.5,'kIdle':0.9,'kNeedsYou':1.0,'kAsleep':1.0}
out=[]
def P(*a): out.append(' '.join(str(x) for x in a))
P('## Pastimes: the table (firmware/src/render/gel/pastimes.cpp) and an estimate for one day')
P('Rows: %d. By look: %s. By growth stage that first knows it: %s. Moves: %s. Tag rows: %s.'%(len(rows),dict(C(r['look'] for r in rows)),dict(sorted(C(r['stage'] for r in rows).items())),', '.join(r['name'] for r in rows if r['move']),', '.join('%s (%s)'%(r['name'],r['tag']) for r in rows if r['tag'])))
mins={k:sum(a*b for a,b in v)/60 for k,v in DAY.items()}
P('\nAssumed day: '+'; '.join('%s %.0f min in %d stretches %s'%(k[1:],mins[k],sum(b for a,b in v),v) for k,v in DAY.items())+'. Share of the time a pastime may be dealt (no live call drawn, no Moment, no finger): '+str(FREE)+'. No calendar tag on, not busy or frantic, not morning. A bit or take with no clip is taken as 3 s. 400 simulated days each.')
res={}
for stage in (1,2,3):
    cnt=C(); rng=random.Random(7); N=400
    for _ in range(N):
        for look,st in DAY.items():
            for d,n in st:
                for _ in range(n): sim(look,d,stage,FREE[look],rng,cnt)
    res[stage]={k:v/N for k,v in cnt.items()}
P('\n| pastime | look | needs | stage | move | clip s | per day, Hatchling (stage 1) | per day, Sprout (2) | per day, Buddy or Chonk (3+) |'); P('|---|---|---|---:|---|---:|---:|---:|---:|')
for r in sorted(rows,key=lambda r:(-res[3].get(r['name'],0))):
    need='tag '+r['tag'] if r['tag'] else ('tier%d (%ds)'%(r['tier'],TIER[r['tier']]) if r['tier'] else 'wait %ds'%r['after'])
    P('| %s | %s | %s | %d | %s | %.1f | %.1f | %.1f | %.1f |'%(r['name'],r['look'][1:],need,r['stage'],'move' if r['move'] else '',r['ms']/1000,res[1].get(r['name'],0),res[2].get(r['name'],0),res[3].get(r['name'],0)))
for s in (1,2,3):
    tot=sum(res[s].values()); seen=[k for k,v in res[s].items() if v>=1]; rare=[r['name'] for r in rows if res[s].get(r['name'],0)<1]
    P('\nStage %d: about %.0f pastimes a day; %d of %d rows at least once a day. Under once a day: %s'%(s,tot,len(seen),len(rows),', '.join(rare)))

P('\n### When a calendar tag is on (idle stretches of the same assumed day, stage 3)')
P('| tags on | tag row | its share of idle pastimes | idle pastimes |'); P('|---|---|---:|---:|')
for tags in (('morning',),('friday',),('morning','friday'),('night',)):
    cnt=C(); rng=random.Random(3)
    for _ in range(200):
        for d,n in DAY['kIdle']:
            for _ in range(n): sim('kIdle',d,3,0.9,rng,cnt,morning='morning' in tags,tags=tags)
    tot=sum(cnt.values())
    for r in rows:
        if r['tag'] and r['look']=='kIdle' and cnt[r['name']]: P('| %s | %s | %.0f%% | %.0f a day |'%('+'.join(tags),r['name'],100*cnt[r['name']]/tot,tot/200))
open('/tmp/boop-review/pastime-tables.md','w').write('\n'.join(out))
