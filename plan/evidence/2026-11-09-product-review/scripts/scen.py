import json,glob,collections,re
C=collections.Counter
W='/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish/characters/'
pack=json.load(open(W+'boop/character.json'))
FACES=[m['id'] for m in pack['moods']]; LAST=[m['id'] for m in pack['moods'] if m.get('moves')]
out=[]
def P(*a): out.append(' '.join(str(x) for x in a))
fs=sorted(glob.glob(W+'boop/evals/*.json'))
grp=C(); ev=C(); start=C(); talk=C(); chk=C()
exp={k:C() for k in ('react','mood','say','move','intensity','sign','said','offered')}
neg={k:C() for k in exp}
scen={k:collections.defaultdict(set) for k in exp}
brief=collections.defaultdict(set); briefR=collections.defaultdict(set); briefU=collections.defaultdict(set); case=collections.defaultdict(set)
brainans={k:C() for k in ('react.face','say','react.move','react.intensity','react.sign','mood')}
nsteps=0; nexp=0
for f in fs:
    d=json.load(open(f)); n=f.split('/')[-1]
    g='scripted' if d.get('scripted') else ('feel' if d.get('judge') else 'must'); grp[g]+=1
    start[d.get('mood','calm')]+=1; talk[d.get('talk','normal')]+=1
    for k in d.get('checks',{}): chk[k]+=1
    for m in (d.get('checks',{}).get('moods_seen','') or '').split('|'):
        if m: scen['mood'][m].add(n)
    for s in d['steps']:
        nsteps+=1; ev[s['event']]+=1
        if s.get('expect'): nexp+=1
        for k,v in (s.get('expect') or {}).items():
            if k not in exp: continue
            for x in str(v).split('|'):
                if x.startswith('!'): neg[k][x[1:]]+=1
                else: exp[k][x]+=1; scen[k][x].add(n)
        for k,v in (s.get('brain') or {}).items():
            if k in brainans: brainans[k][v]+=1
        if s.get('mood') : pass
    for name,dst in (('judge',brief),('reasonable',briefR),('unreasonable',briefU),('case',case)):
        t=(d.get(name) or '').lower()
        for m in FACES+['pride','relief','joy','glee','sulk','huff','cross','despair','swear','lonel','bored','affection','cheek']:
            if re.search(r'\b'+m,t): dst[m].add(n)
P('## Eval scenario files: %d in characters/boop/evals/'%len(fs))
P('Groups: %s. Steps: %d, with an `expect`: %d. Start mood: %s. Talk: %s.'%(dict(grp),nsteps,nexp,dict(start),dict(talk)))
P('\nStep events: '+', '.join('%s %d'%x for x in ev.most_common()))
P('\nWhole-run checks used: '+', '.join('%s %d'%x for x in chk.most_common()))
P('\n### Each mood and emotion in the scenario files')
P('| id | lasting | steps expecting it as `mood` | scenarios | steps accepting it as `react` | scenarios | named in feel briefs (judge+reasonable) | named in "unreasonable" | named in must cases | scripted `brain` face | starts a scenario |'); P('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
for m in sorted(FACES,key=lambda m:-(exp['mood'][m]+exp['react'][m]+len(brief[m]|briefR[m]))):
    P('| %s | %s | %d | %d | %d | %d | %d | %d | %d | %d | %d |'%(m,'yes' if m in LAST else '',exp['mood'][m],len(scen['mood'][m]),exp['react'][m],len(scen['react'][m]),len(brief[m]|briefR[m]),len(briefU[m]),len(case[m]),brainans['react.face'][m],start[m]))
P('\nNegated (`!x`): react %s; mood %s; say %s.'%(dict(neg['react']),dict(neg['mood']),dict(neg['say'])))
P('\nOther feeling words in feel briefs (scenarios): '+', '.join('%s %d'%(k,len(brief[k]|briefR[k])) for k in ['pride','relief','joy','glee','sulk','huff','cross','despair','swear','lonel','bored','affection','cheek']))
for k in ('say','move','intensity'):
    P('\n`expect.%s` values (steps): '%k+', '.join('%s %d'%x for x in exp[k].most_common()))
P('\n`expect.sign` values: '+', '.join('%s %d'%x for x in exp['sign'].most_common()))
P('\n`expect.said` values: '+', '.join('%s %d'%x for x in exp['said'].most_common()))
for k in brainans: P('\nScripted `brain` answers, %s: '%k+', '.join('%s %d'%x for x in brainans[k].most_common()))
# graph
P('\n## Mood graph (character.json)')
inb=collections.defaultdict(lambda:{'ordinary':[],'dramatic':[]})
for m in pack['moods']:
    for kind in ('ordinary','dramatic'):
        for t in m.get('moves',{}).get(kind,[]): inb[t][kind].append(m['id'])
P('| mood | family | out ordinary | out dramatic | in ordinary | in dramatic | in total | in from |'); P('|---|---|---:|---:|---:|---:|---:|---|')
for m in sorted([x for x in pack['moods'] if x.get('moves')],key=lambda m:len(inb[m['id']]['ordinary'])+len(inb[m['id']]['dramatic'])):
    i=inb[m['id']]; P('| %s | %s | %d | %d | %d | %d | %d | %s; jumps: %s |'%(m['id'],m['family'],len(m['moves']['ordinary']),len(m['moves']['dramatic']),len(i['ordinary']),len(i['dramatic']),len(i['ordinary'])+len(i['dramatic']),', '.join(i['ordinary']),', '.join(i['dramatic'])))
calm=[m for m in pack['moods'] if m['id']=='calm'][0]['moves']
one=set(calm['ordinary'])|set(calm['dramatic'])
P('\nFrom calm in one move: ordinary %s; jumps %s.'%(', '.join(calm['ordinary']),', '.join(calm['dramatic'])))
P('Not reachable from calm in one move: '+', '.join(m for m in LAST if m not in one and m!='calm'))
# shortest ordinary-only and any path
import itertools
def bfs(kinds):
    g={m['id']:[t for k in kinds for t in m.get('moves',{}).get(k,[])] for m in pack['moods'] if m.get('moves')}
    dist={'calm':0}; q=['calm']
    while q:
        x=q.pop(0)
        for y in g[x]:
            if y not in dist: dist[y]=dist[x]+1; q.append(y)
    return dist
P('Moves from calm (any move): '+str(bfs(('ordinary','dramatic'))))
P('Moves from calm (ordinary moves only): '+str(bfs(('ordinary',))))
P('\nFaces with no lasting mood (Moment emotions only, %d): '%(len(FACES)-len(LAST))+', '.join(m for m in FACES if m not in LAST))
fam=collections.defaultdict(list)
for m in pack['moods']: fam[m['family']].append(m['id']+('*' if m.get('moves') else ''))
P('\nFamilies (* = lasting): '+'; '.join('%s: %s'%(k,', '.join(v)) for k,v in fam.items()))
open('/tmp/boop-review/scenario-graph-tables.md','w').write('\n'.join(out))
