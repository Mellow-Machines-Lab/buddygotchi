import {palette as P,rect,at,star} from './visual/base.mjs';
import {newMoods} from './mood-catalog.mjs';
import {frames,sceneSvg,round,pad,slab,background,burst,cup,completeCard,props as moodProps} from './mood-art.mjs';
import {oldMoods,profile,lineUp,sleepyFace,ownFace,faceFor as wakeFace,props as wakeProps} from './wake-art.mjs';
import {effects} from './audio/effects.mjs';
import {moods,design,steps,own,bang} from './kit-art.mjs';
const make=design('comedy-v1');

// Comedy: life for the quiet looks and a joke on the finish, as new
// variations of states that exist, so the device turns to them by itself.
// Each is one flip-book drawn for every mood that has it, at the mood's own
// pace and with its own face (wake-art's, which the wake-up shares):
//   idle 4, yawn and stretch: the wake-up's yawn, slower, then rest;
//   idle 5, nodding off: eyes droop shut, the head nods, it snaps awake;
//   idle 6, sneeze: a wind-up, a sneeze, a little shake;
//   asleep 4, snore: two soft breaths, the same in every mood, as asleep is;
//   task_complete, trophy then hiccups: the mood's cheer, then three hics;
//   proud's task_complete, the gift: it holds up a bug it caught;
//   excited's working 6 and idle 7, zoomies: the face zips off and back.
// Each starts and ends on its resting face. Their sounds are scored, not
// routine: a quiet look stays quiet but for a yawn once, a sneeze every
// third loop or a snore every fourth, each soft; zoomies sound as routine
// work does (quiet-mix.mjs).

// A finish's new variation comes after the mood's others: the older moods
// have five (four successes and a failure), the newer six.
const finishes=mood=>oldMoods.includes(mood)?5:6;
export const comedyAdditions=[
 ...moods.map(mood=>make(mood,'idle',4,'yawn-stretch','Yawn and stretch','Eyes droop, a slow wide yawn with both mitts up, a long stretch, then a blink and rest.',9*profile(mood).pace,{sound:'scored'})),
 // Nodding off waits for idle's last tier (tier5: ten minutes since the
 // last turn ended), the snore for ten minutes asleep (`after`, in seconds;
 // occasion-art.mjs).
 ...moods.map(mood=>make(mood,'idle',5,'nod-off','Nodding off','Eyes droop shut and the head nods for two seconds, then it snaps awake, blinks and looks around.',11*profile(mood).pace,{sound:'scored',when:['tier5']})),
 ...moods.map(mood=>make(mood,'idle',6,'sneeze','Sneeze','Ah… ah… a wind-up with the head thrown back, a sneeze and its spray, a little shake.',10*profile(mood).pace,{sound:'scored'})),
 // Asleep looks the same in every mood, so its snore does too.
 ...moods.map(mood=>make(mood,'asleep',4,'snore','Snore','Two soft snoring breaths: the mouth opens on each, and a Z drifts up.',12,{sound:'scored',after:600})),
 ...moods.map(mood=>make(mood,'task_complete',finishes(mood)+1,'trophy-hiccups','Trophy, then hiccups','The mood\'s trophy cheer, then three hiccups that bounce the face.',8,{outcome:'success'})),
 make('proud','task_complete',7,'gift','The gift','Proudly holds up a little pixel bug it caught, then presents it to you.',7,{outcome:'success'}),
 ...['working','idle'].map((state,i)=>make('excited',state,i?7:6,'zoomies','Zoomies','The face zips left, right and off the screen, comes back from the other side and hops.',5*profile('excited').pace,{sound:'routine'}))
];

// The steps of each design: [when (of the loop), pose, cue, cue's gain].
const plans={
 'yawn-stretch':()=>[[0,'home'],[.10,'droop'],[.18,'inhale'],[.27,'yawn','yawn',.40],[.39,'stretch'],[.52,'release'],[.60,'settle'],[.66,'home'],[.70,'blink'],[.73,'home'],[.98,'home'],[1,'home']],
 'nod-off':()=>[[0,'home'],[.24,'heavy'],[.31,'shut'],[.37,'nod'],[.45,'nod-deep'],[.52,'snap'],[.55,'blink'],[.58,'home'],[.63,'glance-left'],[.69,'glance-right'],[.75,'home'],[.98,'home'],[1,'home']],
 'sneeze':()=>[[0,'home'],[.22,'tickle'],[.30,'ah','swipe',.16],[.37,'ah-ah'],[.44,'choo','sneeze',.55],[.48,'spray'],[.52,'shake-left'],[.55,'shake-right'],[.58,'shake-left'],[.62,'blink'],[.66,'home'],[.98,'home'],[1,'home']],
 // Two breaths: in, the mouth opening on a snore; out, a Z drifting up.
 'snore':()=>[0,.5].flatMap(u=>[[u,'rest'],[u+.10,'in'],[u+.18,'snore','snore',.24],[u+.28,'out'],[u+.36,'out-z']]).concat([[.98,'rest'],[1,'rest']]),
 // The cheer's fanfare is the mood's first success's (excited's and proud's
 // have the crowd); then three hiccups, each with its chirp.
 'trophy-hiccups':a=>[[0,'home'],[.06,'cheer-1',['excited','proud'].includes(a.mood)?'trophyB':'trophyA',a.mood==='sad'?.72:.86],[.13,'cheer-2'],[.20,'cheer-3'],[.27,'cheer-4'],[.34,'cheer-5'],[.41,'cheer-6'],
  [.48,'hic-1','hiccup',.42],[.53,'held'],[.61,'hic-2','hiccup',.42],[.66,'held'],[.74,'hic-3','hiccup',.46],[.79,'held'],[.86,'blink'],[.91,'home'],[.98,'home'],[1,'home']],
 'gift':()=>[[0,'home'],[.08,'reach'],[.16,'catch','pop',.42],[.26,'raise','trophyB',.82],[.34,'wiggle'],[.42,'raise'],[.50,'present'],[.60,'present-wiggle'],[.70,'tuck'],[.78,'blink'],[.84,'home'],[.98,'home'],[1,'home']],
 'zoomies':()=>[[0,'home'],[.07,'crouch','cushion',.30],[.13,'zip-left','whoosh',.50],[.19,'zip-right','whoosh',.50],[.25,'off-right','swipe',.45],[.31,'gone'],[.37,'enter-left','swipe',.40],[.43,'overshoot','rubber',.45],[.48,'recoil'],[.53,'hop','pop',.40],[.58,'home'],[.66,'blink'],[.70,'home'],[.98,'home'],[1,'home']]
};
const policies={'yawn-stretch':'entry','nod-off':'silent','sneeze':'sparse','snore':'sparse','trophy-hiccups':'entry','gift':'entry','zoomies':'loop'};
// A sparse design sounds every this many loops, from its first.
export const sparseEvery={'sneeze':3,'snore':4};
export function comedyPlan(a){
 const policy=policies[a.action],every=sparseEvery[a.action];
 // The bank's player sounds every ceil(interval / loop) loops (score.mjs).
 return {steps:steps(a,plans[a.action](a)),policy,intervalSeconds:every?round((every-.5)*a.seconds):0};
}

// ---- The faces ----------------------------------------------------------------
// The mood's resting face, or blinking, as the wake-up has it; the sleepy
// faces are wake-up's too, lined up with the mood's own. On a finish, the
// mood's face at a success, on gold (a cheer's stage).
const blinking=a=>ownFace(a.mood,true);
const sleepy=(eyes,mouth,dx=0,dy=0)=>a=>at(dx,dy,sleepyFace(eyes,mouth,lineUp(a.mood)));
const successFace=(a,stage,blink=false)=>ownFace(a.mood,blink,{complete:true,stage});
const cheering=(stage,dy=0)=>a=>at(0,dy,successFace(a,stage));
// The zoomies' face, which leaves the screen: further than the device's rig
// face goes, so it's baked.
const zip=(dx,dy)=>a=>at(dx,dy,ownFace(a.mood,false,{rig:false}));
// Each pose's face and where it sits.
const faces={
 home:own(),blink:blinking,
 // Yawn and stretch: the wake-up's poses, then a settle.
 ...Object.fromEntries(['droop','inhale','yawn','stretch','release'].map(pose=>[pose,a=>wakeFace(a,pose)])),settle:sleepy('shut','mm',0,1),
 // Nodding off.
 heavy:sleepy('heavy','mm',0,3),shut:sleepy('shut','mm',0,6),nod:sleepy('shut','o',0,12),'nod-deep':sleepy('shut','o',0,17),
 snap:own(0,-8),'glance-left':own(-7,0),'glance-right':own(7,0),
 // Sneeze.
 tickle:sleepy('heavy','o',2,-2),ah:sleepy('squeeze','yawn',0,-6),'ah-ah':sleepy('squeeze','wide',0,-10),
 choo:sleepy('squeeze','mm',0,10),spray:sleepy('shut','mm',0,6),'shake-left':sleepy('shut','mm',-6,0),'shake-right':sleepy('shut','mm',6,0),
 // Snore: the shared sleeping face, whatever the mood.
 rest:()=>sleepyFace('shut','mm',0),in:()=>at(0,-2,sleepyFace('shut','mm',0)),snore:()=>at(0,-4,sleepyFace('shut','o',0)),
 out:()=>at(0,-1,sleepyFace('shut','mm',0)),'out-z':()=>sleepyFace('shut','mm',0),
 // Trophy, then hiccups.
 'cheer-1':cheering(1),'cheer-2':cheering(2,-6),'cheer-3':cheering(3),'cheer-4':cheering(4,-6),'cheer-5':cheering(5),'cheer-6':cheering(6),
 held:cheering(0),'hic-1':cheering(0,-12),'hic-2':cheering(0,-12),'hic-3':cheering(0,-15),
 // The gift.
 reach:cheering(0,4),catch:cheering(0,2),raise:cheering(0,-2),wiggle:cheering(0,-4),present:cheering(0),'present-wiggle':cheering(0,-2),tuck:cheering(0),
 // Zoomies.
 crouch:zip(0,6),'zip-left':zip(-80,-6),'zip-right':zip(80,-6),'off-right':zip(240,-10),gone:zip(400,0),'enter-left':zip(-150,4),
 overshoot:zip(20,0),recoil:zip(-6,0),hop:zip(0,-10)
};
// The finishes, on gold: their faces rest and blink on the success face.
const gold=a=>['trophy-hiccups','gift'].includes(a.action);
const goldFaces={home:a=>successFace(a,0),blink:a=>successFace(a,0,true)};
function faceFor(a,pose){
 if(gold(a)&&goldFaces[pose])return goldFaces[pose](a);
 return faces[pose](a);
}

// ---- What's around the face ---------------------------------------------------
// A pixel Z, `k` px a stroke.
const zee=(x,y,k,c=P.dim)=>rect(x,y,5*k,k,c)+rect(x+3*k,y+k,k,k,c)+rect(x+2*k,y+2*k,k,k,c)+rect(x+k,y+3*k,k,k,c)+rect(x,y+4*k,5*k,k,c);
const drops=list=>list.map(([x,y,s],i)=>rect(x,y,s,s,[P.lightWater,P.blue,P.water][i%3])).join('');
// A snore's bubble: a hollow square that grows as the breath goes out.
const bubble=(x,y,s)=>slab(x,y,s,s,P.lightWater)+rect(x+3,y+3,s-6,s-6,P.black)+rect(x+4,y+4,3,3,P.ink);
// A hiccup's: a little bubble that pops out, and a jolt either side.
const hic=(x,y)=>slab(x,y,16,16,P.dark)+rect(x+4,y+4,8,8,P.ink)+rect(x+4,y+4,4,4,P.lightWater)+rect(26,76,12,4,P.dark)+rect(22,88,10,4,P.dark)+rect(282,76,12,4,P.dark)+rect(288,88,10,4,P.dark);
// Lines left behind by a face on the move.
const trail=(x0,x1,y)=>[0,1,2].map(i=>rect(x0+i*9,y+i*24,Math.max(8,x1-x0-i*18),4,P.dim)).join('');
const puffs=(x,y)=>rect(x,y,8,8,P.dim)+rect(x+12,y+4,6,6,P.prop)+rect(x-10,y+6,6,6,P.prop);
// A little pixel bug: a red shell with spots, a head, antennae and six legs
// that wiggle (`legs` 0 or 1), at 2 px a pixel.
function bug(x,y,legs){
 const k=2,r=(px,py,w,h,c)=>rect(x+px*k,y+py*k,w*k,h*k,c);
 let art=r(6,0,1,3,P.dark)+r(13,0,1,3,P.dark)+r(7,2,6,4,P.dark)+slab(x+2*k,y+5*k,16*k,14*k,P.red)+r(9,6,2,12,P.dark)+r(5,9,3,3,P.dark)+r(13,9,3,3,P.dark)+r(5,14,2,2,P.dark)+r(14,14,2,2,P.dark);
 for(let i=0;i<3;i++){const up=(i+legs)%2?-1:1;art+=r(-1,8+i*4+up,4,1,P.dark)+r(17,8+i*4-up,4,1,P.dark);}
 return art;
}
const sparkles=phase=>phase?star(60,40,16,P.ink)+star(250,30,8,P.ink)+star(270,70,16,P.ink):star(40,64,8,P.ink)+star(240,46,16,P.ink)+star(76,20,8,P.ink);
const trophy=(y=0)=>at(0,y,cup(139,106,.75))+completeCard();
// The cheer's stages, the mood's trophy cheer in its colours.
const cheerStages={'cheer-1':1,'cheer-2':2,'cheer-3':3,'cheer-4':4,'cheer-5':5,'cheer-6':6};
const cheerProps=(a,pose)=>moodProps({...a,action:'cup'},{stage:cheerStages[pose]});
// The gift held up, or held out to you, its legs wiggling on the second pose.
const raised=(a,pose)=>{const legs=pose==='wiggle'?1:0;return bug(136,4,legs)+pad(108,14)+pad(176,14)+sparkles(legs);};
const presented=(a,pose)=>{const legs=pose==='present'?0:1;return bug(136,152,legs)+pad(108,166)+pad(176,166)+sparkles(legs);};
// Each design's props, by pose; any other pose has none.
const props={
 'yawn-stretch':{inhale:wakeProps,yawn:wakeProps,stretch:wakeProps,release:wakeProps},
 'nod-off':{nod:()=>zee(262,58,3),'nod-deep':()=>zee(262,50,3)+zee(282,26,2),snap:()=>bang(36,30)+bang(278,30)},
 sneeze:{
  ah:()=>rect(144,24,6,6,P.dim)+rect(170,16,6,6,P.dim),
  'ah-ah':()=>rect(132,18,6,6,P.dim)+rect(152,8,6,6,P.dim)+rect(178,12,6,6,P.dim),
  choo:()=>drops([[126,160,6],[190,160,6],[110,172,4],[206,172,4],[140,182,6],[176,182,4],[96,182,4],[222,182,6]])+rect(24,92,18,4,P.dim)+rect(278,92,18,4,P.dim)+rect(30,108,12,4,P.dim)+rect(278,108,12,4,P.dim),
  spray:()=>drops([[92,176,4],[226,178,4],[76,186,4],[242,186,4],[118,186,4],[198,186,4]]),
  'shake-left':wakeProps,'shake-right':wakeProps
 },
 snore:{snore:()=>rect(186,130,4,4,P.dim)+rect(194,124,4,4,P.dim),out:()=>bubble(184,128,12)+zee(250,72,2),'out-z':()=>bubble(184,124,18)+zee(258,52,3)},
 'trophy-hiccups':{
  'cheer-1':cheerProps,'cheer-2':cheerProps,'cheer-3':cheerProps,'cheer-4':cheerProps,'cheer-5':cheerProps,'cheer-6':cheerProps,
  'hic-1':()=>trophy(-6)+hic(112,54),'hic-2':()=>trophy(-6)+hic(194,54),'hic-3':()=>trophy(-8)+hic(153,30),held:()=>trophy()
 },
 gift:{
  reach:()=>pad(104,164)+pad(188,164),catch:()=>bug(136,152,0)+pad(108,166)+pad(176,166)+burst(158,160,1,P.ink,4),
  raise:raised,wiggle:raised,present:presented,'present-wiggle':presented,tuck:()=>pad(104,166)+pad(188,166)
 },
 zoomies:{
  crouch:()=>puffs(70,176)+puffs(242,176),'zip-left':()=>trail(196,268,80),'zip-right':()=>trail(52,124,80),'off-right':()=>trail(30,280,76),
  gone:()=>puffs(300,120),'enter-left':()=>puffs(14,128)+puffs(14,96),overshoot:()=>rect(12,90,24,4,P.dim)+rect(18,114,18,4,P.dim),hop:()=>puffs(150,184)
 }
};
function propsFor(a,pose){
 const drawn=props[a.action];
 if(!drawn)throw new Error('Unauthored comedy '+a.action);
 return drawn[pose]?.(a,pose)??'';
}
// The finishes' gold behind, in the cheer's colours, still while it hics;
// the gift's held-up poses take the cheer's later stages.
const backgroundStages={...cheerStages,raise:3,wiggle:4,present:5,'present-wiggle':6};
const backgroundFor=(a,pose)=>gold(a)?background({outcome:'success'},backgroundStages[pose]??0):'';
// A pose drawn whole: the gold behind, the face and its props.
const frame=(a,pose)=>backgroundFor(a,pose)+faceFor(a,pose)+propsFor(a,pose);

export function renderComedyScene(a){
 const plan=comedyPlan(a),id='boop-comedy-'+a.id.replaceAll('.','-');
 const art=frames(a,plan,s=>backgroundFor(a,s.pose),'comedy-background')+frames(a,plan,s=>faceFor(a,s.pose),'comedy-face')+frames(a,plan,s=>propsFor(a,s.pose),'comedy-action');
 // Reduced motion: the resting face, the finishes' cheer and the gift held up.
 const still=a.action==='trophy-hiccups'?frame(a,'cheer-5'):a.action==='gift'?frame(a,'raise')
  :a.action==='snore'?faceFor(a,'rest')+zee(258,52,3):faceFor(a,'home');
 return sceneSvg(a,id,a.caption,art,still);
}
export function comedyScore(a){
 const plan=comedyPlan(a),pace=profile(a.mood),shared=a.state==='asleep',finish=a.state==='task_complete';
 const events=plan.steps.flatMap((s,i)=>s.effect?[{at:s.at,effect:s.effect,
  // A finish's cues play at their own level, its fanfare at its own pitch, as
  // the other finishes'; the asleep snore is the same in every mood.
  gain:round(s.gain*(finish||shared?1:pace.gain)),pitch:shared||/^trophy/.test(s.effect)?1:pace.pitch,
  label:`${a.action} · ${s.pose}`,sync:{part:'comedy-action',step:i,pose:s.pose}}]:[]);
 for(const e of events)if(!effects[e.effect])throw new Error('Missing effect '+e.effect);
 return {id:a.id,seconds:a.seconds,policy:plan.policy,intervalSeconds:plan.intervalSeconds,character:shared?'Shared quiet routine · mood ignored':pace.character,
  description:a.caption+' Code-generated sounds on its visible moments; no speech or music bed.',events,tailSeconds:round(Math.max(0,...events.map(e=>e.at+effects[e.effect].duration-a.seconds)))};
}
