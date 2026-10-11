import {catalog,getAsset} from './catalog.mjs';
import {renderVariation} from './visual/renderer.mjs';
import {syncKeyboard} from './keyboard.mjs';
import {composeScore,cycleHasSound} from './score.mjs';
import {effectRecipe} from './audio/effects.mjs';
import {renderRecipe} from './audio/synth.mjs';
import {renderNeedsYou} from './needs-you.mjs';
import {renderStateScene,stateScore} from './state-art.mjs';
import {quietMix,routineEvents} from './quiet-mix.mjs';
import {renderMoodScene,moodScore} from './mood-art.mjs';

export function makeScene(id){
  const asset=getAsset(id);
  if(asset.renderer==='mood-v4')return {asset,svg:renderMoodScene(asset),score:quietMix(asset,moodScore(asset))};
  if(asset.renderer==='state-v3')return {asset,svg:renderStateScene(asset),score:quietMix(asset,stateScore(asset))};
  const svg=asset.state==='needs_you'?renderNeedsYou(asset):syncKeyboard(renderVariation(asset.mood,asset.state,asset.variation,asset.name),asset);
  return {asset,svg,score:quietMix(asset,composeScore(asset,svg))};
}
export function cueSeed(effect,seed=53){let h=seed>>>0;for(const c of effect)h=Math.imul(h^c.charCodeAt(0),16777619)>>>0;return h;}
export function synthesizeCue(event,seed=53,sampleRate=44100){return renderRecipe(effectRecipe(event.effect,event.pitch),cueSeed(event.effect,seed),sampleRate);}
export function sceneEvents(scene,{cycle=0,seed=53}={}){return routineEvents(scene.score,cycle,seed);}
// Finite PCM is generated only on demand. This helper is for tests/offline use;
// the browser player schedules individual cached cues instead of a full bank.
export function renderSceneAudio(scene,{cycles=1,seed=53,sampleRate=44100}={}){
  if(!Number.isInteger(cycles)||cycles<1||cycles>3)throw new Error('Finite rendering supports 1–3 cycles');
  if(!Number.isInteger(sampleRate)||sampleRate<8000||sampleRate>96000)throw new Error('Invalid sample rate');
  const duration=scene.asset.seconds*cycles+scene.score.tailSeconds+.03;
  const output=new Float32Array(Math.ceil(duration*sampleRate)),cache=new Map();
  for(let cycle=0;cycle<cycles;cycle++)if(cycleHasSound(scene.score,cycle))for(const event of sceneEvents(scene,{cycle,seed})){
    const key=event.effect+':'+event.pitch;
    if(!cache.has(key))cache.set(key,synthesizeCue(event,seed,sampleRate));
    const clip=cache.get(key),start=Math.round((cycle*scene.asset.seconds+event.at)*sampleRate);
    for(let i=0;i<clip.length&&start+i<output.length;i++)output[start+i]+=clip[i]*event.gain*.9;
  }
  return output;
}
export function chooseVariation(pair,{previousId=null,random=Math.random,hostContext={}}={}){
  let state=pair.state;
  if(state==='task_complete'&&!hostContext.completionOutcome)state='reply_ready';
  if(pair.state==='task_complete'&&hostContext.completionOutcome&&!['success','failure'].includes(hostContext.completionOutcome))throw new Error('Invalid task completion outcome');
  if(state==='starting'&&hostContext.startContext&&!['new_task','session','continuation','compacted'].includes(hostContext.startContext))throw new Error('Invalid start context');
  const list=catalog.filter(a=>a.mood===pair.mood&&a.state===state&&
    (state!=='task_complete'||a.outcome===hostContext.completionOutcome)&&
    (state!=='starting'||a.startContext===(hostContext.startContext||'session')));
  if(!list.length)throw new Error('Invalid mood/state pair');
  const choices=list.filter(a=>a.id!==previousId);
  const draw=Math.max(0,Math.min(.999999,Number(random())||0));
  return (choices.length?choices:list)[Math.floor(draw*(choices.length||list.length))].id;
}
