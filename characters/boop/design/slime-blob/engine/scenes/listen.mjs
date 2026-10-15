import {sceneConstants} from './constants.mjs';

export function listenRecipe(variant) {
  return {duration:sceneConstants.cycleMs[variant],contacts:[],
    intent:['lean toward the speaker','tilt and listen','still attentive listening'][variant],
    lean:[.022,-.012,.008][variant],pulseCycles:[2,1,3][variant]};
}
