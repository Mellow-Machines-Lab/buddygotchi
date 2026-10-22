// Voice-first mix. Keep the accepted animation/cue clocks; omit routine sounds,
// never move a retained sound away from its visible contact. No master-volume hack.
import {random} from './audio/synth.mjs';
export const protectedSoundStates=['needs_you','task_complete','error'];
const silenceStates=['idle','asleep','no_app','listening','waiting'];
const highlightEffects=['snap','snip','glass','bash','landing','wood','latch','key','keyB','keyC','softKey','space','paper','rubber','pop','slide'];
function patternSeed(id,seed,cycle){let h=(seed^Math.imul(cycle+1,2654435761))>>>0;for(const c of id)h=Math.imul(h^c.charCodeAt(0),16777619)>>>0;return h;}
export function routineEvents(score,cycle=0,seed=53){
 const mix=score.mix;if(!mix?.gestures)return score.events;
 const rng=random(patternSeed(score.id,seed,cycle)),groups=mix.gestures,chosen=[];let count=0;
 const add=g=>{if(!g||chosen.some(x=>x.group===g)||chosen.length>=4||count>=mix.cueBudget)return;const members=g.members.slice(0,mix.cueBudget-count);chosen.push({group:g,members,gain:.76+rng()*.24});count+=members.length;};
 const keys=groups.filter(g=>['key','keyB','keyC','softKey','space'].includes(g.members[0].effect));
 if(keys.length>=5){
  // A short adjacent run, a gap, then an optional stray contact. Anchors and
  // burst sizes change each cycle; retained presses keep their own releases.
  const length=rng()<.5?2:3,anchor=Math.floor(rng()*Math.max(1,keys.length-length+1));
  for(let i=0;i<length;i++)add(keys[anchor+i]);
  const outside=keys.filter(g=>Math.min(...chosen.map(c=>Math.abs(g.at-c.group.at)))>.55);
  if(outside.length)add(outside[Math.floor(rng()*outside.length)]);
 }else{
  // Preserve the main material action, e.g. the actual SNAP; randomize which
  // supporting contacts are heard, without inventing or delaying impacts.
  const ranked=groups.map(g=>({g,rank:highlightEffects.indexOf(g.members[0].effect)})).sort((a,b)=>(a.rank<0?99:a.rank)-(b.rank<0?99:b.rank));
  const important=ranked.filter(x=>x.rank>=0&&x.rank<=2);
  add(important.length?important[Math.floor(rng()*important.length)].g:groups[Math.floor(rng()*groups.length)]);
  const remaining=groups.map(g=>({g,draw:rng()})).sort((a,b)=>a.draw-b.draw);
  for(const {g}of remaining)if(!chosen.some(c=>Math.abs(c.group.at-g.at)<.075))add(g);
 }
 return chosen.flatMap(c=>c.members.map(e=>({...e,gain:Number((e.gain*.68*c.gain).toFixed(6))}))).sort((a,b)=>a.at-b.at);
}
export function quietMix(asset,score){
 if(protectedSoundStates.includes(asset.state))return score;
 // A comedy design breaks the quiet on purpose (comedy-art.mjs): one
 // 'scored' keeps its soft cue or two as scored, a yawn once or a sneeze or
 // a snore every few loops; one 'routine' takes the routine mix below, even
 // in a quiet state.
 if(asset.sound==='scored')return score;
 const original=score.events.length;
 if(silenceStates.includes(asset.state)&&asset.sound!=='routine')return {...score,policy:'silent',intervalSeconds:0,tailSeconds:0,events:[],description:'Intentionally silent in the voice-first mix.',mix:{profile:'voice-first',originalCueCount:original,retainedCueCount:0}};
 if(!original)return score;
 // An early attack plus a release is one physical key gesture. Pair only when
 // the source actually identifies that release; unrelated cues stay independent.
 const groups=[];const used=new Set();
 for(let i=0;i<original;i++){
  if(used.has(i))continue;const e=score.events[i];
  if(e.effect==='release')continue;
  const members=[e];used.add(i);
  if(e.sync?.key==='press'){
   const j=score.events.findIndex((x,k)=>k>i&&x.sync?.key==='release'&&x.sync.beat===e.sync.beat);
   if(j>=0){members.push(score.events[j]);used.add(j);}
  }else if(e.sync?.pose?.startsWith('key-')){
   const j=score.events.findIndex((x,k)=>k>i&&x.sync?.pose==='up-'+e.sync.pose.slice(4));
   if(j>=0){members.push(score.events[j]);used.add(j);}
  }
  groups.push({at:e.at,members});
 }
 const mix={profile:'voice-first',originalCueCount:original,cueBudget:Math.max(1,Math.floor(original*.30)),gestures:groups};
 const events=routineEvents({...score,mix});
 // Very short busy loops leave a silent cycle between their remaining accents.
 // Longer loops already have generous empty space after their few contact cues.
 const sparse=score.policy==='loop'&&asset.seconds<3.5;
 return {...score,events,policy:sparse?'sparse':score.policy,intervalSeconds:sparse?asset.seconds*2:score.intervalSeconds,
  description:'Voice-first: irregular little bursts, pauses and soft accents selected from real visual contacts. '+score.description,
  mix:{...mix,retainedCueCount:events.length,cueReduction:Number((1-events.length/original).toFixed(4)),routineGainMultiplier:.68,accentMultiplierRange:[.76,1],pattern:'seeded clusters, fresh per playback/cycle',silentAlternateCycles:sparse}};
}
