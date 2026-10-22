import {sceneConstants} from './constants.mjs';
import {sceneMood} from './mood.mjs';
import {profileTraits} from './profile.mjs';

// A successful finish's fourth take: the card as the first take shows it,
// then three small hiccups, each a little body contact.
export const hiccups=Object.freeze({revealMs:680,atMs:Object.freeze([1640,2060,2480]),strength:.45});

export function resultRecipe(outcome,variant,mood='calm',profile=null) {
  const traits=profile?profileTraits(profile):sceneMood(mood);
  if(variant===3&&outcome==='success')return {duration:sceneConstants.cycleMs[1],intent:'present completed work, then hiccup',lean:traits.lean,
    contacts:[{at:hiccups.revealMs+traits.delayMs,kind:'success_reveal',side:0,strength:traits.gain},
      ...hiccups.atMs.map(at=>({at:at+traits.delayMs,kind:'body_contact',side:0,strength:hiccups.strength}))]};
  const at=[680,960,1240][variant]+traits.delayMs;
  const kind=outcome==='success'?'success_reveal':outcome==='failure'?'failure_reveal':'result_reveal';
  // Proud's lifted success shows off a gift beside its card: a small bug.
  const gift=outcome==='success'&&variant===1&&(profile?.mood??mood)==='proud';
  return {duration:sceneConstants.cycleMs[variant],intent:outcome==='success'?'present completed work':outcome==='failure'?'recover and show failed result':'show neutral finish',
    lean:traits.lean,contacts:[{at,kind,side:0,strength:traits.gain}],...(gift?{gift:true}:{})};
}

export function statusResultRecipe(state,variant,mood='calm',profile=null) {
  const result=resultRecipe(null,variant,mood,profile);
  const labels={reply_ready:'READY',error:'TOOL ERROR',stopped:'STOPPED'};
  return {...result,label:labels[state],intent:state==='reply_ready'?'present a neutral ready card':state==='error'?'recover and show a tool warning':'gently brake and settle',
    contacts:result.contacts.map(contact=>({...contact,kind:state+'_reveal'}))};
}
