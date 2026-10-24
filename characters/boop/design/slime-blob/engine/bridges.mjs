import {createVariations} from './variation.mjs';
import {profileTraits} from './scenes/profile.mjs';
import {faceTarget} from './face.mjs';

const clamp=(value,lo,hi)=>Math.min(hi,Math.max(lo,value));
export const bridgeConstants=Object.freeze({
  durationsMs:Object.freeze({ordinary:Object.freeze([420,680,360]),dramatic:Object.freeze([760,920,560])}),
  frequency:14,damping:12,velocityBound:1,reducedGain:.18,dragDeferMs:320,
  bounds:Object.freeze({lean:.06,squash:.05,forward:.04}),
  faceDurationMs:Object.freeze({ordinary:Object.freeze([320,360,460]),dramatic:Object.freeze([240,280,340])})
});
const primitives=Object.freeze({ordinary:Object.freeze(['soft-retarget','gather-settle','blink-retarget']),
  dramatic:Object.freeze(['recoil-compress','recoil-compress','blink-retarget'])});

export function bridgePlan(graph) {
  const result=[];
  for(const [from,node] of Object.entries(graph?.nodes||{}))for(const category of ['ordinary','dramatic']){
    for(const to of node[category]||[])result.push({id:from+'->'+to,from,to,category,primitives:[...primitives[category]]});
  }
  return result;
}

export function bridgeDirection(fromProfile,toProfile) {
  const source=profileTraits(fromProfile),target=profileTraits(toProfile);
  const a=faceTarget(fromProfile),b=faceTarget(toProfile);
  // Advance/recede comes from authored posture, energy and hesitation. Face
  // dimensions break otherwise equivalent body profiles without mood indices.
  const score=(target.lean-source.lean)+(target.gain-source.gain)*.025+(source.delayMs-target.delayMs)/10000
    +(b.eyeOpen-a.eyeOpen)*.01+(b.mouthWidth-a.mouthWidth)*.005;
  return {direction:Math.sign(score),amplitude:clamp(.8+Math.abs(score)*4,.8,1.2)};
}

// The largest |coefficient| each primitive puts on a channel, before amplitude.
export function primitivePeaks(primitive,variant,category) {
  if(primitive==='soft-retarget')return {lean:.009,squash:.004,forward:.003};
  if(primitive==='gather-settle')return {lean:.026,squash:.032,forward:.012};
  if(primitive==='blink-retarget')return category==='dramatic'?{lean:.026,squash:.035,forward:.014}:{lean:.006,squash:.014,forward:.004};
  return variant===0?{lean:.045,squash:.038,forward:.032}:{lean:.022,squash:.048,forward:.026};
}
// CONTINUITY.md, Directed edge bridges: amplitude is limited so no target
// leaves its channel's displacement bound.
export function amplitudeLimit(primitive,variant,category) {
  const peaks=primitivePeaks(primitive,variant,category);
  return Math.min(...Object.entries(bridgeConstants.bounds).map(([name,bound])=>bound/peaks[name]));
}

export function bridgeTarget(primitive,variant,category,progress,direction,amplitude=1) {
  const p=clamp(progress,0,1),pulse=Math.sin(Math.PI*p)**2;
  let lean=0,squash=0,forward=0;
  if(primitive==='soft-retarget'){
    lean=direction*.009*pulse;squash=.004*pulse;forward=.003*pulse;
  }else if(primitive==='gather-settle'){
    lean=direction*.026*pulse;squash=-.032*pulse;forward=.012*Math.sin(Math.PI*2*p)*pulse;
  }else if(primitive==='blink-retarget'){
    const dramatic=category==='dramatic',held=p<.25?0:Math.sin(Math.PI*(p-.25)/.75)**2;
    lean=direction*(dramatic?.026:.006)*held;squash=-(dramatic?.035:.014)*held;forward=-(dramatic?.014:.004)*held;
  }else if(primitive==='recoil-compress'){
    if(variant===0){
      lean=-direction*.045*Math.sin(Math.PI*2*p)*pulse;squash=-.038*pulse;forward=-.032*pulse;
    }else{
      lean=direction*.022*pulse;squash=-.048*pulse;forward=.026*Math.sin(Math.PI*2*p)*pulse;
    }
  }
  return {lean:lean*amplitude,squash:squash*amplitude,forward:forward*amplitude};
}

export function createBridges({graph,profiles,rand,reduced}) {
  const edges=new Map(bridgePlan(graph).map(edge=>[edge.id,edge])),variations=createVariations(rand);
  const channels={lean:{x:0,v:0},squash:{x:0,v:0},forward:{x:0,v:0}};
  let active=null,context={quiet:false,grabActive:false,attention:false};
  function retarget(from,to,time,{bridgeVariant}={}) {
    if(bridgeVariant!==undefined&&(!Number.isInteger(bridgeVariant)||bridgeVariant<0||bridgeVariant>2))throw new RangeError('bridgeVariant must be 0, 1 or 2');
    const canonicalFrom=profiles[from].mood,canonicalTo=profiles[to].mood;
    const edge=edges.get(canonicalFrom+'->'+canonicalTo),category=edge?.category||'direct';
    const variant=edge?(bridgeVariant??variations.next(edge.id)):0;
    const primitive=edge?edge.primitives[variant]:'soft-retarget';
    const direction=bridgeDirection(profiles[from],profiles[to]);
    direction.amplitude=Math.min(direction.amplitude,amplitudeLimit(primitive,variant,category));
    active={from,to,edgeId:edge?.id||null,category,primitive,variant,...direction,
      elapsedMs:0,durationMs:bridgeConstants.durationsMs[edge?.category||'ordinary'][variant],
      startedAtMs:time,deferredMs:0,expired:false,suppressed:context.quiet||context.attention};
    return {durationMs:bridgeConstants.faceDurationMs[edge?.category||'ordinary'][variant]};
  }
  function setContext(value) {
    context={...context,...value};
    // Suppression consumes this gesture; waking/clearing an alert cannot replay
    // an old transition. The face retarget is independent and continues.
    if(active&&(context.quiet||context.attention))active.suppressed=true;
  }
  function advance(dt) {
    let target={lean:0,squash:0,forward:0};
    if(active){
      if(context.grabActive&&active.elapsedMs<active.durationMs&&!active.suppressed&&!active.expired){
        active.deferredMs+=dt*1000;
        if(active.deferredMs>=bridgeConstants.dragDeferMs){active.expired=true;active.suppressed=true;}
      }else active.elapsedMs=Math.min(active.durationMs,active.elapsedMs+dt*1000);
      if(!context.grabActive&&!active.suppressed&&!active.expired&&active.elapsedMs<active.durationMs){
        target=bridgeTarget(active.primitive,active.variant,active.category,active.elapsedMs/active.durationMs,active.direction,active.amplitude);
      }
    }
    const gain=reduced.matches?bridgeConstants.reducedGain:1;
    for(const [name,m] of Object.entries(channels)){
      let left=dt;
      while(left>0){const h=Math.min(left,1/240);m.v+=(bridgeConstants.frequency**2*(target[name]*gain-m.x)-bridgeConstants.damping*m.v)*h;m.x+=m.v*h;left-=h;}
      m.x=clamp(m.x,-bridgeConstants.bounds[name],bridgeConstants.bounds[name]);m.v=clamp(m.v,-bridgeConstants.velocityBound,bridgeConstants.velocityBound);
    }
  }
  function inspect() {
    const progress=active?active.elapsedMs/active.durationMs:1;
    const deferred=Boolean(active&&active.elapsedMs<active.durationMs&&context.grabActive&&!active.suppressed&&!active.expired);
    const phase=!active?'idle':active.expired?'expired':active.suppressed?'suppressed':deferred?'deferred':progress>=1?'settled':progress<.35?'gather':'release';
    return {bridge:active?{...active,progress,phase,deferred}:{from:null,to:null,edgeId:null,category:null,primitive:null,variant:null,
      elapsedMs:0,durationMs:0,startedAtMs:0,deferredMs:0,expired:false,suppressed:false,direction:0,amplitude:0,progress:1,phase:'idle',deferred:false},
      bridgeChannels:Object.fromEntries(Object.entries(channels).map(([name,m])=>[name,{...m}]))};
  }
  return {retarget,setContext,advance,inspect,channels};
}
