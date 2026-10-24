import {createMotionV1} from './motion-v1.mjs';
import {createActing} from './acting.mjs';
import {createFace} from './face.mjs';
import {moodPosture,composePose,lifePose,createPostureWeights} from './compose.mjs';
import {createRouter} from './router.mjs';
import {createScenes} from './scenes/index.mjs';
import {sceneConstants} from './scenes/constants.mjs';
import {createBridges} from './bridges.mjs';
import {gestureGagName,gestureGag} from './scenes/gesture.mjs';
import {idleOccasions,occasionGags} from './scenes/occasion.mjs';

const clamp=(x,lo,hi)=>Math.min(hi,Math.max(lo,x));
const finite=value=>{if(!Number.isFinite(value))throw new TypeError('interaction coordinates must be finite');return value;};

export function createActor({profiles,gags,idleGags,gestures=[],notices=[],occasions=[],graph,rand,reduced,initialEmotion='calm'}) {
  const emotions=Object.keys(profiles);
  let emotion=initialEmotion,expression=initialEmotion;
  const grab={active:false,point:[0,.2],target:[0,0,0],pull:[{x:0,v:0},{x:0,v:0},{x:0,v:0}]};
  // The host's tags and how long its look has shown (setOccasion).
  const occasion={when:new Set(),lookMs:0};
  const extraGags=Object.fromEntries([...[...gestures,...notices].map(gesture=>[gestureGagName(gesture),gestureGag(gesture)]),...occasionGags(occasions)]);
  const acting=createActing({profiles,gags,idleGags,extraGags,idleLooks:idleOccasions(occasions),rand,reduced,initialEmotion,occasion});
  const face=createFace({profiles,initialEmotion,reduced});
  const router=createRouter({hasMood:id=>Object.hasOwn(profiles,id)});
  const scenes=createScenes({rand,reduced,profiles,gestures,notices,occasions,occasion});
  const bridges=createBridges({graph,profiles,rand,reduced});
  const posture=createPostureWeights({emotions,initialEmotion,reduced});
  function sync(time,options) {
    const route=router.resolve(),nextExpression=route.expression||emotion;
    bridges.setContext({quiet:route.quiet,grabActive:grab.active,attention:route.state==='needs_you'});
    if(nextExpression!==expression){
      const faceOptions=bridges.retarget(expression,nextExpression,time,options);
      expression=nextExpression;motion.setEmotion(expression);acting.setMood(expression,time/1000);face.setMood(expression,faceOptions);
    }
    face.setSleeping(route.quiet);
    scenes.setRoute(route,time,expression);
    // Acting plays in idle, and wherever the scene's recipe carries a gag.
    const gag=scenes.gag();
    acting.setSuppressed((route.state!=='idle'&&!gag)||grab.active,time/1000);
    acting.hold(gag?gag.name:null,gag?gag.key:null,time/1000);
    if(route.moment)router.setMomentDuration(route.moment.requestId,scenes.inspect(time).scene.loopDurationMs);
    return route;
  }
  const motion=createMotionV1({rand,reduced,emotions,initialEmotion,onAdvance:dt=>{
    const time=motion.time*1000;
    router.advance(time);sync(time);
    bridges.advance(dt);
    const ended=scenes.advance(dt,time,{grabActive:grab.active});
    if(ended){router.finish(ended);sync(time);}
    acting.advance(dt,motion.time,grab.active);
    // Held, the pull follows the finger quickly; let go, it settles back on
    // a softer spring, a wobble rather than a snap.
    const [stiffness,damping]=grab.active?[256,8]:[100,10];
    for(let i=0;i<3;i++){
      const m=grab.pull[i];let left=dt;
      while(left>0){const h=Math.min(left,1/240);m.v+=(stiffness*(grab.target[i]-m.x)-damping*m.v)*h;m.x+=m.v*h;left-=h;}
      m.x=clamp(m.x,-.72,.72);m.v=clamp(m.v,-6,6);
    }
    face.advance(dt);
    posture.advance(dt,expression);
  }});
  sync(0);
  function inspect() {
    const base=motion.inspect(),performance=acting.inspect(motion.time);
    const scene=scenes.inspect(motion.time*1000);
    const mood=moodPosture({weights:posture.weights,emotions,profiles,time:motion.time,reduced}).map(value=>value*(1-scene.scene.quietMix));
    const pose=composePose(motion.pose(),mood,acting.channels,scenes.activity,bridges.channels).map((value,index)=>clamp(value,-sceneConstants.poseBounds[index],sceneConstants.poseBounds[index]));
    const life=lifePose(acting.channels,scenes.activity,bridges.channels).map((value,index)=>clamp(value,-sceneConstants.lifeBounds[index],sceneConstants.lifeBounds[index]));
    // A gag's lids close the eyes as a blink does; its slide is drawn once
    // one has played. Its contacts follow the scene's.
    return {...base,...performance,...scene,...bridges.inspect(),mood:profiles[emotion].mood,expression,reducedMotion:reduced.matches,
      pose,life,...(acting.gagged?{slide:acting.slide()}:{}),posture:[mood[0],mood[1]],face:face.inspect(Math.max(motion.blink(),acting.lids())),
      contacts:[...scene.contacts,...acting.contacts.map(contact=>({...contact}))],facts:router.facts(),
      grab:{active:grab.active,point:[...grab.point],target:[...grab.target],pull:grab.pull.map(m=>({...m}))}};
  }
  return {
    frame:motion.frame,
    setPaused:motion.setPaused,setHidden:motion.setHidden,
    setReducedMotion(value) {reduced.matches=Boolean(value);},
    setPerformance:acting.setPerformance,
    setMood(id,options={}) {
      if(!Object.hasOwn(profiles,id))throw new RangeError('unknown expression: '+id);
      if(options.bridgeVariant!==undefined&&(!Number.isInteger(options.bridgeVariant)||options.bridgeVariant<0||options.bridgeVariant>2))throw new RangeError('bridgeVariant must be 0, 1 or 2');
      if(id===emotion)return;
      emotion=id;sync(motion.time*1000,options);
    },
    setFacts(value) {
      router.setFacts(value);sync(motion.time*1000);
    },
    // The tags on now and how long the look has shown, in milliseconds: an
    // occasion's take fits by them at its next pick (CONTINUITY.md, Occasions).
    setOccasion({when=[],lookMs=0}={}) {
      occasion.when=new Set(when);occasion.lookMs=Math.max(0,Number(lookMs)||0);
    },
    oneShot(value) {
      const result=router.oneShot(value,motion.time*1000,sceneConstants.cycleMs[0]);
      sync(motion.time*1000);
      if(result.accepted&&['poked','tap_spam'].includes(value.name))motion.impulse(value.name==='poked'?'poke':'shake');
      return result;
    },
    clearTransient() {router.clearTransient();sync(motion.time*1000);},
    holdExpression(id) {router.holdExpression(id&&Object.hasOwn(profiles,id)?id:null);sync(motion.time*1000);},
    setLinkTimedOut(value) {router.setLinkTimedOut(value);sync(motion.time*1000);},
    poke(x=0,y=.2) {motion.impulse('poke',finite(x),finite(y));},
    shake() {motion.impulse('shake');},
    perform(index) {acting.perform(motion.time,index);},
    dragStart(point=[0,.2]) {
      if(grab.active)return;
      if(!Array.isArray(point)||point.length<2)throw new TypeError('drag point requires two normalized coordinates');
      const normalized=[clamp(finite(point[0]),-1,1),clamp(finite(point[1]),-1,1)];
      grab.active=true;grab.point=normalized;grab.target=[0,0,0];
      sync(motion.time*1000);
    },
    dragMove(delta) {
      if(!grab.active)return;
      if(!Array.isArray(delta)||delta.length!==3)throw new TypeError('drag delta requires three body coordinates');
      const vector=delta.map(finite),length=Math.hypot(...vector),scale=length>.64?.64/length:1;
      grab.target=vector.map(v=>v*scale*(reduced.matches?.35:1));
    },
    dragEnd() {
      if(!grab.active)return;
      grab.active=false;grab.target=[0,0,0];acting.deferUntil(motion.time+3);sync(motion.time*1000);
    },
    inspect,
    channels() {
      const value=inspect();
      return {...value,grab:{...value.grab,pull:value.grab.pull.map(m=>m.x)}};
    }
  };
}
