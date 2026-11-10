import json,glob,collections
C=collections.Counter
W='/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish/characters/'
out=[]
def P(*a): out.append(' '.join(str(x) for x in a))
def tab(t,c,top=None):
    P('\n**%s**'%t); P('| value | count |'); P('|---|---:|')
    for k,v in c.most_common(top): P('| %s | %d |'%(k,v))
for pack in ('boop','pixel'):
    fs=sorted(glob.glob(W+pack+'/demo/recordings/*.json'))
    do=C(); dmood=C(); smood=C(); base=C(); act=C(); when=C(); sign=C(); take=C(); loops=C(); var=C(); reason=C(); keys=C(); play=C(); wact=C(); args=C(); secs=0; mt=C()
    per=[]
    for f in fs:
        d=json.load(open(f)); secs+=d.get('length',0); n=0; last=None; lastat=0
        for e in d['events']:
            if 'line' not in e: continue
            try: m=json.loads(e['line'])
            except Exception: continue
            if m.get('t')=='state':
                keys.update(m.keys()); smood[m.get('mood')]+=1; base[m.get('base')]+=1
                if m.get('act'): act[m['act']]+=1
                for w in m.get('when',[]): when[w]+=1
                if m.get('wact'): wact[m['wact'][0]]+=1
                if last is not None: mt[last]+=e['at']-lastat
                last=m.get('mood'); lastat=e['at']
            elif m.get('t')=='do':
                n+=1; a=m.get('args',{}); do[m['name']]+=1; play[m.get('play')]+=1; args.update(a.keys())
                if 'mood' in a: dmood[a['mood']]+=1
                if 'loops' in a: loops[a['loops']]+=1
                if 'variant' in a: var[(m['name'],a['variant'])]+=1
                if 'sign' in a: sign[json.dumps(a['sign']) if not isinstance(a['sign'],str) else a['sign']]+=1
                if 'low' in a: sign['low: '+json.dumps(a['low'])]+=1
                if 'say' in a: take[a['say'].get('take') if isinstance(a['say'],dict) else a['say']]+=1
                if 'reason' in a: reason[a['reason']]+=1
        if last is not None: mt[last]+=d.get('length',lastat)-lastat
        per.append((f.split('/')[-1],d.get('length'),n))
    P('\n## Demo recordings: %s pack, %d recordings, %d s in all'%(pack,len(fs),secs))
    P('Files (length s, `do` messages): '+', '.join('%s %s/%d'%x for x in per))
    tab('`do` designs',do); tab('`do` play rule',play); P('\n`do` args keys: '+str(dict(args)))
    tab('Emotion on a `do` (args.mood)',dmood); tab('Size as loops',loops); tab('Variants',C({'%s %s'%k:v for k,v in var.items()}))
    tab('Signs',sign); tab('Voice takes',take); tab('Narration (reason)',reason)
    tab('`state` mood (messages)',smood); P('\nSeconds in each mood: '+', '.join('%s %.0f'%x for x in mt.most_common()))
    tab('`state` base (Doing)',base); tab('`state` act (activity)',act); tab('`when` tags',when); tab('work acts (wact)',wact); P('\n`state` keys: '+str(dict(keys)))
open('/tmp/boop-review/demo-tables.md','w').write('\n'.join(out))
