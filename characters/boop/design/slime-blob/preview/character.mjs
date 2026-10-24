// The gel slime in the Character Studio (characters/studio/). It owns the
// engine, renderer, sound and pointer wiring; the studio owns the controls.
import {createSlime} from '../engine/index.mjs';
import {createWebGL} from '../render/webgl.mjs';
import {createCanvas2D} from '../render/canvas2d.mjs';
import {eye,target} from '../render/camera.mjs';
import {createProps} from '../render/props.mjs';
import {createPlayer} from '../sound/player.mjs';
import {createReview} from './review.mjs';

const oneShotStates=['starting','helper_return','reply_ready','task_complete','error','stopped','poked','tap_spam','wake_up','listening'];

function create({root,stage,onChange=()=>{}}) {
  const catalog=window.SlimeCatalog,profiles=catalog.expressions,expressions=Object.keys(profiles);
  const scriptCatalog=window.SlimeScripts||{};
  const player=createPlayer({sfx:window.SlimeSFX});
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  let canvas=document.createElement('canvas');
  canvas.setAttribute('role','img');
  canvas.setAttribute('aria-label','A translucent blue slime. Tap to poke it; hold and drag to stretch it, then let go to watch it bounce back.');
  stage.append(canvas);
  let engine=createSlime({seed:1729,catalog,reducedMotion:reduced.matches});
  const onReduced=()=>engine.setReducedMotion(reduced.matches);reduced.addEventListener('change',onReduced);
  let channels=engine.step(0).channels,renderer,shaderError='',paused=false,frames=0,lastStamp=null,presentation=0,alive=true;
  let expression='calm',performanceChoice='auto',fact={state:'idle',outcome:'success',context:'new_task'};
  try{renderer=createWebGL(canvas,catalog);}catch(error){shaderError=String(error.message);renderer=createCanvas2D(canvas,catalog);canvas=renderer.canvas;}
  const propsLayer=createProps(stage);
  function drawFrame(){renderer.draw(channels);propsLayer.draw(channels,canvas.width,canvas.height);}
  function changed(){onChange();}
  function refresh(){const result=engine.step(presentation);channels=result.channels;player.consume(result);drawFrame();changed();}
  function resume(){paused=false;lastStamp=null;}
  function setFace(id,options){if(!profiles[id])return;expression=id;engine.setMood(id,options);engine.setPerformance('auto');performanceChoice='auto';}
  function perform(choice=performanceChoice){
    performanceChoice=choice;resume();engine.setPerformance(choice);engine.perform(choice==='auto'?undefined:Number(choice));changed();
  }
  function poke(x=0,y=.2){resume();engine.poke(x,y);refresh();}
  function shake(){resume();engine.shake();refresh();}
  function size(){const rect=stage.getBoundingClientRect(),ratio=Math.min(devicePixelRatio||1,1.5);canvas.width=Math.max(1,Math.round(rect.width*ratio));canvas.height=Math.max(1,Math.round(rect.height*ratio));drawFrame();}
  const observer=new ResizeObserver(size);observer.observe(stage);

  // Pointer: a quick tap pokes where it lands; a hold drags the surface.
  const dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0),unit=a=>{const n=Math.hypot(...a);return a.map(v=>v/n);},cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
  const forward=unit(target.map((v,i)=>v-eye[i])),right=unit(cross(forward,[0,1,0])),up=cross(right,forward);
  function ray(event){const r=stage.getBoundingClientRect(),x=(event.clientX-r.left)/r.width*2-1,y=1-(event.clientY-r.top)/r.height*2;return unit(forward.map((v,i)=>v+right[i]*x*r.width/r.height*Math.tan(.42)+up[i]*y*Math.tan(.42)));}
  function hit(event){
    if(renderer.kind==='procedural-canvas-fallback'){
      const r=stage.getBoundingClientRect(),x=((event.clientX-r.left)/r.width-.5)*4.5,y=(.74-(event.clientY-r.top)/r.height)*3.35;
      const q=x*x/1.21+(y-.56)*(y-.56)/(.91*.91);return q<=1&&y>.06?[x,y,.847*Math.sqrt(Math.max(0,1-q))]:null;
    }
    const d0=ray(event),r=[1.1,.91,.847],center=[0,.56,0],o=eye.map((v,i)=>(v-center[i])/r[i]),d=d0.map((v,i)=>v/r[i]);
    const a=dot(d,d),b=dot(o,d),c=dot(o,o)-1,disc=b*b-a*c;if(disc<0)return null;
    const distance=(-b-Math.sqrt(disc))/a;if(distance<=0)return null;const p=eye.map((v,i)=>v+distance*d0[i]);return p[1]>.07&&p[2]>.03?p:null;
  }
  let grab=null;
  // How fast the drag moved over its last 80 ms, as the board measures a
  // finger letting go; none once it has stopped.
  function flingOf(old){
    const s=old.samples,last=s.at(-1),now=performance.now();
    if(!last||now-last[0]>80)return [0,0,0];
    let first=s[0];for(const sample of s)if(last[0]-sample[0]>=80)first=sample;
    const seconds=(last[0]-first[0])/1000;
    return seconds>0?last[1].map((v,i)=>(v-first[1][i])/seconds):[0,0,0];
  }
  function release(event,cancel=false){
    if(!grab||(event&&event.pointerId!==grab.id))return;
    const old=grab;grab=null;engine.dragEnd(cancel?[0,0,0]:flingOf(old));if(stage.hasPointerCapture(old.id))stage.releasePointerCapture(old.id);
    if(!cancel&&!old.dragged&&performance.now()-old.stamp<350)poke(old.point[0],old.point[1]);changed();
  }
  function onDown(event){
    if(review.active||grab||event.button>0)return;const anchor=hit(event);if(!anchor)return;resume();
    grab={id:event.pointerId,anchor,point:[anchor[0]/1.1,(anchor[1]-.56)/.91],start:[event.clientX,event.clientY],stamp:performance.now(),dragged:false,pointerType:event.pointerType,samples:[]};
    engine.dragStart(grab.point);stage.setPointerCapture(event.pointerId);event.preventDefault();changed();
  }
  function onMove(event){
    if(!grab||event.pointerId!==grab.id)return;if(event.pointerType==='mouse'&&event.buttons===0){release(event,true);return;}
    if(Math.hypot(event.clientX-grab.start[0],event.clientY-grab.start[1])>5)grab.dragged=true;
    let delta;
    if(renderer.kind==='procedural-canvas-fallback'){const r=stage.getBoundingClientRect();delta=[(event.clientX-grab.start[0])/r.width*4.5,-(event.clientY-grab.start[1])/r.height*3.35,0];}
    else{const direction=ray(event),distance=dot(grab.anchor.map((v,i)=>v-eye[i]),forward)/dot(direction,forward);delta=eye.map((v,i)=>v+distance*direction[i]-grab.anchor[i]);}
    engine.dragMove(delta);grab.samples=[...grab.samples.slice(-7),[performance.now(),delta]];event.preventDefault();
  }
  const stageEnd=event=>release(event,event.type!=='pointerup');
  stage.addEventListener('pointerdown',onDown);stage.addEventListener('pointermove',onMove);
  for(const name of ['pointerup','pointercancel','lostpointercapture'])stage.addEventListener(name,stageEnd);
  const finish=event=>release(event,event.type==='pointercancel'),blur=()=>release(null,true),visibility=()=>{lastStamp=null;if(document.hidden){release(null,true);player.stop();}};
  const out=event=>{if(!event.relatedTarget)release(null,true);};
  document.addEventListener('pointerup',finish,true);document.addEventListener('pointercancel',finish,true);window.addEventListener('blur',blur);document.addEventListener('visibilitychange',visibility);
  document.addEventListener('pointerout',out);
  canvas.addEventListener('webglcontextlost',event=>{event.preventDefault();paused=true;release(null,true);changed();});
  canvas.addEventListener('webglcontextrestored',()=>{try{renderer=createWebGL(canvas,catalog);shaderError='';resume();size();}catch(error){shaderError=String(error.message);}});

  // Host facts: the studio's state picker sets what the device would be told.
  let requestSequence=1000,scriptRun=null,runs=0;
  function setState(state,{outcome=fact.outcome,context=fact.context}={}){
    fact={state,outcome,context};
    release(null,true);engine.dragEnd();resume();engine.setLinkTimedOut(false);
    if(state!=='listening')engine.oneShot({name:'stop_listening'});
    if(state==='needs_you')engine.setFacts({base:'working',attn:{id:++requestSequence,agent:'codex',project:'studio',name:'Review the new scene',more:0}});
    else if(oneShotStates.includes(state)){
      engine.setFacts({base:'working'});
      engine.oneShot({id:++requestSequence,name:state,args:{...(state==='task_complete'?{outcome}:{}),...(state==='starting'?{ctx:context}:{}),loops:1}});
    }else if(state==='no_app'){engine.setFacts({base:'idle'});engine.setLinkTimedOut(true);}
    else if(['idle','asleep','working'].includes(state))engine.setFacts({base:state});
    else engine.setFacts({base:'working',act:state});
    refresh();
  }
  function applyEvent(event){
    switch(event.type){
      case 'facts':engine.setFacts(event.facts);break;
      case 'mood':setFace(event.mood,event.bridgeVariant===undefined?undefined:{bridgeVariant:event.bridgeVariant});break;
      case 'poke':engine.poke(event.x,event.y);break;
      case 'shake':engine.shake();break;
      case 'perform':engine.perform(event.index);break;
      case 'dragStart':engine.dragStart(event.point);break;
      case 'dragMove':engine.dragMove(event.delta);break;
      case 'dragEnd':engine.dragEnd(event.velocity);break;
      case 'oneShot':engine.oneShot(event.moment||event.do);break;
      case 'linkTimedOut':engine.setLinkTimedOut(event.value);break;
    }
  }
  function advanceScript(){
    if(!scriptRun)return;const age=presentation-scriptRun.start;
    while(scriptRun.cursor<scriptRun.events.length&&scriptRun.events[scriptRun.cursor].at<=age)applyEvent(scriptRun.events[scriptRun.cursor++]);
    if(scriptRun.cursor===scriptRun.events.length){scriptRun.done=true;scriptRun=null;}
  }
  // Explicit review replays start a new seeded run. The same actor then persists
  // through every fact, mood, scene and input change inside that run.
  function startReviewRun(){
    release(null,true);player.reset();engine.dragEnd();scriptRun=null;runs++;
    engine=createSlime({seed:53,catalog,reducedMotion:reduced.matches});
    presentation=0;requestSequence=1000;channels=engine.step(0).channels;expression='calm';performanceChoice='auto';fact={...fact,state:'idle'};
    resume();refresh();
  }
  function playScript(name){if(!scriptCatalog[name])return;startReviewRun();scriptRun={name,events:scriptCatalog[name],start:presentation,cursor:0};changed();}
  function stopScript(){if(scriptRun){scriptRun=null;engine.dragEnd();changed();}}
  const review=createReview({root,body:()=>canvas,props:propsLayer,getChannels:()=>channels,cases:[],startRun:startReviewRun,
    getCases:()=>root.querySelector('[data-review-set]').value==='bridges'?(window.SlimeBridgeReview?.cases||[]):(window.SlimeReview?.cases||[]),
    applyCase:item=>{
      scriptRun=null;
      if(item.from){
        const events=scriptCatalog[item.script.split('/').pop()].filter(event=>event.at>=item.startMs&&event.at<item.endMs)
          .map(event=>({...event,at:event.at-item.startMs}));
        for(const event of events.filter(event=>event.at===0))applyEvent(event);
        fact={...fact,state:'idle'};refresh();
        scriptRun={name:item.id,start:presentation,cursor:0,events:events.filter(event=>event.at>0)};
      }else{setFace(item.mood);setState(item.state,{outcome:item.outcome||'success'});}
    }});

  function frame(stamp){
    if(!alive)return;
    if(!document.hidden&&!paused){if(lastStamp!==null)presentation+=Math.min(45,Math.max(0,stamp-lastStamp));advanceScript();const result=engine.step(presentation);channels=result.channels;player.consume(result);drawFrame();frames++;changed();}lastStamp=stamp;
    review.tick(presentation);
    requestAnimationFrame(frame);
  }
  size();requestAnimationFrame(frame);

  function sceneText(){
    const scene=channels.scene;if(!scene)return '';
    return `${scene.phase} · variation ${(scene.variant||0)+1}${scene.implemented?'':' · choreography planned'}`;
  }
  function activity(){
    if(paused)return 'paused';if(grab)return 'stretching';
    const p=channels.performance;return p&&p.age<p.duration?p.label.toLowerCase():'resting';
  }
  return {
    expressions,profiles,scripts:Object.keys(scriptCatalog),
    setFace,setState,perform,poke,shake,playScript,stopScript,
    setPaused(value){release(null,true);paused=value;lastStamp=null;changed();},
    get paused(){return paused;},
    get script(){return scriptRun&&{name:scriptRun.name,seconds:(presentation-scriptRun.start)/1000};},
    get performance(){return performanceChoice;},
    get expression(){return expression;},
    get runs(){return runs;},
    get review(){return review;},
    activity,sceneText,
    async enableSound(){await player.enable();},
    muteSound(){player.setMix({muted:true});},
    setVolume(volume){player.setMix({volume});},
    soundEnabled(){return player.inspect().enabled;},
    getState:()=>({...engine.inspect(),emotion:channels.mood,grab:{...engine.inspect().grab,dragged:Boolean(grab?.dragged),pointerType:grab?.pointerType||null},rendering:renderer.kind,shaderError,frames,paused,emotions:expressions.filter(id=>!id.includes(':')),expressions,referenceMapping:catalog.referenceMapping,material:'simple-blue-translucent-gel',postprocessBloom:renderer.kind==='procedural-webgl',draftGraphImplemented:false,channels}),
    destroy(){
      alive=false;release(null,true);player.reset();observer.disconnect();reduced.removeEventListener('change',onReduced);
      document.removeEventListener('pointerup',finish,true);document.removeEventListener('pointercancel',finish,true);
      window.removeEventListener('blur',blur);document.removeEventListener('visibilitychange',visibility);document.removeEventListener('pointerout',out);
      stage.removeEventListener('pointerdown',onDown);stage.removeEventListener('pointermove',onMove);
      for(const name of ['pointerup','pointercancel','lostpointercapture'])stage.removeEventListener(name,stageEnd);
      stage.replaceChildren();
    }
  };
}

window.SlimeStudio={create};
