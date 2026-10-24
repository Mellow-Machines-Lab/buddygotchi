import {hermite} from './scenes/ramp.mjs';

// Semantic dimensions derived from the existing painter's art primitives. A
// renderer draws each layer's art at its ratios: at rest each ratio is one,
// preserving the authored face.
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
export const faceTransition=Object.freeze({durationMs:180,frequency:20,reducedFrequency:30});
// CONTINUITY.md, Directed edge bridges: the drawn art's size ratios stay in
// (0.75, 4/3), and at most four arts are drawn at once.
export const faceRender=Object.freeze({ratioLow:.75,ratioHigh:4/3,layers:4});
// The shared sleeping face: the tired art, squashed to these dimensions.
export const sleepTarget=Object.freeze({eyeOpen:.004,mouthWidth:.018,curve:.008,cheekAlpha:0,tearAmount:0});
const controlKeys=['eyeX','eyeY','eyeOpen','mouthY','mouthWidth','curve','cheekAlpha','tearAmount'];

export function faceTarget(profile) {
  const art=profile.art,[mouthWidth,curve]=mouthDimensions[art.mouth];
  return {eyeX:art.eyeX,eyeY:art.eyeY,eyeOpen:eyeDimensions[art.eyes],mouthY:art.mouthY,
    mouthWidth,curve,cheekAlpha:art.cheeks==='none'?0:1,tearAmount:profile.tears==='none'?0:1};
}
// A layer's own size, which its drawn ratios are over: its art's, or the
// sleeping face's, the tired art squashed.
export function dimensions(profiles,{artId,sleeping}) {
  return sleeping?{...faceTarget(profiles.tired),...sleepTarget}:faceTarget(profiles[artId]);
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

export function createFace({profiles,initialEmotion,reduced}) {
  let targetId=initialEmotion,targetSleeping=false;
  let target=faceTarget(profiles[targetId]);
  const controls={...target},velocity=Object.fromEntries(controlKeys.map(key=>[key,0]));
  // The arts drawn, oldest first and the current one last. Each layer has a
  // Hermite from its value and slope at the last retarget toward one (the
  // current art) or zero (the others) over the transition's window, so a
  // retarget keeps every weight's velocity; its weight is its share of them.
  let layers=[{artId:initialEmotion,sleeping:false,from:1,tangent:0,to:1,weight:1}];
  function weigh(s) {
    for(const layer of layers)layer.weight=hermite(layer,s).value;
    const sum=layers.reduce((total,layer)=>total+layer.weight,0);
    for(const layer of layers)layer.weight/=sum;
  }
  // The window the arts cross over in, and how far into it they are.
  let transition={from:{...controls},to:{...target},elapsedMs:0,durationMs:faceTransition.durationMs};
  function retarget({durationMs=faceTransition.durationMs}={}) {
    const artId=targetSleeping?'tired':targetId,sleeping=targetSleeping,s=transition.elapsedMs/transition.durationMs;
    target=dimensions(profiles,{artId,sleeping});
    for(const layer of layers){const {value,slope}=hermite(layer,s);Object.assign(layer,{from:value,tangent:slope*durationMs/transition.durationMs,to:0});}
    // An art still fading comes back from the weight it has.
    let top=layers.find(layer=>layer.artId===artId&&layer.sleeping===sleeping);
    if(top)layers.splice(layers.indexOf(top),1);else top={artId,sleeping,from:0,tangent:0};
    top.to=1;layers.push(top);
    // One at zero that can only stay there is gone; past four, so is the
    // faintest, the others' shares growing to fill what it leaves.
    layers=layers.filter(layer=>layer===top||layer.from>0||layer.tangent>0);
    if(layers.length>faceRender.layers)layers.splice(layers.indexOf(layers.slice(0,-1).reduce((a,b)=>b.from<a.from?b:a)),1);
    weigh(0);
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
  // Each layer is drawn at the live ratio over its own size, so the arts
  // crossing over are drawn near one size while the controls move.
  const drawn=layer=>{
    const size=dimensions(profiles,layer);
    return {artId:layer.artId,sleeping:layer.sleeping,weight:layer.weight,eye:softRatio(controls.eyeOpen/size.eyeOpen),
      mouthWidth:softRatio(controls.mouthWidth/size.mouthWidth),mouthHeight:softRatio(controls.curve/size.curve)};
  };
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
      if(layers.length>1){
        transition.elapsedMs=Math.min(transition.durationMs,transition.elapsedMs+dt*1000);
        if(transition.elapsedMs>=transition.durationMs)layers=[layers.at(-1)];
        weigh(transition.elapsedMs/transition.durationMs);
      }
    },
    inspect(blink=0) {
      const top=layers.at(-1);
      return {...controls,artId:top.artId,sleeping:top.sleeping,blink,
        layers:layers.map(drawn),velocity:{...velocity},
        transition:{from:{...transition.from},to:{...transition.to},elapsedMs:transition.elapsedMs,durationMs:transition.durationMs,active:layers.length>1}};
    }
  };
}
