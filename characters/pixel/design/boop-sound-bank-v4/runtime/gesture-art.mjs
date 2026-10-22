import {palette as P,rect,at,star,block} from './visual/base.mjs';
import {newMoods} from './mood-catalog.mjs';
import {frames,sceneSvg,round,pad,slab} from './mood-art.mjs';
import {oldMoods,profile,lineUp,sleepyFace,ownFace} from './wake-art.mjs';
import {effects} from './audio/effects.mjs';
import {moods,steps,own,heart,bang} from './kit-art.mjs';

// gesture: the board's own reaction to what you do to it, one variation a
// gesture, in the engine's order (render::Gesture, firmware/src/render/
// types.h), drawn for every mood with its own face:
//   1 handoff: BOOT handed you an agent: it holds up a parcel and slides it to you;
//   2 stroke: eyes close, it leans into the finger, a purr of hearts;
//   3 ruffle: stroked the wrong way: its top bristles, an indignant huff;
//   4 nose: booped on the nose: a squish, a star where the finger was;
//   5 tickle: it giggles and squirms;
//   6 dizzy: shaken: spiral eyes, a wobble, stars going round;
//   7 pickup: picked up: it looks up, surprised;
//   8 putdown: set down: a squish and a puff of dust;
//   9 startle: a thump on the desk: it jumps;
//   10 peekaboo: turned face up again: it peeks up from below.
// Each plays once, starting and ending on the mood's resting face but the
// peekaboo, which comes up from nothing, with a cue or two.

export const gestures=[
 ['handoff','Here you go','Holds up a parcel and slides it toward you: your next agent.',2.4],
 ['stroke','Stroked','Eyes close and it leans into your finger; a little purr of hearts.',2.6],
 ['ruffle','Ruffled','Stroked the wrong way: its top bristles and it huffs.',2.0],
 ['nose','Boop!','Booped on the nose: a squish and a star where your finger was.',1.6],
 ['tickle','Tickled','Giggles and squirms side to side.',2.0],
 ['dizzy','Dizzy','Shaken: spiral eyes, a wobble and stars going round.',2.6],
 ['pickup','Picked up','Looks up at you, surprised: oh, hi!',1.8],
 ['putdown','Set down','A squish as it lands, and a puff of dust.',1.6],
 ['startle','Startled','A thump on the desk: it jumps, eyes wide.',1.6],
 ['peekaboo','Peekaboo','Turned face up again: it peeks up from below, then sparkles.',2.2]
];
export const gestureAdditions=moods.flatMap(mood=>gestures.map(([action,name,caption,seconds],i)=>({
 id:`${mood}.gesture.${String(i+1).padStart(2,'0')}`,mood,state:'gesture',variation:i+1,action,name,caption,
 seconds:Number((seconds*Math.min(1.15,profile(mood).pace)).toFixed(3)),renderer:'gesture-v1',approval:'Review candidate'
})));

// ---- Plans: [when (of the loop), pose, cue, gain] ---------------------------
const plans={
 handoff:[[0,'home'],[.12,'lift','swipe',.35],[.3,'hold'],[.5,'give','pop',.45],[.7,'given'],[.85,'blink'],[.92,'home'],[1,'home']],
 stroke:[[0,'home'],[.12,'lean'],[.3,'content','shimmer',.25],[.55,'content-2'],[.8,'lean'],[.92,'home'],[1,'home']],
 ruffle:[[0,'home'],[.15,'bristle','crumple',.3],[.4,'huff'],[.6,'bristle'],[.8,'blink'],[.9,'home'],[1,'home']],
 nose:[[0,'home'],[.1,'squish','pop',.5],[.35,'giggle'],[.65,'blink'],[.8,'home'],[1,'home']],
 tickle:[[0,'home'],[.1,'wiggle-left','rubber',.3],[.25,'wiggle-right'],[.4,'wiggle-left','rubber',.3],[.55,'wiggle-right'],[.75,'giggle'],[.9,'home'],[1,'home']],
 dizzy:[[0,'home'],[.1,'spin-1','whoosh',.35],[.3,'spin-2'],[.5,'spin-1'],[.7,'spin-2'],[.85,'blink'],[.93,'home'],[1,'home']],
 pickup:[[0,'home'],[.1,'up','swipe',.3],[.35,'up-2'],[.7,'blink'],[.82,'home'],[1,'home']],
 putdown:[[0,'home'],[.1,'land','cushion',.4],[.3,'settle'],[.6,'blink'],[.7,'home'],[1,'home']],
 startle:[[0,'home'],[.08,'jump','snap',.5],[.3,'wide'],[.6,'blink'],[.72,'home'],[1,'home']],
 peekaboo:[[0,'gone'],[.15,'peek-1'],[.35,'peek-2','pop',.4],[.55,'home'],[.7,'sparkle'],[.88,'blink'],[.94,'home'],[1,'home']]
};
export function gesturePlan(a){
 return {steps:steps(a,plans[a.action]),policy:'entry',intervalSeconds:0};
}

// ---- The faces ---------------------------------------------------------------
// Spiral eyes: a square ring with a dot, at each eye, turned a step.
function spirals(y,turn){
 const one=(x)=>rect(x,94+y,40,4)+rect(x+36,94+y,4,24)+rect(x+8,114+y,32,4)+rect(x+8,102+y,4,16)+rect(x+12,102+y,16,4)+rect(x+20,106+y,4,6);
 const eyes=at(turn?2:0,0,one(68)+one(212));
 return eyes+rect(150,134+y,20,4)+[51,69,237,255].map(x=>block(x,124+y,14,9,P.cheek)).join('');
}
const faces={
 home:own(),blink:a=>ownFace(a.mood,true),
 lift:own(0,-4),hold:own(0,-6),give:own(0,4),given:own(0,2),
 lean:own(6,2),content:a=>at(6,2,sleepyFace('shut','mm',lineUp(a.mood))),'content-2':a=>at(8,4,sleepyFace('shut','mm',lineUp(a.mood))),
 bristle:own(0,-2),huff:own(0,0),
 squish:own(0,8),giggle:a=>at(0,-2,sleepyFace('squeeze','wide',lineUp(a.mood))),
 'wiggle-left':a=>at(-8,0,sleepyFace('squeeze','wide',lineUp(a.mood))),'wiggle-right':a=>at(8,0,sleepyFace('squeeze','wide',lineUp(a.mood))),
 'spin-1':a=>at(-6,0,spirals(lineUp(a.mood),0)),'spin-2':a=>at(6,0,spirals(lineUp(a.mood),1)),
 up:own(0,-10),'up-2':own(0,-12),
 land:own(0,10),settle:own(0,4),
 jump:own(0,-16),wide:own(0,-6),
 gone:()=>'','peek-1':own(0,70),'peek-2':own(0,30),sparkle:own()
};
function faceFor(a,pose){return faces[pose](a);}

// ---- What's around it --------------------------------------------------------
// A parcel: a box with a ribbon, held by two mitts at `y`, `s` its size.
const parcel=(y,s=1)=>{const w=Math.round(48*s),h=Math.round(36*s),x=160-w/2;
 return slab(x,y,w,h,P.amber)+rect(x+w/2-3,y,6,h,P.red)+rect(x,y+h/2-3,w,6,P.red)+pad(x-24,y+h/2-8)+pad(x+w-4,y+h/2-8);};
const bristles=y=>[0,1,2,3,4,5,6,7].map(i=>rect(84+i*20,y+(i%2?6:0),6,14,P.prop)).join('');
const puffs=(x,y)=>rect(x,y,8,8,P.dim)+rect(x+12,y+4,6,6,P.prop)+rect(x-10,y+6,6,6,P.prop);
const props={
 handoff:{lift:()=>parcel(150,.8),hold:()=>parcel(130,.9)+star(60,40,8,P.amber),give:()=>parcel(140,1.25),given:()=>parcel(150,1.4)+star(250,40,16,P.amber)+star(70,30,8,P.amber)},
 stroke:{lean:()=>rect(40,60,24,6,P.prop),content:()=>heart(250,40),'content-2':()=>heart(262,24,P.cheek)+heart(232,56)},
 ruffle:{bristle:a=>bristles(48+lineUp(a.mood)),huff:a=>bristles(50+lineUp(a.mood))+puffs(206,140)},
 nose:{squish:()=>star(160,128,16,P.amber),giggle:()=>star(150,40,8,P.ink)+star(176,24,8,P.ink)},
 tickle:{'wiggle-left':()=>star(40,60,8,P.ink),'wiggle-right':()=>star(270,60,8,P.ink),giggle:()=>star(40,60,8,P.ink)+star(270,60,8,P.ink)},
 dizzy:{'spin-1':()=>star(70,30,8,P.amber)+star(240,24,8,P.amber),'spin-2':()=>star(120,14,8,P.amber)+star(200,18,8,P.amber)},
 pickup:{up:()=>bang(40,24)+bang(274,24),'up-2':()=>bang(40,20)+bang(274,20)},
 putdown:{land:()=>puffs(70,176)+puffs(242,176),settle:()=>puffs(60,180)+puffs(252,180)},
 startle:{jump:()=>bang(36,30)+bang(278,30)+bang(52,30)+bang(262,30),wide:()=>bang(36,30)+bang(278,30)},
 peekaboo:{sparkle:()=>star(60,40,16,P.amber)+star(260,36,16,P.amber)+star(276,70,8,P.ink)}
};
const propsFor=(a,pose)=>props[a.action]?.[pose]?.(a)??'';

export function renderGestureScene(a){
 const plan=gesturePlan(a),id='boop-gesture-'+a.id.replaceAll('.','-');
 const art=frames(a,plan,s=>faceFor(a,s.pose),'gesture-face')+frames(a,plan,s=>propsFor(a,s.pose),'gesture-props');
 const still=a.action==='peekaboo'?faceFor(a,'home'):faceFor(a,plan.steps[2].pose)+propsFor(a,plan.steps[2].pose);
 return sceneSvg(a,id,a.caption,art,still);
}
export function gestureScore(a){
 const plan=gesturePlan(a),pace=profile(a.mood);
 const events=plan.steps.flatMap((s,i)=>s.effect?[{at:s.at,effect:s.effect,gain:round(s.gain*pace.gain),pitch:pace.pitch,
  label:`${a.action} · ${s.pose}`,sync:{part:'gesture-props',step:i,pose:s.pose}}]:[]);
 for(const e of events)if(!effects[e.effect])throw new Error('Missing effect '+e.effect);
 return {id:a.id,seconds:a.seconds,policy:'entry',intervalSeconds:0,character:pace.character,
  description:a.caption+' A cue or two on its moments.',events,tailSeconds:round(Math.max(0,...events.map(e=>e.at+effects[e.effect].duration-a.seconds)))};
}
