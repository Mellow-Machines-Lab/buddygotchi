import {sceneConstants} from './constants.mjs';
import {sceneMood} from './mood.mjs';
import {profileTraits} from './profile.mjs';

export function helpersRecipe(state,variant,mood='calm',profile=null) {
  const traits=profile?profileTraits(profile):sceneMood(mood),returning=state==='helper_return';
  const times=returning?[[680],[960],[1240]][variant]:[[660,1040],[540,880,1220],[820,1640]][variant];
  return {duration:sceneConstants.cycleMs[variant],
    intent:returning?['welcome a neutral report','settle beside a returning helper','receive and inspect a report'][variant]:['send two small helpers','dispatch three helpers','nod and relay to helpers'][variant],
    lean:traits.lean,helperCount:returning?1:[2,3,2][variant],helperDirection:variant===2?-1:1,
    contacts:times.map((at,index)=>({at:at+traits.delayMs,kind:returning?'helper_reveal':'body_contact',
      side:index%2?-1:1,strength:traits.gain}))};
}
