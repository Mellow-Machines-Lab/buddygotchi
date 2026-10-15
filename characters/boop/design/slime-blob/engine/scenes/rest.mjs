import {sceneConstants} from './constants.mjs';

// Both host asleep and explicit link timeout are the deliberate quiet alias:
// they retain mood, close the shared sleeping face, and let live springs settle.
export function restRecipe() {
  return {duration:sceneConstants.cycleMs[0],contacts:[],intent:'quiet rest',lean:0};
}
