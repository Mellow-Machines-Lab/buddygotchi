#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {root,loadEngine,loadCatalog,readScript,runScript} from './trace.mjs';
import {createCues,comedyKinds} from '../engine/cues.mjs';
import {createPlayer,playerPolicy} from '../sound/player.mjs';
const SPEC='sound/README.md, Synchronized reference cues';
if(process.argv.includes('--help')){console.log('node tools/check-cues.mjs\nChecks contact synchronization, quiet policy, deterministic audio and the output mixer without playing sound.');process.exit(0);}
const catalog=loadCatalog(),createSlime=await loadEngine(),plan=catalog.sound;
assert.deepEqual(plan.mix,{routineContactProbability:.25,maxRoutineGesturesPerCycle:4,shortLoopMinimumSeconds:3.5,shortLoopSoundEvery:2,routineVoiceDuck:.25,attentionAfterCueVoiceGapSeconds:.12,routineVoiceWindowSeconds:.45,attention:'Every new request/outcome only once; variation changes never replay ding. Volume zero silences all.'},SPEC);
assert.deepEqual(playerPolicy,{lateMs:150,voices:4,fadeSeconds:.004,routineDuck:.25},SPEC);
let frames=0,totalCues=0;
for(const file of fs.readdirSync(path.join(root,'scripts')).filter(f=>f.endsWith('.jsonl'))){
 const script=readScript(path.join(root,'scripts',file)),a=runScript(createSlime,catalog,script,53),b=runScript(createSlime,catalog,script,53);
 assert.deepEqual(a,b,SPEC+': deterministic cues');
 const silent=runScript(createSlime,{...catalog,sound:null},script,53);
 assert.deepEqual(a.frames,silent.frames,SPEC+': audio randomness cannot change any motion channel');
 const ids=new Set();
 for(const {at,cue} of a.cues){
  const frame=a.frames[at/16],contact=frame.contacts.find(c=>c.id===cue.contactId);
  assert.ok(contact,SPEC+': sound has a visible contact in the same frame');assert.equal(cue.timeMs,contact.timeMs);
  assert.ok(!ids.has(cue.id),SPEC+': unique cues');ids.add(cue.id);
  // Quiet states sound only comedy: idle's sneeze, excited's zoomies, asleep's snore.
  assert.ok(!['idle','asleep','no_app','listening','waiting'].includes(frame.scene.state)||comedyKinds.has(cue.kind),SPEC+': quiet states');
  if(comedyKinds.has(cue.kind))assert.equal(cue.protected,false,SPEC+': comedy is routine, ducked under a line');
 }
 if(file==='attention-sound.jsonl')assert.equal(a.cues.filter(c=>c.cue.recipe==='ding').length,1,SPEC+': 60 seconds and three mood changes produce one ding');
 if(file==='comedy.jsonl'){
  const recipes=a.cues.map(c=>c.cue.recipe);
  for(const recipe of ['sneeze','breath','complete','squish'])assert.ok(recipes.includes(recipe),SPEC+': the comedy script sounds '+recipe);
  assert.equal(a.cues.filter(c=>c.cue.recipe==='squish').length,3,SPEC+': three hiccups, three little contacts');
 }
 totalCues+=a.cues.length;frames+=a.frames.length;
}
// Repeated loops of one result must not fanfare again.
for(const outcome of ['success','failure']){
 const e=createSlime({seed:53,catalog});e.step(0);e.oneShot({id:1,name:'task_complete',args:{outcome,loops:6}});
 let count=0;for(let at=16;at<=26000;at+=16)count+=e.step(at).cues.filter(c=>c.recipe===(outcome==='success'?'complete':'failed')).length;
 assert.equal(count,1,SPEC+': one result cue per request, not per loop');
}
// A held request keeps its sound identity; a genuinely new request sounds again.
const attention=createSlime({seed:53,catalog});attention.step(0);let now=0,dings=[];
const advance=ms=>{for(let i=0;i<ms;i+=16){now+=16;dings.push(...attention.step(now).cues.filter(c=>c.recipe==='ding'));}};
attention.setFacts({base:'working',attn:{id:7,agent:'codex',project:'a'}});advance(2400);
attention.setMood('frightened');attention.setFacts({base:'working',attn:{id:7,agent:'codex',project:'a',name:'Renamed',more:3}});advance(4800);
attention.setLinkTimedOut(true);advance(160);attention.setLinkTimedOut(false);advance(2400);
assert.equal(dings.length,1,SPEC+': mood, wording and link restore do not replay an alert');
attention.setFacts({base:'working',attn:{id:8,agent:'codex',project:'a'}});advance(2400);
assert.equal(dings.length,2,SPEC+': new request earns one new ding');
for(const ding of dings)assert.deepEqual([ding.variant,ding.seed,ding.pitch,ding.gain],[0,53,1,.45],SPEC+': ding identity invariant');
// Long routines stay sparse, and replaying an inspection cannot replay audio.
const e=createSlime({seed:53,catalog});e.step(0);e.setFacts({base:'working'});const counts=new Map();let contacts=0,cues=0;
for(let at=16;at<=600000;at+=16){const out=e.step(at);contacts+=out.channels.contacts.length;cues+=out.cues.length;
 const s=out.channels.scene,key=[s.generation,s.iteration].join(':');counts.set(key,(counts.get(key)||0)+out.cues.length);
 assert.ok(counts.get(key)<=4,SPEC+': four contacts per cycle');if(s.loopDurationMs<3500&&s.iteration%2)assert.equal(out.cues.length,0,SPEC+': short odd cycles silent');
 assert.deepEqual(e.step(at).cues,[],SPEC+': repeated timestamp never replays cues');}
assert.ok(cues>0&&cues<contacts*.4,SPEC+': routine contact selection stays sparse');
// Comedy stays sparse: over twenty minutes of idle, and of sleep, only the
// sneeze and the snore's breaths sound, each with the routine chance.
const comedySound={};
for(const [base,recipe] of [['idle','sneeze'],['asleep','breath']]){
 const s=createSlime({seed:53,catalog});s.step(0);s.setFacts({base});let comedy=0,sounded=0;
 for(let at=16;at<=1200000;at+=16){const out=s.step(at);comedy+=out.channels.contacts.filter(c=>comedyKinds.has(c.kind)).length;
  for(const cue of out.cues){assert.equal(cue.recipe,recipe,SPEC+': '+base+' sounds only its comedy');sounded++;}}
 assert.ok(comedy>0&&sounded>0&&sounded<comedy*.5,SPEC+': '+base+' comedy sounds sparsely ('+sounded+' of '+comedy+')');
 comedySound[base]={contacts:comedy,cues:sounded};
}
// Mock audio backend exercises the real player without a speaker or browser.
const sfx=createRequire(import.meta.url)('../sound/sfx.js');let starts=0,stops=[],levels=[];
const ctx={state:'running',currentTime:1,sampleRate:11025,resume:async()=>{},destination:{},createBuffer:(n,len,rate)=>({copyToChannel:()=>{}}),
 createBufferSource:()=>({connect(){},disconnect(){},start(){starts++;},stop(at){stops.push(at);}}),
 createGain:()=>{const gain={value:1,cancelScheduledValues(){},setValueAtTime(v){this.value=v;},linearRampToValueAtTime(v){this.value=v;}};levels.push(gain);return {gain,connect(){},disconnect(){}};}};
const player=createPlayer({sfx,makeContext:()=>ctx});
const frame=(id,time=1000,generation=1,protectedCue=false)=>({channels:{time:time/1000,expression:'happy',scene:{generation}},cues:[{id,recipe:'poke',timeMs:1000,gain:.2,pitch:1,seed:53,variant:0,protected:protectedCue}]});
player.consume(frame('muted'));await player.enable();player.consume(frame('muted'));assert.equal(starts,0,SPEC+': no unmute backlog');
player.consume(frame('late',1151));assert.equal(starts,0,SPEC+': late drop');player.consume(frame('boundary',1150));assert.equal(starts,1,SPEC+': late boundary inclusive');
player.setMix({voiceActive:true});assert.equal(levels.at(-1).value,.25,SPEC+': routine duck');
player.consume(frame('attention',1000,1,true));assert.equal(levels.at(-1).value,1,SPEC+': protected unducked');
for(let i=0;i<5;i++)player.consume(frame('voice'+i));assert.equal(player.inspect().active,4,SPEC+': four voice bound');assert.ok(stops.includes(1),SPEC+': fifth replaces oldest immediately');
player.setMix({volume:0});assert.equal(player.inspect().active,0,SPEC+': zero volume stops all');assert.ok(stops.includes(1),SPEC+': mute immediate');
const countBefore=starts;player.consume(frame('zero'));player.setMix({volume:1});player.consume(frame('zero'));assert.equal(starts,countBefore,SPEC+': zero volume consumes');
ctx.state='suspended';player.consume(frame('suspended'));ctx.state='running';player.consume(frame('suspended'));assert.equal(starts,countBefore,SPEC+': suspension consumes');
player.consume(frame('fresh'));player.consume({channels:{time:1,expression:'sad',scene:{generation:2}},cues:[]});assert.equal(player.inspect().active,0,SPEC+': interrupted generation clears tails');assert.ok(stops.includes(1.004),SPEC+': interruption tail fade');player.setMix({muted:true});assert.equal(stops.at(-1),1,SPEC+': mute also stops a fading tail');
assert.equal(sfx.recipes.knock,.13,SPEC+': contact knock duration');assert.equal(sfx.recipes.ding,.68,SPEC+': reveal ding duration');
const dingA=sfx.render('ding',{seed:53,variant:0,pitch:.7}),dingB=sfx.render('ding',{seed:53,variant:0,pitch:1.4});assert.deepEqual(dingA.data,dingB.data,SPEC+': invariant ding pitches');
console.log(JSON.stringify({status:'SYNCHRONIZED CUES PASS',frames,cues:totalCues,routineContacts:contacts,routineCues:cues,comedy:comedySound,holdDings:1,player:'mute, stale, suspension, ducking, interruption, four voices'}));
