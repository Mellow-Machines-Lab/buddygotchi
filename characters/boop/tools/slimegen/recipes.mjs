// Bake authored scene recipes; runtime still owns seeded variations and jitter.
import {deskRecipe} from '../../design/slime-blob/engine/scenes/desk.mjs';
import {alertRecipe} from '../../design/slime-blob/engine/scenes/alert.mjs';
import {resultRecipe,statusResultRecipe} from '../../design/slime-blob/engine/scenes/result.mjs';
import {startRecipe,wakeRecipe} from '../../design/slime-blob/engine/scenes/start.mjs';
import {helpersRecipe} from '../../design/slime-blob/engine/scenes/helpers.mjs';
import {touchRecipe} from '../../design/slime-blob/engine/scenes/touch.mjs';
import {listenRecipe} from '../../design/slime-blob/engine/scenes/listen.mjs';
import {restRecipe} from '../../design/slime-blob/engine/scenes/rest.mjs';
import {idleRecipe} from '../../design/slime-blob/engine/scenes/idle.mjs';
export const states=['idle','working','needs_you','task_complete','asleep','no_app','listening','starting','planning','terminal','tool_use','searching','analyzing','testing','delegating','helper_return','waiting','reply_ready','error','stopped','poked','tap_spam','wake_up'];
const kinds=['key_contact','screen_knock','body_contact','alert_reveal','success_reveal','failure_reveal','result_reveal','start_reveal','helper_reveal','reply_ready_reveal','error_reveal','stopped_reveal'];
export function recipes(profiles,q,t){
 const specs=[...states.map(state=>({state})),{state:'task_complete',outcome:'success'},{state:'task_complete',outcome:'failure'},...['new_task','session','continuation','compacted'].map(ctx=>({state:'starting',ctx}))];
 // A recipe's intent describes it for the trace check alone (check-port.py
 // builds with BOOP_GEL_TRACE); the firmware leaves its 24 KB out. Its
 // label stays: the cards draw it.
 let out='struct Contact {T at;uint8_t kind;int8_t side;F strength;};\n'+
  '#ifdef BOOP_GEL_TRACE\n#define SLIME_INTENT(text) text,\n#else\n#define SLIME_INTENT(text)\n#endif\n'+
  'struct Recipe {T duration;F lean;\n#ifdef BOOP_GEL_TRACE\nconst char* intent;\n#endif\nconst char* label;uint8_t count,focus,helpers;int8_t direction;bool jitter;Contact contacts[6];};\n';
 out+='constexpr const char* kContactNames[]={'+kinds.map(JSON.stringify).join(',')+'};\nconstexpr int kRecipeStates='+specs.length+';\nconstexpr Recipe kRecipes[kProfiles][kRecipeStates][3]={\n';
 for(const p of Object.values(profiles)){
  out+='{\n';
  for(const {state,outcome,ctx} of specs){out+='{';for(let v=0;v<3;v++){
   let r,jitter=false;
   if(['working','planning','terminal','tool_use','searching','analyzing','testing','waiting'].includes(state)){r=deskRecipe(state,p.mood,v,()=>.5,p);jitter=true;}
   else if(state==='needs_you')r=alertRecipe(v,p.mood,p);
   else if(state==='task_complete')r=resultRecipe(outcome||null,v,p.mood,p);
   else if(['reply_ready','error','stopped'].includes(state))r=statusResultRecipe(state,v,p.mood,p);
   else if(state==='starting')r=startRecipe(ctx||null,v,p.mood,p);
   else if(state==='wake_up')r=wakeRecipe(v,p.mood,p);
   else if(['delegating','helper_return'].includes(state))r=helpersRecipe(state,v,p.mood,p);
   else if(['poked','tap_spam'].includes(state))r=touchRecipe(state,v);
   else if(state==='listening')r=listenRecipe(v);
   else if(['asleep','no_app'].includes(state))r=restRecipe();else r=idleRecipe();
   out+='{'+[t(r.duration),q(r.lean)].join(',')+',SLIME_INTENT('+JSON.stringify(r.intent)+')'+[r.label?JSON.stringify(r.label):'nullptr',r.contacts.length,r.focusCycles||r.pulseCycles||1,r.helperCount||0,r.helperDirection||1,jitter,'{'+r.contacts.map(c=>'{'+[t(c.at),kinds.indexOf(c.kind),c.side,q(c.strength)].join(',')+'}').join(',')+'}'].join(',')+'},';
  }out+='},\n';}out+='},\n';
 }return out+'};\n';
}
