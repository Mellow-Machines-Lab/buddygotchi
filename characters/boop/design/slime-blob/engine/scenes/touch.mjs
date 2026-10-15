import {sceneConstants} from './constants.mjs';

export function touchRecipe(state,variant) {
  const spam=state==='tap_spam',times=(spam?[[160,400],[160,340,520],[220,620]]:[[160],[200,480],[160,520]])[variant];
  return {duration:sceneConstants.cycleMs[variant],
    intent:(spam?['bounded wobble complaint','squash and recover','small dodge and settle']:['local dent and rebound','side wobble','small settling bounce'])[variant],
    lean:[.008,-.018,.012][variant],contacts:times.map((at,index)=>({at,kind:'body_contact',side:index%2?-1:1,strength:spam?.9:.6}))};
}
