// One-time, allowlisted import from the local audition checkout. No API calls.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const dest=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
if(process.argv.includes('--help')){console.log('node tools/import.mjs --source /absolute/path/to/audition-checkout\nImports only dictionary metadata, 40 selected recordings and their rendered audio. Never reads environment files.');process.exit(0);}
const source=process.argv[process.argv.indexOf('--source')+1];
if(!process.argv.includes('--source')||!source||!path.isAbsolute(source))throw Error('Provide --source /absolute/path/to/audition-checkout');
const read=p=>JSON.parse(fs.readFileSync(path.join(source,p),'utf8'));
const dict=read('internal/voice-recording-plan/dictionary/dictionary.json');
const audition=read('tmp/boop-scene-sampler/dictionary-audio.json');
audition.recorded=audition.recorded.filter(t=>['new','previous'].includes(t.bank));
if(dict.voice_id!=='rErOatUrNIU3vfNcLl6Z'||audition.recorded.length!==40)throw Error('Unexpected audition inventory');
if(fs.existsSync(path.join(dest,'manifest.json'))&&JSON.parse(fs.readFileSync(path.join(dest,'manifest.json'))).recordings.length>40)throw Error('Expanded bank exists: use import-phase1.mjs; never downgrade its manifest to the pilot');
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const write=(name,obj)=>fs.writeFileSync(path.join(dest,name),JSON.stringify(obj,null,2)+'\n');
function copy(src,relative){
 const bytes=fs.readFileSync(src),target=path.join(dest,relative);fs.mkdirSync(path.dirname(target),{recursive:true});
 if(fs.existsSync(target)&&hash(fs.readFileSync(target))!==hash(bytes))throw Error('Refusing to overwrite different audio: '+relative);
 fs.writeFileSync(target,bytes);return {path:relative,bytes:bytes.length,sha256:hash(bytes)};
}
const recordings=audition.recorded.map(t=>{
 const folder=t.bank==='new'?'robot-dictionary-v1':'robot-language-v2';
 const ledger=read(`tmp/${folder}/ledger.json`);
 if(ledger.voice_id!==dict.voice_id||ledger.model_id!=='eleven_v4')throw Error('Unexpected recording origin');
 const id=t.id.split('.')[1]+'-auto', record=ledger.takes[id];
 if(record?.status!=='saved'||record.request.text!==t.script)throw Error('Missing or changed paid master');
 const master=copy(path.join(source,'tmp',folder,id+'.mp3'),`masters/${t.id}.mp3`);
 if(master.sha256!==record.sha256)throw Error('Master integrity mismatch');
 const files={};
 for(const texture of ['original','robot-soft','robot-grain']){
  const expected=`audio/${folder}/${id}-${texture}.wav`;
  if(t.files[texture]!==expected)throw Error('Unexpected input audio path');
  files[texture]={...copy(path.join(source,'tmp/boop-scene-sampler',expected),`audio/${texture}/${t.id}.wav`),encoding:{container:'wav',codec:'pcm_s16le',sampleRate:44100,channels:1}};
 }
 return {id:t.id,entryId:t.entry,mood:t.mood,moodStatus:t.moodStatus,variant:t.variant,script:t.script,seconds:t.seconds,
  routineDurationEligible:t.routineDurationEligible,reviewStatus:t.reviewStatus,performanceId:t.performance,
  sourceBatch:folder,generation:{voiceId:ledger.voice_id,modelId:ledger.model_id,seed:record.request.seed,language:record.request.language_code||'auto'},
  files,master:{...master,encoding:{container:'mp3',nominalBitrate:128000,sampleRate:44100}},
 };
});
write('dictionary.json',{version:dict.version,voice_id:dict.voice_id,moods:dict.moods,policy:dict.policy,stats:dict.stats,entries:dict.entries,excluded:dict.excluded,
 performanceMatrix:'Not copied: planned performance slots can be enumerated from entries[].moods × entries[].variants. Planned slots are not audio files.'});
write('manifest.json',{version:1,status:'audition; not approved for automatic production playback',voiceId:dict.voice_id,defaultTexture:'robot-soft',recordings});
const entries=new Map(dict.entries.map(e=>[e.id,e]));
const index={byState:{},byMood:{},byIntent:{},byEntry:{}};
const add=(bucket,key,id)=>(bucket[key]??=[]).push(id);
for(const r of recordings){const e=entries.get(r.entryId);if(!e)throw Error('Unknown dictionary entry');for(const s of e.states)add(index.byState,s,r.id);add(index.byMood,r.mood,r.id);add(index.byIntent,e.intent,r.id);add(index.byEntry,e.id,r.id);}
write('index.json',index);
// Proposed text plan only. No transcript, account counters, request IDs or credentials.
write('provenance.json',{importedOn:'2026-09-29',voiceId:dict.voice_id,modelId:'eleven_v4',batches:[{name:'robot-language-v2',takes:20},{name:'robot-dictionary-v1',takes:20}],
 excluded:'Other voices, six superseded early Robot Minion auditions, raw accounting ledgers, API keys, execution logs and decoded intermediates.',
 review:'All takes unreviewed by ear at export. Intended mood labels are not listening guarantees.',
 textures:{original:'Decoded and quiet-level-matched; untouched provider MP3 is in masters.',
 'robot-soft':'150 Hz high-pass; 8% mild saturation; 8% 12-bit/sample-hold texture; 12% 92 Hz ring modulation; 4.2 kHz low-pass.',
 'robot-grain':'Same chain with 16% sample-hold texture and 22% ring modulation.'},
 limits:{rmsCeiling:.07,peakCeiling:.55},sourceDictionarySha256:hash(fs.readFileSync(path.join(source,'internal/voice-recording-plan/dictionary/dictionary.json')))});
console.log(`Imported ${recordings.length} original takes, ${recordings.length*3} local WAV renders and ${recordings.length} MP3 masters.`);
