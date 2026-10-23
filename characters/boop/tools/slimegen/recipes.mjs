// Bake authored scene recipes; runtime still owns seeded variations and jitter.
import {deskRecipe} from '../../design/slime-blob/engine/scenes/desk.mjs';
import {alertRecipe} from '../../design/slime-blob/engine/scenes/alert.mjs';
import {resultRecipe,statusResultRecipe} from '../../design/slime-blob/engine/scenes/result.mjs';
import {startRecipe,wakeRecipe} from '../../design/slime-blob/engine/scenes/start.mjs';
import {helpersRecipe} from '../../design/slime-blob/engine/scenes/helpers.mjs';
import {touchRecipe} from '../../design/slime-blob/engine/scenes/touch.mjs';
import {listenRecipe} from '../../design/slime-blob/engine/scenes/listen.mjs';
import {restRecipe,snore} from '../../design/slime-blob/engine/scenes/rest.mjs';
import {idleRecipe} from '../../design/slime-blob/engine/scenes/idle.mjs';
import {takesOf} from '../../design/slime-blob/engine/scenes/index.mjs';
import {gestureRecipe} from '../../design/slime-blob/engine/scenes/gesture.mjs';
import {lookOccasions} from '../../design/slime-blob/engine/scenes/occasion.mjs';
export const states=['idle','working','needs_you','task_complete','asleep','no_app','listening','starting','planning','terminal','tool_use','searching','analyzing','testing','delegating','helper_return','waiting','reply_ready','error','stopped','poked','tap_spam','wake_up','gesture','notice'];
// The contact kinds, as the port's ContactKind numbers them: the scenes',
// then comedy's (a gag's sneeze and zoomies, a snore's breath).
export const kinds=['key_contact','screen_knock','body_contact','alert_reveal','success_reveal','failure_reveal','result_reveal','start_reveal','helper_reveal','reply_ready_reveal','error_reveal','stopped_reveal',
 'sneeze_contact','breath_contact','zoom_contact'];
function recipe(p,{state,outcome,ctx},v,design){
 let r,jitter=false;
 if(state==='gesture')r=gestureRecipe(design.gestures,v);
 else if(state==='notice')r=gestureRecipe(design.notices,v);
 else if(['working','planning','terminal','tool_use','searching','analyzing','testing','waiting'].includes(state)){r=deskRecipe(state,p.mood,v,()=>.5,p);jitter=true;}
 else if(state==='needs_you')r=alertRecipe(v,p.mood,p);
 else if(state==='task_complete')r=resultRecipe(outcome||null,v,p.mood,p);
 else if(['reply_ready','error','stopped'].includes(state))r=statusResultRecipe(state,v,p.mood,p);
 else if(state==='starting')r=startRecipe(ctx||null,v,p.mood,p);
 else if(state==='wake_up')r=wakeRecipe(v,p.mood,p);
 else if(['delegating','helper_return'].includes(state))r=helpersRecipe(state,v,p.mood,p);
 else if(['poked','tap_spam'].includes(state))r=touchRecipe(state,v);
 else if(state==='listening')r=listenRecipe(v);
 else if(state==='asleep')r=restRecipe(v);else if(state==='no_app')r=restRecipe();else r=idleRecipe();
 return {r,jitter};
}
export function recipes(profiles,q,t,{design,gagIds,tagBits}){
 const specs=[...states.map(state=>({state})),{state:'task_complete',outcome:'success'},{state:'task_complete',outcome:'failure'},...['new_task','session','continuation','compacted'].map(ctx=>({state:'starting',ctx}))];
 const takes=specs.map(spec=>takesOf(spec.state,spec.outcome||null)),fourth=[];
 specs.forEach((spec,row)=>{if(takes[row]===4)fourth.push(row);});
 // A recipe; its gag, one acting plays with it (a gesture's, an
 // occasion's), as kGags numbers it, or -1.
 const write=(r,jitter)=>'{'+[t(r.duration),q(r.lean)].join(',')+',SLIME_INTENT('+JSON.stringify(r.intent)+')'+[r.label?JSON.stringify(r.label):'nullptr',r.contacts.length,r.focusCycles||r.pulseCycles||1,r.helperCount||0,r.helperDirection||1,jitter,Boolean(r.gift),r.gag?gagIds.indexOf(r.gag):-1,'{'+r.contacts.map(c=>'{'+[t(c.at),kinds.indexOf(c.kind),c.side,q(c.strength)].join(',')+'}').join(',')+'}'].join(',')+'}';
 const emit=(p,spec,v)=>{const {r,jitter}=recipe(p,spec,v,design);return write(r,jitter);};
 // A recipe's intent describes it for the trace check alone (check-port.py
 // builds with BOOP_GEL_TRACE); the firmware leaves its 24 KB out. Its
 // label stays: the cards draw it. A gift is proud's bug beside its card.
 let out='struct Contact {T at;uint8_t kind;int8_t side;F strength;};\n'+
  '#ifdef BOOP_GEL_TRACE\n#define SLIME_INTENT(text) text,\n#else\n#define SLIME_INTENT(text)\n#endif\n'+
  'struct Recipe {T duration;F lean;\n#ifdef BOOP_GEL_TRACE\nconst char* intent;\n#endif\nconst char* label;uint8_t count,focus,helpers;int8_t direction;bool jitter,gift;int8_t gag;Contact contacts[6];};\n';
 out+='constexpr const char* kContactNames[]={'+kinds.map(JSON.stringify).join(',')+'};\nconstexpr int kContactKinds='+kinds.length+';\n';
 out+='constexpr int kRecipeStates='+specs.length+';\nconstexpr Recipe kRecipes[kProfiles][kRecipeStates][3]={\n';
 for(const p of Object.values(profiles)){
  out+='{\n';
  for(const spec of specs){out+='{';for(let v=0;v<3;v++)out+=emit(p,spec,v)+',';out+='},\n';}out+='},\n';
 }
 // Each row's takes: three, and a fourth for asleep (its snore) and a
 // successful finish (its hiccups), kept apart so the other rows stay three.
 out+='};\nconstexpr int kMaxTakes=4;\nconstexpr uint8_t kRecipeTakes[kRecipeStates]={'+takes.join(',')+'};\n';
 out+='constexpr int kFourthRows='+fourth.length+';\nconstexpr int8_t kFourthRow[kRecipeStates]={'+specs.map((_,row)=>fourth.indexOf(row)).join(',')+'};\n';
 out+='constexpr Recipe kFourthTakes[kProfiles][kFourthRows]={\n';
 for(const p of Object.values(profiles))out+='{'+fourth.map(row=>emit(p,specs[row],3)).join(',')+'},\n';
 // A gesture's takes, one for each, the same in every mood (the row's
 // first three in kRecipes are the first three of these).
 out+='};\nconstexpr Recipe kGestureTakes[kGestureCount]={\n'+design.gestures.map((_,v)=>write(gestureRecipe(design.gestures,v),false)).join(',\n')+'\n};\n';
 // The other looks' occasions: the row each plays in, its tags (bits) and
 // wait (seconds), and its recipe, the same in every mood.
 const looks=lookOccasions(design.occasions);
 out+='struct LookOccasion {uint8_t row;uint32_t when;uint16_t after;Recipe recipe;};\nconstexpr LookOccasion kLookOccasions[]={\n'+
  looks.map(o=>'{'+[states.indexOf(o.state),tagBits(o.when),o.after,write(o.recipe,o.recipe.jitter)].join(',')+'}').join(',\n')+'\n};\n';
 out+='constexpr int kLookOccasionCount=sizeof(kLookOccasions)/sizeof(kLookOccasions[0]);\n';
 // A snore's breath swells the sleeping body: sin² over its window, times its strength.
 return out+'constexpr int kSnoreSwellMs='+snore.swellMs+';\nconstexpr F kSnoreSwell='+q(snore.swell)+';\n';
}
