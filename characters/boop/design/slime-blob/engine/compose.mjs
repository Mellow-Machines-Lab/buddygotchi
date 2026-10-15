// CONTINUITY.md, Phase 1 channel bounds: the mood posture's weights are
// critically damped (frequency 10, or 25 with reduced motion), outside the
// locked blocks, so a mood change starts the body moving without a jolt.
export const postureFilter=Object.freeze({frequency:10,reducedFrequency:25});
export function createPostureWeights({emotions,initialEmotion,reduced}) {
  const springs=emotions.map(id=>({x:Number(id===initialEmotion),v:0}));
  return {
    get weights() {return springs.map(m=>m.x);},
    advance(dt,current) {
      const frequency=reduced.matches?postureFilter.reducedFrequency:postureFilter.frequency;
      for(const [i,m] of springs.entries()){
        const target=Number(emotions[i]===current);
        if(!m.x&&!m.v&&!target)continue;
        let left=dt;
        while(left>0){const h=Math.min(left,1/240);m.v+=(frequency*frequency*(target-m.x)-2*frequency*m.v)*h;m.x+=m.v*h;left-=h;}
      }
    }
  };
}

// The original mood posture is independent of the painted face. The locked
// weights still time the motion blocks; posture reads the filtered ones.
export function moodPosture({weights,emotions,profiles,time,reduced}) {
  let lean=0,squash=0,ripple=0;
  for(let i=0;i<weights.length;i++){
    const mood=profiles[emotions[i]].mood,w=weights[i];
    const low={lazy:-.04,bored:-.022,tired:-.032,exhausted:-.10,disappointed:-.035,sad:-.055,crying:-.045,wounded:-.055,frightened:-.045,shy:-.025,comfy:-.02}[mood]||0;
    const high={proud:.05,determined:.022,hopeful:.025,engaged:.012}[mood]||0;
    squash+=w*(low+high);
    if(!reduced.matches){
      if(mood==='excited')squash+=w*.012*Math.sin(time*4.3);
      if(mood==='scared'||mood==='frightened'){const amplitude=mood==='scared'?.014:.026;lean+=w*amplitude*Math.sin(time*13)*(.35+.65*Math.pow(Math.sin(time*.75),2));}
      if(mood==='crying')squash+=w*.01*Math.sin(time*3.1);
      if(mood==='irritated')lean+=w*.008*Math.sin(time*6.1)*Math.pow(Math.max(0,Math.sin(time*.7)),4);
    }
  }
  return [lean,squash,ripple];
}

export function composePose(base,posture,channels,activity={lean:{x:0},squash:{x:0}},bridge={lean:{x:0},squash:{x:0}}) {
  return [base[0]+channels.lean.x+posture[0]+activity.lean.x+bridge.lean.x,base[1]+channels.squash.x+posture[1]+activity.squash.x+bridge.squash.x,base[2]+channels.ripple.x+posture[2],base[3]];
}

export function lifePose(channels,activity={forward:{x:0}},bridge={forward:{x:0}}) {
  return [Math.max(0,channels.lift.x),channels.roll.x,channels.forward.x+activity.forward.x+bridge.forward.x];
}
