import {palette as P,rect,path,group,at,face,star,keycap,victoryBackground,trophy} from './visual/base.mjs';
import {closeTimelines} from './visual/loop.mjs';
import {acting,sustainedStates} from './state-catalog.mjs';
import {effects} from './audio/effects.mjs';

const GREEN='#83D99A',DEEP='#244634';
const safe=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
const n=x=>Number(x.toFixed(6));
const glyph={
 A:'01110 10001 10001 11111 10001 10001 10001',B:'11110 10001 10001 11110 10001 10001 11110',C:'01111 10000 10000 10000 10000 10000 01111',D:'11110 10001 10001 10001 10001 10001 11110',E:'11111 10000 10000 11110 10000 10000 11111',F:'11111 10000 10000 11110 10000 10000 10000',G:'01111 10000 10000 10111 10001 10001 01111',H:'10001 10001 10001 11111 10001 10001 10001',I:'11111 00100 00100 00100 00100 00100 11111',J:'00111 00010 00010 00010 10010 10010 01100',K:'10001 10010 10100 11000 10100 10010 10001',L:'10000 10000 10000 10000 10000 10000 11111',M:'10001 11011 10101 10101 10001 10001 10001',N:'10001 11001 10101 10011 10001 10001 10001',O:'01110 10001 10001 10001 10001 10001 01110',P:'11110 10001 10001 11110 10000 10000 10000',Q:'01110 10001 10001 10001 10101 10010 01101',R:'11110 10001 10001 11110 10100 10010 10001',S:'01111 10000 10000 01110 00001 00001 11110',T:'11111 00100 00100 00100 00100 00100 00100',U:'10001 10001 10001 10001 10001 10001 01110',V:'10001 10001 10001 10001 10001 01010 00100',W:'10001 10001 10001 10101 10101 10101 01010',X:'10001 10001 01010 00100 01010 10001 10001',Y:'10001 10001 01010 00100 00100 00100 00100',Z:'11111 00001 00010 00100 01000 10000 11111',
 '0':'01110 10001 10011 10101 11001 10001 01110','1':'00100 01100 00100 00100 00100 00100 01110','2':'01110 10001 00001 00010 00100 01000 11111','3':'11110 00001 00001 01110 00001 00001 11110','!':'00100 00100 00100 00100 00100 00000 00100','>':'10000 01000 00100 00010 00100 01000 10000','+':'00000 00100 00100 11111 00100 00100 00000','(':'00010 00100 01000 01000 01000 00100 00010',')':'01000 00100 00010 00010 00010 00100 01000','_':'00000 00000 00000 00000 00000 00000 11111',' ':'00000 00000 00000 00000 00000 00000 00000'
};
export function pixelText(text,x,y,size=2,color=P.ink){
 let art='';for(const [i,c]of[...text].entries())for(const [row,bits]of(glyph[c.toUpperCase()]||glyph[' ']).split(' ').entries())for(let col=0;col<5;col++)if(bits[col]==='1')art+=rect(x+(i*6+col)*size,y+row*size,size,size,color);return art;
}
const centered=(text,y,size=2,color=P.ink)=>pixelText(text,Math.round((320-(text.length*6-1)*size)/2),y,size,color);
function slab(x,y,w,h,color=P.prop){return path(`M${x+6} ${y}h${w-12}v4h6v${h-8}h-6v4H${x+6}v-4h-6V${y+4}h6Z`,color);}
function card(text,y=154,color=P.blue,width){const w=width||Math.max(104,(text.length*6-1)*2+24);return slab((320-w)/2,y,w,30,color)+centered(text,y+8,2,P.black);}
function held(text,y=154,color=P.blue){const w=Math.max(104,(text.length*6-1)*2+24);return card(text,y,color,w)+slab((320-w)/2-10,y+13,24,16,P.ink)+slab((320+w)/2-14,y+13,24,16,P.ink);}
function pad(x,y,w=28,h=16,color=P.ink){return slab(x,y,w,h,color);}
function cube(x,y,size=24,color=P.blue){return rect(x,y,size,size,color)+rect(x+4,y+4,Math.max(4,size-12),4,P.ink)+rect(x+size-5,y+6,5,size-6,P.dim);}
function paper(x,y,w=42,h=34,color=P.blue,pattern=0){return rect(x,y,w,h,P.prop)+rect(x+3,y+3,w-6,h-6,P.black)+rect(x+7,y+7,10,7,color)+rect(x+22,y+8,w-28,4,P.dim)+rect(x+7,y+20,w-14,3,color)+rect(x+7,y+27,Math.max(6,w-22-pattern*3),3,P.dim);}
function board(y=164,pressed=-1,color=P.prop){let art=slab(83,y,154,24,P.dim)+rect(88,y+4,144,16,P.black);for(let row=0;row<2;row++)for(let col=0;col<12;col++)art+=rect(91+col*12,y+5+row*8,8,5,(pressed%24===row*12+col)?P.ink:color);return art;}
function burst(x,y,stage=0,color=P.prop,count=6){let art='';for(let i=0;i<count;i++){const dx=[-1,1,-.55,.55,-1,1,0,0][i%8],dy=[-.6,-.6,-1,-1,0,0,-1,1][i%8],s=stage===0?8:stage===1?6:4;art+=rect(Math.round(x+dx*(14+stage*14)),Math.round(y+dy*(10+stage*10)+stage*3),s,s,i%3===0?P.ink:color);}return art;}
function glass(x,y,color=P.blue){return at(x,y,path('M8 0h32v8h8v32h-8v8H8v-8H0V8h8Zm4 8v4H8v24h4v4h24v-4h4V12h-4V8Z',color)+rect(38,38,10,10,color)+rect(46,46,12,12,P.prop));}
function robot(x,y,pose=0,color=P.blue,cargo=false){return at(x,y,rect(12,-6,6,7,P.dim)+slab(0,0,32,25,color)+rect(5,5,22,12,P.black)+rect(8,8,5,5,P.ink)+rect(20,8,5,5,P.ink)+rect(5,25,22,9,P.dim)+rect(pose%2?2:5,34,8,5,color)+rect(pose%2?22:19,34,8,5,color)+(pose===3?pad(29,-4,12,10):pad(-8,21,12,10))+(cargo?cube(26,20,16,P.amber):''));}
function rail(y=185){return rect(48,y,224,4,P.dim)+[64,104,144,184,224].map(x=>rect(x,y-4,8,4,P.prop)).join('');}
function arrow(x,y,color=P.blue){return at(x,y,rect(0,5,20,6,color)+rect(16,0,6,16,color)+rect(22,4,6,8,color));}

// Each step is the source of truth for BOTH a visible pose and its contact sound.
// Normalized authored key times become absolute seconds once, per performance.
export function statePlan(asset){
 const p=acting[asset.mood],steps=[];
 const add=(u,pose,effect=null,gain=.7)=>steps.push({at:n(u*asset.seconds),pose,effect,gain});
 add(0,'home');
 switch(asset.action){
  case 'start-card':case 'ready-card':case 'continue-card':case 'compact-card':
   add(.09,'lift','paper');add(.19,'reveal','latch');add(.48,'hold');add(.58,'fold','fold');add(.70,'unfold','ratchet');add(.79,'type','key');add(.85,'release','release',.4);add(.92,'home');break;
  case 'step-route':
   add(.08,'pick','paper');add(.19,'step1','wood',.55);add(.31,'step2','wood',.55);add(.43,'step3','wood',.60);add(.57,'reconsider','slide',.45);add(.68,'reorder','paper',.55);add(.80,'route','latch',.48);add(.91,'gather','paper',.4);add(.96,'home');break;
  case 'spy-console':{
   const count={happy:18,excited:24,proud:14,curious:16,determined:22,grumpy:22,sad:12}[asset.mood];
   for(let i=0;i<count;i++){const u=.075+i*.79/count;add(u,'key-'+i,asset.mood==='grumpy'&&i%6===5?'bash':asset.mood==='sad'?'softKey':['key','keyB','keyC','space'][i%4],i%4===0?.76:.55);add(u+.026,'up-'+i,'release',.28);}add(.93,'home');break;}
  case 'socket-toolbox':
   add(.10,'open','latch');add(.23,'pick','metal',.45);add(.37,'plug','latch');add(.49,'crank1','ratchet');add(.59,'crank2','ratchet');add(.69,'crank3','ratchet');add(.81,'unplug','pop',.45);add(.93,'home','wood',.4);break;
  case 'outbound-search':
   add(.10,'lens1','slide',.4);add(.22,'lens2','latch',.28);add(.34,'lens3','slide',.38);add(.45,'send','swipe',.5);add(.56,'outbound');add(.66,'incoming','paper',.5);add(.78,'catch','paper',.65);add(.88,'stack','wood',.38);add(.96,'home');break;
  case 'evidence-desk':
   add(.08,'receive','paper');add(.23,'left','slide',.4);add(.39,'right','slide',.4);add(.55,'zoom','latch',.36);add(.70,'compare','paper',.48);add(.84,'group','wood',.4);add(.94,'home','paper',.32);break;
  case 'test-gate':
   for(let i=0;i<3;i++){add(.10+i*.25,'load-'+i,'wood',.40);add(.20+i*.25,'scan-'+i,'latch',.40);add(.29+i*.25,'exit-'+i,'slide',.32);}add(.94,'home');break;
  case 'helper-hatch':
   add(.10,'open','ratchet');add(.23,'peek','pop',.5);add(.36,'one','landing',.4);add(.50,'two','landing',.42);add(.64,'three','landing',.44);add(.76,'go','swipe',.42);add(.88,'close','latch',.42);add(.96,'home');break;
  case 'helper-drill':
   add(.08,'assemble','landing',.4);add(.21,'salute','cloth',.35);add(.38,'go','paper',.5);add(.49,'march1','wood',.44);add(.59,'march2','wood',.48);add(.69,'march3','wood',.44);add(.81,'away','swipe',.4);add(.95,'home');break;
  case 'helper-courier':
   add(.12,'arrive','slide',.45);add(.27,'park','landing',.42);add(.42,'handover','paper');add(.61,'report','fold',.42);add(.81,'leave','swipe',.4);add(.95,'home');break;
  case 'helper-report':
   add(.10,'arrive','wood',.42);add(.24,'lineup','landing',.4);add(.38,'salute','cloth',.35);add(.51,'report','paper',.62);add(.73,'dismiss','cloth',.32);add(.86,'leave','slide',.4);add(.95,'home');break;
  case 'hourglass-lean':
   add(.16,'grain1');add(.33,'grain2');add(.50,'grain3');add(.67,'low');add(.78,'flip','cloth',.22);add(.89,'settle','cushion',.25);add(.96,'home');break;
  case 'answer-tray':
   add(.10,'page','paper');add(.24,'unfold','fold',.52);add(.43,'offer','slide',.58);add(.62,'present');add(.86,'withdraw','paper',.32);add(.95,'home');break;
  case 'jam-recoil':
   add(.09,'try1','ratchet',.6);add(.20,'jam1','creak',.68);add(.31,'try2','ratchet',.6);add(.39,'jam2','creak',.72);add(.49,'break','snap',.78);add(.60,'scatter','keycap',.55);add(.72,'error','failedAttempt',.62);add(.92,'home');break;
  case 'brake-settle':
   add(.08,'moving1','ratchet',.48);add(.20,'moving2','ratchet',.46);add(.34,'brake','brake',.6);add(.44,'settle','wood',.42);add(.60,'stopped','cloth',.34);add(.87,'lower','slide',.3);add(.96,'home');break;
  case 'squash-hello':
   add(.10,'contact','cushion',.66);add(.19,'squash');add(.32,'rebound','rubber',.44);add(.48,'look');add(.70,'settle','cloth',.2);add(.94,'home');break;
  case 'cushion-shield':
   add(.09,'tap1','cushion',.5);add(.18,'tap2','cushion',.53);add(.28,'tap3','cushion',.56);add(.38,'duck','cloth',.45);add(.48,'shield','rubber',.48);add(.65,'easy','paper',.4);add(.84,'peek');add(.95,'home');break;
  case 'complete-card':
   add(.08,'poise','paper',.45);add(.20,'reveal','trophyB',.9);add(.32,'burst1');add(.47,'burst2');add(.63,'hold');add(.82,'lower','cloth',.25);add(.95,'home');break;
  case 'failed-card':
   add(.10,'brace','creak',.6);add(.23,'strain','creak',.7);add(.36,'break','snap',.63);add(.46,'fallen','landing',.5);add(.55,'failed','failedAttempt',.72);add(.77,'hold');add(.90,'lower','cloth',.28);add(.97,'home');break;
  default:throw new Error('Missing state choreography: '+asset.action);
 }
 add(1,'home');
 const policy=asset.state==='waiting'?'sparse':sustainedStates.includes(asset.state)?'loop':'entry';
 return {steps,policy,intervalSeconds:asset.state==='waiting'?45:0,profile:p};
}

function backgroundDetail(asset,pose){
 if(asset.action==='spy-console'){
  const step=Math.floor(Number(pose.split('-')[1]||0)/3);let s='';
  for(let col=0;col<4;col++)for(let row=0;row<4;row++)s+=pixelText((row+col+step)%2?'1':'0',[12,36,264,288][col],12+((row*34+step*8+col*12)%120),2,row===step%4?GREEN:DEEP);
  s+=pixelText('> '+['RUN()','X++','0101','RUN()'][Math.floor(step/4)%4],106,24,2,GREEN);return s;
 }
 return '';
}
function props(a,pose){
 const m=a.mood,A=a.action,hot=m==='grumpy',home=pose==='home';let s='';
 if(A.endsWith('-card')&&['start-card','ready-card','continue-card','compact-card'].includes(A)){
  const text={ 'start-card':'NEW TASK','ready-card':'READY','continue-card':'CONTINUE','compact-card':'COMPACTED'}[A];
  if(['lift','reveal','hold','fold'].includes(pose)){s+=held(text,pose==='lift'?166:pose==='fold'?176:150,P.amber);if(pose==='reveal')s+=burst(54,166,0,P.amber,4)+burst(262,166,0,P.amber,4);}
  else if(['unfold','type','release'].includes(pose)){s+=board(164,pose==='type'?7:-1)+pad(72,pose==='type'?155:147)+pad(220,pose==='type'?155:147);s+=centered(text,22,2,P.amber);}
  else s+=slab(115,160,90,24,P.dim)+rect(145,155,30,5,P.prop);return s;
 }
 if(A==='step-route'){
  if(home||pose==='pick'||pose==='gather')return paper(133,153,54,32,P.blue)+pad(185,pose==='pick'?144:166);
  const count=pose==='step1'?1:pose==='step2'?2:3;
  for(let i=0;i<count;i++){const x=62+i*76,y=158-i*8+(pose==='reconsider'&&i===1?-18:0);s+=slab(x,y,44,30,pose==='reorder'&&i===1?P.amber:P.blue)+pixelText(String(pose==='reorder'?(i===1?3:i===2?2:1):i+1),x+17,y+8,2,P.black);if(i<count-1)s+=arrow(x+48,y+6,P.dim);}
  s+=pad(57+(count-1)*76,pose==='reconsider'?122:176,30,12);return s;
 }
 if(A==='spy-console'){
  const down=pose.startsWith('key-'),i=Number(pose.split('-')[1]||0);s+=board(164,down?(i*7)%24:-1,GREEN)+pad(84+i%3*8,down?154:146,28,14)+pad(204-i%3*8,down?149:154,28,14);
  if(hot&&down&&i%6===5){s+=burst(95,155,1,P.prop,8)+burst(228,155,1,P.prop,6)+at(38,130,keycap(16,'X'))+at(270,145,keycap(16,'E'));}
  if(m==='sad')s+=Array.from({length:9},(_,k)=>rect(84+k*17,185-(k+i)%3*3,6,6,k%2?P.water:P.blue)).join('');return s;
 }
 if(A==='socket-toolbox'){
  s+=slab(84,164,110,24,P.blue)+rect(126,171,24,6,P.black);
  if(home)return s+rect(88,156,102,8,P.prop)+rect(123,150,30,6,P.dim);
  s+=rect(84,146,10,18,P.prop)+rect(84,142,106,8,P.blue)+rect(226,152,38,36,P.dim)+rect(234,160,22,17,P.black);
  const plugged=['plug','crank1','crank2','crank3'].includes(pose);s+=cube(plugged?232:196,plugged?158:pose==='pick'?126:144,20,P.amber)+rect(plugged?214:188,plugged?164:148,18,6,P.prop);
  if(pose.startsWith('crank')){const k=Number(pose.at(-1));s+=rect(269,136,6,35,P.prop)+pad(k%2?264:254,k%2?132:154,25,14);if(hot)s+=burst(251,158,k%2,P.prop,4);}else s+=pad(195,134);return s;
 }
 if(A==='outbound-search'){
  s+=slab(126,146,66,40,DEEP)+rect(132,161,54,5,GREEN)+rect(156,150,5,32,GREEN)+rect(142,154,5,24,GREEN)+rect(174,154,5,24,GREEN);
  if(['home','lens1','lens2','lens3'].includes(pose)){const x={home:94,lens1:112,lens2:156,lens3:185}[pose];s+=glass(x,128)+pad(x+40,171);}
  if(['send','outbound'].includes(pose)){s+=paper(pose==='send'?218:266,pose==='send'?130:98,34,28,P.blue)+arrow(pose==='send'?200:242,120,P.blue);}
  if(['incoming','catch','stack'].includes(pose)){const x={incoming:248,catch:196,stack:98}[pose];s+=paper(x,150,42,32,P.amber)+paper(x+10,146,42,32,P.blue)+pad(x-8,174);}
  return s;
 }
 if(A==='evidence-desk'){
  const left=pose==='left',right=pose==='right',zoom=pose==='zoom';
  if(home)return paper(132,150,52,36,P.blue);
  s+=paper(62,left?140:152,54,36,P.blue,1)+paper(202,right?140:152,54,36,P.amber,2);
  if(zoom||['compare','group'].includes(pose)){s+=slab(132,143,54,42,P.dim)+cube(140,151,16,P.blue)+cube(160,160,16,P.amber);if(pose==='group')s+=rect(122,181,74,5,P.blue);}
  else s+=glass(left?56:right?194:120,124);
  s+=pad(left?48:right?246:146,172,26,14);return s;
 }
 if(A==='test-gate'){
  s+=rail()+rect(148,144,8,40,P.prop)+rect(196,144,8,40,P.prop)+rect(148,136,56,12,P.dim)+rect(169,139,14,6,P.amber);
  const [phase,index]=pose.split('-'),i=Number(index||0),x=phase==='scan'?164:phase==='exit'?226:76;
  s+=cube(x,160,24,i%2?P.blue:P.prop);if(phase==='scan')s+=rect(158,153,34,4,P.amber)+rect(158,176,34,4,P.amber);else s+=cube(46,170,16,P.blue);
  s+=pad(phase==='load'?65:252,phase==='load'?150:158,24,14);return s;
 }
 if(A==='helper-hatch'){
  s+=rect(66,181,190,6,P.dim);
  if(home||pose==='close')return s+slab(119,157,82,24,P.blue);
  s+=rect(116,159,12,22,P.blue)+rect(194,159,12,22,P.blue)+rect(120,152,78,8,P.prop);
  if(pose==='open')return s+burst(160,165,0,P.prop,4);
  const count={peek:1,one:1,two:2,three:3,go:3}[pose]||1;
  for(let i=0;i<count;i++)s+=robot(pose==='go'?202+i*38:pose==='peek'?144:64+i*78,pose==='peek'?164:141,i%2,P.blue,true);
  if(pose==='go')s+=centered('GO!',24,2,P.amber)+pad(240,116,36,16);return s;
 }
 if(A==='helper-drill'){
  if(home)return rect(86,182,148,5,P.dim)+rect(94,173,20,9,P.blue)+rect(154,173,20,9,P.blue)+rect(214,173,20,9,P.blue);
  const k=pose.startsWith('march')?Number(pose.at(-1)):pose==='away'?4:0;
  for(let i=0;i<3;i++)s+=robot(57+i*67+k*28,144-(k%2)*6,pose==='salute'?3:k%2,i===0?P.amber:P.blue,true);
  if(['salute','go'].includes(pose))s+=pad(258,57,28,20);
  if(['go','march1','march2','march3','away'].includes(pose))s+=centered('GO!',22,3,P.amber);return s;
 }
 if(A==='helper-courier'){
  if(home)return slab(116,180,88,7,P.dim);
  const x={arrive:24,park:72,handover:86,report:86,leave:260}[pose];s+=robot(x,143,pose==='arrive'?1:0,P.blue,pose!=='report');
  if(['handover','report'].includes(pose))s+=held('REPORT',154,P.blue);else s+=paper(x+34,152,40,28,P.amber);return s;
 }
 if(A==='helper-report'){
  if(home)return slab(100,181,120,7,P.dim);
  const dx=pose==='arrive'?-55:pose==='leave'?150:0;
  for(let i=0;i<3;i++)s+=robot(66+i*72+dx,pose==='arrive'?146-i%2*4:144,pose==='salute'?3:i%2,i===1?P.amber:P.blue);
  if(['salute','report','dismiss'].includes(pose))s+=centered('REPORT!',23,2,P.blue);
  if(pose==='report')s+=held('REPORT',152,P.blue);
  if(pose==='salute')s+=pad(260,55,28,18);return s;
 }
 if(A==='hourglass-lean'){
  const x=129,y=141; s+=rect(x-4,y,70,7,P.prop)+rect(x-4,y+40,70,7,P.prop)+path(`M${x} ${y+7}h8v8h8v8h-8v10h-8Zm54 0h8v26h-8V${y+23}h-8v-8h8Z`,P.dim);
  if(pose==='flip')s+=rect(124,162,70,7,P.amber)+pad(194,154,24,16);
  else{const amount={home:4,grain1:3,grain2:2,grain3:1,low:0,settle:4}[pose]??4;for(let j=0;j<amount;j++)s+=rect(142+j*3,152+j*4,30-j*6,4,P.amber);for(let j=0;j<4-amount;j++)s+=rect(139+j*3,178-j*4,36-j*6,4,P.amber);s+=rect(155,164+(amount%3)*3,5,5,P.amber)+pad(203,166,30,16);}
  return s;
 }
 if(A==='answer-tray'){
  s+=slab(81,180,158,7,P.dim);
  if(home)return s+paper(137,151,46,29,P.blue);
  if(['page','unfold','withdraw'].includes(pose))return s+paper(pose==='page'?144:122,pose==='page'?143:150,pose==='page'?36:76,32,P.blue)+pad(197,169);
  return s+held('ANSWER',pose==='offer'?149:154,P.blue)+arrow(263,159,P.blue);
 }
 if(A==='jam-recoil'){
  s+=rect(82,179,158,8,P.dim);
  if(['break','scatter','error'].includes(pose)){s+=cube(pose==='break'?104:75,pose==='break'?149:163,24,P.prop)+cube(pose==='break'?183:216,pose==='break'?148:160,24,P.blue);if(pose!=='error')s+=burst(164,164,pose==='break'?0:2,P.prop,8);else s+=centered('ERROR',23,3,P.red);}
  else{s+=slab(114,151,91,30,P.prop)+rect(133,159,42,12,P.black)+rect(151,143,10,34,P.blue);s+=pad(pose==='try1'||pose==='try2'?194:202,pose.startsWith('jam')?153:140);if(pose.startsWith('jam'))s+=burst(166,159,0,P.red,4);}
  return s;
 }
 if(A==='brake-settle'){
  s+=rail()+rect(259,145,7,37,P.prop)+pad(pose==='brake'||pose==='settle'?242:254,pose==='brake'||pose==='settle'?163:140,26,16,P.red);
  const delta={home:0,moving1:16,moving2:40,brake:48,settle:52,stopped:52,lower:12}[pose]||0;
  for(let i=0;i<3;i++)s+=cube(55+i*47+delta,164,20,i%2?P.prop:P.blue);
  if(['stopped','settle'].includes(pose))s+=centered('STOPPED',22,2,P.blue);return s;
 }
 if(A==='squash-hello'){
  const x={happy:45,excited:253,proud:258,curious:40,determined:145,grumpy:264,sad:62}[m],y=m==='determined'?153:135;
  if(['contact','squash'].includes(pose))s+=pad(x,y,40,22,P.blue)+burst(x+18,y+8,pose==='contact'?0:1,P.blue,4);
  if(pose==='rebound')s+=burst(x+18,y+8,2,m==='grumpy'?P.red:P.blue,4);
  if(pose==='look'&&m==='happy')s+=star(34,31,24,P.amber);
  if(pose==='look'&&m==='curious')s+=glass(247,134);
  if(pose==='look'&&m==='grumpy')s+=pad(258,145,32,16,P.prop);
  return s;
 }
 if(A==='cushion-shield'){
  if(pose.startsWith('tap')){const k=Number(pose.at(-1)),[x,y]=[[36,30],[249,91],[46,143]][k-1];return pad(x,y,38,24,P.blue)+burst(x+17,y+8,k%2,P.blue,4);}
  if(['shield','easy','peek'].includes(pose)){const y=pose==='peek'?148:116;s+=slab(79,y,162,70,m==='sad'?P.lightWater:hot?P.prop:P.blue)+rect(90,y+8,140,5,m==='sad'?P.blue:P.ink)+centered('EASY!',y+25,3,P.black)+pad(66,y+39,27,20)+pad(224,y+39,27,20);}
  return s;
 }
 if(A==='complete-card'){
  if(home||pose==='poise'||pose==='lower')return held('COMPLETE',pose==='poise'?164:154,P.amber);
  s+=held('COMPLETE',154,P.ink);
  const ctx={motion:false,ink:P.dark};s+=trophy(ctx);
  if(['reveal','burst1','burst2'].includes(pose)){const k={reveal:0,burst1:1,burst2:2}[pose];s+=burst(30,40,k,P.red,8)+burst(286,44,k,P.blue,8)+burst(30,160,k,P.ink,8)+burst(290,158,k,P.dark,8);}
  return s;
 }
 if(A==='failed-card'){
  if(['failed','hold','lower','home'].includes(pose))return held('FAILED',154,P.red)+(pose==='home'?'':cube(43,163,20,P.dim)+cube(260,169,16,P.dim));
  if(['brace','strain'].includes(pose))return rect(95,150,132,24,P.dim)+cube(126,121,24,P.prop)+cube(170,121,24,P.blue)+pad(82,174)+pad(218,174)+(pose==='strain'?path('M156 149h8v8h-8v9h8v8h-8Z',P.black):'');
  return cube(pose==='break'?89:57,pose==='break'?155:168,24,P.prop)+cube(pose==='break'?214:251,pose==='break'?149:165,20,P.dim)+burst(159,158,pose==='break'?0:2,P.dim,6);
 }
 throw new Error('Undrawn action '+A);
}

function poseOffset(asset,pose){
 const p=acting[asset.mood],m=asset.mood;
 if(pose==='home')return [0,0];
 if(['contact','squash','jam1','jam2','break','brake'].includes(pose))return [m==='grumpy'?-4:2,4];
 if(['reveal','go','rebound','one','two','three'].includes(pose))return [0,-p.lift];
 if(['duck','shield','easy'].includes(pose))return [0,10];
 if(pose==='left'||pose==='lens1')return [-5,0];
 if(pose==='right'||pose==='lens3')return [5,0];
 if(pose.startsWith('key-'))return [(Number(pose.split('-')[1])%2?1:-1)*(m==='grumpy'?3:1),m==='excited'?3:m==='sad'?2:1];
 if(m==='sad')return [0,3];
 if(m==='proud')return [2,-2];
 return [0,0];
}
function timedFrames(asset,plan,draw,merge=false){
 const {steps}=plan;
 const drawings=steps.slice(0,-1).map((step,i)=>({step,i,art:draw(step.pose)}));
 const groups=merge?[...new Set(drawings.map(d=>d.art))].map(art=>drawings.filter(d=>d.art===art)):drawings.map(d=>[d]);
 return groups.map(items=>{
  const {step,i,art}=items[0],indexes=items.map(d=>d.i);
  const times=[0,...steps.slice(1).map(e=>e.at/asset.seconds)];
  const values=steps.map((_,j)=>Number(indexes.includes(j)||j===steps.length-1&&indexes.includes(0)));
  return group(`<animate attributeName="opacity" values="${values.join(';')}" keyTimes="${times.map(n).join(';')}" dur="${asset.seconds}s" calcMode="discrete" repeatCount="indefinite"/>`+art,`opacity="${indexes.includes(0)?1:0}" data-pose="${step.pose}" data-step="${i}"`);
 }).join('');
}
function faceArt(asset,plan,motion){
 const success=asset.outcome==='success',p=plan.profile;
 const ctx={mood:asset.mood,state:'working',quiet:false,complete:false,motion,ink:success?P.dark:P.ink,bg:success?P.gold:P.black,cheek:success?'#D8576C':P.cheek,actorMotion:''};
 if(asset.outcome==='failure'){
  // Outcome must stay readable even with an excited mood: keep the eyes, restrain
  // the laughing mouth. This is a situational pose, not a silent mood change.
  ctx.mouthOverride=rect(148,134,24,6,P.ink);ctx.suppressDecor=true;
 }
 if(asset.mood==='sad'&&['waiting','poked','tap_spam','task_complete'].includes(asset.state))ctx.state='listening';
 const offsets=plan.steps.map(e=>poseOffset(asset,e.pose).join(' '));
 const anim=motion?`<animateTransform attributeName="transform" type="translate" values="${offsets.join(';')}" keyTimes="${plan.steps.map(e=>n(e.at/asset.seconds)).join(';')}" dur="${asset.seconds}s" calcMode="discrete" repeatCount="indefinite"/>`:'';
 const raw=face(ctx);
 return at(0,-12,group(anim+(motion?closeTimelines(raw,asset.seconds):raw),'data-part="state-face"'));
}
export function renderStateScene(asset){
 const plan=statePlan(asset),id='boop-v3-'+asset.id.replaceAll('.','-'),success=asset.outcome==='success';
 const ctx={motion:true,ink:P.dark};
 let back=success?closeTimelines(victoryBackground(ctx),asset.seconds):'';
 const intro=faceArt(asset,plan,true),art=back+timedFrames(asset,plan,p=>backgroundDetail(asset,p),true)+intro+group(timedFrames(asset,plan,p=>props(asset,p)),'data-part="state-action"');
 const stillPose=asset.action==='complete-card'?'hold':asset.action==='failed-card'?'failed':asset.state==='error'?'error':asset.state==='stopped'?'stopped':asset.state==='tap_spam'?'easy':asset.state==='reply_ready'?'present':asset.action==='helper-drill'?'go':asset.action==='helper-report'?'report':asset.state==='starting'?'reveal':'home';
 let finalArt=art;
 if(success)finalArt=finalArt.replace(/<(rect|path)([^>]* fill="#FFD54A"[^>]*)\/>/g,(_,tag,attrs)=>`<${tag}${attrs}><animate attributeName="fill" values="#FFD54A;#FFC94A;#FFB84A;#FFC94A;#FFD54A" keyTimes="0;0.25;0.5;0.75;1" dur="${asset.seconds}s" repeatCount="indefinite" calcMode="linear"/></${tag}>`);
 const still=(success?rect(0,0,320,192,P.gold):'')+backgroundDetail(asset,'home')+faceArt(asset,plan,false)+props(asset,stillPose);
 return `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240" id="${id}" data-mood="${asset.mood}" data-state="${asset.state}" data-action="${asset.action}" data-loop-seconds="${asset.seconds}" role="img" aria-labelledby="${id}-title ${id}-desc" shape-rendering="crispEdges" overflow="hidden"><title id="${id}-title">${safe(asset.mood+' · '+asset.name)}</title><desc id="${id}-desc">${safe(asset.caption)} Shared SVG and sound cue clock. Bottom 48 pixels reserved for host text.</desc><style>#${id} .state-still{display:none}@media(prefers-reduced-motion:reduce){#${id}:not([data-motion="on"]) .state-motion{display:none}#${id}:not([data-motion="on"]) .state-still{display:inline}}</style><defs><clipPath id="${id}-art"><rect width="320" height="192"/></clipPath></defs><rect width="320" height="240" fill="#000000"/><g clip-path="url(#${id}-art)"><g class="state-motion">${finalArt}</g><g class="state-still">${still}</g></g><g id="reserved-text-zone" data-part="reserved-text-zone"/></svg>`;
}
export function stateScore(asset){
 const plan=statePlan(asset),events=plan.steps.flatMap((s,i)=>s.effect?[{at:s.at,effect:s.effect,gain:n(s.gain*plan.profile.gain),pitch:['trophyB','failedAttempt'].includes(s.effect)?1:plan.profile.pitch,label:s.pose.replaceAll('-',' '),sync:{part:'state-action',pose:s.pose,step:i}}]:[]);
 for(const e of events)if(!effects[e.effect])throw new Error('Missing effect '+e.effect);
 const tailSeconds=n(Math.max(0,...events.map(e=>e.at+effects[e.effect].duration-asset.seconds)));
 return {id:asset.id,seconds:asset.seconds,policy:plan.policy,intervalSeconds:plan.intervalSeconds,description:'Material-specific procedural contacts; no background music or voice. '+asset.caption,character:plan.profile.character,tailSeconds,events};
}
