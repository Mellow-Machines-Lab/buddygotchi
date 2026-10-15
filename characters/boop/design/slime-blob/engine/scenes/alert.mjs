import {sceneConstants} from './constants.mjs';
import {sceneMood} from './mood.mjs';
import {profileTraits} from './profile.mjs';

export function alertRecipe(variant,mood='calm',profile=null) {
  const source=[[420],[420,740],[420,690,960]][variant],traits=profile?profileTraits(profile):sceneMood(mood);
  const times=source.map(at=>source[0]+traits.delayMs+(at-source[0])*traits.spacing);
  return {duration:sceneConstants.cycleMs[variant],intent:'signal once, then hold silently',lean:traits.lean,
    contacts:[...times.map((at,index)=>({at,kind:'screen_knock',side:index%2?-1:1,strength:traits.gain})),
      {at:times[times.length-1]+240,kind:'alert_reveal',side:0,strength:1}]};
}
