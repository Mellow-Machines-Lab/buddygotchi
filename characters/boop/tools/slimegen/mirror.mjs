// The app's read-only mirror: consumes facts and requested moments, never emits
// actions, plays audio, or reports ended. The device alone owns the turn.
import {createSlime} from '../../design/slime-blob/engine/index.mjs';
import {createWebGL} from '../../design/slime-blob/render/webgl.mjs';
import {createCanvas2D} from '../../design/slime-blob/render/canvas2d.mjs';
import {createProps} from '../../design/slime-blob/render/props.mjs';

const stage=document.getElementById('stage');
let canvas=document.getElementById('body');
const catalog=window.SlimeCatalog;
let engine=createSlime({seed:53,catalog}),renderer,elapsed=0,last=null,owed=0,frames=0,visible=false,still=false,listening=false;
try {renderer=createWebGL(canvas,catalog);} catch {renderer=createCanvas2D(canvas,catalog);canvas=renderer.canvas;}
const props=createProps(stage,{hostLane:false});
// At most 60 frames a second, so ProMotion's 120 Hz
// display draws every other refresh. A closed popover draws nothing at all.
const framePeriod=1000/60;
function draw(){const result=engine.step(elapsed);renderer.draw(result.channels);props.draw(result.channels,canvas.width,canvas.height);frames++;return result.channels;}
function resize(){const rect=stage.getBoundingClientRect(),ratio=Math.min(devicePixelRatio||1,2);canvas.width=Math.max(1,Math.round(rect.width*ratio));canvas.height=Math.max(1,Math.round(rect.height*ratio));if(visible||still)draw();}
function facts(value){engine.setFacts(value);engine.setMood(value.mood||'calm');}
window.BoopSlime={
  // Facts and moments change the engine at once; only an open popover draws.
  feed(message){
    if(message.kind==='state')facts(message.value);
    if(message.kind==='moment'&&visible&&!still)engine.oneShot(message.value);
    if(message.kind==='visibility'){
      visible=Boolean(message.value);last=null;
      if(!visible)engine.clearTransient();else{if(listening)engine.oneShot({name:'listening',id:'mirror-listening'});draw();}
    }
    if(message.kind==='listening'){listening=Boolean(message.value);if(visible)engine.oneShot({name:listening?'listening':'stop_listening',id:'mirror-listening'});}
    if(message.kind==='reduced')engine.setReducedMotion(Boolean(message.value));
  },
  // Fixed-clock snapshot used by --snapshots. No host clock or device timer.
  snapshot(value){still=true;engine=createSlime({seed:53,catalog});elapsed=0;facts(value);draw();for(let t=16;t<=960;t+=16){elapsed=t;draw();}return {state:engine.inspect().scene.state,renderer:renderer.kind};},
  // Frames drawn since load, for check-mirror.mjs.
  get frames(){return frames;}
};
new ResizeObserver(resize).observe(stage);
// The clock runs on every refresh while open; a frame is drawn once a 60 Hz
// period is owed (with a millisecond's slack for timer jitter).
function frame(stamp){
  if(visible&&!still&&!document.hidden){
    if(last!==null){const step=Math.max(0,stamp-last);elapsed+=step;owed+=step;}
    last=stamp;
    if(owed>=framePeriod-1){owed=Math.min(owed-framePeriod,framePeriod);draw();}
  }else{last=null;owed=0;}
  requestAnimationFrame(frame);
}
resize();requestAnimationFrame(frame);
document.documentElement.dataset.ready='true';
