import fs from 'node:fs';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {createHash} from 'node:crypto';
import {catalog,moods} from '../runtime/catalog.mjs';
import {moodAdditions,newMoods} from '../runtime/mood-catalog.mjs';
import {makeScene,sceneEvents,chooseVariation,synthesizeCue} from '../runtime/bank.mjs';
import {moodPlan,moodScore,voiceWindows} from '../runtime/mood-art.mjs';
import {stateOrder} from '../runtime/state-catalog.mjs';
import {cycleHasSound} from '../runtime/score.mjs';
if(process.argv.includes('--help')){console.log('Usage: node characters/pixel/design/boop-sound-bank-v4/qa/check.mjs\nBuild the bank first. Checks coverage, V3 fingerprints, clocks, outcomes and procedural audio; no browser or API needed.');process.exit(0);}
const baseline=JSON.parse(fs.readFileSync(new URL('./v3-fingerprints.json',import.meta.url)));
const sha=value=>createHash('sha256').update(value).digest('hex');
const report={status:'pass',moods:moods.length,states:stateOrder.length,performances:catalog.length,newPerformances:moodAdditions.length,preservedByteExact:0,compactedCards:0,newPlansChecked:0,soundContactsChecked:0,synthRecipesChecked:0};
assert.equal(catalog.length,795);assert.equal(moodAdditions.length,480);assert.equal(new Set(catalog.map(a=>a.id)).size,795);
for(const m of moods)for(const s of stateOrder)assert(catalog.some(a=>a.mood===m&&a.state===s));
for(const m of newMoods){
 assert.equal(catalog.filter(a=>a.mood===m).length,80);
 for(const s of stateOrder)assert(catalog.filter(a=>a.mood===m&&a.state===s).length>=3);
 assert.equal(catalog.filter(a=>a.mood===m&&a.state==='working').length,5);
 for(const outcome of ['success','failure'])for(const r of [0,.49,.999])assert.equal(makeScene(chooseVariation({mood:m,state:'task_complete'},{hostContext:{completionOutcome:outcome},random:()=>r})).asset.outcome,outcome);
 assert.equal(makeScene(chooseVariation({mood:m,state:'task_complete'})).asset.state,'reply_ready');
 assert.throws(()=>chooseVariation({mood:m,state:'task_complete'},{hostContext:{completionOutcome:'unknown'}}));
 for(const context of ['new_task','session','continuation','compacted'])for(const r of [0,.49,.999])assert.equal(makeScene(chooseVariation({mood:m,state:'starting'},{hostContext:{startContext:context},random:()=>r})).asset.startContext,context);
}
const recipes=new Map();let routineBefore=0,routineAfter=0;
for(const a of catalog){
 const scene=makeScene(a.id);assert(!/undefined|NaN|Infinity/.test(scene.svg),a.id);
 // The older seven moods' COMPACTED card came after the V3 freeze: drawn the V3 way, with no fingerprint there.
 if(a.renderer!=='mood-v4'&&a.startContext==='compacted'){assert.equal(a.action,'compact-card');report.compactedCards++;continue;}
 if(a.renderer!=='mood-v4'){const old=baseline.hashes[a.id];assert(old,a.id+' missing independent V3 fingerprint');assert.equal(sha(scene.svg),old.svg,a.id+' changed SVG');assert.equal(sha(JSON.stringify(scene.score)),old.score,a.id+' changed score');report.preservedByteExact++;continue;}
 const plan=moodPlan(a);assert.equal(plan.steps[0].at,0);assert.equal(plan.steps.at(-1).at,a.seconds);assert.equal(plan.steps[0].stage,plan.steps.at(-1).stage);
 for(let i=1;i<plan.steps.length;i++)assert(plan.steps[i].at>plan.steps[i-1].at,a.id+' nonincreasing time');
 for(const tag of scene.svg.matchAll(/<animate\b([^>]+)\/>/g)){
  const attrs=Object.fromEntries([...tag[1].matchAll(/(\w+)="([^"]*)"/g)].map(m=>[m[1],m[2]]));
  const values=attrs.values.split(';'),times=attrs.keyTimes.split(';').map(Number);assert.equal(values.length,times.length);assert.equal(times[0],0);assert.equal(times.at(-1),1);assert.equal(values[0],values.at(-1),a.id+' loop values');
 }
 for(const e of moodScore(a).events){assert.equal(e.at,plan.steps[e.sync.step].at);assert.equal(e.effect,plan.steps[e.sync.step].effect);assert(e.gain>=0&&e.gain<=1);recipes.set(e.effect+':'+e.pitch,e);report.soundContactsChecked++;}
 if(['asleep','no_app','idle','listening','waiting'].includes(a.state))assert.equal(scene.score.events.length,0);
 if(a.state==='needs_you'){const dings=scene.score.events.filter(e=>e.effect==='alertDing');assert.equal(dings.length,1);assert.equal(dings[0].pitch,1);assert.equal(dings[0].at,plan.signal);assert.equal(scene.score.policy,'entry');}
 if(['needs_you','task_complete','error'].includes(a.state))assert(!cycleHasSound(scene.score,1));
 if(a.state==='task_complete'&&a.outcome==='failure')assert(!scene.score.events.some(e=>e.effect.startsWith('trophy')));
 if(a.state==='working'){routineBefore+=moodScore(a).events.length;routineAfter+=scene.score.events.length;}
 for(const seed of [1,53,997])for(const cycle of [0,1,4])for(const e of sceneEvents(scene,{seed,cycle}))assert(moodScore(a).events.some(o=>o.at===e.at&&o.effect===e.effect),a.id+' audio moved');
 const window=voiceWindows(a);assert(Number.isFinite(window.earliestEntry)&&Number.isFinite(window.latestExit));
 report.newPlansChecked++;
}
for(const e of recipes.values()){
 const pcm=synthesizeCue(e,53,16000);let peak=0;for(const x of pcm){assert(Number.isFinite(x));peak=Math.max(peak,Math.abs(x));}assert(peak>0);assert(peak<=1.001);report.synthRecipesChecked++;
}
const c={};vm.runInNewContext(fs.readFileSync(new URL('../dist/boop-runtime.js',import.meta.url),'utf8'),c);assert.equal(c.Boop.catalog.length,795);assert.equal(c.Boop.moods.length,13);
assert.equal(report.preservedByteExact,baseline.assetCount);assert.equal(report.compactedCards,7);
assert.equal(c.Boop.makeScene('wounded.working.05').asset.action,'collect-pieces');
report.newWorkingCueReduction=1-routineAfter/routineBefore;assert(report.newWorkingCueReduction>=.60);report.newWorkingRawCues=routineBefore;report.newWorkingRetainedCues=routineAfter;
fs.writeFileSync(new URL('./checks.json',import.meta.url),JSON.stringify(report,null,2)+'\n');console.log(report);
