import {sceneMoodTraits} from './mood.mjs';

const clamp=(value,lo,hi)=>Math.min(hi,Math.max(lo,value));
export const profileLimits=Object.freeze({
  delayMs:160,spacingMin:.88,spacingMax:1.18,gainMin:.68,gainMax:1.12,lean:.022,
  cueWindowSeconds:.48,recoveryGain:Object.freeze({lean:.025,squash:.018,forward:.015})
});

// Derive expression intent from its authored motion, not an arbitrary mood
// index. Quiet/energetic catalogues keep their different timing and amplitudes.
export function profileTraits(profile) {
  if(!profile)return {delayMs:0,spacing:1,gain:1,lean:0};
  if(sceneMoodTraits[profile.mood])return sceneMoodTraits[profile.mood];
  const performances=profile.performances,cues=performances.flatMap(recipe=>recipe.cues);
  const duration=performances.reduce((sum,recipe)=>sum+recipe.duration,0)/performances.length;
  const energy=cues.reduce((sum,cue)=>sum+Math.abs(cue[2]),0)/Math.max(1,cues.length);
  const lean=cues.filter(cue=>cue[1]==='lean'||cue[1]==='forward').reduce((sum,cue)=>sum+cue[2],0)/Math.max(1,cues.length);
  return {delayMs:clamp((duration-3)*120,-profileLimits.delayMs,profileLimits.delayMs),
    spacing:clamp(duration/3.2,profileLimits.spacingMin,profileLimits.spacingMax),
    gain:clamp(.6+energy*.32,profileLimits.gainMin,profileLimits.gainMax),
    lean:clamp(lean*.045,-profileLimits.lean,profileLimits.lean)};
}

export function recoveryGesture(profile,variant,progress) {
  const result={lean:0,squash:0,forward:0};
  // A fourth take (a snore, the hiccups) has no gesture of its own to recover with.
  if(!profile||sceneMoodTraits[profile.mood]||progress<0||progress>1||!profile.performances[variant])return result;
  const performance=profile.performances[variant],time=progress*performance.duration;
  for(const [at,channel,velocity] of performance.cues){
    const target=channel==='roll'?'lean':channel==='lift'?'squash':channel==='ripple'?'forward':channel;
    if(!Object.hasOwn(result,target))continue;
    const age=time-at;
    if(age<0||age>profileLimits.cueWindowSeconds)continue;
    const pulse=Math.sin(Math.PI*age/profileLimits.cueWindowSeconds)**2;
    result[target]+=velocity*profileLimits.recoveryGain[target]*pulse;
  }
  return result;
}
