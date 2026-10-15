// Semantic dimensions derived from the existing painter's art primitives. A
// renderer draws the ONE selected primitive at face.render's ratios: at rest
// each ratio is one, preserving the authored face without silhouette blends.
const eyeDimensions={
  'soft-dot':.049,'comfy-dash':.014,'lazy-equals':.025,'bored-bean':.026,
  'sleepy-lid':.041,'spent-lid':.090,'pleased-bean':.022,'happy-dot':.046,
  'laugh-lid':.123,'amused-wink':.068,'curious-eggs':.049,'attentive-eggs':.058,
  'gentle-resolve':.056,'puzzled-eggs':.0555,'baffled-eggs':.0575,'skeptical-lids':.026,
  'smug-lids':.024,'cheeky-beans':.018,'bashful-squeeze':.038,'averted-eggs':.045,
  'warm-lids':.087,'longing-beans':.043,'annoyed-beans':.027,'irritated-beans':.023,
  'grumpy-beans':.026,'angry-squeeze':.055,'letdown-lids':.035,'sad-lids':.077,
  'crying-lids':.091,'pleading-eyes':.059,'hurt-eggs':.050,'cautious-eggs':.050,
  'scared-water':.080,'welling-eyes':.068,'surprise-dots':.058,'shook-ovals':.029,
  'stare-lids':.038,'hopeful-eggs':.060,'released-lids':.089,'uneasy-almonds':.050,
  'wince-lids':.055,'overloaded-eggs':.060,'rosy-beans':.016,'blank-water':.019
};
const mouthDimensions={
  'tiny-ring':[.018,.026],'little-bean':[.046,.061],'baby-w':[.076,.037],
  'tiny-frown':[.031,.031],'baby-yawn':[.036,.049],'spent-pout':[.046,.009],
  'happy-u':[.076,.121],'wide-laugh':[.135,.107],'crooked-grin':[.086,.060],
  'small-u-line':[.044,.029],'firm-w':[.062,.024],'tilted-o':[.020,.031],
  'little-triangle':[.037,.037],'shook-triangle':[.037,.037],'tiny-triangle':[.031,.037],
  'crooked-pout':[.043,.020],'curled-smirk':[.075,.032],'puckered-three':[.074,.064],
  'tiny-v':[.028,.048],'awkward-w':[.058,.031],'warm-w':[.068,.036],
  'small-pout':[.032,.030],'pushed-pout':[.043,.021],'tense-pout':[.052,.034],
  'grumpy-pout':[.065,.039],'protest-bean':[.074,.075],'sad-pout':[.035,.028],
  'quivering-pout':[.047,.031],'complaining-pout':[.062,.052],'hurt-pout':[.033,.033],
  'uneasy-wave':[.058,.024],'fear-wave':[.079,.032],'frightened-pout':[.070,.081],
  'round-gasp':[.035,.047],'tiny-caret':[.030,.030],'exhale-bean':[.048,.050],
  'side-blep':[.053,.036],'blank-line':[.041,.002],'small-waver':[.062,.024]
};

// CONTINUITY.md, Phase 1 channel bounds: each semantic control is a critically
// damped spring (frequency 20, or 30 with reduced motion) that keeps its
// velocity across retargets.
export const faceTransition=Object.freeze({durationSeconds:.18,frequency:20,reducedFrequency:30});
// CONTINUITY.md, Directed edge bridges: the drawn art's size ratios stay in
// (0.75, 4/3), and the mouth passes through a dot at the swap.
export const faceRender=Object.freeze({ratioLow:.75,ratioHigh:4/3,mouthDot:.8});
// The shared sleeping face: the tired art, squashed to these dimensions.
export const sleepTarget=Object.freeze({eyeOpen:.004,mouthWidth:.018,curve:.008,cheekAlpha:0,tearAmount:0});
const controlKeys=['eyeX','eyeY','eyeOpen','mouthY','mouthWidth','curve','cheekAlpha','tearAmount'];

export function faceTarget(profile) {
  const art=profile.art,[mouthWidth,curve]=mouthDimensions[art.mouth];
  return {eyeX:art.eyeX,eyeY:art.eyeY,eyeOpen:eyeDimensions[art.eyes],mouthY:art.mouthY,
    mouthWidth,curve,cheekAlpha:art.cheeks==='none'?0:1,tearAmount:profile.tears==='none'?0:1};
}
// The sleeping art's own authored size, relative to the tired art it reuses.
export function sleepScale(profiles) {
  const tired=faceTarget(profiles.tired);
  return {eye:sleepTarget.eyeOpen/tired.eyeOpen,mouthWidth:sleepTarget.mouthWidth/tired.mouthWidth,mouthHeight:sleepTarget.curve/tired.curve};
}
// A smooth saturation: slope one at one, never reaching either bound.
export function softRatio(value) {
  const x=value-1,room=x<0?1-faceRender.ratioLow:faceRender.ratioHigh-1;
  return 1+x*room/(room+Math.abs(x));
}
const ease=u=>Math.sin(Math.min(1,Math.max(0,u))*Math.PI/2)**2;

export function createFace({profiles,initialEmotion,reduced}) {
  let targetId=initialEmotion,artId=initialEmotion,targetSleeping=false,sleeping=false;
  let target=faceTarget(profiles[targetId]);
  const controls={...target},velocity=Object.fromEntries(controlKeys.map(key=>[key,0]));
  let bridge=null,bridgeBlink=0;
  let transition={from:{...controls},to:{...target},elapsedMs:0,durationMs:faceTransition.durationSeconds*1000};
  let render={eye:1,mouthWidth:1,mouthHeight:1,mouth:1,cheek:controls.cheekAlpha,tear:controls.tearAmount};
  let mix={cheek:1,tear:1};
  const styles=id=>({cheek:profiles[id].art.cheeks,tear:profiles[id].tears});
  function baseline() {return sleeping?{...faceTarget(profiles.tired),...sleepTarget}:faceTarget(profiles[artId]);}
  function retarget({durationMs=faceTransition.durationSeconds*1000}={}) {
    const nextArt=targetSleeping?'tired':targetId;
    target=faceTarget(profiles[nextArt]);
    if(targetSleeping)target={...target,...sleepTarget};
    // Every discrete art retarget uses this small face-only bridge. Extreme
    // pairs cannot show two silhouettes, and a mid-bridge retarget starts from
    // the current closure, drawn ratios and dips rather than resetting them.
    const from=styles(artId),to=styles(nextArt);
    bridge={age:0,duration:durationMs/1000,startClosure:bridgeBlink,switched:false,
      start:{eye:render.eye,mouthWidth:render.mouthWidth,mouthHeight:render.mouthHeight,cheek:mix.cheek,tear:mix.tear},
      swap:{cheek:from.cheek===to.cheek?1:0,tear:from.tear===to.tear?1:0}};
    transition={from:{...controls},to:{...target},elapsedMs:0,durationMs};
  }
  function setMood(id,options) {
    if(id===targetId)return;
    targetId=id;if(!targetSleeping)retarget(options);
  }
  function setSleeping(value) {
    value=Boolean(value);if(value===targetSleeping)return;
    targetSleeping=value;retarget();
  }
  // What the painters draw. Before the swap the old art eases from the ratio
  // it was drawn at to its own size; after it the new art eases from its own
  // size to the live ratio. A cheek or tear style that changes dips to zero
  // at the swap; one that stays keeps its opacity.
  function updateRender() {
    const base=baseline();
    const live={eye:softRatio(controls.eyeOpen/base.eyeOpen),mouthWidth:softRatio(controls.mouthWidth/base.mouthWidth),
      mouthHeight:softRatio(controls.curve/base.curve)};
    const ratios={},next={};
    if(!bridge){Object.assign(ratios,live);next.cheek=next.tear=1;}
    else if(!bridge.switched){
      const e=ease(bridge.age/(bridge.duration/2));
      for(const key of ['eye','mouthWidth','mouthHeight'])ratios[key]=bridge.start[key]+(1-bridge.start[key])*e;
      for(const key of ['cheek','tear'])next[key]=bridge.start[key]+(bridge.swap[key]-bridge.start[key])*e;
    }else{
      const e=1-bridgeBlink;
      for(const key of ['eye','mouthWidth','mouthHeight'])ratios[key]=1+(live[key]-1)*e;
      for(const key of ['cheek','tear'])next[key]=bridge.swap[key]+(1-bridge.swap[key])*e;
    }
    mix=next;
    render={...ratios,mouth:1-faceRender.mouthDot*bridgeBlink,
      cheek:Math.min(1,Math.max(0,controls.cheekAlpha*mix.cheek)),tear:Math.min(1,Math.max(0,controls.tearAmount*mix.tear))};
  }
  return {
    setMood,setSleeping,
    advance(dt) {
      const frequency=reduced.matches?faceTransition.reducedFrequency:faceTransition.frequency;
      for(const key of controlKeys){
        let x=controls[key],v=velocity[key],left=dt;
        while(left>0){const h=Math.min(left,1/240);v+=(frequency*frequency*(target[key]-x)-2*frequency*v)*h;x+=v*h;left-=h;}
        if(key==='cheekAlpha'||key==='tearAmount')x=Math.min(1,Math.max(0,x));
        controls[key]=x;velocity[key]=v;
      }
      if(bridge){
        bridge.age+=dt;
        transition.elapsedMs=Math.min(transition.durationMs,bridge.age*1000);
        const half=bridge.duration/2;
        if(bridge.age<half){
          bridgeBlink=bridge.startClosure+(1-bridge.startClosure)*ease(bridge.age/half);
        }else if(!bridge.switched){
          artId=targetSleeping?'tired':targetId;sleeping=targetSleeping;bridge.switched=true;bridgeBlink=1;
        }else if(bridge.age<bridge.duration){
          bridgeBlink=Math.cos((bridge.age-half)/half*Math.PI/2)**2;
        }else {bridge=null;bridgeBlink=0;artId=targetSleeping?'tired':targetId;sleeping=targetSleeping;}
      }
      updateRender();
    },
    inspect(naturalBlink=0) {
      return {...controls,artId,art:{...profiles[artId].art},artBaseline:baseline(),
        sleeping,bridgeBlink,blink:Math.max(naturalBlink,bridgeBlink),render:{...render},velocity:{...velocity},
        transition:{from:{...transition.from},to:{...transition.to},elapsedMs:transition.elapsedMs,durationMs:transition.durationMs,active:Boolean(bridge)}};
    }
  };
}
