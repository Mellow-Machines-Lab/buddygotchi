import {moods,states,palette,label,rect,path,block,group,at,move,opacity,frames,star,eyePose,mouth,face,keyboardBase,work,request,trophy,celebration,victoryBackground,listening,disconnected,splash,tears,flood,dustPuff,flyingKeys,keycap} from "./base.mjs";
import {workRecipes,requestBeats,completeBeats,listeningBeats} from "./performances.mjs";
import {sceneSpecs,drawWorkScene,requestScene,completionScene,listeningScene,grumpyActing} from "./scenes.mjs";
import {loopSpec,closeTimelines} from "./loop.mjs";

const safe=s=>String(s).replaceAll("&","&amp;").replaceAll('"',"&quot;").replaceAll("<","&lt;");
const five="0;0.18;0.4;0.66;1";
const act=(ctx,poses,seconds=4,repeat="indefinite")=>move(ctx,poses,seconds,five,repeat);
const show=(ctx,art,values="0;1;1;0;0",seconds=4,repeat="indefinite")=>group(opacity(ctx,values,seconds,five,repeat)+art,`opacity="${values[0]}"`);
const cornerTears=()=>rect(79,110,5,5,palette.blue)+rect(232,110,5,5,palette.lightWater);

function tile(x,y,w=40,h=24,color=palette.dim) {
  return at(x,y,rect(0,0,w,h,color)+rect(3,3,w-6,h-6,palette.black)+rect(7,7,6,6,palette.prop)+rect(17,7,w-24,3,palette.dim)+rect(17,13,w-24,3,palette.dim));
}
function focus(x,y,w,h,color=palette.blue) {
  return at(x,y,path(`M0 7V0h7v3H3v4ZM${w-7} 0h7v7h-3V3h-4ZM0 ${h-7}h3v4h4v3H0ZM${w-3} ${h-7}h3v7h-7v-3h4Z`,color));
}
function effectSquares(ctx,x,y,color=palette.amber,seconds=3.2) {
  return at(x,y,group(act(ctx,"0 0;0 -3;0 -7;0 -10;0 0",seconds,ctx.complete?"1":"indefinite")+(ctx.complete?opacity(ctx,"1;1;1;0;0",seconds,five,"1"):"")+rect(0,0,4,4,color)+rect(11,-6,3,3,color)+rect(-10,-4,3,3,color)));
}
function music(ctx) {
  const note=rect(6,0,3,16,ctx.cheek)+rect(9,0,7,4,ctx.cheek)+rect(0,12,6,6,ctx.cheek);
  return group(at(31,158,group(move(ctx,"0 0;2 -6;-2 -14;1 -23;0 0",3.2,five)+note))+
    at(271,164,group(move(ctx,"0 -15;-2 -23;0 0;2 -7;0 -15",3.2,five)+note)),'data-part="singing-notes"');
}
function breath(ctx,seconds=4,color=palette.prop) {
  const squares=rect(0,0,5,5,color)+rect(8,-3,4,4,color)+rect(15,1,3,3,color);
  return at(189,144,show(ctx,group(act(ctx,"0 0;0 0;9 -3;20 -5;0 0",seconds)+squares),"0;1;1;0;0",seconds));
}
function tearTreatment(ctx,mode="sparse") {
  if(mode==="none")return "";
  if(mode==="corners")return cornerTears();
  if(mode==="flick")return cornerTears()+at(80,112,show(ctx,group(act(ctx,"0 0;0 0;-13 17;-22 33;0 0",4.4)+rect(0,0,7,7,palette.blue)),"0;1;1;0;0",4.4));
  if(mode==="lens")return cornerTears()+at(70,84,group(
    move(ctx,"0 0;0 0;2 16;-12 51;0 0",4.8,five)+
    opacity(ctx,"1;1;1;0;1",4.8,five)+rect(0,0,24,24,palette.water)+rect(3,3,7,7,palette.lightWater)+rect(17,16,4,4,palette.blue),'data-part="big-tear"'));
  return tears({...ctx,state:"listening"});
}
function workProp(ctx,r) {
  const cycle=r.seconds;
  let art="";
  if(r.prop==="chaos")return group(work(ctx),'data-part="working-prop"');
  if(["keyboard","flood","double-keyboard"].includes(r.prop)) {
    const bounce=ctx.mood==="grumpy"?"-3 0;3 3;-3 1;3 4;-3 0":ctx.mood==="excited"?"0 0;0 2;0 0;0 2;0 0":"0 0;0 1;0 0;0 1;0 0";
    art+=group(act(ctx,bounce,ctx.mood==="grumpy"?.6:ctx.mood==="excited"?.8:1.6)+keyboardBase(ctx),'data-part="keyboard"');
    if(r.prop==="flood")art+=flood(ctx);
    if(r.prop==="double-keyboard")art+=group(act(ctx,"-6 0;6 0;-6 0;6 0;-6 0",.48)+rect(97,171,12,4,palette.ink)+rect(169,181,12,4,palette.ink)+rect(205,171,12,4,palette.ink));
  } else if(r.prop==="tiles") {
    for(const [i,x]of[95,142,189].entries())art+=at(x,177,group(move(ctx,`${(i-1)*9} ${i%2?8:-3};0 0;0 0;${(1-i)*6} 3;${(i-1)*9} ${i%2?8:-3}`,cycle,five)+tile(0,0,36,24)));
    art+=at(93,173,group(act(ctx,"0 0;47 0;94 0;47 0;0 0",cycle)+focus(0,0,40,32)));
  } else if(r.prop==="rows") {
    art+=rect(107,172,106,30,palette.dim)+rect(110,175,100,24,palette.black);
    for(let i=0;i<3;i++)art+=rect(125,177+i*7,74-i*8,3,palette.prop);
    art+=at(115,176,group(move(ctx,"0 0;0 7;0 14;0 7;0 0",cycle,five)+rect(0,0,4,4,palette.blue)));
  } else if(r.prop==="compare") {
    art+=tile(102,176,42,27)+tile(176,176,42,27);
    art+=group(act(ctx,"0 0;0 0;74 0;74 0;0 0",cycle)+focus(99,173,48,33));
  } else if(r.prop==="cursor") {
    art+=focus(103,171,115,34,palette.dim)+rect(122,187,32,3,palette.dim)+rect(172,179,19,3,palette.dim);
    art+=at(118,177,group(act(ctx,"0 0;65 1;80 18;15 18;0 0",cycle)+rect(0,0,6,6,palette.blue)));
  } else art+=tile(119,175,82,28)+focus(115,171,90,36);
  return group(art,'data-part="working-prop"');
}
function workEffect(ctx,r) {
  const s=r.seconds;
  switch(r.fx){
    case"music":return music(ctx);
    case"twinkle":return at(271,161,show(ctx,star(0,0,16,palette.amber),"0;1;0;0;0",s));
    case"speed":return group(act(ctx,"0 0;3 0;0 0;-3 0;0 0",.6)+[52,63,250,261].map((x,i)=>rect(x,176+i%2*8,4,4,palette.prop)).join(""));
    case"big-key":return at(154,179,show(ctx,group(act(ctx,"0 0;0 -2;0 6;0 -3;0 0",s)+keycap(16,"E")),"0;1;1;0;0",s))+at(157,164,show(ctx,star(0,0,8,palette.amber),"0;0;1;0;0",s));
    case"turn-tick":return at(278,135,show(ctx,rect(0,0,5,5,palette.amber)+rect(7,-7,4,4,palette.amber),"0;1;0;0;0",s));
    case"spring":return show(ctx,rect(74,171,5,5,palette.amber)+rect(74,181,5,5,palette.amber)+rect(243,171,5,5,palette.amber)+rect(243,181,5,5,palette.amber),"0;0;1;0;0",s);
    case"key-arc":return at(224,172,show(ctx,group(act(ctx,"0 0;-9 -13;-25 -19;-43 -8;0 0",s)+star(0,0,8,palette.amber)),"0;1;1;0;0",s));
    case"straighten":return show(ctx,rect(88,206,143,3,palette.blue),"0;0;1;0;0",s);
    case"blush":return show(ctx,rect(49,138,4,4,ctx.cheek)+rect(58,138,4,4,ctx.cheek)+rect(260,138,4,4,ctx.cheek)+rect(269,138,4,4,ctx.cheek),"0;0;1;1;0",s);
    case"crooked-key":return at(183,174,group(act(ctx,"0 0;0 0;5 -12;3 -3;0 0",s)+keycap(16,"E")));
    case"glass":return at(224,167,group(act(ctx,"0 0;-10 -4;-10 -4;0 0;0 0",s)+focus(0,0,24,24,palette.blue)+rect(23,21,5,5,palette.prop)+rect(27,25,5,5,palette.prop)));
    case"idea":return at(271,63,show(ctx,star(0,0,16,palette.amber),"0;1;1;0;0",s));
    case"brackets":return focus(74,170,172,31,palette.blue);
    case"pressure":return show(ctx,rect(76,174,4,4,palette.blue)+rect(242,174,4,4,palette.blue)+rect(77,185,4,4,palette.blue)+rect(241,185,4,4,palette.blue),"0;0;1;1;0",s);
    case"breath":return breath(ctx,s,ctx.mood==="sad"?palette.blue:palette.prop);
    case"catapult":return flyingKeys(ctx)+at(247,181,group(act(ctx,"0 0;8 -22;16 -10;8 14;0 0",s)+keycap(24,"E")));
    case"dust-storm":return flyingKeys(ctx)+[75,115,160,208,240].map((x,i)=>dustPuff(x,183,ctx,i%2)).join("");
    case"accuse":return at(232,170,show(ctx,group(act(ctx,"0 0;-4 -6;0 0;5 9;0 0",s)+keycap(16,"X")),"0;0;1;1;0",s));
    case"huff":return breath(ctx,s)+flyingKeys(ctx);
    case"sob":return show(ctx,rect(53,149,4,4,palette.blue)+rect(266,149,4,4,palette.blue),"0;1;0;1;0",s);
    default:return "";
  }
}
const glyphs={M:["10001","11011","10101","10101","10001","10001","10001"],W:["10001","10001","10001","10101","10101","11011","10001"],H:["10001","10001","10001","11111","10001","10001","10001"],A:["01110","10001","10001","11111","10001","10001","10001"]};
function comicText(text,size,color) {
  let art="";let x=0;
  for(const letter of text){for(const [row,line]of glyphs[letter].entries())for(let col=0;col<line.length;col++)if(line[col]==="1")art+=rect(x+col*size,row*size,size,size,color);x+=6*size;}
  return at(Math.floor((320-(x-size))/2),176,art);
}
function cackle(ctx) {
  if(!ctx.motion)return group(comicText("MWHAHAHA",4,ctx.ink),'data-part="comic-cackle"');
  return group([1,2,3,4].map((size,i)=>{
    const values=[0,0,0,0,0,0];values[i+1]=1;
    return group(opacity(ctx,values.join(";"),4.8,"0;0.1;0.27;0.45;0.65;1","1")+comicText("MWHAHAHA",size,ctx.ink),`opacity="0" data-size="${size}"`);
  }).join(""),'data-part="comic-cackle"');
}
function resultCard(ctx,variant) {
  if(ctx.mood==="proud"&&variant===2)return cackle(ctx);
  const y=183;
  let card=rect(0,0,54,23,ctx.ink)+rect(4,4,46,15,palette.ink)+rect(10,8,32,3,palette.dim)+rect(10,14,21,2,palette.dim);
  const entrance=variant===1?"0 14;0 8;0 0;0 0;0 0":variant===2?"24 0;12 0;0 0;0 0;0 0":"0 0;-3 0;3 0;0 0;0 0";
  return at(133,y,group(act(ctx,entrance,2.8,"1")+card,'data-part="result-card"'));
}
function makeContext(mood,state,variant) {
  const quiet=["asleep","no_app"].includes(state),complete=state==="task_complete";
  return {mood:quiet?"happy":mood,state,variant,quiet,complete,motion:true,ink:complete?palette.dark:palette.ink,bg:complete?palette.gold:palette.black,cheek:complete?"#D8576C":palette.cheek};
}
function drawing(input) {
  const ctx={...input},n=ctx.variant,m=ctx.mood,s=ctx.state;
  let art="";
  if(s==="working") {
    const r={...workRecipes[m][n-1],seconds:sceneSpecs[m][n-1][3]};
    ctx.actorMotion=m==="grumpy"&&n>1?grumpyActing(ctx):act(ctx,r.beat,r.seconds);
    ctx.gazeMotion=r.gaze?act(ctx,r.gaze,r.seconds):"";
    ctx.suppressDecor=["music","blush"].includes(r.fx);
    // Sad works in its own pouring tears, which face() draws, but in its third.
    if(m==="sad"&&n===3)ctx.tearOverride=tearTreatment(ctx,"corners");
    if(r.mouth==="sing")ctx.mouthOverride=frames(ctx,[mouth(ctx),block(154,128,12,14,ctx.ink),mouth(ctx),block(155,128,10,10,ctx.ink)],3.2,"singing-mouth");
    art=face(ctx)+drawWorkScene(ctx);
  } else if(s==="needs_you") {
    ctx.actorMotion=act(ctx,requestBeats[m][n-1],n===1?2.4:3.4,"1");
    ctx.gazeMotion=act(ctx,n===1?"0 0;-4 -3;3 -1;0 0;0 0":n===2?"0 0;3 2;-3 -2;0 0;0 0":"-3 2;-3 2;3 -3;0 0;0 0",3.4,"1");
    ctx.tearOverride=tearTreatment(ctx,n===1?"flick":"corners");
    art=face(ctx)+request({...ctx,motion:false})+requestScene(ctx);
  } else if(s==="task_complete") {
    ctx.actorMotion=act(ctx,completeBeats[m][n-1],4.2,"1");
    ctx.gazeMotion=act(ctx,n===1?"0 0;0 2;0 2;3 -1;0 0":n===2?"-3 0;3 1;3 1;0 -1;0 0":"0 2;0 2;-2 1;0 -1;0 0",4.2,"1");
    ctx.tearOverride=tearTreatment(ctx,n===1?"flick":"corners");
    if(m==="proud"&&n===2)ctx.mouthOverride=group(opacity(ctx,"1;0;1;0;1",4.8,five,"1")+mouth(ctx))+show(ctx,block(143,130,34,16,ctx.ink),"0;1;0;1;0",4.8,"1");
    art=(n===1?celebration(ctx):victoryBackground(ctx))+face(ctx)+completionScene(ctx)+(m==="proud"&&n===2?cackle(ctx):"");
  } else if(s==="listening") {
    ctx.actorMotion=act(ctx,listeningBeats[m][n-1],4,"1");
    ctx.gazeMotion=n===2?act(ctx,"4 0;4 0;1 0;0 0;0 0",4,"1"):n===3?act(ctx,"-3 1;-3 1;0 0;0 0;0 0",3,"1"):"";
    ctx.tearOverride=tearTreatment(ctx,n===3?"flick":"corners");
    ctx.suppressDecor=true;
    art=face(ctx)+listeningScene(ctx)+listening(ctx);
  } else if(s==="idle") {
    ctx.actorMotion=n===3?act(ctx,"0 0;0 -4;0 3;0 1;0 0",9):"";
    ctx.gazeMotion=n===2?act(ctx,"0 0;-5 0;0 0;5 0;0 0",10):"";
    ctx.tearOverride=cornerTears();ctx.suppressDecor=true;
    art=face(ctx);
  } else {
    ctx.actorMotion=n===1?act(ctx,"0 0;0 -1;0 -2;0 -1;0 0",9):n===2?act(ctx,"0 0;0 0;-2 1;0 0;0 0",10):act(ctx,"0 0;0 4;3 4;2 1;0 0",12);
    if(n===2){
      const open=eyePose(ctx),twitch=s==="asleep"?block(68,95,40,3,ctx.ink)+block(212,93,40,5,ctx.ink):block(68,99,40,3,ctx.ink)+block(212,99,40,3,ctx.ink);
      ctx.eyeOverride=group(opacity(ctx,"1;0;1;1",10,"0;0.45;0.49;1")+open)+group(opacity(ctx,"0;1;0;0",10,"0;0.45;0.49;1")+twitch,'opacity="0"');
    }
    art=face(ctx)+(s==="no_app"?disconnected(ctx):at(271,65,path("M0 0h12v3H8v3H4v3h8v3H0V9h4V6h4V3H0Z",palette.dim)));
  }
  return ctx.complete&&ctx.motion?art.replace(/<(rect|path)([^>]* fill="#FFD54A"[^>]*)\/>/g,(_,tag,attrs)=>`<${tag}${attrs}><animate attributeName="fill" values="#FFD54A;#FFC94A;#FFB84A;#FFC94A;#FFD54A" keyTimes="0;0.25;0.5;0.75;1" dur="6.4s" repeatCount="indefinite" calcMode="linear"/></${tag}>`):art;
}
export function renderVariation(mood,state,variant,name="",options={}) {
  if(!moods.includes(mood)||!states.includes(state)||!Number.isInteger(variant)||variant<1||variant>(state==="working"?5:3))throw new Error("Invalid internal asset key");
  const ctx=makeContext(mood,state,variant),id=`boop-var4-${mood}-${state}-${variant}`;
  const loop=loopSpec(mood,state,variant,state==="working"?sceneSpecs[mood][variant-1][3]:null);
  ctx.loopSeconds=loop.seconds;
  const repeatCount=options.repeatCount??loop.default_repeat_count;
  const title=`${label(mood)} · ${label(state)} · ${name||variant}`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240" id="${id}" data-mood="${mood}" data-state="${state}" data-variant="${variant}" data-loop-seconds="${loop.seconds}" data-repeat-count="${repeatCount}" role="img" aria-labelledby="${id}-title ${id}-desc" shape-rendering="crispEdges" overflow="hidden"><title id="${id}-title">${safe(title)}</title><desc id="${id}-desc">Silent seamless-loop pixel-art variation. ${loop.seconds} seconds per cycle. ${ctx.quiet?"Shared quiet performance; mood ignored.":"Uses the approved V4 face identity."}</desc><style>#${id} .boop-still{display:none}@media(prefers-reduced-motion:reduce){#${id}:not([data-motion="on"]) .boop-motion{display:none}#${id}:not([data-motion="on"]) .boop-still{display:inline}}</style><defs><clipPath id="${id}-bounds"><rect width="320" height="240"/></clipPath></defs><rect width="320" height="240" fill="${ctx.bg}"/><g clip-path="url(#${id}-bounds)"><g class="boop-motion">${closeTimelines(drawing(ctx),loop.seconds,repeatCount)}</g><g class="boop-still">${drawing({...ctx,motion:false})}</g></g></svg>\n`;
}
