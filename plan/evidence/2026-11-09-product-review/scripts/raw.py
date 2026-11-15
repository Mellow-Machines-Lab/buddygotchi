import json,collections,math
C=collections.Counter
W='/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish'
pack=json.load(open(W+'/characters/boop/character.json'))
FACES=[m['id'] for m in pack['moods']]; LAST=[m['id'] for m in pack['moods'] if m.get('moves')]
f='/tmp/boop-eval/20261108-220953-81575.jsonl'
ps=[json.loads(l)['pass'] for l in open(f) if l.startswith('{"pass"')]
out=[]
def P(*a): out.append(' '.join(str(x) for x in a))
P('## Jev\'s raw answers, one standard run (2026-11-08, %d passes): %s'%(len(ps),f))
P('Brains: '+str(dict(C(p['brain'] for p in ps)))+'. Dropped: '+str(dict(C(str(p.get('dropped')) for p in ps))))
qs=C(k for p in ps for k in p['answers']); P('Questions answered: '+str(dict(qs)))
allopt={'mood':LAST,'react.face':FACES+['none']}
for q in ['mood','react.face','react.move','react.intensity','say','react.sign']:
    ch=C(); mass=C(); mx=C(); off=C(); n=0
    for p in ps:
        a=p['answers'].get(q)
        if not a: continue
        n+=1; ch[a['choice']]+=1
        for k,v in (a.get('p') or {}).items():
            mass[k]+=v; mx[k]=max(mx[k],v)
        for o in p.get('options',{}).get(q,[]): off[o]+=1
    if q=='react.sign':
        P('\n### react.sign: asked at %d passes; picked a sign at %d, none at %d'%(n,sum(v for k,v in ch.items() if k!='none'),ch.get('none',0))); continue
    P('\n### %s: asked at %d passes'%(q,n))
    P('| option | offered | chosen | share of asks | summed probability | highest p ever |'); P('|---|---:|---:|---:|---:|---:|')
    keys=sorted(set(off)|set(ch)|set(allopt.get(q,[])),key=lambda k:(-ch[k],-mass[k]))
    for k in keys: P('| %s | %d | %d | %.1f%% | %.1f | %.2f |'%(k,off[k],ch[k],100*ch[k]/n,mass[k],mx[k]))
    P('\nNever chosen: '+', '.join(k for k in keys if ch[k]==0))
    P('Never above p 0.10 at any pass: '+', '.join(k for k in keys if mx[k]<0.10))
# confidence
import statistics
for q in ['mood','react.face','say']:
    tp=[max(p['answers'][q]['p'].values()) for p in ps if q in p['answers'] and p['answers'][q].get('p')]
    P('\n%s: median top probability %.2f; passes where the top choice is under 0.5: %d of %d (%.0f%%).'%(q,statistics.median(tp),sum(t<0.5 for t in tp),len(tp),100*sum(t<0.5 for t in tp)/len(tp)))
# runner-up pairs: top1/top2 when top2>=0.2
for q in ['react.face','mood']:
    pr=C()
    for p in ps:
        a=p['answers'].get(q)
        if not a or not a.get('p'): continue
        s=sorted(a['p'].items(),key=lambda x:-x[1])
        if s[1][1]>=0.2: pr[tuple(sorted((s[0][0],s[1][0])))]+=1
    P('\n### %s: close calls (the runner-up had p of 0.20 or more): %d passes'%(q,sum(pr.values())))
    P('| pair | passes |'); P('|---|---:|')
    for k,v in pr.most_common(25): P('| %s / %s | %d |'%(k[0],k[1],v))
# mood: stay vs move
st=sum(1 for p in ps if 'mood' in p['answers']); 
# say vs face none
both=C((('face' if p['answers'].get('react.face',{}).get('choice','none')!='none' else 'no face'),('say' if p['answers'].get('say',{}).get('choice','none')!='none' else 'no say')) for p in ps)
P('\nFace and say picks together: '+str({' + '.join(k):v for k,v in both.items()}))
open('/tmp/boop-review/raw-tables.md','w').write('\n'.join(out))
