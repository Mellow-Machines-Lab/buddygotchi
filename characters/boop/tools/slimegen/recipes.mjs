// Bakes the authored scene recipes (scenes.mjs) into slime.h's tables; the
// board still owns the seeded variations and jitter.
import {states,recipe,takesOf,gestureRecipe,lookOccasions,snore} from './scenes.mjs';
export {states};
// The contact kinds, as the port's ContactKind numbers them: the scenes',
// then comedy's (a gag's sneeze and zoomies, a snore's breath).
export const kinds=['key_contact','screen_knock','body_contact','alert_reveal','success_reveal','failure_reveal','result_reveal','start_reveal','helper_reveal','reply_ready_reveal','error_reveal','stopped_reveal',
 'sneeze_contact','breath_contact','zoom_contact'];
export function recipes(profiles,q,t,{design,gagIds,tagBits}){
 const specs=[...states.map(state=>({state})),{state:'task_complete',outcome:'success'},{state:'task_complete',outcome:'failure'},...['new_task','session','continuation','compacted'].map(ctx=>({state:'starting',ctx}))];
 const takes=specs.map(spec=>takesOf(spec.state,spec.outcome||null)),fourth=[];
 specs.forEach((spec,row)=>{if(takes[row]===4)fourth.push(row);});
 // A recipe; its gag, one acting plays with it (a gesture's, an
 // occasion's), as kGags numbers it, or -1.
 const write=(r,jitter)=>'{'+[t(r.duration),q(r.lean)].join(',')+','+[r.label?JSON.stringify(r.label):'nullptr',r.contacts.length,r.focusCycles||r.pulseCycles||1,r.helperCount||0,r.helperDirection||1,jitter,Boolean(r.gift),r.gag?gagIds.indexOf(r.gag):-1,'{'+r.contacts.map(c=>'{'+[t(c.at),kinds.indexOf(c.kind),c.side,q(c.strength)].join(',')+'}').join(',')+'}'].join(',')+'}';
 const emit=(p,spec,v)=>{const {r,jitter}=recipe(p,spec,v,design);return write(r,jitter);};
 // A recipe's label is what its card says; a gift is proud's bug beside its card.
 let out='struct Contact {T at;uint8_t kind;int8_t side;F strength;};\n'+
  'struct Recipe {T duration;F lean;const char* label;uint8_t count,focus,helpers;int8_t direction;bool jitter,gift;int8_t gag;Contact contacts[6];};\n';
 out+='constexpr int kContactKinds='+kinds.length+';\n';
 // Their names, which a rig clip's cues name the contact they sound by.
 out+='constexpr const char* kContactKindNames[kContactKinds]={'+kinds.map(k=>JSON.stringify(k)).join(',')+'};\n';
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
