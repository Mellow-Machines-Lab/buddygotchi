"""Archive then convert the fixed voice bank to 8-bit PCM; no API or speech generation."""
import argparse
from array import array
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[1]
RECIPE = 'pcm-u8-mono-11025-coreaudio-v1'
PROFILES = ('original', 'robot-soft', 'robot-grain')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write_json(path, value):
    temp = path.with_suffix(path.suffix+'.tmp')
    temp.write_text(json.dumps(value, indent=2)+'\n')
    temp.replace(path)

def wav_stats(path):
    with wave.open(str(path)) as w:
        assert w.getnchannels() == 1 and w.getsampwidth() == 1
        rate, count = w.getframerate(), w.getnframes()
        x = [v-128 for v in w.readframes(count)]
    return dict(sampleRate=rate, bitsPerSample=8, channels=1, frames=count, seconds=count/rate,
                peak=max(abs(v) for v in x)/128,
                rms=math.sqrt(sum(v*v for v in x)/count)/128)

def quantize(source, target):
    with wave.open(str(source)) as w:
        assert w.getnchannels()==1 and w.getsampwidth()==2 and w.getframerate()==11025
        x=array('h',w.readframes(w.getnframes()))
    if sys.byteorder!='little':x.byteswap()
    # Exact approved preview quantization, without new gain, pitch, effects or dither.
    raw=bytes(max(0,min(255,round(v/256)+128)) for v in x)
    with wave.open(str(target),'wb') as w:
        w.setnchannels(1);w.setsampwidth(1);w.setframerate(11025);w.writeframes(raw)

def run(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('Audio conversion failed: '+result.stderr.strip())

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', required=True, type=Path, help='Absolute local backup directory OUTSIDE the repository; never published')
    parser.add_argument('--jobs', type=int, default=4, choices=range(1,9))
    parser.add_argument('--finalize', action='store_true', help='After every conversion validates, migrate manifests and remove ONLY hash-verified archived WAV/MP3 files')
    args = parser.parse_args()
    archive = args.archive.resolve()
    repo = ROOT.parents[3]
    if not args.archive.is_absolute() or archive == repo or repo in archive.parents:
        raise ValueError('Archive must be an absolute path outside the repository')
    if not archive.exists():
        archive.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(ROOT, archive)
        print('Created local archive', flush=True)
    old = json.loads((archive/'manifest.json').read_text())
    assert not old.get('distribution'), 'Need the original 16-bit WAV archive'
    records = old['recordings']
    assert len(records) == 2722 and len({r['id'] for r in records}) == 2722
    # Validate EVERY original against its published hash before encoding or deleting.
    files = [r['master'] for r in records] + [r['files'][p] for r in records for p in PROFILES]
    for f in files:
        rel = Path(f['path'])
        assert not rel.is_absolute() and '..' not in rel.parts
        assert rel.parts[0] in ('audio','masters') and rel.suffix in ('.wav','.mp3')
        assert sha(archive/rel) == f['sha256'], 'Archive mismatch: '+str(rel)
        if (ROOT/rel).exists(): assert sha(ROOT/rel) == f['sha256'], 'Live source changed'
    print('Verified all 10,888 original audio files in the local archive', flush=True)
    cache = archive/'pcm8-conversion-cache'; cache.mkdir(exist_ok=True)

    def convert(record, profile):
        original = record['files'][profile]
        source = archive/original['path']
        relative = f'audio-pcm8/{profile}/{record["id"]}.wav'
        target = ROOT/relative
        target.parent.mkdir(parents=True, exist_ok=True)
        journal = cache/(profile+'--'+record['id']+'.json')
        if journal.exists() and target.exists():
            result = json.loads(journal.read_text())
            if result.get('recipe') == RECIPE and result['sourceSha256'] == original['sha256'] and result['sha256'] == sha(target):
                return record['id'], profile, result
        # Each worker has its own scratch directory; a partial encode is never published.
        with tempfile.TemporaryDirectory(prefix='boop-pcm8-') as d:
            temp = Path(d); encoded = temp/'encoded.wav'; decoded = temp/'resampled.wav'
            run(['afconvert','-f','WAVE','-d','LEI16@11025','-c','1','-r','127',str(source),str(decoded)])
            quantize(decoded,encoded)
            measurements = wav_stats(encoded)
            assert measurements['sampleRate'] == 11025 and measurements['bitsPerSample']==8
            assert abs(measurements['seconds']-record['seconds']) <= 1/11025, 'Timing drift: '+record['id']
            # Resampling reconstructs inter-sample peaks; observed grain max is 0.578125.
            # Keep the audition recipe unchanged rather than normalize/clip these transients.
            assert 0 < measurements['rms'] <= .073 and measurements['peak'] <= .59, 'Decoded level out of bounds: '+record['id']
            result = dict(path=relative, bytes=encoded.stat().st_size, sha256=sha(encoded),
                          encoding=dict(container='wav',codec='pcm_u8',bitsPerSample=8,sampleRate=11025,channels=1,silence=128),
                          sourceSha256=original['sha256'], recipe=RECIPE, decoded=measurements)
            shutil.copyfile(encoded, target.with_suffix('.wav.tmp'))
            target.with_suffix('.wav.tmp').replace(target)
            write_json(journal, result)
        return record['id'], profile, result

    converted = {}
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(convert,r,p) for r in records for p in PROFILES]
        for n,f in enumerate(as_completed(futures),1):
            ident,profile,result=f.result(); converted[ident,profile]=result
            if n%300==0 or n==len(futures): print(f'Validated {n}/{len(futures)} 8-bit WAVs', flush=True)
    total = sum(f['bytes'] for f in converted.values())
    print(json.dumps(dict(wavFiles=len(converted),pcm8Bytes=total,originalAudioBytes=sum(f['bytes'] for f in files))), flush=True)
    if not args.finalize:
        print('Conversion validated. Originals/manifests unchanged; rerun with --finalize to migrate.', flush=True)
        return
    current = json.loads((ROOT/'manifest.json').read_text())
    assert {r['id'] for r in current['recordings']} == {r['id'] for r in records}
    for r in current['recordings']:
        r['files'] = {p:converted[r['id'],p] for p in PROFILES}
        # Retain the original paid-take identity for review/deduplication, not a broken file path.
        r['master'].pop('path',None)
        r['master']['storage'] = 'local-archive-not-distributed'
    current['version'] = 2
    current['distribution'] = dict(codec='pcm_u8',container='wav',sampleRate=11025,channels=1,bitsPerSample=8,profiles=list(PROFILES),
        recipe=RECIPE,masterPolicy='Hashes retained; original MP3s and WAVs preserved locally outside Git',
        deviceIntegration='PCM-compatible representation; SD loading and whole-clip playback are NOT implemented')
    write_json(ROOT/'manifest.json',current)
    by_id = {r['id']:r for r in current['recordings']}
    review = json.loads((ROOT/'review/phase1-audio.json').read_text())
    for r in review['recorded']:
        r['files'] = {p:'../'+by_id[r['id']]['files'][p]['path'] for p in PROFILES}
    write_json(ROOT/'review/phase1-audio.json',review)
    provenance = json.loads((ROOT/'provenance.json').read_text())
    provenance['compression'] = dict(recipe=RECIPE,date='2026-09-29',newPaidGenerations=0,
        review='User approved the compression audition; individual take review statuses preserved.',
        masters='Local verified archive; not distributed. Original hashes remain in manifest.',
        history='Normal follow-up commit requested; previous large files remain in Git history.')
    write_json(ROOT/'provenance.json',provenance)
    # Recheck both copies immediately before each narrowly scoped removal.
    for f in files:
        live=ROOT/f['path']; saved=archive/f['path']
        if live.exists():
            assert sha(live)==f['sha256'] and sha(saved)==f['sha256']
            live.unlink()
    # Keep the interrupted AAC experiment out of the release, without destroying it.
    moved=0
    for r in records:
        for p in PROFILES:
            for suffix in ('.m4a','.m4a.tmp'):
                rel=Path('audio')/p/(r['id']+suffix);live=ROOT/rel
                if not live.exists():continue
                saved=archive/'abandoned-aac'/rel;saved.parent.mkdir(parents=True,exist_ok=True)
                if saved.exists():assert sha(saved)==sha(live)
                else:shutil.copyfile(live,saved)
                assert sha(saved)==sha(live);live.unlink();moved+=1
    print(f'Finalized PCM8 manifest; originals and {moved} unused AAC files preserved locally', flush=True)

if __name__ == '__main__': main()
