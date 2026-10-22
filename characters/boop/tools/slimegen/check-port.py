#!/usr/bin/env python3
"""Replay every saved JS trace against the actual integer engine."""
import argparse, collections, json, pathlib, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[4]
BASE=ROOT/'characters/boop/design/slime-blob'
TOLERANCE=.0001

def flatten(value, prefix='', result=None):
    if result is None: result={}
    if isinstance(value,dict):
        for key,item in value.items():flatten(item,prefix+'/'+key,result)
    elif isinstance(value,list):
        for key,item in enumerate(value):flatten(item,prefix+'/'+str(key),result)
    else:result[prefix]=value
    return result

def equal(a,b):
    if type(a) in (float,int) and type(b) in (float,int):return abs(a-b)<=TOLERANCE
    return type(a)==type(b) and a==b

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=pathlib.Path,required=True,help='local report directory')
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    exe=args.output/'gel-trace'
    if not (ROOT/'firmware/.pio/libdeps/native/ArduinoJson/src').is_dir() or not (ROOT/'.character-build/firmware/include/moods.h').is_file():
        raise SystemExit('check-port needs ArduinoJson from the native env and the staged pack: run make -C internal fw-test first')
    sources=[ROOT/'characters/boop/tools/gel-trace/main.cpp',ROOT/'firmware/src/render/types.cpp',ROOT/'firmware/src/render/tags.cpp']
    sources += [ROOT/f'characters/boop/firmware/src/render/gel/{name}.cpp' for name in ['engine','scenes','acting','motion','router']]
    # The pack's own headers first, as slimegen just wrote them; the staged
    # build's last, for the moods.h only staging makes (characters/CHARACTER.md §2).
    includes=['firmware/src','firmware/assets','characters/boop/firmware/src','characters/boop/firmware/include','firmware/.pio/libdeps/native/ArduinoJson/src','.character-build/firmware/include']
    subprocess.run(['clang++','-O2','-std=c++17','-DBOOP_GEL_TRACE',*[f'-I{ROOT/path}' for path in includes],*map(str,sources),'-o',str(exe)],check=True)
    report={'tolerance':TOLERANCE,'timing':'No frame shift or omitted channel; categorical fields and cue counts must match exactly.','scripts':[]}
    for script in sorted((BASE/'scripts').glob('*.jsonl')):
        reference=json.loads((BASE/'traces'/f'{script.stem}.json').read_text())
        errors=[];maximum=0;frames=0;cues=[];columns=set(reference['columns'])
        with tempfile.TemporaryFile(mode='w+') as output:
            subprocess.run([str(exe),str(script)],stdout=output,check=True);output.seek(0)
            for frames,line in enumerate(output,1):
                row=json.loads(line);native=flatten(row['channels'])
                # Optional fields absent in a reference frame are represented by null.
                extra=set(native)-columns
                if extra:errors.append({'extra':sorted(extra)})
                for key,want in zip(reference['columns'],reference['frames'][frames-1]):
                    got=native.get(key)
                    if not equal(want,got) and len(errors)<20:errors.append({'at':row['at'],'channel':key,'want':want,'got':got})
                    if type(want) in (int,float) and type(got) in (int,float):maximum=max(maximum,abs(want-got))
                cues.extend({'at':row['at'],'cue':cue} for cue in row['cues'])
        if frames!=len(reference['frames']):errors.append({'frameCount':[len(reference['frames']),frames]})
        if len(cues)!=len(reference['cues']):errors.append({'cueCount':[len(reference['cues']),len(cues)]})
        for index,(want,got) in enumerate(zip(reference['cues'],cues)):
            a,b=flatten(want),flatten(got)
            for key in set(a)|set(b):
                if not equal(a.get(key),b.get(key)) and len(errors)<20:errors.append({'cue':index,'channel':key,'want':a.get(key),'got':b.get(key)})
        item={'script':script.stem,'frames':frames,'channels':len(columns),'cues':len(cues),'maxAbsoluteError':maximum,'errors':errors}
        report['scripts'].append(item);print(script.stem, 'FAIL' if errors else 'PASS',frames,'frames',len(cues),'cues',flush=True)
    report['passed']=all(not item['errors'] for item in report['scripts'])
    (args.output/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    if not report['passed']:raise SystemExit('Port comparison failed; see result.json')
    print('GEL PORT PASS:',sum(s['frames'] for s in report['scripts']),'frames; every scalar and cue checked')
if __name__=='__main__':main()
