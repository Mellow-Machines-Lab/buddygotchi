import {sceneConstants} from './constants.mjs';

// Both host asleep and explicit link timeout are the deliberate quiet alias:
// they retain mood, close the shared sleeping face, and let live springs settle.
// Asleep's fourth take is a snore: two soft breaths, each a slight swell
// and a breath's sound. Its other takes stay still and silent.
export const snore=Object.freeze({durationMs:4800,breathsMs:Object.freeze([600,2600]),strength:.35,swellMs:1200,swell:.07});
export function restRecipe(variant=0) {
  if(variant===3)return {duration:snore.durationMs,intent:'snore: two soft breaths',lean:0,
    contacts:snore.breathsMs.map(at=>({at,kind:'breath_contact',side:0,strength:snore.strength}))};
  return {duration:sceneConstants.cycleMs[0],contacts:[],intent:'quiet rest',lean:0};
}
