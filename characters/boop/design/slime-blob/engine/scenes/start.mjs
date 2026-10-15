import {sceneConstants} from './constants.mjs';
import {sceneMood} from './mood.mjs';
import {profileTraits} from './profile.mjs';

export function startRecipe(ctx,variant,mood='calm',profile=null) {
  const traits=profile?profileTraits(profile):sceneMood(mood),at=[520,820,1080][variant]+traits.delayMs;
  return {duration:sceneConstants.cycleMs[variant],intent:['perk and present start','nod into the new work','stretch and resume'][variant],
    lean:traits.lean,contacts:[{at,kind:'start_reveal',side:0,strength:traits.gain}],
    label:ctx==='new_task'?'NEW TASK':ctx==='continuation'?'RESUME':ctx==='compacted'?'COMPACTED':'START'};
}
