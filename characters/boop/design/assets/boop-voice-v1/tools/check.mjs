import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {loadBank,choices,resolveChoice,assemble} from '../select.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
if(process.argv.includes('--help')){console.log('node tools/check.mjs\nChecks the self-contained voice bank offline; writes exact storage-report.json. No API, playback or device calls.');process.exit(0);}
// Placeholders (character/tools/voicegen/placeholders.py) stand in for slots not yet
// recorded, and are checked on their own below; the rest checks the recorded bank.
function recorded(){const b=loadBank();b.manifest.recordings=b.manifest.recordings.filter(r=>!r.generation?.placeholder);b.dictionary.entries=b.dictionary.entries.filter(e=>e.origin!=='placeholder');return b;}
const b=recorded(),records=b.manifest.recordings,entries=new Map(b.dictionary.entries.map(e=>[e.id,e]));
assert.equal(records.length,2722);assert.equal(new Set(records.map(r=>r.id)).size,2722);assert.equal(entries.size,387);
assert.equal(b.manifest.voiceId,'rErOatUrNIU3vfNcLl6Z');
assert.equal(b.manifest.distribution.codec,'pcm_u8');assert.equal(b.manifest.distribution.sampleRate,11025);
let peak=0,maxRms=0,wavCount=0;const profiles={original:0,'robot-soft':0,'robot-grain':0};
const expectedIndex={byState:{},byMood:{},byIntent:{},byEntry:{}};
const add=(bucket,key,id)=>(bucket[key]??=[]).push(id);
function checkedFile(file){
 assert(!path.isAbsolute(file.path)&&!file.path.split('/').includes('..'));
 const bytes=fs.readFileSync(path.join(root,file.path));assert.equal(bytes.length,file.bytes);assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),file.sha256,file.path);return bytes;
}
for(const r of records){
 assert(entries.has(r.entryId));const e=entries.get(r.entryId);
 for(const s of e.states)add(expectedIndex.byState,s,r.id);add(expectedIndex.byMood,r.mood,r.id);add(expectedIndex.byIntent,e.intent,r.id);add(expectedIndex.byEntry,e.id,r.id);
 assert.equal(r.generation.voiceId,b.manifest.voiceId);assert.equal(r.generation.modelId,'eleven_v4');
 assert.equal(r.master.storage,'local-archive-not-distributed');assert(!('path' in r.master));assert.match(r.master.sha256,/^[a-f0-9]{64}$/);
 assert.deepEqual(Object.keys(r.files).sort(),Object.keys(profiles).sort());
 assert.equal(r.routineDurationEligible,r.seconds<=b.dictionary.policy.maxSeconds);
 for(const [profile,file] of Object.entries(r.files)){
  // Boop's repo keeps only the robot-soft texture; the others may be absent.
  if(profile!=='robot-soft'&&!fs.existsSync(path.join(root,file.path)))continue;
  const bytes=checkedFile(file);assert.equal(bytes.toString('ascii',0,4),'RIFF');assert.equal(bytes.toString('ascii',8,12),'WAVE');
  let p=12,pcm,format;
  while(p+8<=bytes.length){const name=bytes.toString('ascii',p,p+4),n=bytes.readUInt32LE(p+4);if(name==='fmt ')format=bytes.subarray(p+8,p+8+n);if(name==='data')pcm=bytes.subarray(p+8,p+8+n);p+=8+n+n%2;}
  assert(format&&pcm);assert.equal(format.readUInt16LE(0),1);assert.equal(format.readUInt16LE(2),1);assert.equal(format.readUInt32LE(4),11025);assert.equal(format.readUInt16LE(14),8);assert.equal(format.readUInt16LE(12),1);assert.equal(format.readUInt32LE(8),11025);assert(Math.abs(pcm.length/11025-r.seconds)<=1/11025);
  assert.equal(file.path,`audio-pcm8/${profile}/${r.id}.wav`);assert.equal(file.encoding.codec,'pcm_u8');assert.equal(file.encoding.silence,128);assert.equal(file.encoding.bitsPerSample,8);assert.equal(file.encoding.sampleRate,11025);
  assert.match(file.sourceSha256,/^[a-f0-9]{64}$/);assert.equal(file.decoded.frames,pcm.length);
  let power=0,clipPeak=0;for(const v of pcm){const x=(v-128)/128;clipPeak=Math.max(clipPeak,Math.abs(x));power+=x*x;}const rms=Math.sqrt(power/pcm.length);peak=Math.max(peak,clipPeak);maxRms=Math.max(maxRms,rms);
  assert(Math.abs(file.decoded.rms-rms)<1e-12);assert.equal(file.decoded.peak,clipPeak);profiles[profile]+=bytes.length;wavCount++;
 }
}
const expectedWavs=records.length*Object.values(profiles).filter(n=>n>0).length;
assert.deepEqual(b.index,expectedIndex);assert.equal(wavCount,expectedWavs);assert(peak<=.59);assert(maxRms<=.073);
const phase=JSON.parse(fs.readFileSync(path.join(root,'plans/phase1.json'))),later=JSON.parse(fs.readFileSync(path.join(root,'plans/deferred.json')));
const phaseIds=new Set(phase.slots.map(s=>s.performanceId)),laterIds=new Set(later.slots.map(s=>s.id));
assert.equal(phaseIds.size,2702);assert.equal(laterIds.size,4421);assert.equal(new Set([...phaseIds,...laterIds]).size,7123);assert.equal(later.authorized,false);
assert.equal(new Set(records.map(r=>r.performanceId).filter(Boolean)).size,2702);
for(const s of phase.slots){const r=records.find(r=>r.id===s.recordingId);assert(r);assert.equal(r.performanceId,s.performanceId);assert.equal(r.script,s.script);assert.equal(r.mood,s.mood);}
const review=JSON.parse(fs.readFileSync(path.join(root,'review/phase1-audio.json')));assert.equal(review.recorded.length,2702);
for(const t of review.recorded){const r=records.find(r=>r.id===t.id);assert.equal(t.master_sha256,r.master.sha256);for(const [k,p] of Object.entries(t.files))assert.equal(p,'../'+r.files[k].path);}
const fullOptions=choices(b,{state:'starting',mood:'excited',facts:['task_started']},{audition:true});assert(fullOptions.length<=9&&fullOptions.some(c=>c.id==='new.d02'));
assert(choices(b,{state:'working',mood:'grumpy',facts:['work_active']},{audition:true}).length>1);
assert.equal(new Set(records.map(r=>r.master.sha256)).size,2722);
// Keep the original small fixture's exact join/shortlist expectations while the
// full-bank integrity and coverage checks above exercise the expanded manifest.
{
const b=recorded();b.manifest.recordings=b.manifest.recordings.filter(r=>r.sourceBatch!=='robot-dictionary-phase1');
const pilotIds=new Set(b.manifest.recordings.map(r=>r.id));
for(const bucket of Object.values(b.index))for(const key of Object.keys(bucket))bucket[key]=bucket[key].filter(id=>pilotIds.has(id));
const ctx={state:'starting',mood:'excited',facts:['task_started']};
assert.deepEqual(choices(b,ctx).map(c=>c.id),['silence']);
const offered=choices(b,ctx,{audition:true});assert(offered.some(c=>c.id==='new.d02'));assert(offered.length<=9);
assert.equal(resolveChoice(offered,'invented').id,'silence');
for(const context of [{...ctx,facts:[]},{...ctx,state:'asleep'},{...ctx,mood:'nonexistent'},{...ctx,stale:true},{...ctx,recentTakeIds:['new.d02']},{...ctx,recentFamilies:['go']}])assert.equal(choices(b,context,{audition:true}).length,1);
assert.equal(choices(b,{state:'task_complete',mood:'proud',facts:['failure_confirmed']},{audition:true,phrases:true,rare:true}).some(c=>c.label==='Done'),false);
assert(!choices(b,{state:'task_complete',mood:'grumpy',facts:['failure_confirmed']},{audition:true,rare:true}).some(c=>c.explicit));
assert(choices(b,{state:'task_complete',mood:'grumpy',facts:['failure_confirmed']},{audition:true,rare:true,explicit:true}).some(c=>c.explicit));
assert(!choices(b,{state:'needs_you',mood:'grumpy',facts:['pending_request','failure_confirmed']},{audition:true,rare:true,explicit:true}).some(c=>c.explicit));
assert(assemble(b,['new.d02'],ctx,{audition:true}));assert.equal(assemble(b,['new.d02','new.d02'],ctx,{audition:true}),null);
assert.equal(assemble(b,['new.d20'],{state:'task_complete',mood:'proud',facts:['success_or_poke']},{audition:true,rare:true}),null);
const happy={state:'task_complete',mood:'happy',facts:['success_confirmed']};
const joined=assemble(b,['new.d13','new.d19'],happy,{audition:true});assert(joined);assert(joined.seconds<=2.8);assert.equal(joined.clips[1].at,records.find(r=>r.id==='new.d13').seconds+.18);
assert.equal(assemble(b,['new.d13','previous.finish'],happy,{audition:true}),null); // too long together
const happyChoices=choices(b,happy,{audition:true});assert.equal(new Set(happyChoices.map(c=>c.entryId)).size,happyChoices.length);
// Synthetic fixture proves topic and join guards independently of sparse pilot coverage.
const fixture=structuredClone(b),e=fixture.dictionary.entries.find(e=>e.id==='word.begin.go');e.topic='build';
assert.equal(choices(fixture,ctx,{audition:true}).length,1);assert(choices(fixture,{...ctx,topic:'build'},{audition:true}).length>1);
}
const plain=JSON.stringify({dictionary:b.dictionary,manifest:b.manifest,index:b.index});assert(!plain.includes('/Users/'));assert(!plain.includes('xi-api-key'));
const walk=dir=>fs.readdirSync(dir,{withFileTypes:true}).flatMap(d=>{assert(!d.isSymbolicLink());const p=path.join(dir,d.name);return d.isDirectory()?walk(p):[p];});
const allFiles=walk(root),placeholder=p=>path.basename(p).startsWith('placeholder.');assert.equal(allFiles.filter(p=>p.endsWith('.wav')&&!placeholder(p)).length,expectedWavs);
// Every placeholder: its entry, its robot-soft file, and its line in plans/regenerate.json, the list to record.
const all=loadBank(),held=all.manifest.recordings.filter(r=>r.generation?.placeholder),known=new Set(all.dictionary.entries.map(e=>e.id));
assert.deepEqual(JSON.parse(fs.readFileSync(path.join(root,'plans/regenerate.json'))).slots.map(s=>s.take).sort(),held.map(r=>r.id).sort(),'plans/regenerate.json lists every placeholder');
for(const r of held){assert(known.has(r.entryId));assert.equal(r.reviewStatus,'placeholder');assert.equal(r.id,`placeholder.${r.performanceId}`);assert.equal(r.files['robot-soft'].path,`audio-pcm8/robot-soft/${r.id}.wav`);assert.equal(checkedFile(r.files['robot-soft']).toString('ascii',8,12),'WAVE');}
assert.equal(allFiles.filter(placeholder).length,held.length,'no placeholder file without its take');assert(!allFiles.some(p=>/\.(mp3|m4a|tmp)$/.test(p)),'No archived masters, unused AAC or partial renders in release');
const report={version:3,generatedOn:'2026-09-29',codec:'pcm_u8',sampleRate:11025,channels:1,bitsPerSample:8,distinctRecordedTakes:2722,placeholderTakes:held.length,latestBatchNewTakes:2682,phase1Slots:2702,reusedPilotSlots:20,additionalLegacyTakes:20,deferredSlots:4421,plannedDictionaryEntries:387,plannedPerformanceSlots:7123,
 wavFiles:expectedWavs,distributedMp3Masters:0,locallyArchivedMasters:2722,totalRecordedSeconds:records.reduce((n,r)=>n+r.seconds,0),audioBytesByProfile:profiles,defaultRuntimeWavBytes:profiles['robot-soft'],
 allAudioBytes:Object.values(profiles).reduce((n,v)=>n+v,0),recordedMoodCounts:Object.fromEntries(Object.entries(b.index.byMood).map(([k,v])=>[k,v.length])),
 peak,maxRms,packagePayloadBytes:0,metadataAndCodeBytes:0,totalFiles:0,previousPackagePayloadBytes:1103619112,measure:'Sum of file lengths, including this report; excludes directory blocks and Git history. Original masters/WAVs are locally archived. One DSP profile suffices at runtime.',checks:'passed'};
const reportPath=path.join(root,'storage-report.json');
for(let pass=0;pass<5;pass++){
 fs.writeFileSync(reportPath,JSON.stringify(report,null,2)+'\n');const files=walk(root);report.packagePayloadBytes=files.reduce((n,p)=>n+fs.statSync(p).size,0);report.metadataAndCodeBytes=report.packagePayloadBytes-report.allAudioBytes;report.totalFiles=files.length;
}
assert.equal(JSON.parse(fs.readFileSync(reportPath)).packagePayloadBytes,report.packagePayloadBytes);
console.log(JSON.stringify(report,null,2));
