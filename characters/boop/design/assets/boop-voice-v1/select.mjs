// Host-side reference selection. No LLM, network, playback or persistent-state writes.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url));
export function loadBank(){return Object.fromEntries(['dictionary','manifest','index'].map(name=>[name,JSON.parse(fs.readFileSync(path.join(root,name+'.json'),'utf8'))]));}
export function choices(bank,context,{audition=false,explicit=false,phrases=false,rare=false,texture='robot-soft',limit=8}={}){
 const silence={id:'silence',label:'Stay silent',reason:'Silence is always valid'};
 if(!Number.isInteger(limit)||limit<1||limit>8)throw Error('limit must be 1–8');
 if(!['original','robot-soft','robot-grain'].includes(texture))throw Error('Unknown texture');
 if(!bank.dictionary.moods[context.mood]||['asleep','no_app'].includes(context.state)||context.stale)return [silence];
 const facts=new Set(context.facts||[]),moodIds=new Set(bank.index.byMood[context.mood]||[]),stateIds=bank.index.byState[context.state]||[];
 const recordings=new Map(bank.manifest.recordings.map(r=>[r.id,r])), entries=new Map(bank.dictionary.entries.map(e=>[e.id,e]));
 const candidates=stateIds.filter(id=>moodIds.has(id)).map(id=>recordings.get(id)).filter(r=>{
  const e=entries.get(r.entryId);
  return e.moods.includes(context.mood)&&facts.has(e.requires)&&(!e.topic||e.topic===context.topic)
   &&(!e.explicit||explicit)&&(!e.explicit||context.state!=='needs_you')
   &&(e.category!=='phrase'||phrases)&&(e.tier!=='rare'||rare)
   &&(r.reviewStatus==='approved'||audition)&&r.routineDurationEligible
   &&!(context.recentTakeIds||[]).includes(r.id)&&!(context.recentEntryIds||[]).includes(e.id)
   &&!(context.recentFamilies||[]).includes(e.repeatFamily);
 });
 const rank={daily:0,occasional:1,rare:2};
 candidates.sort((a,b)=>rank[entries.get(a.entryId).tier]-rank[entries.get(b.entryId).tier]||a.id.localeCompare(b.id));
 const seen=new Set(),shortlist=candidates.filter(r=>{if(seen.has(r.entryId))return false;seen.add(r.entryId);return true;});
 return [silence,...shortlist.slice(0,limit).map(r=>{const e=entries.get(r.entryId);return {id:r.id,entryId:e.id,label:e.text,intent:e.intent,mood:r.mood,kind:e.category,seconds:r.seconds,requiredFact:e.requires,explicit:e.explicit,reviewStatus:r.reviewStatus,file:r.files[texture].path,encoding:r.files[texture].encoding,sha256:r.files[texture].sha256};})];
}
export function resolveChoice(options,id){return options.find(o=>o.id===id)||options.find(o=>o.id==='silence');}
// A joined clip is still two whole recordings, never word fragments.
export function assemble(bank,ids,context,options={}){
 if(ids.length<1||ids.length>2)return null;
 // Up to eight actually offered clips, not the unfiltered full dictionary.
 const offered=choices(bank,context,options),selected=ids.map(id=>offered.find(o=>o.id===id&&id!=='silence'));
 if(selected.some(x=>!x))return null;
 const entries=selected.map(c=>bank.dictionary.entries.find(e=>e.id===c.entryId));
 if(ids.length===2){
  const body=entries.find(e=>e.category==='nonverbal'),anchor=entries.find(e=>e.assembly==='anchor');
  const pairs={begin:['effort'],work:['effort'],terminal:['effort'],test:['effort'],search:['ponder'],analyze:['ponder'],retry:['effort','frustration'],success:['relief','delight'],celebrate:['relief'],attention:['attention'],setback:['frustration','deflate']};
  if(!body||!anchor||entries.some(e=>e.explicit)||body.repeatFamily===anchor.repeatFamily||!(pairs[anchor.intent]||[]).includes(body.intent))return null;
 }
 const gap=.18,duration=selected.reduce((n,c)=>n+c.seconds,0)+gap*(ids.length-1);
 if(duration>bank.dictionary.policy.maxSeconds)return null;
 let at=0;return {seconds:duration,clips:selected.map(c=>{const result={id:c.id,file:c.file,at,seconds:c.seconds};at+=c.seconds+gap;return result;})};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const args=process.argv.slice(2),value=k=>args[args.indexOf(k)+1];
 if(args.includes('--help'))console.log('node select.mjs --state starting --mood excited --facts task_started [--topic tests] [--audition] [--phrases] [--rare] [--explicit]\nNo playback or API calls. Outputs silence plus up to eight eligible recorded takes. Without --audition only approved takes are eligible.');
 else {
  if(!args.includes('--state')||!args.includes('--mood'))throw Error('Provide --state and --mood; see --help');
  const context={state:value('--state'),mood:value('--mood'),facts:args.includes('--facts')?value('--facts').split(','):[],topic:args.includes('--topic')?value('--topic'):undefined};
  console.log(JSON.stringify({context,options:choices(loadBank(),context,{audition:args.includes('--audition'),explicit:args.includes('--explicit'),phrases:args.includes('--phrases'),rare:args.includes('--rare')})},null,2));
 }
}
