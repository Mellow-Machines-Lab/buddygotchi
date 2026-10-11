import {palette as P,rect,path,group,at,star,keycap} from './visual/base.mjs';
import {pixelText} from './state-art.mjs';
import {moodProfiles} from './mood-catalog.mjs';
import {sustainedStates} from './state-catalog.mjs';
import {effects} from './audio/effects.mjs';
import {protectedSoundStates} from './quiet-mix.mjs';

const green='#83D99A',deep='#244634',amberDark='#352915';
const round=x=>Number(x.toFixed(6));
const safe=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
const text=(s,x,y,k=2,c=P.ink)=>pixelText(s,x,y,k,c);
const centered=(s,y,k=2,c=P.ink)=>text(s,Math.round((320-(s.length*6-1)*k)/2),y,k,c);
const slab=(x,y,w,h,c=P.ink)=>path(`M${x+4} ${y}h${w-8}v4h4v${h-8}h-4v4H${x+4}v-4h-4V${y+4}h4Z`,c);
const pad=(x,y,w=28,h=20)=>slab(x,y,w,h,P.ink);
const cube=(x,y,s=20,c=P.blue)=>rect(x,y,s,s,c)+rect(x+4,y+4,s-8,4,P.ink)+rect(x+s-4,y+4,4,s-4,P.dim);
const card=(s,y=155,c=P.blue)=>{const w=Math.max(112,(s.length*6-1)*2+20);return slab((320-w)/2,y,w,30,c)+centered(s,y+8,2,P.black);};
const held=(s,y=155,c=P.blue)=>card(s,y,c)+pad(74,y+11,24,16)+pad(222,y+11,24,16);
const paper=(x,y,w=42,h=32,c=P.blue,pattern=0)=>rect(x,y,w,h,P.prop)+rect(x+4,y+4,w-8,h-8,P.black)+rect(x+8,y+8,8,6,c)+rect(x+20,y+8,w-28,4,c)+rect(x+8,y+20,w-16,4,c)+(pattern?rect(x+8,y+26,12,3,P.dim):'');
const board=(x=83,y=158,w=154,press=-1)=>slab(x,y,w,28,P.dim)+rect(x+4,y+4,w-8,20,P.black)+Array.from({length:20},(_,i)=>rect(x+8+(i%10)*((w-16)/10),y+7+Math.floor(i/10)*9,Math.max(5,(w-36)/10),5,i===press%20?P.ink:P.prop)).join('');
const desk=()=>rect(45,188,230,4,P.dim);
const burst=(x,y,phase=1,c=P.prop,n=8)=>Array.from({length:n},(_,i)=>{const dx=[-1,1,-.6,.6,0,-1,1,0][i%8],dy=[-.3,-.3,-1,-1,-1,.5,.5,1][i%8],s=phase>2?4:8;return rect(Math.round(x+dx*(16+phase*9)),Math.round(y+dy*(10+phase*7)),s,s,i%3?c:P.ink);}).join('');
const lens=(x,y,c=P.blue)=>at(x,y,path('M8 0h28v8h8v28h-8v8H8v-8H0V8h8Zm4 8v4H8v20h4v4h20v-4h4V12h-4V8Z',c)+rect(34,34,8,8,c)+rect(40,40,12,12,P.prop));
const robot=(x,y,phase=0,c=P.blue,cargo=false)=>at(x,y,rect(12,-5,6,5,P.dim)+slab(0,0,32,24,c)+rect(4,5,24,12,P.black)+rect(8,8,5,5,P.ink)+rect(20,8,5,5,P.ink)+rect(5,24,22,8,P.dim)+rect(phase%2?2:5,32,8,6,c)+rect(phase%2?22:19,32,8,6,c)+(phase===3?pad(29,-5,12,12):pad(-7,20,12,12))+(cargo?cube(26,20,16,P.amber):''));
const cog=(x,y,r=28,c=P.prop,phase=0)=>at(x,y,rect(-r,-r/2,r*2,r,c)+rect(-r/2,-r,r,r*2,c)+rect(-r/2,-r/2,r,r,P.black)+rect(phase%2?-5:-r/2+4,phase%2?-r/2+4:-5,10,10,c));
const plug=(x,y,c=P.prop)=>slab(x,y,34,26,c)+rect(x+34,y+4,12,5,c)+rect(x+34,y+17,12,5,c)+rect(x-18,y+10,18,6,P.dim);
const arrow=(x,y,c=P.blue)=>rect(x,y+6,24,6,c)+path(`M${x+20} ${y}h6v6h6v6h-6v6h-6Z`,c);
const bang=(x,y,c=P.amber)=>rect(x,y,16,40,c)+rect(x,y+48,16,12,c);
const folder=(x,y,w=80,h=50,c=P.dim)=>rect(x,y,30,8,c)+slab(x,y+8,w,h,c)+rect(x+8,y+16,w-16,4,P.prop);
const cup=(x,y,s=1)=>at(x,y,group(path('M0 0h56v30h-8v12H8V30H0ZM-14 4H0v7h-7v12H4v7h-18ZM56 4h14v26H52v-7h11V11h-7ZM22 42h12v15h14v8H8v-8h14Z',P.ochre)+rect(9,4,8,22,P.ink),`transform="scale(${s})"`));
const quietStates=['no_app','asleep','idle','listening','waiting'];
const typingActions=['flow-keys','split-keys','tear-type','tissue-type','umbrella-work','cautious-key','matrix','console'];

// Every retained sound comes from one of these visible contacts. No audio-only jitter.
export function moodPlan(a){
 const p=moodProfiles[a.mood],steps=[];
 const add=(t,stage,effect=null,gain=.55,extra={})=>steps.push({at:round(t),stage,effect,gain,...extra});
 if(a.state==='needs_you'){
  add(0,0);const hits=p.knocks.map((t,i)=>round(t+((a.variation-1)*.06)*(i+1)));
  hits.forEach((t,i)=>{const lead=Math.min(.13,i?(t-hits[i-1])*.30:.13),tail=Math.min(.18,i<hits.length-1?(hits[i+1]-t)*.60:.18);add(t-lead,1,null,0,{hit:i});add(t,2,'knock',p.tapGain,{hit:i});add(t+tail*.55,3,null,0,{hit:i});add(t+tail,4,null,0,{hit:i});});
  const signal=round(hits.at(-1)+.38);add(signal,5,'alertDing',.92);add(signal+.22,6);add(signal+1.08,7);add(a.seconds-.52,8);add(a.seconds-.18,0);add(a.seconds,0);
  return {steps,signal,policy:'entry',intervalSeconds:0};
 }
 const timings={calm:[0,.14,.26,.35,.46,.57,.68,.79,.93,1],engaged:[0,.09,.18,.28,.39,.50,.62,.75,.91,1],annoyed:[0,.10,.18,.34,.42,.59,.66,.80,.94,1],irritated:[0,.07,.14,.23,.29,.44,.53,.69,.89,1],whiny:[0,.13,.23,.35,.43,.59,.68,.82,.94,1],wounded:[0,.16,.23,.38,.47,.61,.69,.83,.95,1]};
 let times=[...(a.sharedQuiet?[0,.12,.23,.34,.46,.57,.68,.79,.92,1]:timings[a.mood])];
 // Different action lengths AND internal pacing: deliberate reveal, clustered work, long retreat.
 if(a.variation%3===2)times=times.map((t,i)=>i>0&&i<8?round(t*.93):t);
 if(a.variation%3===0)times=times.map((t,i)=>i>0&&i<8?round(t+(i%2?.018:-.014)):t);
 const materials={starting:['paper','fold','latch','paper','fold','slide','key','cloth'],planning:['paper','wood','slide','paper','latch','paper','fold','cloth'],terminal:['latch','key','keyB','space','keyC','key','ratchet','cloth'],tool_use:['latch','metal','latch','ratchet','ratchet','metal','slide','cloth'],searching:['slide','latch','slide','swipe','paper','paper','wood','cloth'],analyzing:['paper','slide','paper','latch','paper','wood','slide','cloth'],testing:['wood','latch','slide','wood','latch','slide','wood','cloth'],delegating:['ratchet','pop','landing','wood','wood','swipe','latch','cloth'],helper_return:['slide','landing','cloth','paper','fold','cloth','slide','cloth'],reply_ready:['paper','fold','slide','paper','latch','paper','fold','cloth'],error:['ratchet','creak','latch','snap','failedAttempt','keycap','cloth','cloth'],stopped:['brake','wood','slide','latch','paper','cloth','cloth','cloth'],poked:['cushion','rubber','cushion','cloth','rubber','cloth','cloth','cloth'],tap_spam:['cushion','cushion','cloth','cushion','rubber','cloth','cloth','cloth']};
 let sounds=materials[a.state]||['key','keyB','paper','keyC','wood','slide','key','cloth'];
 if(a.state==='working'){
  if(/paper|patch|folder|tissue|blueprint|feed|pencil|erase/.test(a.action))sounds=['paper','fold','slide','paper','snip','paper','cloth','fold'];
  if(/crank|cable|ratchet/.test(a.action))sounds=['metal','ratchet','creak','latch','ratchet','slide','latch','cloth'];
  if(/stack|garden|collect|belt|sort/.test(a.action))sounds=['wood','slide','paper','wood','latch','slide','paper','cloth'];
 }
 for(let i=0;i<times.length;i++){
  const stage=i===times.length-1?0:i;
  let effect=i>0&&i<9?sounds[i-1]:null,gain=.50;
  if(quietStates.includes(a.state))effect=null;
  if(a.state==='task_complete'){
   effect=i===4?(a.outcome==='success'?(a.variation===2?'trophyB':'trophyA'):'failedAttempt'):i===2?'paper':null;gain=i===4?.86:.32;
  }
  if(a.state==='error'){effect=i===4?'snap':i===5?'failedAttempt':i===2?'ratchet':null;gain=i===5?.78:.48;}
  add(times[i]*a.seconds,stage,effect,gain,{beat:i});
 }
 if(typingActions.includes(a.action)&&!quietStates.includes(a.state)){
  // Motion itself has little bursts and rests. Quiet mix picks a subset of these contacts.
  for(const [i,u]of[.16,.205,.237,.31,.455,.482,.518,.67,.704,.742].entries()){
   const stage=Math.min(7,Math.max(1,Math.floor(u*9)));
   add(u*a.seconds,stage,a.mood==='wounded'?'softKey':['key','keyB','keyC','space'][i%4],.53,{press:i,beat:i});
   add((u+.013)*a.seconds,stage,null,0,{press:-1,beat:i});
  }
 }
 // Hold the home pose before the seam as well as at it. SVG's float time API
 // may land just below duration, so an endpoint-only reset is not sufficient.
 add(a.seconds*.98,0);
 steps.sort((a,b)=>a.at-b.at);
 // A typed contact can coincide with an authored body pose. Merge that instant
 // into one frame (the later contact wins), never duplicate SMIL keyTimes.
 for(let i=steps.length-1;i>0;i--)if(steps[i].at===steps[i-1].at)steps.splice(i-1,1);
 return {steps,policy:quietStates.includes(a.state)?'silent':sustainedStates.includes(a.state)?'loop':'entry',intervalSeconds:0};
}

function eye(x,y,w,h,c=P.ink){const hw=(w-4)/2,hh=(h-4)/2;return slab(x,y,hw,hh,c)+slab(x+hw+4,y,hw,hh,c)+slab(x,y+hh+4,hw,hh,c)+slab(x+hw+4,y+hh+4,hw,hh,c);}
function brow(x,y,ascending,c=P.ink){return [0,1,2].map(i=>rect(x+i*12,y+(ascending?2-i:i)*3,12,4,c)).join('');}
function face(a,s,blink=false){
 const m=a.mood,quiet=a.sharedQuiet,success=a.outcome==='success',ink=success?P.dark:P.ink,bg=success?P.gold:P.black;
 let eyes='',lips='',decor='',gaze=s===0?0:[0,-3,2,-2,3,0,-1,2,0][s];
 if(quiet||blink){eyes=slab(66,88,42,6,ink)+slab(212,88,42,6,ink);lips=rect(149,123,22,4,ink);}
 else if(m==='calm'){eyes=eye(65+gaze,64,48,42,ink)+eye(207+gaze,64,48,42,ink);lips=path('M149 124h5v4h12v-4h5v8h-22Z',ink);}
 else if(m==='engaged'){eyes=eye(64+gaze*2,58,48,48,ink)+eye(208+gaze*2,58,48,48,ink);lips=rect(147,125,26,5,ink);decor=rect(62,47,24,4,ink)+rect(234,47,24,4,ink);}
 else if(m==='annoyed'){
  eyes=eye(68+4,70,40,36,ink)+eye(212+4,65,40,41,ink)+rect(70,68,43,14,bg)+rect(212,63,44,8,bg);lips=rect(147,126,27,5,ink)+rect(169,131,6,3,ink);decor=rect(71,60,39,4,ink)+rect(213,54,36,4,ink);
 }else if(m==='irritated'){
  const twitch=[2,3,5].includes(s)?4:0;eyes=eye(68,67+twitch,40,40-twitch,ink)+eye(211,62,42,44,ink)+rect(68,67+twitch,40,8,bg);lips=rect(145,125,12,5,ink)+rect(157,128,13,5,ink)+rect(170,125,5,5,ink);decor=brow(68,54,false,ink)+rect(213,51,38,5,ink)+(twitch?rect(268,69,8,4,P.red)+rect(276,77,4,8,P.red):'');
 }else if(m==='whiny'){
  eyes=eye(62,57,52,50,ink)+eye(206,57,52,50,ink);decor=brow(67,46,true,ink)+brow(211,46,false,ink)+rect(69,91,38,9,P.blue)+rect(213,91,38,9,P.blue);lips=path('M145 126h8v-5h14v5h8v9h-8v5h-14v-5h-8Z',ink)+rect(152,128,16,5,P.cheek);
  if(s>0&&s<8)for(const x of[72,222])for(let j=0;j<3;j++){const y=107+((s*10+j*17)%55);decor+=rect(x+(j%2)*8,y,j===1?4:6,j===1?4:6,[P.blue,P.lightWater,P.water][j]);}if(s===5)decor+=burst(86,162,2,P.blue,4)+burst(232,162,2,P.blue,4);
 }else if(m==='wounded'){
  eyes=eye(66,60,46,46,ink)+eye(208,60,46,46,ink);decor=brow(68,44,true,ink)+brow(212,44,false,ink)+rect(74,93,28,7,P.blue)+rect(216,93,28,7,P.blue);lips=rect(148,126,8,4,ink)+rect(156,122,12,4,ink)+rect(168,126,4,4,ink);
  if(s===3||s===6)decor+=rect(77,106+(s===6?12:0),6,6,P.lightWater); // one held tear, not sad's waterfall
 }
 if(a.outcome==='failure'||a.state==='error')lips=rect(147,126,26,5,ink); // factual result overrides a smile, never the stored mood
 const cheeks=quiet?'':rect(49,115,14,8,P.cheek)+rect(68,115,14,8,P.cheek)+rect(238,115,14,8,P.cheek)+rect(257,115,14,8,P.cheek);
 let dx=0,dy=0;
 if(s){const curves={calm:[[0,0],[0,0],[0,-1],[0,-1],[0,0],[0,-2],[0,-1],[0,0],[0,0]],engaged:[[0,0],[-2,0],[2,-2],[-2,0],[2,-2],[0,-3],[2,0],[-1,0],[0,0]],annoyed:[[0,0],[3,0],[4,1],[4,1],[-2,0],[-3,0],[3,1],[3,0],[0,0]],irritated:[[0,0],[-3,1],[3,-2],[-3,2],[4,0],[-2,-3],[3,1],[-2,0],[0,0]],whiny:[[0,0],[-3,2],[2,4],[-3,2],[3,4],[0,-2],[-2,3],[2,1],[0,0]],wounded:[[0,0],[0,2],[-3,5],[-4,6],[0,3],[2,1],[0,4],[-1,2],[0,0]]};[dx,dy]=quiet?[0,s<5?2:0]:curves[m][s];}
 if(a.state==='poked'&&s>=2&&s<=4)dy+=s===2?8:3;
 if(a.state==='tap_spam'&&s>=2&&s<=6)dy+=s%2?12:6;
 // The face and its mouth are tagged, so a renderer can find the one that shows
 // in each flip-book step (facegen's face and mouth roles; the device's talking
 // mouth), and so is the step's blink (the popover's tile blinks with it).
 return at(dx,dy,group(eyes+group(lips,'data-part="mouth"')+cheeks+decor,`data-part="face" data-face="${quiet?'shared-rest':m}"${blink?' data-blink="1"':''}`));
}

function work(a,s,press){
 const k=a.action,m=a.mood,p=press??(s*3)%20,active=s>0&&s<8,phase=Math.max(0,s-1),dx=[0,0,14,28,42,58,72,32,0][s];let art=desk();
 if(['flow-keys','split-keys','tear-type','tissue-type','umbrella-work','cautious-key'].includes(k)){
  art+=k==='split-keys'?board(39,159,106,p%10)+board(176,159,106,(p+4)%10):board(83,158,154,p);
  const padX=m==='wounded'&&[2,3].includes(s)?58:100;
  art+=pad(padX,active?148+(p%2)*5:151)+pad(195,active?153-(p%2)*5:151);
  if(k==='tissue-type')art+=slab(34,161,38,26,P.prop)+rect(44,153-(s%4)*9,16,14+(s%4)*9,P.ink)+rect(53,143-(s%4)*9,13,16,P.ink);
  if(k==='umbrella-work')art+=path('M90 138h140v-8h-12v-8h-24v-8h-68v8h-24v8H90Z',P.blue)+rect(157,138,6,28,P.prop);
  if(k==='cautious-key'&&[2,3].includes(s))art+=rect(49,145,6,6,P.blue);
  if(k==='tear-type'&&active)art+=[70,226].map(x=>[0,1,2,3].map(j=>rect(x+(j%2)*8,119+((s*11+j*13)%57),5,5,[P.blue,P.water,P.lightWater][j%3])).join('')).join('')+(s%2?burst(90,178,1,P.blue,4):'');
  return art;
 }
 if(k==='tea-desk'){art+=board(109,163,138,p)+slab(42,153,42,31,P.prop)+rect(84,158,12,18,P.prop)+rect(87,162,5,9,P.black)+rect(38,185,52,4,P.dim);if(active)art+=[0,1,2].map(i=>rect(49+i*11,145-((s*5+i*7)%22),5,5,P.dim)).join('');return art+pad(181,155+(s%2)*4);}
 if(k==='file-garden'||k==='card-sort'){art+=[65,138,211].map((x,i)=>slab(x,167,46,21,P.dim)+rect(x+5,171,36,4,P.blue)+(s>i+1?paper(x+7,148,30,30,P.blue,i):'')).join('');return art+(active?at(dx-30,-Math.min(16,s*3),paper(107,151,35,32)+pad(131,164,20,16)):'');}
 if(k==='polish-row'){art+=board(89,157,150,-1);if(active)art+=rect(60+dx*2,155,42,14,P.blue)+pad(70+dx*2,141,30,20)+[0,1,2,3].map(i=>rect(65+dx*2+i*11,176+(i%2)*4,4,4,P.dim)).join('');return art+path('M254 173h34v15h-34v-5h28v-6h-28Z',P.prop);}
 if(k==='paper-fold'){return art+folder(216,143,60,37)+(s<3?paper(109,143,84,42):s<6?at(0,s%2*3,path('M116 145h68v12h-15v12h-38v-12h-15Z',P.prop)+rect(141,146,19,16,P.blue)):paper(140+dx,152,32,28))+pad(87,154)+pad(202,154);}
 if(k==='cube-belt'){art+=rect(49,177,224,10,P.dim)+[0,1,2,3].map(i=>cube(58+((i*48+dx*2)%192),153,22)).join('');return art+slab(239,139,45,48,P.prop)+rect(244,149,30,22,P.black);}
 if(k==='cable-knit'||k==='cable-tug'){art+=[75,145,215].map((x,i)=>slab(x,159,30,26,P.dim)+rect(x+6,165,16,10,P.black)+(s>i+2?rect(x+10,141,8,27,P.blue):'')).join('');const offset=k==='cable-tug'&&s<5?(s%2?15:-10):0;return art+at(offset,0,path('M56 134h37v13h49v-19h58v14h53v-6h-47v-14h-70v19H99v-13H56Z',P.blue))+pad(41+offset,127);}
 if(k==='blueprint'){const width=s===0||s===8?36:80+s*16;return art+rect(160-width/2,142,width,42,deep)+rect(160-width/2,139,8,47,P.blue)+rect(152+width/2,139,8,47,P.blue)+(active?rect(118,150,34,21,P.blue)+rect(159,159,36,12,green)+pad(95+dx,132):'');}
 if(k==='reluctant-key'||k==='repeat-enter'){art+=board(54,166,110,p)+slab(197,145+(s%2?3:0),69,40,P.prop)+text('ENTER',203,159,1,P.black);return art+pad(active?196:144,active?128+(s%2)*13:143,40,24)+(k==='repeat-enter'&&s>2&&s<7?burst(227,169,s%2,P.prop,4):'');}
 if(k==='crooked-stack'||k==='drag-stack'){const start=k==='drag-stack'?222-dx*1.6:127;for(let i=0;i<4;i++)art+=paper(Math.round(start+(k==='crooked-stack'&&s%3===0?i*5:0)),174-i*12,66,18,P.blue,i);return art+pad(Math.round(start-26),152)+(k==='drag-stack'?rect(55,169,Math.max(4,start-55),5,P.prop):'');}
 if(k==='stuck-drawer'){const pull=[0,2,4,0,5,28,32,12,0][s];return art+slab(87,135,148,52,P.dim)+rect(95,142,132,37,P.black)+at(-pull,0,slab(104,145,130,36,P.prop)+rect(157,153,30,8,P.black)+pad(155,160,34,20));}
 if(k==='pencil-flick'||k==='red-pencil'||k==='erase-again'){
  art+=paper(99,141,120,43,P.blue);const px=k==='pencil-flick'&&s>2&&s<6?135+(s-2)*34:110+(s%4)*19;
  if(k==='erase-again')art+=slab(px,148,33,19,P.prop)+[0,1,2,3,4].map(i=>rect(105+i*20,180-(i%2)*4,4,4,P.dim)).join('');
  else art+=at(px,135+(s%3)*4,rect(0,0,9,35,k==='red-pencil'?P.red:P.amber)+path('M0 35h9l-4 8Z',P.ink));
  if(k==='red-pencil'&&active)art+=path('M120 150h4v4h4v4h4v4h4v4h4v4h-4v-4h-4v-4h-4v-4h-4v-4h-4Z',P.red)+rect(160,158,38,5,P.red);
  return art+pad(px-8,135,27,18);
 }
 if(k==='jammed-feed'){art+=slab(56,145,75,42,P.dim)+rect(64,151,58,10,P.black);for(let i=0;i<(active?s:1);i++)art+=rect(117+i*16,157+(i%2)*8,22,13,P.prop);return art+pad(223,145+(s%2)*10);}
 if(k==='ratchet-kick'||k==='pout-crank'){art+=cog(166,162,24,P.prop,s)+rect(191,157,35,8,P.dim)+pad(211,142+(s%3)*9);if(k==='ratchet-kick'&&s>2&&s<7)art+=burst(168,169,s%3,P.dim,5);return art;}
 if(k==='patch-paper'){art+=paper(94,141,62,42)+paper(164,141,62,42);if(s>2&&s<8)art+=rect(147,151,28,24,P.amber)+rect(153,157,16,12,P.prop);return art+pad(86+(s>3?35:0),144)+pad(207-(s>3?30:0),146);}
 if(k==='shield-desk'){art+=board(100,163,123,p);return art+slab(65,active?145:166,42,40,P.blue)+pad(80,159)+pad(183,153+(s%2)*4);}
 if(k==='peek-folder'){return art+board(90,164,140,p)+folder(114,active&&s<5?98:143,94,42,P.prop)+pad(101,active&&s<5?117:161)+pad(203,active&&s<5?117:161);}
 if(k==='collect-pieces'){art+=slab(128,155,66,33,P.dim)+rect(136,155,50,10,P.black);for(let i=0;i<4;i++){const x=active?Math.round([57,92,215,251][i]+(160-[57,92,215,251][i])*Math.min(.9,s/8)):[57,92,215,251][i];art+=cube(x,169-(i%2)*8,14);}return art+pad(91,154)+pad(204,154);}
 throw new Error('Unauthored working action '+k);
}

function props(a,step){
 const s=step.stage,k=a.action,active=s>0&&s<8,n=Math.min(3,Math.max(0,s-1)),dx=[0,0,18,36,54,72,90,40,0][s],c=a.outcome==='success'?P.dark:P.blue;
 if(a.state==='working')return work(a,s,step.press);
 if(a.state==='asleep'){
  if(k==='dream')return active?rect(265,67-s*4,8,8,P.dim)+(s>4?rect(282,40,4,4,P.dim):''):'';
  if(k==='resettle')return slab(85+(s>3&&s<7?6:0),150,152,24,P.dim)+rect(100,154,120,5,P.prop);
  return '';
 }
 if(a.state==='no_app')return(k==='blanket'?slab(51,143+(active?s%3:0),218,37,P.dim)+rect(61,149,198,5,P.prop):'')+at(k==='plug-rest'&&active?s%3*4:0,0,plug(137,160,P.dim));
 if(a.state==='idle'){
  if(k==='stretch'&&active)return pad(30-dx/6,115-s%3*4,30,24)+pad(260+dx/6,115-s%3*4,30,24);
  return '';
 }
 if(a.state==='listening'){
  if(k==='focus')return [0,1].map(i=>at(i?250:39,49,rect(0,0,30,5,P.blue)+rect(i?25:0,0,5,27,P.blue)+rect(0,98,30,5,P.blue)+rect(i?25:0,76,5,27,P.blue))).join('');
  if(k==='headset')return at(0,active?0:-12,rect(56,26,208,8,P.dim)+rect(48,34,8,84,P.dim)+rect(264,34,8,84,P.dim)+slab(35,82,25,46,P.blue)+slab(260,82,25,46,P.blue));
  return at(active?-s%3*3:0,0,path('M251 127h12v-12h12v-12h19v63h-19v-12h-12v-12h-12Z',P.amber)+rect(235,131,20,10,P.prop));
 }
 if(a.state==='starting'){
  const label={new_task:'NEW TASK',session:'READY',continuation:'CONTINUE',compacted:'COMPACTED'}[a.startContext];
  if(k==='placard')return(s>1&&s<7?held(label,147,P.blue):board())+(s===1?pad(80,165)+pad(213,165):'');
  if(k==='ticket')return slab(63,146,62,42,P.dim)+rect(69,150,50,9,P.black)+(active?card(label,148,P.prop)+pad(220,159):'');
  return rect(59,137,202,49,P.dim)+rect(67,142,186,39,P.black)+(active?centered(label,156,2,P.blue):'')+[0,1,2].map(i=>rect(64,139+i*11,192,7,s>i+1&&s<7?P.black:P.prop)).join('');
 }
 if(a.state==='planning'){
  if(k==='route')return [76,138,200].map((x,i)=>paper(x,147+(i===1?16:0),44,27)+text(String(i+1),x+17,154+(i===1?16:0),1,P.blue)+(s>i+2?arrow(x+44,158,P.blue):'')).join('');
  if(k==='blueprint'){const w=active?150:40;return rect(160-w/2,138,w,47,deep)+rect(155-w/2,133,10,57,P.blue)+rect(155+w/2,133,10,57,P.blue)+(active?rect(99,145,30,21,green)+rect(143,154,30,24,P.blue)+rect(188,145,30,21,green)+pad(91+dx,132):'');}
  return [68,132,196].map((x,i)=>rect(x,142,54,44,P.dim)+rect(x+5,147,44,34,P.black)+paper(x+10,151,34,24,i===1?P.amber:P.blue)).join('')+(active?at(s>3?64:0,0,paper(142,133,34,25,P.amber)):'');
 }
 if(a.state==='terminal'){
  if(k==='matrix')return board(83,159,154,step.press??s*3)+[23,277].map((x,j)=>[0,1,2,3,4].map(i=>text((i+j+s)%2?'01':'10',x,32+((i*25+s*7)%112),1,green)).join('')).join('')+pad(104,149+s%2*4)+pad(190,152-s%2*4);
  if(k==='console')return rect(50,137,220,52,deep)+rect(56,143,208,40,P.black)+text('> RUN()',65,148,2,green)+rect(65+((s*17)%175),172,10,7,green)+pad(37,162)+pad(259,162);
  return slab(46,141,67,46,P.dim)+rect(55,149,49,8,P.black)+rect(113,149,155,35,deep)+text(s%2?'0101 1010':'RUN() X++',119,154,2,green)+cog(75,177,12,P.prop,s)+pad(42,165);
 }
 if(a.state==='tool_use'){
  if(k==='toolbox')return slab(69,153,170,36,P.dim)+rect(78,159,151,24,P.black)+rect(130,143,48,10,P.prop)+(active?at(104+dx/2,123,path('M0 0h10v14h10V0h10v22H20v37H10V22H0Z',P.prop))+pad(117+dx/2,147):rect(122,166,76,8,P.prop));
  if(k==='socket')return plug(78+(active?Math.min(dx,66):0),156)+slab(221,147,40,42,P.dim)+rect(225,155,27,26,P.black)+pad(69+(active?Math.min(dx,66):0),145);
  return cog(118,159,24,P.prop,s)+cog(164,159,20,P.blue,s+1)+rect(186,155,45,8,P.dim)+pad(215,142+s%3*8);
 }
 if(a.state==='searching'){
  if(k==='globe')return slab(124,132,66,55,P.blue)+rect(152,133,8,54,P.black)+rect(130,155,54,7,P.black)+rect(137,135,4,50,P.black)+rect(173,135,4,50,P.black)+lens(65+dx,132)+(s>4&&s<8?paper(239,146,39,33):'');
  if(k==='radar')return slab(106,128,107,60,deep)+rect(154,134,6,48,green)+rect(114,158,91,5,green)+at(159,160,rect(-37+Math.min(6,s)*12,-23,5,45,green))+[0,1,2].map(i=>rect(120+i*30,144+(i%2)*25,7,7,s>i+2?P.amber:P.dim)).join('');
  return rect(122,174,65,8,P.dim)+rect(150,151,7,29,P.prop)+at(active?dx/3:0,0,rect(81,138,106,19,P.prop)+slab(179,131,31,32,P.blue)+rect(78,137,12,24,P.dim))+pad(108,156);
 }
 if(a.state==='analyzing'){
  if(k==='compare')return paper(70,143,62,43,P.blue)+paper(190,143,62,43,P.amber,1)+(active?lens(s%2?72:190,135):'');
  if(k==='lens')return paper(97,137,111,50)+lens(96+dx/2,130)+(s>3&&s<7?rect(115+dx/2,148,12,12,P.blue):'');
  return [62,138,214].map((x,i)=>slab(x,165,46,23,P.dim)+paper(x+5,147,35,32,i===1?P.amber:P.blue,i)).join('')+(active?at(dx,0,paper(65,130,30,26,P.amber)+pad(84,143,22,16)):'');
 }
 if(a.state==='testing'){
  if(k==='gate')return rect(109,133,10,54,P.amber)+rect(201,133,10,54,P.amber)+rect(109,129,102,9,P.amber)+cube(56+dx*1.8,159,24,P.blue)+rect(124,144+(s%4)*8,73,4,P.amber);
  if(k==='bench')return slab(68,154,184,34,P.dim)+[94,150,206].map(x=>rect(x,161,19,19,P.black)).join('')+rect(91,138,16,17,P.prop)+pad(81,active?132+s%2*7:126,36,19)+text('TEST',145,142,1,P.amber);
  return [0,1,2].map(i=>cube(80+i*64,151+(i===s%3?-9:0),28,P.blue)).join('')+lens(70+(s%3)*64,127,P.amber);
 }
 if(a.state==='delegating'){
  if(k==='hatch')return rect(58,184,204,7,P.dim)+[0,1,2].slice(0,n).map(i=>robot(77+i*68+(s>5?(s-5)*13:0),148,s,P.blue,true)).join('')+(s===1?rect(71,159,178,25,P.dim):'');
  if(k==='squad')return [0,1,2].map(i=>robot(69+i*74+(s>5?(s-5)*19:0),148,s===3?3:s,P.blue,true)).join('')+(s>2&&s<6?card('GO!',112,P.amber)+pad(46,50,26,23):'');
  return [0,1,2].map(i=>rect(65+i*72,132,7,35,P.dim)+rect(65+i*72,167,40,6,P.dim)+robot(70+i*72,150,s,P.blue,false)+(active?cube(70+i*72,131+(s%3)*7,14,P.amber):'')).join('');
 }
 if(a.state==='helper_return'){
  if(k==='courier')return robot(active?35+dx:26,148,s,P.blue,true)+(s>3&&s<8?held('REPORT',149):'');
  if(k==='salute')return [0,1,2].map(i=>robot(57+i*88,148,s===3||s===4?3:0,P.blue)).join('')+(s>3&&s<8?card('REPORT',109):'');
  return slab(212,129,55,51,P.blue)+rect(215,136,49,32,P.black)+rect(265,127,6,50,P.dim)+rect(271,127,18,12,active?P.amber:P.dim)+(active?held('REPORT',148):'');
 }
 if(a.state==='waiting'){
  if(k==='hourglass')return rect(242,127,40,7,P.prop)+rect(242,180,40,7,P.prop)+path('M247 134h30v9h-8v8h-8v8h8v8h8v13h-30v-13h8v-8h8v-8h-8v-8h-8Z',P.dim)+rect(258,139+(s%4)*10,7,7,P.amber);
  if(k==='chair')return slab(80,172,160,13,P.dim)+rect(90,180,8,12,P.dim)+rect(222,180,8,12,P.dim)+pad(92,160+s%2*3)+pad(201,160+s%2*3);
  return rect(266,124,5,25,P.dim)+rect(250+(s%5)*6,149,20,20,P.prop)+rect(244,123,51,5,P.dim);
 }
 if(a.state==='needs_you')return requestArt(a,step);
 if(a.state==='reply_ready'){
  if(k==='tray')return rect(67,180,186,7,P.dim)+(active?held('ANSWER',146):paper(127,151,67,32));
  if(k==='scroll'){const w=active?184:38;return rect(160-w/2,146,w,37,P.prop)+rect(152-w/2,141,9,48,P.blue)+rect(159+w/2,141,9,48,P.blue)+(active?centered('ANSWER',155,2,P.black):'');}
  return slab(87,148,145,39,P.blue)+path('M92 149h65v14h10v-14h60v5h-55v14h-20v-14H92Z',P.black)+(active?card('ANSWER',133,P.prop):'');
 }
 if(a.state==='task_complete'){
  if(a.outcome==='success'){
   const fireworks=active?[burst(42,52,s%4,P.ochre),burst(272,57,(s+2)%4,P.ochre),burst(60,145,s%3,P.cheek,5)].join(''):'';
   if(k==='cup')return fireworks+(active?cup(139,106,.75)+held('COMPLETE',155,P.dark).replaceAll(`fill="${P.black}"`,`fill="${P.gold}"`):'');
   if(k==='ribbon')return fireworks+(active?at(135,104,star(0,0,52,P.ochre)+rect(7,37,10,18,P.dark)+rect(33,37,10,18,P.dark))+card('COMPLETE',158,P.prop):'');
   return fireworks+rect(68,178,184,10,P.ochre)+rect(116,165,88,16,P.dark)+(active?cup(143,100,.6)+card('COMPLETE',143,P.prop):'');
  }
  if(k==='fallen-tower')return(s<4?[0,1,2].map(i=>cube(149,163-i*22,22,P.prop)).join(''):[cube(99,155,22,P.prop),cube(205,164,22,P.prop),cube(159,173,16,P.dim)].join(''))+(s>=4&&s<8?held('FAILED',129,P.amber):'');
  if(k==='torn-result')return paper(112-(s>3?30:0),145,47,39,P.prop)+paper(161+(s>3?30:0),145,47,39,P.prop)+(s>=4&&s<8?card('FAILED',113,P.amber):'');
  return rect(93,170,134,16,P.dim)+rect(131,150+(s>3?12:0),58,20,P.prop)+(s>=4&&s<8?held('FAILED',121,P.amber):'');
 }
 if(a.state==='error'){
  let art=k==='jam'?cog(150,162,25,P.dim,s)+rect(179,158,48,8,P.prop)+(s===4?burst(160,164,2,P.prop):''):k==='cable'?plug(94-(s>3?32:0),157)+slab(211,148,36,39,P.dim)+rect(216,158,22,19,P.black):slab(85,146,66,41,P.dim)+paper(137,150,87,34,P.amber);
  return art+(s>=4&&s<8?card('ERROR',113,P.amber):'');
 }
 if(a.state==='stopped'){
  if(k==='brake')return rect(57,179,208,10,P.dim)+cube(86+(s<4?s*18:54),155,23)+pad(201,s<4?144:163)+(s>3&&s<8?card('STOPPED',121,P.prop):'');
  if(k==='lid')return board(83,158,154,-1)+(active?rect(83,139+s*4,154,Math.max(4,48-s*4),P.dim):'');
  return rect(191,128,7,59,P.prop)+card('STOPPED',131,P.prop)+slab(69+Math.min(3,s)*10,169,81,16,P.dim);
 }
 if(a.state==='poked'){
  if(k==='squash')return active?slab(142,137,36,24,P.prop)+(s<5?burst(158,143,Math.min(s,3),P.dim,4):''):'';
  if(k==='peek')return active?slab(s%2?22:260,78,37,29,P.prop):'';
  return active?pad(220-dx/3,115-(s%3)*6,44,36)+(s===4?burst(225,132,1,P.blue,4):''):'';
 }
 if(a.state==='tap_spam'){
  const impacts=active?slab(s%2?24:254,56+(s%3)*27,40,32,P.prop)+burst(s%2?46:273,83+(s%3)*27,1,P.dim,4):'';
  if(k==='shield')return impacts+(active?slab(72,123,176,65,P.blue)+card('EASY!',139,P.prop):'');
  if(k==='duck')return impacts+(s>3&&s<8?card('EASY!',155,P.prop):'');
  return impacts+(active?rect(21,41,105+(s%2)*22,126,P.blue)+rect(193-(s%2)*22,41,106,126,P.blue)+rect(21,35,278,7,P.dim)+card('EASY!',150,P.prop):'');
 }
 throw new Error('Unauthored state '+a.state);
}

function requestArt(a,step){
 const s=step.stage,p=moodProfiles[a.mood],i=step.hit||0;
 let art=rect(122,15,76,6,P.amber)+[0,1,2].map(j=>rect(140+j*16,26,8,8,P.amber)).join(''); // persistent pending indicator
 if(s>=1&&s<=4){
  const locations={calm:[[66,74],[229,83]],engaged:[[66,67],[231,87],[145,54]],annoyed:[[229,82],[76,84],[227,82]],irritated:[[57,74],[238,60],[74,116],[220,99]],whiny:[[88,117],[207,121],[139,132]],wounded:[[83,121],[209,121]]};
  const [x,y]=locations[a.mood][i%locations[a.mood].length],offset=s===1?12:s===2?0:s===3?4:8;
  if(a.action==='card-knock')art+=at(x-26,y-13+offset,slab(0,0,68,42,P.prop)+text('ASK',15,12,2,P.black)+pad(-9,21,22,20));
  else art+=pad(x-19,y-10+offset,a.mood==='irritated'?46:38,a.mood==='wounded'?26:30);
  if(s===2||s===3)art+=burst(x,y+7,s===2?1:2,a.mood==='irritated'?P.amber:P.blue,6);
 }
 if(s>=5&&s<=8){
  const shift=s===8?-132:0;
  if(a.action==='bell-pull')art+=at(0,shift,rect(247,37,6,73,P.prop)+pad(232,87,35,28)+path('M138 41h44v15h24v17h14v54h16v18H84v-18h16V73h14V56h24Z',P.amber)+rect(149,145,22,12,P.prop)+(s===5?burst(159,109,3,P.amber):''));
  else art+=at(0,shift,slab(45,43,230,137,amberDark)+rect(45,43,230,8,P.amber)+bang(70,71,P.amber)+text(a.action==='card-knock'?'YOU':'ASK',121,75,4,P.amber)+rect(122,120,102,6,P.prop)+rect(122,136,69,6,P.prop));
 }
 return art;
}

function background(a,s){
 if(a.outcome!=='success')return '';
 // Slow tone shifts and traveling coarse tiles, not a full-screen strobe.
 const colors=[P.gold,'#FFD14A','#FFC54A','#FFBA4A','#FFC54A','#FFD14A',P.gold,'#FFD84A',P.gold];
 return rect(0,0,320,192,colors[s])+[0,1,2,3,4].map(i=>rect(((i*76+s*12)%380)-30,13+(i%3)*48,36,9,'#EDAE26')).join('');
}
function frames(a,plan,draw,part){
 const drawings=plan.steps.slice(0,-1).map((step,i)=>({art:draw(step),i})),unique=[...new Set(drawings.map(x=>x.art))];
 return group(unique.map(art=>{
  const indexes=drawings.filter(d=>d.art===art).map(d=>d.i);
  const values=plan.steps.map((_,i)=>Number(indexes.includes(i)||i===plan.steps.length-1&&indexes.includes(0)));
  return group(`<animate attributeName="opacity" values="${values.join(';')}" keyTimes="${plan.steps.map(x=>round(x.at/a.seconds)).join(';')}" dur="${a.seconds}s" repeatCount="indefinite" calcMode="discrete"/>`+art,`opacity="${indexes.includes(0)?1:0}" data-step="${indexes.join(',')}"`);
 }).join(''),`data-part="${part}"`);
}
export function renderMoodScene(a){
 const plan=moodPlan(a),id='boop-v4-'+a.id.replaceAll('.','-');
 const art=frames(a,plan,e=>background(a,e.stage),'mood-background')+frames(a,plan,e=>face(a,e.stage,e.stage===8),'mood-face')+frames(a,plan,e=>props(a,e),'mood-action');
 const stillStep={stage:a.state==='needs_you'?6:a.state==='task_complete'||a.state==='error'?5:0};
 const still=background(a,stillStep.stage)+face(a,0)+props(a,stillStep);
 return `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240" id="${id}" data-mood="${a.mood}" data-state="${a.state}" data-action="${a.action}" data-loop-seconds="${a.seconds}" data-text-top="192" role="img" aria-labelledby="${id}-title ${id}-desc" shape-rendering="crispEdges" overflow="hidden"><title id="${id}-title">${safe(a.mood+' · '+a.name)}</title><desc id="${id}-desc">${safe(a.caption+' '+moodProfiles[a.mood].character)} Loopable pixel animation; procedural synchronized SFX; bottom 48 pixels reserved for host text.</desc><defs><clipPath id="${id}-clip"><rect width="320" height="192"/></clipPath></defs><style>#${id} .still{display:none}@media(prefers-reduced-motion:reduce){#${id}:not([data-motion="on"]) .motion{display:none}#${id}:not([data-motion="on"]) .still{display:inline}}</style><rect width="320" height="240" fill="#000000"/><g clip-path="url(#${id}-clip)"><g class="motion">${art}</g><g class="still">${still}</g></g><g data-part="reserved-text-zone"/></svg>`;
}
export function moodScore(a){
 const plan=moodPlan(a),profile=moodProfiles[a.mood];
 const events=plan.steps.flatMap((s,i)=>s.effect?[{at:s.at,effect:s.effect,gain:round(s.gain*(['needs_you','task_complete','error'].includes(a.state)?1:profile.gain)),pitch:['alertDing','trophyA','trophyB','failedAttempt'].includes(s.effect)?1:profile.pitch,label:s.effect==='alertDing'?'Ding · request revealed':`${a.action} · contact ${i}`,sync:{part:'mood-action',step:i,pose:'stage-'+s.stage}}]:[]);
 for(const e of events)if(!effects[e.effect])throw new Error('Missing effect '+e.effect);
 return {id:a.id,seconds:a.seconds,policy:plan.policy,intervalSeconds:plan.intervalSeconds,character:profile.character,description:a.caption+' Sparse code-generated material effects, no speech or music bed.',events,tailSeconds:round(Math.max(0,...events.map(e=>e.at+effects[e.effect].duration-a.seconds)))};
}
// When speech may enter over a scene, in seconds: .12 s after its last
// attention cue ends for needs_you, task_complete and error, else .45 s.
// The quiet mix keeps those states' cues, so the score may be mixed or not.
export function voiceStart(state,score){
 return protectedSoundStates.includes(state)?Math.max(0,...score.events.map(e=>e.at+effects[e.effect].duration))+.12:.45;
}
export function voiceWindows(a){
 const start=voiceStart(a.state,moodScore(a)),protectedScene=protectedSoundStates.includes(a.state);
 return {suggested: true,duckRoutineSfx:!protectedScene,earliestEntry:round(start),latestExit:round(a.seconds-.25),fitsWithinCycle:start<a.seconds-.25,note:'Candidate entry/exit bounds, not a generated recording. If the take does not fit, extend the host hold or follow after the animation; never speed up speech to force it.'};
}
