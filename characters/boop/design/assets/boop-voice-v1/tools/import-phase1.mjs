// Allowlisted, local-only extension. No paid calls, credentials or account exports.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const dest=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
if(process.argv.includes('--help')){console.log('node tools/import-phase1.mjs --source /absolute/path/to/audition-checkout\nPreserves the pilot and imports the frozen completed first pass, portable audition and disjoint deferred plan. No API calls.');process.exit(0);}
const source=process.argv[process.argv.indexOf('--source')+1];
assert(process.argv.includes('--source')&&path.isAbsolute(source||''),'Supply an absolute --source');
const read=p=>JSON.parse(fs.readFileSync(p));const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const write=(name,value)=>{const target=path.join(dest,name);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,JSON.stringify(value,null,2)+'\n');};
function copy(src,relative){
 const bytes=fs.readFileSync(src),target=path.join(dest,relative);fs.mkdirSync(path.dirname(target),{recursive:true});
 if(fs.existsSync(target))assert.equal(hash(fs.readFileSync(target)),hash(bytes),'Refuse different existing file '+relative);
 else fs.copyFileSync(src,target);
 return {path:relative,bytes:bytes.length,sha256:hash(bytes)};
}
const author=path.join(source,'internal/voice-recording-plan/dictionary'),cache=path.join(source,'tmp/robot-dictionary-phase1');
const plan=read(path.join(author,'phase1-plan.json')),later=read(path.join(author,'phase2-deferred.json')),preview=read(path.join(cache,'preview.json')),ledger=read(path.join(cache,'ledger.json'));
const manifest=read(path.join(dest,'manifest.json')),dict=read(path.join(dest,'dictionary.json')),byEntry=new Map(dict.entries.map(e=>[e.id,e]));
assert(!manifest.distribution,'Compact bank exists: do not re-import 16-bit WAVs. Preserve the compressed manifest and use the archived source with tools/compress.py.');
assert.equal(plan.voice_id,manifest.voiceId);assert.equal(plan.model_id,'eleven_v4');assert.equal(ledger.plan_sha256,hash(fs.readFileSync(path.join(author,'phase1-plan.json'))));
assert.equal(preview.recorded.length,2702);assert.equal(later.authorized,false);
const jobs=new Map(plan.jobs.map(j=>[j.id,j])),deferred=new Set(later.performances.map(p=>p.id));
assert.equal(jobs.size,2702);assert.equal(deferred.size,4421);assert.equal(new Set([...jobs.keys(),...deferred]).size,7123);
const byPerformance=new Map(manifest.recordings.filter(r=>r.performanceId).map(r=>[r.performanceId,r]));
const original=new Map(manifest.recordings.map(r=>[r.id,r]));
let added=0;
for(const t of preview.recorded){
 const j=jobs.get(t.performance),r=ledger.takes[t.performance];assert(j&&r);assert.equal(t.script,j.script);assert.equal(t.mood,j.mood);assert.equal(t.master_sha256,r.sha256);
 assert(['saved','reused'].includes(r.status));assert(!path.isAbsolute(r.master)&&!r.master.split('/').includes('..'));
 assert.equal(hash(fs.readFileSync(path.join(cache,r.master))),r.sha256);
 if(byPerformance.has(t.performance)){
  const old=byPerformance.get(t.performance);assert.equal(old.master.sha256,r.sha256);assert.equal(old.script,t.script);assert.equal(old.mood,t.mood);continue;
 }
 assert.equal(r.status,'saved');assert.equal(r.request.text,j.script);assert.equal(r.request.seed,j.seed);
 const id=t.id;assert(!original.has(id));const master=copy(path.join(cache,r.master),`masters/${id}.mp3`),files={};
 for(const texture of ['original','robot-soft','robot-grain']){
  const expected=`audio/phase1/${j.id}-${texture}.wav`;assert.equal(t.files[texture],expected);
  files[texture]={...copy(path.join(source,'tmp/boop-scene-sampler',expected),`audio/${texture}/${id}.wav`),encoding:{container:'wav',codec:'pcm_s16le',sampleRate:44100,channels:1}};
 }
 const record={id,entryId:t.entry,mood:t.mood,moodStatus:t.moodStatus,variant:t.variant,script:t.script,seconds:t.seconds,routineDurationEligible:t.routineDurationEligible,
  reviewStatus:t.reviewStatus,performanceId:t.performance,sourceBatch:'robot-dictionary-phase1',generation:{voiceId:plan.voice_id,modelId:plan.model_id,seed:j.seed,language:'auto'},files,
  master:{...master,encoding:{container:'mp3',nominalBitrate:128000,sampleRate:44100}}};
 manifest.recordings.push(record);byPerformance.set(t.performance,record);original.set(id,record);added++;
}
assert.equal(manifest.recordings.length,2722);assert.equal(byPerformance.size,2702);
manifest.scope={phase1Slots:2702,newPhase1Takes:2682,reusedPilotTakes:20,additionalLegacyTakes:20,deferredSlots:4421};
write('manifest.json',manifest);
const index={byState:{},byMood:{},byIntent:{},byEntry:{}};const add=(b,k,id)=>(b[k]??=[]).push(id);
for(const r of manifest.recordings){const e=byEntry.get(r.entryId);assert(e);for(const s of e.states)add(index.byState,s,r.id);add(index.byMood,r.mood,r.id);add(index.byIntent,e.intent,r.id);add(index.byEntry,e.id,r.id);}
write('index.json',index);
// The published plans are safe slot inventories, not workstation paths or request journals.
write('plans/phase1.json',{version:1,voiceId:plan.voice_id,modelId:plan.model_id,sourceDictionarySha256:plan.sourceSha256,
 summary:plan.summary,slots:plan.jobs.map(j=>({performanceId:j.id,recordingId:byPerformance.get(j.id).id,entryId:j.entry,mood:j.mood,variant:j.variant,script:j.script,seed:j.seed}))});
write('plans/deferred.json',{version:1,authorized:false,sourceDictionarySha256:later.sourceSha256,note:'Disjoint complement. Check manifest performance IDs before any future generation. New paid generation requires authorization.',slots:later.performances});
const provenance=read(path.join(dest,'provenance.json'));
if(!provenance.batches.some(b=>b.name==='robot-dictionary-phase1'))provenance.batches.push({name:'robot-dictionary-phase1',takes:2682,reusedPilotSlots:20});
provenance.phase1={completedSlots:2702,submittedNewCharacters:44815,sourcePlanSha256:ledger.plan_sha256,publicationAuthorizedOn:'2026-09-29',listeningApproval:'Not inferred from publication consent; retain per-take review status.'};
write('provenance.json',provenance);
// Standalone review resolves the manifest, never local tmp or source checkout paths.
const recorded=preview.recorded.map(t=>{const r=byPerformance.get(t.performance);return {...t,id:r.id,files:Object.fromEntries(Object.entries(r.files).map(([k,f])=>[k,'../'+f.path]))};});
write('review/phase1-audio.json',{summary:{selected:2702,ready:2702,entries:387},recorded});
fs.mkdirSync(path.join(dest,'review'),{recursive:true});
for(const f of ['phase1-review.mjs','phase1-review.css','dictionary.css']){
 let text=fs.readFileSync(path.join(author,f),'utf8');
 if(f.endsWith('.mjs'))text=text.replaceAll('href="phase1-plan.json"','href="../plans/phase1.json"').replaceAll('href="phase2-deferred.json"','href="../plans/deferred.json"');
 fs.writeFileSync(path.join(dest,'review',f),text);
}
console.log(JSON.stringify({added,totalRecordings:manifest.recordings.length,phase1Slots:2702,deferred:4421},null,2));
