import json,collections,re
C=collections.Counter
W='/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish/characters/boop/'
takes=[l.rstrip('\n').split('\t') for l in open(W+'mac/takes.tsv') if not l.startswith('#') and l.count('\t')==7]
out=[]
def P(*a): out.append(' '.join(str(x) for x in a))
P('## Voice takes: the pack against what the 9 runs said')
P('Takes in takes.tsv: %d. Distinct texts: %d. Total audio: %.0f min.'%(len(takes),len({t[1] for t in takes}),sum(int(t[7]) for t in takes)/60000))
for col,name in ((4,'kind'),(2,'part'),(3,'meaning')):
    c=C(t[col] for t in takes); d=collections.defaultdict(set)
    for t in takes: d[t[col]].add(t[1])
    P('\nBy %s (takes / distinct texts): '%name+', '.join('%s %d/%d'%(k,v,len(d[k])) for k,v in c.most_common()))
said=json.load(open('/tmp/boop-review/said-seen.json')); said.pop('none',None)
texts={t[1] for t in takes}
bytext=collections.defaultdict(list)
for t in takes: bytext[t[1]].append(t)
hit=C(); unmatched=C(); lead=C()
for s,v in said.items():
    if s in texts: hit[s]+=v; continue
    # lead sound + take
    parts=s.split(' ')
    ok=False
    for i in range(1,len(parts)):
        a,b=' '.join(parts[:i]),' '.join(parts[i:])
        if b in texts and (a in texts):
            hit[b]+=v; lead[a]+=v; ok=True; break
    if not ok: unmatched[s]+=v
P('\nSaid in the runs: %d Moments, %d distinct strings. Matched to take texts: %d distinct texts (main take), %d distinct lead sounds; unmatched strings: %d (%d uses): %s'%(sum(said.values()),len(said),len(hit),len(lead),len(unmatched),sum(unmatched.values()),', '.join(list(unmatched)[:15])))
used=set(hit)|set(lead)
P('Distinct take texts ever heard (main or lead): %d of %d (%.0f%%). Never heard: %d texts.'%(len(used),len(texts),100*len(used)/len(texts),len(texts-used)))
P('\n| kind | distinct texts | heard in 9 runs | share |'); P('|---|---:|---:|---:|')
for k in C(t[4] for t in takes):
    tx={t[1] for t in takes if t[4]==k}; P('| %s | %d | %d | %.0f%% |'%(k,len(tx),len(tx&used),100*len(tx&used)/len(tx)))
P('\n| meaning (say kind) | part | distinct texts | heard | uses of its texts (main take) |'); P('|---|---|---:|---:|---:|')
mean=collections.defaultdict(set); part={}
for t in takes: mean[t[3]].add(t[1]); part[t[3]]=t[2]
rows=[]
for m,tx in mean.items(): rows.append((sum(hit[x] for x in tx),m,part[m],len(tx),len(tx&used)))
for u,m,p,n,h in sorted(rows,reverse=True): P('| %s | %s | %d | %d | %d |'%(m,p,n,h,u))
P('\n(A text can belong to several meanings, so uses are counted under each.)')
# mood coverage of takes
mc=C()
for t in takes:
    for m in t[5].split(): mc[m]+=1
P('\nTakes recorded per mood tag (a take lists the moods it suits): '+', '.join('%s %d'%x for x in mc.most_common()))
# signs
sg=json.load(open('/tmp/boop-review/signs-seen.json'))
def lines(f):
    r=[]
    for l in open(W+'steering/'+f):
        m=re.match(r'- (\[[^\]]*\] )?(.*)',l.strip())
        if m: r.append(((m.group(1) or '').strip(' []'),m.group(2)))
    return r
P('\n## Signs: the pack\'s lines against what the 9 runs held up')
for f in ('signs.md','replies.md','asks.md'):
    ls=lines(f); P('\n### %s: %d lines'%(f,len(ls))); P('| tags | line | times held up |'); P('|---|---|---:|')
    tot=0;zero=0
    for tag,txt in ls:
        q=txt.split('|')[0].strip()
        if '{' in q:
            rx='^'+re.escape(q).replace(r'\{words\}','.+').replace(r'\{WORDS\}','.+').replace(r'\{turns\}',r'\d+').replace(r'\{thread\}','.+').replace(r'\{agent\}','.+')+'$'
            n=sum(v for k,v in sg.items() if re.match(rx,k) ) if q not in('{words}',) else -1
        else: n=sg.get(q,0)
        if n==0: zero+=1
        P('| %s | %s | %s |'%(tag,txt,'(any words; not counted)' if n<0 else n))
    P('\nLines never held up: %d of %d.'%(zero,len(ls)))
open('/tmp/boop-review/voice-signs-tables.md','w').write('\n'.join(out))
