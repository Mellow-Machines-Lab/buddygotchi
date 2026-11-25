// The slime's scenes as authored: for each state and take, the recipe
// slimegen bakes into slime.h (its length, lean and contacts, timed in ms),
// and the gestures', notices' and pastimes' gags. One set of takes for each
// state: the mood changes only the face and, on a recipe that's `moody`,
// the timing traits (profileTraits), which the board applies as it deals a
// take (render/gel/scenes.h, inMood). The board plays them: it jitters a
// desk's contacts, deals the takes and owns every spring.
// The board's states, as the engine names them (render/types.cpp).
export const states=['idle','working','needs_you','task_complete','asleep','no_app','listening','planning','terminal','tool_use','searching','analyzing','testing','delegating','waiting','reply_ready','poked','tap_spam','wake_up','gesture','notice'];
// The activities with no row of their own, each with the row of the desk
// the board shows for it (render/gel/router.cpp's deskStateOf): the four
// the Mac no longer sends (its Act has four: tool_use, analyzing, terminal
// and waiting), and tool_use, which it sends for typing and the desk shows
// as working.
export const standsIn=Object.freeze({planning:'working',tool_use:'working',searching:'analyzing',testing:'terminal',delegating:'terminal'});
// The recipe table's state rows: the states with takes of their own.
export const rows=states.filter(state=>!standsIn[state]);
// A take's length: the first take's, the second's, the third's.
const cycleMs=[3200,3700,4200];

// Representative expressive intent, independent of factual outcome. The same
// request is signalled once; mood shapes the movement, never its meaning.
export const sceneMoodTraits=Object.freeze({
  happy:Object.freeze({delayMs:0,spacing:1,gain:1.05,lean:.014}),
  grumpy:Object.freeze({delayMs:-40,spacing:.86,gain:1.12,lean:.024}),
  sad:Object.freeze({delayMs:160,spacing:1.18,gain:.62,lean:-.016})
});
// An expression's intent: how late, how spread, how strong and which way
// its scenes' contacts lean. The reviewed moods' are the table above; every
// other expression's are its own `traits` (expressions.json), numbers once
// derived from the mood gestures it had before the motion layer. On a moody
// recipe the board moves each contact to first + delayMs + (at - first) *
// spacing, its first contact's time, multiplies its strength by gain, and
// adds lean to the recipe's.
export function profileTraits(profile) {
  return sceneMoodTraits[profile.mood]||profile.traits;
}

// The desk: rhythm, rather than tint, distinguishes each take. The mood's
// traits give each mood its own timing over it.
const rhythms={
  working:[[580,780,1040],[560,760,1680,1880],[1100,2220]],
  terminal:[[600,780,960],[780,1810,2090],[580,740,900,1060,1960,2120]],
  analyzing:[[1020],[720,1680],[1520]]
};
// Waiting has no keys, and leans the same in every mood.
function deskRecipe(state,variant) {
  const focusCycles=[1,2,3][variant];
  if(state==='waiting')return {duration:cycleMs[variant],contacts:[],focusCycles,lean:[.006,.014,-.010][variant],
    intent:['still attentive watch','small side look while waiting','settle at the same desk'][variant]};
  const contacts=rhythms[state][variant].map((at,index)=>({at,kind:'key_contact',side:index%2?-1:1,strength:1}));
  return {duration:cycleMs[variant],contacts,intent:state==='terminal'?'type and inspect':'type and think',lean:.018,focusCycles,moody:true};
}

// Needs you: one move for every mood and take, the pack's rig clip `knock`
// (rig/clips/knock.json), which the face plays by this scene's time: a fist
// knocks on the glass, the clip's cues, which sound here, then the alert's
// ding, once. If nobody comes, the knock climbs (`knock-climb.json`, the
// face's to play and sound, from kKnockClimbAtMs): `climb` says whether it
// follows the knock at once ('replaces': the climb is the whole knock, a
// step after the first) or after `followsMs` with nobody come ('follows').
// The scene lasts until the climb is over, so a needs-you interrupted
// after its ding comes back to its silent hold, never to a second climb.
export const knock=Object.freeze({climb:'follows',followsMs:20000});
export const knockClimbAtMs=knockClip=>knock.climb==='replaces'?knockClip.ms:knock.followsMs;
function alertRecipe(design) {
  const hits=design.knockClip.cues.filter(([,name])=>name==='screen_knock').map(([at])=>at);
  return {duration:knockClimbAtMs(design.knockClip)+design.climbClip.ms,intent:'knock on the glass, then hold silently',lean:0,
    contacts:[...hits.map((at,index)=>({at,kind:'screen_knock',side:index%2?-1:1,strength:1})),
      {at:hits[hits.length-1]+240,kind:'alert_reveal',side:0,strength:1}]};
}

// A successful finish's fourth take: the card as the first take shows it,
// then three small hiccups, each a little body contact.
const hiccups=Object.freeze({revealMs:680,atMs:Object.freeze([1640,2060,2480]),strength:.45});
function resultRecipe(outcome,variant) {
  if(variant===3&&outcome==='success')return {duration:cycleMs[1],intent:'present completed work, then hiccup',lean:0,moody:true,
    contacts:[{at:hiccups.revealMs,kind:'success_reveal',side:0,strength:1},
      ...hiccups.atMs.map(at=>({at,kind:'body_contact',side:0,strength:hiccups.strength}))]};
  const at=[680,960,1240][variant];
  const kind=outcome==='success'?'success_reveal':outcome==='failure'?'failure_reveal':'result_reveal';
  // The lifted success may show off a gift beside its card, a small bug:
  // only proud does (the board's inMood).
  const gift=outcome==='success'&&variant===1;
  return {duration:cycleMs[variant],intent:outcome==='success'?'present completed work':outcome==='failure'?'recover and show failed result':'show neutral finish',
    lean:0,moody:true,contacts:[{at,kind,side:0,strength:1}],...(gift?{gift:true}:{})};
}
function statusResultRecipe(state,variant) {
  const result=resultRecipe(null,variant);
  return {...result,intent:'show a neutral reply',
    contacts:result.contacts.map(contact=>({...contact,kind:state+'_reveal'}))};
}

// wake_up: the person back at the Mac after a long break. The start family's
// body, with no card: a stretch up and forward (a presentation beat), then
// a soft settle, and the mood's own recovery.
function wakeRecipe(variant) {
  const stretch={kind:'start_reveal',side:0,strength:1};
  const settle=side=>({kind:'body_contact',side,strength:.35});
  const beats=[[[560,stretch],[1180,settle(0)]],[[760,stretch],[1240,settle(1)],[1420,settle(-1)]],
    [[900,stretch],[1500,{...stretch,strength:.7}]]][variant];
  return {duration:cycleMs[variant],intent:['yawn and stretch up','stretch, then shake awake','slow double stretch'][variant],
    lean:0,moody:true,contacts:beats.map(([at,beat])=>({at,...beat}))};
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

// The pastimes' bodies (`pastimes`): a gag the engine's acting plays in
// place of its next gesture, or a take its scene plays as the look's next
// (with a gag, if it has one). The face's table (render/gel/pastimes.cpp)
// names each and says when it's dealt.
const pastimeGagName=pastime=>'pastime:'+pastime.id;
export function pastimeTakes(pastimes) {
  return pastimes.filter(o=>o.recipe).map(o=>({id:o.id,
    recipe:{duration:Math.round(o.recipe.duration*1000),intent:o.label,lean:o.recipe.lean,jitter:o.recipe.jitter,
      contacts:o.recipe.contacts.map(([at,kind,strength,side])=>({at:Math.round(at*1000),kind,side,strength})),
      gag:o.gag?pastimeGagName(o):null}}));
}
export function pastimeGags(pastimes) {
  return pastimes.filter(o=>o.gag).map(o=>[pastimeGagName(o),{label:o.label,...o.gag}]);
}

// A row's takes: three, and a fourth for asleep (its snore) and a successful
// finish (its hiccups); a gesture's ten, one for each.
export function takesOf(state,outcome=null) {
  return state==='gesture'?10:state==='asleep'||(state==='task_complete'&&outcome==='success')?4:3;
}
// The recipe for a state (and its outcome) and take, the same in
// every mood, and whether the board jitters its contacts (a desk's).
export function recipe({state,outcome},v,design){
 let r,jitter=false;
 if(standsIn[state])throw Error(state+' has no row of its own');
 if(state==='gesture')r=gestureRecipe(design.gestures,v);
 else if(state==='notice')r=noticeRecipe(design.noticeClip);
 else if(['working','terminal','analyzing','waiting'].includes(state)){r=deskRecipe(state,v);jitter=true;}
 else if(state==='needs_you')r=alertRecipe(design);
 else if(state==='task_complete')r=resultRecipe(outcome||null,v);
 else if(state==='reply_ready')r=statusResultRecipe(state,v);
 else if(state==='wake_up')r=wakeRecipe(v);
 else if(['poked','tap_spam'].includes(state))r=touchRecipe(state,v);
 else if(state==='listening')r=listenRecipe(v);
 else if(state==='asleep')r=restRecipe(v);else if(state==='no_app')r=restRecipe();else r=idleRecipe();
 return {r,jitter};
}