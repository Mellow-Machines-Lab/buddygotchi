import {sceneConstants} from './constants.mjs';

// CONTINUITY.md, Occasions: a look's takes that need tags (`when`, every one
// on: the part of the day, a holiday, party, busy, frantic) or a wait
// (`after`, seconds the look has shown), as the host says them
// (setOccasion). While one fits, a pick goes to one this often; otherwise,
// and while none fits, the look deals as it always has.
export const occasionShare=.67;
export const occasionGagName=occasion=>'occasion:'+(typeof occasion.gag==='string'?occasion.gag:occasion.id);
export function fits(entry,occasion) {
  return entry.when.every(tag=>occasion.when.has(tag))&&entry.after*1000<=occasion.lookMs;
}
// Idle's: gags acting plays in place of its next gesture, in catalogue order.
export function idleOccasions(occasions) {
  return occasions.filter(o=>o.looks.includes('idle')).map(o=>({id:o.id,when:o.when,after:o.after,gag:occasionGagName(o)}));
}
// The other looks': a recipe each (and a gag, if it has one) for each look
// it names, flattened in catalogue order; the port's table is the same.
export function lookOccasions(occasions) {
  return occasions.filter(o=>o.recipe).flatMap(o=>o.looks.map(state=>({id:o.id,state,when:o.when,after:o.after,
    recipe:{duration:Math.round(o.recipe.duration*1000),intent:o.label,lean:o.recipe.lean,jitter:o.recipe.jitter,
      contacts:o.recipe.contacts.map(([at,kind,strength,side])=>({at:Math.round(at*1000),kind,side,strength})),
      gag:o.gag?occasionGagName(o):null}})));
}
// The gags occasions carry, each once: those named by another occasion are its.
export function occasionGags(occasions) {
  return occasions.filter(o=>o.gag&&typeof o.gag==='object').map(o=>[occasionGagName(o),{label:o.label,...o.gag}]);
}
// A look's recipe as it plays: a jittered one takes the desk's bounded
// jitter, contact by contact (its time, then its strength).
export function realizeOccasion(recipe,rand) {
  const contacts=recipe.contacts.map(contact=>recipe.jitter?{...contact,at:contact.at+(rand()*2-1)*sceneConstants.timingJitterMs,
    strength:contact.strength*(1+(rand()*2-1)*sceneConstants.gainJitter)}:{...contact});
  return {duration:recipe.duration,intent:recipe.intent,lean:recipe.lean,contacts,focusCycles:1,gag:recipe.gag};
}
