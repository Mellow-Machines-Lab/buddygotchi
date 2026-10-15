import {sceneConstants} from './constants.mjs';
import {sceneMood} from './mood.mjs';
import {profileTraits} from './profile.mjs';

export function resultRecipe(outcome,variant,mood='calm',profile=null) {
  const traits=profile?profileTraits(profile):sceneMood(mood),at=[680,960,1240][variant]+traits.delayMs;
  const kind=outcome==='success'?'success_reveal':outcome==='failure'?'failure_reveal':'result_reveal';
  return {duration:sceneConstants.cycleMs[variant],intent:outcome==='success'?'present completed work':outcome==='failure'?'recover and show failed result':'show neutral finish',
    lean:traits.lean,contacts:[{at,kind,side:0,strength:traits.gain}]};
}

export function statusResultRecipe(state,variant,mood='calm',profile=null) {
  const result=resultRecipe(null,variant,mood,profile);
  const labels={reply_ready:'READY',error:'TOOL ERROR',stopped:'STOPPED'};
  return {...result,label:labels[state],intent:state==='reply_ready'?'present a neutral ready card':state==='error'?'recover and show a tool warning':'gently brake and settle',
    contacts:result.contacts.map(contact=>({...contact,kind:state+'_reveal'}))};
}
