"""Picks the deferred phrase slots that give each of say's meanings a phrase in
the voice moods that have none, up to two a mood, and prints the coverage
before and after. Writes phrase-slots.json. Run from the repo root:

    python3 plan/evidence/2026-10-25-voice-range/phrase_slots.py plan/evidence/2026-10-25-voice-range/phrase-slots.json
"""
import json, collections, sys
sys.path.insert(0, 'characters/boop/tools/voicegen')
import voicegen as vg
B = 'characters/boop/design/assets/boop-voice-v1/'
d = json.load(open(B+'dictionary.json')); m = json.load(open(B+'manifest.json')); p = json.load(open(B+'plans/deferred.json'))
E = {e['id']: e for e in d['entries']}
VM = list(d['moods'])  # 13 voice moods
have = collections.defaultdict(set)  # (meaning, kind) -> voice moods recorded
for r in m['recordings']:
    e = E.get(r['entryId'])
    if not e: continue
    part, mean = vg.answer(e)
    if part == 'attention': continue
    try: mo = vg.mood(r)
    except SystemExit: continue
    have[(mean, vg.kind(e))].add(mo)
# phrase slots that fill a (meaning, voice mood) with no phrase yet, up to 2 per cell
pick = collections.defaultdict(list)
for s in p['slots']:
    e = E[s['entry']]
    if e['category'] != 'phrase' or e['explicit']: continue
    part, mean = vg.answer(e)
    if part == 'attention': continue
    if s['mood'] in have[(mean, 'phrase')]: continue
    cell = (mean, s['mood'])
    if len(pick[cell]) < 2 and e['id'] not in [E[x['entry']]['id'] for x in pick[cell]]:
        pick[cell].append(s)
tot = sum(len(v) for v in pick.values())
by = collections.Counter(); 
for (mean, mo), v in pick.items(): by[mean] += len(v)
print('slots picked', tot); print(dict(by))
# coverage after, in voice moods
for mean in sorted({k[0] for k in have}):
    before = have[(mean,'phrase')]; after = before | {mo for (mm, mo) in pick if mm == mean}
    print(f'{mean:12} phrase voice moods {len(before):2} -> {len(after):2}')
json.dump({'note': 'Draft subset of deferred.json: phrase slots that give each meaning a phrase in voice moods that have none, up to 2 each. Not authorized for generation.', 'slots': [s['id'] for v in pick.values() for s in v]}, open(sys.argv[1], 'w'), indent=1)
