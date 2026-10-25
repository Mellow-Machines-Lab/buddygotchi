// The slime's scenes as authored: for each state, mood and take, the recipe
// slimegen bakes into slime.h (its length, lean and contacts, timed in ms),
// and the gestures', notices' and occasions' gags. The board plays them: it
// jitters a desk's contacts, deals the takes and owns every spring.
export const states=['idle','working','needs_you','task_complete','asleep','no_app','listening','starting','planning','terminal','tool_use','searching','analyzing','testing','delegating','helper_return','waiting','reply_ready','error','stopped','poked','tap_spam','wake_up','gesture','notice'];
// A take's length: the first take's, the second's, the third's.
const cycleMs=[3200,3700,4200];

// Representative expressive intent, independent of factual outcome. The same
// request is signalled once; mood shapes the movement, never its meaning.
export const sceneMoodTraits=Object.freeze({
  happy:Object.freeze({delayMs:0,spacing:1,gain:1.05,lean:.014}),
  grumpy:Object.freeze({delayMs:-40,spacing:.86,gain:1.12,lean:.024}),
  sad:Object.freeze({delayMs:160,spacing:1.18,gain:.62,lean:-.016}),
  frightened:Object.freeze({delayMs:240,spacing:1.28,gain:.68,lean:-.018})
});
const clamp=(value,lo,hi)=>Math.min(hi,Math.max(lo,value));
const limits=Object.freeze({delayMs:160,spacingMin:.88,spacingMax:1.18,gainMin:.68,gainMax:1.12,lean:.022});
// An expression's intent, from its authored motion rather than an arbitrary
// mood index, so quiet and energetic ones keep their timing and amplitudes:
// how late, how spread, how strong and which way its scenes' contacts lean.
export function profileTraits(profile) {
  if(sceneMoodTraits[profile.mood])return sceneMoodTraits[profile.mood];
  const performances=profile.performances,cues=performances.flatMap(recipe=>recipe.cues);
  const duration=performances.reduce((sum,recipe)=>sum+recipe.duration,0)/performances.length;
  const energy=cues.reduce((sum,cue)=>sum+Math.abs(cue[2]),0)/Math.max(1,cues.length);
  const lean=cues.filter(cue=>cue[1]==='lean'||cue[1]==='forward').reduce((sum,cue)=>sum+cue[2],0)/Math.max(1,cues.length);
  return {delayMs:clamp((duration-3)*120,-limits.delayMs,limits.delayMs),
    spacing:clamp(duration/3.2,limits.spacingMin,limits.spacingMax),
    gain:clamp(.6+energy*.32,limits.gainMin,limits.gainMax),
    lean:clamp(lean*.045,-limits.lean,limits.lean)};
}

// The desk: rhythm, rather than tint, distinguishes each take.
const rhythms={
  working:[[580,780,1040],[560,760,1680,1880],[1100,2220]],
  terminal:[[600,780,960],[780,1810,2090],[580,740,900,1060,1960,2120]],
  planning:[[940],[620,860],[760,1560]],
  tool_use:[[520],[780,1060],[620,1460]],
  searching:[[620],[540,760],[660,1640]],
  analyzing:[[1020],[720,1680],[1520]],
  testing:[[560],[480,720],[740,1840]],
  waiting:[[],[],[]]
};
function deskRecipe(state,variant,profile) {
  const mood=profile.mood;
  let times=[...rhythms[state][variant]],intent=state==='terminal'?'type and inspect':'type and think';
  let gain=1,lean=.018;
  if(mood==='frightened'){
    times=[[800,1700,2040],[740,1800,2240,2480],[1080,2380]][variant];
    intent='hesitate, try, pause, retry';gain=.68;lean=-.018;
  }else if(mood==='grumpy'&&state==='terminal'){
    times=[[640,800,960],[800,960,1120,2100],[660,820,980,1140,2120]][variant];
    intent='firm compact cluster, then inspect';gain=1.12;lean=.032;
  }else if(mood==='sad'){
    times=times.filter((_,index)=>index%2===0);intent='small effort and longer pause';gain=.62;lean=-.016;
  }else if(mood==='happy'){intent='buoyant working rhythm';gain=1.05;}
  else if(mood==='crying'&&state==='working'){
    times=[[760,1780],[640,2120],[1020,2300]][variant];
    intent='pause, gather, continue through tears';gain=.55;lean=-.024;
  }else if(mood!=='grumpy'||state!=='working'){
    const traits=profileTraits(profile),first=times[0]||0;
    times=times.map(at=>first+traits.delayMs+(at-first)*traits.spacing);
    gain=traits.gain;lean+=traits.lean;
    intent=profile.performances[variant].type+' layered over '+state;
  }
  if(state==='waiting'){
    times=[];lean=[.006,.014,-.010][variant];
    intent=['still attentive watch','small side look while waiting','settle at the same desk'][variant];
  }
  const contacts=times.map((at,index)=>({at,kind:'key_contact',side:index%2?-1:1,strength:gain}));
  return {duration:cycleMs[variant],contacts,intent,lean,focusCycles:[1,2,3][variant]};
}

// Needs you: its knocks, then the alert, once.
function alertRecipe(variant,profile) {
  const source=[[420],[420,740],[420,690,960]][variant],traits=profileTraits(profile);
  const times=source.map(at=>source[0]+traits.delayMs+(at-source[0])*traits.spacing);
  return {duration:cycleMs[variant],intent:'signal once, then hold silently',lean:traits.lean,
    contacts:[...times.map((at,index)=>({at,kind:'screen_knock',side:index%2?-1:1,strength:traits.gain})),
      {at:times[times.length-1]+240,kind:'alert_reveal',side:0,strength:1}]};
}

// A successful finish's fourth take: the card as the first take shows it,
// then three small hiccups, each a little body contact.
const hiccups=Object.freeze({revealMs:680,atMs:Object.freeze([1640,2060,2480]),strength:.45});
function resultRecipe(outcome,variant,profile) {
  const traits=profileTraits(profile);
  if(variant===3&&outcome==='success')return {duration:cycleMs[1],intent:'present completed work, then hiccup',lean:traits.lean,
    contacts:[{at:hiccups.revealMs+traits.delayMs,kind:'success_reveal',side:0,strength:traits.gain},
      ...hiccups.atMs.map(at=>({at:at+traits.delayMs,kind:'body_contact',side:0,strength:hiccups.strength}))]};
  const at=[680,960,1240][variant]+traits.delayMs;
  const kind=outcome==='success'?'success_reveal':outcome==='failure'?'failure_reveal':'result_reveal';
  // Proud's lifted success shows off a gift beside its card: a small bug.
  const gift=outcome==='success'&&variant===1&&profile.mood==='proud';
  return {duration:cycleMs[variant],intent:outcome==='success'?'present completed work':outcome==='failure'?'recover and show failed result':'show neutral finish',
    lean:traits.lean,contacts:[{at,kind,side:0,strength:traits.gain}],...(gift?{gift:true}:{})};
}
function statusResultRecipe(state,variant,profile) {
  const result=resultRecipe(null,variant,profile);
  const labels={reply_ready:'READY',error:'TOOL ERROR',stopped:'STOPPED'};
  return {...result,label:labels[state],intent:state==='reply_ready'?'present a neutral ready card':state==='error'?'recover and show a tool warning':'gently brake and settle',
    contacts:result.contacts.map(contact=>({...contact,kind:state+'_reveal'}))};
}

function startRecipe(ctx,variant,profile) {
  const traits=profileTraits(profile),at=[520,820,1080][variant]+traits.delayMs;
  return {duration:cycleMs[variant],intent:['perk and present start','nod into the new work','stretch and resume'][variant],
    lean:traits.lean,contacts:[{at,kind:'start_reveal',side:0,strength:traits.gain}],
    label:ctx==='new_task'?'NEW TASK':ctx==='continuation'?'RESUME':ctx==='compacted'?'COMPACTED':'START'};
}
// wake_up: the person back at the Mac after a long break. The start family's
// body without its card: a stretch up and forward (a presentation beat), then
// a soft settle, and the mood's own recovery.
function wakeRecipe(variant,profile) {
  const traits=profileTraits(profile),stretch={kind:'start_reveal',side:0,strength:traits.gain};
  const settle=side=>({kind:'body_contact',side,strength:.35});
  const beats=[[[560,stretch],[1180,settle(0)]],[[760,stretch],[1240,settle(1)],[1420,settle(-1)]],
    [[900,stretch],[1500,{...stretch,strength:traits.gain*.7}]]][variant];
  return {duration:cycleMs[variant],intent:['yawn and stretch up','stretch, then shake awake','slow double stretch'][variant],
    lean:traits.lean,contacts:beats.map(([at,beat])=>({at:at+traits.delayMs,...beat}))};
}

function helpersRecipe(state,variant,profile) {
  const traits=profileTraits(profile),returning=state==='helper_return';
  const times=returning?[[680],[960],[1240]][variant]:[[660,1040],[540,880,1220],[820,1640]][variant];
  return {duration:cycleMs[variant],
    intent:returning?['welcome a neutral report','settle beside a returning helper','receive and inspect a report'][variant]:['send two small helpers','dispatch three helpers','nod and relay to helpers'][variant],
    lean:traits.lean,helperCount:returning?1:[2,3,2][variant],helperDirection:variant===2?-1:1,
    contacts:times.map((at,index)=>({at:at+traits.delayMs,kind:returning?'helper_reveal':'body_contact',
      side:index%2?-1:1,strength:traits.gain}))};
}

function touchRecipe(state,variant) {
  const spam=state==='tap_spam',times=(spam?[[160,400],[160,340,520],[220,620]]:[[160],[200,480],[160,520]])[variant];
  return {duration:cycleMs[variant],
    intent:(spam?['bounded wobble complaint','squash and recover','small dodge and settle']:['local dent and rebound','side wobble','small settling bounce'])[variant],
    lean:[.008,-.018,.012][variant],contacts:times.map((at,index)=>({at,kind:'body_contact',side:index%2?-1:1,strength:spam?.9:.6}))};
}

function listenRecipe(variant) {
  return {duration:cycleMs[variant],contacts:[],
    intent:['lean toward the speaker','tilt and listen','still attentive listening'][variant],
    lean:[.022,-.012,.008][variant],pulseCycles:[2,1,3][variant]};
}

// Asleep and a lost link rest: they keep the mood, close the shared sleeping
// face and let the springs settle. Asleep's fourth take is a snore: two soft
// breaths, each a slight swell and a breath's sound; the others are still.
export const snore=Object.freeze({durationMs:4800,breathsMs:Object.freeze([600,2600]),strength:.35,swellMs:1200,swell:.07});
function restRecipe(variant=0) {
  if(variant===3)return {duration:snore.durationMs,intent:'snore: two soft breaths',lean:0,
    contacts:snore.breathsMs.map(at=>({at,kind:'breath_contact',side:0,strength:snore.strength}))};
  return {duration:cycleMs[0],contacts:[],intent:'quiet rest',lean:0};
}
// Idle's takes are the expression's acting: its gestures and its comedy.
function idleRecipe() {
  return {duration:cycleMs[0],contacts:[],intent:'existing mood audition',lean:0};
}

// The board's own reaction to what you do to it: one take for each gesture,
// in the board's order (render::Gesture). Each is a short scene whose
// contacts dent the body and sound, and a gag acting plays with it
// (gesture:<id>), under a face the board borrows for it.
export const gestureNames=Object.freeze(['handoff','stroke','ruffle','nose','tickle','dizzy','pickup','putdown','startle','peekaboo']);
// The scene outlasts its gag a little, so the body settles before it ends.
const gestureTailMs=200;
export const gestureGagName=gesture=>'gesture:'+gesture.id;
export function gestureRecipe(gestures,variant) {
  const gesture=gestures[variant]||gestures[0];
  return {duration:Math.round(gesture.duration*1000)+gestureTailMs,intent:gesture.label,lean:0,
    contacts:gesture.contacts.map(([at,kind,strength,side])=>({at:Math.round(at*1000),kind,side,strength})),
    gag:gestureGagName(gesture)};
}
// The notice state's takes: it hears its name and looks up at you. Each
// is the pack's rig clip for it (rig/clips/notice.json), which moves the
// body and sounds its cues, under a face of its own the board borrows,
// dealt as any state's takes are. The scene times the clip and outlasts it
// a little, so the body settles before it ends.
export const noticeNames=Object.freeze(['notice-surprised','notice-happy','notice-pleased']);
export function noticeRecipe(clip) {
  return {duration:clip.ms+gestureTailMs,intent:'notice: the rig clip',lean:0,contacts:[]};
}
// A gesture's gag: its keys and impulses; its sounds are the scene's.
export function gestureGag(gesture) {
  return {label:gesture.label,duration:gesture.duration,keys:gesture.keys,cues:gesture.cues,contacts:[]};
}

// Occasions: a look's takes that need tags (`when`, every one on: the part of
// the day, a holiday, party, busy, frantic) or a wait (`after`, seconds the
// look has shown). While one fits, a pick goes to one this often; otherwise,
// and while none fits, the look deals as it always has.
export const occasionShare=.67;
const occasionGagName=occasion=>'occasion:'+(typeof occasion.gag==='string'?occasion.gag:occasion.id);
// Idle's: gags acting plays in place of its next gesture, in catalogue order.
export function idleOccasions(occasions) {
  return occasions.filter(o=>o.looks.includes('idle')).map(o=>({id:o.id,when:o.when,after:o.after,gag:occasionGagName(o)}));
}
// The other looks': a recipe each (and a gag, if it has one) for each look
// it names, flattened in catalogue order.
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

// A row's takes: three, and a fourth for asleep (its snore) and a successful
// finish (its hiccups); a gesture's ten, one for each.
export function takesOf(state,outcome=null) {
  return state==='gesture'?10:state==='asleep'||(state==='task_complete'&&outcome==='success')?4:3;
}
// The recipe for a profile's state (its outcome or context) and take, and
// whether the board jitters its contacts (a desk's).
export function recipe(p,{state,outcome,ctx},v,design){
 let r,jitter=false;
 if(state==='gesture')r=gestureRecipe(design.gestures,v);
 else if(state==='notice')r=noticeRecipe(design.noticeClip);
 else if(['working','planning','terminal','tool_use','searching','analyzing','testing','waiting'].includes(state)){r=deskRecipe(state,v,p);jitter=true;}
 else if(state==='needs_you')r=alertRecipe(v,p);
 else if(state==='task_complete')r=resultRecipe(outcome||null,v,p);
 else if(['reply_ready','error','stopped'].includes(state))r=statusResultRecipe(state,v,p);
 else if(state==='starting')r=startRecipe(ctx||null,v,p);
 else if(state==='wake_up')r=wakeRecipe(v,p);
 else if(['delegating','helper_return'].includes(state))r=helpersRecipe(state,v,p);
 else if(['poked','tap_spam'].includes(state))r=touchRecipe(state,v);
 else if(state==='listening')r=listenRecipe(v);
 else if(state==='asleep')r=restRecipe(v);else if(state==='no_app')r=restRecipe();else r=idleRecipe();
 return {r,jitter};
}
