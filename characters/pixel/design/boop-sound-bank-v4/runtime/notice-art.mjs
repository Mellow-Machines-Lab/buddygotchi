import {palette as P,at,star} from './visual/base.mjs';
import {frames,sceneSvg,round} from './mood-art.mjs';
import {profile,lineUp,sleepyFace,ownFace} from './wake-art.mjs';
import {effects} from './audio/effects.mjs';
import {moods,steps,own,heart,bang} from './kit-art.mjs';

// notice: the brain's reaction when you name it in your prompt: it heard
// its name and looks up at you, surprised and pleased. Three variations,
// drawn for every mood with its own face, dealt as any reaction's are:
//   1 perk: it looks up at you, an exclamation either side, then a twinkle;
//   2 hop: a little hop, eyes squeezed with glee, a heart or two;
//   3 beam: it leans in close and beams, sparkles round it.
// Each plays once, starting and ending on the mood's resting face, with a
// cue or two.

export const notices=[
 ['perk','Heard its name','Looks up at you, surprised: oh, that\'s me!',2.0],
 ['hop','A happy hop','Hops up at its name, eyes squeezed with glee.',1.8],
 ['beam','Beams at you','Leans in close and beams, sparkles round it.',2.2]
];
export const noticeAdditions=moods.flatMap(mood=>notices.map(([action,name,caption,seconds],i)=>({
 id:`${mood}.notice.${String(i+1).padStart(2,'0')}`,mood,state:'notice',variation:i+1,action,name,caption,
 seconds:Number((seconds*Math.min(1.15,profile(mood).pace)).toFixed(3)),renderer:'notice-v1',approval:'Review candidate'
})));

// ---- Plans: [when (of the loop), pose, cue, gain] ---------------------------
const plans={
 perk:[[0,'home'],[.1,'up','swipe',.3],[.3,'up-2'],[.55,'twinkle','shimmer',.25],[.75,'blink'],[.82,'home'],[1,'home']],
 hop:[[0,'home'],[.1,'squish'],[.22,'jump','pop',.4],[.42,'glee'],[.65,'glee-2'],[.85,'home'],[1,'home']],
 beam:[[0,'home'],[.15,'lean','shimmer',.3],[.35,'close'],[.65,'close-2'],[.85,'blink'],[.92,'home'],[1,'home']]
};
export function noticePlan(a){
 return {steps:steps(a,plans[a.action]),policy:'entry',intervalSeconds:0};
}

// ---- The faces ---------------------------------------------------------------
const glee=dy=>a=>at(0,dy,sleepyFace('squeeze','wide',lineUp(a.mood)));
const faces={
 home:own(),blink:a=>ownFace(a.mood,true),
 up:own(0,-10),'up-2':own(0,-12),twinkle:own(0,-10),
 squish:own(0,6),jump:own(0,-16),glee:glee(-6),'glee-2':glee(-2),
 lean:own(0,-4),close:own(0,-6),'close-2':own(0,-5)
};
const faceFor=(a,pose)=>faces[pose](a);

// ---- What's around it --------------------------------------------------------
const props={
 perk:{up:()=>bang(40,24)+bang(274,24),'up-2':()=>bang(40,20)+bang(274,20),twinkle:()=>star(56,36,16,P.gold)+star(258,30,8,P.ink)},
 hop:{jump:()=>star(150,8,8,P.ink),glee:()=>heart(250,40),'glee-2':()=>heart(262,24,P.cheek)+heart(52,44)},
 beam:{close:()=>star(60,40,16,P.gold)+star(260,36,8,P.ink),'close-2':()=>star(264,30,16,P.gold)+star(52,48,8,P.ink)+star(240,120,8,P.amber)}
};
const propsFor=(a,pose)=>props[a.action]?.[pose]?.(a)??'';

export function renderNoticeScene(a){
 const plan=noticePlan(a),id='boop-notice-'+a.id.replaceAll('.','-');
 const art=frames(a,plan,s=>faceFor(a,s.pose),'notice-face')+frames(a,plan,s=>propsFor(a,s.pose),'notice-props');
 const still=faceFor(a,plan.steps[2].pose)+propsFor(a,plan.steps[2].pose);
 return sceneSvg(a,id,a.caption,art,still);
}
export function noticeScore(a){
 const plan=noticePlan(a),pace=profile(a.mood);
 const events=plan.steps.flatMap((s,i)=>s.effect?[{at:s.at,effect:s.effect,gain:round(s.gain*pace.gain),pitch:pace.pitch,
  label:`${a.action} · ${s.pose}`,sync:{part:'notice-props',step:i,pose:s.pose}}]:[]);
 for(const e of events)if(!effects[e.effect])throw new Error('Missing effect '+e.effect);
 return {id:a.id,seconds:a.seconds,policy:'entry',intervalSeconds:0,character:pace.character,
  description:a.caption+' A cue or two on its moments.',events,tailSeconds:round(Math.max(0,...events.map(e=>e.at+effects[e.effect].duration-a.seconds)))};
}
