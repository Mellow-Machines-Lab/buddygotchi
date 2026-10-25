import {palette as P,rect,at,star} from './visual/base.mjs';
import {newMoods} from './mood-catalog.mjs';
import {frames,sceneSvg,round,pad,slab} from './mood-art.mjs';
import {oldMoods,profile,lineUp,sleepyFace,ownFace,faceFor as wakeFace,props as wakeProps} from './wake-art.mjs';
import {moods,design,steps,own,heart} from './kit-art.mjs';
const make=design('occasion-v1');

// Occasions: variations that fit only some of the time, which the device
// turns to by itself. Each carries `when`, the tags that must all be on
// (the engine's: firmware/src/render/tags.h), or `after`, how many seconds
// the look must have shown first:
//   idle: coffee (morning), a nightcap (night), a party hat (party: a
//     milestone day, New Year's, a stage reached), Halloween's witch hat
//     and pumpkin, winter's hat and snow, Valentine's hearts, Friday's
//     shades;
//   working: coffee (morning), sweat (frantic: four agents or more), a
//     stretch five minutes into the agents' work (tier4);
//   asleep: a nightcap (night), and a dream after half an hour, the same in
//     every mood, as asleep is;
//   wake_up: the wake-up in a party hat, with confetti (party).
// Each is the mood's own face at rest with a small bob and a blink, and the
// occasion around it. The quiet looks stay silent (quiet-mix.mjs).

// Each mood's variations so far: the idle ones (excited's zoomies is a
// seventh), working's (its zoomies a sixth), asleep's four and the wake-up.
const idleN=mood=>mood==='excited'?7:6, workN=mood=>mood==='excited'?6:5;
const idles=[
 ['coffee','Morning coffee','Holds a steaming mug, sips, and blinks awake.',['morning']],
 ['nightcap','Nightcap','In a droopy nightcap with a pompom, eyes heavy.',['night']],
 ['party','Party hat','In a striped party hat, confetti drifting down.',['party']],
 ['halloween','Halloween','In a witch hat, a jack-o\'-lantern grinning beside it.',['halloween']],
 ['winter','Winter','In a red bobble hat while the snow falls.',['winter']],
 ['hearts','Valentine','Little hearts float up around it.',['valentines']],
 ['shades','Friday','Slips on its shades: it\'s Friday.',['friday']]
];
export const occasionAdditions=[
 ...moods.flatMap(mood=>idles.map(([action,name,caption,when],i)=>make(mood,'idle',idleN(mood)+1+i,action,name,caption,8*profile(mood).pace,{when}))),
 ...moods.map(mood=>make(mood,'working',workN(mood)+1,'coffee','Morning coffee','Sips from a steaming mug between keystrokes.',6*profile(mood).pace,{when:['morning']})),
 ...moods.map(mood=>make(mood,'working',workN(mood)+2,'sweat','Frantic','Sweat flies and its eyes dart: a lot is going on.',3,{when:['frantic'],sound:'routine'})),
 ...moods.map(mood=>make(mood,'working',workN(mood)+3,'stretch','A long stretch','It has been working a while: a yawn, a big stretch, back to it.',7*profile(mood).pace,{when:['tier4']})),
 // Asleep is the same in every mood.
 ...moods.map(mood=>make(mood,'asleep',5,'nightcap-sleep','Nightcap','Asleep in a nightcap, the pompom bobbing with each breath.',12,{when:['night']})),
 ...moods.map(mood=>make(mood,'asleep',6,'dream','Dreaming','A long sleep: a dream bubble of stars drifts up.',12,{after:1800})),
 ...moods.map(mood=>make(mood,'wake_up',2,'party-wake','Party morning','The wake-up in a party hat, with confetti as it pops awake.',5.6*profile(mood).pace,{when:['party']}))
];

// ---- Plans: [when (of the loop), pose] ------------------------------------
const rest=[[0,'home'],[.25,'bob'],[.45,'home'],[.62,'blink'],[.66,'home'],[.8,'bob'],[.98,'home'],[1,'home']];
const plans={
 coffee:[[0,'home'],[.2,'sip'],[.4,'sip-2'],[.55,'home'],[.7,'blink'],[.74,'home'],[.98,'home'],[1,'home']],
 sweat:[[0,'home'],[.15,'dart-left'],[.3,'dart-right'],[.45,'home'],[.6,'dart-left'],[.75,'dart-right'],[.98,'home'],[1,'home']],
 stretch:[[0,'home'],[.1,'droop'],[.2,'inhale'],[.32,'yawn'],[.45,'stretch'],[.6,'release'],[.72,'home'],[.8,'blink'],[.84,'home'],[.98,'home'],[1,'home']],
 'nightcap-sleep':[[0,'sleep'],[.25,'sleep-in'],[.5,'sleep'],[.75,'sleep-in'],[.98,'sleep'],[1,'sleep']],
 dream:[[0,'sleep'],[.2,'dream-1'],[.45,'dream-2'],[.7,'dream-3'],[.9,'sleep'],[.98,'sleep'],[1,'sleep']],
 'party-wake':[[0,'home'],[.08,'droop'],[.18,'inhale'],[.3,'yawn'],[.42,'stretch'],[.56,'release'],[.84,'awake'],[.93,'blink'],[.98,'home'],[1,'home']]
};
export function occasionPlan(a){
 return {steps:steps(a,plans[a.action]??rest),policy:'silent',intervalSeconds:0};
}

// ---- The faces ---------------------------------------------------------------
const faces={
 home:own(),bob:own(0,-3),blink:a=>ownFace(a.mood,true),sip:own(0,-2),'sip-2':own(0,-4),
 'dart-left':own(-6,0),'dart-right':own(6,0),
 sleep:()=>sleepyFace('shut','mm',0),'sleep-in':()=>at(0,-2,sleepyFace('shut','mm',0)),
 'dream-1':()=>sleepyFace('shut','mm',0),'dream-2':()=>at(0,-1,sleepyFace('shut','mm',0)),'dream-3':()=>sleepyFace('shut','mm',0),
 awake:a=>wakeFace(a,'awake')
};
function faceFor(a,pose){
 if(faces[pose])return faces[pose](a);
 return wakeFace(a,pose);  // the stretch's and the wake-up's poses
}

// ---- What's around the face --------------------------------------------------
// A mug in the lower right, steam rising (`phase` 0 or 1), or raised to sip.
function mug(x,y,phase){
 const steam=[0,1,2].map(i=>rect(x+6+i*8,y-10-((i+phase)%2)*6,4,6,P.dim)).join('');
 return steam+slab(x,y,28,26,P.amber)+rect(x+4,y+4,20,4,P.ink)+rect(x+28,y+6,8,4,P.amber)+rect(x+32,y+6,4,12,P.amber)+rect(x+28,y+16,8,4,P.amber);
}
// A droopy nightcap over the top of the face, its pompom swinging.
function nightcap(y,swing=0){
 return rect(96,y+40,128,10,P.ink)+rect(104,y+28,116,12,P.blue)+rect(118,y+16,96,12,P.blue)+rect(140,y+6,68,10,P.blue)
  +rect(200,y+4,22,8,P.blue)+rect(218+swing,y+10,10,10,P.blue)+slab(222+swing,y+18,16,16,P.ink);
}
// A striped cone with a pompom, and confetti at `phase`.
function partyHat(y=0){
 return rect(152,y+8,16,10,P.red)+rect(146,y+18,28,10,P.amber)+rect(140,y+28,40,10,P.red)+rect(134,y+38,52,10,P.amber)+rect(128,y+48,64,8,P.red)
  +slab(152,y-6,16,16,P.gold);
}
const confetti=phase=>[[30,20],[70,52],[262,28],[290,64],[48,140],[276,128]].map(([x,y],i)=>rect(x,(y+phase*14)%170,6,6,[P.red,P.amber,P.blue,P.gold][(i+phase)%4])).join('');
function witchHat(){
 return rect(150,2,20,12,P.dark)+rect(140,14,40,14,P.dark)+rect(128,28,64,14,P.dark)+rect(124,42,72,6,P.amber)+rect(96,48,128,10,P.dark);
}
function pumpkin(x,y,lit){
 const glow=lit?P.gold:P.amber;
 return rect(x+14,y-6,6,8,'#3BA55D')+slab(x,y,36,30,P.ochre)+rect(x+7,y+8,6,6,glow)+rect(x+23,y+8,6,6,glow)+rect(x+9,y+20,18,4,glow);
}
function bobble(){
 return rect(100,42,120,12,P.ink)+rect(108,24,104,18,P.red)+rect(124,12,72,12,P.red)+slab(150,-2,20,18,P.ink);
}
const snow=phase=>[[24,10],[60,40],[110,4],[200,30],[250,8],[292,44],[40,120],[280,110],[16,70],[300,150]]
 .map(([x,y])=>rect(x,(y+phase*12)%186,4,4,P.ink)).join('');
const hearts=phase=>[[40,140],[260,120],[80,40],[230,30]].map(([x,y],i)=>heart(x,(y-phase*16+180)%180,i%2?P.cheek:P.red)).join('');
// Shades over the eyes, the older moods' and the newer ones' line-ups.
function shades(a){
 const y=lineUp(a.mood);
 return rect(60,88+y,56,26,P.dark)+rect(204,88+y,56,26,P.dark)+rect(116,94+y,88,6,P.dark)+rect(66,92+y,12,4,P.ink)+rect(210,92+y,12,4,P.ink);
}
const sweat=phase=>[[56,60],[256,56],[44,92],[270,96]].map(([x,y],i)=>rect(x+(i%2?6:-6)*phase,y+phase*10,6,10,i%2?P.lightWater:P.blue)).join('')
 +rect(16,120,20,4,P.dim)+rect(284,120,20,4,P.dim);
const bubble=n=>[rect(196,134,6,6,P.dim),rect(214,116,8,8,P.dim),slab(226,40,72,64,P.dim)+rect(232,46,60,52,P.black)].slice(0,n).join('')
 +(n>2?star(262,72,16,P.gold)+star(244,56,8,P.ink)+star(282,90,8,P.ink):'');

const props={
 coffee:(a,pose)=>pose==='sip'||pose==='sip-2'?mug(200,128-(pose==='sip-2'?8:0),pose==='sip'?0:1):mug(250,140,pose==='blink'?1:0),
 nightcap:(a,pose)=>nightcap(lineUp(a.mood),pose==='bob'?4:0),
 party:(a,pose)=>partyHat(pose==='bob'?-3:0)+confetti(pose==='bob'?1:pose==='blink'?2:0),
 halloween:(a,pose)=>witchHat()+pumpkin(250,140,pose!=='blink'),
 winter:(a,pose)=>bobble()+snow(pose==='bob'?1:pose==='blink'?2:0),
 hearts:(a,pose)=>hearts(pose==='bob'?1:pose==='blink'?2:0),
 shades:(a,pose)=>pose==='blink'?shades(a):shades(a)+(pose==='bob'?star(262,70,8,P.ink):''),
 sweat:(a,pose)=>sweat(pose==='dart-left'?0:1),
 stretch:(a,pose)=>wakeProps(a,pose),
 'nightcap-sleep':(a,pose)=>nightcap(0,pose==='sleep-in'?4:0),
 dream:(a,pose)=>pose==='dream-1'?bubble(1):pose==='dream-2'?bubble(2):pose==='dream-3'?bubble(3):'',
 'party-wake':(a,pose)=>partyHat(-6)+wakeProps(a,pose)+(pose==='awake'?confetti(1)+confetti(2):'')
};
function propsFor(a,pose){
 const drawn=props[a.action];
 if(!drawn)throw new Error('Unauthored occasion '+a.action);
 return drawn(a,pose)??'';
}

export function renderOccasionScene(a){
 const plan=occasionPlan(a),id='boop-occasion-'+a.id.replaceAll('.','-');
 const art=frames(a,plan,s=>faceFor(a,s.pose),'occasion-face')+frames(a,plan,s=>propsFor(a,s.pose),'occasion-props');
 const pose=plan.steps[0].pose;
 return sceneSvg(a,id,a.caption,art,faceFor(a,pose)+propsFor(a,pose));
}
export function occasionScore(a){
 // A party wake-up's line waits until it's awake, as the wake-up's does.
 const awake=occasionPlan(a).steps.find(s=>s.pose==='awake');
 const pace=profile(a.mood);
 // Work goes on under a working occasion: soft keys through the loop, of
 // which the routine mix sounds a few, picked afresh each loop.
 const keys=a.state!=='working'?[]:Array.from({length:8},(_,i)=>({at:round((i+.5)/8*a.seconds),effect:['key','softKey','keyB','keyC'][i%4],
  gain:round(.3*pace.gain),pitch:pace.pitch,label:'Typing',sync:{part:'occasion-props',step:i,pose:null}}));
 return {id:a.id,seconds:a.seconds,policy:keys.length?'loop':'silent',intervalSeconds:0,character:pace.character,
  ...(awake?{voiceSeconds:awake.at}:{}),
  description:a.caption+(keys.length?' Soft typing under it.':' Silent: the occasion is in the picture.'),events:keys,tailSeconds:0};
}
