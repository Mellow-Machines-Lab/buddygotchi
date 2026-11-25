// Bakes the authored scene recipes (scenes.mjs) into slime.h's tables, one
// set of takes for each state; the board applies the mood's traits and
// owns the seeded variations and jitter.
import {states,rows,standsIn,recipe,takesOf,gestureRecipe,pastimeTakes,snore,knockClimbAtMs} from './scenes.mjs';
export {states};
// The contact kinds, as the port's ContactKind numbers them: the scenes',
// then comedy's (a gag's sneeze and zoomies, a snore's breath).
export const kinds=['key_contact','screen_knock','body_contact','alert_reveal','success_reveal','failure_reveal','result_reveal','start_reveal','reply_ready_reveal',
 'sneeze_contact','breath_contact','zoom_contact'];
export function recipes(q,t,{design,gagIds}){
 const specs=[...rows.map(state=>({state})),{state:'task_complete',outcome:'success'},{state:'task_complete',outcome:'failure'}];
 const takes=specs.map(spec=>takesOf(spec.state,spec.outcome||null)),fourth=[];
 specs.forEach((spec,row)=>{if(takes[row]===4)fourth.push(row);});
 // A recipe; its gag, one acting plays with it (a gesture's, a
 // pastime's), as kGags numbers it, or -1.
 const write=(r,jitter)=>'{'+[t(r.duration),q(r.lean)].join(',')+','+[r.contacts.length,r.focusCycles||r.pulseCycles||1,jitter,Boolean(r.gift),Boolean(r.moody),r.gag?gagIds.indexOf(r.gag):-1,'{'+r.contacts.map(c=>'{'+[t(c.at),kinds.indexOf(c.kind),c.side,q(c.strength)].join(',')+'}').join(',')+'}'].join(',')+'}';
 const emit=(spec,v)=>{const {r,jitter}=recipe(spec,v,design);return write(r,jitter);};
 // A gift is proud's bug beside its trophy. A moody recipe takes the
 // mood's timing traits as the board deals it.
 let out='struct Contact {T at;uint8_t kind;int8_t side;F strength;};\n'+
  'struct Recipe {T duration;F lean;uint8_t count,focus;bool jitter,gift,moody;int8_t gag;Contact contacts[6];};\n';
 out+='constexpr int kContactKinds='+kinds.length+';\n';
 // Their names, which a rig clip's cues name the contact they sound by.
 out+='constexpr const char* kContactKindNames[kContactKinds]={'+kinds.map(k=>JSON.stringify(k)).join(',')+'};\n';
 // Each state's row: its own, or the row of the state that stands in for
 // it; then a finish's success and failure, after the states' rows.
 out+='constexpr int kStates='+states.length+', kStateRows='+rows.length+', kRecipeStates='+specs.length+';\n';
 out+='constexpr uint8_t kRecipeRow[kStates]={'+states.map(state=>rows.indexOf(standsIn[state]||state)).join(',')+'};\n';
 out+='constexpr Recipe kRecipes[kRecipeStates][3]={\n';
 for(const spec of specs){out+='{';for(let v=0;v<3;v++)out+=emit(spec,v)+',';out+='},\n';}
 // Each row's takes: three, and a fourth for asleep (its snore) and a
 // successful finish (its hiccups), kept apart so the other rows stay three.
 out+='};\nconstexpr int kMaxTakes=4;\nconstexpr uint8_t kRecipeTakes[kRecipeStates]={'+takes.join(',')+'};\n';
 out+='constexpr int kFourthRows='+fourth.length+';\nconstexpr int8_t kFourthRow[kRecipeStates]={'+specs.map((_,row)=>fourth.indexOf(row)).join(',')+'};\n';
 out+='constexpr Recipe kFourthTakes[kFourthRows]={'+fourth.map(row=>emit(specs[row],3)).join(',')+'\n';
 // A gesture's takes, one for each, the same in every mood (the row's
 // first three in kRecipes are the first three of these).
 out+='};\nconstexpr Recipe kGestureTakes[kGestureCount]={\n'+design.gestures.map((_,v)=>write(gestureRecipe(design.gestures,v),false)).join(',\n')+'\n};\n';
 // The pastimes' takes: each its name and its recipe, the same in every mood.
 const pastimes=pastimeTakes(design.pastimes);
 out+='struct PastimeTake {const char* id;Recipe recipe;};\nconstexpr PastimeTake kPastimeTakes[]={\n'+
  pastimes.map(o=>'{'+[JSON.stringify(o.id),write(o.recipe,o.recipe.jitter)].join(',')+'}').join(',\n')+'\n};\n';
 out+='constexpr int kPastimeTakeCount=sizeof(kPastimeTakes)/sizeof(kPastimeTakes[0]);\n';
 // A snore's breath swells the sleeping body: sin² over its window, times its strength.
 // Where needs you's knock climbs, if nobody comes (scenes.mjs `knock`).
 out+='constexpr uint32_t kKnockClimbAtMs='+knockClimbAtMs(design.knockClip)+';\n';
 return out+'constexpr int kSnoreSwellMs='+snore.swellMs+';\nconstexpr F kSnoreSwell='+q(snore.swell)+';\n';
}
