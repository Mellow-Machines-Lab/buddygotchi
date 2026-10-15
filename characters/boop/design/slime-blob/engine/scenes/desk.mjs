import {sceneConstants} from './constants.mjs';
import {profileTraits} from './profile.mjs';

// Rhythm, rather than tint, distinguishes each representative variation.
const rhythms={
  working:[[580,780,1040],[560,760,1680,1880],[1100,2220]],
  terminal:[[600,780,960],[780,1810,2090],[580,740,900,1060,1960,2120]],
  planning:[[940],[620,860],[760,1560]],
  tool_use:[[520],[780,1060],[620,1460]],
  searching:[[620],[540,760],[660,1640]],
  analyzing:[[1020],[720,1680],[1520]],
  testing:[[560],[480,720],[740,1840]],
  waiting:[[],[],[]]
};
export function deskRecipe(state,mood,variant,rand,profile=null) {
  let times=[...rhythms[state][variant]],intent=state==='terminal'?'type and inspect':'type and think';
  let gain=1,lean=.018;
  if(mood==='frightened'){
    times=[[800,1700,2040],[740,1800,2240,2480],[1080,2380]][variant];
    intent='hesitate, try, pause, retry';gain=.68;lean=-.018;
  }else if(mood==='grumpy'&&state==='terminal'){
    times=[[640,800,960],[800,960,1120,2100],[660,820,980,1140,2120]][variant];
    intent='firm compact cluster, then inspect';gain=1.12;lean=.032;
  }else if(mood==='sad'){
    times=times.filter((_,index)=>index%2===0);intent='small effort and longer pause';gain=.62;lean=-.016;
  }else if(mood==='happy'){intent='buoyant working rhythm';gain=1.05;}
  else if(mood==='crying'&&state==='working'){
    times=[[760,1780],[640,2120],[1020,2300]][variant];
    intent='pause, gather, continue through tears';gain=.55;lean=-.024;
  }else if(profile&&!(mood==='grumpy'&&state==='working')){
    const traits=profileTraits(profile),first=times[0]||0;
    times=times.map(at=>first+traits.delayMs+(at-first)*traits.spacing);
    gain=traits.gain;lean+=traits.lean;
    intent=profile.performances[variant].type+' layered over '+state;
  }
  if(state==='waiting'){
    times=[];lean=[.006,.014,-.010][variant];
    intent=['still attentive watch','small side look while waiting','settle at the same desk'][variant];
  }
  const contacts=times.map((at,index)=>({at:at+(rand()*2-1)*sceneConstants.timingJitterMs,
    kind:'key_contact',side:index%2?-1:1,strength:gain*(1+(rand()*2-1)*sceneConstants.gainJitter)}));
  return {duration:sceneConstants.cycleMs[variant],contacts,intent,lean,focusCycles:[1,2,3][variant]};
}
