// Boop V4: big-eyed minimal faces and a square-particle effects language.
// Pixel geometry + discrete SMIL animation. No runtime dependencies or audio.
export const moods = ["happy", "excited", "proud", "curious", "determined", "grumpy", "sad"];
export const states = ["idle", "working", "needs_you", "task_complete", "listening", "asleep", "no_app"];
export const palette = { ink: "#F8F7EF", black: "#000000", cheek: "#F1787D", blue: "#71B7F5", water: "#3597E4", lightWater: "#BEE9FF", amber: "#F4BC50", red: "#FF596C", dim: "#757568", prop: "#B6B6A5", gold: "#FFD54A", dark: "#302338", ochre: "#EDAE26" };
export const label = text => text.replaceAll("_", " ").replace(/\b\w/g, c => c.toUpperCase());
const esc = text => String(text).replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll("<", "&lt;");
const rect = (x, y, w, h, fill = palette.ink) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${fill}"/>`;
const path = (d, fill = palette.ink) => `<path d="${d}" fill="${fill}"/>`;
const block = (x, y, w, h, fill = palette.ink) => path(`M${x+1} ${y}h${w-2}v1h1v${h-2}h-1v1H${x+1}v-1h-1V${y+1}h1Z`, fill);
const group = (art, attrs = "") => `<g${attrs ? " " + attrs : ""}>${art}</g>`;
const at = (x, y, art) => group(art, `transform="translate(${x} ${y})"`);
// A part of the mood's resting face, tagged where it's drawn, for the
// device's rig face to draw in its place: an eye, open or shut (eye-l,
// eye-r, shut-l, shut-r), the mouth or the cheeks, its art drawn `x`, `y` px
// from where the resting face draws it, before what moves it.
const part = (name, art, x = 0, y = 0) => group(art, `data-part="${name}" data-at="${x},${y}"`);
function animate(ctx, attribute, values, seconds, times, repeat = "indefinite", begin = 0) {
  if (!ctx.motion) return "";
  return `<animate attributeName="${attribute}" values="${values}" keyTimes="${times}" dur="${seconds}s" begin="${begin}s" repeatCount="${repeat}" calcMode="discrete" fill="freeze"/>`;
}
function move(ctx, values, seconds, times, repeat = "indefinite", begin = 0) {
  if (!ctx.motion) return "";
  return `<animateTransform attributeName="transform" type="translate" values="${values}" keyTimes="${times}" dur="${seconds}s" begin="${begin}s" repeatCount="${repeat}" calcMode="discrete" fill="freeze"/>`;
}
const opacity = (ctx, values, seconds, times, repeat = "indefinite", begin = 0) => animate(ctx, "opacity", values, seconds, times, repeat, begin);
function frames(ctx, drawings, seconds, part) {
  const times = Array.from({length:drawings.length+1}, (_, i) => i/drawings.length).join(";");
  return group(drawings.map((drawing, i) => {
    const values = Array.from({length:drawings.length+1}, (_, k) => Number(k % drawings.length === i)).join(";");
    return group(opacity(ctx, values, seconds, times) + drawing, `opacity="${i===0?1:0}" data-frame="${i}"`);
  }).join(""), `data-part="${part}"`);
}
function fourEye(x, y, w, h, fill) {
  const a=(w-4)/2, b=(h-4)/2;
  return block(x,y,a,b,fill)+block(x+a+4,y,a,b,fill)+block(x,y+b+4,a,b,fill)+block(x+a+4,y+b+4,a,b,fill);
}
function star(x,y,size,color) {
  const s=size/8;
  return at(x,y,path(`M${3*s} 0h${2*s}v${2*s}h${s}v${s}h${2*s}v${2*s}h-${2*s}v${s}h-${s}v${2*s}h-${2*s}v-${2*s}h-${s}v-${s}H0V${3*s}h${2*s}v-${s}h${s}Z`,color));
}
function slopedLid(x,y,right,ctx,strength=4) {
  return Array.from({length:5},(_,i)=>rect(x+i*8,y,8,2+(right?4-i:i)*strength,ctx.bg)).join("");
}
function sadLid(x,y,right,ctx) {
  return Array.from({length:5},(_,i)=>rect(x+i*8,y,8,3+(right?i:4-i)*4,ctx.bg)).join("");
}
// The two eyes, left and right, tagged as the resting face's when the face
// is (ctx.rest) and `rest` says these are its eyes; `shut`, its shut ones.
function pair(ctx,[left,right],rest=true,shut=false) {
  if(!ctx.rest||!rest)return left+right;
  return part(shut?"shut-l":"eye-l",left)+part(shut?"shut-r":"eye-r",right);
}
function eyePose(ctx) {
  const {mood,state,ink,bg}=ctx;
  if(state==="asleep")return block(68,94,40,5,ink)+block(212,94,40,5,ink);
  if(state==="no_app")return block(68,94,40,8,ink)+block(212,94,40,8,ink);
  // Each eye with what's drawn with it: a star cut out of it, a lid, a brow.
  if(mood==="happy")return group(pair(ctx,[fourEye(62,56,52,56,ink)+star(77,69,24,bg),fourEye(206,56,52,56,ink)+star(221,69,24,bg)]),'data-part="happy-eyes"');
  if(mood==="excited") {
    const steps=[0,6,12,18,12,6,0];
    return group(pair(ctx,[steps.map((x,i)=>rect(71+x,70+i*6,12,6,ink)).join(""),steps.map((x,i)=>rect(237-x,70+i*6,12,6,ink)).join("")]),'data-part="scrunched-eyes"');
  }
  if(mood==="proud")return pair(ctx,[fourEye(65,75,46,34,ink)+rect(65,75,46,13,bg)+rect(63,69,30,4,ink),fourEye(211,70,42,40,ink)+rect(211,70,42,6,bg)+rect(221,61,30,4,ink)]);
  if(mood==="curious") {
    // Its eyes look about: only the first pose is its resting face's.
    const poses=[
      [fourEye(74,82,28,28,ink),fourEye(201,53,62,62,ink)],
      [fourEye(67,69,42,42,ink),fourEye(211,69,42,42,ink)],
      [fourEye(57,53,62,62,ink),fourEye(218,82,28,28,ink)],
      [fourEye(67,66,42,46,ink),fourEye(211,70,42,42,ink)]
    ];
    return frames(ctx,poses.map((eyes,i)=>pair(ctx,eyes,i===0)),state==="idle"?3.6:2.8,"curious-eyes");
  }
  if(mood==="determined")return pair(ctx,[fourEye(67,80,42,30,ink)+rect(65,68,15,4,ink)+rect(80,70,15,4,ink)+rect(95,72,14,4,ink),
    fourEye(211,80,42,30,ink)+rect(211,72,14,4,ink)+rect(225,70,15,4,ink)+rect(240,68,15,4,ink)]);
  if(mood==="grumpy")return pair(ctx,[fourEye(68,70,40,44,ink)+slopedLid(68,70,false,ctx),fourEye(212,70,40,44,ink)+slopedLid(212,70,true,ctx)]);
  return pair(ctx,[fourEye(68,66,40,48,ink)+sadLid(68,66,false,ctx),fourEye(212,66,40,48,ink)+sadLid(212,66,true,ctx)]);
}
const shutEyes=ctx=>pair(ctx,[block(68,99,40,5,ctx.ink),block(212,99,40,5,ctx.ink)],true,true);
function eyes(ctx) {
  if(ctx.eyeOverride)return ctx.eyeOverride;
  if(["asleep","no_app"].includes(ctx.state))return eyePose(ctx);
  if(ctx.shut)return shutEyes(ctx);
  const period=ctx.state==="listening"?8.4:7.2;
  const open=group(opacity(ctx,"1;0;1;1",period,"0;0.78;0.805;1")+eyePose(ctx));
  const closed=group(opacity(ctx,"0;1;0;0",period,"0;0.78;0.805;1")+shutEyes(ctx),"opacity=\"0\"");
  return group(open+closed,"data-part=\"eyes\"");
}
function mouth(ctx) {
  if(ctx.mouthOverride)return ctx.mouthOverride;
  const {mood,state,ink,bg}=ctx;
  if(["asleep","no_app"].includes(state))return block(148,132,24,4,ink);
  if(state==="listening") {
    if(mood==="happy")return path("M150 129h4v4h12v-4h4v8h-20Z",ink);
    if(mood==="sad")return path("M147 137h6v-5h14v5h6v5h-10v-5h-6v5h-10Z",ink);
  }
  if(mood==="happy")return path("M150 129h4v4h12v-4h4v8h-20Z",ink);
  if(mood==="excited")return group(
    path("M138 125h44v18h-6v7h-6v5h-20v-5h-6v-7h-6Z",ink)+
    path("M144 131h32v10h-6v8h-20v-8h-6Z",bg)+rect(150,144,20,5,ctx.cheek),'data-part="wide-laugh"');
  if(mood==="proud")return path("M137 132h30v-5h8v-5h8v11h-7v5h-7v5h-32Z",ink)+rect(140,132,23,3,bg);
  if(mood==="curious")return path("M152 129h16v16h-16Zm4 4v8h8v-8Z",ink);
  if(mood==="determined")return block(143,131,34,8,ink)+rect(152,134,3,5,bg)+rect(164,134,3,5,bg);
  if(mood==="grumpy") {
    if(state==="task_complete")return path("M140 134h24v-5h12v5h-7v6h-29Z",ink);
    return path("M141 135h6v-6h26v6h6v12h-38Z",ink)+rect(146,140,28,7,bg)+rect(152,130,3,6,bg)+rect(165,130,3,6,bg);
  }
  if(state==="task_complete")return path("M141 128h6v5h26v-5h6v13h-6v5h-26v-5h-6Z",ink)+rect(148,140,24,4,ctx.cheek);
  return path("M141 134h6v-7h26v7h6v18h-9v-6h-20v6h-9Z",ink)+rect(150,140,20,6,ctx.cheek);
}
function cheeks(ctx) {
  const y=ctx.mood==="excited"?120:124;
  return block(51,y,14,9,ctx.cheek)+block(69,y,14,9,ctx.cheek)+block(237,y,14,9,ctx.cheek)+block(255,y,14,9,ctx.cheek);
}
function anger(ctx) {
  const mark=path("M0 6h6V0h5v11H0ZM17 0h5v6h6v5H17ZM0 17h11v11H6v-6H0ZM17 17h11v5h-6v6h-5Z",palette.red);
  return at(270,41,group(move(ctx,"0 0;0 -2;1 -2;0 0;0 0",2.4,"0;0.25;0.4;0.55;1")+mark,"data-part=\"anger-mark\""));
}
// Particles are independent squares. Their stepped trajectories imply acceleration,
// impact and rebound; there are no solid tear ribbons or scaled/blurred sprites.
function splash(ctx,x,y,phase=0) {
  let art="";
  for(const [i,dx]of[-17,-9,10,19].entries()) {
    const size=i%2?4:3, color=i%2?palette.lightWater:palette.blue;
    if(!ctx.motion){art+=rect(dx, i%2?-5:2,size,size,color);continue;}
    art+=group(move(ctx,`0 0;${Math.round(dx*.3)} -4;${Math.round(dx*.65)} -8;${dx} -4;${dx+Math.sign(dx)*4} 6;0 0`,1.2,"0;0.2;0.4;0.6;0.85;1","indefinite",phase)+
      opacity(ctx,"0;1;1;1;0;0",1.2,"0;0.2;0.4;0.6;0.85;1","indefinite",phase)+rect(0,0,size,size,color),'opacity="0"');
  }
  return at(x,y,group(art,'data-part="square-splash"'));
}
function tears(ctx) {
  let art="";
  if(ctx.state==="working") {
    // Four staggered lanes per eye: a broad waterfall of separate little cubes.
    for(const [side,x]of[69,223].entries()) {
      for(let lane=0;lane<4;lane++)for(let j=0;j<7;j++) {
        const size=[5,4,6,4,5,4,6][(j+lane)%7];
        const color=[palette.blue,palette.lightWater,palette.water][(j+lane+side)%3];
        const phase=-j*(1.4/7)-lane*.045-side*.09;
        art+=at(x+lane*7,ctx.motion?109:109+j*9,group(
          move(ctx,"0 0;0 5;1 13;0 25;-1 40;1 59;0 0",1.4,"0;0.17;0.34;0.51;0.68;0.88;1","indefinite",phase)+
          opacity(ctx,"1;1;1;1;1;0;1",1.4,"0;0.17;0.34;0.51;0.68;0.88;1","indefinite",phase)+rect(0,0,size,size,color),`data-part="tear-particle" data-lane="${lane}"`));
      }
      art+=splash(ctx,x+4,176,-side*.6)+splash(ctx,x+20,177,-.3-side*.6);
    }
    return group(art,'data-part="square-tears" data-width="28"');
  }
  for(const [side,x]of[78,232].entries()) {
    for(let j=0;j<5;j++) {
      const size=[7,4,6,5,4][j],color=[palette.blue,palette.lightWater,palette.water][j%3];
      const dx=[0,5,-2,4,1][j];
      const stillY=112+j*12;
      art+=at(x+dx,ctx.motion?112:stillY,group(
        move(ctx,"0 0;0 4;1 11;-1 23;2 40;1 58;0 0",1.5,"0;0.17;0.34;0.51;0.68;0.88;1","indefinite",-j*.3-side*.15)+
        opacity(ctx,"1;1;1;1;1;0;1",1.5,"0;0.17;0.34;0.51;0.68;0.88;1","indefinite",-j*.3-side*.15)+rect(0,0,size,size,color),'data-part="tear-particle"'));
    }
    art+=splash(ctx,x+3,174,-side*.6);
  }
  return group(art,'data-part="square-tears"');
}
function faceMotion(ctx) {
  if(ctx.actorMotion!==undefined)return ctx.actorMotion;
  const {mood,state}=ctx;
  if(["asleep","no_app"].includes(state))return move(ctx,"0 0;0 -1;0 -2;0 -1;0 0",8,"0;0.2;0.4;0.6;1");
  if(state==="needs_you")return move(ctx,"0 0;-3 -3;2 1;-2 -2;0 0;0 0",2.2,"0;0.15;0.3;0.45;0.65;1","1");
  if(state==="task_complete") {
    const poses={happy:"0 0;-4 -4;4 -4;0 0;0 0",excited:"0 0;0 -10;0 2;0 -6;0 0",proud:"0 0;0 8;0 10;0 2;0 0",curious:"0 0;-4 -3;4 -3;0 0;0 0",determined:"0 0;0 -4;0 3;0 1;0 0",grumpy:"0 0;0 3;-2 0;0 0;0 0",sad:"0 0;0 3;-1 1;1 1;0 0"};
    return move(ctx,poses[mood],3.4,"0;0.2;0.45;0.7;1","1");
  }
  if(state==="listening")return move(ctx,"0 0;0 0;0 -2;0 0;0 0",6,"0;0.25;0.4;0.65;1");
  if(state==="idle") {
    if(mood==="curious")return move(ctx,"-3 1;0 -2;3 1;0 -2;-3 1",3.6,"0;0.25;0.5;0.75;1");
    if(mood==="excited")return move(ctx,"0 0;0 -3;0 0;0 -2;0 0;0 0",3.2,"0;0.16;0.3;0.44;0.6;1");
    return move(ctx,"0 0;0 0;0 -1;0 0;0 0",8,"0;0.3;0.4;0.6;1");
  }
  const work={
    happy:["0 0;-2 -2;2 0;0 2;0 0",2.4,"0;0.2;0.4;0.6;1"],
    excited:["0 0;0 3;0 -4;0 3;0 -4;0 0;0 0",1.6,"0;0.16;0.3;0.44;0.58;0.75;1"],
    proud:["0 0;0 0;5 -4;5 -4;0 0",4.4,"0;0.3;0.45;0.7;1"],
    curious:["-3 1;0 -2;3 1;0 -2;-3 1",2.8,"0;0.25;0.5;0.75;1"],
    determined:["0 0;0 2;0 0;0 2;0 0",1.8,"0;0.2;0.4;0.6;1"],
    grumpy:["0 0;0 -4;-2 4;2 1;0 -3;2 4;-2 1;0 0",1.2,"0;0.12;0.25;0.38;0.5;0.62;0.75;1"],
    sad:["0 0;0 2;-2 0;2 1;0 0;0 0",3.2,"0;0.2;0.3;0.4;0.55;1"]
  };
  return move(ctx,...work[mood]);
}
// Whether a face is its mood's resting face, moved, which the device's rig
// face draws in its place: its eyes, mouth and cheeks the idle face's, in
// its colours, and no tears of sad's own, which pour from its eyes. What
// else it has is its decoration. `rig: false` keeps it baked.
function resting(ctx) {
  if(ctx.rig===false||ctx.quiet||ctx.eyeOverride||ctx.mouthOverride)return false;
  if(ctx.mood==="sad"&&ctx.tearOverride===undefined)return false;
  return ctx.ink===palette.ink&&ctx.bg===palette.black&&ctx.cheek===palette.cheek&&mouth(ctx)===mouth({...ctx,state:"idle"});
}
function face(ctx) {
  ctx={...ctx,rest:resting(ctx)};
  let art=group((ctx.gazeMotion||"")+eyes(ctx),'data-part="gaze"')+(ctx.rest?part("cheeks",cheeks(ctx)):cheeks(ctx));
  const tremble=ctx.mood==="sad"&&!ctx.quiet&&ctx.state!=="listening"?move(ctx,"0 0;1 0;-1 0;0 0;0 0",2.1,"0;0.2;0.3;0.4;1"):"";
  art+=ctx.rest?part("mouth",tremble+mouth(ctx)):group(tremble+mouth(ctx),"data-part=\"mouth\"");
  let decor="";
  if(!ctx.quiet&&ctx.mood==="sad")decor+=ctx.tearOverride!==undefined?ctx.tearOverride:tears(ctx);
  if(!ctx.quiet&&ctx.mood==="grumpy")decor+=anger(ctx);
  if(!ctx.quiet&&!ctx.suppressDecor&&ctx.mood==="happy")decor+=group(
    at(268,43,group(opacity(ctx,"1;0;1;1",2.4,"0;0.32;0.56;1")+move(ctx,"0 0;0 -3;0 0;0 0",2.4,"0;0.35;0.6;1")+star(0,0,16,ctx.complete?ctx.ink:palette.amber)))+
    at(48,49,group(opacity(ctx,"0;1;0;0",2.4,"0;0.25;0.65;1")+star(0,0,8,ctx.complete?ctx.ink:palette.amber))),'data-part="outer-sparkles"');
  if(!ctx.quiet&&!ctx.suppressDecor&&ctx.mood==="proud")decor+=at(277,106,group(opacity(ctx,"1;1;0;1",4.4,"0;0.3;0.5;1")+star(0,0,16,ctx.ink)));
  art+=ctx.rest&&decor?group(decor,'data-part="decor"'):decor;
  const y=ctx.state==="needs_you"?24:ctx.complete?8:0;
  return at(0,y,group(faceMotion(ctx)+art,"data-part=\"face\""));
}
function keyboardBase(ctx) {
  let art=block(83,170,154,29,palette.dim)+rect(87,172,146,22,palette.black);
  const period={happy:1.2,excited:.72,proud:1.6,curious:1.8,determined:1,grumpy:.95,sad:1.7}[ctx.mood];
  for(let row=0;row<2;row++)for(let col=0;col<10;col++){
    const x=90+col*14,y=175+row*9;
    art+=rect(x,y,10,5,palette.dim);
    if((row+col)%3===0)art+=group(opacity(ctx,col%2?"0;1;0;0":"1;0;0;1",period,"0;0.25;0.5;1")+rect(x,y+1,10,4,palette.ink),`opacity="${col%2?0:1}"`);
  }
  return art+rect(129,194,62,3,palette.prop);
}
function dustPuff(x,y,ctx,delay=0) {
  const direction=delay?1:-1;
  return at(x,y,group(Array.from({length:5},(_,i)=>{
    const size=[8,5,6,4,3][i],dx=direction*(9+i*6),dy=-6-i*5;
    const phase=-i*.16-delay*.35;
    return group(opacity(ctx,"1;1;1;0;1",1.1,"0;0.23;0.6;0.9;1","indefinite",phase)+
      move(ctx,`0 0;${Math.round(dx*.5)} ${dy};${dx} ${dy+5};${dx} ${dy+12};0 0`,1.1,"0;0.23;0.5;0.9;1","indefinite",phase)+
      rect(i%2*5,i%3*4,size,size,i%2?palette.dim:palette.prop),'opacity="0"');
  }).join(""),'data-part="square-dust"'));
}
function keycap(size,letter="X") {
  const unit=size/8, glyph=letter==="X"?[[2,2],[4,2],[3,3],[2,4],[4,4]]:[[2,2],[3,2],[4,2],[2,3],[3,3],[2,4],[3,4],[4,4]];
  return rect(0,0,size,size,palette.prop)+rect(0,0,size-unit,size-unit,palette.ink)+glyph.map(([x,y])=>rect(x*unit,y*unit,unit,unit,palette.dark)).join("");
}
function flyingKeys(ctx) {
  let art="";
  for(let i=0;i<12;i++) {
    const right=i>=6, n=i%6,x=(right?174:96)+n*10,y=175+i%2*7;
    const dx=(right?1:-1)*[55,72,84,44,65,90][n],dy=-[38,53,31,61,42,48][n];
    const safeDx=right?Math.min(dx,305-x):Math.max(dx,9-x);
    const phase=-i*.145,seconds=1.8;
    art+=at(x,y,group(opacity(ctx,"1;1;1;1;0;1",seconds,"0;0.2;0.4;0.7;0.9;1","indefinite",phase)+
      move(ctx,`0 0;${Math.round(safeDx*.45)} ${dy};${Math.round(safeDx*.7)} ${dy-4};${safeDx} ${dy+19};${safeDx} 22;0 0`,seconds,"0;0.2;0.4;0.7;0.9;1","indefinite",phase)+
      keycap(i%4===0?16:8,i%2?"E":"X"),'opacity="0" data-part="sideways-key"'));
    if(i%2===0)art+=at(x,y,group(
      move(ctx,`0 0;${Math.round(safeDx*.7)} ${dy+8};${safeDx} 8;0 0`,1.2,"0;0.3;0.85;1","indefinite",phase)+
      opacity(ctx,"1;1;0;1",1.2,"0;0.3;0.85;1","indefinite",phase)+rect(0,0,4,4,palette.prop),'opacity="0" data-part="broken-key-fragment"'));
  }
  // Draw depth as three integer-sized sprites, never a blurry scale transform.
  for(let volley=0;volley<2;volley++)for(const [i,size]of[8,16,24].entries())art+=group(
    opacity(ctx,`${i===0?1:0};${i===1?1:0};${i===2?1:0};0;${i===0?1:0}`,1.8,"0;0.2;0.4;0.66;1","indefinite",-volley*.9)+
    at(volley?164+i*18:152-i*20,184+i*9,keycap(size,"X")),`opacity="0" data-part="approaching-key" data-size="${size}" data-volley="${volley}"`);
  return group(art,"data-part=\"flying-keycaps\"");
}
function flood(ctx) {
  let art="";
  for(let row=0;row<3;row++){
    const tiles=Array.from({length:18},(_,i)=>rect(79+i*9,199-row*9,7,7,[palette.water,palette.blue,palette.water,palette.lightWater][(i+row)%4])).join("");
    art+=group((row?opacity(ctx,row===1?"0;1;1;0;0":"0;0;1;0;0",8.4,"0;0.2;0.45;0.82;1"):"")+tiles,`opacity="${row?0:1}" data-part="water-tiles" data-row="${row}"`);
  }
  for(const [x,dy]of[[110,0],[151,-2],[201,1]])art+=at(x,190+dy,group(move(ctx,"0 0;2 -4;-2 -11;2 -16;0 -10;0 0;0 0",8.4,"0;0.15;0.3;0.5;0.7;0.85;1")+keycap(8,"E")));
  art+=splash(ctx,101,191,-.3)+splash(ctx,219,193,-.9);
  art+=group(opacity(ctx,"0;0;1;0;0",8.4,"0;0.48;0.52;0.7;1")+rect(243,174,4,4,palette.amber)+rect(253,164,3,3,palette.amber)+rect(253,183,3,3,palette.amber),'opacity="0" data-part="comic-short-circuit"');
  return group(art,"data-part=\"keyboard-flood\"");
}
function work(ctx) {
  const mood=ctx.mood;
  let boardMotion="";
  if(mood==="grumpy")boardMotion=move(ctx,"-3 0;3 3;-3 1;3 4;-3 0",.6,"0;0.25;0.5;0.75;1");
  else if(mood==="excited")boardMotion=move(ctx,"0 0;0 2;0 0;0 2;0 0",.8,"0;0.25;0.5;0.75;1");
  else if(mood==="sad")boardMotion=move(ctx,"0 0;-2 0;2 1;-3 1;0 0;0 0",8.4,"0;0.3;0.5;0.7;0.85;1");
  let art=group(boardMotion+keyboardBase(ctx),"data-part=\"keyboard\"");
  if(mood==="grumpy")art+=dustPuff(73,178,ctx)+dustPuff(237,178,ctx,1)+flyingKeys(ctx)+group(opacity(ctx,"1;0;1;0;1",.6,"0;0.2;0.5;0.7;1")+rect(145,158,5,5,palette.amber)+rect(162,152,5,5,palette.amber)+rect(174,160,5,5,palette.amber),'opacity="0"');
  if(mood==="sad")art+=flood(ctx);
  if(mood==="excited")art+=group(move(ctx,"0 0;2 0;0 0;-2 0;0 0",.8,"0;0.25;0.5;0.75;1")+[59,68,247,256].map((x,i)=>rect(x,175+i%2*8,4,4,palette.prop)).join("")+star(264,151,16,palette.amber),'data-part="speed-pixels"');
  if(mood==="happy")art+=at(263,160,group(move(ctx,"0 0;0 -3;0 -5;0 0;0 0",2.4,"0;0.25;0.45;0.65;1")+path("M8 0h5v15H5v-5h3Zm5 0h9v5h-9Z",palette.cheek)));
  if(mood==="proud")art+=at(246,158,group(opacity(ctx,"0;1;1;0;0",4.4,"0;0.42;0.56;0.75;1")+star(0,0,24,palette.amber),"opacity=\"0\""));
  if(mood==="curious") {
    const glass=path("M5 0h16v5h5v16h-5v5H5v-5H0V5h5Zm2 6v14h12V6Z",palette.blue)+path("M22 21h5v5h5v5h-6v-5h-4Z",palette.prop);
    art+=at(239,157,group(move(ctx,"0 0;-5 3;0 0;4 -4;0 0",2.8,"0;0.25;0.5;0.75;1")+glass,"data-part=\"inspection-glass\""));
  }
  if(mood==="determined")art+=rect(73,170,4,17,palette.blue)+rect(243,170,4,17,palette.blue);
  return art;
}
function request(ctx) {
  const question=["curious","sad"].includes(ctx.mood);
  let tile=path("M0 0h60v39H29v8h-8v-8H0Z",palette.amber)+rect(4,4,52,31,palette.black);
  if(question)tile+=path("M19 8h19v5h5v9h-6v5h-8v-8h8v-5H23v5h-6v-6h2Zm9 22h8v5h-8Z",palette.amber);
  else tile+=rect(13,16,6,6,palette.amber)+rect(27,16,6,6,palette.amber)+rect(41,16,6,6,palette.amber);
  const tap=group(move(ctx,"0 0;-4 0;0 0;-4 0;0 0;0 0",1.9,"0;0.2;0.35;0.5;0.65;1","1")+block(67,17,10,10,palette.ink)+rect(60,11,4,4,palette.amber)+rect(60,30,4,4,palette.amber),"data-part=\"knock\"");
  return at(24,23,group(move(ctx,"0 3;0 -2;0 0;0 0",1.2,"0;0.25;0.5;1","1")+tile+tap,"data-part=\"request-cue\""));
}
function trophy(ctx) {
  const cup=path("M9 0h28v6h8v15h-9v6h-7v9h10v6H7v-6h10v-9h-7v-6H1V6h8Z",ctx.ink)+
    path("M13 4h20v15h-5v5H18v-5h-5Z",palette.ink)+rect(5,10,5,7,palette.gold)+rect(36,10,5,7,palette.gold)+rect(20,26,6,10,palette.ochre)+rect(12,37,22,2,palette.ink);
  return at(137,14,group(move(ctx,"0 8;0 2;0 -3;0 0;0 0",1.6,"0;0.2;0.4;0.7;1","1")+cup,"data-part=\"trophy\""));
}
function firework(ctx,x,y,delay,color) {
  if(!ctx.motion)return at(x,y,star(-8,-8,16,color));
  let rays="";
  for(const [dx,dy]of [[0,-24],[16,-16],[24,0],[16,16],[0,24],[-16,16],[-24,0],[-16,-16]]) {
    rays+=group(move(ctx,`0 0;${Math.round(dx*.45)} ${Math.round(dy*.45)};${dx} ${dy};${dx} ${dy+5};${dx} ${dy+5}`,1.1,"0;0.25;0.5;0.75;1","1",delay)+rect(-2,-2,4,4,color));
  }
  return at(x,y,group(opacity(ctx,"0;1;1;0;0",1.1,"0;0.05;0.65;0.95;1","1",delay)+rays,"opacity=\"0\" data-part=\"firework\""));
}
function goldCycle(ctx) {
  if(!ctx.motion)return "";
  // Hue motion is deliberately slow and similar in brightness, not a strobe.
  return '<animate attributeName="fill" values="#FFD54A;#FFC94A;#FFB84A;#FFC94A;#FFD54A" keyTimes="0;0.25;0.5;0.75;1" dur="6.4s" repeatCount="indefinite" calcMode="linear"/>';
}
function victoryBackground(ctx) {
  let art=`<rect width="320" height="240" fill="${palette.gold}" data-part="victory-color">${goldCycle(ctx)}</rect>`;
  // Square lanes travel only along the perimeter, leaving the face uncluttered.
  for(const [cornerX,cornerY,dir]of[[0,0,1],[272,0,-1],[0,192,-1],[272,192,1]]) {
    let lane="";
    for(let i=0;i<4;i++)lane+=rect(i*12,i*12,8,8,i%2?"#FFE575":"#EEA638");
    art+=at(cornerX,cornerY,group(move(ctx,dir>0?"0 0;4 0;4 4;0 4;0 0":"4 4;0 4;0 0;4 0;4 4",1.6,"0;0.25;0.5;0.75;1")+lane,'data-part="victory-lane"'));
  }
  const bands=[0,1,2,3].map(phase=>{
    let tiles="";
    for(let i=0;i<10;i++) {
      const x=70+i*18,y=208+((i+phase)%3)*9;
      tiles+=rect(x,y,6,6,(i+phase)%2?"#FFE575":"#EEA638");
    }
    return tiles;
  });
  return group(art+frames(ctx,bands,1.6,"victory-rhythm"),'data-part="victory-background"');
}
function celebration(ctx) {
  let art=victoryBackground(ctx);
  art+=firework(ctx,38,56,.1,palette.red)+firework(ctx,282,28,.7,palette.ink)+firework(ctx,39,176,1.4,palette.dark)+firework(ctx,280,178,2.1,palette.blue);
  if(ctx.motion) {
    for(const [x,y,color] of [[24,69,palette.blue],[53,115,palette.red],[271,113,palette.dark],[300,71,palette.red],[120,23,palette.ink],[194,24,palette.blue]]) {
      art+=at(x,y,group(opacity(ctx,"0;1;1;0;0",4.8,"0;0.1;0.55;0.9;1","1")+move(ctx,"0 0;3 6;-3 14;4 24;0 34;0 34",4.8,"0;0.2;0.4;0.6;0.8;1","1")+rect(0,0,4,4,color),"opacity=\"0\" data-part=\"confetti\""));
    }
  }
  return art;
}
function listening(ctx) {
  return group(path("M141 175h8v4h-4v11h4v4h-8Z",palette.blue)+path("M171 175h8v19h-8v-4h4v-11h-4Z",palette.blue)+rect(157,181,6,6,palette.blue),"data-part=\"listening-cue\"");
}
function disconnected(ctx) {
  return group(path("M145 174h9v3h-6v8h6v3h-9ZM166 174h9v14h-9v-3h6v-8h-6Z",palette.dim)+rect(154,177,3,3,palette.dim)+rect(163,182,3,3,palette.dim)+rect(158,172,3,3,palette.dim)+rect(158,189,3,3,palette.dim),"data-part=\"disconnected-cue\"");
}
function scene(ctx) {
  let art=ctx.complete?celebration(ctx):"";
  art+=face(ctx);
  if(ctx.state==="working")art+=work(ctx);
  if(ctx.state==="needs_you")art+=request(ctx);
  if(ctx.complete)art+=trophy(ctx);
  if(ctx.state==="listening")art+=listening(ctx);
  if(ctx.state==="no_app")art+=disconnected(ctx);
  if(ctx.state==="asleep")art+=path("M270 64h14v3h-4v3h-4v3h8v3h-14v-3h4v-3h4v-3h-8Z",palette.dim);
  // Gold cut-outs in eyelids and the trophy must track the moving background.
  return ctx.complete&&ctx.motion?art.replace(/<(rect|path)([^>]* fill="#FFD54A"[^>]*)\/>/g,(_,tag,attrs)=>`<${tag}${attrs}>${goldCycle(ctx)}</${tag}>`):art;
}
export function renderSVG(mood,state) {
  if(!moods.includes(mood)||!states.includes(state))throw new Error("Unknown Boop mood/state");
  const quiet=["asleep","no_app"].includes(state),complete=state==="task_complete";
  const ctx={mood:quiet?"happy":mood,state,quiet,complete,motion:true,ink:complete?palette.dark:palette.ink,bg:complete?palette.gold:palette.black,cheek:complete?"#D8576C":palette.cheek};
  const id=`boop-v4-${mood}-${state}`;
  const desc=quiet?`Shared ${label(state)} face, independent of mood.`:`${label(mood)} Boop, ${label(state)}. Exaggerated pixel expression with mood-specific motion. Silent base-design review.`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240" id="${id}" data-mood="${mood}" data-state="${state}" data-revision="4" role="img" aria-labelledby="${id}-title ${id}-desc" shape-rendering="crispEdges">\n<title id="${id}-title">${label(mood)} · ${label(state)}</title>\n<desc id="${id}-desc">${esc(desc)}</desc>\n<style>#${id} .boop-still{display:none}@media(prefers-reduced-motion:reduce){#${id}:not([data-motion="on"]) .boop-motion{display:none}#${id}:not([data-motion="on"]) .boop-still{display:inline}}</style>\n<rect data-part="background" width="320" height="240" fill="${ctx.bg}"/>\n<g class="boop-motion">${scene(ctx)}</g>\n<g class="boop-still">${scene({...ctx,motion:false})}</g>\n</svg>\n`;
}
// V4 drawing primitives are reused by the internal variation renderer.
export {rect,path,block,group,at,part,animate,move,opacity,frames,fourEye,star,eyePose,eyes,mouth,face,keyboardBase,work,request,trophy,firework,goldCycle,victoryBackground,celebration,listening,disconnected,splash,tears,flood,dustPuff,flyingKeys,keycap};
