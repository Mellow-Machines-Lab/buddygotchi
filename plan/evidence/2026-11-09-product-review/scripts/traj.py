import json,glob,collections,re,sys,os
C=collections.Counter
W='/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish'
pack=json.load(open(W+'/characters/boop/character.json'))
FACES=[m['id'] for m in pack['moods']]; LAST=[m['id'] for m in pack['moods'] if m.get('moves')]
H=os.path.expanduser('~/.boopdev/')
files=[H+'night-2026-11-01/traj-A.jsonl',H+'night-2026-11-01/traj-B.jsonl',H+'night-2026-11-01/traj-C.jsonl',H+'day2/traj-d2a.jsonl',H+'day2/traj-d2b.jsonl',H+'tonight/traj-t0.jsonl',H+'tonight/traj-t1.jsonl',H+'tonight/traj-t2.jsonl','/tmp/boop-eval/20261108-220953-81575.trajectories.jsonl']
names=['A','B','C','d2a','d2b','t0','t1','t2','nov8']
def cls(l):
    if l.startswith('You said to Boop'): return 'your words'
    if 'started turn' in l: return 'turn start'
    if l.startswith('You asked') : return 'prompt reading'
    if l.startswith('Nothing has happened'): return 'idle check-in'
    if 'is still working' in l: return 'working check-in'
    if l.startswith('You poked'): return 'poke'
    if re.match(r'You (stroked|shook|swiped|ruffled|tickled|booped|picked|put|leaned|held|thumped|startled|played)',l): return 'other touch'
    if 'keep failing' in l or re.search(r"'s \w+ failed",l): return 'check failed'
    if re.search(r"'s \w+ passed .* after failing",l): return 'check passed after failing'
    if 'Boop' in l and ('by itself' in l or 'Boop is' in l or "Boop's" in l) and re.match(r'(claude|codex)',l): return 'work act'
    if 'finished turn' in l:
        o='failed' if ': failed' in l else 'done'
        ln=re.search(r'a (very short|short|long|very long) turn',l)
        return 'finish %s, %s'%(o, ln.group(1) if ln else '?')
    if l.startswith('You came back'): return 'back'
    if l.startswith('You locked') or l.startswith('You unlocked'): return 'lock/unlock'
    if 'hushed' in l: return 'hush'
    if 'wish' in l: return 'wish'
    if 'Someone' in l or 'buddies' in l or 'buddy' in l: return 'world'
    if 'compacted' in l: return 'compact'
    if l.startswith('You answered'): return 'answered'
    return 'other'
out=[]
def P(*a): out.append(' '.join(str(x) for x in a))
def table(title,cnt,total=None,zero=None,top=None):
    P('\n### '+title); total=total or sum(cnt.values()) or 1
    P('| value | count | share |'); P('| --- | ---: | ---: |')
    for k,v in cnt.most_common(top): P('| %s | %d | %.1f%% |'%(k,v,100*v/total))
    if zero is not None:
        z=[x for x in zero if cnt.get(x,0)==0]; P('\nNever: '+(', '.join(z) if z else '(none)'))
runs={}
allp=[]
for n,f in zip(names,files):
    for l in open(f):
        d=json.loads(l)
        prev=d['starts_in_mood']; pf=None
        for i,q in enumerate(d['passes']):
            q['run']=n; q['file']=d['file']; q['cls']=cls(q['line']); q['prev_mood']=prev; q['talk']=d['talk']
            q['dur']=d['passes'][-1]['at_s']; q['prev_face']=pf
            if q.get('face') not in (None,'none'): pf=q['face']
            prev=q['mood']; allp.append(q)
N=len(allp)
P('## Real Jev trajectories: 9 runs, %d passes'%N)
P('\n| run | scenarios | passes | no Moment | Moment, face none | Moment with a face | mood moves | virtual hours | moves/h |'); P('|---|---:|---:|---:|---:|---:|---:|---:|---:|')
for n in names+['ALL']:
    ps=[q for q in allp if n=='ALL' or q['run']==n]
    sc={(q['run'],q['file']):q['dur'] for q in ps}
    hrs=sum(sc.values())/3600; mv=sum(1 for q in ps if q['mood']!=q['prev_mood'])
    P('| %s | %d | %d | %d (%.0f%%) | %d | %d | %d | %.0f | %.2f |'%(n,len(sc),len(ps),sum('face' not in q for q in ps),100*sum('face' not in q for q in ps)/len(ps),sum(q.get('face')=='none' for q in ps),sum(q.get('face') not in (None,'none') for q in ps),mv,hrs,mv/hrs))
# exclude long-away scenarios for moves/hour
sc={}
for q in allp: sc[(q['run'],q['file'])]=q['dur']
short={k for k,v in sc.items() if v<=4*3600}
mv=sum(1 for q in allp if q['mood']!=q['prev_mood'] and (q['run'],q['file']) in short); hrs=sum(sc[k] for k in short)/3600
P('\nScenarios of 4 h or less only: %d moves in %.0f virtual hours = %.2f moves/h (%d of %d scenario runs).'%(mv,hrs,mv/hrs,len(short),len(sc)))
table('Mood after each pass (16 lasting moods)',C(q['mood'] for q in allp),zero=LAST)
P('\nPer run (count of passes in the mood):'); P('| mood | '+' | '.join(names)+' |'); P('|---|'+'---:|'*len(names))
for m in sorted(LAST,key=lambda m:-sum(q['mood']==m for q in allp)): P('| %s | '%m+' | '.join(str(sum(q['mood']==m and q['run']==n for q in allp)) for n in names)+' |')
moves=C((q['prev_mood'],q['mood']) for q in allp if q['mood']!=q['prev_mood'])
table('Mood moves: the mood moved to',C(b for (a,b),v in moves.items() for _ in range(v)),zero=LAST)
table('Mood moves: the mood left',C(a for (a,b),v in moves.items() for _ in range(v)),zero=LAST)
table('Mood moves: from > to (top 40)',C({'%s > %s'%k:v for k,v in moves.items()}),top=40)
edges={(m['id'],t) for m in pack['moods'] for t in m.get('moves',{}).get('ordinary',[])+m.get('moves',{}).get('dramatic',[])}
P('\nGraph edges: %d. Edges never taken in any run: %d.'%(len(edges),sum(1 for e in edges if moves.get(e,0)==0)))
P('Never taken: '+', '.join('%s>%s'%e for e in sorted(edges) if moves.get(e,0)==0))
P('Moves not on today\'s graph (older graph or a start mood): '+', '.join('%s>%s (%d)'%(a,b,v) for (a,b),v in moves.items() if (a,b) not in edges))
mom=[q for q in allp if 'face' in q]
table('Emotion (react.face) of each Moment played, "none" included',C(q['face'] for q in mom),zero=FACES)
P('\nPer run:'); fc=C(q['face'] for q in mom)
P('| face | '+' | '.join(names)+' |'); P('|---|'+'---:|'*len(names))
for m,_ in fc.most_common(): P('| %s | '%m+' | '.join(str(sum(q['face']==m and q['run']==n for q in mom)) for n in names)+' |')
table('Move (animation) of each Moment',C(q['move'] for q in mom))
table('Size of each Moment',C(q['size'] for q in mom))
table('Size of Moments with a face',C(q['size'] for q in mom if q['face']!='none'))
said=C(q['said'] for q in mom)
P('\n### Voice: what Boop said'); P('Moments that said something: %d of %d (%.0f%%). Distinct texts: %d.'%(sum(v for k,v in said.items() if k!='none'),len(mom),100*sum(v for k,v in said.items() if k!='none')/len(mom),len(said)-1))
table('Voice texts, top 60',C({k:v for k,v in said.items() if k!='none'}),top=60)
once=[k for k,v in said.items() if v==1]; P('\nTexts said exactly once: %d. Texts said 1-2 times: %d.'%(len(once),sum(1 for v in said.values() if v<=2)))
sg=C(q['sign'] for q in allp if 'sign' in q)
P('\n### Signs'); P('Passes with a sign: %d of %d (%.0f%%). Distinct signs: %d.'%(sum(sg.values()),N,100*sum(sg.values())/N,len(sg)))
table('Signs, top 70',sg,top=70)
json.dump(sg,open('/tmp/boop-review/signs-seen.json','w'))
json.dump(said,open('/tmp/boop-review/said-seen.json','w'))
table('Narration, top 40',C(q['narration'] for q in allp if 'narration' in q),top=40)
# by event class
P('\n### By event: passes, Moment rate, top faces, top moods moved to')
P('| event | passes | Moment with a face | said something | sign | mood moved | top faces | top moods moved to |'); P('|---|---:|---:|---:|---:|---:|---|---|')
bc=collections.defaultdict(list)
for q in allp: bc[q['cls']].append(q)
for k,ps in sorted(bc.items(),key=lambda x:-len(x[1])):
    f=C(q['face'] for q in ps if q.get('face') not in (None,'none')); mm=C(q['mood'] for q in ps if q['mood']!=q['prev_mood'])
    n=len(ps)
    P('| %s | %d | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %s | %s |'%(k,n,100*sum(f.values())/n,100*sum(q.get('said','none')!='none' for q in ps)/n,100*sum('sign' in q for q in ps)/n,100*sum(mm.values())/n,', '.join('%s %d'%x for x in f.most_common(5)),', '.join('%s %d'%x for x in mm.most_common(4))))
# repetition
faced=[q for q in allp if q.get('face') not in (None,'none')]
same=sum(1 for q in faced if q['prev_face']==q['face']); wp=sum(1 for q in faced if q['prev_face'])
P('\nFace same as the Moment before it in the same scenario: %d of %d (%.0f%%).'%(same,wp,100*same/wp))
P('Face equals the mood after the pass: %d of %d (%.0f%%).'%(sum(q['face']==q['mood'] for q in faced),len(faced),100*sum(q['face']==q['mood'] for q in faced)/len(faced)))
# Substitution across runs at the same scenario step
key=collections.defaultdict(dict)
for q in allp: key[(q['file'],q['step'],q['line'])].setdefault(q['run'],q)
subF=C(); subM=C(); nstep=0; agreeF=0; agreeM=0
for k,d in key.items():
    if len(d)<5: continue
    nstep+=1
    fs=C(q.get('face','no Moment') for q in d.values()); ms=C(q['mood'] for q in d.values())
    if len(fs)==1: agreeF+=1
    if len(ms)==1: agreeM+=1
    for a in fs:
        for b in fs:
            if a<b: subF[(a,b)]+=min(fs[a],fs[b])
    for a in ms:
        for b in ms:
            if a<b: subM[(a,b)]+=min(ms[a],ms[b])
P('\n### Substitution: the same step of the same scenario, across runs')
P('Steps seen in 5 or more runs: %d. Same face in every run: %d (%.0f%%). Same mood in every run: %d (%.0f%%).'%(nstep,agreeF,100*agreeF/nstep,agreeM,100*agreeM/nstep))
tot=C(q.get('face','no Moment') for q in allp)
P('\n| face pair | swaps | share of the rarer face\'s uses |'); P('|---|---:|---:|')
for (a,b),v in subF.most_common(45): P('| %s / %s | %d | %.0f%% |'%(a,b,v,100*v/min(tot[a],tot[b])))
totm=C(q['mood'] for q in allp)
P('\n| mood pair | swaps | share of the rarer mood\'s passes |'); P('|---|---:|---:|')
for (a,b),v in subM.most_common(30): P('| %s / %s | %d | %.0f%% |'%(a,b,v,100*v/min(totm[a],totm[b])))
# face context similarity by class
import math
vec={f:C() for f in FACES}
for q in faced: vec[q['face']][q['cls']]+=1
def cos(a,b):
    d=sum(a[k]*b[k] for k in a); na=math.sqrt(sum(v*v for v in a.values())); nb=math.sqrt(sum(v*v for v in b.values()))
    return d/(na*nb) if na and nb else 0
prs=[(cos(vec[a],vec[b]),a,b) for i,a in enumerate(FACES) for b in FACES[i+1:] if sum(vec[a].values())>=15 and sum(vec[b].values())>=15]
P('\n### Faces used at the same kinds of event (cosine over event classes, faces with 15+ uses)'); P('| pair | cosine | uses |'); P('|---|---:|---|')
for c,a,b in sorted(prs,reverse=True)[:30]: P('| %s / %s | %.2f | %d / %d |'%(a,b,c,sum(vec[a].values()),sum(vec[b].values())))
P('\n### Each face\'s events'); P('| face | uses | events |'); P('|---|---:|---|')
for f in sorted(FACES,key=lambda f:-sum(vec[f].values())):
    if sum(vec[f].values()): P('| %s | %d | %s |'%(f,sum(vec[f].values()),', '.join('%s %d'%x for x in vec[f].most_common(5))))
open('/tmp/boop-review/traj-tables.md','w').write('\n'.join(out))
