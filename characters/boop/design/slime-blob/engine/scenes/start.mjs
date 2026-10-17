import {sceneConstants} from './constants.mjs';
import {sceneMood} from './mood.mjs';
import {profileTraits} from './profile.mjs';

export function startRecipe(ctx,variant,mood='calm',profile=null) {
  const traits=profile?profileTraits(profile):sceneMood(mood),at=[520,820,1080][variant]+traits.delayMs;
  return {duration:sceneConstants.cycleMs[variant],intent:['perk and present start','nod into the new work','stretch and resume'][variant],
    lean:traits.lean,contacts:[{at,kind:'start_reveal',side:0,strength:traits.gain}],
    label:ctx==='new_task'?'NEW TASK':ctx==='continuation'?'RESUME':ctx==='compacted'?'COMPACTED':'START'};
}

// wake_up: the person back at the Mac after a long break. The start family's
// body without its card: a stretch up and forward (a presentation beat), then
// a soft settle, and the mood's own recovery.
export function wakeRecipe(variant,mood='calm',profile=null) {
  const traits=profile?profileTraits(profile):sceneMood(mood),stretch={kind:'start_reveal',side:0,strength:traits.gain};
  const settle=side=>({kind:'body_contact',side,strength:.35});
  const beats=[[[560,stretch],[1180,settle(0)]],[[760,stretch],[1240,settle(1)],[1420,settle(-1)]],
    [[900,stretch],[1500,{...stretch,strength:traits.gain*.7}]]][variant];
  return {duration:sceneConstants.cycleMs[variant],intent:['yawn and stretch up','stretch, then shake awake','slow double stretch'][variant],
    lean:traits.lean,contacts:beats.map(([at,beat])=>({at:at+traits.delayMs,...beat}))};
}
