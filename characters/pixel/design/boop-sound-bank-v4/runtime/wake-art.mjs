import {palette as P,rect,path,block,group,at,star,face as baseFace} from './visual/base.mjs';
import {acting} from './state-catalog.mjs';
import {moodProfiles,newMoods} from './mood-catalog.mjs';
import {moodFace,frames,sceneSvg,round,pad} from './mood-art.mjs';
import {effects} from './audio/effects.mjs';

// wake_up: you're back at the Mac after a long break, and Boop wakes up for
// you. One flip-book for all 13 drawn moods: the eyes droop, a big yawn with
// both mitts up, a long stretch (a joint creaks), a little shake, then the
// mood's own face, awake, with a hop and its own flourish, and a blink. It
// starts and ends on the mood's resting face, so it plays over any look.

export const oldMoods=Object.keys(acting);
// A mood's pace, gain, pitch and character: the older moods' acting, or the
// newer ones' profile.
export const profile=mood=>acting[mood]??moodProfiles[mood];
const hop={happy:6,excited:10,proud:4,curious:4,determined:3,grumpy:2,sad:1,calm:2,engaged:4,annoyed:1,irritated:3,whiny:2,wounded:1};
// What each mood does once it's awake: sparkles, a huff, or a tear; or
// nothing, its face says it.
const flourish={happy:'sparkle',excited:'sparkle',proud:'sparkle',grumpy:'huff',annoyed:'huff',irritated:'huff',sad:'tear',whiny:'tear',wounded:'tear'};

export const wakeAdditions=[...oldMoods,...newMoods].map(mood=>({
 id:`${mood}.wake_up.01`,mood,state:'wake_up',variation:1,action:'stretch-yawn',name:'Good morning',
 caption:'Eyes droop, a big yawn with both mitts up, a long stretch and a shake, then awake in the mood with a hop.',
 seconds:Number((5.6*profile(mood).pace).toFixed(3)),
 renderer:'wake-v1',approval:'Review candidate'
}));

// Each step is one pose and the contact sound that goes with it, if any.
export function wakePlan(a){
 const steps=[],add=(u,pose,effect=null,gain=.5)=>steps.push({at:round(u*a.seconds),pose,effect,gain});
 add(0,'home');add(.08,'droop');add(.18,'inhale');add(.30,'yawn');add(.42,'stretch','creak',.34);add(.56,'release');
 add(.66,'shake-left');add(.71,'shake-right');add(.76,'shake-left');
 add(.84,'awake',flourish[a.mood]==='sparkle'?'sprinkle':'pop',.42);add(.93,'blink');add(.98,'home');add(1,'home');
 // A line said over it starts once Boop is awake, not mid-yawn.
 return {steps,voiceAt:steps.find(s=>s.pose==='awake').at,policy:'entry',intervalSeconds:0};
}

// The sleepy faces are shared: the mood comes back when Boop wakes. `y` lines
// them up with the mood's own face (the newer moods sit a little higher).
export const lineUp=mood=>oldMoods.includes(mood)?0:-6;
const sleepyEyes={
 heavy:y=>block(68,94+y,40,16)+block(212,94+y,40,16),
 squeeze:y=>[[0,0],[12,8],[24,16],[12,24],[0,32]].map(([dx,dy])=>rect(72+dx,82+y+dy,12,8)+rect(236-dx,82+y+dy,12,8)).join(''),
 shut:y=>block(68,99+y,40,5)+block(212,99+y,40,5)
};
const sleepyMouth={
 o:y=>path(`M152 ${128+y}h16v16h-16Zm4 4v8h8v-8Z`,P.ink),
 yawn:y=>block(140,120+y,40,42)+rect(146,126+y,28,30,P.dark)+rect(150,148+y,20,8,P.cheek),
 wide:y=>block(136,114+y,48,50)+rect(142,120+y,36,38,P.dark)+rect(148,150+y,24,8,P.cheek),
 mm:y=>rect(150,134+y,20,4)+rect(146,130+y,4,4)+rect(170,130+y,4,4)
};
export function sleepyFace(eyes,mouth,y){
 const cheeks=[51,69,237,255].map(x=>block(x,124+y,14,9,P.cheek)).join('');
 return group(sleepyEyes[eyes](y)+group(sleepyMouth[mouth](y),'data-part="mouth"')+cheeks,'data-part="face"');
}
// The mood's own face, at rest, or blinking: the older moods' from the
// first pack's face, the newer ones' from their flip-books. `complete`, it's
// the face at a success, on gold, the newer moods' at a cheer's `stage`.
// Tagged for the rig face to draw (visual/base.mjs part) but at a success,
// or with `rig` false.
export function ownFace(mood,blink,{complete=false,stage=0,rig=true}={}){
 if(!oldMoods.includes(mood))return moodFace(complete?{mood,state:'task_complete',outcome:'success'}:{mood,state:'wake_up'},stage,blink,rig);
 const ink=complete?P.dark:P.ink;
 const ctx={mood,state:complete?'task_complete':'idle',quiet:false,complete,motion:false,ink,bg:complete?P.gold:P.black,cheek:complete?'#D8576C':P.cheek,shut:blink,rig};
 const art=baseFace(ctx);
 return blink?art.replace('data-part="face"','data-part="face" data-blink="1"'):art;
}
// Where the face sits in each pose; awake, it hops by its mood's own height.
// The comedy's yawn borrows these poses.
const offsets={home:[0,0],droop:[0,4],inhale:[0,2],yawn:[0,-4],stretch:[0,-8],release:[0,2],'shake-left':[-5,0],'shake-right':[5,0],blink:[0,0]};
export function faceFor(a,pose){
 const y=lineUp(a.mood),[dx,dy]=pose==='awake'?[0,-hop[a.mood]]:offsets[pose];
 const art={home:()=>ownFace(a.mood,false),awake:()=>ownFace(a.mood,false),blink:()=>ownFace(a.mood,true),
  droop:()=>sleepyFace('heavy','o',y),inhale:()=>sleepyFace('squeeze','o',y),yawn:()=>sleepyFace('squeeze','yawn',y),
  stretch:()=>sleepyFace('squeeze','wide',y),release:()=>sleepyFace('shut','mm',y),
  'shake-left':()=>sleepyFace('shut','mm',y),'shake-right':()=>sleepyFace('shut','mm',y)}[pose]();
 return at(dx,dy,art);
}
// The mitts, the yawn's tear and the waking flourish, around the face.
export function props(a,pose){
 switch(pose){
  case 'inhale':return pad(40,138)+pad(252,138);
  case 'yawn':return pad(48,24)+pad(244,24);
  case 'stretch':return pad(26,8)+pad(266,8)+rect(64,40,6,6,P.dim)+rect(250,40,6,6,P.dim)+rect(58,52,4,4,P.dim)+rect(258,52,4,4,P.dim);
  case 'release':return pad(44,92)+pad(248,92)+rect(114,108,6,6,P.lightWater);
  case 'shake-left':case 'shake-right':{const k=pose==='shake-left'?-1:1;return rect(160+k*112,70,6,6,P.dim)+rect(160+k*120,86,4,4,P.dim)+rect(160+k*112,102,6,6,P.dim);}
  case 'awake':{
   const f=flourish[a.mood];
   if(f==='sparkle')return star(36,36,16,P.amber)+star(266,30,16,P.amber)+star(280,62,8,P.amber);
   if(f==='huff')return rect(196,140,6,6,P.dim)+rect(206,134,6,6,P.dim)+rect(214,144,4,4,P.dim);
   if(f==='tear')return rect(84,120,6,6,P.blue)+rect(86,132,4,4,P.lightWater);
   return '';
  }
  default:return '';
 }
}
export function renderWakeScene(a){
 const plan=wakePlan(a),id='boop-wake-'+a.id.replaceAll('.','-');
 const art=frames(a,plan,s=>faceFor(a,s.pose),'wake-face')+frames(a,plan,s=>props(a,s.pose),'wake-action');
 const still=faceFor(a,'awake')+props(a,'awake');
 return sceneSvg(a,id,a.caption,art,still);
}
export function wakeScore(a){
 const plan=wakePlan(a),pace=profile(a.mood);
 const events=plan.steps.flatMap((s,i)=>s.effect?[{at:s.at,effect:s.effect,gain:round(s.gain*pace.gain),pitch:pace.pitch,label:`${a.action} · ${s.pose}`,sync:{part:'wake-action',step:i,pose:s.pose}}]:[]);
 for(const e of events)if(!effects[e.effect])throw new Error('Missing effect '+e.effect);
 return {id:a.id,seconds:a.seconds,policy:plan.policy,intervalSeconds:plan.intervalSeconds,voiceSeconds:plan.voiceAt,character:pace.character,description:a.caption+' A creak on the stretch and a pop as it wakes; no speech or music bed.',events,tailSeconds:round(Math.max(0,...events.map(e=>e.at+effects[e.effect].duration-a.seconds)))};
}
