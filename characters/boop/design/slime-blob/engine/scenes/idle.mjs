import {sceneConstants} from './constants.mjs';

// Idle variations are the expression catalogue's three authored performances.
// Acting owns their quiet intervals and persistent springs, as in the audition.
export function idleRecipe() {
  return {duration:sceneConstants.cycleMs[0],contacts:[],intent:'existing mood audition',lean:0};
}
